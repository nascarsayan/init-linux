#!/bin/bash
set -ex
az login --service-principal -u $SP_USER -p $SP_PASS --tenant $MS_TENANT
first=600
last=1000
curr=$first
span=5
sleep_time=10

is_az_login_required () {
  token_expiry_time_str=$(az account get-access-token --query "expiresOn" --output tsv 2>/dev/null)
  [[ -n $token_expiry_time_str ]] || return 0
  token_expiry_time=$(date --date="$token_expiry_time_str" +%s)
  deadline=$(date --date='+10 min' +%s)
  [[ $token_expiry_time -ge $deadline ]] || return 0
  echo "cached az login should work"
  return 1
}

az_login () {
  is_az_login_required || return 0
  az login --service-principal -u $SP_USER -p $SP_PASS --tenant $MS_TENANT || return 1
}

while :
do
if [ $(($curr + $span - 1)) -gt $last ]
then
  curr=$first
fi
  az_login
  curr_end=$(($curr + $span - 1))
  next=$(($curr_end + 1))
  sed -n "$curr,${curr_end}p;${next}q" "$HOME/appl/vms.txt" | xargs -I {} az scvmm vm create -l eastus2euap --custom-location arcvmm-scale-cl -g aadk8test -v arcvmm-scale-vmmserver -i {} -n {}-scale --query "id" -o tsv
  sleep $sleep_time
done

# sed -n "41,100p;101q" vms.txt | xargs -I {} az scvmm vm create -l eastus2euap --custom-location arcvmm-scale-cl -g aadk8test -v arcvmm-scale-vmmserver -i {} -n {}-scale --no-wait --debug
