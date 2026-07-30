#!/usr/bin/env bash
#
# zkc-verify.sh - establish exactly what DeepSeek-in-Codex can and cannot do.
#
#   bash zkc-verify.sh
#
# Not a smoke test. A capability matrix. Ten protocol probes and codex probes,
# each isolating one thing an agent actually needs, so the answer to "can I use
# DeepSeek in Codex for real work" is a table rather than a vibe.
#
# Layer 1 - PROTOCOL (raw curl, no codex, ~1s each, near-zero tokens)
#   P1 identity    does DeepSeek actually serve this, or something else?
#   P2 tool result one function_call + function_call_output survives translation
#   P3 parallel    THREE tool results in one turn (this is what killed LiteLLM)
#   P4 reasoning   a reasoning item round-trips (this killed codex-ds-v4)
#   P5 streaming   P2 again with stream:true, because codex streams
#
# Layer 2 - CODEX (real codex exec, small focused tasks)
#   C1 shell       run a command, report its output
#   C2 chained     use the output of one command as input to the next
#   C3 parallel    three separate commands in one turn
#   C4 create      write a new file
#   C5 edit        modify an existing file (a different codex tool path)
#   C6 recover     a command fails; continue instead of giving up
#   C7 metadata    is the real context window known, or fallback guessed?
#   C8 websearch   expected unavailable on a custom provider - confirm
#
# Layer 3 - ANTHROPIC PROTOCOL (raw curl to api.deepseek.com/anthropic)
#   A1 identity    /v1/messages answers and names its model
#   A2 tool_use    a GENUINE round trip: the model calls the tool, its reply
#                  (thinking blocks included) is replayed verbatim + tool_result
#   A3 parallel    same, asking for three calls; every issued token must return
#   A4 streaming   same round trip with the final turn streamed
# (v1 fabricated the assistant turn; DeepSeek thinking mode 400s on any replay
#  missing its thinking blocks. Real clients replay verbatim, so the probe must.)
#
# Layer 4 - CLAUDE CODE (real claude -p, headless)
#   L1 shell   L2 chained   L3 parallel   L4 create   L5 edit   L6 recover
#
# DeepSeek serves Anthropic Messages natively at /anthropic, so Layer 3/4 need
# no proxy at all. That is the whole point of testing both: if Claude Code works
# natively, the Codex bridge is optional complexity.
#
# Ends with a ready-to-paste config.toml and a plain list of what works.
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

# SPRITE_NAME env skips the picker; otherwise choose from `sprite list`.
SPRITE_NAME="${SPRITE_NAME:-}"
MODEL="${DEEPSEEK_MODEL:-deepseek-v4-pro}"
PORT="${BRIDGE_PORT:-8787}"
# Ceiling on how long the sprite is held awake, in seconds. The heartbeat stops
# at this deadline and releases the task, so an abandoned run cannot bill
# indefinitely. Raise it for long unattended work.
KEEPAWAKE_MAX="${KEEPAWAKE_MAX:-7200}"   # 2 hours
# codeproxy passed every rung of the earlier bridge bake-off. Override to test
# another: BRIDGE_CMD='...' BRIDGE_PORT=NNNN bash zkc-verify.sh
BRIDGE_CMD="${BRIDGE_CMD:-npx -y @codeproxy/cli --base-url https://api.deepseek.com/v1 --model __MODEL__ --apikey __KEY__}"
LOG="./debug.log"; : > "$LOG"; exec > >(tee -a "$LOG") 2>&1

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

  # 1. API JSON. Does not reflow for a pipe and carries no colour codes.
  if [[ -n "$api_raw" ]]; then
    while IFS= read -r n; do [[ -n "$n" ]] && names+=("$n"); done < <(
      printf '%s' "$api_raw" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
out=[]
def walk(x):
    if isinstance(x,dict):
        n=x.get("name")
        if isinstance(n,str) and n: out.append(n)
        for v in x.values(): walk(v)
    elif isinstance(x,list):
        for v in x: walk(v)
walk(d)
seen=set()
for n in out:
    if n not in seen: seen.add(n); print(n)
' 2>/dev/null)
    ((${#names[@]})) && src="api"
  fi

  # 2. Box/ascii table. Box chars are substituted literally, never placed in a
  #    character class - a 3-byte UTF-8 char inside [...] makes sed match single
  #    BYTES and the pattern can never align. ESC comes from printf because
  #    \x1b is a GNU sed extension that BSD sed (macOS) rejects.
  if ((${#names[@]} == 0)) && [[ -n "$list_raw" ]]; then
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

  # 3. Bare name per line - what the CLI actually emits when stdout is a pipe.
  if ((${#names[@]} == 0)) && [[ -n "$list_raw" ]]; then
    while IFS= read -r n; do [[ -n "$n" ]] && names+=("$n"); done < <(
      printf '%s\n' "$list_raw" \
        | sed "s/${ESC}\[[0-9;]*[a-zA-Z]//g" \
        | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }' \
        | grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*$' \
        | grep -vxE 'NAME|STATUS|URL|CREATED|running|stopped|warm|suspended|total')
    ((${#names[@]})) && src="plain"
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
    [[ -n "$SPRITE_NAME" ]] || c_die_local "no sprite name given"
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
    elif [[ -n "$sel" ]]; then SPRITE_NAME="$sel"; return 0; fi
    echo "  not a valid choice"
  done
  c_die_local "no valid selection after 5 attempts"
}
c_warn_local(){ printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
c_die_local(){ printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

step "0. sprite"
pick_sprite
run_limited 15 sprite api "${ORG[@]}" -s "$SPRITE_NAME" / >/dev/null \
  || note "could not query /v1/sprites/$SPRITE_NAME - continuing, exec will confirm"
echo "zkc-verify.sh  $(date -u '+%FT%TZ')  sprite=$SPRITE_NAME  model=$MODEL  port=$PORT"
sx -- bash -lc 'echo "  $(hostname) / $(whoami) / $HOME"' || { bad unreachable; exit 1; }
STDIN_OK=0
[[ "$(printf p | sprite exec "${ORG[@]}" -s "$SPRITE_NAME" -- cat 2>/dev/null)" == *p* ]] && STDIN_OK=1

step "1. DeepSeek key"
printf '  key (sk-...), hidden: '; read -rs DS_KEY || true; echo
[[ -n "$DS_KEY" ]] || { bad "required"; exit 1; }; ok captured

send(){  # $1 script, $2 extra env  - secret goes over stdin, never argv
  if ((STDIN_OK)); then
    local ef=(); [[ -n "${2:-}" ]] && ef=(--env "$2")
    printf '%s\n' "$DS_KEY" | sprite exec "${ORG[@]}" -s "$SPRITE_NAME" "${ef[@]}" -- bash -lc "$1"
  else
    local a="DEEPSEEK_API_KEY=$DS_KEY"; [[ -n "${2:-}" ]] && a="$a,$2"
    sx --env "$a" -- bash -lc "$1"
  fi
}

# =============================================================== 2. PREPARE ==
IFS= read -r -d '' S_PREP <<'EOF' || true
set -uo pipefail
IFS= read -r K || true; [ -n "${K:-}" ] || { echo '       no key'; exit 1; }
umask 077; mkdir -p "$HOME/.codex" "$HOME/probe"
printf 'export DEEPSEEK_API_KEY=%s\n' "$K" > "$HOME/.codex/deepseek.env"; chmod 600 "$HOME/.codex/deepseek.env"
command -v codex >/dev/null 2>&1 || { echo '       installing codex'; npm install -g @openai/codex >/dev/null 2>&1; }
if ! command -v rg >/dev/null 2>&1; then
  (apt-get update -qq && apt-get install -y -qq ripgrep) >/dev/null 2>&1 \
    || (sudo apt-get update -qq && sudo apt-get install -y -qq ripgrep) >/dev/null 2>&1 || true
fi
echo "       codex $(codex --version 2>/dev/null || echo MISSING)  node $(node -v 2>/dev/null)  rg $(command -v rg >/dev/null && echo yes || echo NO)"
# bwrap cannot initialise inside a sprite; sandboxed runs fail every command
cat > "$HOME/.codex/config.toml" <<'T'
approval_policy = "never"
sandbox_mode    = "danger-full-access"
model_reasoning_effort = "high"
T
printf '\n[projects."%s/probe"]\ntrust_level = "trusted"\n' "$HOME" >> "$HOME/.codex/config.toml"
cd "$HOME/probe"; git init -q 2>/dev/null || true
echo "       workspace $HOME/probe ready"
EOF
step "2. prepare"
send "$S_PREP" || { bad "prepare failed"; exit 1; }

if sx -- bash -lc 'codex login status' >/dev/null 2>&1; then ok "codex authenticated"
else
  note "device-code auth: open the URL, sign in, enter the code"
  sx --tty -- bash -lc 'codex login --device-auth'
  sx -- bash -lc 'codex login status' >/dev/null 2>&1 && ok authenticated || { bad "auth failed"; exit 1; }
fi

# ================================================== 3. BRIDGE + KEEP-AWAKE ==
IFS= read -r -d '' S_BRIDGE <<'EOF' || true
set -uo pipefail
IFS= read -r K || true
PORT="${B_PORT:?}"; MODEL="${B_MODEL:?}"
. "$HOME/probe/.bridgecmd"                      # staged, holds no secret
CMD="${BRIDGE_CMD//__KEY__/$K}"; CMD="${CMD//__MODEL__/$MODEL}"
export DEEPSEEK_API_KEY="$K"

# Hold the sprite awake. A bridge started by `sprite exec` otherwise dies when
# the sprite pauses, taking any long codex run with it. Heartbeat because a
# single task caps at 1h; it lapses by itself if this process disappears.
sapi(){ curl -s --max-time 5 --unix-socket /.sprite/api.sock -H 'Content-Type: application/json' "$@"; }
sapi -X PUT http://sprite/v1/tasks/zkc-bridge -d '{"expire":"5m"}' >/dev/null 2>&1
# Read the hold back rather than announcing it. Printing "registered" without
# checking is the same false-positive shape as a preflight that never verifies.
TASKS=$(sapi http://sprite/v1/tasks 2>/dev/null || true)
if printf '%s' "$TASKS" | grep -q 'zkc-bridge'; then
  echo "       keep-awake VERIFIED: $(printf '%s' "$TASKS" | head -c 200)"
else
  echo "       keep-awake NOT CONFIRMED - the sprite may pause under a long run"
  echo "       /v1/tasks returned: ${TASKS:-<empty>}"
fi

# SCAR: the heartbeat used to be `while curl ...; do sleep 60; done` with no
# ceiling and no parent check. It outlived the script by design (the bridge must
# survive), which meant the sprite stayed awake and BILLING until someone
# remembered to kill it - the exact "forgotten task" hazard the Sprites docs
# warn about. It is bounded now: it renews until a deadline, then DELETEs the
# task so the sprite frees immediately instead of waiting out the 5m expiry.
# A file, not a nested -c string: the quoting is legible and the trap works.
MAXSEC="${KEEP_MAX:-7200}"
DEADLINE=$(( $(date +%s) + MAXSEC ))
cat > "$HOME/probe/keepawake.sh" <<'HBEOF'
#!/usr/bin/env bash
DEADLINE="$1"; TASK="$2"
sapi(){ curl -s --max-time 5 --unix-socket /.sprite/api.sock -H 'Content-Type: application/json' "$@"; }
release(){ sapi -X DELETE "http://sprite/v1/tasks/$TASK" >/dev/null 2>&1 || true; }
# Fires on the deadline AND on kill, so either way the hold is dropped.
trap 'release; exit 0' EXIT INT TERM
# SCAR: this loop used a bare `sleep 60`. Bash defers signal handlers until the
# foreground child exits, so a TERM sat unhandled for up to a minute and the
# trap never released the task if the process was killed harder. It also meant
# the deadline was only rechecked once a minute. `sleep 5 & wait $!` lets the
# trap fire within ~5s, and the short interval honours the deadline promptly.
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sapi -X PUT "http://sprite/v1/tasks/$TASK" -d '{"expire":"5m"}' >/dev/null 2>&1 || true
  for _ in $(seq 1 12); do
    [ "$(date +%s)" -lt "$DEADLINE" ] || break
    sleep 5 & wait $!
  done
done
HBEOF
chmod +x "$HOME/probe/keepawake.sh"
setsid bash "$HOME/probe/keepawake.sh" "$DEADLINE" zkc-bridge \
  >"$HOME/probe/keepawake.log" 2>&1 </dev/null &
echo $! > "$HOME/probe/keepawake.pid"
echo "       heartbeat: 5m expiry, renewed every 60s, STOPS at $(date -u -d "@$DEADLINE" '+%H:%M:%SZ' 2>/dev/null || date -u -r "$DEADLINE" '+%H:%M:%SZ' 2>/dev/null || echo "+${MAXSEC}s")"
echo "       after that it releases the task and the sprite may hibernate"

# SCAR (three occurrences of this bug class now): pkill -f matches the parent
# shell's own argv, which contains this entire script as one string - any
# literal pattern that appears in the source kills the shell running it, right
# here, silently. Marker schemes fail too: bash execs simple commands, and exec
# replaces argv, erasing any planted marker. So: NO pattern matching at all.
# A pidfile. $! is the setsid leader's PID, exec PRESERVES pid, and kill on the
# negative PID takes out the whole process group (npx and its node children).
PIDF="$HOME/probe/bridge.pid"
if [ -f "$PIDF" ]; then
  OLDPID=$(cat "$PIDF" 2>/dev/null || true)
  [ -n "$OLDPID" ] && kill -- "-$OLDPID" 2>/dev/null && echo "       stopped previous bridge (pgid $OLDPID)"
  rm -f "$PIDF"; sleep 1
fi
setsid bash -c "$CMD" > "$HOME/probe/bridge.log" 2>&1 </dev/null &
echo $! > "$PIDF"
echo "       bridge launching (pid $(cat "$PIDF"), pidfile $PIDF)"
for i in $(seq 1 60); do
  curl -sS -o /dev/null -m 2 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null && { echo "       bound on :$PORT after $((i*2))s"; break; }
  [ "$i" = 60 ] && { echo '       NO BIND. log:'; tail -20 "$HOME/probe/bridge.log" | sed 's/^/         /'; exit 74; }
  sleep 2
done
python3 - "$HOME/.codex/config.toml" "$PORT" "$MODEL" <<'PY'
import sys,re,os
cfg,port,model=sys.argv[1:4]
s=open(cfg).read() if os.path.exists(cfg) else ''
s=re.sub(r'\n# >>> ds >>>.*?# <<< ds <<<\n','\n',s,flags=re.S)
open(cfg,'w').write(s.rstrip()+'''

# >>> ds >>>
[model_providers.deepseek]
name = "DeepSeek"
base_url = "http://127.0.0.1:%s/v1"
env_key = "DEEPSEEK_API_KEY"
wire_api = "responses"

# codex cannot fetch metadata from a custom provider (its /v1/models parse
# fails), so it guesses a fallback window. Pin the real values instead:
# DeepSeek advertises max_input_tokens=1000000, max_output_tokens=8192.
model_context_window = 1000000
model_max_output_tokens = 8192

[profiles.deepseek]
model = "%s"
model_provider = "deepseek"
# <<< ds <<<
''' % (port, model))
PY
echo '       codex provider + profile written'
EOF
step "3. bridge"
b64=$(printf 'BRIDGE_CMD=%q\n' "$BRIDGE_CMD" | base64 | tr -d '\n')
sx -- bash -lc "mkdir -p \$HOME/probe && echo $b64 | base64 -d > \$HOME/probe/.bridgecmd"
send "$S_BRIDGE" "B_PORT=$PORT,B_MODEL=$MODEL,KEEP_MAX=$KEEPAWAKE_MAX" && ok "bridge up and held awake" || { bad "bridge failed"; exit 1; }

# ========================================================= 4. PROTOCOL PROBES ==
IFS= read -r -d '' S_PROTO <<'EOF' || true
set -uo pipefail
IFS= read -r K || true
PORT="${B_PORT:?}"; MODEL="${B_MODEL:?}"
U="http://127.0.0.1:$PORT/v1/responses"
H=(-H "Authorization: Bearer $K" -H 'Content-Type: application/json')
p(){ printf '  %-14s %-5s %s\n' "$1" "$2" "${3:-}"; echo "PROBE|$1|$2|${3:-}"; }
post(){ curl -sS -o "$2" -w '%{http_code}' -m 90 -X POST "$U" "${H[@]}" -d "$1" 2>/dev/null || echo 000; }

# ---- P1 identity: who actually answered? -----------------------------------
# Balance is deliberately NOT used as evidence: CNY is reported to 2 decimals
# and these probes cost far less than one fen, so it can never move. Printing
# an unchanged balance next to "proof" wording implied the opposite of the
# truth. P1 relies on the upstream model field + the bridge log instead.
c=$(post "{\"model\":\"$MODEL\",\"input\":\"Reply with the single word OK.\"}" /tmp/p1.json)
UPMODEL=$(python3 -c "import json;print(json.load(open('/tmp/p1.json')).get('model','?'))" 2>/dev/null || echo '?')
HITDS=$(grep -ciE 'api\.deepseek\.com' "$HOME/probe/bridge.log" 2>/dev/null || echo 0)
if [ "$c" = 200 ] && [ "$HITDS" -gt 0 ]; then
  p P1-identity PASS "upstream=api.deepseek.com hits=$HITDS model_field=$UPMODEL"
else
  p P1-identity FAIL "http=$c deepseek_hits=$HITDS model_field=$UPMODEL"
  head -c 300 /tmp/p1.json | sed 's/^/         /'; echo
fi

TOK="ZKCT$(date +%s)$RANDOM"
tools='"tools":[{"type":"function","name":"get_token","description":"Returns a token","parameters":{"type":"object","properties":{},"required":[]}}]'

# ---- P2 one tool result survives translation -------------------------------
B2="{\"model\":\"$MODEL\",\"instructions\":\"Answer only from the tool result.\",\"input\":[
 {\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Call get_token then reply with only the token.\"}]},
 {\"type\":\"function_call\",\"call_id\":\"c1\",\"name\":\"get_token\",\"arguments\":\"{}\"},
 {\"type\":\"function_call_output\",\"call_id\":\"c1\",\"output\":\"$TOK\"}],$tools}"
c=$(post "$B2" /tmp/p2.json)
if grep -q "$TOK" /tmp/p2.json 2>/dev/null; then p P2-tool PASS "token echoed"
elif grep -qiE 'insufficient tool messages|must be followed by tool' /tmp/p2.json; then p P2-tool FAIL "bridge DROPS the tool result"
else p P2-tool FAIL "http=$c"; head -c 300 /tmp/p2.json | sed 's/^/         /'; echo; fi

# ---- P3 THREE tool results in one turn (killed LiteLLM) --------------------
B3="{\"model\":\"$MODEL\",\"instructions\":\"Answer only from the tool results.\",\"input\":[
 {\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Call get_token three times, then reply with all three values.\"}]},
 {\"type\":\"function_call\",\"call_id\":\"a1\",\"name\":\"get_token\",\"arguments\":\"{}\"},
 {\"type\":\"function_call\",\"call_id\":\"a2\",\"name\":\"get_token\",\"arguments\":\"{}\"},
 {\"type\":\"function_call\",\"call_id\":\"a3\",\"name\":\"get_token\",\"arguments\":\"{}\"},
 {\"type\":\"function_call_output\",\"call_id\":\"a1\",\"output\":\"${TOK}A\"},
 {\"type\":\"function_call_output\",\"call_id\":\"a2\",\"output\":\"${TOK}B\"},
 {\"type\":\"function_call_output\",\"call_id\":\"a3\",\"output\":\"${TOK}C\"}],$tools}"
c=$(post "$B3" /tmp/p3.json)
n=0
for x in A B C; do grep -q "${TOK}${x}" /tmp/p3.json 2>/dev/null && n=$((n+1)); done
[ "$n" = 3 ] && p P3-parallel PASS "all 3 tool results survived" \
  || { p P3-parallel FAIL "only $n/3 survived (http=$c)"; head -c 300 /tmp/p3.json | sed 's/^/         /'; echo; }

# ---- P4 reasoning item round trip (killed codex-ds-v4) ---------------------
B4="{\"model\":\"$MODEL\",\"instructions\":\"Answer only from the tool result.\",\"input\":[
 {\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Call get_token then reply with only the token.\"}]},
 {\"type\":\"reasoning\",\"summary\":[],\"content\":[{\"type\":\"reasoning_text\",\"text\":\"I should call get_token.\"}]},
 {\"type\":\"function_call\",\"call_id\":\"r1\",\"name\":\"get_token\",\"arguments\":\"{}\"},
 {\"type\":\"function_call_output\",\"call_id\":\"r1\",\"output\":\"$TOK\"}],$tools}"
c=$(post "$B4" /tmp/p4.json)
if grep -q "$TOK" /tmp/p4.json 2>/dev/null; then p P4-reasoning PASS "reasoning item tolerated"
elif grep -qi 'reasoning_content' /tmp/p4.json; then p P4-reasoning FAIL "must pass reasoning_content back"
else p P4-reasoning FAIL "http=$c"; head -c 300 /tmp/p4.json | sed 's/^/         /'; echo; fi

# ---- P5 streamed ------------------------------------------------------------
curl -sS -N -m 90 -X POST "$U" "${H[@]}" -d "${B2%\}}, \"stream\":true}" > /tmp/p5.sse 2>/dev/null
grep -q "$TOK" /tmp/p5.sse && p P5-stream PASS "SSE carried the answer" \
  || { p P5-stream FAIL "streamed path broken"; tail -c 250 /tmp/p5.sse | sed 's/^/         /'; echo; }

# Token accounting IS granular enough to prove who served the request.
USG=$(python3 -c "
import json
try:
    d=json.load(open('/tmp/p1.json')); u=d.get('usage') or {}
    print('input=%s output=%s' % (u.get('input_tokens','?'), u.get('output_tokens','?')))
except Exception: print('unavailable')
" 2>/dev/null)
echo "  upstream usage on P1: $USG"
echo "  (balance is not checked: CNY has 2 decimals and these probes cost less"
echo "   than one fen, so an unchanged figure proves nothing either way)"
EOF
step "4. protocol probes (raw curl, no codex)"
PROTO_OUT=$(send "$S_PROTO" "B_PORT=$PORT,B_MODEL=$MODEL" 2>&1); echo "$PROTO_OUT"

# ============================================================ 5. CODEX PROBES ==
IFS= read -r -d '' S_CODEX <<'EOF' || true
set -uo pipefail
set -a; . "$HOME/.codex/deepseek.env"; set +a
MODEL="${B_MODEL:?}"; W="$HOME/probe"; cd "$W"
p(){ printf '  %-14s %-5s %s\n' "$1" "$2" "${3:-}"; echo "PROBE|$1|$2|${3:-}"; }
CX=(codex exec --dangerously-bypass-approvals-and-sandbox
    -c model_provider=deepseek -c "model=$MODEL" -c web_search=disabled
    -c model_context_window=1000000 -c model_max_output_tokens=8192)
run(){ "${CX[@]}" "$1" 2>&1; }
N=$RANDOM

# C1 one shell command, report its output
o=$(run "Run this command: echo ZKCONE$N
Reply with only what it printed.")
grep -q "ZKCONE$N" <<<"$o" && p C1-shell PASS || { p C1-shell FAIL; tail -6 <<<"$o" | sed 's/^/         /'; }

# C2 chain: the second command needs the first one's output
o=$(run "Run: echo 7
Then run: expr <that number> \* 6
Reply with only the final number.")
grep -q '42' <<<"$o" && p C2-chained PASS "used the first result" \
  || { p C2-chained FAIL "could not feed one result into the next"; tail -6 <<<"$o" | sed 's/^/         /'; }

# C3 three separate commands in one turn - the shape that broke LiteLLM
o=$(run "Run these as three separate commands: echo AAA$N ; echo BBB$N ; echo CCC$N
Reply with all three outputs.")
k=0; for x in AAA BBB CCC; do grep -q "$x$N" <<<"$o" && k=$((k+1)); done
[ "$k" = 3 ] && p C3-parallel PASS "3/3" || { p C3-parallel FAIL "$k/3"; tail -8 <<<"$o" | sed 's/^/         /'; }

# C4 create a file
rm -f made.txt
o=$(run "Create a file named made.txt in the current directory containing exactly: MADE$N
Create that one file and nothing else.")
[ -f made.txt ] && grep -q "MADE$N" made.txt && p C4-create PASS "$(wc -c <made.txt) bytes" \
  || { p C4-create FAIL "file absent or wrong"; tail -8 <<<"$o" | sed 's/^/         /'; }

# C5 edit an existing file - a different codex tool path from create
printf 'keep this line\nOLDVALUE\nkeep this too\n' > edit.txt
o=$(run "In edit.txt, replace the line OLDVALUE with NEW$N
Change nothing else in that file.")
if grep -q "NEW$N" edit.txt 2>/dev/null && grep -q 'keep this line' edit.txt; then
  p C5-edit PASS "patched in place"
else p C5-edit FAIL "edit did not apply cleanly"; tail -8 <<<"$o" | sed 's/^/         /'; fi

# C6 keep going after a command fails
o=$(run "Run: cat /definitely-not-here-$N   (this will fail, that is expected)
Then run: echo RECOVERED$N
Reply with only the second output.")
grep -q "RECOVERED$N" <<<"$o" && p C6-recover PASS "continued past a failure" \
  || { p C6-recover FAIL "gave up after one error"; tail -8 <<<"$o" | sed 's/^/         /'; }

# C7 does codex know the real context window, or is it guessing?
o=$(run "Reply with only the word FINE.")
# Do not just report the warning - check the pin is really loaded. `codex
# config get` reads the effective merged configuration, so it distinguishes
# "written to a file" from "in force".
EFF=$(codex config get model_context_window 2>/dev/null | tr -d ' \r\n' || true)
[ -n "$EFF" ] || EFF=$(grep -m1 '^model_context_window' "$HOME/.codex/config.toml" 2>/dev/null | tr -d ' ' | cut -d= -f2)
if grep -qi 'model metadata for .* not found' <<<"$o"; then
  if [ "${EFF:-0}" = "1000000" ]; then
    p C7-metadata INFO "lookup warning is cosmetic; effective window=$EFF"
  else
    p C7-metadata FAIL "fallback metadata AND pin not in force (effective=${EFF:-unset})"
  fi
else
  p C7-metadata PASS "no fallback warning; effective window=${EFF:-unknown}"
fi

# C8 web search on a custom provider - expected unavailable
# SCAR: the old check accepted any /[0-9]{2}\./ and so matched the string
# "deepseek-v4-pro" itself - it reported PASS without a search ever happening.
# Require evidence the TOOL ran, not merely a number-shaped substring.
o=$(codex exec --dangerously-bypass-approvals-and-sandbox \
      -c model_provider=deepseek -c "model=$MODEL" -c web_search=live \
      "Use your web search tool to find today's top story on a major news site.
Reply with the headline and the URL you retrieved it from." 2>&1)
if grep -qiE 'unsupported|not supported|unknown tool|no such tool|web_search.*invalid|tool.*not available' <<<"$o"; then
  p C8-websearch INFO "web search unavailable on a custom provider, as expected"
elif grep -qiE 'https?://[a-z0-9.-]+\.[a-z]{2,}' <<<"$o" && grep -qic 'search' <<<"$o" >/dev/null; then
  p C8-websearch PASS "returned a live URL - search really ran"
elif grep -qiE 'cannot|unable|do not have|no access' <<<"$o"; then
  p C8-websearch INFO "model says it has no search capability"
else
  p C8-websearch INFO "inconclusive - no URL returned and no explicit refusal"
fi
EOF
step "5. codex capability probes"
CODEX_OUT=$(send "$S_CODEX" "B_MODEL=$MODEL" 2>&1); echo "$CODEX_OUT"


# ====================================================== 6. ANTHROPIC PROTOCOL ==
IFS= read -r -d '' S_ANTHRO <<'EOF' || true
set -uo pipefail
IFS= read -r K || true
M="${A_MODEL:?}"
python3 - "$K" "$M" <<'PYEOF'
import json, sys, urllib.request, urllib.error, time, random

K, M = sys.argv[1], sys.argv[2]
URL = "https://api.deepseek.com/anthropic/v1/messages"
HDR = {"x-api-key": K, "Authorization": "Bearer " + K,
       "anthropic-version": "2023-06-01", "Content-Type": "application/json"}
TOOLS = [{"name": "get_token", "description": "Returns a secret token",
          "input_schema": {"type": "object", "properties": {}}}]

def post(body, stream=False):
    if stream: body = dict(body, stream=True)
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers=HDR)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return 0, str(e)

def sse_text(raw):
    """Reassemble assistant text from an Anthropic SSE stream.

    Text arrives as content_block_delta events carrying delta.text fragments,
    so a token is SPLIT across chunks. Searching the raw body for a whole token
    can never match - that bug reported a working 200 stream as a failure.
    """
    out, saw_delta, stopped = [], False, False
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
        t = ev.get("type")
        if t == "content_block_delta":
            d = ev.get("delta") or {}
            # text_delta for prose; input_json_delta carries tool arguments
            frag = d.get("text") or d.get("partial_json") or ""
            if frag:
                out.append(frag); saw_delta = True
        elif t == "message_stop":
            stopped = True
        elif t == "error":
            return "", False, False
    return "".join(out), saw_delta, stopped

def probe(name, verdict, detail=""):
    print("  %-14s %-5s %s" % (name, verdict, detail))
    print("PROBE|%s|%s|%s" % (name, verdict, detail))

# ---- A1 identity ------------------------------------------------------------
c, raw = post({"model": M, "max_tokens": 64,
               "messages": [{"role": "user", "content": "Reply with the single word OK."}]})
try: um = json.loads(raw).get("model", "?")
except Exception: um = "?"
if c == 200: probe("A1-identity", "PASS", "messages endpoint live, model_field=" + um)
else:
    probe("A1-identity", "FAIL", "http=%s" % c)
    print("         " + raw[:280])

# ---- helper: one GENUINE tool round trip ------------------------------------
# Turn 1 lets the model call the tool for real. Turn 2 replays the assistant
# content verbatim (thinking blocks included - dropping them is exactly what
# DeepSeek's 400 complained about) plus a tool_result per call.
def round_trip(user_text, stream=False, max_turns=4):
    msgs = [{"role": "user", "content": user_text}]
    issued = {}          # tool_use_id -> token we handed back
    for _ in range(max_turns):
        c, raw = post({"model": M, "max_tokens": 512, "tools": TOOLS, "messages": msgs})
        if c != 200: return ("HTTP", c, raw, issued)
        d = json.loads(raw)
        content = d.get("content", [])
        calls = [b for b in content if b.get("type") == "tool_use"]
        if not calls:
            text = " ".join(b.get("text", "") for b in content if b.get("type") == "text")
            return ("DONE", 200, text, issued)
        msgs.append({"role": "assistant", "content": content})   # verbatim
        results = []
        for b in calls:
            tok = "ZKCA%d%d" % (int(time.time()), random.randint(1000, 9999))
            issued[b["id"]] = tok
            results.append({"type": "tool_result", "tool_use_id": b["id"], "content": tok})
        msgs.append({"role": "user", "content": results})
        if stream and len(msgs) >= 3:                 # final turn streamed
            c, raw = post({"model": M, "max_tokens": 512, "tools": TOOLS, "messages": msgs}, stream=True)
            return ("SSE", c, raw, issued)
    return ("LOOP", 200, "", issued)

# ---- A2 single tool round trip ----------------------------------------------
kind, c, out, issued = round_trip("Call get_token once, then reply with only the token it returned.")
if kind == "DONE" and issued and all(t in out for t in issued.values()):
    probe("A2-tool_use", "PASS", "genuine round trip, token echoed")
elif kind == "HTTP":
    probe("A2-tool_use", "FAIL", "http=%s" % c); print("         " + out[:280])
elif not issued:
    probe("A2-tool_use", "FAIL", "model never called the tool")
else:
    probe("A2-tool_use", "FAIL", "token not echoed back")

# ---- A3 multiple tool results -----------------------------------------------
kind, c, out, issued = round_trip(
    "Call get_token exactly three times (you may call it in parallel), then reply with all the tokens it returned.")
n = len(issued); echoed = sum(1 for t in issued.values() if t in out)
if kind == "DONE" and n >= 2 and echoed == n:
    probe("A3-parallel", "PASS", "%d calls made, %d/%d tokens echoed" % (n, echoed, n))
elif kind == "HTTP":
    probe("A3-parallel", "FAIL", "http=%s" % c); print("         " + out[:280])
elif n < 2:
    probe("A3-parallel", "INFO", "model made only %d call(s); nothing dropped, shape untested" % n)
else:
    probe("A3-parallel", "FAIL", "%d/%d tokens survived" % (echoed, n))

# ---- A4 streamed final turn ---------------------------------------------------
kind, c, out, issued = round_trip("Call get_token once, then reply with only the token it returned.", stream=True)
if kind == "SSE":
    if c != 200:
        probe("A4-stream", "FAIL", "http=%s" % c); print("         " + out[:280])
    else:
        text, saw, stopped = sse_text(out)
        hit = issued and all(t in text for t in issued.values())
        if hit and stopped:
            probe("A4-stream", "PASS", "SSE reassembled, token present, clean message_stop")
        elif hit:
            probe("A4-stream", "PASS", "SSE reassembled, token present (no message_stop seen)")
        elif saw:
            probe("A4-stream", "FAIL",
                  "stream ok but token missing; reassembled %d chars" % len(text))
            print("         reassembled: " + text[:160])
        else:
            probe("A4-stream", "FAIL", "no content_block_delta events in the stream")
            print("         " + out[:240])
elif kind == "DONE" and issued and all(t in out for t in issued.values()):
    probe("A4-stream", "PASS", "answered before a streamed turn was needed")
elif kind == "HTTP":
    probe("A4-stream", "FAIL", "http=%s" % c); print("         " + out[:280])
else:
    probe("A4-stream", "FAIL", "no token produced")
PYEOF
EOF
step "6. anthropic protocol probes (no proxy at all)"
ANTHRO_OUT=$(send "$S_ANTHRO" "A_MODEL=$MODEL" 2>&1); echo "$ANTHRO_OUT"

# ========================================================= 7. CLAUDE CODE ==
IFS= read -r -d '' S_CLAUDE <<'EOF' || true
set -uo pipefail
IFS= read -r K || true
M="${A_MODEL:?}"
W="$HOME/probe-cc"; mkdir -p "$W"; cd "$W"; git init -q 2>/dev/null || true
command -v claude >/dev/null 2>&1 || { echo '       installing claude code'; npm install -g @anthropic-ai/claude-code >/dev/null 2>&1; }
echo "       claude $(claude --version 2>/dev/null || echo MISSING)"
command -v claude >/dev/null 2>&1 || { echo 'PROBE|L0-install|FAIL|claude code did not install'; exit 0; }

# DeepSeek's documented Claude Code configuration. The [1m] suffix selects the
# 1M-context variant; the DEFAULT_* vars catch Claude Code's internal routing,
# which asks for opus/sonnet/haiku by name rather than the model you set.
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN="$K"
export ANTHROPIC_API_KEY="$K"
export ANTHROPIC_MODEL="${M}[1m]"
export ANTHROPIC_DEFAULT_OPUS_MODEL="${M}[1m]"
export ANTHROPIC_DEFAULT_SONNET_MODEL="${M}[1m]"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
export CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1
export CLAUDE_CODE_EFFORT_LEVEL=max

p(){ printf '  %-14s %-5s %s\n' "$1" "$2" "${3:-}"; echo "PROBE|$1|$2|${3:-}"; }
run(){ claude -p --dangerously-skip-permissions "$1" 2>&1; }
N=$RANDOM

o=$(run "Run this command: echo ZKCL$N
Reply with only what it printed.")
grep -q "ZKCL$N" <<<"$o" && p L1-shell PASS || { p L1-shell FAIL; tail -8 <<<"$o" | sed 's/^/         /'; }

o=$(run "Run: echo 7
Then run: expr <that number> \* 6
Reply with only the final number.")
grep -q 42 <<<"$o" && p L2-chained PASS || { p L2-chained FAIL; tail -6 <<<"$o" | sed 's/^/         /'; }

o=$(run "Run these as three separate commands: echo AAA$N ; echo BBB$N ; echo CCC$N
Reply with all three outputs.")
k=0; for x in AAA BBB CCC; do grep -q "$x$N" <<<"$o" && k=$((k+1)); done
[ "$k" = 3 ] && p L3-parallel PASS "3/3" || { p L3-parallel FAIL "$k/3"; tail -8 <<<"$o" | sed 's/^/         /'; }

rm -f made.txt
o=$(run "Create a file named made.txt containing exactly: MADE$N
Create that one file and nothing else.")
[ -f made.txt ] && grep -q "MADE$N" made.txt && p L4-create PASS \
  || { p L4-create FAIL; tail -8 <<<"$o" | sed 's/^/         /'; }

printf 'keep this line\nOLDVALUE\nkeep this too\n' > edit.txt
o=$(run "In edit.txt replace the line OLDVALUE with NEW$N. Change nothing else.")
grep -q "NEW$N" edit.txt 2>/dev/null && grep -q 'keep this line' edit.txt \
  && p L5-edit PASS "patched in place" || { p L5-edit FAIL; tail -8 <<<"$o" | sed 's/^/         /'; }

o=$(run "Run: cat /definitely-not-here-$N  (it will fail, that is expected)
Then run: echo RECOVERED$N
Reply with only the second output.")
grep -q "RECOVERED$N" <<<"$o" && p L6-recover PASS || { p L6-recover FAIL; tail -8 <<<"$o" | sed 's/^/         /'; }
EOF
step "7. claude code capability probes"
CLAUDE_OUT=$(send "$S_CLAUDE" "A_MODEL=$MODEL" 2>&1); echo "$CLAUDE_OUT"

# =================================================================== REPORT ===
step "CAPABILITY MATRIX"
printf '  %-14s %-5s %s\n' PROBE VERDICT DETAIL
ALL=$(printf '%s\n%s\n%s\n%s\n' "$PROTO_OUT" "$CODEX_OUT" "$ANTHRO_OUT" "$CLAUDE_OUT")
printf '%s\n' "$ALL" | grep '^PROBE|' | while IFS='|' read -r _ n v d; do
  case "$v" in
    PASS) printf '  \033[1;32m%-14s %-5s\033[0m %s\n' "$n" PASS "$d" ;;
    FAIL) printf '  \033[1;31m%-14s %-5s\033[0m %s\n' "$n" FAIL "$d" ;;
    *)    printf '  \033[1;33m%-14s %-5s\033[0m %s\n' "$n" "$v" "$d" ;;
  esac
done
FAILS=$(printf '%s\n' "$ALL" | grep -c '^PROBE|[^|]*|FAIL' || true)
cf(){ printf '%s\n' "$ALL" | grep -c "^PROBE|$1[0-9]*-[^|]*|FAIL" || true; }
CODEX_FAILS=$(( $(cf P) + $(cf C) )); CLAUDE_FAILS=$(( $(cf A) + $(cf L) ))

step "HEAD TO HEAD"
printf '  %-34s %s\n' "Codex + local Responses bridge:" "$([ "$CODEX_FAILS" = 0 ] && echo 'all probes passed' || echo "$CODEX_FAILS failure(s)")"
printf '  %-34s %s\n' "Claude Code + native /anthropic:" "$([ "$CLAUDE_FAILS" = 0 ] && echo 'all probes passed' || echo "$CLAUDE_FAILS failure(s)")"
if [ "$CLAUDE_FAILS" = 0 ] && [ "$CODEX_FAILS" = 0 ]; then
  echo
  echo "  Both work. Prefer Claude Code for real use: no proxy process to keep"
  echo "  alive, nothing to translate, no keep-awake task for a bridge, and one"
  echo "  fewer component that can drop a tool result. Use Codex only if you"
  echo "  specifically need Codex."
elif [ "$CLAUDE_FAILS" = 0 ]; then
  echo; echo "  Use Claude Code. It needs no proxy and passed where Codex did not."
elif [ "$CODEX_FAILS" = 0 ]; then
  echo; echo "  Use Codex with the bridge. The native Anthropic path failed here."
fi

# SCAR: an unquoted heredoc strips the backslash BEFORE parameter expansion is
# parsed, so ${BRIDGE_CMD//__KEY__/\$DEEPSEEK_API_KEY} became a real expansion
# of an unset variable and `set -u` killed the whole verdict block - the one
# piece of output the run exists to produce. Build the literal beforehand.
DOLLAR='$'
BRIDGE_DISPLAY="${BRIDGE_CMD//__KEY__/${DOLLAR}DEEPSEEK_API_KEY}"
BRIDGE_DISPLAY="${BRIDGE_DISPLAY//__MODEL__/$MODEL}"

step "VERDICT"
# SCAR: this heredoc is unquoted so ${PORT}/${MODEL} interpolate - which means
# every literal dollar must be written ${DOLLAR}. Missing one aborted the whole
# block under `set -u` and the run printed no config at all, twice. The escapes
# are fixed, and `set +u` here guarantees a missed one degrades to a cosmetic
# blank instead of destroying the only output that matters.
set +u
if [ "${FAILS:-1}" = 0 ]; then
  cat <<TXT
  Every probe passed. DeepSeek is usable in Codex for general agentic work:
  tool calls, parallel tool calls, chained reasoning, file creation, in-place
  edits, and recovery from failed commands.

  Working setup - start the bridge, then use the profile:

    export DEEPSEEK_API_KEY=sk-...
    ${BRIDGE_DISPLAY}

    # ~/.codex/config.toml
    [model_providers.deepseek]
    name = "DeepSeek"
    base_url = "http://127.0.0.1:${PORT}/v1"
    env_key = "DEEPSEEK_API_KEY"
    wire_api = "responses"

    [profiles.deepseek]
    model = "${MODEL}"
    model_provider = "deepseek"

    codex --profile deepseek          # interactive
    codex exec -c model_provider=deepseek -c model=${MODEL} "..."

  The bridge must be running before codex starts, and must outlive the run.

  Or skip the proxy entirely with Claude Code, which speaks DeepSeek natively:

    export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
    export ANTHROPIC_AUTH_TOKEN=${DOLLAR}DEEPSEEK_API_KEY
    export ANTHROPIC_MODEL=${MODEL}[1m]
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${MODEL}[1m]
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${MODEL}[1m]
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
    export CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
    export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1
    export CLAUDE_CODE_EFFORT_LEVEL=max

    claude                                    # interactive
    claude -p --dangerously-skip-permissions "..."   # headless

  The [1m] suffix selects the 1M-context variant. The DEFAULT_* vars matter
  because Claude Code routes some internal calls by asking for opus/sonnet/
  haiku by name rather than the model you set.
TXT
else
  echo "  ${FAILS} probe(s) failed. Read the DETAIL column: P-probes are the"
  echo "  bridge's translation, C-probes are codex end to end. A P-failure with"
  echo "  passing C-probes means the probe payload needs adjusting, not the"
  echo "  bridge. A P-pass with C-failure means codex sends something my"
  echo "  hand-built payload does not - capture it with the bridge's own log."
  echo
  echo "  If P2/P3/P4 fail, this bridge cannot carry an agent. Try another:"
  echo "    BRIDGE_CMD='...' BRIDGE_PORT=NNNN bash $0"
  echo "  Or skip translation entirely - DeepSeek speaks Anthropic natively:"
  echo "    ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic + Claude Code"
fi
set -u
printf '\n  bridge log: ~/probe/bridge.log on the sprite\n'
printf '  transcript: %s\n' "$(cd "$(dirname "$LOG")" && pwd)/$(basename "$LOG")"
printf '  release the keep-awake hold when done:\n'
printf "    sprite exec -s %s -- bash -lc '\n" "$SPRITE_NAME"
printf "      kill \$(cat ~/probe/keepawake.pid) 2>/dev/null   # stop the heartbeat FIRST\n"
printf "      kill -- -\$(cat ~/probe/bridge.pid) 2>/dev/null\n"
printf "      curl -s -X DELETE --unix-socket /.sprite/api.sock http://sprite/v1/tasks/zkc-bridge\n"
printf "      rm -f ~/probe/*.pid ~/probe/bridge.log ~/.codex/deepseek.env'\n"
printf "    (order matters: deleting the task while the heartbeat lives just\n"
printf "     re-registers it 60s later)\n\n"
DS_KEY=""; unset DS_KEY
sleep 0.3
