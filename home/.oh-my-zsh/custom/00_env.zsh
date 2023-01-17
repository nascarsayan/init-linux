export whome="/mnt/c/Users/$USER"
command -v nvim > /dev/null && alias vim="nvim"
command -v batcat > /dev/null && alias cat="batcat"
# export EDITOR="code"
export EDITOR="vim"
export HELM_EXPERIMENTAL_OCI=1
export GO111MODULE=on
export KUBECONFIG="$HOME/.kube/config"
export HOMEBREW_NO_AUTO_UPDATE=1

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

command -v kubecolor >/dev/null 2>&1 && alias kubectl="kubecolor"
command -v kubectl >/dev/null && compdef kubecolor=kubectl

# SPACESHIP_KUBECTL_SHOW=true
SPACESHIP_DOCKER_SHOW=false
SPACESHIP_GOLANG_SHOW=false

batchvmcreate()
{
	count=$1
	for i in {001..$count}; do
		template=$(cat $vvm | sed "s/sn-load-test/sn-load-test-$i/g")
		echo "$template" | kubectl apply -f -
	done
}

batchvmdel()
{
	count=$1
	for i in {001..$count}; do
		template=$(cat $vvm | sed "s/sn-load-test/sn-load-test-$i/g")
		echo "$template" | kubectl delete --recursive -f -
	done
}

fmt()
{
	file=$vmmo/pkg/gopowershell/shell.go
	mat="fmt.Println"
	pre="// "
	if grep -Fq "$pre$mat" $file; then
		sed -i "s|$pre$mat|$mat|" $file
	else
		sed -i "s|$mat|$pre$mat|" $file
	fi
}

SPACESHIP_TIME_SHOW=true
SPACESHIP_USER_SHOW=always
SPACESHIP_HOST_SHOW=always
