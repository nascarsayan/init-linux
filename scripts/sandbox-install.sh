#!/usr/bin/env bash
set -euo pipefail

umask 022

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
TEMPLATE_ZSHRC="${SCRIPT_DIR}/../templates/zshrc-tpl.zsh"
TEMPLATE_TMUX="${SCRIPT_DIR}/../templates/tmuxrc-tpl.conf"
DEFAULT_TEMPLATE_URL="https://raw.githubusercontent.com/nascarsayan/init-linux/zinit/templates/zshrc-tpl.zsh"
DEFAULT_TMUX_URL="https://raw.githubusercontent.com/nascarsayan/.tmux.local/master/.tmux.conf.local"
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
SANDBOX_MODE=$(( NO_SANDBOX ? 0 : 1 ))

# Sandbox paths
BASE_DIR="$SANDBOX_HOME"
BIN_DIR="${BASE_DIR}/bin"
CACHE_DIR="${BASE_DIR}/cache"
ZSH_DIR="${BASE_DIR}/zsh"
TMUX_DIR="${BASE_DIR}/tmux"
FZF_DIR="${BASE_DIR}/fzf"
P10K_DIR="${BASE_DIR}/p10k"
KREW_DIR="${BASE_DIR}/krew"
ZINIT_HOME="${BASE_DIR}/zinit/zinit.git"
ENV_SCRIPT="${BASE_DIR}/activate.sh"
PROFILE_SNIPPET="/etc/profile.d/sandbox.sh"

cleanup_environment() {
  require_root
  log "Removing ${BASE_DIR}"
  rm -rf "$BASE_DIR"
  if [ -f "$PROFILE_SNIPPET" ]; then
    log "Removing ${PROFILE_SNIPPET}"
    rm -f "$PROFILE_SNIPPET"
  fi
  log "Cleanup complete"
}

ensure_dirs() {
  mkdir -p "$BIN_DIR" "$CACHE_DIR" "$ZSH_DIR" "$TMUX_DIR" "$FZF_DIR" "$P10K_DIR" "$KREW_DIR" "$(dirname "$ZINIT_HOME")"
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
      for pkg in fzf zoxide tmux; do
        if ! install_pkg "$pkg"; then
          log "Warning: unable to install $pkg via apt"
        fi
      done
      ;;
    dnf)
      for pkg in fzf zoxide tmux; do
        if ! install_pkg "$pkg"; then
          log "Warning: unable to install $pkg via dnf"
        fi
      done
      ;;
    *)
      if command -v brew >/dev/null 2>&1; then
        for pkg in fzf zoxide tmux; do
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

ensure_tmux() {
  if ensure_command tmux; then
    return
  fi
  log 'tmux not found; attempting installation'
  detect_pkg_manager
  case "$pkg_manager" in
    apt)
      install_pkg tmux
      ;;
    dnf)
      install_pkg tmux
      ;;
    *)
      log 'tmux unavailable (no apt/dnf); skipping tmux binary install'
      return 1
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
  KREW_ROOT="$krew_root" KREW_HOME="$krew_root" "${tmp}/krew-${os}_${arch}" install krew >/dev/null 2>&1 || log 'Warning: failed to bootstrap krew'
  rm -rf "$tmp" "$archive"
  log "Installed krew under ${krew_root}"
}

write_zshenv() {
  cat <<'EOF' >"${ZSH_DIR}/.zshenv"
export SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
export PATH="${SANDBOX_HOME}/bin:${PATH}"
export ZINIT_HOME="${SANDBOX_HOME}/zinit/zinit.git"
export TMUX_HOME="${SANDBOX_HOME}/tmux"
export FZF_HOME="${SANDBOX_HOME}/fzf"
[ -f "${TMUX_HOME}/.tmux.conf" ] && export TMUX_CONF="${TMUX_HOME}/.tmux.conf"
[ -r "${SANDBOX_HOME}/p10k/p10k.zsh" ] && export P10K_CONFIG="${SANDBOX_HOME}/p10k/p10k.zsh"
export KREW_ROOT="${SANDBOX_HOME}/krew"
export KREW_HOME="${KREW_ROOT}"
export PATH="${KREW_ROOT}/bin:${PATH}"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\/\\}#" "${ZSH_DIR}/.zshenv"
}

write_zshrc() {
  if [ -f "$TEMPLATE_ZSHRC" ]; then
    cp "$TEMPLATE_ZSHRC" "${ZSH_DIR}/.zshrc"
    chmod 0644 "${ZSH_DIR}/.zshrc"
    return
  fi

  local template_url="${SANDBOX_TEMPLATE_URL:-$DEFAULT_TEMPLATE_URL}"
  if curl -fsSL "$template_url" -o "${ZSH_DIR}/.zshrc"; then
    chmod 0644 "${ZSH_DIR}/.zshrc"
    log "Fetched zsh template from ${template_url}"
    return
  else
    log "Zsh template not found at ${TEMPLATE_ZSHRC} and download failed from ${template_url}; writing minimal config"
    cat <<'EOF' >"${ZSH_DIR}/.zshrc"
if [ -n "${SANDBOX_HOME:-}" ] && [ -f "${SANDBOX_HOME}/zinit/zinit.git/zinit.zsh" ]; then
  source "${SANDBOX_HOME}/zinit/zinit.git/zinit.zsh"
fi
EOF
  fi
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

write_login_wrapper() {
  local wrapper="${BIN_DIR}/sandbox-login"
  cat <<'EOF' >"$wrapper"
#!/usr/bin/env bash
set -e
SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
if [ -f "${SANDBOX_HOME}/activate.sh" ]; then
  # shellcheck disable=SC1090
  source "${SANDBOX_HOME}/activate.sh"
fi
exec zsh -il "$@"
EOF
  sed -i "s#__BASE__#${BASE_DIR//\\/\\\\}#" "$wrapper"
  chmod +x "$wrapper"
  log "Created sandbox login wrapper at ${wrapper}"
}

install_tmux_local() {
  if ! ensure_command git; then
    log 'Git not available; skipping tmux repo clone'
    return
  fi
  git_clone_or_update https://github.com/gpakosz/.tmux.git "${TMUX_DIR}/.tmux"
  git_clone_or_update https://github.com/nascarsayan/.tmux.local.git "${TMUX_DIR}/.tmux.local"
}

setup_tmux_files() {
  install_tmux_local
  local target_conf="${TMUX_DIR}/.tmux.conf"
  if [ -f "$TEMPLATE_TMUX" ]; then
    cp "$TEMPLATE_TMUX" "$target_conf"
    chmod 0644 "$target_conf"
  else
    local tmux_url="${SANDBOX_TMUX_TEMPLATE_URL:-$DEFAULT_TMUX_URL}"
    if curl -fsSL "$tmux_url" -o "$target_conf"; then
      chmod 0644 "$target_conf"
      log "Fetched tmux template from ${tmux_url}"
    else
      log "Tmux template unavailable; skipping tmux configuration"
      rm -f "$target_conf"
    fi
  fi

  if [ -d "${TMUX_DIR}/.tmux" ]; then
    ln -sf "${TMUX_DIR}/.tmux/.tmux.conf" "$target_conf"
  fi
  if [ -d "${TMUX_DIR}/.tmux.local" ] && [ -f "${TMUX_DIR}/.tmux.local/.tmux.conf.local" ]; then
    ln -sf "${TMUX_DIR}/.tmux.local/.tmux.conf.local" "${TMUX_DIR}/.tmux.conf.local"
  fi
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
[ "${SANDBOX_ENV_ACTIVATED:-0}" -eq 1 ] && return 0 2>/dev/null || true
export SANDBOX_ENV_ACTIVATED=1
export SANDBOX_HOME="${SANDBOX_HOME:-__BASE__}"
export PATH="${SANDBOX_HOME}/bin:${PATH}"
export ZDOTDIR="${SANDBOX_HOME}/zsh"
export ZINIT_HOME="${SANDBOX_HOME}/zinit/zinit.git"
export TMUX_HOME="${SANDBOX_HOME}/tmux"
export FZF_HOME="${SANDBOX_HOME}/fzf"
[ -f "${TMUX_HOME}/.tmux.conf" ] && export TMUX_CONF="${TMUX_HOME}/.tmux.conf"
[ -r "${SANDBOX_HOME}/p10k/p10k.zsh" ] && export P10K_CONFIG="${SANDBOX_HOME}/p10k/p10k.zsh"
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
  require_root
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
  install_crush
  install_croc
  install_codex
  install_gh
  install_fzf
  install_zoxide
  install_k9s
  install_kubecolor
  install_krew
  install_zinit
  setup_zsh_files
  setup_tmux_files
  write_activation_script
  write_login_wrapper
  write_profile_snippet
  log 'Installation complete. Use /root/sandbox/bin/sandbox-login (e.g. via SSH RemoteCommand) or source /root/sandbox/activate.sh manually.'
}

main "$@"
