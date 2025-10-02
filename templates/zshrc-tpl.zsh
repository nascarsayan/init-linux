if [[ -n "${SAYANN_BASE:-}" ]]; then
  export XDG_CACHE_HOME="${SAYANN_BASE}/zsh/cache"
  export XDG_DATA_HOME="${SAYANN_BASE}/zinit"
  export XDG_CONFIG_HOME="${SAYANN_BASE}/zsh/config"
  : "${ZINIT_HOME:=${SAYANN_BASE}/zinit/zinit.git}"
  export TMUX_HOME="${SAYANN_BASE}/tmux"
  export FZF_HOME="${SAYANN_BASE}/fzf"
fi

if [[ -r "${SAYANN_BASE}/zsh/cache/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${SAYANN_BASE}/zsh/cache/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source "${ZINIT_HOME}/zinit.zsh"

autoload -Uz is-at-least
if is-at-least 5.1 "$ZSH_VERSION"; then
  export POWERLEVEL10K_DISABLE_CONFIGURATION_WIZARD=1
  zinit ice depth=1
  zinit load romkatv/powerlevel10k
else
  print -P "%F{yellow}[sayann]%f Skipping powerlevel10k (needs zsh>=5.1, current $ZSH_VERSION)."
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

HISTFILE="${SAYANN_BASE}/zsh/.zsh_history"
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
  [ -f "${FZF_HOME}/completion.zsh" ] && source "${FZF_HOME}/completion.zsh"
  [ -f "${FZF_HOME}/key-bindings.zsh" ] && source "${FZF_HOME}/key-bindings.zsh"
fi

BUN_INSTALL="$HOME/.bun"
PATH="$BUN_INSTALL/bin:$PATH"
GITTOP="/home/sayann/Code/monolith"
PYTHONPATH="/home/sayann/Code/monolith/src/cluster_deployment/deployment/"
export BUN_INSTALL PATH GITTOP PYTHONPATH

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

export TMUX_CONFIG="${TMUX_HOME}/.tmux.conf"
if command -v tmux >/dev/null 2>&1 && [ -f "$TMUX_CONFIG" ]; then
  export TMUX_CONF="$TMUX_CONFIG"
  alias tmux="tmux -f $TMUX_CONFIG"
fi

zinit ice blockf
zinit light Aloxaf/fzf-tab

zstyle ':completion:*' menu select
zstyle ':completion:*:descriptions' format '%d'
zstyle ':fzf-tab:*' switch-group ',' '.'

autoload -Uz compinit
compinit

autoload -U +X bashcompinit && bashcompinit

[[ ! -f "${SAYANN_BASE}/zsh/.p10k.zsh" ]] || source "${SAYANN_BASE}/zsh/.p10k.zsh"
[ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"

bindkey -e
