# llm-quota-exporter

Prometheus exporter for LLM *subscription* usage and quota windows. It reads
the credential files that the vendor CLIs already maintain in your home
directory, polls each vendor's own usage endpoint, and serves the results as
normalized gauges.

| Provider  | Credentials read              | Upstream endpoint |
|-----------|-------------------------------|-------------------|
| anthropic | `~/.claude/.credentials.json` | `GET api.anthropic.com/api/oauth/usage` |
| openai    | `~/.codex/auth.json`          | `GET chatgpt.com/backend-api/wham/usage` |
| gemini    | `~/.gemini/oauth_creds.json`  | `POST cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary` |
| grok      | `~/.grok/auth.json`           | see module docstring |
| kimi      | `~/.kimi/`                    | see module docstring |

Providers whose credential files are absent are skipped quietly; providers
that fail keep serving their last snapshot with `llm_quota_scrape_success` 0.

## Metrics

- `llm_quota_utilization_ratio{provider,window,scope}` — 0..1, 1.0 = limit hit.
  `window` is normalized where the vendor reports a length (`five_hour`,
  `seven_day`); `scope` is `all` or a model slug (`opus`, `gemini_3_pro`, ...).
- `llm_quota_reset_timestamp_seconds{provider,window,scope}` — unix reset time.
- `llm_provider_info{provider,plan,tier}` — subscription details, value 1.
- `llm_quota_scrape_success{provider}`, `llm_quota_last_success_timestamp_seconds{provider}`,
  `llm_quota_poll_duration_seconds{provider}` — poll health.

## Usage

```console
$ llm-quota-exporter --once            # poll once, dump metrics to stdout
$ llm-quota-exporter --port 9184       # serve /metrics, polling every 5 min
$ llm-quota-exporter --providers anthropic,openai
```

Polling is decoupled from scraping: upstream APIs are hit once per
`--interval` (default 300 s) regardless of scrape frequency.

## Credential handling

Refresh policy is per provider, driven by each vendor's token semantics:

- **Anthropic, OpenAI** — never refreshed, strictly read-only. Both rotate
  refresh tokens with reuse detection, and their CLIs hold tokens in memory
  across long-lived sessions, so any rotation from outside the CLI revokes
  the session (observed with Anthropic as forced re-logins). An expired
  on-disk token is a data gap until the CLI next runs, not an error to fix.
- **Grok, Kimi** — rotating refresh tokens, but short access tokens (6 h /
  15 min) make read-only impractical: refresh happens only once the on-disk
  token has already expired (no running CLI is managing the file), after
  proving the credential file is writable (consuming a token and then
  failing to persist its replacement is the catastrophic case), and the
  rotated pair is persisted atomically in the CLI's own format.
- **Gemini** — non-rotating refresh token, public installed-app client id:
  refreshed in memory only; the credential file is never rewritten.

Failed providers back off exponentially (up to 8x the poll interval).

## Development

```console
$ python -m pytest
$ python -m llm_quota_exporter.cli --once --log-level debug
```
