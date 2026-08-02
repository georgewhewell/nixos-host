"""Anthropic (Claude Pro/Max subscription) quota provider.

Reads the Claude Code OAuth token from ~/.claude/.credentials.json and queries
the same endpoint the official client uses for its usage display:

    GET https://api.anthropic.com/api/oauth/usage

The response reports utilization percentages (0-100) and reset times for the
five-hour session window, the seven-day window, and model-scoped weekly caps
(either as seven_day_<model> objects or entries in a `limits` array).
"""

from __future__ import annotations

import json
import logging
import os
import re
import tempfile
import time
from pathlib import Path
from typing import Any

import httpx

from .._time import parse_iso8601
from .base import CredentialsUnavailable, Provider, ProviderError, ProviderSnapshot, QuotaSample

log = logging.getLogger(__name__)

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
# Public client id of the Claude Code installed app, required by the token endpoint.
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
OAUTH_BETA_HEADER = "oauth-2025-04-20"

# Non-window keys that may appear at the top level of the usage response.
_NON_WINDOW_KEYS = {"limits", "extra_usage"}


class AnthropicProvider(Provider):
    name = "anthropic"

    def credential_path(self) -> Path:
        return self._home / ".claude" / ".credentials.json"

    def fetch(self) -> ProviderSnapshot:
        creds = self._read_credentials()
        token = self._current_token(creds)
        response = self._usage_request(token)
        if response.status_code == 401:
            # A fresh-looking token that 401s means Claude Code owns a newer
            # one (or the session was revoked); never refresh in that case.
            raise ProviderError("HTTP 401 with an unexpired token; leaving auth to the claude CLI")
        if response.status_code != 200:
            raise ProviderError(f"usage endpoint returned HTTP {response.status_code}")

        usage = response.json()
        samples = tuple(_parse_usage(usage))
        if not samples:
            raise ProviderError(f"no quota windows in usage response: {list(usage)}")

        info = {}
        if subscription := creds.get("subscriptionType"):
            info["plan"] = str(subscription)
        if tier := creds.get("rateLimitTier"):
            info["tier"] = str(tier)
        return ProviderSnapshot(samples=samples, info=info, spend_usd=_parse_spend(usage))

    def _read_credentials(self) -> dict[str, Any]:
        try:
            raw = json.loads(self.credential_path().read_text())
        except FileNotFoundError as exc:
            raise CredentialsUnavailable(str(exc)) from exc
        except (OSError, json.JSONDecodeError) as exc:
            raise ProviderError(f"unreadable credentials file: {exc}") from exc
        oauth = raw.get("claudeAiOauth")
        if not isinstance(oauth, dict):
            raise CredentialsUnavailable("claudeAiOauth section missing from credentials file")
        return oauth

    def _usage_request(self, token: str) -> httpx.Response:
        try:
            return self._client.get(
                USAGE_URL,
                headers={
                    "Authorization": f"Bearer {token}",
                    "anthropic-beta": OAUTH_BETA_HEADER,
                    "Accept": "application/json",
                },
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"usage request failed: {exc}") from exc

    def _current_token(self, creds: dict[str, Any]) -> str:
        expires_at = creds.get("expiresAt")  # unix milliseconds
        expired = isinstance(expires_at, (int, float)) and expires_at / 1000 < time.time() + 60
        if not expired and (token := creds.get("accessToken")):
            return str(token)
        if creds.get("refreshToken"):
            return self._refresh(creds)
        raise CredentialsUnavailable("no usable accessToken/refreshToken in credentials file")

    def _refresh(self, creds: dict[str, Any]) -> str:
        """Refresh the expired token and persist the rotated pair.

        Anthropic rotates refresh tokens: an in-memory-only refresh strands
        Claude Code on a consumed token and its next refresh trips reuse
        detection, revoking the whole session (observed as forced re-logins).
        We only get here when the on-disk token has already expired — i.e. no
        running claude session is managing the file — and the rotated pair is
        written back atomically, preserving the rest of the file (mcpOAuth...).
        """
        try:
            response = self._client.post(
                TOKEN_URL,
                json={
                    "grant_type": "refresh_token",
                    "refresh_token": creds["refreshToken"],
                    "client_id": CLIENT_ID,
                },
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"token refresh failed: {exc}") from exc
        if response.status_code != 200:
            raise ProviderError(f"token refresh returned HTTP {response.status_code}")
        payload = response.json()
        token = payload.get("access_token")
        if not token:
            raise ProviderError("token refresh response had no access_token")

        path = self.credential_path()
        try:
            raw = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise ProviderError(f"refreshed but could not re-read credentials file: {exc}") from exc
        oauth = dict(raw.get("claudeAiOauth") or {})
        oauth["accessToken"] = token
        oauth["refreshToken"] = payload.get("refresh_token", creds["refreshToken"])
        if expires_in := payload.get("expires_in"):
            oauth["expiresAt"] = int((time.time() + float(expires_in)) * 1000)
        raw["claudeAiOauth"] = oauth
        try:
            fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
            with os.fdopen(fd, "w") as handle:
                json.dump(raw, handle)
            os.chmod(tmp, 0o600)
            os.replace(tmp, path)
        except OSError as exc:
            raise ProviderError(f"refreshed but could not persist rotated tokens: {exc}") from exc
        log.info("anthropic: refreshed access token and persisted rotated pair")
        return str(token)


def _parse_usage(usage: dict[str, Any]) -> list[QuotaSample]:
    samples: list[QuotaSample] = []
    for key, value in usage.items():
        if key in _NON_WINDOW_KEYS or not isinstance(value, dict):
            continue
        utilization = value.get("utilization")
        if not isinstance(utilization, (int, float)):
            continue
        window, scope = _split_window(key)
        samples.append(
            QuotaSample(
                window=window,
                scope=scope,
                utilization=utilization / 100.0,
                resets_at=parse_iso8601(value.get("resets_at")),
            )
        )
    for entry in usage.get("limits") or []:
        if not isinstance(entry, dict) or entry.get("kind") != "weekly_scoped":
            continue
        percent = entry.get("percent")
        if not isinstance(percent, (int, float)):
            continue
        model = (entry.get("scope") or {}).get("model") or {}
        display_name = model.get("display_name")
        if not display_name:
            continue  # scope-less entries duplicate the seven_day_<model> keys
        scope = _slugify(display_name)
        if any(s.window == "seven_day" and s.scope == scope for s in samples):
            continue  # already reported as a seven_day_<model> object
        samples.append(
            QuotaSample(
                window="seven_day",
                scope=scope,
                utilization=percent / 100.0,
                resets_at=parse_iso8601(entry.get("resets_at")),
            )
        )
    extra = usage.get("extra_usage")
    if isinstance(extra, dict) and isinstance(extra.get("utilization"), (int, float)):
        samples.append(
            QuotaSample(window="extra_usage", scope="all", utilization=extra["utilization"] / 100.0)
        )
    return samples


def _parse_spend(usage: dict[str, Any]) -> float | None:
    """Extra-usage credit spend in USD: spend.used.amount_minor / 10^exponent."""
    used = (usage.get("spend") or {}).get("used")
    if not isinstance(used, dict):
        return None
    amount_minor = used.get("amount_minor")
    if not isinstance(amount_minor, (int, float)):
        return None
    exponent = used.get("exponent")
    return amount_minor / (10 ** exponent if isinstance(exponent, int) else 100)


def _split_window(key: str) -> tuple[str, str]:
    """Map response keys to (window, scope): seven_day_opus -> ("seven_day", "opus")."""
    if key.startswith("seven_day_"):
        return "seven_day", key.removeprefix("seven_day_")
    return key, "all"


def _slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
