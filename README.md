# Sprites.dev Codex / Kimi Launcher and Keepalive Utilities

This directory contains two complementary Bash utilities for running coding agents on an existing [Sprites.dev](https://sprites.dev/) Sprite and keeping that Sprite available for unattended work:

- **`sprite-codex.sh`** — the main interactive bootstrap, workspace manager, provider configurator, session manager, and agent launcher. It can run either **OpenAI Codex** or the **official Kimi Code CLI** inside a native detachable Sprite TTY session.
- **`keepalive.sh`** — an independent keep-awake manager. It inventories current Sprites and their known keep-awake deadlines, then optionally creates or extends a separate Tasks API hold without starting a coding agent.

The two scripts are deliberately separate. `sprite-codex.sh` is primarily about preparing and supervising an agent session. `keepalive.sh` is primarily about keeping an already-existing Sprite running when you want the VM to remain available independently of an agent session.

> These scripts operate on **existing Sprites only**. They do not create or destroy Sprites.

---

## 1. How the two scripts fit together

A typical workflow is:

```text
local machine
   |
   |  sprite CLI
   v
existing Sprites.dev Sprite
   |
   +-- GitHub-backed project workspace
   |
   +-- Codex or Kimi Code native TTY session
   |      |
   |      +-- bounded Tasks API heartbeat created by sprite-codex.sh
   |
   +-- optional independent manual keepalive
          |
          +-- Tasks API heartbeat created by keepalive.sh
```

Both keep-awake mechanisms use the Sprite-local Tasks API, but they have different lifecycles:

- **Agent hold (`sprite-codex.sh`)**: follows the managed Codex/Kimi runner and has a configured hard deadline. It ends when the runner exits or when that hard deadline is reached.
- **Manual hold (`keepalive.sh`)**: runs independently inside the Sprite and continues until its own hard deadline, even if no Codex/Kimi session is attached from the local terminal.

They can coexist. Stopping the manual keepalive does not stop Codex/Kimi, and ending a Codex/Kimi session does not automatically remove an unrelated manual keepalive.

---

## 2. Important keep-awake terminology

Both scripts distinguish between the **rolling Tasks API lease** and the **real hard deadline**.

### Rolling Tasks API lease

The scripts register a task with:

```text
expire = 5m
```

and refresh that task approximately once per minute.

The `expires_at` value returned by the Sprite Tasks API therefore normally shows only the next short rolling lease. It is **not** the total number of hours requested by the user.

### Hard deadline

Each script separately records the absolute deadline at which it must stop refreshing its task.

For example, if you request an eight-hour hold:

```text
hard deadline = now + 8 hours
rolling task lease = about 5 minutes, refreshed every ~60 seconds
```

This distinction is the reason `keepalive.sh` does not simply display the Tasks API `expires_at` field when deciding how long a Sprite is expected to remain held awake.

### Native TTY activity is separate

A live native Sprite TTY session is itself activity. Therefore, when the `sprite-codex.sh` Tasks hold reaches its hard cap, this does **not** guarantee that the Sprite will immediately become idle if the Codex/Kimi TTY session is still alive.

---

# `sprite-codex.sh`

## 3. Purpose

`sprite-codex.sh` is the main one-Sprite coding-agent bootstrap and session manager.

Its normal job is to:

1. choose the coding agent;
2. choose an existing Sprite;
3. discover and reattach to an already-running managed TTY when one exists;
4. prepare the Sprite's tools and project workspace when a new run is required;
5. establish process-scoped GitHub and Fly.io credentials;
6. configure the selected model provider;
7. synchronize the local `./workspace/` tree into the Sprite project when safe;
8. compare the Sprite Git repository with GitHub and optionally push pending work;
9. verify that the selected agent/provider can actually operate;
10. launch the agent in a native detachable Sprite TTY; and
11. maintain a bounded Tasks API keep-awake heartbeat while the agent runner remains alive.

The script intentionally uses **one selected Sprite per invocation**. All setup, repository operations, provider services, task heartbeats, and agent commands target that Sprite only.

---

## 4. Supported agents and providers

### Codex

When **Codex** is selected, the script supports four provider modes:

| Provider | Behavior |
|---|---|
| OpenAI | Normal Codex provider and Codex authentication on the Sprite |
| DeepSeek V4 Pro | Codex configured for `deepseek-v4-pro`; direct Responses is probed first and a local bridge is used when necessary |
| Kimi K3 | Codex uses Moonshot/Kimi K3 through a local Responses adapter; Formula web search is exposed through a helper |
| MiniMax M3 | Codex uses MiniMax M3 through its native OpenAI-compatible Responses API |

### Kimi Code

The script can alternatively launch the **official Kimi Code CLI** as a first-class agent.

Kimi Code uses its own normal login mechanism. Authentication is performed inside Kimi Code with `/login`; the bootstrap does not translate that credential into Codex-style provider variables.

Supported Kimi Code startup modes are:

- start a new session;
- continue the most recent Kimi Code session.

Supported approval modes are:

- `normal`;
- `yolo`;
- `auto`.

---

## 5. Native Sprite TTY session management

The normal interactive path is **tmux-free**.

New agents run directly inside a native detachable Sprite TTY. The script gives each managed run a deterministic tag based on the current local project path, for example:

```text
sprite-codex-native-<project-hash>
sprite-kimi-code-native-<project-hash>
```

This lets the script distinguish Codex and Kimi Code sessions even when they use the same repository.

### Existing-session detection

Before asking for GitHub, Fly.io, or provider credentials, the script reads and validates the Sprite `/exec` session inventory.

If an existing managed native session is found, it offers to attach to that session instead of performing a new bootstrap. This is the fast resume path and avoids unnecessary credential prompts and workspace mutations.

The local resume-state file is treated as a **hint**, not as proof that a remote session is alive. The live Sprite session API remains authoritative.

### Detaching

Detach from a native Sprite TTY without stopping the remote agent with:

```text
Ctrl+\
```

The agent continues running on the Sprite.

### Reattaching

You can rerun `sprite-codex.sh`, which will rediscover the managed session, or attach directly when you know the session ID:

```bash
sprite sessions attach <session-id>
```

### Transport recovery

If the local TTY transport ends with a non-zero transport error, the script checks whether the same remote session ID is still alive. When enabled, it automatically reattaches to that **same** native Sprite TTY rather than starting a duplicate agent.

A clean detach is treated differently from a transport failure.

### Duplicate-session protection

The script validates live-session inventory before deciding that no session exists. An unknown or malformed inventory is not interpreted as an empty inventory.

`FORCE_NEW_SESSION=1` can be used to replace managed sessions, but existing sessions are not silently killed: interactive confirmation is required.

A legacy tmux guard also remains for older v31-and-earlier managed Codex sessions so a native session is not accidentally started alongside an old tmux-managed one.

---

## 6. Codex conversation start modes

For a new native Codex TTY, the script supports:

### Resume

```bash
codex resume --last
```

Loads the most recent Codex conversation.

### Fork

```bash
codex fork --last
```

Copies the recent conversation history into a new writable thread. This is useful when the original conversation reports an active writer or cannot safely be resumed.

### New

Starts a fresh Codex conversation while preserving the repository, files, Git state, and older Codex conversation files on disk.

If a resume attempt fails, the script does not delete conversation state or automatically kill Codex-like processes. It reports the observed processes and can offer to fork the conversation instead.

---

## 7. Codex installation and updating

The script checks the Codex version available on the Sprite and maintains a resolver at:

```text
~/.local/bin/sprite-codex-cli
```

The resolver examines multiple possible Codex installations, including user-local, system, and Sprite/NVM locations, and selects the highest usable semantic version.

If no suitable Codex installation is available, or the version is below `MIN_CODEX_VERSION`, the script installs/upgrades Codex into the Sprite user's persistent `~/.local` prefix.

An optional pre-run latest-stable Codex update is offered before an existing managed Codex session is attached or a new one is launched. A live Codex session triggers extra protection before an update is permitted.

The runner also detects a verified Codex executable/version change after the TUI exits. When an in-app update has replaced Codex, it can relaunch the updated executable and resume the same conversation, with a guard against endless update/relaunch loops.

---

## 8. Sprite preparation

Before a new agent is launched, the remote setup verifies or installs the required base tools.

For Codex runs this includes, as needed:

- Git;
- curl;
- Python 3;
- tar;
- Node.js;
- npm;
- Codex;
- Fly CLI;
- provider-specific adapter tooling when required.

For Kimi Code runs, the script installs or verifies the official Kimi Code CLI in its canonical user location and provides a stable wrapper at:

```text
~/.local/bin/sprite-kimi-code
```

The script persists non-secret PATH configuration in the Sprite user's shell startup files so the installed user tools remain discoverable in later shells.

---

## 9. GitHub repository handling

The Sprite workspace is GitHub-backed.

The script accepts or detects a repository in:

```text
OWNER/REPO
```

format and asks for a repository-scoped GitHub PAT. The intended token is a fine-grained PAT limited to that repository with sufficient Contents read/write permission.

The repository bootstrap can:

- clone the requested repository when necessary;
- repair or normalize the existing Sprite repository;
- set the expected GitHub origin;
- preserve existing workspace files where the repair path requires an overlay;
- fetch and prune the origin;
- establish branch tracking;
- configure a local commit identity when one is absent;
- verify read access with `git ls-remote`;
- perform a dry-run push capability check without modifying the remote.

A persistent Git credential-helper **program** is installed on the Sprite, but it reads the token from the process environment. The GitHub token itself is not written into the remote URL or a credential file by this bootstrap.

### Pre-launch repository comparison

After workspace preparation, the script compares the active branch with its same-named branch on GitHub and reports:

- current branch;
- whether the remote branch exists;
- commits ahead;
- commits behind;
- uncommitted/untracked changes.

Depending on `REPO_PUSH_MODE`, it can optionally stage, commit, and push all pending local changes before launching the agent.

Safety rules include:

- no automatic force-push;
- no automatic push over a remote branch that has moved ahead;
- divergent local/remote history must be resolved manually;
- detached HEAD is not automatically pushed.

---

## 10. Shared Codex + Kimi Code workspace behavior

Codex and Kimi Code deliberately use separate native TTY tags but may share the same repository checkout.

When a peer managed agent is already live, `SHARED_WORKSPACE_MODE=auto` normally chooses **reuse** for the same remote workspace.

In reuse mode, the second bootstrap avoids repository mutations that could interfere with the first agent. It skips operations such as:

- fetch/repair of the working tree;
- local workspace overlay;
- startup commit/push operations.

Both agents may then edit the same working tree, so they should be given non-overlapping tasks and Git status should be inspected regularly.

`SHARED_WORKSPACE_MODE=sync` deliberately permits synchronization even while the peer is live and should be used only when that risk is intentional.

---

## 11. Local `./workspace/` upload

For a normal new-agent bootstrap, the script recursively uploads the contents of:

```text
./workspace/
```

from the local project directory into:

```text
<remote-project-root>/workspace/
```

The archive preserves nested directories, hidden entries, symlinks, and executable bits.

This is an **overlay**, not a remote mirror/delete operation. Existing remote-only files are not intentionally removed simply because they are absent from the local `workspace/` tree.

The upload is skipped when shared-workspace reuse is active because another managed agent may already be editing the same repository.

---

## 12. Fly.io integration

The script accepts or detects a Fly application name and asks for an app-scoped Fly token.

It installs/verifies the Fly CLI on the Sprite and runs a real `fly status --app <app>` capability check before the coding agent starts.

Both `FLY_API_TOKEN` and the standard `FLY_ACCESS_TOKEN` alias are provided to the managed agent runner.

---

## 13. Credential and secret handling

GitHub, Fly.io, DeepSeek, Moonshot, and MiniMax credentials are intended to remain **process-scoped**.

The bootstrap:

- collects secrets interactively with hidden input unless supplied through environment variables;
- serializes the permitted credential environment as JSON;
- hex-encodes it into a delimiter-safe `SPRITE_CODEX_ENV_HEX` value for transport;
- decodes it only inside the Sprite process;
- passes only the intended values into the managed runner;
- removes unrelated secret-looking inherited variables from the agent environment;
- does not print raw credential values in its capability checks.

The encoded environment remains secret-equivalent and can briefly be visible in local process arguments while `sprite exec` is being invoked.

Provider-specific behavior:

- **OpenAI Codex** uses Codex's normal authentication store on the Sprite.
- **Kimi Code** owns its standard Kimi Code login state.
- **DeepSeek / Moonshot / MiniMax** API keys are supplied to the relevant provider process tree rather than persisted as ordinary credential files by the bootstrap.

The script installs a `sprite-auth-check` helper that reports credential presence/capability without printing raw secrets.

---

## 14. Provider-specific setup

### OpenAI

OpenAI mode uses normal Codex authentication and a wrapper configured for the managed environment.

Before launch, the script verifies normal Codex operation with an ephemeral preflight that also checks GitHub-origin access.

If authentication fails — including the case where the current ChatGPT/Codex account has reached a usage or credit limit — interactive recovery can:

1. rerun device-code login;
2. optionally clear the Sprite's stored Codex credentials first so a different account can be selected; and
3. rerun the same preflight.

The recovery loop can be repeated until a working account is selected or the user aborts. Non-interactive runs remain fail-fast.

### DeepSeek V4 Pro

The script probes the native DeepSeek Responses endpoint.

If the native path is accepted, direct transport is used. Otherwise it can configure the local bridge path used by the Codex profile. Authentication failures are treated as errors rather than silently falling back.

### Kimi K3 through Codex

The script configures a local Responses adapter/gateway backed by Moonshot/Kimi K3. Formula web search is exposed through:

```text
sprite-kimi-web-search
```

The Moonshot API key remains with the gateway/adapter process tree and is deliberately excluded from ordinary Codex shell-tool access.

### MiniMax M3

MiniMax M3 is configured through its native OpenAI-compatible Responses API. It does not require the CodeProxy-style adapter used by some other custom providers.

---

## 15. Preflight verification

Before opening the final interactive TTY, the script verifies the actual selected environment.

Depending on the agent/provider this includes checks such as:

- GitHub origin exists and is reachable;
- GitHub token/capability is present in the long-running runner;
- Fly token/app access works;
- selected provider can return the expected Codex preflight response;
- Kimi Code is installed and usable;
- the chosen provider launcher/profile is the one actually executed.

`NO_AGENT_LAUNCH=1` can be used to perform setup and preflight without opening an interactive agent TUI.

---

## 16. Agent Tasks API keep-awake hold

When a new managed TTY session is launched, `sprite-codex.sh` starts a heartbeat associated with the session tag.

The runner writes non-secret hold state under:

```text
~/.local/state/sprite-codex/
```

Important files include:

```text
hold-state-<session-tag>
hold-deadline-<session-tag>
hold-released-<session-tag>.marker
hold-ended-<session-tag>.marker
runner-pid-<session-tag>
provider-<session-tag>
workdir-<session-tag>
```

The heartbeat:

1. registers a five-minute Tasks API hold;
2. refreshes it approximately once per minute;
3. continues only while the managed runner is alive;
4. stops refreshing when the configured hard deadline is reached;
5. deletes its task when the runner exits.

When the hard cap is reached while the coding agent is still alive, the state becomes `released`, but the native TTY itself may still count as activity.

`SPRITE_RUN_HOURS` therefore means **maximum Tasks-heartbeat duration**, not a guaranteed total VM runtime.

---

## 17. Basic `sprite-codex.sh` usage

Interactive:

```bash
bash sprite-codex.sh
```

Typical non-interactive selections can be supplied through environment variables, for example:

```bash
CODING_AGENT=codex \
CODEX_PROVIDER=openai \
SPRITE_NAME=my-sprite \
SPRITE_RUN_HOURS=8 \
bash sprite-codex.sh
```

Kimi Code example:

```bash
CODING_AGENT=kimi-code \
KIMI_CODE_APPROVAL_MODE=normal \
SPRITE_RUN_HOURS=8 \
bash sprite-codex.sh
```

Setup/preflight without opening the final TUI:

```bash
NO_AGENT_LAUNCH=1 bash sprite-codex.sh
```

---

## 18. Important `sprite-codex.sh` environment variables

### Target and agent selection

| Variable | Purpose |
|---|---|
| `CODING_AGENT=ask|codex|kimi-code` | Select agent |
| `CODEX_PROVIDER=ask|openai|deepseek|kimi|minimax` | Select Codex provider |
| `SPRITE_NAME` | Request a particular existing Sprite |
| `SPRITE_ORG` | Pass a Sprites organization to the CLI |
| `SPRITE_WORKDIR` | Override the absolute remote project root |
| `SPRITE_RUN_HOURS` | Maximum agent Tasks-heartbeat duration |

### Session behavior

| Variable | Purpose |
|---|---|
| `CODEX_START_MODE=ask|resume|fork|new` | How a new Codex TTY should open the conversation |
| `KIMI_CODE_START_MODE=ask|continue|new` | Kimi Code session behavior |
| `KIMI_CODE_APPROVAL_MODE=normal|yolo|auto` | Kimi Code approval mode |
| `FORCE_NEW_SESSION=1` | Explicitly request managed-session replacement |
| `TTY_AUTO_REATTACH=1|0` | Enable/disable automatic same-session reattachment |
| `TTY_REATTACH_ATTEMPTS` | Maximum consecutive reattach failures; `0` means unlimited |
| `TTY_REATTACH_CONFIRM_TRIES` | Bounded live-session confirmation attempts |
| `TTY_REATTACH_DELAY` | Delay between reattach attempts |

### Shared workspace

| Variable | Purpose |
|---|---|
| `SHARED_WORKSPACE_MODE=auto|reuse|sync` | Controls repository mutation when the peer agent is already live |

### Repository and deployment

| Variable | Purpose |
|---|---|
| `GITHUB_REPOSITORY=OWNER/REPO` | GitHub repository |
| `GITHUB_PAT` | Repository-scoped PAT |
| `FLY_APP` | Fly.io app |
| `FLY_API_TOKEN` | Fly.io token |
| `REPO_PUSH_MODE=ask|always|never` | Whether to commit/push pending Sprite work before launch |
| `REPO_PUSH_COMMIT_MESSAGE` | Commit message used by automatic push |

### Provider credentials/configuration

| Variable | Purpose |
|---|---|
| `DEEPSEEK_API_KEY` | DeepSeek credential |
| `DEEPSEEK_TRANSPORT=auto|direct|bridge` | DeepSeek transport policy |
| `MOONSHOT_API_KEY` | Kimi K3/Moonshot credential |
| `MOONSHOT_BASE_URL` | Moonshot API base URL |
| `KIMI_MODEL` | Kimi model used by Codex adapter |
| `KIMI_FORMULA_URI` | Formula search backend |
| `MINIMAX_API_KEY` | MiniMax credential |
| `MINIMAX_BASE_URL` | MiniMax API base URL |
| `MINIMAX_MODEL` | MiniMax model |

### Codex setup and preflight

| Variable | Purpose |
|---|---|
| `MIN_CODEX_VERSION` | Minimum accepted Codex version |
| `CODEX_PREFLIGHT_TIMEOUT` | Hard timeout for provider preflight |
| `CODEX_UPDATE_MODE=ask|always|never` | Pre-run latest-stable update behavior |
| `CODEX_UPDATE_LIVE_OVERRIDE=1` | Explicit non-interactive override for updating with live Codex state |
| `NO_AGENT_LAUNCH=1` | Stop after setup/preflight |

### Control transport

| Variable | Purpose |
|---|---|
| `SPRITE_CONTROL_TIMEOUT` | Timeout for bounded control operations |
| `SPRITE_CONNECT_TRIES` | Number of connection attempts |
| `SPRITE_CONTROL_TRANSPORT=auto|websocket|http-post` | Non-TTY Sprite control transport |

The script contains additional tuning variables for Kimi request pacing, adapter ports, Formula rounds, and completion limits. See the variable block near the top of the script for the current complete set.

---

# `keepalive.sh`

## 19. Purpose

`keepalive.sh` maintains a selected Sprite in a running state for a user-chosen period **without requiring the coding-agent launcher to remain active**.

Its revised startup behavior is intentionally decision-oriented: before changing anything, it displays the current Sprite inventory and the best-known remaining hard timeout for each already-running Sprite.

This lets you answer the practical question:

> “Does this Sprite already have enough keep-awake time remaining, or do I actually need to extend it?”

---

## 20. Read-only inventory

Run:

```bash
bash keepalive.sh inventory
```

or simply:

```bash
bash keepalive.sh
```

The script first discovers the current Sprite inventory and displays columns similar to:

```text
SPRITE        STATE      HOLD REMAINING    HARD DEADLINE (UTC)    SOURCE / TASKS
my-sprite     running    6h 24m            2026-09-01 02:41 UTC   codex:sprite-codex-native-...; tasks=1
other         warm       -                 -                      not probed (avoids wake)
```

### Discovery strategy

The script does not trust a cached Sprite name.

Every invocation resolves the current inventory again using:

1. the structured Sprite API; then
2. `sprite list` as a fallback.

A supplied `SPRITE_NAME` is accepted only if it can be confirmed against the current inventory when discovery succeeds.

### Avoiding accidental wake-ups

For each Sprite, `keepalive.sh` first reads its lifecycle state through the control plane.

It performs the deeper `sprite exec` hold probe **only when the Sprite is already reported as `running`**.

Warm, cold, stopped, paused, or suspended Sprites are not exec-probed merely to inspect their hold, because the exec itself could wake the Sprite and defeat the purpose of a read-only status check.

---

## 21. How inventory determines remaining time

For an already-running Sprite, the script reads:

- current Tasks API records;
- `keepalive.sh` deadline state; and
- `sprite-codex.sh` agent-hold state.

Known manual keepalive deadlines are read from:

```text
~/.local/state/sprite-keepalive/*.deadline
```

Known coding-agent deadlines are read from:

```text
~/.local/state/sprite-codex/hold-state-*
~/.local/state/sprite-codex/hold-deadline-*
```

A deadline is treated as meaningful only when it corresponds to an active Tasks API task and the recorded hold state is still valid.

When multiple known holds exist, the inventory reports the **latest known hard deadline**, because that is the best indication of how long a known helper will continue holding the Sprite awake.

### `unknown*`

If the Sprite has an active Tasks API task but `keepalive.sh` cannot find the longer-term hard deadline that owns it, the inventory displays an `unknown*` style result instead of falsely presenting the short rolling task lease as the true remaining runtime.

---

## 22. Safe default startup behavior

Running:

```bash
bash keepalive.sh
```

shows the inventory first and then asks:

```text
Start or extend a keep-awake hold after reviewing the table? [y/N]:
```

The default is **No**.

Pressing Enter leaves all existing Sprite holds unchanged.

This is the recommended interactive mode when you want to inspect the current remaining time before deciding whether an extension is necessary.

---

## 23. Explicit keepalive start

To explicitly request a duration from now:

```bash
bash keepalive.sh start 8
```

This still shows the inventory first, but `start 8` is treated as an explicit request to proceed.

If no duration is supplied after opting in interactively, the script asks for a duration and defaults to five hours.

Positive fractional hours are accepted as long as the resulting duration is at least 60 seconds.

### Existing later deadline is preserved

Starting the same manual task again will **not shorten** an existing later manual deadline.

For example, if the existing manual hold ends in ten hours and you run:

```bash
bash keepalive.sh start 2
```

that two-hour request does not reduce the ten-hour deadline.

Use `stop` when you intentionally want to release the manual hold.

---

## 24. Workspace upload performed by `keepalive.sh`

By default, `start` also uploads the local:

```text
./workspace/
```

tree into:

```text
<remote-project-root>/workspace/
```

before starting the manual hold.

The upload:

- preserves nested paths;
- includes dotfiles;
- preserves symlinks without dereferencing them;
- preserves executable bits;
- overlays the remote tree rather than deleting remote-only files.

Disable this behavior with:

```bash
SPRITE_UPLOAD_WORKSPACE=0 bash keepalive.sh start 8
```

The remote project root defaults to:

```text
$HOME/workspaces/<current-local-directory-name>
```

and can be overridden with an absolute `SPRITE_WORKDIR`.

---

## 25. Manual heartbeat implementation

The manual keepalive stores state under:

```text
~/.local/state/sprite-keepalive/
```

For the default task name `manual-keepalive`, it manages files such as:

```text
manual-keepalive.pid
manual-keepalive.deadline
manual-keepalive.last-ok
manual-keepalive.fail-count
manual-keepalive-heartbeat.sh
manual-keepalive-service-runner.sh
manual-keepalive.log
manual-keepalive-service-start.log
```

The default Sprite Service name is:

```text
keepalive-manual-keepalive
```

### Startup sequence

The script:

1. establishes an initial five-minute Tasks API hold synchronously;
2. writes the chosen hard deadline;
3. attempts to run the heartbeat as a Sprite Service when services are available and enabled;
4. verifies the Service by checking its process, first successful refresh, task record, and Service state;
5. falls back to a detached `nohup`/`setsid` heartbeat process if the Service cannot become healthy;
6. refuses to create a duplicate heartbeat when an old/partial Service cannot be safely removed.

The runtime is considered healthy only after a new heartbeat process has actually refreshed the task and the task can be read back from the API.

### Refresh loop

Approximately every minute, the heartbeat renews:

```text
expire = 5m
```

and records:

- the last successful refresh epoch;
- the number of consecutive failures;
- heartbeat log entries.

At the hard deadline it releases the Tasks API task and exits.

### Sprite Service limitation

When the Service path is used, the service definition can restart the heartbeat on a future Sprite wake. It cannot autonomously wake a Sprite after the Tasks API hold has already lapsed.

---

## 26. `keepalive.sh status`

Run:

```bash
bash keepalive.sh status
```

After selecting the target Sprite, status reports detailed diagnostics for this helper's task, including:

- Sprite hostname;
- managed task name;
- managed Service name;
- detached heartbeat PID state;
- Sprite Service definition/state;
- recorded hard deadline;
- remaining requested hold time;
- last successful refresh time and age;
- consecutive refresh failures;
- this helper's current Tasks API record;
- all current Tasks API holds on the Sprite;
- recent heartbeat log;
- recent Sprite Service log.

Warnings are emitted when the heartbeat runtime appears active but its task record is missing, or when a recorded refresh is unexpectedly stale.

---

## 27. `keepalive.sh stop`

Run:

```bash
bash keepalive.sh stop
```

This releases **only the selected manual keepalive task managed by this helper**.

It stops/deletes the matching heartbeat Service/process, removes its task from the Tasks API, and clears its own deadline/refresh state.

It does **not** intentionally stop:

- Codex;
- Kimi Code;
- unrelated native TTY sessions;
- other Sprite Services;
- other Tasks API holds.

---

## 28. `keepalive.sh` commands

| Command | Behavior |
|---|---|
| `bash keepalive.sh` | Show inventory, then optionally start/extend; default is no action |
| `bash keepalive.sh inventory` | Read-only inventory; never changes a hold |
| `bash keepalive.sh start 8` | Show inventory, then explicitly request an 8-hour manual hold |
| `bash keepalive.sh status` | Inspect this helper's hold on the selected Sprite |
| `bash keepalive.sh stop` | Release only this helper's hold |

---

## 29. `keepalive.sh` environment variables

| Variable | Default | Purpose |
|---|---:|---|
| `SPRITE_NAME` | empty | Request a particular currently-existing Sprite |
| `SPRITE_ORG` | empty | Pass `-o <organization>` to the Sprite CLI |
| `SPRITE_KEEPALIVE_HOURS` | interactive | Default start duration |
| `SPRITE_TASK_NAME` | `manual-keepalive` | Tasks API task name managed by this helper |
| `SPRITE_KEEPALIVE_USE_SERVICE` | `1` | Prefer a Sprite Service over detached-process fallback |
| `SPRITE_UPLOAD_WORKSPACE` | `1` | Upload local `./workspace/` before `start` |
| `SPRITE_WORKDIR` | derived | Absolute remote project root override |

`SPRITE_TASK_NAME` is restricted to letters, digits, dot, underscore, and hyphen.

---

# 30. Recommended operating patterns

## Start or resume coding work

```bash
bash sprite-codex.sh
```

If a managed TTY already exists, reattach to it. Otherwise complete the bootstrap and start a new agent session.

## Check whether the Sprite already has enough time remaining

```bash
bash keepalive.sh inventory
```

If the known remaining hard cap is sufficient, do nothing.

## Inspect and optionally extend interactively

```bash
bash keepalive.sh
```

Review the table. Press Enter to make no change, or answer `y` and select the Sprite/duration.

## Explicitly keep a Sprite awake for another eight hours

```bash
bash keepalive.sh start 8
```

## Keep the Sprite awake without uploading local workspace files

```bash
SPRITE_UPLOAD_WORKSPACE=0 bash keepalive.sh start 8
```

## Diagnose a manual hold

```bash
bash keepalive.sh status
```

## Release the manual hold without touching the coding session

```bash
bash keepalive.sh stop
```

---

# 31. State and persistence summary

## Local machine

`sprite-codex.sh` keeps non-secret resume metadata locally so a later invocation can recognize the previous target/session as a hint. Live Sprite APIs remain authoritative and stale saved state is discarded when the referenced Sprite no longer exists.

Secrets supplied interactively are not intended to be written into that resume state.

## Sprite

### `sprite-codex.sh`

Persistent/non-secret support files are primarily placed under:

```text
~/.local/bin/
~/.local/state/sprite-codex/
~/.config/sprite-codex/
~/.codex/
```

The exact Codex auth contents under `~/.codex/` are owned by Codex itself in normal OpenAI mode.

### `keepalive.sh`

Manual keepalive state lives under:

```text
~/.local/state/sprite-keepalive/
```

Service logs may also be available under the Sprite service-log directory.

---

# 32. Failure-safety philosophy

Both scripts are intentionally conservative around ambiguous remote state.

Examples include:

- a stale saved Sprite name does not override the current Sprite inventory;
- an unreadable native session inventory is not treated as “no sessions”;
- existing agent sessions are not silently killed;
- `keepalive.sh` does not wake warm/cold Sprites merely to inspect them;
- the manual keepalive refuses duplicate heartbeat runtimes after an unhealthy Service that cannot be removed;
- Git synchronization will not force-push over divergence;
- credentials are capability-checked without printing raw secrets;
- transport operations are bounded where possible;
- non-zero TTY transport failure attempts recovery of the same remote session rather than immediately creating a replacement.

---

# 33. Requirements

## Local machine

For `sprite-codex.sh`:

- Bash 4 or newer;
- `sprite` CLI;
- Python 3;
- tar;
- an interactive terminal for the final TUI.

Git on the local machine is useful for automatic GitHub repository detection, but the repository can also be supplied explicitly.

On macOS, the system Bash may be too old. Install a newer Bash and invoke the script with that executable.

For `keepalive.sh`:

- Bash;
- `sprite` CLI;
- Python 3;
- tar when workspace upload is enabled.

## Sprite

The main launcher verifies or installs the remote tools it needs when a supported package/install path is available. The Sprite must permit normal `sprite exec` operations and access to its local control socket/Tasks API for the heartbeat features.

---

# 34. Security recommendations

- Use a **fine-grained GitHub PAT** scoped only to the required repository.
- Give that PAT only the permissions actually required; the launcher expects read/write repository Contents capability when push support is wanted.
- Use an **app-scoped Fly token**, preferably with a short expiry.
- Treat `SPRITE_CODEX_ENV_HEX` as a secret because it is only an encoding, not encryption.
- Avoid exporting long-lived provider credentials globally when interactive hidden prompts are practical.
- Do not copy diagnostic command lines containing secret-equivalent encoded environment values into public logs.
- Remember that normal OpenAI Codex authentication and Kimi Code authentication are owned by those CLIs and may have their own persistent login stores on the Sprite.

---

# 35. What these scripts deliberately do not do

They do not:

- create a Sprite;
- destroy a Sprite;
- automatically kill unrelated sessions;
- treat a short Tasks API `expires_at` lease as the true user-requested timeout;
- guarantee that a Sprite becomes idle immediately when a Tasks hold ends;
- force-push a diverged Git branch;
- use a cached Sprite name as authoritative live state;
- require tmux for normal new sessions.

---

## In short

Use **`sprite-codex.sh`** when you want to prepare or resume the coding environment and run Codex/Kimi Code in a robust detachable Sprite TTY.

Use **`keepalive.sh`** when you want to inspect the current live Sprites and their meaningful remaining keep-awake time, then optionally add or extend an independent manual hold without disturbing the coding session.

