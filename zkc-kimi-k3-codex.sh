#!/usr/bin/env bash
#
# zkc-kimi-k3-verify-v24.sh - test Kimi K3 across raw APIs, Codex, and Claude Code.
#
#   # Default: full matrix (protocol + Anthropic + Codex + Claude Code)
#   bash zkc-kimi-k3-verify-v24.sh
#
#   # Focused reruns remain available
#   ZKC_LAYERS=codex KIMI_CODEX_ROUTER=codeproxy bash zkc-kimi-k3-verify-v24.sh
#   ZKC_LAYERS=anthropic bash zkc-kimi-k3-verify-v24.sh
#
#   # Re-run the already-proven Responses protocol explicitly
#   ZKC_LAYERS=protocol bash zkc-kimi-k3-verify-v24.sh
#
# Not a smoke test. A capability matrix with protocol and client probes,
# each isolating one thing an agent actually needs, so the answer to "can I use
# Kimi K3 in Codex for real work" is a table rather than a vibe.
#
# Layer 1 - PROTOCOL (raw HTTP, no codex, small focused requests)
#   P1 identity    does Moonshot actually serve Kimi K3, or something else?
#   P2 tool result one function_call + function_call_output survives translation
#   P3 parallel    THREE tool results in one turn (this is what killed LiteLLM)
#   P4 reasoning   preserved thinking + a scientific tool argument survive translation
#   P5 streaming   P2 again with stream:true, because codex streams
#   P6-P8 web      opt-in Kimi Formula search: execution, synthesis, verification
#
# Layer 2 - CODEX (real codex exec, small focused tasks)
#   C1 shell       run a command, report its output
#   C2 chained     use the output of one command as input to the next
#   C3 parallel    three separate commands in one turn
#   C4 create      write a new file
#   C5 edit        modify an existing file (a different codex tool path)
#   C6 recover     a command fails; continue instead of giving up
#   C7 metadata    effective config, catalog metadata, optional long-context proof
#   C8 native web  whether this Responses bridge advertises standalone search
#   C11 preserve   whether upstream reasoning_content is replayed byte-identically
#   C9 science     reproducible Arrhenius + Bateman-chain numerical suite
#   C10 reasoning  structured reasoning-summary observability during science
#
# Layer 3 - ANTHROPIC PROTOCOL (raw HTTP to api.moonshot.ai/anthropic)
#   A1 identity    /v1/messages answers and names its model
#   A2 tool_use    a GENUINE round trip: the model calls the tool, its reply
#                  (thinking blocks included) is replayed verbatim + tool_result
#   A3 parallel    same, asking for three calls; every issued token must return
#   A4 streaming   streamed tool-use turn reconstructed, then streamed final turn
# (v1 fabricated the assistant turn; Kimi preserved-thinking mode rejects replay
#  missing its thinking blocks. Real clients replay verbatim, so the probe must.)
#
# Layer 4 - CLAUDE CODE (real claude -p, headless)
#   L1 shell   L2 chained   L3 parallel   L4 create   L5 edit   L6 recover
#   L7 websearch (open-ended, structured tool evidence)   L8 science
#   L9 reasoning-summary observability during the science run
#
# Kimi serves Anthropic Messages compatibly at /anthropic, so Layer 3/4 need
# no proxy at all. That is the whole point of testing both: if Claude Code works
# natively, the Codex bridge is optional complexity.
#
# Ends with ready-to-paste Codex profile/config files and a plain list of what works.
#
if [ -z "${BASH_VERSION:-}" ]; then echo "run with bash: bash $0" >&2; exit 1; fi
# macOS still ships bash 3.2.57 as /bin/bash. This script uses `read -r -d ""`,
# process substitution and nested parameter substitution, and 3.2 differs on
# backslash handling inside ${v//pat/rep} within a heredoc - which is exactly
# what crashed the verdict block. Fail loudly instead of subtly.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "error: bash ${BASH_VERSION} is too old (need 4+)." >&2
  echo "  macOS ships 3.2 as /bin/bash. Install a current one:" >&2
  echo "    brew install bash && /opt/homebrew/bin/bash $0" >&2
  exit 1
fi
set -uo pipefail
umask 077

# This verifier is designed for disposable Sprites and deliberately lets the
# tested coding agents execute commands inside the Sprite. Remote dependencies
# are installed into a persistent user-local directory inside the Sprite. In
# CC Switch mode, a missing host Codex CLI may also be installed without sudo
# under KIMI_HOST_CODEX_PREFIX so the selected Codex probes can actually run.
ZKC_FORCE_INSTALL="${ZKC_FORCE_INSTALL:-0}"
KEEP_BRIDGE="${KEEP_BRIDGE:-0}"
# Prefix every transcript/console line with an ISO-8601 UTC timestamp.
# Set ZKC_LOG_TIMESTAMPS=0 only when a machine consumer requires legacy raw lines.
ZKC_LOG_TIMESTAMPS="${ZKC_LOG_TIMESTAMPS:-1}"
# Select a comma-separated subset of protocol,anthropic,codex,claude.
# The latest validated runs completed both raw protocol layers, so this
# revision defaults to the complete matrix. All four layers are selected and
# optional web/science/long-context probes are enabled unless explicitly
# overridden. Use a smaller ZKC_LAYERS subset only for focused debugging.
ZKC_LAYERS="${ZKC_LAYERS:-all}"
# Low-tier account guardrail: the current account has previously reported 20 RPM,
# so 3.2 seconds leaves jitter margin. A local gateway now enforces this between
# every upstream request, including requests issued inside Codex/Claude sessions.
# Raw HTTP retries are bounded; ordinary rate
# limits require Retry-After, while engine overload uses a short bounded
# exponential backoff. TPD stops by default; an explicit KIMI_TPD_ACTION=wait
# permits one wait-until-reset attempt.
KIMI_MIN_REQUEST_INTERVAL_MS="${KIMI_MIN_REQUEST_INTERVAL_MS:-3200}"
KIMI_RATE_RETRIES="${KIMI_RATE_RETRIES:-2}"
KIMI_RETRY_MAX_SECONDS="${KIMI_RETRY_MAX_SECONDS:-60}"
# Engine overload is a transient capacity condition, not a daily-quota stop.
# Retry it with bounded exponential backoff even when Retry-After is absent.
KIMI_ENGINE_OVERLOAD_RETRIES="${KIMI_ENGINE_OVERLOAD_RETRIES:-3}"
KIMI_ENGINE_OVERLOAD_BASE_SECONDS="${KIMI_ENGINE_OVERLOAD_BASE_SECONDS:-5}"
KIMI_MAX_CONCURRENCY="${KIMI_MAX_CONCURRENCY:-1}"
# Daily-quota handling. "stop" exits the selected layer immediately and prints
# the exact reset deadline. "wait" sleeps once until Retry-After plus a small
# grace period, then resumes. It never loops indefinitely or bypasses quota.
KIMI_TPD_ACTION="${KIMI_TPD_ACTION:-stop}"
KIMI_TPD_WAIT_MAX_SECONDS="${KIMI_TPD_WAIT_MAX_SECONDS:-7200}"
KIMI_TPD_GRACE_SECONDS="${KIMI_TPD_GRACE_SECONDS:-5}"
KIMI_RESET_TIMEZONE="${KIMI_RESET_TIMEZONE:-Asia/Kuala_Lumpur}"
# Raw HTTP diagnostics are emitted as redacted, single-line HTTP| records.
# errors: log transport/HTTP errors only; all: log every raw request; off: disable.
KIMI_HTTP_LOG_LEVEL="${KIMI_HTTP_LOG_LEVEL:-errors}"
KIMI_HTTP_BODY_MAX="${KIMI_HTTP_BODY_MAX:-2048}"

# SPRITE_NAME env skips the picker; otherwise choose from `sprite list`.
SPRITE_NAME="${SPRITE_NAME:-}"
MODEL="${KIMI_MODEL:-kimi-k3}"
ANTHROPIC_API_MODEL="${KIMI_ANTHROPIC_API_MODEL:-$MODEL}"
CLAUDE_MODEL="${KIMI_CLAUDE_MODEL:-${KIMI_ANTHROPIC_MODEL:-${MODEL}[1m]}}"
CONTEXT_WINDOW="${KIMI_CONTEXT_WINDOW:-1048576}"
# Moonshot counts the requested max_completion_tokens against RPM/TPM/TPD
# admission limits even when the model emits far fewer tokens. Keep routine
# verification calls at a rate-safe cap; the documented K3 default remains a
# separate fact and can be tested explicitly by overriding the probe cap.
MODEL_DEFAULT_MAX_OUTPUT_TOKENS="${KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS:-131072}"
MAX_OUTPUT_TOKENS="${KIMI_PROBE_MAX_OUTPUT_TOKENS:-1024}"
# Reasoning-heavy probes can consume their entire output allowance internally
# before emitting a tool call. Keep routine probes cheap, but give P4 a separate
# low-quota budget and one bounded escalation when the first response ends
# exactly at the cap with no output item.
REASONING_OUTPUT_TOKENS="${KIMI_REASONING_PROBE_MAX_OUTPUT_TOKENS:-16384}"
REASONING_RETRY_OUTPUT_TOKENS="${KIMI_REASONING_RETRY_MAX_OUTPUT_TOKENS:-32768}"
# Raw Anthropic tool turns preserve thinking blocks and need more room than the
# cheapest identity/echo probes, while remaining bounded on low-quota accounts.
ANTHROPIC_OUTPUT_TOKENS="${KIMI_ANTHROPIC_PROBE_MAX_OUTPUT_TOKENS:-16384}"
# Official web-search Formula calls often need a separate synthesis turn after
# tool execution. Keep that turn bounded but larger than the routine 1024 cap.
WEB_OUTPUT_TOKENS="${KIMI_WEB_PROBE_MAX_OUTPUT_TOKENS:-32768}"
# Real Codex work must not inherit the verifier's 1024-token routine cap. The
# isolated Codex profile and Codex layer use this independent client budget.
CLIENT_OUTPUT_TOKENS="${KIMI_CLIENT_MAX_OUTPUT_TOKENS:-16384}"
# Codex routing mode. The normal deployment keeps Codex and Claude Code inside
# the Sprite, so the default is the headless codeproxy Responses-to-Chat bridge.
# CC Switch remains an explicit host-desktop compatibility branch only.
CODEX_ROUTER="${KIMI_CODEX_ROUTER:-codeproxy}"
CC_SWITCH_BASE_URL="${KIMI_CC_SWITCH_BASE_URL:-}"
CC_SWITCH_MODEL="${KIMI_CC_SWITCH_MODEL:-$MODEL}"
HOST_CODEX_BIN="${KIMI_HOST_CODEX_BIN:-codex}"
# A full-matrix run needs a host Codex CLI for CC Switch. Discover common
# installer locations first, then optionally install the pinned CLI into a
# user-local prefix without sudo when it is absent from PATH.
AUTO_INSTALL_HOST_CODEX="${KIMI_AUTO_INSTALL_HOST_CODEX:-1}"
HOST_CODEX_PREFIX="${KIMI_HOST_CODEX_PREFIX:-$HOME/.local/share/zkc-kimi-k3-tools/npm}"
# P4 measured that codeproxy does not expose a Responses reasoning-summary item.
# Keep Codex summary support disabled unless a later bridge version proves it.
CODEX_REASONING_SUMMARIES="${KIMI_CODEX_REASONING_SUMMARIES:-0}"
# Codex capability probes use high reasoning; science/reasoning probes use
# max effort so the matrix does not measure K3 at its weakest setting.
CODEX_SIMPLE_REASONING_EFFORT="${KIMI_CODEX_SIMPLE_REASONING_EFFORT:-high}"
CODEX_COMPLEX_REASONING_EFFORT="${KIMI_CODEX_COMPLEX_REASONING_EFFORT:-max}"
REQUEST_TIMEOUT="${KIMI_REQUEST_TIMEOUT:-300}"
CODEX_STANDALONE_WEB_SEARCH="${CODEX_STANDALONE_WEB_SEARCH:-0}"
# Open-web probes fetch model-selected URLs. Opt in explicitly.
OPEN_WEB_TEST="${OPEN_WEB_TEST:-0}"
WEB_MAX_AGE_DAYS="${WEB_MAX_AGE_DAYS:-60}"
SCIENCE_TEST="${SCIENCE_TEST:-1}"
LONG_CONTEXT_TOKENS="${KIMI_LONG_CONTEXT_TEST_TOKENS:-8192}"
PORT="${BRIDGE_PORT:-8787}"
GATEWAY_PORT="${KIMI_GATEWAY_PORT:-8790}"
GATEWAY_PORT_SPAN="${KIMI_GATEWAY_PORT_SPAN:-100}"
BRIDGE_PORT_SPAN="${BRIDGE_PORT_SPAN:-100}"
BRIDGE_PORT_STRICT="${BRIDGE_PORT_STRICT:-0}"
KEEPAWAKE_MAX="${KEEPAWAKE_MAX:-7200}"

# Tested package versions. Codex, codeproxy, and Claude dependencies are installed
# inside the selected Sprite. Explicit CC Switch mode additionally uses a host Codex CLI;
# when absent, it can be installed into KIMI_HOST_CODEX_PREFIX without sudo.
# Set ZKC_FORCE_INSTALL=1 to refresh remote tools to these exact versions.
CODEPROXY_VERSION="${CODEPROXY_VERSION:-0.2.9}"
CODEX_VERSION="${CODEX_VERSION:-0.146.0}"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.220}"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"
RUN_ID="${RUN_ID//[^A-Za-z0-9._-]/_}"
# Sprites task names accept lowercase letters, digits, and dashes only.
# Keep RUN_ID human-readable for filesystem paths, but generate the task name
# independently so ISO timestamp capitals (T/Z) can never invalidate it.
TASK_NAME="zkc-$(date -u +%Y%m%dt%H%M%sz)-$$-$RANDOM"

is_uint(){ [[ "$1" =~ ^[0-9]+$ ]]; }
need_uint(){ is_uint "$2" || { echo "error: $1 must be an unsigned integer" >&2; exit 2; }; }
need_bool(){ [[ "$2" == 0 || "$2" == 1 ]] || { echo "error: $1 must be 0 or 1" >&2; exit 2; }; }
need_uint BRIDGE_PORT "$PORT"
need_uint KIMI_GATEWAY_PORT "$GATEWAY_PORT"
need_uint KIMI_GATEWAY_PORT_SPAN "$GATEWAY_PORT_SPAN"
need_uint BRIDGE_PORT_SPAN "$BRIDGE_PORT_SPAN"
need_bool BRIDGE_PORT_STRICT "$BRIDGE_PORT_STRICT"
(( PORT >= 1 && PORT <= 65535 )) || { echo "error: BRIDGE_PORT must be 1..65535" >&2; exit 2; }
(( GATEWAY_PORT >= 1 && GATEWAY_PORT <= 65535 )) || { echo "error: KIMI_GATEWAY_PORT must be 1..65535" >&2; exit 2; }
(( GATEWAY_PORT_SPAN <= 1000 )) || { echo "error: KIMI_GATEWAY_PORT_SPAN must be <= 1000" >&2; exit 2; }
(( BRIDGE_PORT_SPAN <= 1000 )) || { echo "error: BRIDGE_PORT_SPAN must be <= 1000" >&2; exit 2; }
need_uint KIMI_CONTEXT_WINDOW "$CONTEXT_WINDOW"
need_uint KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS "$MODEL_DEFAULT_MAX_OUTPUT_TOKENS"
need_uint KIMI_PROBE_MAX_OUTPUT_TOKENS "$MAX_OUTPUT_TOKENS"
need_uint KIMI_REASONING_PROBE_MAX_OUTPUT_TOKENS "$REASONING_OUTPUT_TOKENS"
need_uint KIMI_REASONING_RETRY_MAX_OUTPUT_TOKENS "$REASONING_RETRY_OUTPUT_TOKENS"
need_uint KIMI_ANTHROPIC_PROBE_MAX_OUTPUT_TOKENS "$ANTHROPIC_OUTPUT_TOKENS"
need_uint KIMI_WEB_PROBE_MAX_OUTPUT_TOKENS "$WEB_OUTPUT_TOKENS"
need_uint KIMI_CLIENT_MAX_OUTPUT_TOKENS "$CLIENT_OUTPUT_TOKENS"
[[ "$CODEX_ROUTER" == cc-switch || "$CODEX_ROUTER" == codeproxy ]] || { echo "error: KIMI_CODEX_ROUTER must be cc-switch or codeproxy" >&2; exit 2; }
[[ "$CC_SWITCH_MODEL" == "$MODEL" ]] || { echo "error: KIMI_CC_SWITCH_MODEL must exactly match KIMI_MODEL ($MODEL)" >&2; exit 2; }
[[ -z "$CC_SWITCH_BASE_URL" || "$CC_SWITCH_BASE_URL" =~ ^http://(127\.0\.0\.1|localhost):[0-9]{1,5}(/v1)?/?$ ]] || { echo "error: KIMI_CC_SWITCH_BASE_URL must be empty or a localhost HTTP route" >&2; exit 2; }
# macOS libc regex uses RE_DUP_MAX=255, so an interval capped at 256 is invalid
# even under a current Homebrew Bash. Check length separately and keep the
# character-class regex unbounded for portability.
(( ${#HOST_CODEX_BIN} >= 1 && ${#HOST_CODEX_BIN} <= 256 )) \
  || { echo "error: unsafe KIMI_HOST_CODEX_BIN length" >&2; exit 2; }
[[ "$HOST_CODEX_BIN" =~ ^[A-Za-z0-9_./+-]+$ ]] \
  || { echo "error: unsafe KIMI_HOST_CODEX_BIN characters" >&2; exit 2; }
need_bool KIMI_CODEX_REASONING_SUMMARIES "$CODEX_REASONING_SUMMARIES"
[[ "$CODEX_SIMPLE_REASONING_EFFORT" =~ ^(minimal|low|medium|high|max|xhigh)$ ]] || { echo "error: KIMI_CODEX_SIMPLE_REASONING_EFFORT must be minimal, low, medium, high, max, or xhigh" >&2; exit 2; }
[[ "$CODEX_COMPLEX_REASONING_EFFORT" =~ ^(minimal|low|medium|high|max|xhigh)$ ]] || { echo "error: KIMI_CODEX_COMPLEX_REASONING_EFFORT must be minimal, low, medium, high, max, or xhigh" >&2; exit 2; }
need_uint KIMI_REQUEST_TIMEOUT "$REQUEST_TIMEOUT"
need_uint WEB_MAX_AGE_DAYS "$WEB_MAX_AGE_DAYS"
need_uint KIMI_LONG_CONTEXT_TEST_TOKENS "$LONG_CONTEXT_TOKENS"
need_uint KEEPAWAKE_MAX "$KEEPAWAKE_MAX"
need_bool CODEX_STANDALONE_WEB_SEARCH "$CODEX_STANDALONE_WEB_SEARCH"
need_bool OPEN_WEB_TEST "$OPEN_WEB_TEST"
need_bool SCIENCE_TEST "$SCIENCE_TEST"
need_bool ZKC_FORCE_INSTALL "$ZKC_FORCE_INSTALL"
need_bool KEEP_BRIDGE "$KEEP_BRIDGE"
need_bool ZKC_LOG_TIMESTAMPS "$ZKC_LOG_TIMESTAMPS"
need_uint KIMI_MIN_REQUEST_INTERVAL_MS "$KIMI_MIN_REQUEST_INTERVAL_MS"
need_uint KIMI_RATE_RETRIES "$KIMI_RATE_RETRIES"
need_uint KIMI_RETRY_MAX_SECONDS "$KIMI_RETRY_MAX_SECONDS"
need_uint KIMI_ENGINE_OVERLOAD_RETRIES "$KIMI_ENGINE_OVERLOAD_RETRIES"
need_uint KIMI_ENGINE_OVERLOAD_BASE_SECONDS "$KIMI_ENGINE_OVERLOAD_BASE_SECONDS"
need_uint KIMI_MAX_CONCURRENCY "$KIMI_MAX_CONCURRENCY"
need_bool KIMI_AUTO_INSTALL_HOST_CODEX "$AUTO_INSTALL_HOST_CODEX"
[[ "$KIMI_TPD_ACTION" == stop || "$KIMI_TPD_ACTION" == wait ]] || { echo "error: KIMI_TPD_ACTION must be stop or wait" >&2; exit 2; }
need_uint KIMI_TPD_WAIT_MAX_SECONDS "$KIMI_TPD_WAIT_MAX_SECONDS"
need_uint KIMI_TPD_GRACE_SECONDS "$KIMI_TPD_GRACE_SECONDS"
[[ "$KIMI_RESET_TIMEZONE" =~ ^[A-Za-z0-9_+./-]{1,128}$ ]] || { echo "error: unsafe KIMI_RESET_TIMEZONE" >&2; exit 2; }
[[ "$KIMI_HTTP_LOG_LEVEL" == off || "$KIMI_HTTP_LOG_LEVEL" == errors || "$KIMI_HTTP_LOG_LEVEL" == all ]] || { echo "error: KIMI_HTTP_LOG_LEVEL must be off, errors, or all" >&2; exit 2; }
need_uint KIMI_HTTP_BODY_MAX "$KIMI_HTTP_BODY_MAX"
(( KIMI_HTTP_BODY_MAX >= 128 && KIMI_HTTP_BODY_MAX <= 65536 )) || { echo "error: KIMI_HTTP_BODY_MAX must be 128..65536" >&2; exit 2; }
(( KIMI_MIN_REQUEST_INTERVAL_MS >= 3000 && KIMI_MIN_REQUEST_INTERVAL_MS <= 60000 )) || { echo "error: KIMI_MIN_REQUEST_INTERVAL_MS must be 3000..60000 for the configured low-quota pacing guard" >&2; exit 2; }
(( KIMI_RATE_RETRIES <= 5 )) || { echo "error: KIMI_RATE_RETRIES must be <=5" >&2; exit 2; }
(( KIMI_RETRY_MAX_SECONDS >= 1 && KIMI_RETRY_MAX_SECONDS <= 600 )) || { echo "error: KIMI_RETRY_MAX_SECONDS must be 1..600" >&2; exit 2; }
(( KIMI_ENGINE_OVERLOAD_RETRIES <= 5 )) || { echo "error: KIMI_ENGINE_OVERLOAD_RETRIES must be <=5" >&2; exit 2; }
(( KIMI_ENGINE_OVERLOAD_BASE_SECONDS >= 1 && KIMI_ENGINE_OVERLOAD_BASE_SECONDS <= 120 )) || { echo "error: KIMI_ENGINE_OVERLOAD_BASE_SECONDS must be 1..120" >&2; exit 2; }
(( KIMI_MAX_CONCURRENCY >= 1 && KIMI_MAX_CONCURRENCY <= 8 )) || { echo "error: KIMI_MAX_CONCURRENCY must be 1..8" >&2; exit 2; }
(( KIMI_TPD_WAIT_MAX_SECONDS >= 60 && KIMI_TPD_WAIT_MAX_SECONDS <= 86400 )) || { echo "error: KIMI_TPD_WAIT_MAX_SECONDS must be 60..86400" >&2; exit 2; }
(( KIMI_TPD_GRACE_SECONDS <= 120 )) || { echo "error: KIMI_TPD_GRACE_SECONDS must be <=120" >&2; exit 2; }
(( PORT >= 1024 && PORT <= 65535 )) || { echo "error: BRIDGE_PORT must be 1024..65535" >&2; exit 2; }
(( REQUEST_TIMEOUT >= 10 && REQUEST_TIMEOUT <= 3600 )) || { echo "error: KIMI_REQUEST_TIMEOUT must be 10..3600" >&2; exit 2; }
(( CONTEXT_WINDOW >= 1024 && CONTEXT_WINDOW <= 4000000 )) || { echo "error: KIMI_CONTEXT_WINDOW must be 1024..4000000" >&2; exit 2; }
(( MODEL_DEFAULT_MAX_OUTPUT_TOKENS >= 1 && MODEL_DEFAULT_MAX_OUTPUT_TOKENS <= 1048576 )) || { echo "error: KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS must be 1..1048576" >&2; exit 2; }
(( MAX_OUTPUT_TOKENS >= 1024 && MAX_OUTPUT_TOKENS <= MODEL_DEFAULT_MAX_OUTPUT_TOKENS )) || { echo "error: KIMI_PROBE_MAX_OUTPUT_TOKENS must be 1024..KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS" >&2; exit 2; }
(( REASONING_OUTPUT_TOKENS >= MAX_OUTPUT_TOKENS && REASONING_OUTPUT_TOKENS <= MODEL_DEFAULT_MAX_OUTPUT_TOKENS )) || { echo "error: KIMI_REASONING_PROBE_MAX_OUTPUT_TOKENS must be KIMI_PROBE_MAX_OUTPUT_TOKENS..KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS" >&2; exit 2; }
(( REASONING_RETRY_OUTPUT_TOKENS >= REASONING_OUTPUT_TOKENS && REASONING_RETRY_OUTPUT_TOKENS <= MODEL_DEFAULT_MAX_OUTPUT_TOKENS )) || { echo "error: KIMI_REASONING_RETRY_MAX_OUTPUT_TOKENS must be KIMI_REASONING_PROBE_MAX_OUTPUT_TOKENS..KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS" >&2; exit 2; }
(( WEB_OUTPUT_TOKENS >= 1024 && WEB_OUTPUT_TOKENS <= MODEL_DEFAULT_MAX_OUTPUT_TOKENS )) || { echo "error: KIMI_WEB_PROBE_MAX_OUTPUT_TOKENS must be 1024..KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS" >&2; exit 2; }
(( ANTHROPIC_OUTPUT_TOKENS >= 1024 && ANTHROPIC_OUTPUT_TOKENS <= MODEL_DEFAULT_MAX_OUTPUT_TOKENS )) || { echo "error: KIMI_ANTHROPIC_PROBE_MAX_OUTPUT_TOKENS must be 1024..KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS" >&2; exit 2; }
(( CLIENT_OUTPUT_TOKENS >= 1024 && CLIENT_OUTPUT_TOKENS <= MODEL_DEFAULT_MAX_OUTPUT_TOKENS )) || { echo "error: KIMI_CLIENT_MAX_OUTPUT_TOKENS must be 1024..KIMI_MODEL_DEFAULT_MAX_OUTPUT_TOKENS" >&2; exit 2; }
(( LONG_CONTEXT_TOKENS <= CONTEXT_WINDOW )) || { echo "error: KIMI_LONG_CONTEXT_TEST_TOKENS cannot exceed KIMI_CONTEXT_WINDOW" >&2; exit 2; }
(( WEB_MAX_AGE_DAYS <= 3650 )) || { echo "error: WEB_MAX_AGE_DAYS must be <=3650" >&2; exit 2; }
(( KEEPAWAKE_MAX <= 86400 )) || { echo "error: KEEPAWAKE_MAX must be <=86400" >&2; exit 2; }
[[ "$MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$ ]] || { echo "error: unsafe KIMI_MODEL" >&2; exit 2; }
[[ "$ANTHROPIC_API_MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$ ]] || { echo "error: unsafe KIMI_ANTHROPIC_API_MODEL" >&2; exit 2; }
(( ${#CLAUDE_MODEL} <= 128 )) && [[ "$CLAUDE_MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*(\[[A-Za-z0-9._:/-]+\])?$ ]] || { echo "error: unsafe KIMI_CLAUDE_MODEL" >&2; exit 2; }
[[ -z "$SPRITE_NAME" || "$SPRITE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || { echo "error: unsafe SPRITE_NAME" >&2; exit 2; }
[[ -z "${SPRITE_ORG:-}" || "${SPRITE_ORG}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || { echo "error: unsafe SPRITE_ORG" >&2; exit 2; }
for pv in "$CODEPROXY_VERSION" "$CODEX_VERSION" "$CLAUDE_CODE_VERSION"; do
  [[ "$pv" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$ ]] || { echo "error: package versions must be exact semver values" >&2; exit 2; }
done

# Normalize and validate layer selection once on the host.
ZKC_LAYERS_NORM="$(printf '%s' "$ZKC_LAYERS" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
[[ -n "$ZKC_LAYERS_NORM" ]] || { echo "error: ZKC_LAYERS cannot be empty" >&2; exit 2; }
if [[ "$ZKC_LAYERS_NORM" == all ]]; then
  ZKC_LAYERS_NORM="protocol,anthropic,codex,claude"
fi
IFS=',' read -r -a _zkc_layers <<<"$ZKC_LAYERS_NORM"
L_PROTOCOL=0; L_ANTHROPIC=0; L_CODEX=0; L_CLAUDE=0
for _layer in "${_zkc_layers[@]}"; do
  case "$_layer" in
    protocol) L_PROTOCOL=1;;
    anthropic) L_ANTHROPIC=1;;
    codex) L_CODEX=1;;
    claude) L_CLAUDE=1;;
    *) echo "error: unknown ZKC_LAYERS entry: $_layer (use protocol,anthropic,codex,claude,all)" >&2; exit 2;;
  esac
done
(( L_PROTOCOL + L_ANTHROPIC + L_CODEX + L_CLAUDE > 0 )) || { echo "error: no layers selected" >&2; exit 2; }
CODEX_USES_CC_SWITCH=0; CODEX_USES_CODEPROXY=0
if (( L_CODEX )); then
  [[ "$CODEX_ROUTER" == cc-switch ]] && CODEX_USES_CC_SWITCH=1 || CODEX_USES_CODEPROXY=1
fi
REMOTE_NEED_CODEPROXY=0; (( L_PROTOCOL || CODEX_USES_CODEPROXY )) && REMOTE_NEED_CODEPROXY=1
REMOTE_NEED_CODEX=0; (( CODEX_USES_CODEPROXY )) && REMOTE_NEED_CODEX=1
NEED_BRIDGE=$REMOTE_NEED_CODEPROXY
NEED_API_KEY=0; (( L_PROTOCOL || L_ANTHROPIC || L_CLAUDE || CODEX_USES_CODEPROXY )) && NEED_API_KEY=1
NEED_GATEWAY=$NEED_API_KEY
NEED_SPRITE=$NEED_API_KEY
if [[ "$KEEP_BRIDGE" == 1 && "$NEED_BRIDGE" == 0 ]]; then
  echo "error: KEEP_BRIDGE=1 is only valid for protocol or KIMI_CODEX_ROUTER=codeproxy" >&2
  exit 2
fi
SELECTED_LAYERS=""
for _pair in "protocol:$L_PROTOCOL" "anthropic:$L_ANTHROPIC" "codex:$L_CODEX" "claude:$L_CLAUDE"; do
  _name=${_pair%%:*}; _enabled=${_pair#*:}
  [[ "$_enabled" == 1 ]] || continue
  SELECTED_LAYERS+="${SELECTED_LAYERS:+,}${_name}"
done
unset _zkc_layers _layer _pair _name _enabled

# Keep the v3 behavior: the complete terminal transcript is written beside
# the command invocation. Override with ZKC_LOG=/path/to/file.log if needed.
#
# Logging is line-buffered and timestamped at the host as output arrives. The
# timestamp stays outside the structured PROBE payload, so existing parsers can
# continue to consume the captured raw probe output inside this script.
LOG="${ZKC_LOG:-./kimi-k3-debug.log}"
mkdir -p -- "$(dirname -- "$LOG")" || { echo "error: cannot create log directory" >&2; exit 2; }
: > "$LOG" || { echo "error: cannot create log $LOG" >&2; exit 2; }
chmod 600 "$LOG" 2>/dev/null || true
LOG_ABS="$(cd "$(dirname -- "$LOG")" && pwd)/$(basename -- "$LOG")"

timestamp_stream() {
  local line ts
  while IFS= read -r line || [[ -n "$line" ]]; do
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    printf '[%s] %s\n' "$ts" "$line"
  done
}

if [[ "$ZKC_LOG_TIMESTAMPS" == 1 ]]; then
  exec > >(timestamp_stream | tee -a -- "$LOG") 2>&1
else
  exec > >(tee -a -- "$LOG") 2>&1
fi
printf 'transcript: %s\n' "$LOG_ABS"
printf 'logging: timestamps=%s zone=UTC format=ISO-8601 run_id=%s pid=%s http_level=%s http_body_max=%s\n' \
  "$ZKC_LOG_TIMESTAMPS" "$RUN_ID" "$$" "$KIMI_HTTP_LOG_LEVEL" "$KIMI_HTTP_BODY_MAX"

ORG=(); [[ -n "${SPRITE_ORG:-}" ]] && ORG=(-o "$SPRITE_ORG")
step(){ printf '\n\033[1;36m=== %s\033[0m\n' "$*"; }
ok(){   printf '\033[1;32m  PASS\033[0m %s\n' "$*"; }
bad(){  printf '\033[1;31m  FAIL\033[0m %s\n' "$*"; }
note(){ printf '       %s\n' "$*"; }
sx(){ sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "$@" </dev/null; }

# SCAR: this function called `sprite api` and `sprite list` WITHOUT </dev/null.
# Those CLIs read stdin; with a terminal attached they block forever and print
# nothing - the run appeared to hang right after "=== 0. sprite". The sx()
# helper has closed stdin all along for exactly this reason; detection did not.
# Every call below is stdin-closed, time-bounded, and announced before it runs.
run_limited() {  # $1 seconds, rest: command. stdin closed, output on stdout.
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" </dev/null 2>/dev/null
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@" </dev/null 2>/dev/null
  else
    "$@" </dev/null 2>/dev/null
  fi
}

pick_sprite() {
  [[ -n "$SPRITE_NAME" ]] && { note "using SPRITE_NAME=$SPRITE_NAME from env"; return 0; }
  local names=() src="" ESC api_raw list_raw n
  ESC=$(printf '\033')

  # Two CLI calls total, both bounded. Parse the captured text three ways
  # rather than re-invoking the CLI per strategy.
  printf '       querying sprite api ... '
  api_raw=$(run_limited 20 sprite api "${ORG[@]}" /sprites || true)
  printf '%s\n' "$([ -n "$api_raw" ] && echo ok || echo 'no output')"
  printf '       querying sprite list ... '
  list_raw=$(run_limited 20 sprite list "${ORG[@]}" || true)
  printf '%s\n' "$([ -n "$list_raw" ] && echo ok || echo 'no output')"

  # 1. `sprite list` is authoritative because its rows contain sprites only.
  #    The /sprites API response may also contain an enclosing organization
  #    object with its own `name`; recursively collecting every `name` therefore
  #    misidentifies the organization as a sprite.
  #
  #    Box/ascii table. Box chars are substituted literally, never placed in a
  #    character class - a 3-byte UTF-8 char inside [...] makes sed match single
  #    BYTES and the pattern can never align. ESC comes from printf because
  #    \x1b is a GNU sed extension that BSD sed (macOS) rejects.
  if [[ -n "$list_raw" ]]; then
    while IFS= read -r n; do
      [[ "$n" == "NAME" || -z "$n" ]] && continue
      names+=("$n")
    done < <(printf '%s\n' "$list_raw" \
             | sed "s/${ESC}\[[0-9;]*[a-zA-Z]//g" \
             | grep -e '│' -e '|' \
             | sed 's/│/ /g; s/|/ /g' \
             | awk '$1 != "NAME" && $1 ~ /^[A-Za-z0-9]/ { print $1 }')
    ((${#names[@]})) && src="table"
  fi

  # 2. Bare name per line - what some CLI versions emit when stdout is a pipe.
  #    An organization summary such as `wen-pu-phua: 0 / 1 running ...` is not
  #    a bare name and is deliberately rejected by the whole-line expression.
  if ((${#names[@]} == 0)) && [[ -n "$list_raw" ]]; then
    while IFS= read -r n; do [[ -n "$n" ]] && names+=("$n"); done < <(
      printf '%s\n' "$list_raw" \
        | sed "s/${ESC}\[[0-9;]*[a-zA-Z]//g" \
        | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }' \
        | grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*$' \
        | grep -vxE 'NAME|STATUS|URL|CREATED|LAST|RUNNING|running|stopped|warm|cold|suspended|total')
    ((${#names[@]})) && src="plain"
  fi

  # 3. API JSON fallback. Inspect known sprite collections rather than walking
  #    every dictionary and accepting every `name`. This prevents an enclosing
  #    organization record from being presented as a sprite.
  if ((${#names[@]} == 0)) && [[ -n "$api_raw" ]]; then
    while IFS= read -r n; do [[ -n "$n" ]] && names+=("$n"); done < <(
      printf '%s' "$api_raw" | python3 -c '
import json, sys

try:
    document = json.load(sys.stdin)
except Exception:
    sys.exit(0)

out = []
seen = set()
sprite_hints = {
    "status", "state", "url", "hostname", "created", "created_at",
    "last_running", "last_running_at", "updated_at", "sprite_id", "id"
}

def emit(record):
    if not isinstance(record, dict):
        return
    name = record.get("name") or record.get("sprite_name")
    if isinstance(name, str) and name and name not in seen:
        seen.add(name)
        out.append(name)

def walk(value, sprite_collection=False):
    if isinstance(value, list):
        for item in value:
            walk(item, sprite_collection)
        return
    if not isinstance(value, dict):
        return

    # A record containing `sprites` is a container (often an organization),
    # never itself a sprite even when it also has a `name` field.
    if "sprites" in value:
        walk(value["sprites"], True)

    # Common response wrappers. Preserve whether the parent was already known
    # to be a sprite collection.
    for key in ("items", "results", "data"):
        if key in value:
            walk(value[key], sprite_collection)

    if "sprites" not in value:
        if sprite_collection or any(key in value for key in sprite_hints):
            emit(value)

walk(document)
for name in out:
    print(name)
' 2>/dev/null)
    ((${#names[@]})) && src="api"
  fi

  # 4. Never block the run - explain, then ask.
  if ((${#names[@]} == 0)); then
    c_warn_local "could not detect sprites automatically"
    [[ -n "$api_raw"  ]] && { echo "       api said:"; printf '%s\n' "$api_raw"  | head -4 | sed 's/^/         /'; }
    [[ -n "$list_raw" ]] && { echo "       list said:"; printf '%s\n' "$list_raw" | head -6 | sed 's/^/         /'; }
    [[ -z "$api_raw$list_raw" ]] && c_warn_local "both calls returned nothing - are you logged in? (sprite login)"
    c_warn_local "SPRITE_ORG is ${SPRITE_ORG:-<unset>}; some accounts need -o <org>"
    printf '  type the sprite name: '
    read -r SPRITE_NAME || { echo; c_die_local "no input (EOF) - use SPRITE_NAME=<name> bash $0"; }
    [[ "$SPRITE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || c_die_local "invalid sprite name"
    return 0
  fi

  if ((${#names[@]} == 1)); then
    SPRITE_NAME="${names[0]}"; note "one sprite (via $src): $SPRITE_NAME"; return 0
  fi
  echo "  sprites (via $src):"
  local i=1; for n in "${names[@]}"; do printf '    %d) %s\n' "$i" "$n"; i=$((i+1)); done
  local sel="" tries=0
  while (( tries < 5 )); do
    tries=$((tries+1))
    printf '  pick [1-%d] or type a name: ' "${#names[@]}"
    if ! read -r sel; then echo; c_die_local "no input (EOF) - use SPRITE_NAME=<name> bash $0"; fi
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#names[@]} )); then
      SPRITE_NAME="${names[$((sel-1))]}"; return 0
    elif [[ "$sel" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then SPRITE_NAME="$sel"; return 0; fi
    echo "  not a valid choice"
  done
  c_die_local "no valid selection after 5 attempts"
}
c_warn_local(){ printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
c_die_local(){ printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup_remote(){
  [[ -n "${SPRITE_NAME:-}" ]] || return 0
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME" -- bash -s -- "$RUN_ID" "$TASK_NAME" <<'ZKC_CLEANUP'
set -u
run_id="$1"; task="$2"
root="$HOME/.cache/zkc-kimi-k3/$run_id"
for f in keepawake.pid gateway.pid bridge.pid; do
  [ -f "$root/$f" ] || continue
  p=$(cat "$root/$f" 2>/dev/null || true)
  case "$p" in (*[!0-9]*|"") continue;; esac
  cmd=$(tr '\000' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)
  case "$cmd" in
    (*"$root/"*) kill -- "-$p" 2>/dev/null || kill "$p" 2>/dev/null || true;;
    (*) printf "       refusing to kill reused/unrelated pid %s\n" "$p" >&2;;
  esac
done
curl -sS --max-time 5 -X DELETE --unix-socket /.sprite/api.sock \
  "http://sprite/v1/tasks/$task" >/dev/null 2>&1 || true
rm -rf -- "$root"
ZKC_CLEANUP
}
CLEANED=0
finish_cleanup(){
  local rc=$?
  if [[ "$KEEP_BRIDGE" != 1 && "$CLEANED" != 1 ]]; then
    cleanup_remote >/dev/null 2>&1 || true
    CLEANED=1
  fi
  KIMI_KEY=""; unset KIMI_KEY 2>/dev/null || true
  return "$rc"
}
trap finish_cleanup EXIT
trap 'exit 130' INT TERM HUP

step "0. execution environment"
STDIN_OK=0
if (( NEED_SPRITE )); then
  pick_sprite
  run_limited 15 sprite api "${ORG[@]}" -s "$SPRITE_NAME" / >/dev/null \
    || note "could not query /v1/sprites/$SPRITE_NAME - continuing, exec will confirm"
  echo "zkc-kimi-k3-verify-v24.sh  $(date -u '+%FT%TZ')  sprite=$SPRITE_NAME  model=$MODEL  port=$PORT"
  sx -- bash -lc 'echo "  $(hostname) / $(whoami) / $HOME"' || { bad unreachable; exit 1; }
  [[ "$(printf p | sprite exec "${ORG[@]}" -s "$SPRITE_NAME" -- cat 2>/dev/null)" == *p* ]] && STDIN_OK=1
  note "remote API/client dependencies are isolated inside the selected Sprite"
else
  SPRITE_NAME=""
  echo "zkc-kimi-k3-verify-v24.sh  $(date -u '+%FT%TZ')  host_codex=1  model=$MODEL"
  note "Codex-only CC Switch mode does not require or contact a Sprite"
fi
echo "  context=$CONTEXT_WINDOW  Kimi default max_completion_tokens=$MODEL_DEFAULT_MAX_OUTPUT_TOKENS"
echo "  verifier output cap=$MAX_OUTPUT_TOKENS (routine low-quota default)"
echo "  reasoning probe cap=$REASONING_OUTPUT_TOKENS retry_cap=$REASONING_RETRY_OUTPUT_TOKENS"
if (( CODEX_USES_CC_SWITCH )); then
  echo "  anthropic probe cap=$ANTHROPIC_OUTPUT_TOKENS  web synthesis cap=$WEB_OUTPUT_TOKENS  codex output policy=managed by CC Switch"
else
  echo "  anthropic probe cap=$ANTHROPIC_OUTPUT_TOKENS  web synthesis cap=$WEB_OUTPUT_TOKENS  codeproxy Codex cap=$CLIENT_OUTPUT_TOKENS"
fi
echo "  codex reasoning summaries=$CODEX_REASONING_SUMMARIES (0 matches measured codeproxy behavior)"
echo "  codex effort simple=$CODEX_SIMPLE_REASONING_EFFORT complex=$CODEX_COMPLEX_REASONING_EFFORT"
echo "  codex_router=$CODEX_ROUTER  in_sprite_bridge_port=$PORT  mapped_model=$MODEL"
echo "  layers=$SELECTED_LAYERS  min_request_interval_ms=$KIMI_MIN_REQUEST_INTERVAL_MS  raw_http_retries=$KIMI_RATE_RETRIES"
echo "  engine_overload_retries=$KIMI_ENGINE_OVERLOAD_RETRIES  base_backoff_seconds=$KIMI_ENGINE_OVERLOAD_BASE_SECONDS"
echo "  tpd_action=$KIMI_TPD_ACTION  tpd_wait_max_seconds=$KIMI_TPD_WAIT_MAX_SECONDS  reset_timezone=$KIMI_RESET_TIMEZONE"
echo "  shared request-gateway max_concurrency=$KIMI_MAX_CONCURRENCY"
echo "  raw_anthropic_api_model=$ANTHROPIC_API_MODEL  claude_code_selector=$CLAUDE_MODEL"
if (( CODEX_USES_CC_SWITCH )); then
  note "CC Switch is explicit host-only compatibility mode; the default and full matrix use in-Sprite codeproxy"
fi
if (( L_PROTOCOL && L_ANTHROPIC && L_CODEX && L_CLAUDE )); then
  note "full matrix enabled: protocol, Anthropic, in-Sprite Codex, Claude Code, science, and long-context probes will run; web remains opt-in while upstream is being updated"
fi

run_remote(){  # $1 script, $2 optional non-secret env bundle
  local ef=(); [[ -n "${2:-}" ]] && ef=(--env "$2")
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "${ef[@]}" -- bash -lc "$1" </dev/null
}

send_secret(){  # $1 script, $2 optional non-secret env bundle
  ((STDIN_OK)) || { bad "sprite exec stdin transport is required; refusing to put the API key in argv"; return 77; }
  local ef=(); [[ -n "${2:-}" ]] && ef=(--env "$2")
  printf '%s\n' "$KIMI_KEY" | sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "${ef[@]}" -- bash -lc "$1"
}

layer_probe_names(){
  case "$1" in
    protocol) printf '%s\n' "P1-identity P2-tool P4-reasoning P4-source P4-preserve P4-enforce P4-visible P5-stream P3-parallel P6-webtool P7-websynth P8-webverify";;
    anthropic) printf '%s\n' "A1-identity A2-tool_use A3-parallel A4-stream A4-thinking";;
    codex) printf '%s\n' "C0-config C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve";;
    claude) printf '%s\n' "L1-shell L2-chained L3-parallel L4-create L5-edit L6-recover L7-websearch L8-science L9-reasoning L10-preserve";;
    *) return 2;;
  esac
}

skipped_layer_output(){
  local layer="$1" reason="layer not selected by ZKC_LAYERS=$SELECTED_LAYERS" n
  for n in $(layer_probe_names "$layer"); do
    printf '  %-14s %-7s %s\nPROBE|%s|SKIP|%s\n' "$n" SKIP "$reason" "$n" "$reason"
  done
}

complete_layer_output(){
  local layer="$1" enabled="$2" varname="$3" rc="${4:-0}" data n reason line extra=""
  data="${!varname:-}"
  [ "$enabled" = 1 ] || return 0
  if grep -qiE 'connection closed|broken pipe|connection reset|unexpected EOF|transport.*closed' <<<"$data"; then
    reason="layer transport closed before the probe reported a result"
  elif [ "$rc" -ne 0 ]; then
    reason="layer command exited $rc before the probe reported a result"
  else
    reason="selected layer ended without reporting this probe"
  fi
  for n in $(layer_probe_names "$layer"); do
    if ! grep -q "^PROBE|$n|" <<<"$data"; then
      printf -v line '  %-14s %-7s %s\nPROBE|%s|BLOCKED|%s' "$n" BLOCKED "$reason" "$n" "$reason"
      extra+="${extra:+$'\n'}$line"
    fi
  done
  if [ -n "$extra" ]; then
    printf '%s\n' "$extra" | tee /dev/stderr >/dev/null
    data+="${data:+$'\n'}$extra"
    printf -v "$varname" '%s' "$data"
  fi
}

# =============================================================== 2. PREPARE ==
IFS= read -r -d '' S_PREP <<'EOF' || true
set -uo pipefail
umask 077
# S_PREP must only ever execute inside the selected Sprite. Check before
# creating directories or invoking npm, even if someone extracts this block.
[ -S /.sprite/api.sock ] || {
  echo '       refusing prepare/install outside a Sprite runtime'
  exit 70
}
RUN_ID="${Z_RUN_ID:?}"; FORCE_INSTALL="${Z_FORCE_INSTALL:-0}"
NEED_CODEPROXY="${Z_NEED_CODEPROXY:-0}"; NEED_CODEX="${Z_NEED_CODEX:-0}"; NEED_CLAUDE="${Z_NEED_CLAUDE:-0}"
ROOT="$HOME/.cache/zkc-kimi-k3/$RUN_ID"
CODEX_HOME="$ROOT/codex-home"; WORK="$ROOT/probe"; CCFG="$ROOT/claude-config"
TMP="$ROOT/tmp"
mkdir -p "$CODEX_HOME" "$WORK" "$CCFG" "$TMP"
chmod 700 "$ROOT" "$CODEX_HOME" "$WORK" "$CCFG" "$TMP"

TOOL_ROOT="$HOME/.local/share/zkc-kimi-k3-tools"
TOOL_PREFIX="$TOOL_ROOT/npm"
TOOL_BIN="$TOOL_PREFIX/node_modules/.bin"
mkdir -p "$TOOL_ROOT/bin" "$TOOL_PREFIX"
chmod 700 "$TOOL_ROOT" "$TOOL_ROOT/bin" "$TOOL_PREFIX"
export PATH="$TOOL_ROOT/bin:$TOOL_BIN:$PATH"

# Resolve a codeproxy launcher. Some npm releases install a normal .bin link;
# others are most reliably launched through their built dist/cli entry point.
resolve_codeproxy() {
  local c entry nodebin wrapper
  for c in "$TOOL_BIN/codeproxy" "$TOOL_BIN/codeproxy-cli"; do
    [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  for entry in \
      "$TOOL_PREFIX/node_modules/@codeproxy/cli/dist/cli.js" \
      "$TOOL_PREFIX/node_modules/@codeproxy/cli/dist/cli.mjs" \
      "$TOOL_PREFIX/node_modules/@codeproxy/cli/dist/cli.cjs"; do
    [ -f "$entry" ] || continue
    nodebin=$(command -v node) || return 1
    wrapper="$TOOL_ROOT/bin/codeproxy"
    printf '#!/usr/bin/env bash\nexec %q %q "$@"\n' "$nodebin" "$entry" > "$wrapper"
    chmod 700 "$wrapper"
    printf '%s\n' "$wrapper"
    return 0
  done
  c=$(command -v codeproxy 2>/dev/null || true)
  [ -n "$c" ] && { printf '%s\n' "$c"; return 0; }
  return 1
}

CODEX_BIN=$(command -v codex 2>/dev/null || true)
CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
CODEPROXY_BIN=$(resolve_codeproxy 2>/dev/null || true)
need_install=0
[ "$NEED_CODEX" = 0 ] || { [ -n "$CODEX_BIN" ] && "$CODEX_BIN" --version >/dev/null 2>&1 || need_install=1; }
[ "$NEED_CLAUDE" = 0 ] || { [ -n "$CLAUDE_BIN" ] && "$CLAUDE_BIN" --version >/dev/null 2>&1 || need_install=1; }
[ "$NEED_CODEPROXY" = 0 ] || { [ -n "$CODEPROXY_BIN" ] && "$CODEPROXY_BIN" --help >/dev/null 2>&1 || need_install=1; }
[ "$FORCE_INSTALL" = 0 ] || { [ "$NEED_CODEX$NEED_CLAUDE$NEED_CODEPROXY" = 000 ] || need_install=1; }

if [ "$need_install" = 1 ]; then
  command -v npm >/dev/null 2>&1 || {
    echo '       npm is required inside the Sprite for the selected client/bridge layer'
    exit 69
  }
  packages=()
  [ "$NEED_CODEPROXY" = 0 ] || packages+=("@codeproxy/cli@$Z_CODEPROXY_VERSION")
  [ "$NEED_CODEX" = 0 ] || packages+=("@openai/codex@$Z_CODEX_VERSION")
  [ "$NEED_CLAUDE" = 0 ] || packages+=("@anthropic-ai/claude-code@$Z_CLAUDE_VERSION")
  echo "       installing selected CLI dependencies INSIDE sprite $(hostname)"
  echo "       persistent prefix: $TOOL_PREFIX"
  printf '       packages:'; printf ' %s' "${packages[@]}"; echo
  # Explicitly include optional dependencies and allow lifecycle scripts. Newer
  # Claude Code packages use an optional platform-native package plus install.cjs.
  if ! env npm_config_ignore_scripts=false npm_config_omit= \
      npm install --prefix "$TOOL_PREFIX" --include=optional --ignore-scripts=false \
        --no-audit --no-fund --loglevel=error "${packages[@]}"; then
    echo '       npm installation failed inside the Sprite'
    exit 69
  fi
  hash -r
  export PATH="$TOOL_ROOT/bin:$TOOL_BIN:$PATH"
fi

CODEX_BIN="$TOOL_BIN/codex"
[ -x "$CODEX_BIN" ] || CODEX_BIN=$(command -v codex 2>/dev/null || true)
CLAUDE_BIN="$TOOL_BIN/claude"
[ -x "$CLAUDE_BIN" ] || CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
CODEPROXY_BIN=$(resolve_codeproxy 2>/dev/null || true)

# Claude's wrapper can exist even when its native optional package or generated
# bin/claude.exe is absent. Run the package installer once, then explicitly add
# the current platform package if the first repair did not succeed.
if [ "$NEED_CLAUDE" = 1 ] && [ -n "$CLAUDE_BIN" ] && ! "$CLAUDE_BIN" --version >/dev/null 2>&1; then
  CLAUDE_PKG="$TOOL_PREFIX/node_modules/@anthropic-ai/claude-code"
  [ -f "$CLAUDE_PKG/install.cjs" ] && node "$CLAUDE_PKG/install.cjs" >/dev/null 2>&1 || true
fi
if [ "$NEED_CLAUDE" = 1 ] && [ -n "$CLAUDE_BIN" ] && ! "$CLAUDE_BIN" --version >/dev/null 2>&1; then
  PLATFORM_PKG=$(node - <<'NODE' 2>/dev/null || true
const p = process.platform;
const a = process.arch;
let suffix = `${p}-${a}`;
if (p === 'linux') {
  let musl = false;
  try { musl = !process.report.getReport().header.glibcVersionRuntime; } catch (_) {}
  if (musl) suffix += '-musl';
}
process.stdout.write(`@anthropic-ai/claude-code-${suffix}`);
NODE
)
  if [ -n "$PLATFORM_PKG" ]; then
    env npm_config_ignore_scripts=false npm_config_omit= \
      npm install --prefix "$TOOL_PREFIX" --include=optional --ignore-scripts=false \
        --no-audit --no-fund --loglevel=error \
        "$PLATFORM_PKG@$Z_CLAUDE_VERSION" >/dev/null 2>&1 || true
    [ -f "$TOOL_PREFIX/node_modules/@anthropic-ai/claude-code/install.cjs" ] && \
      node "$TOOL_PREFIX/node_modules/@anthropic-ai/claude-code/install.cjs" >/dev/null 2>&1 || true
  fi
fi

if [ "$NEED_CODEX" = 1 ]; then
  [ -n "$CODEX_BIN" ] && "$CODEX_BIN" --version >/dev/null 2>&1 || {
    echo '       codex launcher is missing or not executable after install'; exit 69;
  }
fi
if [ "$NEED_CLAUDE" = 1 ]; then
  [ -n "$CLAUDE_BIN" ] && "$CLAUDE_BIN" --version >/dev/null 2>&1 || {
    echo '       claude launcher is missing or its native platform package was not installed';
    echo "       inspected prefix: $TOOL_PREFIX"; exit 69;
  }
fi
if [ "$NEED_CODEPROXY" = 1 ]; then
  [ -n "$CODEPROXY_BIN" ] && "$CODEPROXY_BIN" --help >/dev/null 2>&1 || {
    echo '       codeproxy launcher is missing or not executable after install';
    echo "       inspected prefix: $TOOL_PREFIX"; exit 69;
  }
fi
{
  printf 'export ZKC_ROOT=%q\n' "$ROOT"
  printf 'export ZKC_WORK=%q\n' "$WORK"
  printf 'export ZKC_TMP=%q\n' "$TMP"
  printf 'export CODEX_HOME=%q\n' "$CODEX_HOME"
  printf 'export CLAUDE_CONFIG_DIR=%q\n' "$CCFG"
  printf 'export CODEX_BIN=%q\n' "$CODEX_BIN"
  printf 'export CLAUDE_BIN=%q\n' "$CLAUDE_BIN"
  printf 'export CODEPROXY_BIN=%q\n' "$CODEPROXY_BIN"
  printf 'export PATH=%q\n' "$PATH"
} > "$ROOT/runtime.env"
chmod 600 "$ROOT/runtime.env"

cat > "$CODEX_HOME/config.toml" <<T
approval_policy = "never"
sandbox_mode = "danger-full-access"
model_reasoning_effort = "high"

[shell_environment_policy]
inherit = "core"
ignore_default_excludes = false

[shell_environment_policy.filters]
"MOONSHOT_*" = "exclude"
"ANTHROPIC_*" = "exclude"
"*_API_KEY" = "exclude"
"*_AUTH_TOKEN" = "exclude"

[projects."$WORK"]
trust_level = "trusted"
T
chmod 600 "$CODEX_HOME/config.toml"
cd "$WORK"; git init -q 2>/dev/null || true
cat > "$WORK/science_harness.py" <<'PYSCI'
#!/usr/bin/env python3
import ast, json, math, os, resource, shutil, subprocess, sys
from pathlib import Path

R = 8.31446261815324
CASE = {
    "experiment": "Arrhenius ordinary-least-squares fit",
    "gas_constant_j_mol_k": R,
    "temperatures_k": [285.0, 300.0, 315.0, 330.0, 345.0],
    "rate_constants_s_inv": [
        0.011204416921085876,
        0.05720624134071952,
        0.26148299964068195,
        1.005002582207556,
        3.5322902035803665
    ],
    "prediction_temperature_k": 325.0,
    "bateman_chain": {
        "parent_half_life_h": 9.0,
        "daughter_half_life_h": 3.0,
        "initial_parent_atoms": 2500000000000.0
    }
}

PROMPT = """You are being evaluated on reproducible scientific reasoning, not prose.
Read science_case.json. Treat the data as a first-order reaction obeying
ln(k) = ln(A) - Ea/(R*T). Fit y=ln(k) against x=1/T by ordinary least squares
using all points. Then predict k and the half-life ln(2)/k at the requested
temperature. Also solve the consecutive decay chain P -> D -> stable using the
Bateman equations. Initially there are only parent atoms. Calculate the time of
maximum daughter population, the parent, daughter, and stable populations at
that time, the daughter activity in Bq, and the relative mass-balance residual.

Requirements:
1. Use Python for the numerical calculation; do not estimate by eye.
2. Write an executable science_calc.py that reads science_case.json and writes
   science_result.json. Run it before finishing.
3. science_result.json must contain numeric fields slope_k, intercept,
   activation_energy_j_mol, preexponential_s_inv, r_squared,
   predicted_k_s_inv, half_life_s, daughter_peak_time_h,
   parent_atoms_at_peak, daughter_atoms_at_peak, stable_atoms_at_peak,
   daughter_activity_bq_at_peak, mass_balance_relative_error; and string fields
   method, derivation, dimensional_check, bateman_derivation,
   bateman_dimensional_check.
4. Explain in derivation why Ea=-slope*R and why the first-order half-life
   formula applies.
5. Derive the Bateman peak condition dN_D/dt=0, show the peak-time formula,
   and explain the hour-to-second conversion used for activity in Bq.
6. Do not modify science_case.json.
"""

NUMERIC = (
    "slope_k", "intercept", "activation_energy_j_mol",
    "preexponential_s_inv", "r_squared", "predicted_k_s_inv", "half_life_s",
    "daughter_peak_time_h", "parent_atoms_at_peak", "daughter_atoms_at_peak",
    "stable_atoms_at_peak", "daughter_activity_bq_at_peak",
    "mass_balance_relative_error"
)

def expected(case):
    ts=case["temperatures_k"]; ks=case["rate_constants_s_inv"]
    x=[1.0/t for t in ts]; y=[math.log(k) for k in ks]
    mx=sum(x)/len(x); my=sum(y)/len(y)
    slope=sum((a-mx)*(b-my) for a,b in zip(x,y))/sum((a-mx)**2 for a in x)
    intercept=my-slope*mx
    ea=-slope*case["gas_constant_j_mol_k"]
    pre=math.exp(intercept)
    fit=[intercept+slope*a for a in x]
    ss_res=sum((b-f)**2 for b,f in zip(y,fit))
    ss_tot=sum((b-my)**2 for b in y)
    r2=1.0-ss_res/ss_tot
    tp=case["prediction_temperature_k"]
    kp=pre*math.exp(-ea/(case["gas_constant_j_mol_k"]*tp))
    chain=case["bateman_chain"]
    hp=chain["parent_half_life_h"]; hd=chain["daughter_half_life_h"]
    n0=chain["initial_parent_atoms"]
    lp=math.log(2.0)/hp; ld=math.log(2.0)/hd
    tpeak=math.log(ld/lp)/(ld-lp)
    np_=n0*math.exp(-lp*tpeak)
    nd=n0*lp/(ld-lp)*(math.exp(-lp*tpeak)-math.exp(-ld*tpeak))
    ns=n0-np_-nd
    activity=(ld/3600.0)*nd
    balance=abs((np_+nd+ns)-n0)/n0
    return {
        "slope_k":slope, "intercept":intercept,
        "activation_energy_j_mol":ea, "preexponential_s_inv":pre,
        "r_squared":r2, "predicted_k_s_inv":kp,
        "half_life_s":math.log(2.0)/kp,
        "daughter_peak_time_h":tpeak,
        "parent_atoms_at_peak":np_, "daughter_atoms_at_peak":nd,
        "stable_atoms_at_peak":ns,
        "daughter_activity_bq_at_peak":activity,
        "mass_balance_relative_error":balance
    }

def prepare(folder):
    d=Path(folder); d.mkdir(parents=True,exist_ok=True)
    (d/"science_case.json").write_text(json.dumps(CASE,indent=2)+"\n")
    (d/"science_prompt.txt").write_text(PROMPT+"\n")

def close(got,want,rel=5e-3,abs_=1e-8):
    return abs(got-want)<=max(abs_,rel*max(abs(want),1.0))

def assess(got, exp, include_text=True, label="case"):
    bad=[]
    for key in NUMERIC:
        try: value=float(got[key])
        except Exception: bad.append(label+":"+key+":missing/non-numeric"); continue
        if key == "mass_balance_relative_error":
            if value < 0 or value > 1e-10:
                bad.append("%s:%s got=%g expected<=1e-10"%(label,key,value))
            continue
        rel=1e-5 if key in ("slope_k","intercept","r_squared","daughter_peak_time_h") else 5e-3
        if not close(value,exp[key],rel=rel):
            bad.append("%s:%s got=%g expected=%g"%(label,key,value,exp[key]))
    if include_text:
        for key in ("method","derivation","dimensional_check",
                    "bateman_derivation","bateman_dimensional_check"):
            if not isinstance(got.get(key),str) or len(got[key].strip())<20:
                bad.append(key+":too short")
        text={k:str(got.get(k,"")).lower() for k in
              ("method","derivation","dimensional_check",
               "bateman_derivation","bateman_dimensional_check")}
        if "least" not in text["method"] or "bateman" not in text["method"]:
            bad.append("method:must identify least-squares and Bateman methods")
        if not all(x in text["derivation"] for x in ("slope","half")) or not (
                "ea" in text["derivation"] or "activation" in text["derivation"]):
            bad.append("derivation:must connect slope, Ea, and half-life")
        if not all(x in text["dimensional_check"] for x in ("mol","s")):
            bad.append("dimensional_check:must discuss molar-energy and time units")
        if "peak" not in text["bateman_derivation"] or not (
                "lambda" in text["bateman_derivation"] or "decay" in text["bateman_derivation"]):
            bad.append("bateman_derivation:must state peak/decay-constant condition")
        if "3600" not in text["bateman_dimensional_check"] or "bq" not in text["bateman_dimensional_check"]:
            bad.append("bateman_dimensional_check:must explain 3600 s/h and Bq")
    return bad

def vet_calc(calc):
    tree=ast.parse(calc.read_text(), filename=str(calc))
    allowed={"json","math","pathlib","statistics","sys"}
    denied_calls={"eval","exec","compile","__import__","breakpoint","input"}
    denied_attrs={"system","popen","spawn","fork","execv","execve","socket","urlopen","request"}
    for node in ast.walk(tree):
        if isinstance(node,ast.Import):
            for alias in node.names:
                if alias.name.split('.')[0] not in allowed:
                    raise ValueError("disallowed import: "+alias.name)
        elif isinstance(node,ast.ImportFrom):
            if (node.module or '').split('.')[0] not in allowed:
                raise ValueError("disallowed import-from: "+str(node.module))
        elif isinstance(node,ast.Call):
            if isinstance(node.func,ast.Name) and node.func.id in denied_calls:
                raise ValueError("disallowed call: "+node.func.id)
            if isinstance(node.func,ast.Attribute) and node.func.attr in denied_attrs:
                raise ValueError("disallowed attribute call: "+node.func.attr)

def _limits():
    resource.setrlimit(resource.RLIMIT_CPU,(12,12))
    resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024*1024,16*1024*1024))
    resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))
    try: resource.setrlimit(resource.RLIMIT_NPROC,(16,16))
    except Exception: pass
    try: resource.setrlimit(resource.RLIMIT_AS,(768*1024*1024,768*1024*1024))
    except Exception: pass

def run_calc(d, calc, result):
    vet_calc(calc)
    runner=[sys.executable,"-I","-S",str(calc)]
    if shutil.which("unshare"):
        try:
            ok=subprocess.run(["unshare","-n","true"],stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL,timeout=2).returncode==0
            if ok: runner=["unshare","-n","--"]+runner
        except Exception: pass
    safe_env={"PATH":os.environ.get("PATH","/usr/bin:/bin"),"HOME":str(d),
              "LANG":"C.UTF-8","LC_ALL":"C.UTF-8","PYTHONNOUSERSITE":"1"}
    subprocess.run(runner,cwd=d,check=True,env=safe_env,preexec_fn=_limits,
                   stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
    return json.loads(result.read_text())

def validate(folder):
    d=Path(folder); calc=d/"science_calc.py"; result=d/"science_result.json"
    case_path=d/"science_case.json"
    if not calc.exists() or not result.exists() or not case_path.exists():
        print("missing science_calc.py, science_result.json, or science_case.json"); return 2
    original=json.loads(case_path.read_text())
    bad=[]
    try:
        got=run_calc(d,calc,result)
        if json.loads(case_path.read_text()) != original:
            bad.append("science_calc.py modified science_case.json")
        exp=expected(original)
        bad.extend(assess(got,exp,include_text=True,label="original"))

        # Generalization control: mutate several physical inputs and rerun the
        # submitted program. A hard-coded answer can pass one fixture; it cannot
        # pass this unseen perturbation while preserving the required interface.
        perturbed=json.loads(json.dumps(original))
        perturbed["rate_constants_s_inv"][2] *= 1.037
        perturbed["prediction_temperature_k"] = 323.0
        perturbed["bateman_chain"]["parent_half_life_h"] = 8.5
        perturbed["bateman_chain"]["daughter_half_life_h"] = 2.8
        perturbed["bateman_chain"]["initial_parent_atoms"] = 2.7e12
        case_path.write_text(json.dumps(perturbed,indent=2)+"\n")
        got2=run_calc(d,calc,result)
        if json.loads(case_path.read_text()) != perturbed:
            bad.append("science_calc.py modified perturbed science_case.json")
        exp2=expected(perturbed)
        bad.extend(assess(got2,exp2,include_text=False,label="perturbed"))
        try:
            if close(float(got2["predicted_k_s_inv"]),float(got["predicted_k_s_inv"]),rel=1e-8):
                bad.append("perturbation did not change predicted_k_s_inv; result may be hard-coded")
            if close(float(got2["daughter_peak_time_h"]),float(got["daughter_peak_time_h"]),rel=1e-8):
                bad.append("perturbation did not change daughter_peak_time_h; result may be hard-coded")
        except Exception:
            pass
    except Exception as e:
        print("calculation is not reproducible: %s"%e); return 3
    finally:
        # Restore the supplied fixture and leave science_result.json consistent
        # with it for inspection after the verifier finishes.
        try:
            case_path.write_text(json.dumps(original,indent=2)+"\n")
            if calc.exists(): run_calc(d,calc,result)
        except Exception:
            pass
    if bad:
        print("; ".join(bad)); return 5
    print("validated original + perturbed cases: Ea=%.3f J/mol, R2=%.8f, "
          "k(325K)=%.8g s^-1; Bateman peak=%.6f h, daughter activity=%.8g Bq"%
          (exp["activation_energy_j_mol"],exp["r_squared"],exp["predicted_k_s_inv"],
           exp["daughter_peak_time_h"],exp["daughter_activity_bq_at_peak"]))
    return 0

if __name__=="__main__":
    if len(sys.argv)!=3 or sys.argv[1] not in ("prepare","validate"):
        raise SystemExit("usage: science_harness.py prepare|validate DIR")
    if sys.argv[1]=="prepare":
        prepare(sys.argv[2]); raise SystemExit(0)
    raise SystemExit(validate(sys.argv[2]))
PYSCI
chmod 700 "$WORK/science_harness.py"
echo "       workspace $WORK ready"
echo "       selected dependencies: codeproxy=$NEED_CODEPROXY codex=$NEED_CODEX claude=$NEED_CLAUDE"
[ "$NEED_CODEX" = 0 ] || echo "       codex $($CODEX_BIN --version 2>/dev/null || echo MISSING)"
[ "$NEED_CLAUDE" = 0 ] || echo "       claude $($CLAUDE_BIN --version 2>/dev/null || echo MISSING)"
[ "$NEED_CODEPROXY" = 0 ] || echo "       codeproxy=$CODEPROXY_BIN"
EOF
step "1. prepare"
if (( NEED_SPRITE )); then
  run_remote "$S_PREP" "Z_RUN_ID=$RUN_ID,Z_FORCE_INSTALL=$ZKC_FORCE_INSTALL,Z_NEED_CODEPROXY=$REMOTE_NEED_CODEPROXY,Z_NEED_CODEX=$REMOTE_NEED_CODEX,Z_NEED_CLAUDE=$L_CLAUDE,Z_CODEPROXY_VERSION=$CODEPROXY_VERSION,Z_CODEX_VERSION=$CODEX_VERSION,Z_CLAUDE_VERSION=$CLAUDE_CODE_VERSION"
  PREP_RC=$?
  if (( PREP_RC != 0 )); then
    bad "prepare failed (exit $PREP_RC)"
    note "installation was attempted only inside sprite $SPRITE_NAME"
    note "the Sprite needs npm/network access for its persistent user-local CLI toolchain"
    exit "$PREP_RC"
  fi
else
  note "skipped; host Codex and CC Switch are managed outside the verifier"
fi

step "2. Kimi API key"
KIMI_KEY=""
if (( NEED_API_KEY )); then
  ((STDIN_OK)) || { bad "sprite exec cannot carry stdin securely; aborting before reading a key"; exit 1; }
  printf '  key (sk-...), hidden: '; read -rs KIMI_KEY || true; echo
  [[ "$KIMI_KEY" =~ ^sk-[A-Za-z0-9._-]{8,}$ ]] || { bad "invalid or unsafe key format"; exit 1; }
  ok captured
else
  note "not requested; CC Switch owns the Kimi key for host-routed Codex"
fi

# ================================================== 3. BRIDGE + KEEP-AWAKE ==
IFS= read -r -d '' S_BRIDGE <<'EOF' || true
set -uo pipefail
umask 077
IFS= read -r K || true; [ -n "${K:-}" ] || { echo '       no key'; exit 1; }
RUN_ID="${Z_RUN_ID:?}"; ROOT="$HOME/.cache/zkc-kimi-k3/$RUN_ID"
. "$ROOT/runtime.env"
PORT="${B_PORT:?}"; MODEL="${B_MODEL:?}"; CONTEXT="${B_CONTEXT:?}"
GATEWAY_PORT="${B_GATEWAY_PORT:-8790}"; GATEWAY_SPAN="${B_GATEWAY_SPAN:-100}"
START_BRIDGE="${B_START_BRIDGE:-1}"
MAXOUT="${B_MAXOUT:?}"; WEB_NATIVE="${B_WEB_NATIVE:-0}"; REASONING_SUMMARIES="${B_REASONING_SUMMARIES:-0}"
TIMEOUT="${B_TIMEOUT:-300}"; TASK="${Z_TASK:?}"; KEEP_BRIDGE_REMOTE="${B_KEEP_BRIDGE:-0}"
PORT_SPAN="${B_PORT_SPAN:-100}"; PORT_STRICT="${B_PORT_STRICT:-0}"
MIN_INTERVAL_MS="${B_MIN_INTERVAL_MS:-3200}"; MAX_CONCURRENCY="${B_MAX_CONCURRENCY:-1}"

sapi(){ curl -sS --fail --max-time 5 --unix-socket /.sprite/api.sock -H 'Content-Type: application/json' "$@"; }

# A prior verifier run may have left codeproxy alive if its cleanup was
# interrupted. Stop only processes whose argv contains both codeproxy and a
# zkc-kimi-k3 run directory. Never kill an unrelated listener.
for proc in /proc/[0-9]*/cmdline; do
  [ -r "$proc" ] || continue
  pid="${proc#/proc/}"; pid="${pid%/cmdline}"
  [ "$pid" = "$$" ] && continue
  cmd=$(tr '\000' ' ' < "$proc" 2>/dev/null || true)
  case "$cmd" in
    (*codeproxy*".cache/zkc-kimi-k3/"*)
      if kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null; then
        echo "       stopped stale verifier bridge pid=$pid"
      fi
      ;;
  esac
done
sleep 1

port_open(){
  python3 - "$1" <<'PORTPY'
import socket, sys
port=int(sys.argv[1])
s=socket.socket()
s.settimeout(0.25)
try:
    used=(s.connect_ex(("127.0.0.1", port)) == 0)
finally:
    s.close()
raise SystemExit(0 if used else 1)
PORTPY
}

REQUESTED_PORT="$PORT"
if port_open "$PORT"; then
  if [ "$PORT_STRICT" = 1 ]; then
    echo "       requested port $PORT is occupied and BRIDGE_PORT_STRICT=1"
    exit 73
  fi
  found=""
  last=$((PORT + PORT_SPAN))
  [ "$last" -le 65535 ] || last=65535
  candidate=$((PORT + 1))
  while [ "$candidate" -le "$last" ]; do
    if ! port_open "$candidate"; then found="$candidate"; break; fi
    candidate=$((candidate + 1))
  done
  [ -n "$found" ] || {
    echo "       no free loopback port in range $PORT-$last"
    exit 73
  }
  PORT="$found"
  echo "       requested port $REQUESTED_PORT is occupied; using free port $PORT"
fi
printf '%s
' "$PORT" > "$ROOT/bridge.port"
GATEWAY_REQUESTED="$GATEWAY_PORT"
if port_open "$GATEWAY_PORT"; then
  found=""; last=$((GATEWAY_PORT + GATEWAY_SPAN)); [ "$last" -le 65535 ] || last=65535
  candidate=$((GATEWAY_PORT + 1))
  while [ "$candidate" -le "$last" ]; do
    if ! port_open "$candidate"; then found="$candidate"; break; fi
    candidate=$((candidate + 1))
  done
  [ -n "$found" ] || { echo "       no free gateway port in range $GATEWAY_PORT-$last"; exit 73; }
  GATEWAY_PORT="$found"
  echo "       requested pacing-gateway port $GATEWAY_REQUESTED is occupied; using $GATEWAY_PORT"
fi
printf '%s
' "$GATEWAY_PORT" > "$ROOT/gateway.port"
# The documented Tasks API accepts an upsert at PUT /v1/tasks with the name in
# the JSON body. Verify the exact task with GET /v1/tasks/:name so a formatting
# change in the list endpoint cannot create a false negative.
TASK_HTTP=$(curl -sS --max-time 5 --unix-socket /.sprite/api.sock \
  -H 'Content-Type: application/json' -o "$ROOT/task-upsert.json" -w '%{http_code}' \
  -X PUT http://sprite/v1/tasks \
  -d "{\"name\":\"$TASK\",\"expire\":\"5m\"}" 2>/dev/null || true)
[ -n "$TASK_HTTP" ] || TASK_HTTP=000
TASK_ONE=$(sapi "http://sprite/v1/tasks/$TASK" 2>/dev/null || true)
TASK_MATCH=$(printf '%s' "$TASK_ONE" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(1)
want=sys.argv[1]
raise SystemExit(0 if isinstance(d,dict) and d.get("name")==want and d.get("expires_at") else 1)
' "$TASK" 2>/dev/null && echo yes || echo no)
if [ "$TASK_HTTP" = 200 ] && [ "$TASK_MATCH" = yes ]; then
  echo "       keep-awake VERIFIED: $(printf '%s' "$TASK_ONE" | head -c 200)"
else
  echo "       keep-awake NOT CONFIRMED (upsert_http=$TASK_HTTP)"
  [ -s "$ROOT/task-upsert.json" ] && head -c 200 "$ROOT/task-upsert.json" | sed 's/^/         /'
  echo
fi
rm -f "$ROOT/task-upsert.json"

MAXSEC="${KEEP_MAX:-7200}"; DEADLINE=$(( $(date +%s) + MAXSEC ))
cat > "$ROOT/keepawake.sh" <<'HBEOF'
#!/usr/bin/env bash
set -u
DEADLINE="$1"; TASK="$2"
sapi(){ curl -sS --fail --max-time 5 --unix-socket /.sprite/api.sock -H 'Content-Type: application/json' "$@"; }
release(){ sapi -X DELETE "http://sprite/v1/tasks/$TASK" >/dev/null 2>&1 || true; }
trap 'release; exit 0' EXIT INT TERM
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sapi -X PUT "http://sprite/v1/tasks/$TASK" -d '{"expire":"5m"}' >/dev/null 2>&1 || true
  for _ in $(seq 1 12); do
    [ "$(date +%s)" -lt "$DEADLINE" ] || break
    sleep 5 & wait $!
  done
done
HBEOF
chmod 700 "$ROOT/keepawake.sh"
setsid bash "$ROOT/keepawake.sh" "$DEADLINE" "$TASK" >"$ROOT/keepawake.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$ROOT/keepawake.pid"

cat > "$ROOT/pacing_gateway.py" <<'PYGATE'
#!/usr/bin/env python3
import hashlib, http.client, json, os, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT=int(os.environ["Z_GATEWAY_PORT"])
MIN_INTERVAL=float(os.environ.get("Z_MIN_INTERVAL_MS","3200"))/1000.0
MAX_CONCURRENCY=max(1,int(os.environ.get("Z_MAX_CONCURRENCY","1")))
TRACE=os.environ["Z_GATEWAY_TRACE"]
TIMEOUT=int(os.environ.get("Z_GATEWAY_TIMEOUT","300"))
pace_lock=threading.Lock(); trace_lock=threading.Lock(); last_start=0.0; seq=0
sem=threading.BoundedSemaphore(MAX_CONCURRENCY)

def digest(value):
    return hashlib.sha256(value.encode("utf-8","replace")).hexdigest()

def analyze_request(data):
    out={"assistant_messages":0,"assistant_reasoning_hashes":[],"assistant_thinking_hashes":[]}
    try: doc=json.loads(data.decode("utf-8"))
    except Exception: return out
    messages=doc.get("messages") if isinstance(doc,dict) else None
    if not isinstance(messages,list): return out
    for msg in messages:
        if not isinstance(msg,dict) or msg.get("role")!="assistant": continue
        out["assistant_messages"]+=1
        rc=msg.get("reasoning_content")
        if isinstance(rc,str) and rc: out["assistant_reasoning_hashes"].append(digest(rc))
        content=msg.get("content")
        if isinstance(content,list):
            for block in content:
                if not isinstance(block,dict) or block.get("type") not in ("thinking","redacted_thinking"): continue
                value=block.get("thinking") or block.get("text") or block.get("data")
                if isinstance(value,str) and value: out["assistant_thinking_hashes"].append(digest(value))
    return out

def analyze_response(raw, content_type):
    reasoning=[]; thinking=[]
    if "text/event-stream" in (content_type or ""):
        rparts=[]; tparts=[]
        for line in raw.decode("utf-8","replace").splitlines():
            if not line.startswith("data:"): continue
            payload=line[5:].strip()
            if not payload or payload=="[DONE]": continue
            try: ev=json.loads(payload)
            except Exception: continue
            try:
                delta=ev.get("choices",[{}])[0].get("delta") or {}
                if isinstance(delta.get("reasoning_content"),str): rparts.append(delta["reasoning_content"])
            except Exception: pass
            d=ev.get("delta") if isinstance(ev,dict) else None
            if isinstance(d,dict) and d.get("type")=="thinking_delta" and isinstance(d.get("thinking"),str): tparts.append(d["thinking"])
        if rparts: reasoning.append("".join(rparts))
        if tparts: thinking.append("".join(tparts))
    else:
        try: doc=json.loads(raw.decode("utf-8","replace"))
        except Exception: doc={}
        if isinstance(doc,dict):
            try:
                msg=doc["choices"][0]["message"]
                rc=msg.get("reasoning_content") if isinstance(msg,dict) else None
                if isinstance(rc,str) and rc: reasoning.append(rc)
            except Exception: pass
            content=doc.get("content")
            if isinstance(content,list):
                for block in content:
                    if isinstance(block,dict) and block.get("type") in ("thinking","redacted_thinking"):
                        value=block.get("thinking") or block.get("text") or block.get("data")
                        if isinstance(value,str) and value: thinking.append(value)
    return {"response_reasoning_hashes":[digest(x) for x in reasoning if x],
            "response_thinking_hashes":[digest(x) for x in thinking if x]}

def trace(record):
    global seq
    with trace_lock:
        seq+=1; record["seq"]=seq
        with open(TRACE,"a",encoding="utf-8") as f:
            f.write(json.dumps(record,separators=(",",":"),sort_keys=True)+"\n")

class Handler(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.0"
    def log_message(self,*args): pass
    def do_GET(self): self.forward()
    def do_POST(self): self.forward()
    def do_PUT(self): self.forward()
    def do_DELETE(self): self.forward()
    def forward(self):
        global last_start
        if self.path=="/__zkc_health":
            self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(b'{"ok":true}'); return
        n=int(self.headers.get("Content-Length") or 0); body=self.rfile.read(n) if n else b""
        request_meta=analyze_request(body)
        with sem:
            with pace_lock:
                now=time.monotonic(); wait=last_start+MIN_INTERVAL-now
                if wait>0: time.sleep(wait)
                last_start=time.monotonic(); started=last_start
            headers={k:v for k,v in self.headers.items() if k.lower() not in {"host","connection","content-length","accept-encoding","transfer-encoding"}}
            headers["Host"]="api.moonshot.ai"; headers["Accept-Encoding"]="identity"
            conn=http.client.HTTPSConnection("api.moonshot.ai",443,timeout=TIMEOUT)
            raw=bytearray(); status=502; ctype=""
            try:
                conn.request(self.command,self.path,body=body if body else None,headers=headers)
                resp=conn.getresponse(); status=resp.status; ctype=resp.getheader("Content-Type") or ""
                self.send_response(status)
                for k,v in resp.getheaders():
                    if k.lower() in {"transfer-encoding","content-length","connection","keep-alive"}: continue
                    self.send_header(k,v)
                self.send_header("Connection","close"); self.end_headers()
                while True:
                    chunk=resp.read(65536)
                    if not chunk: break
                    if len(raw)<64*1024*1024: raw.extend(chunk[:64*1024*1024-len(raw)])
                    self.wfile.write(chunk); self.wfile.flush()
            except Exception as exc:
                try:
                    self.send_response(502); self.send_header("Content-Type","application/json"); self.end_headers()
                    self.wfile.write(json.dumps({"error":{"type":"gateway_transport_error","message":str(exc)}}).encode())
                except Exception: pass
            finally:
                try: conn.close()
                except Exception: pass
            response_meta=analyze_response(bytes(raw),ctype)
            trace({"method":self.command,"path":self.path.split("?",1)[0],"status":status,
                   "elapsed_ms":round((time.monotonic()-started)*1000),**request_meta,**response_meta})

ThreadingHTTPServer(("127.0.0.1",PORT),Handler).serve_forever()
PYGATE
chmod 700 "$ROOT/pacing_gateway.py"
: > "$ROOT/gateway-trace.jsonl"; chmod 600 "$ROOT/gateway-trace.jsonl"
setsid env Z_GATEWAY_PORT="$GATEWAY_PORT" Z_MIN_INTERVAL_MS="$MIN_INTERVAL_MS" \
  Z_MAX_CONCURRENCY="$MAX_CONCURRENCY" Z_GATEWAY_TIMEOUT="$TIMEOUT" \
  Z_GATEWAY_TRACE="$ROOT/gateway-trace.jsonl" \
  python3 "$ROOT/pacing_gateway.py" >"$ROOT/gateway.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$ROOT/gateway.pid"
for i in $(seq 1 30); do
  curl -sS -o /dev/null -m 2 "http://127.0.0.1:$GATEWAY_PORT/__zkc_health" 2>/dev/null && break
  [ "$i" = 30 ] && { echo '       pacing gateway did not bind'; tail -20 "$ROOT/gateway.log" | sed 's/^/         /'; exit 74; }
  sleep 1
done
echo "       per-request pacing gateway bound on :$GATEWAY_PORT (interval=${MIN_INTERVAL_MS}ms concurrency=$MAX_CONCURRENCY)"

if [ "$START_BRIDGE" = 1 ]; then
  CFG="$ROOT/bridge-config.json"
  python3 - "$CFG" "$GATEWAY_PORT" "$MODEL" "$TIMEOUT" 3<<<"$K" <<'PYCONFIG'
import json, os, sys
cfg,gateway_port,model,timeout=sys.argv[1:5]
key=os.read(3,65536).decode().rstrip("\n")
data={"version":"1.0","currentUpstream":"kimi","timeoutMs":int(timeout)*1000,
      "upstreams":{"kimi":{"baseUrl":"http://127.0.0.1:%s/v1"%gateway_port,
                             "apiKey":key,"model":model}}}
fd=os.open(cfg,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,"w") as f: json.dump(data,f)
PYCONFIG
  trap 'rm -f "$CFG"' EXIT
  setsid env -u MOONSHOT_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY \
    "$CODEPROXY_BIN" --config "$CFG" --upstream-format openai-chat \
    --host 127.0.0.1 --port "$PORT" > "$ROOT/bridge.log" 2>&1 </dev/null &
  printf '%s\n' "$!" > "$ROOT/bridge.pid"
  unset K
  for i in $(seq 1 60); do
    curl -sS -o /dev/null -m 2 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null && { echo "       bridge bound on :$PORT after $((i*2))s"; break; }
    [ "$i" = 60 ] && { echo '       NO BRIDGE BIND. redacted log tail:'; tail -20 "$ROOT/bridge.log" | sed -E 's/sk-[A-Za-z0-9._-]{8,}/sk-REDACTED/g; s/^/         /'; exit 74; }
    sleep 2
  done
  rm -f "$CFG"; trap - EXIT
python3 - "$CODEX_HOME/config.toml" "$CODEX_HOME/kimi.config.toml" "$CODEX_HOME/models.json" "$PORT" "$MODEL" "$CONTEXT" "$MAXOUT" "$WEB_NATIVE" "$REASONING_SUMMARIES" <<'PY'
import json, os, sys
cfg,profile,catalog,port,model,context,maxout,web_native,reasoning_summaries=sys.argv[1:10]
entry = {
    "slug": model,
    "prefer_websockets": False,
    "support_verbosity": True,
    "default_verbosity": "low",
    "apply_patch_tool_type": "freeform",
    "web_search_tool_type": "text",
    "input_modalities": ["text"],
    "supports_image_detail_original": False,
    "truncation_policy": {"mode":"tokens","limit":10000},
    "supports_parallel_tool_calls": True,
    "tool_mode": None,
    "multi_agent_version": "v2",
    "use_responses_lite": False,
    "include_skills_usage_instructions": False,
    "auto_review_model_override": None,
    "context_window": int(context),
    "max_context_window": int(context),
    "effective_context_window_percent": 95,
    "auto_compact_token_limit": None,
    "comp_hash": "3000",
    "reasoning_summary_format": "experimental",
    "default_reasoning_summary": "auto" if reasoning_summaries == "1" else "none",
    "display_name": model,
    "description": "Kimi K3 through the local Chat-to-Responses bridge.",
    "default_reasoning_level": "max",
    "supported_reasoning_levels": [
        {"effort":"low","description":"Rate-safe capability probes"},
        {"effort":"high","description":"Complex coding and scientific work"},
        {"effort":"max","description":"Maximum reasoning depth"}
    ],
    "shell_type": "shell_command",
    "visibility": "list",
    "minimal_client_version": "0.144.0",
    "supported_in_api": True,
    "availability_nux": None,
    "upgrade": None,
    "priority": 1,
    "base_instructions": "You are Codex, a coding agent working in the user's current workspace.",
    "model_messages": None,
    "experimental_supported_tools": [],
    "supports_search_tool": web_native == "1",
    "default_service_tier": None,
    "supports_reasoning_summaries": reasoning_summaries == "1"
}
with open(catalog,"w") as f:
    json.dump({"models":[entry]},f,indent=2); f.write("\n")
with open(cfg,"a") as f:
    f.write("\n[model_providers.kimi]\n")
    f.write('name = "Kimi K3 via selected Codex router"\n')
    f.write('base_url = "http://127.0.0.1:%s/v1"\n' % port)
    f.write('requires_openai_auth = false\nwire_api = "responses"\n')
    f.write('request_max_retries = 2\nstream_max_retries = 2\n')
    f.write('supports_standalone_web_search = %s\n' % ('true' if web_native=='1' else 'false'))
with open(profile,"w") as f:
    f.write('model = %s\n' % json.dumps(model))
    f.write('model_provider = "kimi"\n')
    f.write('model_catalog_json = %s\n' % json.dumps(catalog))
    f.write('model_context_window = %s\nmodel_max_output_tokens = %s\n' % (context,maxout))
    f.write('model_reasoning_effort = "max"\n')
    if reasoning_summaries == '1':
        f.write('model_reasoning_summary = "auto"\nmodel_supports_reasoning_summaries = true\n')
    else:
        f.write('model_supports_reasoning_summaries = false\n')
for path in (cfg,profile,catalog): os.chmod(path,0o600)
PY
  echo "       isolated Codex config + measured model catalog written under $CODEX_HOME"
  echo "       Codex output cap=$MAXOUT reasoning_summaries=$REASONING_SUMMARIES"
  echo "       Responses bridge endpoint=http://127.0.0.1:$PORT/v1"
else
  unset K
  echo "       Responses bridge not requested; pacing gateway remains active for raw Anthropic/Claude traffic"
fi
echo "       Moonshot gateway endpoint=http://127.0.0.1:$GATEWAY_PORT"
if [ "$KEEP_BRIDGE_REMOTE" = 1 ]; then
  echo "       heartbeat task=$TASK; KEEP_BRIDGE=1 leaves this run active"
else
  echo "       heartbeat task=$TASK; automatic cleanup is enabled"
fi
EOF
step "3. pacing gateway and Responses bridge"
if (( NEED_GATEWAY )); then
  if send_secret "$S_BRIDGE" "Z_RUN_ID=$RUN_ID,Z_TASK=$TASK_NAME,B_PORT=$PORT,B_GATEWAY_PORT=$GATEWAY_PORT,B_GATEWAY_SPAN=$GATEWAY_PORT_SPAN,B_START_BRIDGE=$NEED_BRIDGE,B_PORT_SPAN=$BRIDGE_PORT_SPAN,B_PORT_STRICT=$BRIDGE_PORT_STRICT,B_MODEL=$MODEL,B_CONTEXT=$CONTEXT_WINDOW,B_MAXOUT=$CLIENT_OUTPUT_TOKENS,B_REASONING_SUMMARIES=$CODEX_REASONING_SUMMARIES,B_MODEL_DEFAULT=$MODEL_DEFAULT_MAX_OUTPUT_TOKENS,B_WEB_NATIVE=$CODEX_STANDALONE_WEB_SEARCH,B_TIMEOUT=$REQUEST_TIMEOUT,B_KEEP_BRIDGE=$KEEP_BRIDGE,B_MIN_INTERVAL_MS=$KIMI_MIN_REQUEST_INTERVAL_MS,B_MAX_CONCURRENCY=$KIMI_MAX_CONCURRENCY,KEEP_MAX=$KEEPAWAKE_MAX"; then
    ACTUAL_GATEWAY_PORT=$(run_remote 'cat "$HOME/.cache/zkc-kimi-k3/$Z_RUN_ID/gateway.port"' "Z_RUN_ID=$RUN_ID" 2>/dev/null | tr -d '
')
    is_uint "$ACTUAL_GATEWAY_PORT" && (( ACTUAL_GATEWAY_PORT >= 1 && ACTUAL_GATEWAY_PORT <= 65535 )) || { bad "pacing gateway did not report a valid port"; exit 1; }
    GATEWAY_PORT="$ACTUAL_GATEWAY_PORT"
    if (( NEED_BRIDGE )); then
      ACTUAL_PORT=$(run_remote 'cat "$HOME/.cache/zkc-kimi-k3/$Z_RUN_ID/bridge.port"' "Z_RUN_ID=$RUN_ID" 2>/dev/null | tr -d '
')
      is_uint "$ACTUAL_PORT" && (( ACTUAL_PORT >= 1 && ACTUAL_PORT <= 65535 )) || { bad "bridge started but did not report a valid port"; exit 1; }
      PORT="$ACTUAL_PORT"; ok "pacing gateway + Responses bridge ready"
    else
      ok "per-request pacing gateway ready"
    fi
  else
    bad "remote pacing gateway/bridge startup failed"; exit 1
  fi
else
  note "not started; selected layers do not contact Moonshot from the Sprite"
fi

# ========================================================= 4. PROTOCOL PROBES ==
IFS= read -r -d '' S_PROTO <<'EOF' || true
set -uo pipefail
IFS= read -r K || true
PORT="${B_PORT:?}"; GATEWAY_PORT="${B_GATEWAY_PORT:?}"; MODEL="${B_MODEL:?}"; TIMEOUT="${B_TIMEOUT:-300}"
WEB_TEST="${B_WEB_TEST:-1}"; WEB_AGE="${B_WEB_AGE:-60}"; PROBE_MAX="${B_MAXOUT:-1024}"
REASONING_MAX="${B_REASONING_MAX:-4096}"; REASONING_RETRY_MAX="${B_REASONING_RETRY_MAX:-8192}"
HTTP_LOG_LEVEL="${B_HTTP_LOG_LEVEL:-errors}"; HTTP_BODY_MAX="${B_HTTP_BODY_MAX:-2048}"
MIN_INTERVAL_MS="${B_MIN_INTERVAL_MS:-3200}"; RATE_RETRIES="${B_RATE_RETRIES:-2}"; RETRY_MAX="${B_RETRY_MAX:-60}"
ENGINE_RETRIES="${B_ENGINE_RETRIES:-3}"; ENGINE_BASE="${B_ENGINE_BASE:-5}"; WEB_MAX="${B_WEB_MAX:-4096}"
TPD_ACTION="${B_TPD_ACTION:-stop}"; TPD_WAIT_MAX="${B_TPD_WAIT_MAX:-7200}"; TPD_GRACE="${B_TPD_GRACE:-5}"; RESET_TZ="${B_RESET_TZ:-UTC}"
python3 -u - "$PORT" "$GATEWAY_PORT" "$MODEL" "$TIMEOUT" "$WEB_TEST" "$WEB_AGE" "$PROBE_MAX" "$REASONING_MAX" "$REASONING_RETRY_MAX" "$HTTP_LOG_LEVEL" "$HTTP_BODY_MAX" "$MIN_INTERVAL_MS" "$RATE_RETRIES" "$RETRY_MAX" "$ENGINE_RETRIES" "$ENGINE_BASE" "$WEB_MAX" "$TPD_ACTION" "$TPD_WAIT_MAX" "$TPD_GRACE" "$RESET_TZ" 3<<<"$K" <<'PYEOF'
import copy
import datetime as dt
import html
import email.utils
import http.client
import ipaddress
import json
import math
import random
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

KEY = __import__("os").read(3,65536).decode().rstrip("\n")
PORT, GATEWAY_PORT, MODEL, TIMEOUT, WEB_TEST, WEB_AGE, PROBE_MAX, REASONING_MAX, REASONING_RETRY_MAX, HTTP_LOG_LEVEL, HTTP_BODY_MAX, MIN_INTERVAL_MS, RATE_RETRIES, RETRY_MAX, ENGINE_RETRIES, ENGINE_BASE, WEB_MAX, TPD_ACTION, TPD_WAIT_MAX, TPD_GRACE, RESET_TZ = sys.argv[1:22]
TIMEOUT, WEB_AGE, PROBE_MAX, REASONING_MAX, REASONING_RETRY_MAX, HTTP_BODY_MAX = int(TIMEOUT), int(WEB_AGE), int(PROBE_MAX), int(REASONING_MAX), int(REASONING_RETRY_MAX), int(HTTP_BODY_MAX)
MIN_INTERVAL = int(MIN_INTERVAL_MS) / 1000.0
RATE_RETRIES, RETRY_MAX = int(RATE_RETRIES), int(RETRY_MAX)
ENGINE_RETRIES, ENGINE_BASE, WEB_MAX = int(ENGINE_RETRIES), int(ENGINE_BASE), int(WEB_MAX)
TPD_WAIT_MAX, TPD_GRACE = int(TPD_WAIT_MAX), int(TPD_GRACE)
LAST_REQUEST_STARTED = 0.0
WEB_TEST = WEB_TEST == "1"
RESPONSES_URL = f"http://127.0.0.1:{PORT}/v1/responses"
CHAT_URL = f"http://127.0.0.1:{GATEWAY_PORT}/v1/chat/completions"
LOCAL_HEADERS = {
    "Authorization": "Bearer " + KEY,
    "Content-Type": "application/json",
}
UPSTREAM_HEADERS = {
    "Authorization": "Bearer " + KEY,
    "Content-Type": "application/json",
}
TOOLS = [{
    "type": "function",
    "name": "get_token",
    "description": "Returns a token supplied by the test harness",
    "parameters": {"type": "object", "properties": {}, "required": []},
}]


def probe(name, verdict, detail=""):
    print("  %-14s %-5s %s" % (name, verdict, detail))
    print("PROBE|%s|%s|%s" % (name, verdict, detail))


def _one_line(value, limit=None):
    text = ("" if value is None else str(value)).replace("\r", " ").replace("\n", " ")
    text = re.sub(r"(?i)bearer\s+[A-Za-z0-9._-]+", "Bearer REDACTED", text)
    text = re.sub(r"sk-[A-Za-z0-9._-]{8,}", "sk-REDACTED", text)
    text = re.sub(r"\s+", " ", text).strip().replace("|", "\\u007c")
    if limit is not None and len(text) > limit:
        text = text[:limit] + "...<truncated>"
    return text


def _safe_url(url):
    try:
        u = urllib.parse.urlsplit(url)
        return urllib.parse.urlunsplit((u.scheme, u.netloc, u.path, "", ""))
    except Exception:
        return str(url).split("?", 1)[0]


def _body_summary(body):
    if not isinstance(body, dict):
        return "none" if body is None else type(body).__name__
    model = body.get("model", "-")
    cap = body.get("max_completion_tokens", body.get("max_output_tokens", body.get("max_tokens", "-")))
    stream = bool(body.get("stream", False))
    tools = body.get("tools")
    tool_count = len(tools) if isinstance(tools, list) else 0
    messages = body.get("messages")
    msg_count = len(messages) if isinstance(messages, list) else 0
    inp = body.get("input")
    input_count = len(inp) if isinstance(inp, list) else (1 if inp is not None else 0)
    return "model=%s cap=%s stream=%s tools=%s messages=%s input_items=%s" % (
        _one_line(model, 128), cap, int(stream), tool_count, msg_count, input_count)


def _header_subset(headers):
    wanted = {}
    items = headers.items() if hasattr(headers, "items") else (headers or [])
    for key, value in items:
        lk = str(key).lower()
        if (lk == "date" or lk == "retry-after" or lk == "cf-ray" or
                "request-id" in lk or lk.startswith("x-ratelimit-") or
                lk.startswith("ratelimit-")):
            wanted[lk] = _one_line(value, 512)
    return wanted


def _error_info(raw):
    try:
        document = json.loads(raw or "{}")
    except Exception:
        return {"type": "", "message": "", "request_id": ""}
    error = document.get("error") if isinstance(document, dict) else None
    if not isinstance(error, dict):
        error = {}
    return {
        "type": _one_line(error.get("type", ""), 128),
        "message": _one_line(error.get("message", ""), HTTP_BODY_MAX),
        "request_id": _one_line(document.get("request_id") or error.get("request_id") or "", 256),
    }


def _rate_kind(raw, headers=None):
    info = _error_info(raw)
    material = (raw or "") + " " + json.dumps(headers or {}, sort_keys=True) + " " + info["type"]
    upper = material.upper()
    for name in ("TPD", "TPM", "RPM", "CONCURRENCY"):
        if name in upper:
            return name
    etype = info["type"].lower()
    if etype == "engine_overloaded_error":
        return "ENGINE_OVERLOAD"
    if etype == "exceeded_current_quota_error":
        return "QUOTA"
    if etype == "rate_limit_reached_error":
        return "RATE_LIMIT"
    return "API"


def http_diagnostic(label, meta, raw="", force=False):
    if HTTP_LOG_LEVEL == "off":
        return
    code = int(meta.get("status") or 0)
    if not force and HTTP_LOG_LEVEL != "all" and 0 < code < 400:
        return
    headers = meta.get("headers") or {}
    error = _error_info(raw)
    fields = {
        "label": label,
        "method": meta.get("method", "?"),
        "url": meta.get("url", "?"),
        "status": code,
        "elapsed_ms": meta.get("elapsed_ms", "?"),
        "request_bytes": meta.get("request_bytes", 0),
        "request": meta.get("request_summary", ""),
        "request_id": headers.get("x-request-id") or headers.get("request-id") or headers.get("x-moonshot-request-id") or headers.get("msh-request-id") or error.get("request_id") or "-",
        "retry_after": headers.get("retry-after", "-"),
        "error_type": error.get("type") or "-",
        "rate_kind": _rate_kind(raw, headers) if code == 429 else "-",
        "headers": json.dumps(headers, sort_keys=True, separators=(",", ":")),
        "body": _one_line(raw, HTTP_BODY_MAX),
    }
    print("HTTP|" + "|".join("%s=%s" % (k, _one_line(v)) for k, v in fields.items()))


def rate_detail(raw, meta=None, suffix=""):
    headers = (meta or {}).get("headers") or {}
    kind = _rate_kind(raw, headers)
    detail = ("Moonshot engine overloaded (HTTP 429)" if kind == "ENGINE_OVERLOAD"
              else "Moonshot %s rate limit reached (HTTP 429)" % kind)
    error = _error_info(raw)
    retry = headers.get("retry-after")
    request_id = headers.get("x-request-id") or headers.get("request-id") or headers.get("x-moonshot-request-id") or headers.get("msh-request-id") or error.get("request_id")
    extras = []
    if error.get("type"):
        extras.append("error_type=%s" % error["type"])
    if retry:
        extras.append("retry_after=%s" % retry)
    if request_id:
        extras.append("request_id=%s" % request_id)
    if suffix:
        extras.append(suffix)
    return detail + (("; " + "; ".join(extras)) if extras else "")


def _request_once(label, url, body=None, headers=None, stream=False):
    data = None if body is None else json.dumps(body, separators=(",", ":")).encode()
    req = urllib.request.Request(url, data=data, headers=headers or {})
    global LAST_REQUEST_STARTED
    now = time.monotonic()
    wait = LAST_REQUEST_STARTED + MIN_INTERVAL - now
    if wait > 0:
        time.sleep(wait)
    LAST_REQUEST_STARTED = time.monotonic()
    started = LAST_REQUEST_STARTED
    method = "POST" if data is not None else "GET"
    meta = {
        "method": method,
        "url": _safe_url(url),
        "request_bytes": len(data or b""),
        "request_summary": _body_summary(body),
        "headers": {},
        "elapsed_ms": 0,
        "status": 0,
    }
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            payload = r.read(32*1024*1024+1)
            meta["status"] = r.status
            meta["headers"] = _header_subset(r.headers.items())
            meta["elapsed_ms"] = round((time.monotonic() - started) * 1000)
            if len(payload)>32*1024*1024:
                raw = "response exceeded 32 MiB safety limit"
                meta["status"] = 0
                http_diagnostic(label, meta, raw, force=True)
                return 0, raw, meta
            raw = payload.decode("utf-8", "replace")
            http_diagnostic(label, meta, raw)
            return r.status, raw, meta
    except urllib.error.HTTPError as e:
        raw = e.read(32*1024*1024+1).decode("utf-8", "replace")
        meta["status"] = e.code
        meta["headers"] = _header_subset(e.headers.items() if e.headers else [])
        meta["elapsed_ms"] = round((time.monotonic() - started) * 1000)
        http_diagnostic(label, meta, raw, force=True)
        return e.code, raw, meta
    except Exception as e:
        raw = str(e)
        meta["elapsed_ms"] = round((time.monotonic() - started) * 1000)
        http_diagnostic(label, meta, raw, force=True)
        return 0, raw, meta


def _retry_after_seconds(headers):
    value = (headers or {}).get("retry-after")
    if not value:
        return None
    try:
        return max(0.0, float(value))
    except Exception:
        try:
            when = email.utils.parsedate_to_datetime(value)
            if when.tzinfo is None:
                when = when.replace(tzinfo=dt.timezone.utc)
            return max(0.0, (when - dt.datetime.now(dt.timezone.utc)).total_seconds())
        except Exception:
            return None


def _tpd_usage(raw):
    text = _error_info(raw).get("message") or (raw or "")
    m = re.search(r"current:\s*([0-9]+)\s*,\s*limit:\s*([0-9]+)", text, re.I)
    if not m:
        return None, None
    return int(m.group(1)), int(m.group(2))


def _reset_deadline(delay):
    when = dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=max(0.0, delay))
    utc_text = when.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    local_text = utc_text
    if ZoneInfo is not None:
        try:
            local_text = when.astimezone(ZoneInfo(RESET_TZ)).replace(microsecond=0).isoformat()
        except Exception:
            pass
    return utc_text, local_text


def _emit_tpd_guard(label, raw, meta, action, delay, reason):
    current, limit = _tpd_usage(raw)
    reset_utc, reset_local = _reset_deadline(delay or 0.0)
    over = (current - limit) if current is not None and limit is not None else "-"
    fields = {
        "label": label, "action": action, "requested_action": TPD_ACTION,
        "reason": reason, "wait_max_seconds": TPD_WAIT_MAX,
        "grace_seconds": TPD_GRACE,
        "current": current if current is not None else "-",
        "limit": limit if limit is not None else "-", "over_by": over,
        "retry_after_seconds": "%.3f" % delay if delay is not None else "-",
        "reset_utc": reset_utc if delay is not None else "-",
        "reset_local": reset_local if delay is not None else "-",
        "timezone": RESET_TZ,
    }
    print("TPD_GUARD|" + "|".join("%s=%s" % (k, _one_line(v)) for k, v in fields.items()))


def request(label, url, body=None, headers=None, stream=False):
    transient_attempts = 0
    tpd_waited = False
    attempt = 0
    while True:
        attempt += 1
        code, raw, meta = _request_once(label, url, body, headers, stream)
        kind = _rate_kind(raw, meta.get("headers") or {}) if code == 429 else ""
        if code == 429 and kind == "TPD":
            delay = _retry_after_seconds(meta.get("headers") or {})
            action = TPD_ACTION
            can_wait = (action == "wait" and not tpd_waited and delay is not None and
                        delay + TPD_GRACE <= TPD_WAIT_MAX)
            if can_wait:
                guard_action, guard_reason = "wait", "server-retry-after"
            elif tpd_waited:
                guard_action, guard_reason = "stop-after-wait", "repeated-tpd-after-wait"
            elif TPD_ACTION != "wait":
                guard_action, guard_reason = "stop", "configured-stop"
            elif delay is None:
                guard_action, guard_reason = "stop", "missing-retry-after"
            else:
                guard_action, guard_reason = "stop", "retry-after-exceeds-wait-max"
            _emit_tpd_guard(label, raw, meta, guard_action, delay, guard_reason)
            if can_wait:
                sleep_for = delay + TPD_GRACE
                print("HTTP_RETRY|label=%s|attempt=%d|next_attempt=%d|status=429|rate_kind=TPD|mode=wait-until-reset|sleep_seconds=%.3f" %
                      (_one_line(label), attempt, attempt + 1, sleep_for))
                time.sleep(sleep_for)
                tpd_waited = True
                continue
            return code, raw, meta
        if code == 429 and kind == "QUOTA":
            return code, raw, meta
        if code == 429:
            delay = _retry_after_seconds(meta.get("headers") or {})
            retry_limit = ENGINE_RETRIES if kind == "ENGINE_OVERLOAD" else RATE_RETRIES
            if transient_attempts >= retry_limit:
                return code, raw, meta
            if delay is None:
                if kind == "ENGINE_OVERLOAD":
                    delay = min(float(RETRY_MAX), float(ENGINE_BASE) * (2.0 ** transient_attempts))
                else:
                    return code, raw, meta
        elif code == 0 or code in (502, 503, 504):
            if transient_attempts >= RATE_RETRIES:
                return code, raw, meta
            delay = min(RETRY_MAX, 2.0 ** transient_attempts)
        else:
            return code, raw, meta
        transient_attempts += 1
        delay = min(float(RETRY_MAX), max(delay, MIN_INTERVAL))
        print("HTTP_RETRY|label=%s|attempt=%d|next_attempt=%d|status=%s|rate_kind=%s|sleep_seconds=%.3f" %
              (_one_line(label), attempt, attempt + 1, code, kind or "transport", delay))
        time.sleep(delay)


def post_json(label, body):
    body = dict(body)
    body.setdefault("max_output_tokens", min(PROBE_MAX, 8192))
    code, raw, meta = request(label, RESPONSES_URL, body, LOCAL_HEADERS)
    try:
        return code, json.loads(raw), raw, meta
    except Exception:
        return code, {}, raw, meta


def output_items(response):
    out = response.get("output")
    return out if isinstance(out, list) else []


def function_calls(response):
    return [x for x in output_items(response)
            if isinstance(x, dict) and x.get("type") == "function_call"]


def text_from_response(response):
    parts = []
    for item in output_items(response):
        if not isinstance(item, dict):
            continue
        if item.get("type") == "message":
            for block in item.get("content") or []:
                if isinstance(block, dict) and block.get("type") in ("output_text", "text"):
                    value = block.get("text")
                    if isinstance(value, str):
                        parts.append(value)
        elif item.get("type") in ("output_text", "text"):
            value = item.get("text")
            if isinstance(value, str):
                parts.append(value)
    if not parts and isinstance(response.get("output_text"), str):
        parts.append(response["output_text"])
    return "".join(parts)


def user_item(text):
    return {
        "type": "message",
        "role": "user",
        "content": [{"type": "input_text", "text": text}],
    }


def genuine_round_trip(label, prompt, token_values):
    first_body = {
        "model": MODEL,
        "instructions": "Use the provided tool exactly as requested. Do not invent tool results.",
        "input": [user_item(prompt)],
        "tools": TOOLS,
        "tool_choice": "required",
    }
    c1, first, raw1, meta1 = post_json(label + ":first", first_body)
    calls = function_calls(first)
    if c1 != 200:
        return {"kind": "HTTP1", "code": c1, "raw": raw1, "meta": meta1, "first": first, "calls": []}
    if not calls:
        return {"kind": "NO_CALL", "code": c1, "raw": raw1, "meta": meta1, "first": first, "calls": []}

    supplied = []
    outputs = []
    for i, call in enumerate(calls):
        token = token_values[i] if i < len(token_values) else token_values[-1] + str(i + 1)
        supplied.append(token)
        call_id = call.get("call_id") or call.get("id")
        outputs.append({"type": "function_call_output", "call_id": call_id, "output": token})

    final_body = {
        "model": MODEL,
        "instructions": "Reply using only the exact tool result value or values, with no explanation.",
        "input": [user_item(prompt)] + output_items(first) + outputs,
        "tools": TOOLS,
    }
    c2, final, raw2, meta2 = post_json(label + ":final", final_body)
    return {
        "kind": "DONE" if c2 == 200 else "HTTP2",
        "code": c2,
        "raw": raw2, "meta": meta2,
        "first": first,
        "final": final,
        "calls": calls,
        "supplied": supplied,
        "final_body": final_body,
        "text": text_from_response(final),
    }


def stream_text(label, body):
    streamed = dict(body)
    streamed["stream"] = True
    code, raw, meta = request(label, RESPONSES_URL, streamed, LOCAL_HEADERS, stream=True)
    fragments = []
    completed = False
    for line in raw.splitlines():
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[5:].strip()
        if not payload or payload == "[DONE]":
            continue
        try:
            event = json.loads(payload)
        except Exception:
            continue
        et = event.get("type", "")
        if et in ("response.output_text.delta", "response.refusal.delta"):
            delta = event.get("delta")
            if isinstance(delta, str):
                fragments.append(delta)
        elif et in ("response.completed", "response.done"):
            completed = True
    return code, "".join(fragments), completed, raw, meta


# P1: send one request directly to Moonshot Chat Completions, then the same
# basic task through the local Responses bridge. This proves the key and model
# with an actual inference rather than assuming /v1/models is exhaustive.
direct_code, direct_raw, direct_meta = request("P1-identity:direct", CHAT_URL, {
    "model": MODEL,
    "messages": [{"role": "user", "content": "Reply with the single word OK."}],
    "reasoning_effort": "low",
    "max_completion_tokens": min(PROBE_MAX, 2048),
}, UPSTREAM_HEADERS)
try:
    direct = json.loads(direct_raw)
    direct_model = direct.get("model", "?")
except Exception:
    direct_model = "?"

if direct_code == 429:
    probe("P1-identity", "BLOCKED", rate_detail(direct_raw, direct_meta, "source=direct-chat preflight"))
    for name in ("P2-tool", "P4-reasoning", "P4-source", "P4-preserve",
                 "P4-enforce", "P4-visible", "P5-stream", "P3-parallel",
                 "P6-webtool", "P7-websynth", "P8-webverify"):
        probe(name, "BLOCKED", "not attempted after direct-chat preflight rate limit")
    raise SystemExit(0)

p1_code, p1, p1_raw, p1_meta = post_json("P1-identity:bridge", {
    "model": MODEL,
    "input": "Reply with the single word OK.",
    "reasoning": {"effort": "low"},
    "max_output_tokens": min(PROBE_MAX, 2048),
})
bridge_model = p1.get("model", "?") if isinstance(p1, dict) else "?"
if p1_code == 429:
    probe("P1-identity", "BLOCKED", rate_detail(p1_raw, p1_meta, "source=responses-bridge preflight"))
    for name in ("P2-tool", "P4-reasoning", "P4-source", "P4-preserve",
                 "P4-enforce", "P4-visible", "P5-stream", "P3-parallel",
                 "P6-webtool", "P7-websynth", "P8-webverify"):
        probe(name, "BLOCKED", "not attempted after Responses-bridge preflight rate limit")
    raise SystemExit(0)
if direct_code == 200 and p1_code == 200:
    probe("P1-identity", "PASS", f"direct_model={direct_model}; bridge_model={bridge_model}")
else:
    probe("P1-identity", "FAIL",
          f"direct_http={direct_code} direct_model={direct_model} bridge_http={p1_code} bridge_model={bridge_model}")
    print("         " + (p1_raw or direct_raw)[:300])

usage = (p1.get("usage") or {}) if isinstance(p1, dict) else {}
print("  bridge usage on P1: input=%s output=%s" %
      (usage.get("input_tokens", "?"), usage.get("output_tokens", "?")))

# P2/P4/P5 share one genuine model-issued tool call so Kimi's exact preserved
# reasoning output is replayed instead of fabricating an invalid assistant turn.
tok = "ZKKT%d%d" % (int(time.time()), random.randint(1000, 9999))
r2 = genuine_round_trip("P2-tool", "Call get_token exactly once, then answer with only its result.", [tok])
if r2.get("kind") == "DONE" and tok in r2.get("text", ""):
    probe("P2-tool", "PASS", "genuine tool round trip; token echoed")
elif r2.get("code") == 429:
    probe("P2-tool", "BLOCKED", rate_detail(r2.get("raw"), r2.get("meta")))
elif r2.get("kind") == "NO_CALL":
    probe("P2-tool", "FAIL", "model never issued a function_call")
else:
    probe("P2-tool", "FAIL", "kind=%s http=%s" % (r2.get("kind"), r2.get("code")))
    print("         " + r2.get("raw", "")[:300])

# P4 is split into functional reasoning, preservation, and visibility. A
# bridge can carry a correct reasoning-dependent tool turn while declining to
# expose private reasoning as a Responses `reasoning` item.
science_prompt = (
    "For a first-order process, k1=1.20e-3 s^-1 at T1=300 K and "
    "k2=4.50e-3 s^-1 at T2=330 K. Using R=8.314462618 J mol^-1 K^-1 "
    "and ln(k2/k1)=Ea/R*(1/T1-1/T2), calculate Ea in kJ/mol. "
    "Call submit_activation_energy exactly once with that number."
)
science_tools = [{
    "type": "function", "name": "submit_activation_energy",
    "description": "Submit the calculated activation energy in kJ/mol",
    "parameters": {"type":"object", "properties": {
        "activation_energy_kj_mol": {"type":"number"}},
        "required":["activation_energy_kj_mol"]}
}]
expected_ea = 8.314462618 * math.log(4.50e-3/1.20e-3) / (1/300.0-1/330.0) / 1000.0
first_body = {
    "model": MODEL, "instructions": "Solve accurately, then call the tool.",
    "input": [user_item(science_prompt)], "tools": science_tools,
    "tool_choice": "required", "reasoning": {"effort":"high","summary":"auto"},
    "max_output_tokens": REASONING_MAX
}
sc1, sf, sfraw, sfmeta = post_json("P4-reasoning:first", first_body)
scalls = function_calls(sf)
usage1 = (sf.get("usage") or {}) if isinstance(sf, dict) else {}
try:
    used1 = int(usage1.get("output_tokens"))
except Exception:
    used1 = -1
cap_retry_used = False
if (sc1 == 200 and not scalls and
        used1 >= REASONING_MAX and REASONING_RETRY_MAX > REASONING_MAX):
    cap_retry_used = True
    print("CAP_RETRY|label=P4-reasoning:first|from=%d|to=%d|reason=output_cap_exhausted" %
          (REASONING_MAX, REASONING_RETRY_MAX), flush=True)
    retry_body = copy.deepcopy(first_body)
    retry_body["max_output_tokens"] = REASONING_RETRY_MAX
    sc1, sf, sfraw, sfmeta = post_json("P4-reasoning:cap-retry", retry_body)
    scalls = function_calls(sf)
    usage1 = (sf.get("usage") or {}) if isinstance(sf, dict) else {}
    try:
        used1 = int(usage1.get("output_tokens"))
    except Exception:
        used1 = -1
submitted = None
if scalls:
    try:
        submitted = float(json.loads(scalls[0].get("arguments") or "{}")["activation_energy_kj_mol"])
    except Exception:
        pass
science_token = "ZKSCI%d" % random.randint(100000,999999)
science_ok = sc1 == 200 and submitted is not None and abs(submitted-expected_ea) <= 0.02*expected_ea
science_final_ok = False
sc2 = None
sraw = ""
if science_ok:
    call_id = scalls[0].get("call_id") or scalls[0].get("id")
    sc2, sfinal, sraw, smeta = post_json("P4-reasoning:final", {
        "model": MODEL,
        "instructions": "Reply with only the exact validator token.",
        "input": [user_item(science_prompt)] + output_items(sf) + [{
            "type":"function_call_output", "call_id":call_id, "output":science_token}],
        "tools": science_tools, "max_output_tokens": PROBE_MAX
    })
    science_final_ok = sc2 == 200 and science_token in text_from_response(sfinal)
if science_ok and science_final_ok:
    probe("P4-reasoning", "PASS", "scientific argument correct (Ea=%.3f kJ/mol) and turn survived" % submitted)
elif sc1 == 429 or sc2 == 429:
    probe("P4-reasoning", "BLOCKED", rate_detail(sfraw, sfmeta) if sc1 == 429 else rate_detail(sraw, smeta))
elif sc1 == 200 and not scalls and used1 >= (REASONING_RETRY_MAX if cap_retry_used else REASONING_MAX):
    probe("P4-reasoning", "TRUNCATED",
          "reasoning consumed the full output cap before a tool call; output_tokens=%d cap=%d%s" %
          (used1, REASONING_RETRY_MAX if cap_retry_used else REASONING_MAX,
           "; cap retry exhausted" if cap_retry_used else ""))
    print("         " + json.dumps(sf)[:300], flush=True)
else:
    probe("P4-reasoning", "FAIL", "scientific reasoning/tool turn failed submitted=%r expected=%.3f" % (submitted, expected_ea))
    print("         " + (sfraw if sc1 != 200 else (sraw if science_ok else json.dumps(sf)))[:300], flush=True)

# Direct Chat exposes reasoning_content; compare that source surface with the
# bridge's Responses surface rather than assuming the translator must publish it.
direct_tools = [{"type":"function", "function": {
    "name":"submit_activation_energy", "description":"Submit Ea in kJ/mol",
    "parameters": science_tools[0]["parameters"]}}]
dc, draw, dmeta = request("P4-source", CHAT_URL, {
    "model":MODEL, "messages":[{"role":"user","content":science_prompt}],
    "tools":direct_tools, "tool_choice":"required", "reasoning_effort":"high",
    "max_completion_tokens":min(REASONING_MAX, 8192)
}, UPSTREAM_HEADERS)
dmsg = {}
try:
    dmsg = json.loads(draw)["choices"][0]["message"]
except Exception:
    pass
dreason = dmsg.get("reasoning_content") if isinstance(dmsg,dict) else None
if dc == 200 and isinstance(dreason,str) and dreason.strip():
    probe("P4-source", "PASS", "direct Chat returned reasoning_content (%d chars)" % len(dreason))
elif dc == 429:
    probe("P4-source", "BLOCKED", rate_detail(draw, dmeta, "direct reasoning source not observed"))
else:
    probe("P4-source", "FAIL", "direct reasoning_content absent http=%s" % dc)

# Exact replay and a stripped negative control reveal whether Preserved Thinking
# is operationally enforced, not merely documented.
preserve_exact = preserve_stripped = None
if dc == 200 and isinstance(dmsg,dict) and dmsg.get("tool_calls"):
    tc = dmsg["tool_calls"][0]
    tool_result = {"role":"tool", "tool_call_id":tc["id"],
                   "name":"submit_activation_energy", "content":science_token}
    preserve_exact, eraw, emeta = request("P4-preserve:exact", CHAT_URL, {
        "model":MODEL,
        "messages":[{"role":"user","content":science_prompt}, dmsg, tool_result],
        "tools":direct_tools, "reasoning_effort":"high", "max_completion_tokens":min(PROBE_MAX, 8192)
    }, UPSTREAM_HEADERS)
    if preserve_exact == 429:
        probe("P4-preserve", "BLOCKED", rate_detail(eraw, emeta, "exact replay not observed"))
        probe("P4-enforce", "BLOCKED", "not attempted after the exact-replay rate limit")
    else:
        stripped = copy.deepcopy(dmsg)
        stripped.pop("reasoning_content", None)
        preserve_stripped, sraw2, s2meta = request("P4-enforce:stripped", CHAT_URL, {
            "model":MODEL,
            "messages":[{"role":"user","content":science_prompt}, stripped, tool_result],
            "tools":direct_tools, "reasoning_effort":"high", "max_completion_tokens":min(PROBE_MAX, 8192)
        }, UPSTREAM_HEADERS)
        if preserve_exact == 200:
            probe("P4-preserve", "PASS", "complete assistant message replay accepted")
            if preserve_stripped == 429:
                probe("P4-enforce", "BLOCKED", rate_detail(sraw2, s2meta, "negative control not observed"))
            elif preserve_stripped != 200:
                probe("P4-enforce", "PASS", "stripped reasoning rejected http=%s" % preserve_stripped)
            else:
                probe("P4-enforce", "LIMIT",
                      "endpoint tolerated a stripped negative control; preserve the complete message anyway")
        else:
            probe("P4-preserve", "FAIL", "exact replay http=%s" % preserve_exact)
            probe("P4-enforce", "SKIP", "exact replay failed, so enforcement control is not meaningful")
elif dc == 429:
    probe("P4-preserve", "BLOCKED", "not attempted because the direct source request was rate-limited")
    probe("P4-enforce", "BLOCKED", "not attempted because the direct source request was rate-limited")
elif dc != 200:
    probe("P4-preserve", "SKIP", "direct source request failed http=%s; no assistant tool turn to replay" % dc)
    probe("P4-enforce", "SKIP", "no assistant tool turn available for the negative control")
else:
    probe("P4-preserve", "FAIL", "direct response contained no tool call for preservation control")
    probe("P4-enforce", "SKIP", "no assistant tool turn available for the negative control")

reasoning_items = [x for x in output_items(sf)
                   if isinstance(x,dict) and x.get("type")=="reasoning"]
usage_details = ((sf.get("usage") or {}).get("output_tokens_details") or {}) if isinstance(sf,dict) else {}
reasoning_tokens = usage_details.get("reasoning_tokens")
if reasoning_items:
    probe("P4-visible", "PASS", "%d Responses reasoning item(s) exposed" % len(reasoning_items))
elif isinstance(dreason,str) and dreason.strip():
    probe("P4-visible", "LIMIT", "upstream reasons, bridge exposes no reasoning item; accounting=%r" % reasoning_tokens)
elif dc == 429:
    probe("P4-visible", "BLOCKED",
          "direct reasoning-source visibility was not observed because of rate limiting")
else:
    probe("P4-visible", "LIMIT", "reasoning surface unavailable on both paths")

if r2.get("final_body"):
    sc, st, completed, sraw, stream_meta = stream_text("P5-stream", r2["final_body"])
    if sc == 200 and tok in st:
        probe("P5-stream", "PASS", "SSE deltas reassembled; token present")
    elif sc == 429:
        probe("P5-stream", "BLOCKED", rate_detail(sraw, stream_meta))
    else:
        probe("P5-stream", "FAIL", f"http={sc} completed={completed} chars={len(st)}")
        print("         " + sraw[-300:])
elif r2.get("code") == 429:
    probe("P5-stream", "BLOCKED", "not attempted because the shared tool round trip was rate-limited")
else:
    probe("P5-stream", "FAIL", "no valid tool round trip to stream")

# P3: ask the model to issue three calls, then replay every issued call exactly.
toks = [tok + "A", tok + "B", tok + "C"]
r3 = genuine_round_trip(
    "P3-parallel", "Call get_token exactly three times in parallel, then answer with all three results.", toks)
issued = len(r3.get("calls") or [])
echoed = sum(1 for value in r3.get("supplied") or [] if value in r3.get("text", ""))
if r3.get("kind") == "DONE" and issued == 3 and echoed == 3:
    probe("P3-parallel", "PASS", "3 calls issued; 3/3 results survived")
elif r3.get("code") == 429:
    probe("P3-parallel", "BLOCKED", rate_detail(r3.get("raw"), r3.get("meta")))
elif r3.get("kind") == "DONE" and issued < 3 and echoed == issued:
    probe("P3-parallel", "LIMIT", f"model issued {issued} call(s); all survived, parallel shape incomplete")
else:
    probe("P3-parallel", "FAIL", f"kind={r3.get('kind')} issued={issued} echoed={echoed}")
    print("         " + r3.get("raw", "")[:300])

# P6-P8: an open-ended, time-sensitive scientific research task through Kimi's
# recommended Formula API official web-search tool. The model chooses the topic;
# the harness checks the full tool/fiber flow, synthesis, and cited pages.
def parse_json_object(text):
    if not isinstance(text,str):
        return None
    text=re.sub(r'^```(?:json)?\s*|\s*```$', '', text.strip(), flags=re.I|re.S)
    a,b=text.find('{'),text.rfind('}')
    if a<0 or b<a:
        return None
    try:
        return json.loads(text[a:b+1])
    except Exception:
        return None

def norm_text(raw):
    raw=re.sub(r'(?is)<script.*?</script>|<style.*?</style>', ' ', raw)
    raw=re.sub(r'(?s)<[^>]+>', ' ', raw)
    return re.sub(r'\s+', ' ', html.unescape(raw)).strip().lower()

class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, host, ip, port=443, timeout=25):
        super().__init__(host,port,timeout=timeout,context=ssl.create_default_context())
        self._ip=ip
    def connect(self):
        sock=socket.create_connection((self._ip,self.port),self.timeout)
        self.sock=self._context.wrap_socket(sock,server_hostname=self.host)

def public_ip(host):
    if not host or host.lower() in ("localhost","localhost.localdomain"):
        raise ValueError("local hostname rejected")
    for family,_,_,_,addr in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM):
        ip=ipaddress.ip_address(addr[0])
        if ip.is_global:
            return str(ip)
    raise ValueError("hostname has no public IP")

def fetch_page(url, redirects=0):
    try:
        if redirects>3: raise ValueError("too many redirects")
        u=urllib.parse.urlsplit(url)
        if u.scheme.lower()!="https" or u.username or u.password:
            raise ValueError("only credential-free HTTPS URLs are allowed")
        if u.port not in (None,443): raise ValueError("non-443 port rejected")
        host=u.hostname; ip=public_ip(host)
        path=urllib.parse.urlunsplit(("","",u.path or "/",u.query,""))
        conn=PinnedHTTPSConnection(host,ip,443,min(TIMEOUT,25))
        conn.request("GET",path,headers={"User-Agent":"Mozilla/5.0 zkc-capability-probe","Accept":"text/html,application/json,text/plain;q=0.9,*/*;q=0.1"})
        r=conn.getresponse()
        if r.status in (301,302,303,307,308):
            loc=r.getheader("Location"); conn.close()
            if not loc: return 0,"redirect without Location"
            return fetch_page(urllib.parse.urljoin(url,loc),redirects+1)
        body=r.read(500001); ctype=(r.getheader("Content-Type") or "").lower(); status=r.status
        conn.close()
        if len(body)>500000: return 0,"page exceeded 500 kB safety limit"
        if ctype and not any(x in ctype for x in ("text/","json","xml","javascript")):
            return 0,"non-text content rejected"
        return status,body.decode("utf-8","replace")
    except Exception as e:
        return 0,str(e)

if not WEB_TEST:
    probe("P6-webtool", "SKIP", "upstream web search is being updated; set OPEN_WEB_TEST=1 for an explicit non-production probe")
    probe("P7-websynth", "SKIP", "upstream web search is being updated; set OPEN_WEB_TEST=1 for an explicit non-production probe")
    probe("P8-webverify", "SKIP", "upstream web search is being updated; set OPEN_WEB_TEST=1 for an explicit non-production probe")
else:
    today=dt.datetime.now(dt.timezone.utc).date()
    q=("Today is %s. Use the provided web search tool before choosing a topic. "
       "Select one notable astronomy, Earth-science, physics, chemistry, or "
       "biomedical result, dataset, or mission update announced within the last "
       "%d days. This is open ended: decide what matters only after searching. "
       "Compare a primary or official source with at least one independent source. "
       "State the central finding, one unresolved uncertainty, and why the evidence "
       "matters. Return ONLY JSON with keys topic, announcement_date, "
       "central_finding, uncertainty, synthesis, and sources. sources must contain "
       "at least two objects with title, url, published_date, role, and "
       "evidence_quote. Use full http(s) URLs.") % (today.isoformat(), WEB_AGE)

    formula_uri="moonshot/web-search:latest"
    formula_base=f"http://127.0.0.1:{GATEWAY_PORT}/v1/formulas/"+formula_uri
    tools_http,tools_raw,tools_meta=request("P6-webtool:declaration",formula_base+"/tools",None,UPSTREAM_HEADERS)
    try:
        formula_tools=json.loads(tools_raw).get("tools") or []
    except Exception:
        formula_tools=[]
    messages=[{"role":"system","content":"You are a careful scientific research analyst."},
              {"role":"user","content":q}]
    calls=fibers_ok=encrypted_results=0
    queries=[]
    final_text=""
    web_finish_reason=None
    web_http=tools_http
    if tools_http==200 and formula_tools:
        for turn in range(6):
            if calls >= 4:
                break
            body={"model":MODEL,"messages":messages,"tools":formula_tools,
                  "reasoning_effort":"max","max_completion_tokens":WEB_MAX}
            if calls==0:
                body["tool_choice"]="required"
            web_http,wr,web_meta=request("P6-webtool:chat-%d" % (turn+1),CHAT_URL,body,UPSTREAM_HEADERS)
            if web_http!=200:
                break
            try:
                wd=json.loads(wr); choice=wd["choices"][0]; msg=choice["message"]
            except Exception:
                web_http=0; break
            tool_calls=msg.get("tool_calls") or []
            web_finish_reason=choice.get("finish_reason")
            if web_finish_reason=="tool_calls" and tool_calls:
                # K3 requires preserved thinking: replay the complete assistant
                # message exactly, including reasoning_content when present.
                messages.append(msg)
                for tc in tool_calls:
                    fn=tc.get("function") or {}
                    calls+=1
                    try:
                        parsed_args=json.loads(fn.get("arguments") or "{}")
                        if isinstance(parsed_args.get("query"),str):
                            queries.append(parsed_args["query"])
                    except Exception:
                        pass
                    fc,fraw,fmeta=request("P6-webtool:fiber-%d" % calls,formula_base+"/fibers",
                                    {"name":fn.get("name"),
                                     "arguments":fn.get("arguments") or "{}"},
                                    UPSTREAM_HEADERS)
                    result=""
                    try:
                        fiber=json.loads(fraw)
                        ctx=fiber.get("context") or {}
                        result=ctx.get("output") or ctx.get("encrypted_output") or ""
                        if fc==200 and fiber.get("status")=="succeeded" and result:
                            fibers_ok+=1
                            if ctx.get("encrypted_output"):
                                encrypted_results+=1
                    except Exception:
                        pass
                    messages.append({"role":"tool","tool_call_id":tc.get("id"),
                                     "content":result or ("fiber_error_http_%s"%fc)})
                continue
            final_text=msg.get("content") or ""
            break

        # Formula tool execution can complete at the call ceiling before a
        # user-facing answer is emitted. Force one bounded, tool-free synthesis
        # turn over the preserved transcript.
        if web_http == 200 and calls > 0 and fibers_ok == calls and not final_text:
            messages.append({"role":"user","content":
                "Using only the web-search results already present above, return the requested JSON now. Do not call any more tools."})
            final_body={"model":MODEL,"messages":messages,
                        "reasoning_effort":"high","max_completion_tokens":WEB_MAX}
            web_http,wr,web_meta=request("P6-webtool:final-synthesis",CHAT_URL,final_body,UPSTREAM_HEADERS)
            if web_http == 200:
                try:
                    wd=json.loads(wr); web_finish_reason=wd["choices"][0].get("finish_reason"); final_text=(wd["choices"][0]["message"].get("content") or "")
                except Exception:
                    final_text=""

    p6_ready = tools_http==200 and bool(formula_tools) and calls>0 and fibers_ok==calls
    if tools_http==429:
        probe("P6-webtool","BLOCKED",rate_detail(tools_raw,tools_meta,"Formula declaration not observed"))
    elif tools_http!=200 or not formula_tools:
        probe("P6-webtool","FAIL","Formula tool declaration fetch http=%s tools=%d"%
              (tools_http,len(formula_tools)))
    elif p6_ready and web_http==200 and web_finish_reason=="length":
        probe("P6-webtool","TRUNCATED",
              "Formula execution completed, but the %d-token synthesis budget ended with finish_reason=length"%WEB_MAX)
    elif web_http==200 and calls>0 and fibers_ok==calls and final_text:
        probe("P6-webtool","PASS",
              "Formula flow complete: %d call(s), %d fiber(s), %d encrypted result(s), %d query string(s)"%
              (calls,fibers_ok,encrypted_results,len(queries)))
    elif p6_ready and web_http==429:
        probe("P6-webtool","BLOCKED",rate_detail(wr,web_meta,
              "Formula calls and fibers completed; final synthesis was capacity-blocked"))
    elif p6_ready:
        probe("P6-webtool","LIMIT",
              "Formula calls and fibers completed, but no final synthesis was emitted after a bounded tool-free turn; chat_http=%s calls=%d fibers=%d"%
              (web_http,calls,fibers_ok))
    else:
        probe("P6-webtool","FAIL",
              "Formula flow incomplete chat_http=%s calls=%d fibers=%d final_chars=%d"%
              (web_http,calls,fibers_ok,len(final_text)))

    obj=parse_json_object(final_text)
    sources=obj.get("sources",[]) if isinstance(obj,dict) else []
    urls=[x.get("url") for x in sources if isinstance(x,dict) and isinstance(x.get("url"),str)]
    hosts={urllib.parse.urlparse(u).hostname for u in urls if u.startswith("https://")}
    uncertainty=(obj or {}).get("uncertainty","") if isinstance(obj,dict) else ""
    synthesis=(obj or {}).get("synthesis","") if isinstance(obj,dict) else ""
    roles={str(x.get("role","")).strip().lower() for x in sources if isinstance(x,dict)}
    date_value=(obj or {}).get("announcement_date","") if isinstance(obj,dict) else ""
    fresh=False
    try:
        announced=dt.date.fromisoformat(str(date_value)[:10])
        age=(today-announced).days
        fresh=-2 <= age <= WEB_AGE+7
    except Exception:
        age=None
    strong=(len(urls)>=2 and len({h for h in hosts if h})>=2 and
            len(uncertainty)>=30 and len(synthesis)>=80 and fresh and
            bool(roles & {"primary","official"}) and "independent" in roles)
    if p6_ready and web_finish_reason=="length":
        probe("P7-websynth","BLOCKED","not evaluated because final synthesis was truncated by the configured output budget")
    elif strong:
        probe("P7-websynth","PASS",
              "%d sources across %d domains; roles and freshness checked (age=%s days)"%
              (len(urls),len(hosts),age))
    elif p6_ready and not final_text:
        probe("P7-websynth","BLOCKED",
              "not evaluated because the Formula tool path completed without a final synthesis")
    else:
        probe("P7-websynth","FAIL",
              "weak synthesis sources=%d domains=%d fresh=%s roles=%s"%
              (len(urls),len(hosts),fresh,",".join(sorted(roles))))
        print("         "+final_text[:300].replace("\n"," "))
    reachable=0
    verified=0
    for src in sources[:4]:
        if not isinstance(src,dict) or not isinstance(src.get("url"),str):
            continue
        status,page=fetch_page(src["url"])
        if 200<=status<400:
            reachable+=1
            quote=src.get("evidence_quote") or ""
            nq=norm_text(quote)
            if len(nq)>=20 and nq[:80] in norm_text(page):
                verified+=1
    if p6_ready and web_finish_reason=="length":
        probe("P8-webverify","BLOCKED","not evaluated because no complete synthesis was available")
    elif reachable>=2 and verified>=1:
        probe("P8-webverify","PASS","%d URLs reachable; %d evidence quote(s) matched"%(reachable,verified))
    elif reachable>=2:
        probe("P8-webverify","LIMIT","%d URLs reachable, but quotes could not be text-matched"%reachable)
    else:
        probe("P8-webverify","LIMIT","only %d cited URL(s) independently reachable"%reachable)

PYEOF
EOF
step "4. protocol probes (raw HTTP, no codex)"
API_BLOCKED=0
PROTO_RC=0
if (( L_PROTOCOL )); then
  PROTO_OUT=$(send_secret "$S_PROTO" "B_PORT=$PORT,B_GATEWAY_PORT=$GATEWAY_PORT,B_MODEL=$MODEL,B_TIMEOUT=$REQUEST_TIMEOUT,B_WEB_TEST=$OPEN_WEB_TEST,B_WEB_AGE=$WEB_MAX_AGE_DAYS,B_MAXOUT=$MAX_OUTPUT_TOKENS,B_REASONING_MAX=$REASONING_OUTPUT_TOKENS,B_REASONING_RETRY_MAX=$REASONING_RETRY_OUTPUT_TOKENS,B_WEB_MAX=$WEB_OUTPUT_TOKENS,B_HTTP_LOG_LEVEL=$KIMI_HTTP_LOG_LEVEL,B_HTTP_BODY_MAX=$KIMI_HTTP_BODY_MAX,B_MIN_INTERVAL_MS=$KIMI_MIN_REQUEST_INTERVAL_MS,B_RATE_RETRIES=$KIMI_RATE_RETRIES,B_RETRY_MAX=$KIMI_RETRY_MAX_SECONDS,B_ENGINE_RETRIES=$KIMI_ENGINE_OVERLOAD_RETRIES,B_ENGINE_BASE=$KIMI_ENGINE_OVERLOAD_BASE_SECONDS,B_TPD_ACTION=$KIMI_TPD_ACTION,B_TPD_WAIT_MAX=$KIMI_TPD_WAIT_MAX_SECONDS,B_TPD_GRACE=$KIMI_TPD_GRACE_SECONDS,B_RESET_TZ=$KIMI_RESET_TIMEZONE" 2>&1 | tee /dev/stderr)
  PROTO_RC=$?
  printf '%s\n' "$PROTO_OUT" | grep -qE '(^TPD_GUARD\||^HTTP\|.*rate_kind=(TPD|QUOTA)(\||$))' && API_BLOCKED=1
else
  PROTO_OUT=$(skipped_layer_output protocol | tee /dev/stderr)
fi
complete_layer_output protocol "$L_PROTOCOL" PROTO_OUT "$PROTO_RC"

# ====================================================== 5. ANTHROPIC PROTOCOL ==
IFS= read -r -d '' S_ANTHRO <<'EOF' || true
set -uo pipefail
if [ "${A_API_BLOCKED:-0}" = 1 ]; then
  for row in     'A1-identity|BLOCKED|not attempted after an earlier Moonshot rate-limit response'     'A2-tool_use|BLOCKED|not attempted after an earlier Moonshot rate-limit response'     'A3-parallel|BLOCKED|not attempted after an earlier Moonshot rate-limit response'     'A4-stream|BLOCKED|not attempted after an earlier Moonshot rate-limit response'     'A4-thinking|BLOCKED|not attempted after an earlier Moonshot rate-limit response'; do
    IFS='|' read -r n v d <<<"$row"; printf '  %-14s %-7s %s
PROBE|%s|%s|%s
' "$n" "$v" "$d" "$n" "$v" "$d"
  done
  exit 0
fi
IFS= read -r K || true
M="${A_MODEL:?}"; GATEWAY_PORT="${A_GATEWAY_PORT:?}"; TIMEOUT="${A_TIMEOUT:-300}"; MAXTOK="${A_MAXTOK:-1024}"
HTTP_LOG_LEVEL="${A_HTTP_LOG_LEVEL:-errors}"; HTTP_BODY_MAX="${A_HTTP_BODY_MAX:-2048}"
MIN_INTERVAL_MS="${A_MIN_INTERVAL_MS:-3200}"; RATE_RETRIES="${A_RATE_RETRIES:-2}"; RETRY_MAX="${A_RETRY_MAX:-60}"
ENGINE_RETRIES="${A_ENGINE_RETRIES:-3}"; ENGINE_BASE="${A_ENGINE_BASE:-5}"
TPD_ACTION="${A_TPD_ACTION:-stop}"; TPD_WAIT_MAX="${A_TPD_WAIT_MAX:-7200}"; TPD_GRACE="${A_TPD_GRACE:-5}"; RESET_TZ="${A_RESET_TZ:-UTC}"
python3 -u - "$M" "$GATEWAY_PORT" "$TIMEOUT" "$MAXTOK" "$HTTP_LOG_LEVEL" "$HTTP_BODY_MAX" "$MIN_INTERVAL_MS" "$RATE_RETRIES" "$RETRY_MAX" "$ENGINE_RETRIES" "$ENGINE_BASE" "$TPD_ACTION" "$TPD_WAIT_MAX" "$TPD_GRACE" "$RESET_TZ" 3<<<"$K" <<'PYEOF'
import email.utils, json, os, re, sys, urllib.request, urllib.error, time, random, datetime as dt
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

K=os.read(3,65536).decode().rstrip("\n")
M, GATEWAY_PORT, TIMEOUT, MAXTOK, HTTP_LOG_LEVEL, HTTP_BODY_MAX = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], int(sys.argv[6])
MIN_INTERVAL = int(sys.argv[7]) / 1000.0
RATE_RETRIES, RETRY_MAX = int(sys.argv[8]), int(sys.argv[9])
ENGINE_RETRIES, ENGINE_BASE = int(sys.argv[10]), int(sys.argv[11])
TPD_ACTION, TPD_WAIT_MAX, TPD_GRACE, RESET_TZ = sys.argv[12], int(sys.argv[13]), int(sys.argv[14]), sys.argv[15]
LAST_REQUEST_STARTED = 0.0
URL = f"http://127.0.0.1:{GATEWAY_PORT}/anthropic/v1/messages"
HDR = {"Authorization": "Bearer " + K,
       "anthropic-version": "2023-06-01", "Content-Type": "application/json"}
TOOLS = [{"name": "get_token", "description": "Returns a secret token",
          "input_schema": {"type": "object", "properties": {}}}]

def probe(name, verdict, detail=""):
    print("  %-14s %-5s %s" % (name, verdict, detail))
    print("PROBE|%s|%s|%s" % (name, verdict, detail))

def _one_line(value, limit=None):
    text = ("" if value is None else str(value)).replace("\r", " ").replace("\n", " ")
    text = re.sub(r"(?i)bearer\s+[A-Za-z0-9._-]+", "Bearer REDACTED", text)
    text = re.sub(r"sk-[A-Za-z0-9._-]{8,}", "sk-REDACTED", text)
    text = re.sub(r"\s+", " ", text).strip().replace("|", "\\u007c")
    if limit is not None and len(text) > limit:
        text = text[:limit] + "...<truncated>"
    return text


def _header_subset(headers):
    wanted = {}
    items = headers.items() if hasattr(headers, "items") else (headers or [])
    for key, value in items:
        lk = str(key).lower()
        if (lk == "date" or lk == "retry-after" or lk == "cf-ray" or
                "request-id" in lk or lk.startswith("x-ratelimit-") or
                lk.startswith("ratelimit-")):
            wanted[lk] = _one_line(value, 512)
    return wanted


def _error_info(raw):
    try:
        document = json.loads(raw or "{}")
    except Exception:
        return {"type": "", "message": "", "request_id": ""}
    error = document.get("error") if isinstance(document, dict) else None
    if not isinstance(error, dict):
        error = {}
    return {
        "type": _one_line(error.get("type", ""), 128),
        "message": _one_line(error.get("message", ""), HTTP_BODY_MAX),
        "request_id": _one_line(document.get("request_id") or error.get("request_id") or "", 256),
    }


def _rate_kind(raw, headers=None):
    info = _error_info(raw)
    material = (raw or "") + " " + json.dumps(headers or {}, sort_keys=True) + " " + info["type"]
    upper = material.upper()
    for name in ("TPD", "TPM", "RPM", "CONCURRENCY"):
        if name in upper:
            return name
    etype = info["type"].lower()
    if etype == "engine_overloaded_error":
        return "ENGINE_OVERLOAD"
    if etype == "exceeded_current_quota_error":
        return "QUOTA"
    if etype == "rate_limit_reached_error":
        return "RATE_LIMIT"
    return "API"


def _http_log(label, status, elapsed_ms, body, raw, headers):
    if HTTP_LOG_LEVEL == "off" or (HTTP_LOG_LEVEL != "all" and 0 < status < 400):
        return
    hs = _header_subset(headers)
    error = _error_info(raw)
    request_id = hs.get("x-request-id") or hs.get("request-id") or hs.get("x-moonshot-request-id") or hs.get("msh-request-id") or error.get("request_id") or "-"
    fields = {
        "label": label,
        "method": "POST",
        "url": URL,
        "status": status,
        "elapsed_ms": elapsed_ms,
        "request_bytes": len(json.dumps(body, separators=(",", ":")).encode()),
        "request": "model=%s cap=%s stream=%s tools=%s messages=%s" % (
            _one_line(body.get("model", "-"), 128), body.get("max_tokens", "-"),
            int(bool(body.get("stream"))), len(body.get("tools") or []), len(body.get("messages") or [])),
        "request_id": request_id,
        "retry_after": hs.get("retry-after", "-"),
        "error_type": error.get("type") or "-",
        "rate_kind": _rate_kind(raw, hs) if status == 429 else "-",
        "headers": json.dumps(hs, sort_keys=True, separators=(",", ":")),
        "body": _one_line(raw, HTTP_BODY_MAX),
    }
    print("HTTP|" + "|".join("%s=%s" % (k, _one_line(v)) for k, v in fields.items()))


def _post_once(label, body, stream=False):
    if stream:
        body = dict(body, stream=True)
    data = json.dumps(body, separators=(",", ":")).encode()
    req = urllib.request.Request(URL, data=data, headers=HDR)
    global LAST_REQUEST_STARTED
    now = time.monotonic()
    wait = LAST_REQUEST_STARTED + MIN_INTERVAL - now
    if wait > 0:
        time.sleep(wait)
    LAST_REQUEST_STARTED = time.monotonic()
    started = LAST_REQUEST_STARTED
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            raw = r.read().decode("utf-8", "replace")
            meta = {"headers": _header_subset(r.headers.items()), "status": r.status}
            _http_log(label, r.status, round((time.monotonic()-started)*1000), body, raw, r.headers.items())
            return r.status, raw, meta
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        meta = {"headers": _header_subset(e.headers.items() if e.headers else []), "status": e.code}
        _http_log(label, e.code, round((time.monotonic()-started)*1000), body, raw, e.headers.items() if e.headers else [])
        return e.code, raw, meta
    except Exception as e:
        raw = str(e)
        meta = {"headers": {}, "status": 0}
        _http_log(label, 0, round((time.monotonic()-started)*1000), body, raw, [])
        return 0, raw, meta


def _retry_after_seconds(headers):
    value = (headers or {}).get("retry-after")
    if not value:
        return None
    try:
        return max(0.0, float(value))
    except Exception:
        try:
            when = email.utils.parsedate_to_datetime(value)
            if when.tzinfo is None:
                when = when.replace(tzinfo=dt.timezone.utc)
            return max(0.0, (when - dt.datetime.now(dt.timezone.utc)).total_seconds())
        except Exception:
            return None


def _tpd_usage(raw):
    text = _error_info(raw).get("message") or (raw or "")
    m = re.search(r"current:\s*([0-9]+)\s*,\s*limit:\s*([0-9]+)", text, re.I)
    if not m:
        return None, None
    return int(m.group(1)), int(m.group(2))


def _reset_deadline(delay):
    when = dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=max(0.0, delay))
    utc_text = when.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    local_text = utc_text
    if ZoneInfo is not None:
        try:
            local_text = when.astimezone(ZoneInfo(RESET_TZ)).replace(microsecond=0).isoformat()
        except Exception:
            pass
    return utc_text, local_text


def _emit_tpd_guard(label, raw, delay, action, reason):
    current, limit = _tpd_usage(raw)
    reset_utc, reset_local = _reset_deadline(delay or 0.0)
    over = (current - limit) if current is not None and limit is not None else "-"
    fields = {
        "label": label, "action": action, "requested_action": TPD_ACTION,
        "reason": reason, "wait_max_seconds": TPD_WAIT_MAX,
        "grace_seconds": TPD_GRACE,
        "current": current if current is not None else "-",
        "limit": limit if limit is not None else "-", "over_by": over,
        "retry_after_seconds": "%.3f" % delay if delay is not None else "-",
        "reset_utc": reset_utc if delay is not None else "-",
        "reset_local": reset_local if delay is not None else "-",
        "timezone": RESET_TZ,
    }
    print("TPD_GUARD|" + "|".join("%s=%s" % (k, _one_line(v)) for k, v in fields.items()))


def post(label, body, stream=False):
    transient_attempts = 0
    tpd_waited = False
    attempt = 0
    while True:
        attempt += 1
        code, raw, meta = _post_once(label, body, stream)
        kind = _rate_kind(raw, meta.get("headers") or {}) if code == 429 else ""
        if code == 429 and kind == "TPD":
            delay = _retry_after_seconds(meta.get("headers") or {})
            can_wait = (TPD_ACTION == "wait" and not tpd_waited and delay is not None and
                        delay + TPD_GRACE <= TPD_WAIT_MAX)
            if can_wait:
                guard_action, guard_reason = "wait", "server-retry-after"
            elif tpd_waited:
                guard_action, guard_reason = "stop-after-wait", "repeated-tpd-after-wait"
            elif TPD_ACTION != "wait":
                guard_action, guard_reason = "stop", "configured-stop"
            elif delay is None:
                guard_action, guard_reason = "stop", "missing-retry-after"
            else:
                guard_action, guard_reason = "stop", "retry-after-exceeds-wait-max"
            _emit_tpd_guard(label, raw, delay, guard_action, guard_reason)
            if can_wait:
                sleep_for = delay + TPD_GRACE
                print("HTTP_RETRY|label=%s|attempt=%d|next_attempt=%d|status=429|rate_kind=TPD|mode=wait-until-reset|sleep_seconds=%.3f" %
                      (_one_line(label), attempt, attempt + 1, sleep_for))
                time.sleep(sleep_for)
                tpd_waited = True
                continue
            return code, raw, meta
        if code == 429 and kind == "QUOTA":
            return code, raw, meta
        if code == 429:
            delay = _retry_after_seconds(meta.get("headers") or {})
            retry_limit = ENGINE_RETRIES if kind == "ENGINE_OVERLOAD" else RATE_RETRIES
            if transient_attempts >= retry_limit:
                return code, raw, meta
            if delay is None:
                if kind == "ENGINE_OVERLOAD":
                    delay = min(float(RETRY_MAX), float(ENGINE_BASE) * (2.0 ** transient_attempts))
                else:
                    return code, raw, meta
        elif code == 0 or code in (502, 503, 504):
            if transient_attempts >= RATE_RETRIES:
                return code, raw, meta
            delay = min(RETRY_MAX, 2.0 ** transient_attempts)
        else:
            return code, raw, meta
        transient_attempts += 1
        delay = min(float(RETRY_MAX), max(delay, MIN_INTERVAL))
        print("HTTP_RETRY|label=%s|attempt=%d|next_attempt=%d|status=%s|rate_kind=%s|sleep_seconds=%.3f" %
              (_one_line(label), attempt, attempt + 1, code, kind or "transport", delay))
        time.sleep(delay)


def parse_anthropic_sse(raw):
    """Reconstruct Anthropic content blocks from an SSE response.

    This deliberately preserves thinking/signature/tool_use blocks so the
    assistant turn can be replayed exactly on the next request.  Looking only
    for text_delta is insufficient for a streamed tool-use turn: the useful
    output may be input_json_delta plus hidden thinking deltas, with no prose.
    """
    blocks, partial_json = {}, {}
    saw_event, message_stop, stop_reason = False, False, None
    errors = []
    for line in raw.splitlines():
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[5:].strip()
        if not payload or payload == "[DONE]":
            continue
        try:
            ev = json.loads(payload)
        except Exception:
            continue
        saw_event = True
        typ = ev.get("type")
        if typ == "content_block_start":
            idx = int(ev.get("index", len(blocks)))
            blocks[idx] = dict(ev.get("content_block") or {})
        elif typ == "content_block_delta":
            idx = int(ev.get("index", 0))
            block = blocks.setdefault(idx, {})
            delta = ev.get("delta") or {}
            dtyp = delta.get("type")
            if dtyp == "text_delta":
                block["text"] = block.get("text", "") + delta.get("text", "")
            elif dtyp == "thinking_delta":
                block["thinking"] = block.get("thinking", "") + delta.get("thinking", "")
            elif dtyp == "signature_delta":
                block["signature"] = block.get("signature", "") + delta.get("signature", "")
            elif dtyp == "input_json_delta":
                partial_json[idx] = partial_json.get(idx, "") + delta.get("partial_json", "")
        elif typ == "content_block_stop":
            idx = int(ev.get("index", 0))
            if idx in partial_json:
                try:
                    blocks.setdefault(idx, {})["input"] = json.loads(partial_json[idx] or "{}")
                except Exception:
                    blocks.setdefault(idx, {})["input"] = {}
                    blocks[idx]["_unparsed_input_json"] = partial_json[idx]
        elif typ == "message_delta":
            stop_reason = (ev.get("delta") or {}).get("stop_reason") or stop_reason
        elif typ == "message_stop":
            message_stop = True
        elif typ == "error":
            errors.append(ev.get("error") or ev)
    ordered = [blocks[i] for i in sorted(blocks)]
    # Private parser diagnostics must never be replayed to the API.
    for block in ordered:
        block.pop("_unparsed_input_json", None)
    text = "".join(b.get("text", "") for b in ordered if b.get("type") == "text")
    return {
        "blocks": ordered,
        "text": text,
        "saw_event": saw_event,
        "message_stop": message_stop,
        "stop_reason": stop_reason,
        "errors": errors,
    }

# ---- shared error classification --------------------------------------------
def rate_detail(raw, meta=None):
    headers = (meta or {}).get("headers") or {}
    error = _error_info(raw)
    kind = _rate_kind(raw, headers)
    extras = []
    if error.get("type"):
        extras.append("error_type=%s" % error["type"])
    if headers.get("retry-after"):
        extras.append("retry_after=%s" % headers["retry-after"])
    request_id = headers.get("x-request-id") or headers.get("request-id") or headers.get("x-moonshot-request-id") or headers.get("msh-request-id") or error.get("request_id")
    if request_id:
        extras.append("request_id=%s" % request_id)
    suffix = ("; remaining Anthropic probes not attempted" if kind in ("TPD", "QUOTA")
              else "; this probe was not completed after bounded retries")
    detail = (("Moonshot engine overloaded (HTTP 429)" if kind == "ENGINE_OVERLOAD"
               else "Moonshot %s rate limit reached (HTTP 429)" % kind) + suffix)
    return detail + (("; " + "; ".join(extras)) if extras else "")

def http_verdict(name, code, raw, meta=None):
    if code == 429:
        probe(name, "BLOCKED", rate_detail(raw, meta))
        return _rate_kind(raw, (meta or {}).get("headers") or {}) in ("TPD", "QUOTA")
    probe(name, "FAIL", "http=%s model=%s" % (code, M))
    print("         " + str(raw)[:280])
    return False

# ---- A1 identity ------------------------------------------------------------
blocked = False
c, raw, meta = post("A1-identity", {"model": M, "max_tokens": min(MAXTOK, 1024),
               "messages": [{"role": "user", "content": "Reply with the single word OK."}]})
try: um = json.loads(raw).get("model", "?")
except Exception: um = "?"
if c == 200:
    probe("A1-identity", "PASS", "messages endpoint live, model_field=" + um)
elif c == 429:
    blocked = http_verdict("A1-identity", c, raw, meta)
else:
    http_verdict("A1-identity", c, raw, meta)

# ---- helper: one GENUINE tool round trip ------------------------------------
# Turn 1 lets the model call the tool for real. Turn 2 replays the assistant
# content verbatim (thinking blocks included) plus a tool_result per call.
def round_trip(user_text, max_turns=4):
    msgs = [{"role": "user", "content": user_text}]
    issued = {}
    for _ in range(max_turns):
        c, raw, meta = post("A2/A3-tool:turn-%d" % (len(msgs)+1), {"model": M, "max_tokens": MAXTOK, "tools": TOOLS,
                       "tool_choice": {"type": "auto"}, "messages": msgs})
        if c != 200:
            return ("HTTP", c, raw, issued, meta)
        d = json.loads(raw)
        content = d.get("content", [])
        calls = [b for b in content if b.get("type") == "tool_use"]
        if not calls:
            text = " ".join(b.get("text", "") for b in content if b.get("type") == "text")
            if d.get("stop_reason") == "max_tokens":
                return ("TRUNCATED", 200, text, issued, meta)
            return ("DONE", 200, text, issued, meta)
        msgs.append({"role": "assistant", "content": content})
        results = []
        for b in calls:
            tok = "ZKCA%d%d" % (int(time.time()), random.randint(1000, 9999))
            issued[b["id"]] = tok
            results.append({"type": "tool_result", "tool_use_id": b["id"], "content": tok})
        msgs.append({"role": "user", "content": results})
    return ("LOOP", 200, "", issued, meta)

# ---- A2 single tool round trip ----------------------------------------------
if blocked:
    probe("A2-tool_use", "BLOCKED", "not attempted after an earlier rate-limit response")
else:
    kind, c, out, issued, meta = round_trip(
        "You must call get_token exactly once. After the result arrives, reply with only that token.")
    if kind == "DONE" and issued and all(t in out for t in issued.values()):
        probe("A2-tool_use", "PASS", "genuine round trip, token echoed")
    elif kind == "HTTP":
        blocked = http_verdict("A2-tool_use", c, out, meta)
    elif kind == "TRUNCATED":
        probe("A2-tool_use", "TRUNCATED", "response stopped at max_tokens before the tool round trip completed")
    elif not issued:
        probe("A2-tool_use", "FAIL", "model never called the tool")
    else:
        probe("A2-tool_use", "FAIL", "token not echoed back")

# ---- A3 multiple tool results -----------------------------------------------
if blocked:
    probe("A3-parallel", "BLOCKED", "not attempted after an earlier rate-limit response")
else:
    kind, c, out, issued, meta = round_trip(
        "You must call get_token exactly three times. Call all three before replying, then return every token.")
    n = len(issued); echoed = sum(1 for t in issued.values() if t in out)
    if kind == "DONE" and n >= 2 and echoed == n:
        probe("A3-parallel", "PASS", "%d calls made, %d/%d tokens echoed" % (n, echoed, n))
    elif kind == "HTTP":
        blocked = http_verdict("A3-parallel", c, out, meta)
    elif kind == "TRUNCATED":
        probe("A3-parallel", "TRUNCATED", "response stopped at max_tokens before all tool results were synthesized")
    elif n < 2:
        probe("A3-parallel", "LIMIT", "model made only %d call(s); nothing dropped, shape untested" % n)
    else:
        probe("A3-parallel", "FAIL", "%d/%d tokens survived" % (echoed, n))

# ---- A4 fully streamed two-turn tool round trip -----------------------------
# Kimi K3 has thinking enabled on the Anthropic-compatible endpoint. Forced
# Anthropic tool choice ("any" or a named tool) is incompatible with manual
# thinking, so use the supported auto mode and an unambiguous instruction.
if blocked:
    probe("A4-stream", "BLOCKED", "not attempted after an earlier rate-limit response")
    probe("A4-thinking", "BLOCKED", "not attempted after an earlier rate-limit response")
else:
    first_body = {
        "model": M,
        "max_tokens": MAXTOK,
        "tools": TOOLS,
        "tool_choice": {"type": "auto"},
        "messages": [{"role": "user", "content":
                      "You must call get_token exactly once. Do not answer directly. "
                      "After its result arrives, reply with only that token."}],
    }
    c1, raw1, meta1 = post("A4-stream:first", first_body, stream=True)
    if c1 != 200:
        if c1 == 429:
            http_verdict("A4-stream", c1, raw1, meta1)
            probe("A4-thinking", "BLOCKED", "stream was blocked by the same rate limit")
        else:
            http_verdict("A4-stream", c1, raw1, meta1)
            probe("A4-thinking", "SKIP", "first streamed request was rejected")
    else:
        st1 = parse_anthropic_sse(raw1)
        calls = [b for b in st1["blocks"] if b.get("type") == "tool_use"]
        think = [b for b in st1["blocks"] if b.get("type") in ("thinking", "redacted_thinking")]
        if think:
            signed = any(bool(b.get("signature")) for b in think if b.get("type") == "thinking")
            probe("A4-thinking", "PASS" if signed else "LIMIT",
                  "%d streamed thinking block(s); signature=%s" % (len(think), signed))
        else:
            probe("A4-thinking", "LIMIT", "stream exposed no thinking block")

        if st1["stop_reason"] == "max_tokens":
            probe("A4-stream", "TRUNCATED", "first stream stopped at max_tokens before the round trip completed")
        elif st1["errors"]:
            probe("A4-stream", "FAIL", "first stream emitted an error event")
            print("         " + str(st1["errors"][0])[:240])
        elif len(calls) != 1:
            probe("A4-stream", "LIMIT",
                  "auto tool choice produced %d tool calls; streaming worked but round trip was not exercised" %
                  len(calls))
        else:
            token = "ZKCAS%d%d" % (int(time.time()), random.randint(1000, 9999))
            msgs = [
                first_body["messages"][0],
                {"role": "assistant", "content": st1["blocks"]},
                {"role": "user", "content": [{"type": "tool_result",
                                               "tool_use_id": calls[0]["id"],
                                               "content": token}]},
            ]
            # "none" is compatible with thinking and prevents a second call.
            final_body = {"model": M, "max_tokens": MAXTOK, "messages": msgs,
                          "tools": TOOLS, "tool_choice": {"type": "none"}}
            c2, raw2, meta2 = post("A4-stream:final", final_body, stream=True)
            if c2 != 200:
                if c2 == 429:
                    http_verdict("A4-stream", c2, raw2, meta2)
                else:
                    http_verdict("A4-stream", c2, raw2, meta2)
            else:
                st2 = parse_anthropic_sse(raw2)
                hit = token in st2["text"]
                if st2["stop_reason"] == "max_tokens":
                    probe("A4-stream", "TRUNCATED", "final stream stopped at max_tokens before emitting the required token")
                elif st2["errors"]:
                    probe("A4-stream", "FAIL", "final stream emitted an error event")
                    print("         " + str(st2["errors"][0])[:240])
                elif hit and st1["message_stop"] and st2["message_stop"]:
                    probe("A4-stream", "PASS",
                          "both SSE turns reconstructed; exact assistant replay accepted; token echoed")
                elif hit:
                    probe("A4-stream", "LIMIT",
                          "token echoed, but message_stop missing first=%s final=%s" %
                          (st1["message_stop"], st2["message_stop"]))
                else:
                    probe("A4-stream", "FAIL",
                          "final SSE text omitted token; stop=%s chars=%d" %
                          (st2["stop_reason"], len(st2["text"])))
                    print("         final text: " + st2["text"][:180])
PYEOF
EOF
step "5. anthropic protocol probes (raw HTTP, no proxy)"
ANTHRO_RC=0
if (( L_ANTHROPIC )); then
  ANTHRO_OUT=$(send_secret "$S_ANTHRO" "A_GATEWAY_PORT=$GATEWAY_PORT,A_MODEL=$ANTHROPIC_API_MODEL,A_TIMEOUT=$REQUEST_TIMEOUT,A_MAXTOK=$ANTHROPIC_OUTPUT_TOKENS,A_API_BLOCKED=$API_BLOCKED,A_HTTP_LOG_LEVEL=$KIMI_HTTP_LOG_LEVEL,A_HTTP_BODY_MAX=$KIMI_HTTP_BODY_MAX,A_MIN_INTERVAL_MS=$KIMI_MIN_REQUEST_INTERVAL_MS,A_RATE_RETRIES=$KIMI_RATE_RETRIES,A_RETRY_MAX=$KIMI_RETRY_MAX_SECONDS,A_ENGINE_RETRIES=$KIMI_ENGINE_OVERLOAD_RETRIES,A_ENGINE_BASE=$KIMI_ENGINE_OVERLOAD_BASE_SECONDS,A_TPD_ACTION=$KIMI_TPD_ACTION,A_TPD_WAIT_MAX=$KIMI_TPD_WAIT_MAX_SECONDS,A_TPD_GRACE=$KIMI_TPD_GRACE_SECONDS,A_RESET_TZ=$KIMI_RESET_TIMEZONE" 2>&1 | tee /dev/stderr)
  ANTHRO_RC=$?
  printf '%s\n' "$ANTHRO_OUT" | grep -qE '(^TPD_GUARD\||^HTTP\|.*rate_kind=(TPD|QUOTA)(\||$))' && API_BLOCKED=1
else
  ANTHRO_OUT=$(skipped_layer_output anthropic | tee /dev/stderr)
fi
complete_layer_output anthropic "$L_ANTHROPIC" ANTHRO_OUT "$ANTHRO_RC"

# ============================================================ 6. CODEX PROBES ==
IFS= read -r -d '' S_CODEX <<'EOF' || true
set -uo pipefail
umask 077
if [ "${B_API_BLOCKED:-0}" = 1 ]; then
  for n in C0-config C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve; do
    printf '  %-14s %-7s %s
PROBE|%s|BLOCKED|%s
' "$n" BLOCKED 'not attempted after a Moonshot rate-limit response' "$n" 'not attempted after a Moonshot rate-limit response'
  done
  exit 0
fi
RUN_ID="${Z_RUN_ID:?}"; ROOT="$HOME/.cache/zkc-kimi-k3/$RUN_ID"
. "$ROOT/runtime.env"
export CODEX_HOME
MODEL="${B_MODEL:?}"; CONTEXT="${B_CONTEXT:?}"; MAXOUT="${B_MAXOUT:?}"; MODEL_DEFAULT="${B_MODEL_DEFAULT:-131072}"
WEB_NATIVE="${B_WEB_NATIVE:-0}"; LONGCTX="${B_LONGCTX:-0}"; SCIENCE="${B_SCIENCE:-1}"
TIMEOUT="${B_TIMEOUT:-300}"; MIN_INTERVAL_MS="${B_MIN_INTERVAL_MS:-3200}"
SIMPLE_EFFORT="${B_SIMPLE_EFFORT:-high}"; COMPLEX_EFFORT="${B_COMPLEX_EFFORT:-max}"
W="$ZKC_WORK"; cd "$W"
TRACE_START=$(wc -l < "$ROOT/gateway-trace.jsonl" 2>/dev/null || echo 0)
p(){ printf '  %-14s %-5s %s\n' "$1" "$2" "${3:-}"; echo "PROBE|$1|$2|${3:-}"; }
CX=("$CODEX_BIN" exec --profile kimi --ephemeral --dangerously-bypass-approvals-and-sandbox
    -c web_search=disabled -c model_reasoning_effort="$SIMPLE_EFFORT" --json)
PACE_FILE="$ROOT/codex-last-call.ns"
pace_cli(){
  python3 - "$PACE_FILE" "$MIN_INTERVAL_MS" <<'PYPACE'
import os, sys, time
path, ms = sys.argv[1], int(sys.argv[2])
now = time.time_ns(); last = 0
try: last = int(open(path).read().strip() or 0)
except Exception: pass
wait = (last + ms*1_000_000 - now) / 1_000_000_000
if wait > 0: time.sleep(wait)
now = time.time_ns()
tmp = path + ".tmp"
with open(tmp, "w") as f: f.write(str(now))
os.replace(tmp, path)
PYPACE
}
run(){ pace_cli; timeout "$TIMEOUT" "${CX[@]}" "$1" 2>&1; }
N=$RANDOM
toml_get(){
  python3 - "$1" "$2" <<'PYTOML'
import re,sys
path,key=sys.argv[1:3]
try:
    import tomllib
    with open(path,"rb") as f: d=tomllib.load(f)
    v=d
    for part in key.split("."): v=v[part]
    if isinstance(v,bool): print("true" if v else "false")
    else: print(v)
except Exception:
    try:
        text=open(path,errors="replace").read()
        m=re.search(r"(?m)^\s*"+re.escape(key)+r"\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^#\n]+))",text)
        if m: print(next(x for x in m.groups() if x is not None).strip())
    except Exception: pass
PYTOML
}

reasoning_continuity(){
  python3 - "$ROOT/gateway-trace.jsonl" "$TRACE_START" "$1" "$2" <<'PYPRESERVE'
import json,sys
path,start,path_prefix,kind=sys.argv[1],int(sys.argv[2]),sys.argv[3],sys.argv[4]
response_key="response_reasoning_hashes" if kind=="reasoning" else "response_thinking_hashes"
request_key="assistant_reasoning_hashes" if kind=="reasoning" else "assistant_thinking_hashes"
rows=[]
try:
    with open(path,errors="replace") as f:
        for i,line in enumerate(f):
            if i < start: continue
            try: row=json.loads(line)
            except Exception: continue
            if str(row.get("path","")).startswith(path_prefix): rows.append(row)
except Exception:
    pass
observed=[]; replayed=[]
for i,row in enumerate(rows):
    for h in row.get(response_key,[]) or []:
        observed.append(h)
        if any(h in (later.get(request_key,[]) or []) for later in rows[i+1:]): replayed.append(h)
if not observed: print("LIMIT|no upstream %s block was observable on the traced client turns"%kind)
elif replayed: print("PASS|%d/%d observed %s block hash(es) were replayed unchanged on a later request"%(len(set(replayed)),len(set(observed)),kind))
else: print("FAIL|%d upstream %s block hash(es) were observed, but none survived unchanged into a later request"%(len(set(observed)),kind))
PYPRESERVE
}

codex_json_status(){
  python3 - "$1" 3<&0 <<'PYCXSTATUS'
import json,os,re,sys
rc=int(sys.argv[1]); raw=os.read(3,64*1024*1024).decode("utf-8","replace")
if rc==124: print("TIMEOUT|Codex exceeded the configured timeout"); raise SystemExit
errs=[]
for line in raw.splitlines():
    try: ev=json.loads(line)
    except Exception: continue
    if not isinstance(ev,dict): continue
    typ=str(ev.get("type","")).lower()
    if typ in ("error","turn.failed","response.failed") or ev.get("is_error") is True:
        errs.append(json.dumps(ev,ensure_ascii=False))
    item=ev.get("item")
    if isinstance(item,dict) and str(item.get("type","")).lower() in ("error","api_error"):
        errs.append(json.dumps(item,ensure_ascii=False))
text=" ".join(errs); low=text.lower()
if re.search(r"\btpd\b|daily token|exceeded_current_quota|current:\s*\d+.*limit:",low): print("QUOTA|"+text[:500])
elif "engine_overloaded_error" in low or "engine is currently overloaded" in low or re.search(r"\b(tpm|rpm|concurrency)\b|rate_limit_reached_error",low): print("RATE|"+text[:500])
elif re.search(r"max[_ -]?(tokens|turns)|token limit|turn limit",low): print("TRUNCATED|"+text[:500])
elif errs or rc!=0: print("ENVERR|"+(text[:500] or "Codex exited %d"%rc))
else: print("OK|")
PYCXSTATUS
}
codex_guard(){
  local name="$1" rc="$2" raw="$3" status kind detail
  status=$(printf '%s' "$raw" | codex_json_status "$rc")
  kind=${status%%|*}; detail=${status#*|}
  case "$kind" in
    OK) return 1;;
    QUOTA) p "$name" BLOCKED "Moonshot QUOTA: ${detail:-hard quota response}"; CODEX_HARD_QUOTA=1; exit 75;;
    RATE) p "$name" BLOCKED "${detail:-Moonshot transient capacity response}";;
    TIMEOUT) p "$name" TIMEOUT "$detail";;
    TRUNCATED) p "$name" TRUNCATED "${detail:-Codex reached a turn/token ceiling}";;
    *) p "$name" ENVERR "${detail:-Codex command/configuration error}";;
  esac
  return 0
}
CODEX_HARD_QUOTA=0

# C0 isolates profile/auth/catalog failures before they cascade into every
# capability probe. A custom provider must not request OpenAI authentication.
echo "       running C0-config ..."
o=$(run "Reply with only the word READY."); C0_RC=$?
if codex_guard C0-config "$C0_RC" "$o"; then
  for n in C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve; do
    p "$n" BLOCKED "not attempted after C0-config did not complete"
  done
  exit 0
fi
C0_MODEL=$(toml_get "$CODEX_HOME/kimi.config.toml" model | tr -d ' \r\n' || true)
if grep -qiE 'sign in with chatgpt|codex login|requires.*openai|authentication.*openai|legacy profile|model catalog.*(failed|error)' <<<"$o"; then
  p C0-config ENVERR "profile/auth/catalog preflight failed"
  tail -10 <<<"$o" | sed 's/^/         /'
  for n in C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve; do
    p "$n" BLOCKED "not attempted after C0-config failure"
  done
  exit 0
elif grep -q READY <<<"$o" && { [ -z "$C0_MODEL" ] || [ "$C0_MODEL" = "$MODEL" ]; }; then
  p C0-config PASS "custom provider loaded without OpenAI authentication; model=${C0_MODEL:-$MODEL}"
else
  p C0-config ENVERR "preflight returned no READY or wrong model=${C0_MODEL:-unset}"
  tail -10 <<<"$o" | sed 's/^/         /'
  for n in C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve; do
    p "$n" BLOCKED "not attempted after C0-config failure"
  done
  exit 0
fi

# C1 one shell command, report its output
echo "       running C1-shell ..."
o=$(run "Run this command: echo ZKCONE$N
Reply with only what it printed."); rc=$?
if codex_guard C1-shell "$rc" "$o"; then :; elif grep -q "ZKCONE$N" <<<"$o"; then p C1-shell PASS; else p C1-shell FAIL; tail -6 <<<"$o" | sed 's/^/         /'; fi

# C2 chain: the second command needs the first one's output
echo "       running C2-chained ..."
o=$(run "Run: echo 7
Then run: expr <that number> \* 6
Reply with only the final number."); rc=$?
if codex_guard C2-chained "$rc" "$o"; then :; elif grep -q '42' <<<"$o"; then p C2-chained PASS "used the first result"; else p C2-chained FAIL "could not feed one result into the next"; tail -6 <<<"$o" | sed 's/^/         /'; fi

# C3 three separate commands in one turn - the shape that broke LiteLLM
echo "       running C3-parallel ..."
o=$(run "Run these as three separate commands: echo AAA$N ; echo BBB$N ; echo CCC$N
Reply with all three outputs."); rc=$?
if codex_guard C3-parallel "$rc" "$o"; then :; else k=0; for x in AAA BBB CCC; do grep -q "$x$N" <<<"$o" && k=$((k+1)); done; [ "$k" = 3 ] && p C3-parallel PASS "3/3" || { p C3-parallel FAIL "$k/3"; tail -8 <<<"$o" | sed 's/^/         /'; }; fi

# C4 create a file
echo "       running C4-create ..."
rm -f made.txt
o=$(run "Create a file named made.txt in the current directory containing exactly: MADE$N
Create that one file and nothing else."); rc=$?
if codex_guard C4-create "$rc" "$o"; then :
elif python3 - "made.txt" "MADE$N" <<'PYFILE'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
if not p.is_file(): raise SystemExit(1)
data = p.read_bytes()
raise SystemExit(0 if data.rstrip(b"\r\n") == sys.argv[2].encode() else 1)
PYFILE
then
  p C4-create PASS "content exact after ignoring terminal newline style ($(wc -c <made.txt) bytes)"
else
  p C4-create FAIL "file absent or contains data beyond the expected text/newline"; tail -8 <<<"$o" | sed 's/^/         /'
fi

# C5 edit an existing file - a different codex tool path from create
echo "       running C5-edit ..."
printf 'keep this line\nOLDVALUE\nkeep this too\n' > edit.txt
o=$(run "In edit.txt, replace the line OLDVALUE with NEW$N
Change nothing else in that file."); rc=$?
printf 'keep this line\nNEW%s\nkeep this too\n' "$N" > "$ZKC_TMP/c5.expected"
if codex_guard C5-edit "$rc" "$o"; then :
elif cmp -s edit.txt "$ZKC_TMP/c5.expected"; then
  p C5-edit PASS "exact in-place patch"
else p C5-edit FAIL "edit changed unexpected content"; tail -8 <<<"$o" | sed 's/^/         /'; fi

# C6 keep going after a command fails
echo "       running C6-recover ..."
o=$(run "Run: cat /definitely-not-here-$N   (this will fail, that is expected)
Then run: echo RECOVERED$N
Reply with only the second output."); rc=$?
if codex_guard C6-recover "$rc" "$o"; then :; elif grep -q "RECOVERED$N" <<<"$o"; then p C6-recover PASS "continued past a failure"; else p C6-recover FAIL "gave up after one error"; tail -8 <<<"$o" | sed 's/^/         /'; fi

# C7: separate what is actually known. The effective profile is a hard fact;
# model-catalog discovery and a large-context acceptance test are different.
echo "       running C7-metadata ..."
o=$(run "Reply with only the word FINE."); rc=$?
if codex_guard C7-config "$rc" "$o"; then
  p C7-catalog BLOCKED "metadata request did not complete"
  p C7-context BLOCKED "metadata request did not complete"
else
EFF=$(toml_get "$CODEX_HOME/kimi.config.toml" model_context_window | tr -d ' \r\n' || true)
EOUT=$(toml_get "$CODEX_HOME/kimi.config.toml" model_max_output_tokens | tr -d ' \r\n' || true)
[ -n "$EFF" ] || EFF=$(grep -m1 '^model_context_window' "$CODEX_HOME/kimi.config.toml" | tr -d ' ' | cut -d= -f2)
[ -n "$EOUT" ] || EOUT=$(grep -m1 '^model_max_output_tokens' "$CODEX_HOME/kimi.config.toml" | tr -d ' ' | cut -d= -f2)
if [ "$EFF" = "$CONTEXT" ] && [ "$EOUT" = "$MAXOUT" ]; then
  p C7-config PASS "effective window=$EFF probe_output_cap=$EOUT; K3 documented default=$MODEL_DEFAULT"
else
  p C7-config FAIL "window=${EFF:-unset}/$CONTEXT max_output=${EOUT:-unset}/$MAXOUT"
fi
if [ ! -s "$CODEX_HOME/models.json" ]; then
  p C7-catalog FAIL "generated model catalog is missing"
elif grep -qiE 'model metadata for .* not found|model catalog.*(failed|error)' <<<"$o"; then
  p C7-catalog FAIL "Codex did not load the generated model catalog"
else
  p C7-catalog PASS "measured Kimi catalog loaded; parallel=true summaries=false search=$WEB_NATIVE"
fi
if [ "${LONGCTX:-0}" -gt 0 ] 2>/dev/null; then
  SENT="CTX${RANDOM}${RANDOM}"
  python3 - "$LONGCTX" "$SENT" > "$ZKC_TMP/zkc-long-prompt.txt" <<'PYCTX'
import sys
n=int(sys.argv[1]); sentinel=sys.argv[2]
print("Remember the sentinel %s. Ignore all filler.\n" % sentinel)
print("alpha " * n)
print("\nReply with only the sentinel %s." % sentinel)
PYCTX
  lo=$(cat "$ZKC_TMP/zkc-long-prompt.txt" | timeout "$TIMEOUT" "$CODEX_BIN" exec --profile kimi --ephemeral \
       --dangerously-bypass-approvals-and-sandbox -c web_search=disabled -c model_reasoning_effort="$SIMPLE_EFFORT" --json - 2>&1); rc=$?
  if codex_guard C7-context "$rc" "$lo"; then :
  elif grep -q "$SENT" <<<"$lo"; then
    p C7-context PASS "accepted approximately $LONGCTX filler tokens and recovered sentinel"
  elif grep -qiE 'context|too many tokens|input.*long' <<<"$lo"; then
    p C7-context FAIL "context rejected near requested size=$LONGCTX"
  else
    p C7-context FAIL "long-context run returned no sentinel"
  fi
else
  p C7-context SKIP "set KIMI_LONG_CONTEXT_TEST_TOKENS for a costly acceptance proof"
fi
fi

# C8: native Codex standalone web search is a provider capability. Custom
# providers default it to false, so do not infer support from a prose URL.
if [ "$WEB_NATIVE" != 1 ]; then
  p C8-nativeweb LIMIT "supports_standalone_web_search=false for this bridge"
else
  o=$(timeout "$TIMEOUT" "$CODEX_BIN" exec --profile kimi --ephemeral --dangerously-bypass-approvals-and-sandbox \
        -c web_search=live -c model_reasoning_effort="$SIMPLE_EFFORT" --json \
        "Search the live web for a scientific announcement from the last 7 days. Return title, date, and URL." 2>&1); rc=$?
  if codex_guard C8-nativeweb "$rc" "$o"; then :
  else
  WEB_EVENT=$(printf '%s\n' "$o" | python3 -c '
import json,sys
for line in sys.stdin:
    try: d=json.loads(line)
    except Exception: continue
    item=d.get("item") if isinstance(d,dict) else None
    if isinstance(item,dict) and item.get("type")=="web_search":
        print(item.get("status") or "web_search"); break
' 2>/dev/null || true)
  if [ -n "$WEB_EVENT" ]; then
    p C8-nativeweb PASS "structured web_search item status=$WEB_EVENT"
  else
    p C8-nativeweb FAIL "provider advertised search but emitted no web_search item"
    tail -6 <<<"$o" | sed 's/^/         /'
  fi
  fi
fi

# C9: reproducible scientific reasoning. The agent must write and run a Python
# calculation; the harness reruns it and independently checks every number.
if [ "$SCIENCE" = 1 ]; then
  echo "       running C9/C10 scientific reasoning suite ..."
  SD="$W/science-codex"
  rm -rf "$SD"
  python3 "$W/science_harness.py" prepare "$SD"
  cd "$SD"
  so=$(cat science_prompt.txt | timeout "$TIMEOUT" "$CODEX_BIN" exec --profile kimi --ephemeral \
      --dangerously-bypass-approvals-and-sandbox -c web_search=disabled \
      -c model_reasoning_effort="$COMPLEX_EFFORT" --json - 2>&1); rc=$?
  if codex_guard C9-science "$rc" "$so"; then
    p C10-reasoning BLOCKED "science request did not complete"
  else
  SCI_OK=0
  if v=$(python3 "$W/science_harness.py" validate "$SD" 2>&1); then
    SCI_OK=1
    p C9-science PASS "$v"
  else
    p C9-science FAIL "$v"
    tail -10 <<<"$so" | sed 's/^/         /'
  fi
  REASON_OBS=$(printf '%s\n' "$so" | python3 -c '
import json,sys
count=chars=0
for line in sys.stdin:
    try: ev=json.loads(line)
    except Exception: continue
    item=ev.get("item") if isinstance(ev,dict) else None
    if isinstance(item,dict) and item.get("type")=="reasoning":
        count+=1
        for key in ("text","summary","content"):
            value=item.get(key)
            if isinstance(value,str): chars+=len(value)
            elif isinstance(value,list): chars+=len(json.dumps(value))
print("%d:%d"%(count,chars))
' 2>/dev/null || echo 0:0)
  RC=${REASON_OBS%%:*}; RCH=${REASON_OBS#*:}
  if [ "${RC:-0}" -gt 0 ]; then
    p C10-reasoning PASS "$RC structured reasoning item(s), approximately $RCH serialized chars"
  elif [ "$SCI_OK" = 1 ]; then
    p C10-reasoning LIMIT "complex science passed, but bridge/Codex exposed no reasoning summary item"
  else
    p C10-reasoning FAIL "science failed and no structured reasoning summary was observable"
  fi
  fi
  cd "$W"
else
  p C9-science SKIP "SCIENCE_TEST=0"
  p C10-reasoning SKIP "SCIENCE_TEST=0"
fi

# C11 verifies the property K3 depends on: an upstream reasoning_content block
# generated on one turn must arrive byte-identically in a later client request.
C11=$(reasoning_continuity "/v1/chat/completions" reasoning)
C11V=${C11%%|*}; C11D=${C11#*|}
p C11-preserve "$C11V" "$C11D"
EOF
resolve_host_codex_bin(){
  local requested="$HOST_CODEX_BIN" candidate npm_prefix
  if [[ "$requested" == */* ]] && [ -x "$requested" ]; then
    printf '%s\n' "$requested"; return 0
  fi
  if candidate=$(command -v "$requested" 2>/dev/null) && [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"; return 0
  fi
  for candidate in     "$HOME/.local/bin/codex"     "/opt/homebrew/bin/codex"     "/usr/local/bin/codex"     "$HOME/.npm-global/bin/codex"     "$HOST_CODEX_PREFIX/node_modules/.bin/codex"; do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  [ "$AUTO_INSTALL_HOST_CODEX" = 1 ] || return 1
  command -v npm >/dev/null 2>&1 || return 1
  mkdir -p "$HOST_CODEX_PREFIX" || return 1
  printf '       host Codex CLI not found; installing @openai/codex@%s under %s ...\n'     "$CODEX_VERSION" "$HOST_CODEX_PREFIX" >&2
  npm install --prefix "$HOST_CODEX_PREFIX" --no-audit --no-fund --loglevel=error     "@openai/codex@$CODEX_VERSION" >/dev/null 2>&1 || return 1
  candidate="$HOST_CODEX_PREFIX/node_modules/.bin/codex"
  [ -x "$candidate" ] || return 1
  printf '%s\n' "$candidate"
}
run_codex_cc_switch_host(){
  local codex_bin route host port W N o rc k active_model active_provider active_base active_context catalog
  codex_bin=$(resolve_host_codex_bin) || {
    printf '  %-14s %-5s %s\nPROBE|C0-config|ENVERR|%s\n' C0-config ENVERR "host Codex CLI not found and user-local install was unavailable" "host Codex CLI not found and user-local install was unavailable"
    for n in C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve; do
      printf '  %-14s %-7s %s\nPROBE|%s|BLOCKED|%s\n' "$n" BLOCKED 'not attempted after C0-config failure' "$n" 'not attempted after C0-config failure'
    done
    return 0
  }
  # Codex has no `config get` subcommand. Read the user-level TOML that
  # CC Switch manages. An explicit KIMI_CC_SWITCH_BASE_URL overrides only the
  # discovered local provider route; no port is treated as fixed truth.
  IFS='|' read -r active_model active_provider active_base active_context catalog < <(
    python3 - "${CODEX_HOME:-$HOME/.codex}/config.toml" <<'PYHOSTCFG'
import sys
path=sys.argv[1]
try:
    import tomllib
    with open(path,"rb") as f: d=tomllib.load(f)
except Exception:
    d={}
model=str(d.get("model") or "")
provider=str(d.get("model_provider") or "")
providers=d.get("model_providers") if isinstance(d.get("model_providers"),dict) else {}
pdata=providers.get(provider) if isinstance(providers.get(provider),dict) else {}
base=str((pdata or {}).get("base_url") or "")
context=str(d.get("model_context_window") or "")
catalog=str(d.get("model_catalog_json") or "")
print("|".join(x.replace("|","") for x in (model,provider,base,context,catalog)))
PYHOSTCFG
  )
  route="${CC_SWITCH_BASE_URL:-$active_base}"
  if [[ ! "$route" =~ ^http://(127\.0\.0\.1|localhost):[0-9]{1,5}(/v1)?/?$ ]]; then
    printf '  %-14s %-5s %s
PROBE|C0-config|ENVERR|%s
' C0-config ENVERR       "could not discover a valid local CC Switch route from Codex config"       "could not discover a valid local CC Switch route from Codex config"
    for n in C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve; do
      printf '  %-14s %-7s %s
PROBE|%s|BLOCKED|%s
' "$n" BLOCKED 'CC Switch route discovery failed' "$n" 'CC Switch route discovery failed'
    done
    return 0
  fi
  read -r host port < <(python3 - "$route" <<'PYURL'
from urllib.parse import urlparse
import sys
u=urlparse(sys.argv[1]); print(u.hostname or "",u.port or 80)
PYURL
)
  if ! python3 - "$host" "$port" <<'PYSOCK'
import socket,sys
try:
    with socket.create_connection((sys.argv[1],int(sys.argv[2])),timeout=2): pass
except OSError: raise SystemExit(1)
PYSOCK
  then
    printf '  %-14s %-5s %s
PROBE|C0-config|ENVERR|%s
' C0-config ENVERR "CC Switch Local Routing is not listening at $route" "CC Switch Local Routing is not listening at $route"
    for n in C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve; do
      printf '  %-14s %-7s %s
PROBE|%s|BLOCKED|%s
' "$n" BLOCKED 'enable CC Switch routing and Codex takeover first' "$n" 'enable CC Switch routing and Codex takeover first'
    done
    return 0
  fi

  W=$(mktemp -d "${TMPDIR:-/tmp}/zkc-kimi-codex-ccswitch.XXXXXX") || return 1
  trap 'rm -rf -- "$W"' RETURN
  git -C "$W" init -q 2>/dev/null || true
  N=$RANDOM
  p_host(){ printf '  %-14s %-5s %s\n' "$1" "$2" "${3:-}"; echo "PROBE|$1|$2|${3:-}"; }
  pace_host(){ sleep 3.2; }
  host_codex_once(){
    local prompt="$1" effort="${2:-$CODEX_SIMPLE_REASONING_EFFORT}" web="${3:-disabled}" json_mode="${4:-0}"
    local extra=()
    [ "$json_mode" = 1 ] && extra+=(--json)
    pace_host
    if command -v timeout >/dev/null 2>&1; then
      (cd "$W" && timeout "$REQUEST_TIMEOUT" "$codex_bin" exec --ephemeral --dangerously-bypass-approvals-and-sandbox \
        -c "web_search=$web" -c "model_reasoning_effort=$effort" "${extra[@]}" "$prompt") 2>&1
    elif command -v gtimeout >/dev/null 2>&1; then
      (cd "$W" && gtimeout "$REQUEST_TIMEOUT" "$codex_bin" exec --ephemeral --dangerously-bypass-approvals-and-sandbox \
        -c "web_search=$web" -c "model_reasoning_effort=$effort" "${extra[@]}" "$prompt") 2>&1
    else
      (cd "$W" && "$codex_bin" exec --ephemeral --dangerously-bypass-approvals-and-sandbox \
        -c "web_search=$web" -c "model_reasoning_effort=$effort" "${extra[@]}" "$prompt") 2>&1
    fi
  }
  host_codex_call(){
    local prompt="$1" effort="${2:-$CODEX_SIMPLE_REASONING_EFFORT}" web="${3:-disabled}" json_mode="${4:-0}"
    local attempt=0 out rc delay
    while :; do
      out=$(host_codex_once "$prompt" "$effort" "$web" "$json_mode"); rc=$?
      if grep -qiE 'engine_overloaded_error|engine is currently overloaded' <<<"$out" && \
         [ "$attempt" -lt "$KIMI_ENGINE_OVERLOAD_RETRIES" ]; then
        delay=$(( KIMI_ENGINE_OVERLOAD_BASE_SECONDS * (1 << attempt) ))
        [ "$delay" -gt "$KIMI_RETRY_MAX_SECONDS" ] && delay="$KIMI_RETRY_MAX_SECONDS"
        attempt=$((attempt+1))
        printf 'HOST_RETRY|client=codex|reason=engine_overload|attempt=%d|sleep_seconds=%d\n' "$attempt" "$delay" >&2
        sleep "$delay"
        continue
      fi
      printf '%s\n' "$out"
      return "$rc"
    done
  }
  host_codex_stdin_once(){
    local file="$1" effort="${2:-$CODEX_SIMPLE_REASONING_EFFORT}" web="${3:-disabled}"
    pace_host
    if command -v timeout >/dev/null 2>&1; then
      (cd "$W" && timeout "$REQUEST_TIMEOUT" "$codex_bin" exec --ephemeral --dangerously-bypass-approvals-and-sandbox \
        -c "web_search=$web" -c "model_reasoning_effort=$effort" - <"$file") 2>&1
    elif command -v gtimeout >/dev/null 2>&1; then
      (cd "$W" && gtimeout "$REQUEST_TIMEOUT" "$codex_bin" exec --ephemeral --dangerously-bypass-approvals-and-sandbox \
        -c "web_search=$web" -c "model_reasoning_effort=$effort" - <"$file") 2>&1
    else
      (cd "$W" && "$codex_bin" exec --ephemeral --dangerously-bypass-approvals-and-sandbox \
        -c "web_search=$web" -c "model_reasoning_effort=$effort" - <"$file") 2>&1
    fi
  }
  host_codex_stdin(){
    local file="$1" effort="${2:-$CODEX_SIMPLE_REASONING_EFFORT}" web="${3:-disabled}"
    local attempt=0 out rc delay
    while :; do
      out=$(host_codex_stdin_once "$file" "$effort" "$web"); rc=$?
      if grep -qiE 'engine_overloaded_error|engine is currently overloaded' <<<"$out" && \
         [ "$attempt" -lt "$KIMI_ENGINE_OVERLOAD_RETRIES" ]; then
        delay=$(( KIMI_ENGINE_OVERLOAD_BASE_SECONDS * (1 << attempt) ))
        [ "$delay" -gt "$KIMI_RETRY_MAX_SECONDS" ] && delay="$KIMI_RETRY_MAX_SECONDS"
        attempt=$((attempt+1))
        printf 'HOST_RETRY|client=codex|reason=engine_overload|attempt=%d|sleep_seconds=%d\n' "$attempt" "$delay" >&2
        sleep "$delay"
        continue
      fi
      printf '%s\n' "$out"
      return "$rc"
    done
  }
  block_rest(){
    local reason="$1" n
    for n in C1-shell C2-chained C3-parallel C4-create C5-edit C6-recover C7-config C7-catalog C7-context C8-nativeweb C9-science C10-reasoning C11-preserve; do
      p_host "$n" BLOCKED "$reason"
    done
  }

  if [ "$active_model" != "$CC_SWITCH_MODEL" ]; then
    p_host C0-config FAIL "CC Switch/Codex active model=${active_model:-unset}; expected exact model=$CC_SWITCH_MODEL"
    block_rest "not attempted until CC Switch menu and request model both map to $CC_SWITCH_MODEL"
    return 0
  fi
  if [ -n "$active_base" ] && [ "${active_base%/}" != "${route%/}" ]; then
    p_host C0-config FAIL "active provider route=$active_base; expected $route"
    block_rest "not attempted until Codex takeover points at the CC Switch local route"
    return 0
  fi
  o=$(host_codex_call "Reply with only the word READY."); rc=$?
  if grep -qiE '(^|[^0-9])429([^0-9]|$)|rate[_ -]?limit|TPD|TPM|RPM' <<<"$o"; then
    p_host C0-config BLOCKED "Moonshot rate limit returned through CC Switch"
    block_rest "not attempted after C0 rate limit"
    return 0
  fi
  if [ "$rc" -ne 0 ] || ! grep -q READY <<<"$o"; then
    p_host C0-config FAIL "CC Switch route/model preflight did not return READY (exit=$rc)"
    tail -8 <<<"$o" | sed 's/^/         /'
    block_rest "not attempted after C0-config failure"
    return 0
  fi
  p_host C0-config PASS "host Codex -> CC Switch route; model=$active_model provider=${active_provider:-managed}"

  o=$(host_codex_call "Run this command: echo ZKCONE$N. Reply with only what it printed.")
  grep -q "ZKCONE$N" <<<"$o" && p_host C1-shell PASS || { p_host C1-shell FAIL; tail -6 <<<"$o" | sed 's/^/         /'; }

  o=$(host_codex_call "Run: echo 7. Then run: expr <that number> \\* 6. Reply with only the final number.")
  grep -q '42' <<<"$o" && p_host C2-chained PASS "used the first result" || { p_host C2-chained FAIL; tail -6 <<<"$o" | sed 's/^/         /'; }

  o=$(host_codex_call "Run these as three separate commands: echo AAA$N ; echo BBB$N ; echo CCC$N. Reply with all three outputs.")
  k=0; for x in AAA BBB CCC; do grep -q "$x$N" <<<"$o" && k=$((k+1)); done
  [ "$k" = 3 ] && p_host C3-parallel PASS "3/3" || { p_host C3-parallel FAIL "$k/3"; tail -8 <<<"$o" | sed 's/^/         /'; }

  rm -f "$W/made.txt"
  o=$(host_codex_call "Create made.txt in the current directory containing exactly MADE$N. Create that one file and nothing else.")
  if python3 - "$W/made.txt" "MADE$N" <<'PYFILE'
import pathlib, sys
p=pathlib.Path(sys.argv[1])
if not p.is_file(): raise SystemExit(1)
raise SystemExit(0 if p.read_bytes().rstrip(b"\r\n") == sys.argv[2].encode() else 1)
PYFILE
  then p_host C4-create PASS "content exact after ignoring terminal newline style"
  else p_host C4-create FAIL "file absent or contains data beyond expected text/newline"; tail -8 <<<"$o" | sed 's/^/         /'; fi

  printf 'keep this line\nOLDVALUE\nkeep this too\n' > "$W/edit.txt"
  o=$(host_codex_call "In edit.txt replace the line OLDVALUE with NEW$N. Change nothing else.")
  printf 'keep this line\nNEW%s\nkeep this too\n' "$N" > "$W/edit.expected"
  cmp -s "$W/edit.txt" "$W/edit.expected" && p_host C5-edit PASS "exact in-place patch" || { p_host C5-edit FAIL "unexpected file content"; tail -8 <<<"$o" | sed 's/^/         /'; }

  o=$(host_codex_call "Run: cat /definitely-not-here-$N (failure expected). Then run: echo RECOVERED$N. Reply with only the second output.")
  grep -q "RECOVERED$N" <<<"$o" && p_host C6-recover PASS || { p_host C6-recover FAIL; tail -8 <<<"$o" | sed 's/^/         /'; }

  p_host C7-config PASS "CC Switch route=$route exact_model=$active_model"
  if [ -n "$catalog" ] && [ -s "$catalog" ] && python3 - "$catalog" "$CC_SWITCH_MODEL" <<'PYCAT'
import json, sys
try: d=json.load(open(sys.argv[1]))
except Exception: raise SystemExit(1)
needle=sys.argv[2]
def walk(x):
    if isinstance(x, dict):
        if any(x.get(k)==needle for k in ("slug","id","model","name")): return True
        return any(walk(v) for v in x.values())
    if isinstance(x, list): return any(walk(v) for v in x)
    return False
raise SystemExit(0 if walk(d) else 1)
PYCAT
  then p_host C7-catalog PASS "CC Switch catalog maps $CC_SWITCH_MODEL"
  else p_host C7-catalog LIMIT "runtime model is exact, but model_catalog_json was not inspectable"
  fi
  if [ -n "$active_context" ] && [ "$active_context" != "$CONTEXT_WINDOW" ]; then
    p_host C7-context FAIL "configured context=$active_context expected=$CONTEXT_WINDOW"
  elif [ "$LONG_CONTEXT_TOKENS" -gt 0 ]; then
    SENT="CTX${RANDOM}${RANDOM}"
    python3 - "$LONG_CONTEXT_TOKENS" "$SENT" > "$W/long-context.txt" <<'PYCTX'
import sys
n=int(sys.argv[1]); sentinel=sys.argv[2]
print("Remember the sentinel %s. Ignore all filler." % sentinel)
print("alpha " * n)
print("Reply with only the sentinel %s." % sentinel)
PYCTX
    o=$(host_codex_stdin "$W/long-context.txt")
    if grep -q "$SENT" <<<"$o"; then
      p_host C7-context PASS "configured=${active_context:-not exposed}; accepted approximately $LONG_CONTEXT_TOKENS filler tokens"
    elif grep -qiE 'context|too many tokens|input.*long' <<<"$o"; then
      p_host C7-context FAIL "long-context input rejected near requested size=$LONG_CONTEXT_TOKENS"
    else
      p_host C7-context FAIL "long-context run returned no sentinel"
      tail -8 <<<"$o" | sed 's/^/         /'
    fi
  else
    p_host C7-context SKIP "KIMI_LONG_CONTEXT_TEST_TOKENS=0"
  fi

  if [ "$OPEN_WEB_TEST" = 1 ]; then
    o=$(host_codex_call "Use live web search to find one scientific announcement from the last 7 days. Return its title, publication date, and URL." "$CODEX_SIMPLE_REASONING_EFFORT" live 1)
    WEB_EVENT=$(printf '%s\n' "$o" | python3 -c '
import json,sys
for line in sys.stdin:
    try: d=json.loads(line)
    except Exception: continue
    item=d.get("item") if isinstance(d,dict) else None
    if isinstance(item,dict) and item.get("type")=="web_search":
        print(item.get("status") or "web_search"); break
' 2>/dev/null || true)
    WEB_URL=$(grep -Eo 'https://[^[:space:]"<>]+' <<<"$o" | head -1 || true)
    if [ -n "$WEB_EVENT" ]; then
      p_host C8-nativeweb PASS "structured web_search item status=$WEB_EVENT"
    elif grep -qiE 'web search.*(unsupported|disabled)|supports_standalone_web_search=false|unknown.*web_search' <<<"$o"; then
      p_host C8-nativeweb LIMIT "CC Switch Chat-routing path does not expose a native Codex web_search item"
    elif [ -n "$WEB_URL" ]; then
      p_host C8-nativeweb LIMIT "web result text contained a URL, but no structured web_search item was exposed"
    else
      p_host C8-nativeweb FAIL "live web probe returned neither a structured event nor a source URL"
      tail -8 <<<"$o" | sed 's/^/         /'
    fi
  else
    p_host C8-nativeweb SKIP "OPEN_WEB_TEST=0"
  fi

  if [ "$SCIENCE_TEST" = 1 ]; then
    SD="$W/science-codex"; rm -rf "$SD"; mkdir -p "$SD"
    EXPECTED_EA=$(python3 - <<'PYEXP'
import math
R=8.314462618; k1=0.0025; k2=0.0170; t1=298.15; t2=338.15
print(f"{R*math.log(k2/k1)/(1/t1-1/t2)/1000:.3f}")
PYEXP
)
    o=$(host_codex_call "Work in the science-codex directory. Create solve.py that computes the Arrhenius activation energy Ea = R*ln(k2/k1)/(1/T1-1/T2)/1000 using R=8.314462618 J/(mol K), k1=0.0025, k2=0.0170, T1=298.15 K, and T2=338.15 K. Run it. It must write result.json containing exactly one JSON key ea_kj_mol whose numeric value is rounded to three decimals. Do not hard-code the final value." "$CODEX_COMPLEX_REASONING_EFFORT" disabled 1)
    SCI_OK=0
    if python3 - "$SD/solve.py" "$SD/result.json" "$EXPECTED_EA" <<'PYSCI'
import json,pathlib,subprocess,sys
script,result,expected=sys.argv[1],sys.argv[2],float(sys.argv[3])
if not pathlib.Path(script).is_file(): raise SystemExit(1)
subprocess.run([sys.executable,script],cwd=str(pathlib.Path(script).parent),
               check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
d=json.load(open(result))
if set(d)!={"ea_kj_mol"}: raise SystemExit(1)
raise SystemExit(0 if abs(float(d["ea_kj_mol"])-expected)<0.0005 else 1)
PYSCI
    then
      SCI_OK=1
      p_host C9-science PASS "independently reran solve.py; Ea=$EXPECTED_EA kJ/mol"
    else
      p_host C9-science FAIL "code/result missing or independently computed value was incorrect"
      tail -10 <<<"$o" | sed 's/^/         /'
    fi
    REASON_OBS=$(printf '%s\n' "$o" | python3 -c '
import json,sys
count=chars=0
for line in sys.stdin:
    try: ev=json.loads(line)
    except Exception: continue
    item=ev.get("item") if isinstance(ev,dict) else None
    if isinstance(item,dict) and item.get("type") in ("reasoning","reasoning_summary"):
        count+=1; chars+=len(json.dumps(item,ensure_ascii=False))
print(f"{count}:{chars}")
' 2>/dev/null || echo 0:0)
    RCNT=${REASON_OBS%%:*}; RCHARS=${REASON_OBS#*:}
    if [ "${RCNT:-0}" -gt 0 ]; then
      p_host C10-reasoning PASS "$RCNT structured reasoning item(s), approximately $RCHARS serialized chars"
    elif [ "$SCI_OK" = 1 ]; then
      p_host C10-reasoning LIMIT "complex science passed, but CC Switch/Codex exposed no reasoning summary item"
    else
      p_host C10-reasoning FAIL "science failed and no structured reasoning item was observable"
    fi
  else
    p_host C9-science SKIP "SCIENCE_TEST=0"
    p_host C10-reasoning SKIP "SCIENCE_TEST=0"
  fi
  p_host C11-preserve ENVERR "host CC Switch compatibility mode is outside the in-Sprite wire trace; use KIMI_CODEX_ROUTER=codeproxy for preservation verification"
  rm -rf -- "$W"
  trap - RETURN
}

step "6. codex capability probes"
CODEX_RC=0
if (( L_CODEX )); then
  if (( CODEX_USES_CC_SWITCH )); then
    CODEX_OUT=$(run_codex_cc_switch_host 2>&1 | tee /dev/stderr)
    CODEX_RC=$?
  else
    CODEX_OUT=$(run_remote "$S_CODEX" "Z_RUN_ID=$RUN_ID,B_TIMEOUT=$REQUEST_TIMEOUT,B_MODEL=$MODEL,B_CONTEXT=$CONTEXT_WINDOW,B_MAXOUT=$CLIENT_OUTPUT_TOKENS,B_MODEL_DEFAULT=$MODEL_DEFAULT_MAX_OUTPUT_TOKENS,B_WEB_NATIVE=$CODEX_STANDALONE_WEB_SEARCH,B_LONGCTX=$LONG_CONTEXT_TOKENS,B_SCIENCE=$SCIENCE_TEST,B_API_BLOCKED=$API_BLOCKED,B_MIN_INTERVAL_MS=$KIMI_MIN_REQUEST_INTERVAL_MS,B_SIMPLE_EFFORT=$CODEX_SIMPLE_REASONING_EFFORT,B_COMPLEX_EFFORT=$CODEX_COMPLEX_REASONING_EFFORT" 2>&1 | tee /dev/stderr)
    CODEX_RC=$?
  fi
  printf '%s\n' "$CODEX_OUT" | grep -qE '(^TPD_GUARD\||^PROBE\|C[^|]*\|BLOCKED\|Moonshot (TPD|QUOTA)|exceeded_current_quota_error)' && API_BLOCKED=1
else
  CODEX_OUT=$(skipped_layer_output codex | tee /dev/stderr)
fi
complete_layer_output codex "$L_CODEX" CODEX_OUT "$CODEX_RC"


# ========================================================= 7. CLAUDE CODE ==
IFS= read -r -d '' S_CLAUDE <<'EOF' || true
set -uo pipefail
umask 077
ONLY="${A_ONLY:-all}"
want(){ [ "$ONLY" = all ] || case ",$ONLY," in (*",$1,"*) return 0;; (*) return 1;; esac; }
if [ "${A_API_BLOCKED:-0}" = 1 ]; then
  for n in L1-shell L2-chained L3-parallel L4-create L5-edit L6-recover L7-websearch L8-science L9-reasoning L10-preserve; do
    want "$n" || continue
    printf '  %-14s %-7s %s
PROBE|%s|BLOCKED|%s
' "$n" BLOCKED 'not attempted after a Moonshot rate-limit response' "$n" 'not attempted after a Moonshot rate-limit response'
  done
  exit 0
fi
IFS= read -r K || true; [ -n "${K:-}" ] || { echo 'PROBE|L0-auth|FAIL|no key received'; exit 0; }
RUN_ID="${Z_RUN_ID:?}"; ROOT="$HOME/.cache/zkc-kimi-k3/$RUN_ID"
. "$ROOT/runtime.env"
CMODEL="${A_MODEL:?}"; GATEWAY_PORT="${A_GATEWAY_PORT:?}"; CONTEXT="${A_CONTEXT:-1048576}"; TIMEOUT="${A_TIMEOUT:-300}"
WEB_TEST="${A_WEB_TEST:-1}"; WEB_AGE="${A_WEB_AGE:-60}"; SCIENCE="${A_SCIENCE:-0}"
MIN_INTERVAL_MS="${A_MIN_INTERVAL_MS:-3200}"
ENGINE_RETRIES="${A_ENGINE_RETRIES:-3}"; ENGINE_BASE="${A_ENGINE_BASE:-5}"; RETRY_MAX="${A_RETRY_MAX:-60}"
W="$ROOT/probe-cc"; mkdir -p "$W" "$ZKC_TMP/claude"; chmod 700 "$W" "$ZKC_TMP/claude"
cd "$W"; git init -q 2>/dev/null || true
TRACE_START="${A_TRACE_START:-$(wc -l < "$ROOT/gateway-trace.jsonl" 2>/dev/null || echo 0)}"
echo "       claude $($CLAUDE_BIN --version 2>/dev/null || echo MISSING)"
echo "       claude invocation: prompt immediately follows -p; --tools restricts built-ins; strict MCP mode disables MCP discovery"

# Kimi's documented Claude Code configuration. This verifier runs in a
# disposable Sprite and disables Claude's optional bubblewrap-based subprocess
# scrubbing so the agent can execute the capability probes without requiring
# bubblewrap inside the Sprite.
export ANTHROPIC_BASE_URL="http://127.0.0.1:$GATEWAY_PORT/anthropic"
export ANTHROPIC_MODEL="$CMODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$CMODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$CMODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$CMODEL"
export ANTHROPIC_DEFAULT_FABLE_MODEL="$CMODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$CMODEL"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="$CONTEXT"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1
export CLAUDE_CODE_EFFORT_LEVEL=max
export ENABLE_TOOL_SEARCH=false
export CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=0
export CLAUDE_CODE_SKIP_PROMPT_HISTORY=1
export CLAUDE_CODE_TMPDIR="$ZKC_TMP/claude"
export DISABLE_TELEMETRY=1

p(){ printf '  %-14s %-5s %s\n' "$1" "$2" "${3:-}"; echo "PROBE|$1|$2|${3:-}"; }
PACE_FILE="$ROOT/claude-last-call.ns"
pace_cli(){
  python3 - "$PACE_FILE" "$MIN_INTERVAL_MS" <<'PYPACE'
import os, sys, time
path, ms = sys.argv[1], int(sys.argv[2])
now = time.time_ns(); last = 0
try: last = int(open(path).read().strip() or 0)
except Exception: pass
wait = (last + ms*1_000_000 - now) / 1_000_000_000
if wait > 0: time.sleep(wait)
now = time.time_ns(); tmp = path + ".tmp"
with open(tmp, "w") as f: f.write(str(now))
os.replace(tmp, path)
PYPACE
}
claude_call(){
  local tools="$1" prompt="$2"; shift 2
  pace_cli
  # `--allowedTools` accepts a variadic list. Putting the prompt after it can
  # make Claude Code parse the prompt itself as another permission rule. Pass
  # the print-mode prompt immediately after `-p`, use `--tools` to restrict the
  # built-ins, and rely on strict MCP mode to load no MCP servers.
  ANTHROPIC_AUTH_TOKEN="$K" timeout "$TIMEOUT" "$CLAUDE_BIN" -p "$prompt" \
    --dangerously-skip-permissions --strict-mcp-config --disable-slash-commands \
    --no-session-persistence --tools "$tools" --output-format json "$@"
}
CLAUDE_QUOTA_BLOCKED=0
CLAUDE_QUOTA_DETAIL=""
CLAUDE_CONFIG_BLOCKED=0
CLAUDE_CONFIG_DETAIL=""
CLAUDE_LAST=""
CLAUDE_TRANSIENT_DETAIL=""
claude_json_status(){
  python3 - "$1" 3<&0 <<'PYSTATUS'
import json,os,re,sys
rc=int(sys.argv[1]); raw=os.read(3,64*1024*1024).decode("utf-8","replace")
if rc==124:
    print("TIMEOUT|Claude Code exceeded the configured timeout"); raise SystemExit
objects=[]
for line in raw.splitlines():
    try: objects.append(json.loads(line))
    except Exception: pass
if not objects:
    try: objects=[json.loads(raw)]
    except Exception: objects=[]
errs=[]
def walk(x, error_context=False):
    if isinstance(x,dict):
        ec=error_context or x.get("is_error") is True or str(x.get("type","")).lower() in ("error","api_error")
        if ec:
            for k in ("error","message","result","detail"):
                v=x.get(k)
                if isinstance(v,str): errs.append(v)
                elif isinstance(v,dict): walk(v,True)
        for v in x.values(): walk(v,ec)
    elif isinstance(x,list):
        for v in x: walk(v,error_context)
for obj in objects: walk(obj)
text=" ".join(errs)
l=text.lower()
if re.search(r"\btpd\b|daily token|exceeded_current_quota|current:\s*\d+.*limit:",l):
    print("QUOTA|"+text[:500]); raise SystemExit
if "engine_overloaded_error" in l or "engine is currently overloaded" in l:
    print("ENGINE|"+text[:500]); raise SystemExit
if re.search(r"\b(tpm|rpm|concurrency)\b|rate_limit_reached_error",l):
    print("RATE|"+text[:500]); raise SystemExit
if errs or rc!=0:
    print("ERROR|"+(text[:500] or ("Claude Code exited %d"%rc))); raise SystemExit
print("OK|")
PYSTATUS
}
claude_capture(){
  local tools="$1"; shift
  local attempt=0 rc delay status kind detail
  if [ "$CLAUDE_QUOTA_BLOCKED" = 1 ]; then return 75; fi
  if [ "$CLAUDE_CONFIG_BLOCKED" = 1 ]; then return 76; fi
  while :; do
    CLAUDE_LAST=$(claude_call "$tools" "$@" 2>&1); rc=$?
    status=$(printf '%s' "$CLAUDE_LAST" | claude_json_status "$rc")
    kind=${status%%|*}; detail=${status#*|}
    if [ "$kind" = ENGINE ] && [ "$attempt" -lt "$ENGINE_RETRIES" ]; then
      delay=$(( ENGINE_BASE * (1 << attempt) )); [ "$delay" -gt "$RETRY_MAX" ] && delay="$RETRY_MAX"
      attempt=$((attempt+1))
      printf 'CLIENT_RETRY|client=claude|reason=engine_overload|attempt=%d|sleep_seconds=%d\n' "$attempt" "$delay" >&2
      sleep "$delay"; continue
    fi
    break
  done
  case "$kind" in
    OK) return 0;;
    QUOTA) CLAUDE_QUOTA_BLOCKED=1; CLAUDE_QUOTA_DETAIL="Moonshot TPD/quota limit reached: ${detail:-structured API error}"; return 75;;
    ENGINE|RATE) CLAUDE_TRANSIENT_DETAIL="Moonshot transient capacity/rate response remained after bounded retries: ${detail:-structured API error}"; return 78;;
    TIMEOUT) CLAUDE_TRANSIENT_DETAIL="$detail"; return 77;;
  esac
  if [ "$rc" -ne 0 ] && grep -qiE 'Input must be provided|unknown option|unknown argument|Ignoring --allowedTools|Wildcard tool name|not supported in allow rules|invalid.*tool|authentication.*conflict' <<<"$CLAUDE_LAST"; then
    CLAUDE_CONFIG_BLOCKED=1
    CLAUDE_CONFIG_DETAIL=$(tail -3 <<<"$CLAUDE_LAST" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
    return 76
  fi
  return "$rc"
}
quota_detail(){ printf '%s' "${CLAUDE_QUOTA_DETAIL:-Moonshot hard quota response; probe not completed}"; }
transient_detail(){ printf '%s' "${CLAUDE_TRANSIENT_DETAIL:-Moonshot transient capacity response; probe not completed}"; }
config_detail(){ printf '%s' "Claude Code invocation/configuration error; remaining Claude probes not attempted: ${CLAUDE_CONFIG_DETAIL:-see prior probe}"; }
show_tail(){ tail -8 <<<"$1" | sed 's/^/         /'; }
claude_stream_status(){
  local file="$1" rc="$2"
  python3 - "$file" "$rc" <<'PYSTREAM'
import json,re,sys
path,rc=sys.argv[1],int(sys.argv[2])
if rc==124: print("TIMEOUT|Claude Code exceeded the configured timeout"); raise SystemExit
errs=[]; saw_result=False; result_subtypes=[]
for line in open(path,errors="replace"):
    try: ev=json.loads(line)
    except Exception: continue
    if isinstance(ev,dict) and ev.get("type")=="result":
        saw_result=True
        if isinstance(ev.get("subtype"),str): result_subtypes.append(ev["subtype"])
        if ev.get("is_error"):
            for k in ("error","result","message","subtype"):
                v=ev.get(k)
                if isinstance(v,str): errs.append(v)
    elif isinstance(ev,dict) and ev.get("type") in ("error","api_error"):
        errs.append(json.dumps(ev,ensure_ascii=False))
text=" ".join(errs); low=text.lower(); subtype_text=" ".join(result_subtypes).lower()
if re.search(r"\btpd\b|daily token|exceeded_current_quota|current:\s*\d+.*limit:",low): print("QUOTA|"+text[:500])
elif "engine_overloaded_error" in low or "engine is currently overloaded" in low or re.search(r"\b(tpm|rpm|concurrency)\b|rate_limit_reached_error",low): print("RATE|"+text[:500])
elif re.search(r"max[_ -]?(tokens|turns)|turn limit|token limit",low+" "+subtype_text): print("TRUNCATED|"+(text[:500] or "Claude Code reached its configured turn/token ceiling: "+subtype_text))
elif errs or rc!=0: print("ERROR|"+(text[:500] or "Claude Code exited %d"%rc))
elif saw_result: print("OK|")
else: print("ERROR|no terminal result event")
PYSTREAM
}

reasoning_continuity(){
  python3 - "$ROOT/gateway-trace.jsonl" "$TRACE_START" "$1" "$2" <<'PYPRESERVE'
import json,sys
path,start,path_prefix,kind=sys.argv[1],int(sys.argv[2]),sys.argv[3],sys.argv[4]
response_key="response_reasoning_hashes" if kind=="reasoning" else "response_thinking_hashes"
request_key="assistant_reasoning_hashes" if kind=="reasoning" else "assistant_thinking_hashes"
rows=[]
try:
    with open(path,errors="replace") as f:
        for i,line in enumerate(f):
            if i < start: continue
            try: row=json.loads(line)
            except Exception: continue
            if str(row.get("path","")).startswith(path_prefix): rows.append(row)
except Exception: pass
observed=[]; replayed=[]
for i,row in enumerate(rows):
    for h in row.get(response_key,[]) or []:
        observed.append(h)
        if any(h in (later.get(request_key,[]) or []) for later in rows[i+1:]): replayed.append(h)
if not observed: print("LIMIT|no upstream %s block was observable on the traced client turns"%kind)
elif replayed: print("PASS|%d/%d observed %s block hash(es) were replayed unchanged on a later request"%(len(set(replayed)),len(set(observed)),kind))
else: print("FAIL|%d upstream %s block hash(es) were observed, but none survived unchanged into a later request"%(len(set(observed)),kind))
PYPRESERVE
}
N=$RANDOM

if want L1-shell; then
if claude_capture "Bash" "Run this command: echo ZKCL$N
Reply with only what it printed."; then
  o=$CLAUDE_LAST
  grep -q "ZKCL$N" <<<"$o" && p L1-shell PASS || { p L1-shell FAIL; show_tail "$o"; }
else
  rc=$?; [ "$rc" = 75 ] && p L1-shell BLOCKED "$(quota_detail)" || { [ "$rc" = 76 ] && p L1-shell ENVERR "$(config_detail)" || { [ "$rc" = 77 ] && p L1-shell TIMEOUT "$(transient_detail)" || { [ "$rc" = 78 ] && p L1-shell BLOCKED "$(transient_detail)" || { p L1-shell FAIL "claude exited $rc"; show_tail "$CLAUDE_LAST"; }; }; }; }
fi

fi

if want L2-chained; then
if claude_capture "Bash" "Run: echo 7
Then run: expr <that number> \* 6
Reply with only the final number."; then
  o=$CLAUDE_LAST
  grep -q 42 <<<"$o" && p L2-chained PASS || { p L2-chained FAIL; show_tail "$o"; }
else
  rc=$?; [ "$rc" = 75 ] && p L2-chained BLOCKED "$(quota_detail)" || { [ "$rc" = 76 ] && p L2-chained ENVERR "$(config_detail)" || { [ "$rc" = 77 ] && p L2-chained TIMEOUT "$(transient_detail)" || { [ "$rc" = 78 ] && p L2-chained BLOCKED "$(transient_detail)" || { p L2-chained FAIL "claude exited $rc"; show_tail "$CLAUDE_LAST"; }; }; }; }
fi

fi

if want L3-parallel; then
if claude_capture "Bash" "Run these as three separate commands: echo AAA$N ; echo BBB$N ; echo CCC$N
Reply with all three outputs."; then
  o=$CLAUDE_LAST
  k=0; for x in AAA BBB CCC; do grep -q "$x$N" <<<"$o" && k=$((k+1)); done
  [ "$k" = 3 ] && p L3-parallel PASS "3/3" || { p L3-parallel FAIL "$k/3"; show_tail "$o"; }
else
  rc=$?; [ "$rc" = 75 ] && p L3-parallel BLOCKED "$(quota_detail)" || { [ "$rc" = 76 ] && p L3-parallel ENVERR "$(config_detail)" || { [ "$rc" = 77 ] && p L3-parallel TIMEOUT "$(transient_detail)" || { [ "$rc" = 78 ] && p L3-parallel BLOCKED "$(transient_detail)" || { p L3-parallel FAIL "claude exited $rc"; show_tail "$CLAUDE_LAST"; }; }; }; }
fi

fi

if want L4-create; then
rm -f made.txt
if claude_capture "Read,Write" "Create a file named made.txt containing exactly: MADE$N
Create that one file and nothing else."; then
  o=$CLAUDE_LAST
  if python3 - "made.txt" "MADE$N" <<'PYFILE'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
if not p.is_file(): raise SystemExit(1)
data = p.read_bytes()
raise SystemExit(0 if data.rstrip(b"\r\n") == sys.argv[2].encode() else 1)
PYFILE
  then
    p L4-create PASS "content exact after ignoring terminal newline style"
  else
    p L4-create FAIL "file absent or contains data beyond the expected text/newline"
    [ -f made.txt ] && python3 - "made.txt" <<'PYDIAG'
import pathlib, sys
b=pathlib.Path(sys.argv[1]).read_bytes()
print("         file_bytes=%d repr=%r" % (len(b), b[:160]))
PYDIAG
    show_tail "$o"
  fi
else
  rc=$?; [ "$rc" = 75 ] && p L4-create BLOCKED "$(quota_detail)" || { [ "$rc" = 76 ] && p L4-create ENVERR "$(config_detail)" || { [ "$rc" = 77 ] && p L4-create TIMEOUT "$(transient_detail)" || { [ "$rc" = 78 ] && p L4-create BLOCKED "$(transient_detail)" || { p L4-create FAIL "claude exited $rc"; show_tail "$CLAUDE_LAST"; }; }; }; }
fi

fi

if want L5-edit; then
printf 'keep this line\nOLDVALUE\nkeep this too\n' > edit.txt
if claude_capture "Read,Edit" "In edit.txt replace the line OLDVALUE with NEW$N. Change nothing else."; then
  o=$CLAUDE_LAST
  printf 'keep this line\nNEW%s\nkeep this too\n' "$N" > "$ZKC_TMP/l5.expected"
  cmp -s edit.txt "$ZKC_TMP/l5.expected" \
    && p L5-edit PASS "exact in-place patch" || { p L5-edit FAIL "unexpected file content"; show_tail "$o"; }
else
  rc=$?; [ "$rc" = 75 ] && p L5-edit BLOCKED "$(quota_detail)" || { [ "$rc" = 76 ] && p L5-edit ENVERR "$(config_detail)" || { [ "$rc" = 77 ] && p L5-edit TIMEOUT "$(transient_detail)" || { [ "$rc" = 78 ] && p L5-edit BLOCKED "$(transient_detail)" || { p L5-edit FAIL "claude exited $rc"; show_tail "$CLAUDE_LAST"; }; }; }; }
fi

fi

if want L6-recover; then
if claude_capture "Bash" "Run: cat /definitely-not-here-$N  (it will fail, that is expected)
Then run: echo RECOVERED$N
Reply with only the second output."; then
  o=$CLAUDE_LAST
  grep -q "RECOVERED$N" <<<"$o" && p L6-recover PASS || { p L6-recover FAIL; show_tail "$o"; }
else
  rc=$?; [ "$rc" = 75 ] && p L6-recover BLOCKED "$(quota_detail)" || { [ "$rc" = 76 ] && p L6-recover ENVERR "$(config_detail)" || { [ "$rc" = 77 ] && p L6-recover TIMEOUT "$(transient_detail)" || { [ "$rc" = 78 ] && p L6-recover BLOCKED "$(transient_detail)" || { p L6-recover FAIL "claude exited $rc"; show_tail "$CLAUDE_LAST"; }; }; }; }
fi

fi

# L7: open-ended search
if want L7-websearch; then
# must choose a recent scientific development after searching, compare a
# primary/official source with independent reporting, expose an actual
# WebSearch tool_use event, and return a machine-checkable synthesis.
if [ "$CLAUDE_QUOTA_BLOCKED" = 1 ]; then
  p L7-websearch BLOCKED "$(quota_detail)"
elif [ "$CLAUDE_CONFIG_BLOCKED" = 1 ]; then
  p L7-websearch BLOCKED "$(config_detail)"
elif [ "$WEB_TEST" = 1 ]; then
  TODAY=$(date -u +%F)
  L7PROMPT=$(cat <<TXT
Today is $TODAY. Use the WebSearch tool before choosing a topic. Select one
scientific result, dataset release, observatory or space-mission update, or
major clinical-study result announced during the last $WEB_AGE days that you
judge important. This is deliberately open ended: decide what is most worth
investigating only after searching.

Compare at least one primary or official source with at least one independent
source. Return JSON only with keys question, central_claim, uncertainty,
why_it_matters, and sources. sources must be an array with at least two objects,
each containing title, url, publication_date, role, and evidence. Use role
"primary" or "official" for one source and "independent" for another. Do not
invent a URL, date, quotation, or result.
TXT
)
  L7RAW="$ZKC_TMP/zkc-claude-web.jsonl"
  pace_cli
  ANTHROPIC_AUTH_TOKEN="$K" timeout "$TIMEOUT" "$CLAUDE_BIN" -p "$L7PROMPT" \
    --dangerously-skip-permissions --strict-mcp-config --disable-slash-commands --no-session-persistence \
    --tools "WebSearch" --output-format stream-json --verbose --max-turns 6 \
    >"$L7RAW" 2>&1
  L7RC=$?
  L7STATUS=$(claude_stream_status "$L7RAW" "$L7RC")
  L7K=${L7STATUS%%|*}; L7ERR=${L7STATUS#*|}
  if [ "$L7K" = QUOTA ]; then
    CLAUDE_QUOTA_BLOCKED=1; CLAUDE_QUOTA_DETAIL="$L7ERR"
    p L7-websearch BLOCKED "$L7ERR"
  elif [ "$L7K" = RATE ]; then
    p L7-websearch BLOCKED "$L7ERR"
  elif [ "$L7K" = TIMEOUT ]; then
    p L7-websearch TIMEOUT "$L7ERR"
  elif [ "$L7K" = TRUNCATED ]; then
    p L7-websearch TRUNCATED "$L7ERR"
  elif [ "$L7K" = ERROR ]; then
    if grep -qiE 'websearch.*(unsupported|unavailable|unknown)|unknown tool|tool.*not (supported|available)' <<<"$L7ERR"; then
      p L7-websearch LIMIT "server-side WebSearch tool unsupported by the Anthropic compatibility endpoint"
    else
      p L7-websearch ENVERR "$L7ERR"
    fi
  else
  L7CHECK=$(python3 - "$L7RAW" "$TODAY" "$WEB_AGE" <<'PYWEB'
import datetime as dt, http.client, ipaddress, json, re, socket, ssl, sys, urllib.parse
path,today_s,age_s=sys.argv[1:4]
today=dt.date.fromisoformat(today_s); max_age=int(age_s)
saw=False; final=""; all_text=[]

class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, host, ip, timeout=20):
        super().__init__(host, port=443, timeout=timeout, context=ssl.create_default_context())
        self._pinned_ip = ip
    def connect(self):
        sock = socket.create_connection((self._pinned_ip, 443), self.timeout, self.source_address)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)

def public_ip(host):
    if not host or host.lower() in {"localhost", "localhost.localdomain"}:
        raise ValueError("local hostname rejected")
    addrs=[]
    for _,_,_,_,addr in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM):
        ip=ipaddress.ip_address(addr[0])
        if not ip.is_global:
            raise ValueError("non-public address rejected")
        addrs.append(str(ip))
    if not addrs:
        raise ValueError("hostname has no public address")
    return addrs[0]

def fetch_https(url, redirects=0):
    if redirects > 3:
        raise ValueError("too many redirects")
    u=urllib.parse.urlsplit(url)
    if u.scheme.lower() != "https" or u.username or u.password or u.port not in (None,443):
        raise ValueError("only credential-free HTTPS on port 443 is allowed")
    host=u.hostname; ip=public_ip(host)
    pathpart=urllib.parse.urlunsplit(("","",u.path or "/",u.query,""))
    conn=PinnedHTTPSConnection(host,ip,20)
    try:
        conn.request("GET",pathpart,headers={"User-Agent":"Mozilla/5.0 zkc-capability-probe","Accept":"text/html,application/json,text/plain;q=0.9,*/*;q=0.1"})
        r=conn.getresponse()
        if r.status in (301,302,303,307,308):
            loc=r.getheader("Location")
            if not loc:
                raise ValueError("redirect without Location")
            return fetch_https(urllib.parse.urljoin(url,loc),redirects+1)
        body=r.read(500001)
        if len(body)>500000:
            raise ValueError("response exceeded 500 kB")
        ctype=(r.getheader("Content-Type") or "").lower()
        if ctype and not any(x in ctype for x in ("text/","json","xml","javascript")):
            raise ValueError("non-text content rejected")
        return r.status
    finally:
        conn.close()

def walk(x):
    global saw
    if isinstance(x,dict):
        if x.get("type")=="tool_use" and str(x.get("name","")).lower()=="websearch":
            saw=True
        for v in x.values(): walk(v)
    elif isinstance(x,list):
        for v in x: walk(v)
    elif isinstance(x,str):
        all_text.append(x)

for line in open(path,errors="replace"):
    try: ev=json.loads(line)
    except Exception: continue
    walk(ev)
    if ev.get("type")=="result" and isinstance(ev.get("result"),str):
        final=ev["result"]

def object_from(text):
    text=re.sub(r'^```(?:json)?\s*|\s*```$', '', text.strip(), flags=re.I|re.S)
    a,b=text.find('{'),text.rfind('}')
    if a<0 or b<a: return None
    try: return json.loads(text[a:b+1])
    except Exception: return None

obj=object_from(final)
sources=obj.get("sources",[]) if isinstance(obj,dict) else []
urls=[x.get("url") for x in sources if isinstance(x,dict) and isinstance(x.get("url"),str)]
hosts={urllib.parse.urlparse(u).hostname for u in urls if u.startswith("https://")}
roles={str(x.get("role","")).lower() for x in sources if isinstance(x,dict)}
uncertainty=(obj or {}).get("uncertainty","") if isinstance(obj,dict) else ""
claim=(obj or {}).get("central_claim","") if isinstance(obj,dict) else ""
fresh_dates=[]
for src in sources:
    try:
        d=dt.date.fromisoformat(str(src.get("publication_date",""))[:10])
        age=(today-d).days
        if -2 <= age <= max_age+7: fresh_dates.append(age)
    except Exception:
        pass
reachable=0
for url in urls[:4]:
    try:
        status=fetch_https(url)
        if 200 <= status < 400:
            reachable += 1
    except Exception:
        pass
strong=(len(urls)>=2 and len({h for h in hosts if h})>=2 and
        len(uncertainty)>=30 and len(claim)>=50 and bool(fresh_dates) and
        bool(roles & {"primary","official"}) and "independent" in roles)
if not saw:
    print("FAIL|no WebSearch tool_use event in Claude stream-json")
elif not strong:
    print("FAIL|WebSearch ran but synthesis was weak: urls=%d domains=%d roles=%s fresh_dates=%d"%
          (len(urls),len(hosts),",".join(sorted(roles)),len(fresh_dates)))
elif reachable>=2:
    print("PASS|WebSearch event; %d sources across %d domains; %d independently reachable"%
          (len(urls),len(hosts),reachable))
else:
    print("LIMIT|WebSearch and synthesis passed, but only %d cited URL(s) were independently reachable"%reachable)
PYWEB
)
  L7V=${L7CHECK%%|*}; L7D=${L7CHECK#*|}
  p L7-websearch "$L7V" "$L7D"
  fi
else
  p L7-websearch SKIP "upstream web search is being updated; set OPEN_WEB_TEST=1 for an explicit non-production probe"
fi

fi

# L8/L9: deterministic science and observable reasoning
if want L8-science || want L9-reasoning; then
# Codex. Passing prose is insufficient: Claude Code must create executable code
# and a result file whose regression, prediction, units, and derivation validate.
if [ "$CLAUDE_QUOTA_BLOCKED" = 1 ]; then
  p L8-science BLOCKED "$(quota_detail)"
  p L9-reasoning BLOCKED "$(quota_detail)"
elif [ "$CLAUDE_CONFIG_BLOCKED" = 1 ]; then
  p L8-science BLOCKED "$(config_detail)"
  p L9-reasoning BLOCKED "$(config_detail)"
elif [ "$SCIENCE" = 1 ]; then
  echo "       running L8/L9 scientific reasoning suite ..."
  SD="$W/science-claude"
  rm -rf "$SD"
  python3 "$ZKC_WORK/science_harness.py" prepare "$SD"
  cd "$SD"
  L8RAW="$ZKC_TMP/zkc-claude-science.jsonl"
  pace_cli
  L8PROMPT=$(cat science_prompt.txt)
  ANTHROPIC_AUTH_TOKEN="$K" timeout "$TIMEOUT" "$CLAUDE_BIN" -p "$L8PROMPT" \
    --dangerously-skip-permissions --strict-mcp-config --disable-slash-commands --no-session-persistence \
    --tools "Bash,Read,Write,Edit" --output-format stream-json --verbose --max-turns 12 \
    >"$L8RAW" 2>&1
  L8RC=$?
  L8STATUS=$(claude_stream_status "$L8RAW" "$L8RC")
  L8K=${L8STATUS%%|*}; L8ERR=${L8STATUS#*|}
  if [ "$L8K" = QUOTA ]; then
    CLAUDE_QUOTA_BLOCKED=1; CLAUDE_QUOTA_DETAIL="$L8ERR"
    p L8-science BLOCKED "$L8ERR"; p L9-reasoning BLOCKED "$L8ERR"
  elif [ "$L8K" = RATE ]; then
    p L8-science BLOCKED "$L8ERR"; p L9-reasoning BLOCKED "$L8ERR"
  elif [ "$L8K" = TIMEOUT ]; then
    p L8-science TIMEOUT "$L8ERR"; p L9-reasoning TIMEOUT "$L8ERR"
  elif [ "$L8K" = TRUNCATED ]; then
    p L8-science TRUNCATED "$L8ERR"; p L9-reasoning TRUNCATED "$L8ERR"
  elif [ "$L8K" = ERROR ]; then
    p L8-science ENVERR "$L8ERR"; p L9-reasoning ENVERR "$L8ERR"
  else
  LSCI_OK=0
  if v=$(python3 "$ZKC_WORK/science_harness.py" validate "$SD" 2>&1); then
    LSCI_OK=1
    p L8-science PASS "$v"
  else
    p L8-science FAIL "$v"
    tail -10 "$L8RAW" | sed 's/^/         /'
  fi
  LREASON=$(python3 - "$L8RAW" <<'PYREASON'
import json,sys
count=chars=0

def walk(x):
    global count,chars
    if isinstance(x,dict):
        typ=str(x.get("type","")).lower()
        if typ in ("thinking","reasoning","reasoning_summary"):
            count+=1
            for key in ("thinking","text","summary","content"):
                value=x.get(key)
                if isinstance(value,str): chars+=len(value)
                elif isinstance(value,list): chars+=len(json.dumps(value))
        for v in x.values(): walk(v)
    elif isinstance(x,list):
        for v in x: walk(v)
for line in open(sys.argv[1],errors="replace"):
    try: walk(json.loads(line))
    except Exception: pass
print("%d:%d"%(count,chars))
PYREASON
)
  LRC=${LREASON%%:*}; LRCH=${LREASON#*:}
  if [ "${LRC:-0}" -gt 0 ]; then
    p L9-reasoning PASS "$LRC streamed thinking/reasoning block(s), approximately $LRCH serialized chars"
  elif [ "$LSCI_OK" = 1 ]; then
    p L9-reasoning LIMIT "complex science passed, but Claude stream-json exposed no thinking summary"
  else
    p L9-reasoning FAIL "science failed and no thinking/reasoning block was observable"
  fi
  fi
  cd "$W"
else
  p L8-science SKIP "SCIENCE_TEST=0"
  p L9-reasoning SKIP "SCIENCE_TEST=0"
fi
fi

# L10 measures preserved thinking on the actual Claude Code wire, not merely
# whether a thinking block was visible in client output.
if want L10-preserve; then
  L10=$(reasoning_continuity "/anthropic/v1/messages" thinking)
  L10V=${L10%%|*}; L10D=${L10#*|}
  p L10-preserve "$L10V" "$L10D"
fi

EOF
step "7. claude code capability probes"
CLAUDE_RC=0
if (( L_CLAUDE )); then
  CLAUDE_OUT=""
  CLAUDE_TRACE_START=$(run_remote 'wc -l < "$HOME/.cache/zkc-kimi-k3/$Z_RUN_ID/gateway-trace.jsonl" 2>/dev/null || echo 0' "Z_RUN_ID=$RUN_ID" | tr -d '[:space:]')
  [[ "$CLAUDE_TRACE_START" =~ ^[0-9]+$ ]] || CLAUDE_TRACE_START=0
  # Keep each sprite exec below long-session transport limits. L8 and L9 share
  # one model turn, so they remain paired; every other probe reconnects cleanly.
  for _claude_group in L1-shell L2-chained L3-parallel L4-create L5-edit L6-recover L7-websearch 'L8-science,L9-reasoning' L10-preserve; do
    _claude_part=$(send_secret "$S_CLAUDE" "Z_RUN_ID=$RUN_ID,A_GATEWAY_PORT=$GATEWAY_PORT,A_ONLY=$_claude_group,A_TIMEOUT=$REQUEST_TIMEOUT,A_MODEL=$CLAUDE_MODEL,A_CONTEXT=$CONTEXT_WINDOW,A_WEB_TEST=$OPEN_WEB_TEST,A_WEB_AGE=$WEB_MAX_AGE_DAYS,A_SCIENCE=$SCIENCE_TEST,A_API_BLOCKED=$API_BLOCKED,A_MIN_INTERVAL_MS=$KIMI_MIN_REQUEST_INTERVAL_MS,A_ENGINE_RETRIES=$KIMI_ENGINE_OVERLOAD_RETRIES,A_ENGINE_BASE=$KIMI_ENGINE_OVERLOAD_BASE_SECONDS,A_RETRY_MAX=$KIMI_RETRY_MAX_SECONDS,A_TRACE_START=$CLAUDE_TRACE_START" 2>&1 | tee /dev/stderr)
    _claude_rc=$?
    CLAUDE_OUT+="${CLAUDE_OUT:+$'\n'}$_claude_part"
    if printf '%s\n' "$_claude_part" | grep -qE '(^TPD_GUARD\||^PROBE\|L[^|]*\|BLOCKED\|Moonshot TPD/quota|exceeded_current_quota_error)'; then
      API_BLOCKED=1
    fi
    if [ "$_claude_rc" -ne 0 ]; then CLAUDE_RC="$_claude_rc"; fi
  done
  unset _claude_group _claude_part _claude_rc CLAUDE_TRACE_START
else
  CLAUDE_OUT=$(skipped_layer_output claude | tee /dev/stderr)
fi
complete_layer_output claude "$L_CLAUDE" CLAUDE_OUT "$CLAUDE_RC"

# =================================================================== REPORT ===
step "CAPABILITY MATRIX"
printf '  %-14s %-5s %s\n' PROBE VERDICT DETAIL
ALL=$(printf '%s\n%s\n%s\n%s\n' "$PROTO_OUT" "$ANTHRO_OUT" "$CODEX_OUT" "$CLAUDE_OUT")
# Reconnected layers may emit a probe more than once. Keep the last terminal
# row for each known probe in stable matrix order.
PROBE_ROWS=""
for _layer in protocol anthropic codex claude; do
  for _probe in $(layer_probe_names "$_layer"); do
    _row=$(printf '%s\n' "$ALL" | grep "^PROBE|$_probe|" | tail -1 || true)
    [ -z "$_row" ] || PROBE_ROWS+="${PROBE_ROWS:+$'\n'}$_row"
  done
done
unset _layer _probe _row
printf '%s\n' "$PROBE_ROWS" | while IFS='|' read -r _ n v d; do
  case "$v" in
    PASS)    printf '  \033[1;32m%-14s %-7s\033[0m %s\n' "$n" PASS "$d" ;;
    FAIL)    printf '  \033[1;31m%-14s %-7s\033[0m %s\n' "$n" FAIL "$d" ;;
    BLOCKED)   printf '  \033[1;35m%-14s %-9s\033[0m %s\n' "$n" BLOCKED "$d" ;;
    ENVERR)    printf '  \033[1;36m%-14s %-9s\033[0m %s\n' "$n" ENVERR "$d" ;;
    TIMEOUT)   printf '  \033[1;36m%-14s %-9s\033[0m %s\n' "$n" TIMEOUT "$d" ;;
    TRUNCATED) printf '  \033[1;33m%-14s %-9s\033[0m %s\n' "$n" TRUNCATED "$d" ;;
    *)         printf '  \033[1;33m%-14s %-9s\033[0m %s\n' "$n" "$v" "$d" ;;
  esac
done
FAILS=$(printf '%s\n' "$PROBE_ROWS" | grep -c '^PROBE|[^|]*|FAIL' || true)
BLOCKEDS=$(printf '%s\n' "$PROBE_ROWS" | grep -c '^PROBE|[^|]*|BLOCKED' || true)
LIMITS=$(printf '%s\n' "$PROBE_ROWS" | grep -c '^PROBE|[^|]*|LIMIT' || true)
SKIPS=$(printf '%s\n' "$PROBE_ROWS" | grep -c '^PROBE|[^|]*|SKIP' || true)
ENVERRS=$(printf '%s\n' "$PROBE_ROWS" | grep -c '^PROBE|[^|]*|ENVERR' || true)
TIMEOUTS=$(printf '%s\n' "$PROBE_ROWS" | grep -c '^PROBE|[^|]*|TIMEOUT' || true)
TRUNCATEDS=$(printf '%s\n' "$PROBE_ROWS" | grep -c '^PROBE|[^|]*|TRUNCATED' || true)
cv(){ printf '%s\n' "$PROBE_ROWS" | grep -c "^PROBE|$1[0-9]*-[^|]*|$2|" || true; }
cf(){ cv "$1" FAIL; }
group_summary(){
  local prefix="$1" f b l s e t x
  f=$(cv "$prefix" FAIL); b=$(cv "$prefix" BLOCKED); l=$(cv "$prefix" LIMIT); s=$(cv "$prefix" SKIP)
  e=$(cv "$prefix" ENVERR); t=$(cv "$prefix" TIMEOUT); x=$(cv "$prefix" TRUNCATED)
  printf '%s failure(s), %s blocked, %s environment error(s), %s timeout(s), %s truncated, %s limitation(s), %s skipped' "$f" "$b" "$e" "$t" "$x" "$l" "$s"
}
BRIDGE_PROTOCOL_FAILS=$(cf P)
CODEX_E2E_FAILS=$(cf C)
ANTHROPIC_PROTOCOL_FAILS=$(cf A)
CLAUDE_E2E_FAILS=$(cf L)
BRIDGE_PROTOCOL_BLOCKED=$(cv P BLOCKED)
CODEX_E2E_BLOCKED=$(cv C BLOCKED)
ANTHROPIC_PROTOCOL_BLOCKED=$(cv A BLOCKED)
CLAUDE_E2E_BLOCKED=$(cv L BLOCKED)
E2E_FAILS=$(( CODEX_E2E_FAILS + CLAUDE_E2E_FAILS ))
PROTOCOL_FAILS=$(( BRIDGE_PROTOCOL_FAILS + ANTHROPIC_PROTOCOL_FAILS ))
E2E_BLOCKED=$(( CODEX_E2E_BLOCKED + CLAUDE_E2E_BLOCKED ))
PROTOCOL_BLOCKED=$(( BRIDGE_PROTOCOL_BLOCKED + ANTHROPIC_PROTOCOL_BLOCKED ))
SELECTED_FAILS=0; SELECTED_BLOCKEDS=0; SELECTED_LIMITS=0; SELECTED_SKIPS=0
SELECTED_ENVERRS=0; SELECTED_TIMEOUTS=0; SELECTED_TRUNCATEDS=0
if (( L_PROTOCOL )); then SELECTED_FAILS=$((SELECTED_FAILS + BRIDGE_PROTOCOL_FAILS)); SELECTED_BLOCKEDS=$((SELECTED_BLOCKEDS + BRIDGE_PROTOCOL_BLOCKED)); SELECTED_LIMITS=$((SELECTED_LIMITS + $(cv P LIMIT))); SELECTED_SKIPS=$((SELECTED_SKIPS + $(cv P SKIP))); SELECTED_ENVERRS=$((SELECTED_ENVERRS + $(cv P ENVERR))); SELECTED_TIMEOUTS=$((SELECTED_TIMEOUTS + $(cv P TIMEOUT))); SELECTED_TRUNCATEDS=$((SELECTED_TRUNCATEDS + $(cv P TRUNCATED))); fi
if (( L_ANTHROPIC )); then SELECTED_FAILS=$((SELECTED_FAILS + ANTHROPIC_PROTOCOL_FAILS)); SELECTED_BLOCKEDS=$((SELECTED_BLOCKEDS + ANTHROPIC_PROTOCOL_BLOCKED)); SELECTED_LIMITS=$((SELECTED_LIMITS + $(cv A LIMIT))); SELECTED_SKIPS=$((SELECTED_SKIPS + $(cv A SKIP))); SELECTED_ENVERRS=$((SELECTED_ENVERRS + $(cv A ENVERR))); SELECTED_TIMEOUTS=$((SELECTED_TIMEOUTS + $(cv A TIMEOUT))); SELECTED_TRUNCATEDS=$((SELECTED_TRUNCATEDS + $(cv A TRUNCATED))); fi
if (( L_CODEX )); then SELECTED_FAILS=$((SELECTED_FAILS + CODEX_E2E_FAILS)); SELECTED_BLOCKEDS=$((SELECTED_BLOCKEDS + CODEX_E2E_BLOCKED)); SELECTED_LIMITS=$((SELECTED_LIMITS + $(cv C LIMIT))); SELECTED_SKIPS=$((SELECTED_SKIPS + $(cv C SKIP))); SELECTED_ENVERRS=$((SELECTED_ENVERRS + $(cv C ENVERR))); SELECTED_TIMEOUTS=$((SELECTED_TIMEOUTS + $(cv C TIMEOUT))); SELECTED_TRUNCATEDS=$((SELECTED_TRUNCATEDS + $(cv C TRUNCATED))); fi
if (( L_CLAUDE )); then SELECTED_FAILS=$((SELECTED_FAILS + CLAUDE_E2E_FAILS)); SELECTED_BLOCKEDS=$((SELECTED_BLOCKEDS + CLAUDE_E2E_BLOCKED)); SELECTED_LIMITS=$((SELECTED_LIMITS + $(cv L LIMIT))); SELECTED_SKIPS=$((SELECTED_SKIPS + $(cv L SKIP))); SELECTED_ENVERRS=$((SELECTED_ENVERRS + $(cv L ENVERR))); SELECTED_TIMEOUTS=$((SELECTED_TIMEOUTS + $(cv L TIMEOUT))); SELECTED_TRUNCATEDS=$((SELECTED_TRUNCATEDS + $(cv L TRUNCATED))); fi
TPD_GUARD_LINE=$(printf '%s\n' "$ALL" | grep '^TPD_GUARD|' | tail -1 || true)
tpd_field(){ printf '%s\n' "$TPD_GUARD_LINE" | tr '|' '\n' | sed -n "s/^$1=//p" | head -1; }
TPD_CURRENT=$(tpd_field current); TPD_LIMIT=$(tpd_field limit); TPD_OVER=$(tpd_field over_by)
TPD_RETRY_AFTER=$(tpd_field retry_after_seconds); TPD_RESET_UTC=$(tpd_field reset_utc)
TPD_RESET_LOCAL=$(tpd_field reset_local); TPD_RESET_TZ=$(tpd_field timezone); TPD_ACTION_USED=$(tpd_field action)
TPD_ACTION_REQUESTED=$(tpd_field requested_action); TPD_STOP_REASON=$(tpd_field reason)

step "HEAD TO HEAD"
printf '  %-36s %s\n' "Responses bridge protocol:" "$(group_summary P)"
printf '  %-36s %s\n' "Codex end to end:" "$(group_summary C)"
printf '  %-36s %s\n' "Anthropic raw protocol:" "$(group_summary A)"
printf '  %-36s %s\n' "Claude Code end to end:" "$(group_summary L)"

if (( L_CODEX && L_CLAUDE )); then
  if [ "$CODEX_E2E_FAILS" = 0 ] && [ "$CLAUDE_E2E_FAILS" = 0 ] && \
     [ "$CODEX_E2E_BLOCKED" = 0 ] && [ "$CLAUDE_E2E_BLOCKED" = 0 ] && \
     [ "$(cv C ENVERR)" = 0 ] && [ "$(cv L ENVERR)" = 0 ] && \
     [ "$(cv C TIMEOUT)" = 0 ] && [ "$(cv L TIMEOUT)" = 0 ] && \
     [ "$(cv C TRUNCATED)" = 0 ] && [ "$(cv L TRUNCATED)" = 0 ]; then
    echo; echo "  Both selected clients are operational for the tested workflows."
  else
    echo; echo "  One or both selected client paths did not complete cleanly; inspect C- and L-probes."
  fi
elif (( L_CODEX )); then
  if [ "$CODEX_E2E_FAILS" = 0 ] && [ "$CODEX_E2E_BLOCKED" = 0 ] && \
     [ "$(cv C ENVERR)" = 0 ] && [ "$(cv C TIMEOUT)" = 0 ] && [ "$(cv C TRUNCATED)" = 0 ]; then
    echo; echo "  The selected Codex layer completed without FAIL or BLOCKED."
  else
    echo; echo "  The selected Codex layer did not complete cleanly; inspect C-probes."
  fi
elif (( L_CLAUDE )); then
  if [ "$CLAUDE_E2E_FAILS" = 0 ] && [ "$CLAUDE_E2E_BLOCKED" = 0 ] && \
     [ "$(cv L ENVERR)" = 0 ] && [ "$(cv L TIMEOUT)" = 0 ] && [ "$(cv L TRUNCATED)" = 0 ]; then
    echo; echo "  The selected Claude Code layer completed without FAIL or BLOCKED."
  else
    echo; echo "  The selected Claude Code layer did not complete cleanly; inspect L-probes."
  fi
else
  echo; echo "  Client layers were not selected; this run covers raw protocol diagnostics only."
fi
if (( L_ANTHROPIC && L_CLAUDE )) && [ "$ANTHROPIC_PROTOCOL_FAILS" -gt 0 ] && [ "$CLAUDE_E2E_FAILS" = 0 ]; then
  echo "  NOTE: raw Anthropic probe failures do not invalidate Claude Code when all"
  echo "  L-probes pass; that pattern indicates a probe/model-alias mismatch."
fi

DOLLAR='$'

step "VERDICT"
# SCAR: this heredoc is unquoted so ${PORT}/${MODEL} interpolate - which means
# every literal dollar must be written ${DOLLAR}. Missing one aborted the whole
# block under `set -u` and the run printed no config at all, twice. The escapes
# are fixed, and `set +u` here guarantees a missed one degrades to a cosmetic
# blank instead of destroying the only output that matters.
set +u
if [ "${SELECTED_FAILS:-1}" = 0 ] && [ "${SELECTED_BLOCKEDS:-1}" = 0 ] && \
   [ "${SELECTED_ENVERRS:-1}" = 0 ] && [ "${SELECTED_TIMEOUTS:-1}" = 0 ] && \
   [ "${SELECTED_TRUNCATEDS:-1}" = 0 ]; then
  cat <<TXT
  All selected probes completed without FAIL or BLOCKED.
  Selected layers: ${SELECTED_LAYERS}. Unselected layers are shown as SKIP and
  are not treated as proof that those clients work.

  Selected probes report ${SELECTED_LIMITS} explicit limitation(s) and
  ${SELECTED_SKIPS} selected optional skip(s). LIMIT is a measured boundary;
  web-search SKIPs are expected unless OPEN_WEB_TEST=1 is explicitly set.

  Codex uses the in-Sprite codeproxy bridge by default. The verifier installs
  Codex and codeproxy inside the selected Sprite, exports CODEX_HOME to the
  isolated configuration under the run directory, and routes every upstream
  request through the shared pacing/trace gateway before Kimi.

    # Interactive example inside the selected Sprite while KEEP_BRIDGE=1:
    codex --profile kimi
    codex exec --profile kimi --ephemeral "..."

  KIMI_CODEX_ROUTER=cc-switch is retained only as an explicit host-desktop
  compatibility branch. It cannot verify preserved reasoning on the in-Sprite
  wire and is not the normal deployment path.

  Claude Code uses Kimi's native Anthropic-compatible endpoint inside the selected Sprite:

    export ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic
    export ANTHROPIC_AUTH_TOKEN=${DOLLAR}MOONSHOT_API_KEY
    export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1
    export ENABLE_TOOL_SEARCH=false
    export ANTHROPIC_MODEL=${CLAUDE_MODEL}
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${CLAUDE_MODEL}
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${CLAUDE_MODEL}
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=${CLAUDE_MODEL}
    export ANTHROPIC_DEFAULT_FABLE_MODEL=${CLAUDE_MODEL}
    export CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_MODEL}
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CONTEXT_WINDOW}
    export CLAUDE_CODE_EFFORT_LEVEL=max

    claude                                    # interactive
    CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=0 claude -p "..." --dangerously-skip-permissions --strict-mcp-config --tools "Bash,Read,Write,Edit"

  Raw protocol probes use ${MAX_OUTPUT_TOKENS} tokens, Anthropic tool probes
  use ${ANTHROPIC_OUTPUT_TOKENS}, reasoning probes use ${REASONING_OUTPUT_TOKENS},
  and explicit web synthesis uses ${WEB_OUTPUT_TOKENS}. The in-Sprite codeproxy
  profile uses a ${CLIENT_OUTPUT_TOKENS}-token Codex cap. Every Sprite-originated
  Moonshot request is serialized and started at least ${KIMI_MIN_REQUEST_INTERVAL_MS} ms apart,
  and runs only these selected layers: ${SELECTED_LAYERS}.
  TPD handling is ${KIMI_TPD_ACTION}; reset deadlines use ${KIMI_RESET_TIMEZONE}.
  Moonshot's gateway counts the requested maximum toward rate-limit admission,
  even when the generated response is much shorter. Set
  KIMI_PROBE_MAX_OUTPUT_TOKENS=${MODEL_DEFAULT_MAX_OUTPUT_TOKENS} only for an
  explicit full-default-output stress run; it can exhaust low-tier TPD quickly.

  The [1m] suffix is the documented Claude Code selector. Raw hand-built
  Messages API probes use the canonical model ID ${ANTHROPIC_API_MODEL} instead.
  Codex accepts text and image input but has no native video input channel;
  extract keyframes (and optionally transcribe audio) before a Codex video
  workflow, or call the Kimi API directly for native video understanding.
  The DEFAULT_* vars matter
  because Claude Code routes some internal calls by asking for opus/sonnet/
  haiku by name rather than the model you set.

  Default full-matrix command:
    bash $0

  Focused reruns remain available:
    ZKC_LAYERS=claude SCIENCE_TEST=1 bash $0
    ZKC_LAYERS=codex KIMI_CODEX_ROUTER=codeproxy SCIENCE_TEST=1 bash $0
    ZKC_LAYERS=protocol,anthropic bash $0
TXT
  if (( ! L_CODEX && ! L_CLAUDE )); then
    echo "  Only selected client layers are evidence of client usability; unselected layers remain SKIP."
  fi
elif [ "${SELECTED_FAILS:-1}" = 0 ]; then
  echo "  The selected run is incomplete but has no capability FAIL:"
  echo "    blocked=${SELECTED_BLOCKEDS} environment_errors=${SELECTED_ENVERRS} timeouts=${SELECTED_TIMEOUTS} truncated=${SELECTED_TRUNCATEDS}."
  echo "  ENVERR is excluded from capability failure counts; TRUNCATED means the verifier budget ended the response."
  if [ -n "${TPD_GUARD_LINE:-}" ]; then
    echo
    echo "  Daily token allowance exhausted: ${TPD_CURRENT:-?} / ${TPD_LIMIT:-?} tokens"
    echo "  (${TPD_OVER:-?} over the limit). Server Retry-After: ${TPD_RETRY_AFTER:-?} seconds."
    echo "  Expected reset: ${TPD_RESET_UTC:-unknown} UTC; ${TPD_RESET_LOCAL:-unknown} (${TPD_RESET_TZ:-local})."
    if [ "${TPD_ACTION_USED:-stop}" = stop-after-wait ]; then
      echo "  The script waited once for the advertised reset, but TPD remained active."
      echo "  It stopped rather than entering an indefinite retry loop."
    elif [ "${TPD_ACTION_USED:-stop}" = stop ]; then
      echo "  TPD handling stopped here (reason: ${TPD_STOP_REASON:-unknown}; requested: ${TPD_ACTION_REQUESTED:-stop})."
      echo "  To wait once and resume automatically when Retry-After is within the safety cap:"
      echo "    KIMI_TPD_ACTION=wait KIMI_TPD_WAIT_MAX_SECONDS=7200 bash $0"
    fi
  fi
  if (( ! L_CODEX && ! L_CLAUDE )); then
    echo "  Only selected client layers are evidence of client usability; unselected layers remain SKIP."
  else
    (( L_CODEX )) && echo "  Codex result: $(group_summary C)."
    (( L_CLAUDE )) && echo "  Claude Code result: $(group_summary L)."
  fi
elif [ "${SELECTED_FAILS:-1}" -gt 0 ]; then
  echo "  ${SELECTED_FAILS} selected capability probe(s) failed; blocked=${SELECTED_BLOCKEDS}, environment_errors=${SELECTED_ENVERRS}, timeouts=${SELECTED_TIMEOUTS}, truncated=${SELECTED_TRUNCATEDS}."
  echo "  Inspect only the selected prefixes for this run: P=Responses protocol,"
  echo "  A=Anthropic protocol, C=Codex, L=Claude Code. Unselected SKIP rows are not failures."
  if [ -n "${TPD_GUARD_LINE:-}" ]; then
    echo "  A TPD block also occurred; reset is expected at ${TPD_RESET_UTC:-unknown} UTC"
    echo "  (${TPD_RESET_LOCAL:-unknown} ${TPD_RESET_TZ:-local})."
  fi
fi
set -u
printf '\n  transcript: %s\n' "$(cd "$(dirname "$LOG")" && pwd)/$(basename "$LOG")"
if [ "$KEEP_BRIDGE" = 1 ]; then
  printf '  KEEP_BRIDGE=1: bridge remains active under run id %s on Sprite %s.\n' "$RUN_ID" "$SPRITE_NAME"
  printf '  Remote endpoint: http://127.0.0.1:%s/v1 (reachable from inside that Sprite).\n' "$PORT"
  printf '  Noninteractive Codex example from the host:\n'
  _remote_codex='root="$HOME/.cache/zkc-kimi-k3/'"$RUN_ID"'"; . "$root/runtime.env"; export CODEX_HOME; cd "$ZKC_WORK"; "$CODEX_BIN" exec --profile kimi --dangerously-bypass-approvals-and-sandbox -c web_search=disabled "Reply with only: BRIDGE_OK"'
  printf '    sprite exec %s -s %q -- bash -lc %q\n' "${ORG[*]}" "$SPRITE_NAME" "$_remote_codex"
  unset _remote_codex
  printf '  The keep-awake task is bounded by KEEPAWAKE_MAX=%s seconds.\n' "$KEEPAWAKE_MAX"
  printf '  Manual cleanup command:\n'
  printf '    sprite exec %s -s %q -- bash -c %q _ %q %q\n' "${ORG[*]}" "$SPRITE_NAME" \
    'root="$HOME/.cache/zkc-kimi-k3/$1"; for f in keepawake.pid gateway.pid bridge.pid; do [ -f "$root/$f" ] || continue; p=$(cat "$root/$f" 2>/dev/null || true); case "$p" in (*[!0-9]*|"") continue;; esac; cmd=$(tr "\000" " " < "/proc/$p/cmdline" 2>/dev/null || true); case "$cmd" in (*"$root/"*) kill -- "-$p" 2>/dev/null || true;; esac; done; curl -sS --max-time 5 -X DELETE --unix-socket /.sprite/api.sock "http://sprite/v1/tasks/$2" >/dev/null 2>&1 || true; rm -rf -- "$root"' "$RUN_ID" "$TASK_NAME"
else
  cleanup_remote || true
  CLEANED=1
  if (( NEED_SPRITE )); then
    printf '  bridge, heartbeat, temporary configs, and remote run workspace removed.\n'
  else
    printf '  host Codex temporary workspace removed; CC Switch configuration was not modified.\n'
  fi
fi
KIMI_KEY=""; unset KIMI_KEY
sleep 0.3
