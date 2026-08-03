# llm-quota-exporter

A Prometheus exporter for the **subscription usage and rate-limit windows** of
the major LLM CLIs. It reads the credential files the vendor CLIs already keep
in your home directory, polls each vendor's own usage endpoint, and serves the
results as normalized gauges — so you can see, in Grafana, how close you are to
your Claude / Codex / Gemini / Grok / Kimi limits before you hit them.

There is no official metrics endpoint for consumer LLM subscriptions; this
talks to the same private endpoints the CLIs use for their own usage displays.

![dashboard](dashboards/screenshot.png)

## Providers

| Provider  | Credentials read              | Endpoint |
|-----------|-------------------------------|----------|
| anthropic | `~/.claude/.credentials.json` | `GET api.anthropic.com/api/oauth/usage` |
| openai    | `~/.codex/auth.json`          | `GET chatgpt.com/backend-api/wham/usage` |
| gemini    | `~/.gemini/oauth_creds.json`  | `POST cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` |
| grok      | `~/.grok/auth.json`           | `GET cli-chat-proxy.grok.com/v1/billing` |
| kimi      | `~/.kimi-code/credentials/…`  | `GET api.kimi.com/coding/v1/usages` |

Providers whose credential files are absent are skipped quietly. A provider
that fails keeps serving its last snapshot with `llm_quota_scrape_success` 0
and backs off exponentially.

> These are undocumented, reverse-engineered endpoints. They can change or
> break at any time. This project is not affiliated with any provider.

## Install

### pip / uv

```console
$ pip install llm-quota-exporter        # or: uv tool install llm-quota-exporter
$ llm-quota-exporter --port 9184
```

### Nix

```console
$ nix run github:georgewhewell/quota-exporter -- --once
```

Flake outputs: `packages.default`, `overlays.default`, and
`nixosModules.default` (options under `services.llm-quota-exporter`).

```nix
{
  inputs.llm-quota-exporter.url = "github:georgewhewell/quota-exporter";

  # in your NixOS configuration:
  imports = [ inputs.llm-quota-exporter.nixosModules.default ];
  services.llm-quota-exporter = {
    enable = true;
    user = "alice";          # whose ~ holds the CLI credentials
    openFirewall = true;
  };
}
```

## Usage

```console
$ llm-quota-exporter --once                    # poll once, print metrics, exit
$ llm-quota-exporter --port 9184               # serve /metrics, poll every 5 min
$ llm-quota-exporter --providers anthropic,openai
$ llm-quota-exporter --home /home/alice        # credentials of another user
```

Polling is decoupled from scraping: upstream APIs are hit once per
`--interval` (default 300 s) regardless of how often Prometheus scrapes.

## Metrics

| Metric | Labels | Meaning |
|--------|--------|---------|
| `llm_quota_utilization_ratio` | provider, window, scope | 0–1, 1.0 = limit reached |
| `llm_quota_reset_timestamp_seconds` | provider, window, scope | unix reset time |
| `llm_quota_used` / `llm_quota_limit` | provider, window, scope | absolute native units, where reported |
| `llm_spend_usd` | provider | overage / extra-usage spend, where reported |
| `llm_credits_balance` | provider | remaining prepaid credits, where reported |
| `llm_provider_info` | provider, plan, tier | 1; subscription details |
| `llm_quota_scrape_success` | provider | 1 if the last poll succeeded |
| `llm_quota_last_success_timestamp_seconds` | provider | unix time of last success |
| `llm_quota_poll_duration_seconds` | provider | last poll duration |

`window` is normalized where the vendor reports a length (`five_hour`,
`seven_day`, `monthly`); `scope` is `all` or a model slug (`opus`,
`gemini_3_pro`, …).

## Credential handling

Tokens are only ever read; the exporter never logs or transmits them.
Refresh policy is per provider, driven by each vendor's token semantics:

- **anthropic, openai** — never refreshed, strictly read-only. Both rotate
  refresh tokens with reuse detection and hold tokens in memory across
  long-lived sessions, so any refresh from outside the CLI can revoke the
  session. An expired token is a data gap until the CLI next runs.
- **grok, kimi** — short access tokens (6 h / 15 min) that make read-only
  impractical: refreshed only once the on-disk token has expired (no running
  CLI is managing the file), after proving the credential file is writable,
  then persisted atomically in the CLI's own format.
- **gemini** — non-rotating refresh token; refreshed in memory only, the
  file is never rewritten.

## Grafana

A ready-made dashboard lives in [`dashboards/`](dashboards/). Import
`llm-quota.json` and select your data source.

## Optional: per-model token usage

The dashboard's "Tokens by model" / "Cost & sessions" panels are populated
not by this exporter but by the CLIs' own **OpenTelemetry** metrics. If you
want them, point the CLIs at an OTLP collector that writes into the same
Prometheus/VictoriaMetrics store — the exporter and the OTel metrics then sit
side by side. In brief:

- **Claude Code** — `CLAUDE_CODE_ENABLE_TELEMETRY=1`,
  `OTEL_METRICS_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_ENDPOINT=…`,
  `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative`
  (delta is dropped by Prometheus remote-write). Emits `claude_code.token.usage`.
- **Grok CLI** — `GROK_EXTERNAL_OTEL=1` + the standard `OTEL_*` vars. Emits
  `grok_code.token.usage`.
- **Gemini CLI** — `telemetry` block in `~/.gemini/settings.json`
  (`target: "local"`, `otlpEndpoint`). Emits `gemini_cli.token.usage`.
- **Codex** — `[otel]` block in `~/.codex/config.toml`.

All metric names carry a `model` label. If you don't set this up, those
panels simply show no data; the quota panels work regardless.

## Development

```console
$ uv run pytest          # or: nix flake check
$ ruff check .
```

## License

MIT
