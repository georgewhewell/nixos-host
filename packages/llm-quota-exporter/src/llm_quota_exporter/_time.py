"""Timestamp parsing helpers shared by providers."""

from __future__ import annotations

from datetime import UTC, datetime


def parse_iso8601(value: object) -> float | None:
    """Parse an ISO-8601 timestamp to unix seconds; None on absent/non-string/unparseable input."""
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.timestamp()
