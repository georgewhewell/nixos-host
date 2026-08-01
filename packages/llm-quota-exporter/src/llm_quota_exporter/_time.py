"""Timestamp parsing helpers shared by providers."""

from __future__ import annotations

from datetime import datetime, timezone


def parse_iso8601(value: str | None) -> float | None:
    """Parse an ISO-8601 timestamp to unix seconds; None on absent/unparseable input."""
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.timestamp()
