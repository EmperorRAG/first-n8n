// =====================================================================
// modules/secrets-bootstrap.bicep
//
// Seeds the three required Key Vault secrets (D6 = deploymentScripts):
//   - pg-admin-password
//   - n8n-encryption-key
//   - n8n-jwt-secret
//
// Behaviour: GENERATE ONLY IF MISSING. The script is idempotent; it
// never overwrites an existing secret. This lets the operator pre-seed
// `pg-admin-password` with the live PG admin value (preserves data) or
// rely on Phase 7 cutover to reset PG admin to the generated value.
//
// `forceUpdateTag` is a constant ('v1') so the script runs once at
// initial deploy (D6 mitigation). Bumping it forces a re-run.
// =====================================================================

targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Key Vault to seed.')
param keyVaultName string

@description('Resource ID of the deploy managed identity (must already have Secrets Officer on the vault).')
param deployIdentityResourceId string

@description('Bump to force a re-run of the seeding script.')
param forceUpdateTag string = 'v3'

resource seed 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'seed-kv-secrets-${uniqueString(resourceGroup().id, keyVaultName)}'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deployIdentityResourceId}': {}
    }
  }
  properties: {
    azCliVersion: '2.62.0'
    forceUpdateTag: forceUpdateTag
    timeout: 'PT10M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    environmentVariables: [
      { name: 'KV_NAME', value: keyVaultName }
    ]
    scriptContent: '''#!/bin/bash
set -euo pipefail
# 64-char alphanumeric secrets via python3 (always available in the
# Azure CLI deployment-script container; openssl is not, and a piped
# /dev/urandom + tr trips SIGPIPE under `set -o pipefail`).
gen() {
  python3 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(64)))"
}
for name in pg-admin-password n8n-encryption-key n8n-jwt-secret; do
  exists=$(az keyvault secret list --vault-name "$KV_NAME" --query "[?name=='$name'].name | [0]" -o tsv 2>/dev/null || true)
  if [ -z "$exists" ]; then
    val=$(gen)
    az keyvault secret set --vault-name "$KV_NAME" --name "$name" --value "$val" -o none
    echo "Seeded $name"
  else
    echo "Skipped $name (exists)"
  fi
done
'''
  }
}

@description('Provisioning state of the seed script (Succeeded if all secrets present).')
output provisioningState string = seed.properties.provisioningState
