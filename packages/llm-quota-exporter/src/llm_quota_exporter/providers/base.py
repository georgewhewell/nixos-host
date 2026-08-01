"""Provider abstraction: each provider turns local CLI credentials into quota samples."""

from __future__ import annotations

import abc
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import ClassVar

import httpx


class ProviderError(RuntimeError):
    """A provider failed to produce a snapshot this cycle."""


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
