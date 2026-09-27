#!/usr/bin/env bash
# v59: diagnose global Fly YAML parse errors before blaming a token.
# Shows config path/source, bounded metadata and forbidden-character counts,
# never config contents. Compares the same token/app with temporary clean
# FLY_CONFIG_DIR; comparison success alone NEVER satisfies the launch gate.
# On confirmed corrupt owned files AND a successful isolated app check, option 5
# offers a guarded backup/reset requiring RESET FLY CONFIG. No automatic reset.
# Resets only config.yml, preserving its original bytes in a private 0600 backup;
# saved Fly login/settings are no longer active. Existing agent processes, binary,
# repository fly.toml, Git state and other .fly files are not rewritten by repair.
# Pause concurrent Fly writers before repair. Recheck normally after repair;
# interrupted writes have unknown outcome and are never replayed automatically.
# --check-fly works independently of normal setup. Other modes are unchanged.
# Sources (checked 2026-09-27):
# https://raw.githubusercontent.com/superfly/flyctl/master/flyctl/flyctl.go
# https://raw.githubusercontent.com/superfly/flyctl/master/helpers/config.go
# https://raw.githubusercontent.com/superfly/flyctl/master/internal/config/config.go
# https://raw.githubusercontent.com/superfly/flyctl/master/internal/command/command.go
#
# v58: Fly validation diagnostics and target correction. The status check remains
# mandatory; a nonzero exit is NOT treated as proof of an invalid token.
# --check-fly selects a Sprite/app and runs only that check, without GitHub/model
# credentials, setup, synchronization, or Codex attachment/launch. It can wake a
# cold Sprite and transfers a temporary credential-free validation helper.
# Failed Fly checks show bounded, redacted CLI diagnostics, distinguish likely
# access/app/network/service/process failures, and allow changing FLY_APP without
# re-entering the same token. Tokens are never accepted solely on error text.
# This does not repair Fly infrastructure or prove deploy/SSH/write permissions.
# Fly docs: https://fly.io/docs/flyctl/integrating/
#           https://fly.io/docs/security/tokens/
#
# v57: Retrieve is repository-first sync, not a recovery-branch copy.
# Prompts for GitHub repo/PAT before Sprite access; discovers matching disk
# checkouts, fetches latest branch history, and requires SYNC approval to commit,
# integrate and push the existing branch. No Codex terminal is required.
# No force/reset/rebase; verifies exact published OID. See --help for limits.
# v56: independent --retrieve / --recover mode (opening menu 6).
# Bypasses the old TTY/session; probes fresh non-TTY exec via HTTP POST (when
# supported) and WebSocket fallback for reads only. No mutation is replayed.
# Select an existing repository through the folder browser; status, GitHub PAT
# validation, isolated recovery-branch snapshot/push, verified existing-commit push,
# saved-ref publication, folder ZIP, diagnostics, advanced one-command Git console.
# No agent/provider/Fly setup, credential extraction, reset, kill or restart.
# A cold Sprite may wake; an unreachable machine/control plane cannot be bypassed.
# GitHub PAT is sent through exec stdin, not argv or persistent credential files.
# Guided snapshot leaves the source HEAD/branch/index alone and excludes ignored
# files; unfinished Git operations, submodules, LFS, sparse worktrees need manual care.
# A verified recovery branch is not proof main is synchronized or all files backed up.
# Advanced Git commands run ONLY as explicitly typed and confirmed; can be destructive.
# Exit 137 stops automatic attach retry and points to recovery, not a guessed OOM fix.
# SPRITE_RETRIEVE_TRANSPORT=auto|http-post|websocket (auto prefers advertised HTTP).
# SPRITE_RETRIEVE_TIMEOUT=180 (1..3600), SPRITE_RETRIEVE_PROBE_TIMEOUT=30 (1..300).
# Local control marker removal uses portable sed, not GNU-only sed -i.
#
#
# v55: choose the remote ZIP source using a folder browser, not an assumed ~/output.
# Opening menu 4 / --download-output: select Sprite, browse existing folders,
# D to select the current folder, then confirm its absolute path before transfer.
# H=home, U=parent, /=filesystem root, W=saved workspace/folder shortcuts, T=hidden.
# No live Codex terminal is needed. --output-dir / SPRITE_OUTPUT_DIR start the
# interactive browser at an explicit path. Noninteractive downloads require one.
# Post-session offers use the same browser. File mode input/output roots are unchanged.
# Archives from this browser use the selected folder name as their top-level member.
# Browse timeout: SPRITE_FOLDER_TIMEOUT=45 (1..300 seconds per read-only request).
# The local launch directory remains the ZIP destination; source files are unchanged.
#
# v54: session discovery must not equate is_active=false with process exit.
# Offer listed TTY sessions with false/missing activity metadata; exclude explicit
# ended statuses and invalid/non-TTY rows. Attachment still rechecks identity.
# Both early attach/file mode and normal-run duplicate/reconnect checks are fixed.
# Inventory counts distinguish a truly empty response from filtered records.
# Activity metadata is NOT a terminal-health check; the attach endpoint may still
# reject a stale session. No restart, kill, key recovery or new launch is automatic.
# API/SDK reference: https://sprites.dev/api/sprites/exec
# https://github.com/superfly/sprites-go/blob/main/session.go
# sprite-codex-v59.sh — updated 2026-09-26
#
# Existing single-Sprite bootstrap: OpenAI/Codex or official Kimi Code CLI,
# GitHub/Fly environment credentials, workspace sync, optional pushes,
# native detachable TTY sessions, resume/fork, update and reconnect support.
#
# v53 simplifies --files/--shell into input/output file pickers.
# Downloads are restricted to <selected-workspace>/output/; uploads select local
# launch-directory files/folders and publish under <selected-workspace>/input/.
# Arrow keys + Space + Enter when curses/terminal support is available; numbered
# multi-select fallback otherwise. SPRITE_FILE_UI=auto|arrows|menu (default auto).
# Both pickers navigate only below their roots; no paths or transfer commands needed.
# Input is created only after upload confirmation. Conflicts keep both via suffixes,
# still protected by atomic no-clobber publication. Completed earlier batch items
# remain if a later item fails. Selections are revalidated; no agent restart needed.
# Hidden names are hidden initially (H reveals them); selected folders still include
# hidden contents. Links/special files are never followed by transfer pickers.
# Advanced shell remains explicit; it is NOT restricted to the picker directories.
# Existing post-session ~/output download convention is unchanged; --files uses
# workspace/output, NOT ~/output or /output. --output-dir is rejected in --files.
#
# v52 adds an independent shell/file-access menu (--files or --shell, startup 5).
# Pick an existing Sprite and a live session's recorded workspace, or --workdir.
# Starts a separate Bash TTY only on request; never attaches/restarts Codex, loads
# its credentials, runs token/model checks, updates, Mobbin, or Git sync/push.
# Browse/preview, upload local files/directories and download files/directory ZIPs
# while Codex remains in the other local terminal. Both share the Sprite filesystem.
# No-overwrite uploads are streamed into a private hidden sibling stage, verified,
# then published atomically. No directory overlays; links/special files rejected.
# Individual downloads are checked with SHA-256; directory downloads reuse v51 ZIP.
# SPRITE_FILE_TIMEOUT=3600 (1..86400). Both transfer directions stream large files.
# --session-id in file mode selects a workspace, NOT an attachment. --workdir or
# SPRITE_WORKDIR selects an existing remote directory instead. No local cwd hash.
# In file mode, exit from Bash returns to the LOCAL transfer menu. Remote Bash cd
# does not move the menu's directory. Bash uses no profile/rc and no history file.
# A shell shares permissions/files, not the live agent's process-scoped tokens.
# Race checks are not filesystem snapshots: finish writes before transfers.
# No overwrite, source deletion, automatic extraction, or resumable transfer.
# Local CLI context is private; caller .sprite and resume-state JSON are unchanged.
# Native shell exec flags verified: https://docs.fly.io/sprites/cli/commands/
#
# v51 adds optional output ZIP download when an agent terminal returns, including
# early attach-only, normal reattachment, and newly launched sessions.
# v51 originally defaulted to $HOME/output; v55 replaces that assumption with browsing.
# v55: SPRITE_OUTPUT_DIR / --output-dir sets the browser start, or an explicit noninteractive source.
# SPRITE_OUTPUT_DOWNLOAD=ask|always|never (default ask, default answer No).
# --download-output retrieves files without launching/attaching to an agent.
# ZIPs are saved in the LOCAL directory where this invocation started, not on
# the Sprite or beside this script. ZIP64 streams via non-TTY exec, using only
# local Sprites authentication. No remote ZIP file, public server, provider key,
# Git sync/push, source deletion or automatic extraction. SHA-256 and ZIP CRCs
# must pass before a private local .partial becomes the uniquely named ZIP.
# Symlinks/special files are skipped; symlinked root path components are rejected.
# Finish writes first: detected source changes fail the download, not Codex.
# Closing the local terminal cannot display an exit prompt: use download-only later.
# SPRITE_DOWNLOAD_TIMEOUT=3600 bounds remote scan/compression/transfer (1..86400).
# SPRITE_OUTPUT_COMPRESSION=1 (0..9); 0 stores without compression.
# SPRITE_DOWNLOAD_TRANSPORT=websocket|http-post (default websocket).
# With download declined/disabled, attach-only still executes no remote command.
# Download failures preserve the preceding agent/attach exit status; explicit
# --download-output reports its own failure status. No automatic resume of .partial.
#
# v50 adds an opening Attach / Normal setup / Quit menu (interactive, no run flag).
# Attach-only runs BEFORE bootstrap configuration validation, model tests, agent/
# provider choice, Codex updates, Mobbin, tokens, workspace setup or saved state.
# --attach-only skips straight to Sprite/session selection; --session-id ID plus
# SPRITE_NAME selects one exact native terminal after a fresh inventory check.
# All active native TTYs on the chosen Sprite are listed, regardless of project.
# Attachment itself never executes a new remote command, kills a session, writes
# project state, or falls through to bootstrap. A confirmed output download does
# run a separate read-only non-TTY archive command. It needs only local sprite + Python 3.9+.
# --bootstrap skips the new opening menu and preserves the old setup workflow.
# Bare non-interactive runs retain the old bootstrap behavior; attach needs a TTY.
# SPRITE_ATTACH_TIMEOUT=25 bounds each local CLI inventory/context/help call.
# SPRITE_ORG selects the CLI organization; otherwise the global CLI default is used.
# Other bootstrap-only environment settings (including FORCE_NEW_SESSION) do not
# affect attach-only. TTY_AUTO_REATTACH/TTY_REATTACH_* still control reconnects.
# The attach picker uses native Sprite sessions, not a new tmux client or Codex
# conversation picker. Legacy tmux-only discovery remains in normal bootstrap.
#
# v49 makes saved-conversation selection explicit: resume runs `codex resume`
# through the existing provider launcher, without --last or a conversation ID.
# Fork/recovery uses `codex fork` so the user selects the intended source history.
# Post-update relaunches also open the resume picker, rather than guessing which
# saved conversation was just active. Live native TTY reattachment is unchanged.
# Resume interrupt exit codes do not trigger fork recovery or an update relaunch.
# The new-conversation default remains unchanged; choose Resume to see history.
# Codex resume/fork docs checked 2026-09-23:
# https://developers.openai.com/codex/cli/reference/
#
# v48 adds optional official Mobbin hosted MCP setup after the Codex update stage.
# MOBBIN_MCP_MODE=ask|always|never (ask defaults to No; noninteractive skips).
# MOBBIN_MCP_LOGIN=ask|always|never; browser OAuth runs inside the selected Sprite
# with automatic loopback port forwarding. No Mobbin API key is requested.
# Login credentials are stored by Codex, not in the process-only provider env map.
# Existing servers/settings are preserved; conflicting/disabled entries are not
# replaced/enabled. Failure is non-fatal; no running Codex session is restarted.
# Reattach may require a later agent restart before newly added tools are loaded.
# MOBBIN_MCP_LOGIN_TIMEOUT=300 (1..1800 seconds). Model defaults remain unchanged.
# Mobbin docs: https://docs.mobbin.com/mcp/introduction
# Codex docs: https://developers.openai.com/codex/mcp
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
#   bash sprite-codex-v59.sh                       # Attach / Normal setup / Quit
#   bash sprite-codex-v59.sh --attach-only         # no keys or bootstrap setup
#   SPRITE_NAME=my-sprite bash sprite-codex-v59.sh --attach-only --session-id 1847
#   bash sprite-codex-v59.sh --download-output     # download ~/output as local ZIP
#   SPRITE_OUTPUT_DIR=/output bash sprite-codex-v59.sh --download-output
#   bash sprite-codex-v59.sh --bootstrap           # old normal workflow
#   bash sprite-codex-v59.sh --show-models          # no API calls
#   bash sprite-codex-v59.sh --test-models          # host API tests only
#   bash sprite-codex-v59.sh --test-models-sprite   # API tests on one Sprite only
#   bash sprite-codex-v59.sh --test-models-before-run
#   bash sprite-codex-v59.sh --test-models --json-output ./model-tests.json
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
  echo 'macOS users: brew install bash; then use "$(brew --prefix)/bin/bash" to run this script.' >&2
  exit 1
fi

set -Eeuo pipefail
set +x +v
umask 077

show_usage() {
  cat <<'HELP'
Usage: bash sprite-codex-v59.sh [option] [--output-dir PATH] [--json-output PATH | --session-id ID]

  (no option)               Attach / Setup / Quit / Download / Files / Retrieve menu.
  --attach-only             Select a Sprite and attach to an existing live TTY.
  --session-id ID           With --attach-only or --files + SPRITE_NAME: exact TTY.
  --files, --shell          Independent shell/file menu alongside live Codex.
  --retrieve, --recover     Repo-first GitHub sync from Sprite disk; no Codex attach.
  --workdir PATH            With --files/--retrieve: existing Sprite directory or search hint.
  --bootstrap               Skip the opening menu; run normal setup workflow.
  --download-output         Select a Sprite, browse folders, download one as a ZIP.
  --output-dir PATH         Start folder browser here; exact source without a TTY.
  --test-models             Test DeepSeek, MiniMax and Moonshot from this host.
  --test-models-sprite      Test all three from one selected Sprite.
  --test-models-before-run  Require host tests to pass, then run normal bootstrap.
  --show-models             Display configured model IDs and base URLs; no calls.
  --help, -h                Display this help.

Attach-only bypasses all model/agent choices, credential entry/validation, model
API tests, Codex updates, Mobbin and workspace setup. Attachment never launches or
replaces an agent, or falls back into bootstrap. Only an accepted output download
runs a separate read-only remote archive command. Works from ANY local directory;
all active native TTYs on the chosen Sprite are considered, not just this project.
Requires an authenticated local sprite CLI, Python 3.9+, and an interactive TTY.
SPRITE_NAME / SPRITE_ORG can preselect the Sprite / organization. Without an org,
the global CLI default is used (not the current project's .sprite context).
Session IDs are Sprite terminal IDs, NOT Codex conversation UUIDs. Discovery
errors remain unknown, never "no sessions". Missing/ended exact targets exit 3.
The picker offers refresh, another Sprite, or quit; it does not discover detached
tmux servers without a native TTY. Use normal setup for legacy tmux recovery.
SPRITE_ATTACH_TIMEOUT=25 (1..300) bounds inventory/context/help requests only.
TTY_AUTO_REATTACH and TTY_REATTACH_* control retries to the same live session.
Ctrl+\ detaches. No provider keys are copied out of or injected into the process.
Bare non-interactive runs retain the previous bootstrap behavior. Explicit test
modes and --bootstrap do not show the opening menu. --json-output is not allowed
with --attach-only; bootstrap-only environment settings are ignored on attachment.

Repository-first retrieve mode (--retrieve / --recover, opening menu 6):
1. Enter GitHub OWNER/REPO (or repository URL), then a hidden PAT; authenticate
   locally and check Git write-service access BEFORE choosing/accessing a Sprite.
2. Choose Sprite, use fresh bounded non-TTY execs, search accessible checkouts
   for a matching GitHub origin. Select the checkout and target GitHub branch.
3. Fetch the CURRENT GitHub branch tip. Review HEAD, ahead/behind commits and
   uncommitted tracked/deleted/non-ignored files; approve with SYNC before writing.
4. Stage final working files, commit if needed on the EXISTING local branch, and
   publish unpublished history to the selected GitHub branch. No backup branch,
   clone, overlay, forced push, automatic reset/rebase or replacement of the repo.
   GitHub-only commits require explicit integration approval in the sync plan.
   Fast-forward or ordinary merge preserves history. Conflicts stop publication;
   local commits remain. Successful push requires verification of the exact OID.
Finish writers first: this does not stop Codex or create a filesystem snapshot.
Analysis creates Git objects/fetches but preserves HEAD, files and normal index.
Guided sync bypasses hooks/signing, checks basic secret patterns and >100 MiB blobs;
not an exhaustive secret scanner. It stops on unfinished Git ops/locks, shallow or
unrelated histories, detached HEAD, submodules/LFS and sparse checkouts. Use ZIP or
advanced Git deliberately for those cases. Ignored files are excluded from Git.
Search uses home/common workspace roots plus saved hints; skips symlinks,
dependencies and virtual filesystems. Limits/permission omissions are reported.
--workdir/SPRITE_WORKDIR adds a search hint; matching origin is always required.
Uses HTTP POST when advertised, then WebSocket for read-only retries. Unknown
write outcomes are NOT replayed. Rerun comparison; saved commits remain on disk.
A cold Sprite may wake; no operation bypasses an inaccessible host/exec/filesystem.
No provider/Fly keys or old process credentials are used. PAT is memory/stdin/env
only, never written into URLs/config/receipts. Branch rules still apply to pushes.
SPRITE_RETRIEVE_TIMEOUT=180 (1..3600), SPRITE_RETRIEVE_PROBE_TIMEOUT=30 (1..300).
SPRITE_RETRIEVE_TRANSPORT=auto|http-post|websocket; no automatic write transport retry.
--session-id, --output-dir and --json-output are rejected with retrieve mode.
The advanced Git console and folder ZIP download remain available after selection.

Simplified file mode (--files / --shell, opening menu 5):
Select a live session's recorded workspace, or supply --workdir. --session-id ID
selects an exact live terminal's workspace and requires SPRITE_NAME. --session-id
and --workdir cannot be combined. Ambiguous workspace metadata is never guessed.
No Codex attach,
restart, keys, token checks, updates, Mobbin, Git sync or pushes occur.
Downloads select only files/folders under <workspace>/output/. Uploads select
from the LOCAL launch directory and place each selection under <workspace>/input/.
No upload/download paths or shell commands need to be typed. input/ is created
only after a confirmed upload. Use ./input/ and ./output/ in Codex instructions.
Picker: Up/Down moves, Space selects, Right opens a folder, Left goes back,
Enter confirms selected items (or the highlighted file), Q cancels. Hidden files
start hidden; H reveals them. A selects all in view; / filters; V previews text.
SPRITE_FILE_UI=auto|arrows|menu selects the UI (default auto). With no curses or
an unsupported/small terminal, a numbered multi-select picker is used instead.
Both pickers stay under their root folders. Symlinks and special files are not
selectable. Selected folders include hidden regular files: exclude credentials.
Each selected upload lands at input/<basename>; nested folder contents remain
nested. Downloaded files use their basenames locally; selected folders become
separate ZIPs. Existing names get numeric suffixes; no files are overwritten.
Batch transfers are sequential; earlier completed items remain if a later one
fails. Finish writers first; checks are not atomic filesystem snapshots.
No source deletion, automatic local extraction or transfer resumption.
SPRITE_FILE_TIMEOUT=3600 (1..86400) bounds file transfers. Folder ZIP downloads
use SPRITE_DOWNLOAD_TIMEOUT. Existing ~/output post-session downloads below are
unchanged: that is a DIFFERENT folder convention from file mode's ./output/.
--output-dir is rejected with --files; SPRITE_OUTPUT_DIR does not move its root.
The explicit advanced shell is separate and is NOT restricted to input/output;
it shares files/permissions, not the running Codex process's credentials.

Folder ZIP download (opening menu 4 / --download-output):
Select a Sprite, then browse existing folders. No ~/output or workspace is assumed.
Numbers open folders; D selects the current folder and asks for final confirmation.
U=parent, H=home, /=filesystem root, W=workspace shortcuts, T=hidden, R=refresh,
N/B=next/previous folder page, Q=cancel. P optionally accepts an exact remote path.
Names/sizes of some files are shown to identify a folder; contents are not previewed.
Saved workspace shortcuts are hints, not live-session claims. No Codex is launched.
The chosen folder name is the ZIP's top-level folder. File mode remains limited
to <workspace>/output downloads and <workspace>/input uploads as before.
A missing ~/output is no longer an error unless it is explicitly selected. Browse
any readable, non-symlinked folder; /, the whole home directory, and virtual system
folders /proc, /sys, /dev cannot be archived. No directory is created or cleared.
--output-dir / SPRITE_OUTPUT_DIR set the starting location for interactive browsing.
Without a terminal, an explicit folder AND SPRITE_NAME are required; no guessing.
The destination is the local working DIRECTORY AT SCRIPT START, not the script's
location or temporary CLI context. No live Codex terminal is needed for download.
SPRITE_FOLDER_TIMEOUT=45 (1..300) bounds each directory/shortcut listing.
SPRITE_OUTPUT_DOWNLOAD=ask|always|never controls the post-session offer (default ask).
After an actual attachment/agent return, 'ask' offers the same folder browser.
Declining that offer performs NO remote exec. 'ask' skips noninteractive runs.
'--download-output' explicitly requests download mode; an interactive run still
requires confirmation of the selected folder. Errors allow browsing another folder.
SPRITE_DOWNLOAD_TIMEOUT=3600 (1..86400) bounds scan/compression/transfer.
SPRITE_OUTPUT_COMPRESSION=1 (0..9, 0 = uncompressed ZIP).
SPRITE_DOWNLOAD_TRANSPORT=websocket|http-post; default websocket.
Uses local Sprites login and Python 3.9+ locally/on Sprite; no other API keys.
ZIP64 supports large files; streams file bytes in chunks, with metadata in memory.
Verifies length, SHA-256, ZIP structure and CRCs; no extraction or source deletion.
Includes hidden regular files: put only deliverables, NOT credentials, in output.
Skips symlinks/special files; rejects symlinked root components and unsafe ZIP names.
Finish writers first: changes observed during archiving reject the transfer.
A closed/crashed terminal cannot offer a prompt. Rerun --download-output later.
Failed downloads remove local partial files when cleanup can run; retries start
again. A forced kill/power loss can leave a hidden .sprite-output-*.partial file.
No automatic remote ZIP staging or temporary archive remains on the Sprite.
Post-session downloads do not replace the agent exit code; --download-output has
its own success/failure exit status. Declining the offer performs NO remote exec.

Optional Mobbin MCP setup runs AFTER the Codex update stage (Codex agent only).
MOBBIN_MCP_MODE=ask|always|never (default ask; interactive default No).
MOBBIN_MCP_LOGIN=ask|always|never (default ask; noninteractive never opens OAuth).
MOBBIN_MCP_LOGIN_TIMEOUT=300 bounds browser OAuth (1..1800 seconds).
The official hosted server uses OAuth, not a pasted API key, and requires a
Mobbin Pro/Team/Enterprise plan. Tool calls may use Mobbin AI credits.
Configuration is persistent in ~/.codex/config.toml on the selected Sprite.
Codex stores OAuth credentials normally; they are NOT process-only tokens.
Existing MCP entries are preserved; 'never' does not uninstall an existing entry.
The login exec enables automatic localhost forwarding; agent exec behavior is unchanged.
Live Codex sessions are not restarted; newly added tools may need a later restart.
Installation/OAuth failures do not prevent ordinary session reattachment.

Fly-only diagnostic mode: --check-fly
Select a Sprite, confirm the actual Fly app, and enter the Fly token hidden.
No GitHub/model keys, model tests, installs, Git sync or Codex/session action.
Uses existing local Sprite authentication and installed Sprite fly/flyctl.
FLY_APP is a Fly app name, not necessarily the Sprite name or repository name.
Failure includes the CLI exit status and redacted diagnostic excerpts; categories
are hints, not definitive diagnoses. The Fly retry menu adds 4) Change target app.
The default for a failed Fly check is retrying the same token, not replacement.
Validation is NOT skipped or weakened. Status access does not prove deployment,
SSH or write rights. No token/debug dump is written by this validator. The normal
JSON/hex Sprite credential transport still appears in process arguments; do not
use shell tracing. Standalone --check-fly does not rotate a running agent's env.

Every credential used by a NEW run is validated on the selected Sprite:
GitHub authentication + repository/write-service access, Fly app status, and a
completion from each selected/experiment provider. Failed checks offer hidden
replacement, retry, or abort; noninteractive failures stop before agent launch.
TOKEN_CHECK_TIMEOUT=180 (1..900) bounds each request; checks cannot be skipped.
Fly YAML startup errors show the expected remote global config path, metadata and
forbidden-character counts (never file contents). A temporary clean-config status
comparison uses the same token/app; passing it does not bypass the normal gate.
Only a confirmed corrupt owned config with a successful clean comparison permits
menu option 5: back up/reset config.yml after typing RESET FLY CONFIG. Pause other
Fly writers first. Old saved login/settings become inactive; the backup is secret.
No automatic reset or interrupted-write replay. Recheck normal app access afterward.
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
_JSON_OUTPUT_SELECTED=0
ATTACH_SESSION_ID=""
OUTPUT_HOST_DIR="$PWD"
SPRITE_OUTPUT_DIR="${SPRITE_OUTPUT_DIR:-}"
OUTPUT_PATH_EXPLICIT=0
[[ -z $SPRITE_OUTPUT_DIR ]] || OUTPUT_PATH_EXPLICIT=1
[[ -n $SPRITE_OUTPUT_DIR ]] || SPRITE_OUTPUT_DIR='~/output' 
SPRITE_OUTPUT_DOWNLOAD="${SPRITE_OUTPUT_DOWNLOAD:-ask}"
OUTPUT_PINNED_CONTEXT=""
_OUTPUT_DIR_SELECTED=0
FILE_WORKDIR="${SPRITE_WORKDIR:-}"
_FILE_WORKDIR_SELECTED=0
while (($#)); do
  case "$1" in
    --help|-h) show_usage; exit 0 ;;
    --attach-only|--files|--shell|--retrieve|--recover|--check-fly|--bootstrap|--download-output|--test-models|--test-models-sprite|--test-models-before-run|--show-models)
      (( _MODE_SELECTED == 0 )) || { echo "error: select only one run mode" >&2; exit 2; }
      _MODE_SELECTED=1
      case "$1" in
        --attach-only) RUN_MODE=attach ;;
        --files|--shell) RUN_MODE=files ;;
        --retrieve|--recover) RUN_MODE=retrieve ;;
        --check-fly) RUN_MODE=check-fly ;;
        --bootstrap) RUN_MODE=bootstrap ;;
        --download-output) RUN_MODE=download ;;
        --test-models) RUN_MODE=test-local ;;
        --test-models-sprite) RUN_MODE=test-sprite ;;
        --test-models-before-run) MODEL_TEST_MODE=always ;;
        --show-models) RUN_MODE=show ;;
      esac
      shift ;;
    --json-output)
      [[ $# -ge 2 && -n $2 && $2 != --* ]] || { echo "error: --json-output requires a path" >&2; exit 2; }
      MODEL_TEST_JSON=$2; _JSON_OUTPUT_SELECTED=1; shift 2 ;;
    --output-dir)
      [[ $# -ge 2 && -n $2 && $2 != --* && $_OUTPUT_DIR_SELECTED == 0 ]] || {
        echo "error: --output-dir requires one remote folder path" >&2; exit 2;
      }
      SPRITE_OUTPUT_DIR=$2; _OUTPUT_DIR_SELECTED=1; OUTPUT_PATH_EXPLICIT=1; shift 2 ;;
    --workdir)
      [[ $# -ge 2 && -n $2 && $2 != --* && $_FILE_WORKDIR_SELECTED == 0 ]] || {
        echo "error: --workdir requires one existing Sprite directory" >&2; exit 2;
      }
      FILE_WORKDIR=$2; _FILE_WORKDIR_SELECTED=1; shift 2 ;;
    --session-id)
      [[ $# -ge 2 && $2 =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ && -z $ATTACH_SESSION_ID ]] || {
        echo "error: --session-id requires one valid Sprite terminal ID" >&2; exit 2;
      }
      ATTACH_SESSION_ID=$2; shift 2 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; show_usage >&2; exit 2 ;;
  esac
done

if [[ $RUN_MODE == check-fly ]] && (( _JSON_OUTPUT_SELECTED || _OUTPUT_DIR_SELECTED || _FILE_WORKDIR_SELECTED )); then
  echo "error: --check-fly does not accept --json-output, --output-dir or --workdir" >&2; exit 2
fi

# v50: the first interactive choice is deliberately before all bootstrap-only
# settings and side effects. The attach branch exits unconditionally afterwards.
if [[ -n $ATTACH_SESSION_ID && $RUN_MODE != attach && $RUN_MODE != files ]]; then
  echo "error: --session-id must be used with --attach-only or --files" >&2; exit 2
fi
if [[ ( $RUN_MODE == attach || $RUN_MODE == download || $RUN_MODE == files || $RUN_MODE == retrieve ) && $_JSON_OUTPUT_SELECTED == 1 ]]; then
  echo "error: --json-output cannot be used with --attach-only, --download-output or --files/--retrieve" >&2; exit 2
fi
if [[ $RUN_MODE == bootstrap && $_MODE_SELECTED == 0 && $_JSON_OUTPUT_SELECTED == 0 && -t 0 && -t 1 ]]; then
  while :; do
    printf '\n=== Sprite Codex: what would you like to do?\n'
    printf '    1) Attach to an existing Sprite terminal session [default]\n'
    printf '    2) Normal setup / launch or resume a saved conversation\n'
    printf '    3) Quit\n'
    printf '    4) Choose a Sprite folder and download it as a ZIP (no agent launch)\n'
    printf '    5) File picker alongside Codex (output downloads / input uploads)\n'
    printf '    6) Retrieve / sync repository to GitHub (no Codex attachment required)\n'
    printf '  Select [1-6]: '
    if ! IFS= read -r _startup_choice; then printf '\n'; exit 0; fi
    case "${_startup_choice,,}" in
      ''|1|a|attach) RUN_MODE=attach; break ;;
      2|b|bootstrap|setup) break ;;
      3|q|quit) exit 0 ;;
      4|d|download) RUN_MODE=download; break ;;
      5|f|files|shell) RUN_MODE=files; break ;;
      6|r|retrieve|recover) RUN_MODE=retrieve; break ;;
      *) printf '  Invalid selection. Choose 1, 2, 3, 4, 5, or 6.\n' ;;
    esac
  done
fi

# v51: this hook is explicit, not an EXIT trap. Help/test/cancel/setup failures
# never trigger an output read; terminal hangup cannot trigger a hidden download.
output_download_python() {
  cat <<'OUTPUT_DOWNLOAD_PY'
"""Optional host-side ZIP download; no provider credentials or remote ZIP file."""
from __future__ import annotations
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata
import zipfile
import zlib

# The remote program is embedded below when packaging this single-file script.
REMOTE_OUTPUT_PY = r'''"""Read one output directory and stream a ZIP64 archive plus a completion record.
Never creates an archive on the Sprite, follows symlinks, or changes source files.
"""
import hashlib
import json
import os
import re
import stat
import sys
import time
import zipfile

FOOTER_SIZE = 512
FOOTER_MAGIC = b"\nSPRITE_CODEX_OUTPUT_V1 "
CHUNK = 1024 * 1024


class OutputError(Exception):
    pass


def signature(st):
    return (st.st_dev, st.st_ino, st.st_mode, st.st_size,
            st.st_mtime_ns, st.st_ctime_ns)


def open_directory(path, allow_base=False):
    """Open each component without following any symlink, including at the root."""
    home = os.path.expanduser("~")
    if path.startswith("~/"):
        path = os.path.join(home, path[2:])
    elif path.startswith("$HOME/"):
        path = os.path.join(home, path[6:])
    if not path.startswith("/") or "\0" in path or ".." in path.split("/"):
        raise OutputError("unsafe_path")
    path = os.path.normpath(path)
    if not allow_base and path in ("/", os.path.normpath(home)):
        raise OutputError("unsafe_path")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open("/", flags)
    try:
        for part in path.split("/"):
            if not part:
                continue
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def scan(fd, prefix="", result=None):
    if result is None:
        result = {}
    result[prefix] = ("dir", signature(os.fstat(fd)))
    with os.scandir(fd) as entries:
        names = sorted(entry.name for entry in entries)
    for name in names:
        # Portable ZIP paths: reject Windows separators/drive/stream syntax and
        # control characters rather than silently changing filenames.
        if name in (".", "..") or any(c in name for c in ("\\", ":")) or any(ord(c) < 32 or ord(c) == 127 for c in name):
            raise OutputError("unsafe_name")
        try:
            name.encode("utf-8")
        except UnicodeError:
            raise OutputError("unsafe_name") from None
        rel = prefix + name
        st = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if stat.S_ISDIR(st.st_mode):
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            try:
                if signature(os.fstat(child)) != signature(st):
                    raise OutputError("changed")
                scan(child, rel + "/", result)
            finally:
                os.close(child)
        elif stat.S_ISREG(st.st_mode):
            result[rel] = ("file", signature(st))
        else:
            # No reading outside output via links, and no hanging on FIFOs/devices.
            result[rel] = ("skip", signature(st))
    return result


class HashWriter:
    def __init__(self, raw):
        self.raw = raw
        self.digest = hashlib.sha256()
        self.size = 0

    def write(self, data):
        self.raw.write(data)
        self.digest.update(data)
        self.size += len(data)
        return len(data)

    def tell(self):
        return self.size

    def flush(self):
        self.raw.flush()


def zip_info(name, st, directory=False, level=1):
    value = time.localtime(st.st_mtime)
    if value.tm_year < 1980:
        date = (1980, 1, 1, 0, 0, 0)
    elif value.tm_year > 2107:
        date = (2107, 12, 31, 23, 59, 58)
    else:
        date = tuple(value[:6])
    info = zipfile.ZipInfo(name, date)
    info.create_system = 3
    info.external_attr = ((stat.S_IFDIR if directory else stat.S_IFREG) | (st.st_mode & 0o777)) << 16
    if directory:
        info.external_attr |= 0x10
    info.compress_type = zipfile.ZIP_DEFLATED if level and not directory else zipfile.ZIP_STORED
    info._compresslevel = level  # Compatible with Python 3.9+.
    info.file_size = 0 if directory else st.st_size
    return info


def write_tree(archive, fd, initial, level, prefix="", archive_root="output"):
    if signature(os.fstat(fd)) != initial[prefix][1]:
        raise OutputError("changed")
    archive.writestr(zip_info(archive_root + "/" + prefix, os.fstat(fd), True, level), b"")
    with os.scandir(fd) as entries:
        names = sorted(entry.name for entry in entries)
    for name in names:
        rel = prefix + name
        st = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if stat.S_ISDIR(st.st_mode):
            key = rel + "/"
            if initial.get(key) != ("dir", signature(st)):
                raise OutputError("changed")
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            try:
                write_tree(archive, child, initial, level, key, archive_root)
            finally:
                os.close(child)
        elif stat.S_ISREG(st.st_mode):
            if initial.get(rel) != ("file", signature(st)):
                raise OutputError("changed")
            source_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
            with os.fdopen(source_fd, "rb") as source:
                before = os.fstat(source.fileno())
                if not stat.S_ISREG(before.st_mode) or signature(before) != signature(st):
                    raise OutputError("changed")
                # ZIP64 is enabled before writing the header, including >4 GiB files.
                with archive.open(zip_info(archive_root + "/" + rel, before, level=level), "w", force_zip64=True) as target:
                    remaining = before.st_size
                    while remaining:
                        data = source.read(min(CHUNK, remaining))
                        if not data:
                            raise OutputError("changed")
                        target.write(data)
                        remaining -= len(data)
                    if source.read(1) or signature(os.fstat(source.fileno())) != signature(before):
                        raise OutputError("changed")
        elif initial.get(rel) != ("skip", signature(st)):
            raise OutputError("changed")


def validate_selection(path, root, checks):
    if checks is None:
        return
    if not isinstance(checks, dict):
        raise OutputError("invalid_request")
    if checks.get("kind") == "directory":
        absolute = os.path.normpath(os.path.expanduser(path))
        if path.startswith("$HOME/"):
            absolute = os.path.normpath(os.path.join(os.path.expanduser("~"), path[6:]))
        if any(absolute == p or absolute.startswith(p + "/") for p in ("/proc", "/sys", "/dev")):
            raise OutputError("unsafe_path")
        if checks.get("expected") is not None and list(signature(os.fstat(root))) != checks["expected"]:
            raise OutputError("changed")
        return
    if not isinstance(checks.get("scope"), dict):
        raise OutputError("invalid_request")
    scope = checks["scope"]
    workspace = scope.get("workspace", "")
    if scope.get("folder") != "output" or not workspace.startswith("/"):
        raise OutputError("unsafe_path")
    boundary = os.path.join(os.path.normpath(workspace), "output")
    if os.path.commonpath((boundary, os.path.normpath(path))) != boundary:
        raise OutputError("unsafe_path")
    base = open_directory(workspace, allow_base=True)
    try:
        if [os.fstat(base).st_dev, os.fstat(base).st_ino] != scope.get("identity"):
            raise OutputError("changed")
        folder = os.open("output", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=base)
        try:
            if [os.fstat(folder).st_dev, os.fstat(folder).st_ino] != scope.get("root_identity"):
                raise OutputError("changed")
        finally:
            os.close(folder)
    finally:
        os.close(base)
    if checks.get("expected") is not None and list(signature(os.fstat(root))) != checks["expected"]:
        raise OutputError("changed")


def stream_output(path, nonce, level, checks=None):
    if not re.fullmatch(r"[0-9a-f]{32}", nonce) or not 0 <= level <= 9:
        raise OutputError("invalid_request")
    archive_root = checks.get("archive_root", "output") if isinstance(checks, dict) else "output"
    if (not isinstance(archive_root, str) or not archive_root or archive_root in (".", "..")
            or any(c in archive_root for c in ("/", "\\", ":"))
            or any(ord(c) < 32 or ord(c) == 127 for c in archive_root)):
        raise OutputError("unsafe_name")
    root = open_directory(path)
    try:
        validate_selection(path, root, checks)
        initial = scan(root)
        files = sum(kind == "file" for kind, _ in initial.values())
        if not files:
            raise OutputError("empty")
        skipped = sum(kind == "skip" for kind, _ in initial.values())
        raw_bytes = sum(sig[3] for kind, sig in initial.values() if kind == "file")
        writer = HashWriter(sys.stdout.buffer)
        with zipfile.ZipFile(writer, "w", allowZip64=True) as archive:
            write_tree(archive, root, initial, level, archive_root=archive_root)
        # This is a checked read, not an atomic filesystem snapshot. Stop writers
        # first; changes visible during either scan invalidate the whole transfer.
        if scan(root) != initial:
            raise OutputError("changed")
        # Detect replacement/rename of the requested root while reading through fd.
        check = open_directory(path)
        try:
            if signature(os.fstat(check)) != signature(os.fstat(root)):
                raise OutputError("changed")
        finally:
            os.close(check)
        validate_selection(path, root, checks)
        writer.flush()
        metadata = dict(nonce=nonce, size=writer.size, sha256=writer.digest.hexdigest(),
                        files=files, raw_bytes=raw_bytes, skipped=skipped)
        payload = FOOTER_MAGIC + json.dumps(metadata, separators=(",", ":")).encode("ascii")
        if len(payload) >= FOOTER_SIZE:
            raise OutputError("invalid_request")
        sys.stdout.buffer.write(payload.ljust(FOOTER_SIZE - 1, b" ") + b"\n")
        sys.stdout.buffer.flush()
    finally:
        os.close(root)


if __name__ == "__main__":
    try:
        if sys.version_info < (3, 9):
            raise OutputError("python_version")
        stream_output(sys.argv[1], sys.argv[2], int(sys.argv[3]), json.loads(sys.argv[4]) if len(sys.argv) > 4 else None)
    except BrokenPipeError:
        os._exit(1)
    except (OutputError, OSError, ValueError, RuntimeError, zipfile.BadZipFile) as exc:
        if isinstance(exc, OutputError):
            reason = str(exc)
        elif isinstance(exc, FileNotFoundError):
            reason = "missing_or_changed"
        elif isinstance(exc, PermissionError):
            reason = "permission"
        else:
            reason = "read_failed"
        # Do not send raw exception strings or secret-bearing file contents.
        print("SPRITE_OUTPUT_ERROR=" + reason, file=sys.stderr)
        raise SystemExit(1)
'''
FOOTER_SIZE = 512
FOOTER_MAGIC = b"\nSPRITE_CODEX_OUTPUT_V1 "


class DownloadError(Exception):
    pass


class DownloadInterrupted(Exception):
    def __init__(self, signum):
        self.signum = signum


def safe(value):
    return "".join(c if c.isprintable() and not unicodedata.category(c).startswith("C") else "?" for c in str(value))


def integer(name, default, minimum, maximum):
    value = os.environ.get(name, str(default))
    if not re.fullmatch(r"[0-9]{1,6}", value) or not minimum <= int(value) <= maximum:
        raise DownloadError(f"{name} must be {minimum}..{maximum}.")
    return int(value)


def stop_local_transfer(proc):
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=2)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()


def verify_download(handle, nonce, archive_root="output"):
    """Verify nonce/length/SHA-256 and every ZIP CRC; never extract any file."""
    size = handle.seek(0, os.SEEK_END)
    if size <= FOOTER_SIZE:
        raise DownloadError("No complete output archive was received.")
    handle.seek(-FOOTER_SIZE, os.SEEK_END)
    footer = handle.read(FOOTER_SIZE)
    if not footer.startswith(FOOTER_MAGIC) or not footer.endswith(b"\n"):
        raise DownloadError("Download ended without its completion record; ZIP not saved.")
    try:
        meta = json.loads(footer[len(FOOTER_MAGIC):].strip())
        valid = (isinstance(meta, dict) and meta.get("nonce") == nonce
                 and type(meta.get("size")) is int and meta["size"] == size - FOOTER_SIZE
                 and isinstance(meta.get("sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", meta["sha256"])
                 and all(type(meta.get(key)) is int and meta[key] >= 0 for key in ("files", "raw_bytes", "skipped"))
                 and meta["files"] > 0)
    except (ValueError, TypeError):
        valid = False
    if not valid:
        raise DownloadError("Invalid download completion record; ZIP not saved.")
    handle.seek(0)
    if handle.read(4) != b"PK\x03\x04":
        raise DownloadError("Unexpected non-ZIP data in the download stream.")
    handle.seek(0)
    digest = hashlib.sha256()
    remaining = meta["size"]
    while remaining:
        data = handle.read(min(1024 * 1024, remaining))
        if not data:
            raise DownloadError("Truncated archive.")
        digest.update(data)
        remaining -= len(data)
    if digest.hexdigest() != meta["sha256"]:
        raise DownloadError("SHA-256 mismatch; the partial download was rejected.")
    handle.truncate(meta["size"])
    handle.flush()
    handle.seek(0)
    try:
        with zipfile.ZipFile(handle, "r") as archive:
            seen, files, raw_bytes = set(), 0, 0
            for item in archive.infolist():
                parts = PurePosixPath(item.filename).parts
                if (not parts or parts[0] != archive_root or item.filename.startswith("/")
                    or ".." in parts or "\\" in item.filename or ":" in item.filename
                    or item.filename in seen or item.flag_bits & 1
                    or stat.S_ISLNK(item.external_attr >> 16)):
                    raise DownloadError("Unsafe or unexpected archive member; ZIP rejected.")
                seen.add(item.filename)
                if not item.is_dir():
                    files += 1
                    raw_bytes += item.file_size
            if files != meta["files"] or raw_bytes != meta["raw_bytes"]:
                raise DownloadError("Archive manifest does not match the completed transfer.")
            if archive.testzip() is not None:
                raise DownloadError("ZIP CRC verification failed.")
    except (zipfile.BadZipFile, RuntimeError, EOFError, NotImplementedError, zlib.error):
        raise DownloadError("ZIP integrity verification failed.") from None
    os.fsync(handle.fileno())
    return meta


def remote_failure(stderr):
    stderr.seek(0, os.SEEK_END)
    stderr.seek(max(0, stderr.tell() - 8192))
    text = stderr.read().decode("utf-8", "replace")
    messages = {
        "empty": "The remote output folder contains no regular files; nothing was downloaded.",
        "missing_or_changed": "The selected folder/file is missing or changed during reading. Choose the correct folder and finish writes before retrying.",
        "permission": "The Sprite user cannot read that output folder. Check its ownership and permissions.",
        "unsafe_path": "Choose a specific folder, not /, the whole home directory, or a path containing '..'.",
        "unsafe_name": "A filename has control characters, a backslash, or colon; rename it for a portable ZIP.",
        "changed": "Output changed while being archived; finish writing and retry. No final ZIP was saved.",
        "read_failed": "Remote output could not be read. Check permissions, symlinked path components and available resources.",
        "python_version": "Python 3.9 or newer is required on the Sprite.",
        "invalid_request": "The remote archive request was rejected.",
    }
    hits = re.findall(r"^SPRITE_OUTPUT_ERROR=([a-z_]+)$", text, re.M)
    return messages.get(hits[-1]) if hits else None


def download(sprite, output_dir, local_dir, org, context_file="", checks=None):
    cli = shutil.which("sprite")
    if not cli:
        raise DownloadError("The local sprite CLI was not found; authenticate it with sprite login.")
    cli = os.path.abspath(cli)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", sprite):
        raise DownloadError("Invalid Sprite name.")
    if org and (org.startswith("-") or any(c.isspace() or not c.isprintable() for c in org)):
        raise DownloadError("Invalid SPRITE_ORG.")
    if not output_dir or not (output_dir.startswith("/") or output_dir.startswith("~/") or output_dir.startswith("$HOME/")):
        raise DownloadError("SPRITE_OUTPUT_DIR / --output-dir must be an absolute Sprite path or start with ~/ or $HOME/.")
    if any(ord(c) < 32 for c in output_dir) or ".." in output_dir.split("/"):
        raise DownloadError("The output folder must not contain control characters or '..'.")
    directory = Path(local_dir)
    if not directory.is_dir():
        raise DownloadError("The local launch directory no longer exists.")
    deadline = integer("SPRITE_DOWNLOAD_TIMEOUT", 3600, 1, 86400)
    level = integer("SPRITE_OUTPUT_COMPRESSION", 1, 0, 9)
    transport = os.environ.get("SPRITE_DOWNLOAD_TRANSPORT", "websocket")
    if transport not in ("websocket", "http-post"):
        raise DownloadError("SPRITE_DOWNLOAD_TRANSPORT must be websocket or http-post.")
    archive_root = archive_component(checks.get("archive_root", "output") if isinstance(checks, dict) else "output")
    nonce = secrets.token_hex(16)
    proc, partial = None, None
    try:
        # A private CLI cwd prevents the local project's .sprite from changing
        # either the download target or the destination directory.
        with tempfile.TemporaryDirectory(prefix="sprite-output-context-") as context, tempfile.TemporaryFile() as errors:
            # Preserve the exact selected organization without reading credentials.
            copy_download_context(context_file, context)
            fd, partial = tempfile.mkstemp(prefix=".sprite-output-", suffix=".partial", dir=directory)
            with os.fdopen(fd, "w+b") as handle:
                args = [cli, "exec", *(["-o", org] if org else []), "-s", sprite]
                if transport == "http-post":
                    args.append("--http-post")
                args += ["--no-port-forward", "--", "python3", "-c", REMOTE_OUTPUT_PY, output_dir, nonce, str(level)]
                if checks is not None:
                    args.append(json.dumps(checks, separators=(",", ":")))
                print("       Streaming ZIP from the Sprite (no remote ZIP staging file)...", flush=True)
                proc = subprocess.Popen(args, cwd=context, stdin=subprocess.DEVNULL,
                                        stdout=handle, stderr=errors, start_new_session=True)
                started = time.monotonic()
                next_progress = started + 5
                while proc.poll() is None:
                    now = time.monotonic()
                    if now - started >= deadline:
                        raise DownloadError(f"Download exceeded SPRITE_DOWNLOAD_TIMEOUT={deadline}s; no final ZIP was saved.")
                    if now >= next_progress:
                        print(f"       Received {os.fstat(handle.fileno()).st_size / (1024*1024):,.1f} MiB...", flush=True)
                        next_progress = now + 5
                    time.sleep(0.1)
                problem = remote_failure(errors)
                if problem:
                    raise DownloadError(problem)
                print("       Verifying SHA-256 and ZIP contents...", flush=True)
                meta = verify_download(handle, nonce, archive_root)
                if proc.returncode:
                    # A received footer confirms completion of this request,
                    # and checksum/CRC verify its exact received bytes. The CLI
                    # connection, not an unkeyed checksum, handles authentication.
                    # This also handles known CLI missing-exit-frame failures.
                    print(f"       Warning: Sprite CLI exited {proc.returncode}, but the complete archive passed integrity checks.", flush=True)
                folder_slug = re.sub(r"[^A-Za-z0-9._-]+", "-", archive_root).strip(".-")[:64] or "folder"
                filename = f"sprite-{sprite}-{folder_slug}-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}-{nonce[:8]}.zip"
                target = directory / filename
                # Atomic no-clobber promotion: never overwrite an existing user file.
                os.link(partial, target)
                os.unlink(partial)
                partial = None
            print(f"  Saved: {safe(target)}", flush=True)
            print(f"       {meta['files']} file(s); ZIP {meta['size']:,} bytes; source {meta['raw_bytes']:,} bytes")
            print(f"       SHA-256: {meta['sha256']}")
            if meta["skipped"]:
                print(f"       Skipped {meta['skipped']} symlink/special-file entry/entries; links are never followed.")
            print("       Original files remain on the Sprite. Nothing was extracted or deleted.")
            return 0
    finally:
        stop_local_transfer(proc)
        if partial is not None:
            try:
                os.unlink(partial)
            except FileNotFoundError:
                pass


REMOTE_FOLDER_PY = r'''
# This source is run only inside a separate non-TTY Sprite exec.
import errno
import json
import os
import re
import stat
import sys

library = {"__name__": "sprite_zip_library"}
exec(compile(archive_source, "sprite_zip_library", "exec"), library)
open_directory = library["open_directory"]
signature = library["signature"]
OutputError = library["OutputError"]
PAGE_SIZE = 30
MAX_ENTRIES = 100000


def folder_path(value):
    home = os.path.normpath(os.path.expanduser("~"))
    if value in ("", "~", "$HOME"):
        value = home
    elif value.startswith("~/"):
        value = os.path.join(home, value[2:])
    elif value.startswith("$HOME/"):
        value = os.path.join(home, value[6:])
    if (not value.startswith("/") or len(value) > 8192 or ".." in value.split("/")
            or any(ord(c) < 32 or ord(c) == 127 for c in value)):
        raise OutputError("unsafe_path")
    return os.path.normpath(value)


def virtual(path):
    return any(path == p or path.startswith(p + "/") for p in ("/proc", "/sys", "/dev"))


def list_folder(req):
    path = folder_path(req.get("path", "~"))
    home = folder_path("~")
    if virtual(path):
        raise OutputError("virtual_path")
    fd = open_directory(path, allow_base=True)
    try:
        before = signature(os.fstat(fd))
        dirs, files, skipped, hidden = [], [], 0, 0
        file_count = 0
        with os.scandir(fd) as iterator:
            for count, entry in enumerate(iterator, 1):
                if count > MAX_ENTRIES:
                    raise OutputError("too_many_entries")
                st = entry.stat(follow_symlinks=False)
                if entry.name.startswith(".") and not req.get("hidden", False):
                    hidden += 1
                    continue
                if stat.S_ISDIR(st.st_mode):
                    dirs.append(entry.name)
                elif stat.S_ISREG(st.st_mode):
                    file_count += 1
                    # Names/sizes only; no file contents are read for previews.
                    files.append({"name": entry.name, "size": st.st_size})
                else:
                    skipped += 1
        if signature(os.fstat(fd)) != before:
            raise OutputError("changed")
        dirs.sort(key=lambda s: (s.casefold(), s))
        files.sort(key=lambda r: (r["name"].casefold(), r["name"]))
        pages = max(1, (len(dirs) + PAGE_SIZE - 1) // PAGE_SIZE)
        page = min(max(0, int(req.get("page", 0))), pages - 1)
        return dict(path=path, home=home, signature=list(before),
                    folders=dirs[page*PAGE_SIZE:(page+1)*PAGE_SIZE],
                    folder_count=len(dirs), files=files[:8], file_count=file_count,
                    hidden=hidden, skipped=skipped, page=page, pages=pages,
                    can_download=path not in ("/", home))
    finally:
        os.close(fd)


def workspace_places():
    home = folder_path("~")
    found = {}
    def add(path, label):
        try:
            path = folder_path(path)
            if virtual(path):
                return
            fd = open_directory(path, allow_base=True)
            os.close(fd)
            found.setdefault(path, label)
        except (OSError, ValueError, OutputError):
            pass
    # Bounded saved workspace hints; never inspect credentials, history or envs.
    try:
        fd = open_directory(home + "/.local/state/sprite-codex", allow_base=True)
    except (OSError, OutputError):
        fd = None
    if fd is not None:
        try:
            with os.scandir(fd) as iterator:
                for count, entry in enumerate(iterator, 1):
                    if count > 4096 or len(found) >= 128:
                        break
                    if not entry.name.startswith("workdir-"):
                        continue
                    try:
                        f = os.open(entry.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                        try:
                            st = os.fstat(f)
                            if not stat.S_ISREG(st.st_mode) or st.st_size > 8192:
                                continue
                            path = os.read(f, 8193).decode("utf-8").strip()
                            if path.startswith("/"):
                                add(path, "saved workspace hint")
                        finally:
                            os.close(f)
                    except (OSError, UnicodeError):
                        pass
        finally:
            os.close(fd)
    for base in (home + "/workspaces", "/workspaces", "/workspace"):
        add(base, "workspace directory")
        try:
            fd = open_directory(base, allow_base=True)
            try:
                with os.scandir(fd) as iterator:
                    for count, entry in enumerate(iterator, 1):
                        if count > 2048 or len(found) >= 256:
                            break
                        if not entry.name.startswith(".") and entry.is_dir(follow_symlinks=False):
                            add(base + "/" + entry.name, "workspace folder")
            finally:
                os.close(fd)
        except (OSError, OutputError):
            pass
    # Common output locations are shortcuts only, not assumed correct targets.
    for path in (home + "/output", "/output", "/app"):
        add(path, "existing folder")
    return {"places": [{"path": p, "label": found[p]} for p in sorted(found, key=lambda p: (p.casefold(), p))]}


def serve():
    req = json.loads(sys.argv[1])
    nonce = req.get("nonce", "")
    if not re.fullmatch(r"[0-9a-f]{32}", nonce):
        raise ValueError("invalid nonce")
    try:
        if sys.version_info < (3, 9):
            raise OutputError("python_version")
        if req.get("op") == "list":
            value = list_folder(req)
        elif req.get("op") == "places":
            value = workspace_places()
        else:
            raise OutputError("invalid_request")
        result = {"nonce": nonce, "ok": True, "data": value}
    except (OutputError, OSError, ValueError) as exc:
        if isinstance(exc, OutputError):
            reason = str(exc)
        elif isinstance(exc, FileNotFoundError):
            reason = "missing"
        elif isinstance(exc, PermissionError):
            reason = "permission"
        elif isinstance(exc, OSError) and exc.errno in (errno.ELOOP, errno.ENOTDIR):
            reason = "not_directory"
        else:
            reason = "read_failed"
        result = {"nonce": nonce, "ok": False, "error": reason}
    print("SPRITE_FOLDER_JSON=" + json.dumps(result, ensure_ascii=True, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    serve()
'''

class FolderCancelled(Exception):
    pass


def archive_component(value):
    """Use one safe, literal directory name as the ZIP's top-level folder."""
    if (not isinstance(value, str) or not value or value in (".", "..")
            or any(c in value for c in ("/", "\\", ":"))
            or any(ord(c) < 32 or ord(c) == 127 for c in value)):
        raise DownloadError("The folder name is not portable in a ZIP; select or rename a different folder.")
    try:
        value.encode("utf-8")
    except UnicodeError:
        raise DownloadError("The folder name cannot be encoded as UTF-8.") from None
    return value


def copy_download_context(context_file, context):
    if not context_file:
        return
    with open(context_file, "rb") as source:
        raw_context = source.read(65537)
    if len(raw_context) > 65536 or not isinstance(json.loads(raw_context), dict):
        raise DownloadError("Invalid saved Sprite CLI context; refusing to guess a download organization.")
    pinned = Path(context) / ".sprite"
    pinned.write_bytes(raw_context)
    pinned.chmod(0o600)


class FolderPicker:
    """Numbered remote folder browser. No shell commands or paths are required."""
    def __init__(self, sprite, org, context_file=""):
        cli = shutil.which("sprite")
        if not cli:
            raise DownloadError("The local sprite CLI was not found; authenticate it with sprite login.")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", sprite):
            raise DownloadError("Invalid Sprite name.")
        if org and (org.startswith("-") or any(c.isspace() or not c.isprintable() for c in org)):
            raise DownloadError("Invalid SPRITE_ORG.")
        self.cli, self.sprite, self.org = os.path.abspath(cli), sprite, org
        self.context_file = context_file
        self.timeout = integer("SPRITE_FOLDER_TIMEOUT", 45, 1, 300)
        self.transport = os.environ.get("SPRITE_DOWNLOAD_TRANSPORT", "websocket")
        if self.transport not in ("websocket", "http-post"):
            raise DownloadError("SPRITE_DOWNLOAD_TRANSPORT must be websocket or http-post.")

    def request(self, path="~", *, page=0, hidden=False, op="list"):
        nonce = secrets.token_hex(16)
        req = dict(nonce=nonce, op=op, path=path, page=page, hidden=hidden)
        code = "archive_source = " + repr(REMOTE_OUTPUT_PY) + "\n" + REMOTE_FOLDER_PY
        args = [self.cli, "exec", *(["-o", self.org] if self.org else []), "-s", self.sprite]
        if self.transport == "http-post":
            args.append("--http-post")
        args += ["--no-port-forward", "--", "python3", "-c", code,
                 json.dumps(req, ensure_ascii=True, separators=(",", ":"))]
        proc = None
        with tempfile.TemporaryDirectory(prefix="sprite-folder-context-") as context, \
                tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
            copy_download_context(self.context_file, context)
            try:
                proc = subprocess.Popen(args, cwd=context, stdin=subprocess.DEVNULL,
                                        stdout=output, stderr=errors, start_new_session=True)
                try:
                    proc.wait(timeout=self.timeout)
                except subprocess.TimeoutExpired:
                    raise DownloadError(f"Folder listing timed out after {self.timeout}s; retry or choose another folder.") from None
                output.seek(0)
                raw = output.read(512*1024 + 1)
                if len(raw) > 512*1024:
                    raise DownloadError("Folder listing was too large; no download was started.")
                lines = [line[len(b"SPRITE_FOLDER_JSON="):] for line in raw.splitlines()
                         if line.startswith(b"SPRITE_FOLDER_JSON=")]
                if len(lines) != 1:
                    raise DownloadError("No verified folder listing was received; check the Sprite connection and Python 3.9+.")
                try:
                    result = json.loads(lines[0])
                except (ValueError, UnicodeError):
                    raise DownloadError("Invalid folder-listing response; no folder was selected.") from None
                if not isinstance(result, dict) or result.get("nonce") != nonce or type(result.get("ok")) is not bool:
                    raise DownloadError("Invalid folder-listing completion record; no folder was selected.")
                if not result["ok"]:
                    messages = {
                        "missing": "That folder does not exist on the Sprite. Choose another folder; nothing was created.",
                        "permission": "The Sprite user cannot read that folder. Choose a readable folder (no sudo is used).",
                        "not_directory": "That path is not a directory or includes a symlink. Links are not followed.",
                        "unsafe_path": "Use an absolute remote folder or a ~/ path without '..' or control characters.",
                        "virtual_path": "Virtual system folders /proc, /sys and /dev cannot be browsed or archived here.",
                        "changed": "The directory changed while listing. Refresh after its file writes finish.",
                        "too_many_entries": "Too many entries in this directory; use P to open a specific subfolder.",
                        "python_version": "Python 3.9 or newer is required on the Sprite.",
                    }
                    raise DownloadError(messages.get(result.get("error"), "The remote folder could not be read."))
                data = result.get("data")
                if not isinstance(data, dict):
                    raise DownloadError("Invalid folder-listing data.")
                if op == "list":
                    if (not isinstance(data.get("path"), str) or not data["path"].startswith("/")
                            or not isinstance(data.get("home"), str) or not data["home"].startswith("/")
                            or not isinstance(data.get("signature"), list) or len(data["signature"]) != 6
                            or not all(type(x) is int for x in data["signature"])
                            or not isinstance(data.get("folders"), list) or len(data["folders"]) > 30
                            or not all(isinstance(x, str) and x not in ("", ".", "..") and "/" not in x for x in data["folders"])
                            or not isinstance(data.get("files"), list)
                            or not all(isinstance(x, dict) and isinstance(x.get("name"), str) and type(x.get("size")) is int for x in data["files"])
                            or not all(type(data.get(k)) is int and data[k] >= 0 for k in ("page", "pages", "file_count", "folder_count", "hidden", "skipped"))
                            or data["pages"] < 1 or data["page"] >= data["pages"] or len(data["files"]) > 8
                            or type(data.get("can_download")) is not bool):
                        raise DownloadError("Invalid folder metadata; no folder was selected.")
                elif not isinstance(data.get("places"), list) or not all(
                        isinstance(x, dict) and isinstance(x.get("path"), str) and x["path"].startswith("/")
                        and isinstance(x.get("label"), str) for x in data["places"]):
                    raise DownloadError("Invalid workspace shortcuts.")
                # The nonce completion record is authoritative for read-only probes
                # even if the local CLI subsequently loses an exit frame.
                return data
            finally:
                stop_local_transfer(proc)

    @staticmethod
    def ask(prompt):
        try:
            return input(prompt).strip()
        except EOFError:
            raise FolderCancelled() from None

    def places(self):
        print("\n=== workspace / output shortcuts", flush=True)
        print("       Saved paths are hints, not proof of a live Codex session.")
        places = self.request(op="places")["places"]
        if not places:
            print("       No saved workspace folders found. Browse from home or / instead.")
            return None
        for i, place in enumerate(places, 1):
            print(f"    {i}) {safe(place['path'])}  [{safe(place['label'])}]")
        while True:
            choice = self.ask("  Open shortcut number, or Enter to go back: ").lower()
            if choice in ("", "b", "q"):
                return None
            if choice.isdecimal() and 1 <= int(choice) <= len(places):
                return places[int(choice)-1]["path"]
            print("       Choose a displayed number, or Enter to go back.")

    def choose(self, local_dir, start="~"):
        path, page, hidden = start or "~", 0, False
        while True:
            print(f"\n=== choose remote folder to download as ZIP — {safe(self.sprite)}", flush=True)
            try:
                info = self.request(path, page=page, hidden=hidden)
                path, page = info["path"], info["page"]
            except DownloadError as exc:
                info = None
                print(f"       Cannot browse {safe(path)}: {exc}")
            if info is not None:
                print(f"       REMOTE folder: {safe(path)}")
                print(f"       LOCAL ZIP directory: {safe(local_dir)}")
                for i, name in enumerate(info["folders"], 1):
                    print(f"    {i}) {safe(name)}/")
                if not info["folders"]:
                    print("       No visible subfolders here.")
                if info["files"]:
                    print(f"       Files here (names only; showing {len(info['files'])} of {info['file_count']}):")
                    for item in info["files"]:
                        print(f"         {safe(item['name'])}  ({item['size']:,} bytes)")
                if info["hidden"]:
                    print(f"       {info['hidden']} hidden entries not shown; T toggles their display.")
                if info["skipped"]:
                    print(f"       {info['skipped']} symlink/special entries not offered.")
                if info["pages"] > 1:
                    print(f"       Folder page {page+1}/{info['pages']} — N next, B previous page.")
                if not info["can_download"]:
                    print("       Open a subfolder: archiving / or the entire home folder is disabled.")
            print("       Number = open folder | D = ZIP this folder | U = parent | H = home")
            print("       W = workspace shortcuts | / = filesystem root | P = enter path (optional)")
            print("       T = hidden names | R = refresh | Q = cancel")
            choice = self.ask("  Folder action: ").lower()
            if choice in ("q", "quit", ""):
                raise FolderCancelled()
            if choice == "d":
                if info is None:
                    print("       A verified folder listing is required before downloading.")
                    continue
                if not info["can_download"]:
                    print("       Choose a specific subfolder rather than / or the entire home folder.")
                    continue
                try:
                    root_name = archive_component(PurePosixPath(path).name)
                except DownloadError as exc:
                    print("       " + str(exc))
                    continue
                print("\n=== confirm folder ZIP")
                print(f"       Sprite: {safe(self.sprite)}")
                print(f"       Source: {safe(path)}")
                print(f"       ZIP contents start with: {safe(root_name)}/")
                print(f"       Save into: {safe(local_dir)}")
                print("       Includes nested folders and ALL regular files, including hidden files.")
                print("       Check for credentials before confirming; symlinks/special files are skipped.")
                print("       Finish writes first. Codex is not paused; no source files will be deleted.")
                if self.ask("  Download this selected folder as a ZIP? [y/N]: ").lower() not in ("y", "yes"):
                    print("       Not downloaded. You can choose another folder.")
                    continue
                return path, {"kind": "directory", "expected": info["signature"], "archive_root": root_name}
            if choice == "r":
                continue
            if choice == "t":
                hidden, page = not hidden, 0
                continue
            if choice in ("n", "b") and info is not None:
                page = min(info["pages"] - 1, page + 1) if choice == "n" else max(0, page - 1)
                continue
            if choice == "h":
                path, page = "~", 0
                continue
            if choice == "/":
                path, page = "/", 0
                continue
            if choice == "u":
                path, page = (str(PurePosixPath(path).parent) if path.startswith("/") else "~"), 0
                continue
            if choice == "w":
                try:
                    target = self.places()
                    if target:
                        path, page = target, 0
                except DownloadError as exc:
                    print("       " + str(exc))
                continue
            if choice == "p":
                target = self.ask("  Remote folder (absolute or ~/; Enter cancels): ")
                if target:
                    path, page = target, 0
                continue
            if info is not None and choice.isdecimal() and 1 <= int(choice) <= len(info["folders"]):
                path, page = str(PurePosixPath(path) / info["folders"][int(choice)-1]), 0
                continue
            print("       Choose a listed number or one of the actions above.")


def main():
    if sys.version_info < (3, 9):
        raise DownloadError("Local Python 3.9 or newer is required.")
    sprite, mode, local_dir, output_dir, org = sys.argv[1:6]
    context_file = sys.argv[6] if len(sys.argv) > 6 else ""
    # The shell always supplies 0/1; direct old helper callers provide an explicit
    # output_dir and retain their noninteractive semantics.
    explicit = sys.argv[7] if len(sys.argv) > 7 else "1"
    if explicit not in ("0", "1"):
        raise DownloadError("Invalid folder-selection mode.")
    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    if mode not in ("ask", "always", "never"):
        raise DownloadError("SPRITE_OUTPUT_DOWNLOAD must be ask, always, or never.")
    if mode == "never" or (mode == "ask" and not interactive):
        return 0
    print("\n=== download Sprite folder as ZIP", flush=True)
    print(f"       Sprite: {safe(sprite)}\n       Local ZIP directory: {safe(local_dir)}")
    if mode == "ask":
        try:
            answer = input("  Browse Sprite folders and download one as a ZIP now? [y/N]: ").strip().lower()
        except EOFError:
            answer = "n"
        if answer not in ("y", "yes"):
            print("       Download skipped; remote files are unchanged.")
            return 0
    if not interactive:
        if explicit != "1":
            raise DownloadError("Without an interactive terminal, specify --output-dir or SPRITE_OUTPUT_DIR; no default folder is assumed.")
        root_name = archive_component(PurePosixPath(output_dir).name)
        print(f"       Explicit remote folder: {safe(output_dir)}")
        print("       Includes hidden regular files; finish writes first. Source files remain unchanged.")
        return download(sprite, output_dir, local_dir, org, context_file,
                        checks={"kind": "directory", "archive_root": root_name})
    picker = FolderPicker(sprite, org, context_file)
    start, failed = (output_dir if explicit == "1" else "~"), False
    while True:
        try:
            path, checks = picker.choose(local_dir, start)
        except FolderCancelled:
            print("       Folder download cancelled. No final ZIP was saved; source files are unchanged.")
            return 1 if failed else 0
        try:
            return download(sprite, path, local_dir, org, context_file, checks=checks)
        except DownloadError as exc:
            print("error: " + str(exc), file=sys.stderr)
            print("       No final ZIP was saved. You can choose another folder or retry after writes finish.")
            start, failed = path, True

if __name__ == "__main__":
    def interrupted(signum, frame):
        raise DownloadInterrupted(signum)
    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, DownloadInterrupted) as exc:
        print("\n       Download interrupted. Original files and agent sessions were not deleted or stopped.", file=sys.stderr)
        raise SystemExit(128 + getattr(exc, "signum", signal.SIGINT))
    except (DownloadError, OSError, ValueError) as exc:
        message = str(exc) if isinstance(exc, DownloadError) else "Local file/CLI operation failed (check free disk space, permissions and connection)."
        print("error: " + message, file=sys.stderr)
        print("       No final ZIP was saved. Retry with --download-output; the source files remain on the Sprite.", file=sys.stderr)
        raise SystemExit(1)
OUTPUT_DOWNLOAD_PY
}

run_output_download() {
  local selected_sprite=$1 mode=${2:-$SPRITE_OUTPUT_DOWNLOAD} context_file=${3:-${OUTPUT_PINNED_CONTEXT:-}}
  [[ $mode != never ]] || return 0
  command -v python3 >/dev/null 2>&1 || { echo "warning: output download requires local python3" >&2; return 127; }
  python3 -c "$(output_download_python)" "$selected_sprite" "$mode" "$OUTPUT_HOST_DIR" "$SPRITE_OUTPUT_DIR" "${SPRITE_ORG:-}" "$context_file" "${OUTPUT_PATH_EXPLICIT:-1}"
}

maybe_download_output() {
  local selected_sprite=$1 session_rc=${2:-0} download_rc=0
  # Do not start another operation after an interrupt/hangup/termination.
  case "$session_rc" in 129|130|131|137|143) return 0 ;; esac
  [[ $SPRITE_OUTPUT_DOWNLOAD != never ]] || return 0
  if run_output_download "$selected_sprite"; then
    return 0
  else
    download_rc=$?
    printf 'warning: optional output download did not finish (exit %s); session exit status is preserved.
' "$download_rc" >&2
    return 0
  fi
}

attach_only_python() {
  cat <<'ATTACH_ONLY_PY'
"""Local-only Sprite/session picker. Optional download is a separate host hook.

CLI/API contracts checked 2026-09-24:
https://docs.sprites.dev/api/dev-latest/exec/
https://docs.sprites.dev/api/dev-latest/sprites/
https://docs.sprites.dev/cli/commands/
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import termios
import time
import unicodedata
from urllib.parse import urlencode


class AttachError(Exception):
    def __init__(self, message: str, code: int = 1):
        super().__init__(message)
        self.code = code


class Cancelled(Exception):
    pass


def safe(value: object, limit: int = 180) -> str:
    """Never let inventory metadata inject terminal control/format characters."""
    text = str(value) if value is not None else ""
    text = "".join(c if c.isprintable() and not unicodedata.category(c).startswith("C")
                   else " " for c in text)
    return " ".join(text.split())[:limit]


def identifier(value: object, label: str, pattern: str) -> str:
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        raise AttachError("Invalid " + label + ".", 2)
    text = str(value)
    if not re.fullmatch(pattern, text):
        raise AttachError("Invalid " + label + ".", 2)
    return text


NAME_PATTERN = r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}"
SESSION_PATTERN = r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}"


def env_int(name: str, default: int, minimum: int, maximum: int) -> int:
    text = os.environ.get(name, str(default))
    if not re.fullmatch(r"[0-9]{1,6}", text) or not minimum <= int(text) <= maximum:
        raise AttachError(f"{name} must be {minimum}..{maximum}.", 2)
    return int(text)


def flag(value: object):
    if isinstance(value, bool):
        return value
    if isinstance(value, (str, int)) and str(value).lower() in ("true", "false", "1", "0"):
        return str(value).lower() in ("true", "1")
    return None


def collection(root: object, keys: tuple[str, ...], depth: int = 0):
    """Reject an error/unknown schema rather than treating it as an empty list."""
    if isinstance(root, list):
        return root, {}
    if not isinstance(root, dict) or depth > 4 or root.get("error"):
        raise AttachError("Unrecognized or unsuccessful inventory response; session state is unknown.")
    for key in keys:
        if key in root:
            if key == "data" and isinstance(root[key], dict):
                continue  # wrapper, not the collection itself
            if not isinstance(root[key], list):
                raise AttachError("Invalid inventory collection; session state is unknown.")
            return root[key], root
    for key in ("data", "result", "response"):
        if isinstance(root.get(key), dict):
            items, meta = collection(root[key], keys, depth + 1)
            return items, {**root, **meta}
    raise AttachError("Unrecognized inventory response; session state is unknown.")


def created_info(record: dict):
    value = next((record[k] for k in
                  ("created_at", "createdAt", "created", "started_at", "startedAt", "started")
                  if record.get(k) not in (None, "")), "")
    epoch = 0.0
    try:
        epoch = float(value)
    except (TypeError, ValueError):
        try:
            date = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            if date.tzinfo is None:
                date = date.replace(tzinfo=dt.timezone.utc)
            epoch = date.timestamp()
        except (ValueError, OverflowError, OSError):
            pass
    if not math.isfinite(epoch):
        epoch = 0.0
    try:
        display = dt.datetime.fromtimestamp(epoch, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC") if epoch > 0 else "unknown"
    except (ValueError, OverflowError, OSError):
        epoch, display = 0.0, "unknown"
    return value, epoch, display


def command_info(record: dict):
    command = record.get("command", record.get("cmd", ""))
    if isinstance(command, list) and all(isinstance(x, str) for x in command):
        argv = command
    elif isinstance(command, str):
        try:
            argv = shlex.split(command)
        except ValueError:
            argv = []
    else:
        argv = []
    # These are display hints about the recorded session command, not a scan of
    # its child processes and not a promise that the agent is currently working.
    label = "Other terminal"
    workdir = record.get("workdir", record.get("dir", record.get("cwd", "")))
    if not isinstance(workdir, str):
        workdir = ""
    for index, arg in enumerate(argv):
        base = os.path.basename(arg)
        if re.fullmatch(r"sprite-(codex|kimi-code)-native-[A-Za-z0-9._-]+", base):
            label = "Kimi Code runner" if base.startswith("sprite-kimi-code-") else "Codex runner"
            # The managed runner receives RUN_SECONDS, TASK_NAME, SESSION_TAG,
            # WORKDIR. Prefer that workspace over the entrypoint's initial cwd.
            if "-runner" in base and len(argv) > index + 4 and argv[index + 1].isdigit():
                if argv[index + 4].startswith("/"):
                    workdir = argv[index + 4]
                    break
    if label == "Other terminal" and argv:
        program = os.path.basename(argv[0])
        if program in ("codex", "sprite-codex-cli") or program.startswith("sprite-codex-"):
            label = "Codex command"
        elif program in ("kimi", "sprite-kimi-code"):
            label = "Kimi Code command"
        elif program in ("bash", "sh", "zsh", "fish", "dash"):
            label = "Shell (" + program + ")"
        elif program == "tmux":
            label = "tmux client terminal"
    return command, label, safe(workdir) or "unknown"


def parse_sessions(root: object):
    records, meta = collection(root, ("sessions", "items", "data"))
    if flag(meta.get("has_more")) is True or meta.get("next_continuation_token"):
        raise AttachError("Incomplete session inventory; refusing to choose from a partial response.")
    rows, excluded, seen = [], {"inactive": 0, "non_tty": 0, "unknown": 0}, set()
    for record in records:
        if not isinstance(record, dict):
            raise AttachError("Invalid session record; session state is unknown.")
        sid = identifier(record.get("id", record.get("session_id")), "session ID in inventory", SESSION_PATTERN)
        if sid in seen:
            raise AttachError("Duplicate session ID in inventory; refresh before attaching.")
        seen.add(sid)
        active_keys = ("is_active", "isActive", "active")
        tty_keys = ("tty", "is_tty", "isTty")
        active_key = next((k for k in active_keys if k in record), None)
        tty_key = next((k for k in tty_keys if k in record), None)
        # Activity is display metadata, not a process-exit signal. The exec API
        # can return sessions whose is_active flag is false; the official SDK
        # does not remove them. Let the attach endpoint decide if a listed TTY
        # is attachable, after our existing identity/existence recheck.
        active = flag(record[active_key]) if active_key else None
        tty = flag(record[tty_key]) if tty_key else None
        status = str(record.get("status", record.get("state", ""))).strip().lower()
        if status in ("exited", "ended", "stopped", "dead", "completed", "failed", "terminated", "killed", "closed"):
            # Retain the internal counter name for callers; it now counts only
            # explicit terminal-ended statuses, never an activity flag alone.
            excluded["inactive"] += 1
            continue
        if tty is None:
            excluded["unknown"] += 1
            continue
        if not tty:
            excluded["non_tty"] += 1
            continue
        command, label, workdir = command_info(record)
        created, epoch, display = created_info(record)
        identity = hashlib.sha256(json.dumps([sid, command, created], sort_keys=True).encode()).hexdigest()
        rows.append({"id": sid, "label": label, "workdir": workdir, "created": display,
                     "epoch": epoch, "identity": identity, "activity": active})
    rows.sort(key=lambda r: (r["epoch"], r["id"]), reverse=True)
    return rows, excluded


def ask(prompt: str) -> str:
    try:
        return input(prompt).strip()
    except EOFError:
        raise Cancelled()


class Picker:
    def __init__(self, context: str, selection_only: bool = False):
        self.context = context
        self.cli = shutil.which("sprite")
        if not self.cli:
            raise AttachError("Required local command not found: sprite", 127)
        self.cli = os.path.abspath(self.cli)
        org = os.environ.get("SPRITE_ORG", "")
        if org and (org.startswith("-") or any(c.isspace() or not c.isprintable() for c in org)):
            raise AttachError("Invalid SPRITE_ORG.", 2)
        self.org = ["-o", org] if org else []
        self.timeout = env_int("SPRITE_ATTACH_TIMEOUT", 25, 1, 300)
        self.auto = 0 if selection_only else env_int("TTY_AUTO_REATTACH", 1, 0, 1)
        self.attempts = 0 if selection_only else env_int("TTY_REATTACH_ATTEMPTS", 12, 0, 99999)
        self.confirm_tries = 1 if selection_only else env_int("TTY_REATTACH_CONFIRM_TRIES", 8, 1, 99999)
        self.delay = 0 if selection_only else env_int("TTY_REATTACH_DELAY", 3, 0, 300)

    def capture(self, args: list[str], check: bool = True):
        try:
            result = subprocess.run([self.cli, *args], cwd=self.context,
                                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, encoding="utf-8", errors="replace",
                                    timeout=self.timeout, check=False)
        except subprocess.TimeoutExpired:
            raise AttachError("Sprite CLI request timed out; session state is unknown.") from None
        except OSError:
            raise AttachError("Could not execute the local Sprite CLI.") from None
        if check and result.returncode:
            # Do not echo arbitrary CLI responses: they may contain credentials
            # or full command arguments. Preserve the actionable status only.
            raise AttachError(f"Sprite CLI request failed (exit {result.returncode}). Check your Sprites login, organization and connection.")
        return result

    def api(self, path: str, sprite: str = ""):
        args = ["api", *self.org]
        if sprite:
            args.extend(("-s", sprite))
        result = self.capture([*args, path])
        try:
            return json.loads(result.stdout)
        except (ValueError, TypeError):
            raise AttachError("Sprite API returned invalid JSON; session state is unknown.") from None

    def sprites(self):
        found, token, seen = {}, "", set()
        for _ in range(1000):
            path = "/sprites"
            if token:
                path += "?" + urlencode({"continuation_token": token})
            records, meta = collection(self.api(path), ("sprites", "sprite_list", "items", "data"))
            for record in records:
                if not isinstance(record, dict):
                    raise AttachError("Invalid Sprite inventory record.")
                name = identifier(record.get("name", record.get("sprite_name")), "Sprite name in inventory", NAME_PATTERN)
                found[name] = safe(record.get("status", record.get("state", "unknown")), 30) or "unknown"
            token = meta.get("next_continuation_token") or ""
            if not token:
                if flag(meta.get("has_more")) is True:
                    raise AttachError("Sprite inventory is incomplete: the next-page token is missing.")
                return sorted(found.items())
            if not isinstance(token, str) or token in seen or len(token) > 8192:
                raise AttachError("Invalid or repeated Sprite pagination token.")
            seen.add(token)
        raise AttachError("Sprite pagination limit reached; inventory is incomplete.")

    def choose_sprite(self, requested: str = "") -> str:
        if requested:
            return identifier(requested, "SPRITE_NAME", NAME_PATTERN)
        while True:
            print("\n=== choose Sprite (current CLI organization" + (", " + safe(self.org[1]) if self.org else "") + ")", flush=True)
            try:
                sprites = self.sprites()
            except AttachError as exc:
                print("Warning: " + str(exc), flush=True)
                if ask("  R = retry, Q = quit [Q]: ").lower() == "r":
                    continue
                raise Cancelled()
            if not sprites:
                raise AttachError("No Sprites were returned for this organization. Nothing was created or launched.", 3)
            for index, (name, state) in enumerate(sprites, 1):
                print(f"    {index}) {name}  (reported state: {state})")
            answer = ask("  Choose Sprite number or name; R = refresh, Q = quit: ")
            if answer.lower() == "q":
                raise Cancelled()
            if answer.lower() == "r":
                continue
            # Names are resolved against this inventory, never as shell text.
            if re.fullmatch(r"[0-9]{1,6}", answer) and 1 <= int(answer) <= len(sprites):
                return sprites[int(answer) - 1][0]
            if answer in dict(sprites):
                return answer
            print("  Invalid selection; choose one of the listed Sprites.")

    def sessions(self, sprite: str):
        return parse_sessions(self.api("/exec", sprite))

    def choose_session(self, sprite: str, requested: str = ""):
        while True:
            print(f"\n=== listed native terminal sessions on {sprite}", flush=True)
            try:
                rows, excluded = self.sessions(sprite)
            except AttachError as exc:
                if requested:
                    raise
                print("Warning: " + str(exc))
                answer = ask("  R = retry, S = choose another Sprite, Q = quit [Q]: ").lower()
                if answer == "r":
                    continue
                if answer == "s":
                    return None
                raise Cancelled()
            if requested:
                row = next((r for r in rows if r["id"] == requested), None)
                if row is None:
                    raise AttachError("Requested session is not confirmed as a live native terminal on this Sprite. No process was launched.", 3)
                return row
            total = len(rows) + sum(excluded.values())
            print(f"       Exec inventory: {total} record(s); {len(rows)} terminal candidate(s).")
            for index, row in enumerate(rows, 1):
                print(f"    {index}) ID={row['id']}  {row['label']}")
                print(f"       Created: {row['created']}\n       Workspace: {row['workdir']}")
                activity = row.get("activity")
                if activity is False:
                    print("       API activity: false (not proof of exit; attachment is still offered).")
                elif activity is True:
                    print("       API activity: true (not a terminal responsiveness check).")
                else:
                    print("       API activity: not reported or unrecognized (not used as an exit signal).")
            if excluded["inactive"]:
                print(f"       Not offered: {excluded['inactive']} session(s) explicitly reported as ended.")
            if excluded["non_tty"]:
                print(f"       Not offered: {excluded['non_tty']} non-terminal command(s).")
            if excluded["unknown"]:
                print(f"       Not offered: {excluded['unknown']} session(s) with unconfirmed TTY metadata.")
            if rows:
                print("       Newest first. Labels describe recorded commands, not conversation titles.")
                answer = ask("  Attach number [1]; R = refresh, S = another Sprite, Q = quit: ")
            else:
                print("       No attachable native terminal was returned. Nothing will be launched.")
                if total == 0:
                    print("       The exec API returned an empty collection, not a filtered-out terminal.")
                print("       A Sprite reported as running does not itself prove a Codex terminal exists.")
                print("       Saved Codex conversations and legacy tmux-only sessions are not this inventory.")
                answer = ask("  R = refresh, S = another Sprite, Q = quit [Q]: ")
            if answer.lower() == "q" or (not rows and not answer):
                raise Cancelled()
            if answer.lower() == "s":
                return None
            if answer.lower() == "r":
                continue
            answer = answer or "1"
            if re.fullmatch(r"[0-9]{1,6}", answer) and 1 <= int(answer) <= len(rows):
                return rows[int(answer) - 1]
            print("  Invalid selection; no session was attached.")

    def live_same_session(self, sprite: str, row: dict) -> bool:
        """Check listed identity, not output activity or keyboard responsiveness."""
        rows, _ = self.sessions(sprite)
        current = next((r for r in rows if r["id"] == row["id"]), None)
        if current and current["identity"] != row["identity"]:
            raise AttachError("Session identity changed since selection; refusing to attach to a potentially reused ID.")
        return current is not None

    def attach(self, sprite: str, row: dict) -> int:
        # Keep the caller's .sprite file and project resume-state files untouched.
        self.capture(["use", *self.org, sprite])
        command = None
        for candidate in (["sessions", "attach"], ["attach"]):
            if self.capture([*candidate, "--help"], check=False).returncode == 0:
                command = candidate
                break
        if command is None:
            raise AttachError("This Sprite CLI has no recognized session-attach command.", 127)
        # Recheck AFTER the picker and context creation, immediately before attach.
        if not self.live_same_session(sprite, row):
            raise AttachError("Selected session ended before attachment. No replacement was started.", 3)
        print(f"\n       Attaching to {sprite}, native session {row['id']} ({row['label']}).")
        print("       Existing process credentials are unchanged; no keys, updates or setup.")
        print("       Detach with Ctrl+\\. This is NOT codex resume; no new Codex is launched.", flush=True)
        failures = 0
        while True:
            started = time.monotonic()
            terminal_state = termios.tcgetattr(sys.stdin.fileno())
            try:
                # No timeout on interactive use. The CLI receives the real TTY
                # and handles raw mode, resizing and its own detach shortcut.
                rc = subprocess.call([self.cli, *command, row["id"]], cwd=self.context)
            finally:
                try:
                    termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, terminal_state)
                except termios.error:
                    pass
            rc = 128 - rc if rc < 0 else rc
            if rc == 0:
                print("\n       Attachment ended cleanly; no replacement session was launched.")
                return 0
            if rc == 137:
                print("\n       Attachment ended with exit 137; not automatically retrying this terminal.")
                print("       This is not proof of OOM or file loss. Use opening menu 6 / --retrieve for independent Git recovery.")
                return rc
            if rc in (129, 130, 131, 143) or not self.auto:
                return rc
            if time.monotonic() - started >= 30:
                failures = 0
            failures += 1
            if self.attempts and failures > self.attempts:
                print("       Automatic reattach limit reached; rerun --attach-only to reconnect.")
                return rc
            print(f"\n       Attachment ended with exit {rc}; checking the SAME session before retrying.", flush=True)
            confirmed = False
            last_error = None
            for attempt in range(self.confirm_tries):
                try:
                    if self.live_same_session(sprite, row):
                        confirmed = True
                        break
                    last_error = None
                except AttachError as exc:
                    last_error = exc
                if attempt + 1 < self.confirm_tries:
                    time.sleep(self.delay)
            if not confirmed:
                print("       " + (str(last_error) if last_error else "The selected terminal is no longer confirmed live."))
                print("       Nothing was started or replaced; rerun --attach-only after connectivity recovers.")
                return rc
            time.sleep(self.delay)


def main() -> int:
    if sys.version_info < (3, 9):
        raise AttachError("Attach-only requires local Python 3.9 or newer.", 2)
    selection_only = len(sys.argv) > 3 and sys.argv[3] == "download"
    if not selection_only and (not sys.stdin.isatty() or not sys.stdout.isatty()):
        raise AttachError("Attach-only requires an interactive terminal for stdin and stdout. Nothing was launched.", 2)
    requested_id = sys.argv[1] if len(sys.argv) > 1 else ""
    requested_sprite = os.environ.get("SPRITE_NAME", "")
    receipt = sys.argv[2] if len(sys.argv) > 2 else ""
    def write_receipt(sprite):
        if receipt:
            with open(receipt, "w", encoding="utf-8") as handle:
                json.dump({"sprite": sprite}, handle)
            selected_context = os.path.join(context, ".sprite")
            if os.path.isfile(selected_context):
                with open(selected_context, "rb") as source:
                    data = source.read(65537)
                if len(data) > 65536:
                    raise AttachError("Sprite CLI context is unexpectedly large; download target was not preserved.")
                with open(receipt + ".context", "wb") as target:
                    target.write(data)
    if selection_only and not requested_sprite and (not sys.stdin.isatty() or not sys.stdout.isatty()):
        raise AttachError("Noninteractive --download-output requires SPRITE_NAME.", 2)
    if requested_id:
        identifier(requested_id, "--session-id", SESSION_PATTERN)
        if not requested_sprite:
            raise AttachError("--session-id requires SPRITE_NAME to avoid attaching to the same ID on the wrong Sprite.", 2)
    print("\n=== choose Sprite for output download" if selection_only else "\n=== attach-only: existing native Sprite terminal", flush=True)
    print("       Uses your local Sprites login; no GitHub, Fly-app or model keys are requested.")
    if os.environ.get("FORCE_NEW_SESSION") == "1":
        print("       FORCE_NEW_SESSION=1 is ignored in attach-only mode; existing sessions will not be killed.")
    with tempfile.TemporaryDirectory(prefix="sprite-codex-attach-") as context:
        picker = Picker(context, selection_only=selection_only)
        sprite = picker.choose_sprite(requested_sprite)
        if selection_only:
            write_receipt(sprite)
            return 0
        while True:
            row = picker.choose_session(sprite, requested_id)
            if row is None:
                sprite = picker.choose_sprite()
                continue
            rc = picker.attach(sprite, row)
            write_receipt(sprite)
            return rc


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Cancelled:
        print("\n       Attach-only cancelled; no new session was launched.")
        raise SystemExit(0)
    except KeyboardInterrupt:
        print("\n       Attach-only interrupted; no remote kill or replacement was requested.")
        raise SystemExit(130)
    except AttachError as exc:
        print("error: " + str(exc), file=sys.stderr)
        raise SystemExit(exc.code)
    except OSError:
        print("error: local terminal or temporary-context operation failed; no bootstrap fallback.", file=sys.stderr)
        raise SystemExit(1)
ATTACH_ONLY_PY
}

run_attach_only() {
  command -v python3 >/dev/null 2>&1 || { echo "error: local python3 is required for attach-only" >&2; return 127; }
  # -c leaves stdin attached to the real terminal for the picker and Sprite CLI.
  # All inventory parsing happens locally. No helper is uploaded to the Sprite.
  python3 -c "$(attach_only_python)" "$ATTACH_SESSION_ID" "${1:-}" "$RUN_MODE"
}


# v52: all file-mode dispatch stays above bootstrap config/credentials/side effects.
file_access_python() {
  cat <<'FILES_ACCESS_PY'
"""Local shell/file menu for one existing Sprite, separate from its agent TTY.
Generated into sprite-codex-v59.sh; uses the retained picker and ZIP downloader.
"""
from __future__ import annotations
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import secrets
import shlex
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import termios
import time
import types
import unicodedata

REMOTE_FILES_PY = r'''"""Small stat/list/preview, checked streaming transfer and shell helper on Sprite.
No account credentials or process inspection. Paths are opened without symlinks.
"""
import base64
import ctypes
import errno
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import stat
import struct
import sys
import time

CHUNK = 1024 * 1024
MAX_MANIFEST = 16 * 1024 * 1024
MAX_ENTRIES = 100000
MAGIC = b"SPRITE_FILES_UPLOAD_V1\n"
DONE = b"SPRITE_FILES_UPLOAD_DONE "
FILE_MAGIC = b"\nSPRITE_CODEX_FILE_V1 "
FOOTER_SIZE = 512

class FileError(Exception):
    pass

def signature(st):
    return (st.st_dev, st.st_ino, st.st_mode, st.st_size, st.st_mtime_ns, st.st_ctime_ns)

def path_value(value, base="/"):
    if not isinstance(value, str) or not value or len(value) > 8192 or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise FileError("invalid_path")
    if value == "~" or value == "$HOME":
        value = os.path.expanduser("~")
    elif value.startswith("~/"):
        value = os.path.expanduser("~") + value[1:]
    elif value.startswith("$HOME/"):
        value = os.path.expanduser("~") + value[5:]
    elif value.startswith("~"):
        raise FileError("invalid_path")
    return os.path.normpath(value if value.startswith("/") else os.path.join(base, value))

def open_dir(path):
    if not os.path.isabs(path):
        raise FileError("invalid_path")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.split("/"):
            if not part:
                continue
            if part in (".", ".."):
                raise FileError("invalid_path")
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise

def inspect_path(path):
    if path == "/":
        st = os.stat(path)
    else:
        parent = open_dir(os.path.dirname(path))
        try:
            st = os.stat(os.path.basename(path), dir_fd=parent, follow_symlinks=False)
        finally:
            os.close(parent)
    kind = "dir" if stat.S_ISDIR(st.st_mode) else "file" if stat.S_ISREG(st.st_mode) else "link" if stat.S_ISLNK(st.st_mode) else "special"
    return dict(path=path, kind=kind, size=st.st_size, identity=[st.st_dev, st.st_ino], signature=list(signature(st)))

def component(value):
    if (not isinstance(value, str) or not value or value in (".", "..") or len(value.encode("utf-8")) > 255
        or any(c in value for c in ("/", "\\", ":")) or any(ord(c) < 32 or ord(c) == 127 for c in value)):
        raise FileError("invalid_name")
    return value

def validate_manifest(data):
    if not isinstance(data, dict) or data.get("kind") not in ("file", "dir") or not isinstance(data.get("entries"), list):
        raise FileError("invalid_manifest")
    entries = data["entries"]
    if len(entries) > MAX_ENTRIES:
        raise FileError("too_many_entries")
    seen, dirs = set(), set()
    for item in entries:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            raise FileError("invalid_manifest")
        path = item["path"]
        if not path or len(path.encode("utf-8")) > 8192 or path in seen or item.get("kind") not in ("file", "dir"):
            raise FileError("invalid_manifest")
        for part in path.split("/"):
            component(part)
        parent = path.rpartition("/")[0]
        if parent and parent not in dirs:
            raise FileError("invalid_manifest")
        seen.add(path)
        if item["kind"] == "dir":
            dirs.add(path)
        elif type(item.get("size")) is not int or not 0 <= item["size"] < 2**63:
            raise FileError("invalid_manifest")
        if type(item.get("executable", False)) is not bool:
            raise FileError("invalid_manifest")
    if data["kind"] == "file" and (len(entries) != 1 or entries[0]["kind"] != "file" or entries[0]["path"] != "payload"):
        raise FileError("invalid_manifest")
    return entries

def read_exact(source, n):
    parts = []
    while n:
        data = source.read(min(n, CHUNK))
        if not data:
            raise FileError("incomplete_upload")
        parts.append(data)
        n -= len(data)
    return b"".join(parts)

def rename_no_replace(src_fd, src, dst_fd, dst):
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = getattr(libc, "renameat2", None)
    if renameat2 is None:
        raise FileError("atomic_rename_unavailable")
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    if renameat2(src_fd, os.fsencode(src), dst_fd, os.fsencode(dst), 1):
        err = ctypes.get_errno()
        if err == errno.EEXIST:
            raise FileError("destination_exists")
        raise FileError("atomic_rename_failed")

def scope_guard(req, path):
    scope = req.get("scope")
    if scope is None:
        return
    if not isinstance(scope, dict) or scope.get("folder") not in ("input", "output"):
        raise FileError("invalid_scope")
    workspace = path_value(scope.get("workspace"))
    root = os.path.join(workspace, scope["folder"])
    if os.path.commonpath((root, path)) != root:
        raise FileError("outside_selected_folder")
    fd = open_dir(workspace)
    try:
        if [os.fstat(fd).st_dev, os.fstat(fd).st_ino] != scope.get("identity"):
            raise FileError("workspace_changed")
        child = os.open(scope["folder"], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
        try:
            if scope.get("root_identity") is not None and [os.fstat(child).st_dev, os.fstat(child).st_ino] != scope["root_identity"]:
                raise FileError("directory_changed")
        finally:
            os.close(child)
    finally:
        os.close(fd)


def check_expected(req, st):
    if req.get("expected") is not None and list(signature(st)) != req["expected"]:
        raise FileError("selection_changed_refresh_picker")


def input_folder(req, path, create=False):
    workspace = open_dir(path)
    try:
        if [os.fstat(workspace).st_dev, os.fstat(workspace).st_ino] != req.get("identity"):
            raise FileError("workspace_changed")
        if create:
            try:
                os.mkdir("input", 0o700, dir_fd=workspace)
            except FileExistsError:
                pass
        try:
            fd = os.open("input", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=workspace)
        except FileNotFoundError:
            if create:
                raise
            return dict(exists=False, names=[])
        try:
            st = os.fstat(fd)
            if create:
                return dict(path=os.path.join(path, "input"), kind="dir", size=st.st_size,
                            identity=[st.st_dev, st.st_ino], signature=list(signature(st)))
            names = []
            with os.scandir(fd) as entries:
                for entry in entries:
                    names.append(entry.name)
                    if len(names) > MAX_ENTRIES:
                        raise FileError("too_many_entries")
            return dict(exists=True, names=names)
        finally:
            os.close(fd)
    finally:
        os.close(workspace)


def upload(req, source):
    path = path_value(req["path"])
    scope_guard(req, path)
    name = component(req["name"])
    if path == "/":
        raise FileError("root_upload_refused")
    parent = open_dir(path)
    stage_fd, old_cwd, stage = None, None, None
    try:
        if [os.fstat(parent).st_dev, os.fstat(parent).st_ino] != req["identity"]:
            raise FileError("directory_changed")
        try:
            os.stat(name, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise FileError("destination_exists")
        if read_exact(source, len(MAGIC)) != MAGIC:
            raise FileError("invalid_upload")
        length = struct.unpack("!Q", read_exact(source, 8))[0]
        if not 0 < length <= MAX_MANIFEST:
            raise FileError("invalid_manifest")
        raw = read_exact(source, length)
        manifest = json.loads(raw)
        entries = validate_manifest(manifest)
        manifest_hash = hashlib.sha256(raw).hexdigest()
        if manifest_hash != req["manifest_sha256"]:
            raise FileError("manifest_checksum")
        # A hidden sibling stage keeps final files invisible until completion.
        stage_name = ".sprite-upload-" + req["nonce"] + "-" + secrets.token_hex(4)
        os.mkdir(stage_name, 0o700, dir_fd=parent)
        stage = stage_name
        stage_fd = os.open(stage, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        old_cwd = os.open(".", os.O_RDONLY | os.O_DIRECTORY)
        os.fchdir(stage_fd)
        if manifest["kind"] == "dir":
            os.mkdir("payload", 0o700)
        total, count = 0, 0
        for entry in entries:
            target = "payload/" + entry["path"] if manifest["kind"] == "dir" else "payload"
            if entry["kind"] == "dir":
                os.mkdir(target, 0o700)
                continue
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            h = hashlib.sha256()
            with os.fdopen(fd, "wb") as output:
                left = entry["size"]
                while left:
                    chunk = read_exact(source, min(CHUNK, left))
                    output.write(chunk)
                    h.update(chunk)
                    total += len(chunk)
                    left -= len(chunk)
                if read_exact(source, 32) != h.digest():
                    raise FileError("file_checksum")
                output.flush()
                os.fchmod(output.fileno(), 0o700 if entry.get("executable") else 0o600)
                os.fsync(output.fileno())
            count += 1
        if read_exact(source, len(DONE) + 32) != DONE + req["nonce"].encode("ascii"):
            raise FileError("incomplete_upload")
        check = open_dir(path)
        try:
            if [os.fstat(check).st_dev, os.fstat(check).st_ino] != req["identity"]:
                raise FileError("directory_changed")
        finally:
            os.close(check)
        # Linux RENAME_NOREPLACE protects against concurrently created targets,
        # including empty directories; never overlay a live working tree.
        scope_guard(req, path)
        rename_no_replace(stage_fd, "payload", parent, name)
        return dict(path=os.path.join(path, name), files=count, size=total, manifest_sha256=manifest_hash)
    finally:
        if stage_fd is not None:
            os.close(stage_fd)
        if stage is not None:
            # Cleanup by a held directory descriptor, not an untrusted path chain.
            os.fchdir(parent)
            shutil.rmtree(stage, ignore_errors=True)
        if old_cwd is not None:
            os.fchdir(old_cwd)
            os.close(old_cwd)
        os.close(parent)

def download_file(req, output):
    path = path_value(req["path"])
    scope_guard(req, path)
    parent = open_dir(os.path.dirname(path))
    try:
        name = os.path.basename(path)
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        with os.fdopen(fd, "rb") as source:
            before = os.fstat(source.fileno())
            check_expected(req, before)
            if not stat.S_ISREG(before.st_mode):
                raise FileError("not_regular_file")
            h, left = hashlib.sha256(), before.st_size
            while left:
                chunk = source.read(min(CHUNK, left))
                if not chunk:
                    raise FileError("source_changed")
                output.write(chunk)
                h.update(chunk)
                left -= len(chunk)
            if (source.read(1) or signature(os.fstat(source.fileno())) != signature(before)
                or signature(os.stat(name, dir_fd=parent, follow_symlinks=False)) != signature(before)):
                raise FileError("source_changed")
            check = open_dir(os.path.dirname(path))
            try:
                if (os.fstat(check).st_dev, os.fstat(check).st_ino) != (os.fstat(parent).st_dev, os.fstat(parent).st_ino):
                    raise FileError("source_changed")
            finally:
                os.close(check)
            scope_guard(req, path)
            meta = dict(nonce=req["nonce"], size=before.st_size, sha256=h.hexdigest())
            footer = FILE_MAGIC + json.dumps(meta, separators=(",", ":")).encode("ascii")
            output.write(footer.ljust(FOOTER_SIZE - 1, b" ") + b"\n")
            output.flush()
    finally:
        os.close(parent)

def handle(req):
    path = path_value(req.get("path", "~"), req.get("base", "/"))
    action = req["action"]
    if action in ("input-status", "ensure-input"):
        return input_folder(req, path, create=action == "ensure-input")
    scope_guard(req, path)
    if action == "stat":
        result = inspect_path(path)
        if req.get("expected") is not None and result["signature"] != req["expected"]:
            raise FileError("selection_changed_refresh_picker")
        return result
    if action == "list":
        fd = open_dir(path)
        try:
            with os.scandir(fd) as iterator:
                names = []
                for item in iterator:
                    names.append(item.name)
                    if len(names) > MAX_ENTRIES:
                        raise FileError("too_many_entries")
            names.sort()
            offset = req.get("offset", 0)
            if type(offset) is not int or offset < 0:
                raise FileError("invalid_request")
            entries = []
            for name in names[offset:offset+100]:
                try:
                    st = os.stat(name, dir_fd=fd, follow_symlinks=False)
                except FileNotFoundError:
                    continue
                kind = "dir" if stat.S_ISDIR(st.st_mode) else "file" if stat.S_ISREG(st.st_mode) else "link" if stat.S_ISLNK(st.st_mode) else "special"
                entries.append(dict(name=name, kind=kind, size=st.st_size, signature=list(signature(st))))
            return dict(path=path, entries=entries, total=len(names), offset=offset)
        finally:
            os.close(fd)
    if action == "preview":
        parent = open_dir(os.path.dirname(path))
        try:
            fd = os.open(os.path.basename(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            with os.fdopen(fd, "rb") as source:
                st = os.fstat(source.fileno())
                check_expected(req, st)
                if not stat.S_ISREG(st.st_mode):
                    raise FileError("not_regular_file")
                data = source.read(16384)
                return dict(data=base64.b64encode(data).decode("ascii"), truncated=st.st_size > len(data))
        finally:
            os.close(parent)
    if action == "upload":
        return upload(req, sys.stdin.buffer)
    if action == "get":
        download_file(req, sys.stdout.buffer)
        return None
    if action == "shell":
        fd = open_dir(path)
        if [os.fstat(fd).st_dev, os.fstat(fd).st_ino] != req["identity"]:
            os.close(fd)
            raise FileError("directory_changed")
        os.fchdir(fd)
        os.close(fd)
        env = os.environ.copy()
        for key in list(env):
            if any(x in key.upper() for x in ("TOKEN", "SECRET", "PASSWORD", "API_KEY", "PRIVATE_KEY")) or key in ("SPRITE_CODEX_ENV_HEX", "BASH_ENV", "ENV", "PROMPT_COMMAND") or key.startswith("BASH_FUNC_"):
                env.pop(key, None)
        env["PATH"] = os.path.expanduser("~/.local/bin") + ":" + os.path.expanduser("~/.fly/bin") + ":" + env.get("PATH", "/usr/bin:/bin")
        env.update(PS1="sprite-files:\\w\\$ ", HISTFILE="/dev/null", PWD=path)
        # Do not source arbitrary startup commands or load another agent's env.
        os.execvpe("bash", ["bash", "--noprofile", "--norc", "-i"], env)
    raise FileError("invalid_action")

def main():
    req = json.loads(sys.argv[1])
    nonce = req.get("nonce", "")
    if not re.fullmatch(r"[0-9a-f]{32}", nonce):
        raise FileError("invalid_request")
    seconds = req.get("timeout", 3600)
    if type(seconds) is not int or not 1 <= seconds <= 86400:
        raise FileError("invalid_timeout")
    def timed_out(*unused):
        raise FileError("timeout")
    if req.get("action") != "shell":
        signal.signal(signal.SIGALRM, timed_out)
        signal.alarm(seconds)
    try:
        data = handle(req)
        if data is not None:
            print(json.dumps(dict(ok=True, nonce=nonce, data=data), separators=(",", ":")), flush=True)
    except (FileError, OSError, ValueError, KeyError, TypeError) as exc:
        reason = str(exc) if isinstance(exc, FileError) else "permission" if isinstance(exc, PermissionError) else "missing" if isinstance(exc, FileNotFoundError) else "operation_failed"
        # Never echo exception text containing arbitrary paths/data/credentials.
        print(json.dumps(dict(ok=False, nonce=nonce, error=reason), separators=(",", ":")), file=sys.stderr, flush=True)
        return 1
    finally:
        signal.alarm(0)
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        os._exit(1)
'''

remote = types.ModuleType("files_remote_library")
exec(compile(REMOTE_FILES_PY, "files_remote_library", "exec"), remote.__dict__)

class FilesError(Exception):
    pass

class Cancelled(Exception):
    pass

def safe(value):
    return "".join(c if c.isprintable() and not unicodedata.category(c).startswith("C") else "?" for c in str(value))

def ask(prompt):
    try:
        return input(prompt).strip()
    except EOFError:
        raise Cancelled()

def raw_workspace(record):
    """Extract unmodified path bytes, never reuse the display-sanitized label."""
    command = record.get("command", record.get("cmd", ""))
    if isinstance(command, list) and all(isinstance(s, str) for s in command):
        argv = command
    elif isinstance(command, str):
        try:
            argv = shlex.split(command)
        except ValueError:
            return ""
    else:
        argv = []
    managed = False
    for index, arg in enumerate(argv):
        base = os.path.basename(arg)
        if re.fullmatch(r"sprite-(codex|kimi-code)-native-[A-Za-z0-9._-]+", base):
            managed = True
            if ("-runner" in base and len(argv) > index + 6 and argv[index + 1].isdigit()
                and argv[index + 4].startswith("/") and argv[index + 5] in ("new", "resume", "fork")
                and argv[index + 6] in ("codex", "kimi-code")):
                return argv[index + 4]
    # A malformed/ambiguous managed command must not fall back to its entrypoint's
    # home directory. Ask explicitly instead of operating on the wrong workspace.
    if managed:
        return ""
    value = record.get("workdir", record.get("dir", record.get("cwd", "")))
    return value if isinstance(value, str) and value.startswith("/") else ""

def int_setting(name, default, minimum, maximum):
    value = os.environ.get(name, str(default))
    if not re.fullmatch(r"[0-9]{1,6}", value) or not minimum <= int(value) <= maximum:
        raise FilesError(f"{name} must be {minimum}..{maximum}.")
    return int(value)

def error_from_stream(data):
    for line in data.decode("utf-8", "replace").splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict) and item.get("ok") is False and isinstance(item.get("error"), str):
            return safe(item["error"])
    return "transport_or_remote_error"

def receipt(data, nonce):
    try:
        value = json.loads(data)
    except (ValueError, UnicodeError):
        raise FilesError("The remote result was incomplete or invalid; operation status is unknown.") from None
    if not isinstance(value, dict) or value.get("nonce") != nonce or value.get("ok") is not True or not isinstance(value.get("data"), dict):
        raise FilesError("The remote operation did not provide a matching success receipt.")
    return value["data"]

def stop_transfer(proc):
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=2)
        except ProcessLookupError:
            pass
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()

class Deadline:
    """Bound blocked pipe writes as well as waits on Unix local terminals."""
    def __init__(self, seconds):
        self.seconds = seconds
    def __enter__(self):
        self.previous = signal.getsignal(signal.SIGALRM)
        def expired(*unused):
            raise FilesError("Transfer timed out. Inspect the destination before retrying; no automatic retry was attempted.")
        signal.signal(signal.SIGALRM, expired)
        signal.alarm(self.seconds)
    def __exit__(self, *unused):
        signal.alarm(0)
        signal.signal(signal.SIGALRM, self.previous)

class UploadSource:
    """A metadata snapshot with fd-based, bounded-memory content streaming."""
    def __init__(self, path, expected=None, boundary=None):
        supplied = Path(os.path.abspath(os.path.expanduser(path)))
        if boundary is not None:
            boundary = os.path.normpath(boundary)
            if os.path.commonpath((boundary, str(supplied))) != boundary:
                raise FilesError("Upload selection is outside the local launch directory.")
            # Validate the entire parent chain BEFORE any resolve/follow operation.
            checked = remote.open_dir(str(supplied.parent))
            os.close(checked)
        initial = supplied.lstat()
        if not (stat.S_ISREG(initial.st_mode) or stat.S_ISDIR(initial.st_mode)):
            raise FilesError("Choose a regular file or directory, not a symlink or special file.")
        if expected is not None and list(remote.signature(initial)) != expected:
            raise FilesError("Local selection changed; refresh the picker before uploading.")
        self.path = supplied if boundary is not None else supplied.resolve(strict=True)
        self.parent = remote.open_dir(str(self.path.parent))
        self.name = self.path.name
        self.root = None
        self.kind = "dir" if stat.S_ISDIR(initial.st_mode) else "file"
        self.entries, self.signatures = [], {}
        try:
            current = os.stat(self.name, dir_fd=self.parent, follow_symlinks=False)
            if expected is not None and list(remote.signature(current)) != expected:
                raise FilesError("Local selection changed before upload.")
            if self.kind == "dir":
                self.root = os.open(self.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self.parent)
                if expected is not None and list(remote.signature(os.fstat(self.root))) != expected:
                    raise FilesError("Local folder changed before upload.")
                self.scan(self.root, "", self.entries, self.signatures)
            else:
                current = os.stat(self.name, dir_fd=self.parent, follow_symlinks=False)
                self.signatures[""] = remote.signature(current)
                self.entries = [dict(path="payload", kind="file", size=current.st_size, executable=bool(current.st_mode & 0o111))]
            self.manifest = json.dumps(dict(kind=self.kind, entries=self.entries), separators=(",", ":"), ensure_ascii=True).encode("ascii")
            if len(self.manifest) > remote.MAX_MANIFEST:
                raise FilesError("The upload manifest is too large; split the directory into smaller uploads.")
            remote.validate_manifest(json.loads(self.manifest))
        except BaseException:
            self.close()
            raise
    def close(self):
        if self.root is not None:
            os.close(self.root)
            self.root = None
        if self.parent is not None:
            os.close(self.parent)
            self.parent = None
    def scan(self, fd, prefix, entries, signatures):
        signatures[prefix] = remote.signature(os.fstat(fd))
        with os.scandir(fd) as iterator:
            names = []
            for entry in iterator:
                names.append(entry.name)
                if len(names) > remote.MAX_ENTRIES:
                    raise FilesError("Directory has too many entries; split the upload.")
        for name in sorted(names):
            remote.component(name)
            path = prefix + name
            st = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(st.st_mode):
                entries.append(dict(path=path, kind="dir"))
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                try:
                    self.scan(child, path + "/", entries, signatures)
                finally:
                    os.close(child)
            elif stat.S_ISREG(st.st_mode):
                entries.append(dict(path=path, kind="file", size=st.st_size, executable=bool(st.st_mode & 0o111)))
                signatures[path] = remote.signature(st)
            else:
                raise FilesError("Upload contains a symlink or special file; remove it or upload an ordinary-file subset.")
            if len(entries) > remote.MAX_ENTRIES:
                raise FilesError("Too many entries; split the upload.")
    def file_fd(self, path):
        if self.kind == "file":
            return os.open(self.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.parent)
        parent = os.dup(self.root)
        try:
            parts = path.split("/")
            for part in parts[:-1]:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                os.close(parent)
                parent = child
            return os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        finally:
            os.close(parent)
    def stream(self, destination, nonce):
        destination.write(remote.MAGIC)
        destination.write(struct.pack("!Q", len(self.manifest)))
        destination.write(self.manifest)
        total = 0
        last_progress = time.monotonic()
        for entry in self.entries:
            if entry["kind"] != "file":
                continue
            key = "" if self.kind == "file" else entry["path"]
            with os.fdopen(self.file_fd(entry["path"]), "rb") as source:
                before = os.fstat(source.fileno())
                if not stat.S_ISREG(before.st_mode) or remote.signature(before) != self.signatures[key]:
                    raise FilesError("Local source changed during upload; destination was not deliberately published.")
                h, left = hashlib.sha256(), before.st_size
                while left:
                    data = source.read(min(remote.CHUNK, left))
                    if not data:
                        raise FilesError("Local source changed during upload.")
                    destination.write(data)
                    h.update(data)
                    total += len(data)
                    left -= len(data)
                    if time.monotonic() - last_progress >= 5:
                        print(f"       Sent {total / 1048576:,.1f} MiB...", flush=True)
                        last_progress = time.monotonic()
                if source.read(1) or remote.signature(os.fstat(source.fileno())) != self.signatures[key]:
                    raise FilesError("Local source changed during upload.")
                destination.write(h.digest())
        if self.kind == "dir":
            entries, signatures = [], {}
            self.scan(self.root, "", entries, signatures)
            if entries != self.entries or signatures != self.signatures:
                raise FilesError("Local directory changed during upload.")
            root_signature = self.signatures[""]
        else:
            root_signature = self.signatures[""]
        if remote.signature(os.stat(self.name, dir_fd=self.parent, follow_symlinks=False)) != root_signature:
            raise FilesError("Local upload root changed.")
        # Commit marker is withheld until the entire local snapshot revalidates.
        destination.write(remote.DONE + nonce.encode("ascii"))
        destination.flush()
        return total

def verify_raw_download(handle, nonce):
    length = handle.seek(0, os.SEEK_END)
    if length < remote.FOOTER_SIZE:
        raise FilesError("Download is incomplete; no final file was saved.")
    handle.seek(-remote.FOOTER_SIZE, os.SEEK_END)
    footer = handle.read(remote.FOOTER_SIZE)
    if not footer.startswith(remote.FILE_MAGIC) or not footer.endswith(b"\n"):
        raise FilesError("Download completion record is missing; no final file was saved.")
    try:
        data = json.loads(footer[len(remote.FILE_MAGIC):].strip())
    except ValueError:
        raise FilesError("Download completion record is invalid.") from None
    if (not isinstance(data, dict) or data.get("nonce") != nonce or type(data.get("size")) is not int
        or data["size"] != length - remote.FOOTER_SIZE or not isinstance(data.get("sha256"), str)
        or not re.fullmatch(r"[0-9a-f]{64}", data["sha256"])):
        raise FilesError("Download completion record does not match this request.")
    handle.seek(0)
    h, left = hashlib.sha256(), data["size"]
    while left:
        chunk = handle.read(min(remote.CHUNK, left))
        if not chunk:
            raise FilesError("Truncated download.")
        h.update(chunk)
        left -= len(chunk)
    if h.hexdigest() != data["sha256"]:
        raise FilesError("Download SHA-256 mismatch; no final file was saved.")
    handle.truncate(data["size"])
    handle.flush()
    os.fsync(handle.fileno())
    return data

class Browser:
    def __init__(self, picker_module, output_module, context, local_dir):
        self.a = types.SimpleNamespace(**picker_module)
        self.o = types.SimpleNamespace(**output_module)
        self.picker = self.a.Picker(context, selection_only=True)
        self.local_dir = Path(local_dir).resolve()
        self.timeout = int_setting("SPRITE_FILE_TIMEOUT", 3600, 1, 86400)
        self.sprite, self.cwd = "", ""
    def args(self, req, tty=False):
        result = [self.picker.cli, "exec", *self.picker.org, "-s", self.sprite]
        if tty:
            result += ["--tty", "--dir", req["path"]]
        return [*result, "--no-port-forward", "--", "python3", "-c", REMOTE_FILES_PY, json.dumps(req, separators=(",", ":"))]
    def request(self, action, path=None, **extra):
        return dict(action=action, path=path or self.cwd or "~", nonce=secrets.token_hex(16), timeout=self.timeout, **extra)
    def control(self, action, path=None, **extra):
        req = self.request(action, path, **extra)
        req["timeout"] = self.picker.timeout
        try:
            result = subprocess.run(self.args(req), cwd=self.picker.context, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=self.picker.timeout)
        except subprocess.TimeoutExpired:
            raise FilesError("Remote file request timed out; no automatic retry was attempted.") from None
        if result.returncode:
            raise FilesError("Remote file operation failed: " + error_from_stream(result.stderr))
        return receipt(result.stdout, req["nonce"])
    def pin(self, sprite):
        self.sprite = sprite
        self.picker.capture(["use", *self.picker.org, sprite])
    def select_workspace(self, requested_id="", override=""):
        if override:
            if requested_id:
                raise FilesError("Use either --session-id or --workdir, not both.")
            return self.set_cwd(override)
        while True:
            try:
                raw = self.picker.api("/exec", self.sprite)
                rows, _ = self.a.parse_sessions(raw)
                records, _ = self.a.collection(raw, ("sessions", "items", "data"))
            except self.a.AttachError as exc:
                if requested_id:
                    raise
                print("Warning: " + str(exc))
                answer = ask("  R = retry session discovery, M = enter workspace, Q = quit [Q]: ").lower()
                if answer == "r":
                    continue
                if answer == "m":
                    return self.set_cwd(ask("  Existing absolute Sprite workspace (or ~/...): "))
                raise Cancelled()
            by_id = {str(r.get("id", r.get("session_id"))): r for r in records}
            print(f"\n=== choose workspace on {self.sprite} (does not attach to the agent)")
            for index, row in enumerate(rows, 1):
                row["raw_workdir"] = raw_workspace(by_id[row["id"]])
                print(f"    {index}) ID={row['id']}  {row['label']}  created={row['created']}")
                print("       Recorded workspace: " + safe(row["raw_workdir"] or "unknown; enter it manually"))
            if requested_id:
                chosen = next((r for r in rows if r["id"] == requested_id), None)
                if chosen is None:
                    raise FilesError("Requested session is not confirmed live; no workspace was guessed.")
            else:
                if not rows:
                    print("       No live native terminal was returned; an existing workspace can still be selected manually.")
                answer = ask("  Workspace session number; M = manual path, R = refresh, Q = quit: ")
                if answer.lower() == "q" or not answer:
                    raise Cancelled()
                if answer.lower() == "r":
                    continue
                if answer.lower() == "m":
                    return self.set_cwd(ask("  Existing absolute Sprite workspace (or ~/...): "))
                if not re.fullmatch(r"[0-9]{1,6}", answer) or not 1 <= int(answer) <= len(rows):
                    print("Invalid selection.")
                    continue
                chosen = rows[int(answer)-1]
            if not self.picker.live_same_session(self.sprite, chosen):
                raise FilesError("Selected session ended before its workspace could be confirmed. Refresh or select a manual path.")
            if not chosen["raw_workdir"]:
                if requested_id:
                    raise FilesError("Session workspace cannot be determined. Rerun with --workdir and its exact path.")
                return self.set_cwd(ask("  Workspace not recorded; enter the exact absolute directory: "))
            print("       Using the recorded workspace, not a live child-process cwd probe.")
            return self.set_cwd(chosen["raw_workdir"])
    def set_cwd(self, path):
        if not path:
            raise FilesError("No directory entered.")
        info = self.control("stat", path, base=self.cwd or "/")
        if info.get("kind") != "dir":
            raise FilesError("Selected path must be an existing ordinary directory, not a symlink.")
        # Validate every path component now; subsequent operations reopen safely.
        self.control("list", info["path"], offset=0)
        self.cwd = info["path"]
        print("       Remote directory: " + safe(self.cwd))
        return self.cwd
    def browse(self):
        offset = 0
        while True:
            result = self.control("list", self.cwd, offset=offset)
            entries = result["entries"]
            print("\n=== " + safe(self.cwd))
            for index, entry in enumerate(entries, 1):
                print(f"    {index:3}) {entry['kind']:7} {entry['size']:>12,}  {safe(entry['name'])}")
            print(f"       Page {offset // 100 + 1}; {result['total']} entries. Symlinks are listed but not followed.")
            answer = ask("  Number = open; N/P = page, U = parent, Q = file menu: ")
            if answer.lower() == "q" or not answer:
                return
            if answer.lower() == "n":
                if offset + 100 < result["total"]:
                    offset += 100
                continue
            if answer.lower() == "p":
                offset = max(0, offset - 100)
                continue
            if answer.lower() == "u":
                self.set_cwd(os.path.dirname(self.cwd))
                offset = 0
                continue
            if not re.fullmatch(r"[0-9]{1,3}", answer) or not 1 <= int(answer) <= len(entries):
                print("Invalid selection.")
                continue
            entry = entries[int(answer)-1]
            path = os.path.join(self.cwd, entry["name"])
            if entry["kind"] == "dir":
                self.set_cwd(path)
                offset = 0
            elif entry["kind"] == "file":
                choice = ask("  P = preview text (first 16 KiB), D = download, Enter = back: ").lower()
                if choice == "p":
                    preview = self.control("preview", path)
                    data = base64.b64decode(preview["data"], validate=True)
                    if b"\0" in data:
                        print("       Binary-looking file; preview withheld. Download it instead.")
                    else:
                        text = data.decode("utf-8", "replace")
                        print("\n" + "\n".join(safe(line) for line in text.splitlines()))
                        if preview["truncated"]:
                            print("       [preview truncated]")
                elif choice == "d":
                    self.download(path)
            else:
                print("       Symlinks and special files cannot be opened by this file menu.")
    def shell(self):
        info = self.control("stat", self.cwd)
        if info.get("kind") != "dir":
            raise FilesError("Directory is no longer available.")
        req = self.request("shell", self.cwd, identity=info["identity"])
        print("\n       Opening a SEPARATE Bash terminal in " + safe(self.cwd))
        print("       Codex is not attached, restarted, paused or signalled by this operation.")
        print("       This shell does not inherit the running agent's GitHub/Fly/model tokens.")
        print("       Type exit to return to this LOCAL file menu for uploads/downloads.")
        print("       Shell cd does not change the selected workspace or the input/output picker roots.", flush=True)
        state = termios.tcgetattr(sys.stdin.fileno())
        try:
            rc = subprocess.call(self.args(req, tty=True), cwd=self.picker.context)
        finally:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, state)
        print(f"\n       Shell viewer returned (exit {rc}); existing Codex session was not changed.")
        print("       Ctrl+\\ detaches rather than exits a shell; a detached shell may remain on the Sprite.")
    def upload(self):
        path = ask("  LOCAL file or directory to upload (no shell escaping/globs; blank cancels): ")
        if not path:
            return
        source = UploadSource(path if os.path.isabs(os.path.expanduser(path)) else str(self.local_dir / path))
        proc = None
        try:
            name = ask(f"  New name under {safe(self.cwd)} [{safe(source.name)}]: ") or source.name
            remote.component(name)
            info = self.control("stat", self.cwd)
            if info.get("kind") != "dir":
                raise FilesError("Upload destination is not a directory.")
            print(f"       LOCAL {safe(source.path)} -> SPRITE {safe(os.path.join(self.cwd, name))}")
            print("       No overwrites or directory merging. Hidden regular files are included; exclude secrets yourself.")
            if ask("  Upload now? [y/N]: ").lower() not in ("y", "yes"):
                return
            req = self.request("upload", self.cwd, name=name, identity=info["identity"], manifest_sha256=hashlib.sha256(source.manifest).hexdigest())
            with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors, Deadline(self.timeout):
                proc = subprocess.Popen(self.args(req), cwd=self.picker.context, stdin=subprocess.PIPE,
                                        stdout=output, stderr=errors, start_new_session=True)
                try:
                    total = source.stream(proc.stdin, req["nonce"])
                    proc.stdin.close()
                    proc.wait()
                except BrokenPipeError:
                    proc.wait(timeout=5)
                    errors.seek(0)
                    raise FilesError("Upload rejected: " + error_from_stream(errors.read())) from None
                output.seek(0)
                errors.seek(0)
                if proc.returncode:
                    raise FilesError("Upload not confirmed: " + error_from_stream(errors.read()) + ". Inspect the destination before retrying.")
                data = receipt(output.read(), req["nonce"])
                count = sum(e["kind"] == "file" for e in source.entries)
                if data.get("size") != total or data.get("files") != count or data.get("manifest_sha256") != req["manifest_sha256"]:
                    raise FilesError("Upload receipt mismatch; inspect the destination before retrying.")
                print(f"  Uploaded: {safe(data['path'])} ({count} files; {total:,} bytes)")
                print("       Tell Codex this exact path and ask it to read the completed upload.")
        finally:
            stop_transfer(proc)
            source.close()
    def download(self, path=""):
        path = path or ask("  REMOTE file/folder (relative to this menu's directory; blank cancels): ")
        if not path:
            return
        info = self.control("stat", path, base=self.cwd)
        resolved = info["path"]
        if info["kind"] == "dir":
            print("       Folder downloads use the checked ZIP exporter; the archive's top-level directory is output/.")
            print("       Finish writes first. Hidden regular files are included; symlinks/special files are skipped.")
            if ask("  Download this directory as a ZIP to the LOCAL launch directory? [y/N]: ").lower() not in ("y", "yes"):
                return
            org = self.picker.org[1] if self.picker.org else ""
            return self.o.download(self.sprite, resolved, str(self.local_dir), org,
                                   os.path.join(self.picker.context, ".sprite"))
        if info["kind"] != "file":
            raise FilesError("Download requires a regular file or ordinary directory, not a symlink/special file.")
        name = ask(f"  New LOCAL filename [{safe(os.path.basename(resolved))}]: ") or os.path.basename(resolved)
        remote.component(name)
        target = self.local_dir / name
        if os.path.lexists(target):
            raise FilesError("Local filename already exists; choose a new name. Nothing was overwritten.")
        print(f"       SPRITE {safe(resolved)} -> LOCAL {safe(target)}")
        if ask("  Download now? [y/N]: ").lower() not in ("y", "yes"):
            return
        self.download_raw(resolved, target)
    def download_raw(self, path, target, scope=None, expected=None):
        req = self.request("get", path, scope=scope, expected=expected)
        proc, partial = None, None
        try:
            fd, partial = tempfile.mkstemp(prefix=".sprite-file-", suffix=".partial", dir=self.local_dir)
            with os.fdopen(fd, "w+b") as output, tempfile.TemporaryFile() as errors, Deadline(self.timeout):
                proc = subprocess.Popen(self.args(req), cwd=self.picker.context, stdin=subprocess.DEVNULL,
                                        stdout=output, stderr=errors, start_new_session=True)
                progress = time.monotonic() + 5
                while proc.poll() is None:
                    if time.monotonic() >= progress:
                        print(f"       Received {os.fstat(output.fileno()).st_size / 1048576:,.1f} MiB...", flush=True)
                        progress = time.monotonic() + 5
                    time.sleep(0.1)
                if proc.returncode:
                    errors.seek(0)
                    raise FilesError("File download failed: " + error_from_stream(errors.read()))
                metadata = verify_raw_download(output, req["nonce"])
                os.link(partial, target)  # atomic no-clobber final publication
                os.unlink(partial)
                partial = None
                print(f"  Saved: {safe(target)} ({metadata['size']:,} bytes)")
                print("       SHA-256: " + metadata["sha256"])
        finally:
            stop_transfer(proc)
            if partial:
                try:
                    os.unlink(partial)
                except FileNotFoundError:
                    pass
    def menu(self):
        while True:
            print(f"\n=== shell / files on {self.sprite}")
            print("       REMOTE: " + safe(self.cwd))
            print("       LOCAL uploads/downloads: " + safe(self.local_dir))
            print("    1) Browse remote directory / preview files")
            print("    2) Open separate Bash shell here")
            print("    3) Upload a local file or directory (new destination only)")
            print("    4) Download a remote file or directory (ZIP for directory)")
            print("    5) Change remote directory")
            print("    6) Select another session's workspace")
            print("    7) Choose another Sprite")
            print("    0) Quit file access (leave Codex running)")
            answer = ask("  Select [0-7]: ")
            try:
                if answer in ("0", "q", "quit", ""):
                    return 0
                if answer == "1":
                    self.browse()
                elif answer == "2":
                    self.shell()
                elif answer == "3":
                    self.upload()
                elif answer == "4":
                    self.download()
                elif answer == "5":
                    path = ask("  Existing remote directory (absolute, ~/..., or relative; blank cancels): ")
                    if path:
                        self.set_cwd(path)
                elif answer == "6":
                    self.select_workspace()
                elif answer == "7":
                    # Keep old target/path coherent until the new selection works.
                    old_sprite, old_cwd = self.sprite, self.cwd
                    try:
                        self.pin(self.picker.choose_sprite())
                        self.cwd = ""
                        self.select_workspace()
                    except BaseException:
                        self.pin(old_sprite)
                        self.cwd = old_cwd
                        raise
                else:
                    print("Invalid selection.")
            except (FilesError, self.a.AttachError, self.o.DownloadError, remote.FileError) as exc:
                print("  Warning: " + safe(exc), file=sys.stderr)
            except OSError as exc:
                print("  Warning: filesystem/transport operation failed (" + type(exc).__name__ + "). Check paths and permissions; no bootstrap fallback.", file=sys.stderr)
            except (Cancelled, self.a.Cancelled):
                print("       Selection cancelled; returning to file menu.")
            except KeyboardInterrupt:
                print("\n       File operation interrupted. Inspect destination before retrying; Codex was not signalled by this menu.")

# v53: directory-scoped, no-path-entry transfer picker.
PAGE_SIZE = 15


def human_size(size):
    if size is None:
        return "folder"
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{value:,.0f} {unit}" if unit == "B" else f"{value:,.1f} {unit}"
        value /= 1024


def relative_path(root, relative):
    """Only picker-produced, relative paths; no links or '..' navigation escapes."""
    if not isinstance(relative, str) or relative.startswith("/"):
        raise FilesError("Invalid file selection; select it again from the list.")
    if relative:
        for part in relative.split("/"):
            remote.component(part)
    root = os.path.normpath(str(root))
    result = os.path.normpath(os.path.join(root, relative))
    if os.path.commonpath((root, result)) != root:
        raise FilesError("The selection is outside this picker's folder.")
    return result


def numbered_selection(value, length):
    """Parse e.g. '1 3,5-7'; never interpret input as Python or shell code."""
    if not re.fullmatch(r"[0-9, \t-]{1,1024}", value):
        raise FilesError("Use item numbers, for example 1 3-5.")
    result = set()
    for token in re.split(r"[,\s]+", value.strip()):
        if not token:
            continue
        match = re.fullmatch(r"([0-9]{1,6})(?:-([0-9]{1,6}))?", token)
        if not match:
            raise FilesError("Invalid number range; use 1 3-5.")
        first, last = int(match[1]), int(match[2] or match[1])
        if not 1 <= first <= last <= length:
            raise FilesError("An item number is outside the displayed page.")
        result.update(range(first-1, last))
    if not result:
        raise FilesError("Select at least one displayed item.")
    return sorted(result)


def alternative_name(name, number):
    remote.component(name)
    stem, suffix = os.path.splitext(name)
    if not stem:
        stem, suffix = name, ""
    extra = f" ({number})"
    # Retain extension where possible without exceeding a filesystem component.
    while len((stem + extra + suffix).encode("utf-8")) > 255 and stem:
        stem = stem[:-1]
    if not stem:
        raise FilesError("Filename is too long to generate a safe alternative.")
    return remote.component(stem + extra + suffix)


class FilePicker:
    """Multi-selection with folder navigation, arrows/Space or numbered fallback.

    The loader operates relative to a fixed root. Display text is never used as
    a path, and selected parent directories supersede their selected children.
    """
    def __init__(self, title, root_label, loader, verb, preview=None):
        self.title, self.root_label = title, str(root_label)
        self.loader, self.verb, self.preview = loader, verb, preview
        self.current, self.query, self.message = "", "", ""
        self.hidden = False
        self.entries, self.selected = [], {}
        self.page, self.cursor = 0, 0
        self.reload()

    def reload(self):
        rows = self.loader(self.current)
        if not isinstance(rows, list) or len(rows) > remote.MAX_ENTRIES:
            raise FilesError("Invalid or oversized file listing.")
        entries, seen = [], set()
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("name"), str):
                raise FilesError("Invalid file entry.")
            name = row["name"]
            if name in seen:
                raise FilesError("Duplicate file entry; refresh the listing.")
            seen.add(name)
            valid = True
            try:
                remote.component(name)
            except remote.FileError:
                valid = False
            entry = dict(row, rel=(self.current + "/" if self.current else "") + name)
            entry["selectable"] = valid and row.get("kind") in ("file", "dir")
            entries.append(entry)
        self.entries = sorted(entries, key=lambda e: (e.get("kind") != "dir", e["name"].casefold(), e["name"]))
        self.page, self.cursor = 0, 0

    def visible(self):
        return [e for e in self.entries if (self.hidden or not e["name"].startswith("."))
                and self.query.casefold() in e["name"].casefold()]

    def covered(self, entry):
        rel = entry["rel"]
        return any(e["kind"] == "dir" and rel.startswith(key + "/") for key, e in self.selected.items())

    def toggle(self, entry):
        if not entry["selectable"]:
            self.message = "Links, special files and unsupported names cannot be selected."
            return
        key = entry["rel"]
        if key in self.selected:
            del self.selected[key]
        elif self.covered(entry):
            self.message = "Already included by a selected parent folder."
        else:
            if entry["kind"] == "dir":
                self.selected = {k: e for k, e in self.selected.items() if not k.startswith(key + "/")}
            self.selected[key] = dict(entry)
            self.message = f"{len(self.selected)} item(s) selected."

    def select_all(self):
        for entry in self.visible():
            if entry["selectable"] and entry["rel"] not in self.selected and not self.covered(entry):
                self.toggle(entry)

    def enter_folder(self, entry):
        if entry["kind"] != "dir" or not entry["selectable"]:
            self.message = "Select an ordinary folder to open."
            return
        old = self.current
        self.current = entry["rel"]
        try:
            self.reload()
            self.query = ""
        except BaseException:
            self.current = old
            raise

    def parent(self):
        if self.current:
            self.current = self.current.rpartition("/")[0]
            self.query = ""
            self.reload()
        else:
            self.message = "Already at this picker's root; navigation outside it is disabled."

    def result(self):
        return [self.selected[key] for key in sorted(self.selected)]

    def preview_text(self, entry):
        if entry["kind"] != "file" or not entry["selectable"] or self.preview is None:
            return "Text preview is available only for regular files."
        return self.preview(entry)

    def run(self):
        mode = os.environ.get("SPRITE_FILE_UI", "auto")
        if mode not in ("auto", "arrows", "menu"):
            raise FilesError("SPRITE_FILE_UI must be auto, arrows, or menu.")
        term = os.environ.get("TERM", "")
        if mode != "menu" and term not in ("", "dumb") and sys.stdin.isatty() and sys.stdout.isatty():
            try:
                import curses
            except ImportError:
                if mode == "arrows":
                    print("       Arrow UI is unavailable; using the numbered picker.")
            else:
                try:
                    return curses.wrapper(self.screen, curses)
                except curses.error:
                    print("       This terminal cannot display the arrow UI; using the numbered picker.")
        return self.numbered()

    def numbered(self):
        while True:
            rows = self.visible()
            self.page = min(self.page, max(0, (len(rows)-1)//PAGE_SIZE))
            page = rows[self.page*PAGE_SIZE:(self.page+1)*PAGE_SIZE]
            print(f"\n=== {self.title}")
            print("       Folder: " + safe(os.path.join(self.root_label, self.current)))
            print(f"       {len(self.selected)} selected | page {self.page+1}/{max(1, (len(rows)+PAGE_SIZE-1)//PAGE_SIZE)} | hidden {'shown' if self.hidden else 'hidden'}")
            if self.query:
                print("       Filter: " + safe(self.query))
            for index, entry in enumerate(page, 1):
                mark = "x" if entry["rel"] in self.selected else "+" if self.covered(entry) else " " if entry["selectable"] else "-"
                label = entry["name"] + ("/" if entry["kind"] == "dir" else "")
                size = human_size(None if entry["kind"] == "dir" else entry.get("size", 0))
                print(f"    {index:2}) [{mark}] {size:>12}  {safe(label)}" + (" [not selectable]" if not entry["selectable"] else ""))
            if not page:
                print("       No visible files here. Refresh after Codex finishes writing, or toggle hidden files.")
            if self.message:
                print("       " + safe(self.message))
                self.message = ""
            print(f"       Numbers toggle selection (1 3-5). Enter or T = {self.verb} selected.")
            print("       O number = open folder | V number = preview | U = parent | N/P = pages")
            print("       A = select all in view | C = clear | F = filter | H = hidden | R = refresh | Q = back")
            answer = ask("  File picker: ")
            command = answer.lower()
            try:
                if command in ("q", "quit"):
                    return []
                if command in ("", "t"):
                    if self.selected:
                        return self.result()
                    self.message = "Select file numbers first, then press Enter. Q returns without a transfer."
                elif command == "a":
                    self.select_all()
                elif command == "c":
                    self.selected.clear()
                elif command == "h":
                    self.hidden = not self.hidden
                    self.page = 0
                elif command == "f":
                    self.query = ask("  Filename filter (blank clears): ")
                    self.page = 0
                elif command == "r":
                    self.reload()
                elif command == "u":
                    self.parent()
                elif command == "n":
                    self.page = min(self.page+1, max(0, (len(rows)-1)//PAGE_SIZE))
                elif command == "p":
                    self.page = max(0, self.page-1)
                elif re.fullmatch(r"[ov]\s+[0-9]{1,6}", command):
                    index = int(command.split()[1])-1
                    if not 0 <= index < len(page):
                        raise FilesError("Choose an item number on this page.")
                    if command[0] == "o":
                        self.enter_folder(page[index])
                    else:
                        print("\n" + self.preview_text(page[index]))
                else:
                    for index in numbered_selection(answer, len(page)):
                        self.toggle(page[index])
            except (FilesError, remote.FileError, OSError) as exc:
                self.message = safe(exc) if isinstance(exc, (FilesError, remote.FileError)) else "File operation failed; refresh and check permissions."

    def screen(self, screen, curses):
        screen.keypad(True)
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        while True:
            height, width = screen.getmaxyx()
            if height < 12 or width < 48:
                raise curses.error("terminal too small")
            rows = self.visible()
            self.cursor = max(0, min(self.cursor, max(0, len(rows)-1)))
            capacity = height - 9
            start = (self.cursor//capacity)*capacity
            screen.erase()
            def put(y, text, attr=0):
                if 0 <= y < height-1:
                    screen.addnstr(y, 0, safe(text), max(1, width-1), attr)
            put(0, self.title, curses.A_BOLD)
            put(1, "Folder: " + os.path.join(self.root_label, self.current))
            put(2, f"{len(self.selected)} selected | {len(rows)} visible | hidden {'shown' if self.hidden else 'hidden'} | filter: {self.query}")
            for offset, entry in enumerate(rows[start:start+capacity]):
                mark = "x" if entry["rel"] in self.selected else "+" if self.covered(entry) else " " if entry["selectable"] else "-"
                label = entry["name"] + ("/" if entry["kind"] == "dir" else "")
                size = human_size(None if entry["kind"] == "dir" else entry.get("size", 0))
                put(4+offset, f"[{mark}] {size:>12}  {label}", curses.A_REVERSE if start+offset == self.cursor else 0)
            if not rows:
                put(4, "No visible files. R refreshes; H toggles hidden files.")
            put(height-5, self.message)
            put(height-4, f"Up/Down move  Space select  Enter {self.verb}  Right open  Left back")
            put(height-3, "A all  C clear  / filter  H hidden  R refresh  V preview  Q cancel")
            screen.refresh()
            key = screen.get_wch()
            self.message = ""
            try:
                if key in ("q", "Q", "\x1b"):
                    return []
                if key == "\x03":
                    raise KeyboardInterrupt()
                if key in (curses.KEY_UP, "k"):
                    self.cursor = max(0, self.cursor-1)
                elif key in (curses.KEY_DOWN, "j"):
                    self.cursor = min(max(0, len(rows)-1), self.cursor+1)
                elif key == curses.KEY_NPAGE:
                    self.cursor = min(max(0, len(rows)-1), self.cursor+capacity)
                elif key == curses.KEY_PPAGE:
                    self.cursor = max(0, self.cursor-capacity)
                elif key == " " and rows:
                    self.toggle(rows[self.cursor])
                elif key in ("\n", "\r", curses.KEY_ENTER):
                    if self.selected:
                        return self.result()
                    if rows:
                        if rows[self.cursor]["kind"] == "dir":
                            self.enter_folder(rows[self.cursor])
                        else:
                            self.toggle(rows[self.cursor])
                            if self.selected:
                                return self.result()
                elif key == curses.KEY_RIGHT and rows:
                    self.enter_folder(rows[self.cursor])
                elif key in (curses.KEY_LEFT, curses.KEY_BACKSPACE, "\x7f", "u", "U"):
                    self.parent()
                elif key in ("a", "A"):
                    self.select_all()
                elif key in ("c", "C"):
                    self.selected.clear()
                elif key in ("h", "H"):
                    self.hidden = not self.hidden
                    self.cursor = 0
                elif key in ("r", "R"):
                    self.reload()
                elif key in ("f", "F", "/"):
                    # Small in-screen line editor: no shell command parsing.
                    value = ""
                    while True:
                        screen.move(height-5, 0)
                        screen.clrtoeol()
                        put(height-5, "Filter (Enter applies, Esc cancels): " + value)
                        screen.refresh()
                        char = screen.get_wch()
                        if char in ("\n", "\r", curses.KEY_ENTER):
                            self.query, self.cursor = value, 0
                            break
                        if char == "\x1b":
                            break
                        if char in (curses.KEY_BACKSPACE, "\x7f", "\b"):
                            value = value[:-1]
                        elif isinstance(char, str) and char.isprintable() and len(value) < 128:
                            value += char
                elif key in ("v", "V") and rows:
                    lines = self.preview_text(rows[self.cursor]).splitlines()
                    offset = 0
                    while True:
                        screen.erase()
                        put(0, "Text preview — Up/Down scroll, Q/Enter return", curses.A_BOLD)
                        for index, line in enumerate(lines[offset:offset+height-3]):
                            put(index+2, line)
                        screen.refresh()
                        char = screen.get_wch()
                        if char in ("q", "Q", "\x1b", "\n", "\r"):
                            break
                        if char in (curses.KEY_DOWN, curses.KEY_NPAGE):
                            offset = min(max(0, len(lines)-1), offset+(height-3 if char == curses.KEY_NPAGE else 1))
                        elif char in (curses.KEY_UP, curses.KEY_PPAGE):
                            offset = max(0, offset-(height-3 if char == curses.KEY_PPAGE else 1))
            except (FilesError, remote.FileError, OSError) as exc:
                self.message = safe(exc) if isinstance(exc, (FilesError, remote.FileError)) else "Cannot read this entry; refresh and check permissions."


class SimpleBrowser(Browser):
    """Only input/output transfers are exposed; the optional shell stays separate."""
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        mode = os.environ.get("SPRITE_FILE_UI", "auto")
        if mode not in ("auto", "arrows", "menu"):
            raise FilesError("SPRITE_FILE_UI must be auto, arrows, or menu.")
        st = self.local_dir.stat()
        self.local_identity = [st.st_dev, st.st_ino]
        self.workspace_identity = None

    def set_cwd(self, path):
        result = super().set_cwd(path)
        info = self.control("stat", result)
        self.workspace_identity = info["identity"]
        return result

    def scope(self, folder, root_info=None):
        if folder not in ("input", "output") or not self.workspace_identity:
            raise FilesError("Select the Codex workspace first.")
        value = dict(workspace=self.cwd, identity=self.workspace_identity, folder=folder)
        if root_info:
            value["root_identity"] = root_info["identity"]
        return value

    def folder_info(self, folder, create=False):
        if create:
            return self.control("ensure-input", self.cwd, identity=self.workspace_identity)
        path = os.path.join(self.cwd, folder)
        info = self.control("stat", path, scope=self.scope(folder))
        if info["kind"] != "dir":
            raise FilesError(f"{folder}/ must be an ordinary directory, not a symlink or file.")
        return info

    def remote_listing(self, root, relative, scope):
        path = relative_path(root, relative)
        rows, offset = [], 0
        while True:
            data = self.control("list", path, offset=offset, scope=scope)
            rows.extend(data["entries"])
            if len(rows) > remote.MAX_ENTRIES:
                raise FilesError("Too many entries; organize the folder into subfolders.")
            offset += 100
            if offset >= data["total"]:
                return rows

    def local_listing(self, relative):
        current = self.local_dir.stat()
        if [current.st_dev, current.st_ino] != self.local_identity:
            raise FilesError("The local launch directory changed; restart file mode.")
        fd = remote.open_dir(relative_path(self.local_dir, relative))
        try:
            rows = []
            with os.scandir(fd) as entries:
                for entry in entries:
                    try:
                        st = os.stat(entry.name, dir_fd=fd, follow_symlinks=False)
                    except FileNotFoundError:
                        continue
                    kind = "dir" if stat.S_ISDIR(st.st_mode) else "file" if stat.S_ISREG(st.st_mode) else "link" if stat.S_ISLNK(st.st_mode) else "special"
                    rows.append(dict(name=entry.name, kind=kind, size=st.st_size, signature=list(remote.signature(st))))
                    if len(rows) > remote.MAX_ENTRIES:
                        raise FilesError("Too many local entries; choose a smaller launch directory.")
            return rows
        finally:
            os.close(fd)

    def preview_remote(self, root, scope, entry):
        result = self.control("preview", relative_path(root, entry["rel"]), scope=scope, expected=entry.get("signature"))
        data = base64.b64decode(result["data"], validate=True)
        if b"\0" in data:
            return "Binary-looking file; download it to open locally."
        text = "\n".join(safe(line) for line in data.decode("utf-8", "replace").splitlines())
        return text + ("\n[preview limited to 16 KiB]" if result["truncated"] else "")

    def preview_local(self, entry):
        path = relative_path(self.local_dir, entry["rel"])
        parent = remote.open_dir(os.path.dirname(path))
        try:
            fd = os.open(os.path.basename(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            with os.fdopen(fd, "rb") as source:
                st = os.fstat(source.fileno())
                if not stat.S_ISREG(st.st_mode) or list(remote.signature(st)) != entry["signature"]:
                    raise FilesError("File changed since listing; refresh before previewing.")
                data = source.read(16384)
        finally:
            os.close(parent)
        if b"\0" in data:
            return "Binary-looking file; it can still be uploaded."
        return "\n".join(safe(line) for line in data.decode("utf-8", "replace").splitlines()) + ("\n[preview limited to 16 KiB]" if st.st_size > len(data) else "")

    def choose_outputs(self):
        info = self.folder_info("output")
        root, scope = info["path"], self.scope("output", info)
        picker = FilePicker("Download from Codex output/", root,
                            lambda rel: self.remote_listing(root, rel, scope), "download",
                            lambda entry: self.preview_remote(root, scope, entry))
        chosen = picker.run()
        if chosen:
            self.download_selected(chosen, root, scope)

    def browse(self):
        return self.choose_outputs()

    def download(self, path=""):
        if path:
            raise FilesError("Use the output/ picker; arbitrary download paths are not accepted in simplified file mode.")
        return self.choose_outputs()

    def download_all(self):
        info = self.folder_info("output")
        self.download_selected([dict(rel="", name="output", kind="dir", signature=info["signature"])],
                               info["path"], self.scope("output", info))

    def next_local_name(self, name, reserved):
        remote.component(name)
        candidate, number = name, 2
        while candidate in reserved or os.path.lexists(self.local_dir / candidate):
            candidate = alternative_name(name, number)
            number += 1
            if number > 10000:
                raise FilesError("Too many filename conflicts; move old local copies aside.")
        reserved.add(candidate)
        return candidate

    def download_selected(self, chosen, root, scope):
        plans, reserved = [], set()
        for entry in chosen:
            path = relative_path(root, entry["rel"])
            info = self.control("stat", path, scope=scope, expected=entry.get("signature"))
            if info["kind"] != entry["kind"]:
                raise FilesError("A selected item changed; reopen the picker.")
            name = self.next_local_name(entry["name"], reserved) if entry["kind"] == "file" else "unique output ZIP"
            plans.append((entry, path, name))
        print(f"\n=== Download {len(plans)} selected item(s)")
        print("       LOCAL destination: " + safe(self.local_dir))
        for entry, path, name in plans:
            print("       output/" + safe(entry["rel"] or ".") + " -> " + safe(name))
        print("       Files keep their format; each selected folder becomes a ZIP. Existing local names get a new suffix.")
        print("       Finish Codex writes first. Folder ZIPs include hidden regular files, but do not follow links.")
        if ask("  Download selected items now? [y/N]: ").lower() not in ("y", "yes"):
            return
        completed = 0
        try:
            for entry, path, name in plans:
                if entry["kind"] == "dir":
                    org = self.picker.org[1] if self.picker.org else ""
                    self.o.download(self.sprite, path, str(self.local_dir), org,
                                    os.path.join(self.picker.context, ".sprite"),
                                    checks=dict(scope=scope, expected=entry.get("signature")))
                else:
                    self.download_raw(path, self.local_dir / name, scope=scope, expected=entry.get("signature"))
                completed += 1
        finally:
            print(f"       Download batch: {completed}/{len(plans)} item(s) completed. Originals remain on the Sprite.")

    def upload(self):
        picker = FilePicker("Upload local files to Codex input/", self.local_dir, self.local_listing,
                            "upload", self.preview_local)
        chosen = picker.run()
        if not chosen:
            return
        # Resolve only folder existence now; create input/ AFTER confirmation.
        state = self.control("input-status", self.cwd, identity=self.workspace_identity)
        names = set(state["names"])
        plans = []
        for entry in chosen:
            name, number = entry["name"], 2
            while name in names:
                name = alternative_name(entry["name"], number)
                number += 1
                if number > 10000:
                    raise FilesError("Too many remote filename conflicts.")
            names.add(name)
            plans.append((entry, name))
        print(f"\n=== Upload {len(plans)} selected item(s)")
        print("       SPRITE destination: " + safe(os.path.join(self.cwd, "input")))
        for entry, name in plans:
            print("       " + safe(entry["rel"]) + " -> input/" + safe(name))
        print("       Each selection keeps its basename; folders keep their contents. Conflicts get a new suffix, never an overwrite.")
        print("       Selecting a folder includes its hidden regular files. Do not include credentials; links/special files are rejected.")
        if ask("  Upload selected items now? [y/N]: ").lower() not in ("y", "yes"):
            return
        info = self.folder_info("input", create=True)
        scope, completed = self.scope("input", info), 0
        try:
            for entry, name in plans:
                path = relative_path(self.local_dir, entry["rel"])
                current = self.local_dir.stat()
                if [current.st_dev, current.st_ino] != self.local_identity:
                    raise FilesError("The local launch directory changed; reopen file mode.")
                source = UploadSource(path, expected=entry.get("signature"), boundary=str(self.local_dir))
                try:
                    self.send_source(source, name, info, scope)
                    completed += 1
                finally:
                    source.close()
        finally:
            print(f"       Upload batch: {completed}/{len(plans)} item(s) completed. Finished uploads were not rolled back.")
        print("       Tell Codex: Read the files in ./input/ and save finished deliverables in ./output/.")

    def send_source(self, source, name, info, scope):
        req = self.request("upload", info["path"], name=name, identity=info["identity"], scope=scope,
                           manifest_sha256=hashlib.sha256(source.manifest).hexdigest())
        proc = None
        try:
            with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors, Deadline(self.timeout):
                proc = subprocess.Popen(self.args(req), cwd=self.picker.context, stdin=subprocess.PIPE,
                                        stdout=output, stderr=errors, start_new_session=True)
                try:
                    total = source.stream(proc.stdin, req["nonce"])
                    proc.stdin.close()
                    proc.wait()
                except BrokenPipeError:
                    proc.wait(timeout=5)
                    errors.seek(0)
                    raise FilesError("Upload rejected: " + error_from_stream(errors.read())) from None
                output.seek(0)
                errors.seek(0)
                if proc.returncode:
                    raise FilesError("Upload not confirmed: " + error_from_stream(errors.read()) + ". Inspect input/ before retrying.")
                data = receipt(output.read(), req["nonce"])
                count = sum(e["kind"] == "file" for e in source.entries)
                if (data.get("path") != os.path.join(info["path"], name) or data.get("size") != total
                    or data.get("files") != count or data.get("manifest_sha256") != req["manifest_sha256"]):
                    raise FilesError("Upload receipt mismatch; inspect input/ before retrying.")
                print(f"  Uploaded: input/{safe(name)} ({count} files; {total:,} bytes)")
        finally:
            stop_transfer(proc)

    def view_inputs(self):
        info = self.folder_info("input")
        scope = self.scope("input", info)
        # Reuse selection UI solely for browsing/preview; no transfer follows.
        picker = FilePicker("Browse Codex input/ (read-only; Q returns)", info["path"],
                            lambda rel: self.remote_listing(info["path"], rel, scope), "return",
                            lambda entry: self.preview_remote(info["path"], scope, entry))
        picker.run()

    def menu(self):
        while True:
            print(f"\n=== Codex files on {self.sprite}")
            print("       Workspace: " + safe(self.cwd))
            print("       Download from: " + safe(os.path.join(self.cwd, "output")))
            print("       Upload to:     " + safe(os.path.join(self.cwd, "input")))
            print("       Local folder:  " + safe(self.local_dir))
            print("    1) Choose output files/folders to download")
            print("    2) Choose local files/folders to upload into input/")
            print("    3) Download all output/ as one ZIP")
            print("    4) Browse uploaded input/ files")
            print("    5) Select another session's workspace")
            print("    6) Choose another Sprite")
            print("    7) Open a separate shell (advanced; not needed for transfers)")
            print("    0) Quit file access (leave Codex running)")
            answer = ask("  File actions [0-7]: ")
            try:
                if answer in ("0", "q", "quit", ""):
                    return 0
                if answer == "1":
                    self.choose_outputs()
                elif answer == "2":
                    self.upload()
                elif answer == "3":
                    self.download_all()
                elif answer == "4":
                    self.view_inputs()
                elif answer == "5":
                    self.select_workspace()
                elif answer == "6":
                    old_sprite, old_cwd, old_identity = self.sprite, self.cwd, self.workspace_identity
                    try:
                        self.pin(self.picker.choose_sprite())
                        self.cwd, self.workspace_identity = "", None
                        self.select_workspace()
                    except BaseException:
                        self.pin(old_sprite)
                        self.cwd, self.workspace_identity = old_cwd, old_identity
                        raise
                elif answer == "7":
                    print("       Advanced shell is unrestricted by the input/output picker; exit returns here.")
                    self.shell()
                else:
                    print("Invalid selection.")
            except (FilesError, self.a.AttachError, self.o.DownloadError, remote.FileError) as exc:
                print("  Warning: " + safe(exc), file=sys.stderr)
                if "missing" in str(exc):
                    print("       Ask Codex to create ./output/ and save completed files there. input/ is created on the first confirmed upload.")
            except OSError as exc:
                print("  Warning: file/transport operation failed (" + type(exc).__name__ + "); check permissions or refresh. No setup fallback.", file=sys.stderr)
            except (Cancelled, self.a.Cancelled):
                print("       Selection cancelled; returning to file actions.")
            except KeyboardInterrupt:
                print("\n       File operation interrupted. Inspect completed transfers before retrying; Codex was not signalled.")


def main():
    if sys.version_info < (3, 9):
        raise FilesError("Shell/file mode requires Python 3.9 or newer locally and on the Sprite.")
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise FilesError("Shell/file mode needs an interactive local terminal; no remote operation was started.")
    source_dir, local_dir, requested_id, workdir = sys.argv[1:5]
    picker_module = runpy.run_path(os.path.join(source_dir, "picker.py"))
    output_module = runpy.run_path(os.path.join(source_dir, "output.py"))
    if requested_id and not os.environ.get("SPRITE_NAME"):
        raise FilesError("--session-id requires SPRITE_NAME to avoid selecting the wrong Sprite.")
    print("\n=== Codex input/output file picker")
    print("       No Codex launch/attach, provider keys, token validation, updates, Mobbin, Git sync or pushes.")
    print("       This mode uses the same filesystem, NOT the running agent's process environment.")
    print("       Avoid concurrent edits to the same file; tell Codex when new inputs are ready.")
    with tempfile.TemporaryDirectory(prefix="sprite-codex-files-context-") as context:
        browser = SimpleBrowser(picker_module, output_module, context, local_dir)
        try:
            browser.pin(browser.picker.choose_sprite(os.environ.get("SPRITE_NAME", "")))
            browser.select_workspace(requested_id, workdir)
            return browser.menu()
        except browser.a.Cancelled:
            return 0
        except browser.a.AttachError as exc:
            raise FilesError(str(exc)) from None

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Cancelled:
        print("\n       File access cancelled; existing Codex was not changed.")
        raise SystemExit(0)
    except KeyboardInterrupt:
        print("\n       File access interrupted; no Codex kill/restart was requested.")
        raise SystemExit(130)
    except (FilesError, remote.FileError) as exc:
        print("error: " + safe(exc), file=sys.stderr)
        raise SystemExit(1)
    except OSError as exc:
        print("error: local/remote file-access operation failed (" + type(exc).__name__ + "); no setup fallback.", file=sys.stderr)
        raise SystemExit(1)
FILES_ACCESS_PY
}

run_file_access() (
  command -v python3 >/dev/null 2>&1 || { echo "error: local python3 is required" >&2; exit 127; }
  local_sources=$(mktemp -d)
  trap 'rm -rf -- "$local_sources"' EXIT
  attach_only_python >"$local_sources/picker.py"
  output_download_python >"$local_sources/output.py"
  python3 -c "$(file_access_python)" "$local_sources" "$OUTPUT_HOST_DIR" "$ATTACH_SESSION_ID" "$FILE_WORKDIR"
)

retrieve_python() {
  cat <<'RETRIEVE_PY'
"""Local interactive retrieve mode. Embedded into sprite-codex-v59.sh."""
import contextlib
import getpass
import hashlib
import json
import os
import re
import runpy
import secrets
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import warnings
from pathlib import Path, PurePosixPath
from types import SimpleNamespace

REMOTE_RETRIEVE_PY = '"""Remote, one-request recovery worker. No old TTY/session or agent is used."""\nimport contextlib\nimport hashlib\nimport json\nimport os\nimport re\nimport signal\nimport stat\nimport subprocess\nimport sys\nimport tempfile\nimport time\nimport urllib.error\nimport urllib.request\nfrom pathlib import Path\n\nPREFIX = "SPRITE_RETRIEVE_JSON="\nMAX_OUTPUT = 2 * 1024 * 1024\nMAX_FILES = 100000\nMAX_BLOB = 100 * 1024 * 1024\nTOKEN = ""\nDEADLINE = 0.0\n\nclass RecoveryError(Exception):\n    pass\n\n\ndef redact(value):\n    text = str(value)\n    if TOKEN:\n        text = text.replace(TOKEN, "[REDACTED]")\n    text = re.sub(r"(?:github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]+)", "[REDACTED]", text)\n    text = re.sub(r"(https?://)[^/\\s@]+@", r"\\1[REDACTED]@", text)\n    return "".join(c if c in "\\n\\t" or (ord(c) >= 32 and ord(c) != 127) else "?" for c in text)\n\n\ndef clean_env():\n    keys = ("HOME", "PATH", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR", "SSL_CERT_FILE", "SSL_CERT_DIR")\n    env = {k: os.environ[k] for k in keys if k in os.environ}\n    env["PATH"] = os.path.expanduser("~/.local/bin") + ":/usr/local/bin:/usr/bin:/bin:" + env.get("PATH", "")\n    env.update(GIT_TERMINAL_PROMPT="0", GIT_PAGER="cat", PAGER="cat", GIT_OPTIONAL_LOCKS="0",\n               GIT_EDITOR="false", GIT_SEQUENCE_EDITOR="false", GH_PROMPT_DISABLED="1")\n    return env\n\n\ndef run(args, cwd=None, env=None, data=None, check=True, timeout=120):\n    seconds = min(timeout, max(1, DEADLINE - time.monotonic())) if DEADLINE else timeout\n    # Spool potentially large diagnostics; never accumulate arbitrary child output in RAM.\n    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:\n        p = subprocess.Popen(args, cwd=cwd, env=env or clean_env(), stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,\n                             stdout=output, stderr=errors, start_new_session=True)\n        try:\n            p.communicate(data, timeout=seconds)\n        except (subprocess.TimeoutExpired, KeyboardInterrupt):\n            with contextlib.suppress(ProcessLookupError):\n                os.killpg(p.pid, signal.SIGTERM)\n            try:\n                p.wait(timeout=2)\n            except subprocess.TimeoutExpired:\n                with contextlib.suppress(ProcessLookupError): os.killpg(p.pid, signal.SIGKILL)\n                p.wait()\n            raise RecoveryError("This recovery command timed out. Its effects may be partial; inspect status before retrying.") from None\n        output.seek(0); errors.seek(0)\n        out, err = output.read(MAX_OUTPUT+1), errors.read(MAX_OUTPUT+1)\n    if len(out) > MAX_OUTPUT or len(err) > MAX_OUTPUT:\n        raise RecoveryError("Git output exceeded the display limit. Narrow the command; any completed changes remain.")\n    if check and p.returncode:\n        detail = redact(err.decode("utf-8", "replace") or out.decode("utf-8", "replace"))\n        raise RecoveryError("Git/command failed (exit %s): %s" % (p.returncode, detail[:6000]))\n    return p.returncode, out, err\n\n\ndef git(root, args, **kwargs):\n    return run(["git", "--no-pager", "-c", "color.ui=false", "-C", str(root), *args], **kwargs)\n\n\ndef textgit(root, args, **kwargs):\n    return git(root, args, **kwargs)[1].decode("utf-8", "replace").strip()\n\n\ndef directory(path):\n    if not isinstance(path, str) or any(ord(c) < 32 or ord(c) == 127 for c in path):\n        raise RecoveryError("Invalid directory path.")\n    if path == "~" or path.startswith("~/"):\n        path = os.path.expanduser(path)\n    if not path.startswith("/") or ".." in Path(path).parts:\n        raise RecoveryError("Choose an absolute directory or a ~/ path; parent components are not accepted.")\n    path = os.path.normpath(path)\n    if any(path == p or path.startswith(p + "/") for p in ("/proc", "/sys", "/dev")):\n        raise RecoveryError("Virtual system paths cannot be recovery repositories.")\n    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)\n    try:\n        for component in Path(path).parts[1:]:\n            nxt = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)\n            os.close(fd); fd = nxt\n    finally:\n        os.close(fd)\n    return path\n\n\ndef github_repo(url):\n    for pattern in (r"https://github\\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\\.git)?/?",\n                    r"git@github\\.com:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\\.git)?",\n                    r"ssh://git@github\\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\\.git)?/?"):\n        m = re.fullmatch(pattern, url.strip(), re.I)\n        if m and all(x not in (".", "..") for x in m[1].split("/")):\n            return m[1]\n    return ""\n\n\ndef repo_info(path):\n    path = directory(path)\n    if textgit(path, ["rev-parse", "--is-inside-work-tree"]) != "true":\n        raise RecoveryError("Select an existing non-bare Git working directory. Nothing will be cloned or replaced.")\n    root = directory(textgit(path, ["rev-parse", "--show-toplevel"]))\n    gd = textgit(root, ["rev-parse", "--absolute-git-dir"])\n    common = textgit(root, ["rev-parse", "--git-common-dir"])\n    common = os.path.abspath(os.path.join(root, common))\n    raw_origin = textgit(root, ["config", "--get", "remote.origin.url"], check=False)\n    repo = github_repo(raw_origin)\n    head = textgit(root, ["rev-parse", "--verify", "HEAD"], check=False)\n    if head and not re.fullmatch(r"[0-9a-f]{40,64}", head):\n        raise RecoveryError("Unrecognized HEAD identity.")\n    branch = textgit(root, ["symbolic-ref", "--quiet", "--short", "HEAD"], check=False)\n    return dict(root=root, gitdir=gd, common=common, repo=repo, head=head, branch=branch,\n                origin=("https://github.com/"+repo+".git") if repo else "[missing or unsupported origin; not displayed]")\n\n\ndef index_signature(info):\n    p = Path(info["gitdir"]) / "index"\n    try:\n        with p.open("rb") as f:\n            h = hashlib.sha256()\n            for b in iter(lambda:f.read(1024*1024), b""): h.update(b)\n            return h.hexdigest()\n    except FileNotFoundError:\n        return "missing"\n\n\ndef state(info):\n    root = info["root"]\n    entries = git(root, ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])[1].split(b"\\0")\n    names = sorted(set(os.fsdecode(x) for x in entries if x))\n    if len(names) > MAX_FILES:\n        raise RecoveryError("Repository exceeds recovery\'s 100,000-file inspection limit; use a narrower archive/manual Git.")\n    h = hashlib.sha256()\n    h.update(json.dumps([info["head"], info["branch"], info["repo"], index_signature(info)], sort_keys=True).encode())\n    st = os.stat(root)\n    h.update(str((st.st_dev, st.st_ino)).encode())\n    for name in names:\n        if os.path.isabs(name) or ".." in Path(name).parts:\n            raise RecoveryError("Unexpected path in Git inventory.")\n        try:\n            s = os.lstat(os.path.join(root, name))\n            signature = (s.st_mode, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_ino, s.st_dev)\n        except FileNotFoundError:\n            signature = None\n        h.update(json.dumps([name, signature], ensure_ascii=True).encode())\n    return h.hexdigest(), len(names)\n\n\ndef status(path):\n    info = repo_info(path)\n    raw = git(info["root"], ["status", "--porcelain=v1", "-z", "--untracked-files=all"])[1]\n    parts = raw.split(b"\\0"); rows = []; i = 0\n    while i < len(parts):\n        entry = parts[i]; i += 1\n        if not entry: continue\n        code = entry[:2].decode("ascii", "replace")\n        name = os.fsdecode(entry[3:]); old = ""\n        if "R" in code or "C" in code:\n            if i < len(parts): old = os.fsdecode(parts[i]); i += 1\n        rows.append(dict(status=code, path=name, old=old))\n    digest, count = state(info)\n    info.update(fingerprint=digest, files=count, changes=rows, dirty=bool(rows))\n    info["operation"] = [p for p in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "index.lock")\n                         if os.path.exists(os.path.join(info["gitdir"], p))]\n    info["identity_name"] = textgit(info["root"], ["config", "user.name"], check=False)\n    info["identity_email"] = textgit(info["root"], ["config", "user.email"], check=False)\n    info["recent"] = textgit(info["root"], ["log", "-5", "--format=%h %s"], check=False)[:4000] if info["head"] else ""\n    return info\n\n\ndef unchanged(info, expected):\n    current = repo_info(info["root"])\n    digest, _ = state(current)\n    if not expected or digest != expected:\n        raise RecoveryError("Repository files, HEAD, origin, or index changed since review. Refresh before writing; no automatic retry.")\n\n\ndef api_json(path, token):\n    req = urllib.request.Request("https://api.github.com"+path,\n        headers={"Authorization":"Bearer "+token, "Accept":"application/vnd.github+json", "User-Agent":"sprite-codex-retrieve-v57"})\n    # Do not forward an Authorization header across a redirect.\n    class NoRedirect(urllib.request.HTTPRedirectHandler):\n        def redirect_request(self, *args, **kwargs): return None\n    try:\n        with urllib.request.build_opener(NoRedirect()).open(req, timeout=min(30, max(1, DEADLINE-time.monotonic())) if DEADLINE else 30) as r:\n            data = r.read(MAX_OUTPUT+1)\n        if len(data) > MAX_OUTPUT: raise RecoveryError("GitHub response exceeded the safe limit.")\n        return json.loads(data)\n    except urllib.error.HTTPError as e:\n        raise RecoveryError("GitHub verification failed (HTTP %d). Check token expiry, repository selection/permissions, SSO, or rate limits." % e.code) from None\n    except (urllib.error.URLError, ValueError):\n        raise RecoveryError("GitHub verification did not complete; token validity is unknown.") from None\n\n\ndef authenticate(info, token, expected_repo):\n    if not info["repo"] or info["repo"].lower() != str(expected_repo).lower():\n        raise RecoveryError("Origin changed or is not an approved github.com repository; authenticate the selected repository again.")\n    if not token or "\\n" in token or "\\r" in token or "\\x00" in token:\n        raise RecoveryError("A GitHub PAT without control characters is required.")\n    user = api_json("/user", token)\n    data = api_json("/repos/"+info["repo"], token)\n    if not isinstance(user, dict) or not user.get("login") or not isinstance(data, dict):\n        raise RecoveryError("Unexpected GitHub authentication response.")\n    if str(data.get("full_name", "")).lower() != info["repo"].lower():\n        raise RecoveryError("GitHub repository identity differs; no redirect/rename is accepted automatically.")\n    permissions = data.get("permissions", {})\n    if permissions and not any(permissions.get(x) for x in ("push", "admin", "maintain")):\n        raise RecoveryError("GitHub reports no write permission for this repository.")\n    return {"login":user["login"], "id":str(user.get("id", "")), "repo":info["repo"],\n            "note":"Authentication/repository access verified; the actual push remains subject to token scopes and branch rules."}\n\n\nCREDENTIAL = \'\'\'#!/usr/bin/env python3\nimport os, sys\nfields = dict(line.rstrip("\\\\n").split("=",1) for line in sys.stdin if "=" in line)\nrepo = os.environ.get("SPRITE_RETRIEVE_REPO", "").lower()\npath = fields.get("path", "").removesuffix(".git").lower()\nif len(sys.argv)>1 and sys.argv[1]=="get" and fields.get("protocol")=="https" and fields.get("host")=="github.com" and path==repo:\n    print("username=x-access-token")\n    print("password="+os.environ.get("SPRITE_RETRIEVE_TOKEN", ""))\n\'\'\'\n\n\n@contextlib.contextmanager\ndef credentials(info, token, hooks=False):\n    with tempfile.TemporaryDirectory(prefix="sprite-retrieve-auth-") as temp:\n        helper = Path(temp)/"credential.py"; helper.write_text(CREDENTIAL); helper.chmod(0o700)\n        import shlex\n        env = clean_env()\n        env.update(SPRITE_RETRIEVE_TOKEN=token, SPRITE_RETRIEVE_REPO=info["repo"])\n        cfg = [("credential.helper", ""), ("credential.https://github.com.helper", ""),\n               ("credential.https://github.com.helper", "!"+shlex.quote(sys.executable)+" "+shlex.quote(str(helper))),\n               ("credential.useHttpPath", "true"), ("credential.interactive", "false"),\n               ("http.extraHeader", ""), ("http.followRedirects", "false"),\n               ("remote.origin.url", info["origin"]), ("remote.origin.pushurl", info["origin"])]\n        if not hooks: cfg.append(("core.hooksPath", "/dev/null"))\n        env["GIT_CONFIG_COUNT"] = str(len(cfg))\n        for i,(k,v) in enumerate(cfg): env["GIT_CONFIG_KEY_%d"%i]=k; env["GIT_CONFIG_VALUE_%d"%i]=v\n        yield env\n\n\ndef oid_remote(info, branch, env):\n    result = textgit(info["root"], ["ls-remote", "--heads", info["origin"], "refs/heads/"+branch], env=env)\n    if not result: return ""\n    rows = result.splitlines()\n    if len(rows) != 1: raise RecoveryError("Remote branch query was ambiguous.")\n    oid, ref = rows[0].split("\\t", 1)\n    if ref != "refs/heads/"+branch or not re.fullmatch(r"[0-9a-f]{40,64}", oid):\n        raise RecoveryError("Unrecognized remote branch result.")\n    return oid\n\n\ndef validate_branch(info, branch, recovery=False):\n    if not isinstance(branch, str) or len(branch)>240 or branch.startswith("-"):\n        raise RecoveryError("Invalid branch name.")\n    if recovery and not re.fullmatch(r"sprite-recovery/[A-Za-z0-9._-]+", branch):\n        raise RecoveryError("A recovery branch must start with sprite-recovery/ and contain one safe suffix.")\n    git(info["root"], ["check-ref-format", "refs/heads/"+branch])\n\n\ndef safe_snapshot_paths(info):\n    # Registered submodules/LFS need their own payload transfer. Never falsely\n    # report those pointer-only commits as a complete backup.\n    stages = git(info["root"], ["ls-files", "--stage", "-z"])[1]\n    if any(p.startswith(b"160000 ") for p in stages.split(b"\\0")):\n        raise RecoveryError("Guided snapshots do not back up submodule worktrees. Use ZIP/manual Git for each repository.")\n    names = git(info["root"], ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])[1]\n    attrs = git(info["root"], ["check-attr", "-z", "--stdin", "filter"], data=names)[1]\n    if b"\\0filter\\0lfs\\0" in attrs:\n        raise RecoveryError("Git LFS is present. Use manual Git with LFS installed or a ZIP; guided recovery will not upload pointers alone.")\n    if info["operation"]:\n        raise RecoveryError("Unfinished Git operation or lock detected: "+", ".join(info["operation"])+". Nothing is removed automatically; use ZIP or resolve it explicitly.")\n    if textgit(info["root"], ["config", "--bool", "core.sparseCheckout"], check=False) == "true":\n        raise RecoveryError("Guided snapshots do not support sparse checkouts. Use existing-commit push or manual Git.")\n\n\ndef secret_path(name):\n    parts = Path(name).parts; base = parts[-1].lower() if parts else ""\n    return (any(p.lower() in (".ssh", ".aws", ".codex", ".sprites", ".sprite-fly-tokens") for p in parts)\n            or (base.startswith(".env") and not base.endswith((".example", ".sample", ".template")))\n            or base in ("id_rsa", "id_ed25519", ".netrc", ".git-credentials", "credentials.json", "auth.json")\n            or base.endswith((".pem", ".p12", ".pfx", ".key")))\n\n\nSECRETS = re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{24,}")\n\n\ndef scan_tree(info, tree, env):\n    args = ["diff-tree", "--no-commit-id", "--name-only", "-r", "-z", info["head"], tree] if info["head"] else ["ls-tree", "-r", "--name-only", "-z", tree]\n    names = git(info["root"], args, env=env)[1].split(b"\\0")\n    for bname in names:\n        if not bname: continue\n        name = os.fsdecode(bname)\n        spec = tree+":"+name\n        rc, raw, _ = git(info["root"], ["cat-file", "-s", spec], env=env, check=False)\n        if rc: continue  # deletion, no blob is exported\n        if secret_path(name):\n            raise RecoveryError("Potential credential file in the recovery commit: "+redact(name)+". Review/exclude it before retrying.")\n        size = int(raw)\n        if size > MAX_BLOB:\n            raise RecoveryError("Changed file exceeds 100 MiB: "+redact(name)+". Download a ZIP or use LFS deliberately; no GitHub push was attempted.")\n        # cat-file streamed to disk, with bounded scan overlap, instead of loading huge blobs.\n        p = subprocess.Popen(["git", "-C", info["root"], "cat-file", "blob", spec], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)\n        previous = b""\n        try:\n            while True:\n                chunk = p.stdout.read(1024*1024)\n                if not chunk: break\n                data = previous + chunk\n                if SECRETS.search(data) or (TOKEN and TOKEN.encode() in data):\n                    raise RecoveryError("Potential credential content detected in "+redact(name)+". No credential value is displayed; no push was attempted.")\n                previous = data[-1024:]\n                if DEADLINE and time.monotonic() >= DEADLINE:\n                    raise RecoveryError("Credential-content scan timed out; no push was attempted.")\n            if p.wait(timeout=5): raise RecoveryError("Could not inspect a recovery blob.")\n        finally:\n            if p.poll() is None: p.kill(); p.wait()\n            p.stdout.close()\n\n\ndef journal(info, opid, data):\n    base = Path(info["common"]) / "sprite-retrieve"\n    base.mkdir(mode=0o700, exist_ok=True)\n    if base.is_symlink() or not base.is_dir(): raise RecoveryError("Unsafe recovery receipt directory.")\n    fd, temp = tempfile.mkstemp(prefix=".receipt-", dir=base)\n    try:\n        with os.fdopen(fd, "w") as f:\n            json.dump(data, f, ensure_ascii=True); f.write("\\n"); f.flush(); os.fsync(f.fileno())\n        os.replace(temp, base/(opid+".json"))\n    finally:\n        with contextlib.suppress(FileNotFoundError): os.unlink(temp)\n\n\ndef snapshot(req):\n    info = status(req["path"]); unchanged(info, req.get("expected"))\n    safe_snapshot_paths(info)\n    branch = req["branch"]; validate_branch(info, branch, recovery=True)\n    opid = req["opid"]\n    if not re.fullmatch(r"[0-9a-f]{32}", opid): raise RecoveryError("Invalid operation ID.")\n    # Revalidate credentials before creating a Git commit, not after the mutation.\n    user = authenticate(info, TOKEN, req.get("repo"))\n    ref = "refs/heads/"+branch\n    if textgit(info["root"], ["show-ref", "--hash", "--verify", ref], check=False):\n        raise RecoveryError("Recovery ref already exists. Use Publish saved recovery branch; no duplicate commit was made.")\n    with credentials(info, TOKEN) as network_env, tempfile.TemporaryDirectory(prefix="sprite-retrieve-index-") as temp:\n        # Staging/clean filters do not need GitHub credentials. Only the later\n        # network publish subprocess receives the PAT environment.\n        env = clean_env()\n        env["GIT_INDEX_FILE"] = str(Path(temp)/"index")\n        git(info["root"], ["read-tree", info["head"]] if info["head"] else ["read-tree", "--empty"], env=env)\n        git(info["root"], ["add", "-A", "--", "."], env=env)\n        tree = textgit(info["root"], ["write-tree"], env=env)\n        scan_tree(info, tree, env)\n        unchanged(info, req.get("expected"))\n        name = req.get("author_name") or info["identity_name"] or user["login"]\n        email = req.get("author_email") or info["identity_email"] or (user["id"]+"+"+user["login"]+"@users.noreply.github.com")\n        if any(c in name+email for c in "\\r\\n\\x00") or not name or "@" not in email:\n            raise RecoveryError("Provide a valid single-line commit identity.")\n        env.update(GIT_AUTHOR_NAME=name, GIT_COMMITTER_NAME=name, GIT_AUTHOR_EMAIL=email, GIT_COMMITTER_EMAIL=email)\n        message = req.get("message", "Recover Sprite workspace")\n        if not isinstance(message, str) or not message.strip() or len(message)>2000 or "\\x00" in message:\n            raise RecoveryError("Invalid commit message.")\n        commit = textgit(info["root"], ["-c", "commit.gpgSign=false", "commit-tree", tree, *(["-p", info["head"]] if info["head"] else []), "-m", message], env=env)\n        git(info["root"], ["update-ref", "-m", "Sprite recovery snapshot", ref, commit, "0"*len(commit)], env=env)\n        receipt = dict(opid=opid, branch=branch, commit=commit, tree=tree, source=info["root"], repo=info["repo"], status="saved_local", time=int(time.time()))\n        journal(info, opid, receipt)\n        try:\n            published = publish(info, branch, commit, network_env)\n            receipt.update(published); journal(info, opid, receipt)\n        except RecoveryError as e:\n            receipt["push_error"] = redact(e)\n        receipt["source_changed_after_capture"] = state(repo_info(info["root"]))[0] != req.get("expected")\n        return receipt\n\n\ndef publish(info, branch, commit, env):\n    validate_branch(info, branch, recovery=True)\n    remote = oid_remote(info, branch, env)\n    if remote and remote != commit:\n        raise RecoveryError("Remote recovery branch has different content; it will not be overwritten.")\n    if not remote:\n        git(info["root"], ["push", "--porcelain", info["origin"], commit+":refs/heads/"+branch], env=env)\n    actual = oid_remote(info, branch, env)\n    if actual != commit:\n        raise RecoveryError("Push result could not be verified on GitHub. Inspect this ref before retrying.")\n    return dict(status="verified_on_github", remote_commit=actual, branch=branch, commit=commit)\n\n\ndef push_current(req):\n    info = status(req["path"]); unchanged(info, req.get("expected"))\n    if not info["head"] or not info["branch"]:\n        raise RecoveryError("Current-branch push requires an existing commit and attached branch. Use a recovery snapshot instead.")\n    if info["operation"]: raise RecoveryError("An unfinished Git operation/lock must be inspected first.")\n    authenticate(info, TOKEN, req.get("repo"))\n    with credentials(info, TOKEN, hooks=True) as env:\n        branch = info["branch"]; validate_branch(info, branch)\n        remote = oid_remote(info, branch, env)\n        if remote and remote != info["head"]:\n            git(info["root"], ["fetch", "--no-tags", "--no-recurse-submodules", "--no-write-fetch-head", info["origin"], "refs/heads/"+branch], env=env)\n            rc, _, _ = git(info["root"], ["merge-base", "--is-ancestor", remote, info["head"]], env=env, check=False)\n            if rc:\n                raise RecoveryError("GitHub branch is ahead or divergent. No pull/reset/force-push was done; save a recovery branch instead.")\n        unchanged(info, req.get("expected"))\n        git(info["root"], ["push", "--porcelain", info["origin"], info["head"]+":refs/heads/"+branch], env=env)\n        actual = oid_remote(info, branch, env)\n        if actual != info["head"]: raise RecoveryError("Remote commit could not be verified; inspect GitHub before retrying.")\n        return dict(status="verified_on_github", branch=branch, commit=actual, uncommitted_files_not_included=info["dirty"])\n\n\nREAD_COMMANDS = {"status", "diff", "log", "show", "rev-parse", "ls-files", "ls-remote", "reflog"}\nCOMMANDS = READ_COMMANDS | {"fetch", "add", "commit", "push", "pull", "merge", "rebase", "cherry-pick", "branch", "restore", "reset", "rm", "mv", "stash"}\n\n\ndef command(req):\n    info = repo_info(req["path"])\n    args = req.get("args")\n    if (not isinstance(args, list) or not args or args[0] not in COMMANDS or len(args)>200\n            or any(not isinstance(a,str) or "\\x00" in a or len(a)>8192 for a in args)):\n        raise RecoveryError("Enter a supported Git subcommand, not a shell command, alias, or global Git option.")\n    if not req.get("confirmed"):\n        raise RecoveryError("The advanced command must be confirmed explicitly.")\n    if TOKEN:\n        authenticate(info, TOKEN, req.get("repo"))\n        with credentials(info, TOKEN, hooks=True) as env:\n            rc, out, err = git(info["root"], args, env=env, check=False, timeout=600)\n    else:\n        if args[0] not in READ_COMMANDS:\n            raise RecoveryError("Authenticate GitHub first for advanced mutation commands.")\n        rc, out, err = git(info["root"], args, check=False)\n    return dict(exit=rc, stdout=redact(out.decode("utf-8", "replace")), stderr=redact(err.decode("utf-8", "replace")),\n                note="Executed once. Inspect status; success of a command is not proof the whole workspace is backed up.")\n\n\ndef diagnostics():\n    names = []\n    rc, out, _ = run(["ps", "-eo", "pid,ppid,stat,tty,etime,comm"], check=False)\n    for line in out.decode("utf-8", "replace").splitlines():\n        if any(n in line.lower() for n in ("codex", "kimi", "git", "node", "pid")): names.append(line)\n    disk = os.statvfs(os.path.expanduser("~"))\n    return dict(home=os.path.expanduser("~"), git=run(["git", "--version"], check=False)[1].decode().strip(),\n                processes="\\n".join(names[:100]), free_bytes=disk.f_bavail*disk.f_frsize,\n                note="Process names only; no arguments/environments. Presence is not responsiveness. No process was stopped.")\n\n\n# v57: repository-first synchronization, separate from the legacy backup helpers.\ndef normalize_target(value):\n    if not isinstance(value, str):\n        raise RecoveryError(\'Enter a GitHub repository as OWNER/REPO or a GitHub repository URL.\')\n    value = value.strip()\n    repo = github_repo(value)\n    if not repo and re.fullmatch(r\'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\', value):\n        repo = value.removesuffix(\'.git\')\n    if not repo or any(p in (\'.\', \'..\', \'\') for p in repo.split(\'/\')):\n        raise RecoveryError(\'Enter OWNER/REPO or a repository URL on github.com (no credentials, query, or branch suffix).\')\n    return repo\n\n\ndef authorize_target(repo, token):\n    """Runs on the laptop BEFORE Sprite selection, and again on the Sprite."""\n    import base64\n    repo = normalize_target(repo)\n    user = authenticate({\'repo\': repo}, token, repo)\n    meta = api_json(\'/repos/\' + repo, token)\n    if meta.get(\'archived\') or meta.get(\'disabled\'):\n        raise RecoveryError(\'The selected GitHub repository is archived or disabled; writes are unavailable.\')\n    class NoRedirect(urllib.request.HTTPRedirectHandler):\n        def redirect_request(self, *args, **kwargs): return None\n    header = base64.b64encode((\'x-access-token:\' + token).encode()).decode()\n    req = urllib.request.Request(\'https://github.com/\' + repo + \'.git/info/refs?service=git-receive-pack\',\n        headers={\'Authorization\': \'Basic \' + header, \'User-Agent\': \'sprite-codex-retrieve-v57\'})\n    try:\n        seconds = min(30, max(1, DEADLINE-time.monotonic())) if DEADLINE else 30\n        with urllib.request.build_opener(NoRedirect()).open(req, timeout=seconds) as response:\n            data = response.read(1048576)\n            mime = response.headers.get(\'Content-Type\', \'\').split(\';\')[0].strip()\n            if mime != \'application/x-git-receive-pack-advertisement\' or b\'# service=git-receive-pack\\n\' not in data[:128]:\n                raise RecoveryError(\'GitHub did not return its authenticated Git write-service advertisement.\')\n    except urllib.error.HTTPError as exc:\n        raise RecoveryError(\'GitHub write-service check failed (HTTP %s). Check PAT Contents: read/write, SSO and repository selection.\' % exc.code) from None\n    except (urllib.error.URLError, TimeoutError):\n        raise RecoveryError(\'GitHub write-service check could not finish; write access is unverified.\') from None\n    user.update(default_branch=str(meta.get(\'default_branch\') or \'\'),\n        note=\'PAT/repository and Git write-service access verified without a write. Branch protections and other server rules still apply to the actual push.\')\n    return user\n\n\ndef discover_repositories(req):\n    target = normalize_target(req[\'repo\']).lower()\n    home = os.path.expanduser(\'~\')\n    roots = req.get(\'roots\') or [home, \'/home\', \'/workspace\', \'/workspaces\', \'/work\', \'/app\', \'/data\', \'/srv\', \'/opt\', \'/mnt\']\n    if not isinstance(roots, list) or len(roots) > 30:\n        raise RecoveryError(\'Invalid repository search roots.\')\n    extra = req.get(\'start\')\n    if extra: roots = [extra] + roots\n    # Non-secret workspace receipts are only search hints. Origin is always checked.\n    state_dir = Path(home)/\'.local/state/sprite-codex\'\n    if not state_dir.is_symlink() and state_dir.is_dir():\n        for hint in list(state_dir.glob(\'workdir-*\'))[:500]:\n            if hint.is_symlink() or not hint.is_file(): continue\n            try:\n                if hint.stat().st_size < 4096:\n                    roots.insert(0, hint.read_text().strip())\n            except (OSError, UnicodeError): pass\n    skip = {\'.git\', \'.cache\', \'.npm\', \'.nvm\', \'.rustup\', \'.cargo\', \'.venv\', \'venv\',\n            \'node_modules\', \'__pycache__\', \'.mypy_cache\', \'.next\', \'.codex\', \'.sprites\'}\n    forbidden = (\'/proc\', \'/sys\', \'/dev\', \'/run\', \'/.sprite\')\n    visited = set(); found = {}; scanned = 0; errors = 0; limited = False; inspected = []\n    stop_at = min(DEADLINE-5, time.monotonic()+90) if DEADLINE else time.monotonic()+90\n    stack = []\n    for root in reversed(roots):\n        try: root = directory(root)\n        except (OSError, RecoveryError): continue\n        if root not in inspected:\n            inspected.append(root); stack.append((root, 0))\n    while stack:\n        if scanned >= 30000 or time.monotonic() >= stop_at:\n            limited = True; break\n        path, depth = stack.pop()\n        if path in visited or any(path == p or path.startswith(p+\'/\') for p in forbidden): continue\n        visited.add(path); scanned += 1\n        try:\n            with os.scandir(path) as listing: entries = list(listing)\n        except OSError:\n            errors += 1; continue\n        marker = next((x for x in entries if x.name == \'.git\'), None)\n        if marker and not marker.is_symlink():\n            try:\n                # Do not hash every file until the user chooses this checkout.\n                if github_repo(textgit(path, [\'config\', \'--get\', \'remote.origin.url\'], check=False)).lower() == target:\n                    info = repo_info(path)\n                    if info[\'repo\'].lower() == target: found[info[\'root\']] = info\n            except (RecoveryError, OSError): errors += 1\n        for item in entries:\n            if item.name in skip or item.is_symlink(): continue\n            try: is_dir = item.is_dir(follow_symlinks=False)\n            except OSError:\n                errors += 1; continue\n            if not is_dir: continue\n            if depth >= 20: limited = True; continue\n            stack.append((item.path, depth+1))\n    return dict(matches=sorted(found.values(), key=lambda x:x[\'root\']), roots=inspected,\n                scanned=scanned, unreadable=errors, limited=limited,\n                note=\'Only accessible non-symlink Git checkouts whose origin matches the requested GitHub repository are offered. Dependency/cache and virtual-system directories are skipped.\')\n\n\ndef sync_env():\n    env = clean_env()\n    cfg = [(\'core.hooksPath\', \'/dev/null\'), (\'commit.gpgSign\', \'false\'), (\'gc.auto\', \'0\'),\n           (\'maintenance.auto\', \'false\'), (\'merge.autoStash\', \'false\'), (\'merge.verifySignatures\', \'false\')]\n    env[\'GIT_CONFIG_COUNT\'] = str(len(cfg))\n    for i, (key, value) in enumerate(cfg):\n        env[\'GIT_CONFIG_KEY_%d\'%i] = key; env[\'GIT_CONFIG_VALUE_%d\'%i] = value\n    return env\n\n\ndef guided_guards(info, target):\n    if info[\'repo\'].lower() != normalize_target(target).lower():\n        raise RecoveryError(\'The checkout origin no longer matches the selected GitHub repository.\')\n    if not info[\'branch\']:\n        raise RecoveryError(\'This checkout has detached HEAD. Choose an attached checkout or use the advanced Git console to select a branch explicitly.\')\n    safe_snapshot_paths(info)\n    if textgit(info[\'root\'], [\'rev-parse\', \'--is-shallow-repository\']) == \'true\':\n        raise RecoveryError(\'Shallow history cannot prove the full ancestry here. Fetch full history explicitly before retrying; no commit/push was made.\')\n    rewrites = textgit(info[\'root\'], [\'config\', \'--get-regexp\', r\'^url\\..*\\.(insteadof|pushinsteadof)$\'], check=False)\n    if rewrites:\n        raise RecoveryError(\'Git URL-rewrite configuration is present. Review it before guided sync; the selected GitHub destination must not be redirected.\')\n\n\n@contextlib.contextmanager\ndef staged_candidate(info):\n    """Construct Git objects only, without changing HEAD, checkout or normal index."""\n    with tempfile.TemporaryDirectory(prefix=\'sprite-sync-index-\') as tmp:\n        env = sync_env(); env[\'GIT_INDEX_FILE\'] = str(Path(tmp)/\'index\')\n        git(info[\'root\'], [\'read-tree\', info[\'head\']] if info[\'head\'] else [\'read-tree\', \'--empty\'], env=env)\n        git(info[\'root\'], [\'add\', \'-A\', \'--\', \'.\'], env=env)\n        tree = textgit(info[\'root\'], [\'write-tree\'], env=env)\n        yield tree, env\n\n\ndef fetched_tip(info, branch, env, expected=None):\n    validate_branch(info, branch)\n    tip = oid_remote(info, branch, env)\n    if expected is not None and tip != expected:\n        raise RecoveryError(\'The GitHub branch changed since review. Refresh and approve a new comparison; nothing was force-pushed.\')\n    if tip:\n        git(info[\'root\'], [\'fetch\', \'--no-tags\', \'--no-recurse-submodules\', \'--no-write-fetch-head\',\n                          \'--no-auto-maintenance\', info[\'origin\'], \'refs/heads/\'+branch], env=env)\n        if oid_remote(info, branch, env) != tip:\n            raise RecoveryError(\'The GitHub branch changed while fetching. Refresh the comparison.\')\n        git(info[\'root\'], [\'cat-file\', \'-e\', tip+\'^{commit}\'], env=env)\n    return tip\n\n\ndef sync_plan(req):\n    info = status(req[\'path\']); target = req[\'repo\']\n    guided_guards(info, target)\n    authenticate(info, TOKEN, target)\n    branch = req.get(\'branch\') or info[\'branch\']; validate_branch(info, branch)\n    with credentials(info, TOKEN) as env:\n        remote = fetched_tip(info, branch, env)\n    if remote and not info[\'head\']:\n        raise RecoveryError(\'The checkout has no commit but GitHub already has history. Refusing an unrelated replacement; use a matching existing checkout.\')\n    ahead = behind = 0\n    relation = \'new_branch\' if not remote else \'equal\'\n    base = \'\'\n    if remote and info[\'head\']:\n        base = textgit(info[\'root\'], [\'merge-base\', remote, info[\'head\']], check=False)\n        if not base:\n            raise RecoveryError(\'The checkout and GitHub branch have unrelated histories. No wholesale replacement or force-push is permitted.\')\n        counts = textgit(info[\'root\'], [\'rev-list\', \'--left-right\', \'--count\', remote+\'...\'+info[\'head\']]).split()\n        behind, ahead = map(int, counts)\n        relation = \'diverged\' if ahead and behind else \'behind\' if behind else \'ahead\' if ahead else \'equal\'\n    elif info[\'head\']:\n        ahead = int(textgit(info[\'root\'], [\'rev-list\', \'--count\', info[\'head\']]))\n    with staged_candidate(info) as (tree, env):\n        head_tree = textgit(info[\'root\'], [\'rev-parse\', info[\'head\']+\'^{tree}\']) if info[\'head\'] else \'\'\n        args = [\'diff-tree\', \'--no-commit-id\', \'--stat\', \'-r\', info[\'head\'], tree] if info[\'head\'] else [\'ls-tree\', \'-r\', \'--name-only\', tree]\n        summary = textgit(info[\'root\'], args, env=env)\n    unchanged(info, info[\'fingerprint\'])\n    local_range = (remote+\'..\'+info[\'head\']) if remote else info[\'head\']\n    remote_range = (info[\'head\']+\'..\'+remote) if info[\'head\'] and remote else \'\'\n    return dict(**info, target_branch=branch, remote_commit=remote, candidate_tree=tree,\n        needs_commit=(tree != head_tree), ahead=ahead, behind=behind, relation=relation,\n        remote_latest=textgit(info[\'root\'], [\'log\', \'-1\', \'--format=%H %cI %s\', remote]) if remote else \'(branch does not exist on GitHub)\',\n        local_only=textgit(info[\'root\'], [\'log\', \'-20\', \'--format=%h %s\', local_range]) if local_range else \'\',\n        remote_only=textgit(info[\'root\'], [\'log\', \'-20\', \'--format=%h %s\', remote_range]) if remote_range else \'\',\n        change_summary=summary[:20000], summary_truncated=len(summary)>20000,\n        no_op=(not info[\'dirty\'] and not ahead and not behind and bool(remote)))\n\n\ndef scan_outgoing(info, head, remote, env):\n    """Inspect every outgoing commit, not just the final diff (deleted secrets count)."""\n    commits = textgit(info[\'root\'], [\'rev-list\', \'--max-count=1001\', head] + ([\'^\'+remote] if remote else []), env=env).splitlines()\n    if len(commits)>1000:\n        raise RecoveryError(\'More than 1,000 unpublished commits need review; guided sync stops rather than skipping checks.\')\n    for oid in commits:\n        parents = textgit(info[\'root\'], [\'show\', \'-s\', \'--format=%P\', oid], env=env).split()\n        scan_tree(dict(info, head=parents[0] if parents else \'\'), oid, env)\n\n\ndef merge_preview(info, head, remote, env):\n    code, out, err = git(info[\'root\'], [\'merge-tree\', \'--write-tree\', head, remote], env=env, check=False, timeout=180)\n    if code:\n        if code == 1:\n            detail = redact(out.decode(\'utf-8\', \'replace\'))[-5000:]\n            raise RecoveryError(\'Merge conflicts detected before changing the working files. No push was made. Any new local commit remains saved.\\n\'+detail)\n        raise RecoveryError(\'Cannot safely preview this merge (Git 2.38+ required). No push was made; inspect the local commit and Git version.\')\n    tree = out.decode(\'utf-8\',\'replace\').splitlines()[0]\n    if not re.fullmatch(r\'[0-9a-f]{40,64}\', tree):\n        raise RecoveryError(\'Unexpected merge preview; no merge/push was attempted.\')\n    return tree\n\n\ndef sync_apply(req):\n    if req.get(\'confirmed\') is not True:\n        raise RecoveryError(\'Synchronization requires explicit approval of the displayed plan.\')\n    opid = req.get(\'opid\',\'\')\n    if not re.fullmatch(r\'[0-9a-f]{32}\', opid): raise RecoveryError(\'Invalid synchronization operation ID.\')\n    info = status(req[\'path\']); guided_guards(info, req[\'repo\'])\n    unchanged(info, req.get(\'expected\'))\n    target_branch = req[\'branch\']; validate_branch(info, target_branch)\n    if req.get(\'source_branch\') != info[\'branch\'] or req.get(\'source_head\') != info[\'head\']:\n        raise RecoveryError(\'Source branch/HEAD changed after review.\')\n    author = authenticate(info, TOKEN, req[\'repo\'])\n    env = sync_env()\n    for label, field, fallback in [(\'name\', \'author_name\', info[\'identity_name\'] or author[\'login\']),\n                                    (\'email\', \'author_email\', info[\'identity_email\'] or author[\'id\']+\'+\'+author[\'login\']+\'@users.noreply.github.com\')]:\n        value = req.get(field) or fallback\n        if not isinstance(value,str) or not value or any(ord(c)<32 for c in value) or len(value)>320:\n            raise RecoveryError(\'Invalid commit identity.\')\n        env[\'GIT_AUTHOR_\'+label.upper()] = value; env[\'GIT_COMMITTER_\'+label.upper()] = value\n    message = req.get(\'message\') or \'Sync Sprite repository to GitHub\'\n    if not isinstance(message,str) or \'\\x00\' in message or not message.strip() or len(message)>8192:\n        raise RecoveryError(\'Invalid commit message.\')\n    import fcntl\n    lock_path = Path(info[\'common\'])/\'sprite-codex-sync.lock\'\n    fd = os.open(lock_path, os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW, 0o600)\n    phase = \'reviewed\'; current_commit = info[\'head\']; result = {}\n    try:\n        try: fcntl.flock(fd, fcntl.LOCK_EX|fcntl.LOCK_NB)\n        except BlockingIOError:\n            raise RecoveryError(\'Another guided synchronization holds this repository lock. No write was attempted.\') from None\n        unchanged(info, req[\'expected\'])\n        with credentials(info, TOKEN) as network_env:\n            remote = fetched_tip(info, target_branch, network_env, expected=req.get(\'remote_commit\',\'\'))\n            behind = False\n            if remote and info[\'head\']:\n                code, _, _ = git(info[\'root\'], [\'merge-base\',\'--is-ancestor\',remote,info[\'head\']], check=False)\n                if code not in (0,1): raise RecoveryError(\'Cannot verify GitHub ancestry.\')\n                behind = code == 1\n            if behind and not req.get(\'allow_merge\'):\n                raise RecoveryError(\'GitHub has commits not in this checkout. Merging/fast-forwarding was not approved.\')\n            with staged_candidate(info) as (tree, temporary_env):\n                if tree != req.get(\'candidate_tree\'):\n                    raise RecoveryError(\'Working files no longer match the reviewed content; refresh before committing.\')\n                scan_tree(info, tree, temporary_env)\n            if info[\'head\']: scan_outgoing(info, info[\'head\'], remote, env)\n            unchanged(info, req[\'expected\'])\n            # Record intent without secrets. A lost connection must not replay a write.\n            result = dict(repo=info[\'repo\'], source_root=info[\'root\'], source_branch=info[\'branch\'],\n                          branch=target_branch, old_head=info[\'head\'], remote_before=remote,\n                          operation_id=opid, status=\'started\', phase=phase)\n            journal(info, opid, result)\n            if info[\'dirty\'] or not info[\'head\']:\n                git(info[\'root\'], [\'add\', \'-A\', \'--\', \'.\'], env=env)\n                phase = \'staged\'\n                if textgit(info[\'root\'], [\'write-tree\'], env=env) != tree:\n                    raise RecoveryError(\'The staged contents differ from the reviewed files. Staging remains; no commit/push was made.\')\n                if git(info[\'root\'], [\'diff\', \'--quiet\', \'--\'], env=env, check=False)[0] or textgit(info[\'root\'], [\'ls-files\',\'--others\',\'--exclude-standard\'], env=env):\n                    raise RecoveryError(\'Files changed during staging. No commit/push was made; review staging before retrying.\')\n                now = repo_info(info[\'root\'])\n                if now[\'head\'] != info[\'head\'] or now[\'branch\'] != info[\'branch\']:\n                    raise RecoveryError(\'HEAD changed during staging; no commit/push was made by this step.\')\n                old_tree = textgit(info[\'root\'], [\'rev-parse\', info[\'head\']+\'^{tree}\'], env=env) if info[\'head\'] else \'\'\n                if tree != old_tree:\n                    git(info[\'root\'], [\'commit\', \'--no-gpg-sign\', \'-m\', message], env=env, timeout=180)\n                    current_commit = textgit(info[\'root\'], [\'rev-parse\',\'HEAD\'], env=env)\n                    if textgit(info[\'root\'], [\'rev-parse\',\'HEAD^{tree}\'], env=env) != tree:\n                        raise RecoveryError(\'HEAD tree changed while committing; inspect the checkout before retrying.\')\n                    phase = \'committed\'\n                    journal(info, opid, dict(result, status=\'local_only\', phase=phase, commit=current_commit))\n            if not current_commit:\n                raise RecoveryError(\'There is no commit to publish.\')\n            if behind:\n                check = status(info[\'root\'])\n                if check[\'dirty\'] or check[\'operation\'] or check[\'head\'] != current_commit or check[\'branch\'] != info[\'branch\']:\n                    raise RecoveryError(\'Checkout changed before integration; saved commits remain, and no merge/push was made.\')\n                code, _, _ = git(info[\'root\'], [\'merge-base\',\'--is-ancestor\',current_commit,remote], env=env, check=False)\n                if code == 0:\n                    git(info[\'root\'], [\'merge\', \'--ff-only\', \'--no-edit\', remote], env=env, timeout=180)\n                else:\n                    expected_merge = merge_preview(info, current_commit, remote, env)\n                    unchanged(check, check[\'fingerprint\'])\n                    git(info[\'root\'], [\'merge\', \'--no-edit\', \'--no-gpg-sign\', remote], env=env, timeout=180)\n                    if textgit(info[\'root\'], [\'rev-parse\',\'HEAD^{tree}\'], env=env) != expected_merge:\n                        raise RecoveryError(\'Merge result differed from preview. It remains local; no push was made.\')\n                phase = \'integrated\'; current_commit = textgit(info[\'root\'], [\'rev-parse\',\'HEAD\'], env=env)\n                journal(info, opid, dict(result, status=\'local_only\', phase=phase, commit=current_commit))\n            scan_outgoing(info, current_commit, remote, env)\n            check = status(info[\'root\'])\n            if check[\'head\'] != current_commit or check[\'branch\'] != info[\'branch\'] or check[\'dirty\'] or check[\'operation\']:\n                raise RecoveryError(\'Checkout changed before publication. Local commits remain; refresh the comparison.\')\n            # Recheck both during analysis and immediately before a normal, non-force push.\n            if oid_remote(info, target_branch, network_env) != remote:\n                raise RecoveryError(\'GitHub advanced during synchronization. Local commits remain; refresh the comparison. No force-push was made.\')\n            if current_commit != remote:\n                git(info[\'root\'], [\'push\',\'--porcelain\',\'--no-follow-tags\',\'--recurse-submodules=no\',info[\'origin\'],current_commit+\':refs/heads/\'+target_branch], env=network_env, timeout=180)\n            phase = \'push_returned\'\n            actual = oid_remote(info, target_branch, network_env)\n            if actual != current_commit:\n                raise RecoveryError(\'The intended commit is not verified as the current GitHub branch tip. Inspect GitHub before retrying.\')\n            end = status(info[\'root\'])\n            result.update(status=\'verified_on_github\', phase=\'verified\', commit=current_commit, remote_commit=actual,\n                          remaining_dirty=end[\'dirty\'], source_head_now=end[\'head\'],\n                          source_changed_after_sync=(end[\'head\'] != current_commit or end[\'dirty\'] or end[\'branch\'] != info[\'branch\']))\n            journal(info, opid, result)\n            return result\n    except (RecoveryError, OSError) as exc:\n        if not result: raise\n        result.update(status=\'not_verified\', phase=phase, commit=current_commit, error=redact(exc))\n        with contextlib.suppress(RecoveryError, OSError): journal(info, opid, result)\n        return result\n    finally:\n        os.close(fd)\n\n\ndef dispatch(req):\n    op = req.get("op")\n    if op == "discover": return discover_repositories(req)\n    if op == "sync_plan": return sync_plan(req)\n    if op == "sync_apply": return sync_apply(req)\n    if op == "probe": return dict(ok="SPRITE_RETRIEVE_OK", home=os.path.expanduser("~"), python=list(sys.version_info[:3]))\n    if op == "diagnostics": return diagnostics()\n    if op == "status": return status(req["path"])\n    if op == "auth": return authenticate(repo_info(req["path"]), TOKEN, req.get("repo"))\n    if op == "snapshot": return snapshot(req)\n    if op == "push_current": return push_current(req)\n    if op == "command": return command(req)\n    if op == "refs":\n        info = repo_info(req["path"])\n        raw = textgit(info["root"], ["for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads/sprite-recovery/"])\n        return [dict(branch=line.split()[0], commit=line.split()[1]) for line in raw.splitlines()]\n    if op == "publish":\n        info = repo_info(req["path"]); validate_branch(info, req["branch"], recovery=True)\n        authenticate(info, TOKEN, req.get("repo"))\n        commit = textgit(info["root"], ["rev-parse", "--verify", "refs/heads/"+req["branch"]+"^{commit}"])\n        if commit != req.get("commit"): raise RecoveryError("Saved recovery ref changed since selection.")\n        with credentials(info, TOKEN) as env: return publish(info, req["branch"], commit, env)\n    raise RecoveryError("Unknown recovery action.")\n\n\ndef main():\n    global TOKEN, DEADLINE\n    if sys.version_info < (3,9): raise RecoveryError("Python 3.9+ is required on the Sprite.")\n    raw = sys.stdin.buffer.read(65537)\n    if len(raw)>65536: raise RecoveryError("Request too large.")\n    req = json.loads(raw)\n    nonce = req.get("nonce", "")\n    if not re.fullmatch(r"[0-9a-f]{32}", nonce): raise RecoveryError("Invalid request identity.")\n    TOKEN = req.pop("token", "")\n    DEADLINE = time.monotonic() + min(3600, max(5, int(req.get("timeout", 180))))\n    try:\n        result = dict(nonce=nonce, ok=True, data=dispatch(req))\n    except (RecoveryError, OSError, ValueError) as e:\n        msg = redact(e) if isinstance(e, RecoveryError) else "Filesystem/command error (%s); inspect permissions, tools, disk space and connection."%type(e).__name__\n        result = dict(nonce=nonce, ok=False, error=msg)\n    print(PREFIX+json.dumps(result, ensure_ascii=True, separators=(",", ":")), flush=True)\n\nif __name__ == "__main__":\n    main()\n'

class RetrieveError(Exception):
    pass

class Cancelled(Exception):
    pass


def safe(value):
    return ''.join(c if c in '\n\t' or (c.isprintable() and ord(c) != 127) else '?' for c in str(value))


def ask(prompt):
    try:
        return input(prompt).strip()
    except EOFError:
        raise Cancelled() from None


def integer(name, default, high):
    value = os.environ.get(name, str(default))
    if not re.fullmatch(r'[1-9][0-9]*', value) or int(value)>high:
        raise RetrieveError(name+' must be 1..'+str(high))
    return int(value)


class Channel:
    """New exec commands only. An old session's ID, state and transport are irrelevant."""
    def __init__(self, picker, sprite, remote_code=REMOTE_RETRIEVE_PY):
        self.picker, self.sprite, self.code = picker, sprite, remote_code
        self.context, self.cli, self.org = picker.context, picker.cli, picker.org
        self.timeout = integer('SPRITE_RETRIEVE_TIMEOUT', 180, 3600)
        self.probe_timeout = integer('SPRITE_RETRIEVE_PROBE_TIMEOUT', 30, 300)
        choice = os.environ.get('SPRITE_RETRIEVE_TRANSPORT', 'auto')
        if choice not in ('auto', 'websocket', 'http-post'):
            raise RetrieveError('SPRITE_RETRIEVE_TRANSPORT must be auto, websocket, or http-post.')
        help_result = picker.capture(['exec', '--help'], check=False)
        supports_http = '--http-post' in (help_result.stdout + help_result.stderr)
        if choice == 'http-post' and not supports_http:
            raise RetrieveError('This local Sprite CLI does not advertise --http-post; upgrade it or select websocket.')
        self.modes = (['http-post', 'websocket'] if supports_http else ['websocket']) if choice == 'auto' else [choice]
        self.mode = self.modes[0]
        self.last_status = None

    def _call(self, request, mode, timeout):
        nonce = secrets.token_hex(16)
        payload = dict(request, nonce=nonce, timeout=max(5, timeout-5))
        args = [self.cli, 'exec', *self.org, '-s', self.sprite]
        if mode == 'http-post': args.append('--http-post')
        args += ['--no-port-forward', '--', 'python3', '-c', self.code]
        local_env = os.environ.copy()
        # The local Sprites CLI needs its own login, not the separate GitHub token.
        for key in ('GITHUB_PAT', 'GH_TOKEN', 'GITHUB_TOKEN', 'FLY_API_TOKEN', 'FLY_ACCESS_TOKEN',
                    'DEEPSEEK_API_KEY', 'MINIMAX_API_KEY', 'MOONSHOT_API_KEY', 'OPENAI_API_KEY'):
            local_env.pop(key, None)
        p = None
        with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
            try:
                p = subprocess.Popen(args, cwd=self.context, env=local_env, stdin=subprocess.PIPE,
                                     stdout=output, stderr=errors, start_new_session=True)
                try:
                    p.communicate(json.dumps(payload, ensure_ascii=True).encode(), timeout=timeout)
                except subprocess.TimeoutExpired:
                    raise RetrieveError('Recovery exec timed out; command outcome is unknown. A remote operation may still be running.') from None
                output.seek(0); raw = output.read(4*1024*1024+1)
                if len(raw)>4*1024*1024:
                    raise RetrieveError('Recovery result exceeded the safe display limit; inspect the repository before retrying.')
                markers = [line[len(b'SPRITE_RETRIEVE_JSON='):] for line in raw.splitlines() if line.startswith(b'SPRITE_RETRIEVE_JSON=')]
                if len(markers)!=1:
                    raise RetrieveError('No verified recovery response (local CLI exit %s). Command outcome is unknown.'%p.returncode)
                try: result = json.loads(markers[0])
                except (ValueError, UnicodeError): raise RetrieveError('Malformed recovery response; no success is claimed.') from None
                if (not isinstance(result, dict) or result.get('nonce') != nonce or type(result.get('ok')) is not bool):
                    raise RetrieveError('Recovery response identity failed verification; no success is claimed.')
                # A matching completion marker is authoritative even if the CLI
                # later loses its exit frame. Raw stderr is never echoed (may have secrets).
                if p.returncode:
                    print('       Verified completion received despite local CLI exit %s.'%p.returncode)
                return result
            finally:
                if p is not None and p.poll() is None:
                    with contextlib.suppress(ProcessLookupError): os.killpg(p.pid, signal.SIGTERM)
                    try: p.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        with contextlib.suppress(ProcessLookupError): os.killpg(p.pid, signal.SIGKILL)
                        p.wait()

    def call(self, op, *, mutation=False, token='', **kwargs):
        modes = [self.mode]+[m for m in self.modes if m!=self.mode]
        if mutation: modes = modes[:1]
        errors = []
        timeout = self.probe_timeout if op == 'probe' else self.timeout
        for mode in modes:
            try:
                result = self._call(dict(op=op, token=token, **kwargs), mode, timeout)
            except RetrieveError as e:
                errors.append(mode+': '+str(e))
                if mutation:
                    raise RetrieveError(str(e)+' This write was NOT retried. Refresh Git status and the latest GitHub comparison before another write.') from None
                continue
            self.mode = mode
            if not result['ok']:
                message = safe(result.get('error', 'Recovery command failed.'))
                if token: message = message.replace(token, '[REDACTED]')
                raise RetrieveError(message)
            return result.get('data')
        raise RetrieveError('\n       '.join(errors)+'\n       Neither a running label nor an old TTY can guarantee exec access. No destructive restart is attempted.')

    def probe(self):
        value = self.call('probe')
        if not isinstance(value, dict) or value.get('ok') != 'SPRITE_RETRIEVE_OK':
            raise RetrieveError('Unexpected probe marker.')
        print('       Independent command access verified via '+self.mode+'. No Codex terminal was attached.')
        return value


class Retrieve:
    def __init__(self, picker, output, context, local_dir):
        self.picker, self.o, self.context, self.local_dir = picker, output, context, local_dir
        self.channel = None; self.sprite = ''; self.path = ''; self.token = ''; self.auth_repo = ''; self.user = None
        self.context_file = str(Path(context)/'.sprite')
        self.pinned = ''

    def pin(self, sprite):
        self.picker.capture(['use', *self.picker.org, sprite])
        self.sprite = sprite
        self.pinned = self.context_file if Path(self.context_file).is_file() else ''
        self.channel = Channel(self.picker, sprite)
        self.token = ''; self.auth_repo = ''; self.user = None; self.path = ''

    def wait_for_access(self):
        while True:
            print('\n=== independent recovery access — '+self.sprite, flush=True)
            print('       A fresh exec may wake a cold Sprite. It does not restart or replace an existing agent.')
            try:
                self.channel.probe()
                return True
            except RetrieveError as e:
                print('       '+str(e))
            choice = ask('  R = retry probes, S = another Sprite, Q = quit [Q]: ').lower()
            if choice=='r': continue
            if choice=='s': return False
            raise Cancelled()

    def folder_picker(self):
        # Reuse the non-secret browser with the independently tested transport.
        org = self.picker.org[1] if self.picker.org else ''
        folder = self.o.FolderPicker(self.sprite, org, self.pinned)
        folder.transport = self.channel.mode
        folder.timeout = min(self.channel.timeout, 300)
        return folder

    def select_repository(self, start='~'):
        folder = self.folder_picker(); path = start or '~'; page=0; hidden=False
        while True:
            print('\n=== choose existing Git repository — '+self.sprite, flush=True)
            info = None
            try:
                info = folder.request(path, page=page, hidden=hidden); path=info['path']; page=info['page']
                print('       REMOTE: '+safe(path))
                for i,name in enumerate(info['folders'],1): print('    %d) %s/'%(i,safe(name)))
                if info['files']:
                    print('       Files: '+', '.join(safe(x['name']) for x in info['files']))
                if info['pages']>1: print('       Page %s/%s (N next / B previous)'%(page+1,info['pages']))
            except self.o.DownloadError as e:
                print('       '+str(e))
            print('       Number = open folder | G = use repository here | W = workspace shortcuts')
            print('       U = parent | H = home | / = root | P = path | T = hidden | R = refresh | Q = back')
            c=ask('  Repository action: ').lower()
            if c in ('','q'): raise Cancelled()
            if c=='g' and info:
                try:
                    s=self.channel.call('status', path=path)
                    print('       Git root: '+safe(s['root'])+'\n       Origin: '+safe(s['origin']))
                    if ask('  Use this repository? [y/N]: ').lower() not in ('y','yes'): continue
                    self.path=s['root']; self.token=''; self.auth_repo=''; self.user=None
                    return
                except RetrieveError as e: print('       '+str(e))
            elif c=='w':
                try:
                    target=folder.places()
                    if target: path=target; page=0
                except self.o.DownloadError as e: print('       '+str(e))
            elif c=='u': path=str(PurePosixPath(path).parent) if path.startswith('/') else '~'; page=0
            elif c=='h': path='~'; page=0
            elif c=='/': path='/'; page=0
            elif c=='p':
                target=ask('  Existing absolute or ~/ directory: ')
                if target: path=target; page=0
            elif c=='t': hidden=not hidden; page=0
            elif c in ('n','b') and info: page=min(info['pages']-1,page+1) if c=='n' else max(0,page-1)
            elif c=='r': pass
            elif info and c.isdecimal() and 1<=int(c)<=len(info['folders']):
                path=str(PurePosixPath(path)/info['folders'][int(c)-1]); page=0
            else: print('       Select a displayed action. No folder is created or replaced.')

    def show_status(self):
        s=self.channel.call('status',path=self.path)
        print('\n       Repository: '+safe(s['root'])+'\n       Origin: '+safe(s['origin']))
        print('       Branch: '+safe(s['branch'] or '(detached HEAD)')+' | HEAD: '+safe(s['head'] or '(no commit)'))
        print('       %s tracked/non-ignored paths; %s changed entries.'%(s['files'],len(s['changes'])))
        for r in s['changes'][:200]: print('         '+safe(r['status'])+' '+safe(r['path']))
        if len(s['changes'])>200: print('       Display capped at 200 changes. Use advanced git status to narrow inspection.')
        if s['operation']: print('       Git operation/lock: '+', '.join(s['operation']))
        print('       Ignored/untracked secrets are NOT a Git backup. This status has not fetched GitHub.')
        print('       Review contents privately before publishing. Basic secret checks are not exhaustive.')
        return s

    def authenticate(self, s=None):
        s=s or self.channel.call('status',path=self.path)
        if not s['repo']: raise RetrieveError('Origin is not a supported github.com repository; no remote is rewritten.')
        if self.token and self.auth_repo==s['repo']: return
        print('\n       GitHub target: '+safe(s['repo']))
        print('       Only a repository-scoped GitHub PAT is needed. No Fly or model key is requested.')
        print('       The PAT stays in this recovery process and remote command environments; not on disk or in command arguments.')
        # Reuse only a local token the user explicitly supplies to this invocation,
        # never /proc or the dead agent's environment.
        candidate=os.environ.get('GITHUB_PAT') or os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN') or ''
        if candidate and ask('  Use the GitHub token already in this LOCAL environment? [y/N]: ').lower() not in ('y','yes'):
            candidate=''
        while True:
            if not candidate:
                with warnings.catch_warnings():
                    warnings.simplefilter('error', getpass.GetPassWarning)
                    try:
                        candidate=getpass.getpass('  GitHub PAT (hidden; Enter cancels): ')
                    except getpass.GetPassWarning:
                        raise RetrieveError('Hidden token entry is unavailable; no echoed fallback is allowed.') from None
            if not candidate: raise Cancelled()
            try:
                user=self.channel.call('auth',path=self.path,token=candidate,repo=s['repo'])
            except RetrieveError as e:
                print('       '+str(e).replace(candidate,'[REDACTED]')); candidate=''
                if ask('  Enter a replacement token? [y/N]: ').lower() in ('y','yes'): continue
                raise Cancelled()
            self.token=candidate; self.auth_repo=s['repo']; self.user=user
            print('       GitHub user '+safe(user['login'])+' verified for '+safe(user['repo'])+'.')
            print('       '+safe(user['note']))
            return

    def receipt(self, result, opid):
        # Local receipt is deliberately non-secret. Worktree files are not copied here.
        fd,name=tempfile.mkstemp(prefix='sprite-retrieve-'+self.sprite+'-',suffix='.json',dir=self.local_dir)
        with os.fdopen(fd,'w') as f:
            json.dump({**result, 'sprite':self.sprite, 'operation_id':opid},f,indent=2,ensure_ascii=True); f.write('\n')
        print('       Recovery receipt: '+safe(name))

    def report_push(self, r, opid):
        self.receipt(r,opid)
        print('       Branch: '+safe(r.get('branch',''))+'\n       Commit: '+safe(r.get('commit','')))
        if r.get('status')=='verified_on_github':
            print('       VERIFIED: GitHub currently advertises this exact commit on that branch.')
        else:
            print('       SAVED ON SPRITE ONLY. GitHub backup has NOT been verified.')
            if r.get('push_error'): print('       '+safe(r['push_error']))
            print('       Use Publish saved recovery branch to inspect/retry without creating another commit.')
        if r.get('source_changed_after_capture'):
            print('       Source changed after capture. This does NOT back up those later edits.')
        if r.get('uncommitted_files_not_included'):
            print('       Uncommitted/staged files were NOT included in this current-branch push.')

    def snapshot(self):
        s=self.show_status(); self.authenticate(s)
        opid=secrets.token_hex(16)
        branch='sprite-recovery/'+self.sprite+'-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())+'-'+opid[:8]
        print('\n=== save current work to a NEW recovery branch')
        print('       Target: '+safe(s['repo'])+' / '+branch)
        print('       Includes current tracked files/deletions and non-ignored untracked files.')
        print('       Preserves the original branch, HEAD and staging index. Does not pull, reset, checkout, merge, or stop Codex.')
        print('       Staged-only versions overwritten in the working tree are not a separate backup. Ignored files require ZIP.')
        print('       This is a recovery commit, not an update to main. Commit hooks/signing are bypassed for this snapshot only.')
        print('       Finish writers first. Submodules, LFS, sparse checkouts and unfinished Git operations need manual handling.')
        if ask('  Type BACKUP to confirm this GitHub write, or Enter to cancel: ')!='BACKUP': return
        message=ask('  Commit message [Recover Sprite workspace]: ') or 'Recover Sprite workspace'
        name=s['identity_name'] or (self.user['login'] if self.user else '')
        email=s['identity_email'] or (self.user['id']+'+'+self.user['login']+'@users.noreply.github.com')
        print('       Commit identity: '+safe(name)+' <'+safe(email)+'>')
        if ask('  Use this identity? [Y/n]: ').lower() in ('n','no'):
            name=ask('  Author name: '); email=ask('  Author email: ')
        print('       Request ID: '+opid+'; intended branch: '+branch,flush=True)
        r=self.channel.call('snapshot',mutation=True,path=self.path,token=self.token,repo=self.auth_repo,
                            expected=s['fingerprint'],opid=opid,branch=branch,message=message,author_name=name,author_email=email)
        self.report_push(r,opid)
        print('       The normal branch was not moved. Merge/review the recovery branch separately.')

    def publish_saved(self):
        refs=self.channel.call('refs',path=self.path)
        if not refs: print('       No saved sprite-recovery/ branches were found.'); return
        for i,r in enumerate(refs,1): print('    %d) %s  %s'%(i,safe(r['branch']),r['commit']))
        c=ask('  Saved branch number; Enter cancels: ')
        if not c.isdecimal() or not 1<=int(c)<=len(refs): return
        r=refs[int(c)-1]; self.authenticate()
        if ask('  Verify/publish this exact saved commit to GitHub? Type PUSH: ')!='PUSH': return
        value=self.channel.call('publish',mutation=True,path=self.path,token=self.token,repo=self.auth_repo,**r)
        self.report_push(value,secrets.token_hex(16))

    def push_current(self):
        s=self.show_status(); self.authenticate(s)
        print('       Push EXISTING HEAD to '+safe(s['repo'])+' branch '+safe(s['branch'] or '(detached)'))
        print('       This does NOT commit staged/uncommitted files. No force-push or automatic pull/merge.')
        if ask('  Type PUSH to confirm, or Enter to cancel: ')!='PUSH': return
        r=self.channel.call('push_current',mutation=True,path=self.path,token=self.token,repo=self.auth_repo,expected=s['fingerprint'])
        self.report_push(r,secrets.token_hex(16))

    def zip(self):
        folder=self.folder_picker()
        path,checks=folder.choose(self.local_dir,self.path or '~')
        key='SPRITE_DOWNLOAD_TRANSPORT'; old=os.environ.get(key); os.environ[key]=self.channel.mode
        try:
            self.o.download(self.sprite,path,self.local_dir,self.picker.org[1] if self.picker.org else '',self.pinned,checks=checks)
        finally:
            if old is None: os.environ.pop(key,None)
            else: os.environ[key]=old
        print('       ZIP is a file export, not a GitHub sync. Symlinks/special files are skipped; linked-worktree external Git metadata may be outside the chosen folder.')

    def git_console(self):
        print('\n=== advanced Git command console (independent NON-TTY exec)')
        print('       Each command runs ONCE in '+safe(self.path)+'. No Bash syntax, cd, pager, or interactive editor.')
        print('       Use full commands such as git status or git commit -m "Recovery". Q returns to the menu.')
        print('       Commands can change/delete files and refs AS TYPED. Nothing is automatically undone or retried.')
        print('       Do not paste tokens. Origins on github.com use temporary credentials, not saved global configuration.')
        while True:
            line=ask('  git> ')
            if line.lower() in ('','q','quit'): return
            try: args=shlex.split(line)
            except ValueError: print('       Unbalanced quotes.'); continue
            if args and args[0]=='git': args=args[1:]
            if not args or args[0] not in {'status','diff','log','show','rev-parse','ls-files','ls-remote','reflog','fetch','add','commit','push','pull','merge','rebase','cherry-pick','branch','restore','reset','rm','mv','stash'}:
                print('       Unsupported command. Use a normal Git subcommand, not a shell/global Git option.'); continue
            if any(x in args for x in (';', '&&', '|', '>', '<')):
                print('       Shell operators are not supported.'); continue
            if args[0] not in {'status','diff','log','show','rev-parse','ls-files','ls-remote','reflog'}: self.authenticate()
            print('       RUN ON '+safe(self.sprite)+': '+safe(shlex.join(['git',*args])))
            if ask('  Execute this exact command? Type RUN: ')!='RUN': continue
            try:
                r=self.channel.call('command',mutation=True,path=self.path,token=self.token,repo=self.auth_repo,args=args,confirmed=True)
                print(safe(r['stdout'])); print(safe(r['stderr'])); print('       Git exit: '+str(r['exit']))
            except RetrieveError as e:
                print('       '+str(e)); print('       Refresh status before retrying a write.')

    def menu(self):
        while True:
            print('\n=== retrieve / Git recovery — '+self.sprite)
            print('       Repository: '+safe(self.path)+'\n       Local downloads/receipts: '+safe(self.local_dir))
            print('    1) Inspect Git status and changed filenames')
            print('    2) Save current work to a NEW recovery branch on GitHub')
            print('    3) Publish / verify a saved recovery branch')
            print('    4) Push current branch\'s EXISTING commits (does not commit files)')
            print('    5) Download a folder as a ZIP (no GitHub token needed)')
            print('    6) Advanced Git command console (independent non-TTY commands)')
            print('    7) Check command access, disk space and process names')
            print('    8) Select another existing repository')
            print('    9) Choose another Sprite')
            print('    0) Quit (leave Sprite and Codex untouched)')
            c=ask('  Recovery action: ')
            if c in ('','0','q'): return
            try:
                if c=='1': self.show_status()
                elif c=='2': self.snapshot()
                elif c=='3': self.publish_saved()
                elif c=='4': self.push_current()
                elif c=='5': self.zip()
                elif c=='6': self.git_console()
                elif c=='7':
                    self.channel.probe(); d=self.channel.call('diagnostics')
                    print('       Free bytes: '+str(d['free_bytes'])+'\n'+safe(d['processes'])+'\n       '+safe(d['note']))
                elif c=='8': self.select_repository(self.path)
                elif c=='9': return 'another'
                else: print('       Select a displayed number.')
            except (RetrieveError,self.o.DownloadError) as e: print('error: '+str(e))
            except (Cancelled,self.o.FolderCancelled): print('       Action cancelled; earlier completed work remains.')


# v57: the interactive path is repo-first. Legacy v56 backup primitives above
# remain available for compatibility/tests, but are not the default Retrieve UI.
def local_target_authorization():
    module = {'__name__': 'sprite_retrieve_authorization'}
    exec(compile(REMOTE_RETRIEVE_PY, 'retrieve-authorization', 'exec'), module)
    print('\n=== retrieve: choose GitHub destination first')
    default = os.environ.get('GITHUB_REPOSITORY', '')
    while True:
        value = ask('  GitHub repository (OWNER/REPO or URL)' + (' ['+safe(default)+']' if default else '') + ': ') or default
        if not value: raise Cancelled()
        try: repo = module['normalize_target'](value)
        except module['RecoveryError'] as e:
            print('       '+safe(e)); default = ''; continue
        break
    print('       Use a PAT scoped to '+safe(repo)+' with Contents: read and write.')
    print('       Token entry is hidden. No credentials are written into Git configuration or URLs.')
    candidate = os.environ.get('GITHUB_PAT') or os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN') or ''
    if candidate and ask('  Use the GitHub token in this LOCAL environment? [y/N]: ').lower() not in ('y','yes'):
        candidate = ''
    while True:
        if not candidate:
            with warnings.catch_warnings():
                warnings.simplefilter('error', getpass.GetPassWarning)
                try: candidate = getpass.getpass('  GitHub PAT (hidden; Enter cancels): ')
                except getpass.GetPassWarning:
                    raise RetrieveError('Hidden token entry is unavailable; no echoed fallback is allowed.') from None
        if not candidate: raise Cancelled()
        module['TOKEN'] = candidate
        try:
            user = module['authorize_target'](repo, candidate)
        except (module['RecoveryError'], OSError, ValueError) as e:
            print('       '+module['redact'](e)); candidate = ''; module['TOKEN'] = ''
            if ask('  Enter another PAT? [y/N]: ').lower() in ('y','yes'): continue
            raise Cancelled()
        print('       Verified '+safe(user['login'])+' for '+safe(repo)+'.')
        print('       '+safe(user['note']))
        module['TOKEN'] = ''
        return repo, candidate, user


class RepositorySync(Retrieve):
    def pin(self, sprite):
        authorized = self.auth_repo, self.token, self.user
        super().pin(sprite)
        self.auth_repo, self.token, self.user = authorized
        self.target_branch = ''

    def discover(self, start=''):
        roots = None
        while True:
            print('\n=== search Sprite disk for '+safe(self.auth_repo), flush=True)
            print('       Matches use the GitHub origin, not folder names. No clone, overlay or Codex attach.')
            result = self.channel.call('discover', repo=self.auth_repo, start=start, roots=roots)
            print('       Searched %d accessible directories; %d matching checkout(s).'%(result['scanned'],len(result['matches'])))
            print('       Roots: '+', '.join(safe(p) for p in result['roots']))
            if result['limited'] or result['unreadable']:
                print('       Search was limited or some paths were unreadable; this is NOT an exhaustive whole-disk search.')
            print('       '+safe(result['note']))
            rows = result['matches']
            for i, row in enumerate(rows, 1):
                print('    %d) %s'%(i,safe(row['root'])))
                print('       Branch: %s | HEAD: %s'%(safe(row['branch'] or '(detached)'),safe(row['head'] or '(no commit)')))
            if not rows:
                print('       No matching checkout found in this search. Nothing will be created or copied over.')
            answer = ask('  Checkout number; R = rescan, P = search another folder, S = another Sprite, Q = quit: ')
            if answer.lower() in ('','q'): raise Cancelled()
            if answer.lower()=='s': return False
            if answer.lower()=='r': continue
            if answer.lower()=='p':
                root = ask('  Search under existing absolute or ~/ folder: ')
                if root: roots=[root]; start=''
                continue
            if not answer.isdecimal() or not 1 <= int(answer) <= len(rows):
                print('       Choose a listed checkout.'); continue
            row = rows[int(answer)-1]
            current = self.channel.call('status', path=row['root'])
            if current['repo'].lower() != self.auth_repo.lower():
                print('       Origin changed after discovery. Rescan before selecting.'); continue
            print('       Source: '+safe(current['root'])+' on '+safe(self.sprite))
            print('       GitHub repository: '+safe(self.auth_repo))
            print('       Local branch: '+safe(current['branch'] or '(detached HEAD)'))
            if ask('  Use this checkout? [y/N]: ').lower() not in ('y','yes'): continue
            self.path = current['root']
            default = current['branch'] or (self.user or {}).get('default_branch') or 'main'
            self.target_branch = ask('  Target GitHub branch ['+safe(default)+']: ') or default
            return True

    def review_sync(self):
        print('\n=== fetch and compare with the current GitHub branch tip', flush=True)
        print('       Fetch/analysis may add Git objects, but does not commit, alter the normal index, or push.')
        plan = self.channel.call('sync_plan', path=self.path, repo=self.auth_repo, token=self.token, branch=self.target_branch)
        print('       Source checkout: '+safe(plan['root']))
        print('       Local branch: '+safe(plan['branch'])+' | HEAD: '+safe(plan['head'] or '(none)'))
        print('       Destination: '+safe(self.auth_repo)+' / '+safe(plan['target_branch']))
        print('       Latest GitHub commit: '+safe(plan['remote_latest']))
        print('       Local-only commits: %d | GitHub-only commits: %d | Uncommitted entries: %d' %
              (plan['ahead'],plan['behind'],len(plan['changes'])))
        if plan['local_only']: print('\n       Local commits not yet on the target (up to 20):\n'+safe(plan['local_only']))
        if plan['remote_only']: print('\n       GitHub commits not yet in the checkout (up to 20):\n'+safe(plan['remote_only']))
        if plan['changes']:
            print('\n       Pending files (tracked changes/deletions and non-ignored untracked files):')
            for row in plan['changes'][:300]: print('         '+safe(row['status'])+' '+safe(row['path']))
            if len(plan['changes'])>300: print('       Display limited to 300 entries; use the advanced console for more detail.')
        if plan['change_summary']: print('\n'+safe(plan['change_summary']))
        if plan['summary_truncated']: print('       File summary truncated; review more detail in the advanced console.')
        if plan['no_op']:
            print('\n       UP TO DATE at this check: the branch tips match and there are no uncommitted Git changes.')
            print('       No commit or push was needed. Ignored files and other branches are outside this check.')
            return
        print('\n=== approve synchronization')
        print('       Destination is the selected branch, NOT a new sprite-recovery/ branch.')
        print('       Commit all final working-file changes with git add -A, then push unpublished commits.')
        print('       Ignored files are excluded; staged-only versions are replaced by final working-file versions.')
        if plan['behind']:
            print('       GitHub has newer commits: approval also permits fast-forwarding or a normal merge before push.')
            print('       Conflicts stop publication; no automatic conflict resolution, rebase, reset, or force-push.')
        if not plan['remote_commit']:
            print('       The target GitHub branch does not exist: approval will create that branch, preserving local history.')
        if plan['branch'] != plan['target_branch']:
            print('       Local '+safe(plan['branch'])+' will publish to GitHub '+safe(plan['target_branch'])+'; this mapping is explicit.')
        name = plan['identity_name'] or self.user['login']
        email = plan['identity_email'] or self.user['id']+'+'+self.user['login']+'@users.noreply.github.com'
        print('       Commit identity: '+safe(name)+' <'+safe(email)+'>')
        print('       Guided sync disables Git hooks/signing. Basic secret checks are not exhaustive.')
        print('       Stop file writers first. This does not pause Codex; changes after review cause a stop when detected.')
        if ask('  Type SYNC to commit/integrate/push this plan, or Enter to cancel: ') != 'SYNC':
            print('       Sync cancelled. No commit, merge, or push was requested.'); return
        message = (ask('  Commit message [Sync Sprite changes to GitHub]: ') or 'Sync Sprite changes to GitHub') if plan['needs_commit'] else 'Sync Sprite changes to GitHub'
        opid = secrets.token_hex(16)
        print('       Sync operation ID: '+opid, flush=True)
        result = self.channel.call('sync_apply', mutation=True, path=self.path, repo=self.auth_repo, token=self.token,
            branch=plan['target_branch'], source_branch=plan['branch'], source_head=plan['head'],
            expected=plan['fingerprint'], candidate_tree=plan['candidate_tree'], remote_commit=plan['remote_commit'],
            allow_merge=bool(plan['behind']), confirmed=True, opid=opid, message=message,
            author_name=name, author_email=email)
        try:
            self.receipt(result, opid)
        except OSError:
            print('       Warning: local receipt could not be saved; the verified remote result is reported below.')
        print('       Phase: '+safe(result.get('phase',''))+' | Commit: '+safe(result.get('commit','')))
        if result['status']=='verified_on_github':
            print('       VERIFIED: GitHub '+safe(result['repo'])+' branch '+safe(result['branch'])+' advertises this exact commit.')
            if result.get('source_changed_after_sync'):
                print('       The checkout has changed again; this does NOT cover those later changes. Re-run comparison.')
            else: print('       Checked-out HEAD matches that commit and no uncommitted Git changes were found at final verification.')
        else:
            print('       NOT VERIFIED ON GITHUB. Any completed local staging/commits/merge remain on the Sprite.')
            print('       '+safe(result.get('error','Inspect Git status and the saved operation receipt.')))
            print('       Refresh comparison before retrying. No write is replayed automatically.')

    def menu(self):
        pending = True
        while True:
            if pending:
                try: self.review_sync()
                except RetrieveError as exc: print('error: '+safe(exc))
                pending = False
            print('\n=== retrieve / repository sync — '+safe(self.sprite))
            print('    R) Refresh GitHub comparison and offer synchronization')
            print('    F) Find another checkout of this same GitHub repository')
            print('    G) Choose a different GitHub repository / PAT')
            print('    S) Choose another Sprite')
            print('    A) Advanced Git command console')
            print('    Z) Download a folder ZIP instead')
            print('    Q) Quit (do not stop Sprite or Codex)')
            action = ask('  Retrieve action [Q]: ').lower()
            try:
                if action in ('','q','0'): return 'done'
                if action=='r': pending=True
                elif action=='f':
                    if not self.discover(): return 'another'
                    pending=True
                elif action=='g': return 'target'
                elif action=='s': return 'another'
                elif action=='a': self.git_console()
                elif action=='z': self.zip()
                else: print('       Choose a displayed action.')
            except (RetrieveError,self.o.DownloadError) as exc: print('error: '+safe(exc))
            except (Cancelled,self.o.FolderCancelled): print('       Action cancelled; earlier completed writes remain.')


def main():
    if sys.version_info<(3,9): raise RetrieveError('Local Python 3.9+ is required.')
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise RetrieveError('Retrieve mode requires an interactive local terminal for review/confirmation; no remote action was started.')
    sources,local_dir,start=sys.argv[1:4]
    a=SimpleNamespace(**runpy.run_path(str(Path(sources)/'picker.py')))
    o=SimpleNamespace(**runpy.run_path(str(Path(sources)/'output.py')))
    print('\n=== Retrieve: sync the repository on Sprite disk, without attaching to Codex')
    print('       Repo -> PAT validation -> Sprite -> matching checkout -> latest GitHub comparison -> approval.')
    print('       Persisted files/commits are used; memory-only work cannot be recovered.')
    try:
        # Ask/validate GitHub BEFORE the first Sprite selection or remote command.
        authorized=local_target_authorization()
        with tempfile.TemporaryDirectory(prefix='sprite-retrieve-context-') as context:
            picker=a.Picker(context,selection_only=True)
            r=RepositorySync(picker,o,context,local_dir)
            r.auth_repo,r.token,r.user=authorized
            requested=os.environ.get('SPRITE_NAME','')
            while True:
                r.pin(picker.choose_sprite(requested)); requested=''
                if not r.wait_for_access(): continue
                if not r.discover(start): start=''; continue
                start=''
                result=r.menu()
                if result=='target':
                    r.auth_repo,r.token,r.user=local_target_authorization()
                    requested=r.sprite
                    continue
                if result!='another': return 0
    except a.AttachError as e:
        raise RetrieveError(str(e)) from None
    except (a.Cancelled,Cancelled,o.FolderCancelled):
        print('       Retrieve closed. No Sprite/agent was stopped; completed writes remain.')
        return 0

if __name__=='__main__':
    try: raise SystemExit(main())
    except KeyboardInterrupt:
        print('\n       Recovery interrupted. Do not assume a pending Git write was rolled back; inspect status before retrying.',file=sys.stderr)
        raise SystemExit(130)
    except (RetrieveError,OSError) as e:
        print('error: '+safe(e),file=sys.stderr)
        raise SystemExit(1)
RETRIEVE_PY
}

run_retrieve() (
  command -v python3 >/dev/null 2>&1 || { echo "error: local python3 is required" >&2; exit 127; }
  local_sources=$(mktemp -d)
  trap 'rm -rf -- "$local_sources"' EXIT
  attach_only_python >"$local_sources/picker.py"
  output_download_python >"$local_sources/output.py"
  # Source is secret-free; credentials enter only the interactive helper in memory.
  retrieve_python >"$local_sources/retrieve.py"
  python3 "$local_sources/retrieve.py" "$local_sources" "$OUTPUT_HOST_DIR" "$FILE_WORKDIR"
)

if [[ $RUN_MODE == retrieve ]]; then
  if [[ -n $ATTACH_SESSION_ID ]] || (( _OUTPUT_DIR_SELECTED == 1 || _JSON_OUTPUT_SELECTED == 1 )); then
    echo "error: --retrieve does not accept --session-id, --output-dir, or --json-output" >&2; exit 2
  fi
  if run_retrieve; then exit 0; else exit $?; fi
fi

if (( _FILE_WORKDIR_SELECTED == 1 )) && [[ $RUN_MODE != files ]]; then
  echo "error: --workdir requires --files/--shell or --retrieve (or opening menu choice 5/6)" >&2; exit 2
fi
if [[ $RUN_MODE == files ]]; then
  if (( _OUTPUT_DIR_SELECTED == 1 )); then
    echo "error: --files always uses the selected workspace/output; --output-dir belongs to --download-output or agent modes" >&2; exit 2
  fi
  if [[ -n $ATTACH_SESSION_ID && $_FILE_WORKDIR_SELECTED == 1 ]]; then
    echo "error: select --session-id OR --workdir, not both" >&2; exit 2
  fi
  # An exact session overrides an inherited bootstrap workspace hint.
  [[ -z $ATTACH_SESSION_ID ]] || FILE_WORKDIR=""
  if run_file_access; then exit 0; else exit $?; fi
fi

if [[ $RUN_MODE == attach || $RUN_MODE == download ]]; then
  # Keep only the selected Sprite name in a transient, non-secret local receipt.
  # The picker may choose another Sprite; never assume the original env name won.
  _selection_receipt=$(mktemp)
  trap 'rm -f -- "${_selection_receipt:-}" "${_selection_receipt:-}.context"' EXIT
  if run_attach_only "$_selection_receipt"; then _attach_rc=0; else _attach_rc=$?; fi
  _output_sprite=""
  if [[ -s $_selection_receipt ]]; then
    _output_sprite=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sprite"])' "$_selection_receipt") || _output_sprite=""
  fi
  rm -f -- "$_selection_receipt"
  [[ ! -f $_selection_receipt.context ]] || OUTPUT_PINNED_CONTEXT="$_selection_receipt.context"
  if [[ -n $_output_sprite ]]; then
    if [[ $RUN_MODE == download ]]; then
      if run_output_download "$_output_sprite" always; then exit 0; else exit $?; fi
    else
      maybe_download_output "$_output_sprite" "$_attach_rc"
    fi
  fi
  exit "$_attach_rc"
fi

case "$MODEL_TEST_MODE" in ask|always|never) ;; *) echo "error: MODEL_TEST_MODE must be ask, always or never" >&2; exit 2 ;; esac

MOBBIN_MCP_MODE="${MOBBIN_MCP_MODE:-ask}"
MOBBIN_MCP_LOGIN="${MOBBIN_MCP_LOGIN:-ask}"
MOBBIN_MCP_LOGIN_TIMEOUT="${MOBBIN_MCP_LOGIN_TIMEOUT:-300}"
for _mobbin_setting in MOBBIN_MCP_MODE MOBBIN_MCP_LOGIN; do
  case "${!_mobbin_setting}" in
    ask|always|never) ;;
    *) echo "error: $_mobbin_setting must be ask, always, or never" >&2; exit 2 ;;
  esac
done
[[ $MOBBIN_MCP_LOGIN_TIMEOUT =~ ^[1-9][0-9]{0,3}$ ]] && (( MOBBIN_MCP_LOGIN_TIMEOUT <= 1800 )) || {
  echo "error: MOBBIN_MCP_LOGIN_TIMEOUT must be 1..1800 seconds" >&2; exit 2;
}
MOBBIN_MCP_DECIDED=0
MOBBIN_MCP_SELECTED=0
MOBBIN_MCP_DONE=0
MOBBIN_MCP_HELPER=""

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
      note "$context: opening the saved-conversation picker: codex resume"
      return 0
      ;;
    fork)
      CODEX_START_ACTION=fork
      CODEX_MODE_SELECTED=1
      note "$context: opening the saved-conversation fork picker: codex fork"
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
  printf '    1) Resume a saved conversation (choose in Codex)\n'
  printf '    2) Fork a saved conversation (choose in Codex; new writable thread)\n'
  printf '    3) Start a new Codex conversation [default]\n'
  printf '  Select [1-3]: '
  IFS= read -r choice || true
  case "${choice,,}" in
    1|r|resume)
      CODEX_START_ACTION=resume
      note "Codex will run: codex resume"
      if [[ $CODEX_PROVIDER == deepseek ]]; then
        note "resume replays the conversation you select through the selected DeepSeek native Responses provider"
      elif [[ $CODEX_PROVIDER == kimi ]]; then
        note "resume replays the conversation you select through the selected Moonshot native Responses provider"
      elif [[ $CODEX_PROVIDER == minimax ]]; then
        note "resume uses the MiniMax native Responses provider selected for this run"
      else
        note "resume uses the normal OpenAI Codex provider selected for this run"
      fi
      ;;
    2|f|fork)
      CODEX_START_ACTION=fork
      note "Codex will run: codex fork"
      note "the selected conversation history is preserved under a new writable thread ID"
      note "select the intended source conversation; forking creates a separate thread, not a reattachment"
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
    local clean_out
    clean_out=$(mktemp)
    if sed '/^__SPRITE_CODEX_REMOTE_RC__=[0-9][0-9]*$/d' "$out_file" >"$clean_out"; then
      cat "$clean_out" >"$out_file"
    fi
    rm -f -- "$clean_out"
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
  local name=$1 kind=$2 fly_scope=""
  # Changing the Fly app must invalidate Fly approval, not an unrelated GitHub
  # credential that was already validated earlier in this invocation.
  [[ $kind != fly ]] || fly_scope=${FLY_APP:-}
  printf '%s\0' "$kind" "${!name:-}" "$SPRITE_NAME" "${SPRITE_ORG:-}" \
    "${GITHUB_REPOSITORY:-}" "$fly_scope" \
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
  local name=$1 kind=$2 operation=${3:-check} repair_ticket=${4:-} nonce packed output cli_rc=0 parsed_rc=1 result_file
  local SPRITE_FLY_CONFIG_ACTION=$operation SPRITE_FLY_CONFIG_RECEIPT=$repair_ticket
  TOKEN_LAST_FLY_REPAIR=""
  TOKEN_LAST_CATEGORY=""
  [[ $operation == check || ( $operation == repair && $kind == fly && -n $repair_ticket ) ]] || return 2
  local -a names=("$name" TOKEN_CHECK_TIMEOUT)
  if [[ $kind == fly ]]; then
    names+=(SPRITE_FLY_CONFIG_ACTION)
    [[ $operation != repair ]] || names+=(SPRITE_FLY_CONFIG_RECEIPT)
  fi
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
  result_file=$(mktemp) || return 1
  cleanup_files+=("$result_file")
  if printf '%s' "$output" | python3 -c '
import json, re, sys
kind, nonce, name, cli_rc, operation, result_file = sys.argv[1:]
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
    if category == "config-repaired" and (operation != "repair" or kind != "fly"):
        raise ValueError()
    if operation == "repair" and row["passed"]:
        raise ValueError()
    repair_ticket = row.get("fly_config_repair", "")
    if (not isinstance(repair_ticket, str) or (repair_ticket and
        (kind != "fly" or category != "cli-config-parse" or operation != "check" or
         not re.fullmatch(r"[a-f0-9]{2,16384}", repair_ticket)))):
        raise ValueError()
    diagnostics = row.get("diagnostics", [])
    if (not isinstance(diagnostics, list) or len(diagnostics) > 16 or
        any(not isinstance(d, str) or not d.isascii() or len(d) > 600 or
            not all(c.isprintable() for c in d) for d in diagnostics) or
        (diagnostics and kind != "fly")):
        raise ValueError()
except (ValueError, TypeError, KeyError):
    print("       FAIL %s: Sprite did not confirm this validation request (transport rc=%s). No token was accepted." % (name, cli_rc))
    raise SystemExit(1)
with open(result_file, "w", encoding="utf-8") as f:
    json.dump({"category": category, "ticket": repair_ticket}, f)
label = "DONE" if category == "config-repaired" else ("PASS" if row["passed"] else "FAIL")
print("       %s %s [%s]: %s" % (label, name, category, detail))
for diagnostic in diagnostics:
    print("       Fly diagnostic: " + diagnostic)
raise SystemExit(0 if row["passed"] or category == "config-repaired" else (130 if category == "interrupted" else 1))
' "$kind" "$nonce" "$name" "$cli_rc" "$operation" "$result_file"; then
    parsed_rc=0
  else
    parsed_rc=$?
  fi
  if [[ -s $result_file ]]; then
    local -a result_values=()
    mapfile -t result_values < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["category"]); print(d["ticket"])' "$result_file")
    TOKEN_LAST_CATEGORY=${result_values[0]:-}
    TOKEN_LAST_FLY_REPAIR=${result_values[1]:-}
  fi
  rm -f -- "$result_file"
  return "$parsed_rc"
}

# Disable echo before publishing the prompt, not only when read starts.  A fast
# paste or automated terminal may send input as soon as the prompt is visible.
# The subshell owns restoration traps; it does not alter the caller's traps.
read_hidden_credential() (
  local prompt=$1 value terminal_state
  [[ -t 0 ]] || return 1
  terminal_state=$(stty -g) || return 1
  stty -echo || return 1
  trap 'stty "$terminal_state" 2>/dev/null || true' EXIT
  trap 'exit 130' INT
  trap 'exit 129' HUP
  trap 'exit 143' TERM
  printf '%s' "$prompt" >&2
  if ! IFS= read -r value; then printf '\n' >&2; return 1; fi
  printf '\n' >&2
  printf '%s' "$value"
)

prompt_validated_secret() {
  local name=$1 label=$2 kind=$3 fingerprint choice rc entered_secret target_app repair_ticket confirmation
  fingerprint=$(credential_fingerprint "$name" "$kind") || die "cannot fingerprint credential context"
  if [[ -n ${!name:-} && ${TOKEN_VALIDATED[$name]:-} == "$fingerprint" ]]; then
    note "$name already verified for this Sprite and target in this run"
    return 0
  fi
  while :; do
    if [[ -z ${!name:-} ]]; then
      [[ -t 0 ]] || die "$name is required; no interactive terminal is available"
      if ! entered_secret=$(read_hidden_credential "  $label, hidden (Enter aborts): "); then
        die "credential entry cancelled; no new agent launched"
      fi
      printf -v "$name" '%s' "$entered_secret"
      unset entered_secret
      [[ -n ${!name:-} ]] || die "credential entry cancelled; no new agent launched"
    fi
    if [[ $kind == fly ]]; then
      note "Fly target: app=$FLY_APP; command host: Sprite=$SPRITE_NAME"
      note "checking app access, not testing whether the Sprite is running"
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
      if [[ $kind == fly && ${TOKEN_LAST_CATEGORY:-} == cli-config-parse ]]; then
        printf '\n  Fly configuration must be addressed; this is not a rejected-token result.\n'
      else
        printf '\n  %s did not pass validation.\n' "$name"
      fi
      if [[ $kind == fly ]]; then
        printf '    1) Enter a replacement token\n    2) Retry the same token [default]\n    3) Abort without launching\n    4) Change the target Fly app (keep this token)\n'
        printf '    5) Back up/reset diagnosed corrupt Fly config (confirmation required)\n'
        printf '  Select [1-5]: '
      else
        printf '    1) Enter a replacement token [default]\n    2) Retry the same token\n    3) Abort without launching\n'
        printf '  Select [1-3]: '
      fi
      IFS= read -r choice || die "credential validation cancelled; no new agent launched"
      case "${choice,,}" in
        '') [[ $kind == fly ]] || printf -v "$name" '%s' ''; break ;;
        1|n|new|replace) printf -v "$name" '%s' ''; break ;;
        2|r|retry) break ;;
        3|a|abort|q|quit) die "credential validation cancelled; no new agent launched" ;;
        4|app|target)
          if [[ $kind != fly ]]; then warn "invalid selection"; continue; fi
          printf '  Target Fly app [%s] (not necessarily the Sprite name): ' "$FLY_APP"
          IFS= read -r target_app || die "Fly target selection cancelled; no new agent launched"
          target_app=${target_app:-$FLY_APP}
          if [[ ! $target_app =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
            warn "invalid Fly app name; token and target are unchanged"; continue
          fi
          FLY_APP=$target_app
          label="Fly.io token for $FLY_APP"
          note "retrying app=$FLY_APP with the same hidden token; nothing was launched"
          break ;;
        5|repair)
          if [[ $kind != fly || -z ${TOKEN_LAST_FLY_REPAIR:-} ]]; then
            warn "no confirmed corrupt-config repair is available; rerun the check and inspect its diagnostics"
            continue
          fi
          repair_ticket=$TOKEN_LAST_FLY_REPAIR
          warn "this will back up and reset ONLY the diagnosed global Fly config.yml on Sprite $SPRITE_NAME"
          note "saved Fly login/settings will be replaced with empty-token defaults; pause other Fly commands first"
          note "the protected backup can contain old credentials; never upload or paste it"
          note "Codex, Git files, repository fly.toml and the Fly executable will not be replaced"
          printf '  Type RESET FLY CONFIG to confirm, or Enter to cancel: '
          IFS= read -r confirmation || die "Fly config repair cancelled; nothing launched"
          if [[ $confirmation != 'RESET FLY CONFIG' ]]; then
            note "repair cancelled; no config change requested"
            continue
          fi
          if validate_token_once "$name" "$kind" repair "$repair_ticket"; then
            note "retrying the NORMAL app-access check with the same hidden token; repair alone does not validate it"
            break
          else
            rc=$?
            (( rc != 130 )) || die "repair interrupted; outcome may be unknown; inspect with --check-fly before retrying"
            warn "repair was not confirmed; it will NOT be replayed automatically"
            note "choose 2 to inspect/recheck the current state before any further repair"
          fi ;;
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

# Optional official Mobbin Streamable HTTP MCP. Configure separately from OAuth:
# `codex mcp add --url` can initiate login, which must not block unattended setup.
# The equivalent documented TOML entry is added atomically and checked by Codex.
make_mobbin_mcp_helper() {
  if [[ -n ${MOBBIN_MCP_HELPER:-} && -f $MOBBIN_MCP_HELPER ]]; then return 0; fi
  MOBBIN_MCP_HELPER=$(mktemp)
  cleanup_files+=("$MOBBIN_MCP_HELPER")
  cat >"$MOBBIN_MCP_HELPER" <<'MOBBIN_MCP_PY'
#!/usr/bin/env python3
"""Secret-free Mobbin configuration; OAuth credentials stay in Codex's store."""
import fcntl
import glob
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

URL = "https://api.mobbin.com/mcp"


def fail(message, code=78):
    print("Mobbin MCP: " + message, file=sys.stderr, flush=True)
    raise SystemExit(code)


def load_toml(text):
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib
        except ImportError:
            fail("Python 3.11+ or tomli is required on the Sprite; no configuration changed.", 75)
    try:
        return tomllib.loads(text)
    except (ValueError, TypeError):
        # TOML errors may echo config values, including secrets: never print them.
        fail("existing Codex TOML is invalid; no configuration changed.")


def atomic_write(path, data):
    fd, tmp = tempfile.mkstemp(prefix=".sprite-mobbin-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_config(path):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        fail("refusing a symlink, non-file or differently owned config.toml; leaving it untouched.")
    return path.read_bytes()


def check_entry(root):
    servers = root.get("mcp_servers", {})
    if not isinstance(servers, dict):
        fail("mcp_servers is not a TOML table; leaving it untouched.")
    if "mobbin" not in servers:
        return "missing"
    entry = servers["mobbin"]
    if not isinstance(entry, dict) or entry.get("url") not in (URL, URL + "/") or entry.get("command"):
        fail("the name 'mobbin' already has a different configuration; it was NOT replaced.")
    if entry.get("enabled", True) is False:
        return "disabled"
    if any(entry.get(k) for k in ("bearer_token", "bearer_token_env_var", "http_headers", "env_http_headers", "http_headers_helper")):
        fail("existing Mobbin uses custom authentication/headers; manage it manually. Nothing replaced.")
    return "existing"


def runtime(home):
    codex_home = home / ".codex"
    configured_home = os.environ.get("CODEX_HOME")
    if configured_home and Path(configured_home).expanduser().resolve() != codex_home.resolve():
        fail("remote CODEX_HOME differs from ~/.codex used by this bootstrap; align it before installing.")
    env = os.environ.copy()
    # No GitHub/Fly/model credentials are needed by MCP configuration or login.
    for key in list(env):
        if any(word in key.upper() for word in ("TOKEN", "SECRET", "PASSWORD", "API_KEY", "PRIVATE_KEY")):
            env.pop(key, None)
    bins = [str(home / ".local/bin"), str(home / ".fly/bin")]
    nodes = []
    for pattern in ("/.sprite/languages/node/nvm/versions/node/*/bin/node",
                    str(home / ".nvm/versions/node/*/bin/node"),
                    str(home / ".local/share/nvm/versions/node/*/bin/node")):
        nodes.extend(glob.glob(pattern))
    def node_version(p):
        match = re.search(r"/v?(\d+)\.(\d+)\.(\d+)/bin/node$", p)
        return tuple(map(int, match.groups())) if match else (0, 0, 0)
    bins.extend(str(Path(p).parent) for p in sorted(nodes, key=node_version, reverse=True))
    env["PATH"] = os.pathsep.join(bins + [env.get("PATH", "/usr/local/bin:/usr/bin:/bin")])
    env["CODEX_HOME"] = str(codex_home)
    resolver = home / ".local/bin/sprite-codex-cli"
    codex = str(resolver) if resolver.is_file() and os.access(resolver, os.X_OK) else shutil.which("codex", path=env["PATH"])
    if not codex:
        fail("Codex is not available yet; defer until Sprite tool setup/update completes.", 75)
    return codex_home, codex, env


def codex_output(codex, env, home, args):
    try:
        result = subprocess.run([codex, *args], cwd=home, env=env, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        fail("Codex management command failed or timed out; no authentication was verified.")
    if result.returncode:
        fail("Codex management command failed; check its version and config manually (raw output withheld).")
    return result.stdout


def verify_cli(codex, env, home):
    output = codex_output(codex, env, home, ["mcp", "get", "mobbin", "--json"])
    try:
        entry = json.loads(output)
        transport = entry.get("transport", entry)
        valid = isinstance(transport, dict) and transport.get("url") in (URL, URL + "/")
        valid = valid and entry.get("enabled", True) is not False
        valid = valid and transport.get("type", "streamable_http") == "streamable_http"
    except (ValueError, AttributeError):
        valid = False
    if not valid:
        fail("Codex did not confirm the expected enabled Mobbin HTTP entry; check config overrides manually.")


def configure(home, codex_home, codex, env):
    codex_output(codex, env, home, ["mcp", "--help"])
    if codex_home.is_symlink():
        fail("refusing to modify a symlinked ~/.codex directory.")
    codex_home.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_path = codex_home / ".sprite-mobbin-config.lock"
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            fail("another Mobbin setup is running; retry later.")
        path = codex_home / "config.toml"
        before = read_config(path)
        text = (before or b"").decode("utf-8")
        root = load_toml(text)
        state = check_entry(root)
        if state == "disabled":
            print("MOBBIN_MCP_RESULT=disabled", flush=True)
            return
        if state == "existing":
            verify_cli(codex, env, home)
            print("MOBBIN_MCP_RESULT=existing", flush=True)
            return
        addition = ('\n\n# Mobbin hosted MCP (sprite-codex v48); OAuth is managed by Codex.\n'
                    '[mcp_servers.mobbin]\n'
                    'url = "https://api.mobbin.com/mcp"\n'
                    'enabled = true\nrequired = false\n'
                    'startup_timeout_sec = 30\ntool_timeout_sec = 120\n')
        after = (text + addition).encode("utf-8")
        parsed = load_toml(after.decode("utf-8"))
        expected = dict(root.get("mcp_servers", {}))
        expected["mobbin"] = parsed["mcp_servers"]["mobbin"]
        if parsed != dict(root, mcp_servers=expected):
            fail("configuration merge was not isolated to Mobbin; no changes made.")
        if before is not None:
            backups = codex_home / "backup-sprite-codex"
            if backups.is_symlink():
                fail("backup directory is a symlink; no changes made.")
            backups.mkdir(mode=0o700, exist_ok=True)
            fd, backup = tempfile.mkstemp(prefix="config.toml.mobbin-", suffix=".bak", dir=backups)
            with os.fdopen(fd, "wb") as out:
                out.write(before)
            os.chmod(backup, 0o600)
        # Do not silently overwrite a user/editor change made during preparation.
        if read_config(path) != before:
            fail("config.toml changed concurrently; no replacement performed.")
        atomic_write(path, after)
        try:
            verify_cli(codex, env, home)
        except BaseException:
            if read_config(path) == after:
                if before is None:
                    path.unlink()
                else:
                    atomic_write(path, before)
                print("Mobbin MCP: restored the pre-install config after verification failed.", file=sys.stderr)
            raise
        print("MOBBIN_MCP_RESULT=added", flush=True)


def login(home, codex_home, codex, env, request, timeout):
    if not re.fullmatch(r"[a-f0-9]{32}", request) or not 1 <= timeout <= 1800:
        fail("invalid login request.")
    state_dir = home / ".local/state/sprite-codex"
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    result_path = state_dir / ("mobbin-mcp-login-" + request + ".json")
    def record(status):
        atomic_write(result_path, json.dumps({"request_id": request, "status": status}).encode())
    # Only this request's completion record can confirm success after a TTY detach.
    record("pending")
    child = None
    rc = 1
    fd = os.open(codex_home / ".sprite-mobbin-login.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            record("busy")
            fail("a managed Mobbin login is already running; no second login started.")
        try:
            root = load_toml((read_config(codex_home / "config.toml") or b"").decode("utf-8"))
            if check_entry(root) != "existing":
                fail("Mobbin must be configured and enabled before login.")
            verify_cli(codex, env, home)
            def interrupted(signum, frame):
                raise InterruptedError("login interrupted")
            signal.signal(signal.SIGTERM, interrupted)
            signal.signal(signal.SIGHUP, interrupted)
            child = subprocess.Popen([codex, "mcp", "login", "mobbin"], cwd=home, env=env,
                                     stdin=subprocess.DEVNULL, start_new_session=True)
            rc = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            print("Mobbin MCP: browser authorization timed out.", file=sys.stderr)
            rc = 124
        except (KeyboardInterrupt, InterruptedError):
            print("Mobbin MCP: browser authorization interrupted.", file=sys.stderr)
            rc = 130
        finally:
            # Stop only our one OAuth management subprocess, never an agent session.
            if child is not None and child.poll() is None:
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
                except ProcessLookupError:
                    pass
            record("ok" if rc == 0 else "failed")
    raise SystemExit(rc if rc >= 0 else 128 - rc)


def main():
    home = Path.home()
    codex_home, codex, env = runtime(home)
    if sys.argv[1:] == ["configure"]:
        configure(home, codex_home, codex, env)
    elif len(sys.argv) == 4 and sys.argv[1] == "login":
        login(home, codex_home, codex, env, sys.argv[2], int(sys.argv[3]))
    else:
        fail("invalid action.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError):
        fail("filesystem/runtime error; check ownership, free space and Codex configuration (details withheld).")
MOBBIN_MCP_PY
}

run_mobbin_mcp_login() {
  local request rc=0 result=""
  [[ -t 0 && -t 1 ]] || {
    warn "no interactive terminal: Mobbin is configured, but OAuth login was not attempted"
    note "rerun from a terminal with MOBBIN_MCP_MODE=always MOBBIN_MCP_LOGIN=always"
    return 0
  }
  make_mobbin_mcp_helper
  request=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
  note "open the authorization URL printed by Codex in your LOCAL browser and approve Mobbin"
  note "automatic Sprite port forwarding is enabled for this login's loopback callback"
  note "finish authorization here; Ctrl+C cancels it, while Ctrl+\\ only detaches the login viewer"
  # Do not use --no-port-forward here: the local browser must reach the Sprite's
  # loopback OAuth listener. No public Sprite URL or external callback is enabled.
  # Empty decoded environment removes inherited API secrets but preserves HOME.
  if sprite exec "${ORG[@]}" -s "$SPRITE_NAME" --tty \
      --env "SPRITE_CODEX_ENV_HEX=7b7d" -- \
      python3 -c "$ENV_EXEC_PY" python3 -c "$(<"$MOBBIN_MCP_HELPER")" \
      login "$request" "$MOBBIN_MCP_LOGIN_TIMEOUT"; then rc=0; else rc=$?; fi
  # A clean local detach also returns 0. It is NOT proof that OAuth succeeded.
  result=$(control_exec_limited 15 -- python3 -c '
import json, pathlib, re, sys
request = sys.argv[1]
if not re.fullmatch(r"[a-f0-9]{32}", request): raise SystemExit(2)
p = pathlib.Path.home()/".local/state/sprite-codex"/("mobbin-mcp-login-"+request+".json")
try: data = json.loads(p.read_text())
except (OSError, ValueError): raise SystemExit(1)
if data.get("request_id") != request: raise SystemExit(1)
status = data.get("status")
if status not in ("ok", "pending", "failed", "busy"): raise SystemExit(1)
print("MOBBIN_LOGIN_RESULT="+status)
' "$request" 2>/dev/null || true)
  if grep -qx 'MOBBIN_LOGIN_RESULT=ok' <<<"$result"; then
    ok "Codex completed Mobbin OAuth on the selected Sprite"
    note "this verifies the login flow, not a paid Mobbin search; inspect /mcp in Codex"
  else
    warn "Mobbin OAuth success was not confirmed (viewer rc=$rc); configuration is retained"
    note "a detached login can remain pending until its timeout; no automatic second login was started"
    note "rerun with MOBBIN_MCP_MODE=always MOBBIN_MCP_LOGIN=always when ready to authorize"
    note "for callback problems, see the Mobbin section in README.md; no login token should be pasted into chat"
  fi
  return 0
}

maybe_setup_mobbin_mcp() {
  local phase=${1:-early} answer="" output="" rc=0 state="" login_now=0
  [[ $AGENT_KIND == codex && $MOBBIN_MCP_MODE != never && $MOBBIN_MCP_DONE == 0 ]] || return 0
  if [[ $MOBBIN_MCP_DECIDED == 0 ]]; then
    MOBBIN_MCP_DECIDED=1
    step "optional Mobbin MCP setup (after Codex update)"
    if [[ $MOBBIN_MCP_MODE == always ]]; then
      MOBBIN_MCP_SELECTED=1
    elif [[ -t 0 && -t 1 ]]; then
      note "Mobbin requires a Pro, Team or Enterprise plan and browser OAuth; no API token is requested"
      printf '  Install/configure the official Mobbin MCP for Codex on this Sprite? [y/N]: '
      IFS= read -r answer || answer=n
      case "${answer,,}" in y|yes) MOBBIN_MCP_SELECTED=1 ;; esac
    fi
    if [[ $MOBBIN_MCP_SELECTED != 1 ]]; then
      MOBBIN_MCP_DONE=1
      note "Mobbin setup skipped; existing MCP configuration and login are unchanged"
      return 0
    fi
    note "only the Mobbin MCP entry is added; model providers and other MCP servers are preserved"
    note "authorizing permits Codex to send Mobbin tool queries; searches may consume Mobbin AI credits"
    note "Mobbin OAuth credentials persist in Codex's normal store on the Sprite, unlike the process-only model keys"
  fi
  # Do not run ahead of a requested update that is awaiting its after-setup retry.
  if [[ $CODEX_UPDATE_REQUESTED == 1 && $CODEX_UPDATE_COMPLETED != 1 ]]; then
    if [[ $phase == early ]]; then
      note "Mobbin setup is deferred until the requested Codex update completes"
    else
      MOBBIN_MCP_DONE=1
      warn "requested Codex update was not verified; optional Mobbin setup skipped for this run"
    fi
    return 0
  fi
  make_mobbin_mcp_helper
  if output=$(run_remote_file "$MOBBIN_MCP_HELPER" "7b7d" "" -- \
      python3 @SPRITE_PAYLOAD@ configure 2>&1); then rc=0; else rc=$?; fi
  state=$(sed -n 's/^MOBBIN_MCP_RESULT=\(added\|existing\|disabled\)$/\1/p' <<<"$output" | tail -1)
  if (( rc != 0 )) || [[ -z $state ]]; then
    [[ -z $output ]] || printf '%s\n' "$output"
    if (( rc == 75 )) && [[ $phase == early ]]; then
      note "Mobbin setup will be retried after Sprite tools are ready; reattachment remains available"
    else
      MOBBIN_MCP_DONE=1
      warn "optional Mobbin setup was not verified (rc=$rc); continuing without a Mobbin readiness claim"
    fi
    return 0
  fi
  MOBBIN_MCP_DONE=1
  if [[ $state == disabled ]]; then
    note "Mobbin is already configured but disabled; its explicit setting was preserved (no login attempted)"
    return 0
  fi
  ok "Mobbin MCP configuration verified by Codex ($state) on Sprite $SPRITE_NAME"
  if [[ $CODEX_UPDATE_LIVE_DETECTED == 1 ]]; then
    warn "an existing Codex process may not load a newly added MCP server until its next restart"
    note "this script will not restart/replace it for Mobbin; normal reattachment is unchanged"
  fi
  case "$MOBBIN_MCP_LOGIN" in
    always) login_now=1 ;;
    ask)
      if [[ -t 0 && -t 1 ]]; then
        if [[ $state == added ]]; then
          printf '  Authorize Mobbin in your browser now? [Y/n]: '
          IFS= read -r answer || answer=n
          case "${answer,,}" in ''|y|yes) login_now=1 ;; esac
        else
          printf '  Mobbin is already configured. Run browser login again? [y/N]: '
          IFS= read -r answer || answer=n
          case "${answer,,}" in y|yes) login_now=1 ;; esac
        fi
      fi ;;
  esac
  if (( login_now )); then
    run_mobbin_mcp_login
  else
    note "Mobbin login was not tested or changed; an existing Codex OAuth login may still be usable"
    note "for a new connection, rerun with MOBBIN_MCP_MODE=always MOBBIN_MCP_LOGIN=always"
  fi
  return 0
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
# executable and then reopen the resume picker. The user chooses the saved chat;
# no automatic latest-session lookup or transcript-output parsing is performed.
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
      echo "       opening the saved-conversation picker: codex resume"
      echo "       select the conversation to continue; no conversation ID or --last is supplied"
      "$CODEX_LAUNCHER" resume
      ;;
    fork)
      echo "       opening the saved-conversation fork picker: codex fork"
      echo "       select the intended source; Codex creates a separate thread without replacing the source history"
      "$CODEX_LAUNCHER" fork
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

  # An interrupted picker/run is not a request to fork or restart. A clean
  # exit is handled below; do not claim it proves that a conversation was resumed.
  case "$codex_rc" in
    129|130|131|143)
      echo "       Codex was interrupted (rc=$codex_rc); no fork or update relaunch will be attempted"
      exit "$codex_rc"
      ;;
  esac

  if (( codex_rc != 0 )) && [[ $launch_mode == resume ]]; then
    echo >&2
    echo "warning: Codex resume exited with rc=$codex_rc" >&2
    if codex_processes=$(pgrep -af '([c]odex|[a]pp-server|[c]odeproxy)' 2>/dev/null); then
      echo "warning: Codex-like processes are still present; they will not be terminated automatically:" >&2
      printf '%s\n' "$codex_processes" | sed 's/^/         /' >&2
    else
      echo "warning: no live Codex, app-server, or codeproxy process was found" >&2
      echo "         this process-name probe alone cannot establish whether a conversation has an active writer" >&2
    fi
    echo "         this recovery step will not delete transcript files, reset the workspace, or terminate other agents" >&2
    if [[ -t 0 && -t 1 ]]; then
      printf '  Open the fork picker to select a saved conversation for a new thread? [y/N]: '
      IFS= read -r fork_after_resume || fork_after_resume=n
    else
      fork_after_resume=n
    fi
    case "${fork_after_resume,,}" in
      y|yes)
        launch_mode=fork
        if run_codex_mode "$launch_mode"; then
          codex_rc=0
        else
          codex_rc=$?
        fi
        ;;
      *)
        echo "       fork recovery skipped; rerun and choose Resume to select the intended saved conversation"
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

    # Open the picker with the verified update. Without an explicit user
    # selection, the latest saved thread need not be the one that just ended.
    launch_mode=resume
    echo "       relaunching with the updated Codex and opening the resume picker"
    echo "       select the conversation you were working on before the update"
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
    tty=r.get("tty",r.get("is_tty",r.get("isTty",False)))
    tty_ok=isinstance(tty,(str,int,bool)) and str(tty).lower() in ("true","1")
    ended=str(r.get("status",r.get("state",""))).strip().lower() in ("exited","ended","stopped","dead","completed","failed","terminated","killed","closed")
    # is_active is activity metadata, not an exit status.
    if not sid or ended or not tty_ok or tag not in cmd: continue
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
    tty = record.get("tty", record.get("is_tty", record.get("isTty", False)))
    tty_ok = isinstance(tty, (str, int, bool)) and str(tty).lower() in ("true", "1")
    ended = str(record.get("status", record.get("state", ""))).strip().lower() in (
        "exited", "ended", "stopped", "dead", "completed", "failed", "terminated", "killed", "closed")
    # Keep quiet/detached candidates in live-update and duplicate protections.
    if not session_id or ended or not tty_ok or "sprite-codex-native-" not in command:
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
      note "the running TTY keeps its installed runner logic; new v49 runners reopen the resume picker after a verified update"
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

# Compatibility name: verifies a listed session has no explicit ended status;
# is_active/last_activity are deliberately NOT used as process-liveness signals.
session_id_is_active() {
  local sid=$1 raw; [[ -n $sid ]] || return 1; raw=$(get_sessions_json)
  python3 -c 'import json,sys
sid=sys.argv[1]
try: root=json.load(sys.stdin)
except Exception: raise SystemExit(1)
items=(root.get("sessions") or root.get("data") or root.get("items") or []) if isinstance(root,dict) else root
for r in items if isinstance(items,list) else []:
 if not isinstance(r,dict): continue
 rid=str(r.get("id",r.get("session_id","")))
 ended=str(r.get("status",r.get("state",""))).strip().lower() in ("exited","ended","stopped","dead","completed","failed","terminated","killed","closed")
 if rid==sid and not ended: raise SystemExit(0)
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
    if (( rc == 137 )); then warn "attachment exited 137; use opening menu 6 / --retrieve for independent repository recovery"; return "$rc"; fi
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
  maybe_download_output "$SPRITE_NAME" "$rc"
  return "$rc"
}

# v31-and-earlier migration guard only; normal v32 sessions never use tmux.
legacy_tmux_probe() {
  local session=$1
  control_exec_limited 15 -- bash -lc 's=$1; command -v tmux >/dev/null 2>&1 || exit 3; tmux has-session -t "$s" 2>/dev/null || exit 1; panes=$(tmux list-panes -t "$s" -F "#{pane_dead}|#{pane_start_command}|#{pane_current_command}" 2>/dev/null || true); meta=$(tmux show-environment -t "$s" SPRITE_CODEX_TASK 2>/dev/null || true); printf "%s\n%s\n" "$panes" "$meta" | grep -q "sprite-codex" && exit 0; exit 4' _ "$session" >/dev/null 2>&1
}
legacy_tmux_kill() { local session=$1; control_exec_limited 20 -- tmux kill-session -t "$session" >/dev/null 2>&1; }
legacy_tmux_attach() {
  local session=$1 rc=0
  warn "attaching to a legacy tmux-managed Codex session from v31 or earlier"
  note "this one legacy attachment still has tmux input/copy-mode behavior"
  if sprite exec "${ORG[@]}" -s "$SPRITE_NAME" --tty --no-port-forward -- tmux attach-session -d -t "$session"; then rc=0; else rc=$?; fi
  maybe_download_output "$SPRITE_NAME" "$rc"
  return "$rc"
}
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
import hashlib
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


# API token checks use fixed messages. Fly also returns bounded diagnostic text
# only after redacting secrets and terminal control sequences on the Sprite.
class TokenFailure(Exception):
    def __init__(self, category, detail, diagnostics=None):
        super().__init__(detail)
        self.category = category
        self.diagnostics = diagnostics or []
        self.fly_config_repair = ""


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


def fly_capture(argv, child_env, workdir, timeout):
    """Bound total runtime AND buffered bytes; never store CLI output on disk.

    If the byte cap is exceeded, suppress the WHOLE excerpt (not a raw prefix
    which might end in a partial secret). A quiet process is still deadline-bound.
    Only this read-only check's new process group is stopped on cancellation.
    """
    import selectors
    import subprocess
    limit = 128 * 1024
    data = bytearray()
    overflow = False
    process = subprocess.Popen(argv, env=child_env, cwd=workdir,
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    selector = selectors.DefaultSelector()
    end = time.monotonic() + timeout
    completed = False
    try:
        selector.register(process.stdout, selectors.EVENT_READ)
        while selector.get_map():
            remaining = end - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(argv, timeout)
            for event, _ in selector.select(min(remaining, 0.2)):
                chunk = os.read(event.fileobj.fileno(), 16384)
                if not chunk:
                    selector.unregister(event.fileobj)
                    continue
                if not overflow and len(data) + len(chunk) <= limit:
                    data.extend(chunk)
                else:
                    overflow = True
                    data.clear()
        rc = process.wait(timeout=max(0.001, end - time.monotonic()))
        completed = True
        return rc, bytes(data).decode('utf-8', 'replace'), overflow
    finally:
        selector.close()
        if not completed or process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        process.stdout.close()


def fly_redacted_text(text, env, key):
    """Redact before extracting/truncating lines. Not a general secret scanner."""
    import base64
    secrets_to_hide = {key}
    for name, value in env.items():
        if name not in ('TOKEN_CHECK_TIMEOUT', 'MODEL_TEST_MAX_TOKENS') and value and (name.upper().endswith('_PAT') or any(word in name.upper() for word in ('TOKEN', 'SECRET', 'PASSWORD', 'API_KEY', 'PRIVATE_KEY'))):
            secrets_to_hide.add(value)
    # Macaroon token bundles have multiple independently sensitive components.
    for part in re.split(r'[\s,]+', key):
        if len(part) >= 8 and part.lower() not in ('bearer', 'flyv1'):
            secrets_to_hide.add(part)
    variants = set()
    for value in secrets_to_hide:
        if not value:
            continue
        variants.update((value, json.dumps(value)[1:-1], urllib.parse.quote(value, safe=''),
                         urllib.parse.quote_plus(value, safe=''), value.encode().hex(),
                         base64.b64encode(value.encode()).decode(),
                         base64.urlsafe_b64encode(value.encode()).decode().rstrip('=')))
    # Strip OSC (including hyperlinks) and ANSI display controls before masking.
    text = re.sub(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)', '', text)
    text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text)
    for value in sorted(variants, key=len, reverse=True):
        text = text.replace(value, '[REDACTED]')
    text = re.sub(r'(?i)\bFlyV1\s+[^\r\n]+', '[REDACTED FLY CREDENTIAL]', text)
    text = re.sub(r'(?i)\b(?:fm[12]|fo[12]|gh[pousr]|github_pat|sk)_[A-Za-z0-9_./+\-=]+', '[REDACTED]', text)
    text = re.sub(r'(?i)((?:authorization|proxy-authorization)\s*[:=]\s*)[^\r\n]+', r'\1[REDACTED]', text)
    text = re.sub(r'(?i)\bBearer\s+[^\r\n]+', 'Bearer [REDACTED]', text)
    text = re.sub(r'(?i)((?:[\w-]*(?:token|password|secret|api[_-]?key)[\w-]*)[\s\"\x27]*[:=]\s*)[^\r\n]+', r'\1[REDACTED]', text)
    text = re.sub(r'(https?://)[^\s/@]+:[^\s/@]+@', r'\1[REDACTED]@', text)
    # Query/fragment values can carry credentials, even under unexpected names.
    text = re.sub(r'(https?://[^\s?#]+)[?#][^\s]+', r'\1?[REDACTED]', text)
    text = ''.join(c if (c.isprintable() or c == '\n') else ' ' for c in text)
    return text.encode('ascii', 'backslashreplace').decode('ascii')


def fly_failure_hint(rc, text):
    """Heuristic labels only: never turn error text into a successful check."""
    lower = text.lower()
    if rc < 0 or rc in (129, 130, 131, 137, 139, 143):
        return 'process-terminated', 'The Fly check process ended by signal or a signal-style exit; this is not a token verdict.'
    if rc in (126, 127) or any(x in lower for x in ('unknown flag', 'unknown command', 'exec format error', 'panic:', 'yaml:', 'toml:', 'permission denied')):
        return 'cli-configuration', 'The CLI output suggests an executable/configuration/permission problem, not necessarily a bad token.'
    if any(x in lower for x in ('no such host', 'dial tcp', 'connection refused', 'connection reset', 'network is unreachable', 'i/o timeout', 'tls handshake', 'x509:', 'certificate', 'proxyconnect', 'context deadline exceeded', 'temporary failure in name resolution')):
        return 'network', 'The CLI output suggests DNS/network/TLS failure; token validity is not established.'
    if re.search(r'\b429\b|rate.?limit|too many requests', lower):
        return 'rate-limit', 'The CLI output suggests rate limiting; retry without replacing the token.'
    if re.search(r'\b(?:500|502|503|504)\b|bad gateway|service unavailable|internal server error', lower):
        return 'service', 'The CLI output suggests a service failure; token validity is not established.'
    if 'app' in lower and any(x in lower for x in ('not found', 'could not find', 'could not resolve', 'cannot find', 'does not exist')):
        return 'app-or-access', 'Check FLY_APP and app permissions; an unavailable app is not proof the token is invalid.'
    if re.search(r'\b401\b|unauthenticated|unauthori[sz]ed|invalid (?:access )?token|token (?:has )?expired|token (?:was )?revoked', lower):
        return 'authentication', 'Fly reports an authentication-related rejection; check token formatting, expiry and scope.'
    if re.search(r'\b403\b|forbidden|not authori[sz]ed|permission|access denied|insufficient.*scope', lower):
        return 'access', 'The CLI output suggests denied access; the token may be valid for a different app or scope.'
    return 'access-or-service', 'Fly app access was not confirmed; inspect the diagnostic, target app and CLI before replacing the token.'


# v59 global config diagnosis: content never leaves the Sprite.
FLY_EMPTY_CONFIG = (b'# Recreated after explicit sprite-codex confirmation. No saved tokens.\n'
                    b'access_token: ""\nmetrics_token: ""\n'
                    b'send_metrics: false\nauto_update: false\nsynthetics_agent: false\n')


def fly_global_config_error(text):
    lower = text.lower()
    return ('yaml:' in lower and any(word in lower for word in
            ('error loading config', 'while parsing config', 'control characters are not allowed',
             'invalid leading utf-8', 'invalid trailing utf-8')))


def fly_config_inspect(child_env, workdir):
    """Bounded metadata/character scan, NOT a full YAML parser. No values returned."""
    import stat
    raw_dir = child_env.get('FLY_CONFIG_DIR') if 'FLY_CONFIG_DIR' in child_env else os.path.join(child_env.get('HOME', os.path.expanduser('~')), '.fly')
    info = {'source': 'FLY_CONFIG_DIR' if 'FLY_CONFIG_DIR' in child_env else 'HOME/.fly',
            'path': '', 'issue': '', 'eligible': False}
    if not raw_dir or not os.path.isabs(raw_dir) or any(ord(c) < 32 or ord(c) == 127 for c in raw_dir):
        info['issue'] = 'Config directory is empty, relative or contains control characters; automatic repair is disabled.'
        return info
    directory = os.path.normpath(raw_dir)
    path = os.path.join(directory, 'config.yml')
    info['path'] = path
    if len(path) > 2048 or os.path.realpath(path) != path:
        info['issue'] = 'Symlinked or overlong config path; contents not inspected and automatic repair disabled.'
        return info
    fd = None
    try:
        parent = os.stat(directory, follow_symlinks=False)
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            info['issue'] = 'Config is not a regular file; contents not inspected.'
            return info
        info.update(size=before.st_size, mode=stat.S_IMODE(before.st_mode), uid=before.st_uid)
        if before.st_size > 1024 * 1024:
            info['issue'] = 'Config exceeds the 1 MiB inspection limit; automatic repair disabled.'
            return info
        data = bytearray()
        while len(data) <= 1024 * 1024:
            chunk = os.read(fd, min(65536, 1024 * 1024 + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        after = os.fstat(fd)
        if len(data) > 1024 * 1024 or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            info['issue'] = 'Config changed during inspection; retry before any repair.'
            return info
        data = bytes(data)
        encoding = 'utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig'
        try:
            decoded = data.decode(encoding)
        except UnicodeError:
            info.update(invalid_encoding=True, forbidden=0, examples=[])
        else:
            def allowed(n):
                return n in (9, 10, 13, 0x85) or 0x20 <= n <= 0x7e or 0xa0 <= n <= 0xd7ff or 0xe000 <= n <= 0xfffd or 0x10000 <= n <= 0x10ffff
            count, examples = 0, []
            for i, c in enumerate(decoded):
                if not allowed(ord(c)):
                    count += 1
                    if len(examples) < 4:
                        examples.append((i, ord(c)))
            info.update(invalid_encoding=False, forbidden=count, examples=examples)
        info['fingerprint'] = {'sha256': hashlib.sha256(data).hexdigest(), 'dev': before.st_dev,
                               'ino': before.st_ino, 'size': before.st_size, 'mtime_ns': before.st_mtime_ns,
                               'ctime_ns': before.st_ctime_ns, 'mode': before.st_mode, 'uid': before.st_uid,
                               'nlink': before.st_nlink, 'parent_dev': parent.st_dev, 'parent_ino': parent.st_ino}
        info['eligible'] = bool(info['invalid_encoding'] or info['forbidden']) and before.st_uid == os.geteuid() and before.st_nlink == 1 and parent.st_uid == os.geteuid() and stat.S_ISDIR(parent.st_mode) and directory != '/'
        return info
    except FileNotFoundError:
        info['issue'] = 'Expected config.yml was not found; this path is not proven to be the failing input.'
    except PermissionError:
        info['issue'] = 'Config or its directory is not readable by this Sprite user; automatic repair disabled.'
    except OSError:
        info['issue'] = 'Config metadata could not be read safely; automatic repair disabled.'
    finally:
        if fd is not None:
            os.close(fd)
    return info


def fly_config_diagnose(fly, child_env, workdir, key, timeout, diagnostics):
    """A clean config status check is comparison evidence, NEVER a launch pass."""
    import subprocess
    clean = lambda value: fly_redacted_text(str(value), child_env, key)
    info = fly_config_inspect(child_env, workdir)
    diagnostics = list(diagnostics)
    diagnostics.append('Stage: global YAML config load. This failure precedes app authentication; token validity is not established by the original command.')
    if info['path']:
        diagnostics.append(('Expected global config (%s): ' % info['source']) + clean(info['path'])[:490])
    if 'size' in info:
        diagnostics.append('File metadata: %d bytes; mode %03o; owner uid %d. Contents are NOT displayed.' % (info['size'], info['mode'], info['uid']))
    if info['issue']:
        diagnostics.append(info['issue'])
    elif info.get('invalid_encoding'):
        diagnostics.append('File scan: invalid UTF-8/UTF-16 text encoding; file content and offending byte values withheld.')
    elif info.get('forbidden'):
        diagnostics.append('File scan: %d forbidden YAML character(s); %s. Offsets are character offsets, not file contents.' % (info['forbidden'], ', '.join('U+%04X at offset %d' % (code, offset) for offset, code in info['examples'])))
    else:
        diagnostics.append('File scan: no forbidden characters detected. This is not a complete YAML syntax/type validation.')
    ticket = ''
    # FLY_CONFIG_DIR changes only for this child. HOME, endpoints, proxies, app,
    # binary and supplied token remain the same. No saved login is copied.
    with tempfile.TemporaryDirectory(prefix='sprite-fly-clean-config-') as fresh:
        path = os.path.join(fresh, 'config.yml')
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as f:
            f.write(FLY_EMPTY_CONFIG)
        isolated = child_env.copy()
        isolated['FLY_CONFIG_DIR'] = fresh
        try:
            rc, output, overflow = fly_capture([fly, 'status', '--app', child_env['FLY_APP']], isolated, workdir, min(timeout, 30))
        except subprocess.TimeoutExpired:
            diagnostics.append('Clean-config comparison: TIMEOUT; no token verdict and no config changes.')
        except OSError:
            diagnostics.append('Clean-config comparison: could not start/complete; no token verdict and no config changes.')
        else:
            if rc == 0 and not overflow and not fly_global_config_error(output):
                diagnostics.append('Clean-config comparison: PASS with the SAME entered token/app/binary. The original global config is still broken; this is NOT a normal-launch pass.')
                current = fly_config_inspect(child_env, workdir)
                if info['eligible'] and current.get('fingerprint') == info.get('fingerprint'):
                    ticket = json.dumps({'version': 1, 'path': info['path'], 'source': info['source'],
                                         'fingerprint': info['fingerprint']}, sort_keys=True, separators=(',', ':')).encode().hex()
                    diagnostics.append('Repair available: choose 5, then type RESET FLY CONFIG. Only this diagnosed config.yml is backed up and reset; a normal app-access check is still required.')
                else:
                    diagnostics.append('No automatic reset offered: the file is not a stable, owned regular file with confirmed invalid text. Review configuration separately.')
            elif not overflow and fly_global_config_error(output):
                diagnostics.append('Clean-config comparison: YAML failure persists. FLY_CONFIG_DIR may be ignored or another input may be involved; do not reset a guessed file.')
            elif overflow:
                diagnostics.append('Clean-config comparison: output exceeded the safe cap; excerpt suppressed, no token verdict.')
            else:
                category, hint = fly_failure_hint(rc, clean(output))
                diagnostics.append(('Clean-config comparison: exit %s [%s]. ' % (rc, category)) + hint)
                text = clean(output)
                lines = [' '.join(line.split()) for line in text.splitlines() if line.strip()]
                errors = [line for line in lines if re.search(r'(?i)error|fail|denied|unauthor|not found|invalid|timeout|expired|forbidden', line)]
                for line in (errors or lines)[-2:]:
                    diagnostics.append('Clean-config diagnostic: ' + line[:560])
    failure = TokenFailure('cli-config-parse', 'Fly could not load its global YAML configuration. Replacing the token or changing the app does not repair that file. See the configuration and isolated-test diagnostics.', diagnostics[:16])
    failure.fly_config_repair = ticket
    return failure


def repair_fly_config(child_env, workdir, key, ticket_hex):
    """Explicitly authorized, guarded reset. Never a credential-validation pass."""
    import fcntl
    import stat
    clean = lambda value: fly_redacted_text(str(value), child_env, key)
    if not re.fullmatch(r'[a-f0-9]{2,16384}', ticket_hex or ''):
        raise TokenFailure('configuration', 'No valid diagnosed config receipt; run the ordinary Fly check again.')
    try:
        ticket = json.loads(bytes.fromhex(ticket_hex))
    except (ValueError, UnicodeError):
        raise TokenFailure('configuration', 'Invalid config repair receipt; nothing reset.') from None
    info = fly_config_inspect(child_env, workdir)
    expected = {'version': 1, 'path': info['path'], 'source': info['source'], 'fingerprint': info.get('fingerprint')}
    if not info['eligible'] or ticket != expected:
        raise TokenFailure('config-changed', 'The diagnosed file changed, is unsafe, or is no longer corrupt. Nothing reset; run the ordinary Fly check again.')
    directory = os.path.dirname(info['path'])
    backup_dir = ''
    temporary = ''
    lockfd = dirfd = None
    try:
        dirfd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        parent = os.fstat(dirfd)
        if (parent.st_dev, parent.st_ino) != (ticket['fingerprint']['parent_dev'], ticket['fingerprint']['parent_ino']):
            raise TokenFailure('config-changed', 'Config directory changed; nothing reset.')
        # Serializes our repair attempts only. Pause other Fly writers first;
        # old flyctl versions do not necessarily use a compatible file lock.
        lockfd = os.open('.sprite-codex-repair.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=dirfd)
        lockstat = os.fstat(lockfd)
        if not stat.S_ISREG(lockstat.st_mode) or lockstat.st_uid != os.geteuid() or lockstat.st_nlink != 1:
            raise TokenFailure('configuration', 'Unsafe repair lock; nothing reset.')
        try:
            fcntl.flock(lockfd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise TokenFailure('config-busy', 'Another config repair is in progress; nothing reset.') from None
        current = fly_config_inspect(child_env, workdir)
        if not current['eligible'] or current.get('fingerprint') != ticket['fingerprint']:
            raise TokenFailure('config-changed', 'Config changed before backup; nothing reset.')
        original_fd = os.open('config.yml', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dirfd)
        with os.fdopen(original_fd, 'rb') as f:
            original = f.read(1024 * 1024 + 1)
        if hashlib.sha256(original).hexdigest() != ticket['fingerprint']['sha256']:
            raise TokenFailure('config-changed', 'Config changed while backing up; nothing reset.')
        backup_dir = tempfile.mkdtemp(prefix='sprite-codex-config-backup-', dir=directory)
        backup = os.path.join(backup_dir, 'config.yml')
        fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as f:
            f.write(original); f.flush(); os.fsync(f.fileno())
        bfd = os.open(backup_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(bfd)
        finally: os.close(bfd)
        fd, temporary = tempfile.mkstemp(prefix='.sprite-fly-reset-', dir=directory)
        with os.fdopen(fd, 'wb') as f:
            f.write(FLY_EMPTY_CONFIG); f.flush(); os.fsync(f.fileno())
        current = fly_config_inspect(child_env, workdir)
        if not current['eligible'] or current.get('fingerprint') != ticket['fingerprint']:
            raise TokenFailure('config-changed', 'Config changed before replacement; original path was not reset. A private backup may have been retained.')
        os.replace(temporary, 'config.yml', dst_dir_fd=dirfd)
        temporary = ''
        os.fsync(dirfd)
    finally:
        if temporary:
            try: os.unlink(temporary)
            except OSError: pass
        if lockfd is not None: os.close(lockfd)
        if dirfd is not None: os.close(dirfd)
    return ['Private original backup (may contain old credentials; do NOT share): ' + clean(backup)[:490],
            'Reset only: ' + clean(info['path'])[:530],
            'Saved Fly login/settings were replaced with empty-token defaults. Binary, project fly.toml, Git files and Codex sessions were not changed.',
            'No app-access success is inferred from this repair. Retry the normal check with the same token.']


def check_fly_token(env, key, timeout):
    import shutil
    import subprocess
    app = env.get('FLY_APP', '')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*', app):
        raise TokenFailure('configuration', 'FLY_APP must be a valid app name.')
    child_env = env.copy()
    home = child_env.get('HOME', os.path.expanduser('~'))
    child_env['PATH'] = home + '/.local/bin:' + home + '/.fly/bin:' + child_env.get('PATH', '/usr/local/bin:/usr/bin:/bin')
    fly = shutil.which('fly', path=child_env['PATH']) or shutil.which('flyctl', path=child_env['PATH'])
    if not fly:
        raise TokenFailure('configuration', 'Fly CLI is missing on the selected Sprite; install fly/flyctl and retry.')
    child_env['FLY_API_TOKEN'] = child_env['FLY_ACCESS_TOKEN'] = key
    child_env['FLY_APP'] = app
    # Do not enable verbose/debug tracing or token inspection as a workaround.
    for name in ('LOG_LEVEL', 'FLY_LOG_LEVEL', 'FLY_DEBUG', 'DEBUG', 'FLY_VERBOSE', 'FLY_LOG_GQL_ERRORS'):
        child_env.pop(name, None)
    child_env['NO_COLOR'] = '1'
    child_env.pop('FLY_UPDATE_CHECK', None)
    child_env['FLY_NO_UPDATE_CHECK'] = '1'
    child_env['FLY_SEND_METRICS'] = 'false'
    child_env['FLY_SYNTHETICS_AGENT'] = 'false'
    clean = lambda value: fly_redacted_text(str(value), env, key)
    diagnostics = ['Executable: ' + clean(fly)[:520]]
    overridden = [name for name in ('FLY_API_BASE_URL', 'FLY_FLAPS_BASE_URL', 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY') if child_env.get(name)]
    if overridden:
        diagnostics.append('Inherited endpoint/proxy settings present (values hidden): ' + ', '.join(overridden))
    # Empty transient cwd avoids a repository fly.toml. HOME and saved CLI
    # configuration remain unchanged. No output or token is written by this code.
    with tempfile.TemporaryDirectory(prefix='sprite-fly-check-') as workdir:
        try:
            rc, output, overflow = fly_capture([fly, 'status', '--app', app], child_env, workdir, timeout)
        except subprocess.TimeoutExpired:
            raise TokenFailure('timeout', 'fly status timed out for the selected app; token validity is not established.', diagnostics) from None
        except OSError:
            raise TokenFailure('cli-configuration', 'The installed Fly executable could not be started; no token was accepted.', diagnostics) from None
        # Configuration errors may reveal YAML values in the raw excerpt. Do not
        # relay that excerpt. Report metadata and a clean-config A/B check instead.
        if not overflow and fly_global_config_error(output):
            raise fly_config_diagnose(fly, child_env, workdir, key, timeout, diagnostics)
    if rc == 0:
        return 'fly status succeeded for the selected app with both Fly token aliases; deployment/SSH permissions are not proven.'
    if overflow:
        redacted = ''
        diagnostics.append('CLI output exceeded 128 KiB; the entire excerpt was suppressed to avoid exposing a partial credential.')
    else:
        redacted = clean(output)
        lines = [' '.join(line.split()) for line in redacted.splitlines() if line.strip()]
        # Prefer error lines over normal status tables and update notices.
        errors = [line for line in lines if re.search(r'(?i)error|fail|denied|unauthor|not found|could not|invalid|timeout|expired|forbidden', line)]
        for line in (errors or lines)[-3:]:
            diagnostics.append(line[:590])
        if not lines:
            diagnostics.append('fly/flyctl returned no diagnostic text.')
    category, hint = fly_failure_hint(rc, redacted)
    # Do not include app/paths in the fixed detail: those belong to sanitized UI.
    raise TokenFailure(category, ('fly status exited %s. ' % rc) + hint, diagnostics[:6])

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
        action = env.get("SPRITE_FLY_CONFIG_ACTION", "check")
        if action not in ("check", "repair") or (action == "repair" and kind != "fly"):
            raise TokenFailure("configuration", "Invalid Fly config operation; nothing reset.")
        if action == "repair":
            # Same remote config scope as the normal checker. No token is written.
            with tempfile.TemporaryDirectory(prefix="sprite-fly-check-") as cwd:
                diagnostics = repair_fly_config(env, cwd, key, env.get("SPRITE_FLY_CONFIG_RECEIPT", ""))
            raise TokenFailure("config-repaired", "Global config backed up/reset by explicit request. Retry the normal Fly check; app access has not been accepted.", diagnostics)
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
        if kind == "fly" and exc.diagnostics:
            result["diagnostics"] = exc.diagnostics
        if kind == "fly" and exc.fly_config_repair:
            result["fly_config_repair"] = exc.fly_config_repair
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
    return 0 if result["passed"] or result.get("category") == "config-repaired" else 1


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

run_fly_check_only() {
  need_local sprite
  need_local python3
  step "Fly app-access diagnostic only"
  note "uses your local Sprites login; no GitHub/model keys or agent setup"
  note "does not install/update flyctl or change any existing Codex session"
  note "global YAML errors trigger a clean-config comparison; config reset is opt-in with explicit confirmation"
  pick_sprite
  local selected_app=${FLY_APP:-} answer=""
  [[ -n $selected_app ]] || selected_app=$(detect_fly_app || true)
  if [[ -t 0 ]]; then
    printf '  Target Fly app%s (not necessarily the Sprite name): ' "${selected_app:+ [$selected_app]}"
    IFS= read -r answer || die "Fly diagnostic cancelled"
    selected_app=${answer:-$selected_app}
  fi
  [[ $selected_app =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "set FLY_APP to the actual Fly app or enter it at the prompt"
  FLY_APP=$selected_app
  if [[ -n ${FLY_API_TOKEN:-} && -n ${FLY_ACCESS_TOKEN:-} && $FLY_API_TOKEN != "$FLY_ACCESS_TOKEN" ]]; then
    warn "Fly aliases differ; this check uses FLY_API_TOKEN for BOTH aliases"
  fi
  FLY_API_TOKEN=${FLY_API_TOKEN:-${FLY_ACCESS_TOKEN:-}}
  prompt_validated_secret FLY_API_TOKEN "Fly.io token for $FLY_APP" fly
  ok "Fly app-status access verified on $SPRITE_NAME for app $FLY_APP"
  note "no deploy/SSH/write operation was tested; running agent credentials were not changed"
}

# Test-only dispatch precedes sprite/GitHub/Fly setup and every session action.
case "$RUN_MODE" in
  check-fly) run_fly_check_only; exit $? ;;
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
# Snapshot local project selection metadata for a later output download. Explicit
# SPRITE_ORG still takes precedence, and the selected Sprite is always passed -s.
_output_context_parent="$OUTPUT_HOST_DIR"
while :; do
  if [[ -f $_output_context_parent/.sprite ]]; then
    OUTPUT_PINNED_CONTEXT=$(mktemp)
    cleanup_files+=("$OUTPUT_PINNED_CONTEXT")
    cat "$_output_context_parent/.sprite" >"$OUTPUT_PINNED_CONTEXT"
    break
  fi
  [[ $_output_context_parent != / ]] || break
  _output_context_parent=$(dirname "$_output_context_parent")
done
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
  maybe_setup_mobbin_mcp early
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

# Retry a deferred first-install only after tools and requested Codex update.
maybe_setup_mobbin_mcp after-setup

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

if [[ $OUTPUT_PATH_EXPLICIT == 1 ]]; then
  note "generated deliverables: requested folder is $SPRITE_OUTPUT_DIR on the Sprite"
else
  note "generated deliverables: use ./output in Codex's workspace; the ZIP menu lets you choose any specific folder"
fi
note "after the terminal returns, output ZIP downloads go to: $OUTPUT_HOST_DIR"
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
    note "rerun and choose 'Resume a saved conversation' to open the Codex picker (no chat ID required)"
    if (( launch_rc != 0 )); then
      note "only if Codex explicitly reports an active-writer conflict, consider Fork and select the intended source chat"
    fi
  else
    note "resume state is retained as a history hint; rerun and choose Kimi Code continue if it exited"
  fi
fi
maybe_download_output "$SPRITE_NAME" "$launch_rc"
exit "$launch_rc"
