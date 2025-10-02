# sayann-install.sh usage

This directory contains the `sayann-install.sh` bootstrap which provisions a lightweight, opt-in shell environment under `/root/sayann`. You can run it individually or stream it via `curl | bash`. The shell integration only activates when `SAYANN_ENABLE=1` is present, so other users on the box remain unaffected.

## Quickstart

```bash
# Run locally
sudo scripts/sayann-install.sh

# Or curl | bash (requires root)
curl -fsSL https://raw.githubusercontent.com/nascarsayan/init-linux/zinit/scripts/sayann-install.sh | sudo bash

# Remove everything later
curl -fsSL https://raw.githubusercontent.com/nascarsayan/init-linux/zinit/scripts/sayann-install.sh | sudo bash -s -- --cleanup
# or
sudo scripts/sayann-install.sh --cleanup
```

## What the installer does

- Creates `/root/sayann` with `bin`, `cache`, `zsh`, and `zinit` subdirectories.
- Downloads static binaries (crush, croc, codex, gh, fzf, zoxide) into `/root/sayann/bin`, falling back to pinned versions when rate-limited.
- Installs zinit under `/root/sayann/zinit` without touching other users.
- Copies `templates/zshrc-tpl.zsh` into `/root/sayann/zsh/.zshrc`. If the file is missing locally, the script fetches it from GitHub (`DEFAULT_TEMPLATE_URL`) or writes a minimal stub.
- Clones tmux configs (`gpakosz/.tmux` and `nascarsayan/.tmux.local`) under `/root/sayann/tmux` and keeps them sandboxed.
- Writes `/root/sayann/activate.sh` and `/etc/profile.d/sayann.sh`. Activation only happens when `SAYANN_ENABLE=1` is set.

## Using the environment

```bash
# Opt-in when SSHing
SAYANN_ENABLE=1 ssh root@host

# Or enable in an existing session
export SAYANN_ENABLE=1
source /root/sayann/activate.sh

# Jump into the zsh profile
zsh -i
```

Your binaries live at `/root/sayann/bin`, `ZDOTDIR=/root/sayann/zsh`, and tmux reads from `/root/sayann/tmux`; `command -v crush` (and friends) should resolve there once activated. `Ctrl-R` in zsh opens the bundled fzf history search, and `tmux` automatically loads the private config. Other users stay on their stock PATH/configs.

## Testing with Docker

A Rocky Linux 8 harness lives under `docker/rocky8/`.

```bash
# Build the test image
docker build -t sayann/init-rocky8 -f docker/rocky8/Dockerfile .

# Run the installer once
docker run --rm sayann/init-rocky8 bash -lc '/usr/local/src/sayann-install.sh'

# Inspect the generated config
docker run --rm sayann/init-rocky8 bash -lc 'ls /root/sayann/zsh && head -n 10 /root/sayann/zsh/.zshrc'

# Exercise the shell interactively (first run downloads zinit plugins)
docker run --rm -it -e SAYANN_ENABLE=1 \
  sayann/init-rocky8 bash -lc '/usr/local/src/sayann-install.sh && source /root/sayann/activate.sh && exec zsh -i'

# Two-step workflow
container=sayann-test

# Install once and keep the container running
docker run -d --rm --name "$container" -e SAYANN_ENABLE=1 \
  sayann/init-rocky8 bash -lc '/usr/local/src/sayann-install.sh && tail -f /dev/null'

# Inspect PATH/ZDOTDIR/TMUX and binaries
docker exec "$container" bash -lc 'source /root/sayann/activate.sh && echo PATH=$PATH && echo ZDOTDIR=$ZDOTDIR && echo TMUX_CONF=$TMUX_CONF && command -v crush croc codex gh fzf zoxide'

# Tear down
docker stop "$container"
```

## Config knobs

- `SAYANN_BASE_DIR`: install root (defaults to `/root/sayann`).
- `SAYANN_TEMPLATE_URL`: override the remote template URL when the local copy is absent.
- `SAYANN_TMUX_TEMPLATE_URL`: override the fallback tmux config URL.
- `SAYANN_ENABLE`: opt-in flag recognised by `/etc/profile.d/sayann.sh` and tests.
- `FZF_VERSION`: override the fzf release version downloaded into the sandbox.

## Notes

- The script requires root (writes under `/root` and `/etc/profile.d`).
- Re-running the installer is idempotent; binaries are overwritten in place, templates re-copied.
- GitHub API calls may rate-limit; pinned release URLs are provided for the required tools.
- The default shell is never changed; activation only happens for sessions that set `SAYANN_ENABLE=1`.
- Pass `--cleanup` to remove `/root/sayann` and `/etc/profile.d/sayann.sh` if you need to roll back.
