#!/usr/bin/env bash
set -Eeuo pipefail

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

warn() {
  log "Warning: $*"
}

# Individual tool installs call die() on a failed download/extract, which would
# abort the whole run before the shell config, wrappers and ',' alias are
# written. Run them in a subshell so their exit only kills that one step.
try_step() {
  local step="$1"
  if ! ( "$step" ); then
    warn "step '${step}' failed; continuing"
  fi
}

IS_ROOT=0
[ "$(id -u)" -eq 0 ] && IS_ROOT=1

# Root is optional. Everything under $BASE_DIR is written as the invoking user;
# only the system-wide bits (package installs, /etc/profile.d hook) need
# elevation, and those degrade to a warning instead of aborting the run.
# Resolves to '' when root, 'sudo -n' when passwordless sudo works, else unset
# -> callers skip the privileged step.
SUDO=""
HAVE_PRIV=0
detect_priv() {
  if [ "$IS_ROOT" -eq 1 ]; then
    SUDO=""
    HAVE_PRIV=1
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    SUDO="sudo -n"
    HAVE_PRIV=1
  else
    SUDO=""
    HAVE_PRIV=0
  fi
}
detect_priv

# Flags
CLEANUP_ONLY=0
NO_SANDBOX=0
SANDBOX_HOME_ARG=""
DEBUG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      DEBUG=1
      shift
      ;;
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

  (default)        Install a sandboxed environment under ~/sandbox
                   (/root/sandbox when run as root), or --sandbox-dir
  --sandbox-dir    Set an explicit sandbox directory
  --debug          Enable bash xtrace logs for troubleshooting
  --no-sandbox     Install packages globally via apt/dnf/brew (no sandbox directories)
  --cleanup        Remove the sandbox directory and profile hook

Root is NOT required. Without root (or passwordless sudo) the installer skips
system package installs and the /etc/profile.d/sandbox.sh hook, warns, and
continues; everything else lands under the sandbox directory. Use the ',' alias
it adds to your shell rc, or <sandbox-dir>/bin/sandbox-shell, to enter it.

You can forward flags when piping from curl, e.g.:
  curl -fsSL <url> | bash -s -- --sandbox-dir "$HOME/dev" --debug
USAGE
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [ "$DEBUG" -eq 1 ]; then
  set -x
fi

if [ "$NO_SANDBOX" -eq 1 ] && [ "$CLEANUP_ONLY" -eq 1 ]; then
  die "--cleanup cannot be combined with --no-sandbox"
fi

# /root/sandbox is only writable when actually root; fall back to the invoking
# user's home so a non-root run has a sane default instead of a permission error.
if [ "$IS_ROOT" -eq 1 ]; then
  DEFAULT_SANDBOX_HOME=/root/sandbox
else
  DEFAULT_SANDBOX_HOME="${HOME:-$(cd ~ && pwd)}/sandbox"
fi
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
TMUX_DIR="${BASE_DIR}/tmux"
TMUX_MAIN_REPO_DIR="${TMUX_DIR}/.tmux"
TMUX_LOCAL_REPO_DIR="${TMUX_DIR}/.tmux.local"
TMUX_CONF="${TMUX_DIR}/.tmux.conf"
TMUX_CONF_LOCAL="${TMUX_DIR}/.tmux.conf.local"
TMUX_SOCKET_NAME_DEFAULT="${SANDBOX_TMUX_SOCKET:-sayann}"
ENV_SCRIPT="${BASE_DIR}/activate.sh"
PROFILE_SNIPPET="/etc/profile.d/sandbox.sh"
GH_API_WARNED=0

cleanup_environment() {
  log "Removing ${BASE_DIR}"
  rm -rf "$BASE_DIR"
  remove_comma_aliases
  if [ -f "$PROFILE_SNIPPET" ]; then
    if [ "$HAVE_PRIV" -eq 1 ]; then
      log "Removing ${PROFILE_SNIPPET}"
      $SUDO rm -f "$PROFILE_SNIPPET" || warn "unable to remove ${PROFILE_SNIPPET}"
    else
      warn "skipping removal of ${PROFILE_SNIPPET} (needs root); delete it manually if unwanted"
    fi
  fi
  log "Cleanup complete"
}

ensure_dirs() {
  mkdir -p \
    "$BIN_DIR" \
    "$CACHE_DIR" \
    "$TMUX_DIR" \
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

# Last-resort dnf path for hosts whose only configured repo is an unreachable
# internal mirror. Typical cluster-node failure:
#   Errors during downloading metadata for repository 'local-yum':
#     - Curl error (7): Couldn't connect to server ... Connection refused
# which makes every package install fail, zsh included.
#
# Bypasses the configured repos entirely with an ephemeral --repofrompath against
# the public Rocky mirror; nothing is written to /etc/yum.repos.d, so the host's
# repo config is unchanged. GPG and TLS verification are disabled because these
# hosts often have neither the public GPG keys nor a CA bundle that trusts the
# mirror. That is a deliberate trade-off for bootstrapping a dev sandbox over a
# trusted network -- do not copy this into production provisioning.
dnf_public_fallback() {
  local arch major base
  arch="$(uname -m)"
  major=""
  if [ -r /etc/os-release ]; then
    major="$( . /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID%%.*}" )"
  fi
  case "$major" in
    8|9|10) ;;
    *)
      warn "no public mirror known for VERSION_ID='${major:-unknown}'; skipping public-repo fallback"
      return 1
      ;;
  esac
  base="https://dl.rockylinux.org/pub/rocky/${major}"
  warn "configured repos failed; retrying via public Rocky ${major} mirror with GPG/TLS verification DISABLED: $*"
  $SUDO dnf \
    --disablerepo='*' \
    --repofrompath="pub-baseos,${base}/BaseOS/${arch}/os/" \
    --repofrompath="pub-appstream,${base}/AppStream/${arch}/os/" \
    --setopt=sslverify=0 \
    --setopt=pub-baseos.sslverify=0 \
    --setopt=pub-appstream.sslverify=0 \
    --nogpgcheck -y install "$@" >/dev/null 2>&1
}

# Never fatal: a failed system package install just means the corresponding
# sandbox tool is skipped. Returns non-zero so callers can react.
install_pkg() {
  if [ "$HAVE_PRIV" -ne 1 ]; then
    warn "cannot install system package(s) '$*' without root/passwordless sudo; skipping"
    return 1
  fi
  case "$pkg_manager" in
    apt)
      log "Installing package via apt: $*"
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || true
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null 2>&1 || {
        warn "apt-get install failed for: $*"
        return 1
      }
      ;;
    dnf)
      log "Installing package via dnf: $*"
      if $SUDO dnf install -y "$@" >/dev/null 2>&1; then
        :
      elif dnf_public_fallback "$@"; then
        log "Installed via public-mirror fallback: $*"
      else
        warn "dnf install failed for: $*"
        return 1
      fi
      ;;
    *)
      warn "no supported package manager for installing $*"
      return 1
      ;;
  esac
}

install_global_packages() {
  detect_pkg_manager
  case "$pkg_manager" in
    apt)
      for pkg in zsh tmux fzf zoxide; do
        if ! install_pkg "$pkg"; then
          log "Warning: unable to install $pkg via apt"
        fi
      done
      ;;
    dnf)
      for pkg in zsh tmux fzf zoxide; do
        if ! install_pkg "$pkg"; then
          log "Warning: unable to install $pkg via dnf"
        fi
      done
      ;;
    *)
      if command -v brew >/dev/null 2>&1; then
        for pkg in zsh tmux fzf zoxide; do
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
  # curl/tar/gzip are load-bearing for every download step; without them there
  # is nothing to install, so these stay fatal.
  for cmd in curl tar gzip; do
    if ! ensure_command "$cmd"; then
      die "required command '$cmd' not found"
    fi
  done
  # The rest gate individual tools only. Without root we cannot install them,
  # so warn and let the affected installers skip themselves.
  detect_pkg_manager
  ensure_command unzip || install_pkg unzip \
    || warn "'unzip' unavailable; tools shipped as zip archives will be skipped"
  if ! ensure_command xz; then
    case "$pkg_manager" in
      apt) install_pkg xz-utils || true ;;
      dnf) install_pkg xz || true ;;
    esac
    ensure_command xz || warn "'xz' unavailable; tools shipped as .tar.xz will be skipped"
  fi
  ensure_command find || install_pkg findutils \
    || warn "'find' unavailable; archive-extraction helpers may misbehave"
  ensure_command git || install_pkg git \
    || warn "'git' unavailable; zinit and tmux config setup will be skipped"
}

ensure_zsh() {
  if ensure_command zsh; then
    return
  fi
  log 'zsh not found; attempting installation'
  detect_pkg_manager
  case "$pkg_manager" in
    apt|dnf)
      install_pkg zsh || return 1
      ;;
    *)
      if ensure_command brew; then
        log 'installing zsh via Homebrew'
        brew install zsh >/dev/null || return 1
      else
        log 'zsh unavailable (no apt/dnf/brew); skipping shell setup'
        return 1
      fi
      ;;
  esac
  ensure_command zsh
}

ensure_tmux() {
  if ensure_command tmux; then
    return
  fi
  log 'tmux not found; attempting installation'
  detect_pkg_manager
  case "$pkg_manager" in
    apt|dnf)
      install_pkg tmux || return 1
      ;;
    *)
      if ensure_command brew; then
        log 'installing tmux via Homebrew'
        brew install tmux >/dev/null || return 1
      else
        log 'tmux unavailable (no apt/dnf/brew); skipping tmux setup'
        return 1
      fi
      ;;
  esac
  ensure_command tmux
}

fetch_latest_asset_url() {
  local repo="$1" pattern="$2"
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local curl_args=(
    -fsSL
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: sandbox-install"
  )
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  local api_response url
  api_response=$(curl "${curl_args[@]}" "$api_url" 2>/dev/null || true)
  if [ -z "$api_response" ]; then
    if [ "$GH_API_WARNED" -eq 0 ]; then
      log "GitHub API unavailable/rate-limited; using pinned release fallbacks. Set GITHUB_TOKEN to increase limits."
      GH_API_WARNED=1
    fi
    return 1
  fi

  url=$(printf '%s' "$api_response" |
    grep -o '"browser_download_url"[^"]*"[^"]*' |
    sed -E 's/^"browser_download_url"[^"]*"([^"]*)$/\1/' |
    grep -E -- "$pattern" |
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

install_jnv() {
  local name="jnv"
  local archive="$CACHE_DIR/${name}.tar.xz"
  local url="https://github.com/ynqa/jnv/releases/download/v0.6.1/jnv-x86_64-unknown-linux-musl.tar.xz"
  download_asset "$name" "$url" "$archive"

  local tmp
  tmp=$(mktemp -d)
  if ! tar -xJf "$archive" -C "$tmp"; then
    rm -rf "$tmp" "$archive"
    die 'jnv: failed to extract archive'
  fi

  local bin_path
  bin_path=$(find "$tmp" -type f -name "jnv" -perm -u+x | head -n 1 || true)
  if [ -z "$bin_path" ]; then
    rm -rf "$tmp" "$archive"
    die 'jnv: binary not found after extraction'
  fi

  install -m 0755 "$bin_path" "$BIN_DIR/jnv"
  rm -rf "$tmp" "$archive"
  log "Installed jnv to ${BIN_DIR}/jnv"
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
export BUN_INSTALL="${SANDBOX_HOME}/.bun"
export PATH="${BUN_INSTALL}/bin:${PATH}"
typeset -gU path

# Strip Synopsys Verdi PLI dirs from LD_LIBRARY_PATH for interactive shells.
# Must happen in .zshenv (before /etc/zshrc -> /etc/profile.d/*.sh spawns
# subprocesses like grepconf, flatpak, tclsh autoinit, locale, sed). With
# verdi's PLI dirs in LD, glibc walks 4 NFS dirs x ~10 hwcaps/tls variants
# x ~10 libs for every child, ~1000 cold-NFS stats per shell startup.
# `eda_on` restores; needed if running VCS/Verdi.
if [[ -o interactive && -n "${LD_LIBRARY_PATH:-}" ]]; then
  export __ORIG_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
  typeset -a __ld_parts __ld_kept
  __ld_parts=("${(@s/:/)LD_LIBRARY_PATH}")
  __ld_kept=(${__ld_parts:#/tools/synopsys/*})
  export LD_LIBRARY_PATH="${(j/:/)__ld_kept}"
  unset __ld_parts __ld_kept
fi
eda_on()  { [[ -n "${__ORIG_LD_LIBRARY_PATH:-}" ]] && export LD_LIBRARY_PATH="$__ORIG_LD_LIBRARY_PATH"; }
eda_off() {
  local -a parts kept
  parts=("${(@s/:/)LD_LIBRARY_PATH}")
  kept=(${parts:#/tools/synopsys/*})
  export LD_LIBRARY_PATH="${(j/:/)kept}"
}
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

  # Sandbox-local aliases live in a marker-delimited block. Drop any previous
  # block first, then also strip unmarked copies: the common `curl | bash` path
  # has no local templates and fetches the published one, which may predate the
  # markers and still carry these aliases inline. Without this the block is
  # appended on top of them and every alias ends up defined twice.
  sed -i '/^# >>> sandbox aliases >>>$/,/^# <<< sandbox aliases <<<$/d' "$target"
  sed -i "/^[[:space:]]*alias ls='eza /d" "$target"
  sed -i '/^[[:space:]]*alias tmux=.TMUX_CONF=/d' "$target"
  cat <<'EOF' >>"$target"

# >>> sandbox aliases >>>
alias ls='eza -lh --group-directories-first --icons=auto'
if [[ -n "${SANDBOX_HOME:-}" ]]; then
  : "${TMUX_SOCKET_NAME:=sayann}"
  alias tmux='TMUX_CONF=${SANDBOX_HOME}/tmux/.tmux.conf TMUX_CONF_LOCAL=${SANDBOX_HOME}/tmux/.tmux.conf.local tmux -L ${TMUX_SOCKET_NAME} -f ${SANDBOX_HOME}/tmux/.tmux.conf'
fi
# <<< sandbox aliases <<<
EOF
}

setup_zsh_files() {
  write_zshenv
  write_zshrc
  mkdir -p "${ZSH_DIR}/cache" "${ZSH_DIR}/config"
  touch "${ZSH_DIR}/.zsh_history"
  log "Wrote ZDOTDIR configuration under ${ZSH_DIR}"
  write_p10k
}

# p10k config is always overwritten from the repo template -- it is generated by
# `p10k configure` and checked in, so the template is the single source of truth.
# Download failures leave any existing file untouched (curl writes to a temp
# first) so a network blip cannot wipe a working prompt config.
write_p10k() {
  local target="${P10K_DIR}/p10k.zsh"
  if [ -f "${SCRIPT_DIR}/../templates/p10k.zsh" ]; then
    cp "${SCRIPT_DIR}/../templates/p10k.zsh" "$target"
    chmod 0644 "$target"
    log "Installed p10k config from local template (overwrote any existing)"
    return
  fi
  local p10k_url="${SANDBOX_P10K_TEMPLATE_URL:-$DEFAULT_P10K_URL}"
  local tmp
  tmp="$(mktemp)" || {
    warn "unable to create temp file for p10k config; keeping existing"
    return 0
  }
  if curl -fsSL "$p10k_url" -o "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$target"
    chmod 0644 "$target"
    log "Installed p10k config from ${p10k_url} (overwrote any existing)"
  else
    rm -f "$tmp"
    warn "unable to fetch p10k template from ${p10k_url}; keeping existing config"
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

write_sbox_wrapper() {
  local wrapper="${BIN_DIR}/sbox"
  cat <<'EOF' >"$wrapper"
#!/usr/bin/env bash
set -euo pipefail

SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
INSTALLER_URL="${SANDBOX_INSTALLER_URL:-https://snas.short.gy/linux-init}"
SELF_PATH="${BASH_SOURCE[0]}"
SBOX_BIN_DIR="$(cd -- "$(dirname -- "$SELF_PATH")" >/dev/null 2>&1 && pwd)"
SHELL_WRAPPER="${SBOX_BIN_DIR}/sandbox-shell"
SSH_WRAPPER="${SBOX_BIN_DIR}/sssh"

usage() {
  cat <<'USAGE'
usage: sbox <command>

commands:
  update        Re-run installer for this sandbox (updates binaries/config)
  update-bins   Alias of update
  install claude-code
               Install/update n + latest Node, bun, and Claude Code
  shell         Launch sandbox zsh login shell
  ssh           Run sandbox ssh helper (sssh)
  help          Show this help
USAGE
}

# No root check: the installer writes everything under $SANDBOX_HOME as the
# invoking user and degrades the privileged steps (system packages,
# /etc/profile.d hook) to warnings.
run_update() {
  curl -fsSL "$INSTALLER_URL" | bash -s -- --sandbox-dir "$SANDBOX_HOME"
}

run_install_claude_code() {
  local n_install_url="https://bit.ly/n-install"
  local bun_install_url="https://bun.com/install"
  local claude_pkg_primary="@anthropic-ai/claude-code"
  local claude_pkg_fallback="@anthropic/claude-code"

  export PATH="$HOME/n/bin:$HOME/.bun/bin:$PATH"

  ensure_libatomic() {
    if command -v ldconfig >/dev/null 2>&1 && ldconfig -p 2>/dev/null | grep -q 'libatomic\.so\.1'; then
      return
    fi
    echo "[sbox] libatomic.so.1 missing; attempting install..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y >/dev/null
      apt-get install -y libatomic1 >/dev/null
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y libatomic >/dev/null
    elif command -v yum >/dev/null 2>&1; then
      yum install -y libatomic >/dev/null
    else
      echo "[sbox] unable to auto-install libatomic (unsupported package manager)" >&2
      return 1
    fi
  }

  if ! command -v n >/dev/null 2>&1; then
    echo "[sbox] n not found; installing via n-install..."
    curl -fsSL "$n_install_url" | bash -s -- -y
  fi
  export PATH="$HOME/n/bin:$PATH"
  if ! command -v n >/dev/null 2>&1; then
    echo "[sbox] n installation failed (n not on PATH)" >&2
    exit 1
  fi

  echo "[sbox] installing/updating Node.js (latest) via n..."
  n latest
  ensure_libatomic || true
  hash -r
  export PATH="$HOME/n/bin:$PATH"
  if ! command -v node >/dev/null 2>&1; then
    echo "[sbox] node not found after n latest" >&2
    exit 1
  fi

  if ! command -v bun >/dev/null 2>&1; then
    echo "[sbox] bun not found; installing..."
    curl -fsSL "$bun_install_url" | bash
  fi
  export PATH="$HOME/.bun/bin:$PATH"
  if ! command -v bun >/dev/null 2>&1; then
    echo "[sbox] bun installation failed (bun not on PATH)" >&2
    exit 1
  fi

  echo "[sbox] installing/updating Claude Code via bun..."
  if bun i -g "$claude_pkg_primary"; then
    return
  fi
  echo "[sbox] primary package ${claude_pkg_primary} failed; trying ${claude_pkg_fallback}..."
  bun i -g "$claude_pkg_fallback"
}

cmd="${1:-help}"
subcmd="${2:-}"
case "$cmd" in
  update|update-bins)
    run_update
    ;;
  install)
    case "$subcmd" in
      claude-code)
        run_install_claude_code
        ;;
      *)
        echo "[sbox] unknown install target: ${subcmd:-<empty>}" >&2
        usage >&2
        exit 1
        ;;
    esac
    ;;
  shell)
    shift || true
    exec "$SHELL_WRAPPER" "$@"
    ;;
  ssh)
    shift || true
    exec "$SSH_WRAPPER" "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "[sbox] unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
EOF
  sed -i "s#__BASE__#${BASE_DIR//\\/\\\\}#" "$wrapper"
  chmod +x "$wrapper"
  log "Created sandbox lifecycle helper at ${wrapper}"
}

install_zinit() {
  if [ -d "$ZINIT_HOME" ]; then
    log 'Zinit already present; fetching latest changes'
    git -C "$ZINIT_HOME" pull --ff-only >/dev/null 2>&1 || log 'Warning: unable to update existing zinit clone'
  else
    git clone --depth 1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" >/dev/null 2>&1
  fi
}

setup_tmux_files() {
  local fallback_local_url="${SANDBOX_TMUX_TEMPLATE_URL:-https://raw.githubusercontent.com/gpakosz/.tmux/master/.tmux.conf.local}"

  if ! ensure_command tmux; then
    log 'Warning: tmux not installed; skipping tmux config setup'
    return
  fi

  git_clone_or_update "https://github.com/gpakosz/.tmux.git" "$TMUX_MAIN_REPO_DIR"
  if [ ! -f "${TMUX_MAIN_REPO_DIR}/.tmux.conf" ]; then
    log "Warning: ${TMUX_MAIN_REPO_DIR}/.tmux.conf not found after clone"
    return
  fi
  ln -sfn "${TMUX_MAIN_REPO_DIR}/.tmux.conf" "$TMUX_CONF"

  git_clone_or_update "https://github.com/nascarsayan/.tmux.local.git" "$TMUX_LOCAL_REPO_DIR"
  if [ -f "${TMUX_LOCAL_REPO_DIR}/.tmux.conf.local" ]; then
    ln -sfn "${TMUX_LOCAL_REPO_DIR}/.tmux.conf.local" "$TMUX_CONF_LOCAL"
  elif [ -f "${TMUX_MAIN_REPO_DIR}/.tmux.conf.local" ]; then
    cp -f "${TMUX_MAIN_REPO_DIR}/.tmux.conf.local" "$TMUX_CONF_LOCAL"
  elif curl -fsSL "$fallback_local_url" -o "$TMUX_CONF_LOCAL"; then
    chmod 0644 "$TMUX_CONF_LOCAL"
  else
    log "Warning: unable to provision ${TMUX_CONF_LOCAL}"
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
export TMUX_CONF="${SANDBOX_HOME}/tmux/.tmux.conf"
export TMUX_CONF_LOCAL="${SANDBOX_HOME}/tmux/.tmux.conf.local"
export TMUX_SOCKET_NAME="${TMUX_SOCKET_NAME:-__TMUX_SOCKET_NAME__}"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\/\\}#" "$ENV_SCRIPT"
  sed -i "s#__TMUX_SOCKET_NAME__#${TMUX_SOCKET_NAME_DEFAULT//\/\\}#" "$ENV_SCRIPT"
  chmod 0644 "$ENV_SCRIPT"
}

COMMA_USER=""
COMMA_HOME=""
COMMA_SHELL=""

# Under `curl ... | sudo bash` $HOME is /root and $SHELL is inherited, neither of
# which describes the operator's real interactive shell. Resolve the invoking
# user from SUDO_USER and read their login shell out of passwd instead.
resolve_invoking_user() {
  COMMA_USER="${SUDO_USER:-$(id -un)}"
  local pw=""
  if command -v getent >/dev/null 2>&1; then
    pw="$(getent passwd "$COMMA_USER" 2>/dev/null || true)"
  fi
  if [ -n "$pw" ]; then
    COMMA_HOME="$(printf '%s' "$pw" | cut -d: -f6)"
    COMMA_SHELL="$(printf '%s' "$pw" | cut -d: -f7)"
  fi
  [ -n "$COMMA_HOME" ] || COMMA_HOME="${HOME:-}"
  # passwd often records nologin/false for LDAP or service accounts; in that
  # case whatever is actually running is the better signal.
  case "${COMMA_SHELL##*/}" in
    ''|nologin|false) COMMA_SHELL="${SHELL:-/bin/sh}" ;;
  esac
}

# Echoes the rc file for COMMA_SHELL, or returns 1 for shells we do not know how
# to edit safely.
comma_rc_file() {
  case "${COMMA_SHELL##*/}" in
    zsh)
      # Honour ZDOTDIR only when it is the user's own and lives outside the
      # sandbox. Under sudo it belongs to the elevated environment, and when the
      # installer is re-run from inside the sandbox shell ZDOTDIR is
      # $BASE_DIR/zsh -- whose .zshrc write_zshrc overwrites on every run, so an
      # alias placed there would be silently wiped by the next `sbox update`.
      if [ -z "${SUDO_USER:-}" ] && [ -n "${ZDOTDIR:-}" ] &&
         case "$ZDOTDIR" in "$BASE_DIR"|"$BASE_DIR"/*) false ;; *) true ;; esac; then
        printf '%s\n' "${ZDOTDIR}/.zshrc"
      else
        printf '%s\n' "${COMMA_HOME}/.zshrc"
      fi
      ;;
    bash) printf '%s\n' "${COMMA_HOME}/.bashrc" ;;
    ksh)  printf '%s\n' "${COMMA_HOME}/.kshrc" ;;
    fish) printf '%s\n' "${COMMA_HOME}/.config/fish/config.fish" ;;
    sh|dash|ash) printf '%s\n' "${COMMA_HOME}/.profile" ;;
    *) return 1 ;;
  esac
}

alias_block_begin() { printf '# >>> sandbox shortcut (%s) >>>' "$1"; }
alias_block_end()   { printf '# <<< sandbox shortcut (%s) <<<' "$1"; }

# awk-based rather than sed-based on purpose: the markers contain #, >, <, ( and )
# and the alias names are ',' / ',,', so every sed delimiter and regex-metachar
# choice needs escaping. awk lets us compare marker lines with string equality.
# Rewrites through `cat >` rather than `mv` so the rc file keeps its inode, owner
# and mode.
strip_alias_block() {
  local rc="$1" name="$2" tmp
  [ -f "$rc" ] || return 0
  tmp="${rc}.sbx.$$"
  # Blank lines are buffered and only flushed once a non-blank line follows, so
  # the separator blank we emit before a block is discarded along with the block
  # itself. Without this every reinstall orphans one blank line per alias and the
  # rc file grows without bound. Blank runs elsewhere are reproduced verbatim.
  awk -v b="$(alias_block_begin "$name")" -v e="$(alias_block_end "$name")" '
    $0 == b          { nb = 0; skip = 1; next }
    $0 == e          { skip = 0; next }
    skip             { next }
    /^[ \t]*$/       { nb++; next }
                     { for (i = 0; i < nb; i++) print ""; nb = 0; print }
    END              { for (i = 0; i < nb; i++) print "" }
  ' "$rc" >"$tmp" 2>/dev/null && cat "$tmp" >"$rc" 2>/dev/null
  rm -f "$tmp"
}

# Anchors on the alias name followed by '=' (posix) or whitespace (fish), so ','
# never matches a ',,' definition or vice versa.
alias_line_re() { printf '^alias[ \t]+%s([ \t]*=|[ \t])' "$1"; }

find_alias_line() {
  local rc="$1" name="$2"
  [ -f "$rc" ] || return 0
  awk -v re="$(alias_line_re "$name")" '
    { s = $0; sub(/^[ \t]+/, "", s) }
    s ~ re { print s; exit }
  ' "$rc" 2>/dev/null
}

remove_alias_line() {
  local rc="$1" name="$2" tmp
  [ -f "$rc" ] || return 0
  tmp="${rc}.sbx.$$"
  awk -v re="$(alias_line_re "$name")" '
    { s = $0; sub(/^[ \t]+/, "", s) }
    s ~ re { next }
    { print }
  ' "$rc" >"$tmp" 2>/dev/null && cat "$tmp" >"$rc" 2>/dev/null
  rm -f "$tmp"
}

# Distinguishes "an alias this installer wrote" from "an alias the user wrote".
# Only the former may be rewritten when the sandbox directory changes. Older
# installer versions wrote these without markers, so shape is the only signal:
# ',' pointed at a */bin/sandbox-shell, ',,' at a socket-scoped tmux invocation.
alias_is_sandbox_managed() {
  local name="$1" line="$2"
  case "$name" in
    ,)
      case "$line" in *"/bin/sandbox-shell"*) return 0 ;; esac
      ;;
    ,,)
      case "$line" in *tmux*-L*) return 0 ;; esac
      ;;
  esac
  return 1
}

# Installs or refreshes one alias. Reinstalling into a different --sandbox-dir
# must repoint the alias: leaving the old one behind would silently exec a path
# that no longer exists. So our own block is always dropped and rewritten with
# current paths, while an alias the user wrote themselves is left untouched.
upsert_alias() {
  local rc="$1" name="$2" line="$3" existing

  # Drop our previous block first, so what remains is only user-authored.
  strip_alias_block "$rc" "$name"

  existing="$(find_alias_line "$rc" "$name")"
  if [ -n "$existing" ]; then
    if alias_is_sandbox_managed "$name" "$existing"; then
      remove_alias_line "$rc" "$name"
      log "'${name}' alias pointed at a previous sandbox install; repointing it"
    else
      log "'${name}' alias is user-defined in ${rc}; leaving it alone"
      return 0
    fi
  fi

  mkdir -p "$(dirname "$rc")" 2>/dev/null || true
  if ! printf '\n%s\n%s\n%s\n' \
       "$(alias_block_begin "$name")" "$line" "$(alias_block_end "$name")" >>"$rc" 2>/dev/null; then
    warn "unable to write ${rc}; add manually: ${line}"
    return 0
  fi
  # If root created the file it would otherwise be root-owned and unwritable
  # for the user it was created for.
  if [ "$IS_ROOT" -eq 1 ] && [ "$COMMA_USER" != "root" ]; then
    chown "${COMMA_USER}:" "$rc" 2>/dev/null || true
  fi
  log "Set '${name}' alias in ${rc}"
}

# `,`  -> drop into the sandbox shell.
# `,,` -> attach the sandbox tmux session, creating it if absent.
# Idempotent, and repoints both at the current sandbox dir on reinstall. An
# alias the user wrote themselves is never touched. Nothing here is fatal.
install_comma_alias() {
  resolve_invoking_user
  local rc comma_line dcomma_line tmux_env tmux_cmd
  if ! rc="$(comma_rc_file)"; then
    warn "unrecognized login shell '${COMMA_SHELL}' for ${COMMA_USER}; add manually: alias ,='${BIN_DIR}/sandbox-shell'"
    return 0
  fi

  # `new-session -A -s` attaches when the session exists and creates it
  # otherwise; `attach -t` only ever attaches and fails with "no sessions" on a
  # cold server. TMUX_CONF/TMUX_CONF_LOCAL and -f matter only on the create
  # path -- an existing server already has its config loaded -- but without them
  # a session first started by ',,' would come up with stock tmux config instead
  # of the sandbox one.
  tmux_env="TMUX_CONF=${TMUX_CONF} TMUX_CONF_LOCAL=${TMUX_CONF_LOCAL}"
  tmux_cmd="tmux -L ${TMUX_SOCKET_NAME_DEFAULT} -f ${TMUX_CONF} new-session -A -s ${TMUX_SOCKET_NAME_DEFAULT}"

  if [ "${COMMA_SHELL##*/}" = "fish" ]; then
    comma_line="alias , '${BIN_DIR}/sandbox-shell'"
    # fish has no VAR=val cmd prefix syntax; `env` is the portable equivalent.
    dcomma_line="alias ,, 'env ${tmux_env} ${tmux_cmd}'"
  else
    comma_line="alias ,='${BIN_DIR}/sandbox-shell'"
    dcomma_line="alias ,,='${tmux_env} ${tmux_cmd}'"
  fi

  upsert_alias "$rc" ","  "$comma_line"
  upsert_alias "$rc" ",," "$dcomma_line"
}

# --cleanup counterpart. Removes only aliases that both look installer-generated
# and actually reference the sandbox being torn down, so a user-authored alias --
# or one belonging to a second sandbox install elsewhere -- survives.
remove_comma_aliases() {
  resolve_invoking_user
  local rc name existing
  rc="$(comma_rc_file)" || return 0
  [ -f "$rc" ] || return 0
  for name in ',' ',,'; do
    existing="$(find_alias_line "$rc" "$name")"
    [ -n "$existing" ] || continue
    case "$existing" in
      *"$BASE_DIR"*) ;;
      *)
        log "'${name}' alias in ${rc} does not reference ${BASE_DIR}; leaving it alone"
        continue
        ;;
    esac
    if ! alias_is_sandbox_managed "$name" "$existing"; then
      log "'${name}' alias is user-defined in ${rc}; leaving it alone"
      continue
    fi
    strip_alias_block "$rc" "$name"
    remove_alias_line "$rc" "$name"
    log "Removed sandbox '${name}' alias from ${rc}"
  done
}

# /etc/profile.d is the only genuinely root-owned artifact, and it is purely
# opt-in convenience (gated on SANDBOX_ENABLE anyway). Skip it without root
# instead of aborting -- the `,` alias and bin/sandbox-shell cover the same need
# from the user's own rc file.
write_profile_snippet() {
  if [ "$HAVE_PRIV" -ne 1 ]; then
    warn "skipping ${PROFILE_SNIPPET} (needs root); use the ',' alias or ${BIN_DIR}/sandbox-shell instead"
    return 0
  fi
  local tmp
  tmp="$(mktemp)" || {
    warn "unable to create temp file for ${PROFILE_SNIPPET}; skipping"
    return 0
  }
  cat <<EOF >"$tmp"
# shellcheck shell=sh
if [ -z "\${SANDBOX_ENABLE:-}" ]; then
  return 0 2>/dev/null || true
fi
if [ -f "${BASE_DIR}/activate.sh" ]; then
  . "${BASE_DIR}/activate.sh"
fi
EOF
  if $SUDO install -m 0644 "$tmp" "$PROFILE_SNIPPET" 2>/dev/null; then
    log "Wrote ${PROFILE_SNIPPET}"
  else
    warn "unable to write ${PROFILE_SNIPPET}; continuing without the system-wide hook"
  fi
  rm -f "$tmp"
}

main() {
  if [ "$IS_ROOT" -eq 1 ]; then
    log "Running as root; sandbox dir: ${BASE_DIR}"
  elif [ "$HAVE_PRIV" -eq 1 ]; then
    log "Running unprivileged with passwordless sudo available; sandbox dir: ${BASE_DIR}"
  else
    log "Running unprivileged without sudo; system package installs and ${PROFILE_SNIPPET} will be skipped. Sandbox dir: ${BASE_DIR}"
  fi
  if [ "$NO_SANDBOX" -eq 1 ]; then
    ensure_base_prereqs
    ensure_zsh || log 'zsh installation skipped (not available)'
    ensure_tmux || log 'tmux installation skipped (not available)'
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
  ensure_tmux || log 'tmux setup skipped'
  for step in \
    install_crush install_croc install_procs install_codex install_gh \
    install_fzf install_zoxide install_fd install_xh install_ripgrep \
    install_tre install_k9s install_kubecolor install_krew install_sysz \
    install_jnv install_eza install_yazi install_7zz install_yq \
    install_helix install_zellij install_delta install_bat install_btop \
    install_gobang install_duf install_broot; do
    try_step "$step"
  done
  try_step setup_tmux_files
  try_step install_zinit
  setup_zsh_files
  write_activation_script
  write_shell_wrapper
  write_sssh_wrapper
  write_sbox_wrapper
  write_profile_snippet
  install_comma_alias
  log "Installation complete. Launch ${BASE_DIR}/bin/sbox help to see lifecycle commands."
}

main "$@"
