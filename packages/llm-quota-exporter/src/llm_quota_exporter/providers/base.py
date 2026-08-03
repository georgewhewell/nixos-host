"""Provider abstraction: each provider turns local CLI credentials into quota samples."""

from __future__ import annotations

import abc
import os
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import ClassVar

import httpx


class ProviderError(RuntimeError):
    """A provider failed to produce a snapshot this cycle.

    ``status_code`` carries the upstream HTTP status when the failure came from
    a response, so callers can distinguish definitive errors (403/404) from
    transient ones (5xx, network) without string-matching the message.
    """

    def __init__(self, message: str, *, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


class CredentialsUnavailable(ProviderError):
    """No usable credentials found in the user's home directory."""


@dataclass(frozen=True, slots=True)
class QuotaSample:
    """One quota window observation, normalized across providers.

    utilization is a ratio in [0, 1] (1.0 = limit exhausted); resets_at is a
    unix timestamp in seconds, or None when the provider does not report one.
    used/limit are absolute values in provider-native units (credits,
    requests, ...) for the providers that report them.
    """

    window: str
    scope: str
    utilization: float
    resets_at: float | None = None
    used: float | None = None
    limit: float | None = None


@dataclass(frozen=True, slots=True)
class ProviderSnapshot:
    samples: tuple[QuotaSample, ...]
    info: Mapping[str, str] = field(default_factory=dict)
    # Extra-usage / pay-as-you-go spend in USD, where the provider reports it.
    spend_usd: float | None = None
    # Remaining prepaid credits in provider-native units.
    credits_balance: float | None = None


def json_object(response: httpx.Response, context: str) -> dict:
    """Decode an httpx response body as a JSON object, or raise a clear error.

    Guards against non-JSON bodies (JSONDecodeError) and JSON that isn't an
    object (a bare array/number would break the ``.get``/``.items`` that
    parsers rely on), turning both into a legible ProviderError rather than an
    ``AttributeError`` buried in the poller's catch-all.
    """
    try:
        payload = response.json()
    except ValueError as exc:
        raise ProviderError(f"{context}: response was not valid JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise ProviderError(f"{context}: expected a JSON object, got {type(payload).__name__}")
    return payload


def assert_writable(path: Path) -> None:
    """Prove a credential file is writable BEFORE consuming a refresh token.

    Providers with rotating refresh tokens must call this first: refreshing
    consumes the old token, so failing to persist afterwards (e.g. under a
    sandboxed service without a write path for the credential directory)
    strands the CLI on a consumed token and gets the token family revoked.
    """
    try:
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.wtest.")
        os.close(fd)
        os.unlink(tmp)
    except OSError as exc:
        raise ProviderError(f"credential dir not writable, refusing to refresh: {exc}") from exc


class Provider(abc.ABC):
    """Base class for one upstream subscription/quota source.

    Instances are long-lived: they may cache refreshed access tokens in memory
    between fetches, but must never write credentials back to disk (the owning
    CLI manages its own credential file, and racing it corrupts logins).
    """

    name: ClassVar[str]

    def __init__(self, home: Path, client: httpx.Client) -> None:
        self._home = home
        self._client = client

    @abc.abstractmethod
    def credential_path(self) -> Path:
        """Path of the credential file this provider reads."""

    def available(self) -> bool:
        """Whether credentials exist locally; unavailable providers are skipped quietly."""
        return self.credential_path().exists()

    @abc.abstractmethod
    def fetch(self) -> ProviderSnapshot:
        """Fetch current quota state from the upstream API.

        Raises ProviderError (or subclasses) on failure; the poller records the
        failure and keeps serving the previous snapshot.
        """
