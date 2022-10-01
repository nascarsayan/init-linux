#!/bin/bash
# This script onboards your VMM Sever to the private preview of Arc enabled Virtual Machine Manager
# This script is provided as is and without warranties.
# version: 1.2
#
# *Usage
# After downloading the script into a path '/path/to/script.sh', run
# source /path/to/script.sh [STEP-NUMBER] # , for example,
# source ./arc-scvmm-onboard.sh

#* Leave these variables as they are (even the blank ones)
export ENV_DUMP_FILE="$HOME/.vmmrc"
export HELMVALUESPATH="$HOME/cc-helm-values.yaml"
# shellcheck source=/dev/null
[ -n "$ENV_DUMP_FILE" ] && [ -f "$ENV_DUMP_FILE" ] && source "$ENV_DUMP_FILE"
curr_time="$(date '+%m%d')"
[ -z "$START_DATE" ] && export START_DATE="$curr_time"
export HELM_VERSION="v3.6.3"
export HELM_URL="https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3"
export AZCLI_URL="https://aka.ms/InstallAzureCLIDeb"
export ARCSCVMM_CLI_URL="https://arcscvmm.blob.core.windows.net/extensions/scvmm-0.1.3-py2.py3-none-any.whl"
export ARCVMWARE_CLI_URL="https://arcvmwaredl.blob.core.windows.net/arc-appliance/connectedvmware-0.1.2-py2.py3-none-any.whl"
export VMM_EXT="microsoft.scvmm"
export CLSEXT_NAME="azure-vmmoperator"
export CLUSTER_EXT_V=""
export HELM_EXPERIMENTAL_OCI=1
export CL_SPID="bc313c14-388c-4e7d-a58e-70017303ee3b"
export CL_OID
export K8BRIDGE_SPID="319f651f-7ddb-4fc6-9857-7aef9250bd05"
export K8BRIDGE_OID
export CLS_EXT_ID
export CC_ID
export CL_ID

#* Update these variables according to your environment.

#*location where user wants to deploy connected cluster. (eastus|westeurope|eastus2euap|westus)
export AZ_LOCATION=""

is_canary="false"
is_df="false"
echo "$AZ_LOCATION" | grep -iFq "euap" && is_canary="true"
echo "$AZ_LOCATION" | grep -iFq "westus" && is_df="true"

#*common prefix
PREFIX_STUB="arcvmm-$START_DATE"
[[ $is_canary == "true" ]] && PREFIX_STUB="can-$PREFIX_STUB"

#*name of the connected cluster to be created.
export CLUSTER_NAME="${PREFIX_STUB}-cc"

#*http://*name of the app id to be used to create connected cluster. NOTE: Should be a valid DNS label.
export SP_NAME="http://$CLUSTER_NAME"

#*subscription name or id where user wants to deploy connected cluster.
export AZ_SUBSCRIPTION=""

#*resource group name or id where user wants to deploy connected cluster.
export AZ_RG="$PREFIX_STUB"

#*name of the custom location resource user wants to create. NOTE: Should be a valid DNS label.
export CUSTOMLOCATION_NAME="${PREFIX_STUB}-cl"

#* name for the vmmserver resource to be created on the cluster.
export VMMSERVER_NAME="${PREFIX_STUB}-vmmserver"

#* ip of the vmm server which user wants to connect to.
export VMMSERVER_FQDN=""

#* OPTIONAL. port to be used to connect to vmm server. Default is 8100
export VMMSERVER_PORT=""

#* username of vmmserver.
export VMMSERVER_USERNAME=''

#* password of vmmserver.
export VMMSERVER_PASSWORD=''

export_envvars()
{
  start_or_end=$1
  envvars=(
    "PREFIX_STUB"
    "CL_SPID"
    "CL_OID"
    "K8BRIDGE_SPID"
    "K8BRIDGE_OID"
    "CLS_EXT_ID"
    "CC_ID"
    "CL_ID"
    "HELMVALUESPATH"
    "START_DATE"

    "ENV_DUMP_FILE"
    "HELM_VERSION"
    "HELM_URL"
    "AZCLI_URL"
    "ARCSCVMM_CLI_URL"
    "VMM_EXT"
    "CLSEXT_NAME"
    "CLUSTER_EXT_V"
    "VMMSERVER_PORT"
    "HELM_EXPERIMENTAL_OCI"

    "CLUSTER_NAME"
    "SP_NAME"
    "AZ_SUBSCRIPTION"
    "AZ_RG"
    "AZ_LOCATION"
    "CUSTOMLOCATION_NAME"
    "VMMSERVER_NAME"
    "VMMSERVER_FQDN"
    "VMMSERVER_USERNAME"
    "VMMSERVER_PASSWORD"
    "CLOUD_NAME"
    "VMTEMP_NAME"
    "VN_NAME"
  )
  result=""
  for envvar in "${envvars[@]}"; do
    key="$envvar"
    eval "value=\"\${$key}\""
    value=$(sed 's/\\/\\\\/g' <<<"$value")
    result+="export $key='${value}'"$'\n'
  done
  result+="export VMM_PREV_END_STEP='$step'"$'\n'
  echo "$result" >"$ENV_DUMP_FILE"
  echo -e "# $(date) at STEP $step $start_or_end:\n$result\n\n" >>"$ENV_DUMP_FILE.history"
}

install_ok()
{
  export_envvars "END"
  echo "STEP $step END."
  input=""
  while [ "$input" != "y" ] && [ "$input" != "Y" ] && [ "$input" != "n" ] && [ "$input" != "N" ]; do
    echo "If the installation was successful and you wish to proceed please type [y] or if you encountered any error please type [n], followed by [ENTER]: "
    read -r -t 5 input
    [ -z "$input" ] && input="y"
  done
  if [ "$input" = "n" ] || [ "$input" = "N" ]; then
    return 1
  else
    return 0
  fi
}

proceedInstallation()
{
  ((step++))

  if [ -n "$startstep" ] && [ "$step" -lt "$startstep" ]; then
    echo "STEP $step SKIP."
    return 1
  fi

  input=""
  while [ "$input" != "y" ] && [ "$input" != "Y" ] && [ "$input" != "n" ] && [ "$input" != "N" ]; do
    echo -e "STEP $step START.\nDo you want to proceed with this step? Please type [y] or [n], followed by [ENTER]: "
    read -r -t 5 input
    [ -z "$input" ] && input="y"
  done
  if [ "$input" = "n" ] || [ "$input" = "N" ]; then
    return 1
  else
    export_envvars "START"
    return 0
  fi
}

commands_exist()
{
  for i in "$@"; do
    if ! command -v "$i" &>/dev/null; then
      return 1
    fi
  done
  return 0
}

is_az_login_required()
{
  token_expiry_time_str=$(az account get-access-token --query "expiresOn" --output tsv 2>/dev/null)
  [[ $token_expiry_time_str ]] || return 0
  token_expiry_time=$(date --date="$token_expiry_time_str" +%s)
  deadline=$(date --date='+10 min' +%s)
  [[ $token_expiry_time -ge $deadline ]] || return 0
  return 1
}

az_login()
{
  is_az_login_required || return 0
  az login --use-device-code -o table || return 1
}

install_zsh()
{
  sudo apt update
  sudo apt install zsh git curl tmux -y

  if ! commands_exist "zsh" "git" "curl"; then
    echo "zsh, git, curl installation failed. Please try again."
    return
  fi

  [ -d "$HOME/.oh-my-zsh" ] && rm -rf "$HOME/.oh-my-zsh"
  [ -d "$HOME/.fzf" ] && rm -rf "$HOME/.fzf"
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

  if [ ! -f "$HOME/.zshrc" ]; then
    echo "oh-my-zsh could not be cloned. Please try again."
    return
  fi
  # Auto update oh-my-zsh
  perl -i -pe "s~# (?=(zstyle ':omz:update' mode auto))~~" "$HOME"/.zshrc
  sed -i 's/# DISABLE_UPDATE_PROMPT/DISABLE_UPDATE_PROMPT/' "$HOME"/.zshrc
  echo "Installing zsh plugins"
  ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
  echo "Installing spaceship prompt"
  git clone https://github.com/denysdovhan/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
  ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
  sed -i 's/robbyrussell/spaceship/' "$HOME"/.zshrc
  echo "Installing zsh autosuggestions"
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM"/plugins/zsh-autosuggestions
  echo "Installing zsh syntax-highlighting"
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM"/plugins/zsh-syntax-highlighting
  echo "Installing kubectl aliases"
  wget https://raw.githubusercontent.com/ahmetb/kubectl-alias/master/.kubectl_aliases -O "$ZSH_CUSTOM"/51_kubectl.zsh

  echo "Installing fzf"
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install --all

  echo "Configuring tmux"
  git clone https://github.com/gpakosz/.tmux.git ~/.tmux
  ln -s -f ~/.tmux/.tmux.conf ~/.tmux.conf
  cp ~/.tmux/.tmux.conf.local ~/.tmux.conf.local

  echo "Adding az competions"
  bash -c "cat > $HOME/.oh-my-zsh/custom/utils.zsh << EOF
# azure cli
[ -f /usr/local/etc/bash_completion.d/az ] && source /usr/local/etc/bash_completion.d/az
[ -f /etc/bash_completion.d/azure-cli ] && source /etc/bash_completion.d/azure-cli

command -v kubecolor >/dev/null 2>&1 && alias kubectl=kubecolor
compdef kubecolor=kubectl

export PATH=\"$HOME/.local/bin:$PATH\"
# arc scvmm env variables
[ -f $ENV_DUMP_FILE ] && source $ENV_DUMP_FILE
EOF"

  bash -c "cat >> $HOME/.bashrc << EOF
export PATH=\"$HOME/.local/bin:$PATH\"
# arc scvmm env variables
[ -f $ENV_DUMP_FILE ] && source $ENV_DUMP_FILE
EOF"

  echo "Adding plugins to zsh"
  sed -i -e 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions sudo kubectl)/g' "$HOME"/.zshrc
  chsh -s "$(which zsh)"

  echo "**** zsh was installed. To enter zsh from bash, type 'zsh' in the bash prompt. ****"
}

prepare_cluster_node()
{
  # https://www.itzgeek.com/how-tos/linux/ubuntu-how-tos/install-containerd-on-ubuntu-22-04.html
  echo "Installing Curl.."
  sudo apt install -y curl apt-transport-https ca-certificates gnupg lsb-release
  echo "Installing Docker and containerd..."
  sudo mkdir -p /etc/apt/keyrings

  echo "Adding Docker's GPG Keys"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  echo "Adding Kubernetes' GPG Keys"
  sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
  echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io
  [[ $(tail -n 1 /etc/containerd/config.toml) == "SystemdCgroup = true" ]] || cat <<EOF | sudo tee -a /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
SystemdCgroup = true
EOF

  cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF

  sudo sed -i 's/^disabled_plugins \=/\#disabled_plugins \=/g' /etc/containerd/config.toml
  sudo systemctl enable containerd
  sudo systemctl restart containerd

  echo "Installing Kubernetes components..."
  sudo apt update -q && sudo apt install -qy kubectl kubelet kubeadm
  sudo apt-mark hold kubelet kubeadm
  sudo mkdir -p /var/lib/kubelet/
  echo "--container-runtime=remote --container-runtime-endpoint=/run/containerd/containerd.sock" | sudo tee /var/lib/kubelet/kubeadm-flags.env > /dev/null
  sudo systemctl restart kubelet

  echo "Installing optional package: kubecolor"
  curl -fsSL https://github.com/dty1er/kubecolor/releases/download/v0.0.20/kubecolor_0.0.20_Linux_x86_64.tar.gz | tar -xz -C /tmp
  sudo mv /tmp/kubecolor /usr/local/bin
}

bootstrap()
{
  sudo swapoff -a
  sleep 20

  sudo kubeadm init --pod-network-cidr=192.168.0.0/16

  mkdir -p "$HOME"/.kube
  sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
  sudo chown "$(id -u):$(id -g)" "$HOME"/.kube/config

  kubectl taint nodes --all node-role.kubernetes.io/master-
  kubectl taint nodes --all node-role.kubernetes.io/control-plane-

  kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
  kubectl create -f https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml

  echo -e "Sleeping for 15s.\n\nkubectl get pods -A\n"
  sleep 15

  kubectl get pods --all-namespaces
}

install_helm()
{
  echo "Downloading and installing Helm"
  curl -sSL $HELM_URL | bash -s -- -v $HELM_VERSION
  # shellcheck disable=SC2154
  helm completion zsh > "${fpath[1]}/_helm"
  echo "Installed Helm version $HELM_VERSION"
}

install_azcli()
{
  az version 2>/dev/null || (curl -sL https://aka.ms/InstallAzureCLIDeb | sudo -E bash)
  echo "Installed Az CLI"

  if [ "$(az cloud show -n Dogfood --query name -o tsv)" != "Dogfood" ]; then
    az cloud register --debug --name Dogfood --endpoint-management "https://management-preview.core.windows-int.net/" --endpoint-gallery "https://df.gallery.azure-test.net/" --endpoint-active-directory "https://login.windows-ppe.net/" --endpoint-active-directory-resource-id "https://management.core.windows.net/" --endpoint-active-directory-graph-resource-id "https://graph.ppe.windows.net/" --endpoint-resource-manager "https://api-dogfood.resources.windows-int.net/"
  fi

  if [ "$is_df" = "true" ]; then
    az cloud set --name Dogfood
    echo "az cloud has been set to Dogfood endpoint"
  fi
}

install_azcli_extensions()
{
  echo "Downloading and adding extensions to az cli"

  echo "Adding connectedk8s extension to az cli"
  az extension add --yes --name connectedk8s
  echo "Added connectedk8s extension to az cli"

  echo "Adding k8sconfiguration extension to az cli"
  az extension add --yes --name k8sconfiguration
  echo "Added k8sconfiguration extension to az cli"

  echo "Adding k8s-extension extension to az cli"
  az extension add --yes --name k8s-extension
  echo "Added k8s-extension extension to az cli"

  echo "Adding customlocation extension to az cli"
  az extension add --yes --name customlocation
  echo "Added customlocation extension to az cli"

  echo "Adding arcscvmm extension to az cli"
  az extension add --yes --source $ARCSCVMM_CLI_URL
  echo "Added arcscvmm extension to az cli"

  echo "Adding arcvmware extension to az cli"
  az extension add --yes --source $ARCVMWARE_CLI_URL
  echo "Added arcvmware extension to az cli"

  echo "Added required extensions to az cli"
}

connect_cluster2Azure()
{
  az_login
  az account set -s "$AZ_SUBSCRIPTION"

  group=$(az group show -n "$AZ_RG" 2>/dev/null)
  if [ -z "$group" ]; then
    echo "Resource Group '$AZ_RG' does not exist. Trying to create the resource group"
    az group create -n "$AZ_RG" -l "$AZ_LOCATION"
  fi

  echo "Registering providers for the subscription"
  az provider register --namespace Microsoft.kubernetes --wait
  az provider register --namespace Microsoft.KubernetesConfiguration --wait
  az provider register --namespace Microsoft.SCVMM --wait

  subscriptionId=$(az account show --query id -o tsv)

  if [ "$is_df" = "true" ]; then
    cat << EOF > cc-helm-values.yaml
global:
  azureEnvironment: AZUREDOGFOOD
systemDefaultValues:
  optIn:
    ManagedIdentityAuth: false
  clusterconnect-agent:
    connect_dp_endpoint_override: https://dp.stage.k8sconnect.azure.com:8082/
    notification_dp_endpoint_override: https://df.guestnotificationservice.azure.com/
    enabled: true
  azureArcAgents:
    config_dp_endpoint_override: https://partner.dp.kubernetesconfiguration-test.azure.com
EOF
    mv cc-helm-values.yaml "$HELMVALUESPATH"
  fi

  echo "Installing k8s agents and connecting cluster"

  CL_OID=$(az ad sp show --id $CL_SPID --query objectId -o tsv)
  az connectedk8s connect --debug -l "$AZ_LOCATION" -g "$AZ_RG" -n "$CLUSTER_NAME" --custom-locations-oid "$CL_OID"

  CC_ID=$(az connectedk8s show -n "$CLUSTER_NAME" -g "$AZ_RG" --query id -o tsv)
  az resource wait --debug --ids "$CC_ID" --custom "properties.provisioningState=='Succeeded'" --interval 30 --timeout 600
}

assign_roles()
{
  CL_OID=$(az ad sp show --id $CL_SPID --query objectId -o tsv)
  K8BRIDGE_OID=$(az ad sp show --id $K8BRIDGE_SPID --query objectId -o tsv)

  kubectl create clusterrolebinding CL-admin --clusterrole=cluster-admin --user "$CL_OID"
  kubectl create clusterrolebinding K8-admin --clusterrole=cluster-admin --user "$K8BRIDGE_OID"

  CC_ID=$(az connectedk8s show -n "$CLUSTER_NAME" -g "$AZ_RG" --query id -o tsv)
  echo "Connected Cluster Id is: $CC_ID"

  # Assign "Azure Arc Enabled Kubernetes Cluster User Role"
  az role assignment create --assignee "$K8BRIDGE_OID" --role "Azure Arc Enabled Kubernetes Cluster User Role" --scope "$CC_ID"

  subscriptionId=$(az account show --query id -o tsv)
  # Assign "Reader" role
  az role assignment create --assignee "$K8BRIDGE_OID" --role "Reader" --scope "/subscriptions/$subscriptionId"
}

create_cluster_extension()
{
  args=()
  [[ $is_canary == "true" ]] && args+=(--release-train dev)
  [ -n "$CLUSTER_EXT_V" ] && args+=(--version "$CLUSTER_EXT_V" --auto-upgrade false)

  az k8s-extension create --debug --cluster-type connectedClusters --cluster-name "$CLUSTER_NAME" --resource-group "$AZ_RG" --name $CLSEXT_NAME --extension-type $VMM_EXT --scope cluster --config "Microsoft.CustomLocation.ServiceAccount"=$CLSEXT_NAME "${args[@]}"

  az k8s-extension show --resource-group "$AZ_RG" --name $CLSEXT_NAME --cluster-type connectedClusters --cluster-name "$CLUSTER_NAME"
}

connect_customLocation()
{
  az_login
  az account set -s "$AZ_SUBSCRIPTION"

  CLS_EXT_ID=$(az k8s-extension show --cluster-type connectedClusters --cluster-name "$CLUSTER_NAME" --resource-group "$AZ_RG" --name $CLSEXT_NAME --query id -o tsv)

  CC_ID=$(az connectedk8s show -n "$CLUSTER_NAME" -g "$AZ_RG" --query id -o tsv)

  az customlocation create --resource-group "$AZ_RG" --name "$CUSTOMLOCATION_NAME" --cluster-extension-ids "$CLS_EXT_ID" -l "$AZ_LOCATION" --namespace "$CUSTOMLOCATION_NAME" --host-resource-id "$CC_ID" --debug

  CL_ID=$(az customlocation show --resource-group "$AZ_RG" --name "$CUSTOMLOCATION_NAME" --query id -o tsv)
  echo "Custom Location ARM Id: : $CL_ID"
}

connect_vmmserver()
{
  CL_ID=$(az customlocation show --resource-group "$AZ_RG" --name "$CUSTOMLOCATION_NAME" --query id -o tsv)

  args=()
  [ -n "$VMMSERVER_PORT" ] && args+=(--port "$VMMSERVER_PORT")

  az scvmm vmmserver connect -n "$VMMSERVER_NAME" -g "$AZ_RG" -l "$AZ_LOCATION" --fqdn "$VMMSERVER_FQDN" "${args[@]}" --custom-location "$CL_ID" --username "$VMMSERVER_USERNAME" --password "$VMMSERVER_PASSWORD" --debug

  echo "VMM Server connected."
}

## Main

(
  step=0
  startstep="$1"
  [ -n "$startstep" ] && echo "Resuming the script from STEP $startstep"

  echo "Installing zsh and shell utils."
  if proceedInstallation; then
    install_zsh
    echo "STEP $step END."
    exit
  fi
  echo "We have successfully installed zsh and other shell utilities."

  echo "Installing Docker, kubeadm, kubelet and kubectl.."
  if proceedInstallation; then
    prepare_cluster_node
    install_ok || exit 33
  fi
  echo "We have successfully installed and configured Docker, kubeadm, kubelet and kubectl on this VM."

  echo "Now we need to bootstrap the master node."
  if proceedInstallation; then
    bootstrap
    install_ok || exit 33
  fi
  echo "We now have a single-host Kubernetes cluster spun up using kubeadm and equipped with Calico."

  echo "Installing Helm.."
  if proceedInstallation; then
    install_helm
    install_ok || exit 33
  fi

  echo "Installing azcli and azcli extensions.."
  if proceedInstallation; then
    install_azcli
    install_azcli_extensions
    install_ok || exit 33
  fi

  echo "We have successfully installed helm, azcli, and azcli extensions."

  [ -z "$PREFIX_STUB" ] && echo "Please set common prefix." && exit 33
  [ -z "$AZ_LOCATION" ] && echo "Please set az location." && exit 33
  [ -z "$AZ_SUBSCRIPTION" ] && echo "Please set subscription." && exit 33

  echo "Setting up connected cluster.."
  if proceedInstallation; then
    connect_cluster2Azure
    install_ok || exit 33
  fi
  echo "Your kubernetes cluster is onboarded."

  echo "Assigning roles and cluster permissions.."
  if proceedInstallation; then
    assign_roles
    install_ok || exit 33
  fi

  echo "Installing cluster extension.."
  if proceedInstallation; then
    create_cluster_extension
    install_ok || exit 33
  fi

  echo "Now we do PUT custom location."
  if proceedInstallation; then
    connect_customLocation
    install_ok || exit 33
  fi

  echo "Now we do PUT vmmserver."
  if proceedInstallation; then
    connect_vmmserver
    install_ok || exit 33
  fi

  echo "-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0"
  echo "           Your onboarding is now complete!     "
  echo "-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0-0"

) |& tee -a arc-scvmm-output.log
