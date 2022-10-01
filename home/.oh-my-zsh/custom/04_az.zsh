ARCSCVMM_BLOB_KEY=""

# upload any temporary file to storage account arcscvmm.
function upload() {
	[ -z "$1" ] && echo "Usage: upload <file>" && return 1
	[ -z "$ARCSCVMM_BLOB_KEY" ] && echo "\
	ARCSCVMM_BLOB_KEY is not set. Set it to the value of:\n\n\
	az storage account keys list --subscription 'ARC-Testing' -g snaskar-rg -n arcscvmm --query '[0].value' -o tsv\
	" && return 1
	fpth=$1
	fname=$(basename $fpth)
	az storage blob upload --account-key $ARCSCVMM_BLOB_KEY --account-name arcscvmm -c temp -f $fpth -n $fname
	echo "https://arcscvmm.blob.core.windows.net/temp/$fname"
}

is_az_login_required()
{
  token_expiry_time_str=$(az account get-access-token --query "expiresOn" --output tsv 2>/dev/null)
  [[ $token_expiry_time_str ]] || return 0
  token_expiry_time=$(date --date="$token_expiry_time_str" +%s)
  deadline=$(date --date='+10 min' +%s)
  [[ $token_expiry_time -ge $deadline ]] || return 0
  echo "cached az login should work"
  return 1
}

az_login()
{
  is_az_login_required || return 0
  az login --use-device-code -o table || return 1
}

