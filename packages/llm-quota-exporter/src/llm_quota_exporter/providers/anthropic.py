"""Anthropic (Claude Pro/Max subscription) quota provider.

Reads the Claude Code OAuth token from ~/.claude/.credentials.json and queries
the same endpoint the official client uses for its usage display:

    GET https://api.anthropic.com/api/oauth/usage

The response reports utilization percentages (0-100) and reset times for the
five-hour session window, the seven-day window, and model-scoped weekly caps
(either as seven_day_<model> objects or entries in a `limits` array).

Auth is strictly read-only — see _current_token for why refreshing from here
is catastrophic. An expired token is a data gap, not an error to fix.
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any

import httpx

from .._time import parse_iso8601
from .base import (
    CredentialsUnavailable,
    Provider,
    ProviderError,
    ProviderSnapshot,
    QuotaSample,
    json_object,
)

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
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

        usage = json_object(response, "usage endpoint")
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
        oauth = raw.get("claudeAiOauth") if isinstance(raw, dict) else None
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
        """Strictly read-only auth: this provider must NEVER refresh.

        Anthropic rotates refresh tokens with reuse detection, and claude
        sessions can run for days holding their tokens in memory — any
        rotation from outside the CLI strands a live session and gets the
        whole token family revoked (observed in practice as forced
        re-logins). Claude Code rewrites the credentials file whenever it
        runs; an expired on-disk token just means a data gap until then.
        """
        expires_at = creds.get("expiresAt")  # unix milliseconds
        if isinstance(expires_at, (int, float)) and expires_at / 1000 < time.time() + 60:
            raise ProviderError("on-disk token expired; will recover when claude next runs")
        if token := creds.get("accessToken"):
            return str(token)
        raise CredentialsUnavailable("no accessToken in credentials file")


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
