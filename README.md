# deepseek-agent-verify

**Can DeepSeek V4 Pro actually drive a coding agent?** Not "does it return 200" — can it run a tool, receive the result, act on it, edit a file, and recover from a failure?

`zkc-verify.sh` answers that with a 23-probe capability matrix, run inside a [sprites.dev](https://sprites.dev) sandbox against **both** OpenAI Codex and Anthropic's Claude Code.

Short answer: **both work.** Claude Code needs no proxy. Codex needs one, and most proxies silently fail.

---

## Verified results

Three consecutive runs on clean sprites. `codex-cli 0.144.3`, `claude 2.1.207`, `deepseek-v4-pro`.

| Layer | Probes | Result |
|---|---|---|
| **P1–P5** Responses protocol, raw curl through the bridge | identity, tool result, 3 parallel tool results, reasoning item, streaming | 5 PASS |
| **C1–C8** real `codex exec` | shell, chained, parallel, create, edit, recover, metadata, web search | 7 PASS, 1 INFO |
| **A1–A4** Anthropic protocol, raw curl, no proxy | identity, tool_use round trip, parallel, streaming | 4 PASS |
| **L1–L6** real `claude -p` | shell, chained, parallel, create, edit, recover | 6 PASS |

**22 PASS · 1 INFO · 0 FAIL.** The INFO is cosmetic: Codex prints a metadata-lookup warning even when the context window is correctly pinned.

---

## Quick start

```bash
bash zkc-verify.sh
```

Requires **bash 4+** (macOS ships 3.2 — `brew install bash`), the `sprite` CLI, and a DeepSeek API key. Everything else installs itself on the sprite.

The run picks a sprite (or set `SPRITE_NAME=`), prompts for your key, installs Codex and Claude Code, does device-code auth, starts the bridge, runs all 23 probes, and prints a matrix plus a ready-to-paste config. Full transcript lands in `./debug.log`.

```bash
SPRITE_NAME=my-sprite bash zkc-verify.sh          # skip the picker
BRIDGE_CMD='...' BRIDGE_PORT=9090 bash zkc-verify.sh   # test another proxy
DEEPSEEK_MODEL=deepseek-v4-flash bash zkc-verify.sh
```

---

## The configurations it validates

### Claude Code — no proxy

DeepSeek serves the Anthropic Messages API natively, so nothing translates.

```bash
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN=sk-your-key
export ANTHROPIC_MODEL=deepseek-v4-pro[1m]
export ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro[1m]
export ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro[1m]
export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
export CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1
export CLAUDE_CODE_EFFORT_LEVEL=max

claude
```

- The base URL must end in `/anthropic`. Pointing at `/v1` gets 400s — Claude Code sends Anthropic-shaped bodies.
- `[1m]` selects the 1M-context variant.
- The `DEFAULT_*` vars are **not** redundant: Claude Code routes some internal calls by asking for opus/sonnet/haiku *by name*, ignoring `ANTHROPIC_MODEL`.

### Codex — needs a translating bridge

```bash
export DEEPSEEK_API_KEY=sk-your-key
npx -y @codeproxy/cli --base-url https://api.deepseek.com/v1 \
    --model deepseek-v4-pro --apikey $DEEPSEEK_API_KEY
```

```toml
# ~/.codex/config.toml
[model_providers.deepseek]
name = "DeepSeek"
base_url = "http://127.0.0.1:8787/v1"
env_key = "DEEPSEEK_API_KEY"
wire_api = "responses"
model_context_window = 1000000
model_max_output_tokens = 8192

[profiles.deepseek]
model = "deepseek-v4-pro"
model_provider = "deepseek"
```

The bridge must be running before Codex starts and must outlive the session.

---

## Why Codex needs a bridge

Codex speaks **only** the OpenAI Responses API. DeepSeek serves **only** Chat Completions. Different request shapes, different tool-call representations, different streaming events.

Four traps, each of which cost a debugging session:

**`wire_api = "chat"` is dead.** Every 2025-era tutorial says to set it. Codex removed that path. It must be `"responses"`.

**Most proxies fail on tool calls.** Three were tested:

| Proxy | Transport | Tool round trip |
|---|---|---|
| LiteLLM | PASS | **FAIL** — drops the `role: "tool"` message → `insufficient tool messages following tool_calls` |
| codex-deepseek-v4-proxy | PASS | **FAIL** — `reasoning_content must be passed back` |
| **@codeproxy/cli** | PASS | **PASS** |

Single-turn pings pass on all three. The failure only appears on the first real tool call — which is exactly why this harness exists.

**`-m` alone is not enough.** `codex -m deepseek-v4-pro` changes the model name but leaves the provider on OpenAI's path, giving "model not supported". You need `model_provider` too.

**Codex can't read metadata from a custom provider,** so it guesses a fallback context window. Pin it explicitly.

---

## What the probes actually check

The design principle: **a probe must be unfakeable.**

- Tool-result probes issue a **random token per call** and require it echoed back. A model that never received its own tool output cannot produce it.
- The Anthropic probes do a **genuine two-turn round trip** — the model really calls the tool, and its reply is replayed *verbatim* including thinking blocks. Fabricating that turn fails, because DeepSeek's thinking mode rejects any replay missing them.
- Streaming probes **reassemble** SSE `content_block_delta` fragments before checking. A token is split across chunks; grepping the raw body finds nothing even when the stream is perfect.
- Identity is proved from the wire — upstream `model` field, bridge-log hits to `api.deepseek.com`, and per-request token accounting — not from asking the model who it is. (It says "GPT-5"; Codex's system prompt tells it so.)

---

## Security notes

No API key is ever written to `debug.log`, printed to the terminal, or placed in argv on your machine. Input uses `read -rs`; the key travels to the sprite over exec stdin. The staged bridge-command file holds a `__KEY__` placeholder, and the printed config shows `$DEEPSEEK_API_KEY` as literal text.

Three things to know anyway:

1. **The key is in argv on the sprite.** `@codeproxy/cli` takes `--apikey` on the command line, so it's visible to `ps` *inside the sandbox*. Fine for a single-tenant isolated VM; not something to replicate on a shared host.
2. **The key is written to `~/.codex/deepseek.env` on the sprite**, mode 600. The detached bridge needs it after your exec session ends. Remove it when done (below).
3. **`debug.log` is gitignored — keep it that way.** It contains no key, but it does contain sprite/org names and a one-time device-auth code.

**Both agents run with sandboxing disabled** (`--dangerously-bypass-approvals-and-sandbox`, `--dangerously-skip-permissions`). This is correct *here*: a sprite is a hardware-isolated VM with a DNS egress allowlist, which is the environment those flags are documented for. Bubblewrap cannot even initialise inside one. **Do not copy these flags to your laptop.**

`BRIDGE_CMD` is executed via `bash -c`. It's your own override knob, but never paste one from an untrusted source. Likewise `npx -y` fetches and runs a third-party package at launch — pin or vendor it if that matters to you.

Cleanup — the keep-awake task bills while held:

```bash
sprite exec -s YOUR_SPRITE -- bash -lc '
  kill -- -$(cat ~/probe/bridge.pid) 2>/dev/null
  rm -f ~/probe/bridge.pid ~/probe/bridge.log ~/.codex/deepseek.env
  curl -s -X DELETE --unix-socket /.sprite/api.sock http://sprite/v1/tasks/zkc-bridge'
```

---

## Limitations

These are **capability** probes, not endurance tests. Six short tasks per harness. Long-session behaviour, context compaction near the 1M boundary, and cost at scale are all unverified.

Results are pinned to the versions above. The proxy landscape moves quickly — re-run rather than trusting this table.

---

## Which should you use?

|  | Claude Code | Codex |
|---|---|---|
| Proxy | none | required |
| Processes to babysit | 0 | 1 |
| Context window | `[1m]` suffix | manual pin |
| Failure surface | smaller | translation layer |

**Use Claude Code unless you specifically need Codex.** Fewer moving parts, and no translator that can silently drop a tool result.

---

## License

MIT. No warranty — verify against your own setup before depending on it.
