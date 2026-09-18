#!/usr/bin/env bash
# sprite-codex-v47.sh — updated 2026-09-18
#
# Existing single-Sprite bootstrap: OpenAI/Codex or official Kimi Code CLI,
# GitHub/Fly environment credentials, workspace sync, optional pushes,
# native detachable TTY sessions, resume/fork, update and reconnect support.
#
# v47 adds mandatory, in-Sprite validation of every credential used by a new run.
# GitHub PAT: authenticated user, target repository and Git write-service access.
# Fly: fly status --app "$FLY_APP" with both token aliases. Providers: completed
# native Responses generation on the configured model. All checks precede repo
# sync and any new Codex agent/preflight; replacement/retry/abort is offered on failure.
# Existing live-session reattachment does not start a process or rotate its keys.
# TOKEN_CHECK_TIMEOUT=180 (1..900) bounds each validation request. No skip switch.
#
# v46 fixes reuse of an existing Sprite with stale/unwritable upload paths.
# All file transfers now use non-TTY exec stdin, a fresh private remote directory,
# and SHA-256 validation before execution/extraction. No --file upload API is used.
# Existing session selection, duplicate guards and detachable TTY behavior remain.
# v45 custom-provider defaults (unchanged by this fix):
#   DeepSeek: deepseek-flash (DeepSeek V4.1 Flash)
#   MiniMax:  MiniMax-M3
#   Moonshot: kimi-k3
# All three use native Responses APIs. No CodeProxy or Formula gateway is
# installed or started. Model IDs, endpoints, context and reasoning are overridable.
#
# Usage:
#   bash sprite-codex-v47.sh                        # existing interactive workflow
#   bash sprite-codex-v47.sh --show-models          # no API calls
#   bash sprite-codex-v47.sh --test-models          # host API tests only
#   bash sprite-codex-v47.sh --test-models-sprite   # API tests on one Sprite only
#   bash sprite-codex-v47.sh --test-models-before-run
#   bash sprite-codex-v47.sh --test-models --json-output ./model-tests.json
#
# API tests validate completed replies, SSE streaming and a two-request function
# call round trip; all providers are attempted. Exit 0=all pass, 1=failed/missing
# credentials, 2=configuration/report error, 130=interrupted. Tests may incur API
# charges. Test-only paths do not install Codex, touch repositories or attach to,
# create or terminate agent sessions. They do not require GitHub/Fly credentials.
# Remote tests transfer one temporary, secret-free Python helper and may wake a
# cold Sprite. --json-output is a Sprite path when testing on a Sprite.
#
# Provider settings:
#   DEEPSEEK_API_KEY, MINIMAX_API_KEY, MOONSHOT_API_KEY (KIMI_API_KEY is an alias)
#   DEEPSEEK_MODEL, MINIMAX_MODEL, KIMI_MODEL (MOONSHOT_MODEL is an alias)
#   DEEPSEEK_BASE_URL, MINIMAX_BASE_URL, MOONSHOT_BASE_URL
#   DEEPSEEK_CONTEXT_WINDOW, MINIMAX_CONTEXT_WINDOW, KIMI_CONTEXT_WINDOW
#   DEEPSEEK_REASONING_EFFORT, MINIMAX_REASONING_EFFORT, KIMI_REASONING_EFFORT
#   CODEX_PROVIDER=ask|openai|deepseek|minimax|kimi|moonshot
#   MODEL_TEST_MODE=ask|always|never (ask defaults to No; noninteractive skips)
#   MODEL_TEST_TIMEOUT=180, MODEL_TEST_MAX_TOKENS=4096, MODEL_TEST_RETRIES=0
#   MODEL_TEST_JSON=/path/report.json
#   KIMI_MIN_REQUEST_INTERVAL_MS=20000 (test request pacing only)
#   MODEL_TEST_ALLOW_LOCALHOST=1 permits HTTP only to localhost in test-only mode;
#     intended for offline regression tests, never for production credentials.
#
# Existing overrides retained:
#   CODING_AGENT=ask|codex|kimi-code, SPRITE_NAME, SPRITE_ORG, SPRITE_WORKDIR,
#   GITHUB_PAT, GITHUB_REPOSITORY, FLY_API_TOKEN, FLY_APP,
#   CODEX_{DEEPSEEK,MINIMAX,MOONSHOT}_ACCESS=ask|0|1,
#   MIN_CODEX_VERSION=0.144.0, CODEX_PREFLIGHT_TIMEOUT=180,
#   CODEX_UPDATE_MODE=ask|always|never, CODEX_UPDATE_LIVE_OVERRIDE=0|1,
#   SPRITE_CONTROL_TIMEOUT=25, SPRITE_CONNECT_TRIES=3,
#   SPRITE_UPLOAD_TIMEOUT=120, SPRITE_UPLOAD_TMPDIR=/absolute/remote/path,
#   SPRITE_CONTROL_TRANSPORT=auto|websocket|http-post,
#   KIMI_CODE_START_MODE=ask|continue|new,
#   KIMI_CODE_APPROVAL_MODE=normal|yolo|auto,
#   SHARED_WORKSPACE_MODE=auto|reuse|sync,
#   NO_AGENT_LAUNCH=1 (NO_CODEX_LAUNCH remains an alias), SPRITE_RUN_HOURS,
#   FORCE_NEW_SESSION=1, CODEX_START_MODE=ask|resume|fork|new,
#   RESUME_CODEX_HISTORY=1, SPRITE_SESSION_STATE,
#   REPO_PUSH_MODE=ask|always|never, REPO_PUSH_COMMIT_MESSAGE,
#   STARTUP_REPO_PUSH_MODE=ask|always|never, EXIT_AFTER_STARTUP_REPO_PUSH=1,
#   TTY_AUTO_REATTACH=1|0, TTY_REATTACH_ATTEMPTS=12,
#   TTY_REATTACH_CONFIRM_TRIES=8, TTY_REATTACH_DELAY=3.
# DEEPSEEK_TRANSPORT=auto|direct is accepted; bridge is retired with a clear error.
# Old Kimi gateway/Formula settings have no effect in the native provider path.
#
# Security: custom-provider keys are environment-only; test reports never contain
# raw response/reasoning bodies or keys. Normal Codex YOLO behavior is retained.
# API keys remain excluded from Codex shell/tools unless explicitly enabled.
# Sprite's JSON/hex environment transport is encoding, not encryption: the packed
# secret-equivalent value may appear in local process arguments. Do not use -x.
# OpenAI and Kimi Code CLI retain their own normal authentication stores.
# The script never invokes `sprite create` or `sprite destroy`.
#
# Documentation verified 2026-09-18:
# https://api-docs.deepseek.com/
# https://api-docs.deepseek.com/guides/responses_api/
# https://platform.minimax.io/docs/guides/text-generation
# https://platform.minimax.io/docs/api-reference/responses-create
# https://platform.kimi.ai/docs/guide/kimi-k3-quickstart
# https://platform.kimi.ai/docs/guide/codex-kimi
# https://learn.chatgpt.com/docs/config-file/config-advanced

if [[ -z ${BASH_VERSION:-} ]]; then
  echo "error: run this script with bash" >&2
  exit 1
fi
if (( BASH_VERSINFO[0] < 4 )); then
  echo "error: bash 4+ is required; found $BASH_VERSION" >&2
  echo "macOS users: brew install bash && /opt/homebrew/bin/bash $0" >&2
  exit 1
fi

set -Eeuo pipefail
set +x +v
umask 077

show_usage() {
  cat <<'HELP'
Usage: bash sprite-codex-v47.sh [option] [--json-output PATH]

  (no option)               Normal Sprite bootstrap; optional model-test prompt.
  --test-models             Test DeepSeek, MiniMax and Moonshot from this host.
  --test-models-sprite      Test all three from one selected Sprite.
  --test-models-before-run  Require host tests to pass, then run normal bootstrap.
  --show-models             Display configured model IDs and base URLs; no calls.
  --help, -h                Display this help.

Every credential used by a NEW run is validated on the selected Sprite:
GitHub authentication + repository/write-service access, Fly app status, and a
completion from each selected/experiment provider. Failed checks offer hidden
replacement, retry, or abort; noninteractive failures stop before agent launch.
TOKEN_CHECK_TIMEOUT=180 (1..900) bounds each request; checks cannot be skipped.
MODEL_TEST_MODE=never disables only the optional full suite, NOT token validation.
Fly accepts FLY_API_TOKEN or FLY_ACCESS_TOKEN; successful validation sets both.
Live-session reattachment preserves the existing process and its credentials.

Keys: DEEPSEEK_API_KEY, MINIMAX_API_KEY, MOONSHOT_API_KEY.
Missing keys are prompted with hidden input on a terminal, otherwise fail.
Tests: completed reply, SSE stream, function-call/result round trip.
Model IDs: DEEPSEEK_MODEL, MINIMAX_MODEL, KIMI_MODEL (or MOONSHOT_MODEL).
CODEX_PROVIDER=moonshot is an alias for CODEX_PROVIDER=kimi.

Existing Sprites are reused. New agent runs get native detachable TTY sessions;
this same managed agent/project, when already live, is reattached, not duplicated.
FORCE_NEW_SESSION=1 means confirmed replacement, NOT a parallel session.
SHARED_WORKSPACE_MODE=reuse skips repository sync/upload/commit/push.
SPRITE_UPLOAD_TIMEOUT=120 bounds each payload reception (not setup/agent runtime).
SPRITE_UPLOAD_TMPDIR=/absolute/path selects an existing writable remote temp base;
otherwise the remote TMPDIR or /tmp is used. Transfers use exec stdin, not --file.

MODEL_TEST_MODE=ask|always|never controls tests in the normal workflow.
MODEL_TEST_TIMEOUT=180     Hard deadline in seconds per HTTP attempt.
MODEL_TEST_MAX_TOKENS=4096  Per-request output budget, including reasoning.
MODEL_TEST_RETRIES=0       Optional retries for 429/502/503/504; 0..3.
MODEL_TEST_JSON=PATH       Optional report (0600, atomic replace).
KIMI_MIN_REQUEST_INTERVAL_MS=20000 controls Moonshot pacing in tests only.

Test-only modes need Bash 4+ and Unix Python 3.9+; Sprite tests also need sprite.
Full bootstrap additionally needs normal Sprite/GitHub/Fly access. Native Codex
configuration requires Python 3.11+ on the Sprite, or Python with tomli installed.
--json-output is a remote path with --test-models-sprite, local otherwise.
Tests make billable API calls; no agent, GitHub or Fly credentials are needed.
All three must pass for exit 0. Failures/missing keys exit 1; bad arguments exit 2.
HELP
}

RUN_MODE=bootstrap
MODEL_TEST_MODE="${MODEL_TEST_MODE:-ask}"
MODEL_TEST_JSON="${MODEL_TEST_JSON:-}"
_MODE_SELECTED=0
while (($#)); do
  case "$1" in
    --help|-h) show_usage; exit 0 ;;
    --test-models|--test-models-sprite|--test-models-before-run|--show-models)
      (( _MODE_SELECTED == 0 )) || { echo "error: select only one run mode" >&2; exit 2; }
      _MODE_SELECTED=1
      case "$1" in
        --test-models) RUN_MODE=test-local ;;
        --test-models-sprite) RUN_MODE=test-sprite ;;
        --test-models-before-run) MODEL_TEST_MODE=always ;;
        --show-models) RUN_MODE=show ;;
      esac
      shift ;;
    --json-output)
      [[ $# -ge 2 && -n $2 && $2 != --* ]] || { echo "error: --json-output requires a path" >&2; exit 2; }
      MODEL_TEST_JSON=$2; shift 2 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; show_usage >&2; exit 2 ;;
  esac
done
case "$MODEL_TEST_MODE" in ask|always|never) ;; *) echo "error: MODEL_TEST_MODE must be ask, always or never" >&2; exit 2 ;; esac

# Single source of truth for generation, tests, menus and remote launchers.
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-flash}"
MINIMAX_MODEL="${MINIMAX_MODEL:-MiniMax-M3}"
KIMI_MODEL="${KIMI_MODEL:-${MOONSHOT_MODEL:-kimi-k3}}"
MODEL="$DEEPSEEK_MODEL"
PROFILE="sprite-deepseek"
MINIMAX_PROFILE="sprite-minimax"
KIMI_PROFILE="sprite-kimi"
DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"
MINIMAX_BASE_URL="${MINIMAX_BASE_URL:-https://api.minimax.io/v1}"
MOONSHOT_BASE_URL="${MOONSHOT_BASE_URL:-https://api.moonshot.ai/v1}"
DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL%/}"
MINIMAX_BASE_URL="${MINIMAX_BASE_URL%/}"
MOONSHOT_BASE_URL="${MOONSHOT_BASE_URL%/}"
MOONSHOT_API_KEY="${MOONSHOT_API_KEY:-${KIMI_API_KEY:-}}"
DEEPSEEK_CONTEXT_WINDOW="${DEEPSEEK_CONTEXT_WINDOW:-1048576}"
MINIMAX_CONTEXT_WINDOW="${MINIMAX_CONTEXT_WINDOW:-1000000}"
KIMI_CONTEXT_WINDOW="${KIMI_CONTEXT_WINDOW:-1048576}"
DEEPSEEK_REASONING_EFFORT="${DEEPSEEK_REASONING_EFFORT:-high}"
MINIMAX_REASONING_EFFORT="${MINIMAX_REASONING_EFFORT:-high}"
KIMI_REASONING_EFFORT="${KIMI_REASONING_EFFORT:-high}"
KIMI_MIN_REQUEST_INTERVAL_MS="${KIMI_MIN_REQUEST_INTERVAL_MS:-20000}"
MODEL_TEST_TIMEOUT="${MODEL_TEST_TIMEOUT:-180}"
MODEL_TEST_MAX_TOKENS="${MODEL_TEST_MAX_TOKENS:-4096}"
MODEL_TEST_RETRIES="${MODEL_TEST_RETRIES:-0}"
MODEL_TEST_ALLOW_LOCALHOST="${MODEL_TEST_ALLOW_LOCALHOST:-0}"
MODEL_TEST_PROMPT=0
TOKEN_CHECK_TIMEOUT="${TOKEN_CHECK_TIMEOUT:-180}"
[[ $TOKEN_CHECK_TIMEOUT =~ ^[1-9][0-9]{0,2}$ ]] && (( TOKEN_CHECK_TIMEOUT <= 900 )) || {
  echo "error: TOKEN_CHECK_TIMEOUT must be 1..900 seconds" >&2; exit 2;
}

if [[ $RUN_MODE == show ]]; then
  printf 'Defaults verified: 2026-09-18; configured models (not live availability)\n'
  printf '%-10s %-25s %s\n' 'Provider' 'Model' 'API base URL'
  printf '%-10s %-25s %s\n' DeepSeek "$DEEPSEEK_MODEL" "$DEEPSEEK_BASE_URL" MiniMax "$MINIMAX_MODEL" "$MINIMAX_BASE_URL" Moonshot "$KIMI_MODEL" "$MOONSHOT_BASE_URL"
  exit 0
fi
for _v in DEEPSEEK_MODEL MINIMAX_MODEL KIMI_MODEL; do
  [[ ${!_v} =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] || { echo "error: invalid $_v" >&2; exit 2; }
done
for _v in DEEPSEEK_CONTEXT_WINDOW MINIMAX_CONTEXT_WINDOW KIMI_CONTEXT_WINDOW; do
  [[ ${!_v} =~ ^[1-9][0-9]{3,6}$ ]] || { echo "error: invalid $_v" >&2; exit 2; }
done
for _v in DEEPSEEK_REASONING_EFFORT KIMI_REASONING_EFFORT; do
  case "${!_v}" in low|high|max) ;; *) echo "error: $_v must be low, high or max" >&2; exit 2 ;; esac
done
case "$MINIMAX_REASONING_EFFORT" in low|high) ;; *) echo "error: MINIMAX_REASONING_EFFORT must be low or high" >&2; exit 2 ;; esac
[[ $MODEL_TEST_ALLOW_LOCALHOST == 0 || $MODEL_TEST_ALLOW_LOCALHOST == 1 ]] || { echo "error: MODEL_TEST_ALLOW_LOCALHOST must be 0 or 1" >&2; exit 2; }
if [[ $RUN_MODE == bootstrap && $MODEL_TEST_ALLOW_LOCALHOST == 1 ]]; then
  echo "error: localhost HTTP is permitted only in test-only mode" >&2; exit 2
fi
MIN_CODEX_VERSION="${MIN_CODEX_VERSION:-0.144.0}"
CODEX_PREFLIGHT_TIMEOUT="${CODEX_PREFLIGHT_TIMEOUT:-180}"
CODEX_UPDATE_MODE="${CODEX_UPDATE_MODE:-ask}"
CODEX_UPDATE_LIVE_OVERRIDE="${CODEX_UPDATE_LIVE_OVERRIDE:-0}"
CODEX_MOONSHOT_ACCESS="${CODEX_MOONSHOT_ACCESS:-ask}"
CODEX_MINIMAX_ACCESS="${CODEX_MINIMAX_ACCESS:-ask}"
CODEX_DEEPSEEK_ACCESS="${CODEX_DEEPSEEK_ACCESS:-ask}"
[[ $CODEX_PREFLIGHT_TIMEOUT =~ ^[1-9][0-9]*$ ]] || {
  echo "error: CODEX_PREFLIGHT_TIMEOUT must be a positive integer number of seconds" >&2
  exit 2
}
case "$CODEX_UPDATE_MODE" in
  ask|always|never) ;;
  *) echo "error: CODEX_UPDATE_MODE must be ask, always, or never" >&2; exit 2 ;;
esac
[[ $CODEX_UPDATE_LIVE_OVERRIDE == 0 || $CODEX_UPDATE_LIVE_OVERRIDE == 1 ]] || {
  echo "error: CODEX_UPDATE_LIVE_OVERRIDE must be 0 or 1" >&2
  exit 2
}
for _access_var in CODEX_MOONSHOT_ACCESS CODEX_MINIMAX_ACCESS CODEX_DEEPSEEK_ACCESS; do
  case "${!_access_var}" in
    ask|0|1) ;;
    *) echo "error: $_access_var must be ask, 0, or 1" >&2; exit 2 ;;
  esac
done
SPRITE_UPLOAD_TIMEOUT="${SPRITE_UPLOAD_TIMEOUT:-120}"
SPRITE_UPLOAD_TMPDIR="${SPRITE_UPLOAD_TMPDIR:-}"
[[ $SPRITE_UPLOAD_TIMEOUT =~ ^[1-9][0-9]{0,4}$ ]] || {
  echo "error: SPRITE_UPLOAD_TIMEOUT must be a positive integer (seconds, at most 99999)" >&2; exit 2;
}
[[ -z $SPRITE_UPLOAD_TMPDIR || $SPRITE_UPLOAD_TMPDIR == /* ]] || {
  echo "error: SPRITE_UPLOAD_TMPDIR must be an absolute path on the Sprite" >&2; exit 2;
}
SPRITE_CONTROL_TIMEOUT="${SPRITE_CONTROL_TIMEOUT:-25}"
SPRITE_CONNECT_TRIES="${SPRITE_CONNECT_TRIES:-3}"
SPRITE_CONTROL_TRANSPORT="${SPRITE_CONTROL_TRANSPORT:-auto}"
for _v in SPRITE_CONTROL_TIMEOUT SPRITE_CONNECT_TRIES; do
  [[ ${!_v} =~ ^[1-9][0-9]*$ ]] || { echo "error: $_v must be a positive integer" >&2; exit 2; }
done
case "$SPRITE_CONTROL_TRANSPORT" in
  auto|websocket|http-post) ;;
  *) echo "error: SPRITE_CONTROL_TRANSPORT must be auto, websocket, or http-post" >&2; exit 2 ;;
esac
TTY_AUTO_REATTACH="${TTY_AUTO_REATTACH:-1}"
TTY_REATTACH_ATTEMPTS="${TTY_REATTACH_ATTEMPTS:-12}"
TTY_REATTACH_CONFIRM_TRIES="${TTY_REATTACH_CONFIRM_TRIES:-8}"
TTY_REATTACH_DELAY="${TTY_REATTACH_DELAY:-3}"
[[ $TTY_AUTO_REATTACH == 0 || $TTY_AUTO_REATTACH == 1 ]] || {
  echo "error: TTY_AUTO_REATTACH must be 0 or 1" >&2; exit 2;
}
for _v in TTY_REATTACH_ATTEMPTS TTY_REATTACH_CONFIRM_TRIES TTY_REATTACH_DELAY; do
  [[ ${!_v} =~ ^[0-9]+$ ]] || { echo "error: $_v must be a non-negative integer" >&2; exit 2; }
done
(( TTY_REATTACH_CONFIRM_TRIES >= 1 )) || { echo "error: TTY_REATTACH_CONFIRM_TRIES must be at least 1" >&2; exit 2; }
HOST_DIR="$PWD"
# Preserve command-line/environment selection separately from any Sprite name
# loaded from resumable session state. A stale state file must never become a
# new implicit SPRITE_NAME after that Sprite has been replaced or destroyed.
REQUESTED_SPRITE_NAME="${SPRITE_NAME:-}"
REQUESTED_SPRITE_ORG="${SPRITE_ORG:-}"
SPRITE_NAME="$REQUESTED_SPRITE_NAME"
CODING_AGENT="${CODING_AGENT:-ask}"
case "$CODING_AGENT" in
  ask|codex|kimi-code) ;;
  *) echo "error: CODING_AGENT must be ask, codex, or kimi-code" >&2; exit 2 ;;
esac
CODEX_PROVIDER="${CODEX_PROVIDER:-ask}"
[[ $CODEX_PROVIDER == moonshot ]] && CODEX_PROVIDER=kimi
case "$CODEX_PROVIDER" in
  ask|openai|deepseek|kimi|minimax) ;;
  *) echo "error: CODEX_PROVIDER must be ask, openai, deepseek, kimi, or minimax" >&2; exit 2 ;;
esac
TRANSPORT="${DEEPSEEK_TRANSPORT:-direct}"
NO_AGENT_LAUNCH="${NO_AGENT_LAUNCH:-${NO_CODEX_LAUNCH:-0}}"
FORCE_NEW_SESSION="${FORCE_NEW_SESSION:-0}"
[[ $FORCE_NEW_SESSION == 0 || $FORCE_NEW_SESSION == 1 ]] || {
  echo "error: FORCE_NEW_SESSION must be 0 or 1" >&2; exit 2;
}
CODEX_START_MODE="${CODEX_START_MODE:-ask}"
KIMI_CODE_START_MODE="${KIMI_CODE_START_MODE:-ask}"
KIMI_CODE_APPROVAL_MODE="${KIMI_CODE_APPROVAL_MODE:-normal}"
SHARED_WORKSPACE_MODE="${SHARED_WORKSPACE_MODE:-auto}"
case "$KIMI_CODE_START_MODE" in
  ask|continue|new) ;;
  *) echo "error: KIMI_CODE_START_MODE must be ask, continue, or new" >&2; exit 2 ;;
esac
case "$KIMI_CODE_APPROVAL_MODE" in
  normal|yolo|auto) ;;
  *) echo "error: KIMI_CODE_APPROVAL_MODE must be normal, yolo, or auto" >&2; exit 2 ;;
esac
case "$SHARED_WORKSPACE_MODE" in
  auto|reuse|sync) ;;
  *) echo "error: SHARED_WORKSPACE_MODE must be auto, reuse, or sync" >&2; exit 2 ;;
esac
[[ $NO_AGENT_LAUNCH == 0 || $NO_AGENT_LAUNCH == 1 ]] || {
  echo "error: NO_AGENT_LAUNCH must be 0 or 1" >&2; exit 2;
}
RESUME_CODEX_HISTORY="${RESUME_CODEX_HISTORY:-0}"
[[ $RESUME_CODEX_HISTORY == 0 || $RESUME_CODEX_HISTORY == 1 ]] || {
  echo "error: RESUME_CODEX_HISTORY must be 0 or 1" >&2
  exit 2
}
case "$CODEX_START_MODE" in
  ask|resume|fork|new) ;;
  *) echo "error: CODEX_START_MODE must be ask, resume, fork, or new" >&2; exit 2 ;;
esac
# Legacy compatibility: RESUME_CODEX_HISTORY=1 explicitly forces resume mode.
[[ $RESUME_CODEX_HISTORY == 1 ]] && CODEX_START_MODE=resume
# Set when the script decides how a newly created TTY should start Codex.
# DeepSeek Thinking remains enabled whenever DeepSeek is selected.
CODEX_START_ACTION=new
CODEX_MODE_SELECTED=0
CODEX_UPDATE_REQUESTED=0
CODEX_UPDATE_COMPLETED=0
CODEX_UPDATE_LIVE_DETECTED=0
RESUME_KIMI_CODE_LAST=0
KIMI_CODE_MODE_SELECTED=0
AGENT_KIND=""
AGENT_LABEL=""
AGENT_PROVIDER=""
DEFAULT_RUN_HOURS="${DEFAULT_RUN_HOURS:-8}"
SPRITE_RUN_HOURS="${SPRITE_RUN_HOURS:-}"
STARTUP_REPO_PUSH_MODE="${STARTUP_REPO_PUSH_MODE:-ask}"
EXIT_AFTER_STARTUP_REPO_PUSH="${EXIT_AFTER_STARTUP_REPO_PUSH:-0}"
case "$STARTUP_REPO_PUSH_MODE" in
  ask|always|never) ;;
  *) echo "error: STARTUP_REPO_PUSH_MODE must be ask, always, or never" >&2; exit 2 ;;
esac
[[ $EXIT_AFTER_STARTUP_REPO_PUSH == 0 || $EXIT_AFTER_STARTUP_REPO_PUSH == 1 ]] || {
  echo "error: EXIT_AFTER_STARTUP_REPO_PUSH must be 0 or 1" >&2
  exit 2
}

case "$TRANSPORT" in
  auto|direct) ;;
  bridge) echo "error: DEEPSEEK_TRANSPORT=bridge is retired; use the native Responses API (direct)" >&2; exit 2 ;;
  *) echo "error: DEEPSEEK_TRANSPORT must be auto or direct" >&2; exit 2 ;;
esac

ORG=()
[[ -n ${SPRITE_ORG:-} ]] && ORG=(-o "$SPRITE_ORG")

C_RESET=$'\033[0m'
C_CYAN=$'\033[1;36m'
C_GREEN=$'\033[1;32m'
C_RED=$'\033[1;31m'
C_YELLOW=$'\033[1;33m'

step() { printf '\n%s=== %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
ok()   { printf '%s  PASS%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s  WARN%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
note() { printf '       %s\n' "$*"; }

local_network_advisory() {
  # Best-effort only. Do not change host networking automatically.
  [[ $(uname -s 2>/dev/null || true) == Linux ]] || return 0
  local warned=0 conn val iface ps
  if command -v nmcli >/dev/null 2>&1; then
    conn=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
      | awk -F: '$2=="wifi" || $2=="802-11-wireless" {print $1; exit}')
    if [[ -n $conn ]]; then
      val=$(nmcli -g 802-11-wireless.powersave connection show "$conn" 2>/dev/null | head -1 || true)
      if [[ $val == 3 ]]; then
        warn "host Wi-Fi power saving appears enabled for '$conn'; long-lived TTY/WebSocket connections may be less reliable"
        note "consider disabling Wi-Fi power saving for that connection while supervising unattended Codex runs"
        warned=1
      fi
    fi
  fi
  if (( warned == 0 )) && command -v iw >/dev/null 2>&1; then
    iface=$(iw dev 2>/dev/null | awk '$1=="Interface" {print $2; exit}')
    if [[ -n $iface ]]; then
      ps=$(iw dev "$iface" get power_save 2>/dev/null || true)
      if grep -qi 'on' <<<"$ps"; then
        warn "host Wi-Fi interface '$iface' reports power_save on; long-lived TTY/WebSocket connections may be less reliable"
        note "consider disabling Wi-Fi power saving while supervising unattended Codex runs"
      fi
    fi
  fi
}

choose_coding_agent() {
  local choice=""
  case "$CODING_AGENT" in
    codex)
      AGENT_KIND=codex
      AGENT_LABEL=Codex
      note "coding agent forced by CODING_AGENT=codex"
      return 0
      ;;
    kimi-code)
      AGENT_KIND=kimi-code
      AGENT_LABEL="Kimi Code"
      note "coding agent forced by CODING_AGENT=kimi-code"
      return 0
      ;;
  esac

  # A forced legacy CODEX_PROVIDER continues to imply Codex.
  if [[ $CODEX_PROVIDER != ask ]]; then
    AGENT_KIND=codex
    AGENT_LABEL=Codex
    note "CODEX_PROVIDER=$CODEX_PROVIDER implies CODING_AGENT=codex"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    AGENT_KIND=codex
    AGENT_LABEL=Codex
    note "no interactive input; defaulting to Codex for backward compatibility"
    return 0
  fi

  printf '\n  Which coding agent should run in the Sprite?\n'
  printf '    1) Codex [default]\n'
  printf '    2) Kimi Code CLI\n'
  printf '  Select [1-2]: '
  IFS= read -r choice || true
  case "${choice,,}" in
    ''|1|c|codex) AGENT_KIND=codex; AGENT_LABEL=Codex ;;
    2|k|kimi|kimi-code) AGENT_KIND=kimi-code; AGENT_LABEL="Kimi Code" ;;
    *) warn "invalid selection; defaulting to Codex"; AGENT_KIND=codex; AGENT_LABEL=Codex ;;
  esac
  note "selected coding agent: $AGENT_LABEL"
}

choose_codex_provider() {
  local choice=""
  case "$CODEX_PROVIDER" in
    openai)
      note "Codex provider forced by CODEX_PROVIDER=openai"
      return 0
      ;;
    deepseek)
      note "Codex provider forced by CODEX_PROVIDER=deepseek"
      return 0
      ;;
    kimi)
      note "Codex provider forced by CODEX_PROVIDER=kimi"
      return 0
      ;;
    minimax)
      note "Codex provider forced by CODEX_PROVIDER=minimax"
      return 0
      ;;
  esac

  if [[ ! -t 0 ]]; then
    CODEX_PROVIDER=deepseek
    note "no interactive input; defaulting to DeepSeek ($DEEPSEEK_MODEL)"
    return 0
  fi

  printf '\n  Which provider should Codex use?\n'
  printf '    1) OpenAI - normal Codex provider/authentication\n'
  printf '    2) DeepSeek - %s [default]\n' "$DEEPSEEK_MODEL"
  printf '    3) Moonshot - %s (native Responses + web search)\n' "$KIMI_MODEL"
  printf '    4) MiniMax - %s (native Responses API)\n' "$MINIMAX_MODEL"
  printf '  Select [1-4]: '
  IFS= read -r choice || true
  case "${choice,,}" in
    1|o|openai) CODEX_PROVIDER=openai ;;
    ''|2|d|deepseek) CODEX_PROVIDER=deepseek ;;
    3|k|kimi|moonshot|kimi-k3) CODEX_PROVIDER=kimi ;;
    4|m|minimax|minimax-m3) CODEX_PROVIDER=minimax ;;
    *)
      warn "invalid selection; defaulting to DeepSeek ($DEEPSEEK_MODEL)"
      CODEX_PROVIDER=deepseek
      ;;
  esac
  note "selected Codex provider: $CODEX_PROVIDER"
}

choose_kimi_code_approval_mode() {
  local choice=""
  if [[ $KIMI_CODE_APPROVAL_MODE != normal ]]; then
    note "Kimi Code approval mode forced: $KIMI_CODE_APPROVAL_MODE"
    return 0
  fi
  [[ -t 0 ]] || return 0
  printf '\n  Which Kimi Code approval mode should be used?\n'
  printf '    1) Normal confirmations [default]\n'
  printf '    2) YOLO: auto-approve tools, but questions are still allowed\n'
  printf '    3) Auto: fully autonomous, no questions\n'
  printf '  Select [1-3]: '
  IFS= read -r choice || true
  case "${choice,,}" in
    ''|1|n|normal) KIMI_CODE_APPROVAL_MODE=normal ;;
    2|y|yolo) KIMI_CODE_APPROVAL_MODE=yolo ;;
    3|a|auto) KIMI_CODE_APPROVAL_MODE=auto ;;
    *) warn "invalid selection; using normal confirmations"; KIMI_CODE_APPROVAL_MODE=normal ;;
  esac
  note "Kimi Code approval mode: $KIMI_CODE_APPROVAL_MODE"
}

choose_kimi_code_start_mode() {
  local context=${1:-"new Kimi Code TTY"}
  local choice=""
  case "$KIMI_CODE_START_MODE" in
    continue)
      RESUME_KIMI_CODE_LAST=1
      KIMI_CODE_MODE_SELECTED=1
      note "$context: continuing the most recent Kimi Code session"
      return 0
      ;;
    new)
      RESUME_KIMI_CODE_LAST=0
      KIMI_CODE_MODE_SELECTED=1
      note "$context: starting a new Kimi Code session"
      return 0
      ;;
  esac
  if [[ ! -t 0 ]]; then
    RESUME_KIMI_CODE_LAST=0
    KIMI_CODE_MODE_SELECTED=1
    warn "no interactive input; starting a new Kimi Code session"
    return 0
  fi
  printf '\n  How should Kimi Code start in the new TTY?\n'
  printf '    1) Continue the most recent Kimi Code session\n'
  printf '    2) Start a new Kimi Code session [default]\n'
  printf '  Select [1-2]: '
  IFS= read -r choice || true
  case "${choice,,}" in
    1|c|continue|resume) RESUME_KIMI_CODE_LAST=1; note "Kimi Code will run: kimi --continue" ;;
    ''|2|n|new) RESUME_KIMI_CODE_LAST=0; note "Kimi Code will start a fresh session in the shared repository workspace" ;;
    *) warn "invalid selection; starting a new Kimi Code session"; RESUME_KIMI_CODE_LAST=0 ;;
  esac
  KIMI_CODE_MODE_SELECTED=1
}

choose_codex_start_mode() {
  local context=${1:-"new Codex TTY"}
  local choice=""

  case "$CODEX_START_MODE" in
    resume)
      CODEX_START_ACTION=resume
      CODEX_MODE_SELECTED=1
      note "$context: resuming the most recent Codex conversation"
      return 0
      ;;
    fork)
      CODEX_START_ACTION=fork
      CODEX_MODE_SELECTED=1
      note "$context: forking the most recent Codex conversation into a new writable thread"
      return 0
      ;;
    new)
      CODEX_START_ACTION=new
      CODEX_MODE_SELECTED=1
      note "$context: starting a new Codex conversation"
      return 0
      ;;
  esac

  if [[ ! -t 0 ]]; then
    warn "no interactive input is available; defaulting to a new Codex conversation"
    CODEX_START_ACTION=new
    CODEX_MODE_SELECTED=1
    return 0
  fi

  printf '\n  How should Codex start in the new TTY?\n'
  printf '    1) Resume the most recent Codex conversation\n'
  printf '    2) Fork the most recent conversation (same history, new writable thread)\n'
  printf '    3) Start a new Codex conversation [default]\n'
  printf '  Select [1-3]: '
  IFS= read -r choice || true
  case "${choice,,}" in
    1|r|resume)
      CODEX_START_ACTION=resume
      note "Codex will run: codex resume --last"
      if [[ $CODEX_PROVIDER == deepseek ]]; then
        note "resume replays the previous chat history through the selected DeepSeek native Responses provider"
      elif [[ $CODEX_PROVIDER == kimi ]]; then
        note "resume replays the previous chat history through the selected Moonshot native Responses provider"
      elif [[ $CODEX_PROVIDER == minimax ]]; then
        note "resume uses the MiniMax native Responses provider selected for this run"
      else
        note "resume uses the normal OpenAI Codex provider selected for this run"
      fi
      ;;
    2|f|fork)
      CODEX_START_ACTION=fork
      note "Codex will run: codex fork --last"
      note "the selected conversation history is preserved under a new writable thread ID"
      note "this is the safe choice when the original thread reports an active writer"
      ;;
    ''|3|n|new)
      CODEX_START_ACTION=new
      note "Codex will start a new conversation in the existing repository workspace"
      note "repository files, Git state, and uncommitted work are preserved"
      ;;
    *)
      warn "invalid selection; starting a new Codex conversation"
      CODEX_START_ACTION=new
      ;;
  esac
  CODEX_MODE_SELECTED=1
}

cleanup_files=()
cleanup_dirs=()
cleanup() {
  local f d
  for f in "${cleanup_files[@]:-}"; do
    [[ -n $f ]] && rm -f -- "$f" 2>/dev/null || true
  done
  for d in "${cleanup_dirs[@]:-}"; do
    [[ -n $d ]] && rm -rf -- "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT

need_local() {
  command -v "$1" >/dev/null 2>&1 || die "required local command not found: $1"
}

run_limited() {
  local secs=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" </dev/null
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

# `sx` is retained for longer remote work whose completion must not be retried
# automatically. Short read/control operations should use control_exec_limited.
sx() {
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "$@" </dev/null
}

# ---------------------------------------------------------------------------
# Bounded non-TTY control exec with transport fallback and framing sentinel.
# ---------------------------------------------------------------------------
# Sprites supports both normal WebSocket exec and --http-post for non-TTY
# commands. A CLI transport can fail after the remote command has already
# completed (for example "no exit frame received"). To avoid confusing a local
# framing failure with the remote command's exit status, every short control
# command is run beneath a tiny shell wrapper which emits a completion sentinel.
#
# IMPORTANT: this helper is only for idempotent/read/control operations. A timed
# out exec may continue remotely after the local connection disappears, so
# non-idempotent launch work (notably native Codex TTY startup) has its own verifier.
SPRITE_EXEC_HTTP_POST_SUPPORT=""
CONTROL_REMOTE_SENTINEL='__SPRITE_CODEX_REMOTE_RC__='

sprite_exec_supports_http_post() {
  if [[ -z $SPRITE_EXEC_HTTP_POST_SUPPORT ]]; then
    if sprite exec --help 2>&1 | grep -q -- '--http-post'; then
      SPRITE_EXEC_HTTP_POST_SUPPORT=1
    else
      SPRITE_EXEC_HTTP_POST_SUPPORT=0
    fi
  fi
  [[ $SPRITE_EXEC_HTTP_POST_SUPPORT == 1 ]]
}

_control_exec_attempt() {
  local secs=$1 mode=$2 out_file=$3 err_file=$4
  shift 4
  [[ ${1:-} == -- ]] && shift
  (($#)) || return 2

  local raw_out raw_err rc remote_rc=""
  local -a extra=()
  raw_out=$(mktemp); raw_err=$(mktemp)
  [[ $mode == http-post ]] && extra=(--http-post)

  # The wrapper itself exits normally after printing the remote command's rc.
  # Thus, if the CLI later reports a missing exit frame but the sentinel arrived,
  # we still know conclusively whether the remote command succeeded.
  local wrapper='"$@"; rc=$?; printf "\n__SPRITE_CODEX_REMOTE_RC__=%d\n" "$rc"; exit 0'
  if command -v timeout >/dev/null 2>&1; then
    if timeout "$secs" sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "${extra[@]}" --no-port-forward -- \
        bash -c "$wrapper" _ "$@" >"$raw_out" 2>"$raw_err" </dev/null; then rc=0; else rc=$?; fi
  elif command -v gtimeout >/dev/null 2>&1; then
    if gtimeout "$secs" sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "${extra[@]}" --no-port-forward -- \
        bash -c "$wrapper" _ "$@" >"$raw_out" 2>"$raw_err" </dev/null; then rc=0; else rc=$?; fi
  else
    if sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "${extra[@]}" --no-port-forward -- \
        bash -c "$wrapper" _ "$@" >"$raw_out" 2>"$raw_err" </dev/null; then rc=0; else rc=$?; fi
  fi

  # Bash variables cannot contain NUL bytes. Scrub transport noise before any
  # caller can capture this function's stdout/stderr with $(...).
  tr -d '\000' <"$raw_out" >"$out_file" 2>/dev/null || cp "$raw_out" "$out_file"
  tr -d '\000' <"$raw_err" >"$err_file" 2>/dev/null || cp "$raw_err" "$err_file"

  remote_rc=$(sed -n 's/^__SPRITE_CODEX_REMOTE_RC__=\([0-9][0-9]*\)$/\1/p' "$out_file" | tail -1)
  rm -f "$raw_out" "$raw_err" 2>/dev/null || true
  if [[ $remote_rc =~ ^[0-9]+$ ]]; then
    # Remove only our sentinel line; preserve the command's actual stdout.
    sed -i '/^__SPRITE_CODEX_REMOTE_RC__=[0-9][0-9]*$/d' "$out_file" 2>/dev/null || true
    CONTROL_ATTEMPT_REMOTE_SEEN=1
    CONTROL_ATTEMPT_REMOTE_RC=$remote_rc
    CONTROL_ATTEMPT_CLI_RC=$rc
    return 0
  fi

  CONTROL_ATTEMPT_REMOTE_SEEN=0
  CONTROL_ATTEMPT_REMOTE_RC=""
  CONTROL_ATTEMPT_CLI_RC=$rc
  return 1
}

control_exec_limited() {
  local secs=$1
  shift
  local first second mode rc out err first_err="" first_rc=""
  out=$(mktemp); err=$(mktemp)

  case "$SPRITE_CONTROL_TRANSPORT" in
    websocket) first=websocket; second="" ;;
    http-post) first=http-post; second="" ;;
    auto) first=websocket; second=http-post ;;
  esac

  for mode in "$first" "$second"; do
    [[ -n $mode ]] || continue
    if [[ $mode == http-post ]] && ! sprite_exec_supports_http_post; then
      continue
    fi
    : >"$out"; : >"$err"
    CONTROL_ATTEMPT_REMOTE_SEEN=0
    CONTROL_ATTEMPT_REMOTE_RC=""
    CONTROL_ATTEMPT_CLI_RC=""
    if _control_exec_attempt "$secs" "$mode" "$out" "$err" "$@"; then
      cat "$out"
      # If the remote sentinel arrived, transport framing noise is non-authoritative.
      # Preserve genuine remote stderr, but suppress the known local framing line.
      sed '/^Error: no exit frame received$/d' "$err" >&2 || true
      rc=$CONTROL_ATTEMPT_REMOTE_RC
      rm -f "$out" "$err" 2>/dev/null || true
      return "$rc"
    fi
    first_rc=${CONTROL_ATTEMPT_CLI_RC:-1}
    first_err=$(cat "$err" 2>/dev/null || true)
    # A second attempt is safe here only because callers of this helper are
    # deliberately restricted to idempotent/read/control operations.
  done

  cat "$out" 2>/dev/null || true
  [[ -z $first_err ]] || printf '%s\n' "$first_err" >&2
  rc=${first_rc:-1}
  rm -f "$out" "$err" 2>/dev/null || true
  return "$rc"
}

# Validate a specific Sprite instead of assuming that a value loaded from an
# old state file or inherited through SPRITE_NAME still exists. The API check is
# cheap; exec is a fallback for CLI/API versions whose root metadata route
# differs. Both calls are bounded and stdin-closed.
sprite_target_exists() {
  local candidate=${1:-}
  [[ -n $candidate ]] || return 1
  run_limited 15 sprite api "${ORG[@]}" -s "$candidate" / >/dev/null 2>&1 && return 0
  run_limited 15 sprite exec "${ORG[@]}" -s "$candidate" -- true >/dev/null 2>&1 && return 0
  return 1
}


# Print the Sprite names that are present in the *current* management-plane
# inventory. This is deliberately different from sprite_target_exists(): an old
# name may still answer a direct API lookup even after it has been replaced.
# For resume-state validation, `sprite list` is authoritative.
current_sprite_names() {
  local api_raw="" list_raw="" parsed=""

  # Use the same API-first source as pick_sprite(). This removes the v29 split
  # brain where saved-state validation trusted an unparsable `sprite list` while
  # the picker immediately rediscovered the same Sprite through /sprites.
  api_raw=$(run_limited 20 sprite api "${ORG[@]}" /sprites 2>/dev/null || true)
  if [[ -n $api_raw ]]; then
    parsed=$(RAW_SPRITE_API="$api_raw" python3 - <<'PYAPI'
import json, os, re
try:
    root=json.loads(os.environ.get("RAW_SPRITE_API", ""))
except Exception:
    raise SystemExit
valid=re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
out=[]
def emit(v):
    if isinstance(v, list):
        for x in v:
            if isinstance(x, dict):
                n=x.get("name") or x.get("sprite_name")
                if isinstance(n,str) and valid.fullmatch(n):
                    out.append(n)
    elif isinstance(v, dict):
        n=v.get("name") or v.get("sprite_name")
        if isinstance(n,str) and valid.fullmatch(n) and ({"id","status","state","url"} & set(v)):
            out.append(n)
        else:
            for x in v.values():
                if isinstance(x,dict):
                    n=x.get("name") or x.get("sprite_name")
                    if isinstance(n,str) and valid.fullmatch(n) and ({"id","status","state","url"} & set(x)):
                        out.append(n)
def walk(v):
    if isinstance(v,list):
        emit(v); return
    if not isinstance(v,dict):
        return
    found=False
    for k in ("sprites","sprite_list"):
        if k in v:
            emit(v[k]); found=True
    for k in ("data","result","results","response"):
        if isinstance(v.get(k),(dict,list)):
            walk(v[k]); found=True
    if not found and "items" in v:
        emit(v["items"])
walk(root)
for n in dict.fromkeys(out):
    print(n)
PYAPI
)
    if [[ -n $parsed ]]; then
      printf '%s\n' "$parsed"
      return 0
    fi
  fi

  # Fallback to the human/table output. Only return early when parsing actually
  # produced at least one valid Sprite name; non-empty decorations/header text
  # are not themselves evidence of a usable inventory.
  list_raw=$(run_limited 20 sprite list "${ORG[@]}" 2>&1 || true)
  [[ -n $list_raw ]] || return 0
  parsed=$(RAW_SPRITE_LIST="$list_raw" python3 - <<'PYLIST'
import os, re
raw=os.environ.get("RAW_SPRITE_LIST", "")
ansi=re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
valid=re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
statuses={"running","warm","cold","stopped","paused","suspended"}
seen=set()

def emit(name, status):
    name=name.strip()
    status=status.strip().lower().split()[0] if status.strip() else ""
    if valid.fullmatch(name) and status in statuses and name not in seen:
        seen.add(name)
        print(name)

for line in raw.splitlines():
    line=ansi.sub("", line).replace("\u00a0", " ").replace("**", "")
    if "│" in line or "|" in line:
        cells=[c.strip() for c in re.split(r"[│|]", line)]
        cells=[c for c in cells if c]
        if len(cells) >= 2:
            emit(cells[0], cells[1])
            continue
    # Defensive fallback for whitespace tables: first token is name, second
    # status. This also handles CLI formatting changes without treating headers
    # as Sprites because status must be one of the known lifecycle values.
    cells=re.split(r"\s{2,}", line.strip())
    if len(cells) >= 2:
        emit(cells[0], cells[1])
PYLIST
)
  [[ -n $parsed ]] && printf '%s\n' "$parsed"
}

sprite_in_current_inventory() {
  local candidate=${1:-} n
  [[ -n $candidate ]] || return 1
  while IFS= read -r n; do
    [[ $n == "$candidate" ]] && return 0
  done < <(current_sprite_names)
  return 1
}

# Return the management-plane lifecycle status without relying on a remote exec.
# A cold Sprite has lost RAM, so no TTY process can still be attached even though
# its filesystem (including Codex rollout history) remains available.
sprite_target_status() {
  local candidate=${1:-} raw status
  [[ -n $candidate ]] || return 1
  raw=$(run_limited 15 sprite api "${ORG[@]}" -s "$candidate" / 2>/dev/null || true)
  if [[ -n $raw ]]; then
    status=$(RAW_SPRITE_STATUS="$raw" python3 - "$candidate" <<'PY'
import json, os, sys
candidate=sys.argv[1]
try:
    root=json.loads(os.environ.get("RAW_SPRITE_STATUS", ""))
except Exception:
    raise SystemExit(1)

def records(node):
    if isinstance(node, dict):
        yield node
        for key in ("sprite", "data", "result", "response"):
            child=node.get(key)
            if isinstance(child, (dict, list)):
                yield from records(child)
    elif isinstance(node, list):
        for child in node:
            if isinstance(child, (dict, list)):
                yield from records(child)

fallback=""
for rec in records(root):
    value=rec.get("status", rec.get("state", ""))
    if isinstance(value, str) and value:
        name=rec.get("name", rec.get("sprite_name", ""))
        if name == candidate:
            print(value.lower()); raise SystemExit(0)
        if not fallback:
            fallback=value.lower()
if fallback:
    print(fallback); raise SystemExit(0)
raise SystemExit(1)
PY
) || status=""
    [[ -n $status ]] && { printf '%s
' "$status"; return 0; }
  fi

  raw=$(run_limited 15 sprite list "${ORG[@]}" 2>/dev/null || true)
  [[ -n $raw ]] || return 1
  RAW_SPRITE_LIST="$raw" python3 - "$candidate" <<'PY'
import os, re, sys
candidate=sys.argv[1]
ansi=re.compile(r"\[[0-9;?]*[ -/]*[@-~]")
known={"cold","warm","running","stopped","suspended","paused"}
for line in os.environ.get("RAW_SPRITE_LIST", "").splitlines():
    clean=ansi.sub("", line)
    if not re.search(r"(?<![A-Za-z0-9._-])"+re.escape(candidate)+r"(?![A-Za-z0-9._-])", clean):
        continue
    words={w.lower() for w in re.findall(r"[A-Za-z]+", clean)}
    hit=known & words
    if hit:
        print(sorted(hit)[0]); raise SystemExit(0)
raise SystemExit(1)
PY
}

# sprite exec --env uses a comma-separated KEY=value string and provides no
# escaping for commas inside values. Serialize the requested variables as JSON
# and hex-encode the JSON so every possible shell environment value survives
# that transport. Environment variables cannot contain NUL bytes, which are
# used only as the local name/value framing below.
make_exec_env() {
  local name value
  for name in "$@"; do
    value=${!name-}
    [[ -n $value ]] || die "environment value is empty: $name"
  done
  {
    for name in "$@"; do
      value=${!name}
      printf '%s\0%s\0' "$name" "$value"
    done
  } | python3 -c '
import json, sys
parts = sys.stdin.buffer.read().split(b"\0")
if parts and parts[-1] == b"":
    parts.pop()
if len(parts) % 2:
    raise SystemExit("invalid environment framing")
data = {
    parts[i].decode("utf-8"): parts[i + 1].decode("utf-8")
    for i in range(0, len(parts), 2)
}
sys.stdout.write(json.dumps(data, separators=(",", ":")).encode("utf-8").hex())
'
}

# Decode the environment map inside the Sprite, merge it into the current
# process environment, and exec the requested command without a credential file.
ENV_EXEC_PY='import json, os, sys
if len(sys.argv) < 2:
    raise SystemExit("missing command")
encoded = os.environ.pop("SPRITE_CODEX_ENV_HEX", "")
if not encoded:
    raise SystemExit("missing encoded environment")
values = json.loads(bytes.fromhex(encoded).decode("utf-8"))
env = os.environ.copy()
allowed = {str(k) for k in values}
for name in list(env):
    if any(word in name.upper() for word in ("TOKEN", "SECRET", "PASSWORD", "API_KEY", "PRIVATE_KEY")) and name not in allowed:
        env.pop(name, None)
env.update({str(k): str(v) for k, v in values.items()})
os.execvpe(sys.argv[1], sys.argv[1:], env)'

# Transfer bytes through the exec process itself. The old --file path tried to
# overwrite fixed /tmp names BEFORE the remote command could run, so chmod/sudo
# inside that command could not repair it. This receiver and its consumer run
# under the same remote identity. Nothing touches a previous invocation's files.
#
# Usage: run_remote_file LOCAL_FILE ENV_HEX REMOTE_CWD -- COMMAND [ARGS...]
# Replace each exact @SPRITE_PAYLOAD@ argument with the verified private file.
# No eval, source text in URL arguments, or automatic retry after execution.
run_remote_file() {
  local source=$1 env_hex=$2 workdir=$3 metadata size digest receiver
  shift 3
  [[ ${1:-} == -- ]] && shift
  (($#)) || { echo "error: run_remote_file needs a remote command" >&2; return 2; }
  [[ -f $source && -r $source ]] || { echo "error: local payload is not readable: $source" >&2; return 2; }
  metadata=$(python3 - "$source" <<'PAYLOAD_META_PY'
import hashlib, sys
size = 0
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        size += len(chunk)
        h.update(chunk)
print(size, h.hexdigest())
PAYLOAD_META_PY
  ) || return 2
  read -r size digest <<<"$metadata"
  local -a options=(--no-port-forward)
  [[ -z $env_hex ]] || options+=(--env "SPRITE_CODEX_ENV_HEX=$env_hex")
  [[ -z $workdir ]] || options+=(--dir "$workdir")
  receiver=$(cat <<'PAYLOAD_RECEIVER'
set -Eeuo pipefail
set +x +v
umask 077
size=$1; expected=$2; receive_timeout=$3; base=$4; decoder=$5
shift 5
[[ $size =~ ^[0-9]+$ && $expected =~ ^[a-f0-9]{64}$ ]] || exit 95
[[ $receive_timeout =~ ^[1-9][0-9]*$ ]] || exit 95
base=${base:-${TMPDIR:-/tmp}}
[[ $base == /* && -d $base ]] || {
  printf 'error: remote temporary base must be an existing absolute directory: %s\n' "$base" >&2
  exit 96
}
for cmd in mktemp head sha256sum timeout; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf 'error: payload reception requires remote command: %s\n' "$cmd" >&2
    exit 96
  }
done
stage=$(mktemp -d -- "${base%/}/sprite-codex.XXXXXXXXXX") || {
  printf 'error: cannot create a private transfer directory under %s (uid=%s)\n' "$base" "$(id -u)" >&2
  printf 'Set SPRITE_UPLOAD_TMPDIR to a writable remote directory; no ownership or permissions were changed.\n' >&2
  exit 96
}
cleanup_payload() { rm -rf -- "$stage" 2>/dev/null || true; }
trap cleanup_payload EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
payload="$stage/payload"
# Read the known byte count, not EOF: a CLI that delays stdin EOF cannot leave
# reception hanging. Never execute a partially received shell/Python program.
if ! timeout "$receive_timeout" head -c "$size" >"$payload"; then
  echo 'error: remote payload reception failed or timed out; command was NOT run' >&2
  exit 97
fi
actual=$(sha256sum -- "$payload")
actual=${actual%% *}
if [[ $actual != "$expected" ]]; then
  echo 'error: remote payload checksum mismatch; command was NOT run' >&2
  exit 97
fi
chmod 600 "$payload"
command_args=()
found=0
for arg in "$@"; do
  if [[ $arg == @SPRITE_PAYLOAD@ ]]; then
    command_args+=("$payload")
    found=1
  else
    command_args+=("$arg")
  fi
done
(( found )) || { echo 'error: missing payload placeholder' >&2; exit 95; }
# Environment decoding takes place only after reception and verification. The
# helper sees /dev/null on stdin, never script bytes or the operator's terminal.
# Keep this parent shell alive so its EXIT trap removes only this private stage.
if [[ -n ${SPRITE_CODEX_ENV_HEX:-} ]]; then
  python3 -c "$decoder" "${command_args[@]}" </dev/null
else
  "${command_args[@]}" </dev/null
fi
PAYLOAD_RECEIVER
  )
  # Deliberately do not use run_limited/sx: those redirect stdin to /dev/null.
  # Non-TTY WebSocket exec carries the file stream. Existing short control calls
  # can still use the configured HTTP-POST fallback independently.
  local -a deadline_command=()
  if [[ -n ${_TOKEN_EXEC_LIMIT:-} ]]; then
    deadline_command=(python3 -c '
import os, signal, subprocess, sys
p = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    rc = p.wait(timeout=int(sys.argv[1]))
except (subprocess.TimeoutExpired, KeyboardInterrupt) as exc:
    try: os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError: pass
    p.wait()
    rc = 130 if isinstance(exc, KeyboardInterrupt) else 124
    print("token validation transport interrupted/timed out", file=sys.stderr)
raise SystemExit(rc if rc >= 0 else 128-rc)
' "$_TOKEN_EXEC_LIMIT")
  fi
  "${deadline_command[@]}" sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "${options[@]}" -- \
    bash -c "$receiver" sprite-codex-transfer "$size" "$digest" \
      "$SPRITE_UPLOAD_TIMEOUT" "$SPRITE_UPLOAD_TMPDIR" "$ENV_EXEC_PY" "$@" <"$source"
}

# Install a new immutable pair of native entrypoints. They retain SESSION_TAG
# in their names for native session discovery, but never truncate a live runner.
install_native_entrypoints() {
  local runner_source=$1 entry_source=$2 installer request_id
  request_id=$(python3 -c 'import secrets; print(secrets.token_hex(12))') || return 1
  REMOTE_RUNNER="$REMOTE_HOME/.local/bin/${SESSION_TAG}-runner-${request_id}"
  REMOTE_ENTRY="$REMOTE_HOME/.local/bin/${SESSION_TAG}-entry-${request_id}"
  installer=$(mktemp)
  cleanup_files+=("$installer")
  python3 - "$runner_source" "$entry_source" "$REMOTE_RUNNER" "$REMOTE_ENTRY" >"$installer" <<'BUILD_ENTRY_INSTALLER_PY'
import json, pathlib, sys
sources = sys.argv[1:3]
destinations = sys.argv[3:5]
items = [[dst, pathlib.Path(src).read_bytes().hex()] for src, dst in zip(sources, destinations)]
print("#!/usr/bin/env python3\nimport os, tempfile\nitems = " + repr(items))
print(r"""
created = []
try:
    for path, encoded in items:
        directory = os.path.dirname(path)
        os.makedirs(directory, mode=0o700, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".sprite-entry-", dir=directory)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(bytes.fromhex(encoded))
                f.flush()
                os.fsync(f.fileno())
            os.chmod(temporary, 0o700)
            # link is atomic and refuses any pre-existing destination, including
            # symlinks. Each install has fresh names; never overwrite a live file.
            os.link(temporary, path)
            created.append(path)
        finally:
            os.unlink(temporary)
except BaseException:
    for path in created:
        try:
            os.unlink(path)
        except OSError:
            pass
    raise
print("       installed new private native runner/entrypoint pair")
""")
BUILD_ENTRY_INSTALLER_PY
  [[ -s $installer ]] || return 1
  run_remote_file "$installer" "" "" -- python3 @SPRITE_PAYLOAD@
}

sx_env() {
  local env_hex=$1
  shift
  [[ ${1:-} == -- ]] && shift
  (($#)) || die "sx_env requires a remote command"
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME"     --env "SPRITE_CODEX_ENV_HEX=$env_hex" --     python3 -c "$ENV_EXEC_PY" "$@" </dev/null
}

prompt_secret() {
  local var_name=$1 label=$2 current
  current=${!var_name:-}
  if [[ -z $current ]]; then
    printf '  %s, hidden: ' "$label"
    IFS= read -rs current || true
    echo
  else
    note "$var_name supplied by environment"
  fi
  [[ -n $current ]] || die "$label is required"
  printf -v "$var_name" '%s' "$current"
}

# Verified only for this invocation, exact credential, target Sprite and scope.
# Nothing from this cache is persisted in resume state or credential files.
declare -A TOKEN_VALIDATED=()

credential_fingerprint() {
  local name=$1 kind=$2
  printf '%s\0' "$kind" "${!name:-}" "$SPRITE_NAME" "${SPRITE_ORG:-}" \
    "${GITHUB_REPOSITORY:-}" "${FLY_APP:-}" \
    "$DEEPSEEK_MODEL" "$MINIMAX_MODEL" "$KIMI_MODEL" \
    "$DEEPSEEK_BASE_URL" "$MINIMAX_BASE_URL" "$MOONSHOT_BASE_URL" \
    "$DEEPSEEK_REASONING_EFFORT" "$MINIMAX_REASONING_EFFORT" "$KIMI_REASONING_EFFORT" \
    | if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | cut -d ' ' -f 1
      elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | cut -d ' ' -f 1
      else
        python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
      fi
}

validate_token_once() {
  local name=$1 kind=$2 nonce packed output cli_rc=0
  local -a names=("$name" TOKEN_CHECK_TIMEOUT)
  case "$kind" in
    github) names+=(GITHUB_REPOSITORY) ;;
    fly) names+=(FLY_APP) ;;
    deepseek|minimax|moonshot) names+=("${MODEL_TEST_ENV_NAMES[@]}") ;;
    *) die "unsupported credential validation kind" ;;
  esac
  nonce=$(python3 -c 'import secrets; print(secrets.token_hex(16))') || return 1
  if [[ -z ${MODEL_TEST_HELPER:-} || ! -f $MODEL_TEST_HELPER ]]; then make_model_test_helper; fi
  packed=$(make_exec_env "${names[@]}") || return 1
  # Dynamic local limits the local CLI too. Each remote operation has its own
  # hard timeout. There is no automatic retransmission of a billable model call.
  local _TOKEN_EXEC_LIMIT=$((TOKEN_CHECK_TIMEOUT * 3 + SPRITE_UPLOAD_TIMEOUT + SPRITE_CONTROL_TIMEOUT + 15))
  if output=$(run_remote_file "$MODEL_TEST_HELPER" "$packed" "" -- \
      python3 @SPRITE_PAYLOAD@ --validate-token "$kind" "$nonce" 2>&1); then
    cli_rc=0
  else
    cli_rc=$?
  fi
  (( cli_rc != 130 && cli_rc != 143 )) || return 130
  # Never print raw Sprite CLI errors: they could echo the --env argument.
  # Require a result for this exact request, even when the CLI claims exit 0.
  printf '%s' "$output" | python3 -c '
import json, re, sys
kind, nonce, name, cli_rc = sys.argv[1:]
try:
    rows = [json.loads(line.split("=",1)[1]) for line in sys.stdin.read().splitlines()
            if line.startswith("SPRITE_TOKEN_RESULT=")]
    if len(rows) != 1:
        raise ValueError()
    row = rows[0]
    if (not isinstance(row, dict) or row.get("schema_version") != 1 or
        row.get("nonce") != nonce or row.get("kind") != kind or type(row.get("passed")) is not bool):
        raise ValueError()
    category, detail = row.get("category"), row.get("detail")
    if (not isinstance(category, str) or not re.fullmatch(r"[a-z-]{1,40}", category) or
        not isinstance(detail, str) or not detail.isascii() or not all(c.isprintable() for c in detail) or len(detail) > 500):
        raise ValueError()
    if row["passed"] != (category == "ok"):
        raise ValueError()
except (ValueError, TypeError, KeyError):
    print("       FAIL %s: Sprite did not confirm this validation request (transport rc=%s). No token was accepted." % (name, cli_rc))
    raise SystemExit(1)
print("       %s %s [%s]: %s" % ("PASS" if row["passed"] else "FAIL", name, category, detail))
raise SystemExit(0 if row["passed"] else (130 if category == "interrupted" else 1))
' "$kind" "$nonce" "$name" "$cli_rc"
}

prompt_validated_secret() {
  local name=$1 label=$2 kind=$3 fingerprint choice rc
  fingerprint=$(credential_fingerprint "$name" "$kind") || die "cannot fingerprint credential context"
  if [[ -n ${!name:-} && ${TOKEN_VALIDATED[$name]:-} == "$fingerprint" ]]; then
    note "$name already verified for this Sprite and target in this run"
    return 0
  fi
  while :; do
    if [[ -z ${!name:-} ]]; then
      [[ -t 0 ]] || die "$name is required; no interactive terminal is available"
      printf '  %s, hidden (Enter aborts): ' "$label"
      if ! IFS= read -rs "$name"; then printf '\n'; die "credential entry cancelled; no new agent launched"; fi
      printf '\n'
      [[ -n ${!name:-} ]] || die "credential entry cancelled; no new agent launched"
    fi
    note "validating $name on Sprite $SPRITE_NAME"
    if validate_token_once "$name" "$kind"; then
      fingerprint=$(credential_fingerprint "$name" "$kind") || die "cannot record credential validation"
      TOKEN_VALIDATED[$name]=$fingerprint
      # Rebuild aliases from the accepted value, never from a failed candidate.
      case "$kind" in
        github) GH_TOKEN=$GITHUB_PAT; GITHUB_TOKEN=$GITHUB_PAT ;;
        fly) FLY_ACCESS_TOKEN=$FLY_API_TOKEN ;;
      esac
      return 0
    else
      rc=$?
    fi
    unset 'TOKEN_VALIDATED[$name]'
    (( rc != 130 )) || die "credential validation interrupted; no new agent launched"
    [[ -t 0 ]] || die "$name did not pass validation; no new agent launched (non-interactive run)"
    while :; do
      printf '\n  %s did not pass validation.\n' "$name"
      printf '    1) Enter a replacement token [default]\n    2) Retry the same token\n    3) Abort without launching\n'
      printf '  Select [1-3]: '
      IFS= read -r choice || die "credential validation cancelled; no new agent launched"
      case "${choice,,}" in
        ''|1|n|new|replace) printf -v "$name" '%s' ''; break ;;
        2|r|retry) break ;;
        3|a|abort|q|quit) die "credential validation cancelled; no new agent launched" ;;
        *) warn "invalid selection" ;;
      esac
    done
  done
}

assert_token_validation_gate() {
  local name kind fingerprint spec
  local -a required=(GITHUB_PAT:github FLY_API_TOKEN:fly)
  if [[ $AGENT_KIND == codex ]]; then
    [[ $CODEX_PROVIDER != deepseek && $CODEX_DEEPSEEK_ACCESS != 1 ]] || required+=(DEEPSEEK_API_KEY:deepseek)
    [[ $CODEX_PROVIDER != minimax && $CODEX_MINIMAX_ACCESS != 1 ]] || required+=(MINIMAX_API_KEY:minimax)
    [[ $CODEX_PROVIDER != kimi && $CODEX_MOONSHOT_ACCESS != 1 ]] || required+=(MOONSHOT_API_KEY:moonshot)
  fi
  for spec in "${required[@]}"; do
    name=${spec%:*}; kind=${spec#*:}
    [[ -n ${!name:-} ]] || die "credential gate: $name is missing; refusing to launch"
    fingerprint=$(credential_fingerprint "$name" "$kind") || die "credential gate failed"
    [[ ${TOKEN_VALIDATED[$name]:-} == "$fingerprint" ]] || die "credential gate: $name or its target changed or was never validated; refusing to launch"
  done
  [[ ${GH_TOKEN:-} == "$GITHUB_PAT" && ${GITHUB_TOKEN:-} == "$GITHUB_PAT" ]] || die "credential gate: GitHub aliases differ from the validated token"
  [[ ${FLY_ACCESS_TOKEN:-} == "$FLY_API_TOKEN" ]] || die "credential gate: Fly aliases differ from the validated token"
}

collect_validated_credentials() {
  step "validate credentials on the selected Sprite"
  note "every supplied credential must pass before repository synchronization or a new Codex agent/preflight"
  note "provider checks make one generation request per used key and may incur charges"
  note "failed checks allow replacement/retry/abort; network or quota failures are not proof of an invalid token"
  note "credentials use process-scoped JSON/hex transport; the encoded value may appear in local process arguments"
  prompt_validated_secret GITHUB_PAT "GitHub PAT for $GITHUB_REPOSITORY" github
  if [[ -n ${FLY_ACCESS_TOKEN:-} && -n ${FLY_API_TOKEN:-} && $FLY_ACCESS_TOKEN != "$FLY_API_TOKEN" ]]; then
    warn "Fly aliases differ; validating FLY_API_TOKEN and replacing FLY_ACCESS_TOKEN only after success"
  fi
  FLY_API_TOKEN=${FLY_API_TOKEN:-${FLY_ACCESS_TOKEN:-}}
  prompt_validated_secret FLY_API_TOKEN "Fly.io token for $FLY_APP" fly
  if [[ $AGENT_KIND == codex ]]; then
    step "optional provider-key access for Codex experiments"
    choose_codex_secret_access CODEX_MOONSHOT_ACCESS MOONSHOT_API_KEY "Moonshot"
    choose_codex_secret_access CODEX_MINIMAX_ACCESS MINIMAX_API_KEY "MiniMax"
    choose_codex_secret_access CODEX_DEEPSEEK_ACCESS DEEPSEEK_API_KEY "DeepSeek"
    if [[ $CODEX_PROVIDER == deepseek || $CODEX_DEEPSEEK_ACCESS == 1 ]]; then
      note "DeepSeek credential target: $DEEPSEEK_MODEL at $DEEPSEEK_BASE_URL"
      prompt_validated_secret DEEPSEEK_API_KEY "DeepSeek API key" deepseek
    fi
    if [[ $CODEX_PROVIDER == minimax || $CODEX_MINIMAX_ACCESS == 1 ]]; then
      note "MiniMax credential target: $MINIMAX_MODEL at $MINIMAX_BASE_URL"
      prompt_validated_secret MINIMAX_API_KEY "MiniMax API or Subscription Key" minimax
    fi
    if [[ $CODEX_PROVIDER == kimi || $CODEX_MOONSHOT_ACCESS == 1 ]]; then
      note "Moonshot credential target: $KIMI_MODEL at $MOONSHOT_BASE_URL"
      prompt_validated_secret MOONSHOT_API_KEY "Moonshot API key" moonshot
    fi
  fi
  assert_token_validation_gate
  ok "all credentials required by this run passed validation"
}

choose_codex_secret_access() {
  local access_var=$1 key_var=$2 label=$3 choice="" current
  [[ $AGENT_KIND == codex ]] || { printf -v "$access_var" '%s' 0; return 0; }
  current=${!access_var}

  case "$current" in
    1)
      note "$access_var=1: $label will be available to Codex-run experiment processes"
      return 0
      ;;
    0)
      note "$access_var=0: $label will remain hidden from Codex shell/tools"
      return 0
      ;;
  esac

  if [[ ! -t 0 ]]; then
    printf -v "$access_var" '%s' 0
    note "non-interactive run: optional $label access defaults to disabled"
    return 0
  fi

  printf '\n  Make %s available to Codex-run experiment processes? [y/N]: ' "$key_var"
  IFS= read -r choice || true
  case "${choice,,}" in
    y|yes|1) printf -v "$access_var" '%s' 1 ;;
    ''|n|no|0) printf -v "$access_var" '%s' 0 ;;
    *) warn "invalid selection; $label experiment access remains disabled"; printf -v "$access_var" '%s' 0 ;;
  esac

  if [[ ${!access_var} == 1 ]]; then
    warn "$key_var will be process-scoped but readable by commands Codex launches for this run"
    note "the bootstrap will not write the key to a credential file; do not ask Codex to print or dump its environment"
  else
    note "$label experiment access disabled; Codex shell/tools will not receive $key_var"
  fi
}

build_codex_credential_env() {
  local -a names=(
    GH_TOKEN GITHUB_TOKEN GITHUB_REPOSITORY GH_REPO GH_HOST GH_PROMPT_DISABLED GIT_TERMINAL_PROMPT
    FLY_API_TOKEN FLY_ACCESS_TOKEN FLY_APP
    CODEX_MOONSHOT_ACCESS CODEX_MINIMAX_ACCESS CODEX_DEEPSEEK_ACCESS
  )
  local n
  for n in "$@"; do names+=("$n"); done
  [[ $CODEX_MOONSHOT_ACCESS == 1 ]] && names+=(MOONSHOT_API_KEY)
  [[ $CODEX_MINIMAX_ACCESS == 1 ]] && names+=(MINIMAX_API_KEY)
  [[ $CODEX_DEEPSEEK_ACCESS == 1 ]] && names+=(DEEPSEEK_API_KEY)

  local -A seen=()
  local -a unique=()
  for n in "${names[@]}"; do
    [[ -n ${seen[$n]+x} ]] && continue
    seen[$n]=1
    unique+=("$n")
  done
  make_exec_env "${unique[@]}"
}

# Parse a GitHub remote into OWNER/REPO when possible.
detect_github_repo() {
  local url=""
  command -v git >/dev/null 2>&1 || return 0
  git -C "$HOST_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  url=$(git -C "$HOST_DIR" remote get-url origin 2>/dev/null || true)
  [[ -n $url ]] || return 0
  python3 - "$url" <<'PY'
import re, sys
u = sys.argv[1].strip()
patterns = [
    r"^(?:https?://|ssh://git@)github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?$",
    r"^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$",
]
for p in patterns:
    m = re.match(p, u)
    if m:
        print(f"{m.group(1)}/{m.group(2)}")
        break
PY
}

# Read app = "..." from the host's fly.toml without requiring a new Python.
detect_fly_app() {
  local f="$HOST_DIR/fly.toml"
  [[ -f $f ]] || return 0
  python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]
try:
    import tomllib
    with open(p, "rb") as fh:
        value = tomllib.load(fh).get("app")
    if isinstance(value, str) and value.strip():
        print(value.strip())
        raise SystemExit
except (ImportError, Exception):
    pass
for line in open(p, encoding="utf-8", errors="replace"):
    m = re.match(r'^\s*app\s*=\s*["\']([^"\']+)["\']\s*(?:#.*)?$', line)
    if m:
        print(m.group(1).strip())
        break
PY
}

pick_sprite() {
  if [[ -n $SPRITE_NAME ]]; then
    if sprite_in_current_inventory "$SPRITE_NAME"; then
      note "using SPRITE_NAME=$SPRITE_NAME (confirmed in current Sprite inventory)"
      return 0
    fi
    warn "Sprite '$SPRITE_NAME' is not present in the current Sprite inventory; refreshing the Sprite selection"
    SPRITE_NAME=""
  fi

  local api_raw="" list_raw="" parsed="" n sel i
  local -a names=()
  local -A seen=()

  add_name() {
    local candidate=$1
    [[ $candidate =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 0
    [[ -n ${SPRITE_ORG:-} && $candidate == "$SPRITE_ORG" ]] && return 0
    case "${candidate,,}" in
      name|sprite|sprites|organization|organisation|org|status|state|url|created|updated|running|stopped|warm|suspended|total)
        return 0 ;;
    esac
    [[ -n ${seen[$candidate]:-} ]] && return 0
    seen[$candidate]=1
    names+=("$candidate")
  }

  printf '       querying sprite api ... '
  api_raw=$(run_limited 20 sprite api "${ORG[@]}" /sprites 2>/dev/null || true)
  printf '%s\n' "$([[ -n $api_raw ]] && echo ok || echo 'no output')"

  if [[ -n $api_raw ]]; then
    while IFS= read -r n; do add_name "$n"; done < <(
      printf '%s' "$api_raw" | python3 -c '
import json, re, sys
try: root = json.load(sys.stdin)
except Exception: raise SystemExit
valid = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
out = []
def emit(v):
    if isinstance(v, list):
        for x in v:
            if isinstance(x, dict):
                n = x.get("name") or x.get("sprite_name")
                if isinstance(n, str) and valid.fullmatch(n): out.append(n)
    elif isinstance(v, dict):
        n = v.get("name") or v.get("sprite_name")
        if isinstance(n, str) and valid.fullmatch(n) and ({"id","status","state","url"} & set(v)):
            out.append(n)
        else:
            for x in v.values():
                if isinstance(x, dict):
                    n = x.get("name") or x.get("sprite_name")
                    if isinstance(n, str) and valid.fullmatch(n) and ({"id","status","state","url"} & set(x)):
                        out.append(n)
def walk(v):
    if isinstance(v, list): emit(v); return
    if not isinstance(v, dict): return
    found = False
    for k in ("sprites","sprite_list"):
        if k in v: emit(v[k]); found = True
    for k in ("data","result","results","response"):
        if isinstance(v.get(k), (dict,list)): walk(v[k]); found = True
    if not found and "items" in v: emit(v["items"])
walk(root)
for n in dict.fromkeys(out): print(n)
' 2>/dev/null
    )
  fi

  if ((${#names[@]} == 0)); then
    printf '       querying sprite list ... '
    list_raw=$(run_limited 20 sprite list "${ORG[@]}" 2>&1 || true)
    printf '%s\n' "$([[ -n $list_raw ]] && echo ok || echo 'no output')"
    if [[ -n $list_raw ]]; then
      while IFS= read -r parsed; do add_name "$parsed"; done < <(
        printf '%s\n' "$list_raw" | python3 -c '
import re, sys
ansi = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
valid = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
meta = {"NAME","SPRITE","SPRITES","ORGANIZATION","ORGANISATION","ORG","STATUS","STATE","URL","CREATED","UPDATED","RUNNING","STOPPED","WARM","SUSPENDED","TOTAL"}
lines = [ansi.sub("", x.rstrip()) for x in sys.stdin]
def norm(s): return re.sub(r"\s+", " ", s.strip()).upper()
def table(rows):
    hi = ni = None
    for i,row in enumerate(rows):
        for j,c in enumerate(row):
            if norm(c) in {"NAME","SPRITE","SPRITE NAME","SPRITE_NAME"}: hi,ni=i,j; break
        if hi is not None: break
    if hi is None: return []
    out=[]
    for row in rows[hi+1:]:
        if ni < len(row):
            v=row[ni].strip()
            if valid.fullmatch(v) and norm(v) not in meta: out.append(v)
    return out
rows=[]
for line in lines:
    if "│" in line or "|" in line:
        c=[x.strip() for x in re.split(r"[│|]",line)]
        if c and not c[0]: c.pop(0)
        if c and not c[-1]: c.pop()
        if c: rows.append(c)
out=table(rows)
if not out:
    rows=[[x.strip() for x in re.split(r"\s{2,}",line.strip()) if x.strip()] for line in lines]
    out=table([x for x in rows if len(x)>=2])
if not out:
    out=[line.strip() for line in lines if valid.fullmatch(line.strip()) and norm(line) not in meta]
for n in dict.fromkeys(out): print(n)
' 2>/dev/null
      )
    fi
  fi

  if ((${#names[@]} == 0)); then
    warn "no Sprite names could be detected automatically"
    note "make sure 'sprite login' has completed; some accounts also need SPRITE_ORG"
    printf '  type the Sprite name: '
    IFS= read -r SPRITE_NAME || true
    [[ -n $SPRITE_NAME ]] || die "no Sprite selected"
    return 0
  fi

  if ((${#names[@]} == 1)); then
    SPRITE_NAME=${names[0]}
    note "one Sprite found: $SPRITE_NAME"
    return 0
  fi

  echo "  Sprites:"
  i=1
  for n in "${names[@]}"; do
    printf '    %d) %s\n' "$i" "$n"
    ((i++))
  done
  while :; do
    printf '  choose [1-%d] or type a name: ' "${#names[@]}"
    IFS= read -r sel || true
    if [[ $sel =~ ^[0-9]+$ ]] && ((sel >= 1 && sel <= ${#names[@]})); then
      SPRITE_NAME=${names[sel-1]}
      break
    elif [[ $sel =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      SPRITE_NAME=$sel
      break
    fi
    warn "invalid selection"
  done
}

# Build a one-shot updater that installs the latest stable Codex npm release in
# a versioned directory and atomically repoints ~/.local/bin/codex. Existing
# release directories are never modified, which keeps the files backing a live
# Codex process intact even when the operator explicitly overrides the warning.
make_codex_latest_updater() {
  local f
  f=$(mktemp)
  cleanup_files+=("$f")
  cat >"$f" <<'CODEX_UPDATE_REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REQUEST_ID=${1:?request id required}
[[ $REQUEST_ID =~ ^[A-Za-z0-9._-]{8,96}$ ]] || {
  echo "invalid Codex update request id" >&2
  exit 46
}

export PATH="$HOME/.local/bin:$HOME/.fly/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# A Sprite's Node runtime may live under an NVM tree that a minimal non-login
# shell does not place on PATH. Discover those bins before requiring npm/node.
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r d; do
    [[ -n $d ]] || continue
    case ":$PATH:" in
      *":$d:"*) ;;
      *) PATH="$d:$PATH" ;;
    esac
  done < <(python3 - <<'PYNODE'
import glob, os, re

def key(path):
    match = re.search(r"/v?(\d+)\.(\d+)\.(\d+)/bin/node$", path)
    return tuple(map(int, match.groups())) if match else (0, 0, 0)

patterns = [
    "/.sprite/languages/node/nvm/versions/node/*/bin/node",
    os.path.expanduser("~/.nvm/versions/node/*/bin/node"),
    os.path.expanduser("~/.local/share/nvm/versions/node/*/bin/node"),
]
seen = set()
rows = []
for pattern in patterns:
    for node in glob.glob(pattern):
        if os.path.isfile(node) and os.access(node, os.X_OK):
            directory = os.path.dirname(node)
            if directory not in seen:
                seen.add(directory)
                rows.append((key(node), directory))
for _, directory in sorted(rows, reverse=True):
    print(directory)
PYNODE
  )
fi
export PATH

for cmd in python3 node npm; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "cannot update Codex: required Sprite command is missing: $cmd" >&2
    exit 47
  }
done

version_ge() {
  python3 - "$1" "$2" <<'PYVER'
import re, sys

def version(value):
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", value or "")
    if not match:
        raise SystemExit(2)
    return tuple(map(int, match.groups()))

raise SystemExit(0 if version(sys.argv[1]) >= version(sys.argv[2]) else 1)
PYVER
}

version_eq() {
  python3 - "$1" "$2" <<'PYVER'
import re, sys

def version(value):
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", value or "")
    if not match:
        raise SystemExit(2)
    return tuple(map(int, match.groups()))

raise SystemExit(0 if version(sys.argv[1]) == version(sys.argv[2]) else 1)
PYVER
}

resolver="$HOME/.local/bin/sprite-codex-cli"
current_path=""
current_version=""
if [[ -x $resolver ]]; then
  current_path=$("$resolver" --sprite-codex-resolve 2>/dev/null || true)
  current_version=$("$resolver" --version 2>/dev/null || true)
else
  current_path=$(command -v codex 2>/dev/null || true)
  if [[ -n $current_path ]]; then
    current_version=$("$current_path" --version 2>/dev/null || true)
  fi
fi
printf '       current Codex: %s | %s\n' "${current_path:-not found}" "${current_version:-unknown}"

latest_json=$(npm view --json @openai/codex@latest version)
latest=$(LATEST_JSON="$latest_json" python3 - <<'PYLATEST'
import json, os
raw = os.environ.get("LATEST_JSON", "")
try:
    value = json.loads(raw)
except Exception:
    value = raw.strip().strip('"')
if isinstance(value, list):
    value = value[-1] if value else ""
if not isinstance(value, str):
    value = ""
print(value.strip())
PYLATEST
)
[[ $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "npm did not return a valid stable Codex version: ${latest:-empty}" >&2
  exit 48
}
printf '       latest stable npm release: %s\n' "$latest"

release_root="$HOME/.local/share/sprite-codex/codex-releases"
config_root="$HOME/.config/sprite-codex"
selection="$HOME/.local/bin/codex"
marker="$config_root/codex-latest-update.state"
mkdir -p "$release_root" "$config_root" "$HOME/.local/bin"
chmod 700 "$release_root" "$config_root" "$HOME/.local/bin" 2>/dev/null || true

target=""
target_version=""
shopt -s nullglob
for candidate in "$release_root/$latest" "$release_root/$latest"-*; do
  [[ -x $candidate/bin/codex ]] || continue
  candidate_version=$("$candidate/bin/codex" --version 2>/dev/null || true)
  if version_eq "$candidate_version" "$latest"; then
    target=$candidate
    target_version=$candidate_version
    break
  fi
done
shopt -u nullglob

stage=""
cleanup_stage() {
  [[ -z $stage ]] || rm -rf -- "$stage" 2>/dev/null || true
}
trap cleanup_stage EXIT INT TERM

if [[ -z $target ]]; then
  stage=$(mktemp -d "$release_root/.install-${latest}.XXXXXX")
  echo "       installing @openai/codex@$latest into an isolated user release"
  npm install -g --prefix "$stage" --no-audit --no-fund --loglevel=error \
    "@openai/codex@$latest"
  [[ -x $stage/bin/codex ]] || {
    echo "the isolated Codex install did not create $stage/bin/codex" >&2
    exit 49
  }
  target_version=$("$stage/bin/codex" --version 2>/dev/null || true)
  version_eq "$target_version" "$latest" || {
    echo "isolated Codex reported an unexpected version: ${target_version:-unknown}" >&2
    exit 49
  }
  target="$release_root/${latest}-${REQUEST_ID}"
  [[ ! -e $target ]] || target="$release_root/${latest}-${REQUEST_ID}-$$"
  mv -- "$stage" "$target"
  stage=""
else
  echo "       verified isolated Codex $latest already exists; reusing it"
fi

target_version=$("$target/bin/codex" --version 2>/dev/null || true)
version_eq "$target_version" "$latest" || {
  echo "the isolated Codex release became unusable after selection: ${target_version:-unknown}" >&2
  exit 49
}

# Replace only the selector. Do not npm-update the package directory from which a
# live Node/Codex process may still be loading code.
if [[ -e $selection && ! -f $selection && ! -L $selection ]]; then
  echo "refusing to replace non-file Codex selector: $selection" >&2
  exit 50
fi
selector_tmp="$HOME/.local/bin/.codex-select-${REQUEST_ID}-$$"
rm -f -- "$selector_tmp"
ln -s "$target/bin/codex" "$selector_tmp"
if ! mv -Tf -- "$selector_tmp" "$selection" 2>/dev/null; then
  rm -f -- "$selection"
  mv -- "$selector_tmp" "$selection"
fi
hash -r 2>/dev/null || true

if [[ -x $resolver ]]; then
  selected_path=$("$resolver" --sprite-codex-resolve 2>/dev/null || true)
  selected_version=$("$resolver" --version 2>/dev/null || true)
else
  selected_path=$selection
  selected_version=$("$selection" --version 2>/dev/null || true)
fi
[[ -n $selected_path && -n $selected_version ]] || {
  echo "the latest Codex was installed, but the active selector could not be verified" >&2
  exit 51
}
version_ge "$selected_version" "$latest" || {
  echo "the active Codex resolver still selects an older version: $selected_version" >&2
  exit 51
}

marker_tmp="$marker.${REQUEST_ID}.tmp"
{
  printf 'request_id=%s\n' "$REQUEST_ID"
  printf 'status=ok\n'
  printf 'latest=%s\n' "$latest"
  printf 'selected_path=%s\n' "$selected_path"
  printf 'selected_version=%s\n' "$selected_version"
  printf 'isolated_target=%s\n' "$target"
  printf 'updated_at=%s\n' "$(date -u '+%FT%TZ')"
} >"$marker_tmp"
chmod 600 "$marker_tmp"
mv -f -- "$marker_tmp" "$marker"

printf '       selected Codex: %s | %s\n' "$selected_path" "$selected_version"
printf '       isolated release: %s\n' "$target"
echo "CODEX_LATEST_UPDATE_OK request_id=$REQUEST_ID latest=$latest"
CODEX_UPDATE_REMOTE
  printf '%s' "$f"
}

run_codex_latest_update() {
  local helper request_id rc=0 verify=""
  helper=$(make_codex_latest_updater)
  request_id=$(python3 - <<'PYREQUEST'
import secrets, time
print("%x-%s" % (int(time.time()), secrets.token_hex(8)))
PYREQUEST
)

  step "update Codex CLI to the latest stable release"
  note "the update is credential-free and does not read or modify ~/.codex conversation files"
  note "the selected release is installed separately, then ~/.local/bin/codex is switched atomically"
  cleanup_files+=("$helper")
  if run_remote_file "$helper" "" "" -- bash @SPRITE_PAYLOAD@ "$request_id"; then
    CODEX_UPDATE_COMPLETED=1
    ok "latest stable Codex was selected on Sprite $SPRITE_NAME"
    return 0
  else
    rc=$?
  fi

  # The CLI transport can fail after the remote npm/install command completed.
  # Verify this exact request id before reporting a failure; never retry the
  # non-idempotent install automatically.
  verify=$(control_exec_limited 20 -- bash -lc '
marker="$HOME/.config/sprite-codex/codex-latest-update.state"
request=$1
[[ -f $marker ]] || exit 1
actual_request=$(sed -n "s/^request_id=//p" "$marker" | tail -1)
status=$(sed -n "s/^status=//p" "$marker" | tail -1)
[[ $actual_request == "$request" && $status == ok ]] || exit 1
cat "$marker"
' _ "$request_id" 2>/dev/null || true)
  if [[ $verify == *"request_id=$request_id"* && $verify == *$'status=ok'* ]]; then
    printf '%s\n' "$verify" | sed 's/^/       verified: /'
    CODEX_UPDATE_COMPLETED=1
    ok "latest stable Codex update completed despite a local transport error"
    return 0
  fi

  warn "latest Codex update did not complete or could not be verified (rc=$rc)"
  note "continuing with the currently selected Codex; normal setup still enforces MIN_CODEX_VERSION"
  return "$rc"
}

make_remote_setup() {
  local f
  f=$(mktemp)
  cleanup_files+=("$f")
  cat >"$f" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
WORKDIR=$1
MIN_CODEX_VERSION=$2
CODEX_PROVIDER=${3:-deepseek}
AGENT_KIND=${4:-codex}
case "$AGENT_KIND" in codex|kimi-code) ;; *) echo "invalid agent kind: $AGENT_KIND" >&2; exit 39 ;; esac
case "$CODEX_PROVIDER" in openai|deepseek|kimi|minimax|none) ;; *) echo "invalid Codex provider: $CODEX_PROVIDER" >&2; exit 39 ;; esac

export PATH="$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.fly/bin:$PATH"
mkdir -p "$HOME/.local/bin" "$HOME/.config/sprite-codex" "$HOME/.codex" "$WORKDIR"

as_root() {
  if [[ $(id -u) -eq 0 ]]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else return 1
  fi
}

required_pairs=("git:git" "curl:curl" "python3:python3" "tar:tar")
if [[ $AGENT_KIND == codex ]]; then
  required_pairs+=("npm:npm" "node:nodejs")
fi
missing=()
for pair in "${required_pairs[@]}"; do
  cmd=${pair%%:*}; pkg=${pair#*:}
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]})); then
  command -v apt-get >/dev/null 2>&1 || {
    echo "missing required commands and no supported package manager is available: ${missing[*]}" >&2
    exit 40
  }
  echo "       installing missing base packages only: ${missing[*]}"
  as_root apt-get update -qq
  DEBIAN_FRONTEND=noninteractive as_root apt-get install -y -qq ca-certificates "${missing[@]}"
else
  echo "       base tools already installed; skipping package installation"
fi

required_commands=(git curl python3 tar)
[[ $AGENT_KIND == codex ]] && required_commands+=(npm node)
for cmd in "${required_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command on Sprite: $cmd" >&2; exit 41; }
done

version_ge() {
  python3 - "$1" "$2" <<'PYVER'
import re, sys

def parts(v):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", v)
    if not m:
        raise SystemExit(2)
    return tuple(map(int, m.groups()))

raise SystemExit(0 if parts(sys.argv[1]) >= parts(sys.argv[2]) else 1)
PYVER
}

if [[ $AGENT_KIND == codex ]]; then
# Sprites usually include Codex, and a Sprite can accumulate more than one
# installation path over time (system package, npm global, standalone updater,
# or ~/.local). Build one stable resolver and always launch Codex through it.
# This prevents an older ~/.local/bin/codex from shadowing a newer system
# binary, or vice versa, after an in-app update.
cat > "$HOME/.local/bin/sprite-codex-cli" <<'CODEX_RESOLVER'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$HOME/.fly/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# Sprite's preinstalled Codex commonly lives under its NVM-managed Node tree,
# e.g. /.sprite/languages/node/nvm/versions/node/v24.x/bin/codex. A deliberately
# minimal/fresh shell does not necessarily put that directory on PATH. Discover
# Node runtime directories from the filesystem so the resolver works even when
# shell startup files have not run.
while IFS= read -r d; do
  [[ -n $d ]] || continue
  case ":$PATH:" in
    *":$d:"*) ;;
    *) PATH="$d:$PATH" ;;
  esac
done < <(python3 - <<'PYNODE'
import glob, os, re

def key(path):
    m = re.search(r"/v?(\d+)\.(\d+)\.(\d+)/bin/node$", path)
    return tuple(map(int, m.groups())) if m else (0, 0, 0)

patterns = [
    "/.sprite/languages/node/nvm/versions/node/*/bin/node",
    os.path.expanduser("~/.nvm/versions/node/*/bin/node"),
    os.path.expanduser("~/.local/share/nvm/versions/node/*/bin/node"),
]
seen=set(); rows=[]
for pat in patterns:
    for node in glob.glob(pat):
        if os.path.isfile(node) and os.access(node, os.X_OK):
            d=os.path.dirname(node)
            if d not in seen:
                seen.add(d); rows.append((key(node), d))
for _, d in sorted(rows, reverse=True):
    print(d)
PYNODE
)
export PATH

candidate_lines() {
  python3 - <<'PYRES'
import glob, os, subprocess
seen=set(); paths=[]

def add(p):
    if not p: return
    p=os.path.expanduser(p)
    if not (os.path.isfile(p) and os.access(p, os.X_OK)): return
    try: rp=os.path.realpath(p)
    except Exception: rp=p
    if rp in seen: return
    seen.add(rp); paths.append(p)

# PATH order first, then persistent/user locations and Sprite/NVM locations.
for d in os.environ.get("PATH", "").split(os.pathsep):
    add(os.path.join(d, "codex"))
for p in (
    os.path.expanduser("~/.local/bin/codex"),
    "/usr/local/bin/codex",
    "/usr/bin/codex",
):
    add(p)
for pat in (
    "/.sprite/languages/node/nvm/versions/node/*/bin/codex",
    os.path.expanduser("~/.nvm/versions/node/*/bin/codex"),
    os.path.expanduser("~/.local/share/nvm/versions/node/*/bin/codex"),
):
    for p in glob.glob(pat):
        add(p)
try:
    pref=subprocess.check_output(["npm","prefix","-g"], text=True, stderr=subprocess.DEVNULL).strip()
    add(os.path.join(pref,"bin","codex"))
except Exception:
    pass
for p in paths:
    try:
        env=os.environ.copy()
        # NPM-installed Codex launchers generally use /usr/bin/env node. Ensure
        # the selected binary's own bin directory is first when probing it.
        env["PATH"] = os.path.dirname(p) + os.pathsep + env.get("PATH", "")
        out=subprocess.check_output([p,"--version"], text=True, stderr=subprocess.STDOUT, timeout=10, env=env).strip().replace("\n"," ")
    except Exception as e:
        out="ERROR:"+str(e)
    print(p+"\t"+out)
PYRES
}

choose_best() {
  candidate_lines | python3 -c '
import re,sys
rows=[]
for i,line in enumerate(sys.stdin):
    line=line.rstrip("\n")
    if "\t" not in line: continue
    path,out=line.split("\t",1)
    m=re.search(r"(\d+)\.(\d+)\.(\d+)",out)
    ver=tuple(map(int,m.groups())) if m else None
    rows.append((path,out,ver,i))
if not rows: raise SystemExit(1)
parsed=[r for r in rows if r[2] is not None]
if parsed:
    # Highest semantic version wins. For ties, preserve PATH/candidate order.
    best=max(parsed,key=lambda r:(r[2],-r[3]))
else:
    best=rows[0]
print(best[0])
'
}

case "${1:-}" in
  --sprite-codex-inventory)
    candidate_lines
    exit 0
    ;;
  --sprite-codex-resolve)
    choose_best
    exit $?
    ;;
esac

best=$(choose_best) || {
  echo "no usable Codex executable was found" >&2
  exit 127
}
# If the chosen launcher belongs to an NVM bin directory, its matching `node`
# must be visible to /usr/bin/env when Codex starts.
export PATH="$(dirname "$best"):$PATH"
exec "$best" "$@"
CODEX_RESOLVER
chmod 700 "$HOME/.local/bin/sprite-codex-cli"

codex_path_before=$("$HOME/.local/bin/sprite-codex-cli" --sprite-codex-resolve 2>/dev/null || true)
codex_version_output=$("$HOME/.local/bin/sprite-codex-cli" --version 2>/dev/null || true)
install_codex=0
if [[ -n $codex_path_before ]]; then
  if version_ge "$codex_version_output" "$MIN_CODEX_VERSION"; then
    echo "       Codex already installed and sufficient: $codex_version_output"
    echo "       selected executable: $codex_path_before"
  else
    rc=$?
    if [[ $rc == 1 ]]; then
      echo "       Codex is older than $MIN_CODEX_VERSION: ${codex_version_output:-unknown}; upgrading"
      install_codex=1
    else
      echo "       Codex exists but its version could not be parsed: ${codex_version_output:-unknown}; keeping it"
      echo "       selected executable: $codex_path_before"
    fi
  fi
else
  echo "       Codex is not installed; installing it"
  install_codex=1
fi

if [[ $install_codex == 1 ]]; then
  # Always install into the Sprite user's persistent home. Avoid a second
  # system-global npm installation that may be shadowed by ~/.local/bin.
  echo "       installing/updating Codex in persistent user prefix: $HOME/.local"
  npm install -g --prefix "$HOME/.local" @openai/codex@latest >/dev/null
  hash -r
  codex_version_output=$("$HOME/.local/bin/sprite-codex-cli" --version 2>/dev/null || true)
  version_ge "$codex_version_output" "$MIN_CODEX_VERSION" || {
    echo "Codex upgrade did not produce version $MIN_CODEX_VERSION or newer: ${codex_version_output:-unknown}" >&2
    "$HOME/.local/bin/sprite-codex-cli" --sprite-codex-inventory >&2 || true
    exit 42
  }
fi

codex_path_after=$("$HOME/.local/bin/sprite-codex-cli" --sprite-codex-resolve 2>/dev/null || true)
[[ -n $codex_path_after ]] || { echo "Codex installation failed" >&2; exit 42; }
codex_version_after=$("$HOME/.local/bin/sprite-codex-cli" --version 2>/dev/null || true)

# Verify from a deliberately minimal fresh shell as well. The resolver itself
# discovers Sprite/NVM Codex + Node paths from disk, so this tests persistence
# without assuming shell startup files populate PATH.
fresh_path=$(env -i HOME="$HOME" PATH="$HOME/.local/bin:$HOME/.fly/bin:/usr/local/bin:/usr/bin:/bin" bash --noprofile --norc -c '"$HOME/.local/bin/sprite-codex-cli" --sprite-codex-resolve' 2>/dev/null || true)
fresh_version=$(env -i HOME="$HOME" PATH="$HOME/.local/bin:$HOME/.fly/bin:/usr/local/bin:/usr/bin:/bin" bash --noprofile --norc -c '"$HOME/.local/bin/sprite-codex-cli" --version' 2>/dev/null || true)
if [[ -z $fresh_path || -z $fresh_version ]]; then
  echo "Codex was visible in the setup shell but the filesystem-based resolver failed in a minimal fresh shell" >&2
  echo "       setup selection: $codex_path_after | $codex_version_after" >&2
  "$HOME/.local/bin/sprite-codex-cli" --sprite-codex-inventory >&2 || true
  exit 42
fi
if [[ $fresh_path != "$codex_path_after" || $fresh_version != "$codex_version_after" ]]; then
  echo "warning: Codex resolution differs in a fresh shell" >&2
  echo "         setup: $codex_path_after | $codex_version_after" >&2
  echo "         fresh: $fresh_path | $fresh_version" >&2
fi

echo "       Codex executable inventory:"
"$HOME/.local/bin/sprite-codex-cli" --sprite-codex-inventory | sed 's/^/         /'
echo "       active Codex: $codex_path_after | $codex_version_after"
echo "       custom providers use native Responses; no npx/CodeProxy adapter is needed"
else
  kimi_install_marker="$HOME/.config/sprite-codex/kimi-code-official-installed"
  kimi_official_path="$HOME/.kimi-code/bin/kimi"

  kimi_install_diagnostics() {
    local candidate
    echo "Kimi Code installer completed, but its executable could not be used." >&2
    printf '       PATH=%s\n' "$PATH" >&2
    for candidate in "$HOME/.kimi-code/bin/kimi" "$HOME/.local/bin/kimi"; do
      if [[ -e $candidate || -L $candidate ]]; then
        printf '       candidate: ' >&2
        ls -ld "$candidate" >&2 || true
      else
        printf '       missing: %s\n' "$candidate" >&2
      fi
    done
    candidate=$(command -v kimi 2>/dev/null || true)
    printf '       command -v kimi: %s\n' "${candidate:-not found}" >&2
  }

  # The official installer writes ~/.kimi-code/bin into ~/.bashrc, but that
  # cannot change PATH in this already-running setup shell. Check its canonical
  # install location directly. This also resumes cleanly after the exact case
  # where installation succeeded but the old bootstrap rejected it.
  if [[ -x $kimi_official_path ]]; then
    echo "       official Kimi Code binary already present; skipping installation"
  else
    echo "       installing the official Kimi Code CLI"
    kimi_installer=$(mktemp)
    trap 'rm -f "$kimi_installer"' EXIT
    curl -fsSL https://code.kimi.com/kimi-code/install.sh -o "$kimi_installer"
    bash "$kimi_installer"
    rm -f "$kimi_installer"
    trap - EXIT
    hash -r
  fi

  if [[ ! -f $kimi_official_path || ! -x $kimi_official_path ]]; then
    kimi_install_diagnostics
    exit 45
  fi
  kimi_path=$kimi_official_path
  if [[ $kimi_path != "$HOME/.local/bin/kimi" ]]; then
    ln -sfn "$kimi_path" "$HOME/.local/bin/kimi"
  fi
  if ! kimi_version_output=$("$kimi_path" --version 2>&1); then
    echo "Kimi Code executable failed its version check: $kimi_path" >&2
    printf '%s\n' "$kimi_version_output" >&2
    kimi_install_diagnostics
    exit 45
  fi
  kimi_version=$(head -1 <<<"$kimi_version_output")
  [[ -n $kimi_version ]] || { echo "Kimi Code executable did not report a version" >&2; exit 45; }
  printf '%s\n' "$kimi_version" >"$kimi_install_marker"
  chmod 600 "$kimi_install_marker"
  cat > "$HOME/.local/bin/sprite-kimi-code" <<'KIMI_CODE_RESOLVER'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.fly/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
kimi_path="$HOME/.kimi-code/bin/kimi"
if [[ ! -f $kimi_path || ! -x $kimi_path ]]; then
  echo "Kimi Code executable is unavailable at $kimi_path; rerun the Sprite bootstrap" >&2
  exit 127
fi
exec "$kimi_path" "$@"
KIMI_CODE_RESOLVER
  chmod 700 "$HOME/.local/bin/sprite-kimi-code"
  echo "       active Kimi Code: $kimi_path | $kimi_version"
fi

if command -v fly >/dev/null 2>&1; then
  echo "       Fly CLI already installed; skipping"
elif command -v flyctl >/dev/null 2>&1; then
  echo "       flyctl already installed; adding a user-local 'fly' alias"
  ln -sf "$(command -v flyctl)" "$HOME/.local/bin/fly"
else
  echo "       Fly CLI is not installed; installing it"
  curl -fsSL https://fly.io/install.sh | sh >/dev/null
fi
command -v fly >/dev/null 2>&1 || { echo "Fly CLI installation failed" >&2; exit 43; }

# Persist only non-secret path configuration.
for rc in "$HOME/.profile" "$HOME/.bashrc"; do
  touch "$rc"
  python3 - "$rc" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p, errors="replace").read()
s=re.sub(r'(?ms)^# >>> sprite-codex-path >>>\n.*?^# <<< sprite-codex-path <<<\n?', '', s)
block='''# >>> sprite-codex-path >>>
export PATH="$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.fly/bin:$PATH"
# <<< sprite-codex-path <<<
'''
open(p,"w").write(s.rstrip()+"\n\n"+block)
PY
done

# Git reads the token from the current process environment.
cat > "$HOME/.local/bin/git-credential-sprite" <<'CRED'
#!/usr/bin/env bash
set -euo pipefail
protocol=""; host=""
while IFS='=' read -r key value; do
  case "$key" in protocol) protocol=$value;; host) host=$value;; esac
done
if [[ "$protocol" == https && "$host" == github.com && -n ${GITHUB_TOKEN:-} ]]; then
  printf 'username=x-access-token\npassword=%s\n' "$GITHUB_TOKEN"
fi
CRED
chmod 700 "$HOME/.local/bin/git-credential-sprite"
git config --global --replace-all credential.https://github.com.helper "$HOME/.local/bin/git-credential-sprite"
git config --global credential.useHttpPath true

# Safe capability probe for Codex and operators. It never prints raw tokens.
# It is useful precisely because Sprites gateway connections are unrelated to
# the process-scoped GitHub/Fly credentials used by this script.
cat > "$HOME/.local/bin/sprite-auth-check" <<'AUTHCHECK'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$HOME/.fly/bin:$PATH"

mode=${1:-all}
repo=${GITHUB_REPOSITORY:-${GH_REPO:-}}
app=${FLY_APP:-}

github_check() {
  local token_present=0 git_ok=0 gh_ok=na rc=0
  [[ -n ${GH_TOKEN:-${GITHUB_TOKEN:-}} ]] && token_present=1
  printf 'github_token_env=%s\n' "$([[ $token_present == 1 ]] && echo present || echo missing)"

  if [[ -d .git ]] && GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code origin HEAD >/dev/null 2>&1; then
    git_ok=1
  fi
  printf 'github_git_origin=%s\n' "$([[ $git_ok == 1 ]] && echo ok || echo failed)"

  if command -v gh >/dev/null 2>&1 && [[ -n $repo && $token_present == 1 ]]; then
    if GH_PROMPT_DISABLED=1 gh api "repos/$repo" --silent >/dev/null 2>&1; then
      gh_ok=ok
    else
      gh_ok=failed
    fi
  fi
  printf 'github_gh_api=%s\n' "$gh_ok"
  (( token_present == 1 && git_ok == 1 )) || rc=1
  [[ $gh_ok != failed ]] || rc=1
  return "$rc"
}

fly_check() {
  local token_present=0 fly_ok=0
  [[ -n ${FLY_API_TOKEN:-${FLY_ACCESS_TOKEN:-}} ]] && token_present=1
  printf 'fly_token_env=%s\n' "$([[ $token_present == 1 ]] && echo present || echo missing)"
  if command -v fly >/dev/null 2>&1 && [[ -n $app && $token_present == 1 ]] \
     && fly status --app "$app" >/dev/null 2>&1; then
    fly_ok=1
  fi
  printf 'fly_app_access=%s\n' "$([[ $fly_ok == 1 ]] && echo ok || echo failed)"
  (( token_present == 1 && fly_ok == 1 ))
}

case "$mode" in
  github) github_check ;;
  fly) fly_check ;;
  all) github_check; fly_check ;;
  *) echo "usage: sprite-auth-check [all|github|fly]" >&2; exit 2 ;;
esac
AUTHCHECK
chmod 700 "$HOME/.local/bin/sprite-auth-check"

if [[ $AGENT_KIND == codex ]]; then
  printf '       codex=%s\n' "$("$HOME/.local/bin/sprite-codex-cli" --version 2>/dev/null || echo unknown)"
else
  printf '       kimi_code=%s\n' "$("$HOME/.local/bin/sprite-kimi-code" --version 2>/dev/null | head -1 || echo unknown)"
fi
printf '       fly=%s\n' "$(fly version 2>/dev/null | head -1 || echo unknown)"
printf '       workspace=%s\n' "$WORKDIR"
REMOTE
  printf '%s' "$f"
}
make_github_bootstrap() {
  local f
  f=$(mktemp)
  cleanup_files+=("$f")
  cat >"$f" <<'GITHUB_REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

WORKDIR=${1:?workdir required}
GITHUB_REPOSITORY=${2:?OWNER/REPO required}
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

export PATH="$HOME/.local/bin:$PATH"
REPO_URL="https://github.com/${GITHUB_REPOSITORY}.git"
API_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}"
mkdir -p "$HOME/.local/bin" "$(dirname "$WORKDIR")"

# The helper returns credentials only for github.com and only from the current
# process environment. No PAT is stored in Git config or on disk.
cat > "$HOME/.local/bin/git-credential-sprite" <<'CRED'
#!/usr/bin/env bash
set -euo pipefail
protocol=""; host=""
while IFS='=' read -r key value; do
  case "$key" in protocol) protocol=$value;; host) host=$value;; esac
done
if [[ "$protocol" == https && "$host" == github.com && -n ${GITHUB_TOKEN:-} ]]; then
  printf 'username=x-access-token\npassword=%s\n' "$GITHUB_TOKEN"
fi
CRED
chmod 700 "$HOME/.local/bin/git-credential-sprite"
git config --global --replace-all credential.https://github.com.helper "$HOME/.local/bin/git-credential-sprite"
git config --global credential.useHttpPath true

TMP=$(mktemp -d)
cleanup_tmp(){ rm -rf "$TMP"; }
trap cleanup_tmp EXIT

USER_HTTP=$(curl -sS -o "$TMP/user.json" -w '%{http_code}' \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  https://api.github.com/user)
REPO_HTTP=$(curl -sS -o "$TMP/repo.json" -w '%{http_code}' \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  "$API_URL")
[[ $USER_HTTP == 200 && $REPO_HTTP == 200 ]] || {
  echo "GitHub API failed for $GITHUB_REPOSITORY (user_http=$USER_HTTP repo_http=$REPO_HTTP)" >&2
  python3 - "$TMP/user.json" "$TMP/repo.json" <<'PYERR' >&2
import json,sys
for path in sys.argv[1:]:
    try:
        d=json.load(open(path)); print(d.get("message",d))
    except Exception:
        pass
PYERR
  exit 51
}

IFS=$'\t' read -r GH_LOGIN GH_ID DEFAULT_BRANCH PUSH_PERMISSION < <(
  python3 - "$TMP/user.json" "$TMP/repo.json" <<'PYMETA'
import json,sys
u=json.load(open(sys.argv[1]))
r=json.load(open(sys.argv[2]))
perm=r.get("permissions") or {}
login=str(u.get("login") or "sprite-codex")
uid=str(u.get("id") or "")
branch=str(r.get("default_branch") or "main")
if perm:
    push="true" if bool(perm.get("push") or perm.get("admin") or perm.get("maintain")) else "false"
else:
    push="unknown"
print("\t".join((login,uid,branch,push)))
PYMETA
)

normalize_remote() {
  python3 - "$1" <<'PYNORM'
import re,sys
u=sys.argv[1].strip()
for p in (
    r'^(?:https?://|ssh://git@)github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?$',
    r'^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$',
):
    m=re.match(p,u,re.I)
    if m:
        print((m.group(1)+"/"+m.group(2)).lower())
        break
PYNORM
}

clone_with_overlay() {
  local stage item
  stage=$(mktemp -d "$TMP/clone.XXXXXX")
  echo "       cloning $GITHUB_REPOSITORY into the Sprite workspace"
  GIT_TERMINAL_PROMPT=0 git clone "$REPO_URL" "$stage/repo"
  mkdir -p "$stage/overlay"
  if [[ -d $WORKDIR ]]; then
    shopt -s dotglob nullglob
    for item in "$WORKDIR"/*; do
      [[ $(basename "$item") == .git ]] && continue
      cp -a "$item" "$stage/overlay/"
    done
    shopt -u dotglob nullglob
  fi
  rm -rf "$WORKDIR"
  mv "$stage/repo" "$WORKDIR"
  shopt -s dotglob nullglob
  for item in "$stage/overlay"/*; do cp -a "$item" "$WORKDIR/"; done
  shopt -u dotglob nullglob
}

TARGET_NORM=${GITHUB_REPOSITORY,,}
if git -C "$WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
  ORIGIN=$(git -C "$WORKDIR" remote get-url origin 2>/dev/null || true)
  HAS_HEAD=0
  git -C "$WORKDIR" rev-parse --verify HEAD >/dev/null 2>&1 && HAS_HEAD=1
  if [[ -z $ORIGIN && $HAS_HEAD == 0 ]]; then
    # Upgrade the empty placeholder repository created by older script versions.
    clone_with_overlay
  elif [[ -z $ORIGIN ]]; then
    git -C "$WORKDIR" remote add origin "$REPO_URL"
  else
    ORIGIN_NORM=$(normalize_remote "$ORIGIN")
    [[ $ORIGIN_NORM == "$TARGET_NORM" ]] || {
      echo "workspace origin points to $ORIGIN, not $GITHUB_REPOSITORY" >&2
      echo "refusing to replace a populated repository automatically" >&2
      exit 52
    }
    git -C "$WORKDIR" remote set-url origin "$REPO_URL"
  fi
else
  clone_with_overlay
fi

# Scope the helper to this repository as well as globally, so nested Git
# processes launched by Codex consistently use the environment-backed PAT.
git -C "$WORKDIR" config --local credential.https://github.com.helper "$HOME/.local/bin/git-credential-sprite"
git -C "$WORKDIR" config --local credential.useHttpPath true
git -C "$WORKDIR" remote set-url origin "$REPO_URL"

GIT_TERMINAL_PROMPT=0 git -C "$WORKDIR" ls-remote --exit-code origin HEAD >/dev/null
GIT_TERMINAL_PROMPT=0 git -C "$WORKDIR" fetch --prune origin

if ! git -C "$WORKDIR" rev-parse --verify HEAD >/dev/null 2>&1; then
  if git -C "$WORKDIR" show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH"; then
    git -C "$WORKDIR" checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
  else
    git -C "$WORKDIR" checkout --orphan "$DEFAULT_BRANCH"
  fi
fi

CURRENT_BRANCH=$(git -C "$WORKDIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
if [[ -n $CURRENT_BRANCH ]] && git -C "$WORKDIR" show-ref --verify --quiet "refs/remotes/origin/$CURRENT_BRANCH"; then
  git -C "$WORKDIR" branch --set-upstream-to="origin/$CURRENT_BRANCH" "$CURRENT_BRANCH" >/dev/null 2>&1 || true
fi

# Supply a usable commit identity without requiring a second prompt. Explicit
# local Git config already present in the repo is preserved.
if ! git -C "$WORKDIR" config --local user.name >/dev/null; then
  git -C "$WORKDIR" config --local user.name "$GH_LOGIN"
fi
if ! git -C "$WORKDIR" config --local user.email >/dev/null; then
  if [[ -n $GH_ID ]]; then
    git -C "$WORKDIR" config --local user.email "${GH_ID}+${GH_LOGIN}@users.noreply.github.com"
  else
    git -C "$WORKDIR" config --local user.email "${GH_LOGIN}@users.noreply.github.com"
  fi
fi

# Opening receive-pack with --dry-run verifies the PAT can authenticate for a
# push without changing the repository. Probe a temporary branch name rather
# than the active branch: a stale local branch may legitimately be behind the
# remote, and that status is handled by the explicit comparison before Codex.
PUSH_CHECK="permission-only (empty or detached repository)"
if [[ -n $CURRENT_BRANCH ]] && git -C "$WORKDIR" rev-parse --verify HEAD >/dev/null 2>&1; then
  PROBE_REF="refs/heads/sprite-codex-permission-probe-$$"
  PUSH_OUT=$(GIT_TERMINAL_PROMPT=0 git -C "$WORKDIR" push --dry-run --porcelain \
    origin "HEAD:$PROBE_REF" 2>&1) || {
      printf '%s\n' "$PUSH_OUT" >&2
      echo "GitHub fetch works, but push authentication could not be verified" >&2
      echo "ensure the PAT has Contents: read and write for $GITHUB_REPOSITORY" >&2
      exit 53
    }
  PUSH_CHECK="verified without changing the remote"
fi
if [[ $PUSH_PERMISSION == false ]]; then
  echo "GitHub reports that this token/user does not have push permission" >&2
  echo "grant Contents: read and write for $GITHUB_REPOSITORY" >&2
  exit 54
fi

printf 'repository=%s\nconfigured_at=%s\n' "$GITHUB_REPOSITORY" "$(date -u '+%FT%TZ')" \
  > "$WORKDIR/.git/sprite-codex-github-ready"
chmod 600 "$WORKDIR/.git/sprite-codex-github-ready"

printf '       github repository: %s\n' "$GITHUB_REPOSITORY"
printf '       origin: %s\n' "$(git -C "$WORKDIR" remote get-url origin)"
printf '       branch: %s\n' "${CURRENT_BRANCH:-detached}"
printf '       commit identity: %s <%s>\n' \
  "$(git -C "$WORKDIR" config user.name)" "$(git -C "$WORKDIR" config user.email)"
printf '       fetch: verified\n'
printf '       push dry-run: %s\n' "$PUSH_CHECK"
GITHUB_REMOTE
  printf '%s' "$f"
}

run_github_bootstrap() {
  local env_hex=$1 helper
  helper=$(make_github_bootstrap)
  cleanup_files+=("$helper")
  run_remote_file "$helper" "$env_hex" "$REMOTE_WORKDIR" -- \
    bash @SPRITE_PAYLOAD@ "$REMOTE_WORKDIR" "$GITHUB_REPOSITORY"
}

# Fetch and compare the active Sprite worktree with its same-named branch on
# origin. The final machine-readable line is hex-encoded JSON so normal Git
# output cannot break local parsing.
get_sprite_repo_status() {
  local env_hex=$1
  sx_env "$env_hex" -- bash -lc '
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$PATH"
repo=$1

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "The Sprite workspace is not a Git repository: $repo" >&2
  exit 71
fi
origin=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
[[ -n $origin ]] || { echo "The Sprite repository has no origin remote" >&2; exit 72; }

GIT_TERMINAL_PROMPT=0 git -C "$repo" fetch --prune origin
branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
head_exists=false
git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1 && head_exists=true
remote_exists=false
ahead=0
behind=0

if [[ -n $branch ]] && git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  remote_exists=true
  read -r behind ahead < <(git -C "$repo" rev-list --left-right --count "origin/$branch...HEAD")
elif [[ -n $branch && $head_exists == true ]]; then
  ahead=$(git -C "$repo" rev-list --count HEAD)
fi

status_porcelain=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
dirty=false
[[ -n $status_porcelain ]] && dirty=true

printf "       repository: %s\n" "$repo"
printf "       origin: %s\n" "$origin"
printf "       branch: %s\n" "${branch:-detached HEAD}"
printf "       remote branch: %s\n" "$([[ $remote_exists == true ]] && printf present || printf absent)"
printf "       local commits ahead: %s\n" "$ahead"
printf "       local commits behind: %s\n" "$behind"
printf "       uncommitted changes: %s\n" "$dirty"
if [[ -n $status_porcelain ]]; then
  echo "       local status:"
  printf "%s\n" "$status_porcelain" | sed "s/^/         /"
fi

python3 - "$repo" "$origin" "$branch" "$remote_exists" "$head_exists" "$ahead" "$behind" "$dirty" <<"PYREPOSTATUS"
import json,sys
keys=("repo","origin","branch","remote_exists","head_exists","ahead","behind","dirty")
vals=list(sys.argv[1:])
data=dict(zip(keys,vals))
for key in ("remote_exists","head_exists","dirty"):
    data[key]=data[key].lower()=="true"
for key in ("ahead","behind"):
    data[key]=int(data[key])
print("SPRITE_REPO_STATUS_HEX="+json.dumps(data,separators=(",",":")).encode().hex())
PYREPOSTATUS
' _ "$REMOTE_WORKDIR"
}

push_all_sprite_repo_changes() {
  local env_hex=$1 branch=$2
  sx_env "$env_hex" -- bash -lc '
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$PATH"
repo=$1
branch=$2
: "${REPO_PUSH_COMMIT_MESSAGE:?REPO_PUSH_COMMIT_MESSAGE is required}"

[[ -n $branch ]] || { echo "cannot push from detached HEAD" >&2; exit 73; }
GIT_TERMINAL_PROMPT=0 git -C "$repo" fetch --prune origin

# Recheck immediately before mutating anything. Never auto-push over remote
# commits and never force-push.
if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  read -r behind ahead < <(git -C "$repo" rev-list --left-right --count "origin/$branch...HEAD")
  if (( behind > 0 )); then
    echo "origin/$branch moved ahead by $behind commit(s); refusing automatic push" >&2
    exit 74
  fi
fi

if [[ -n $(git -C "$repo" status --porcelain=v1 --untracked-files=all) ]]; then
  git -C "$repo" add -A
  if ! git -C "$repo" diff --cached --quiet; then
    git -C "$repo" commit -m "$REPO_PUSH_COMMIT_MESSAGE"
  fi
fi

if ! git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "there is no commit to push" >&2
  exit 75
fi

GIT_TERMINAL_PROMPT=0 git -C "$repo" push --set-upstream origin "HEAD:refs/heads/$branch"
printf "       pushed HEAD to origin/%s\n" "$branch"
printf "       local HEAD: %s\n" "$(git -C "$repo" rev-parse --short HEAD)"
' _ "$REMOTE_WORKDIR" "$branch"
}

check_and_offer_repo_push() {
  local mode=${REPO_PUSH_MODE:-ask}
  local output marker parsed branch remote_exists ahead behind dirty head_exists
  local should_push=0 answer="" commit_message sync_env

  case "$mode" in
    ask|always|never) ;;
    *) die "REPO_PUSH_MODE must be ask, always, or never" ;;
  esac

  step "compare Sprite repository with GitHub"
  output=$(get_sprite_repo_status "$GITHUB_ENV" 2>&1) || {
    printf '%s\n' "$output"
    die "could not compare the Sprite repository with GitHub"
  }
  printf '%s\n' "$output" | grep -v '^SPRITE_REPO_STATUS_HEX=' || true
  marker=$(printf '%s\n' "$output" | sed -n 's/^SPRITE_REPO_STATUS_HEX=//p' | tail -1)
  [[ -n $marker ]] || die "repository comparison returned no status record"

  parsed=$(python3 - "$marker" <<'PYLOCALSTATUS'
import json,sys
try:
    d=json.loads(bytes.fromhex(sys.argv[1]).decode())
except Exception as exc:
    raise SystemExit(f"invalid repository status: {exc}")
print("\t".join((
    str(d.get("branch", "")),
    "1" if d.get("remote_exists") else "0",
    str(int(d.get("ahead", 0))),
    str(int(d.get("behind", 0))),
    "1" if d.get("dirty") else "0",
    "1" if d.get("head_exists") else "0",
)))
PYLOCALSTATUS
) || die "$parsed"
  IFS=$'\t' read -r branch remote_exists ahead behind dirty head_exists <<<"$parsed"

  if [[ -z $branch ]]; then
    warn "the Sprite repository is on a detached HEAD; automatic push is unavailable"
    return 0
  fi

  if (( behind > 0 && ahead > 0 )); then
    warn "local and origin/$branch have diverged (ahead $ahead, behind $behind)"
    note "resolve the divergence with merge or rebase before pushing; no force-push will be attempted"
    return 0
  fi
  if (( behind > 0 )); then
    warn "origin/$branch is ahead by $behind commit(s)"
    note "pull/rebase the remote changes before pushing local work"
    return 0
  fi

  if (( ahead == 0 && dirty == 0 )); then
    if (( remote_exists == 1 )); then
      ok "Sprite repository is synchronized with origin/$branch"
    else
      warn "origin/$branch does not exist and there are no local commits or changes to push"
    fi
    return 0
  fi

  if (( dirty == 1 )); then
    note "the Sprite has uncommitted tracked or untracked changes"
  fi
  if (( ahead > 0 )); then
    note "the Sprite branch is ahead of origin/$branch by $ahead commit(s)"
  elif (( remote_exists == 0 )); then
    note "origin/$branch does not exist; pushing will create it"
  fi

  case "$mode" in
    always) should_push=1 ;;
    never)
      note "REPO_PUSH_MODE=never; leaving local changes unpushed"
      return 0
      ;;
    ask)
      if [[ ! -t 0 ]]; then
        warn "no interactive input is available; leaving local changes unpushed"
        return 0
      fi
      printf '  Commit any uncommitted changes and push everything to origin/%s? [y/N]: ' "$branch"
      IFS= read -r answer || true
      [[ ${answer,,} == y || ${answer,,} == yes ]] && should_push=1
      ;;
  esac

  if (( should_push == 0 )); then
    note "local repository changes were not pushed"
    return 0
  fi

  commit_message=${REPO_PUSH_COMMIT_MESSAGE:-}
  if (( dirty == 1 )) && [[ -z $commit_message ]]; then
    commit_message="Sync Sprite workspace before Codex launch"
    if [[ -t 0 && $mode == ask ]]; then
      printf '  Commit message [%s]: ' "$commit_message"
      IFS= read -r answer || true
      [[ -n $answer ]] && commit_message=$answer
    fi
  fi
  [[ -n $commit_message ]] || commit_message="Push Sprite commits before Codex launch"

  REPO_PUSH_COMMIT_MESSAGE=$commit_message
  sync_env=$(make_exec_env GH_TOKEN GITHUB_TOKEN GITHUB_REPOSITORY REPO_PUSH_COMMIT_MESSAGE)
  push_all_sprite_repo_changes "$sync_env" "$branch" \
    || die "could not commit and push the Sprite repository changes"
  ok "all local repository changes were pushed to origin/$branch"
}

# Return success only when the active worktree has no uncommitted changes and
# its current branch is fully represented by origin. This is used by the startup
# rescue path before offering a safe exit for later Sprite destruction.
verify_sprite_repo_backed_up() {
  local output marker parsed branch remote_exists ahead behind dirty
  output=$(get_sprite_repo_status "$GITHUB_ENV" 2>&1) || {
    printf '%s\n' "$output"
    return 1
  }
  printf '%s\n' "$output" | grep -v '^SPRITE_REPO_STATUS_HEX=' || true
  marker=$(printf '%s\n' "$output" | sed -n 's/^SPRITE_REPO_STATUS_HEX=//p' | tail -1)
  [[ -n $marker ]] || return 1
  parsed=$(python3 - "$marker" <<'PYVERIFYBACKUP'
import json,sys
d=json.loads(bytes.fromhex(sys.argv[1]).decode())
print("\t".join((
    str(d.get("branch", "")),
    "1" if d.get("remote_exists") else "0",
    str(int(d.get("ahead", 0))),
    str(int(d.get("behind", 0))),
    "1" if d.get("dirty") else "0",
)))
PYVERIFYBACKUP
) || return 1
  IFS=$'\t' read -r branch remote_exists ahead behind dirty <<<"$parsed"
  [[ -n $branch && $remote_exists == 1 && $ahead == 0 && $behind == 0 && $dirty == 0 ]]
}

# Before attaching to a saved/hung Codex TTY, independently wake the Sprite and
# offer to back up the repository through a normal non-TTY sprite exec. This
# intentionally runs before session discovery/attach, so a stuck TTY cannot
# prevent recovery of the files. Authentication remains process-scoped.
startup_repo_rescue() {
  local mode=$STARTUP_REPO_PUSH_MODE answer="" old_repo_push_mode=${REPO_PUSH_MODE-}
  local had_repo_push_mode=0
  [[ ${REPO_PUSH_MODE+x} == x ]] && had_repo_push_mode=1

  [[ $mode != never ]] || {
    note "STARTUP_REPO_PUSH_MODE=never; skipping the pre-attach repository rescue"
    return 0
  }

  if [[ $mode == ask ]]; then
    if [[ ! -t 0 ]]; then
      warn "no interactive input is available; skipping the pre-attach repository rescue"
      return 0
    fi
    printf '\n  Back up the Sprite repository to GitHub before handling the Codex session? [Y/n]: '
    IFS= read -r answer || true
    case "${answer,,}" in
      n|no) note "startup repository rescue skipped"; return 0 ;;
    esac
  fi

  step "back up Sprite repository before Codex session handling"
  note "this uses a separate non-TTY sprite exec; it will not attach to the existing Codex session"
  if ! run_limited 60 sprite exec "${ORG[@]}" -s "$SPRITE_NAME" -- \
      bash -lc 'git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1' _ "$REMOTE_WORKDIR"; then
    warn "no usable Git repository was found at $REMOTE_WORKDIR"
    return 0
  fi

  GITHUB_REPOSITORY="${STATE_GITHUB_REPOSITORY:-${GITHUB_REPOSITORY:-$(detect_github_repo || true)}}"
  if [[ -z $GITHUB_REPOSITORY ]]; then
    printf '  GitHub repository (OWNER/REPO): '
    IFS= read -r GITHUB_REPOSITORY || true
  fi
  [[ $GITHUB_REPOSITORY =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] \
    || die "GitHub repository must be OWNER/REPO"
  note "use a fine-grained PAT limited to $GITHUB_REPOSITORY with Contents: read and write"
  prompt_validated_secret GITHUB_PAT "GitHub PAT for startup repository backup" github
  GH_TOKEN=$GITHUB_PAT
  GITHUB_TOKEN=$GITHUB_PAT
  GITHUB_ENV=$(make_exec_env GH_TOKEN GITHUB_TOKEN GITHUB_REPOSITORY)

  # Repair the process-scoped credential helper and verify the selected origin.
  # No token is written into the remote URL or a credential file.
  run_github_bootstrap "$GITHUB_ENV" || die "could not prepare GitHub access for repository rescue"

  if [[ $mode == always ]]; then
    REPO_PUSH_MODE=always
  else
    REPO_PUSH_MODE=ask
  fi
  check_and_offer_repo_push
  if (( had_repo_push_mode )); then
    REPO_PUSH_MODE=$old_repo_push_mode
  else
    unset REPO_PUSH_MODE
  fi

  if verify_sprite_repo_backed_up; then
    ok "Sprite repository is fully backed up on GitHub"
    if [[ $EXIT_AFTER_STARTUP_REPO_PUSH == 1 ]]; then
      note "EXIT_AFTER_STARTUP_REPO_PUSH=1; stopping before any Codex attach or launch"
      exit 0
    fi
    if [[ $mode == ask && -t 0 ]]; then
      printf '  Continue to the Codex session after this backup? [Y/n]: '
      IFS= read -r answer || true
      case "${answer,,}" in
        n|no)
          note "stopping after repository backup; the Sprite can now be destroyed separately"
          exit 0
          ;;
      esac
    fi
  else
    warn "the repository is not fully backed up; local changes, ahead commits, or remote divergence remain"
    if [[ $EXIT_AFTER_STARTUP_REPO_PUSH == 1 ]]; then
      die "refusing backup-only exit because the Sprite repository is not fully synchronized"
    fi
  fi
}

make_native_configurator() {
  NATIVE_CONFIGURATOR=$(mktemp)
  cleanup_files+=("$NATIVE_CONFIGURATOR")
  cat >"$NATIVE_CONFIGURATOR" <<'NATIVE_CONFIG_PY'
#!/usr/bin/env python3
"""Install a secret-free native Responses provider and modern Codex profile."""
import hashlib
import json
import os
import re
import shlex
import sys
import tempfile
import time
import urllib.parse
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        raise SystemExit("Native provider setup needs Python 3.11+ on the Sprite, or the tomli package.")


def atomic_write(path, text, mode=0o600):
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".sprite-native-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(text)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    workdir, provider, model, base, context, effort = sys.argv[1:7]
    keys = {"deepseek": "DEEPSEEK_API_KEY", "minimax": "MINIMAX_API_KEY", "kimi": "MOONSHOT_API_KEY"}
    if provider not in keys or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", model):
        raise SystemExit("Invalid provider or model")
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username is not None or parsed.password is not None or parsed.query or parsed.fragment:
        raise SystemExit("API base URL must be HTTPS, with no credentials, query, or fragment")
    if not workdir.startswith("/") or not context.isdigit() or not 4096 <= int(context) <= 2097152:
        raise SystemExit("Invalid workspace or context window")
    if effort not in ("low", "high", "max") or (provider == "minimax" and effort == "max"):
        raise SystemExit("Invalid reasoning effort")
    home = os.path.expanduser("~")
    codex_home = os.path.join(home, ".codex")
    profile_name = "sprite-" + provider
    provider_id = "sprite_native_" + provider
    profile_path = os.path.join(codex_home, profile_name + ".config.toml")
    catalog_path = os.path.join(codex_home, "model-catalogs", profile_name + ".json")
    launcher = os.path.join(home, ".local", "bin", "sprite-codex-" + provider)
    base_path = os.path.join(codex_home, "config.toml")
    q = lambda text: json.dumps(text, ensure_ascii=False)
    old = open(base_path, encoding="utf-8").read() if os.path.exists(base_path) else ""
    edited = old
    # Legacy v44 blocks each owned the same project trust table. Remove only
    # explicitly marked bootstrap blocks; never discard unrelated user config.
    markers = ("sprite-deepseek-v4-pro", "sprite-kimi-k3", "sprite-minimax-m3", "sprite-native-" + provider)
    for marker in markers:
        edited = re.sub(r"(?ms)^# >>> " + re.escape(marker) + r" >>>\n.*?^# <<< " + re.escape(marker) + r" <<<\n?", "", edited)
    try:
        previous = tomllib.loads(edited)
    except tomllib.TOMLDecodeError as exc:
        raise SystemExit("Existing unmanaged Codex TOML is invalid; no files changed: " + str(exc))
    if provider_id in previous.get("model_providers", {}):
        raise SystemExit("Unmanaged provider name collision: " + provider_id + "; no files changed")
    block = f'''# >>> sprite-native-{provider} >>>
[model_providers.{provider_id}]
name = {q(provider + ' / ' + model + ' (native Responses)')}
base_url = {q(base.rstrip('/'))}
env_key = {q(keys[provider])}
requires_openai_auth = false
wire_api = "responses"
request_max_retries = 2
stream_max_retries = 2
stream_idle_timeout_ms = 300000
# <<< sprite-native-{provider} <<<
'''
    # Parse before deciding whether a project table exists (quoted TOML keys and
    # inline tables must work as well). Preserve any explicit user trust policy.
    if workdir not in previous.get("projects", {}):
        project_hash = hashlib.sha256(workdir.encode()).hexdigest()[:16]
        block += f'''\n# >>> sprite-project-{project_hash} >>>
[projects.{q(workdir)}]
trust_level = "trusted"
# <<< sprite-project-{project_hash} <<<
'''
    combined = edited.rstrip() + "\n\n" + block
    instructions = (
        "You are Codex, a coding agent working in the current Sprite repository. "
        "Inspect files, make requested changes and verify your work. "
        "GitHub and Fly.io use process-scoped environment credentials and ordinary git, gh and fly commands, "
        "not Sprites gateway connections. Never print, echo, log or dump credentials. "
        "Verify GitHub using $HOME/.local/bin/sprite-auth-check github, git ls-remote or gh api. "
        "Verify Fly using $HOME/.local/bin/sprite-auth-check fly or fly status. "
        "Provider API keys exposed to tools are optional experiment credentials for authenticated API calls only."
    )
    if provider == "kimi":
        instructions += " Use the native web_search tool for fresh information; no Formula or local proxy helper is required."
    entry = {
        "slug": model, "display_name": model,
        "description": provider + " through the native Responses API",
        "default_reasoning_level": effort,
        "supported_reasoning_levels": ([{"effort": "none", "description": "Thinking off"}, {"effort": "high", "description": "Adaptive thinking"}]
                                       if provider == "minimax" else [{"effort": level, "description": level.capitalize() + " reasoning"} for level in ("low", "high", "max")]),
        "shell_type": "shell_command", "visibility": "list", "supported_in_api": True,
        "priority": 0, "base_instructions": instructions,
        # Codex uses this capability flag to send reasoning.effort at all.
        "supports_reasoning_summaries": True, "default_reasoning_summary": "none",
        "support_verbosity": False, "prefer_websockets": False,
        "truncation_policy": {"mode": "bytes", "limit": 10000},
        "supports_parallel_tool_calls": True, "experimental_supported_tools": [],
        "input_modalities": ["text", "image"], "context_window": int(context),
        "max_context_window": int(context), "effective_context_window_percent": 90,
    }
    if provider != "minimax":
        entry["apply_patch_tool_type"] = "freeform"
    # The optional legacy Pro model is text-only. Unknown overrides retain the
    # provider defaults; operators must also override context when appropriate.
    if provider == "deepseek" and model == "deepseek-v4-pro":
        entry["input_modalities"] = ["text"]
    profile = f'''# Managed by sprite-codex v45. No API key values are stored here.
model = {q(model)}
model_provider = {q(provider_id)}
model_catalog_json = {q(catalog_path)}
model_reasoning_effort = {q(effort)}
model_reasoning_summary = "none"
model_context_window = {context}
web_search = {q('live' if provider == 'kimi' else 'disabled')}
approval_policy = "never"
sandbox_mode = "danger-full-access"

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true
exclude = ["DEEPSEEK_API_KEY", "MOONSHOT_API_KEY", "KIMI_API_KEY", "MINIMAX_API_KEY", "OPENAI_API_KEY"]
'''
    # Check generated TOML before changing any files.
    tomllib.loads(combined)
    tomllib.loads(profile)
    launcher_text = '''#!/usr/bin/env bash
set -Eeuo pipefail
set +x
export PATH="$HOME/.local/bin:$HOME/.fly/bin:$PATH"
: "${KEY_REQUIRED:?KEY_REQUIRED is required}"
shell_excludes='["OPENAI_API_KEY","KIMI_API_KEY"'
for spec in 'CODEX_DEEPSEEK_ACCESS:DEEPSEEK_API_KEY' 'CODEX_MINIMAX_ACCESS:MINIMAX_API_KEY' 'CODEX_MOONSHOT_ACCESS:MOONSHOT_API_KEY'; do
  IFS=: read -r access key <<<"$spec"
  if [[ ${!access:-0} == 1 ]]; then
    [[ -n ${!key:-} ]] || { printf '%s=1 requires %s\\n' "$access" "$key" >&2; exit 2; }
  else
    shell_excludes+=',"'"$key"'"'
  fi
done
shell_excludes+=']'
cd -- WORKDIR_VALUE
exec "$HOME/.local/bin/sprite-codex-cli" \\
  --profile PROFILE_VALUE \\
  -c MODEL_OVERRIDE -c PROVIDER_OVERRIDE \\
  -c shell_environment_policy.inherit=all \\
  -c shell_environment_policy.ignore_default_excludes=true \\
  -c "shell_environment_policy.exclude=$shell_excludes" \\
  -c INSTRUCTION_VALUE \\
  --dangerously-bypass-approvals-and-sandbox "$@"
'''
    replacements = {"KEY_REQUIRED": keys[provider], "WORKDIR_VALUE": shlex.quote(workdir),
                    "PROFILE_VALUE": shlex.quote(profile_name), "MODEL_OVERRIDE": shlex.quote("model=" + q(model)),
                    "PROVIDER_OVERRIDE": shlex.quote("model_provider=" + q(provider_id)),
                    "INSTRUCTION_VALUE": shlex.quote("developer_instructions=" + q(instructions))}
    for token, value in replacements.items():
        launcher_text = launcher_text.replace(token, value)
    if old and old != combined:
        backup = os.path.join(codex_home, "backup-sprite-codex", "config.toml.%s.%s.bak" % (time.time_ns(), os.getpid()))
        atomic_write(backup, old)
    atomic_write(catalog_path, json.dumps({"models": [entry]}, indent=2) + "\n")
    atomic_write(profile_path, profile)
    atomic_write(base_path, combined)
    atomic_write(launcher, launcher_text, 0o700)
    for label, value in (("model", model), ("provider", provider_id), ("base_url", base), ("profile", profile_path), ("catalog", catalog_path), ("launcher", launcher)):
        print("       %s=%s" % (label, value))
    print("       transport=native Responses; no proxy or key-bearing config file")
    print("       mode=yolo (existing approvals/sandbox behavior retained)")


if __name__ == "__main__":
    main()
NATIVE_CONFIG_PY
}

make_openai_launcher() {
  local f
  f=$(mktemp)
  cleanup_files+=("$f")
  cat >"$f" <<'OPENAI_LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail
WORKDIR=${1:?workdir required}
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/sprite-codex-openai" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="\$HOME/.local/bin:\$HOME/.fly/bin:\$PATH"
shell_excludes='["OPENAI_API_KEY","KIMI_API_KEY"'
if [[ \${CODEX_DEEPSEEK_ACCESS:-0} == 1 ]]; then
  : "\${DEEPSEEK_API_KEY:?CODEX_DEEPSEEK_ACCESS=1 requires DEEPSEEK_API_KEY}"
else
  shell_excludes+=',"DEEPSEEK_API_KEY"'
fi
if [[ \${CODEX_MOONSHOT_ACCESS:-0} == 1 ]]; then
  : "\${MOONSHOT_API_KEY:?CODEX_MOONSHOT_ACCESS=1 requires MOONSHOT_API_KEY}"
else
  shell_excludes+=',"MOONSHOT_API_KEY"'
fi
if [[ \${CODEX_MINIMAX_ACCESS:-0} == 1 ]]; then
  : "\${MINIMAX_API_KEY:?CODEX_MINIMAX_ACCESS=1 requires MINIMAX_API_KEY}"
else
  shell_excludes+=',"MINIMAX_API_KEY"'
fi
shell_excludes+=']'
cd $(printf '%q' "$WORKDIR")
exec "\$HOME/.local/bin/sprite-codex-cli" \
  -c model_provider=openai \
  -c shell_environment_policy.inherit=all \
  -c shell_environment_policy.ignore_default_excludes=true \
  -c "shell_environment_policy.exclude=\$shell_excludes" \
  -c 'developer_instructions="This Sprite intentionally authenticates GitHub and Fly.io through process-scoped environment credentials and the normal git, gh, and fly CLIs. Sprites gateway connections are not required for these services and /v1/gateway/list must not be used to decide whether GitHub or Fly access exists. Never print, echo, cat, or otherwise reveal token values. Verify GitHub capability with $HOME/.local/bin/sprite-auth-check github, git ls-remote, or gh api. Verify Fly capability with $HOME/.local/bin/sprite-auth-check fly or fly status. GH_TOKEN, GITHUB_TOKEN, FLY_API_TOKEN, and FLY_ACCESS_TOKEN are secrets intended for command authentication only. If DEEPSEEK_API_KEY, MOONSHOT_API_KEY, or MINIMAX_API_KEY is present in a tool environment, it is an experiment credential intended only for authenticated API calls; never print, echo, log, dump, or otherwise reveal it."' \
  --dangerously-bypass-approvals-and-sandbox "\$@"
EOF
chmod 700 "$HOME/.local/bin/sprite-codex-openai"
echo "       launcher=$HOME/.local/bin/sprite-codex-openai"
echo "       provider=built-in OpenAI Codex (no custom provider/profile)"
OPENAI_LAUNCHER
  printf '%s' "$f"
}

openai_login_status() {
  local out rc
  out=$(run_limited 20 sprite exec "${ORG[@]}" -s "$SPRITE_NAME" -- bash -lc '
export PATH="$HOME/.local/bin:$PATH"
"$HOME/.local/bin/sprite-codex-cli" login status 2>&1
' 2>&1) && rc=0 || rc=$?
  printf '%s' "$out"
  return "$rc"
}

run_openai_device_login() {
  # $1=0 keeps the existing credential until the new login replaces it.
  # $1=1 explicitly clears the Sprite's stored Codex credential first, which is
  # useful when switching away from an account whose Codex quota is exhausted.
  local clear_first=${1:-0} out rc

  if [[ ! -t 0 || ! -t 1 ]]; then
    warn "no interactive terminal is available for OpenAI device-code login"
    return 2
  fi

  if [[ $clear_first == 1 ]]; then
    warn "clearing the stored Codex credential on Sprite '$SPRITE_NAME' before login"
    if ! sprite exec "${ORG[@]}" -s "$SPRITE_NAME" --no-port-forward -- \
      bash -lc 'export PATH="$HOME/.local/bin:$PATH"; "$HOME/.local/bin/sprite-codex-cli" logout'; then
      warn "Codex logout failed; existing credentials were not deliberately removed"
      return 1
    fi
  fi

  note "starting: codex login --device-auth"
  if ! sprite exec "${ORG[@]}" -s "$SPRITE_NAME" --tty --no-port-forward -- \
    bash -lc 'export PATH="$HOME/.local/bin:$PATH"; exec "$HOME/.local/bin/sprite-codex-cli" login --device-auth'; then
    warn "OpenAI Codex device-code login did not complete successfully"
    return 1
  fi

  out=$(openai_login_status) && rc=0 || rc=$?
  [[ -z $out ]] || printf '%s\n' "$out" | sed 's/^/       /'
  if [[ $rc == 0 && $out == *"Logged in"* ]]; then
    ok "OpenAI Codex device-code login completed"
    return 0
  fi

  warn "device-code flow returned, but Codex does not yet report a logged-in session"
  return 1
}

check_openai_auth() {
  local out rc ans=""
  out=$(openai_login_status) && rc=0 || rc=$?
  if [[ $rc == 0 && $out == *"Logged in"* ]]; then
    printf '%s\n' "$out" | sed 's/^/       /'
    ok "normal OpenAI Codex authentication is already available on the Sprite"
    return 0
  fi

  if [[ $out == *"Not logged in"* || $out == *"not logged in"* ]]; then
    warn "Codex is not logged in to OpenAI on this Sprite"
    if [[ -t 0 && -t 1 ]]; then
      printf '  Start normal Codex device-code login now? [Y/n]: '
      IFS= read -r ans || true
      case "${ans,,}" in
        n|no)
          note "skipping login; the OpenAI Codex preflight may fail until you authenticate"
          return 0
          ;;
      esac
      # Do not make an unsuccessful login fatal here. The OpenAI preflight below
      # has a second, repeatable recovery menu and will show the actual failure.
      run_openai_device_login 0 || warn "continuing to OpenAI preflight so authentication recovery can be retried there"
      return 0
    fi
    warn "no interactive terminal is available for device-code login"
    return 0
  fi

  warn "could not determine Codex login status; normal Codex will handle authentication when launched"
  [[ -z $out ]] || printf '%s\n' "$out" | sed 's/^/       /'
}

openai_preflight_recovery() {
  local failure_text=${1:-} choice=""

  [[ -t 0 && -t 1 ]] || return 1

  if grep -Eqi "you('ve| have) hit your usage limit|usage limit|purchase more credits|try again at" <<<"$failure_text"; then
    warn "the currently authenticated OpenAI/ChatGPT account appears to have hit its Codex usage limit"
    note "you can authenticate another account and retry without restarting this bootstrap"
  elif grep -Eqi "not logged in|login required|authentication|unauthori[sz]ed|access token|refresh token|credentials" <<<"$failure_text"; then
    warn "the OpenAI preflight appears to have failed for an authentication-related reason"
  else
    warn "the normal OpenAI Codex preflight failed before its success marker was produced"
    note "you can still redo device-code login in case the active account/session is the cause"
  fi

  while true; do
    printf '\n  OpenAI recovery:\n'
    printf '    1) Run device-code login again, then retry preflight [default]\n'
    printf '    2) Clear stored Codex login on this Sprite, device-login again, then retry\n'
    printf '    3) Retry preflight without changing login\n'
    printf '    4) Abort\n'
    printf '  Select [1-4]: '
    IFS= read -r choice || true
    case "${choice,,}" in
      ''|1|l|login|reauth|relogin)
        if run_openai_device_login 0; then return 0; fi
        warn "device-code login failed; choose another recovery action"
        ;;
      2|s|switch|logout)
        if run_openai_device_login 1; then return 0; fi
        warn "credential reset/device login failed; choose another recovery action"
        ;;
      3|r|retry)
        note "retrying normal OpenAI Codex preflight with the current credential"
        return 0
        ;;
      4|a|abort|q|quit|n|no)
        return 1
        ;;
      *) warn "invalid selection" ;;
    esac
  done
}

make_session_runner() {
  local f
  f=$(mktemp)
  cleanup_files+=("$f")
  cat >"$f" <<'RUNNER'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

RUN_SECONDS=${1:?run seconds required}
TASK_NAME=${2:?task name required}
SESSION_TAG=${3:?session tag required}
WORKDIR=${4:?workdir required}
START_MODE=${5:-new}
AGENT_KIND=${6:-codex}
AGENT_PROVIDER=${7:-deepseek}
KIMI_CODE_APPROVAL_MODE=${8:-normal}

[[ $RUN_SECONDS =~ ^[0-9]+$ ]] && ((RUN_SECONDS > 0)) || { echo "invalid run duration: $RUN_SECONDS" >&2; exit 80; }
[[ $TASK_NAME =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid task name: $TASK_NAME" >&2; exit 81; }
[[ $SESSION_TAG =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid session tag: $SESSION_TAG" >&2; exit 85; }
case "$AGENT_KIND" in codex|kimi-code) ;; *) echo "invalid agent kind: $AGENT_KIND" >&2; exit 84 ;; esac
if [[ $AGENT_KIND == codex ]]; then
  case "$START_MODE" in new|resume|fork) ;; *) echo "invalid Codex start mode: $START_MODE" >&2; exit 83 ;; esac
  case "$AGENT_PROVIDER" in openai|deepseek|kimi|minimax) ;; *) echo "invalid Codex provider: $AGENT_PROVIDER" >&2; exit 84 ;; esac
else
  case "$START_MODE" in new|resume) ;; *) echo "invalid Kimi Code start mode: $START_MODE" >&2; exit 83 ;; esac
  [[ $AGENT_PROVIDER == kimi-code ]] || { echo "invalid Kimi Code provider label: $AGENT_PROVIDER" >&2; exit 84; }
fi
case "$KIMI_CODE_APPROVAL_MODE" in normal|yolo|auto) ;; *) echo "invalid Kimi Code approval mode: $KIMI_CODE_APPROVAL_MODE" >&2; exit 84 ;; esac

api() {
  curl -sS --max-time 8 --unix-socket /.sprite/api.sock -H 'Content-Type: application/json' "$@"
}

RUNNER_PID=$$
DEADLINE=$(( $(date +%s) + RUN_SECONDS ))
HB_PID=""
STATE_DIR="$HOME/.local/state/sprite-codex"
HOLD_STATE_FILE="$STATE_DIR/hold-state-${SESSION_TAG}"
HOLD_DEADLINE_FILE="$STATE_DIR/hold-deadline-${SESSION_TAG}"
HOLD_RELEASED_MARKER="$STATE_DIR/hold-released-${SESSION_TAG}.marker"
HOLD_ENDED_FILE="$STATE_DIR/hold-ended-${SESSION_TAG}.marker"
RUNNER_PID_FILE="$STATE_DIR/runner-pid-${SESSION_TAG}"
PROVIDER_FILE="$STATE_DIR/provider-${SESSION_TAG}"
WORKDIR_FILE="$STATE_DIR/workdir-${SESSION_TAG}"
mkdir -p "$STATE_DIR"
printf 'active\n' >"$HOLD_STATE_FILE"
printf '%s\n' "$DEADLINE" >"$HOLD_DEADLINE_FILE"
printf '%s\n' "$RUNNER_PID" >"$RUNNER_PID_FILE"
printf '%s\n' "$AGENT_PROVIDER" >"$PROVIDER_FILE"
printf '%s\n' "$WORKDIR" >"$WORKDIR_FILE"
rm -f "$HOLD_RELEASED_MARKER" "$HOLD_ENDED_FILE"

# Sprite TTY sessions are detachable; ignore a hangup so client loss cannot
# become a reason to terminate the remote runner/Codex process tree.
trap '' HUP

cleanup_task() {
  local ended_at
  if [[ -n $HB_PID ]]; then kill "$HB_PID" 2>/dev/null || true; wait "$HB_PID" 2>/dev/null || true; fi
  api -X DELETE "http://sprite/v1/tasks/$TASK_NAME" >/dev/null 2>&1 || true
  if [[ ! -f $HOLD_RELEASED_MARKER ]]; then
    ended_at=$(date +%s)
    printf 'ended\n' >"$HOLD_STATE_FILE" 2>/dev/null || true
    printf '%s\n' "$ended_at" >"$HOLD_ENDED_FILE" 2>/dev/null || true
  fi
}
trap cleanup_task EXIT INT TERM

heartbeat() {
  trap '' HUP
  trap 'api -X DELETE "http://sprite/v1/tasks/'"$TASK_NAME"'" >/dev/null 2>&1 || true; exit 0' EXIT INT TERM
  local now failures=0
  while kill -0 "$RUNNER_PID" 2>/dev/null; do
    now=$(date +%s)
    if (( now >= DEADLINE )); then
      printf 'released\n' >"$HOLD_STATE_FILE" 2>/dev/null || true
      printf '%s\n' "$now" >"$HOLD_RELEASED_MARKER" 2>/dev/null || true
      echo >&2
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
      echo "WARNING: TASKS API KEEP-AWAKE HOLD HAS REACHED ITS HARD CAP" >&2
      echo "Task '$TASK_NAME' is being released while $AGENT_KIND remains alive." >&2
      echo "The native Sprite TTY remains a running session/activity while it is live." >&2
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
      break
    fi
    if api -X PUT "http://sprite/v1/tasks/$TASK_NAME" -d '{"expire":"5m"}' >/dev/null; then
      (( failures > 0 )) && echo "       Sprite task heartbeat recovered after $failures failed refresh(es)" >&2
      failures=0
    else
      failures=$((failures+1))
      echo "warning: failed to refresh Sprite task $TASK_NAME (consecutive failures=$failures); retrying in about 60 seconds" >&2
    fi
    for _ in $(seq 1 12); do
      kill -0 "$RUNNER_PID" 2>/dev/null || break 2
      [[ $(date +%s) -lt $DEADLINE ]] || break
      sleep 5 & wait $!
    done
  done
}

REGISTERED=0
for attempt in 1 2 3 4 5; do
  if api -X PUT "http://sprite/v1/tasks/$TASK_NAME" -d '{"expire":"5m"}' >/dev/null; then REGISTERED=1; break; fi
  sleep 2
done
[[ $REGISTERED == 1 ]] || { echo "could not register the Sprite keep-awake task after five attempts" >&2; exit 82; }
TASK_JSON=$(api "http://sprite/v1/tasks/$TASK_NAME" 2>/dev/null || true)
[[ -n $TASK_JSON ]] && echo "       task hold verified: $TASK_NAME" || echo "warning: task hold could not be verified; continuing without a confirmed Tasks API hold" >&2
heartbeat &
HB_PID=$!

echo "       native Sprite TTY tag: $SESSION_TAG"
echo "       workspace: $WORKDIR"
echo "       Tasks heartbeat deadline (UTC): $(date -u -d "@$DEADLINE" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -r "$DEADLINE" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "$DEADLINE")"
echo "       Tasks heartbeat deadline (Sprite local): $(date -d "@$DEADLINE" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$DEADLINE" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$DEADLINE")"
echo "       agent: $AGENT_KIND"
echo "       detach without stopping the agent: Ctrl+\\"
echo "       reattach later with: sprite sessions attach <session-id>"
echo

cd "$WORKDIR"
CODEX_PROVIDER="$AGENT_PROVIDER"
case "$CODEX_PROVIDER" in
  openai) CODEX_LAUNCHER="$HOME/.local/bin/sprite-codex-openai" ;;
  deepseek) CODEX_LAUNCHER="$HOME/.local/bin/sprite-codex-deepseek" ;;
  kimi) CODEX_LAUNCHER="$HOME/.local/bin/sprite-codex-kimi" ;;
  minimax) CODEX_LAUNCHER="$HOME/.local/bin/sprite-codex-minimax" ;;
esac
if [[ $AGENT_KIND == codex ]]; then
  echo "       Codex provider: $CODEX_PROVIDER"
else
  echo "       Kimi Code approval mode: $KIMI_CODE_APPROVAL_MODE"
fi

case "$CODEX_PROVIDER" in
  deepseek) [[ $AGENT_KIND != codex || -n ${DEEPSEEK_API_KEY:-} ]] || { echo "DEEPSEEK_API_KEY is missing in the managed runner" >&2; exit 89; } ;;
  kimi) [[ $AGENT_KIND != codex || -n ${MOONSHOT_API_KEY:-} ]] || { echo "MOONSHOT_API_KEY is missing in the managed runner" >&2; exit 90; } ;;
  minimax) [[ $AGENT_KIND != codex || -n ${MINIMAX_API_KEY:-} ]] || { echo "MINIMAX_API_KEY is missing in the managed runner" >&2; exit 91; } ;;
esac
if [[ $AGENT_KIND == codex ]]; then
  _access_rc=92
  for _spec in \
    "CODEX_MOONSHOT_ACCESS:MOONSHOT_API_KEY:Moonshot" \
    "CODEX_MINIMAX_ACCESS:MINIMAX_API_KEY:MiniMax" \
    "CODEX_DEEPSEEK_ACCESS:DEEPSEEK_API_KEY:DeepSeek"; do
    IFS=: read -r _access_var _key_var _label <<<"$_spec"
    case "${!_access_var:-0}" in
      1)
        [[ -n ${!_key_var:-} ]] || { echo "$_access_var=1 but $_key_var is missing in the managed runner" >&2; exit "$_access_rc"; }
        echo "       $_label experiment credential: injected into Codex shell/tool environment"
        ;;
      0) echo "       $_label experiment credential: not exposed to Codex shell/tools" ;;
      *) echo "invalid $_access_var in managed runner: ${!_access_var:-unset}" >&2; exit "$_access_rc" ;;
    esac
    _access_rc=$((_access_rc + 1))
  done
fi

# Verify the exact long-running runner environment without printing credential
# values. These checks catch any future regression between the outer bootstrap
# and the actual native TTY process before Codex starts.
for name in GH_TOKEN GITHUB_TOKEN FLY_API_TOKEN FLY_ACCESS_TOKEN; do
  if [[ -n ${!name:-} ]]; then
    echo "       credential env $name: present"
  else
    echo "credential env $name is missing in the managed agent runner" >&2
    exit 86
  fi
done
if "$HOME/.local/bin/sprite-auth-check" github | sed 's/^/       auth-check: /'; then
  :
else
  echo "GitHub capability check failed inside the managed runner" >&2
  exit 87
fi
if "$HOME/.local/bin/sprite-auth-check" fly | sed 's/^/       auth-check: /'; then
  :
else
  echo "Fly capability check failed inside the managed runner" >&2
  exit 88
fi

if [[ $AGENT_KIND == kimi-code ]]; then
  kimi_args=()
  case "$KIMI_CODE_APPROVAL_MODE" in
    yolo) kimi_args+=(--yolo) ;;
    auto) kimi_args+=(--auto) ;;
  esac
  if [[ $START_MODE == resume ]]; then
    kimi_args+=(--continue)
    echo "       continuing the most recent Kimi Code session"
  else
    echo "       opening a new Kimi Code session in the shared repository workspace"
  fi
  echo "       Kimi Code authentication is managed by the official CLI; use /login if requested"
  set +e
  "$HOME/.local/bin/sprite-kimi-code" "${kimi_args[@]}"
  kimi_code_rc=$?
  set -e
  exit "$kimi_code_rc"
fi

# Keep this runner alive around Codex so an in-app update can replace the
# executable and then resume the same persisted conversation.
CODEX_RESOLVER="$HOME/.local/bin/sprite-codex-cli"

codex_path() {
  "$CODEX_RESOLVER" --sprite-codex-resolve 2>/dev/null || true
}
codex_version() {
  "$CODEX_RESOLVER" --version 2>/dev/null || true
}
version_cmp() {
  python3 - "$1" "$2" <<'PYVC'
import re,sys

def v(s):
    m=re.search(r"(\d+)\.(\d+)\.(\d+)",s or "")
    return tuple(map(int,m.groups())) if m else None

a,b=v(sys.argv[1]),v(sys.argv[2])
if a is None or b is None:
    print("unknown")
elif a>b:
    print("gt")
elif a<b:
    print("lt")
else:
    print("eq")
PYVC
}

launch_mode=$START_MODE
update_restarts=0

run_codex_mode() {
  local mode=$1
  case "$mode" in
    resume)
      echo "       resuming the most recent Codex conversation: codex resume --last"
      "$CODEX_LAUNCHER" resume --last
      ;;
    fork)
      echo "       forking the most recent Codex conversation: codex fork --last"
      echo "       the source history remains intact; Codex will allocate a new writable thread ID"
      "$CODEX_LAUNCHER" fork --last
      ;;
    new)
      echo "       opening a new Codex conversation in the existing repository workspace"
      echo "       repository files and Git state are preserved; previous chat history is not loaded"
      "$CODEX_LAUNCHER"
      ;;
  esac
}

while :; do
  before_path=$(codex_path)
  before_version=$(codex_version)
  echo "       Codex executable before launch: ${before_path:-unknown} | ${before_version:-unknown}"

  if run_codex_mode "$launch_mode"; then
    codex_rc=0
  else
    codex_rc=$?
  fi

  if (( codex_rc != 0 )) && [[ $launch_mode == resume ]]; then
    echo >&2
    echo "warning: Codex resume exited with rc=$codex_rc" >&2
    if codex_processes=$(pgrep -af '([c]odex|[a]pp-server|[c]odeproxy)' 2>/dev/null); then
      echo "warning: Codex-like processes are still present; they will not be terminated automatically:" >&2
      printf '%s\n' "$codex_processes" | sed 's/^/         /' >&2
    else
      echo "warning: no live Codex, app-server, or codeproxy process was found" >&2
      echo "         if Codex reported an active writer, its ownership state is stale" >&2
    fi
    echo "         the saved transcript and workspace have not been changed" >&2
    if [[ -t 0 && -t 1 ]]; then
      printf '  Fork the most recent conversation into a new writable thread now? [Y/n]: '
      IFS= read -r fork_after_resume || true
    else
      fork_after_resume=n
    fi
    case "${fork_after_resume,,}" in
      ''|y|yes)
        launch_mode=fork
        if run_codex_mode "$launch_mode"; then
          codex_rc=0
        else
          codex_rc=$?
        fi
        ;;
      *)
        echo "       resume recovery cancelled; rerun and choose the Codex fork option to preserve the history under a new thread ID"
        ;;
    esac
  fi

  # Re-resolve from scratch after Codex exits. An updater may have installed a
  # standalone ~/.local/bin/codex or changed an npm-managed executable.
  hash -r 2>/dev/null || true
  sleep 1
  after_path=$(codex_path)
  after_version=$(codex_version)
  cmp=$(version_cmp "$after_version" "$before_version")

  if [[ $cmp == gt || ( -n $after_path && -n $before_path && $after_path != "$before_path" && $cmp != lt ) ]]; then
    echo
    echo "       Codex update detected and verified"
    echo "         before: ${before_path:-unknown} | ${before_version:-unknown}"
    echo "         after:  ${after_path:-unknown} | ${after_version:-unknown}"

    fresh_path=$(env -i HOME="$HOME" PATH="$HOME/.local/bin:$HOME/.fly/bin:/usr/local/bin:/usr/bin:/bin" bash --noprofile --norc -c '"$HOME/.local/bin/sprite-codex-cli" --sprite-codex-resolve' 2>/dev/null || true)
    fresh_version=$(env -i HOME="$HOME" PATH="$HOME/.local/bin:$HOME/.fly/bin:/usr/local/bin:/usr/bin:/bin" bash --noprofile --norc -c '"$HOME/.local/bin/sprite-codex-cli" --version' 2>/dev/null || true)
    echo "         fresh shell: ${fresh_path:-unknown} | ${fresh_version:-unknown}"
    if [[ -z $fresh_path || -z $fresh_version ]]; then
      echo "warning: the updated Codex is not visible from a fresh Sprite shell; not relaunching" >&2
      exit "$codex_rc"
    fi

    update_restarts=$((update_restarts+1))
    if (( update_restarts > 2 )); then
      echo "warning: Codex changed repeatedly; refusing an update/relaunch loop" >&2
      exit "$codex_rc"
    fi

    # The just-ended TUI has already persisted its conversation. Resume it so
    # an in-app update returns the user directly to the same work.
    launch_mode=resume
    echo "       relaunching with the updated Codex and resuming the conversation"
    continue
  fi

  if [[ $cmp == eq && $after_path == "$before_path" ]]; then
    echo "       Codex exited with the same executable/version: ${after_version:-unknown}"
  elif [[ $cmp == lt ]]; then
    echo "warning: Codex resolution moved backwards from ${before_version:-unknown} to ${after_version:-unknown}; not relaunching" >&2
  else
    echo "       Codex exited; no verified version/path update was detected"
  fi
  exit "$codex_rc"
done
RUNNER
  printf '%s' "$f"
}

set_org_args() {
  ORG=()
  [[ -n ${SPRITE_ORG:-} ]] && ORG=(-o "$SPRITE_ORG")
  return 0
}

# Restore only the Sprite selection explicitly supplied for this invocation.
# In particular, do not retain a name copied out of a stale resume-state file.
reset_sprite_selection() {
  SPRITE_NAME="$REQUESTED_SPRITE_NAME"
  SPRITE_ORG="$REQUESTED_SPRITE_ORG"
  set_org_args
}

compute_state_file() {
  local key state_root
  key=$(python3 - "$HOST_DIR" <<'PY'
import hashlib, os, sys
p=os.path.realpath(sys.argv[1])
print(hashlib.sha256(p.encode()).hexdigest())
PY
)
  state_root="${XDG_STATE_HOME:-$HOME/.local/state}/sprite-codex"
  mkdir -p "$state_root"
  chmod 700 "$state_root" 2>/dev/null || true
  if [[ $AGENT_KIND == codex ]]; then
    # Preserve the pre-v37 Codex state path for backward compatibility.
    STATE_FILE="${SPRITE_SESSION_STATE:-$state_root/$key.json}"
  else
    STATE_FILE="${SPRITE_SESSION_STATE:-$state_root/$key-kimi-code.json}"
  fi
}

load_state() {
  [[ -f $STATE_FILE ]] || return 1
  mapfile -t STATE_VALUES < <(python3 - "$STATE_FILE" <<'PY'
import json, sys
try: d=json.load(open(sys.argv[1]))
except Exception: raise SystemExit(1)
for k in ("version","host_dir","sprite_name","sprite_org","remote_workdir","session_manager","session_tag","task_name","session_id","tmux_session","deadline_epoch","run_hours","provider","transport","github_repository","agent"):
    v=d.get(k,""); print(v if v is not None else "")
PY
) || return 1
  ((${#STATE_VALUES[@]} >= 16)) || return 1
  STATE_VERSION=${STATE_VALUES[0]:-0}; STATE_HOST_DIR=${STATE_VALUES[1]}; STATE_SPRITE_NAME=${STATE_VALUES[2]}; STATE_SPRITE_ORG=${STATE_VALUES[3]}; STATE_REMOTE_WORKDIR=${STATE_VALUES[4]}; STATE_SESSION_MANAGER=${STATE_VALUES[5]:-}; STATE_SESSION_TAG=${STATE_VALUES[6]:-}; STATE_TASK_NAME=${STATE_VALUES[7]:-}; STATE_SESSION_ID=${STATE_VALUES[8]:-}; STATE_TMUX_SESSION=${STATE_VALUES[9]:-}; STATE_DEADLINE_EPOCH=${STATE_VALUES[10]:-}; STATE_RUN_HOURS=${STATE_VALUES[11]:-}; STATE_CODEX_PROVIDER=${STATE_VALUES[12]:-deepseek}; STATE_TRANSPORT=${STATE_VALUES[13]:-}; STATE_GITHUB_REPOSITORY=${STATE_VALUES[14]:-}; STATE_AGENT=${STATE_VALUES[15]:-codex}
  [[ -n $STATE_SPRITE_NAME && -n $STATE_REMOTE_WORKDIR ]]
}

write_state() {
  local sid=${CURRENT_SESSION_ID:-}
  python3 - "$STATE_FILE" "$HOST_DIR" "$SPRITE_NAME" "${SPRITE_ORG:-}" "$REMOTE_WORKDIR" "$SESSION_TAG" "$TASK_NAME" "$sid" "$SESSION_DEADLINE" "$SPRITE_RUN_HOURS" "$AGENT_PROVIDER" "$TRANSPORT" "$GITHUB_REPOSITORY" "$AGENT_KIND" <<'PY'
import json,os,sys,tempfile,time
(path,host_dir,sprite_name,sprite_org,workdir,tag,task_name,sid,deadline,run_hours,provider,transport,github_repository,agent)=sys.argv[1:]
d={"version":6,"host_dir":os.path.realpath(host_dir),"sprite_name":sprite_name,"sprite_org":sprite_org,"remote_workdir":workdir,"session_manager":"sprite-tty","session_tag":tag,"task_name":task_name,"session_id":sid,"tmux_session":"","deadline_epoch":int(deadline),"run_hours":run_hours,"provider":provider,"transport":transport,"github_repository":github_repository,"agent":agent,"updated_at":int(time.time())}
os.makedirs(os.path.dirname(path),exist_ok=True); fd,tmp=tempfile.mkstemp(prefix=".state.",dir=os.path.dirname(path))
try:
    with os.fdopen(fd,"w") as f: json.dump(d,f,indent=2); f.write("\n")
    os.chmod(tmp,0o600); os.replace(tmp,path)
finally:
    try: os.unlink(tmp)
    except FileNotFoundError: pass
PY
}

update_state_session_id() {
  local sid=$1
  [[ -f $STATE_FILE && -n $sid ]] || return 0
  python3 - "$STATE_FILE" "$sid" <<'PY'
import json,os,sys,tempfile,time
p,sid=sys.argv[1:]
try: d=json.load(open(p))
except Exception: raise SystemExit(0)
d["session_id"]=sid; d["session_manager"]="sprite-tty"; d["updated_at"]=int(time.time())
fd,tmp=tempfile.mkstemp(prefix=".state.",dir=os.path.dirname(p))
with os.fdopen(fd,"w") as f: json.dump(d,f,indent=2); f.write("\n")
os.chmod(tmp,0o600); os.replace(tmp,p)
PY
}

clear_state() { rm -f -- "$STATE_FILE"; }
get_sessions_json() { run_limited 25 sprite api "${ORG[@]}" -s "$SPRITE_NAME" /exec 2>/dev/null || true; }
sessions_inventory_valid() {
  python3 -c 'import json,sys
try: root=json.load(sys.stdin)
except Exception: raise SystemExit(1)
if isinstance(root,list): raise SystemExit(0)
if isinstance(root,dict):
 for k in ("sessions","data","items"):
  if k in root and isinstance(root[k],list): raise SystemExit(0)
raise SystemExit(1)' <<<"$1"
}

native_session_rows() {
  local raw=$1 tag=$2 preferred=${3:-} workdir=${4:-} tmp
  tmp=$(mktemp); cleanup_files+=("$tmp"); printf '%s' "$raw" >"$tmp"
  python3 - "$tmp" "$tag" "$preferred" "$workdir" <<'PY'
import datetime as dt,json,sys
path,tag,preferred,workdir=sys.argv[1:]
try: root=json.load(open(path))
except Exception: raise SystemExit(0)
items=(root.get("sessions") or root.get("data") or root.get("items") or []) if isinstance(root,dict) else root
if not isinstance(items,list): raise SystemExit(0)
def ts(r):
    for k in ("created_at","createdAt","created","started_at","startedAt","started","updated_at","updatedAt"):
        v=r.get(k)
        if v in (None,""): continue
        if isinstance(v,(int,float)): return float(v)
        t=str(v).strip()
        try: return float(t)
        except Exception: pass
        try: return dt.datetime.fromisoformat(t.replace("Z","+00:00")).timestamp()
        except Exception: pass
    return 0.0
rows=[]
for i,r in enumerate(items):
    if not isinstance(r,dict): continue
    sid=str(r.get("id",r.get("session_id",""))); cmd=" ".join(str(r.get("command","")).split()); wd=str(r.get("workdir",r.get("dir","")))
    active=r.get("is_active",r.get("isActive",r.get("active",True))); tty=r.get("tty",r.get("is_tty",r.get("isTty",False)))
    if not sid or active is False or not tty or tag not in cmd: continue
    created=""
    for k in ("created_at","createdAt","created","started_at","startedAt","started"):
        if r.get(k) not in (None,""): created=str(r.get(k)); break
    bonus=2 if preferred and sid==preferred else 1 if workdir and wd==workdir else 0
    rows.append((ts(r),bonus,i,sid,created,wd,cmd))
for epoch,bonus,i,sid,created,wd,cmd in sorted(rows,reverse=True): print("\t".join((str(epoch),sid,created,wd,cmd)))
PY
}

# List every live managed native Codex TTY on the selected Sprite, regardless of
# workspace hash. This is broader than native_session_rows(), which intentionally
# filters to one deterministic project tag for attachment/resume selection.
codex_native_session_rows() {
  local raw=$1 tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  printf '%s' "$raw" >"$tmp"
  python3 - "$tmp" <<'PY'
import datetime as dt, json, sys
path = sys.argv[1]
try:
    root = json.load(open(path))
except Exception:
    raise SystemExit(0)
items = (root.get("sessions") or root.get("data") or root.get("items") or []) if isinstance(root, dict) else root
if not isinstance(items, list):
    raise SystemExit(0)

def timestamp(record):
    for key in ("created_at", "createdAt", "created", "started_at", "startedAt", "started", "updated_at", "updatedAt"):
        value = record.get(key)
        if value in (None, ""):
            continue
        if isinstance(value, (int, float)):
            return float(value)
        text = str(value).strip()
        try:
            return float(text)
        except Exception:
            pass
        try:
            return dt.datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
        except Exception:
            pass
    return 0.0

rows = []
for index, record in enumerate(items):
    if not isinstance(record, dict):
        continue
    session_id = str(record.get("id", record.get("session_id", "")))
    command = " ".join(str(record.get("command", "")).split())
    workdir = str(record.get("workdir", record.get("dir", "")))
    active = record.get("is_active", record.get("isActive", record.get("active", True)))
    tty = record.get("tty", record.get("is_tty", record.get("isTty", False)))
    if not session_id or active is False or not tty or "sprite-codex-native-" not in command:
        continue
    created = ""
    for key in ("created_at", "createdAt", "created", "started_at", "startedAt", "started"):
        if record.get(key) not in (None, ""):
            created = str(record.get(key))
            break
    rows.append((timestamp(record), index, session_id, created, workdir, command))
for epoch, index, session_id, created, workdir, command in sorted(rows, reverse=True):
    print("\x1f".join((str(epoch), session_id, created, workdir, command)))
PY
}

offer_codex_update_before_run() {
  local raw=$1 row sid created workdir command answer="" should_update=0
  local legacy_live=0 process_count=0 process_rows=""
  local -a live_rows=()

  [[ $AGENT_KIND == codex ]] || return 0
  mapfile -t live_rows < <(codex_native_session_rows "$raw")

  # Also recognize the one deterministic legacy tmux session and unmanaged
  # Codex-like processes when no native Codex TTY already proves that Codex is
  # live. Avoid extra control execs on the normal fast reattach path.
  if ((${#live_rows[@]} == 0)); then
    if [[ -n ${LEGACY_TMUX_SESSION:-} ]] && legacy_tmux_probe "$LEGACY_TMUX_SESSION"; then
      legacy_live=1
    fi
    if (( legacy_live == 0 )); then
      process_rows=$(control_exec_limited 10 -- bash -lc \
        "pgrep -af '([c]odex|[a]pp-server)' 2>/dev/null || true" 2>/dev/null || true)
      if [[ -n $process_rows ]]; then
        process_count=$(printf '%s\n' "$process_rows" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
      fi
    fi
  fi

  CODEX_UPDATE_LIVE_DETECTED=0
  if ((${#live_rows[@]} > 0 || legacy_live == 1 || process_count > 0)); then
    CODEX_UPDATE_LIVE_DETECTED=1
  fi

  step "optional Codex CLI update"
  note "CODEX_UPDATE_MODE=$CODEX_UPDATE_MODE"
  if ((${#live_rows[@]} > 0)); then
    warn "${#live_rows[@]} live managed Codex native TTY session(s) were detected on Sprite $SPRITE_NAME"
    for row in "${live_rows[@]}"; do
      IFS=$'\x1f' read -r _ sid created workdir command <<<"$row"
      note "live Codex session: id=$sid created=${created:-unknown} workspace=${workdir:-unknown}"
    done
  fi
  if (( legacy_live == 1 )); then
    warn "live legacy tmux Codex session detected: $LEGACY_TMUX_SESSION"
  fi
  if (( process_count > 0 && ${#live_rows[@]} == 0 && legacy_live == 0 )); then
    warn "$process_count Codex-like process(es) were found even though no managed native Codex TTY row matched"
  fi

  if (( CODEX_UPDATE_LIVE_DETECTED == 1 )); then
    note "updating will not stop, kill, attach to, or rewrite the active conversation"
    note "the active process keeps running; the new selector is used by the next Codex launch or managed relaunch"
    if ((${#live_rows[@]} > 0)); then
      note "the existing native runner already resumes the just-ended conversation after it detects a newer Codex"
    fi
  else
    note "no live Codex session or process was detected by the validated inventory/probes"
  fi

  case "$CODEX_UPDATE_MODE" in
    never)
      note "CODEX_UPDATE_MODE=never; keeping the currently selected Codex unless MIN_CODEX_VERSION requires setup"
      return 0
      ;;
    always)
      if (( CODEX_UPDATE_LIVE_DETECTED == 1 )) && [[ $CODEX_UPDATE_LIVE_OVERRIDE != 1 ]]; then
        if [[ -t 0 && -t 1 ]]; then
          printf '  Codex is live. Type UPDATE to override the warning and install latest anyway: '
          IFS= read -r answer || true
          [[ $answer == UPDATE ]] && should_update=1
        else
          warn "CODEX_UPDATE_MODE=always was requested, but Codex is live and CODEX_UPDATE_LIVE_OVERRIDE is not 1"
          note "skipping the update; set CODEX_UPDATE_LIVE_OVERRIDE=1 only when that live-update override is intentional"
          return 0
        fi
      else
        should_update=1
      fi
      ;;
    ask)
      if [[ ! -t 0 || ! -t 1 ]]; then
        note "no interactive terminal is available; set CODEX_UPDATE_MODE=always to request an automatic pre-run update"
        if (( CODEX_UPDATE_LIVE_DETECTED == 1 )); then
          note "a non-interactive live update additionally requires CODEX_UPDATE_LIVE_OVERRIDE=1"
        fi
        return 0
      fi
      if (( CODEX_UPDATE_LIVE_DETECTED == 1 )); then
        printf '  Codex is live. Type UPDATE to install the latest stable CLI anyway, or press Enter to keep it unchanged: '
        IFS= read -r answer || true
        [[ $answer == UPDATE ]] && should_update=1
      else
        printf '  Update Codex to the latest stable CLI before continuing? [y/N]: '
        IFS= read -r answer || true
        case "${answer,,}" in
          y|yes) should_update=1 ;;
        esac
      fi
      ;;
  esac

  if (( should_update == 0 )); then
    note "Codex update skipped; session attachment and resume behavior are unchanged"
    return 0
  fi

  CODEX_UPDATE_REQUESTED=1
  if ! run_codex_latest_update; then
    # An optional update failure must not prevent attachment to a still-live TTY
    # or alter the user's ability to resume/fork from persisted history.
    note "the optional update failed; continuing without changing session-selection or resume state"
  fi
}

session_id_is_active() {
  local sid=$1 raw; [[ -n $sid ]] || return 1; raw=$(get_sessions_json)
  python3 -c 'import json,sys
sid=sys.argv[1]
try: root=json.load(sys.stdin)
except Exception: raise SystemExit(1)
items=(root.get("sessions") or root.get("data") or root.get("items") or []) if isinstance(root,dict) else root
for r in items if isinstance(items,list) else []:
 rid=str(r.get("id",r.get("session_id",""))); active=r.get("is_active",r.get("isActive",r.get("active",True)))
 if rid==sid and active is not False: raise SystemExit(0)
raise SystemExit(1)' "$sid" <<<"$raw"
}

find_native_session_row() { local tag=$1 preferred=${2:-} workdir=${3:-} raw; raw=$(get_sessions_json); native_session_rows "$raw" "$tag" "$preferred" "$workdir" | sed -n '1p'; }
find_native_session_with_retry() {
  local tag=$1 workdir=${2:-} tries=${3:-3} delay=${4:-1} i row
  for ((i=1; i<=tries; i++)); do
    row=$(find_native_session_row "$tag" "" "$workdir" || true)
    if [[ -n $row ]]; then printf '%s
' "$row"; return 0; fi
    (( i == tries )) && break
    sleep "$delay"
  done
  return 1
}

SESSION_CONTEXT_DIR=""
ensure_session_context() {
  [[ -n $SESSION_CONTEXT_DIR && -d $SESSION_CONTEXT_DIR ]] && return 0
  SESSION_CONTEXT_DIR=$(mktemp -d); cleanup_dirs+=("$SESSION_CONTEXT_DIR")
  ( cd "$SESSION_CONTEXT_DIR"; run_limited 20 sprite use "${ORG[@]}" "$SPRITE_NAME" >/dev/null 2>&1 ) || return 1
}
attach_session() {
  local sid=$1; ensure_session_context || { warn "could not create temporary Sprite CLI context for session attach"; return 1; }
  if ( cd "$SESSION_CONTEXT_DIR"; sprite sessions attach --help >/dev/null 2>&1 ); then ( cd "$SESSION_CONTEXT_DIR"; sprite sessions attach "$sid" );
  elif ( cd "$SESSION_CONTEXT_DIR"; sprite attach --help >/dev/null 2>&1 ); then ( cd "$SESSION_CONTEXT_DIR"; sprite attach "$sid" );
  else warn "this Sprite CLI does not expose a recognized session-attach command"; return 127; fi
}
kill_native_session() {
  local sid=$1
  ensure_session_context || { warn "could not create temporary Sprite CLI context for session kill"; return 1; }
  if ( cd "$SESSION_CONTEXT_DIR"; sprite sessions kill --help >/dev/null 2>&1 ); then
    ( cd "$SESSION_CONTEXT_DIR"; sprite sessions kill "$sid" )
  else
    warn "this Sprite CLI does not expose 'sprite sessions kill'"
    return 127
  fi
}

force_replace_native_sessions() {
  local tag=$1 raw row sid ans count=0
  raw=$(get_sessions_json)
  mapfile -t rows < <(native_session_rows "$raw" "$tag" "" "")
  ((${#rows[@]})) || return 0
  warn "FORCE_NEW_SESSION=1 and ${#rows[@]} live managed native Sprite TTY session(s) already exist"
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r _ sid _ _ _ <<<"$row"
    note "live native session: $sid"
  done
  [[ -t 0 ]] || die "FORCE_NEW_SESSION=1 cannot replace live native sessions without interactive confirmation"
  printf '  Stop ALL of these managed native sessions before starting a new %s session? [y/N]: ' "$AGENT_LABEL"
  IFS= read -r ans || true
  case "${ans,,}" in
    y|yes) ;;
    *) die "refusing to start a duplicate $AGENT_LABEL while a native managed session is live" ;;
  esac
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r _ sid _ _ _ <<<"$row"
    kill_native_session "$sid" || die "could not stop native Sprite session $sid"
  done
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r _ sid _ _ _ <<<"$row"
    confirm_live_session_with_retry "$sid" && die "native Sprite session $sid is still reported active after kill"
  done
  note "all prior managed native sessions were stopped explicitly"
}
confirm_live_session_with_retry() {
  local sid=$1 try=1 delay=$TTY_REATTACH_DELAY
  while (( try <= TTY_REATTACH_CONFIRM_TRIES )); do session_id_is_active "$sid" && return 0; (( try == TTY_REATTACH_CONFIRM_TRIES )) && break; sleep "$delay"; (( delay < 10 )) && delay=$((delay+2)); try=$((try+1)); done
  return 1
}
surface_native_hold_state() {
  local tag=$1 out=""
  out=$(control_exec_limited 10 -- bash -lc 'base="$HOME/.local/state/sprite-codex"; tag=$1; state=$(cat "$base/hold-state-$tag" 2>/dev/null || true); deadline=$(cat "$base/hold-deadline-$tag" 2>/dev/null || true); released=$(cat "$base/hold-released-$tag.marker" 2>/dev/null || true); printf "state=%s deadline=%s released=%s\n" "$state" "$deadline" "$released"' _ "$tag" 2>/dev/null || true)
  case "$out" in *state=released*) warn "the Tasks API heartbeat for '$tag' reached its configured hard cap"; note "$out"; note "the native TTY may still be keeping the Sprite active while the session is live" ;; *state=active*) note "remote hold state: $out" ;; esac
}

attach_native_session_resilient() {
  local sid=$1 tag=${2:-} rc=0 failures=0 started elapsed
  [[ -z $tag ]] || surface_native_hold_state "$tag"
  while :; do
    started=$(date +%s)
    if attach_session "$sid"; then
      rc=0
    else
      rc=$?
    fi
    elapsed=$(( $(date +%s) - started ))
    if (( rc == 0 )); then
      if session_id_is_active "$sid"; then note "detached from native Sprite TTY session $sid; $AGENT_LABEL remains running"; note "rerun this script or use 'sprite sessions attach $sid' to reconnect"; fi
      return 0
    fi
    (( rc == 130 || rc == 129 || rc == 131 )) && return "$rc"
    (( TTY_AUTO_REATTACH == 1 )) || return "$rc"
    (( elapsed >= 30 )) && failures=0; failures=$((failures+1))
    if (( TTY_REATTACH_ATTEMPTS > 0 && failures > TTY_REATTACH_ATTEMPTS )); then warn "automatic native TTY reattach limit reached ($TTY_REATTACH_ATTEMPTS consecutive failures)"; return "$rc"; fi
    warn "local Sprite TTY attachment ended with rc=$rc"; note "checking whether native session $sid is still alive"
    if confirm_live_session_with_retry "$sid"; then update_state_session_id "$sid" 2>/dev/null || true; note "same remote $AGENT_LABEL TTY is live; reattaching in ${TTY_REATTACH_DELAY}s"; sleep "$TTY_REATTACH_DELAY"; continue; fi
    warn "session $sid could not be confirmed after bounded retries"; note "resume state is retained; rerun the script if connectivity recovers"; return "$rc"
  done
}

choose_live_native_session() {
  local tag=$1 preferred=${2:-} workdir_hint=${3:-} raw row i=1 choice chosen sid created wd cmd epoch hint
  raw=$(get_sessions_json); mapfile -t rows < <(native_session_rows "$raw" "$tag" "$preferred" "$workdir_hint"); ((${#rows[@]})) || return 1
  note "reattaching preserves the running process credentials; no new token entry or rotation occurs"
  step "choose live native $AGENT_LABEL TTY session"; note "live managed Sprite TTY sessions on $SPRITE_NAME (newest first):"
  for row in "${rows[@]}"; do IFS=$'\t' read -r epoch sid created wd cmd <<<"$row"; hint=""; [[ -n $preferred && $sid == "$preferred" ]] && hint=" [saved-state hint]"; printf '    %d) id=%s%s\n' "$i" "$sid" "$hint"; printf '       created=%s workspace=%s\n' "${created:-unknown}" "${wd:-unknown}"; printf '       command=%s\n' "${cmd:-unknown}"; ((i++)); done
  if [[ ! -t 0 ]]; then choice=1; else printf '  Attach which session? [1]: '; IFS= read -r choice || true; choice=${choice:-1}; fi
  [[ $choice =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#rows[@]})) || { warn "invalid native session choice"; return 2; }
  chosen=${rows[choice-1]}; IFS=$'\t' read -r epoch sid created wd cmd <<<"$chosen"; note "attaching directly to native Sprite TTY session $sid"; note "detach without stopping $AGENT_LABEL with Ctrl+\\"; update_state_session_id "$sid" 2>/dev/null || true
  local rc
  if attach_native_session_resilient "$sid" "$tag"; then
    rc=0
  else
    rc=$?
  fi
  return "$rc"
}

# v31-and-earlier migration guard only; normal v32 sessions never use tmux.
legacy_tmux_probe() {
  local session=$1
  control_exec_limited 15 -- bash -lc 's=$1; command -v tmux >/dev/null 2>&1 || exit 3; tmux has-session -t "$s" 2>/dev/null || exit 1; panes=$(tmux list-panes -t "$s" -F "#{pane_dead}|#{pane_start_command}|#{pane_current_command}" 2>/dev/null || true); meta=$(tmux show-environment -t "$s" SPRITE_CODEX_TASK 2>/dev/null || true); printf "%s\n%s\n" "$panes" "$meta" | grep -q "sprite-codex" && exit 0; exit 4' _ "$session" >/dev/null 2>&1
}
legacy_tmux_kill() { local session=$1; control_exec_limited 20 -- tmux kill-session -t "$session" >/dev/null 2>&1; }
legacy_tmux_attach() { local session=$1; warn "attaching to a legacy tmux-managed Codex session from v31 or earlier"; note "this one legacy attachment still has tmux input/copy-mode behavior"; note "finish or stop that legacy Codex run, then rerun v34 for native Sprite TTY sessions"; sprite exec "${ORG[@]}" -s "$SPRITE_NAME" --tty --no-port-forward -- tmux attach-session -d -t "$session"; }
legacy_tmux_guard() {
  local session=$1 rc ans
  [[ -n $session ]] || return 1
  if legacy_tmux_probe "$session"; then
    rc=0
  else
    rc=$?
  fi
  case $rc in
    0)
      warn "live legacy tmux Codex session detected: $session"
      if [[ $FORCE_NEW_SESSION == 1 && -t 0 ]]; then printf '  FORCE_NEW_SESSION=1: stop this legacy tmux session before starting native v34? [y/N]: '; IFS= read -r ans || true; case "${ans,,}" in y|yes) legacy_tmux_kill "$session" || die "could not stop legacy tmux session"; return 1 ;; *) die "refusing to start a duplicate Codex while legacy tmux session is live" ;; esac; fi
      if [[ -t 0 ]]; then printf '  Attach to the legacy session now? [Y/n]: '; IFS= read -r ans || true; else ans=y; fi
      case "${ans,,}" in ''|y|yes) legacy_tmux_attach "$session"; return 0 ;; *) die "legacy Codex remains live; refusing to start a second Codex process" ;; esac ;;
    1|3) return 1 ;;
    *) warn "legacy tmux state for '$session' could not be proven"; return 2 ;;
  esac
}

start_native_agent_session() {
  local remote_entry=$1 remote_runner=$2 row sid="" rc watcher="" raw
  assert_token_validation_gate
  raw=$(get_sessions_json)
  [[ -n $raw ]] && sessions_inventory_valid "$raw" || die "cannot validate Sprite session inventory before launch; refusing to risk a duplicate $AGENT_LABEL process"
  row=$(native_session_rows "$raw" "$SESSION_TAG" "${CURRENT_SESSION_ID:-}" "$REMOTE_WORKDIR" | sed -n '1p')
  [[ -z $row ]] || { IFS=$'\t' read -r _ sid _ _ _ <<<"$row"; die "managed native Sprite TTY session $sid is already live; refusing to start a duplicate $AGENT_LABEL process"; }
  CURRENT_SESSION_ID=""; write_state
  (
    for _ in $(seq 1 30); do sleep 1; row=$(find_native_session_row "$SESSION_TAG" "" "$REMOTE_WORKDIR" || true); if [[ -n $row ]]; then IFS=$'\t' read -r _ sid _ _ _ <<<"$row"; [[ -n $sid ]] && update_state_session_id "$sid" >/dev/null 2>&1 || true; exit 0; fi; done
  ) >/dev/null 2>&1 & watcher=$!
  note "starting $AGENT_LABEL directly in a native detachable Sprite TTY"; note "detach with Ctrl+\\; no tmux key prefix or mouse mode is involved"
  if sprite exec "${ORG[@]}" -s "$SPRITE_NAME" --tty --no-port-forward \
    --env "SPRITE_CODEX_ENV_HEX=$ALL_CREDENTIAL_ENV" -- \
    "$remote_entry" bash "$remote_runner" "$RUN_SECONDS" "$TASK_NAME" "$SESSION_TAG" \
      "$REMOTE_WORKDIR" "$AGENT_START_MODE" "$AGENT_KIND" "$AGENT_PROVIDER" "$KIMI_CODE_APPROVAL_MODE"; then
    rc=0
  else
    rc=$?
  fi
  # Session registration can lag slightly behind the local viewer ending. Use a
  # short lookup after a clean detach, and the full reconnect budget after an
  # error, before concluding that no remote TTY survived.
  if (( rc == 0 )); then
    row=$(find_native_session_with_retry "$SESSION_TAG" "$REMOTE_WORKDIR" 3 1 || true)
  else
    row=$(find_native_session_with_retry "$SESSION_TAG" "$REMOTE_WORKDIR" "$TTY_REATTACH_CONFIRM_TRIES" "$TTY_REATTACH_DELAY" || true)
  fi
  kill "$watcher" 2>/dev/null || true; wait "$watcher" 2>/dev/null || true
  if [[ -n $row ]]; then IFS=$'\t' read -r _ sid _ _ _ <<<"$row"; CURRENT_SESSION_ID=$sid; update_state_session_id "$sid" 2>/dev/null || true; fi
  if (( rc == 0 )); then
    if [[ -n $sid ]] && session_id_is_active "$sid"; then note "native Sprite TTY detached cleanly; $AGENT_LABEL remains live as session $sid"; note "reattach later with this script or: sprite sessions attach $sid"; else note "$AGENT_LABEL/native TTY exited cleanly; resume state is retained as a history hint"; fi
    return 0
  fi
  if [[ -n $sid ]] && confirm_live_session_with_retry "$sid"; then warn "initial local TTY transport ended with rc=$rc but remote session $sid is still live"; if (( TTY_AUTO_REATTACH == 1 )); then note "reattaching to the same native Sprite session"; attach_native_session_resilient "$sid" "$SESSION_TAG"; return $?; fi; fi
  warn "$AGENT_LABEL TTY launch/attachment ended with rc=$rc and no live managed session could be confirmed"; return "$rc"
}

prompt_run_limit() {
  local entered=${SPRITE_RUN_HOURS:-}
  if [[ -z $entered ]]; then
    if [[ -t 0 ]]; then
      printf '  Sprite keep-awake limit in hours [%s]: ' "$DEFAULT_RUN_HOURS"
      IFS= read -r entered || true
    fi
    entered=${entered:-$DEFAULT_RUN_HOURS}
  else
    note "SPRITE_RUN_HOURS supplied: $entered"
  fi
  RUN_SECONDS=$(python3 - "$entered" <<'PY'
from decimal import Decimal, InvalidOperation, ROUND_CEILING
import sys
try: h=Decimal(sys.argv[1])
except InvalidOperation: raise SystemExit(2)
if h <= 0 or h > 168: raise SystemExit(2)
print(int((h*Decimal(3600)).to_integral_value(rounding=ROUND_CEILING)))
PY
) || die "run limit must be a positive number of hours, no more than 168"
  SPRITE_RUN_HOURS=$entered
  _run_deadline_preview=$(( $(date +%s) + RUN_SECONDS ))
  note "the Tasks API heartbeat follows the $AGENT_LABEL runner for at most ${SPRITE_RUN_HOURS} hour(s)"
  note "native Sprite TTY sessions are themselves activity, so this bounds the Tasks hold—not total Sprite awake time"
  note "approx Tasks-hold deadline (local): $(date -d "@$_run_deadline_preview" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$_run_deadline_preview" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$_run_deadline_preview")"
  note "approx Tasks-hold deadline (UTC):   $(date -u -d "@$_run_deadline_preview" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -r "$_run_deadline_preview" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "$_run_deadline_preview")"
}

make_model_test_helper() {
  MODEL_TEST_HELPER=$(mktemp)
  cleanup_files+=("$MODEL_TEST_HELPER")
  cat >"$MODEL_TEST_HELPER" <<'MODEL_TEST_PY'
#!/usr/bin/env python3
"""Bounded native-Responses smoke tests. No SDK, shell tools or generated code.

Defaults are injected by the Bash launcher, which is the single source of truth.
All three providers run independently. A successful HTTP status alone is not PASS.
"""
import contextlib
import datetime
import getpass
import json
import os
import re
import secrets
import signal
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

SPECS = (
    ("deepseek", "DEEPSEEK_MODEL", "DEEPSEEK_BASE_URL", "DEEPSEEK_API_KEY", "DEEPSEEK_REASONING_EFFORT"),
    ("minimax", "MINIMAX_MODEL", "MINIMAX_BASE_URL", "MINIMAX_API_KEY", "MINIMAX_REASONING_EFFORT"),
    ("moonshot", "KIMI_MODEL", "MOONSHOT_BASE_URL", "MOONSHOT_API_KEY", "KIMI_REASONING_EFFORT"),
)
MAX_BYTES = 8 * 1024 * 1024
MAX_LINE = 1024 * 1024


class ProbeError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward a provider credential to a redirect target.
        return None


def positive_int(env, name, default, minimum=1, maximum=3600):
    value = env.get(name, str(default))
    if not re.fullmatch(r"[0-9]+", value):
        raise ProbeError(name + " must be an integer")
    number = int(value)
    if not minimum <= number <= maximum:
        raise ProbeError("%s must be %s..%s" % (name, minimum, maximum))
    return number


def validate_base(base, allow_local=False):
    try:
        url = urllib.parse.urlsplit(base)
        port = url.port
    except ValueError:
        raise ProbeError("invalid API base URL")
    local = allow_local and url.scheme == "http" and url.hostname in ("localhost", "127.0.0.1", "::1")
    if not ((url.scheme == "https" or local) and url.hostname):
        raise ProbeError("API base URLs must use HTTPS (HTTP is allowed only for explicit localhost tests)")
    if url.username is not None or url.password is not None or url.query or url.fragment:
        raise ProbeError("API base URL must not contain credentials, a query or a fragment")
    if any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in base) or "\\" in base:
        raise ProbeError("invalid characters in API base URL")
    if port is not None and not 1 <= port <= 65535:
        raise ProbeError("invalid API port")
    return base.rstrip("/")


def sanitizer(keys):
    keys = sorted((key for key in keys if key), key=len, reverse=True)

    def clean(value):
        text = str(value)
        for key in keys:
            text = text.replace(key, "[REDACTED]")
        text = re.sub(r"(?i)bearer\s+[^\s\"']+", "Bearer [REDACTED]", text)
        text = re.sub(r"(?i)((?:api[_-]?key|token|password)\s*[=:]\s*)[^\s,;]+", r"\1[REDACTED]", text)
        text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
        text = " ".join("".join(c if c.isprintable() else " " for c in text).split())
        return text[:360]

    return clean


@contextlib.contextmanager
def deadline(seconds):
    # A socket timeout alone is only an idle timeout. SIGALRM also bounds a
    # slowly trickling stream; this tool runs on Unix Bash/Python on host/Sprite.
    if not hasattr(signal, "setitimer"):
        raise ProbeError("hard timeouts require Unix Python (Linux/macOS/WSL)")

    def expired(signum, frame):
        raise TimeoutError("request exceeded its wall-clock deadline")

    old_handler = signal.signal(signal.SIGALRM, expired)
    old_timer = signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old_handler)
        if old_timer[0]:
            signal.setitimer(signal.ITIMER_REAL, *old_timer)


def output_text(body):
    pieces = []
    for item in body.get("output", []):
        if isinstance(item, dict) and item.get("type") == "message" and item.get("role", "assistant") == "assistant":
            for part in item.get("content", []):
                if isinstance(part, dict) and part.get("type") == "output_text" and isinstance(part.get("text"), str):
                    pieces.append(part["text"])
    if pieces:
        return "".join(pieces).strip()
    text = body.get("output_text")
    return text.strip() if isinstance(text, str) else ""


def checked_response(body):
    if not isinstance(body, dict) or body.get("object") != "response":
        raise ProbeError("HTTP succeeded but body is not a Responses API response object")
    if body.get("error"):
        raise ProbeError("API response contains an error: " + str(body["error"]))
    if body.get("status") != "completed":
        raise ProbeError("response did not complete: status=%s details=%s" % (body.get("status"), body.get("incomplete_details")))
    if not isinstance(body.get("output"), list):
        raise ProbeError("response output is not an array")
    if not isinstance(body.get("model"), str) or not body["model"]:
        raise ProbeError("response does not identify the model that served it")
    return body


def stream_response(response):
    if "text/event-stream" not in response.headers.get("Content-Type", "").lower():
        raise ProbeError("stream request did not return text/event-stream")
    event_name, data_lines, deltas = "", [], []
    received, count = 0, 0
    while True:
        line = response.readline(MAX_LINE + 1)
        received += len(line)
        if len(line) > MAX_LINE or received > MAX_BYTES:
            raise ProbeError("stream exceeded safety size limit")
        if not line:
            raise ProbeError("stream ended without a terminal response.completed event")
        text = line.decode("utf-8", "strict").rstrip("\r\n")
        if text == "":
            if not data_lines:
                event_name = ""
                continue
            raw = "\n".join(data_lines)
            data_lines = []
            if raw == "[DONE]":
                raise ProbeError("stream ended with [DONE] but no completed Responses object")
            event = json.loads(raw)
            if not isinstance(event, dict):
                raise ProbeError("invalid SSE event")
            kind = event.get("type") or event_name
            event_name = ""
            count += 1
            if kind == "response.output_text.delta":
                delta = event.get("delta")
                if not isinstance(delta, str):
                    raise ProbeError("invalid output_text delta")
                deltas.append(delta)
            elif kind in ("response.failed", "response.incomplete", "error"):
                raise ProbeError("stream failure: " + str(event.get("error") or kind))
            elif kind == "response.completed":
                body = checked_response(event.get("response"))
                if not deltas:
                    raise ProbeError("completed stream contained no output_text deltas")
                if "".join(deltas).strip() != output_text(body):
                    raise ProbeError("streamed text differs from the completed response")
                return body, count
        elif text.startswith("data:"):
            data_lines.append(text[5:].lstrip(" "))
        elif text.startswith("event:"):
            event_name = text[6:].strip()
        # Comments/keepalives, id and retry fields are intentionally ignored.


class Client:
    def __init__(self, provider, env, key, clean):
        self.provider, self.key, self.clean = provider, key, clean
        spec = next(row for row in SPECS if row[0] == provider)
        self.model = env[spec[1]]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", self.model):
            raise ProbeError("invalid " + spec[1])
        self.base = validate_base(env[spec[2]], env.get("MODEL_TEST_ALLOW_LOCALHOST") == "1")
        self.effort = env[spec[4]]
        if self.effort not in ("low", "high", "max") or (provider == "minimax" and self.effort == "max"):
            raise ProbeError("unsupported reasoning effort")
        self.timeout = positive_int(env, "MODEL_TEST_TIMEOUT", 180)
        self.max_tokens = positive_int(env, "MODEL_TEST_MAX_TOKENS", 4096, 256, 131072)
        self.retries = positive_int(env, "MODEL_TEST_RETRIES", 0, 0, 3)
        self.interval = positive_int(env, "KIMI_MIN_REQUEST_INTERVAL_MS", 20000, 0, 60000) / 1000 if provider == "moonshot" else 0
        self.last_start = 0.0
        self.last_status = None
        self.usage = {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0}
        self.models = set()
        self.requests = 0
        self.opener = urllib.request.build_opener(NoRedirect())

    def record(self, body):
        if not isinstance(body, dict):
            return
        if isinstance(body.get("model"), str):
            self.models.add(self.clean(body["model"]))
        usage = body.get("usage")
        if isinstance(usage, dict):
            for key in self.usage:
                value = usage.get(key)
                if type(value) is int and value >= 0:
                    self.usage[key] += value

    def request(self, items, tools=None, stream=False):
        body = {"model": self.model, "input": items, "stream": stream,
                "reasoning": {"effort": self.effort}, "max_output_tokens": self.max_tokens,
                "store": False}
        if tools is not None:
            body.update(tools=tools, tool_choice="auto")
        data = json.dumps(body).encode("utf-8")
        self.last_status = None
        for attempt in range(self.retries + 1):
            time.sleep(max(0, self.interval - (time.monotonic() - self.last_start)))
            self.last_start = time.monotonic()
            request = urllib.request.Request(self.base + "/responses", data=data, method="POST", headers={
                "Authorization": "Bearer " + self.key, "Content-Type": "application/json",
                "Accept": "text/event-stream" if stream else "application/json",
                "User-Agent": "sprite-codex-model-test/45"})
            self.requests += 1
            try:
                with deadline(self.timeout):
                    with self.opener.open(request, timeout=self.timeout) as response:
                        self.last_status = response.status
                        if stream:
                            result, _ = stream_response(response)
                        else:
                            raw = response.read(MAX_BYTES + 1)
                            if len(raw) > MAX_BYTES:
                                raise ProbeError("response exceeded safety size limit")
                            result = json.loads(raw)
                        self.record(result)
                        return checked_response(result)
            except urllib.error.HTTPError as exc:
                self.last_status = exc.code
                # Even error bodies can trickle forever; read them under a deadline.
                with contextlib.closing(exc):
                    try:
                        with deadline(min(5, self.timeout)):
                            error = json.loads(exc.read(16384))
                        detail = error.get("error", error)
                        if isinstance(detail, dict):
                            detail = detail.get("message") or detail.get("code") or "API rejected request"
                    except (ValueError, TimeoutError, OSError, AttributeError):
                        detail = "API returned a non-JSON or unreadable error body"
                if exc.code in (429, 502, 503, 504) and attempt < self.retries:
                    hint = exc.headers.get("Retry-After", "")
                    delay = min(60, max(1, int(hint))) if hint.isdigit() else min(60, 2 ** (attempt + 1))
                    time.sleep(delay)
                    continue
                category = {400: "request/model compatibility", 401: "authentication", 402: "balance/quota",
                            403: "permission/model access", 404: "model or endpoint unavailable", 429: "rate limit"}.get(exc.code, "API/transport error")
                raise ProbeError("HTTP %s (%s): %s" % (exc.code, category, self.clean(detail))) from None
        raise ProbeError("request retry budget exhausted")


def probe(client, name):
    if name in ("completion", "streaming"):
        marker = "SPRITE_MODEL_OK" if name == "completion" else "SPRITE_STREAM_OK"
        result = client.request([{"role": "user", "content": "Reply with exactly " + marker + ". No punctuation, markdown or explanation."}], stream=name == "streaming")
        if output_text(result) != marker:
            raise ProbeError("completed response did not return the exact test marker (not a successful smoke test)")
        return "completed response verified" if name == "completion" else "text deltas and completed SSE event verified"
    tool = {"type": "function", "name": "sprite_probe", "description": "Fetch a private one-time connectivity verification value.",
            "parameters": {"type": "object", "properties": {"label": {"type": "string", "enum": ["connectivity"]}},
                           "required": ["label"], "additionalProperties": False}}
    items = [{"role": "user", "content": "Call sprite_probe with label connectivity. You cannot know its value without calling it. After receiving the tool result, reply with exactly the value field, with no other text. Call the tool once."}]
    result = client.request(items, tools=[tool])
    calls = [item for item in result["output"] if isinstance(item, dict) and item.get("type") == "function_call"]
    if len(calls) != 1:
        raise ProbeError("expected exactly one function call; received %s" % len(calls))
    call = calls[0]
    if call.get("name") != "sprite_probe" or not isinstance(call.get("call_id"), str) or not call["call_id"]:
        raise ProbeError("unexpected tool name or missing call_id")
    arguments = call.get("arguments")
    if not isinstance(arguments, str) or json.loads(arguments) != {"label": "connectivity"}:
        raise ProbeError("function arguments failed schema/value validation")
    marker = "TOOL_OK_" + secrets.token_hex(12)
    # Preserve every returned output item, including reasoning/encrypted_content.
    # All providers support stateless replay; do not rely on previous_response_id.
    items += result["output"]
    items.append({"type": "function_call_output", "call_id": call["call_id"], "output": json.dumps({"value": marker})})
    final = client.request(items, tools=[tool])
    if any(item.get("type") in ("function_call", "custom_tool_call") for item in final["output"] if isinstance(item, dict)):
        raise ProbeError("model requested another tool instead of completing the round trip")
    if output_text(final) != marker:
        raise ProbeError("model did not use the one-time value supplied only in the tool result")
    return "function arguments, call_id, reasoning replay and tool-result round trip verified"


def write_report(path, report):
    path = os.path.abspath(os.path.expanduser(path))
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".model-tests-", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(report, out, indent=2)
            out.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


# Token checks deliberately do not return upstream bodies or CLI output. Error
# details can echo a supplied credential; only fixed diagnostics cross the wire.
class TokenFailure(Exception):
    def __init__(self, category, detail):
        super().__init__(detail)
        self.category = category


def token_http_failure(status, headers=None):
    headers = headers or {}
    if status == 401:
        return TokenFailure("authentication", "Token rejected (HTTP 401): invalid, expired or revoked.")
    if status == 402:
        return TokenFailure("quota", "Balance or quota prevents use (HTTP 402); token validity is not established.")
    if status == 429 or (status == 403 and (headers.get("X-RateLimit-Remaining") == "0" or headers.get("Retry-After"))):
        return TokenFailure("rate-limit", "Rate limited; wait and retry. This does not prove the token is invalid.")
    if status == 403:
        return TokenFailure("access", "Access denied (HTTP 403): check token scope, organization approval/SSO and model access; rate limiting is also possible.")
    if status == 404:
        return TokenFailure("access", "Target unavailable (HTTP 404): check repository/app/model and endpoint, and token access.")
    if status is not None and 300 <= status < 400:
        return TokenFailure("configuration", "Redirect refused; update the configured target. Credentials were not forwarded.")
    if status is not None and status >= 500:
        return TokenFailure("service", "Service error (HTTP %s); retry later. Token validity is not established." % status)
    return TokenFailure("request", "Request or response was not usable%s; check endpoint, model and request settings." % (" (HTTP %s)" % status if status else ""))


def token_get(url, key, timeout, *, basic=False, advertisement=False):
    import base64
    auth = "Basic " + base64.b64encode(("x-access-token:" + key).encode()).decode() if basic else "Bearer " + key
    headers = {"Authorization": auth, "User-Agent": "sprite-codex-token-check/47"}
    if not advertisement:
        headers.update({"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10"})
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with deadline(timeout), urllib.request.build_opener(NoRedirect()).open(req, timeout=timeout) as response:
            if response.status != 200:
                raise token_http_failure(response.status, response.headers)
            if advertisement:
                # Only service discovery: never POST a pack, create a ref or push.
                # A bounded prefix avoids downloading an entire large ref list.
                service = b"# service=git-receive-pack\n"
                raw = response.read(4 + len(service) + 4)
                expected = ("%04x" % (4 + len(service))).encode() + service + b"0000"
                if response.headers.get_content_type() != "application/x-git-receive-pack-advertisement" or raw != expected:
                    raise TokenFailure("response", "GitHub did not return the authenticated Git write-service advertisement.")
                return None
            raw = response.read(1024 * 1024 + 1)
            if len(raw) > 1024 * 1024:
                raise TokenFailure("response", "GitHub response exceeded the safety size limit.")
            body = json.loads(raw)
            if not isinstance(body, dict) or body.get("error"):
                raise TokenFailure("response", "GitHub returned an unexpected response object.")
            return body
    except urllib.error.HTTPError as exc:
        failure = token_http_failure(exc.code, exc.headers)
        exc.close()
        raise failure from None


def check_github_token(env, key, timeout):
    repo = env.get("GITHUB_REPOSITORY", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+", repo) or repo.split("/")[-1] in (".", ".."):
        raise TokenFailure("configuration", "GITHUB_REPOSITORY must be a valid OWNER/REPO.")
    user = token_get("https://api.github.com/user", key, timeout)
    if not isinstance(user.get("login"), str) or not user["login"] or type(user.get("id")) is not int:
        raise TokenFailure("response", "GitHub did not return an authenticated user; public repository access alone is not sufficient.")
    metadata = token_get("https://api.github.com/repos/" + repo, key, timeout)
    if str(metadata.get("full_name", "")).lower() != repo.lower():
        raise TokenFailure("configuration", "GitHub returned a different repository; update GITHUB_REPOSITORY.")
    permissions = metadata.get("permissions") or {}
    if not isinstance(permissions, dict):
        raise TokenFailure("response", "GitHub returned invalid repository permissions.")
    if metadata.get("archived") or metadata.get("disabled"):
        raise TokenFailure("access", "Repository is archived or disabled; it is not a writable target.")
    if permissions.get("push") is False and not any(permissions.get(k) is True for k in ("admin", "maintain")):
        raise TokenFailure("access", "GitHub reports no repository push permission. Grant Contents: read and write for the selected repository.")
    # Metadata permission and public reads alone do not prove a PAT can push.
    token_get("https://github.com/" + repo + ".git/info/refs?service=git-receive-pack", key, timeout,
              basic=True, advertisement=True)
    return "Authenticated user, selected repository and Git write-service access verified (no push performed; branch rules still apply)."


def check_fly_token(env, key, timeout):
    import shutil
    import subprocess
    app = env.get("FLY_APP", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*", app):
        raise TokenFailure("configuration", "FLY_APP must be a valid app name.")
    child_env = env.copy()
    home = child_env.get("HOME", os.path.expanduser("~"))
    child_env["PATH"] = home + "/.local/bin:" + home + "/.fly/bin:" + child_env.get("PATH", "/usr/local/bin:/usr/bin:/bin")
    fly = shutil.which("fly", path=child_env["PATH"]) or shutil.which("flyctl", path=child_env["PATH"])
    if not fly:
        raise TokenFailure("configuration", "Fly CLI is missing on the selected Sprite; install fly/flyctl and retry.")
    child_env["FLY_API_TOKEN"] = child_env["FLY_ACCESS_TOKEN"] = key
    # Disable optional diagnostics, never use --access-token or shell expansion.
    for name in ("LOG_LEVEL", "FLY_LOG_LEVEL", "FLY_DEBUG", "DEBUG"):
        child_env.pop(name, None)
    child_env["NO_COLOR"] = "1"
    # Use a transient empty working directory so a repository fly.toml cannot
    # redirect the app lookup. No credential or CLI output is written there.
    with tempfile.TemporaryDirectory(prefix="sprite-fly-check-") as workdir:
        process = subprocess.Popen([fly, "status", "--app", app], env=child_env, cwd=workdir,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            rc = process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
    if rc != 0:
        raise TokenFailure("access-or-service", "fly status failed: token may be invalid/expired, lack app access, or the app/network/service may be unavailable. Check FLY_APP, then replace the token or retry.")
    return "fly status succeeded for the selected app with both Fly token aliases; deployment/SSH permissions are not proven."


def token_main(kind, nonce):
    import subprocess
    env = os.environ.copy()
    key_names = {"github": "GITHUB_PAT", "fly": "FLY_API_TOKEN", "deepseek": "DEEPSEEK_API_KEY",
                 "minimax": "MINIMAX_API_KEY", "moonshot": "MOONSHOT_API_KEY"}
    result = {"schema_version": 1, "nonce": nonce, "kind": kind, "passed": False}
    client = None
    try:
        if kind not in key_names or not re.fullmatch(r"[a-f0-9]{32}", nonce):
            raise TokenFailure("configuration", "Invalid token-check request.")
        key = env.get(key_names[kind], "")
        if not key:
            raise TokenFailure("missing", "Credential is missing.")
        # Fly macaroons can contain spaces/commas. Do not trim or rewrite them.
        if not key.isascii() or any(ord(c) < 32 or ord(c) == 127 for c in key) or key != key.strip():
            raise TokenFailure("format", "Credential contains control/non-ASCII characters or leading/trailing whitespace; re-enter it without changing internal spaces/commas.")
        timeout = positive_int(env, "TOKEN_CHECK_TIMEOUT", 180, 1, 900)
        if kind == "github":
            detail = check_github_token(env, key, timeout)
        elif kind == "fly":
            detail = check_fly_token(env, key, timeout)
        else:
            # A /models listing need not prove generation access or usable quota.
            # Test the actual configured native Responses model, with no tools.
            env.update(MODEL_TEST_TIMEOUT=str(timeout), MODEL_TEST_RETRIES="0", MODEL_TEST_ALLOW_LOCALHOST="0")
            client = Client(kind, env, key, sanitizer([key]))
            probe(client, "completion")
            detail = "Configured model returned a completed, exact-answer Responses reply; generation access verified."
        result.update(passed=True, category="ok", detail=detail)
    except TokenFailure as exc:
        result.update(category=exc.category, detail=str(exc))
    except KeyboardInterrupt:
        result.update(category="interrupted", detail="Token check interrupted; launch is blocked.")
    except (TimeoutError, socket.timeout, subprocess.TimeoutExpired):
        result.update(category="timeout", detail="Validation timed out; token validity is not established. Retry or check connectivity.")
    except urllib.error.URLError:
        result.update(category="network", detail="Network/DNS/TLS error; token validity is not established. Retry or check connectivity.")
    except ProbeError:
        failure = token_http_failure(client.last_status if client else None)
        result.update(category=failure.category, detail=str(failure))
    except (ValueError, KeyError, TypeError, OSError):
        result.update(category="configuration-or-response", detail="Configuration or response could not be validated; check settings and retry.")
    except Exception:
        result.update(category="response", detail="Unexpected validation failure; launch is blocked. No credential or upstream body was logged.")
    print("SPRITE_TOKEN_RESULT=" + json.dumps(result, separators=(",", ":")), flush=True)
    return 0 if result["passed"] else 1


def main():
    env = os.environ.copy()
    if env.get("MODEL_TEST_PROMPT", "0") == "1":
        for _, _, _, name, _ in SPECS:
            if not env.get(name):
                try:
                    env[name] = getpass.getpass(name + " (hidden; Enter marks it missing): ")
                except EOFError:
                    env[name] = ""
    clean = sanitizer([env.get(spec[3], "") for spec in SPECS])
    report = {"schema_version": 1, "checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "defaults_verified_on": "2026-09-18", "scope": "native Responses API; not a Codex CLI or coding-quality benchmark", "providers": []}
    print("Testing all three providers over their native Responses APIs.", flush=True)
    print("Live API calls may incur charges. Keys and raw model/reasoning output are not logged.", flush=True)
    all_ok = True
    for provider, model_var, base_var, key_var, _ in SPECS:
        row = {"provider": provider, "model": clean(env.get(model_var, "")), "tests": [], "passed": False}
        report["providers"].append(row)
        print("\n%s | %s" % (provider.upper(), row["model"]), flush=True)
        try:
            key = env.get(key_var, "")
            if not key.strip():
                raise ProbeError(key_var + " is missing")
            if any(c in key for c in ("\r", "\n", "\x00")):
                raise ProbeError(key_var + " contains invalid header characters")
            client = Client(provider, env, key, clean)
            row["endpoint"] = client.base + "/responses"
        except (ProbeError, KeyError) as exc:
            row["error"] = clean(exc)
            row["tests"] = [{"name": name, "status": "FAIL", "detail": clean(exc)} for name in ("completion", "streaming", "tools")]
            print("  FAIL  " + row["error"], flush=True)
            all_ok = False
            continue
        for name in ("completion", "streaming", "tools"):
            started = time.monotonic()
            print("  RUN   " + name, flush=True)
            client.last_status = None
            try:
                detail = probe(client, name)
                result = {"name": name, "status": "PASS", "detail": detail}
            except (ProbeError, TimeoutError, socket.timeout, urllib.error.URLError, ValueError, OSError) as exc:
                result = {"name": name, "status": "FAIL", "detail": clean(exc)}
            except Exception as exc:
                # No traceback or potentially sensitive response objects in reports.
                result = {"name": name, "status": "FAIL", "detail": "unexpected response shape: " + type(exc).__name__}
            result["seconds"] = round(time.monotonic() - started, 3)
            result["http_status"] = client.last_status
            row["tests"].append(result)
            print("  %-5s %-11s %7.3fs  %s" % (result["status"], name, result["seconds"], result["detail"]), flush=True)
        row["served_models"] = sorted(client.models)
        row["usage"] = client.usage
        row["request_attempts"] = client.requests
        row["passed"] = all(test["status"] == "PASS" for test in row["tests"])
        all_ok = all_ok and row["passed"]
    report["passed"] = all_ok
    print("\nSUMMARY", flush=True)
    for row in report["providers"]:
        print("  %-9s %-24s %s" % (row["provider"], row["model"], "PASS" if row["passed"] else "FAIL"), flush=True)
    path = env.get("MODEL_TEST_JSON", "")
    if path:
        try:
            write_report(path, report)
            print("JSON report: " + clean(path), flush=True)
        except OSError as exc:
            print("Report write failed: " + clean(exc), file=sys.stderr)
            print("SPRITE_MODEL_TEST_RC=2", flush=True)
            return 2
    # The marker lets the host recover this result if Sprite loses its exit frame.
    print("SPRITE_MODEL_TEST_RC=%d" % (0 if all_ok else 1), flush=True)
    return 0 if all_ok else 1


if __name__ == "__main__":
    try:
        if len(sys.argv) == 4 and sys.argv[1] == "--validate-token":
            raise SystemExit(token_main(sys.argv[2], sys.argv[3]))
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nModel tests interrupted.", file=sys.stderr)
        raise SystemExit(130)
MODEL_TEST_PY
}

MODEL_TEST_ENV_NAMES=(
  DEEPSEEK_MODEL MINIMAX_MODEL KIMI_MODEL
  DEEPSEEK_BASE_URL MINIMAX_BASE_URL MOONSHOT_BASE_URL
  DEEPSEEK_REASONING_EFFORT MINIMAX_REASONING_EFFORT KIMI_REASONING_EFFORT
  MODEL_TEST_TIMEOUT MODEL_TEST_MAX_TOKENS MODEL_TEST_RETRIES MODEL_TEST_ALLOW_LOCALHOST
  MODEL_TEST_PROMPT KIMI_MIN_REQUEST_INTERVAL_MS
)

collect_model_test_keys() {
  local name value
  for name in DEEPSEEK_API_KEY MINIMAX_API_KEY MOONSHOT_API_KEY; do
    if [[ -z ${!name:-} && -t 0 ]]; then
      printf '  %s, hidden (Enter marks it missing): ' "$name"
      IFS= read -rs value || value=""
      printf '\n'
      printf -v "$name" '%s' "$value"
    fi
  done
}

run_model_tests_local() {
  local rc
  need_local python3
  collect_model_test_keys
  make_model_test_helper
  (
    export "${MODEL_TEST_ENV_NAMES[@]}" MODEL_TEST_JSON
    export DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-}" MINIMAX_API_KEY="${MINIMAX_API_KEY:-}" MOONSHOT_API_KEY="${MOONSHOT_API_KEY:-}"
    python3 "$MODEL_TEST_HELPER"
  ) && rc=0 || rc=$?
  return "$rc"
}

run_model_tests_sprite() {
  local name packed output cli_rc remote_rc
  local -a names=("${MODEL_TEST_ENV_NAMES[@]}")
  need_local sprite
  need_local python3
  pick_sprite
  collect_model_test_keys
  make_model_test_helper
  [[ -z $MODEL_TEST_JSON ]] || names+=(MODEL_TEST_JSON)
  for name in DEEPSEEK_API_KEY MINIMAX_API_KEY MOONSHOT_API_KEY; do
    [[ -z ${!name:-} ]] || names+=("$name")
  done
  packed=$(make_exec_env "${names[@]}")
  output=$(mktemp)
  cleanup_files+=("$output")
  note "test-only execution on $SPRITE_NAME; no agent/session/repository changes"
  note "Sprite environment transport is secret-equivalent and may appear in local process arguments"
  if run_remote_file "$MODEL_TEST_HELPER" "$packed" "" -- \
    python3 @SPRITE_PAYLOAD@ 2>&1 | tee "$output"; then
    cli_rc=0
  else
    cli_rc=$?
  fi
  remote_rc=$(sed -n 's/^SPRITE_MODEL_TEST_RC=\([012]\)$/\1/p' "$output" | tail -1)
  if [[ $remote_rc =~ ^[012]$ ]]; then
    return "$remote_rc"
  fi
  warn "remote test result was not confirmed (transport rc=$cli_rc); requests were not retried"
  return 1
}

maybe_test_models_before_run() {
  local choice="" should_test=0
  case "$MODEL_TEST_MODE" in
    never) return 0 ;;
    always) should_test=1 ;;
    ask)
      if [[ -t 0 ]]; then
        printf '\n  Test DeepSeek, MiniMax and Moonshot APIs from this host first? (billable) [y/N]: '
        IFS= read -r choice || true
        case "${choice,,}" in y|yes) should_test=1 ;; esac
      fi ;;
  esac
  if (( should_test )); then
    run_model_tests_local || die "one or more model API tests failed; bootstrap has not started"
  fi
  return 0
}

# Test-only dispatch precedes sprite/GitHub/Fly setup and every session action.
case "$RUN_MODE" in
  test-local) run_model_tests_local; exit $? ;;
  test-sprite) run_model_tests_sprite; exit $? ;;
esac

step "local prerequisites"
need_local sprite
need_local python3
need_local tar
local_network_advisory
maybe_test_models_before_run

step "choose coding agent"
choose_coding_agent
if [[ $AGENT_KIND == codex ]]; then
  step "choose Codex provider"
  choose_codex_provider
  AGENT_PROVIDER="$CODEX_PROVIDER"
  case "$CODEX_PROVIDER" in
    openai) note "OpenAI mode uses the installed Codex CLI directly" ;;
    deepseek) note "DeepSeek uses $DEEPSEEK_MODEL through native Responses with $DEEPSEEK_REASONING_EFFORT reasoning" ;;
    kimi) note "Moonshot uses $KIMI_MODEL through native Responses, including native web search" ;;
    minimax) note "MiniMax uses $MINIMAX_MODEL through its native Responses API" ;;
  esac
else
  CODEX_PROVIDER=none
  AGENT_PROVIDER=kimi-code
  TRANSPORT=native
  note "Kimi Code uses its official CLI login and model selection; run /login or /model inside the TUI"
fi

compute_state_file
STATE_HINT_LOADED=0
if load_state; then
  if [[ $(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$HOST_DIR") == "$STATE_HOST_DIR" ]]; then
    if sprite_in_current_inventory "$STATE_SPRITE_NAME"; then
      STATE_HINT_LOADED=1
      if [[ $STATE_SESSION_MANAGER == sprite-tty ]]; then note "saved resume hint: Sprite=$STATE_SPRITE_NAME native_session=${STATE_SESSION_ID:-unknown}"; elif [[ -n ${STATE_TMUX_SESSION:-} ]]; then note "saved legacy hint: Sprite=$STATE_SPRITE_NAME tmux=$STATE_TMUX_SESSION"; fi
    else warn "saved Sprite '$STATE_SPRITE_NAME' is not present in the current Sprite inventory"; note "discarding stale resume state"; clear_state; fi
  fi
fi

step "choose Sprite"
pick_sprite
note "selected Sprite: $SPRITE_NAME"
note "one-Sprite mode: every setup, heartbeat, native TTY, and agent command targets only $SPRITE_NAME"
project_short=$(python3 - "$HOST_DIR" <<'PY'
import hashlib,os,sys
print(hashlib.sha256(os.path.realpath(sys.argv[1]).encode()).hexdigest()[:8])
PY
)
if [[ $AGENT_KIND == codex ]]; then
  SESSION_TAG="sprite-codex-native-${project_short}"
  PEER_SESSION_TAG="sprite-kimi-code-native-${project_short}"
  LEGACY_TMUX_SESSION="sprite-codex-${project_short}"
else
  SESSION_TAG="sprite-kimi-code-native-${project_short}"
  PEER_SESSION_TAG="sprite-codex-native-${project_short}"
  LEGACY_TMUX_SESSION=""
fi
TASK_NAME="$SESSION_TAG"
CURRENT_SESSION_ID=""

# Validate the authoritative native session inventory before deciding whether a
# session exists. API/framing failure must never be interpreted as "zero sessions".
_NATIVE_INVENTORY=$(get_sessions_json)
if [[ -z $_NATIVE_INVENTORY ]] || ! sessions_inventory_valid "$_NATIVE_INVENTORY"; then
  die "could not validate the Sprite /exec session inventory; refusing to infer that no $AGENT_LABEL session exists"
fi

# The Codex update choice must happen before choose_live_native_session(), whose
# successful attachment exits this bootstrap. This preserves the fast resume path
# while still making the latest-version option available on every Codex run.
if [[ $AGENT_KIND == codex ]]; then
  offer_codex_update_before_run "$_NATIVE_INVENTORY"
fi

SHARED_PEER_LIVE=0
PEER_SESSION_ID=""
_peer_row=$(native_session_rows "$_NATIVE_INVENTORY" "$PEER_SESSION_TAG" "" "" | sed -n '1p')
if [[ -n $_peer_row ]]; then
  IFS=$'\t' read -r _ PEER_SESSION_ID _ _ _ <<<"$_peer_row"
  SHARED_PEER_LIVE=1
  warn "a peer coding agent is already live on this Sprite (session $PEER_SESSION_ID)"
  note "the peer uses tag $PEER_SESSION_TAG; this $AGENT_LABEL run uses $SESSION_TAG"
fi

if [[ $FORCE_NEW_SESSION == 1 ]]; then
  force_replace_native_sessions "$SESSION_TAG"
else
  _saved_sid=""; _saved_workdir=""
  if (( STATE_HINT_LOADED )) && [[ $STATE_SPRITE_NAME == "$SPRITE_NAME" && $STATE_SESSION_MANAGER == sprite-tty ]]; then
    _saved_sid=${STATE_SESSION_ID:-}
    _saved_workdir=${STATE_REMOTE_WORKDIR:-}
  fi
  if choose_live_native_session "$SESSION_TAG" "$_saved_sid" "$_saved_workdir"; then
    _native_choice_rc=0
  else
    _native_choice_rc=$?
  fi
  case $_native_choice_rc in
    0) exit 0 ;;  # existing native session was attached; attachment lifecycle ended
    1) ;;         # no managed native session exists; continue toward a new run
    *) exit "$_native_choice_rc" ;;
  esac
fi

if [[ $AGENT_KIND == codex ]] && legacy_tmux_guard "$LEGACY_TMUX_SESSION"; then
  _legacy_rc=0
else
  _legacy_rc=$?
fi
if [[ $AGENT_KIND == codex ]] && (( _legacy_rc == 0 )); then exit 0; fi

if [[ $AGENT_KIND == kimi-code ]]; then
  choose_kimi_code_approval_mode
fi
prompt_run_limit

step "target repository and Fly app"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-$(detect_github_repo || true)}"
if [[ -n $GITHUB_REPOSITORY ]]; then
  note "GitHub repository detected: $GITHUB_REPOSITORY"
else
  printf '  GitHub repository (OWNER/REPO): '
  IFS= read -r GITHUB_REPOSITORY || true
fi
[[ $GITHUB_REPOSITORY =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || die "GitHub repository must be OWNER/REPO"
note "use a fine-grained PAT limited to $GITHUB_REPOSITORY with Contents: read and write"

FLY_APP="${FLY_APP:-$(detect_fly_app || true)}"
if [[ -n $FLY_APP ]]; then
  note "Fly app detected: $FLY_APP"
else
  printf '  Fly.io app name: '
  IFS= read -r FLY_APP || true
fi
[[ $FLY_APP =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "invalid Fly.io app name"
note "use an app-scoped Fly deploy token for $FLY_APP, preferably with a short expiry"

step "connect to Sprite"
# This is the first real exec to the Sprite in the run. It is bounded and uses
# transport fallback. Capture the sanitized successful response to a file rather
# than a Bash variable. The same response is then used to determine REMOTE_HOME:
# do NOT perform a second exec merely to rediscover information we already have.
CONNECT_INFO_FILE=$(mktemp)
cleanup_files+=("$CONNECT_INFO_FILE")
_connected=0
for (( _attempt=1; _attempt<=SPRITE_CONNECT_TRIES; _attempt++ )); do
  : >"$CONNECT_INFO_FILE"
  note "connection attempt $_attempt/$SPRITE_CONNECT_TRIES (up to ${SPRITE_CONTROL_TIMEOUT}s per transport)"
  if control_exec_limited "$SPRITE_CONTROL_TIMEOUT" -- bash -lc \
       'printf "       host=%s user=%s home=%s\n" "$(hostname)" "$(whoami)" "$HOME"' \
       >"$CONNECT_INFO_FILE"; then
    cat "$CONNECT_INFO_FILE"
    _connected=1
    break
  fi
  # Preserve any useful stdout the remote command produced before a framing or
  # transport failure. The helper has already stripped NUL transport noise.
  [[ ! -s $CONNECT_INFO_FILE ]] || sed 's/^/       probe-output: /' "$CONNECT_INFO_FILE"
  warn "attempt $_attempt did not complete through an available control transport"
  (( _attempt < SPRITE_CONNECT_TRIES )) && sleep 3
done
if (( _connected != 1 )); then
  warn "could not execute a bounded non-TTY control command on Sprite '$SPRITE_NAME'"
  note "the management plane may still report the Sprite as running"
  note "if an older detachable TTY exists, rerun and choose it from the existing-session recovery menu before credentials"
  die "Sprite exec/control path is unreachable"
fi

# Parse HOME from the exact response that already proved the Sprite exec path
# works. This avoids v30's redundant HOME probe, which could independently hit a
# flaky transport and falsely fail immediately after a successful connection.
REMOTE_HOME=$(sed -n 's/.* home=\([^[:space:]]*\).*/\1/p' "$CONNECT_INFO_FILE" | tail -1)
if [[ $REMOTE_HOME != /* ]]; then
  warn "successful Sprite probe did not contain a parseable absolute home directory"
  note "captured probe follows:"
  sed 's/^/       /' "$CONNECT_INFO_FILE" >&2 || true
  die "could not determine the Sprite home directory from the successful connection probe"
fi

# With control exec now proven healthy, make the legacy duplicate guard
# definitive before workspace setup or a new native Codex session proceeds.
if [[ $AGENT_KIND == codex ]] && legacy_tmux_guard "$LEGACY_TMUX_SESSION"; then
  _legacy_rc=0
else
  _legacy_rc=$?
fi
if [[ $AGENT_KIND == codex ]] && (( _legacy_rc == 0 )); then exit 0; fi
if [[ $AGENT_KIND == codex ]] && (( _legacy_rc == 2 )); then die "legacy tmux state is ambiguous after a successful control connection; refusing to risk a duplicate Codex"; fi

step "current Sprite task holds"
control_exec_limited "$SPRITE_CONTROL_TIMEOUT" -- bash -lc '
set -uo pipefail
raw=$(curl -sS --max-time 8 --unix-socket /.sprite/api.sock http://sprite/v1/tasks 2>/dev/null || true)
if [[ -z $raw ]]; then
  echo "       Tasks API could not be read"
  exit 0
fi
python3 - "$raw" <<"PYTASKS"
import json,sys
try: d=json.loads(sys.argv[1])
except Exception:
    print("       raw Tasks API: "+sys.argv[1][:500]); raise SystemExit
tasks=d.get("tasks",[]) if isinstance(d,dict) else []
if not tasks:
    print("       no active Tasks API holds")
else:
    print("       active Tasks API holds:")
    for t in tasks:
        print("         %-32s expires_at=%s" % (str(t.get("name","?")), str(t.get("expires_at","?"))))
PYTASKS
' || note "task holds could not be listed within 30s (non-fatal); continuing"

base_name=$(basename "$HOST_DIR")
safe_name=$(printf '%s' "$base_name" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
[[ -n $safe_name ]] || safe_name=workspace
REMOTE_WORKDIR="${SPRITE_WORKDIR:-$REMOTE_HOME/workspaces/$safe_name}"
[[ $REMOTE_WORKDIR == /* ]] || die "SPRITE_WORKDIR must be an absolute path on the Sprite"
note "remote workspace: $REMOTE_WORKDIR"

SHARED_REUSE_ACTIVE=0
PEER_REMOTE_WORKDIR=""
if (( SHARED_PEER_LIVE == 1 )); then
  PEER_REMOTE_WORKDIR=$(control_exec_limited 10 -- bash -lc \
    'cat "$HOME/.local/state/sprite-codex/workdir-$1" 2>/dev/null || true' _ "$PEER_SESSION_TAG" 2>/dev/null || true)
fi
case "$SHARED_WORKSPACE_MODE" in
  reuse) SHARED_REUSE_ACTIVE=1 ;;
  sync) SHARED_REUSE_ACTIVE=0 ;;
  auto)
    if (( SHARED_PEER_LIVE == 1 )) && [[ -z $PEER_REMOTE_WORKDIR || $PEER_REMOTE_WORKDIR == "$REMOTE_WORKDIR" ]]; then
      SHARED_REUSE_ACTIVE=1
    fi
    ;;
esac
if (( SHARED_PEER_LIVE == 1 )); then
  if [[ -n $PEER_REMOTE_WORKDIR && $PEER_REMOTE_WORKDIR != "$REMOTE_WORKDIR" ]]; then
    warn "the live peer reports a different workspace: $PEER_REMOTE_WORKDIR"
  elif (( SHARED_REUSE_ACTIVE == 1 )); then
    warn "shared-workspace reuse is active: setup will not fetch, overlay, upload, commit, or push repository files"
    note "Codex and Kimi Code may now edit the same working tree; give them non-overlapping tasks and inspect git status frequently"
  else
    warn "SHARED_WORKSPACE_MODE=sync permits repository synchronization while the peer agent is live"
    note "this can overwrite or commit a peer's in-progress files; use only when intentional"
  fi
fi

step "prepare Sprite tools and workspace"
setup_file=$(make_remote_setup)
cleanup_files+=("$setup_file")
note "using a fresh private transfer directory; existing sessions and old helper files are left alone"
run_remote_file "$setup_file" "" "" -- \
  bash @SPRITE_PAYLOAD@ "$REMOTE_WORKDIR" "$MIN_CODEX_VERSION" "$CODEX_PROVIDER" "$AGENT_KIND" \
  || die "Sprite tool setup failed"
ok "Sprite tools ready"

# If the early optional update could not run because base tools were missing or a
# transport failed, make one deliberate retry now that npm/node have been checked.
# This path is reached only when no existing session attachment already exited.
if [[ $AGENT_KIND == codex && $CODEX_UPDATE_REQUESTED == 1 && $CODEX_UPDATE_COMPLETED != 1 ]]; then
  step "retry requested Codex update after Sprite tool setup"
  if ! run_codex_latest_update; then
    warn "the requested latest-version update is still unavailable; continuing with the verified installed Codex"
  fi
fi

collect_validated_credentials

step "prepare process-scoped GitHub and Fly.io environment"
GH_TOKEN="$GITHUB_PAT"
GITHUB_TOKEN="$GITHUB_PAT"
GH_REPO="$GITHUB_REPOSITORY"
GH_HOST="github.com"
GH_PROMPT_DISABLED="1"
GIT_TERMINAL_PROMPT="0"
FLY_ACCESS_TOKEN="$FLY_API_TOKEN"
GITHUB_ENV=$(make_exec_env GH_TOKEN GITHUB_TOKEN GITHUB_REPOSITORY GH_REPO GH_HOST GH_PROMPT_DISABLED GIT_TERMINAL_PROMPT)
FLY_ENV=$(make_exec_env FLY_API_TOKEN FLY_ACCESS_TOKEN FLY_APP)
warn "credentials will be process-scoped and will not be persisted on the Sprite"
note "credentials are JSON/hex encoded to survive commas and newlines in sprite exec --env"
note "the encoded value remains secret-equivalent and may briefly appear in local process arguments"

step "configure and verify GitHub repository in the Sprite"
if (( SHARED_REUSE_ACTIVE == 1 )); then
  SHARED_REPO_CHECK=$(sx_env "$GITHUB_ENV" -- bash -lc '
set -Eeuo pipefail
workdir=$1
expected=$2
git -C "$workdir" rev-parse --is-inside-work-tree >/dev/null
origin=$(git -C "$workdir" remote get-url origin)
normalized=${origin#https://github.com/}; normalized=${normalized#git@github.com:}; normalized=${normalized%.git}
[[ $normalized == "$expected" ]] || { echo "origin mismatch: expected $expected, found $origin" >&2; exit 1; }
GIT_TERMINAL_PROMPT=0 git -C "$workdir" ls-remote --exit-code origin HEAD >/dev/null
printf "shared_origin=%s\n" "$origin"
printf "shared_branch=%s\n" "$(git -C "$workdir" branch --show-current)"
' _ "$REMOTE_WORKDIR" "$GITHUB_REPOSITORY" 2>&1) || die "shared Sprite repository verification failed: $SHARED_REPO_CHECK"
  printf '%s\n' "$SHARED_REPO_CHECK"
  ok "reused the existing GitHub-backed working tree without synchronizing repository files"
else
  run_github_bootstrap "$GITHUB_ENV" || die "GitHub repository setup failed"
  ok "normal git fetch, commit, and push are configured for $GITHUB_REPOSITORY"
fi
note "$AGENT_LABEL should use the HTTPS origin directly; no Sprites GitHub gateway is required"

# GitHub and Fly have already passed mandatory in-Sprite validation.
# Do not repeat the old unredacted Fly CLI diagnostic or accept a stale alias.
assert_token_validation_gate

if [[ $AGENT_KIND == kimi-code ]]; then
  TRANSPORT=native
  ALL_CREDENTIAL_ENV=$(make_exec_env GH_TOKEN GITHUB_TOKEN GITHUB_REPOSITORY GH_REPO GH_HOST GH_PROMPT_DISABLED GIT_TERMINAL_PROMPT FLY_API_TOKEN FLY_ACCESS_TOKEN FLY_APP)
  step "prepare official Kimi Code CLI"
  KIMI_CODE_VERSION=$(sprite exec "${ORG[@]}" -s "$SPRITE_NAME" -- \
    bash -lc 'export PATH="$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.fly/bin:$PATH"; "$HOME/.local/bin/sprite-kimi-code" --version; "$HOME/.local/bin/sprite-kimi-code" doctor' 2>&1) \
    || die "Kimi Code installation check failed: $KIMI_CODE_VERSION"
  printf '%s\n' "$KIMI_CODE_VERSION"
  ok "official Kimi Code CLI is installed"
  note "authentication remains in Kimi Code's standard login flow; choose OAuth or Kimi Platform API key with /login"
elif [[ $CODEX_PROVIDER == deepseek || $CODEX_PROVIDER == minimax || $CODEX_PROVIDER == kimi ]]; then
  TRANSPORT=native-responses
  case "$CODEX_PROVIDER" in
    deepseek)
      SELECTED_MODEL=$DEEPSEEK_MODEL; SELECTED_BASE=$DEEPSEEK_BASE_URL
      SELECTED_CONTEXT=$DEEPSEEK_CONTEXT_WINDOW; SELECTED_EFFORT=$DEEPSEEK_REASONING_EFFORT
      SELECTED_KEY=DEEPSEEK_API_KEY; SELECTED_ACCESS=$CODEX_DEEPSEEK_ACCESS ;;
    minimax)
      SELECTED_MODEL=$MINIMAX_MODEL; SELECTED_BASE=$MINIMAX_BASE_URL
      SELECTED_CONTEXT=$MINIMAX_CONTEXT_WINDOW; SELECTED_EFFORT=$MINIMAX_REASONING_EFFORT
      SELECTED_KEY=MINIMAX_API_KEY; SELECTED_ACCESS=$CODEX_MINIMAX_ACCESS ;;
    kimi)
      SELECTED_MODEL=$KIMI_MODEL; SELECTED_BASE=$MOONSHOT_BASE_URL
      SELECTED_CONTEXT=$KIMI_CONTEXT_WINDOW; SELECTED_EFFORT=$KIMI_REASONING_EFFORT
      SELECTED_KEY=MOONSHOT_API_KEY; SELECTED_ACCESS=$CODEX_MOONSHOT_ACCESS ;;
  esac
  step "$CODEX_PROVIDER credential"
  note "$SELECTED_KEY was validated before repository setup"
  ALL_CREDENTIAL_ENV=$(build_codex_credential_env "$SELECTED_KEY")
  if [[ $SELECTED_ACCESS == 1 ]]; then
    warn "the selected provider key is also exposed to Codex-run experiment processes for this run"
  else
    note "the selected key authenticates Codex but remains excluded from Codex shell/tools"
  fi
  step "configure $CODEX_PROVIDER native Responses provider"
  make_native_configurator
  run_remote_file "$NATIVE_CONFIGURATOR" "" "" -- \
    python3 @SPRITE_PAYLOAD@ "$REMOTE_WORKDIR" "$CODEX_PROVIDER" \
      "$SELECTED_MODEL" "$SELECTED_BASE" "$SELECTED_CONTEXT" "$SELECTED_EFFORT" \
    || die "native provider configuration failed"
  ok "Codex profile sprite-$CODEX_PROVIDER configured for $SELECTED_MODEL"
else
  TRANSPORT=normal
  ALL_CREDENTIAL_ENV=$(build_codex_credential_env)

  step "configure normal OpenAI Codex launcher"
  openai_launcher=$(make_openai_launcher)
  cleanup_files+=("$openai_launcher")
  run_remote_file "$openai_launcher" "" "" -- \
    bash @SPRITE_PAYLOAD@ "$REMOTE_WORKDIR" \
    || die "could not configure the normal OpenAI Codex launcher"
  ok "OpenAI mode uses normal Codex provider/authentication with YOLO flags"

  step "check normal OpenAI Codex authentication"
  check_openai_auth
fi

if (( SHARED_REUSE_ACTIVE == 1 )); then
  step "preserve live shared workspace"
  note "shared-workspace reuse: skipping local workspace/ upload to $REMOTE_WORKDIR"
  note "skipping startup commit/push checks; existing repository files remain untouched by sync"
else
step "upload local workspace/ tree"
LOCAL_WORKSPACE_DIR="$HOST_DIR/workspace"
REMOTE_WORKSPACE_DIR="$REMOTE_WORKDIR/workspace"
if [[ ! -d $LOCAL_WORKSPACE_DIR ]]; then
  warn "no local workspace/ directory found at $LOCAL_WORKSPACE_DIR; nothing to upload"
else
  WORKSPACE_ARCHIVE=$(mktemp --suffix=.tar.gz 2>/dev/null || mktemp)
  cleanup_files+=("$WORKSPACE_ARCHIVE")

  # Archive the contents of workspace/, not the workspace directory itself, so
  # extraction maps ./workspace/foo -> <Sprite repo>/workspace/foo. This also
  # preserves hidden entries, nested directories, symlinks, and executable bits.
  tar -C "$LOCAL_WORKSPACE_DIR" -czf "$WORKSPACE_ARCHIVE" . \
    || die "could not archive local workspace/ directory"

  WORKSPACE_FILE_COUNT=$(find "$LOCAL_WORKSPACE_DIR" -type f | wc -l | tr -d ' ')
  WORKSPACE_ENTRY_COUNT=$(find "$LOCAL_WORKSPACE_DIR" -mindepth 1 | wc -l | tr -d ' ')
  note "local workspace/: ${WORKSPACE_FILE_COUNT:-0} regular file(s), ${WORKSPACE_ENTRY_COUNT:-0} total entr$( [[ ${WORKSPACE_ENTRY_COUNT:-0} == 1 ]] && echo y || echo ies )"
  note "destination: $REMOTE_WORKSPACE_DIR"

  run_remote_file "$WORKSPACE_ARCHIVE" "" "" -- bash -c '
set -Eeuo pipefail
dest=$1
archive=$2
mkdir -p "$dest"
tar -xzf "$archive" -C "$dest"
rm -f "$archive"
printf "       Sprite workspace/ now contains:\n"
find "$dest" -mindepth 1 -printf "         %P\n" | sort | sed -n "1,200p"
count=$(find "$dest" -type f | wc -l | tr -d " ")
printf "       regular files in Sprite workspace/: %s\n" "$count"
' _ "$REMOTE_WORKSPACE_DIR" @SPRITE_PAYLOAD@ \
    || die "workspace/ upload failed"
  ok "uploaded local workspace/ tree into $REMOTE_WORKSPACE_DIR"
fi

# This is deliberately the final repository mutation/check before any Codex
# preflight or interactive agent starts, so uploaded specification files are
# included in the comparison and optional push.
check_and_offer_repo_push
fi

assert_token_validation_gate

if [[ $AGENT_KIND == kimi-code ]]; then
  step "verify Kimi Code shared-workspace access"
  KIMI_CODE_CHECK=$(sx_env "$ALL_CREDENTIAL_ENV" -- bash -lc '
set -Eeuo pipefail
cd "$1"
"$HOME/.local/bin/sprite-kimi-code" --version
git remote get-url origin
git ls-remote --exit-code origin HEAD >/dev/null
"$HOME/.local/bin/sprite-auth-check" fly >/dev/null
printf "SPRITE_KIMI_CODE_OK\n"
' _ "$REMOTE_WORKDIR" 2>&1) || die "Kimi Code workspace preflight failed: $KIMI_CODE_CHECK"
  printf '%s\n' "$KIMI_CODE_CHECK"
  grep -q 'SPRITE_KIMI_CODE_OK' <<<"$KIMI_CODE_CHECK" || die "Kimi Code preflight marker was missing"
  ok "Kimi Code is installed in the same GitHub/Fly-enabled Sprite workspace"
  printf '\n%sReady.%s Sprite=%s workspace=%s agent=kimi-code approval=%s\n' \
    "$C_GREEN" "$C_RESET" "$SPRITE_NAME" "$REMOTE_WORKDIR" "$KIMI_CODE_APPROVAL_MODE"
  note "on first launch, use /login and choose Kimi Code OAuth or Kimi Platform API key"
elif [[ $CODEX_PROVIDER == deepseek || $CODEX_PROVIDER == minimax || $CODEX_PROVIDER == kimi ]]; then
  step "verify Codex -> $CODEX_PROVIDER / $SELECTED_MODEL"
  CODEX_CHECK_FILE=$(mktemp)
  cleanup_files+=("$CODEX_CHECK_FILE")
  note "native Responses agent preflight; hard timeout=${CODEX_PREFLIGHT_TIMEOUT}s"
  if ! sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
    --env "SPRITE_CODEX_ENV_HEX=$ALL_CREDENTIAL_ENV" --dir "$REMOTE_WORKDIR" -- \
    python3 -c "$ENV_EXEC_PY" bash -c '
set -Eeuo pipefail
provider=$1
limit=$2
command -v timeout >/dev/null || { echo "GNU timeout is required on the Sprite" >&2; exit 2; }
reply=$(mktemp)
cleanup_reply() { rm -f -- "$reply"; }
trap cleanup_reply EXIT
launcher="$HOME/.local/bin/sprite-codex-$provider"
timeout --kill-after=5 "$limit" "$launcher" exec --ephemeral --output-last-message "$reply" \
  "Run: git remote get-url origin && git ls-remote --exit-code origin HEAD. If both commands succeed, reply with exactly SPRITE_NATIVE_CODEX_OK and nothing else."
python3 - "$reply" <<"PYCHECK"
import sys
text = open(sys.argv[1], encoding="utf-8").read().strip()
if text != "SPRITE_NATIVE_CODEX_OK":
    raise SystemExit("Codex final response did not match the preflight marker")
print("SPRITE_NATIVE_CODEX_FINAL_VERIFIED")
PYCHECK
' _ "$CODEX_PROVIDER" "$CODEX_PREFLIGHT_TIMEOUT" 2>&1 | tee "$CODEX_CHECK_FILE"; then
    die "Codex could not complete the $CODEX_PROVIDER native Responses preflight"
  fi
  grep -qx 'SPRITE_NATIVE_CODEX_FINAL_VERIFIED' "$CODEX_CHECK_FILE" \
    || die "the verified final-response marker was missing"
  ok "Codex is connected to $SELECTED_MODEL and completed the GitHub-origin preflight"
  printf '\n%sReady.%s Sprite=%s workspace=%s provider=%s model=%s transport=native-responses\n' \
    "$C_GREEN" "$C_RESET" "$SPRITE_NAME" "$REMOTE_WORKDIR" "$CODEX_PROVIDER" "$SELECTED_MODEL"
else
  step "verify normal OpenAI Codex"
  CODEX_CHECK_FILE=$(mktemp)
  cleanup_files+=("$CODEX_CHECK_FILE")
  note "using the built-in OpenAI provider; hard timeout=${CODEX_PREFLIGHT_TIMEOUT:-180}s"

  OPENAI_PREFLIGHT_ATTEMPT=0
  while true; do
    OPENAI_PREFLIGHT_ATTEMPT=$((OPENAI_PREFLIGHT_ATTEMPT + 1))
    : >"$CODEX_CHECK_FILE"
    (( OPENAI_PREFLIGHT_ATTEMPT == 1 )) || note "OpenAI preflight retry #$((OPENAI_PREFLIGHT_ATTEMPT - 1))"

    if sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
      --env "SPRITE_CODEX_ENV_HEX=$ALL_CREDENTIAL_ENV,CODEX_PREFLIGHT_TIMEOUT=$CODEX_PREFLIGHT_TIMEOUT" \
      --dir "$REMOTE_WORKDIR" -- \
      python3 -c "$ENV_EXEC_PY" bash -lc '
set -o pipefail
run_check() {
  "$HOME/.local/bin/sprite-codex-openai" exec --ephemeral \
    "Run: git remote get-url origin && git ls-remote --exit-code origin HEAD. If both commands succeed, reply with exactly: SPRITE_CODEX_OPENAI_OK"
}
if command -v timeout >/dev/null 2>&1; then
  timeout "${CODEX_PREFLIGHT_TIMEOUT:-180}" bash -c "$(declare -f run_check); run_check"
else
  run_check
fi
' 2>&1 | tee "$CODEX_CHECK_FILE"; then
      OPENAI_PREFLIGHT_RC=0
    else
      OPENAI_PREFLIGHT_RC=$?
    fi

    CODEX_CHECK=$(cat "$CODEX_CHECK_FILE")
    if [[ $OPENAI_PREFLIGHT_RC == 0 ]] && grep -q 'SPRITE_CODEX_OPENAI_OK' <<<"$CODEX_CHECK"; then
      break
    fi

    if [[ $OPENAI_PREFLIGHT_RC == 0 ]]; then
      warn "Codex exited successfully, but the expected OpenAI preflight marker was missing"
    else
      warn "normal OpenAI Codex preflight exited with status $OPENAI_PREFLIGHT_RC"
    fi

    if ! openai_preflight_recovery "$CODEX_CHECK"; then
      die "normal OpenAI Codex preflight did not succeed and recovery was aborted"
    fi
  done

  ok "normal OpenAI Codex can access the GitHub origin"
  printf '\n%sReady.%s Sprite=%s workspace=%s provider=openai transport=normal\n' \
    "$C_GREEN" "$C_RESET" "$SPRITE_NAME" "$REMOTE_WORKDIR"
fi

if [[ $NO_AGENT_LAUNCH == 1 ]]; then
  note "NO_AGENT_LAUNCH=1; interactive $AGENT_LABEL launch skipped"
  note "no resumable session state was created"
  exit 0
fi

step "create native detachable Sprite TTY $AGENT_LABEL session"
if [[ $AGENT_KIND == codex ]]; then
  if [[ $CODEX_MODE_SELECTED != 1 ]]; then choose_codex_start_mode "creating a new native Sprite TTY Codex session"; fi
  AGENT_START_MODE=$CODEX_START_ACTION
else
  if [[ $KIMI_CODE_MODE_SELECTED != 1 ]]; then choose_kimi_code_start_mode "creating a new native Sprite TTY Kimi Code session"; fi
  if [[ $RESUME_KIMI_CODE_LAST == 1 ]]; then AGENT_START_MODE=resume; else AGENT_START_MODE=new; fi
fi
if [[ ! -t 0 || ! -t 1 ]]; then warn "no interactive terminal is attached, so $AGENT_LABEL cannot open its TUI"; note "rerun from a terminal or set NO_AGENT_LAUNCH=1"; exit 0; fi

SESSION_DEADLINE=$(( $(date +%s) + RUN_SECONDS ))
runner=$(make_session_runner)
cleanup_files+=("$runner")
NATIVE_ENTRY=$(mktemp)
cleanup_files+=("$NATIVE_ENTRY")
cat >"$NATIVE_ENTRY" <<'PYENTRY'
#!/usr/bin/env python3
import json, os, sys
if len(sys.argv) < 2:
    raise SystemExit("missing command")
encoded=os.environ.pop("SPRITE_CODEX_ENV_HEX", "")
if not encoded:
    raise SystemExit("missing encoded environment")
values=json.loads(bytes.fromhex(encoded).decode("utf-8"))
env=os.environ.copy()
# Once Codex is configured to pass intended *_TOKEN variables into shell tools,
# avoid accidentally exposing unrelated secret-looking variables inherited from
# the Sprite base environment. Explicit launcher values are the allow-list for
# such names; normal non-secret environment remains intact.
allowed={str(k) for k in values}
for key in list(env):
    upper=key.upper()
    if any(word in upper for word in ("TOKEN","SECRET","PASSWORD","API_KEY","PRIVATE_KEY")) and key not in allowed:
        env.pop(key, None)
env.update({str(k):str(v) for k,v in values.items()})
os.execvpe(sys.argv[1], sys.argv[1:], env)
PYENTRY
chmod 700 "$NATIVE_ENTRY"
install_native_entrypoints "$runner" "$NATIVE_ENTRY" \
  || die "could not install the native $AGENT_LABEL supervisor/entrypoint"

write_state
note "non-secret resume state saved at $STATE_FILE"
note "only one Sprite is used: $SPRITE_NAME"
note "$AGENT_LABEL will run directly in a native detachable Sprite TTY session"
note "managed tag: $SESSION_TAG"
note "the Tasks API uses a 5-minute hold refreshed every minute until the configured Tasks-hold deadline"
note "the native TTY session itself is also Sprite activity while it remains live"
note "detach cleanly with Ctrl+\\; there is no tmux prefix, mouse mode, or copy mode"
note "on a non-zero transport failure, the script reattaches to the same native session ID"

if start_native_agent_session "$REMOTE_ENTRY" "$REMOTE_RUNNER"; then
  launch_rc=0
else
  launch_rc=$?
fi
if [[ -n ${CURRENT_SESSION_ID:-} ]] && session_id_is_active "$CURRENT_SESSION_ID"; then
  note "$AGENT_LABEL is still running in native Sprite TTY session $CURRENT_SESSION_ID; resume state was kept"
  surface_native_hold_state "$SESSION_TAG" || true
else
  note "no live native managed TTY was confirmed after the attachment ended"
  if [[ $AGENT_KIND == codex ]]; then
    note "conversation files remain on the Sprite"
    note "if resume reported an active writer with no live process, rerun and choose 'Fork the most recent conversation'"
  else
    note "resume state is retained as a history hint; rerun and choose Kimi Code continue if it exited"
  fi
fi
exit "$launch_rc"
