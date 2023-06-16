svnc() {
  url="${1:s/tree\/master/trunk}"
  svn checkout $url
}

freeport() {
	lsof -ti:$1 | xargs kill -9
}

# Youtube-dl
ytv() {
	youtube-dl --config-location ~/.config/youtube-dl/video $1 ; rm -f yt_done.txt
}

yta() {
	youtube-dl --config-location ~/.config/youtube-dl/audio $1 ; rm -f yt_done.txt
}
ytvp() {
	youtube-dl --config-location ~/.config/youtube-dl/video_playlist $1 ; rm -f yt_done.txt
}

ytap() {
	youtube-dl --config-location ~/.config/youtube-dl/audio_playlist $1 ; rm -f yt_done.txt
}

runprom() {
	host=$1
	script_file="$HOME/Code/scripts/ssh/prometheus.zsh"
	ssh $host 'bash -s' < $script_file
	socks_running=$(ps -auxf | grep "ssh -D 1337 -f -C -q -N" | wc -l)
	[ $socks_running -eq 1 ] && ssh -D 1337 -f -C -q -N $host
}

cpsshconf() {
  src=$HOME/.ssh/config
  dest=$whome/.ssh/config
  [ -e dest ] && rm -rf dest
  cp $src $dest
}

fix_wsl2_interop() {
  for i in $(pstree -np -s $$ | grep -o -E '[0-9]+'); do
    if [[ -e "/run/WSL/${i}_interop" ]]; then
      export WSL_INTEROP=/run/WSL/${i}_interop
    fi
  done
}

get_container_size() {
  img=$(cut -d ":" -f 1 <<< $1)
  tag=$(cut -d ":" -f 2 <<< $1)
  curl -s -H "Authorization: JWT " "https://hub.docker.com/v2/repositories/library/$img/tags/?page_size=100" | jq -r ".results[] | select(.name == \"$tag\") | .images[0].size" | numfmt --to=iec-i
}

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

helm_vmm() {
  set -x
  img=$1
  repo=$vmmo
  helm_src=$vmmo/helm
  helm_dest=$vbun/helmcharts/vmm
  rm -rf $helm_dest
  mkdir -p $(dirname $helm_dest)
  cp -r $helm_src $helm_dest
  perl -i -pe "s~(?<=(image: ))arcprivatecloudtest.azurecr.io/operators/azure-vmmoperator:latest~$img~" $helm_dest/templates/controller-deployment.yaml
  helm upgrade azure-vmmoperator $helm_dest -n azure-vmmoperator --install --create-namespace "${@:2}"
  set +x
}

helm_vmm_re() {
  helm_dest=$vmmo/temp/helm
  helm upgrade azure-vmmoperator $helm_dest -n azure-vmmoperator --install
}

helm_acr_login() {
  # spPassword="<Insert password here>"
  # echo $spPassword | helm registry login arcprivatecloudtest.azurecr.io \
  # --username arcprivatecloudtest \
  # --password-stdin
  az acr login -n arcprivatecloudtest -u "$SPN_APP_ID_TEST_ACR" -p "$SPN_KEY_TEST_ACR"
}

helm_push_vmm() {
  img=$1
  helm_tag=$2
  repo=$vmmo
  helm_src=$vmmo/helm
  helm_dest=$vbun/helmcharts/vmm
  rm -rf $helm_dest
  mkdir -p $(dirname $helm_dest)
  cp -r $helm_src $helm_dest
  perl -i -pe "s~arcprivatecloudtest.azurecr.io/operators/azure-vmmoperator:latest~$img~" $helm_dest/templates/controller-deployment.yaml
  perl -i -pe "s~0.1.0~$helm_tag~" $helm_dest/Chart.yaml
  helm chart save $helm_dest arcprivatecloudtest.azurecr.io/helm/azure-scvmmoperator:$helm_tag
  helm chart push arcprivatecloudtest.azurecr.io/helm/azure-scvmmoperator:$helm_tag
}

prom_create() {
  prom_folder="$HOME/Code/temp/kube-prometheus"
  kubectl create -f $prom_folder/manifests/setup
  until kubectl get servicemonitors --all-namespaces ; do date; sleep 1; echo ""; done
  kubectl create -f $prom_folder/manifests/
}

prom_delete() {
  prom_folder="$HOME/Code/temp/kube-prometheus"
  kubectl delete --ignore-not-found=true -f $prom_folder/manifests/ -f manifests/setup
}

set_kc() {
  name=$1
  perl -i -pe "s~(?<=(\.kube/config.d/))[^'\"]*~$name~" $HOME/.oh-my-zsh/custom/00_env.zsh
  export KUBECONFIG="$HOME/.kube/config.d/$name"
}

# Copy the admin kubeconfig (being a superuser) of a kubernetes cluster 
# into the user's default kubeconfig location.
copy_admin_kc() {
  mkdir ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown -R $USER ~/.kube
}

kgponvmm() {
  kgpon azure-vmmoperator -o jsonpath="{.items[0].metadata.name}"
}

curl_wsman() {
	host=$1
	[ -z $host ] && echo "usage: test_wsman <ip>" && return 1; 
	curl \
		--header "Content-Type: application/soap+xml;charset=UTF-8" \
		--header "WSMANIDENTIFY: unauthenticated" http://$host:5985/wsman \
		--data '&lt;s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsmid="http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd"&gt;&lt;s:Header/&gt;&lt;s:Body&gt;&lt;wsmid:Identify/&gt;&lt;/s:Body&gt;&lt;/s:Envelope&gt;'
}

nc_wsman() {
	host=$1
	[ -z $host ] && echo "usage: test_wsman <ip>" && return 1;
	nc -vz $host 5985;
}

# Create vm-minion-$1 to vm-minion-$2 (padded with 4-zeros).
make_minions() {
  s=$1
  e=$2
  for i in $(seq -f "%04g" $s $e); do yq e "(.metadata.name |= \"vm-minion-$i\") | (.metadata.annotations[\"management.azure.com/operationId\"] |= \"testOp1\")" $vvm | ka -; done
}

# Set the prometheus retention period. (Here's itset to 10 days)
set_prom_retention() {
  kubectl patch -n monitoring prometheus k8s -p '{ "spec": {"retention": "10d" }}' --type merge
}

make_gru() {
  ka $vvs;
  echo "Waiting for vmm server"
  while [ "$(kgn minion vmmserver -o jsonpath='{.items[*].status.provisioningStatus.status}')" != "Succeeded" ]; do date; sleep 10; echo ""; done
  ka $vvc; ka $vvmt
  echo "Waiting for cloud"
  while [ "$(kgn minion cloud -o jsonpath='{.items[*].status.provisioningStatus.status}')" != "Succeeded" ]; do date; sleep 5; echo ""; done
  echo "Waiting for vm template"
  while [ "$(kgn minion vmtemplate -o jsonpath='{.items[*].status.provisioningStatus.status}')" != "Succeeded" ]; do date; sleep 5; echo ""; done
}

del_gru() {
  krmf $vvc; krmf $vvmt; krmf $vvs;
}

cleanup_vmm_crs() {
kubectl delete vmmservers.vmmserver.vmm.microsoft.com -A --all
vm_count=$(kubectl get virtualmachines.vmmserver.vmm.microsoft.com -A -o name | wc -l)
kubectl delete virtualmachines.vmmserver.vmm.microsoft.com -A --all --wait=false
echo "Waiting for deletion timestamp to be set for $vm_count VMs"
while [ "$(kubectl get virtualmachines.vmmserver.vmm.microsoft.com -A -o=jsonpath='{.items[*].metadata.deletionTimestamp}' | wc -w)" != "$vm_count" ]; do date; sleep 1; done
for ns in $(kubectl get namespace -o=jsonpath='{.items[*].metadata.name}'); do
  echo "Removing the finalizers for all VMs in $ns namespace"
  kubectl get virtualmachines.vmmserver.vmm.microsoft.com -n $ns -o name | xargs -I {} kubectl patch -n $ns {} -p '{"metadata":{"finalizers":null}}' --type merge
done;
echo "Waiting for all VM CRs to get deleted"
while [ -n "$(kubectl get virtualmachines.vmmserver.vmm.microsoft.com -A -o name)" ]; do date; sleep 1; done
}

cleanup_vmware_crs() {
kubectl delete vcenters.vsphere.vmware.microsoft.com -A --all
vm_count=$(kubectl get virtualmachines.vsphere.vmware.microsoft.com -A -o name | wc -l)
kubectl delete virtualmachines.vsphere.vmware.microsoft.com -A --all --wait=false
echo "Waiting for deletion timestamp to be set for $vm_count VMs"
while [ "$(kubectl get virtualmachines.vsphere.vmware.microsoft.com -A -o=jsonpath='{.items[*].metadata.deletionTimestamp}' | wc -w)" != "$vm_count" ]; do date; sleep 1; done
for ns in $(kubectl get namespace -o=jsonpath='{.items[*].metadata.name}'); do
  echo "Removing the finalizers for all VMs in $ns namespace"
  kubectl get virtualmachines.vsphere.vmware.microsoft.com -n $ns -o name | xargs -I {} kubectl patch -n $ns {} -p '{"metadata":{"finalizers":null}}' --type merge
done;
echo "Waiting for all VM CRs to get deleted"
while [ -n "$(kubectl get virtualmachines.vsphere.vmware.microsoft.com -A -o name)" ]; do date; sleep 1; done
}

list_acr_manifests() {
  az acr repository show-manifests --name arcprivatecloudtest --repository helm/azure-scvmmoperator | yq e '.[].tags.[]' - | sort -V
}

# Merge zsh history with another history file.
# Bash version: https://gist.github.com/calexandre/63547c8dd0e08bf693d298c503e20aab
merge_zsh_hist() {
  builtin fc -R -I $1
  builtin fc -W "$HOME/.zsh_history_2"
  mv "$HOME/.zsh_history" "$HOME/.zsh_history.bk" && mv "$HOME/.zsh_history_2" "$HOME/.zsh_history"
}

curl_wsman() {
	host=$1
	[ -z $host ] && echo "usage: test_wsman <ip>" && return 1; 
	curl \
		--header "Content-Type: application/soap+xml;charset=UTF-8" \
		--header "WSMANIDENTIFY: unauthenticated" http://$host:5985/wsman \
		--data '&lt;s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsmid="http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd"&gt;&lt;s:Header/&gt;&lt;s:Body&gt;&lt;wsmid:Identify/&gt;&lt;/s:Body&gt;&lt;/s:Envelope&gt;'
}

nc_wsman() {
	host=$1
	[ -z $host ] && echo "usage: test_wsman <ip>" && return 1;
	nc -vz $host 5985;
}

