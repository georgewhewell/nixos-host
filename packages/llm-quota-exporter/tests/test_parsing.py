"""Parser tests using response fixtures shaped like the real provider APIs."""

import pytest

from llm_quota_exporter._time import parse_iso8601
from llm_quota_exporter.providers.anthropic import _parse_spend
from llm_quota_exporter.providers.anthropic import _parse_usage as parse_anthropic
from llm_quota_exporter.providers.gemini import _parse_buckets, _parse_summary
from llm_quota_exporter.providers.grok import _parse_monthly, _parse_weekly
from llm_quota_exporter.providers.kimi import _parse_usages
from llm_quota_exporter.providers.openai_codex import _parse_credits
from llm_quota_exporter.providers.openai_codex import _parse_usage as parse_codex


def by_key(samples):
    return {(s.window, s.scope): s for s in samples}


class TestParseIso8601:
    def test_offset(self):
        assert parse_iso8601("2026-08-01T12:00:00+00:00") == pytest.approx(1785585600.0)

    def test_zulu(self):
        assert parse_iso8601("2026-08-01T12:00:00Z") == pytest.approx(1785585600.0)

    def test_absent_and_garbage(self):
        assert parse_iso8601(None) is None
        assert parse_iso8601("") is None
        assert parse_iso8601("soon") is None

    def test_non_string_input(self):
        # grok feeds raw JSON values; a numeric epoch must not raise.
        assert parse_iso8601(1785585600) is None
        assert parse_iso8601({"seconds": 1}) is None


class TestAnthropic:
    def test_windows_and_scoped_limits(self):
        usage = {
            "five_hour": {"utilization": 32.5, "resets_at": "2026-08-01T15:00:00Z"},
            "seven_day": {"utilization": 61.0, "resets_at": "2026-08-04T00:00:00Z"},
            "seven_day_opus": {"utilization": 80.0, "resets_at": "2026-08-04T00:00:00Z"},
            "extra_usage": {"enabled": False},
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "percent": 12.0,
                    "resets_at": "2026-08-04T00:00:00Z",
                    "scope": {"model": {"display_name": "Sonnet 4.5"}},
                },
                {"kind": "something_else", "percent": 99.0},
            ],
        }
        samples = by_key(parse_anthropic(usage))
        assert samples[("five_hour", "all")].utilization == pytest.approx(0.325)
        assert samples[("five_hour", "all")].resets_at == pytest.approx(1785596400.0)
        assert samples[("seven_day", "all")].utilization == pytest.approx(0.61)
        assert samples[("seven_day", "opus")].utilization == pytest.approx(0.80)
        assert samples[("seven_day", "sonnet_4_5")].utilization == pytest.approx(0.12)
        assert len(samples) == 4

    def test_scoped_limit_does_not_duplicate_expanded_key(self):
        usage = {
            "seven_day_opus": {"utilization": 80.0, "resets_at": None},
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "percent": 75.0,
                    "scope": {"model": {"display_name": "Opus"}},
                }
            ],
        }
        samples = by_key(parse_anthropic(usage))
        assert len(samples) == 1
        assert samples[("seven_day", "opus")].utilization == pytest.approx(0.80)

    def test_empty_response(self):
        assert parse_anthropic({}) == []

    def test_scopeless_weekly_limit_skipped(self):
        # limits[] entries without model scope duplicate the seven_day_* keys.
        usage = {
            "seven_day": {"utilization": 59.0, "resets_at": None},
            "limits": [
                {"kind": "weekly_scoped", "percent": 77, "scope": None},
                {"kind": "session", "group": "session", "percent": 30},
            ],
        }
        samples = by_key(parse_anthropic(usage))
        assert list(samples) == [("seven_day", "all")]

    def test_extra_usage_utilization(self):
        usage = {"extra_usage": {"is_enabled": True, "utilization": 40.0}}
        (sample,) = parse_anthropic(usage)
        assert (sample.window, sample.utilization) == ("extra_usage", pytest.approx(0.40))

    def test_spend(self):
        assert _parse_spend({"spend": {"used": {"amount_minor": 1234, "exponent": 2}}}) == pytest.approx(12.34)
        assert _parse_spend({"spend": {"used": None}}) is None
        assert _parse_spend({}) is None


class TestCodex:
    def test_primary_and_secondary_windows(self):
        payload = {
            "plan_type": "plus",
            "rate_limit": {
                "allowed": True,
                "limit_reached": False,
                "primary_window": {
                    "used_percent": 45,
                    "limit_window_seconds": 18000,
                    "reset_after_seconds": 3600,
                    "reset_at": 1785596400,
                },
                "secondary_window": {
                    "used_percent": 12,
                    "limit_window_seconds": 604800,
                    "reset_after_seconds": 500000,
                    "reset_at": 1786000000,
                },
            },
        }
        samples = by_key(parse_codex(payload))
        assert samples[("five_hour", "all")].utilization == pytest.approx(0.45)
        assert samples[("five_hour", "all")].resets_at == 1785596400
        assert samples[("seven_day", "all")].utilization == pytest.approx(0.12)

    def test_null_windows(self):
        assert parse_codex({"rate_limit": {"primary_window": None, "secondary_window": None}}) == []
        assert parse_codex({"rate_limit": None}) == []
        assert parse_codex({}) == []

    def test_unusual_window_length_is_named_by_duration(self):
        payload = {
            "rate_limit": {
                "primary_window": {"used_percent": 10, "limit_window_seconds": 3600, "reset_at": 0}
            }
        }
        (sample,) = parse_codex(payload)
        assert sample.window == "1h"

    def test_code_review_and_additional_limits(self):
        payload = {
            "code_review_rate_limit": {
                "primary_window": {"used_percent": 5, "limit_window_seconds": 604800, "reset_at": 1}
            },
            "additional_rate_limits": [
                {
                    "limit_name": "GPT-5.3-Codex-Spark",
                    "rate_limit": {
                        "primary_window": {"used_percent": 0, "limit_window_seconds": 604800, "reset_at": 2},
                        "secondary_window": None,
                    },
                }
            ],
        }
        samples = by_key(parse_codex(payload))
        assert samples[("seven_day", "code_review")].utilization == pytest.approx(0.05)
        assert samples[("seven_day", "gpt_5_3_codex_spark")].utilization == 0.0

    def test_credits(self):
        assert _parse_credits({"credits": {"balance": "12.5"}}) == pytest.approx(12.5)
        assert _parse_credits({"credits": {"balance": None}}) is None
        assert _parse_credits({}) is None


class TestGrok:
    def test_monthly_with_val_wrapping(self):
        payload = {
            "config": {
                "monthlyLimit": {"val": 200},
                "used": {"val": 50},
                "billingPeriodEnd": "2026-08-04T00:00:00Z",
            }
        }
        (sample,) = _parse_monthly(payload)
        assert sample.window == "monthly"
        assert sample.utilization == pytest.approx(0.25)
        assert sample.resets_at == pytest.approx(1785801600.0)

    def test_monthly_bare_numbers(self):
        (sample,) = _parse_monthly({"config": {"monthlyLimit": 100, "used": 10}})
        assert sample.utilization == pytest.approx(0.10)

    def test_weekly_credits(self):
        payload = {
            "config": {
                "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY"},
                "creditUsagePercent": 37.5,
                "billingPeriodEnd": "2026-08-04T00:00:00Z",
            }
        }
        (sample,) = _parse_weekly(payload)
        assert sample.window == "seven_day"
        assert sample.utilization == pytest.approx(0.375)

    def test_weekly_zero_percent_omitted(self):
        # creditUsagePercent is omitted entirely at 0% usage.
        (sample,) = _parse_weekly({"config": {"currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY"}}})
        assert sample.utilization == 0.0

    def test_empty(self):
        assert _parse_monthly({}) == []
        assert _parse_weekly({}) == []


class TestKimi:
    def test_full_response(self):
        payload = {
            "usage": {"limit": 1000, "used": 400, "resetTime": "2026-08-04T00:00:00Z"},
            "limits": [
                {
                    "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
                    "detail": {"limit": 100, "used": 25, "resetTime": "2026-08-01T15:00:00Z"},
                }
            ],
            "totalQuota": {"limit": 5000, "used": 1250, "resetTime": None},
        }
        samples = by_key(_parse_usages(payload))
        assert samples[("seven_day", "all")].utilization == pytest.approx(0.40)
        assert samples[("five_hour", "all")].utilization == pytest.approx(0.25)
        assert samples[("five_hour", "all")].resets_at == pytest.approx(1785596400.0)
        assert samples[("monthly", "all")].utilization == pytest.approx(0.25)

    def test_remaining_variant(self):
        payload = {"usage": {"limit": 100, "remaining": 30}}
        (sample,) = _parse_usages(payload)
        assert sample.utilization == pytest.approx(0.70)

    def test_protobuf_string_numbers(self):
        # Real deployments encode int64 as JSON strings and use remaining, not used.
        payload = {
            "usage": {"limit": "100", "used": "100", "resetTime": "2026-08-03T00:11:46.320599Z"},
            "limits": [
                {
                    "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
                    "detail": {"limit": "100", "remaining": "100", "resetTime": "2026-08-01T17:11:46.320599Z"},
                }
            ],
            "totalQuota": {},
        }
        samples = by_key(_parse_usages(payload))
        assert samples[("seven_day", "all")].utilization == pytest.approx(1.0)
        assert samples[("five_hour", "all")].utilization == pytest.approx(0.0)
        assert len(samples) == 2

    def test_zero_limit_ignored(self):
        assert _parse_usages({"usage": {"limit": 0, "used": 0}}) == []
        assert _parse_usages({}) == []


class TestGemini:
    def test_summary_groups(self):
        summary = {
            "groups": [
                {
                    "displayName": "Gemini 3 Pro",
                    "buckets": [
                        {
                            "bucketId": "gemini-pro-5h",
                            "window": "5h",
                            "remainingFraction": 0.75,
                            "resetTime": "2026-08-01T15:00:00Z",
                        },
                        {
                            "bucketId": "gemini-pro-weekly",
                            "window": "weekly",
                            "remainingFraction": 0.9,
                            "resetTime": "2026-08-04T00:00:00Z",
                        },
                    ],
                }
            ]
        }
        samples = by_key(_parse_summary(summary))
        assert samples[("five_hour", "gemini_3_pro")].utilization == pytest.approx(0.25)
        assert samples[("seven_day", "gemini_3_pro")].utilization == pytest.approx(0.10)

    def test_plain_buckets_fallback(self):
        quota = [
            {"modelId": "gemini-3-flash", "remainingFraction": 0.5, "resetTime": None},
            {"tokenType": "TOKENS", "remainingFraction": 1.0},
            {"remainingFraction": "not-a-number"},
        ]
        samples = by_key(_parse_buckets(quota))
        assert samples[("bucket", "gemini_3_flash")].utilization == pytest.approx(0.5)
        assert samples[("bucket", "tokens")].utilization == pytest.approx(0.0)
        assert len(samples) == 2

    def test_empty(self):
        assert _parse_summary({}) == []
        assert _parse_buckets([]) == []


class TestJsonObject:
    """The json_object helper turns bad response bodies into clean errors."""

    def _resp(self, body, *, raises=False):
        class _R:
            def json(self_inner):
                if raises:
                    raise ValueError("not json")
                return body

        return _R()

    def test_non_object_rejected(self):
        from llm_quota_exporter.providers.base import ProviderError, json_object

        with pytest.raises(ProviderError):
            json_object(self._resp([1, 2, 3]), "ctx")
        with pytest.raises(ProviderError):
            json_object(self._resp(42), "ctx")

    def test_invalid_json_rejected(self):
        from llm_quota_exporter.providers.base import ProviderError, json_object

        with pytest.raises(ProviderError):
            json_object(self._resp(None, raises=True), "ctx")

    def test_object_passes(self):
        from llm_quota_exporter.providers.base import json_object

        assert json_object(self._resp({"a": 1}), "ctx") == {"a": 1}


class TestCollectorDedup:
    """Colliding (window, scope) tuples must not produce duplicate series."""

    def test_duplicate_samples_deduped(self):
        from llm_quota_exporter.metrics import QuotaCollector
        from llm_quota_exporter.poller import Poller, ProviderState
        from llm_quota_exporter.providers.base import ProviderSnapshot, QuotaSample

        class _FakeProvider:
            name = "fake"

        snap = ProviderSnapshot(samples=(
            QuotaSample(window="seven_day", scope="all", utilization=0.5),
            QuotaSample(window="seven_day", scope="all", utilization=0.9),  # collision
            QuotaSample(window="five_hour", scope="all", utilization=0.1),
        ))
        state = ProviderState(provider=_FakeProvider(), snapshot=snap, last_attempt=1.0, last_success=1.0)
        poller = Poller(states=[state], interval=300)

        families = {f.name: f for f in QuotaCollector(poller).collect()}
        util = families["llm_quota_utilization_ratio"]
        keys = [(s.labels["window"], s.labels["scope"]) for s in util.samples]
        assert keys.count(("seven_day", "all")) == 1
        assert ("five_hour", "all") in keys
        # first value wins
        first = next(s for s in util.samples if s.labels["window"] == "seven_day")
        assert first.value == pytest.approx(0.5)
