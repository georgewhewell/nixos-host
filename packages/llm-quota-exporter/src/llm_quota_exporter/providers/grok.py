"""xAI Grok (Grok Build CLI subscription) quota provider.

Reads the Grok CLI OAuth token from ~/.grok/auth.json (a map of
"issuer::client_id" -> credential entry) and queries the billing endpoints the
CLI's own billing extension uses:

    GET https://cli-chat-proxy.grok.com/v1/billing                 (monthly)
    GET https://cli-chat-proxy.grok.com/v1/billing?format=credits  (weekly)

Numeric fields may arrive bare or wrapped as {"val": N}.

Grok access tokens live ~6 hours and xAI rotates refresh tokens on use
(verified empirically), so like the Kimi provider this one refreshes only
when the on-disk token has already expired (the CLI refreshes ~5 minutes
before expiry while running, so an expired token means no CLI is managing
it) and persists the rotated pair back to auth.json atomically.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
import time
from datetime import UTC, datetime
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
    assert_writable,
    json_object,
)

log = logging.getLogger(__name__)

BILLING_URL = "https://cli-chat-proxy.grok.com/v1/billing"
TOKEN_AUTH_HEADER = "xai-grok-cli"
TOKEN_URL = "https://auth.x.ai/oauth2/token"
# Public client id of the Grok CLI OIDC app, used if the entry lacks one.
DEFAULT_CLIENT_ID = "b1a00492-073a-47ea-816f-4c329264a828"


class GrokProvider(Provider):
    name = "grok"

    def credential_path(self) -> Path:
        if grok_home := os.environ.get("GROK_HOME"):
            return Path(grok_home) / "auth.json"
        return self._home / ".grok" / "auth.json"

    def fetch(self) -> ProviderSnapshot:
        token = self._read_token()
        monthly = self._billing_request(token, params=None)
        weekly = self._billing_request(token, params={"format": "credits"})

        samples = tuple(_parse_monthly(monthly) + _parse_weekly(weekly))
        if not samples:
            raise ProviderError("no billing data in either billing response")
        return ProviderSnapshot(samples=samples)

    def _read_token(self) -> str:
        path = self.credential_path()
        try:
            raw = json.loads(path.read_text())
        except FileNotFoundError as exc:
            raise CredentialsUnavailable(str(exc)) from exc
        except (OSError, json.JSONDecodeError) as exc:
            raise ProviderError(f"unreadable auth.json: {exc}") from exc
        if not isinstance(raw, dict):
            raise CredentialsUnavailable("auth.json is not an object")
        expired_without_refresh = False
        for key, entry in raw.items():
            if not isinstance(entry, dict):
                continue
            token_field = "key" if entry.get("key") else "access_token" if entry.get("access_token") else None
            if token_field is None:
                continue
            expires_at = parse_iso8601(entry.get("expires_at"))
            if expires_at is not None and expires_at < time.time() + 30:
                if entry.get("refresh_token"):
                    return self._refresh(path, raw, key, entry, token_field)
                expired_without_refresh = True
                continue
            return str(entry[token_field])
        if expired_without_refresh:
            raise ProviderError("access token expired and no refresh_token present")
        raise CredentialsUnavailable("no credential entry with a token in auth.json")

    def _refresh(self, path: Path, raw: dict[str, Any], key: str, entry: dict[str, Any], token_field: str) -> str:
        """Refresh the expired token and persist the rotated pair.

        xAI rotates refresh tokens, so the new pair must be written back or the
        CLI would be stranded on a consumed token. We only get here when the
        token has already expired, i.e. no running CLI is managing the file.
        The new access token is written to whichever field held the old one
        (``key`` or ``access_token``) so the CLI reads the fresh value.
        """
        assert_writable(path)
        try:
            response = self._client.post(
                TOKEN_URL,
                data={
                    "grant_type": "refresh_token",
                    "refresh_token": entry["refresh_token"],
                    "client_id": entry.get("oidc_client_id") or DEFAULT_CLIENT_ID,
                },
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"token refresh failed: {exc}") from exc
        if response.status_code != 200:
            raise ProviderError(f"token refresh returned HTTP {response.status_code}")
        payload = json_object(response, "token refresh")
        token = payload.get("access_token")
        if not token:
            raise ProviderError("token refresh response had no access_token")

        expires_in = float(payload.get("expires_in") or 21600)
        updated_entry = dict(entry)
        updated_entry[token_field] = token
        updated_entry["refresh_token"] = payload.get("refresh_token", entry["refresh_token"])
        updated_entry["expires_at"] = (
            datetime.fromtimestamp(time.time() + expires_in, tz=UTC).strftime("%Y-%m-%dT%H:%M:%S.%f000Z")
        )
        updated = dict(raw)
        updated[key] = updated_entry
        try:
            fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
            with os.fdopen(fd, "w") as handle:
                json.dump(updated, handle, indent=2)
            os.chmod(tmp, 0o600)
            os.replace(tmp, path)
        except OSError as exc:
            raise ProviderError(f"refreshed but could not persist rotated tokens: {exc}") from exc
        log.info("grok: refreshed access token and persisted rotated pair")
        return str(token)

    def _billing_request(self, token: str, params: dict[str, str] | None) -> dict[str, Any]:
        try:
            response = self._client.get(
                BILLING_URL,
                params=params,
                headers={
                    "Authorization": f"Bearer {token}",
                    "x-xai-token-auth": TOKEN_AUTH_HEADER,
                    "Accept": "application/json",
                },
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"billing request failed: {exc}") from exc
        if response.status_code in (401, 403):
            raise ProviderError(
                f"HTTP {response.status_code}: token stale; will recover after the grok CLI refreshes it"
            )
        if response.status_code != 200:
            raise ProviderError(f"billing endpoint returned HTTP {response.status_code}")
        payload = response.json()
        return payload if isinstance(payload, dict) else {}


def _unwrap(value: Any) -> float | None:
    """Billing numbers arrive either bare or as {"val": N}."""
    if isinstance(value, dict):
        value = value.get("val")
    return float(value) if isinstance(value, (int, float)) else None


def _parse_monthly(payload: dict[str, Any]) -> list[QuotaSample]:
    config = payload.get("config")
    if not isinstance(config, dict):
        return []
    limit = _unwrap(config.get("monthlyLimit"))
    used = _unwrap(config.get("used"))
    if not limit or used is None:
        return []
    return [
        QuotaSample(
            window="monthly",
            scope="all",
            utilization=used / limit,
            resets_at=parse_iso8601(config.get("billingPeriodEnd")),
            used=used,
            limit=limit,
        )
    ]


def _parse_weekly(payload: dict[str, Any]) -> list[QuotaSample]:
    config = payload.get("config")
    if not isinstance(config, dict):
        return []
    # creditUsagePercent is omitted entirely at 0% usage.
    percent = _unwrap(config.get("creditUsagePercent"))
    if percent is None and "currentPeriod" not in config:
        return []
    return [
        QuotaSample(
            window="seven_day",
            scope="all",
            utilization=(percent or 0.0) / 100.0,
            resets_at=parse_iso8601(config.get("billingPeriodEnd")),
        )
    ]
