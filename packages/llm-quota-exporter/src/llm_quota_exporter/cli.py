"""Command-line entry point for the exporter."""

from __future__ import annotations

import argparse
import logging
import signal
import sys
from pathlib import Path

import httpx
from prometheus_client import CollectorRegistry, generate_latest, start_http_server

from . import __version__
from .metrics import QuotaCollector
from .poller import Poller, ProviderState
from .providers import PROVIDERS

log = logging.getLogger(__name__)

DEFAULT_PORT = 9184
DEFAULT_INTERVAL = 300.0
USER_AGENT = f"llm-quota-exporter/{__version__}"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="llm-quota-exporter",
        description="Prometheus exporter for LLM subscription usage and quota windows",
    )
    parser.add_argument("--listen-address", default="0.0.0.0", help="address to bind (default: %(default)s)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="port to bind (default: %(default)s)")
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help="seconds between upstream polls (default: %(default)s)",
    )
    parser.add_argument(
        "--home",
        type=Path,
        default=Path.home(),
        help="home directory containing CLI credential files (default: %(default)s)",
    )
    parser.add_argument(
        "--providers",
        default="all",
        help=f"comma-separated subset of providers (default: all of {','.join(sorted(PROVIDERS))})",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="poll every provider once, print metrics to stdout and exit",
    )
    parser.add_argument("--log-level", default="info", choices=["debug", "info", "warning", "error"])
    parser.add_argument("--version", action="version", version=USER_AGENT)
    return parser


def select_providers(spec: str) -> list[str]:
    if spec.strip().lower() == "all":
        return sorted(PROVIDERS)
    names = [name.strip().lower() for name in spec.split(",") if name.strip()]
    unknown = sorted(set(names) - set(PROVIDERS))
    if unknown:
        raise SystemExit(f"unknown providers: {', '.join(unknown)} (available: {', '.join(sorted(PROVIDERS))})")
    return list(dict.fromkeys(names))  # de-dupe, preserve order


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=args.log_level.upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    with httpx.Client(
        timeout=httpx.Timeout(30.0),
        headers={"User-Agent": USER_AGENT},
        follow_redirects=True,
    ) as client:
        states = [
            ProviderState(provider=PROVIDERS[name](home=args.home, client=client))
            for name in select_providers(args.providers)
        ]
        poller = Poller(states=states, interval=args.interval)

        registry = CollectorRegistry()
        registry.register(QuotaCollector(poller))

        if args.once:
            poller.poll_once()
            sys.stdout.write(generate_latest(registry).decode())
            return 0 if any(state.snapshot for state in states) else 1

        start_http_server(args.port, addr=args.listen_address, registry=registry)
        log.info(
            "listening on %s:%d, polling %s every %.0fs",
            args.listen_address,
            args.port,
            ", ".join(state.provider.name for state in states),
            args.interval,
        )
        signal.signal(signal.SIGTERM, lambda *_: poller.stop())
        signal.signal(signal.SIGINT, lambda *_: poller.stop())
        poller.run_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
