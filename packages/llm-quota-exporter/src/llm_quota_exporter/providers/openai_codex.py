"""OpenAI (ChatGPT/Codex subscription) quota provider.

Reads the Codex CLI token from ~/.codex/auth.json and queries the endpoint the
CLI itself uses for its rate-limit display:

    GET https://chatgpt.com/backend-api/wham/usage

primary_window is the short (5-hour) window, secondary_window the weekly one;
both report used_percent (0-100), limit_window_seconds and reset_at (epoch s).

No token refresh is attempted: OpenAI rotates refresh tokens on use, so an
out-of-band refresh that does not rewrite auth.json would invalidate the CLI's
own login. On 401 we fail the cycle and recover once the codex CLI refreshes
its credentials.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

import httpx

from .base import (
    CredentialsUnavailable,
    Provider,
    ProviderError,
    ProviderSnapshot,
    QuotaSample,
    json_object,
)

USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
USER_AGENT = "codex-cli"

_WINDOW_NAMES = {"primary_window": "primary", "secondary_window": "secondary"}


class OpenAICodexProvider(Provider):
    name = "openai"

    def credential_path(self) -> Path:
        if codex_home := os.environ.get("CODEX_HOME"):
            return Path(codex_home) / "auth.json"
        return self._home / ".codex" / "auth.json"

    def fetch(self) -> ProviderSnapshot:
        tokens = self._read_tokens()
        access_token = tokens.get("access_token")
        if not access_token:
            raise CredentialsUnavailable("no tokens.access_token in auth.json")

        headers = {
            "Authorization": f"Bearer {access_token}",
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
        }
        if account_id := tokens.get("account_id"):
            headers["ChatGPT-Account-Id"] = account_id

        try:
            response = self._client.get(USAGE_URL, headers=headers)
        except httpx.HTTPError as exc:
            raise ProviderError(f"usage request failed: {exc}") from exc
        if response.status_code in (401, 403):
            raise ProviderError(
                f"HTTP {response.status_code}: access token stale; will recover after the codex CLI refreshes it"
            )
        if response.status_code != 200:
            raise ProviderError(f"usage endpoint returned HTTP {response.status_code}")

        payload = json_object(response, "usage endpoint")
        samples = tuple(_parse_usage(payload))
        if not samples:
            raise ProviderError("no rate-limit windows in usage response")

        info = {}
        if plan := payload.get("plan_type"):
            info["plan"] = str(plan)
        return ProviderSnapshot(samples=samples, info=info, credits_balance=_parse_credits(payload))

    def _read_tokens(self) -> dict[str, Any]:
        try:
            raw = json.loads(self.credential_path().read_text())
        except FileNotFoundError as exc:
            raise CredentialsUnavailable(str(exc)) from exc
        except (OSError, json.JSONDecodeError) as exc:
            raise ProviderError(f"unreadable auth.json: {exc}") from exc
        tokens = raw.get("tokens")
        if not isinstance(tokens, dict):
            raise CredentialsUnavailable("tokens section missing from auth.json (api-key login?)")
        return tokens


def _parse_rate_limit(rate_limit: Any, scope: str) -> list[QuotaSample]:
    samples: list[QuotaSample] = []
    if not isinstance(rate_limit, dict):
        return samples
    for key, window_name in _WINDOW_NAMES.items():
        window = rate_limit.get(key)
        if not isinstance(window, dict):
            continue
        used_percent = window.get("used_percent")
        if not isinstance(used_percent, (int, float)):
            continue
        samples.append(
            QuotaSample(
                window=_describe_window(window, window_name),
                scope=scope,
                utilization=used_percent / 100.0,
                resets_at=float(reset_at) if isinstance(reset_at := window.get("reset_at"), (int, float)) else None,
            )
        )
    return samples


def _parse_usage(payload: dict[str, Any]) -> list[QuotaSample]:
    samples = _parse_rate_limit(payload.get("rate_limit"), "all")
    samples += _parse_rate_limit(payload.get("code_review_rate_limit"), "code_review")
    for entry in payload.get("additional_rate_limits") or []:
        if not isinstance(entry, dict):
            continue
        scope = _slugify(str(entry.get("limit_name") or entry.get("metered_feature") or "additional"))
        samples += _parse_rate_limit(entry.get("rate_limit"), scope)
    return samples


def _parse_credits(payload: dict[str, Any]) -> float | None:
    balance = (payload.get("credits") or {}).get("balance")
    try:
        return float(balance)
    except (TypeError, ValueError):
        return None


def _slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def _describe_window(window: dict[str, Any], fallback: str) -> str:
    """Name windows by their reported length (five_hour/seven_day) when available."""
    seconds = window.get("limit_window_seconds")
    if isinstance(seconds, (int, float)) and seconds > 0:
        hours = seconds / 3600
        if hours <= 12:
            return "five_hour" if round(hours) == 5 else f"{round(hours)}h"
        days = round(hours / 24)
        return "seven_day" if days == 7 else f"{days}d"
    return fallback
