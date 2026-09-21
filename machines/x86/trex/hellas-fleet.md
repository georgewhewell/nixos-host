# Hellas paid inference fleet

Trex runs `hellas-gateway.service` on `192.168.23.8:8080`. While the Strix
fleet is unavailable it executes `SmolLM2-135M-Instruct` locally on Trex's
Radeon RX 5600 XT. Its stable private bearer credential is
`/var/lib/hellas-gateway/bearer-token`; systemd supplies an owner-only copy for
grw at `/run/hellas-gateway/client-token`.

Run normal `opencode` in the directory where you want to work. Home Manager
configures its default model as `hellas/SmolLM2-135M-Instruct` and reads the
credential from that runtime file. It streams normal chat replies. This small
fallback does not advertise tools; switch back to the Qwen model when the paid
Strix providers return.

Chat templates and incremental tool parsing belong to the shared
`hellas-presentation` model adapter. The local gateway supplies the explicit
SmolLM2 template and invokes Catena directly; the paid provider pool is not
configured while its hosts have no network link.

`../hellas-model.nix` defines the fleet's Qwen model, 32K context, 4096-token
output ceiling, stop tokens and execution identities. Services merge this
public execution policy into private runtime configs under `/run`; persisted
funding configuration and payment journals remain intact. Each completed job
costs one devnet unit. Exhausted channels are not automatically replenished.
Failed executions earn no payment; expired unpaid jobs remain as evidence.
Recovery retains permanently refused jobs without blocking fresh requests.
Authenticated delivery retries report a retained job's terminal outcome.
Terminal replies remain available immediately after a provider restart, before
new-work readiness is established. Collecting a retained live result refreshes
readiness from the chain, without accepting another job or rerunning the model.
Acceptance retries also authenticate against the stored channel before waiting
for admission: a retained co-signature is returned exactly, including after a
lost acknowledgement. Otherwise, a retained terminal or an acceptance deadline
already passed by the persisted chain cursor is answered immediately. Fresh
proposals still require current chain readiness before signing.
The September 20 rollout of Hellas `a053fc95` exercised an existing expired
Strix-4 proposal after restart: one `AcceptWork` call returned `Expired` in
0.58 ms round trip (0.34 ms inside the provider). The previous implementation
had repeatedly spent about four seconds waiting for readiness on this same
proposal. Its retained journal was preserved throughout recovery.

Strix-1, Strix-2 and Strix-4 retain their Hellas identities and payment state
on the NFS exports, but are not in the active gateway pool. Strix-3 is bricked.
DeepSeek serving is disabled by default; enabling it requires an explicit
`strix.ds4Serve = true` in the host inventory.

## State and models

`/mnt/Home/hellas/gateway` on trex is bound to `/var/lib/hellas-gateway`.
Each provider mounts its own address-restricted NFS export at `/var/lib/hellas`,
backed by `/mnt/Home/hellas/strix-N` on trex. These exports preserve the fixed
service UIDs 4951–4954; the general Home export squashes clients to UID 1000
and cannot carry the private provider state.

The directories hold identities, work policies, content indexes and signed
payment journals. Keep them together across restarts. Recreating an identity
or deleting a journal is not a way to retry a failed request. The operating
system, Nix store and compiler scratch keep their existing fresh-boot SPDK
layout; Hellas compiler scratch uses `/tmp/hellas`.

Netboot images contain the kernel, initrd and the selected system's closure
manifest; there is no separate store archive. At boot, the initrd mounts
trex's `/nix-store` export read-only and copies the manifest's paths, eight
at a time, into that host's freshly formatted private SPDK volume. Stage 2
registers exactly those paths before starting the Nix daemon. The deployed
trex generation retains the complete source closure for garbage collection.
The rest of trex's store is neither copied nor registered on the Strix.
On September 20, all three active hosts booted this layout with new private XFS
UUIDs, tmpfs roots, and registered closures matching their manifests exactly:

| Host | Registered paths | Initrd copy | Registration |
| --- | ---: | ---: | ---: |
| Strix-1 | 2,327 | 192 seconds | 0.13 seconds |
| Strix-2 | 2,386 | 225 seconds | 0.13 seconds |
| Strix-4 | 2,364 | 168 seconds | 0.13 seconds |

SSH returned in about four minutes on Strix-4 and five minutes on Strix-1/2,
including firmware boot. Before rollout, an isolated copy of Strix-4's closure
also registered exactly and matched sampled NAR hashes; that copy was removed.

The verified model shards, tokenizer, program and environment live under
`/mnt/Home/models/hellas/qwen3.6-35b-a3b`. The allowed environment manifest is
`b50578da2a2aae47d5a8c9699a059b9f0dc0e9fb91fcdb9093ee1aa74d363a6f`.
The first launch indexes the 69.4 GB model; later launches reuse the content
index while the files remain unchanged.
The current index also keys on the client's filesystem device number. A new
NFS mount after reboot can change that number even when the model's inode,
size and timestamps are identical. Strix-4's first new boot therefore spent
274 seconds rehashing weights before opening its RPC endpoint. Systemd's
process-active state precedes this endpoint becoming available.
The descriptor is also an explicit `content` entry. Gateway startup repairs
its public read permissions only when needed: even a redundant `chmod` changes
ctime and invalidates running providers' content indexes. After replacing or
changing permissions on model artifacts, restart the providers to index them.
The graph uses native BF16 activations and cache storage with WMMA prefill.
Only final logits widen to F32 for the host interface. The model generator is
`hellas-ai/catena-qwen3.6`, branch `codex/hellas-model-export`; the compiler is
the private personal fork `georgewhewell/exploratory-catena`, branch
`codex/hellas-exploratory`. Both model and compiler source repositories are
private; authenticate source acquisition separately from sandboxed builds.

A direct Strix-4 measurement on 2026-09-20 loaded the BF16 weights over NFS
in 289 seconds, processed 512 prompt tokens at 120 tokens/s, and decoded at
21.8 tokens/s. A warm short chat prompt reached its first token in 0.48 seconds.
These are model-library timings; gateway and payment timing are separate.
Cold model loading can take minutes. The environment commits
capacity 32768 and prefill chunks of 512 tokens; the provider retains one exact
prefix checkpoint per model worker. Follow-up requests prefer an idle provider
with the longest matching prompt prefix. The checkpoint holds independent GPU
state, so a changed prefix is evaluated cold. The 64 GiB generation budget
includes the checkpoint; the separate 80 GiB asset limit covers weights.

The September 20 paid interactive check used normal OpenCode, called `bash`
to run `df`, returned a 105-token explanation, and answered a second user turn.
Its 8,320-token tool-result prompt reused 8,192 tokens: GPU first-token latency
was 2.9 seconds and the HTTP turn completed in 12.1 seconds. The initial
8,203-token agent prompt was uncached and took 91.5 seconds to its first GPU
token. Short paid requests also streamed 47 and 59 tokens with acknowledged
payments on Strix-1 and Strix-4. Initial model loading still varies with NFS
cache state; these requests reached their first content in 280 and 58 seconds.
Strix-2 also streamed 55 tokens and reached matching certified payment records
on both sides after recovering from the earlier failed job. Its cold model
load took about five minutes; the preceding wait behind the old recovery loop
is not representative of normal request latency.
After the final gateway deployment, repeated short prompts created fresh jobs
on all three providers. Strix-1 and Strix-2 completed in 5.8 and 5.0 seconds;
Strix-4 completed in 171 seconds including its cold model load.
Following the real netboots and the subsequent `a053fc95` service update,
three concurrent requests again completed normally, streaming 42–52 tokens.
All three had identical certified payment evidence in the gateway and provider
journals (cumulative credits 9, 7 and 19 on Strix-1, Strix-2 and Strix-4).
Those fresh model workers took 180–267 seconds per HTTP request, including
cold loading; these are not warm inference timings. Strix-4's corresponding
[paid request trace](https://jaeger.lsd-ag.ch/trace/8741b1f0dc0e485ea25484daa01c7c0b)
connects the HTTP request to the provider GPU, relay and validator RPCs.
The native client, tool execution, gateway, provider GPU and validator RPCs are
connected in [the interactive trace](https://jaeger.lsd-ag.ch/trace/a8886259ddc9f00edfe191f9fbc38861).

OpenCode, gateway, node, validator RPC and relay forwarding spans carry W3C
trace context. The shared trex collector exports traces to ax102 over the
router's WireGuard route. Explorer proof queries continue their own HTTP caller
trace into the indexer; background chain following has its own trace. GPU spans
report first-token latency and reused prompt tokens without recording prompts.

The September 20 telemetry rollout uses Hellas `869dab8a`. The CLI, Fetch,
gateway, node, validator and indexer share one optional `otel` feature and one
SDK lifecycle. Default packages and public musl binaries omit the SDK and
exporters; the development services explicitly enable them. NixOS, nix-darwin
and Home Manager share `otel.enable`, `otel.collectorEndpoint` and the existing
trace-specific `otel.endpoint` options. CLI wrappers scope these variables to
Hellas rather than enabling telemetry in unrelated applications.

Home Manager enables OpenCode's native SDK on its ordinary package. Its plugin
only injects W3C context into the Hellas provider's HTTP transport. The local
collector translates native AI SDK spans to the current GenAI Development
conventions, counts the outer operation once, removes content attributes before
remote export and drops OTLP logs. Hellas logs remain local and are not copied
into trace events. OpenCode currently records content inside its local SDK;
the collector is the boundary that removes it before forwarding.

The live interactive check completed a bash tool call and a second user turn.
The [follow-up trace](https://jaeger.lsd-ag.ch/trace/02ebfa7776813e4a3eca1ef7f25d345a)
records 7,168 cached input tokens on Strix-1. Direct
[node RPC](https://jaeger.lsd-ag.ch/trace/1431c2d18b6038c8e6a3629a75e3cd9f) and
[chain query](https://jaeger.lsd-ag.ch/trace/f102ed0af769bbe6c970509225e4b0f2)
checks also propagated context without the gateway. Fetch's queued dispatch
and outbound HTTP streaming transport were verified with focused fixtures;
this rollout did not make an authenticated request to an external Fetch model.

All six validators were updated sequentially and resumed the same finalized
height. Ax102 was built from its exact running `infra-hellas-proof` baseline
with only the explorer telemetry update; pending Hydra and bot changes in the
main infra checkout were excluded. Its proof HTTP endpoint returned 200 with
the supplied trace context. Its pre-existing archive backlog continues to
catch up independently of serving already indexed proofs.

## Devnet funding and deployment

The fleet uses the six public validators through `wss://devnet.hellas.ai/ws/`
followed by each validator's public key. Exact chain identity, routes and
policies are recorded in each provider's `work.json`. The gateway's
`providers.json` selects the active pool; `providers-all.json` also retains
the unused Strix-3 allocation.

The September 2026 reset added foundation address
`25uDmUCQcwYUHHyXthtEspGB2KVTmbys8vTSqAMXKNqRV` with 1,000,000 units.
Initial funding assigned 1,000 units per node and four distinct 10,000-unit
gateway coins, leaving 956,000 at the foundation address. One node allocation
and one gateway coin remain reserved for Strix-3. Public transaction records
and timeout reveals are retained under `/mnt/Home/hellas/foundation-funding`.
Foundation key custody is `/mnt/Home/hellas/foundation.key` (root only), with
an encrypted backup in `../infra/secrets/hellas-foundation.yaml`.

The active bonds expire at devnet height 517487. Provisioning checks the
chain's 1,000,000-block maximum lifetime before signing. The first offers
used an invalid horizon; their funding was spent into replacement coins,
and their journals remain under each account's `retired-invalid-lifetime`
directory. The replacement transactions and reveals are recorded in
`foundation-funding/bond-timeout-correction`. Do not reuse the retired offers.

The Hellas worktree is `../hellas-strix-paid-gateway`. Devnet validators are
declared in `../infra`; the explorer proof origin has a scoped deployment
checkout at `../infra-hellas-proof` to preserve the live Hydra configuration.
Both public explorer/relay Workers are deployed from `../explorer`.

On trex, retain the `live-tmpfs` specialization until the planned storage
transition reboot: install the parent with `boot`, then activate its
`specialisation/live-tmpfs` child with `test`. Reload NFS exports with
`exportfs -ra` when their declarations change; do not restart SPDK or NFS
under the connected diskless hosts.
