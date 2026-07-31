# sandbox-install.sh usage

`sandbox-install.sh` bootstraps a self-contained shell environment under `/root/sandbox` (root) or `~/sandbox` (non-root) by default. You can run it directly from this repository or stream it via `curl | bash`. The sandbox stays opt‑in: it only activates for sessions where `SANDBOX_ENABLE=1` is present, so other users on the machine remain unaffected.

**Root is not required.** Everything under the sandbox directory is written as the invoking user. Only two things need elevation, and both degrade to a warning rather than aborting the run:

| Step | Without root |
| --- | --- |
| System package installs (`zsh`, `tmux`, `fzf`, `zoxide`, `unzip`, `xz`, `git`) | Skipped unless passwordless `sudo -n` works; already-present binaries are used as-is |
| `/etc/profile.d/sandbox.sh` hook | Skipped — use the `,` alias or `<sandbox-dir>/bin/sandbox-shell` instead |

Individual tool downloads are also best-effort: one failed release fetch no longer aborts the install, so the shell config, wrappers, and `,` alias always get written.

## Quickstart

> ShortURL: https://snas.short.gy/linux-init
> Redirects to:
> https://raw.githubusercontent.com/nascarsayan/init-linux/zinit/scripts/sandbox-install.sh

```bash
# Run locally, no root needed (installs to ~/sandbox)
scripts/sandbox-install.sh

# Or curl | bash
curl -fsSL https://snas.short.gy/linux-init | bash

# Install to a custom sandbox directory
curl -fsSL https://snas.short.gy/linux-init | bash -s -- --sandbox-dir "$HOME/dev"

# As root, if you want the system-wide /etc/profile.d hook and package installs
curl -fsSL https://snas.short.gy/linux-init | sudo bash -s -- --sandbox-dir /root/sayann/dev

# Remove the sandbox later
curl -fsSL https://snas.short.gy/linux-init | bash -s -- --cleanup

# Enable verbose debug trace
curl -fsSL https://snas.short.gy/linux-init | bash -s -- --debug

# Package-manager only install (no sandbox assets)
curl -fsSL https://snas.short.gy/linux-init | sudo bash -s -- --no-sandbox
```

### The `,` and `,,` shortcuts

The installer adds two aliases to the **invoking** user's rc file — resolved from `SUDO_USER` and their passwd login shell, so `sudo bash` still targets your own `~/.bashrc` rather than root's. Supported: bash (`.bashrc`), zsh (`.zshrc`), ksh (`.kshrc`), fish (`.config/fish/config.fish`), sh/dash (`.profile`).

| Alias | Does |
| --- | --- |
| `,` | Drops into the sandbox shell (`<sandbox-dir>/bin/sandbox-shell`) |
| `,,` | Attaches the sandbox tmux session, **creating it if it does not exist** |

`,,` uses `tmux new-session -A -s <socket>` rather than `attach -t`: `-A` attaches to an existing session and creates one otherwise, whereas `attach -t` fails with `no sessions` against a cold server. It also passes `TMUX_CONF`/`TMUX_CONF_LOCAL` and `-f`, which matter only on the create path — an already-running server has its config loaded — but without them a session first started by `,,` would come up with stock tmux config instead of the sandbox gpakosz one.

Both aliases are written into marker-delimited blocks and **repointed on every install**, so moving to a different `--sandbox-dir` updates them instead of leaving a dead path behind:

```bash
curl -fsSL https://snas.short.gy/linux-init | bash -s -- --sandbox-dir ~/dir1
rm -rf ~/dir1
curl -fsSL https://snas.short.gy/linux-init | bash -s -- --sandbox-dir ~/dir2
# ',' and ',,' now point at ~/dir2; no ~/dir1 references remain
```

An alias is only rewritten when it looks installer-generated — `,` pointing at a `*/bin/sandbox-shell`, `,,` at a socket-scoped `tmux`. That shape check is what lets an unmarked alias from an older installer (or one you wrote by hand in the same form) be adopted and refreshed. Anything else is treated as yours and left untouched:

```bash
alias ,='cd /my/project'   # survives; only ,, gets provisioned
```

`,` and `,,` are matched distinctly, so neither is mistaken for the other. Repeat installs do not accumulate lines or blank separators. For zsh, `ZDOTDIR` is honoured only when it points outside the sandbox — the sandbox's own `.zshrc` is regenerated on every run, so an alias placed there would be wiped by the next `sbox update`.

`--cleanup` removes both aliases, but only when they actually reference the sandbox being torn down — a user-authored alias, or one belonging to a second sandbox install elsewhere, is left alone.

### The `,gwq` review shortcut

```bash
,gwq <branch>            # existing branch
,gwq <pr-number>         # all digits -> that PR's head branch
,gwq -b <new-branch>     # new branch forked from the freshly fetched base
,gwq <arg> [base-branch] # override the base
```

Creates or reuses a `gwq` worktree, `cd`s into it, and prints the diff stat against the base.

The argument is interpreted by shape: **all digits means a PR number**, anything else a branch name. For a PR, `gh` supplies the head branch *and* the PR's own base, which is more accurate than guessing via `origin/HEAD`. Otherwise the base is `origin/HEAD`, then `main`, then `master`, and `[base-branch]` always wins.

With `-b` the base is fetched first and the new branch is forked from it, so you always branch from current upstream rather than a stale local ref. It refuses if the branch already exists, rather than silently handing you something that isn't fresh.

The logic lives in `<sandbox-dir>/bin/sbx-gwq-review`, which prints only the worktree path on stdout (all logging goes to stderr) so the rc-side shim is just a `cd "$(...)"`. `,gwq` has to be a shell function rather than an alias — it takes arguments and must `cd` the calling shell.

Behaviour worth knowing:

- **A PR's head branch is often missing from `refs/heads`.** Fork PRs never had one on your remote, and a merged PR's branch is usually deleted — true of both PR #784 and #866 here. `refs/pull/<n>/head` survives all of those, so PR mode falls back to it. `refs/heads` is still tried first, since it gives the branch a natural upstream.
- **A branch gone from the remote but still local** (the same post-merge deletion) degrades to a warning and uses the local branch, instead of failing.
- The local branch is created explicitly as a tracking branch rather than relying on `git worktree add`'s DWIM, which fails with `invalid reference` when more than one remote publishes the same branch name.
- An existing local branch strictly behind the remote is fast-forwarded; one that has **diverged** is left alone with a warning, so local work is never discarded. If the worktree has uncommitted changes nothing is moved.
- Re-running is safe: `gwq add` errors when the directory exists, so an existing worktree is reused.
- The resolved base is written to `<worktree-gitdir>/sbx-review-base` — inside the gitdir, not the working tree, so it can never appear in the diff you are reviewing.
- `SBX_REVIEW_REMOTE` overrides the remote (default `origin`).

### The `,rv` PR review shortcut

```bash
,rv                 # PR for the current branch
,rv <branch>        # PR for a named branch
,rv <number>        # that PR number directly
,rv -c <number>     # check the PR out via the extension
,rv -a              # also add this worktree as a folder in the current window
```

Opens the branch's pull request directly on its **Files Changed** view in VS Code, with inline comment gutters that post to GitHub. Pair it with `,gwq`:

```bash
,gwq sayann/my-feature   # worktree + cd, for building and navigating the code
,rv                      # review the PR for that branch
```

This works because the GitHub Pull Requests extension registers a URI handler. That is not discoverable from its `package.json` — there is no `onUri` activation event, since it activates on `onStartupFinished` — but `window.registerUriHandler` is in the bundle and accepts four paths, of which two are useful here:

| Path | Effect |
| --- | --- |
| `/open-pull-request-changes` | Open the PR's Files Changed view |
| `/checkout-pull-request` | Check the PR out |

The query may be JSON, or simply `?uri=<github pr url>`, which is what `,rv` uses:

```bash
code --open-url "vscode://GitHub.vscode-pull-request-github/open-pull-request-changes?uri=https://github.com/OWNER/REPO/pull/N"
```

The handler's regex requires exactly `https://github.com/<owner>/<repo>/pull/<number>`. Verified against extension version 0.163.

**Must be run from VS Code's integrated terminal** (Remote-SSH is fine) — that is what puts `code` on `PATH` with a live `VSCODE_IPC_HOOK_CLI`. A plain ssh or detached tmux shell has no window to talk to, and `,rv` fails with a clear message rather than hanging.

Both helpers bootstrap their own environment: the integrated terminal is a plain login shell where the sandbox `bin` is not on `PATH` and `gh`'s credentials are invisible (they live in `<sandbox-dir>/.config/gh`, not `~/.config/gh`), so each script prepends the sandbox `bin` and sets `GH_CONFIG_DIR` itself.

### Reaping merged worktrees: `,gcw`

```bash
,gcw            # remove worktrees whose PR is merged
,gcw --dry-run  # report only, change nothing
```

Also runs automatically, detached, whenever `,gwq` creates a **new** worktree. Its log is `<sandbox-dir>/cache/gwq-gc.log`.

Merged detection, in order:

1. **GitHub PR state is `MERGED`.** Authoritative, and the only signal that works with squash merges — a squash-merged branch is not an ancestor of the base, so a git-only check reports it as unmerged and would never reap anything. On `Cerebras/cluster` this is every PR.
2. Otherwise the branch tip is an ancestor of the base ref. Works offline.

Because it runs unattended it is deliberately conservative and skips: anything with uncommitted **or untracked** content, the base branch, the main worktree, whatever the main checkout has checked out, detached worktrees, any path outside gwq's `worktree.basedir`, and the worktree `,gwq` just created (passed as `--skip`).

Branch deletion uses `git branch -d`, falling back to `-D` only when a merged PR positively confirms the work already landed — which is required, since git considers a squash-merged branch unmerged.

Two traps worth knowing about, both of which silently broke earlier versions:

- **Path canonicalisation.** `git worktree list` reports resolved physical paths while gwq reports symlinked ones (on an NFS home `/cb/home/<user>/ws` is a symlink). Comparing them raw made the basedir guard match nothing, and made `--skip` fail to protect the worktree you just entered. Every path comparison is canonicalised with `readlink -f`.
- **The async spawn's redirections.** `,gwq` reads the helper's stdout via command substitution, which blocks until every holder of that pipe closes it. A background child inheriting stdout hangs the `cd` until gc finishes, so the child gets `>>log 2>&1 </dev/null` and `setsid`.

### Completions go stale silently

Two independent traps, both of which quietly broke `kubectl <TAB>` here for months.

**`compinit -C` never re-scans.** The `-C` flag is what keeps startup fast — it trusts the dumpfile and skips scanning `fpath` for new completion functions. The cost is that anything registered later is invisible forever. A dump sat two and a half months stale. The template now does one full rebuild whenever the dump is older than a day, and takes the fast path otherwise.

**zinit symlinks completions to absolute paths.** Each entry in `$ZINIT[COMPLETIONS_DIR]` points into the plugins dir by absolute path, so anything that moves that path — an NFS server rename, or relocating the sandbox — breaks every link at once. Here 179 of 180 pointed at a previous hostname. With `-C` this was completely silent; a full `compinit` instead emits hundreds of `no such file or directory` lines. The template now prunes dangling links on the daily rebuild and tells you to restore them:

```bash
zinit cclear                                  # drop dangling entries
zinit creinstall zsh-users/zsh-completions    # re-link at the current path
rm -f "$ZSH_COMPDUMP" && exec zsh             # rebuild the dump
```

Note that `kubectl` completion does not appear in the dump even when working: the OMZ plugin writes `_kubectl` into `$ZSH_CACHE_DIR/completions`, which only joins `fpath` after the turbo-loaded plugin runs — i.e. after `compinit`. The plugin sets `_comps[kubectl]` itself instead. Check it with `autoload -Uz +X _kubectl`, not by grepping the dump.

Aliases need no separate handling: `complete_aliases` is off, so zsh completes `k` and `kgp` by expanding them to `kubectl`.

### When `dnf` can only see an unreachable internal mirror

On hosts whose only configured repo is a down internal mirror:

```
Errors during downloading metadata for repository 'local-yum':
  - Curl error (7): Couldn't connect to server ... Connection refused
```

`install_pkg` retries automatically against the public Rocky mirror using an ephemeral `--repofrompath`, with `--nogpgcheck` and `sslverify=0`. Nothing is written to `/etc/yum.repos.d`, so the host's repo config is untouched. This is a deliberate trade-off for bootstrapping a dev sandbox over a trusted network — do not copy the pattern into production provisioning. To do it by hand:

```bash
dnf --disablerepo='*' \
  --repofrompath='pub-baseos,https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/' \
  --repofrompath='pub-appstream,https://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/' \
  --setopt=sslverify=0 --nogpgcheck -y install zsh tmux
```

## What the installer does (sandbox mode)

- Creates `/root/sandbox` with `bin`, `cache`, `zsh`, `zinit`, `tmux`, `fzf`, `p10k`, and `krew` subdirectories.
- Downloads static binaries (crush, croc, codex, gh, fzf, zoxide, k9s, kubecolor, sysz) into `/root/sandbox/bin`, falling back to pinned versions when GitHub rate-limits.
- Installs zinit under `/root/sandbox/zinit` without touching other users.
- Copies `templates/zshrc-tpl.zsh` into `/root/sandbox/zsh/.zshrc`. If the file is missing locally, it falls back to the remote template or a minimal stub.
- Clones `gpakosz/.tmux` and `nascarsayan/.tmux.local` under `/root/sandbox/tmux`, wiring tmux to use those configs only when the sandbox is active.
- Drops your Powerlevel10k profile into `/root/sandbox/p10k/p10k.zsh`, so the wizard never appears. This file is **always overwritten** from `templates/p10k.zsh` (or the published copy) — the template is the single source of truth. Regenerate it with `p10k configure` and copy the result back into `templates/p10k.zsh`. A failed download leaves the existing file untouched, so a network blip cannot wipe a working prompt.
- Bootstraps `krew` inside `/root/sandbox/krew`, installs the `tree` and `stern` plugins, and keeps everything scoped to the sandbox.
- Writes `/root/sandbox/activate.sh`, `/etc/profile.d/sandbox.sh`, and shell helpers (`sandbox-login`, `sssh`, `sbox`). Activation only happens when `SANDBOX_ENABLE=1` is present in the environment.

With `--no-sandbox`, the script simply ensures `zsh`, `tmux`, `fzf`, and `zoxide` are installed through the system package manager (apt/dnf/brew) and exits—no sandbox directories or profile hooks are created.

## Using the environment

```bash
# Opt in when SSHing
SANDBOX_ENABLE=1 ssh root@host

# Or enable the sandbox in an existing shell
export SANDBOX_ENABLE=1
source /root/sandbox/activate.sh

# Jump into the sandboxed zsh profile
zsh -i
```

Once activated, binaries reside in `/root/sandbox/bin`, `ZDOTDIR=/root/sandbox/zsh`, tmux reads `/root/sandbox/tmux/.tmux.conf`, and `Ctrl-R` is backed by the sandboxed fzf bindings. Other users stay on their stock PATH/configs. You can also launch the sandbox directly via `/root/sandbox/bin/sandbox-login`, which runs `activate.sh` and drops you into `zsh -il`.

`sbox` lifecycle helper:

```bash
# Update all sandbox binaries/config in place
/root/sandbox/bin/sbox update

# Launch sandbox login shell
/root/sandbox/bin/sbox shell

# Sandbox SSH helper passthrough
/root/sandbox/bin/sbox ssh root@host

# Install/update Claude Code toolchain:
# - n (if missing) + latest Node.js
# - bun (if missing)
# - @anthropic/claude-code via bun
/root/sandbox/bin/sbox install claude-code
```

Example SSH config entry:

```ssh-config
Host sandbox
  HostName <server>
  User root
  RemoteCommand /root/sandbox/bin/sandbox-login
  RequestTTY force
```

## Testing with Docker

The `docker/rocky8/` harness exercises the installer on Rocky Linux 8.

```bash
# Build the test image
docker build -t sandbox/init-rocky8 -f docker/rocky8/Dockerfile .

# Run the installer once
docker run --rm sandbox/init-rocky8 bash -lc '/usr/local/src/sandbox-install.sh'

# Inspect the generated config
docker run --rm sandbox/init-rocky8 bash -lc 'ls /root/sandbox/zsh && head -n 10 /root/sandbox/zsh/.zshrc'

# Exercise the shell interactively (first run fetches zinit plugins)
docker run --rm -it -e SANDBOX_ENABLE=1 \
  sandbox/init-rocky8 bash -lc '/usr/local/src/sandbox-install.sh && source /root/sandbox/activate.sh && exec zsh -i'

# Two-step workflow
container=sandbox-test

docker run -d --rm --name "$container" -e SANDBOX_ENABLE=1 \
  sandbox/init-rocky8 bash -lc '/usr/local/src/sandbox-install.sh && tail -f /dev/null'

docker exec "$container" bash -lc 'source /root/sandbox/activate.sh && echo PATH=$PATH && echo ZDOTDIR=$ZDOTDIR && echo TMUX_CONF=$TMUX_CONF && command -v crush croc codex gh fzf zoxide tmux && ls -A /root/sandbox/p10k'

docker stop "$container"
```

## Config knobs

- `SANDBOX_HOME` / `--sandbox-dir`: install root (defaults to `/root/sandbox`).
- `SANDBOX_TEMPLATE_URL`: override the remote `.zshrc` template URL when the local copy is absent.
- `SANDBOX_TMUX_TEMPLATE_URL`: override the fallback tmux config URL.
- `SANDBOX_TMUX_SOCKET`: tmux socket name used by the sandbox tmux alias (defaults to `sayann`).
- `SANDBOX_P10K_TEMPLATE_URL`: override the fallback Powerlevel10k config URL.
- `GITHUB_TOKEN`: optional token used for GitHub API `releases/latest` lookups to reduce rate-limit fallbacks.
- `SANDBOX_ENABLE`: opt-in flag honoured by `/etc/profile.d/sandbox.sh` and tests.
- `FZF_VERSION`: override the fzf release version downloaded into the sandbox.

## Notes

- Sandbox mode does **not** require root. Run as root only if you want system package installs and the `/etc/profile.d` hook; without it those two steps warn and are skipped.
- Re-running the sandbox installer is idempotent; binaries are overwritten in place and configs re-copied. The `,`/`,,` aliases and the sandbox alias block are marker-guarded, so repeat runs never duplicate them, and installing into a new `--sandbox-dir` repoints the aliases rather than stranding them on the old path.
- Hand edits to `<sandbox-dir>/zsh/.zshrc` and `<sandbox-dir>/p10k/p10k.zsh` are **overwritten** on every run — make changes in `templates/zshrc-tpl.zsh` / `templates/p10k.zsh` instead.
- The published template is what `curl | bash` actually fetches; local edits to `templates/` only take effect for local runs until they are pushed to the `zinit` branch.
- GitHub API calls may rate-limit; pinned release URLs are provided for the required tools.
- The default shell is never changed; activation only happens for sessions that set `SANDBOX_ENABLE=1`.
- Pass `--cleanup` to remove the sandbox dir, `/etc/profile.d/sandbox.sh`, and the `,`/`,,` aliases if you need to roll back. Removing the profile hook needs root; the aliases are removed regardless since they live in your own rc file.
