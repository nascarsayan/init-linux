# sandbox-install.sh usage

`sandbox-install.sh` bootstraps a self-contained shell environment under `/root/sandbox` by default. You can run it directly from this repository or stream it via `curl | bash`. The sandbox stays opt‑in: it only activates for sessions where `SANDBOX_ENABLE=1` is present, so other users on the machine remain unaffected.

## Quickstart

> ShortURL: https://snas.short.gy/linux-init
> Redirects to:
> https://raw.githubusercontent.com/nascarsayan/init-linux/zinit/scripts/sandbox-install.sh

```bash
# Run locally (sandboxed)
sudo scripts/sandbox-install.sh

# Or curl | bash (requires root)
curl -fsSL https://snas.short.gy/linux-init | sudo bash

# Install to a custom sandbox directory
curl -fsSL https://snas.short.gy/linux-init | sudo bash -s -- --sandbox-dir /root/sayann/dev

# Remove the sandbox later
curl -fsSL https://snas.short.gy/linux-init | sudo bash -s -- --cleanup

# Enable verbose debug trace
curl -fsSL https://snas.short.gy/linux-init | sudo bash -s -- --debug

# Package-manager only install (no sandbox assets)
curl -fsSL https://snas.short.gy/linux-init | sudo bash -s -- --no-sandbox
```

## What the installer does (sandbox mode)

- Creates `/root/sandbox` with `bin`, `cache`, `zsh`, `zinit`, `tmux`, `fzf`, `p10k`, and `krew` subdirectories.
- Downloads static binaries (crush, croc, codex, gh, fzf, zoxide, k9s, kubecolor, sysz) into `/root/sandbox/bin`, falling back to pinned versions when GitHub rate-limits.
- Installs zinit under `/root/sandbox/zinit` without touching other users.
- Copies `templates/zshrc-tpl.zsh` into `/root/sandbox/zsh/.zshrc`. If the file is missing locally, it falls back to the remote template or a minimal stub.
- Clones `gpakosz/.tmux` and `nascarsayan/.tmux.local` under `/root/sandbox/tmux`, wiring tmux to use those configs only when the sandbox is active.
- Drops your Powerlevel10k profile into `/root/sandbox/p10k/p10k.zsh`, so the wizard never appears.
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

- Sandbox mode requires root (it writes under `/root` and `/etc/profile.d`).
- Re-running the sandbox installer is idempotent; binaries are overwritten in place and configs re-copied.
- GitHub API calls may rate-limit; pinned release URLs are provided for the required tools.
- The default shell is never changed; activation only happens for sessions that set `SANDBOX_ENABLE=1`.
- Pass `--cleanup` to remove `/root/sandbox` and `/etc/profile.d/sandbox.sh` if you need to roll back.
