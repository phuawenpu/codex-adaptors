#!/usr/bin/env bash
# Keep a selected Sprites.dev Sprite continuously running for a chosen duration.
# Revision 9: pre-action Sprite inventory with lifecycle state and effective
# keep-awake hard-cap remaining time, plus idempotent Service replacement,
# authoritative startup checks, detached-process recovery, and diagnostics.
#
# On `start`, this helper also uploads the complete local ./workspace/ tree into
# the corresponding Sprite workspace folder before establishing the keepalive.
#
# Usage:
#   bash keepalive.sh                       # show inventory; optionally start/extend
#   bash keepalive.sh start 8               # show inventory, then keep alive 8h from now
#   bash keepalive.sh inventory             # show lifecycle + remaining hold; change nothing
#   bash keepalive.sh status                # inspect this helper's hold
#   bash keepalive.sh stop                  # release this helper's hold
#
# Optional environment variables:
#   SPRITE_NAME=<name>              Use this Sprite if it still exists.
#   SPRITE_ORG=<organization>       Pass -o <organization> to the Sprite CLI.
#   SPRITE_KEEPALIVE_HOURS=<hours>  Default duration without prompting.
#   SPRITE_TASK_NAME=<name>         Task name; default: manual-keepalive.
#   SPRITE_KEEPALIVE_USE_SERVICE=1|0 Prefer a Sprite Service heartbeat (default 1).
#   SPRITE_UPLOAD_WORKSPACE=1|0     Upload ./workspace/ on start (default 1).
#   SPRITE_WORKDIR=<absolute path>  Remote project root; otherwise uses
#                                   $HOME/workspaces/<current-dir-name>.

set -euo pipefail

MODE="${1:-start}"
REQUESTED_HOURS="${2:-${SPRITE_KEEPALIVE_HOURS:-}}"
TASK_NAME="${SPRITE_TASK_NAME:-manual-keepalive}"
SPRITE_NAME="${SPRITE_NAME:-}"
UPLOAD_WORKSPACE="${SPRITE_UPLOAD_WORKSPACE:-1}"
HOST_DIR="$PWD"
SPRITE_WORKDIR="${SPRITE_WORKDIR:-}"
WORKSPACE_UPLOAD_STATUS="not-run"

case "$MODE" in
  start|status|stop|inventory) ;;
  -h|--help|help)
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "error: unknown action '$MODE' (use start, inventory, status, or stop)" >&2
    exit 2
    ;;
esac

case "$TASK_NAME" in
  ''|*[!A-Za-z0-9._-]*)
    echo "error: SPRITE_TASK_NAME may contain only letters, digits, dot, underscore, and hyphen" >&2
    exit 2
    ;;
esac

case "$UPLOAD_WORKSPACE" in
  0|1) ;;
  *) echo "error: SPRITE_UPLOAD_WORKSPACE must be 0 or 1" >&2; exit 2 ;;
esac
if [ -n "$SPRITE_WORKDIR" ] && [[ "$SPRITE_WORKDIR" != /* ]]; then
  echo "error: SPRITE_WORKDIR must be an absolute path on the Sprite" >&2
  exit 2
fi

command -v sprite >/dev/null 2>&1 || {
  echo "error: the 'sprite' CLI is not installed or is not on PATH" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "error: python3 is required to parse 'sprite list' safely" >&2
  exit 1
}
if [ "$MODE" = start ] && [ "$UPLOAD_WORKSPACE" = 1 ]; then
  command -v tar >/dev/null 2>&1 || {
    echo "error: tar is required to upload ./workspace/" >&2
    exit 1
  }
fi

ORG=()
[ -n "${SPRITE_ORG:-}" ] && ORG=(-o "$SPRITE_ORG")

step() { printf '\n\033[1;36m=== %s\033[0m\n' "$*"; }
note() { printf '       %s\n' "$*"; }
warn() { printf '\033[1;33m  WARN\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

run_limited() {
  local seconds="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@" </dev/null
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

# Deliberately do not cache a Sprite name locally. Every invocation resolves the
# current Sprite inventory again. This mirrors the picker used by the Codex
# management script: query the structured API first, then parse the human table.
# A supplied SPRITE_NAME is only trusted when it is present in the current
# inventory; it is never treated as resume/cache state.
parse_sprite_api() {
  python3 -c '
import json, re, sys
raw = sys.stdin.read()
valid = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
out = []

def add(v):
    if isinstance(v, str):
        v = v.strip()
        if valid.fullmatch(v) and v not in out:
            out.append(v)

def emit(v):
    if isinstance(v, list):
        for item in v:
            if isinstance(item, dict):
                add(item.get("name") or item.get("sprite_name"))
    elif isinstance(v, dict):
        n = v.get("name") or v.get("sprite_name")
        if isinstance(n, str) and valid.fullmatch(n) and ({"id","status","state","url"} & set(v)):
            add(n)
        else:
            for item in v.values():
                if isinstance(item, dict):
                    n = item.get("name") or item.get("sprite_name")
                    if isinstance(n, str) and valid.fullmatch(n) and ({"id","status","state","url"} & set(item)):
                        add(n)

def walk(v):
    if isinstance(v, list):
        emit(v); return
    if not isinstance(v, dict):
        return
    found = False
    for k in ("sprites", "sprite_list"):
        if k in v:
            emit(v[k]); found = True
    for k in ("data", "result", "results", "response"):
        if isinstance(v.get(k), (dict, list)):
            walk(v[k]); found = True
    if not found and "items" in v:
        emit(v["items"])

try:
    root = json.loads(raw)
except Exception:
    # Some CLI builds can prepend harmless text. If so, try the largest JSON
    # object/array substring rather than declaring discovery dead immediately.
    starts = [i for i, ch in enumerate(raw) if ch in "[{"]
    root = None
    for i in starts:
        try:
            root = json.loads(raw[i:])
            break
        except Exception:
            pass
    if root is None:
        raise SystemExit
walk(root)
for n in out:
    print(n)
'
}

parse_sprite_list() {
  python3 -c '
import re, sys
raw = sys.stdin.read()
ansi_csi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ansi_osc = re.compile(r"\x1b\][^\x07]*(?:\x07|\x1b\\)")
valid = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
statuses = {"running", "warm", "cold", "stopped", "paused", "suspended"}
meta = {
    "name", "sprite", "sprites", "organization", "organisation", "org",
    "status", "state", "url", "created", "updated", "running", "stopped",
    "warm", "cold", "paused", "suspended", "total"
}
out = []

def clean(line):
    line = ansi_osc.sub("", line)
    line = ansi_csi.sub("", line)
    return (line.replace("\u00a0", " ")
                .replace("\u2007", " ")
                .replace("\u202f", " ")
                .replace("**", ""))

def add(v):
    v = v.strip().strip("*`")
    if valid.fullmatch(v) and v.lower() not in meta and v not in out:
        out.append(v)

lines = [clean(line.rstrip("\r\n")) for line in raw.splitlines()]

# 1) Current Sprites CLI table. Require both a lifecycle status and a
#    *.sprites.app URL, which prevents the organization summary line from being
#    mistaken for a Sprite. This does not depend on exact column widths/header.
for line in lines:
    low = line.lower()
    if ".sprites.app" not in low:
        continue
    sm = re.search(r"\b(running|warm|cold|stopped|paused|suspended)\b", low)
    if not sm:
        continue
    prefix = line[:sm.start()]
    # Prefer the first table cell. Accept the common Unicode/ASCII vertical
    # separators, including the heavier box character some terminals render.
    cells = [c.strip() for c in re.split(r"[│┃|]", prefix) if c.strip()]
    for cell in cells:
        candidate = cell.strip().strip("*`")
        if valid.fullmatch(candidate):
            add(candidate)
            break
    else:
        # Borderless fallback: the final identifier before the status is the
        # Sprite name in aligned output.
        toks = re.findall(r"[A-Za-z0-9][A-Za-z0-9._-]*", prefix)
        if toks:
            add(toks[-1])

# 2) Header-aware parser copied from the Codex management script. This handles
#    older box tables and aligned-column output that may omit a sprites.app URL.
def norm(s):
    return re.sub(r"\s+", " ", s.strip()).upper()

def table(rows):
    hi = ni = None
    for i, row in enumerate(rows):
        for j, c in enumerate(row):
            if norm(c) in {"NAME", "SPRITE", "SPRITE NAME", "SPRITE_NAME"}:
                hi, ni = i, j
                break
        if hi is not None:
            break
    if hi is None:
        return []
    vals = []
    for row in rows[hi + 1:]:
        if ni < len(row):
            v = row[ni].strip().strip("*`")
            if valid.fullmatch(v) and v.lower() not in meta:
                vals.append(v)
    return vals

rows = []
for line in lines:
    if any(ch in line for ch in ("│", "┃", "|")):
        cells = [x.strip() for x in re.split(r"[│┃|]", line)]
        if cells and not cells[0]:
            cells.pop(0)
        if cells and not cells[-1]:
            cells.pop()
        if cells:
            rows.append(cells)
for v in table(rows):
    add(v)

spaced = []
for line in lines:
    cells = [x.strip() for x in re.split(r"\s{2,}", line.strip()) if x.strip()]
    if len(cells) >= 2:
        spaced.append(cells)
for v in table(spaced):
    add(v)

# 3) Final conservative row fallback: a line with table separators and a known
#    lifecycle status can yield its first identifier even without the URL.
for line in lines:
    if not any(ch in line for ch in ("│", "┃", "|")):
        continue
    low = line.lower()
    if not re.search(r"\b(running|warm|cold|stopped|paused|suspended)\b", low):
        continue
    cells = [c.strip().strip("*`") for c in re.split(r"[│┃|]", line) if c.strip()]
    if len(cells) >= 2 and valid.fullmatch(cells[0]):
        add(cells[0])

for n in out:
    print(n)
'
}

discover_sprite_names() {
  local api_raw="" list_raw="" parsed=""

  # Match the known-working Codex management script: structured API first.
  printf '       querying sprite api ... ' >&2
  api_raw="$(run_limited 20 sprite api "${ORG[@]}" /sprites 2>/dev/null || true)"
  if [ -n "$api_raw" ]; then
    parsed="$(printf '%s' "$api_raw" | parse_sprite_api || true)"
  fi
  printf '%s\n' "$([ -n "$parsed" ] && echo ok || echo 'no usable names')" >&2
  if [ -n "$parsed" ]; then
    printf '%s\n' "$parsed"
    return 0
  fi

  # Some CLI builds render the human table on stderr. Capture BOTH streams.
  printf '       querying sprite list ... ' >&2
  list_raw="$(run_limited 20 sprite list "${ORG[@]}" 2>&1 || true)"
  parsed="$(printf '%s\n' "$list_raw" | parse_sprite_list || true)"
  printf '%s\n' "$([ -n "$parsed" ] && echo ok || echo 'no usable names')" >&2
  [ -n "$parsed" ] && printf '%s\n' "$parsed"
}

sprite_control_status() {
  local name="$1" raw="" status=""
  raw="$(run_limited 15 sprite api "${ORG[@]}" "/sprites/$name" 2>/dev/null || true)"
  [ -n "$raw" ] || { printf 'unknown\n'; return 0; }
  status="$(printf '%s' "$raw" | python3 -c '
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw)
except Exception:
    starts=[i for i,c in enumerate(raw) if c in "[{" ]
    d=None
    for i in starts:
        try: d=json.loads(raw[i:]); break
        except Exception: pass
if not isinstance(d,dict):
    raise SystemExit
for obj in (d, d.get("data"), d.get("result"), d.get("sprite")):
    if not isinstance(obj,dict):
        continue
    v=obj.get("status") or obj.get("state")
    if isinstance(v,dict):
        v=v.get("status") or v.get("state") or v.get("name")
    if isinstance(v,str) and v.strip():
        print(v.strip().lower()); break
' 2>/dev/null || true)"
  printf '%s\n' "${status:-unknown}"
}

# Probe only an already-running Sprite. This deliberately avoids `sprite exec`
# against warm/cold Sprites, because an exec is itself a wake-up action.
# Output fields (tab separated): hard_deadline, source, task_count, max_lease_epoch,
# known_hard_count, unknown_hard_count.
probe_running_sprite_hold() {
  local name="$1"
  run_limited 20 sprite exec "${ORG[@]}" -s "$name" -- bash -lc '
set -u
raw="$(curl -sS --max-time 8 --unix-socket /.sprite/api.sock http://sprite/v1/tasks 2>/dev/null || true)"
python3 - "$raw" <<'"'"'PYHOLD'"'"'
import datetime as dt, glob, json, os, sys, time

now=int(time.time())
raw=sys.argv[1] if len(sys.argv)>1 else ""
try:
    root=json.loads(raw) if raw else {}
except Exception:
    root={}
tasks=root.get("tasks",[]) if isinstance(root,dict) else []
if not isinstance(tasks,list): tasks=[]

active={}
def iso_epoch(v):
    if not isinstance(v,str) or not v.strip(): return 0
    s=v.strip()
    try:
        if s.endswith("Z"): s=s[:-1]+"+00:00"
        x=dt.datetime.fromisoformat(s)
        if x.tzinfo is None: x=x.replace(tzinfo=dt.timezone.utc)
        return int(x.timestamp())
    except Exception:
        return 0

for t in tasks:
    if not isinstance(t,dict): continue
    name=str(t.get("name","")).strip()
    if not name: continue
    exp=iso_epoch(t.get("expires_at"))
    active[name]=max(active.get(name,0),exp)

candidates=[]
matched=set()
home=os.path.expanduser("~")

# keepalive.sh state: filename stem equals the validated task name.
for f in glob.glob(os.path.join(home,".local/state/sprite-keepalive/*.deadline")):
    task=os.path.basename(f)[:-len(".deadline")]
    try: deadline=int(open(f).read().strip())
    except Exception: continue
    if task in active and deadline>now:
        candidates.append((deadline,"keepalive:"+task))
        matched.add(task)

# sprite-codex state: TASK_NAME == SESSION_TAG in the launcher.
base=os.path.join(home,".local/state/sprite-codex")
for sf in glob.glob(os.path.join(base,"hold-state-*")):
    tag=os.path.basename(sf)[len("hold-state-"):]
    try: state=open(sf).read().strip().lower()
    except Exception: continue
    df=os.path.join(base,"hold-deadline-"+tag)
    try: deadline=int(open(df).read().strip())
    except Exception: continue
    if state=="active" and tag in active and deadline>now:
        candidates.append((deadline,"codex:"+tag))
        matched.add(tag)

if candidates:
    hard,source=max(candidates,key=lambda x:x[0])
else:
    hard=0; source="-"
max_lease=max(active.values(),default=0)
unknown=len(set(active)-matched)
print("%d\t%s\t%d\t%d\t%d\t%d" % (hard,source,len(active),max_lease,len(matched),unknown))
PYHOLD
' 2>/dev/null
}

format_remaining() {
  local seconds="$1"
  if [ "$seconds" -le 0 ] 2>/dev/null; then
    printf 'expired'
    return
  fi
  if [ "$seconds" -ge 86400 ]; then
    printf '%dd %02dh %02dm' "$((seconds/86400))" "$(((seconds%86400)/3600))" "$(((seconds%3600)/60))"
  else
    printf '%dh %02dm' "$((seconds/3600))" "$(((seconds%3600)/60))"
  fi
}

format_epoch_utc() {
  local epoch="$1"
  date -u -d "@$epoch" '+%Y-%m-%d %H:%M UTC' 2>/dev/null \
    || date -u -r "$epoch" '+%Y-%m-%d %H:%M UTC' 2>/dev/null \
    || printf '%s' "$epoch"
}

show_sprite_inventory() {
  local names=() name status probe hard source tasks lease known unknown now remaining label deadline_text source_text
  while IFS= read -r name; do
    [ -n "$name" ] && names+=("$name")
  done < <(discover_sprite_names)

  if [ "${#names[@]}" -eq 0 ]; then
    warn "no current Sprites could be discovered"
    return 1
  fi

  printf '  %-28s %-10s %-17s %-22s %s\n' "SPRITE" "STATE" "HOLD REMAINING" "HARD DEADLINE (UTC)" "SOURCE / TASKS"
  printf '  %-28s %-10s %-17s %-22s %s\n' "----------------------------" "----------" "-----------------" "----------------------" "------------------------------"
  now="$(date +%s)"

  for name in "${names[@]}"; do
    status="$(sprite_control_status "$name")"
    label="-"; deadline_text="-"; source_text="not probed"

    if [ "$status" = running ]; then
      probe="$(probe_running_sprite_hold "$name" || true)"
      if [ -n "$probe" ]; then
        IFS=$'\t' read -r hard source tasks lease known unknown <<<"$probe"
        hard="${hard:-0}"; tasks="${tasks:-0}"; lease="${lease:-0}"; known="${known:-0}"; unknown="${unknown:-0}"
        if [ "$hard" -gt "$now" ] 2>/dev/null; then
          remaining=$((hard-now))
          label="$(format_remaining "$remaining")"
          deadline_text="$(format_epoch_utc "$hard")"
          source_text="$source; tasks=$tasks"
          [ "$unknown" -gt 0 ] 2>/dev/null && source_text="$source_text (+$unknown hard-cap unknown)"
        elif [ "$tasks" -gt 0 ] 2>/dev/null; then
          label="unknown*"
          deadline_text="rolling lease only"
          source_text="tasks=$tasks; hard cap not recorded"
        else
          label="none"
          deadline_text="-"
          source_text="no Tasks API hold"
        fi
      else
        label="probe failed"
        source_text="running, but hold state unreadable"
      fi
    else
      case "$status" in
        warm|cold|stopped|paused|suspended) source_text="not probed (avoids wake)" ;;
        *) source_text="lifecycle unknown; not probed" ;;
      esac
    fi

    printf '  %-28s %-10s %-17s %-22s %s\n' "$name" "$status" "$label" "$deadline_text" "$source_text"
  done
  echo
  note "HOLD REMAINING is the real helper hard cap, not the rolling 5-minute Tasks API lease."
  note "Only Sprites already reported as running are exec-probed; warm/cold Sprites are left untouched."
  note "* 'unknown' means a live Tasks API hold exists but this script cannot find its longer-term deadline state."
}

sprite_reachable() {
  run_limited 25 sprite exec "${ORG[@]}" -s "$1" -- true >/dev/null 2>&1
}

pick_sprite() {
  local names=() name choice i
  while IFS= read -r name; do
    [ -n "$name" ] && names+=("$name")
  done < <(discover_sprite_names)

  # SPRITE_NAME is only a request. If we discovered a current inventory, it
  # must be present there. Never let an old exported value override live state.
  if [ -n "$SPRITE_NAME" ] && [ "${#names[@]}" -gt 0 ]; then
    for name in "${names[@]}"; do
      if [ "$name" = "$SPRITE_NAME" ]; then
        note "using SPRITE_NAME=$SPRITE_NAME (confirmed in current inventory)"
        return 0
      fi
    done
    warn "SPRITE_NAME '$SPRITE_NAME' is not present in the current inventory; ignoring it"
    SPRITE_NAME=""
  fi

  if [ "${#names[@]}" -eq 1 ]; then
    SPRITE_NAME="${names[0]}"
    note "one Sprite found: $SPRITE_NAME"
    return 0
  fi

  if [ "${#names[@]}" -gt 1 ]; then
    echo "  Sprites:"
    i=1
    for name in "${names[@]}"; do
      printf '    %d) %s\n' "$i" "$name"
      i=$((i + 1))
    done
    while :; do
      printf '  choose [1-%d] or type one of the current Sprite names: ' "${#names[@]}"
      read -r choice || die "no Sprite selected"
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#names[@]}" ]; then
        SPRITE_NAME="${names[$((choice - 1))]}"
        return 0
      fi
      for name in "${names[@]}"; do
        if [ "$choice" = "$name" ]; then
          SPRITE_NAME="$name"
          return 0
        fi
      done
      warn "'$choice' is not in the current Sprite inventory"
    done
  fi

  # Only when both automatic discovery routes fail do we permit manual entry.
  # Validate it with a bounded exec before proceeding.
  warn "could not discover current Sprite names from 'sprite api /sprites' or 'sprite list'"
  if [ -n "$SPRITE_NAME" ]; then
    warn "automatic inventory discovery failed; checking supplied SPRITE_NAME=$SPRITE_NAME"
    sprite_reachable "$SPRITE_NAME" && return 0
  fi
  printf '  enter the Sprite name: '
  read -r SPRITE_NAME || die "no Sprite selected"
  [ -n "$SPRITE_NAME" ] || die "no Sprite selected"
  sprite_reachable "$SPRITE_NAME" || die "Sprite '$SPRITE_NAME' is unreachable"
}

hours_to_seconds() {
  awk -v hours="$1" 'BEGIN {
    if (hours !~ /^[0-9]+([.][0-9]+)?$/ || hours <= 0) exit 1
    seconds = int(hours * 3600 + 0.5)
    if (seconds < 60) exit 1
    printf "%d", seconds
  }'
}

step "current Sprite keep-awake status"
show_sprite_inventory || true

if [ "$MODE" = inventory ]; then
  note "inventory mode is read-only; no keep-awake hold was changed"
  exit 0
fi

# In the normal interactive `start` path, do not even select or touch a Sprite
# until the user has seen the inventory and explicitly decides an extension is
# needed. Supplying `start <hours>` remains an explicit command and proceeds.
if [ "$MODE" = start ] && [ -z "$REQUESTED_HOURS" ] && [ -t 0 ]; then
  printf '  Start or extend a keep-awake hold after reviewing the table? [y/N]: '
  read -r _apply || true
  case "${_apply,,}" in
    y|yes) ;;
    *) note "no action requested; existing Sprite holds were left unchanged"; exit 0 ;;
  esac
fi

step "choose Sprite"
pick_sprite
note "selected Sprite: $SPRITE_NAME"

base_name="$(basename "$HOST_DIR")"
safe_name="$(printf '%s' "$base_name" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')"
[ -n "$safe_name" ] || safe_name=workspace

TOTAL_SECONDS=0
if [ "$MODE" = start ]; then
  if [ -z "$REQUESTED_HOURS" ]; then
    printf '  Keep Sprite running for how many hours? [5]: '
    read -r REQUESTED_HOURS || true
    REQUESTED_HOURS="${REQUESTED_HOURS:-5}"
  fi
  TOTAL_SECONDS="$(hours_to_seconds "$REQUESTED_HOURS")" || \
    die "hours must be a positive number representing at least 60 seconds"
fi

REMOTE_FILE="/tmp/sprite-keepalive-setup-$$.sh"
LOCAL_FILE="$(mktemp "${TMPDIR:-/tmp}/sprite-keepalive.XXXXXX")"
cleanup_files=("$LOCAL_FILE")
cleanup() {
  local f
  for f in "${cleanup_files[@]:-}"; do
    [ -n "$f" ] && rm -f -- "$f" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

upload_workspace_tree() {
  local local_workspace="$HOST_DIR/workspace"
  local archive remote_archive remote_root_label file_count entry_count

  if [ "$UPLOAD_WORKSPACE" != 1 ]; then
    WORKSPACE_UPLOAD_STATUS="disabled"
    note "workspace upload disabled by SPRITE_UPLOAD_WORKSPACE=0"
    return 0
  fi
  if [ ! -d "$local_workspace" ]; then
    WORKSPACE_UPLOAD_STATUS="missing"
    warn "no local workspace/ directory found at $local_workspace; nothing to upload"
    return 0
  fi

  archive="$(mktemp "${TMPDIR:-/tmp}/sprite-keepalive-workspace.XXXXXX.tar.gz")"
  cleanup_files+=("$archive")

  # Archive the contents of workspace/, not the directory itself. This preserves
  # nested paths, dotfiles, symlinks, and executable bits without dereferencing
  # symlinks. Extraction is an overlay: remote-only files are never deleted.
  tar -C "$local_workspace" -czf "$archive" . \
    || die "could not archive local workspace/ directory"

  file_count="$(find "$local_workspace" -type f | wc -l | tr -d ' ')"
  entry_count="$(find "$local_workspace" -mindepth 1 | wc -l | tr -d ' ')"
  remote_archive="/tmp/sprite-keepalive-workspace-$$.tar.gz"

  if [ -n "$SPRITE_WORKDIR" ]; then
    remote_root_label="$SPRITE_WORKDIR"
  else
    remote_root_label="\$HOME/workspaces/$safe_name"
  fi

  step "upload local workspace/ tree"
  note "source: $local_workspace"
  note "entries: ${entry_count:-0} total, ${file_count:-0} regular file(s)"
  note "destination: ${remote_root_label}/workspace/"
  note "upload is an overlay; remote-only files are preserved"

  if [ -n "$SPRITE_WORKDIR" ]; then
    sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
      --file "$archive:$remote_archive" -- \
      bash -lc '
set -Eeuo pipefail
archive=$1
root=$2
dest="$root/workspace"
trap '\''rm -f -- "$archive"'\'' EXIT
mkdir -p "$dest"
tar --no-same-owner -xzf "$archive" -C "$dest"
printf "       uploaded workspace to %s\n" "$dest"
' _ "$remote_archive" "$SPRITE_WORKDIR" \
      || die "workspace/ upload failed"
  else
    sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
      --file "$archive:$remote_archive" -- \
      bash -lc '
set -Eeuo pipefail
archive=$1
project=$2
root="$HOME/workspaces/$project"
dest="$root/workspace"
trap '\''rm -f -- "$archive"'\'' EXIT
mkdir -p "$dest"
tar --no-same-owner -xzf "$archive" -C "$dest"
printf "       uploaded workspace to %s\n" "$dest"
' _ "$remote_archive" "$safe_name" \
      || die "workspace/ upload failed"
  fi

  WORKSPACE_UPLOAD_STATUS="uploaded"
  note "workspace upload complete"
}

cat > "$LOCAL_FILE" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required}"
TOTAL_SECONDS="${2:-0}"
TASK_NAME="${3:?task name required}"
USE_SERVICE="${4:-1}"
SELF="$0"
trap 'rm -f "$SELF"' EXIT

STATE_DIR="$HOME/.local/state/sprite-keepalive"
SAFE_TASK="$(printf '%s' "$TASK_NAME" | tr -c 'A-Za-z0-9._-' '_')"
PID_FILE="$STATE_DIR/$SAFE_TASK.pid"
DEADLINE_FILE="$STATE_DIR/$SAFE_TASK.deadline"
LAST_OK_FILE="$STATE_DIR/$SAFE_TASK.last-ok"
FAIL_COUNT_FILE="$STATE_DIR/$SAFE_TASK.fail-count"
HEARTBEAT_FILE="$STATE_DIR/$SAFE_TASK-heartbeat.sh"
SERVICE_RUNNER="$STATE_DIR/$SAFE_TASK-service-runner.sh"
LOG_FILE="$STATE_DIR/$SAFE_TASK.log"
SERVICE_NAME="keepalive-$SAFE_TASK"
SERVICE_LOG="/.sprite/logs/services/$SERVICE_NAME.log"
SERVICE_START_LOG="$STATE_DIR/$SAFE_TASK-service-start.log"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

api() {
  curl -fsS --max-time 10 --unix-socket /.sprite/api.sock \
    -H 'Content-Type: application/json' "$@"
}

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '%s %s\n' "$(ts)" "$*" >>"$LOG_FILE"; }

service_available() {
  command -v sprite-env >/dev/null 2>&1 && sprite-env services --help >/dev/null 2>&1
}

service_json() {
  service_available || return 1
  sprite-env services get "$SERVICE_NAME" 2>/dev/null
}

service_status() {
  local raw
  raw="$(service_json)" || return 1
  python3 - "$raw" <<'PYSERVICE'
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)
state = data.get("state") if isinstance(data, dict) else None
status = state.get("status", "") if isinstance(state, dict) else ""
print(str(status).lower())
PYSERVICE
}

service_exists() {
  service_json >/dev/null 2>&1
}

service_running() {
  [ "$(service_status 2>/dev/null || true)" = running ]
}

stop_service() {
  if service_available; then
    sprite-env services stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi
}

delete_service_best_effort() {
  if service_available; then
    sprite-env services delete "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi
}

wait_service_absent() {
  local _
  service_available || return 0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    service_exists || return 0
    sleep 1
  done
  return 1
}

managed_pid_alive() {
  local pid="${1:-}" cmdline=""
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  if [ -r "/proc/$pid/cmdline" ]; then
    cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
    [[ "$cmdline" == *"$HEARTBEAT_FILE"* ]] || return 1
  fi
  return 0
}

stop_managed_runtime() {
  local preserve_deadline="${1:-0}" pid=""
  stop_service
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi
  if managed_pid_alive "$pid"; then
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
  fi
  rm -f "$PID_FILE"
  if [ "$preserve_deadline" != 1 ]; then
    rm -f "$DEADLINE_FILE" "$LAST_OK_FILE" "$FAIL_COUNT_FILE"
  fi
}

show_all_tasks() {
  local raw
  raw="$(api http://sprite/v1/tasks 2>/dev/null || true)"
  if [ -z "$raw" ]; then
    echo "  Tasks API could not be read"
    return 1
  fi
  python3 - "$raw" <<'PYTASKS'
import json,sys
try: d=json.loads(sys.argv[1])
except Exception:
    print("  raw: "+sys.argv[1][:500]); raise SystemExit
tasks=d.get("tasks",[]) if isinstance(d,dict) else []
if not tasks:
    print("  (none)")
else:
    for t in tasks:
        print("  %-34s started=%s expires=%s" % (
            str(t.get("name","?")), str(t.get("started_at","?")), str(t.get("expires_at","?"))))
PYTASKS
}

case "$MODE" in
  status)
    echo "Sprite: $(hostname)"
    echo "Managed task: $TASK_NAME"
    echo "Managed service: $SERVICE_NAME"

    fallback_alive=0
    if [ -f "$PID_FILE" ]; then
      pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      if managed_pid_alive "$pid"; then
        fallback_alive=1
        echo "Managed heartbeat process: running (pid $pid)"
      else
        echo "Managed heartbeat process: stale, stopped, or not this helper"
      fi
    else
      echo "Managed heartbeat process: not running"
    fi

    service_is_running=0
    if service_available; then
      echo "Service definition/state:"
      if service_data="$(service_json 2>/dev/null)"; then
        printf '%s\n' "$service_data" | sed 's/^/  /'
        service_running && service_is_running=1
      else
        echo "  service not defined"
      fi
    else
      echo "Service status: sprite-env services unavailable"
    fi

    now="$(date +%s)"
    if [ -f "$DEADLINE_FILE" ]; then
      deadline="$(cat "$DEADLINE_FILE" 2>/dev/null || echo 0)"
      echo "Requested deadline epoch: $deadline"
      date -u -d "@$deadline" '+Requested deadline UTC: %Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
        || date -u -r "$deadline" '+Requested deadline UTC: %Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
        || true
      if [ "$deadline" -gt "$now" ] 2>/dev/null; then
        remaining=$((deadline-now))
        printf 'Remaining requested hold: %dh %02dm %02ds\n' "$((remaining/3600))" "$(((remaining%3600)/60))" "$((remaining%60))"
      else
        echo "Remaining requested hold: expired"
      fi
    else
      deadline=0
      echo "Requested deadline: not recorded"
    fi

    if [ -f "$LAST_OK_FILE" ]; then
      last_ok="$(cat "$LAST_OK_FILE" 2>/dev/null || echo 0)"
      date -u -d "@$last_ok" '+Last successful refresh UTC: %Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
        || date -u -r "$last_ok" '+Last successful refresh UTC: %Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
        || echo "Last successful refresh epoch: $last_ok"
      age=$((now-last_ok))
      echo "Last successful refresh age: ${age}s"
    else
      last_ok=0
      echo "Last successful refresh: none recorded"
    fi
    failures="$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)"
    echo "Consecutive refresh failures: $failures"

    task_present=0
    echo "Managed Tasks API record:"
    if api "http://sprite/v1/tasks/$TASK_NAME" 2>/dev/null; then
      task_present=1
    else
      echo "  task '$TASK_NAME' is not currently registered"
    fi
    if [ "$task_present" = 0 ] && { [ "$fallback_alive" = 1 ] || [ "$service_is_running" = 1 ]; }; then
      echo "WARNING: heartbeat runtime/deadline indicates the hold should be active, but the Tasks API record is missing."
    fi
    if [ "$deadline" -gt "$now" ] 2>/dev/null && [ "$last_ok" -gt 0 ] 2>/dev/null && [ $((now-last_ok)) -gt 180 ]; then
      echo "WARNING: last successful refresh is older than 180 seconds."
    fi

    echo "All current Tasks API holds:"
    show_all_tasks || true
    echo "Recent heartbeat log:"
    tail -20 "$LOG_FILE" 2>/dev/null | sed 's/^/  /' || echo "  (no log yet)"
    echo "Recent Sprite Service log:"
    tail -30 "$SERVICE_LOG" 2>/dev/null | sed 's/^/  /' || echo "  (no service log yet)"
    ;;

  stop)
    stop_managed_runtime 0
    api -X DELETE "http://sprite/v1/tasks/$TASK_NAME" >/dev/null 2>&1 || true
    delete_service_best_effort
    log "STOP requested; task released and managed service/process stopped"
    echo "Released task '$TASK_NAME' and stopped this helper's managed heartbeat."
    echo "Other active sessions, services, and task holds are untouched."
    ;;

  start)
    case "$TOTAL_SECONDS" in
      ''|*[!0-9]*) echo "invalid duration" >&2; exit 2 ;;
    esac
    [ "$TOTAL_SECONDS" -ge 60 ] || { echo "duration must be at least 60 seconds" >&2; exit 2; }
    case "$USE_SERVICE" in 0|1) ;; *) echo "invalid service mode" >&2; exit 2 ;; esac

    now="$(date +%s)"
    requested_deadline=$((now + TOTAL_SECONDS))
    old_deadline=0
    if [ -f "$DEADLINE_FILE" ]; then
      old_deadline="$(cat "$DEADLINE_FILE" 2>/dev/null || echo 0)"
      case "$old_deadline" in ''|*[!0-9]*) old_deadline=0 ;; esac
    fi
    if [ "$old_deadline" -gt "$requested_deadline" ]; then
      deadline="$old_deadline"
      echo "Existing keep-alive deadline is later; preserving it instead of shortening the hold."
    else
      deadline="$requested_deadline"
    fi

    # Replace only this helper's runtime. Deleting and recreating its Service
    # avoids the stop/start transition race that can leave an existing Service
    # reported as started without launching a new heartbeat process.
    stop_managed_runtime 1
    if service_available; then
      delete_service_best_effort
      if ! wait_service_absent; then
        echo "old Sprite Service '$SERVICE_NAME' did not disappear after delete" >&2
        echo "refusing to start a second heartbeat runtime" >&2
        rm -f "$DEADLINE_FILE" "$LAST_OK_FILE" "$FAIL_COUNT_FILE" "$PID_FILE"
        exit 1
      fi
    fi
    rm -f "$PID_FILE" "$LAST_OK_FILE" "$SERVICE_START_LOG"
    printf '%s\n' "$deadline" > "$DEADLINE_FILE"
    printf '0\n' > "$FAIL_COUNT_FILE"
    chmod 600 "$DEADLINE_FILE" "$FAIL_COUNT_FILE"
    touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
    log "START requested deadline=$deadline service_preferred=$USE_SERVICE"

    cat > "$HEARTBEAT_FILE" <<HEARTBEAT
#!/usr/bin/env bash
set -uo pipefail
TASK_NAME='$TASK_NAME'
SERVICE_NAME='$SERVICE_NAME'
STATE_DIR='${STATE_DIR}'
DEADLINE_FILE='${DEADLINE_FILE}'
LAST_OK_FILE='${LAST_OK_FILE}'
FAIL_COUNT_FILE='${FAIL_COUNT_FILE}'
PID_FILE='${PID_FILE}'
LOG_FILE='${LOG_FILE}'

api() {
  curl -fsS --max-time 10 --unix-socket /.sprite/api.sock \\
    -H 'Content-Type: application/json' "\$@"
}
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '%s %s\\n' "\$(ts)" "\$*" >>"\$LOG_FILE"; }
release() {
  api -X DELETE "http://sprite/v1/tasks/\$TASK_NAME" >/dev/null 2>&1 || true
  rm -f "\$PID_FILE"
}
trap 'release; exit 0' EXIT INT TERM HUP

printf '%s\\n' "\$\$" > "\$PID_FILE"
chmod 600 "\$PID_FILE"
failures=0
last_failure_reported=0
while :; do
  now="\$(date +%s)"
  deadline="\$(cat "\$DEADLINE_FILE" 2>/dev/null || echo 0)"
  case "\$deadline" in ''|*[!0-9]*) deadline=0 ;; esac
  if [ "\$deadline" -le "\$now" ]; then
    log "deadline reached; releasing task"
    break
  fi

  if api -X PUT "http://sprite/v1/tasks/\$TASK_NAME" -d '{"expire":"5m"}' >/dev/null 2>&1; then
    printf '%s\\n' "\$now" > "\$LAST_OK_FILE"
    chmod 600 "\$LAST_OK_FILE"
    if [ "\$failures" -gt 0 ]; then
      log "refresh recovered after \$failures consecutive failure(s)"
    fi
    failures=0
    printf '0\\n' > "\$FAIL_COUNT_FILE"
  else
    failures=\$((failures+1))
    printf '%s\\n' "\$failures" > "\$FAIL_COUNT_FILE"
    log "refresh FAILED consecutive_failures=\$failures"
  fi

  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    now="\$(date +%s)"
    deadline="\$(cat "\$DEADLINE_FILE" 2>/dev/null || echo 0)"
    [ "\$now" -lt "\$deadline" ] || break
    sleep 5 & wait \$!
  done
done

release
trap - EXIT INT TERM HUP
if command -v sprite-env >/dev/null 2>&1; then
  sprite-env services stop "\$SERVICE_NAME" >/dev/null 2>&1 || true
fi
exit 0
HEARTBEAT
    chmod 700 "$HEARTBEAT_FILE"

    cat > "$SERVICE_RUNNER" <<RUNNER
#!/usr/bin/env bash
exec '$HEARTBEAT_FILE'
RUNNER
    chmod 700 "$SERVICE_RUNNER"

    startup_epoch="$(date +%s)"

    start_detached_heartbeat() {
      rm -f "$PID_FILE" "$LAST_OK_FILE"
      if command -v setsid >/dev/null 2>&1; then
        nohup setsid bash "$HEARTBEAT_FILE" >>"$LOG_FILE" 2>&1 </dev/null &
      else
        nohup bash "$HEARTBEAT_FILE" >>"$LOG_FILE" 2>&1 </dev/null &
      fi
    }

    runtime_ready() {
      local runtime_kind="$1" pid="" last_ok=""
      [ -s "$PID_FILE" ] || return 1
      pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      managed_pid_alive "$pid" || return 1
      [ -s "$LAST_OK_FILE" ] || return 1
      last_ok="$(cat "$LAST_OK_FILE" 2>/dev/null || true)"
      case "$last_ok" in ''|*[!0-9]*) return 1 ;; esac
      [ "$last_ok" -ge "$startup_epoch" ] || return 1
      api "http://sprite/v1/tasks/$TASK_NAME" >/dev/null 2>&1 || return 1
      if [ "$runtime_kind" = service ]; then
        service_running || return 1
      fi
      return 0
    }

    wait_runtime_ready() {
      local runtime_kind="$1" _
      for _ in $(seq 1 30); do
        runtime_ready "$runtime_kind" && return 0
        sleep 1
      done
      return 1
    }

    show_start_diagnostics() {
      echo "Service create/start stream:" >&2
      tail -50 "$SERVICE_START_LOG" 2>/dev/null >&2 || echo "  (no captured Service start stream)" >&2
      echo "Service definition/state:" >&2
      service_json 2>/dev/null | sed 's/^/  /' >&2 || echo "  (service not defined)" >&2
      echo "Sprite Service log ($SERVICE_LOG):" >&2
      tail -50 "$SERVICE_LOG" 2>/dev/null | sed 's/^/  /' >&2 || echo "  (no service log)" >&2
      echo "Heartbeat state log ($LOG_FILE):" >&2
      tail -50 "$LOG_FILE" 2>/dev/null | sed 's/^/  /' >&2 || echo "  (no heartbeat log)" >&2
    }

    cleanup_failed_start() {
      stop_managed_runtime 0
      api -X DELETE "http://sprite/v1/tasks/$TASK_NAME" >/dev/null 2>&1 || true
      delete_service_best_effort
    }

    # Establish a short hold synchronously so the Sprite cannot pause during
    # startup. LAST_OK_FILE is deliberately left absent: only the new heartbeat
    # process may write it, making startup verification authoritative.
    if ! api -X PUT "http://sprite/v1/tasks/$TASK_NAME" \
      -d '{"expire":"5m"}' >/dev/null; then
      echo "could not establish the initial Tasks API hold" >&2
      cleanup_failed_start
      exit 1
    fi

    runtime_kind=detached
    service_candidate=0
    if [ "$USE_SERVICE" = 1 ] && service_available; then
      : > "$SERVICE_START_LOG"
      chmod 600 "$SERVICE_START_LOG"
      if sprite-env services create "$SERVICE_NAME" --cmd "$SERVICE_RUNNER" \
          --duration 15s >"$SERVICE_START_LOG" 2>&1; then
        service_candidate=1
      else
        log "Sprite Service create failed; trying detached heartbeat"
        echo "WARNING: Sprite Service creation failed; using detached heartbeat fallback." >&2
        show_start_diagnostics
      fi

      if [ "$service_candidate" = 1 ]; then
        if wait_runtime_ready service; then
          runtime_kind=service
          log "heartbeat verified as Sprite Service $SERVICE_NAME"
        else
          log "Sprite Service did not become healthy; trying detached heartbeat"
          echo "WARNING: Sprite Service did not become healthy; using detached heartbeat fallback." >&2
          show_start_diagnostics
          stop_service
          delete_service_best_effort
          if ! wait_service_absent; then
            echo "failed to remove unhealthy Sprite Service '$SERVICE_NAME'; refusing a duplicate heartbeat" >&2
            cleanup_failed_start
            exit 1
          fi
          rm -f "$PID_FILE" "$LAST_OK_FILE"
        fi
      else
        delete_service_best_effort
        if ! wait_service_absent; then
          echo "failed to remove partial Sprite Service '$SERVICE_NAME'; refusing a duplicate heartbeat" >&2
          cleanup_failed_start
          exit 1
        fi
      fi
    fi

    if [ "$runtime_kind" != service ]; then
      start_detached_heartbeat
      if ! wait_runtime_ready detached; then
        echo "heartbeat failed to become healthy as either a Service or detached process" >&2
        show_start_diagnostics
        cleanup_failed_start
        exit 1
      fi
      runtime_kind=detached
      log "heartbeat verified as detached process"
    fi

    pid="$(cat "$PID_FILE")"

    if [ "$runtime_kind" = service ]; then
      echo "Heartbeat managed by Sprite Service '$SERVICE_NAME' (current pid $pid)."
      echo "The Service restarts on a future cold wake; it cannot autonomously wake a Sprite after a task lapse."
    else
      echo "Heartbeat running as detached process inside Sprite $(hostname) (pid $pid)."
    fi
    echo "Task name: $TASK_NAME"
    date -u -d "@$deadline" '+Keep-awake deadline: %Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
      || date -u -r "$deadline" '+Keep-awake deadline: %Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
      || echo "Keep-awake deadline epoch: $deadline"
    remaining=$((deadline-$(date +%s)))
    printf 'Remaining: %dh %02dm %02ds\n' "$((remaining/3600))" "$(((remaining%3600)/60))" "$((remaining%60))"
    echo "Tasks API verification:"
    api "http://sprite/v1/tasks/$TASK_NAME"
    echo "All current Tasks API holds:"
    show_all_tasks || true
    echo
    echo "Unrelated shell tabs, TTY sessions, services, and other task holds were not modified."
    ;;

  *) echo "invalid mode" >&2; exit 2 ;;
esac
REMOTE
chmod 700 "$LOCAL_FILE"

if [ "$MODE" = start ]; then
  upload_workspace_tree
fi

step "$MODE keep-awake hold"
if ! sprite exec "${ORG[@]}" -s "$SPRITE_NAME" \
     --file "$LOCAL_FILE:$REMOTE_FILE" -- \
     bash "$REMOTE_FILE" "$MODE" "$TOTAL_SECONDS" "$TASK_NAME" "${SPRITE_KEEPALIVE_USE_SERVICE:-1}"; then
  die "could not $MODE the keep-awake hold on Sprite '$SPRITE_NAME'"
fi

if [ "$MODE" = start ]; then
  case "$WORKSPACE_UPLOAD_STATUS" in
    uploaded) note "local ./workspace/ was overlaid into the corresponding Sprite workspace before the hold started" ;;
    missing)  note "no local ./workspace/ existed, so no workspace files were uploaded" ;;
    disabled) note "workspace upload was disabled for this start" ;;
  esac
  note "the heartbeat runs inside the Sprite; this terminal may now disconnect"
  note "rerun '$0 status' to inspect it or '$0 stop' to release only this hold"
fi
