"""Kimi (Moonshot AI coding plan) quota provider.

Reads the kimi-cli OAuth token from ~/.kimi-code/credentials/kimi-code.json
(or ~/.kimi/..., depending on the distribution), falling back to a coding-plan
api_key from config.toml, and queries the endpoint behind the CLI's /usage
command:

    GET https://api.kimi.com/coding/v1/usages

The response reports a weekly `usage` object, a `limits` array whose windows
include the 5-hour session (duration 300 TIME_UNIT_MINUTE), and sometimes a
monthly `totalQuota`. Some deployments report `remaining` instead of `used`.

Kimi access tokens live only ~15 minutes, so unlike the other providers this
one must refresh to be useful. Moonshot rotates refresh tokens but tolerates
reuse of the previous one (verified empirically), so refresh is safe as long
as the rotated pair is persisted: we refresh only when the on-disk token has
already expired (i.e. the CLI is dormant and not managing it) and write the
new pair back atomically in the CLI's own file format.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
import time
import tomllib
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

USAGES_URL = "https://api.kimi.com/coding/v1/usages"
TOKEN_URL = "https://auth.kimi.com/api/oauth/token"
# Public client id of the kimi-cli device-flow app.
CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098"

_MINUTES = {"TIME_UNIT_MINUTE": 60, "TIME_UNIT_HOUR": 3600, "TIME_UNIT_DAY": 86400}


class KimiProvider(Provider):
    name = "kimi"

    def credential_path(self) -> Path:
        for share_dir in (self._home / ".kimi-code", self._home / ".kimi"):
            path = share_dir / "credentials" / "kimi-code.json"
            if path.exists():
                return path
        return self._home / ".kimi" / "credentials" / "kimi-code.json"

    def available(self) -> bool:
        return self.credential_path().exists() or self._config_api_key() is not None

    def fetch(self) -> ProviderSnapshot:
        token = self._read_token()
        try:
            response = self._client.get(
                USAGES_URL,
                headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"usages request failed: {exc}") from exc
        if response.status_code in (401, 403):
            raise ProviderError(
                f"HTTP {response.status_code}: token stale; will recover after the kimi CLI refreshes it"
            )
        if response.status_code != 200:
            raise ProviderError(f"usages endpoint returned HTTP {response.status_code}")

        payload = json_object(response, "usages endpoint")
        samples = tuple(_parse_usages(payload))
        if not samples:
            raise ProviderError("no usage windows in usages response")

        info = {}
        if level := ((payload.get("user") or {}).get("membership") or {}).get("level"):
            info["plan"] = str(level).removeprefix("LEVEL_").lower()
        return ProviderSnapshot(samples=samples, info=info)

    def _read_token(self) -> str:
        path = self.credential_path()
        if path.exists():
            try:
                creds = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError) as exc:
                raise ProviderError(f"unreadable {path.name}: {exc}") from exc
            if not isinstance(creds, dict):
                raise ProviderError(f"{path.name} is not a JSON object")
            expires_at = creds.get("expires_at")
            expired = isinstance(expires_at, (int, float)) and expires_at < time.time() + 30
            if not expired and (token := creds.get("access_token")):
                return str(token)
            if creds.get("refresh_token"):
                return self._refresh(path, creds)
        if api_key := self._config_api_key():
            return api_key
        raise CredentialsUnavailable("no kimi-code.json credentials or coding-plan api_key found")

    def _refresh(self, path: Path, creds: dict[str, Any]) -> str:
        """Refresh the expired token and persist the rotated pair.

        Persisting is required: Moonshot rotates refresh tokens, so keeping the
        new pair only in memory would strand the CLI on a stale (grace-period)
        token chain. The write is atomic and matches the CLI's file format;
        we only get here when the on-disk token has already expired, i.e. the
        CLI is not running and not racing us.
        """
        assert_writable(path)
        try:
            response = self._client.post(
                TOKEN_URL,
                data={
                    "client_id": CLIENT_ID,
                    "grant_type": "refresh_token",
                    "refresh_token": creds["refresh_token"],
                },
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"token refresh failed: {exc}") from exc
        if response.status_code != 200:
            raise ProviderError(f"token refresh returned HTTP {response.status_code}")
        payload = json_object(response, "token refresh")
        if not payload.get("access_token"):
            raise ProviderError("token refresh response had no access_token")

        expires_in = payload.get("expires_in", 900)
        updated = dict(creds)
        updated.update(
            access_token=payload["access_token"],
            refresh_token=payload.get("refresh_token", creds["refresh_token"]),
            expires_in=expires_in,
            expires_at=time.time() + float(expires_in),
            scope=payload.get("scope", creds.get("scope")),
            token_type=payload.get("token_type", creds.get("token_type")),
        )
        try:
            fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
            with os.fdopen(fd, "w") as handle:
                json.dump(updated, handle)
            os.chmod(tmp, 0o600)
            os.replace(tmp, path)
        except OSError as exc:
            raise ProviderError(f"refreshed but could not persist rotated tokens: {exc}") from exc
        log.info("kimi: refreshed access token and persisted rotated pair")
        return str(payload["access_token"])

    def _config_api_key(self) -> str | None:
        """Coding-plan api_key from config.toml, for non-OAuth logins."""
        for share_dir in (self._home / ".kimi-code", self._home / ".kimi"):
            config_path = share_dir / "config.toml"
            if not config_path.exists():
                continue
            try:
                config = tomllib.loads(config_path.read_text())
            except (OSError, tomllib.TOMLDecodeError):
                continue
            providers = config.get("providers")
            if not isinstance(providers, dict):
                continue
            for provider in providers.values():
                if not isinstance(provider, dict):
                    continue
                if "api.kimi.com/coding" in str(provider.get("base_url", "")) and provider.get("api_key"):
                    return str(provider["api_key"])
        return None


def _window_name(window: dict[str, Any]) -> str:
    duration = window.get("duration")
    unit = _MINUTES.get(str(window.get("timeUnit")), 0)
    if isinstance(duration, (int, float)) and unit:
        hours = duration * unit / 3600
        if round(hours) == 5:
            return "five_hour"
        if round(hours / 24) == 7:
            return "seven_day"
        return f"{round(hours)}h"
    return "unknown"


def _num(value: Any) -> float | None:
    """Coerce ints, floats and protobuf-JSON string-encoded numbers ("100")."""
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


def _sample(detail: dict[str, Any], window: str) -> QuotaSample | None:
    limit = _num(detail.get("limit"))
    if limit is None or limit <= 0:
        return None
    used = _num(detail.get("used"))
    if used is None:
        remaining = _num(detail.get("remaining"))
        if remaining is None:
            return None
        used = limit - remaining
    return QuotaSample(
        window=window,
        scope="all",
        utilization=used / limit,
        resets_at=parse_iso8601(detail.get("resetTime")),
        used=used,
        limit=limit,
    )


def _parse_usages(payload: dict[str, Any]) -> list[QuotaSample]:
    samples: list[QuotaSample] = []
    if isinstance(weekly := payload.get("usage"), dict) and (sample := _sample(weekly, "seven_day")):
        samples.append(sample)
    for entry in payload.get("limits") or []:
        if not isinstance(entry, dict):
            continue
        detail = entry.get("detail")
        window = entry.get("window")
        if isinstance(detail, dict) and isinstance(window, dict) and (sample := _sample(detail, _window_name(window))):
            samples.append(sample)
    if isinstance(monthly := payload.get("totalQuota"), dict) and (sample := _sample(monthly, "monthly")):
        samples.append(sample)
    return samples
