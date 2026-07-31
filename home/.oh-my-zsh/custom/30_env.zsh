export whome="/mnt/c/Users/$USER"
command -v nvim > /dev/null && alias vim="nvim"
# export EDITOR="code"
export EDITOR="vim"
export HELM_EXPERIMENTAL_OCI=1
export GO111MODULE=on
export KUBECONFIG="$HOME/.kube/config"
export HOMEBREW_NO_AUTO_UPDATE=1
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

alias g++="g++ -std=c++17"

export wspc="$HOME/Code/workspaces"
export vbun="$HOME/Code/bunker"
# Set azarc as the path to your AzureArc directory
# azcli
export azcli="$HOME/Code/ms/azure/cli/"
export AZCLI_SRC_PATH="$azcli/azure-cli"
export azclivmm="$azcli/azure-cli-extensions/src/scvmm/"
export azclivmw="$azcli/azure-cli-extensions/src/connectedvmware/"
export azarc="$HOME/Code/dev.azure.com/msazure/One/AzureArc-VMwareOperator"

# operator
export vmmo="$azarc/src/VMMOperator"
alias vmmo="code $azarc/src/vmm.code-workspace"
export vmwo="$azarc/src/VMwareOperator"
alias vmwo="code $azarc/src/vmware.code-workspace"
export vmwcr="$vbun/vmwcr"

alias kndc="kind create cluster --config=$azarc/src/kind-cluster/kind-config;ka $vvbase;ka $vvinit"
alias kndd="kind delete cluster --name kind"
alias kndre="kndd;kndc"

# Mirrors templates/zshrc-tpl.zsh. A bare `alias kubectl=kubecolor` hangs on
# `exec -it`, `attach`, `port-forward`, `logs -f` and `get -w`: kubecolor buffers
# stdout to colorize it, which breaks raw pty streaming. A function lets those
# subcommands reach the real kubectl, and keeps the typed word as `kubectl` so the
# existing completion applies without an extra compdef.
if (( $+commands[kubecolor] )); then
  kubectl() {
    local sub="" a
    for a in "$@"; do
      [[ $a == -* ]] || { sub=$a; break }
    done
    local -a passthrough=(exec attach port-forward proxy cp edit debug wait)
    if (( ${passthrough[(I)$sub]} )); then command kubectl "$@"; return; fi
    case $sub in
      logs) (( ${@[(I)-f]} || ${@[(I)--follow]} )) && { command kubectl "$@"; return } ;;
      get)  (( ${@[(I)-w]} || ${@[(I)--watch]} || ${@[(I)--watch-only]} )) && { command kubectl "$@"; return } ;;
      run|debug) (( ${@[(I)-i]} || ${@[(I)-t]} || ${@[(I)-it]} || ${@[(I)--stdin]} || ${@[(I)--tty]} )) && { command kubectl "$@"; return } ;;
    esac
    command kubecolor "$@"
  }
  (( $+_comps[kubectl] )) && compdef kubecolor=kubectl 2>/dev/null
fi

# SPACESHIP_KUBECTL_SHOW=true
SPACESHIP_DOCKER_SHOW=false
SPACESHIP_GOLANG_SHOW=false

SPACESHIP_TIME_SHOW=true
SPACESHIP_USER_SHOW=always
SPACESHIP_HOST_SHOW=always
