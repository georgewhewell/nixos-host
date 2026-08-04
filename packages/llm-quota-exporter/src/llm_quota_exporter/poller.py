"""Background polling loop, decoupled from Prometheus scrapes.

Upstream quota endpoints are polled at a fixed interval (5-minute default,
matching the etiquette of the official clients); scrapes always serve the most
recent snapshot so scrape frequency never translates into API traffic.
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass, field

from .providers.base import CredentialsUnavailable, Provider, ProviderSnapshot

log = logging.getLogger(__name__)


@dataclass
class ProviderState:
    provider: Provider
    snapshot: ProviderSnapshot | None = None
    last_attempt: float | None = None
    last_success: float | None = None
    last_duration: float | None = None
    last_error: str | None = None
    consecutive_failures: int = 0


@dataclass
class Poller:
    states: list[ProviderState]
    interval: float
    lock: threading.Lock = field(default_factory=threading.Lock)
    _stop: threading.Event = field(default_factory=threading.Event)

    def poll_once(self) -> None:
        for state in self.states:
            # Bail promptly on shutdown: a full cycle can otherwise run several
            # providers x the HTTP timeout, overrunning systemd's stop timeout.
            if self._stop.is_set():
                return
            if self._in_backoff(state):
                continue
            self._poll_provider(state)

    def _in_backoff(self, state: ProviderState) -> bool:
        """Exponential backoff after consecutive failures (max 8x interval)."""
        if state.consecutive_failures == 0 or state.last_attempt is None:
            return False
        wait = self.interval * min(2 ** (state.consecutive_failures - 1), 8)
        return time.time() - state.last_attempt < wait

    def run_forever(self) -> None:
        while not self._stop.is_set():
            started = time.monotonic()
            self.poll_once()
            elapsed = time.monotonic() - started
            self._stop.wait(max(1.0, self.interval - elapsed))

    def stop(self) -> None:
        self._stop.set()

    def _poll_provider(self, state: ProviderState) -> None:
        provider = state.provider
        if not provider.available():
            with self.lock:
                state.last_error = f"credentials not found at {provider.credential_path()}"
            log.debug("%s: skipped, %s", provider.name, state.last_error)
            return

        started = time.time()
        try:
            snapshot = provider.fetch()
        except CredentialsUnavailable as exc:
            # An expected, self-healing gap (e.g. an expired token waiting for
            # the CLI to refresh it): record it, but don't treat it as a
            # failure — escalating backoff here would delay recovery long after
            # the credential became usable again.
            with self.lock:
                state.last_attempt = started
                state.last_duration = time.time() - started
                state.last_error = str(exc)
                state.consecutive_failures = 0
            log.info("%s: credentials not currently usable: %s", provider.name, exc)
        except Exception as exc:  # noqa: BLE001 - one provider must never kill the loop
            with self.lock:
                state.last_attempt = started
                state.last_duration = time.time() - started
                state.last_error = str(exc)
                state.consecutive_failures += 1
            log.warning("%s: poll failed: %s", provider.name, exc)
        else:
            with self.lock:
                state.last_attempt = started
                state.last_duration = time.time() - started
                state.snapshot = snapshot
                state.last_success = time.time()
                state.last_error = None
                state.consecutive_failures = 0
            log.info("%s: %d quota samples", provider.name, len(snapshot.samples))
