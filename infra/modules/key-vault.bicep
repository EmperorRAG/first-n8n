// =====================================================================
// modules/key-vault.bicep
//
// Thin wrapper around the AVM Key Vault module. RBAC mode only;
// soft-delete + purge protection on. Secrets are NOT created here —
// they are seeded by infra/modules/secrets-bootstrap.bicep in Phase 2
// via a Microsoft.Resources/deploymentScripts resource (D6).
// =====================================================================

@description('Globally-unique Key Vault name (3-24 chars).')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Role assignments to create on the vault scope.')
param roleAssignments array = []

module kv 'br/public:avm/res/key-vault/vault:0.11.0' = {
  name: 'kv-${name}'
  params: {
    name: name
    location: location
    tags: tags
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    sku: 'standard'
    publicNetworkAccess: 'Enabled' // Tightened later; out of scope this phase.
    roleAssignments: roleAssignments
  }
}

@description('Resource ID of the Key Vault.')
output id string = kv.outputs.resourceId

@description('Name of the Key Vault.')
output name string = kv.outputs.name

@description('Vault URI (e.g. https://<name>.vault.azure.net/) — used for KV secret references.')
output vaultUri string = kv.outputs.uri
