#!/usr/bin/env bash
# Smart coloured Bash tracer wrapper
# Shows time (ISO), PID, PPID, CWD (as "." if same as entry script dir),
# file:line, and funcname.  Works recursively through sourced/child bash scripts.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <script> [args...]" >&2
  exit 1
fi

# --- record entry script's absolute directory ---
ENTRY_SCRIPT="$1"
ENTRY_DIR="$(cd "$(dirname "$ENTRY_SCRIPT")" && pwd)"
export ENTRY_DIR

# --- colour setup (only if stderr is a TTY) ---
if [[ -t 2 ]]; then
  RED=$'\e[0;31m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[0;33m'; BLUE=$'\e[0;34m'
  MAGENTA=$'\e[0;35m'; CYAN=$'\e[0;36m'; NC=$'\e[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; NC=''
fi

# --- create a temp BASH_ENV file injected into all child bash shells ---
TRACER_ENV="$(mktemp -t bash_tracer_env.XXXXXX)"
cat > "$TRACER_ENV" <<'EOF'
# --- injected by bash-tracer.sh ---
if [[ -t 2 ]]; then
  RED=$'\e[0;31m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[0;33m'; BLUE=$'\e[0;34m'
  MAGENTA=$'\e[0;35m'; CYAN=$'\e[0;36m'; NC=$'\e[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; NC=''
fi

# compute cwd display (show "." if same as entry dir)
_current_dir="$(pwd)"
if [[ -n "${ENTRY_DIR:-}" && "$_current_dir" == "$ENTRY_DIR" ]]; then
  _display_cwd="."
else
  _display_cwd="$_current_dir"
fi

export PS4=$'${RED}time=${YELLOW}$(date "+%Y-%m-%dT%H:%M:%S")'\
$'${NC} ${MAGENTA}pid=${CYAN}$$${NC} ${MAGENTA}ppid=${CYAN}$PPID${NC} '\
$'${BLUE}cwd=${GREEN}${_display_cwd}${NC} '\
$'${BLUE}file=${GREEN}${BASH_SOURCE}:${LINENO}${NC} '\
$'${BLUE}func=${CYAN}${FUNCNAME[0]:-main}${NC}\n'\
$'${GREEN}↳${NC} '
set -o xtrace
EOF

trap 'rm -f "$TRACER_ENV"' EXIT
export BASH_ENV="$TRACER_ENV"

exec bash "$@"
