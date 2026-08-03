"""Google Gemini (Gemini CLI subscription) quota provider.

Reads Google OAuth credentials from ~/.gemini/oauth_creds.json and queries the
Cloud Code private API used by the Gemini CLI and Antigravity:

    POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary
    POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist

The quota summary reports buckets with an explicit window ("5h"/"weekly") and
remainingFraction (0..1, remaining — inverted here to utilization).
loadCodeAssist supplies the tier and the GCP project id the quota call needs.

Token refresh uses Google's standard token endpoint with the Gemini CLI's
public installed-app client credentials; refreshed tokens stay in memory.
"""

from __future__ import annotations

import json
import logging
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

log = logging.getLogger(__name__)

BASE_URL = "https://cloudcode-pa.googleapis.com/v1internal"
TOKEN_URL = "https://oauth2.googleapis.com/token"
# Public installed-app credentials of the Gemini CLI (committed in its source).
CLIENT_ID = "REMOVED_HISTORICAL_OAUTH_VALUE_1"
CLIENT_SECRET = "REMOVED_HISTORICAL_OAUTH_VALUE_2"

_WINDOW_NAMES = {"5h": "five_hour", "weekly": "seven_day"}


class GeminiProvider(Provider):
    name = "gemini"

    _access_token: str | None = None
    _access_token_expiry: float = 0.0
    _project: str | None = None
    _tier: str | None = None
    _summary_unavailable: bool = False

    def credential_path(self) -> Path:
        return self._home / ".gemini" / "oauth_creds.json"

    def fetch(self) -> ProviderSnapshot:
        token = self._get_access_token()
        if self._project is None:
            self._load_code_assist(token)

        samples: tuple[QuotaSample, ...] = ()
        if not self._summary_unavailable:
            try:
                summary = self._post(token, "retrieveUserQuotaSummary", {"project": self._project or ""})
                samples = tuple(_parse_summary(summary))
            except ProviderError as exc:
                # Latch off only on a definitive "not available on this tier"
                # (403/404); transient 5xx/network errors fail the cycle so a
                # single blip doesn't permanently downgrade to the plain list.
                if exc.status_code in (403, 404):
                    self._summary_unavailable = True
                    log.info("gemini: quota summary unavailable (%s), using plain quota from now on", exc)
                else:
                    raise
        if not samples:
            # Some tiers only serve the plainer per-model bucket list.
            quota = self._post(token, "retrieveUserQuota", {"project": self._project or ""})
            samples = tuple(_parse_buckets(quota.get("buckets") or []))
        if not samples:
            raise ProviderError("no quota buckets in either quota response")

        info = {"tier": self._tier} if self._tier else {}
        return ProviderSnapshot(samples=samples, info=info)

    def _get_access_token(self) -> str:
        if self._access_token and time.time() < self._access_token_expiry - 60:
            return self._access_token
        creds = self._read_credentials()
        expiry_ms = creds.get("expiry_date")
        if creds.get("access_token") and isinstance(expiry_ms, (int, float)) and expiry_ms / 1000 > time.time() + 60:
            self._access_token = creds["access_token"]
            self._access_token_expiry = expiry_ms / 1000
            return self._access_token
        return self._refresh(creds)

    def _read_credentials(self) -> dict[str, Any]:
        try:
            creds = json.loads(self.credential_path().read_text())
        except FileNotFoundError as exc:
            raise CredentialsUnavailable(str(exc)) from exc
        except (OSError, json.JSONDecodeError) as exc:
            raise ProviderError(f"unreadable oauth_creds.json: {exc}") from exc
        if not isinstance(creds, dict):
            raise ProviderError("oauth_creds.json is not an object")
        return creds

    def _refresh(self, creds: dict[str, Any]) -> str:
        refresh_token = creds.get("refresh_token")
        if not refresh_token:
            raise CredentialsUnavailable("access token expired and no refresh_token present")
        try:
            response = self._client.post(
                TOKEN_URL,
                data={
                    "client_id": CLIENT_ID,
                    "client_secret": CLIENT_SECRET,
                    "refresh_token": refresh_token,
                    "grant_type": "refresh_token",
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
        log.info("gemini: refreshed access token in memory")
        self._access_token = token
        self._access_token_expiry = time.time() + float(payload.get("expires_in") or 3600)
        return token

    def _load_code_assist(self, token: str) -> None:
        response = self._post(token, "loadCodeAssist", {"metadata": {"ideType": "GEMINI_CLI"}})
        self._project = response.get("cloudaicompanionProject") or ""
        tier = response.get("currentTier") or {}
        if isinstance(tier, dict) and (tier_id := tier.get("id") or tier.get("name")):
            self._tier = str(tier_id)

    def _post(self, token: str, method: str, body: dict[str, Any]) -> dict[str, Any]:
        try:
            response = self._client.post(
                f"{BASE_URL}:{method}",
                json=body,
                headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"{method} request failed: {exc}") from exc
        if response.status_code == 401:
            # Drop the cached token; next cycle re-reads the file and refreshes.
            self._access_token = None
            raise ProviderError(f"{method} returned HTTP 401 (token rejected)", status_code=401)
        if response.status_code != 200:
            raise ProviderError(
                f"{method} returned HTTP {response.status_code}", status_code=response.status_code
            )
        return json_object(response, method)


def _parse_summary(summary: dict[str, Any]) -> list[QuotaSample]:
    samples: list[QuotaSample] = []
    for group in summary.get("groups") or []:
        if not isinstance(group, dict):
            continue
        group_name = _slugify(str(group.get("displayName") or "all"))
        for bucket in group.get("buckets") or []:
            if not isinstance(bucket, dict):
                continue
            remaining = bucket.get("remainingFraction")
            if not isinstance(remaining, (int, float)):
                continue
            window = str(bucket.get("window") or "unknown")
            samples.append(
                QuotaSample(
                    window=_WINDOW_NAMES.get(window, window),
                    scope=group_name,
                    utilization=1.0 - float(remaining),
                    resets_at=parse_iso8601(bucket.get("resetTime")),
                )
            )
    return samples


def _parse_buckets(buckets: list[Any]) -> list[QuotaSample]:
    samples: list[QuotaSample] = []
    for bucket in buckets:
        if not isinstance(bucket, dict):
            continue
        remaining = bucket.get("remainingFraction")
        if not isinstance(remaining, (int, float)):
            continue
        scope = _slugify(str(bucket.get("modelId") or bucket.get("tokenType") or "all"))
        samples.append(
            QuotaSample(
                window="bucket",
                scope=scope,
                utilization=1.0 - float(remaining),
                resets_at=parse_iso8601(bucket.get("resetTime")),
            )
        )
    return samples


def _slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
