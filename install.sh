#!/bin/sh
set -eu

repo=${INIT_SH_REPO:-nascarsayan/init-sh}
ref=${INIT_SH_REF:-master}
box_installer=${INIT_SH_BOX_INSTALL_URL:-https://raw.githubusercontent.com/nascarsayan/box/main/install.sh}
mode=machine

case "${1:-}" in
  --sandboxed) mode=sandboxed; shift ;;
  --machine) shift ;;
esac

for argument in "$@"; do
  if [ "$argument" = "--dry-run" ]; then
    if [ "$mode" = sandboxed ]; then
      printf '+ curl -fsSL %s | sh\n' "$box_installer"
    else
      printf '+ bootstrap init-sh from github.com/%s@%s\n' "$repo" "$ref"
      printf '+ init-sh install %s\n' "$*"
    fi
    exit 0
  fi
done

if [ "$mode" = sandboxed ]; then
  temporary=$(mktemp)
  trap 'rm -f "$temporary"' EXIT HUP INT TERM
  curl -fsSL "$box_installer" -o "$temporary"
  exec sh "$temporary" "$@"
fi

os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Darwin) platform=darwin ;;
  Linux) platform=linux ;;
  *) printf 'init-sh: unsupported operating system: %s\n' "$os" >&2; exit 1 ;;
esac
case "$arch" in
  x86_64|amd64) machine=amd64 ;;
  arm64|aarch64) machine=arm64 ;;
  *) printf 'init-sh: unsupported architecture: %s\n' "$arch" >&2; exit 1 ;;
esac

install_linux_prerequisites() {
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y curl git zsh tar gzip xz
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y curl git zsh tar gzip xz-utils
  else
    printf 'init-sh: Linux requires dnf or apt-get for host packages\n' >&2
    exit 1
  fi
}

if [ "$platform" = darwin ]; then
  if ! command -v brew >/dev/null 2>&1; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
  brew install git zsh minijinja-cli
else
  install_linux_prerequisites
  if ! command -v mise >/dev/null 2>&1; then
    curl -fsSL https://mise.run | sh
  fi
  PATH="$HOME/.local/bin:$PATH"
  export PATH
  if ! command -v minijinja-cli >/dev/null 2>&1; then
    curl -fsSL https://github.com/mitsuhiko/minijinja/releases/latest/download/minijinja-cli-installer.sh | \
      MINIJINJA_CLI_INSTALL_DIR="$HOME/.local" sh
  fi
fi

bin_dir=${INIT_SH_BIN_DIR:-$HOME/.local/bin}
mkdir -p "$bin_dir"
asset="init-sh_${platform}_${machine}.tar.gz"
release_url="https://github.com/${repo}/releases/latest/download/${asset}"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM

if curl -fsSL "$release_url" -o "$temporary_dir/init-sh.tar.gz" && \
   tar -xzf "$temporary_dir/init-sh.tar.gz" -C "$temporary_dir" && \
   [ -x "$temporary_dir/init-sh" ]; then
  mv "$temporary_dir/init-sh" "$bin_dir/init-sh"
else
  printf 'init-sh: no release binary found; building master source\n' >&2
  if ! command -v go >/dev/null 2>&1; then
    if [ "$platform" = darwin ]; then
      brew install go
    else
      mise use --global go@latest
      eval "$(mise activate sh)"
    fi
  fi
  source_url="https://github.com/${repo}/archive/refs/heads/${ref}.tar.gz"
  curl -fsSL "$source_url" -o "$temporary_dir/source.tar.gz"
  mkdir -p "$temporary_dir/source"
  tar -xzf "$temporary_dir/source.tar.gz" -C "$temporary_dir/source" --strip-components=1
  (cd "$temporary_dir/source" && CGO_ENABLED=0 go build -trimpath -o "$bin_dir/init-sh" .)
fi
chmod 0755 "$bin_dir/init-sh"
exec "$bin_dir/init-sh" install "$@"
