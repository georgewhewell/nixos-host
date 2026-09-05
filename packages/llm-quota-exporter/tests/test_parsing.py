"""Parser tests using response fixtures shaped like the real provider APIs."""

import time

import pytest

from llm_quota_exporter._time import parse_iso8601
from llm_quota_exporter.providers.anthropic import _parse_spend
from llm_quota_exporter.providers.anthropic import _parse_usage as parse_anthropic
from llm_quota_exporter.providers.gemini import (
    Credentials,
    _parse_antigravity_credentials,
    _parse_legacy_credentials,
    _parse_plan,
    _parse_summary,
)
from llm_quota_exporter.providers.grok import _parse_monthly, _parse_weekly
from llm_quota_exporter.providers.kimi import _parse_usages
from llm_quota_exporter.providers.openai_codex import _parse_credits
from llm_quota_exporter.providers.openai_codex import _parse_usage as parse_codex
from llm_quota_exporter.providers.deepseek import _parse_balance as parse_ds_balance
from llm_quota_exporter.providers.openrouter import _parse_credits as parse_or_credits
from llm_quota_exporter.providers.openrouter import _parse_key as parse_or_key


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


class TestOpenRouter:
    def test_credits(self):
        (sample,) = parse_or_credits({"data": {"total_credits": 50, "total_usage": 32.761063713}})
        assert (sample.window, sample.scope) == ("credits", "all")
        assert sample.utilization == pytest.approx(0.65522, abs=1e-5)
        assert sample.used == pytest.approx(32.761063713)
        assert sample.limit == 50

    def test_credits_absent_or_unpurchased(self):
        assert parse_or_credits({}) == []
        assert parse_or_credits({"data": {"total_credits": 0, "total_usage": 0}}) == []

    def test_key_limit_is_scoped_to_its_reset_window(self):
        # `usage` is lifetime spend; charging it against a daily `limit` would
        # read 73% instead of the true 10%.
        payload = {
            "data": {
                "limit": 45,
                "limit_reset": "daily",
                "limit_remaining": 40.626385146,
                "usage": 32.687121783,
                "usage_daily": 4.373614854,
            }
        }
        (sample,) = parse_or_key(payload)
        assert sample.window == "daily"
        assert sample.used == pytest.approx(4.373614854)
        assert sample.utilization == pytest.approx(0.09719, abs=1e-5)

    def test_key_falls_back_to_period_usage(self):
        payload = {"data": {"limit": 20, "limit_reset": "weekly", "usage_weekly": 5, "usage": 99}}
        (sample,) = parse_or_key(payload)
        assert sample.window == "weekly"
        assert sample.utilization == pytest.approx(0.25)

    def test_key_lifetime_cap(self):
        (sample,) = parse_or_key({"data": {"limit": 100, "usage": 25}})
        assert sample.window == "key"
        assert sample.utilization == pytest.approx(0.25)

    def test_uncapped_key_emits_nothing(self):
        assert parse_or_key({"data": {"limit": None, "usage": 10}}) == []
        assert parse_or_key({}) == []


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
    # Verbatim body of a real POST /v1internal:retrieveUserQuotaSummary, sent
    # with the Antigravity CLI's User-Agent (without it the call 403s).
    SUMMARY = {
        "groups": [
            {
                "buckets": [
                    {
                        "bucketId": "gemini-weekly",
                        "displayName": "Weekly Limit Remaining",
                        "window": "weekly",
                        "resetTime": "2026-08-14T18:11:20Z",
                        "description": "You have used some of your weekly limit, "
                        "it will fully refresh in 5 days, 6 hours.",
                        "remainingFraction": 0.84875935,
                    },
                    {
                        "bucketId": "gemini-5h",
                        "displayName": "Five Hour Limit Remaining",
                        "window": "5h",
                        "resetTime": "2026-08-09T17:07:39Z",
                        "description": "You have used some of your 5-hour limit, "
                        "it will fully refresh in 4 hours, 58 minutes.",
                        "remainingFraction": 0.9978525,
                    },
                ],
                "displayName": "Gemini Models",
                "description": "Models within this group: Gemini Flash, Gemini Pro",
            },
            {
                "buckets": [
                    {
                        "bucketId": "3p-weekly",
                        "displayName": "Weekly Limit Remaining",
                        "window": "weekly",
                        "resetTime": "2026-08-16T12:10:35Z",
                        "remainingFraction": 1,
                    },
                    {
                        "bucketId": "3p-5h",
                        "displayName": "Five Hour Limit Remaining",
                        "window": "5h",
                        "resetTime": "2026-08-09T17:10:35Z",
                        "remainingFraction": 1,
                    },
                ],
                "displayName": "Claude and GPT models",
                "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
            },
        ],
        "description": "Within each group, models share a weekly limit and a 5-hour limit.",
    }

    def test_summary_groups(self):
        samples = by_key(_parse_summary(self.SUMMARY))
        assert len(samples) == 4
        assert samples[("seven_day", "gemini_models")].utilization == pytest.approx(0.15124065)
        assert samples[("seven_day", "gemini_models")].resets_at == pytest.approx(1786731080.0)
        assert samples[("five_hour", "gemini_models")].utilization == pytest.approx(0.0021475)
        # remainingFraction 1 is a bare int in the real body, not a float.
        assert samples[("seven_day", "claude_and_gpt_models")].utilization == pytest.approx(0.0)
        assert samples[("five_hour", "claude_and_gpt_models")].utilization == pytest.approx(0.0)
        # The endpoint reports fractions only; there are no absolute counters.
        assert all(s.used is None and s.limit is None for s in samples.values())

    def test_unknown_window_and_bad_values_skipped(self):
        summary = {
            "groups": [
                {
                    "displayName": "Gemini Models",
                    "buckets": [
                        {"window": "monthly", "remainingFraction": 0.5},
                        {"window": "5h", "remainingFraction": "not-a-number"},
                        {"window": "5h", "remainingFraction": True},
                        "not-a-dict",
                    ],
                },
                "not-a-dict",
            ]
        }
        samples = by_key(_parse_summary(summary))
        assert list(samples) == [("monthly", "gemini_models")]

    def test_empty(self):
        assert _parse_summary({}) == []
        assert _parse_summary({"groups": []}) == []


class TestGeminiCredentials:
    def test_antigravity_token_file(self):
        # Shape written by `agy`: nested token object, ISO-8601 expiry.
        creds = _parse_antigravity_credentials(
            {
                "auth_method": "consumer",
                "id_token": "eyJhbGc...",
                "token": {
                    "access_token": "ya29.a0-access",
                    "refresh_token": "1//0g-refresh",
                    "token_type": "Bearer",
                    "expiry": "2026-08-09T10:44:26.956653288+02:00",
                },
            }
        )
        assert creds.access_token == "ya29.a0-access"
        assert creds.refresh_token == "1//0g-refresh"
        assert creds.expires_at == pytest.approx(1786265066.956653)
        assert creds.client_id.startswith("1071006060591-")

    def test_legacy_oauth_creds_file(self):
        creds = _parse_legacy_credentials(
            {"access_token": "ya29.legacy", "refresh_token": "1//legacy", "expiry_date": 1786646666000}
        )
        assert creds.expires_at == pytest.approx(1786646666.0)
        assert creds.client_id.startswith("681255809395-")

    def test_missing_and_malformed_fields(self):
        empty = _parse_antigravity_credentials({})
        assert empty.access_token is None and empty.refresh_token is None and empty.expires_at is None
        assert _parse_antigravity_credentials({"token": "not-a-dict"}).access_token is None
        assert _parse_legacy_credentials({"expiry_date": "soon"}).expires_at is None
        # bool is an int subclass; it must not become an epoch.
        assert _parse_legacy_credentials({"expiry_date": True}).expires_at is None

    def test_usable_access_token_respects_expiry(self):
        fresh = Credentials("tok", time.time() + 3600, "r", "cid", "sec")
        assert fresh.usable_access_token() == "tok"
        # The on-disk token is routinely stale; that must force a refresh
        # rather than a doomed 401.
        stale = Credentials("tok", time.time() - 1, "r", "cid", "sec")
        assert stale.usable_access_token() is None
        assert Credentials("tok", None, "r", "cid", "sec").usable_access_token() is None
        assert Credentials(None, time.time() + 3600, "r", "cid", "sec").usable_access_token() is None


class TestGeminiPlan:
    def test_paid_tier_wins_over_current_tier(self):
        # The live account reads currentTier "free-tier" while holding a
        # Google AI Pro subscription; reporting currentTier called a paying
        # subscriber a free user.
        response = {
            "currentTier": {"id": "free-tier", "name": "Antigravity"},
            "paidTier": {"id": "g1-pro-tier", "name": "Google AI Pro"},
        }
        assert _parse_plan(response) == ("pro", "g1-pro-tier")

    def test_ultra(self):
        assert _parse_plan({"paidTier": {"id": "g1-ultra-tier", "name": "Google AI Ultra"}}) == (
            "ultra",
            "g1-ultra-tier",
        )

    def test_no_subscription_falls_back_to_current_tier(self):
        assert _parse_plan({"currentTier": {"id": "free-tier", "name": "Antigravity"}}) == (
            "free",
            "free-tier",
        )

    def test_absent(self):
        assert _parse_plan({}) == (None, None)


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


class TestDeepSeek:
    # Balances arrive as decimal *strings*, not numbers.
    def test_granted_allowance_and_serviceable(self):
        payload = {
            "is_available": True,
            "balance_infos": [
                {
                    "currency": "USD",
                    "total_balance": "3.50",
                    "granted_balance": "5.00",
                    "topped_up_balance": "0.00",
                }
            ],
        }
        granted, serviceable = parse_ds_balance(payload)
        assert (granted.window, granted.scope) == ("granted", "all")
        assert granted.utilization == pytest.approx(0.3)
        assert granted.used == pytest.approx(1.5)
        assert granted.limit == pytest.approx(5.0)
        assert (serviceable.window, serviceable.utilization) == ("serviceable", 0.0)

    def test_exhausted_account_saturates_serviceable(self):
        # The live symptom this exists to catch: every completion 402s.
        payload = {
            "is_available": False,
            "balance_infos": [
                {
                    "currency": "USD",
                    "total_balance": "0.00",
                    "granted_balance": "0.00",
                    "topped_up_balance": "0.00",
                }
            ],
        }
        (serviceable,) = parse_ds_balance(payload)
        assert (serviceable.window, serviceable.utilization) == ("serviceable", 1.0)

    def test_topped_up_balance_reports_no_granted_window(self):
        # No ceiling to divide by, so a ratio would be invented.
        payload = {
            "is_available": True,
            "balance_infos": [
                {
                    "currency": "USD",
                    "total_balance": "42.00",
                    "granted_balance": "0.00",
                    "topped_up_balance": "42.00",
                }
            ],
        }
        assert [s.window for s in parse_ds_balance(payload)] == ["serviceable"]

    def test_non_usd_account_falls_back_to_first_entry(self):
        payload = {
            "is_available": True,
            "balance_infos": [
                {"currency": "CNY", "total_balance": "8.00", "granted_balance": "10.00"}
            ],
        }
        granted, _ = parse_ds_balance(payload)
        assert granted.utilization == pytest.approx(0.2)

    def test_empty_and_malformed(self):
        assert parse_ds_balance({}) == []
        assert parse_ds_balance({"balance_infos": []}) == []
        assert parse_ds_balance({"balance_infos": "nope"}) == []
