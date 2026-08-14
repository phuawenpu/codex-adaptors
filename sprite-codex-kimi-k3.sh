#!/usr/bin/env bash
#
# sprite-codex-openai-deepseek-kimi-k3-resumable-github-yolo-v36.sh
#
# Interactive bootstrap for one sprites.dev Sprite that:
#   1. asks which Codex provider to use (OpenAI, DeepSeek V4 Pro, or Kimi K3);
#   2. asks which existing Sprite to use (it never creates/destroys a Sprite);
#   3. discovers live managed Codex sessions from the Sprite exec/session API;
#   4. reattaches directly to an existing native detachable Sprite TTY session
#      before asking for credentials or starting a second Codex process;
#   5. securely receives a repository-scoped GitHub PAT and app-scoped Fly token;
#   6. clones/repairs the selected GitHub repository as the Sprite workspace;
#   7. verifies Fly.io and configures the selected custom model provider;
#   8. recursively uploads host ./workspace/ into <Sprite repo>/workspace/;
#   9. compares/pushes repository changes according to the configured policy;
#  10. launches Codex directly inside a native `sprite exec --tty` session;
#  11. keeps a bounded Tasks API heartbeat while the Codex runner is alive;
#  12. preserves the native Sprite TTY session across local disconnects and
#      reattaches to the SAME session ID after non-zero transport failures.
#
# v32 introduced—and v34 retains—the tmux-free normal interactive path. Sprites TTY
# sessions are themselves detachable (`Ctrl+\\`) and reattachable through
# `sprite sessions attach <id>`. This avoids tmux mouse/copy-mode/key-binding
# interference and eliminates the nested Sprite-TTY -> tmux-client session layer.
# A small legacy tmux guard remains only to detect/attach a live v31-or-earlier
# managed tmux session so v34 never starts a duplicate Codex during migration.
#
# GitHub, Fly.io, DeepSeek, and Moonshot credentials are not persisted as credential files
# by this script. They are JSON-serialized, hex-encoded into one delimiter-safe
# `SPRITE_CODEX_ENV_HEX` value, decoded in the Sprite process, and inherited only
# by the managed runner/Codex process tree. OpenAI mode uses Codex's normal auth
# store on the Sprite; device-code login therefore persists standard Codex auth.
#
# Usage:
#   bash sprite-codex-kimi-k3.sh
#
# v36 makes Formula web search a bounded multi-round agent loop. K3 may request
# another batch of web_search calls after inspecting the first results; the
# gateway now continues until K3 returns a real final answer instead of exposing
# that intermediate planning message as a successful search result.
#
# v35 adds Kimi K3 through a loopback-only Moonshot gateway and the same pinned
# Responses adapter used for other non-Responses providers. The gateway owns the
# Moonshot key, enforces account-tier pacing, and provides Formula web search via
# `sprite-kimi-web-search`; Codex shell commands never receive the Moonshot key.
#
# Optional non-interactive overrides:
#   CODEX_PROVIDER=ask|openai|deepseek|kimi,
#   SPRITE_NAME, SPRITE_ORG, GITHUB_PAT, GITHUB_REPOSITORY,
#   FLY_API_TOKEN, FLY_APP, DEEPSEEK_API_KEY (DeepSeek mode only),
#   MOONSHOT_API_KEY (Kimi mode only),
#   SPRITE_WORKDIR, DEEPSEEK_TRANSPORT=auto|direct|bridge,
#   MOONSHOT_BASE_URL (default https://api.moonshot.ai/v1),
#   KIMI_MODEL (default kimi-k3), KIMI_FORMULA_URI,
#   KIMI_TIER, KIMI_MIN_REQUEST_INTERVAL_MS, KIMI_REQUEST_TIMEOUT,
#   KIMI_FORMULA_MAX_ROUNDS (default 10, allowed 2..20),
#   KIMI_MAX_COMPLETION_TOKENS, KIMI_BRIDGE_PORT, KIMI_GATEWAY_PORT,
#   MIN_CODEX_VERSION (default 0.144.0), CODEX_PREFLIGHT_TIMEOUT (default 180),
#   SPRITE_CONTROL_TIMEOUT (default 25), SPRITE_CONNECT_TRIES (default 3),
#   SPRITE_CONTROL_TRANSPORT=auto|websocket|http-post (default auto),
#   NO_CODEX_LAUNCH=1, SPRITE_RUN_HOURS (default prompt value 8),
#   FORCE_NEW_SESSION=1,
#   CODEX_START_MODE=ask|resume|new,
#   RESUME_CODEX_HISTORY=1 (legacy alias forcing resume),
#   SPRITE_SESSION_STATE (override local non-secret state path),
#   REPO_PUSH_MODE=ask|always|never, REPO_PUSH_COMMIT_MESSAGE,
#   STARTUP_REPO_PUSH_MODE=ask|always|never,
#   EXIT_AFTER_STARTUP_REPO_PUSH=1,
#   TTY_AUTO_REATTACH=1|0 (default 1),
#   TTY_REATTACH_ATTEMPTS (default 12; 0 means unlimited),
#   TTY_REATTACH_CONFIRM_TRIES (default 8), TTY_REATTACH_DELAY (default 3s).
#
# v34 changes (Codex shell-tool GitHub/Fly authentication):
#   a. Fixes OpenAI-mode credential visibility inside Codex shell tools. Codex
#      normally filters environment names containing KEY/SECRET/TOKEN, so the
#      parent Codex process could have GitHub/Fly credentials while agent-run
#      git/gh/fly commands did not. Both providers now opt into the intended
#      process environment while explicitly excluding provider API secrets.
#   b. Adds the documented Fly FLY_ACCESS_TOKEN alias plus GH_REPO/GH_HOST and
#      non-interactive Git/GitHub CLI hints to the managed environment.
#   c. Sanitizes inherited secret-looking Sprite variables before starting the
#      runner; only secrets explicitly supplied by this launcher survive.
#   d. Adds sprite-auth-check, which reports credential presence/capability only
#      and never prints raw credential values. The runner verifies GitHub and
#      Fly capability in the exact long-running environment before Codex starts.
#   e. Adds session-scoped Codex developer instructions: GitHub/Fly use normal
#      git/gh/fly process credentials here, not Sprites gateway connections.
#
# v33 changes (errexit correctness + native-session guard hardening):
#   a. Removes host-side `set +e` / `set -e` return-code capture. Bash shell
#      options are global inside functions, so v32's legacy migration guard could
#      re-enable errexit and then `return 1` for the normal "no legacy tmux"
#      result, terminating the entire script immediately after Sprite selection.
#   b. Native attach, existing-session selection, legacy migration, initial TTY
#      launch, and post-connect legacy checks now capture status with `if ...`;
#      none of these paths mutate the caller's errexit state.
#   c. An invalid existing-native-session menu selection is an error; it can no
#      longer fall through toward a new-session workflow.
#   d. Native /exec inventory is validated before session selection/replacement,
#      and is validated again immediately before launch. Unknown inventory is
#      never interpreted as "there are no managed sessions".
#
# v32 changes (native Sprite TTY session manager):
#   a. New Codex runs execute directly in a native detachable Sprite TTY. There
#      is no tmux server/client, mouse mode, tmux status line, or tmux copy mode.
#   b. Live session inventory comes from the Sprite exec API. The deterministic
#      runner tag `sprite-codex-native-<workspace-hash>` identifies managed runs;
#      saved JSON state is only a hint and never invents a live session.
#   c. Reattachment uses `sprite sessions attach <id>` in a throwaway local
#      Sprite context, so the user's project .sprite file is not modified.
#   d. Non-zero local transport failures automatically rediscover/reattach the
#      same active session. rc=0 is treated as an intentional/clean detach because
#      native Ctrl+\\ is handled locally and cannot write a remote detach marker.
#   e. The runner stores non-secret hold state on the Sprite filesystem instead
#      of in tmux metadata. Hard-cap release is durable and surfaced later when
#      control access is available. No background process writes tmux UI state.
#   f. v31-and-earlier deterministic tmux sessions are detected before a new
#      native session starts. A live legacy session is attachable but never killed
#      or replaced automatically unless FORCE_NEW_SESSION=1 is explicitly used.
#   g. `SPRITE_RUN_HOURS` now accurately means the Tasks API heartbeat duration.
#      A running native TTY session is itself Sprite activity, so releasing the
#      Tasks hold does not promise that the Sprite will immediately become idle.
#
# One-Sprite design: every remote operation targets exactly one selected Sprite.
# The script never invokes `sprite create` or `sprite destroy`.

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
umask 077

MODEL="deepseek-v4-pro"
PROFILE="deepseek-v4-pro"
BRIDGE_PORT="8787"
KIMI_MODEL="${KIMI_MODEL:-kimi-k3}"
KIMI_PROFILE="kimi-k3"
KIMI_BRIDGE_PORT="${KIMI_BRIDGE_PORT:-8788}"
KIMI_GATEWAY_PORT="${KIMI_GATEWAY_PORT:-8789}"
MOONSHOT_BASE_URL="${MOONSHOT_BASE_URL:-https://api.moonshot.ai/v1}"
KIMI_FORMULA_URI="${KIMI_FORMULA_URI:-moonshot/web-search:latest}"
KIMI_REQUEST_TIMEOUT="${KIMI_REQUEST_TIMEOUT:-180}"
KIMI_MAX_COMPLETION_TOKENS="${KIMI_MAX_COMPLETION_TOKENS:-32768}"
KIMI_FORMULA_MAX_ROUNDS="${KIMI_FORMULA_MAX_ROUNDS:-10}"
KIMI_TIER="${KIMI_TIER:-0}"
case "$KIMI_TIER" in
  0) _kimi_default_interval=20000 ;;
  1) _kimi_default_interval=300 ;;
  2) _kimi_default_interval=120 ;;
  *) _kimi_default_interval=100 ;;
esac
KIMI_MIN_REQUEST_INTERVAL_MS="${KIMI_MIN_REQUEST_INTERVAL_MS:-$_kimi_default_interval}"
[[ $KIMI_MODEL =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$ ]] || { echo "error: unsafe KIMI_MODEL" >&2; exit 2; }
[[ $MOONSHOT_BASE_URL =~ ^https?://[A-Za-z0-9._:-]+(/.*)?$ ]] || { echo "error: unsafe MOONSHOT_BASE_URL" >&2; exit 2; }
for _v in KIMI_REQUEST_TIMEOUT KIMI_MAX_COMPLETION_TOKENS KIMI_FORMULA_MAX_ROUNDS KIMI_TIER KIMI_MIN_REQUEST_INTERVAL_MS KIMI_BRIDGE_PORT KIMI_GATEWAY_PORT; do
  [[ ${!_v} =~ ^[0-9]+$ ]] || { echo "error: $_v must be a non-negative integer" >&2; exit 2; }
done
(( KIMI_REQUEST_TIMEOUT >= 1 )) || { echo "error: KIMI_REQUEST_TIMEOUT must be positive" >&2; exit 2; }
(( KIMI_MAX_COMPLETION_TOKENS >= 1024 )) || { echo "error: KIMI_MAX_COMPLETION_TOKENS must be at least 1024" >&2; exit 2; }
(( KIMI_FORMULA_MAX_ROUNDS >= 2 && KIMI_FORMULA_MAX_ROUNDS <= 20 )) || { echo "error: KIMI_FORMULA_MAX_ROUNDS must be 2..20" >&2; exit 2; }
(( KIMI_MIN_REQUEST_INTERVAL_MS >= 100 && KIMI_MIN_REQUEST_INTERVAL_MS <= 60000 )) || { echo "error: KIMI_MIN_REQUEST_INTERVAL_MS must be 100..60000" >&2; exit 2; }
(( KIMI_BRIDGE_PORT >= 1024 && KIMI_BRIDGE_PORT <= 65535 && KIMI_GATEWAY_PORT >= 1024 && KIMI_GATEWAY_PORT <= 65535 )) || { echo "error: KIMI ports must be in 1024..65535" >&2; exit 2; }
(( KIMI_BRIDGE_PORT != KIMI_GATEWAY_PORT && KIMI_BRIDGE_PORT != BRIDGE_PORT && KIMI_GATEWAY_PORT != BRIDGE_PORT )) || { echo "error: KIMI_BRIDGE_PORT, KIMI_GATEWAY_PORT, and DeepSeek port $BRIDGE_PORT must differ" >&2; exit 2; }
if (( KIMI_TIER == 0 && KIMI_MIN_REQUEST_INTERVAL_MS < 20000 )); then
  echo "warning: Tier 0 documents 3 RPM; an interval below 20000ms may receive 429 responses" >&2
fi
MIN_CODEX_VERSION="${MIN_CODEX_VERSION:-0.144.0}"
CODEX_PREFLIGHT_TIMEOUT="${CODEX_PREFLIGHT_TIMEOUT:-180}"
[[ $CODEX_PREFLIGHT_TIMEOUT =~ ^[1-9][0-9]*$ ]] || {
  echo "error: CODEX_PREFLIGHT_TIMEOUT must be a positive integer number of seconds" >&2
  exit 2
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
CODEX_PROVIDER="${CODEX_PROVIDER:-ask}"
case "$CODEX_PROVIDER" in
  ask|openai|deepseek|kimi) ;;
  *) echo "error: CODEX_PROVIDER must be ask, openai, deepseek, or kimi" >&2; exit 2 ;;
esac
TRANSPORT="${DEEPSEEK_TRANSPORT:-auto}"
NO_CODEX_LAUNCH="${NO_CODEX_LAUNCH:-0}"
FORCE_NEW_SESSION="${FORCE_NEW_SESSION:-0}"
CODEX_START_MODE="${CODEX_START_MODE:-ask}"
RESUME_CODEX_HISTORY="${RESUME_CODEX_HISTORY:-0}"
[[ $RESUME_CODEX_HISTORY == 0 || $RESUME_CODEX_HISTORY == 1 ]] || {
  echo "error: RESUME_CODEX_HISTORY must be 0 or 1" >&2
  exit 2
}
case "$CODEX_START_MODE" in
  ask|resume|new) ;;
  *) echo "error: CODEX_START_MODE must be ask, resume, or new" >&2; exit 2 ;;
esac
# Legacy compatibility: RESUME_CODEX_HISTORY=1 explicitly forces resume mode.
[[ $RESUME_CODEX_HISTORY == 1 ]] && CODEX_START_MODE=resume
# Set when the script decides how a newly created TTY should start Codex.
# DeepSeek Thinking remains enabled whenever DeepSeek is selected.
RESUME_CODEX_LAST=0
CODEX_MODE_SELECTED=0
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
  auto|direct|bridge) ;;
  *) echo "error: DEEPSEEK_TRANSPORT must be auto, direct, or bridge" >&2; exit 2 ;;
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
  esac

  if [[ ! -t 0 ]]; then
    CODEX_PROVIDER=deepseek
    note "no interactive input; defaulting to DeepSeek V4 Pro for backward compatibility"
    return 0
  fi

  printf '\n  Which provider should Codex use?\n'
  printf '    1) OpenAI - normal Codex provider/authentication\n'
  printf '    2) DeepSeek V4 Pro [default]\n'
  printf '    3) Kimi K3 (Moonshot API + Formula web search)\n'
  printf '  Select [1-3]: '
  IFS= read -r choice || true
  case "${choice,,}" in
    1|o|openai) CODEX_PROVIDER=openai ;;
    ''|2|d|deepseek) CODEX_PROVIDER=deepseek ;;
    3|k|kimi|kimi-k3) CODEX_PROVIDER=kimi ;;
    *)
      warn "invalid selection; defaulting to DeepSeek V4 Pro"
      CODEX_PROVIDER=deepseek
      ;;
  esac
  note "selected Codex provider: $CODEX_PROVIDER"
}

choose_codex_start_mode() {
  local context=${1:-"new Codex TTY"}
  local choice=""

  case "$CODEX_START_MODE" in
    resume)
      RESUME_CODEX_LAST=1
      CODEX_MODE_SELECTED=1
      note "$context: resuming the most recent Codex conversation"
      return 0
      ;;
    new)
      RESUME_CODEX_LAST=0
      CODEX_MODE_SELECTED=1
      note "$context: starting a new Codex conversation"
      return 0
      ;;
  esac

  if [[ ! -t 0 ]]; then
    warn "no interactive input is available; defaulting to a new Codex conversation"
    RESUME_CODEX_LAST=0
    CODEX_MODE_SELECTED=1
    return 0
  fi

  printf '\n  How should Codex start in the new TTY?\n'
  printf '    1) Resume the most recent Codex conversation\n'
  printf '    2) Start a new Codex conversation [default]\n'
  printf '  Select [1-2]: '
  IFS= read -r choice || true
  case "${choice,,}" in
    1|r|resume)
      RESUME_CODEX_LAST=1
      note "Codex will run: codex resume --last"
      if [[ $CODEX_PROVIDER == deepseek ]]; then
        warn "resume replays the previous chat history through the current DeepSeek bridge"
      elif [[ $CODEX_PROVIDER == kimi ]]; then
        warn "resume replays the previous chat history through the current Kimi K3 adapter"
      else
        note "resume uses the normal OpenAI Codex provider selected for this run"
      fi
      ;;
    ''|2|n|new)
      RESUME_CODEX_LAST=0
      note "Codex will start a new conversation in the existing repository workspace"
      note "repository files, Git state, and uncommitted work are preserved"
      ;;
    *)
      warn "invalid selection; starting a new Codex conversation"
      RESUME_CODEX_LAST=0
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
env.update({str(k): str(v) for k, v in values.items()})
os.execvpe(sys.argv[1], sys.argv[1:], env)'

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

export PATH="$HOME/.local/bin:$HOME/.fly/bin:$PATH"
mkdir -p "$HOME/.local/bin" "$HOME/.config/sprite-codex" "$HOME/.codex" "$WORKDIR"

as_root() {
  if [[ $(id -u) -eq 0 ]]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else return 1
  fi
}

required_pairs=("git:git" "curl:curl" "python3:python3" "npm:npm" "node:nodejs" "tar:tar")
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

for cmd in git curl python3 npm node tar; do
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
# npx is needed by the DeepSeek and Kimi Responses adapters. OpenAI mode uses
# the installed Codex CLI directly and does not install bridge-only tooling.
if [[ $CODEX_PROVIDER == deepseek || $CODEX_PROVIDER == kimi ]]; then
  if command -v npx >/dev/null 2>&1; then
    echo "       npx already installed; skipping"
  else
    echo "       npx is missing; installing it for the custom-provider adapter"
    npm install -g npx >/dev/null 2>&1 || npm install -g --prefix "$HOME/.local" npx >/dev/null
    hash -r
  fi
  command -v npx >/dev/null 2>&1 || { echo "npx installation failed" >&2; exit 44; }
else
  echo "       OpenAI mode selected; npx/CodeProxy adapter tooling is not required"
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
export PATH="$HOME/.local/bin:$HOME/.fly/bin:$PATH"
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

printf '       codex=%s\n' "$("$HOME/.local/bin/sprite-codex-cli" --version 2>/dev/null || echo unknown)"
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
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
    --file "$helper:/tmp/sprite-codex-github.sh" \
    --env "SPRITE_CODEX_ENV_HEX=$env_hex" \
    --dir "$REMOTE_WORKDIR" -- \
    python3 -c "$ENV_EXEC_PY" \
      bash /tmp/sprite-codex-github.sh "$REMOTE_WORKDIR" "$GITHUB_REPOSITORY"
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
  prompt_secret GITHUB_PAT "GitHub PAT for startup repository backup"
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

make_codex_configurator() {
  local f
  f=$(mktemp)
  cleanup_files+=("$f")
  cat >"$f" <<'PY'
#!/usr/bin/env python3
import json, os, re, stat, sys, time

workdir, transport, port = sys.argv[1:4]
home = os.path.expanduser("~")
codex_home = os.path.join(home, ".codex")
os.makedirs(codex_home, exist_ok=True)
base_cfg = os.path.join(codex_home, "config.toml")
profile_cfg = os.path.join(codex_home, "deepseek-v4-pro.config.toml")
catalog = os.path.join(codex_home, "models.json")
launcher = os.path.join(home, ".local", "bin", "sprite-codex-deepseek-v4-pro")

entry = {
    "slug": "deepseek-v4-pro",
    "prefer_websockets": False,
    "support_verbosity": True,
    "default_verbosity": "low",
    "apply_patch_tool_type": "freeform",
    "web_search_tool_type": "text",
    "input_modalities": ["text"],
    "supports_image_detail_original": False,
    "truncation_policy": {"mode": "tokens", "limit": 10000},
    "supports_parallel_tool_calls": True,
    "tool_mode": None,
    "multi_agent_version": "v2",
    "use_responses_lite": False,
    "include_skills_usage_instructions": False,
    "auto_review_model_override": None,
    "context_window": 1048576,
    "max_context_window": 1048576,
    "effective_context_window_percent": 95,
    "auto_compact_token_limit": None,
    "comp_hash": "3000",
    "reasoning_summary_format": "experimental",
    "default_reasoning_summary": "none",
    "display_name": "DeepSeek-V4-Pro",
    "description": "DeepSeek V4 Pro configured for Codex on a Sprite.",
    "default_reasoning_level": "high",
    "supported_reasoning_levels": [
        {"effort": "low", "description": "Fast responses with lighter reasoning"},
        {"effort": "high", "description": "Greater reasoning depth for complex work"},
        {"effort": "max", "description": "Maximum reasoning depth"},
    ],
    "shell_type": "shell_command",
    "visibility": "list",
    "minimal_client_version": "0.144.0",
    "supported_in_api": True,
    "availability_nux": None,
    "upgrade": None,
    "priority": 1,
    "base_instructions": "You are Codex, a coding agent working in the user's current workspace. The workspace is already connected to GitHub through its HTTPS origin and an environment-backed Git credential helper. Use ordinary git commands for fetch, pull, commit, and push. Do not ask the user to configure the Sprites GitHub gateway.",
    "model_messages": None,
    "experimental_supported_tools": [],
    "supports_search_tool": True,
    "default_service_tier": None,
    "supports_reasoning_summaries": True,
}
with open(catalog, "w") as fh:
    json.dump({"models": [entry]}, fh, indent=2)
    fh.write("\n")
os.chmod(catalog, 0o600)

old = ""
if os.path.exists(base_cfg):
    old = open(base_cfg, errors="replace").read()
    backup_dir = os.path.join(codex_home, "backup-sprite-codex")
    os.makedirs(backup_dir, exist_ok=True)
    backup = os.path.join(backup_dir, f"config.toml.{int(time.time())}.bak")
    open(backup, "w").write(old)

old = re.sub(r'(?ms)^# >>> sprite-deepseek-v4-pro >>>\n.*?^# <<< sprite-deepseek-v4-pro <<<\n?', '', old)
base_url = "https://api.deepseek.com" if transport == "direct" else f"http://127.0.0.1:{port}/v1"
q = json.dumps
auth_lines = 'env_key = "DEEPSEEK_API_KEY"\nrequires_openai_auth = false' if transport == "direct" else 'requires_openai_auth = false'
block = f'''# >>> sprite-deepseek-v4-pro >>>
[model_providers.sprite_deepseek_v4_pro]
name = "DeepSeek V4 Pro ({transport})"
base_url = {q(base_url)}
{auth_lines}
wire_api = "responses"
request_max_retries = 2
stream_max_retries = 2

[projects.{q(workdir)}]
trust_level = "trusted"
# <<< sprite-deepseek-v4-pro <<<
'''
with open(base_cfg, "w") as fh:
    fh.write(old.rstrip() + "\n\n" + block)
os.chmod(base_cfg, 0o600)

profile = f'''model = "deepseek-v4-pro"
model_provider = "sprite_deepseek_v4_pro"
model_catalog_json = {q(catalog)}
# Keep DeepSeek thinking enabled. Do not add a bridge-level thinking=disabled
# override; the compatibility recovery below starts a fresh chat rather than
# weakening the model.
model_reasoning_effort = "high"
model_context_window = 1048576
approval_policy = "never"
sandbox_mode = "danger-full-access"
web_search = "disabled"

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true
exclude = ["DEEPSEEK_API_KEY", "MOONSHOT_API_KEY", "OPENAI_API_KEY"]
'''
with open(profile_cfg, "w") as fh:
    fh.write(profile)
os.chmod(profile_cfg, 0o600)

launcher_text = f'''#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$HOME/.fly/bin:$PATH"
: "${{DEEPSEEK_API_KEY:?DEEPSEEK_API_KEY is required}}"
cd {q(workdir)}
started_bridge=0
bridge_pid=""
bridge_cfg=""
cleanup_bridge() {{
  if [[ "$started_bridge" == 1 && -n "$bridge_pid" ]]; then
    kill -- "-$bridge_pid" 2>/dev/null || kill "$bridge_pid" 2>/dev/null || true
  fi
  [[ -z "$bridge_cfg" ]] || rm -f "$bridge_cfg" 2>/dev/null || true
}}
trap cleanup_bridge EXIT INT TERM

if [[ {q(transport)} == bridge ]]; then
  pidfile="$HOME/.config/sprite-codex/bridge.pid"
  logfile="$HOME/.config/sprite-codex/bridge.log"
  bridge_tcp_ready() {{
    python3 - {port} <<'PYREADY'
import socket, sys
sock = socket.socket()
sock.settimeout(1.0)
try:
    sock.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PYREADY
  }}
  # A listening TCP port is not enough: older/wrong proxy builds may bind but
  # return 404 for the Responses route Codex needs. POST an intentionally
  # incomplete request; any HTTP response except 000/404 proves the route exists.
  bridge_responses_ready() {{
    local code
    code=$(curl -sS -o /tmp/sprite-codeproxy-route-check.json -w '%{{http_code}}' \
      --max-time 8 -X POST "http://127.0.0.1:{port}/v1/responses" \
      -H 'content-type: application/json' -d '{{}}' 2>/dev/null || true)
    [[ "$code" =~ ^[0-9]{{3}}$ && "$code" != 000 && "$code" != 404 ]]
  }}
  if [[ -f "$pidfile" ]]; then
    oldpid=$(cat "$pidfile" 2>/dev/null || true)
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null \
       && bridge_tcp_ready && bridge_responses_ready \
       && grep -q 'Upstream format: anthropic' "$logfile" 2>/dev/null \
       && grep -q 'Upstream URL: https://api.deepseek.com/anthropic/v1/messages' "$logfile" 2>/dev/null; then
      bridge_pid="$oldpid"
    else
      if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
        kill -- "-$oldpid" 2>/dev/null || kill "$oldpid" 2>/dev/null || true
        sleep 1
      fi
      rm -f "$pidfile"
    fi
  fi
  if [[ -z "$bridge_pid" ]]; then
    if bridge_tcp_ready; then
      echo "port {port} is already serving an untracked or incompatible process; refusing to send the DeepSeek key" >&2
      exit 71
    fi
    bridge_cfg=$(mktemp "$HOME/.config/sprite-codex/codeproxy.XXXXXX.json")
    python3 - "$bridge_cfg" <<'PYCFG'
import json, os, sys
cfg = {{
  "version": "1.0",
  "currentUpstream": "deepseek",
  "reasoningEffort": "high",
  "thinking": {{"type": "enabled", "budget_tokens": 32768}},
  "upstreams": {{
    "deepseek": {{
      "baseUrl": "https://api.deepseek.com/anthropic/v1/messages",
      "format": "anthropic",
      "apiKey": os.environ["DEEPSEEK_API_KEY"],
      "model": "deepseek-v4-pro",
      "apiVersion": "2023-06-01",
      "reasoningEffort": "high",
      "thinking": {{"type": "enabled", "budget_tokens": 32768}}
    }}
  }}
}}
with open(sys.argv[1], "w") as f: json.dump(cfg, f)
os.chmod(sys.argv[1], 0o600)
PYCFG
    # Pin the proxy version: an older cached build can bind successfully yet not
    # expose /v1/responses. The config itself explicitly declares Anthropic.
    setsid npx -y @codeproxy/cli@0.2.9 \
      --config "$bridge_cfg" \
      --host 127.0.0.1 --port {port} \
      >"$logfile" 2>&1 </dev/null &
    bridge_pid=$!
    printf '%s\n' "$bridge_pid" > "$pidfile"
    started_bridge=1
    for i in $(seq 1 60); do
      if bridge_tcp_ready; then
        if bridge_responses_ready; then
          echo "       DeepSeek Anthropic bridge is serving /v1/responses on 127.0.0.1:{port}" >&2
          break
        fi
        # A bound server returning 404 is the wrong proxy/version; fail now with
        # the route response and log rather than letting Codex retry mysteriously.
        if [[ $i -ge 5 ]]; then
          echo "DeepSeek bridge bound but /v1/responses is unavailable. Route response:" >&2
          cat /tmp/sprite-codeproxy-route-check.json >&2 2>/dev/null || true
          echo >&2
          echo "tail of $logfile:" >&2
          tail -30 "$logfile" >&2 || true
          exit 73
        fi
      fi
      if ! kill -0 "$bridge_pid" 2>/dev/null; then
        echo "DeepSeek bridge exited before binding; tail of $logfile:" >&2
        tail -30 "$logfile" >&2 || true
        exit 72
      fi
      if [[ $i == 60 ]]; then
        echo "DeepSeek bridge did not bind within 120 seconds; tail of $logfile:" >&2
        tail -30 "$logfile" >&2 || true
        exit 72
      fi
      sleep 2
    done
    rm -f "$bridge_cfg"
    bridge_cfg=""
  fi
  unset DEEPSEEK_API_KEY
fi

# YOLO mode is the Codex alias for disabling both approvals and sandboxing.
# Use the long form so the behavior is explicit in logs and process listings.
exec "$HOME/.local/bin/sprite-codex-cli"   --profile deepseek-v4-pro   -c shell_environment_policy.inherit=all   -c shell_environment_policy.ignore_default_excludes=true   -c 'shell_environment_policy.exclude=["DEEPSEEK_API_KEY","MOONSHOT_API_KEY","OPENAI_API_KEY"]'   -c 'developer_instructions="This Sprite intentionally authenticates GitHub and Fly.io through process-scoped environment credentials and the normal git, gh, and fly CLIs. Sprites gateway connections are not required for these services and /v1/gateway/list must not be used to decide whether GitHub or Fly access exists. Never print, echo, cat, or otherwise reveal token values. Verify GitHub capability with $HOME/.local/bin/sprite-auth-check github, git ls-remote, or gh api. Verify Fly capability with $HOME/.local/bin/sprite-auth-check fly or fly status. GH_TOKEN, GITHUB_TOKEN, FLY_API_TOKEN, and FLY_ACCESS_TOKEN are secrets intended for command authentication only."'   --dangerously-bypass-approvals-and-sandbox "$@"
'''
os.makedirs(os.path.dirname(launcher), exist_ok=True)
with open(launcher, "w") as fh:
    fh.write(launcher_text)
os.chmod(launcher, 0o700)

print(f"       transport={transport}")
if transport == "bridge":
    print("       upstream=DeepSeek Anthropic Messages /v1/messages (thinking preserved)")
print(f"       provider base_url={base_url}")
print(f"       profile={profile_cfg}")
print(f"       launcher={launcher}")
PY
  printf '%s' "$f"
}

make_kimi_configurator() {
  local f
  f=$(mktemp)
  cleanup_files+=("$f")
  cat >"$f" <<'KIMI_SETUP'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

WORKDIR=${1:?workdir required}
KIMI_MODEL=${2:?model required}
MOONSHOT_BASE_URL=${3:?base URL required}
KIMI_FORMULA_URI=${4:?formula URI required}
BRIDGE_PORT=${5:?bridge port required}
GATEWAY_PORT=${6:?gateway port required}
REQUEST_TIMEOUT=${7:?timeout required}
MAX_COMPLETION_TOKENS=${8:?max tokens required}
MIN_REQUEST_INTERVAL_MS=${9:?request interval required}
FORMULA_MAX_ROUNDS=${10:?formula max rounds required}

mkdir -p "$HOME/.local/bin" "$HOME/.config/sprite-codex" "$HOME/.codex"
RUNTIME_ENV="$HOME/.config/sprite-codex/kimi-k3-runtime.env"
{
  printf 'KIMI_WORKDIR=%q\n' "$WORKDIR"
  printf 'KIMI_MODEL=%q\n' "$KIMI_MODEL"
  printf 'MOONSHOT_BASE_URL=%q\n' "$MOONSHOT_BASE_URL"
  printf 'KIMI_FORMULA_URI=%q\n' "$KIMI_FORMULA_URI"
  printf 'KIMI_BRIDGE_PORT=%q\n' "$BRIDGE_PORT"
  printf 'KIMI_GATEWAY_PORT=%q\n' "$GATEWAY_PORT"
  printf 'KIMI_REQUEST_TIMEOUT=%q\n' "$REQUEST_TIMEOUT"
  printf 'KIMI_MAX_COMPLETION_TOKENS=%q\n' "$MAX_COMPLETION_TOKENS"
  printf 'KIMI_MIN_REQUEST_INTERVAL_MS=%q\n' "$MIN_REQUEST_INTERVAL_MS"
  printf 'KIMI_FORMULA_MAX_ROUNDS=%q\n' "$FORMULA_MAX_ROUNDS"
} > "$RUNTIME_ENV"
chmod 600 "$RUNTIME_ENV"

python3 - "$WORKDIR" "$KIMI_MODEL" "$BRIDGE_PORT" <<'PYCONFIG'
import json, os, re, sys, time
workdir, model, bridge_port = sys.argv[1:4]
home = os.path.expanduser("~")
codex_home = os.path.join(home, ".codex")
base_cfg = os.path.join(codex_home, "config.toml")
profile_cfg = os.path.join(codex_home, "kimi-k3.config.toml")
catalog = os.path.join(codex_home, "kimi-k3-models.json")
os.makedirs(codex_home, exist_ok=True)

entry = {
    "slug": model,
    "prefer_websockets": False,
    "support_verbosity": False,
    "default_verbosity": "low",
    "apply_patch_tool_type": "freeform",
    "web_search_tool_type": "text",
    "input_modalities": ["text"],
    "supports_image_detail_original": False,
    "truncation_policy": {"mode": "tokens", "limit": 10000},
    "supports_parallel_tool_calls": False,
    "tool_mode": None,
    "multi_agent_version": "v2",
    "use_responses_lite": False,
    "include_skills_usage_instructions": False,
    "auto_review_model_override": None,
    "context_window": 1048576,
    "max_context_window": 1048576,
    "effective_context_window_percent": 90,
    "auto_compact_token_limit": None,
    "comp_hash": "kimi-k3",
    "reasoning_summary_format": "experimental",
    "default_reasoning_summary": "none",
    "display_name": "Kimi K3",
    "description": "Kimi K3 through the Moonshot Chat Completions API and a local Responses adapter.",
    "default_reasoning_level": "high",
    "supported_reasoning_levels": [
        {"effort": "low", "description": "Lower latency"},
        {"effort": "high", "description": "Normal Kimi K3 thinking"},
    ],
    "shell_type": "shell_command",
    "visibility": "list",
    "minimal_client_version": "0.144.0",
    "supported_in_api": True,
    "availability_nux": None,
    "upgrade": None,
    "priority": 1,
    "base_instructions": (
        "You are Codex, a coding agent in the user's repository. GitHub and Fly.io "
        "are available through ordinary process-scoped command credentials. For fresh "
        "web information, run $HOME/.local/bin/sprite-kimi-web-search with one focused "
        "query; it uses Moonshot's Formula web-search channel. Never use $web_search."
    ),
    "model_messages": None,
    "experimental_supported_tools": [],
    "supports_search_tool": False,
    "default_service_tier": None,
    "supports_reasoning_summaries": False,
}
with open(catalog, "w") as fh:
    json.dump({"models": [entry]}, fh, indent=2)
    fh.write("\n")
os.chmod(catalog, 0o600)

old = ""
if os.path.exists(base_cfg):
    old = open(base_cfg, errors="replace").read()
    backup_dir = os.path.join(codex_home, "backup-sprite-codex")
    os.makedirs(backup_dir, exist_ok=True)
    backup = os.path.join(backup_dir, f"config.toml.{int(time.time())}.bak")
    open(backup, "w").write(old)
old = re.sub(r'(?ms)^# >>> sprite-kimi-k3 >>>\n.*?^# <<< sprite-kimi-k3 <<<\n?', '', old)
q = json.dumps
block = f'''# >>> sprite-kimi-k3 >>>
[model_providers.sprite_kimi_k3]
name = "Kimi K3 (Moonshot via local adapter)"
base_url = "http://127.0.0.1:{bridge_port}/v1"
wire_api = "responses"
requires_openai_auth = false
request_max_retries = 2
stream_max_retries = 2
stream_idle_timeout_ms = 300000

[projects.{q(workdir)}]
trust_level = "trusted"
# <<< sprite-kimi-k3 <<<
'''
with open(base_cfg, "w") as fh:
    fh.write(old.rstrip() + "\n\n" + block)
os.chmod(base_cfg, 0o600)

profile = f'''model = {q(model)}
model_provider = "sprite_kimi_k3"
model_catalog_json = {q(catalog)}
model_context_window = 1048576
approval_policy = "never"
sandbox_mode = "danger-full-access"
web_search = "disabled"

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true
exclude = ["MOONSHOT_API_KEY", "DEEPSEEK_API_KEY", "OPENAI_API_KEY"]
'''
with open(profile_cfg, "w") as fh:
    fh.write(profile)
os.chmod(profile_cfg, 0o600)
PYCONFIG

cat > "$HOME/.local/bin/sprite-kimi-gateway.py" <<'PYGATEWAY'
#!/usr/bin/env python3
import hashlib, json, os, sys, threading, time, urllib.error, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = os.environ.get("MOONSHOT_API_KEY", "")
BASE = os.environ.get("MOONSHOT_BASE_URL", "https://api.moonshot.ai/v1").rstrip("/")
MODEL = os.environ.get("KIMI_MODEL", "kimi-k3")
FORMULA = os.environ.get("KIMI_FORMULA_URI", "moonshot/web-search:latest")
TIMEOUT = int(os.environ.get("KIMI_REQUEST_TIMEOUT", "180"))
MAXTOK = int(os.environ.get("KIMI_MAX_COMPLETION_TOKENS", "32768"))
FORMULA_MAX_ROUNDS = int(os.environ.get("KIMI_FORMULA_MAX_ROUNDS", "10"))
INTERVAL = int(os.environ.get("KIMI_MIN_REQUEST_INTERVAL_MS", "20000")) / 1000.0
PORT = int(os.environ.get("KIMI_GATEWAY_PORT", "8789"))
if not KEY:
    raise SystemExit("MOONSHOT_API_KEY is required")

upstream_lock = threading.Lock()
last_start = [0.0]
formula_tools = [None]

def paced_start():
    wait = INTERVAL - (time.monotonic() - last_start[0])
    if wait > 0:
        time.sleep(wait)
    last_start[0] = time.monotonic()

def upstream_json(method, path, body=None):
    data = json.dumps(body, separators=(",", ":")).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + KEY)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with upstream_lock:
        paced_start()
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
                status = response.status
                raw = response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            status = exc.code
            raw = exc.read().decode("utf-8", "replace")
    try:
        parsed = json.loads(raw)
    except Exception:
        parsed = {"error": {"message": raw[:1000]}}
    if status < 200 or status >= 300:
        message = parsed.get("error", {}).get("message", parsed) if isinstance(parsed, dict) else parsed
        raise RuntimeError(f"Moonshot HTTP {status}: {message}")
    return parsed

def get_formula_tools():
    if formula_tools[0] is not None:
        return formula_tools[0]
    encoded = urllib.parse.quote(FORMULA, safe="")
    body = upstream_json("GET", f"/formulas/{encoded}/tools")
    tools = body.get("tools") if isinstance(body, dict) else body
    if isinstance(tools, dict):
        tools = tools.get("tools")
    if not isinstance(tools, list) or not tools:
        raise RuntimeError("Moonshot Formula returned no web-search tools")
    formula_tools[0] = tools
    return tools

def usage_totals(usages):
    totals = {}
    for usage in usages:
        if not isinstance(usage, dict):
            continue
        for key in ("prompt_tokens", "completion_tokens", "total_tokens", "cached_tokens"):
            value = usage.get(key)
            if isinstance(value, int) and not isinstance(value, bool):
                totals[key] = totals.get(key, 0) + value
    return totals

def formula_search(query, max_rounds=FORMULA_MAX_ROUNDS):
    tools = get_formula_tools()
    messages = [{"role": "user", "content": query + " Use the web_search tool and synthesize a sourced answer."}]
    encoded = urllib.parse.quote(FORMULA, safe="")
    search_calls = 0
    search_rounds = 0
    usages = []

    for round_number in range(1, max_rounds + 1):
        response = upstream_json("POST", "/chat/completions",
                                 {"model": MODEL, "messages": messages, "tools": tools,
                                  "max_completion_tokens": MAXTOK})
        choices = response.get("choices") or []
        if not choices or not isinstance(choices[0], dict):
            raise RuntimeError("Kimi Formula returned no completion choice")
        choice = choices[0]
        message = choice.get("message") or {}
        if not isinstance(message, dict):
            raise RuntimeError("Kimi Formula returned an invalid assistant message")
        finish_reason = choice.get("finish_reason")
        usages.append(response.get("usage"))
        calls = message.get("tool_calls") or []

        if calls:
            if not isinstance(calls, list):
                raise RuntimeError("Kimi Formula returned invalid tool_calls")
            if round_number == max_rounds:
                raise RuntimeError(
                    "Kimi Formula reached max_rounds=%d while requesting more web searches" % max_rounds)

            # K3 Preserved Thinking requires the complete assistant message,
            # including reasoning_content and every tool call, in the next turn.
            messages.append(message)
            search_rounds += 1
            sys.stderr.write("Formula round %d: executing %d web_search call(s)\n" %
                             (round_number, len(calls)))

            for call in calls:
                if not isinstance(call, dict) or not call.get("id"):
                    raise RuntimeError("Formula model returned a tool call without an id")
                fn = call.get("function") or {}
                if fn.get("name") != "web_search":
                    raise RuntimeError("Formula model requested unexpected tool: " + str(fn.get("name")))
                arguments = fn.get("arguments")
                if isinstance(arguments, dict):
                    arguments = json.dumps(arguments, separators=(",", ":"))
                if not isinstance(arguments, str):
                    raise RuntimeError("Formula web_search arguments must be JSON")
                try:
                    parsed_arguments = json.loads(arguments)
                except json.JSONDecodeError as exc:
                    raise RuntimeError("Formula web_search arguments are invalid JSON: %s" % exc)
                if not isinstance(parsed_arguments, dict):
                    raise RuntimeError("Formula web_search arguments must decode to an object")

                fiber = upstream_json("POST", f"/formulas/{encoded}/fibers",
                                      {"name": "web_search", "arguments": arguments})
                context = fiber.get("context") or {}
                output = context.get("output") or context.get("encrypted_output") or ""
                if fiber.get("status") != "succeeded" or not output:
                    raise RuntimeError("Formula fiber did not return usable output")
                messages.append({"role": "tool", "tool_call_id": call["id"],
                                 "name": "web_search", "content": output})
                search_calls += 1
            continue

        if finish_reason == "tool_calls":
            raise RuntimeError("Kimi Formula finished with tool_calls but supplied no tool calls")
        text = message.get("content") or ""
        if not isinstance(text, str) or not text.strip():
            raise RuntimeError("Kimi Formula returned no final content (finish_reason=%s)" % finish_reason)
        if finish_reason != "stop":
            raise RuntimeError("Kimi Formula did not complete its answer (finish_reason=%s)" % finish_reason)
        return {"content": text, "search_calls": search_calls,
                "search_rounds": search_rounds, "rounds": round_number,
                "finish_reason": finish_reason, "usage": response.get("usage"),
                "usage_total": usage_totals(usages)}

    raise RuntimeError("Kimi Formula exhausted its search loop without a final answer")

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "sprite-kimi-gateway/1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % args))

    def send_json(self, status, obj):
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"ok": True, "model": MODEL, "formula": FORMULA, "base": BASE,
                                 "formula_max_rounds": FORMULA_MAX_ROUNDS,
                                 "key_fingerprint": hashlib.sha256(KEY.encode()).hexdigest()[:16]})
        elif self.path in ("/", "/help"):
            self.send_json(200, {
                "service": "sprite-kimi-gateway",
                "formula_search": {
                    "method": "POST", "path": "/formula-search",
                    "body": {"query": "required string", "max_rounds": "optional integer, 2..%d" % FORMULA_MAX_ROUNDS},
                    "timeout_note": "Tier pacing and multi-round searches can take several minutes"
                },
                "health": {"method": "GET", "path": "/health"}
            })
        else:
            self.forward()

    def do_POST(self):
        if self.path == "/formula-search":
            try:
                length = int(self.headers.get("content-length", "0"))
                payload = json.loads(self.rfile.read(length) or b"{}")
                query = str(payload.get("query") or "").strip()
                if not query:
                    raise ValueError("query is required")
                requested_rounds = payload.get("max_rounds", payload.get("maxIterations", FORMULA_MAX_ROUNDS))
                if isinstance(requested_rounds, bool):
                    raise ValueError("max_rounds must be an integer")
                try:
                    requested_rounds = int(requested_rounds)
                except (TypeError, ValueError):
                    raise ValueError("max_rounds must be an integer")
                if requested_rounds < 2 or requested_rounds > FORMULA_MAX_ROUNDS:
                    raise ValueError("max_rounds must be 2..%d" % FORMULA_MAX_ROUNDS)
                self.send_json(200, formula_search(query, requested_rounds))
            except Exception as exc:
                self.send_json(502, {"error": {"message": str(exc)}})
        else:
            self.forward()

    def forward(self):
        if not self.path.startswith("/v1/"):
            self.send_json(404, {"error": {"message": "not found"}})
            return
        try:
            length = int(self.headers.get("content-length", "0"))
            data = self.rfile.read(length) if length else None
            if self.path.rstrip("/") == "/v1/chat/completions" and data:
                payload = json.loads(data)
                requested = payload.pop("max_tokens", 0) or payload.get("max_completion_tokens", 0) or 0
                payload["max_completion_tokens"] = max(int(requested), MAXTOK)
                data = json.dumps(payload, separators=(",", ":")).encode()
            # CodeProxy addresses this gateway as an OpenAI-style `/v1` root,
            # while BASE already includes Moonshot's `/v1` API prefix.
            upstream_path = self.path[3:] if self.path.startswith("/v1/") else self.path
            req = urllib.request.Request(BASE + upstream_path, data=data, method=self.command)
            req.add_header("Authorization", "Bearer " + KEY)
            for name in ("Content-Type", "Accept"):
                value = self.headers.get(name)
                if value:
                    req.add_header(name, value)
            with upstream_lock:
                paced_start()
                try:
                    response = urllib.request.urlopen(req, timeout=TIMEOUT)
                except urllib.error.HTTPError as exc:
                    response = exc
                self.send_response(response.status)
                content_type = response.headers.get("content-type")
                if content_type:
                    self.send_header("Content-Type", content_type)
                self.send_header("Connection", "close")
                self.end_headers()
                while True:
                    chunk = response.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
                response.close()
        except Exception as exc:
            if not self.wfile.closed:
                try:
                    self.send_json(502, {"error": {"message": str(exc)}})
                except Exception:
                    pass

ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
PYGATEWAY
chmod 700 "$HOME/.local/bin/sprite-kimi-gateway.py"

cat > "$HOME/.local/bin/sprite-kimi-web-search" <<'PYSEARCH'
#!/usr/bin/env python3
import json, os, sys, urllib.error, urllib.request
query = " ".join(sys.argv[1:]).strip()
if not query and not sys.stdin.isatty():
    query = sys.stdin.read().strip()
if not query:
    raise SystemExit("usage: sprite-kimi-web-search <focused query>")
port = os.environ.get("KIMI_GATEWAY_PORT", "8789")
request = urllib.request.Request(
    "http://127.0.0.1:%s/formula-search" % port,
    data=json.dumps({"query": query}).encode(), method="POST",
    headers={"content-type": "application/json"})
try:
    with urllib.request.urlopen(request, timeout=900) as response:
        body = json.load(response)
except urllib.error.HTTPError as exc:
    try:
        body = json.load(exc)
        message = body.get("error", {}).get("message", body)
    except Exception:
        message = exc.read().decode("utf-8", "replace")
    raise SystemExit("Kimi Formula search failed: %s" % message)
print(body.get("content") or "")
PYSEARCH
chmod 700 "$HOME/.local/bin/sprite-kimi-web-search"

cat > "$HOME/.local/bin/sprite-codex-kimi-k3" <<'KIMI_LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$HOME/.fly/bin:$PATH"
RUNTIME_ENV="$HOME/.config/sprite-codex/kimi-k3-runtime.env"
[[ -f $RUNTIME_ENV ]] || { echo "missing Kimi runtime configuration: $RUNTIME_ENV" >&2; exit 74; }
# shellcheck disable=SC1090
source "$RUNTIME_ENV"
: "${MOONSHOT_API_KEY:?MOONSHOT_API_KEY is required}"
export KIMI_MODEL KIMI_GATEWAY_PORT KIMI_REQUEST_TIMEOUT
cd "$KIMI_WORKDIR"

GATEWAY="$HOME/.local/bin/sprite-kimi-gateway.py"
GATEWAY_PIDFILE="$HOME/.config/sprite-codex/kimi-gateway.pid"
GATEWAY_LOG="$HOME/.config/sprite-codex/kimi-gateway.log"
BRIDGE_PIDFILE="$HOME/.config/sprite-codex/kimi-codeproxy.pid"
BRIDGE_LOG="$HOME/.config/sprite-codex/kimi-codeproxy.log"
started_gateway=0
started_bridge=0

tcp_ready() {
  python3 - "$1" <<'PYREADY'
import socket,sys
s=socket.socket(); s.settimeout(1)
try: s.connect(("127.0.0.1",int(sys.argv[1])))
except OSError: raise SystemExit(1)
finally: s.close()
PYREADY
}
gateway_ready() {
  local health
  health=$(curl -fsS --max-time 3 "http://127.0.0.1:$KIMI_GATEWAY_PORT/health" 2>/dev/null || true)
  python3 - "$health" "$KIMI_MODEL" "$KIMI_FORMULA_URI" "$MOONSHOT_BASE_URL" <<'PYHEALTH'
import hashlib,json,os,sys
try: d=json.loads(sys.argv[1])
except Exception: raise SystemExit(1)
fingerprint=hashlib.sha256(os.environ.get("MOONSHOT_API_KEY","").encode()).hexdigest()[:16]
raise SystemExit(0 if d.get("ok") and d.get("model")==sys.argv[2] and d.get("formula")==sys.argv[3] and d.get("base").rstrip("/")==sys.argv[4].rstrip("/") and d.get("key_fingerprint")==fingerprint else 1)
PYHEALTH
}
bridge_ready() {
  local pid=""
  [[ -f $BRIDGE_PIDFILE ]] && pid=$(cat "$BRIDGE_PIDFILE" 2>/dev/null || true)
  [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null \
    && tcp_ready "$KIMI_BRIDGE_PORT" \
    && grep -q 'Proxy listening on http://127.0.0.1:'"$KIMI_BRIDGE_PORT" "$BRIDGE_LOG" 2>/dev/null \
    && grep -q 'Upstream format: openai-chat' "$BRIDGE_LOG" 2>/dev/null \
    && grep -q 'Upstream URL: http://127.0.0.1:'"$KIMI_GATEWAY_PORT"'/v1' "$BRIDGE_LOG" 2>/dev/null
}
kill_managed() {
  local file=$1 pid=""
  [[ -f $file ]] && pid=$(cat "$file" 2>/dev/null || true)
  if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$file"
}
cleanup_started_services() {
  if [[ $started_bridge == 1 ]]; then started_bridge=0; kill_managed "$BRIDGE_PIDFILE"; fi
  if [[ $started_gateway == 1 ]]; then started_gateway=0; kill_managed "$GATEWAY_PIDFILE"; fi
}
trap cleanup_started_services EXIT
trap 'cleanup_started_services; exit 0' INT TERM

if ! gateway_ready; then
  kill_managed "$BRIDGE_PIDFILE"
  kill_managed "$GATEWAY_PIDFILE"
  tcp_ready "$KIMI_GATEWAY_PORT" && { echo "Kimi gateway port $KIMI_GATEWAY_PORT belongs to an incompatible process" >&2; exit 75; }
  setsid env \
    MOONSHOT_API_KEY="$MOONSHOT_API_KEY" MOONSHOT_BASE_URL="$MOONSHOT_BASE_URL" \
    KIMI_MODEL="$KIMI_MODEL" KIMI_FORMULA_URI="$KIMI_FORMULA_URI" \
    KIMI_GATEWAY_PORT="$KIMI_GATEWAY_PORT" KIMI_REQUEST_TIMEOUT="$KIMI_REQUEST_TIMEOUT" \
    KIMI_MAX_COMPLETION_TOKENS="$KIMI_MAX_COMPLETION_TOKENS" \
    KIMI_FORMULA_MAX_ROUNDS="$KIMI_FORMULA_MAX_ROUNDS" \
    KIMI_MIN_REQUEST_INTERVAL_MS="$KIMI_MIN_REQUEST_INTERVAL_MS" \
    python3 "$GATEWAY" >"$GATEWAY_LOG" 2>&1 </dev/null &
  gateway_pid=$!
  printf '%s\n' "$gateway_pid" > "$GATEWAY_PIDFILE"
  started_gateway=1
  for _ in $(seq 1 30); do gateway_ready && break; kill -0 "$gateway_pid" 2>/dev/null || break; sleep 1; done
  gateway_ready || { echo "Kimi gateway failed to start; log follows:" >&2; tail -30 "$GATEWAY_LOG" >&2 || true; exit 76; }
fi

if ! bridge_ready; then
  kill_managed "$BRIDGE_PIDFILE"
  tcp_ready "$KIMI_BRIDGE_PORT" && { echo "Kimi adapter port $KIMI_BRIDGE_PORT belongs to an incompatible process" >&2; exit 77; }
  bridge_cfg=$(mktemp "$HOME/.config/sprite-codex/kimi-codeproxy.XXXXXX.json")
  python3 - "$bridge_cfg" <<'PYPROXYCFG'
import json,os,sys
cfg={
  "version":"1.0", "currentUpstream":"kimi-k3",
  "reasoningEffort":"high", "timeoutMs":int(os.environ.get("KIMI_REQUEST_TIMEOUT","180"))*1000,
  "upstreams":{"kimi-k3":{
    "baseUrl":"http://127.0.0.1:%s/v1" % os.environ["KIMI_GATEWAY_PORT"],
    "format":"openai-chat", "apiKey":"local-kimi-gateway", "model":os.environ["KIMI_MODEL"]
  }}
}
with open(sys.argv[1],"w") as f: json.dump(cfg,f)
os.chmod(sys.argv[1],0o600)
PYPROXYCFG
  setsid npx -y @codeproxy/cli@0.2.9 --config "$bridge_cfg" \
    --host 127.0.0.1 --port "$KIMI_BRIDGE_PORT" >"$BRIDGE_LOG" 2>&1 </dev/null &
  bridge_pid=$!
  printf '%s\n' "$bridge_pid" > "$BRIDGE_PIDFILE"
  started_bridge=1
  for _ in $(seq 1 60); do bridge_ready && break; kill -0 "$bridge_pid" 2>/dev/null || break; sleep 2; done
  rm -f "$bridge_cfg"
  bridge_ready || { echo "Kimi Responses adapter failed to start; log follows:" >&2; tail -30 "$BRIDGE_LOG" >&2 || true; exit 78; }
fi

echo "       Kimi gateway: 127.0.0.1:$KIMI_GATEWAY_PORT (tier pacing + Formula search)" >&2
echo "       Responses adapter: 127.0.0.1:$KIMI_BRIDGE_PORT -> $KIMI_MODEL" >&2
unset MOONSHOT_API_KEY
export KIMI_GATEWAY_PORT
if "$HOME/.local/bin/sprite-codex-cli" \
    --profile kimi-k3 \
    -c shell_environment_policy.inherit=all \
    -c shell_environment_policy.ignore_default_excludes=true \
    -c 'shell_environment_policy.exclude=["MOONSHOT_API_KEY","DEEPSEEK_API_KEY","OPENAI_API_KEY"]' \
    -c 'developer_instructions="This Sprite authenticates GitHub and Fly.io through process-scoped environment credentials and normal git, gh, and fly commands. Never reveal token values. For current web information, run $HOME/.local/bin/sprite-kimi-web-search with one focused query; it uses the working moonshot/web-search:latest Formula channel. Never request or declare the broken builtin_function $web_search channel."' \
    --dangerously-bypass-approvals-and-sandbox "$@"; then
  codex_rc=0
else
  codex_rc=$?
fi
exit "$codex_rc"
KIMI_LAUNCHER
chmod 700 "$HOME/.local/bin/sprite-codex-kimi-k3"

printf '       model=%s\n' "$KIMI_MODEL"
printf '       provider=Kimi K3 via @codeproxy/cli Responses adapter\n'
printf '       Moonshot base=%s\n' "$MOONSHOT_BASE_URL"
printf '       Formula=%s (helper: %s)\n' "$KIMI_FORMULA_URI" "$HOME/.local/bin/sprite-kimi-web-search"
printf '       pacing=%sms between Moonshot request starts\n' "$MIN_REQUEST_INTERVAL_MS"
printf '       launcher=%s\n' "$HOME/.local/bin/sprite-codex-kimi-k3"
KIMI_SETUP
  printf '%s' "$f"
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
unset DEEPSEEK_API_KEY MOONSHOT_API_KEY
cd $(printf '%q' "$WORKDIR")
exec "\$HOME/.local/bin/sprite-codex-cli" \
  -c model_provider=openai \
  -c shell_environment_policy.inherit=all \
  -c shell_environment_policy.ignore_default_excludes=true \
  -c 'shell_environment_policy.exclude=["DEEPSEEK_API_KEY","MOONSHOT_API_KEY","OPENAI_API_KEY"]' \
  -c 'developer_instructions="This Sprite intentionally authenticates GitHub and Fly.io through process-scoped environment credentials and the normal git, gh, and fly CLIs. Sprites gateway connections are not required for these services and /v1/gateway/list must not be used to decide whether GitHub or Fly access exists. Never print, echo, cat, or otherwise reveal token values. Verify GitHub capability with $HOME/.local/bin/sprite-auth-check github, git ls-remote, or gh api. Verify Fly capability with $HOME/.local/bin/sprite-auth-check fly or fly status. GH_TOKEN, GITHUB_TOKEN, FLY_API_TOKEN, and FLY_ACCESS_TOKEN are secrets intended for command authentication only."' \
  --dangerously-bypass-approvals-and-sandbox "\$@"
EOF
chmod 700 "$HOME/.local/bin/sprite-codex-openai"
echo "       launcher=$HOME/.local/bin/sprite-codex-openai"
echo "       provider=built-in OpenAI Codex (no custom provider/profile)"
OPENAI_LAUNCHER
  printf '%s' "$f"
}

check_openai_auth() {
  local out rc
  out=$(run_limited 20 sprite exec "${ORG[@]}" -s "$SPRITE_NAME" -- bash -lc '
export PATH="$HOME/.local/bin:$PATH"
"$HOME/.local/bin/sprite-codex-cli" login status 2>&1
' 2>&1) && rc=0 || rc=$?
  if [[ $rc == 0 && $out == *"Logged in"* ]]; then
    printf '%s\n' "$out" | sed 's/^/       /'
    ok "normal OpenAI Codex authentication is already available on the Sprite"
    return 0
  fi

  if [[ $out == *"Not logged in"* || $out == *"not logged in"* ]]; then
    warn "Codex is not logged in to OpenAI on this Sprite"
    if [[ -t 0 && -t 1 ]]; then
      local ans=""
      printf '  Start normal Codex device-code login now? [Y/n]: '
      IFS= read -r ans || true
      case "${ans,,}" in
        n|no)
          note "skipping login; the OpenAI Codex preflight may fail until you authenticate"
          return 0
          ;;
      esac
      note "starting: codex login --device-auth"
      sprite exec "${ORG[@]}" -s "$SPRITE_NAME" --tty --no-port-forward -- \
        bash -lc 'export PATH="$HOME/.local/bin:$PATH"; exec "$HOME/.local/bin/sprite-codex-cli" login --device-auth' \
        || die "OpenAI Codex device-code login failed"
      out=$(run_limited 20 sprite exec "${ORG[@]}" -s "$SPRITE_NAME" -- bash -lc '
export PATH="$HOME/.local/bin:$PATH"
"$HOME/.local/bin/sprite-codex-cli" login status 2>&1
' 2>&1 || true)
      [[ $out == *"Logged in"* ]] || die "Codex still does not report an authenticated OpenAI session"
      printf '%s\n' "$out" | sed 's/^/       /'
      ok "OpenAI Codex login completed"
      return 0
    fi
    warn "no interactive terminal is available for device-code login"
    return 0
  fi

  warn "could not determine Codex login status; normal Codex will handle authentication when launched"
  [[ -z $out ]] || printf '%s\n' "$out" | sed 's/^/       /'
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
RESUME_LAST=${5:-0}
CODEX_PROVIDER=${6:-deepseek}

[[ $RUN_SECONDS =~ ^[0-9]+$ ]] && ((RUN_SECONDS > 0)) || { echo "invalid run duration: $RUN_SECONDS" >&2; exit 80; }
[[ $TASK_NAME =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid task name: $TASK_NAME" >&2; exit 81; }
[[ $SESSION_TAG =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid session tag: $SESSION_TAG" >&2; exit 85; }
[[ $RESUME_LAST == 0 || $RESUME_LAST == 1 ]] || { echo "invalid Codex resume mode: $RESUME_LAST" >&2; exit 83; }
case "$CODEX_PROVIDER" in openai|deepseek|kimi) ;; *) echo "invalid Codex provider: $CODEX_PROVIDER" >&2; exit 84 ;; esac

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
printf '%s\n' "$CODEX_PROVIDER" >"$PROVIDER_FILE"
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
      echo "Task '$TASK_NAME' is being released while Codex remains alive." >&2
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
echo "       detach without stopping Codex: Ctrl+\\"
echo "       reattach later with: sprite sessions attach <session-id>"
echo

cd "$WORKDIR"
case "$CODEX_PROVIDER" in
  openai) CODEX_LAUNCHER="$HOME/.local/bin/sprite-codex-openai" ;;
  deepseek) CODEX_LAUNCHER="$HOME/.local/bin/sprite-codex-deepseek-v4-pro" ;;
  kimi) CODEX_LAUNCHER="$HOME/.local/bin/sprite-codex-kimi-k3" ;;
esac
echo "       Codex provider: $CODEX_PROVIDER"

case "$CODEX_PROVIDER" in
  deepseek) [[ -n ${DEEPSEEK_API_KEY:-} ]] || { echo "DEEPSEEK_API_KEY is missing in the managed runner" >&2; exit 89; } ;;
  kimi) [[ -n ${MOONSHOT_API_KEY:-} ]] || { echo "MOONSHOT_API_KEY is missing in the managed runner" >&2; exit 90; } ;;
esac

# Verify the exact long-running runner environment without printing credential
# values. These checks catch any future regression between the outer bootstrap
# and the actual native TTY process before Codex starts.
for name in GH_TOKEN GITHUB_TOKEN FLY_API_TOKEN FLY_ACCESS_TOKEN; do
  if [[ -n ${!name:-} ]]; then
    echo "       credential env $name: present"
  else
    echo "credential env $name is missing in the managed Codex runner" >&2
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

resume_next=$RESUME_LAST
update_restarts=0
while :; do
  before_path=$(codex_path)
  before_version=$(codex_version)
  echo "       Codex executable before launch: ${before_path:-unknown} | ${before_version:-unknown}"

  set +e
  if [[ $resume_next == 1 ]]; then
    echo "       resuming the most recent Codex conversation: codex resume --last"
    "$CODEX_LAUNCHER" resume --last
  else
    echo "       opening a new Codex conversation in the existing repository workspace"
    echo "       repository files and Git state are preserved; previous chat history is not loaded"
    "$CODEX_LAUNCHER"
  fi
  codex_rc=$?
  set -e

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
    resume_next=1
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
  STATE_FILE="${SPRITE_SESSION_STATE:-$state_root/$key.json}"
}

load_state() {
  [[ -f $STATE_FILE ]] || return 1
  mapfile -t STATE_VALUES < <(python3 - "$STATE_FILE" <<'PY'
import json, sys
try: d=json.load(open(sys.argv[1]))
except Exception: raise SystemExit(1)
for k in ("version","host_dir","sprite_name","sprite_org","remote_workdir","session_manager","session_tag","task_name","session_id","tmux_session","deadline_epoch","run_hours","provider","transport","github_repository"):
    v=d.get(k,""); print(v if v is not None else "")
PY
) || return 1
  ((${#STATE_VALUES[@]} >= 15)) || return 1
  STATE_VERSION=${STATE_VALUES[0]:-0}; STATE_HOST_DIR=${STATE_VALUES[1]}; STATE_SPRITE_NAME=${STATE_VALUES[2]}; STATE_SPRITE_ORG=${STATE_VALUES[3]}; STATE_REMOTE_WORKDIR=${STATE_VALUES[4]}; STATE_SESSION_MANAGER=${STATE_VALUES[5]:-}; STATE_SESSION_TAG=${STATE_VALUES[6]:-}; STATE_TASK_NAME=${STATE_VALUES[7]:-}; STATE_SESSION_ID=${STATE_VALUES[8]:-}; STATE_TMUX_SESSION=${STATE_VALUES[9]:-}; STATE_DEADLINE_EPOCH=${STATE_VALUES[10]:-}; STATE_RUN_HOURS=${STATE_VALUES[11]:-}; STATE_CODEX_PROVIDER=${STATE_VALUES[12]:-deepseek}; STATE_TRANSPORT=${STATE_VALUES[13]:-}; STATE_GITHUB_REPOSITORY=${STATE_VALUES[14]:-}
  [[ -n $STATE_SPRITE_NAME && -n $STATE_REMOTE_WORKDIR ]]
}

write_state() {
  local sid=${CURRENT_SESSION_ID:-}
  python3 - "$STATE_FILE" "$HOST_DIR" "$SPRITE_NAME" "${SPRITE_ORG:-}" "$REMOTE_WORKDIR" "$SESSION_TAG" "$TASK_NAME" "$sid" "$SESSION_DEADLINE" "$SPRITE_RUN_HOURS" "$CODEX_PROVIDER" "$TRANSPORT" "$GITHUB_REPOSITORY" <<'PY'
import json,os,sys,tempfile,time
(path,host_dir,sprite_name,sprite_org,workdir,tag,task_name,sid,deadline,run_hours,provider,transport,github_repository)=sys.argv[1:]
d={"version":5,"host_dir":os.path.realpath(host_dir),"sprite_name":sprite_name,"sprite_org":sprite_org,"remote_workdir":workdir,"session_manager":"sprite-tty","session_tag":tag,"task_name":task_name,"session_id":sid,"tmux_session":"","deadline_epoch":int(deadline),"run_hours":run_hours,"provider":provider,"transport":transport,"github_repository":github_repository,"updated_at":int(time.time())}
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
  printf '  Stop ALL of these managed native sessions before starting a new Codex? [y/N]: '
  IFS= read -r ans || true
  case "${ans,,}" in
    y|yes) ;;
    *) die "refusing to start a duplicate Codex while a native managed session is live" ;;
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
      if session_id_is_active "$sid"; then note "detached from native Sprite TTY session $sid; Codex remains running"; note "rerun this script or use 'sprite sessions attach $sid' to reconnect"; fi
      return 0
    fi
    (( rc == 130 || rc == 129 || rc == 131 )) && return "$rc"
    (( TTY_AUTO_REATTACH == 1 )) || return "$rc"
    (( elapsed >= 30 )) && failures=0; failures=$((failures+1))
    if (( TTY_REATTACH_ATTEMPTS > 0 && failures > TTY_REATTACH_ATTEMPTS )); then warn "automatic native TTY reattach limit reached ($TTY_REATTACH_ATTEMPTS consecutive failures)"; return "$rc"; fi
    warn "local Sprite TTY attachment ended with rc=$rc"; note "checking whether native session $sid is still alive"
    if confirm_live_session_with_retry "$sid"; then update_state_session_id "$sid" 2>/dev/null || true; note "same remote Codex TTY is live; reattaching in ${TTY_REATTACH_DELAY}s"; sleep "$TTY_REATTACH_DELAY"; continue; fi
    warn "session $sid could not be confirmed after bounded retries"; note "resume state is retained; rerun the script if connectivity recovers"; return "$rc"
  done
}

choose_live_native_session() {
  local tag=$1 preferred=${2:-} workdir_hint=${3:-} raw row i=1 choice chosen sid created wd cmd epoch hint
  raw=$(get_sessions_json); mapfile -t rows < <(native_session_rows "$raw" "$tag" "$preferred" "$workdir_hint"); ((${#rows[@]})) || return 1
  step "choose live native Codex TTY session"; note "live managed Sprite TTY sessions on $SPRITE_NAME (newest first):"
  for row in "${rows[@]}"; do IFS=$'\t' read -r epoch sid created wd cmd <<<"$row"; hint=""; [[ -n $preferred && $sid == "$preferred" ]] && hint=" [saved-state hint]"; printf '    %d) id=%s%s\n' "$i" "$sid" "$hint"; printf '       created=%s workspace=%s\n' "${created:-unknown}" "${wd:-unknown}"; printf '       command=%s\n' "${cmd:-unknown}"; ((i++)); done
  if [[ ! -t 0 ]]; then choice=1; else printf '  Attach which session? [1]: '; IFS= read -r choice || true; choice=${choice:-1}; fi
  [[ $choice =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#rows[@]})) || { warn "invalid native session choice"; return 2; }
  chosen=${rows[choice-1]}; IFS=$'\t' read -r epoch sid created wd cmd <<<"$chosen"; note "attaching directly to native Sprite TTY session $sid"; note "detach without stopping Codex with Ctrl+\\"; update_state_session_id "$sid" 2>/dev/null || true
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

start_native_codex_session() {
  local remote_entry=$1 remote_runner=$2 row sid="" rc watcher="" raw
  raw=$(get_sessions_json)
  [[ -n $raw ]] && sessions_inventory_valid "$raw" || die "cannot validate Sprite session inventory before launch; refusing to risk a duplicate Codex process"
  row=$(native_session_rows "$raw" "$SESSION_TAG" "${CURRENT_SESSION_ID:-}" "$REMOTE_WORKDIR" | sed -n '1p')
  [[ -z $row ]] || { IFS=$'\t' read -r _ sid _ _ _ <<<"$row"; die "managed native Sprite TTY session $sid is already live; refusing to start a duplicate Codex process"; }
  CURRENT_SESSION_ID=""; write_state
  (
    for _ in $(seq 1 30); do sleep 1; row=$(find_native_session_row "$SESSION_TAG" "" "$REMOTE_WORKDIR" || true); if [[ -n $row ]]; then IFS=$'\t' read -r _ sid _ _ _ <<<"$row"; [[ -n $sid ]] && update_state_session_id "$sid" >/dev/null 2>&1 || true; exit 0; fi; done
  ) >/dev/null 2>&1 & watcher=$!
  note "starting Codex directly in a native detachable Sprite TTY"; note "detach with Ctrl+\\; no tmux key prefix or mouse mode is involved"
  if sprite exec "${ORG[@]}" -s "$SPRITE_NAME" --tty --no-port-forward \
    --env "SPRITE_CODEX_ENV_HEX=$ALL_CREDENTIAL_ENV" -- \
    "$remote_entry" bash "$remote_runner" "$RUN_SECONDS" "$TASK_NAME" "$SESSION_TAG" \
      "$REMOTE_WORKDIR" "$RESUME_CODEX_LAST" "$CODEX_PROVIDER"; then
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
    if [[ -n $sid ]] && session_id_is_active "$sid"; then note "native Sprite TTY detached cleanly; Codex remains live as session $sid"; note "reattach later with this script or: sprite sessions attach $sid"; else note "Codex/native TTY exited cleanly; resume state is retained as a history hint"; fi
    return 0
  fi
  if [[ -n $sid ]] && confirm_live_session_with_retry "$sid"; then warn "initial local TTY transport ended with rc=$rc but remote session $sid is still live"; if (( TTY_AUTO_REATTACH == 1 )); then note "reattaching to the same native Sprite session"; attach_native_session_resilient "$sid" "$SESSION_TAG"; return $?; fi; fi
  warn "Codex TTY launch/attachment ended with rc=$rc and no live managed session could be confirmed"; return "$rc"
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
  note "the Tasks API heartbeat follows the Codex runner for at most ${SPRITE_RUN_HOURS} hour(s)"
  note "native Sprite TTY sessions are themselves activity, so this bounds the Tasks hold—not total Sprite awake time"
  note "approx Tasks-hold deadline (local): $(date -d "@$_run_deadline_preview" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$_run_deadline_preview" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$_run_deadline_preview")"
  note "approx Tasks-hold deadline (UTC):   $(date -u -d "@$_run_deadline_preview" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -r "$_run_deadline_preview" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "$_run_deadline_preview")"
}

step "local prerequisites"
need_local sprite
need_local python3
need_local tar
local_network_advisory

step "choose Codex provider"
choose_codex_provider
case "$CODEX_PROVIDER" in
  openai) note "OpenAI mode uses the installed Codex CLI directly" ;;
  deepseek) note "DeepSeek mode preserves V4 Pro thinking through the Responses/Anthropic bridge workflow" ;;
  kimi) note "Kimi mode uses Moonshot Chat Completions through a local Responses adapter; Formula search is exposed by sprite-kimi-web-search" ;;
esac

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
note "one-Sprite mode: every setup, heartbeat, native TTY, and Codex command targets only $SPRITE_NAME"
project_short=$(python3 - "$HOST_DIR" <<'PY'
import hashlib,os,sys
print(hashlib.sha256(os.path.realpath(sys.argv[1]).encode()).hexdigest()[:8])
PY
)
SESSION_TAG="sprite-codex-native-${project_short}"
TASK_NAME="$SESSION_TAG"
LEGACY_TMUX_SESSION="sprite-codex-${project_short}"
CURRENT_SESSION_ID=""

# Validate the authoritative native session inventory before deciding whether a
# session exists. API/framing failure must never be interpreted as "zero sessions".
_NATIVE_INVENTORY=$(get_sessions_json)
if [[ -z $_NATIVE_INVENTORY ]] || ! sessions_inventory_valid "$_NATIVE_INVENTORY"; then
  die "could not validate the Sprite /exec session inventory; refusing to infer that no Codex session exists"
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

if legacy_tmux_guard "$LEGACY_TMUX_SESSION"; then
  _legacy_rc=0
else
  _legacy_rc=$?
fi
if (( _legacy_rc == 0 )); then exit 0; fi

prompt_run_limit

step "target credentials"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-$(detect_github_repo || true)}"
if [[ -n $GITHUB_REPOSITORY ]]; then
  note "GitHub repository detected: $GITHUB_REPOSITORY"
else
  printf '  GitHub repository (OWNER/REPO): '
  IFS= read -r GITHUB_REPOSITORY || true
fi
[[ $GITHUB_REPOSITORY =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || die "GitHub repository must be OWNER/REPO"
note "use a fine-grained PAT limited to $GITHUB_REPOSITORY with Contents: read and write"
prompt_secret GITHUB_PAT "GitHub PAT for $GITHUB_REPOSITORY"

FLY_APP="${FLY_APP:-$(detect_fly_app || true)}"
if [[ -n $FLY_APP ]]; then
  note "Fly app detected: $FLY_APP"
else
  printf '  Fly.io app name: '
  IFS= read -r FLY_APP || true
fi
[[ $FLY_APP =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "invalid Fly.io app name"
note "use an app-scoped Fly deploy token for $FLY_APP, preferably with a short expiry"
prompt_secret FLY_API_TOKEN "Fly.io token for $FLY_APP"

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
if legacy_tmux_guard "$LEGACY_TMUX_SESSION"; then
  _legacy_rc=0
else
  _legacy_rc=$?
fi
if (( _legacy_rc == 0 )); then exit 0; fi
if (( _legacy_rc == 2 )); then die "legacy tmux state is ambiguous after a successful control connection; refusing to risk a duplicate Codex"; fi

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

step "prepare Sprite tools and workspace"
setup_file=$(make_remote_setup)
sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
  --file "$setup_file:/tmp/sprite-codex-setup.sh" \
  -- bash /tmp/sprite-codex-setup.sh "$REMOTE_WORKDIR" "$MIN_CODEX_VERSION" "$CODEX_PROVIDER" \
  || die "Sprite tool setup failed"
ok "Sprite tools ready"

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
run_github_bootstrap "$GITHUB_ENV" || die "GitHub repository setup failed"
ok "normal git fetch, commit, and push are configured for $GITHUB_REPOSITORY"
note "Codex should use the HTTPS origin directly; no Sprites GitHub gateway is required"

step "verify Fly.io from the Sprite"
FLY_OUTPUT=$(sx_env "$FLY_ENV" -- bash -lc '
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$HOME/.fly/bin:$PATH"
tmp=$(mktemp); trap "rm -f \"$tmp\"" EXIT
fly status --app "$FLY_APP" > "$tmp"
echo "fly_app=$FLY_APP"
head -12 "$tmp"
' 2>&1) || {
  printf '%s\n' "$FLY_OUTPUT"
  die "Fly.io connection check failed"
}
printf '%s\n' "$FLY_OUTPUT"
ok "Fly.io target app is accessible"

if [[ $CODEX_PROVIDER == deepseek ]]; then
  step "DeepSeek credential"
  prompt_secret DEEPSEEK_API_KEY "DeepSeek API key required by Codex"
  DEEPSEEK_ENV=$(make_exec_env DEEPSEEK_API_KEY)
  ALL_CREDENTIAL_ENV=$(make_exec_env GH_TOKEN GITHUB_TOKEN GITHUB_REPOSITORY GH_REPO GH_HOST GH_PROMPT_DISABLED GIT_TERMINAL_PROMPT FLY_API_TOKEN FLY_ACCESS_TOKEN FLY_APP DEEPSEEK_API_KEY)
  note "DeepSeek is passed per Sprite command; bridge mode uses a short-lived 0600 config that is deleted after startup"

  step "choose DeepSeek V4 Pro transport"
  if [[ $TRANSPORT == auto ]]; then
    PROBE=$(sx_env "$DEEPSEEK_ENV" -- bash -lc '
set -Eeuo pipefail
out=$(mktemp); trap "rm -f \"$out\"" EXIT
status=$(curl -sS -o "$out" -w "%{http_code}" -m 90 \
  -X POST https://api.deepseek.com/responses \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "Content-Type: application/json" \
  --data "{\"model\":\"deepseek-v4-pro\",\"input\":\"Reply with OK.\",\"max_output_tokens\":16}" || echo 000)
case "$status" in
  200|429) echo direct ;;
  401|403)
    echo "DeepSeek authentication failed (HTTP $status)" >&2
    python3 - "$out" <<"DSPY1" >&2
import json,sys
try: print(json.load(open(sys.argv[1])).get("error",{}))
except Exception: pass
DSPY1
    exit 61 ;;
  *)
    msg=$(python3 - "$out" <<"DSPY2"
import json,sys
try:
 d=json.load(open(sys.argv[1])); e=d.get("error",d); print(str(e.get("message",e))[:180] if isinstance(e,dict) else str(e)[:180])
except Exception: print("unparseable response")
DSPY2
)
    echo "bridge|http=$status $msg"
    ;;
esac
' 2>&1) || die "$PROBE"
    if [[ $PROBE == direct ]]; then
      TRANSPORT=direct
      ok "native DeepSeek Responses accepted deepseek-v4-pro"
    else
      TRANSPORT=bridge
      warn "native V4 Pro Responses probe was not accepted: ${PROBE#bridge|}"
      note "using the local Responses-to-Anthropic bridge"
    fi
  else
    note "transport forced by DEEPSEEK_TRANSPORT=$TRANSPORT"
  fi

  step "configure Codex provider"
  configurator=$(make_codex_configurator)
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
    --file "$configurator:/tmp/configure-sprite-codex.py" \
    -- python3 /tmp/configure-sprite-codex.py "$REMOTE_WORKDIR" "$TRANSPORT" "$BRIDGE_PORT" \
    || die "Codex configuration failed"
  ok "Codex profile $PROFILE configured for $MODEL"
elif [[ $CODEX_PROVIDER == kimi ]]; then
  TRANSPORT=kimi-adapter
  step "Kimi K3 credential"
  prompt_secret MOONSHOT_API_KEY "Moonshot API key required by Kimi K3"
  ALL_CREDENTIAL_ENV=$(make_exec_env GH_TOKEN GITHUB_TOKEN GITHUB_REPOSITORY GH_REPO GH_HOST GH_PROMPT_DISABLED GIT_TERMINAL_PROMPT FLY_API_TOKEN FLY_ACCESS_TOKEN FLY_APP MOONSHOT_API_KEY)
  note "the Moonshot key is inherited only by the Kimi gateway/adapter process tree"
  note "Codex shell tools cannot read MOONSHOT_API_KEY; Formula search is available through a loopback helper"

  step "configure Kimi K3 Codex provider"
  kimi_configurator=$(make_kimi_configurator)
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
    --file "$kimi_configurator:/tmp/configure-sprite-codex-kimi.sh" -- \
    bash /tmp/configure-sprite-codex-kimi.sh "$REMOTE_WORKDIR" "$KIMI_MODEL" \
      "$MOONSHOT_BASE_URL" "$KIMI_FORMULA_URI" "$KIMI_BRIDGE_PORT" "$KIMI_GATEWAY_PORT" \
      "$KIMI_REQUEST_TIMEOUT" "$KIMI_MAX_COMPLETION_TOKENS" "$KIMI_MIN_REQUEST_INTERVAL_MS" \
      "$KIMI_FORMULA_MAX_ROUNDS" \
    || die "Kimi K3 Codex configuration failed"
  ok "Codex profile $KIMI_PROFILE configured for $KIMI_MODEL"
else
  TRANSPORT=normal
  ALL_CREDENTIAL_ENV=$(make_exec_env GH_TOKEN GITHUB_TOKEN GITHUB_REPOSITORY GH_REPO GH_HOST GH_PROMPT_DISABLED GIT_TERMINAL_PROMPT FLY_API_TOKEN FLY_ACCESS_TOKEN FLY_APP)

  step "configure normal OpenAI Codex launcher"
  openai_launcher=$(make_openai_launcher)
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
    --file "$openai_launcher:/tmp/configure-sprite-codex-openai.sh" \
    -- bash /tmp/configure-sprite-codex-openai.sh "$REMOTE_WORKDIR" \
    || die "could not configure the normal OpenAI Codex launcher"
  ok "OpenAI mode uses normal Codex provider/authentication with YOLO flags"

  step "check normal OpenAI Codex authentication"
  check_openai_auth
fi

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

  REMOTE_ARCHIVE="/tmp/sprite-codex-workspace-$(basename "$WORKSPACE_ARCHIVE")"
  sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
    --file "$WORKSPACE_ARCHIVE:$REMOTE_ARCHIVE" -- \
    bash -lc '
set -Eeuo pipefail
dest=$1
archive=$2
mkdir -p "$dest"
tar -xzf "$archive" -C "$dest"
rm -f "$archive"
printf "       Sprite workspace/ now contains:\n"
find "$dest" -mindepth 1 -printf "         %P\n" | sort | head -200
count=$(find "$dest" -type f | wc -l | tr -d " ")
printf "       regular files in Sprite workspace/: %s\n" "$count"
' _ "$REMOTE_WORKSPACE_DIR" "$REMOTE_ARCHIVE" \
    || die "workspace/ upload failed"
  ok "uploaded local workspace/ tree into $REMOTE_WORKSPACE_DIR"
fi

# This is deliberately the final repository mutation/check before any Codex
# preflight or interactive agent starts, so uploaded specification files are
# included in the comparison and optional push.
check_and_offer_repo_push

if [[ $CODEX_PROVIDER == deepseek ]]; then
  step "verify Codex -> DeepSeek V4 Pro"
  CODEX_CHECK_FILE=$(mktemp)
  cleanup_files+=("$CODEX_CHECK_FILE")
  note "streaming Codex output; hard timeout=${CODEX_PREFLIGHT_TIMEOUT:-180}s"
  if ! sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
    --env "SPRITE_CODEX_ENV_HEX=$ALL_CREDENTIAL_ENV,CODEX_PREFLIGHT_TIMEOUT=$CODEX_PREFLIGHT_TIMEOUT" \
    --dir "$REMOTE_WORKDIR" -- \
    python3 -c "$ENV_EXEC_PY" bash -lc '
set -o pipefail
run_check() {
  "$HOME/.local/bin/sprite-codex-deepseek-v4-pro" exec --ephemeral \
    "Run: git remote get-url origin && git ls-remote --exit-code origin HEAD. If both commands succeed, reply with exactly: SPRITE_CODEX_DEEPSEEK_V4_PRO_OK"
}
if command -v timeout >/dev/null 2>&1; then
  timeout "${CODEX_PREFLIGHT_TIMEOUT:-180}" bash -c "$(declare -f run_check); run_check"
else
  run_check
fi
' 2>&1 | tee "$CODEX_CHECK_FILE"; then
    CODEX_CHECK=$(cat "$CODEX_CHECK_FILE")
    die "Codex could not complete the DeepSeek V4 Pro preflight"
  fi
  CODEX_CHECK=$(cat "$CODEX_CHECK_FILE")
  grep -q 'SPRITE_CODEX_DEEPSEEK_V4_PRO_OK' <<<"$CODEX_CHECK" \
    || die "Codex ran, but its expected DeepSeek response was missing"
  ok "Codex is connected to $MODEL and can access the GitHub origin via normal git commands"
  printf '\n%sReady.%s Sprite=%s workspace=%s provider=deepseek profile=%s transport=%s\n' \
    "$C_GREEN" "$C_RESET" "$SPRITE_NAME" "$REMOTE_WORKDIR" "$PROFILE" "$TRANSPORT"
elif [[ $CODEX_PROVIDER == kimi ]]; then
  step "verify Codex -> Kimi K3"
  CODEX_CHECK_FILE=$(mktemp)
  cleanup_files+=("$CODEX_CHECK_FILE")
  note "streaming Codex output through the local Responses adapter; hard timeout=${CODEX_PREFLIGHT_TIMEOUT:-180}s"
  if ! sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
    --env "SPRITE_CODEX_ENV_HEX=$ALL_CREDENTIAL_ENV,CODEX_PREFLIGHT_TIMEOUT=$CODEX_PREFLIGHT_TIMEOUT" \
    --dir "$REMOTE_WORKDIR" -- \
    python3 -c "$ENV_EXEC_PY" bash -lc '
set -o pipefail
run_check() {
  "$HOME/.local/bin/sprite-codex-kimi-k3" exec --ephemeral \
    "Run: git remote get-url origin && git ls-remote --exit-code origin HEAD. If both commands succeed, reply with exactly: SPRITE_CODEX_KIMI_K3_OK"
}
if command -v timeout >/dev/null 2>&1; then
  timeout "${CODEX_PREFLIGHT_TIMEOUT:-180}" bash -c "$(declare -f run_check); run_check"
else
  run_check
fi
' 2>&1 | tee "$CODEX_CHECK_FILE"; then
    CODEX_CHECK=$(cat "$CODEX_CHECK_FILE")
    die "Codex could not complete the Kimi K3 preflight"
  fi
  CODEX_CHECK=$(cat "$CODEX_CHECK_FILE")
  grep -q 'SPRITE_CODEX_KIMI_K3_OK' <<<"$CODEX_CHECK" \
    || die "Codex ran, but its expected Kimi K3 response was missing"
  ok "Codex is connected to $KIMI_MODEL and can access the GitHub origin"
  printf '\n%sReady.%s Sprite=%s workspace=%s provider=kimi profile=%s transport=responses-adapter\n' \
    "$C_GREEN" "$C_RESET" "$SPRITE_NAME" "$REMOTE_WORKDIR" "$KIMI_PROFILE"
  note "Formula web search helper: $REMOTE_HOME/.local/bin/sprite-kimi-web-search"
else
  step "verify normal OpenAI Codex"
  CODEX_CHECK_FILE=$(mktemp)
  cleanup_files+=("$CODEX_CHECK_FILE")
  note "using the built-in OpenAI provider; hard timeout=${CODEX_PREFLIGHT_TIMEOUT:-180}s"
  if ! sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
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
    CODEX_CHECK=$(cat "$CODEX_CHECK_FILE")
    die "normal OpenAI Codex could not complete the preflight; if authentication is missing, run 'codex login --device-auth' on the Sprite"
  fi
  CODEX_CHECK=$(cat "$CODEX_CHECK_FILE")
  grep -q 'SPRITE_CODEX_OPENAI_OK' <<<"$CODEX_CHECK" \
    || die "Codex ran, but its expected OpenAI preflight response was missing"
  ok "normal OpenAI Codex can access the GitHub origin"
  printf '\n%sReady.%s Sprite=%s workspace=%s provider=openai transport=normal\n' \
    "$C_GREEN" "$C_RESET" "$SPRITE_NAME" "$REMOTE_WORKDIR"
fi

if [[ $NO_CODEX_LAUNCH == 1 ]]; then
  note "NO_CODEX_LAUNCH=1; interactive Codex launch skipped"
  note "no resumable session state was created"
  exit 0
fi

step "create native detachable Sprite TTY Codex session"
if [[ $CODEX_MODE_SELECTED != 1 ]]; then choose_codex_start_mode "creating a new native Sprite TTY Codex session"; fi
if [[ ! -t 0 || ! -t 1 ]]; then warn "no interactive terminal is attached, so Codex cannot open its TUI"; note "rerun from a terminal or set NO_CODEX_LAUNCH=1"; exit 0; fi

SESSION_DEADLINE=$(( $(date +%s) + RUN_SECONDS ))
runner=$(make_session_runner)
REMOTE_RUNNER="$REMOTE_HOME/.local/bin/${SESSION_TAG}-runner"
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
REMOTE_ENTRY="$REMOTE_HOME/.local/bin/${SESSION_TAG}-entry"
run_limited 30 sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
  --file "$runner:$REMOTE_RUNNER" --file "$NATIVE_ENTRY:$REMOTE_ENTRY" -- \
  bash -lc 'chmod 700 "$1" "$2"' _ "$REMOTE_RUNNER" "$REMOTE_ENTRY" \
  || die "could not install the native Codex supervisor/entrypoint"

write_state
note "non-secret resume state saved at $STATE_FILE"
note "only one Sprite is used: $SPRITE_NAME"
note "Codex will run directly in a native detachable Sprite TTY session"
note "managed tag: $SESSION_TAG"
note "the Tasks API uses a 5-minute hold refreshed every minute until the configured Tasks-hold deadline"
note "the native TTY session itself is also Sprite activity while it remains live"
note "detach cleanly with Ctrl+\\; there is no tmux prefix, mouse mode, or copy mode"
note "on a non-zero transport failure, the script reattaches to the same native session ID"

if start_native_codex_session "$REMOTE_ENTRY" "$REMOTE_RUNNER"; then
  launch_rc=0
else
  launch_rc=$?
fi
if [[ -n ${CURRENT_SESSION_ID:-} ]] && session_id_is_active "$CURRENT_SESSION_ID"; then note "Codex is still running in native Sprite TTY session $CURRENT_SESSION_ID; resume state was kept"; surface_native_hold_state "$SESSION_TAG" || true; else note "no live native managed TTY was confirmed after the attachment ended"; note "resume state is retained as a history hint; rerun and choose resume-last if Codex itself exited"; fi
exit "$launch_rc"
