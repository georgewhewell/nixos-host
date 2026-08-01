"""Prometheus collector translating poller state into metric families."""

from __future__ import annotations

from collections.abc import Iterable

from prometheus_client.core import GaugeMetricFamily
from prometheus_client.registry import Collector

from .poller import Poller


class QuotaCollector(Collector):
    def __init__(self, poller: Poller) -> None:
        self._poller = poller

    def collect(self) -> Iterable[GaugeMetricFamily]:
        utilization = GaugeMetricFamily(
            "llm_quota_utilization_ratio",
            "Fraction of the quota window consumed (1.0 = limit reached)",
            labels=["provider", "window", "scope"],
        )
        resets_at = GaugeMetricFamily(
            "llm_quota_reset_timestamp_seconds",
            "Unix time at which the quota window resets",
            labels=["provider", "window", "scope"],
        )
        info = GaugeMetricFamily(
            "llm_provider_info",
            "Static subscription details per provider",
            labels=["provider", "plan", "tier"],
        )
        success = GaugeMetricFamily(
            "llm_quota_scrape_success",
            "Whether the most recent poll of this provider succeeded",
            labels=["provider"],
        )
        last_success = GaugeMetricFamily(
            "llm_quota_last_success_timestamp_seconds",
            "Unix time of the last successful poll",
            labels=["provider"],
        )
        duration = GaugeMetricFamily(
            "llm_quota_poll_duration_seconds",
            "Duration of the most recent poll attempt",
            labels=["provider"],
        )

        with self._poller.lock:
            for state in self._poller.states:
                name = state.provider.name
                if state.last_attempt is not None:
                    success.add_metric([name], 0.0 if state.last_error else 1.0)
                if state.last_success is not None:
                    last_success.add_metric([name], state.last_success)
                if state.last_duration is not None:
                    duration.add_metric([name], state.last_duration)
                if state.snapshot is None:
                    continue
                snapshot = state.snapshot
                info.add_metric(
                    [name, snapshot.info.get("plan", ""), snapshot.info.get("tier", "")], 1.0
                )
                for sample in snapshot.samples:
                    labels = [name, sample.window, sample.scope]
                    utilization.add_metric(labels, sample.utilization)
                    if sample.resets_at is not None:
                        resets_at.add_metric(labels, sample.resets_at)

        return [utilization, resets_at, info, success, last_success, duration]
