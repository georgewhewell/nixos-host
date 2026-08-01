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
import re
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

    _refreshed_token: str | None = None

    def credential_path(self) -> Path:
        return self._home / ".claude" / ".credentials.json"

    def fetch(self) -> ProviderSnapshot:
        creds = self._read_credentials()
        token = self._refreshed_token or creds.get("accessToken")
        if not token:
            raise CredentialsUnavailable("no accessToken in ~/.claude/.credentials.json")

        response = self._usage_request(token)
        if response.status_code == 401:
            token = self._refresh(creds)
            response = self._usage_request(token)
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
        return ProviderSnapshot(samples=samples, info=info)

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

    def _refresh(self, creds: dict[str, Any]) -> str:
        """Exchange the refresh token for a fresh access token, kept in memory only.

        The credential file is deliberately never rewritten: Claude Code owns it
        and refreshes it on its own schedule.
        """
        refresh_token = creds.get("refreshToken")
        if not refresh_token:
            raise CredentialsUnavailable("access token expired and no refreshToken present")
        try:
            response = self._client.post(
                TOKEN_URL,
                json={
                    "grant_type": "refresh_token",
                    "refresh_token": refresh_token,
                    "client_id": CLIENT_ID,
                },
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"token refresh failed: {exc}") from exc
        if response.status_code != 200:
            raise ProviderError(f"token refresh returned HTTP {response.status_code}")
        token = response.json().get("access_token")
        if not token:
            raise ProviderError("token refresh response had no access_token")
        log.info("anthropic: refreshed access token in memory")
        self._refreshed_token = token
        return token


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
        scope = _slugify(model.get("display_name") or "unknown")
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
    return samples


def _split_window(key: str) -> tuple[str, str]:
    """Map response keys to (window, scope): seven_day_opus -> ("seven_day", "opus")."""
    if key.startswith("seven_day_"):
        return "seven_day", key.removeprefix("seven_day_")
    return key, "all"


def _slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
