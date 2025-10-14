#!/usr/bin/env bash
set -euo pipefail

umask 022

SCRIPT_SOURCE="$0"
if declare -p BASH_SOURCE >/dev/null 2>&1; then
  if [ "${#BASH_SOURCE[@]}" -gt 0 ] && [ -n "${BASH_SOURCE[0]}" ]; then
    SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  fi
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)
TEMPLATE_ZSHRC="${SCRIPT_DIR}/../templates/zshrc-tpl.zsh"
DEFAULT_TEMPLATE_URL="https://raw.githubusercontent.com/nascarsayan/init-linux/zinit/templates/zshrc-tpl.zsh"
DEFAULT_P10K_URL="https://raw.githubusercontent.com/nascarsayan/init-linux/zinit/templates/p10k.zsh"
FZF_VERSION="${FZF_VERSION:-0.65.2}"

log() {
  printf '[sandbox-install] %s\n' "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die 'this installer must run as root (sudo) to manage sandbox assets and profile hooks'
  fi
}

# Flags
CLEANUP_ONLY=0
NO_SANDBOX=0
SANDBOX_HOME_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cleanup)
      CLEANUP_ONLY=1
      shift
      ;;
    --sandbox-dir)
      SANDBOX_HOME_ARG="$2"
      shift 2
      ;;
    --no-sandbox)
      NO_SANDBOX=1
      shift
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: sandbox-install.sh [--sandbox-dir <path>] [--no-sandbox] [--cleanup]

  (default)        Install a sandboxed environment under /root/sandbox (or --sandbox-dir)
  --sandbox-dir    Set an explicit sandbox directory
  --no-sandbox     Install packages globally via apt/dnf/brew (no sandbox directories)
  --cleanup        Remove the sandbox directory and profile hook

You can forward flags when piping from curl, e.g.:
  curl -fsSL <url> | sudo bash -s -- --sandbox-dir /opt/dev-sandbox
USAGE
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [ "$NO_SANDBOX" -eq 1 ] && [ "$CLEANUP_ONLY" -eq 1 ]; then
  die "--cleanup cannot be combined with --no-sandbox"
fi

DEFAULT_SANDBOX_HOME=/root/sandbox
SANDBOX_HOME=${SANDBOX_HOME_ARG:-${SANDBOX_HOME:-$DEFAULT_SANDBOX_HOME}}

# Sandbox paths
BASE_DIR="$SANDBOX_HOME"
BIN_DIR="${BASE_DIR}/bin"
CACHE_DIR="${BASE_DIR}/cache"
ZSH_DIR="${BASE_DIR}/zsh"
FZF_DIR="${BASE_DIR}/fzf"
P10K_DIR="${BASE_DIR}/p10k"
KREW_DIR="${BASE_DIR}/krew"
XDG_CACHE_HOME_DIR="${BASE_DIR}/.cache"
XDG_CONFIG_HOME_DIR="${BASE_DIR}/.config"
XDG_DATA_HOME_DIR="${BASE_DIR}/.local/share"
HELIX_CONFIG_DIR="${XDG_CONFIG_HOME_DIR}/helix"
HELIX_RUNTIME_DIR="${HELIX_CONFIG_DIR}/runtime"
ZINIT_HOME="${BASE_DIR}/zinit/zinit.git"
ENV_SCRIPT="${BASE_DIR}/activate.sh"
PROFILE_SNIPPET="/etc/profile.d/sandbox.sh"

cleanup_environment() {
  # require_root
  log "Removing ${BASE_DIR}"
  rm -rf "$BASE_DIR"
  if [ -f "$PROFILE_SNIPPET" ]; then
    log "Removing ${PROFILE_SNIPPET}"
    rm -f "$PROFILE_SNIPPET"
  fi
  log "Cleanup complete"
}

ensure_dirs() {
  mkdir -p \
    "$BIN_DIR" \
    "$CACHE_DIR" \
    "$ZSH_DIR" \
    "$FZF_DIR" \
    "$P10K_DIR" \
    "$KREW_DIR" \
    "$XDG_CACHE_HOME_DIR" \
    "$XDG_CONFIG_HOME_DIR" \
    "$XDG_DATA_HOME_DIR" \
    "$HELIX_RUNTIME_DIR" \
    "$HELIX_CONFIG_DIR" \
    "$(dirname "$ZINIT_HOME")"
}

ensure_command() {
  command -v "$1" >/dev/null 2>&1
}

pkg_manager=""
detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    pkg_manager="apt"
  elif command -v dnf >/dev/null 2>&1; then
    pkg_manager="dnf"
  else
    pkg_manager=""
  fi
}

install_pkg() {
  case "$pkg_manager" in
    apt)
      log "Installing package via apt: $*"
      DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null
      ;;
    dnf)
      log "Installing package via dnf: $*"
      dnf install -y "$@" >/dev/null
      ;;
    *)
      die "no supported package manager for installing $*"
      ;;
  esac
}

install_global_packages() {
  detect_pkg_manager
  case "$pkg_manager" in
    apt)
      for pkg in fzf zoxide; do
        if ! install_pkg "$pkg"; then
          log "Warning: unable to install $pkg via apt"
        fi
      done
      ;;
    dnf)
      for pkg in fzf zoxide; do
        if ! install_pkg "$pkg"; then
          log "Warning: unable to install $pkg via dnf"
        fi
      done
      ;;
    *)
      if command -v brew >/dev/null 2>&1; then
        for pkg in fzf zoxide; do
          brew install "$pkg" || log "Warning: unable to install $pkg via brew"
        done
      else
        log 'No supported package manager found for --no-sandbox mode'
      fi
      ;;
  esac
}

git_clone_or_update() {
  local repo_url="$1" dest="$2"
  if [ -d "$dest/.git" ]; then
    git -C "$dest" pull --ff-only >/dev/null 2>&1 || log "Warning: unable to update $(basename "$dest")"
  else
    rm -rf "$dest"
    git clone --depth 1 "$repo_url" "$dest" >/dev/null 2>&1 || log "Warning: unable to clone $repo_url"
  fi
}

ensure_base_prereqs() {
  for cmd in curl tar gzip; do
    if ! ensure_command "$cmd"; then
      die "required command '$cmd' not found"
    fi
  done
  if ! ensure_command unzip; then
    detect_pkg_manager
    if [ -n "$pkg_manager" ]; then
      install_pkg unzip
    else
      die "required command 'unzip' not found and unable to install automatically"
    fi
  fi
  if ! ensure_command xz; then
    detect_pkg_manager
    case "$pkg_manager" in
      apt)
        install_pkg xz-utils
        ;;
      dnf)
        install_pkg xz
        ;;
      *)
        die "required command 'xz' not found and unable to install automatically"
        ;;
    esac
  fi
  if ! ensure_command find; then
    detect_pkg_manager
    if [ -n "$pkg_manager" ]; then
      install_pkg findutils
    else
      die "required command 'find' not found and unable to install automatically"
    fi
  fi
  if ! ensure_command git; then
    detect_pkg_manager
    if [ -n "$pkg_manager" ]; then
      install_pkg git
    else
      die 'git not found and unable to install automatically'
    fi
  fi
}

ensure_zsh() {
  if ensure_command zsh; then
    return
  fi
  log 'zsh not found; attempting installation'
  detect_pkg_manager
  case "$pkg_manager" in
    apt)
      install_pkg zsh
      ;;
    dnf)
      install_pkg zsh
      ;;
    *)
      if ensure_command brew; then
        log 'installing zsh via Homebrew'
        brew install zsh >/dev/null
      else
        log 'zsh unavailable (no apt/dnf/brew); skipping shell setup'
        return 1
      fi
      ;;
  esac
}

fetch_latest_asset_url() {
  local repo="$1" pattern="$2"
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local url
  url=$(curl -fsSL "$api_url" |
    grep -o '"browser_download_url"[^"]*"[^"]*' |
    sed -E 's/^"browser_download_url"[^"]*"([^"]*)$/\1/' |
    grep -E "$pattern" |
    head -n 1)
  if [ -n "$url" ]; then
    printf '%s' "$url"
    return 0
  fi
  return 1
}

download_asset() {
  local name="$1" url="$2" dest="$3"
  log "Downloading ${name} from ${url}"
  curl -fsSL "$url" -o "$dest"
}

install_tar_binary() {
  local name="$1" repo="$2" pattern="$3" fallback="$4" binary_name="$5"
  local archive="$CACHE_DIR/${name}.tar.gz"
  local url
  if ! url=$(fetch_latest_asset_url "$repo" "$pattern"); then
    if [ -n "$fallback" ]; then
      log "Falling back to pinned ${name} asset"
      url="$fallback"
    else
      die "Unable to locate ${name} release asset"
    fi
  fi
  download_asset "$name" "$url" "$archive"
  local tmp
  tmp=$(mktemp -d)
  tar -xzf "$archive" -C "$tmp"
  local bin_path
  bin_path=$(find "$tmp" -type f -name "$binary_name" -perm -u+x | head -n 1 || true)
  if [ -z "$bin_path" ]; then
    rm -rf "$tmp"
    die "${name}: binary ${binary_name} not located after extraction"
  fi
  install -m 0755 "$bin_path" "$BIN_DIR/${binary_name}"
  rm -rf "$tmp" "$archive"
  log "Installed ${name} to ${BIN_DIR}/${binary_name}"
}

install_zip_binary() {
  local name="$1" repo="$2" pattern="$3" fallback="$4" binary_name="$5"
  local archive="$CACHE_DIR/${name}.zip"
  local url
  if ! url=$(fetch_latest_asset_url "$repo" "$pattern"); then
    if [ -n "$fallback" ]; then
      log "Falling back to pinned ${name} asset"
      url="$fallback"
    else
      die "Unable to locate ${name} release asset"
    fi
  fi
  download_asset "$name" "$url" "$archive"
  local tmp
  tmp=$(mktemp -d)
  if ! unzip -q "$archive" -d "$tmp"; then
    rm -rf "$tmp" "$archive"
    die "${name}: failed to extract zip archive"
  fi
  local bin_path
  bin_path=$(find "$tmp" -type f -name "$binary_name" -perm -u+x | head -n 1 || true)
  if [ -z "$bin_path" ]; then
    rm -rf "$tmp" "$archive"
    die "${name}: binary ${binary_name} not located after extraction"
  fi
  install -m 0755 "$bin_path" "$BIN_DIR/${binary_name}"
  rm -rf "$tmp" "$archive"
  log "Installed ${name} to ${BIN_DIR}/${binary_name}"
}

install_crush() {
  install_tar_binary \
    "crush" \
    "charmbracelet/crush" \
    "Linux_x86_64.*tar.gz" \
    "https://github.com/charmbracelet/crush/releases/download/v0.10.4/crush_0.10.4_Linux_x86_64.tar.gz" \
    "crush"
}

install_croc() {
  install_tar_binary \
    "croc" \
    "schollz/croc" \
    "Linux-64bit.*tar.gz" \
    "https://github.com/schollz/croc/releases/download/v10.2.4/croc_v10.2.4_Linux-64bit.tar.gz" \
    "croc"
}

install_procs() {
  install_zip_binary \
    "procs" \
    "dalance/procs" \
    "-x86_64-linux\\.zip" \
    "https://github.com/dalance/procs/releases/download/v0.14.10/procs-v0.14.10-x86_64-linux.zip" \
    "procs"
}

install_codex() {
  local name="codex"
  local archive="$CACHE_DIR/${name}.tar.gz"
  local url="https://github.com/openai/codex/releases/download/rust-v0.42.0/codex-x86_64-unknown-linux-musl.tar.gz"
  download_asset "$name" "$url" "$archive"
  local tmp
  tmp=$(mktemp -d)
  tar -xzf "$archive" -C "$tmp"
  local bin_path
  bin_path=$(find "$tmp" -type f -name "codex*" -perm -u+x | head -n 1 || true)
  if [ -z "$bin_path" ]; then
    rm -rf "$tmp"
    die 'codex: binary not found after extraction'
  fi
  install -m 0755 "$bin_path" "$BIN_DIR/codex"
  rm -rf "$tmp" "$archive"
  log "Installed codex to ${BIN_DIR}/codex"
}

install_gh() {
  install_tar_binary \
    "gh" \
    "cli/cli" \
    "linux_amd64.*tar.gz" \
    "https://github.com/cli/cli/releases/download/v2.51.0/gh_2.51.0_linux_amd64.tar.gz" \
    "gh"
}

install_fzf() {
  local bin_url="https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz"
  install_tar_binary \
    "fzf" \
    "junegunn/fzf" \
    "linux_amd64.*tar.gz" \
    "$bin_url" \
    "fzf"
  local shell_archive="$CACHE_DIR/fzf-shell.tar.gz"
  if curl -fsSL "https://github.com/junegunn/fzf/archive/refs/tags/v${FZF_VERSION}.tar.gz" -o "$shell_archive"; then
    local tmp extracted_dir
    tmp=$(mktemp -d)
    tar -xzf "$shell_archive" -C "$tmp"
    extracted_dir=$(find "$tmp" -maxdepth 1 -type d -name "fzf-*" | head -n 1)
    if [ -n "$extracted_dir" ]; then
      [ -f "$extracted_dir/shell/key-bindings.zsh" ] && cp "$extracted_dir/shell/key-bindings.zsh" "${FZF_DIR}/key-bindings.zsh"
      [ -f "$extracted_dir/shell/completion.zsh" ] && cp "$extracted_dir/shell/completion.zsh" "${FZF_DIR}/completion.zsh"
    fi
    rm -rf "$tmp" "$shell_archive"
  else
    log 'Warning: unable to fetch fzf shell scripts archive'
  fi
}

install_zoxide() {
  install_tar_binary \
    "zoxide" \
    "ajeetdsouza/zoxide" \
    "x86_64-unknown-linux-musl.*tar.gz" \
    "https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.8/zoxide-0.9.8-x86_64-unknown-linux-musl.tar.gz" \
    "zoxide"
}

install_fd() {
  install_tar_binary \
    "fd" \
    "sharkdp/fd" \
    "x86_64-unknown-linux-musl.*tar.gz" \
    "https://github.com/sharkdp/fd/releases/download/v10.3.0/fd-v10.3.0-x86_64-unknown-linux-musl.tar.gz" \
    "fd"
}

install_xh() {
  install_tar_binary \
    "xh" \
    "ducaale/xh" \
    "x86_64-unknown-linux-musl.*tar.gz" \
    "https://github.com/ducaale/xh/releases/download/v0.25.0/xh-v0.25.0-x86_64-unknown-linux-musl.tar.gz" \
    "xh"
}

install_ripgrep() {
  install_tar_binary \
    "ripgrep" \
    "BurntSushi/ripgrep" \
    "x86_64-unknown-linux-musl.*tar.gz" \
    "https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz" \
    "rg"
}

install_tre() {
  install_tar_binary \
    "tre" \
    "dduan/tre" \
    "x86_64-unknown-linux-musl.*tar.gz" \
    "https://github.com/dduan/tre/releases/download/v0.4.0/tre-v0.4.0-x86_64-unknown-linux-musl.tar.gz" \
    "tre"
}

install_k9s() {
  install_tar_binary \
    "k9s" \
    "derailed/k9s" \
    "Linux_amd64.*tar.gz" \
    "https://github.com/derailed/k9s/releases/download/v0.50.13/k9s_Linux_amd64.tar.gz" \
    "k9s"
}

install_kubecolor() {
  install_tar_binary \
    "kubecolor" \
    "kubecolor/kubecolor" \
    "linux_amd64.*tar.gz" \
    "https://github.com/kubecolor/kubecolor/releases/download/v0.5.2/kubecolor_0.5.2_linux_amd64.tar.gz" \
    "kubecolor"
}

install_krew() {
  local os="linux"
  local arch="amd64"
  local archive="$CACHE_DIR/krew.tar.gz"
  local krew_root="$KREW_DIR"
  curl -fsSL "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-${os}_${arch}.tar.gz" -o "$archive" || {
    log 'Warning: unable to download krew archive'
    return
  }
  local tmp
  tmp=$(mktemp -d)
  tar -xzf "$archive" -C "$tmp"
  if [ ! -x "$tmp/krew-${os}_${arch}" ]; then
    log 'Warning: krew executable not found after extraction'
    rm -rf "$tmp" "$archive"
    return
  fi
  if KREW_ROOT="$krew_root" KREW_HOME="$krew_root" "${tmp}/krew-${os}_${arch}" install krew >/dev/null 2>&1; then
    PATH="$krew_root/bin:$PATH" KREW_ROOT="$krew_root" KREW_HOME="$krew_root" kubectl krew install tree stern >/dev/null 2>&1 || log 'Warning: failed to install krew plugins (tree, stern)'
    log "Installed krew under ${krew_root}"
  else
    log 'Warning: failed to bootstrap krew'
  fi
  rm -rf "$tmp" "$archive"
}

install_sysz() {
  local target="$BIN_DIR/sysz"
  curl -fsSL "https://github.com/joehillen/sysz/releases/latest/download/sysz" -o "$target" || {
    log 'Warning: unable to download sysz binary'
    return
  }
  chmod +x "$target"
  log "Installed sysz to ${target}"
}

install_yq() {
  local target="$BIN_DIR/yq"
  curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o "$target" || {
    log 'Warning: unable to download yq binary'
    return
  }
  chmod +x "$target"
  log "Installed yq to ${target}"
}

install_helix() {
  local version="${SANDBOX_HELIX_VERSION:-25.07.1}"
  local name="helix"
  local archive="$CACHE_DIR/${name}.tar.xz"
  local url="https://github.com/helix-editor/helix/releases/download/${version}/helix-${version}-x86_64-linux.tar.xz"
  download_asset "$name" "$url" "$archive"

  local tmp
  tmp=$(mktemp -d)
  if ! tar -xJf "$archive" -C "$tmp"; then
    rm -rf "$tmp" "$archive"
    die 'helix: failed to extract archive'
  fi

  local extracted
  extracted=$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "helix-*" | head -n 1 || true)
  if [ -z "$extracted" ]; then
    rm -rf "$tmp" "$archive"
    die 'helix: extracted archive missing helix directory'
  fi

  mkdir -p "$HELIX_CONFIG_DIR"
  rm -rf "$HELIX_RUNTIME_DIR"
  cp -r "$extracted/runtime" "$HELIX_RUNTIME_DIR"
  if [ ! -f "${HELIX_CONFIG_DIR}/config.toml" ]; then
    cat <<'CFG' >"${HELIX_CONFIG_DIR}/config.toml"
theme = "catppuccin-macchiato"

[editor]
line-number = "relative"
mouse = true

[editor.cursor-shape]
insert = "bar"
normal = "block"
select = "underline"

[editor.file-picker]
hidden = false
CFG
  fi
  local hx_binary_url="https://github.com/nascarsayan/init-linux/releases/download/v${version}-glibc228/hx"
  if ! curl -fsSL "$hx_binary_url" -o "${BIN_DIR}/hx"; then
    rm -rf "$tmp" "$archive"
    die "helix: failed to download hx binary from ${hx_binary_url}"
  fi
  chmod 0755 "${BIN_DIR}/hx"

  rm -rf "$tmp" "$archive"
  log "Installed helix ${version} runtime and custom hx binary"
}

install_zellij() {
  install_tar_binary \
    "zellij" \
    "zellij-org/zellij" \
    "zellij-no-web-.*x86_64-unknown-linux-musl\\.tar\\.gz" \
    "https://github.com/zellij-org/zellij/releases/download/v0.43.1/zellij-no-web-x86_64-unknown-linux-musl.tar.gz" \
    "zellij"
}

install_delta() {
  install_tar_binary \
    "delta" \
    "dandavison/delta" \
    "x86_64-unknown-linux-musl\\.tar\\.gz" \
    "https://github.com/dandavison/delta/releases/download/0.18.2/delta-0.18.2-x86_64-unknown-linux-musl.tar.gz" \
    "delta"
}

install_bat() {
  install_tar_binary \
    "bat" \
    "sharkdp/bat" \
    "x86_64-unknown-linux-musl\\.tar\\.gz" \
    "https://github.com/sharkdp/bat/releases/download/v0.25.0/bat-v0.25.0-x86_64-unknown-linux-musl.tar.gz" \
    "bat"
}

install_btop() {
  local name="btop"
  local archive="$CACHE_DIR/${name}.tbz"
  local url="https://github.com/aristocratos/btop/releases/download/v1.4.5/btop-x86_64-linux-musl.tbz"
  download_asset "$name" "$url" "$archive"

  local tmp
  tmp=$(mktemp -d)
  local seven_zip="${BIN_DIR}/7zz"
  if [ -x "$seven_zip" ]; then
    if ! "$seven_zip" x "-o${tmp}" "$archive" >/dev/null 2>&1; then
      rm -rf "$tmp" "$archive"
      die 'btop: failed to extract archive via 7zz'
    fi
    local nested_tar
    nested_tar=$(find "$tmp" -maxdepth 1 -type f -name '*.tar' | head -n 1 || true)
    if [ -n "$nested_tar" ]; then
      if ! tar -xf "$nested_tar" -C "$tmp"; then
        rm -rf "$tmp" "$archive"
        die 'btop: failed to extract nested tar after 7zz unzip'
      fi
      rm -f "$nested_tar"
    fi
  else
    if ! tar -xjf "$archive" -C "$tmp"; then
      rm -rf "$tmp" "$archive"
      die 'btop: failed to extract archive (tar does not support bzip2)'
    fi
  fi

  local bin_path
  bin_path=$(find "$tmp" -type f -name "btop" -perm -u+x | head -n 1 || true)
  if [ -z "$bin_path" ]; then
    rm -rf "$tmp" "$archive"
    die 'btop: executable not found after extraction'
  fi

  install -m 0755 "$bin_path" "$BIN_DIR/btop"
  rm -rf "$tmp" "$archive"
  log "Installed btop to ${BIN_DIR}/btop"
}

install_gobang() {
  install_tar_binary \
    "gobang" \
    "TaKO8Ki/gobang" \
    "x86_64-unknown-linux-musl\\.tar\\.gz" \
    "https://github.com/TaKO8Ki/gobang/releases/download/v0.1.0-alpha.5/gobang-0.1.0-alpha.5-x86_64-unknown-linux-musl.tar.gz" \
    "gobang"
}

install_duf() {
  install_tar_binary \
    "duf" \
    "muesli/duf" \
    "linux_x86_64\\.tar\\.gz" \
    "https://github.com/muesli/duf/releases/download/v0.9.1/duf_0.9.1_linux_x86_64.tar.gz" \
    "duf"
}

install_broot() {
  local target="$BIN_DIR/broot"
  curl -fsSL "https://dystroy.org/broot/download/x86_64-unknown-linux-musl/broot" -o "$target" || {
    log 'Warning: unable to download broot binary'
    return
  }
  chmod +x "$target"
  log "Installed broot to ${target}"
}

install_eza() {
  install_tar_binary \
    "eza" \
    "eza-community/eza" \
    "x86_64-unknown-linux-musl.*tar.gz" \
    "https://github.com/eza-community/eza/releases/download/v0.23.4/eza_x86_64-unknown-linux-musl.tar.gz" \
    "eza"
}

install_yazi() {
  local name="yazi"
  local archive="$CACHE_DIR/${name}.zip"
  local url="https://github.com/sxyazi/yazi/releases/download/v25.5.31/yazi-x86_64-unknown-linux-musl.zip"
  download_asset "$name" "$url" "$archive"
  local tmp
  tmp=$(mktemp -d)
  if ! unzip -q "$archive" -d "$tmp"; then
    rm -rf "$tmp" "$archive"
    die 'yazi: failed to extract archive'
  fi
  local base_dir
  base_dir=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)
  [ -z "$base_dir" ] && base_dir="$tmp"
  local yazi_bin
  yazi_bin=$(find "$base_dir" -type f -name "yazi" -perm -u+x | head -n 1 || true)
  if [ -z "$yazi_bin" ]; then
    rm -rf "$tmp" "$archive"
    die 'yazi: binary yazi not located after extraction'
  fi
  install -m 0755 "$yazi_bin" "$BIN_DIR/yazi"
  local ya_bin
  ya_bin=$(find "$base_dir" -type f -name "ya" -perm -u+x | head -n 1 || true)
  if [ -n "$ya_bin" ]; then
    install -m 0755 "$ya_bin" "$BIN_DIR/ya"
  else
    log 'Warning: yazi helper binary "ya" not found in archive'
  fi
  rm -rf "$tmp" "$archive"
  log "Installed yazi to ${BIN_DIR}/yazi"
}

install_7zz() {
  local name="7zz"
  local archive="$CACHE_DIR/${name}.tar.xz"
  local url="https://github.com/ip7z/7zip/releases/download/25.01/7z2501-linux-x64.tar.xz"
  download_asset "$name" "$url" "$archive"
  local tmp
  tmp=$(mktemp -d)
  if ! tar -xf "$archive" -C "$tmp"; then
    rm -rf "$tmp" "$archive"
    die '7zz: failed to extract archive'
  fi
  local main_bin="$tmp/7zz"
  if [ ! -x "$main_bin" ]; then
    main_bin=$(find "$tmp" -type f -name "7zz" -perm -u+x | head -n 1 || true)
  fi
  if [ -z "$main_bin" ]; then
    rm -rf "$tmp" "$archive"
    die '7zz: binary 7zz not located after extraction'
  fi
  install -m 0755 "$main_bin" "$BIN_DIR/7zz"
  local secondary_bin="$tmp/7zzs"
  if [ ! -x "$secondary_bin" ]; then
    secondary_bin=$(find "$tmp" -type f -name "7zzs" -perm -u+x | head -n 1 || true)
  fi
  if [ -n "$secondary_bin" ]; then
    install -m 0755 "$secondary_bin" "$BIN_DIR/7zzs"
  fi
  rm -rf "$tmp" "$archive"
  log "Installed 7zz to ${BIN_DIR}/7zz"
}

write_zshenv() {
  cat <<'EOF' >"${ZSH_DIR}/.zshenv"
export SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
export PATH="${SANDBOX_HOME}/bin:${PATH}"
export XDG_CACHE_HOME="${SANDBOX_HOME}/.cache"
export XDG_CONFIG_HOME="${SANDBOX_HOME}/.config"
export XDG_DATA_HOME="${SANDBOX_HOME}/.local/share"
export EDITOR="hx"
export ZINIT_HOME="${SANDBOX_HOME}/zinit/zinit.git"
export FZF_HOME="${SANDBOX_HOME}/fzf"
[ -r "${SANDBOX_HOME}/p10k/p10k.zsh" ] && export P10K_CONFIG="${SANDBOX_HOME}/p10k/p10k.zsh"
export HELIX_CONFIG_DIR="${XDG_CONFIG_HOME}/helix"
export HELIX_RUNTIME="${HELIX_CONFIG_DIR}/runtime"
export KREW_ROOT="${SANDBOX_HOME}/krew"
export KREW_HOME="${KREW_ROOT}"
export PATH="${KREW_ROOT}/bin:${PATH}"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\/\\}#" "${ZSH_DIR}/.zshenv"
}

write_zshrc() {
  local target="${ZSH_DIR}/.zshrc"
  if [ -f "$TEMPLATE_ZSHRC" ]; then
    cp "$TEMPLATE_ZSHRC" "$target"
    chmod 0644 "$target"
  else
    local template_url="${SANDBOX_TEMPLATE_URL:-$DEFAULT_TEMPLATE_URL}"
    if curl -fsSL "$template_url" -o "$target"; then
      chmod 0644 "$target"
      log "Fetched zsh template from ${template_url}"
    else
      log "Zsh template not found at ${TEMPLATE_ZSHRC} and download failed from ${template_url}; writing minimal config"
      cat <<'EOF' >"$target"
if [ -n "${SANDBOX_HOME:-}" ] && [ -f "${SANDBOX_HOME}/zinit/zinit.git/zinit.zsh" ]; then
  source "${SANDBOX_HOME}/zinit/zinit.git/zinit.zsh"
fi
alias ls='eza -lh --group-directories-first --icons=auto'
EOF
      return
    fi
  fi

  sed -i "/^alias ls='eza -lh --group-directories-first --icons=auto'$/d" "$target"
  cat <<'EOF' >>"$target"

alias ls='eza -lh --group-directories-first --icons=auto'
EOF
}

setup_zsh_files() {
  write_zshenv
  write_zshrc
  mkdir -p "${ZSH_DIR}/cache" "${ZSH_DIR}/config"
  touch "${ZSH_DIR}/.zsh_history"
  log "Wrote ZDOTDIR configuration under ${ZSH_DIR}"
  if [ ! -f "${P10K_DIR}/p10k.zsh" ]; then
    if [ -f "${SCRIPT_DIR}/../templates/p10k.zsh" ]; then
      cp "${SCRIPT_DIR}/../templates/p10k.zsh" "${P10K_DIR}/p10k.zsh"
    else
      local p10k_url="${SANDBOX_P10K_TEMPLATE_URL:-$DEFAULT_P10K_URL}"
      curl -fsSL "$p10k_url" -o "${P10K_DIR}/p10k.zsh" || log "Warning: unable to fetch p10k template from ${p10k_url}"
    fi
  fi
}

write_shell_wrapper() {
  local wrapper="${BIN_DIR}/sandbox-shell"
  local legacy="${BIN_DIR}/sandbox-login"
  cat <<'EOF' >"$wrapper"
#!/usr/bin/env bash
set -euo pipefail

SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
ENV_SCRIPT="${SANDBOX_HOME}/activate.sh"

if [ -f "${ENV_SCRIPT}" ]; then
  # shellcheck disable=SC1090
  source "${ENV_SCRIPT}"
fi

exec zsh -il "$@"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\\/\\\\}#" "$wrapper"
  chmod +x "$wrapper"
  ln -sf "$(basename "$wrapper")" "$legacy"
  log "Created sandbox shell wrapper at ${wrapper}"
}

write_sssh_wrapper() {
  local wrapper="${BIN_DIR}/sssh"
  cat <<'EOF' >"$wrapper"
#!/usr/bin/env bash
set -euo pipefail

SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
REMOTE_WRAPPER="${SANDBOX_HOME}/bin/sandbox-shell"

if ! command -v ssh >/dev/null 2>&1; then
  echo "[sandbox] ssh not found on PATH" >&2
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "usage: sssh [ssh-options ...] user@host" >&2
  exit 1
fi

remote_host="${@: -1}"
ssh_args=( "${@:1:$#-1}" )

ssh_args+=( "-tt" )

exec ssh "${ssh_args[@]}" "${remote_host}" "cd __BASE__ && ${REMOTE_WRAPPER}"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\\/\\\\}#" "$wrapper"
  chmod +x "$wrapper"
  log "Created sandbox ssh helper at ${wrapper}"
}

install_zinit() {
  if [ -d "$ZINIT_HOME" ]; then
    log 'Zinit already present; fetching latest changes'
    git -C "$ZINIT_HOME" pull --ff-only >/dev/null 2>&1 || log 'Warning: unable to update existing zinit clone'
  else
    git clone --depth 1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" >/dev/null 2>&1
  fi
}

write_activation_script() {
  cat <<'EOF' >"${ENV_SCRIPT}"
# shellcheck shell=sh
export SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
export PATH="${SANDBOX_HOME}/bin:${PATH}"
export ZDOTDIR="${SANDBOX_HOME}/zsh"
export ZINIT_HOME="${SANDBOX_HOME}/zinit/zinit.git"
export FZF_HOME="${SANDBOX_HOME}/fzf"
export EDITOR="hx"
export XDG_CACHE_HOME="${SANDBOX_HOME}/.cache"
export XDG_CONFIG_HOME="${SANDBOX_HOME}/.config"
export XDG_DATA_HOME="${SANDBOX_HOME}/.local/share"
export HELIX_CONFIG_DIR="${XDG_CONFIG_HOME}/helix"
export HELIX_RUNTIME="${HELIX_CONFIG_DIR}/runtime"
export P10K_CONFIG="${SANDBOX_HOME}/p10k/p10k.zsh"
export KREW_ROOT="${SANDBOX_HOME}/krew"
export KREW_HOME="${KREW_ROOT}"
export PATH="${KREW_ROOT}/bin:${PATH}"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\/\\}#" "$ENV_SCRIPT"
  chmod 0644 "$ENV_SCRIPT"
}

write_profile_snippet() {
  cat <<EOF >"${PROFILE_SNIPPET}"
# shellcheck shell=sh
if [ -z "\${SANDBOX_ENABLE:-}" ]; then
  return 0 2>/dev/null || true
fi
if [ -f "${BASE_DIR}/activate.sh" ]; then
  . "${BASE_DIR}/activate.sh"
fi
EOF
  chmod 0644 "$PROFILE_SNIPPET"
}

main() {
  # require_root
  if [ "$NO_SANDBOX" -eq 1 ]; then
    ensure_base_prereqs
    ensure_zsh || log 'zsh installation skipped (not available)'
    install_global_packages
    log 'Global installation completed.'
    return
  fi
  if [ "$CLEANUP_ONLY" -eq 1 ]; then
    cleanup_environment
    return
  fi
  ensure_dirs
  ensure_base_prereqs
  ensure_zsh || log 'zsh setup skipped'
  install_crush
  install_croc
  install_procs
  install_codex
  install_gh
  install_fzf
  install_zoxide
  install_fd
  install_xh
  install_ripgrep
  install_tre
  install_k9s
  install_kubecolor
  install_krew
  install_sysz
  install_eza
  install_yazi
  install_7zz
  install_yq
  install_helix
  install_zellij
  install_delta
  install_bat
  install_btop
  install_gobang
  install_duf
  install_broot
  install_zinit
  setup_zsh_files
  write_activation_script
  write_shell_wrapper
  write_sssh_wrapper
  write_profile_snippet
  log 'Installation complete. Launch locally with /root/sandbox/bin/sandbox-shell or connect via /root/sandbox/bin/sssh user@host.'
}

main "$@"
