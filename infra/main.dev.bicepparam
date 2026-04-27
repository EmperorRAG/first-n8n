// =====================================================================
// main.dev.bicepparam — dev environment values for main.bicep.
// =====================================================================

using './main.bicep'

param location = 'southafricanorth'

param tags = {
  workload: 'first-n8n'
  env: 'dev'
  managedBy: 'bicep'
}

// Existing resources (D2/D3 = reuse).
param storageAccountName = 'stn8n01dev2262613750'
param postgresServerName = 'psql-n8n-01-dev-26070'
param databaseName = 'n8n'

// Provisioned in Phase 1 (bootstrap).
param keyVaultName = 'kv-n8n-01-dev-26070'
param deployIdentityName = 'id-n8n-deploy-dev'
param runtimeIdentityResourceId = '/subscriptions/e056e3bc-66a6-4bcc-a192-a903bfcb9f5d/resourcegroups/rg-n8n-01-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-n8n-runtime-dev'

// Cross-RG references to the shared CAE.
param sharedResourceGroupName = 'rg-mcp-01-dev-southafricanorth'
param caeName = 'cae-mcp-01-dev-southafricanorth'
