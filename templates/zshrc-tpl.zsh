# Sandbox-aware zsh configuration template

# Switch to sandbox paths when SANDBOX_HOME is set, otherwise behave like a
# regular standalone configuration.
typeset -g __SANDBOX_HAS_BASE=0
if [[ -n "${SANDBOX_HOME:-}" ]]; then
  __SANDBOX_HAS_BASE=1
  export XDG_CACHE_HOME="${SANDBOX_HOME}/.cache"
  export XDG_CONFIG_HOME="${SANDBOX_HOME}/.config"
  export XDG_DATA_HOME="${SANDBOX_HOME}/.local/share"
  : "${ZINIT_HOME:=${SANDBOX_HOME}/zinit/zinit.git}"
  export FZF_HOME="${SANDBOX_HOME}/fzf"
  export KREW_ROOT="${SANDBOX_HOME}/krew"
  export KREW_HOME="${KREW_ROOT}"
  export HELIX_CONFIG_DIR="${XDG_CONFIG_HOME}/helix"
  export HELIX_RUNTIME="${HELIX_CONFIG_DIR}/runtime"
  : "${P10K_DEFAULT:=${SANDBOX_HOME}/p10k/p10k.zsh}"
else
  : "${ZINIT_HOME:=${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git}"
  : "${P10K_DEFAULT:=${HOME}/.p10k.zsh}"
  : "${KREW_ROOT:=${HOME}/.krew}"
  export KREW_HOME="${KREW_ROOT}"
fi

# eda_off/eda_on + interactive LD_LIBRARY_PATH strip moved to .zshenv
# (must run before /etc/zshrc spawns subprocesses).

instant_prompt="${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
[[ -r "${instant_prompt}" ]] && source "${instant_prompt}"
unset instant_prompt

source "${ZINIT_HOME}/zinit.zsh"

# No-tty sandboxes lack job control (monitor/zle), so zinit's wait"0" turbo
# scheduling below can fire before the synchronous `compinit` call further
# down defines the real compdef. Stub it so early calls no-op instead of
# erroring; compinit overwrites this with the working function.
(( $+functions[compdef] )) || compdef() { :; }

autoload -Uz is-at-least
if is-at-least 5.1 "$ZSH_VERSION"; then
  export POWERLEVEL10K_DISABLE_CONFIGURATION_WIZARD=1
  zinit ice depth=1
  zinit load romkatv/powerlevel10k
else
  print -P "%F{yellow}[sandbox]%f Skipping powerlevel10k (needs zsh>=5.1, current $ZSH_VERSION)."
fi

zinit ice wait"0" lucid; zinit snippet OMZ::plugins/git/git.plugin.zsh
zinit ice wait"0" lucid; zinit snippet OMZ::plugins/sudo/sudo.plugin.zsh
zinit ice wait"0" lucid; zinit snippet OMZ::plugins/colored-man-pages/colored-man-pages.plugin.zsh
zinit ice wait"0" lucid; zinit snippet OMZ::plugins/kubectl/kubectl.plugin.zsh
zinit ice wait"0" lucid; zinit snippet OMZ::plugins/docker/docker.plugin.zsh
zinit ice wait"0" lucid; zinit snippet OMZ::plugins/docker-compose/docker-compose.plugin.zsh
zinit ice wait"0" lucid; zinit snippet OMZ::plugins/helm/helm.plugin.zsh
zinit ice wait"0" lucid; zinit snippet OMZ::plugins/vscode/vscode.plugin.zsh
zinit ice wait"0" lucid; zinit snippet OMZ::plugins/git-extras/git-extras.plugin.zsh

zinit ice wait"0" lucid; zinit load zsh-users/zsh-autosuggestions
zinit ice wait"0" lucid blockf; zinit load zsh-users/zsh-completions
# syntax-highlighting must load sync (needs $region_highlight from ZLE);
# turbo runs it before ZLE init -> "region_highlight not defined".
zinit load zsh-users/zsh-syntax-highlighting

zinit ice wait"0" lucid; zinit snippet https://raw.githubusercontent.com/ahmetb/kubectl-alias/master/.kubectl_aliases

alias git_current_branch="git rev-parse --abbrev-ref HEAD"
alias ggpush='git push origin $(git_current_branch)'
mkcd() {
  if [ $# -eq 0 ]; then
    printf 'usage: mkcd <directory>\n' >&2
    return 1
  fi
  mkdir -p -- "$1" && cd -- "$1"
}

alias mkcd=mkcd
if (( __SANDBOX_HAS_BASE )); then
  : "${TMUX_SOCKET_NAME:=sayann}"
fi

if command -v pass >/dev/null 2>&1; then
  sshp() {
    SSHPASS="$(pass show ssh/cb)" sshpass -e ssh "$@"
  }
fi

DISABLE_MAGIC_FUNCTIONS=true
DISABLE_UPDATE_PROMPT=true

if (( __SANDBOX_HAS_BASE )); then
  HISTFILE="${SANDBOX_HOME}/zsh/.zsh_history"
else
  HISTFILE="${HOME}/.zsh_history"
fi
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS

# Defer subprocess-spawning prompt integrations to first precmd. Cold NFS
# fork+exec is the slowest part of shell startup; running these after the
# prompt is drawn means the user sees their shell immediately.
__defer_init_done=0
__defer_init() {
  (( __defer_init_done )) && return
  __defer_init_done=1
  command -v mise   >/dev/null 2>&1 && eval "$(mise activate zsh)"
  command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
  command -v atuin  >/dev/null 2>&1 && eval "$(atuin init zsh --disable-up-arrow)"
  add-zsh-hook -d precmd __defer_init
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd __defer_init

if command -v fzf >/dev/null 2>&1; then
  if [[ -n "${FZF_HOME:-}" && -f "${FZF_HOME}/completion.zsh" ]]; then
    source "${FZF_HOME}/completion.zsh"
  elif [[ -f /usr/share/fzf/completion.zsh ]]; then
    source /usr/share/fzf/completion.zsh
  fi
  if [[ -n "${FZF_HOME:-}" && -f "${FZF_HOME}/key-bindings.zsh" ]]; then
    source "${FZF_HOME}/key-bindings.zsh"
  elif [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
  fi
fi

if [[ -d "${KREW_ROOT:-}/bin" ]]; then
  PATH="${KREW_ROOT}/bin:${PATH}"
fi

# ghq + gwq: unified repo/worktree tree under ~/ws/ghq. gwq shim (cd.launch_shell=false
# in ~/.config/gwq/config.toml) lets `gwq cd`/`gwq add` cd this shell instead of spawning one.
if command -v gwq >/dev/null 2>&1; then
  source <(gwq completion zsh)
fi

if command -v ghq >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
  # fzf shows "<repo> <branch>" (padded, aligned); full path travels as a hidden
  # 2nd tab-delimited field for the preview and for cd, so long ~/ws/ghq/... paths
  # never clutter the picker.
  ghq-path() {
    local -A branch_of
    local p b
    while IFS=$'\t' read -r p b; do
      branch_of[$p]=$b
    done < <(gwq list --json -g 2>/dev/null | jq -r '.[] | [.path, .branch] | @tsv')

    local base label br
    for p in ${(f)"$(ghq list --full-path 2>/dev/null)"}; do
      br=${branch_of[$p]:-$(git -C "$p" symbolic-ref --short HEAD 2>/dev/null)}
      base=${p:t}
      label=${base%%=*}
      printf '%s %s\t%s\n' "$label" "${br:-detached}" "$p"
    done | fzf --delimiter '\t' --with-nth 1 \
               --preview 'git -C {2} log -1 --stat --color=always 2>/dev/null' \
               --preview-window 'right:60%' \
      | cut -f2
  }

  # fuzzy-jump to any repo or worktree
  dev() {
    local moveto
    moveto="$(ghq-path)" || return 1
    [[ -z "$moveto" ]] && return 1
    builtin cd "$moveto" || return 1
  }
fi

BUN_INSTALL="${BUN_INSTALL:-${SANDBOX_HOME:-$HOME}/.bun}"
MONOLITH_HOME="${MONOLITH_HOME:-${HOME}/ws/monolith}"
# PYTHONPATH="${PYTHONPATH:-${MONOLITH_HOME}/src/infra}"
export BUN_INSTALL MONOLITH_HOME

# GITTOP tracks the enclosing git repo and is recomputed on every directory
# change -- the zsh counterpart of what Cerebras' global bashrc does in bash
# (`GITTOP=$(git rev-parse --show-toplevel); export GITTOP`, per directory).
# Without a hook zsh simply inherits whatever GITTOP the launching bash happened
# to have, which is why values like .../ws/init-linux used to leak in and stick.
#
# Walked in pure zsh instead of forking git: output is identical in every case
# tested -- including a worktree nested inside another repo, where both correctly
# yield the worktree rather than its parent -- but it costs 0.1ms against 6.5ms
# for `git rev-parse`, and this runs on every cd. ${d:A} resolves symlinks so the
# value matches git's physical path, as the bash version's does.
#
# Note this deliberately does NOT source ${GITTOP}/flow/devenv.sh the way bash's
# auto-loader does; that pulls in monolith module loads and is far too heavy to
# run on every directory change.
_sbx_set_gittop() {
  local d=$PWD
  while [[ -n $d && $d != / ]]; do
    if [[ -e $d/.git ]]; then
      export GITTOP=${d:A}
      return 0
    fi
    d=${d:h}
  done
  # Empty rather than unset when outside a repo, mirroring bash, where callers
  # test `[ -z "$GITTOP" ]`.
  export GITTOP=""
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _sbx_set_gittop
_sbx_set_gittop   # seed for the directory the shell starts in

if command -v kubectl >/dev/null 2>&1 && command -v krew >/dev/null 2>&1; then
  export KREW_ROOT="${KREW_ROOT:-${HOME}/.krew}"
  export KREW_HOME="${KREW_HOME:-${KREW_ROOT}}"
fi

zinit ice blockf
# zinit light Aloxaf/fzf-tab

zstyle ':completion:*' menu select
zstyle ':completion:*:descriptions' format '%d'
# zstyle ':fzf-tab:*' switch-group ',' '.'

: "${ZSH_COMPDUMP:=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/.zcompdump-${HOST}-${ZSH_VERSION}}"
[[ -d ${ZSH_COMPDUMP:h} ]] || mkdir -p ${ZSH_COMPDUMP:h}
autoload -Uz compinit
# -C is what keeps startup fast: it trusts the dumpfile and skips scanning fpath
# for new completions. The cost is that a completion added later is invisible
# forever -- a dump can sit months stale while `kubectl <TAB>` silently misses
# anything registered since. So do one full rebuild whenever the dump is over a
# day old, and take the fast path otherwise.
if [[ -n ${ZSH_COMPDUMP}(#qN.mh+24) || ! -s ${ZSH_COMPDUMP} ]]; then
  # Prune dangling completion symlinks before the full scan. zinit symlinks each
  # completion to an absolute path under its plugins dir, so anything that moves
  # that path -- an NFS server rename, or relocating the sandbox -- leaves every
  # link broken and makes compinit emit hundreds of "no such file or directory"
  # lines. `compinit -C` hid this for months while completions silently vanished.
  if [[ -n ${ZINIT[COMPLETIONS_DIR]:-} && -d ${ZINIT[COMPLETIONS_DIR]} ]]; then
    _sbx_dangling=()
    for _sbx_c in ${ZINIT[COMPLETIONS_DIR]}/*(N@); do
      [[ -e $_sbx_c ]] || _sbx_dangling+=($_sbx_c)
    done
    unset _sbx_c
    if (( $#_sbx_dangling )); then
      rm -f -- $_sbx_dangling
      print -P "%F{yellow}[sandbox]%f pruned $#_sbx_dangling dangling completion link(s); run 'zinit creinstall zsh-users/zsh-completions' to restore them."
    fi
    unset _sbx_dangling
  fi
  compinit -d "$ZSH_COMPDUMP"
else
  compinit -C -d "$ZSH_COMPDUMP"
fi

autoload -U +X bashcompinit && bashcompinit

# Route kubectl through kubecolor, but only for subcommands it can safely
# colorize. A bare `alias kubectl=kubecolor` breaks `exec -it`, `attach`,
# `port-forward`, `logs -f` and `get -w`: kubecolor buffers stdout to colorize it,
# which is incompatible with raw bidirectional pty streaming, so those hang with
# zero output. A function rather than an alias for two reasons -- it can dispatch
# per subcommand, and the typed word stays `kubectl`, so the existing
# _comps[kubectl] completion applies with no extra wiring (an alias would expand
# to `kubecolor` and need its own compdef).
if (( $+commands[kubecolor] )); then
  kubectl() {
    local sub="" a
    for a in "$@"; do
      [[ $a == -* ]] || { sub=$a; break }
    done
    local -a passthrough=(exec attach port-forward proxy cp edit debug wait)
    # Streaming/interactive: must reach the terminal unbuffered.
    if (( ${passthrough[(I)$sub]} )); then
      command kubectl "$@"
      return
    fi
    case $sub in
      logs)
        if (( ${@[(I)-f]} || ${@[(I)--follow]} )); then command kubectl "$@"; return; fi ;;
      get)
        if (( ${@[(I)-w]} || ${@[(I)--watch]} || ${@[(I)--watch-only]} )); then command kubectl "$@"; return; fi ;;
      run|debug)
        if (( ${@[(I)-i]} || ${@[(I)-t]} || ${@[(I)-it]} || ${@[(I)--stdin]} || ${@[(I)--tty]} )); then
          command kubectl "$@"; return
        fi ;;
    esac
    command kubecolor "$@"
  }
  # So that invoking `kubecolor` directly completes too. Deferred, because
  # _comps[kubectl] is populated by the turbo-loaded OMZ plugin, i.e. after this
  # point in the file.
  _sbx_kubecolor_compdef() {
    (( $+_comps[kubectl] )) && compdef kubecolor=kubectl 2>/dev/null
    add-zsh-hook -d precmd _sbx_kubecolor_compdef
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _sbx_kubecolor_compdef
fi

if [[ -n "${P10K_CONFIG:-}" && -f "${P10K_CONFIG}" ]]; then
  source "${P10K_CONFIG}"
elif [[ -f "${SANDBOX_HOME:-${HOME}}/zsh/.p10k.zsh" ]]; then
  source "${SANDBOX_HOME:-${HOME}}/zsh/.p10k.zsh"
elif [[ -f "${P10K_DEFAULT}" ]]; then
  source "${P10K_DEFAULT}"
fi
unset P10K_DEFAULT

WORDCHARS=''

bindkey -e

# broot's `br` shell function. The bash launcher is zsh-compatible, and inside the
# sandbox XDG_CONFIG_HOME points at <sandbox>/.config, so this resolves to the
# sandbox's own broot install. Kept in the template because write_zshrc rewrites
# this file on every install -- appending it live would be lost on the next one.
_broot_launcher="${XDG_CONFIG_HOME:-$HOME/.config}/broot/launcher/bash/br"
[[ -r "${_broot_launcher}" ]] && source "${_broot_launcher}"
unset _broot_launcher
