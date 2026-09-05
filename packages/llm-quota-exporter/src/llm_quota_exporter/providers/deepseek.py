"""DeepSeek (prepaid balance / API key) quota provider.

Like OpenRouter there is no DeepSeek CLI on these machines, so there is no
single credential file to read. The key is wherever it was last configured, so
several shapes are tried, in order:

    $DEEPSEEK_API_KEY
    ~/.pi/agent/auth.json               {"deepseek": {"type": "api_key", "key": ...}}
    ~/.config/opencode/config.json      provider.deepseek.options.apiKey
    ~/.local/share/opencode/auth.json   {"deepseek": {"type": "api", "key": ...}}
    ~/.dsh/credentials.json             dsh's credentials-local store
    ~/.config/deepseek/key              a bare key on one line

One endpoint carries everything DeepSeek exposes about entitlement:

    GET https://api.deepseek.com/user/balance

    {"is_available": false,
     "balance_infos": [{"currency": "USD", "total_balance": "0.00",
                        "granted_balance": "0.00", "topped_up_balance": "0.00"}]}

DeepSeek is pure pay-as-you-go: there is no subscription window, no rate-limit
quota and no reset time in the API, so this provider reports no `resets_at` and
invents no windows it cannot observe. What it can say is how much of the
account's granted allowance has been drawn down, and — most usefully — whether
the account can serve a request at all. `is_available: false` means every
completion returns HTTP 402 Insufficient Balance, which is otherwise only
discoverable by making a request and having it fail.
"""

from __future__ import annotations

import json
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

BASE_URL = "https://api.deepseek.com"


class DeepSeekProvider(Provider):
    name = "deepseek"

    def credential_path(self) -> Path:
        return self._home / ".config" / "deepseek" / "key"

    def available(self) -> bool:
        return self._api_key() is not None

    def fetch(self) -> ProviderSnapshot:
        key = self._api_key()
        if key is None:
            raise CredentialsUnavailable("no DEEPSEEK_API_KEY, pi/opencode/dsh entry or key file found")

        payload = self._get(key, "user/balance")
        balance = _usd_balance(payload)
        if balance is None:
            raise ProviderError("user/balance reported no usable balance_infos entry")

        samples = _parse_balance(payload)
        if not samples:
            raise ProviderError("user/balance reported neither a granted allowance nor availability")

        info = {"plan": "pay-as-you-go"}
        topped_up = _num(balance.get("topped_up_balance"))
        if topped_up is not None:
            info["tier"] = "topped-up" if topped_up > 0 else "granted-only"

        return ProviderSnapshot(
            samples=tuple(samples),
            info=info,
            credits_balance=_num(balance.get("total_balance")),
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
        if env_key := os.environ.get("DEEPSEEK_API_KEY"):
            return env_key.strip()
        for source in (
            self._pi_key,
            self._opencode_config_key,
            self._opencode_auth_key,
            self._dsh_key,
        ):
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
        """pi: {"deepseek": {"type": "api_key", "key": ...}}."""
        return _dig(self._load_json(".pi", "agent", "auth.json"), "deepseek", "key")

    def _opencode_auth_key(self) -> str | None:
        """opencode's logged-in credential store, same shape as pi's."""
        return _dig(self._load_json(".local", "share", "opencode", "auth.json"), "deepseek", "key")

    def _opencode_config_key(self) -> str | None:
        """opencode's declarative config: provider.deepseek.options.apiKey."""
        config = self._load_json(".config", "opencode", "config.json")
        return _dig(config, "provider", "deepseek", "options", "apiKey")

    def _dsh_key(self) -> str | None:
        """dsh-credentials-local, written when the key is entered in the web UI."""
        credentials = self._load_json(".dsh", "credentials.json")
        for keys in (("deepseek",), ("deepseek-official",)):
            if value := _dig(credentials, *keys, "key"):
                return value
        return None


def _parse_balance(payload: dict[str, Any]) -> list[QuotaSample]:
    balance = _usd_balance(payload)
    if balance is None:
        return []

    total = _num(balance.get("total_balance"))
    granted = _num(balance.get("granted_balance"))

    samples: list[QuotaSample] = []
    # Utilization only means something against the granted allowance: a
    # topped-up balance has no ceiling to divide by, so spend against it is
    # unbounded and any ratio would be fiction. Report the granted window
    # alone, and let llm_credits_balance carry the absolute figure.
    if granted is not None and granted > 0:
        remaining = min(max(total or 0.0, 0.0), granted)
        samples.append(
            QuotaSample(
                window="granted",
                scope="all",
                utilization=min(max((granted - remaining) / granted, 0.0), 1.0),
                used=granted - remaining,
                limit=granted,
            )
        )

    # An exhausted account is the single most actionable fact here, and it is
    # not otherwise visible until a completion fails with 402. Surface it as a
    # saturated window so the dashboard's existing thresholds colour it red
    # without needing a bespoke panel.
    available = payload.get("is_available")
    if isinstance(available, bool):
        samples.append(
            QuotaSample(window="serviceable", scope="all", utilization=0.0 if available else 1.0)
        )
    return samples


def _dig(payload: Any, *keys: str) -> str | None:
    """Walk a nested dict, returning the leaf as a non-empty string or None."""
    for key in keys:
        if not isinstance(payload, dict):
            return None
        payload = payload.get(key)
    return str(payload).strip() or None if isinstance(payload, str) else None


def _num(value: Any) -> float | None:
    """DeepSeek returns balances as decimal *strings* ("0.00"), not numbers."""
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


def _usd_balance(payload: dict[str, Any]) -> dict[str, Any] | None:
    """Pick the USD entry from balance_infos, falling back to the first one.

    The API returns one entry per currency (CNY accounts exist), and mixing
    currencies into one gauge would be meaningless. Prefer USD; if the account
    is billed in something else, report that rather than nothing.
    """
    infos = payload.get("balance_infos")
    if not isinstance(infos, list):
        return None
    entries = [entry for entry in infos if isinstance(entry, dict)]
    for entry in entries:
        if str(entry.get("currency", "")).upper() == "USD":
            return entry
    return entries[0] if entries else None
