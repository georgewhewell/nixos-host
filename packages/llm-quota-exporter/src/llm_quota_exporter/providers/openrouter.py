"""OpenRouter (prepaid credits / API key) quota provider.

Unlike the other providers there is no OpenRouter CLI on these machines, so
there is no one credential file to read. The key is whichever agent was
pointed at OpenRouter last, so several shapes are tried, in order:

    $OPENROUTER_API_KEY
    ~/.pi/agent/auth.json               {"openrouter": {"type": "api_key", "key": ...}}
    ~/.config/opencode/config.json      provider.openrouter.options.apiKey
    ~/.local/share/opencode/auth.json   {"openrouter": {"type": "api", "key": ...}}
    ~/.config/openrouter/key            a bare key on one line

Two endpoints are queried:

    GET https://openrouter.ai/api/v1/key      -> per-key limit and usage
    GET https://openrouter.ai/api/v1/credits  -> account credits purchased/spent

OpenRouter is pay-as-you-go rather than a subscription, so "utilization" means
two different things and both are reported: the `credits` window is the share
of purchased credits already spent, and the `key` window (only present when the
key carries an explicit cap) is that key's spend against its own limit.
"""

from __future__ import annotations

import json
import logging
import os
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

log = logging.getLogger(__name__)

BASE_URL = "https://openrouter.ai/api/v1"


class OpenRouterProvider(Provider):
    name = "openrouter"

    def credential_path(self) -> Path:
        return self._home / ".config" / "openrouter" / "key"

    def available(self) -> bool:
        return self._api_key() is not None

    def fetch(self) -> ProviderSnapshot:
        key = self._api_key()
        if key is None:
            raise CredentialsUnavailable("no OPENROUTER_API_KEY, opencode entry or key file found")

        credits = self._get(key, "credits")
        samples = list(_parse_credits(credits))

        info: dict[str, str] = {}
        spend = _num((credits.get("data") or {}).get("total_usage"))
        # The key endpoint is optional: provisioning keys and some org keys are
        # refused there (403) while /credits still answers, so a failure must
        # not lose the credits sample we already have.
        try:
            key_status = self._get(key, "key")
        except ProviderError as exc:
            log.info("openrouter: key endpoint unavailable (%s), reporting credits only", exc)
        else:
            samples.extend(_parse_key(key_status))
            data = key_status.get("data") or {}
            info["plan"] = "free" if data.get("is_free_tier") else "paid"
            # An unnamed key's label is just its own truncated value; only a
            # label the user actually chose is worth a metric label.
            label = str(data.get("label") or "")
            if label and not label.startswith("sk-or-"):
                info["tier"] = label

        if not samples:
            raise ProviderError("neither credits nor key endpoint reported a usable quota")

        return ProviderSnapshot(
            samples=tuple(samples),
            info=info,
            spend_usd=spend,
            credits_balance=_remaining(credits),
        )

    def _get(self, key: str, path: str) -> dict[str, Any]:
        try:
            response = self._client.get(
                f"{BASE_URL}/{path}",
                headers={"Authorization": f"Bearer {key}", "Accept": "application/json"},
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"{path} request failed: {exc}") from exc
        if response.status_code != 200:
            raise ProviderError(
                f"{path} endpoint returned HTTP {response.status_code}", status_code=response.status_code
            )
        return json_object(response, f"{path} endpoint")

    def _api_key(self) -> str | None:
        if env_key := os.environ.get("OPENROUTER_API_KEY"):
            return env_key.strip()
        for source in (self._pi_key, self._opencode_config_key, self._opencode_auth_key):
            if key := source():
                return key
        try:
            return self.credential_path().read_text().strip() or None
        except OSError:
            return None

    def _load_json(self, *parts: str) -> Any:
        try:
            return json.loads(self._home.joinpath(*parts).read_text())
        except (OSError, json.JSONDecodeError):
            return None

    def _pi_key(self) -> str | None:
        """pi: {"openrouter": {"type": "api_key", "key": ...}}."""
        auth = self._load_json(".pi", "agent", "auth.json")
        return _dig(auth, "openrouter", "key")

    def _opencode_auth_key(self) -> str | None:
        """opencode's logged-in credential store, same shape as pi's."""
        auth = self._load_json(".local", "share", "opencode", "auth.json")
        return _dig(auth, "openrouter", "key")

    def _opencode_config_key(self) -> str | None:
        """opencode's declarative config: provider.openrouter.options.apiKey."""
        config = self._load_json(".config", "opencode", "config.json")
        return _dig(config, "provider", "openrouter", "options", "apiKey")


def _dig(payload: Any, *keys: str) -> str | None:
    """Walk a nested dict, returning the leaf as a non-empty string or None."""
    for key in keys:
        if not isinstance(payload, dict):
            return None
        payload = payload.get(key)
    return str(payload).strip() or None if isinstance(payload, str) else None


def _num(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def _remaining(credits: dict[str, Any]) -> float | None:
    data = credits.get("data") or {}
    total = _num(data.get("total_credits"))
    used = _num(data.get("total_usage"))
    if total is None or used is None:
        return None
    return total - used


def _parse_credits(credits: dict[str, Any]) -> list[QuotaSample]:
    data = credits.get("data") or {}
    total = _num(data.get("total_credits"))
    used = _num(data.get("total_usage"))
    if total is None or used is None or total <= 0:
        return []
    return [
        QuotaSample(
            window="credits",
            scope="all",
            utilization=min(used / total, 1.0),
            used=used,
            limit=total,
        )
    ]


def _parse_key(key_status: dict[str, Any]) -> list[QuotaSample]:
    data = key_status.get("data") or {}
    limit = _num(data.get("limit"))
    # A null limit means the key is uncapped and draws on account credits;
    # the credits window already covers that, so emit nothing here.
    if limit is None or limit <= 0:
        return []
    # `usage` is the key's LIFETIME spend, but `limit` applies to the current
    # `limit_reset` period ("daily"/"weekly"/"monthly"), so charging lifetime
    # usage against it overstates the window badly. limit_remaining is the
    # only field scoped to the live window; fall back to the matching
    # usage_<period>, and only use lifetime usage for a lifetime cap.
    reset = str(data.get("limit_reset") or "").lower()
    remaining = _num(data.get("limit_remaining"))
    if remaining is not None:
        used = limit - remaining
    elif reset:
        used = _num(data.get(f"usage_{reset}"))
    else:
        used = _num(data.get("usage"))
    if used is None:
        return []
    return [
        QuotaSample(
            window=reset or "key",
            scope="all",
            utilization=min(max(used, 0.0) / limit, 1.0),
            used=used,
            limit=limit,
        )
    ]
