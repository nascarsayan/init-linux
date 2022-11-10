export whome="/mnt/c/Users/$USER"
alias vim="nvim"
alias cat="bat"
# export EDITOR="code"
export EDITOR="nvim"
export CP_IO_PATH="$HOME/Code/cp/io/"
export HELM_EXPERIMENTAL_OCI=1
export GO111MODULE=on
export KUBECONFIG="$HOME/.kube/config"
export LC_ALL=en_IN.UTF-8
export LANG=en_IN.UTF-8

alias g++="g++ -std=c++17"

export wspc="$HOME/Code/workspaces"
export vbun="$HOME/Code/ms/bunker/vmmBunker"
# Set azarc as the path to your AzureArc directory
# azcli
export azcli="$HOME/Code/ms/azure/cli/"
export AZCLI_SRC_PATH="$azcli/azure-cli"
export azclivmm="$azcli/azure-cli-extensions/src/scvmm/"
export azclivmw="$azcli/azure-cli-extensions/src/connectedvmware/"
export azarc="$HOME/Code/ms/one/AzureArc-VMwareOperator"

# operator
export vmmo="$azarc/src/VMMOperator"
alias vmmo="code $wspc/vmm.code-workspace"
export vmwo="$azarc/src/VMwareOperator"
alias vmwo="code $wspc/vmware.code-workspace"
export azarcref="$HOME/Code/ms/one/Ref-AzureArc-VMwareOperator"
export vmmoref="$azarcref/src/VMMOperator"
export vmworef="$azarcref/src/VMwareOperator"
export vvbase="$vmmo/helm/templates/crds.yaml"
export vvkplug="$vmmo/pkg/kubectl-plugin"
export vvsamp="$vbun/VMMOperator-CRD-Samples/src/VMMOperator/config/samples"
export vvs="$vvsamp/vmmserver_v1alpha1_vmmserver.yaml"
export vvc="$vvsamp/vmmserver_v1alpha1_cloud.yaml"
export vvmt="$vvsamp/vmmserver_v1alpha1_virtualmachinetemplate.yaml"
export vvm="$vvsamp/vmmserver_v1alpha1_virtualmachine.yaml"
export vvn="$vvsamp/vmmserver_v1alpha1_virtualnetwork.yaml"
export vvart="$vvsamp/vmmserver_v1alpha1_virtualmachinestartaction.yaml"
export vvaop="$vvsamp/vmmserver_v1alpha1_virtualmachinestopaction.yaml"
export vvair="$vvsamp/vmmserver_v1alpha1_virtualmachinerepairaction.yaml"
export vvarert="$vvsamp/vmmserver_v1alpha1_virtualmachinerestartaction.yaml"
export vvinit="$vvsamp/init.yaml"
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
