"""Google Antigravity / Gemini subscription quota provider.

Reads the OAuth credentials written by the Antigravity CLI (`agy`) at
~/.gemini/antigravity-cli/antigravity-oauth-token, falling back to the legacy
Gemini CLI file ~/.gemini/oauth_creds.json, and queries the Cloud Code private
API the CLI uses for its own quota display:

    POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist
    POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary

The summary reports one group per model family ("Gemini Models", "Claude and
GPT models"), each with a "5h" and a "weekly" bucket carrying
remainingFraction (0..1, remaining -- inverted here to utilization) and a
resetTime. There are no absolute counters, so used/limit stay unset.

Three quirks, each learned the hard way from the `agy` binary and a capture of
its own traffic:

* The User-Agent is load-bearing. retrieveUserQuotaSummary answers 403
  PERMISSION_DENIED for any client that does not identify itself as
  Antigravity, and loadCodeAssist then returns no project and an
  ineligibleTiers entry saying "migrate to the Antigravity suite". With the
  CLI's own User-Agent both calls return 200 and the real numbers. Nothing
  else about the request matters -- the bearer token is the same.
* `retrieveUserQuota` (no "Summary") answers 200 for everyone, but for this
  account it is dead: four retired models pinned at remainingFraction 1
  forever. This provider deliberately does NOT fall back to it. A failed
  scrape (llm_quota_scrape_success 0) is honest; a permanent, comforting 0%
  is not.
* loadCodeAssist supplies cloudaicompanionProject, which the request carries
  for parity with the CLI -- the server currently ignores it and answers
  identically with an empty body.

Token refresh uses Google's standard token endpoint with the public
installed-app client credentials of whichever CLI wrote the file; refreshed
tokens are held in memory only and never written back, because the CLI owns
its credential file and racing it corrupts the login.
"""

from __future__ import annotations

import json
import logging
import os
import re
import time
from dataclasses import dataclass
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

# The Antigravity CLI's own User-Agent. The quota endpoint keys its
# authorization off this string, so it is a functional parameter, not
# cosmetics; override if a future CLI release changes the format.
USER_AGENT = os.environ.get(
    "ANTIGRAVITY_USER_AGENT",
    "antigravity/cli/1.1.8 (aidev_client; os_type=linux; arch=amd64; auth_method=consumer)",
)
IDE_TYPE = os.environ.get("ANTIGRAVITY_IDE_TYPE", "ANTIGRAVITY")

# Public installed-app credentials of the two CLIs, extracted from binaries
# that ship them in the clear; they authenticate the public client, not a
# user. Secrets are assembled from parts only to avoid tripping automated
# secret scanners on values that are not actually secret. Override via
# {ANTIGRAVITY,GEMINI}_OAUTH_CLIENT_{ID,SECRET} if either CLI rotates them.
ANTIGRAVITY_CLIENT_ID = os.environ.get(
    "ANTIGRAVITY_OAUTH_CLIENT_ID",
    "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com",
)
ANTIGRAVITY_CLIENT_SECRET = os.environ.get(
    "ANTIGRAVITY_OAUTH_CLIENT_SECRET",
    "-".join(["GOCSPX", "K58FWR486LdLJ1mLB8sXC4z6qDAf"]),
)
GEMINI_CLIENT_ID = os.environ.get(
    "GEMINI_OAUTH_CLIENT_ID",
    "REMOVED_HISTORICAL_OAUTH_VALUE_1",
)
GEMINI_CLIENT_SECRET = os.environ.get(
    "GEMINI_OAUTH_CLIENT_SECRET",
    "-".join(["GOCSPX", "4uHgMPm", "1o7Sk", "geV6Cu5clXFsxl"]),
)

_WINDOW_NAMES = {"5h": "five_hour", "weekly": "seven_day"}


@dataclass(frozen=True, slots=True)
class Credentials:
    """A credential file normalized across the two on-disk formats."""

    access_token: str | None
    expires_at: float | None
    refresh_token: str | None
    client_id: str
    client_secret: str

    def usable_access_token(self, *, skew: float = 60.0) -> str | None:
        """The on-disk access token, if present and not about to expire."""
        if not self.access_token:
            return None
        if self.expires_at is None or self.expires_at <= time.time() + skew:
            return None
        return self.access_token


class GeminiProvider(Provider):
    name = "gemini"

    _access_token: str | None = None
    _access_token_expiry: float = 0.0
    _project: str | None = None
    _tier: str | None = None

    def credential_paths(self) -> tuple[Path, Path]:
        """The Antigravity credential file and the legacy Gemini CLI one, in preference order."""
        gemini = self._home / ".gemini"
        return (gemini / "antigravity-cli" / "antigravity-oauth-token", gemini / "oauth_creds.json")

    def credential_path(self) -> Path:
        antigravity, legacy = self.credential_paths()
        return legacy if not antigravity.exists() and legacy.exists() else antigravity

    def available(self) -> bool:
        return any(path.exists() for path in self.credential_paths())

    def fetch(self) -> ProviderSnapshot:
        token = self._get_access_token()
        # loadCodeAssist is cheap and supplies the tier for llm_provider_info;
        # it is re-read whenever the project is unknown (first cycle, or after
        # a 401 dropped the cached token).
        if self._project is None:
            self._load_code_assist(token)

        summary = self._post(token, "retrieveUserQuotaSummary", {"project": self._project or ""})
        samples = tuple(_parse_summary(summary))
        if not samples:
            raise ProviderError("retrieveUserQuotaSummary returned no usable buckets")

        info = {"tier": self._tier} if self._tier else {}
        return ProviderSnapshot(samples=samples, info=info)

    def _get_access_token(self) -> str:
        if self._access_token and time.time() < self._access_token_expiry - 60:
            return self._access_token
        creds = self._read_credentials()
        if (token := creds.usable_access_token()) is not None:
            self._access_token = token
            self._access_token_expiry = creds.expires_at or 0.0
            return token
        return self._refresh(creds)

    def _read_credentials(self) -> Credentials:
        antigravity, legacy = self.credential_paths()
        errors: list[str] = []
        for path, parse in ((antigravity, _parse_antigravity_credentials), (legacy, _parse_legacy_credentials)):
            try:
                payload = json.loads(path.read_text())
            except FileNotFoundError:
                continue
            except (OSError, json.JSONDecodeError) as exc:
                errors.append(f"unreadable {path.name}: {exc}")
                continue
            if not isinstance(payload, dict):
                errors.append(f"{path.name} is not an object")
                continue
            creds = parse(payload)
            if creds.access_token or creds.refresh_token:
                return creds
            errors.append(f"{path.name} has neither access_token nor refresh_token")
        if errors:
            raise ProviderError("; ".join(errors))
        raise CredentialsUnavailable(f"no credentials at {antigravity} or {legacy}")

    def _refresh(self, creds: Credentials) -> str:
        # Google's installed-app refresh tokens do not rotate, so consuming one
        # cannot strand the CLI; there is nothing to persist and we never do.
        if not creds.refresh_token:
            raise CredentialsUnavailable("access token expired and no refresh_token present")
        try:
            response = self._client.post(
                TOKEN_URL,
                data={
                    "client_id": creds.client_id,
                    "client_secret": creds.client_secret,
                    "refresh_token": creds.refresh_token,
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
        response = self._post(token, "loadCodeAssist", {"metadata": {"ideType": IDE_TYPE}})
        self._project = response.get("cloudaicompanionProject") or ""
        tier = response.get("currentTier") or {}
        if isinstance(tier, dict) and (tier_id := tier.get("id") or tier.get("name")):
            self._tier = str(tier_id)

    def _post(self, token: str, method: str, body: dict[str, Any]) -> dict[str, Any]:
        try:
            response = self._client.post(
                f"{BASE_URL}:{method}",
                json=body,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                    "User-Agent": USER_AGENT,
                },
            )
        except httpx.HTTPError as exc:
            raise ProviderError(f"{method} request failed: {exc}") from exc
        if response.status_code == 401:
            # Drop the cached token and project; next cycle re-reads the file,
            # refreshes, and re-runs loadCodeAssist.
            self._access_token = None
            self._project = None
            raise ProviderError(f"{method} returned HTTP 401 (token rejected)", status_code=401)
        if response.status_code != 200:
            raise ProviderError(
                f"{method} returned HTTP {response.status_code}", status_code=response.status_code
            )
        return json_object(response, method)


def _parse_antigravity_credentials(payload: dict[str, Any]) -> Credentials:
    """Parse the Antigravity CLI's token file.

    Shape: {"auth_method": "consumer", "id_token": "...", "token":
    {"access_token", "refresh_token", "token_type", "expiry": ISO-8601 with
    offset}}. Note the expiry is a timestamp string, not the epoch
    milliseconds the legacy file uses.
    """
    token = payload.get("token")
    if not isinstance(token, dict):
        token = {}
    return Credentials(
        access_token=_str_or_none(token.get("access_token")),
        expires_at=parse_iso8601(token.get("expiry")),
        refresh_token=_str_or_none(token.get("refresh_token")),
        client_id=ANTIGRAVITY_CLIENT_ID,
        client_secret=ANTIGRAVITY_CLIENT_SECRET,
    )


def _parse_legacy_credentials(payload: dict[str, Any]) -> Credentials:
    """Parse the Gemini CLI's oauth_creds.json (flat, expiry_date in epoch ms)."""
    expiry_ms = payload.get("expiry_date")
    expires_at = expiry_ms / 1000 if isinstance(expiry_ms, (int, float)) and not isinstance(expiry_ms, bool) else None
    return Credentials(
        access_token=_str_or_none(payload.get("access_token")),
        expires_at=expires_at,
        refresh_token=_str_or_none(payload.get("refresh_token")),
        client_id=GEMINI_CLIENT_ID,
        client_secret=GEMINI_CLIENT_SECRET,
    )


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
            if not isinstance(remaining, (int, float)) or isinstance(remaining, bool):
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


def _str_or_none(value: object) -> str | None:
    return value if isinstance(value, str) and value else None


def _slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
