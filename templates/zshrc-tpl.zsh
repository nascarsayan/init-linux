# Sandbox-aware zsh configuration template

# Switch to sandbox paths when SANDBOX_HOME is set, otherwise behave like a
# regular standalone configuration.
typeset -g __SANDBOX_HAS_BASE=0
if [[ -n "${SANDBOX_HOME:-}" ]]; then
  __SANDBOX_HAS_BASE=1
  export XDG_CACHE_HOME="${SANDBOX_HOME}/zsh/cache"
  export XDG_DATA_HOME="${SANDBOX_HOME}/zinit"
  export XDG_CONFIG_HOME="${SANDBOX_HOME}/zsh/config"
  : "${ZINIT_HOME:=${SANDBOX_HOME}/zinit/zinit.git}"
  export TMUX_HOME="${SANDBOX_HOME}/tmux"
  export FZF_HOME="${SANDBOX_HOME}/fzf"
  export KREW_ROOT="${SANDBOX_HOME}/krew"
  export KREW_HOME="${KREW_ROOT}"
  : "${P10K_DEFAULT:=${SANDBOX_HOME}/p10k/p10k.zsh}"
else
  : "${ZINIT_HOME:=${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git}"
  : "${P10K_DEFAULT:=${HOME}/.p10k.zsh}"
  : "${KREW_ROOT:=${HOME}/.krew}"
  export KREW_HOME="${KREW_ROOT}"
fi

instant_prompt="${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
if [[ __SANDBOX_HAS_BASE -eq 1 ]]; then
  instant_prompt="${SANDBOX_HOME}/zsh/cache/p10k-instant-prompt-${(%):-%n}.zsh"
fi
[[ -r "${instant_prompt}" ]] && source "${instant_prompt}"
unset instant_prompt

source "${ZINIT_HOME}/zinit.zsh"

autoload -Uz is-at-least
if is-at-least 5.1 "$ZSH_VERSION"; then
  export POWERLEVEL10K_DISABLE_CONFIGURATION_WIZARD=1
  zinit ice depth=1
  zinit load romkatv/powerlevel10k
else
  print -P "%F{yellow}[sandbox]%f Skipping powerlevel10k (needs zsh>=5.1, current $ZSH_VERSION)."
fi

zinit snippet OMZ::plugins/git/git.plugin.zsh
zinit snippet OMZ::plugins/sudo/sudo.plugin.zsh
zinit snippet OMZ::plugins/colored-man-pages/colored-man-pages.plugin.zsh
zinit snippet OMZ::plugins/kubectl/kubectl.plugin.zsh
zinit snippet OMZ::plugins/docker/docker.plugin.zsh
zinit snippet OMZ::plugins/docker-compose/docker-compose.plugin.zsh
zinit snippet OMZ::plugins/helm/helm.plugin.zsh
zinit snippet OMZ::plugins/vscode/vscode.plugin.zsh
zinit snippet OMZ::plugins/git-extras/git-extras.plugin.zsh

zinit load zsh-users/zsh-autosuggestions
zinit load zsh-users/zsh-syntax-highlighting
zinit load zsh-users/zsh-completions

zinit snippet https://raw.githubusercontent.com/ahmetb/kubectl-alias/master/.kubectl_aliases

alias git_current_branch="git rev-parse --abbrev-ref HEAD"
alias ggpush='git push origin $(git_current_branch)'

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

for file in "$HOME/.local/share/omarchy/default/bash/envs" \
            "$HOME/.local/share/omarchy/default/bash/aliases" \
            "$HOME/.local/share/omarchy/default/bash/functions"; do
  [ -f "$file" ] && source "$file"
done

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

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

BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
PATH="${BUN_INSTALL}/bin:${PATH}"
GITTOP="${GITTOP:-${HOME}/Code/monolith}"
PYTHONPATH="${PYTHONPATH:-${HOME}/Code/monolith/src/cluster_deployment/deployment/}"
export BUN_INSTALL PATH GITTOP PYTHONPATH

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

if [[ -z "${TMUX_CONF:-}" && -n "${TMUX_HOME:-}" && -f "${TMUX_HOME}/.tmux.conf" ]]; then
  export TMUX_CONF="${TMUX_HOME}/.tmux.conf"
fi
if command -v tmux >/dev/null 2>&1 && [[ -n "${TMUX_CONF:-}" && -f "${TMUX_CONF}" ]]; then
  alias tmux="tmux -f ${TMUX_CONF}"
fi

if command -v kubecolor >/dev/null 2>&1; then
  alias kubectl="kubecolor"
fi

if command -v kubectl >/dev/null 2>&1 && command -v krew >/dev/null 2>&1; then
  export KREW_ROOT="${KREW_ROOT:-${HOME}/.krew}"
  export KREW_HOME="${KREW_HOME:-${KREW_ROOT}}"
fi

zinit ice blockf
zinit light Aloxaf/fzf-tab

zstyle ':completion:*' menu select
zstyle ':completion:*:descriptions' format '%d'
zstyle ':fzf-tab:*' switch-group ',' '.'

autoload -Uz compinit
compinit

autoload -U +X bashcompinit && bashcompinit

if [[ -n "${P10K_CONFIG:-}" && -f "${P10K_CONFIG}" ]]; then
  source "${P10K_CONFIG}"
elif [[ -f "${SANDBOX_HOME:-${HOME}}/zsh/.p10k.zsh" ]]; then
  source "${SANDBOX_HOME:-${HOME}}/zsh/.p10k.zsh"
elif [[ -f "${P10K_DEFAULT}" ]]; then
  source "${P10K_DEFAULT}"
fi
unset P10K_DEFAULT

[[ -f "$HOME/.fzf.zsh" ]] && source "$HOME/.fzf.zsh"

bindkey -e
