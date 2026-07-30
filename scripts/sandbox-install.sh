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

  # Same shortcuts the outer shell's rc gets from install_comma_alias. They are
  # generated here rather than upserted, because this file is rewritten on every
  # install -- an upserted alias would be wiped by the next `sbox update`.
  #
  # ,, is spelled out rather than reusing the tmux alias above: relying on zsh to
  # recursively expand one alias into another is needlessly subtle, and the env
  # vars are only consulted when the tmux server is first started anyway.
  alias ,="${SANDBOX_HOME}/bin/sandbox-shell"
  alias ,,="TMUX_CONF=${SANDBOX_HOME}/tmux/.tmux.conf TMUX_CONF_LOCAL=${SANDBOX_HOME}/tmux/.tmux.conf.local command tmux -L ${TMUX_SOCKET_NAME} -f ${SANDBOX_HOME}/tmux/.tmux.conf new-session -A -s ${TMUX_SOCKET_NAME}"
  alias ,rv="${SANDBOX_HOME}/bin/sbx-review-open"
  alias ,gcw="${SANDBOX_HOME}/bin/sbx-gwq-gc"

  # A function, not an alias: it takes a branch argument and must cd this shell.
  ,gwq() {
    local d
    d="$("${SANDBOX_HOME}/bin/sbx-gwq-review" "$@")" || return $?
    [[ -n "$d" ]] && cd "$d"
  }
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

# Heavy lifting for the ,gwq shortcut. Kept as a script rather than inlined into
# the rc file so the logic is versioned with the sandbox and updated by `sbox
# update`; the rc side stays a two-line shim that only performs the cd.
write_gwq_review_script() {
  local target="${BIN_DIR}/sbx-gwq-review"
  cat <<'EOF' >"$target"
#!/usr/bin/env bash
# Prepare a branch for PR-style review: fetch it, materialise a gwq worktree and
# print that worktree's path on stdout. Every human-facing line goes to stderr so
# the caller can safely do:  cd "$(sbx-gwq-review <branch>)"
set -euo pipefail

log() { printf '[gwq-review] %s\n' "$*" >&2; }
die() { printf '[gwq-review] ERROR: %s\n' "$*" >&2; exit 1; }

# Invoked from whatever shell the user is in -- typically VS Code's integrated
# terminal, a plain login bash where the sandbox bin dir is NOT on PATH and gh's
# credentials are invisible (they live under the sandbox config dir, not
# ~/.config/gh). So bootstrap both instead of assuming an activated sandbox.
SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
case ":${PATH}:" in
  *":${SANDBOX_HOME}/bin:"*) ;;
  *) PATH="${SANDBOX_HOME}/bin:${PATH}"; export PATH ;;
esac
if [ -z "${GH_CONFIG_DIR:-}" ] && [ -d "${SANDBOX_HOME}/.config/gh" ]; then
  export GH_CONFIG_DIR="${SANDBOX_HOME}/.config/gh"
fi

usage() {
  cat >&2 <<'USAGE'
usage: sbx-gwq-review <branch> [base-branch]

Fetches <branch> from origin, creates or reuses a gwq worktree for it, records
the review base, and prints the worktree path on stdout.
[base-branch] defaults to origin/HEAD, then main, then master.
USAGE
}

[ $# -ge 1 ] || { usage; exit 2; }
case "$1" in -h|--help) usage; exit 0 ;; esac

branch="$1"
base_arg="${2:-}"
remote="${SBX_REVIEW_REMOTE:-origin}"

command -v gwq >/dev/null 2>&1 || die "gwq not found on PATH"
command -v jq  >/dev/null 2>&1 || die "jq not found on PATH"
git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
git remote get-url "$remote" >/dev/null 2>&1 || die "no '$remote' remote in this repository"

# Explicit refspec rather than plain `git fetch origin <branch>`: this guarantees
# refs/remotes/<remote>/<branch> exists afterwards, which is what gwq resolves
# the branch against.
log "fetching ${remote}/${branch}"
git fetch --quiet "$remote" "+refs/heads/${branch}:refs/remotes/${remote}/${branch}" \
  || die "cannot fetch branch '${branch}' from ${remote}"

# origin/HEAD is frequently unset (it is only written by an initial clone, not by
# later fetches), so fall back to the conventional names before giving up.
resolve_base() {
  local h c
  if [ -n "$base_arg" ]; then
    printf '%s' "${base_arg#"${remote}"/}"
    return 0
  fi
  if h="$(git symbolic-ref --short "refs/remotes/${remote}/HEAD" 2>/dev/null)"; then
    printf '%s' "${h#"${remote}"/}"
    return 0
  fi
  # Unset: ask the remote what its default branch is and cache the answer, so
  # this costs one network round-trip once rather than on every invocation.
  if git remote set-head "$remote" -a >/dev/null 2>&1 &&
     h="$(git symbolic-ref --short "refs/remotes/${remote}/HEAD" 2>/dev/null)"; then
    printf '%s' "${h#"${remote}"/}"
    return 0
  fi
  for c in main master; do
    if git show-ref --verify --quiet "refs/remotes/${remote}/${c}" ||
       git ls-remote --exit-code --heads "$remote" "$c" >/dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}
base="$(resolve_base)" || die "cannot determine base branch; pass it as the 2nd argument"

log "fetching base ${remote}/${base}"
git fetch --quiet "$remote" "+refs/heads/${base}:refs/remotes/${remote}/${base}" \
  || log "warning: could not refresh ${remote}/${base}; using the cached ref"

remote_ref="refs/remotes/${remote}/${branch}"

# Which worktree, if any, currently has the branch checked out.
wt_holding_branch() {
  git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${branch}" '
    /^worktree / { p = substr($0, 10) }
    $0 == "branch " b { print p; exit }
  '
}

ff_local_branch() {
  local holder
  holder="$(wt_holding_branch)"
  if [ -z "$holder" ]; then
    git branch --quiet --force "$branch" "$remote_ref" \
      && log "fast-forwarded ${branch} to ${remote}/${branch}" \
      || log "warning: could not fast-forward ${branch}"
    return 0
  fi
  # Checked out somewhere: `git branch -f` refuses, so move it via the worktree,
  # and only when there is nothing uncommitted to lose.
  if git -C "$holder" diff --quiet 2>/dev/null && git -C "$holder" diff --cached --quiet 2>/dev/null; then
    git -C "$holder" merge --ff-only "$remote_ref" >/dev/null 2>&1 \
      && log "fast-forwarded ${branch} to ${remote}/${branch}" \
      || log "warning: could not fast-forward ${branch} in ${holder}"
  else
    log "warning: ${holder} has uncommitted changes; leaving ${branch} where it is"
  fi
}

# Create the local branch explicitly rather than leaning on git's DWIM in
# `git worktree add <path> <branch>`: DWIM refuses outright ("invalid reference")
# when more than one remote publishes the same branch name, and it gives no say
# in what happens to an already-existing stale local branch.
ensure_local_branch() {
  local local_sha remote_sha
  if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
    log "creating local branch ${branch} tracking ${remote}/${branch}"
    git branch --quiet --track "$branch" "$remote_ref" \
      || die "cannot create local branch '${branch}'"
    return 0
  fi
  local_sha="$(git rev-parse --verify --quiet "refs/heads/${branch}" || true)"
  remote_sha="$(git rev-parse --verify --quiet "$remote_ref" || true)"
  [ -n "$local_sha" ] && [ -n "$remote_sha" ] || return 0
  [ "$local_sha" = "$remote_sha" ] && return 0
  if git merge-base --is-ancestor "$local_sha" "$remote_sha" 2>/dev/null; then
    ff_local_branch
  else
    log "warning: local ${branch} has diverged from ${remote}/${branch}"
    log "         reviewing the LOCAL state; 'git reset --hard ${remote}/${branch}' in the"
    log "         worktree to match the remote exactly"
  fi
}

# gwq prints a plain "No worktrees found in <dir>" line rather than `[]` when the
# basedir is empty, which makes jq exit non-zero and -- under `set -e` -- would
# abort on first use in a fresh sandbox. So sniff for a JSON array first.
wt_for_branch() {
  local json
  json="$(gwq list --json -g 2>/dev/null || true)"
  case "$json" in
    \[*) ;;
    *) return 0 ;;
  esac
  printf '%s' "$json" \
    | jq -r --arg b "$branch" '.[] | select(.branch == $b) | .path' 2>/dev/null \
    | head -n1
}

ensure_local_branch

# `gwq add` errors out when the directory already exists, so reuse takes priority.
wt="$(wt_for_branch)"
if [ -n "$wt" ] && [ -d "$wt" ]; then
  log "reusing worktree ${wt}"
else
  log "creating worktree for ${branch}"
  gwq add "$branch" >&2 || die "gwq add failed for '${branch}'"
  wt="$(wt_for_branch)"
  [ -n "$wt" ] && [ -d "$wt" ] || die "worktree path not resolvable after gwq add"
  created=1
fi

# Reap merged worktrees in the background after a new one is created.
#
# Both redirections matter. The ,gwq shim reads our stdout via command
# substitution, which blocks until *every* holder of that pipe closes it -- an
# inherited stdout in the child would hang the cd until gc finished. And stdin
# must be detached so a backgrounded child never competes for the terminal.
spawn_gc() {
  local gc="${SANDBOX_HOME}/bin/sbx-gwq-gc" log_dir="${SANDBOX_HOME}/cache"
  [ -x "$gc" ] || return 0
  mkdir -p "$log_dir" 2>/dev/null || return 0
  if command -v setsid >/dev/null 2>&1; then
    setsid "$gc" --skip "$wt" >>"${log_dir}/gwq-gc.log" 2>&1 </dev/null &
  else
    nohup "$gc" --skip "$wt" >>"${log_dir}/gwq-gc.log" 2>&1 </dev/null &
  fi
  log "reaping merged worktrees in the background (${log_dir}/gwq-gc.log)"
}
[ "${created:-0}" -eq 1 ] && spawn_gc

# Stash the base inside the worktree's gitdir -- not the working tree, so it can
# never show up in the diff being reviewed. Editor tooling reads it from here.
gitdir="$(git -C "$wt" rev-parse --absolute-git-dir)"
printf '%s\n' "${remote}/${base}" >"${gitdir}/sbx-review-base"

mb="$(git -C "$wt" merge-base "${remote}/${base}" HEAD 2>/dev/null || true)"
if [ -n "$mb" ]; then
  log "review base ${remote}/${base} @ ${mb:0:12}"
  git -C "$wt" --no-pager diff --stat "${mb}...HEAD" >&2 || true
else
  log "warning: no merge-base between HEAD and ${remote}/${base}"
fi

printf '%s\n' "$wt"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\\/\\\\}#" "$target"
  chmod +x "$target"
  log "Created gwq review helper at ${target}"
}

# Reaps worktrees whose PR has been merged. Runs both on demand and, detached,
# after every new worktree creation.
write_gwq_gc_script() {
  local target="${BIN_DIR}/sbx-gwq-gc"
  cat <<'EOF' >"$target"
#!/usr/bin/env bash
# Delete gwq worktrees (and their local branches) whose work has already landed.
#
# Merged-detection, in order:
#   1. GitHub PR state == MERGED. Authoritative, and the only signal that works
#      with squash merges -- a squash-merged branch is NOT an ancestor of the base,
#      so git alone reports it as unmerged and would never reap anything.
#   2. Otherwise: the branch tip is an ancestor of the base ref. Works offline.
#
# Deliberately conservative, because this runs unattended: anything with
# uncommitted or untracked content is skipped, as is the base branch, the main
# worktree, whatever the main checkout has checked out, detached worktrees, and
# any path outside gwq's basedir.
set -euo pipefail

SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
case ":${PATH}:" in
  *":${SANDBOX_HOME}/bin:"*) ;;
  *) PATH="${SANDBOX_HOME}/bin:${PATH}"; export PATH ;;
esac
if [ -z "${GH_CONFIG_DIR:-}" ] && [ -d "${SANDBOX_HOME}/.config/gh" ]; then
  export GH_CONFIG_DIR="${SANDBOX_HOME}/.config/gh"
fi

DRY=0
SKIP_PATH=""
usage() {
  cat >&2 <<'USAGE'
usage: sbx-gwq-gc [-n] [--skip <path>]

Removes gwq worktrees whose pull request is merged, plus their local branches.

  -n, --dry-run   report what would be removed, change nothing
      --skip      never touch this worktree path (used by sbx-gwq-review to
                  protect the worktree it just created and cd'd into)
USAGE
}
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY=1; shift ;;
    --skip) SKIP_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

ts() { date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo "-"; }
log() { printf '[gwq-gc %s] %s\n' "$(ts)" "$*"; }

git rev-parse --git-dir >/dev/null 2>&1 || { log "not in a git repository; nothing to do"; exit 0; }
command -v gwq >/dev/null 2>&1 || { log "gwq not found; nothing to do"; exit 0; }

remote="${SBX_REVIEW_REMOTE:-origin}"

# Every path comparison below must be canonicalised. `git worktree list` reports
# resolved physical paths while gwq reports symlinked ones -- on an NFS home,
# /cb/home/<user>/ws is a symlink to /net/<server>/.../ws. Comparing them raw
# makes the basedir guard match nothing (so gc silently reaps nothing) and, far
# worse, makes --skip fail to protect the worktree the caller just cd'd into.
canon() { readlink -f -- "$1" 2>/dev/null || printf '%s' "$1"; }

# Only ever touch worktrees gwq itself created.
basedir="$(gwq config get worktree.basedir 2>/dev/null | tr -d '\r' || true)"
case "$basedir" in
  /*) ;;
  *) log "cannot determine gwq worktree.basedir; refusing to remove anything"; exit 0 ;;
esac
basedir="$(canon "$basedir")"
[ -n "$SKIP_PATH" ] && SKIP_PATH="$(canon "$SKIP_PATH")"

base=""
if h="$(git symbolic-ref --short "refs/remotes/${remote}/HEAD" 2>/dev/null)"; then
  base="${h#"${remote}"/}"
else
  for c in main master; do
    git show-ref --verify --quiet "refs/remotes/${remote}/${c}" && { base="$c"; break; }
  done
fi
[ -n "$base" ] || { log "cannot determine base branch; refusing to remove anything"; exit 0; }

main_wt="$(canon "$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')")"
main_branch="$(git -C "$main_wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

# path<TAB>branch, skipping detached entries (no branch to reason about).
entries="$(git worktree list --porcelain | awk '
  /^worktree /{ p = substr($0, 10); b = "" }
  /^branch /  { b = substr($0, 8); sub(/^refs\/heads\//, "", b); print p "\t" b }
')"

removed=0; kept=0
while IFS=$'\t' read -r wt br; do
  [ -n "$wt" ] && [ -n "$br" ] || continue
  wt="$(canon "$wt")"
  [ "$wt" = "$main_wt" ] && continue
  case "$wt" in "$basedir"/*) ;; *) continue ;; esac
  [ -n "$SKIP_PATH" ] && [ "$wt" = "$SKIP_PATH" ] && { log "skip ${br}: just created"; kept=$((kept+1)); continue; }
  [ "$br" = "$base" ] && continue
  [ -n "$main_branch" ] && [ "$br" = "$main_branch" ] && continue

  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    log "skip ${br}: uncommitted or untracked changes"
    kept=$((kept+1)); continue
  fi

  merged=""; pr_merged=0
  if git merge-base --is-ancestor "refs/heads/${br}" "refs/remotes/${remote}/${base}" 2>/dev/null; then
    merged="ancestor of ${remote}/${base}"
  elif command -v gh >/dev/null 2>&1; then
    state="$(gh pr list --head "$br" --state all --json state \
               --jq 'map(select(.state=="MERGED")) | .[0].state // empty' 2>/dev/null || true)"
    if [ "$state" = "MERGED" ]; then
      merged="PR merged (squash)"
      pr_merged=1
    fi
  fi
  [ -n "$merged" ] || { kept=$((kept+1)); continue; }

  if [ "$DRY" -eq 1 ]; then
    log "would remove ${br} (${merged}) -> ${wt}"
    removed=$((removed+1)); continue
  fi

  if git worktree remove "$wt" 2>/dev/null; then
    # A squash-merged branch looks unmerged to git, so -d refuses it. -D is only
    # justified by positive evidence the work is already on the base.
    if git branch -d "$br" >/dev/null 2>&1; then
      :
    elif [ "$pr_merged" -eq 1 ] && git branch -D "$br" >/dev/null 2>&1; then
      :
    else
      log "removed worktree for ${br} but kept the local branch"
    fi
    log "removed ${br} (${merged})"
    removed=$((removed+1))
  else
    log "could not remove worktree ${wt}; leaving ${br} alone"
    kept=$((kept+1))
  fi
done <<EOT
${entries}
EOT

git worktree prune >/dev/null 2>&1 || true
gwq prune >/dev/null 2>&1 || true
if [ "$DRY" -eq 1 ]; then
  log "done (dry run): ${removed} would be removed, ${kept} kept"
else
  log "done: ${removed} removed, ${kept} kept"
fi
EOF
  sed -i "s#__BASE__#${BASE_DIR//\\/\\\\}#" "$target"
  chmod +x "$target"
  log "Created gwq gc helper at ${target}"
}

# Opens the GitHub Pull Requests extension straight onto a PR's Files Changed
# view. The extension registers a URI handler (window.registerUriHandler, active
# from onStartupFinished -- there is no onUri activation event, which is why the
# package.json gives no hint that this works). It accepts either a JSON query or,
# far more conveniently, ?uri=<github pr url>. Verified against extension 0.163.
write_review_open_script() {
  local target="${BIN_DIR}/sbx-review-open"
  cat <<'EOF' >"$target"
#!/usr/bin/env bash
# Open a branch's pull request in VS Code for review.
#
# Requires being run from VS Code's integrated terminal (Remote-SSH is fine):
# that is what puts `code` on PATH with a live VSCODE_IPC_HOOK_CLI. From a plain
# ssh or detached tmux shell there is no window to talk to.
set -euo pipefail

EXT_ID='GitHub.vscode-pull-request-github'

log() { printf '[review-open] %s\n' "$*" >&2; }
die() { printf '[review-open] ERROR: %s\n' "$*" >&2; exit 1; }

# See sbx-gwq-review: the integrated terminal is a plain login shell, so gh is
# neither on PATH nor pointed at the sandbox credentials unless we do it here.
SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
case ":${PATH}:" in
  *":${SANDBOX_HOME}/bin:"*) ;;
  *) PATH="${SANDBOX_HOME}/bin:${PATH}"; export PATH ;;
esac
if [ -z "${GH_CONFIG_DIR:-}" ] && [ -d "${SANDBOX_HOME}/.config/gh" ]; then
  export GH_CONFIG_DIR="${SANDBOX_HOME}/.config/gh"
fi

usage() {
  cat >&2 <<'USAGE'
usage: sbx-review-open [-c] [-a] [branch-or-pr-number]

Resolves the pull request for a branch and opens it in VS Code.

  (no arg)  use the current branch
  <number>  use that PR number directly
  -c        check the PR out via the extension instead of only viewing changes
  -a        also add this worktree as a folder in the current VS Code window
USAGE
}

checkout=0
add_folder=0
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--checkout) checkout=1; shift ;;
    -a|--add-folder) add_folder=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

command -v code >/dev/null 2>&1 \
  || die "'code' not on PATH -- run this from VS Code's integrated terminal"
command -v gh >/dev/null 2>&1 || die "gh not found on PATH"
git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

remote="${SBX_REVIEW_REMOTE:-origin}"
url="$(git remote get-url "$remote" 2>/dev/null)" || die "no '$remote' remote"
# Normalise https://, git@host:, and ssh://git@host/ forms down to owner/repo.
slug="$(printf '%s' "$url" \
  | sed -E 's#^(https?://[^/]+/|ssh://[^/]+/|[^@]+@[^:]+:)##; s#/+$##; s#\.git$##')"
case "$slug" in
  */*) ;;
  *) die "cannot derive owner/repo from ${remote} url: ${url}" ;;
esac
owner="${slug%%/*}"
repo="${slug#*/}"

arg="${1:-}"
if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
  pr="$arg"
else
  branch="${arg:-$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)}"
  [ -n "$branch" ] || die "detached HEAD and no branch/PR given"
  log "looking up PR for branch ${branch}"
  pr="$(gh pr list --head "$branch" --state all --json number \
          --jq 'sort_by(-.number) | .[0].number' 2>/dev/null || true)"
  [ -n "$pr" ] && [ "$pr" != "null" ] \
    || die "no pull request found for branch '${branch}' in ${owner}/${repo}"
fi

if [ "$add_folder" -eq 1 ]; then
  top="$(git rev-parse --show-toplevel)"
  log "adding ${top} to the current window"
  code --add "$top" || log "warning: could not add folder"
fi

path=/open-pull-request-changes
[ "$checkout" -eq 1 ] && path=/checkout-pull-request

# The handler regex requires exactly https://github.com/<owner>/<repo>/pull/<n>.
pr_url="https://github.com/${owner}/${repo}/pull/${pr}"
log "opening ${pr_url}"
code --open-url "vscode://${EXT_ID}${path}?uri=${pr_url}"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\\/\\\\}#" "$target"
  chmod +x "$target"
  log "Created review-open helper at ${target}"
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

has_alias_block() {
  local rc="$1" name="$2"
  [ -f "$rc" ] || return 1
  grep -Fqx "$(alias_block_begin "$name")" "$rc"
}

alias_block_body() {
  local rc="$1" name="$2"
  [ -f "$rc" ] || return 0
  awk -v b="$(alias_block_begin "$name")" -v e="$(alias_block_end "$name")" '
    $0 == b { inb = 1; next }
    $0 == e { inb = 0; next }
    inb     { print }
  ' "$rc" 2>/dev/null
}

# Anchors on the shortcut name followed by '=' (posix alias), whitespace (fish
# alias), or '()' (shell function), so ',' never matches a ',,' definition or
# vice versa and a function-form shim like ',gwq()' is still detected.
#
# The parens are [(][)] rather than \(\) because this is consumed as a *dynamic*
# awk regex, where awk collapses the escape \( into a bare (. That turned the
# branch into ',[ \t]*()' -- an empty group, matching every line starting with a
# comma. ',' then matched ',gwq() {', mistook its own block for a user-authored
# alias, and deleted itself. Bracket expressions cannot be misread this way.
alias_line_re() { printf '^(alias[ \t]+%s([ \t]*=|[ \t])|%s[ \t]*[(][)])' "$1" "$1"; }

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
  local rc comma_line dcomma_line gwq_line rv_line gc_line tmux_env tmux_cmd
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

  # ,gwq must be a function, not an alias: it takes a branch argument and has to
  # cd the *calling* shell, which a subprocess cannot do. Comma-prefixed function
  # names are accepted by both bash and zsh.
  if [ "${COMMA_SHELL##*/}" = "fish" ]; then
    gwq_line="function ,gwq
    set -l d (${BIN_DIR}/sbx-gwq-review \$argv); or return \$status
    test -n \"\$d\"; and cd \$d
end"
  else
    gwq_line=",gwq() {
  local d
  d=\"\$(${BIN_DIR}/sbx-gwq-review \"\$@\")\" || return \$?
  [ -n \"\$d\" ] && cd \"\$d\"
}"
  fi

  # ,rv needs no cd, so a plain alias suffices -- arguments append after the
  # expansion, which is exactly what we want.
  if [ "${COMMA_SHELL##*/}" = "fish" ]; then
    rv_line="alias ,rv '${BIN_DIR}/sbx-review-open'"
    gc_line="alias ,gcw '${BIN_DIR}/sbx-gwq-gc'"
  else
    rv_line="alias ,rv='${BIN_DIR}/sbx-review-open'"
    gc_line="alias ,gcw='${BIN_DIR}/sbx-gwq-gc'"
  fi

  upsert_alias "$rc" ","     "$comma_line"
  upsert_alias "$rc" ",,"    "$dcomma_line"
  upsert_alias "$rc" ",gwq"  "$gwq_line"
  upsert_alias "$rc" ",rv"   "$rv_line"
  upsert_alias "$rc" ",gcw"  "$gc_line"
}

# --cleanup counterpart. Removes only aliases that both look installer-generated
# and actually reference the sandbox being torn down, so a user-authored alias --
# or one belonging to a second sandbox install elsewhere -- survives.
remove_comma_aliases() {
  resolve_invoking_user
  local rc name existing
  rc="$(comma_rc_file)" || return 0
  [ -f "$rc" ] || return 0
  for name in ',' ',,' ',gwq' ',rv' ',gcw'; do
    # A marker block is ours by construction, so match on its body rather than on
    # the definition line -- a function-form shim's first line is just ',gwq()'
    # and carries no path to test against BASE_DIR.
    if has_alias_block "$rc" "$name"; then
      case "$(alias_block_body "$rc" "$name")" in
        *"$BASE_DIR"*)
          strip_alias_block "$rc" "$name"
          log "Removed sandbox '${name}' shortcut from ${rc}"
          ;;
        *)
          log "'${name}' block in ${rc} belongs to another sandbox; leaving it alone"
          ;;
      esac
      continue
    fi
    # Unmarked leftover from an installer version that predates the markers.
    existing="$(find_alias_line "$rc" "$name")"
    [ -n "$existing" ] || continue
    if ! alias_is_sandbox_managed "$name" "$existing"; then
      log "'${name}' is user-defined in ${rc}; leaving it alone"
      continue
    fi
    case "$existing" in
      *"$BASE_DIR"*) ;;
      *)
        log "'${name}' in ${rc} does not reference ${BASE_DIR}; leaving it alone"
        continue
        ;;
    esac
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
  write_gwq_review_script
  write_review_open_script
  write_gwq_gc_script
  write_profile_snippet
  install_comma_alias
  log "Installation complete. Launch ${BASE_DIR}/bin/sbox help to see lifecycle commands."
}

main "$@"
