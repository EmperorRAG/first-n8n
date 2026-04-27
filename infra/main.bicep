// =====================================================================
// main.bicep
//
// Workload-RG-scope entry point for the dev environment.
//   - Phase 2: storage shares + Postgres firewall + KV secret seeding.
//   - Phase 4: CAE storage attachments (cross-RG) + n8n / Ollama /
//     Qdrant Container Apps with runtime-MI Key Vault refs.
// =====================================================================

targetScope = 'resourceGroup'

// ----- Parameters --------------------------------------------------------

@description('Azure region.')
param location string = resourceGroup().location

@description('Resource tags applied to module-managed resources.')
param tags object = {
  workload: 'first-n8n'
  env: 'dev'
  managedBy: 'bicep'
}

@description('Name of the existing storage account (D2 = reuse).')
param storageAccountName string

@description('Name of the existing Postgres flexible server (D3 = reuse).')
param postgresServerName string

@description('Name of the n8n database on the Postgres server.')
param databaseName string = 'n8n'

@description('Name of the Key Vault provisioned in Phase 1.')
param keyVaultName string

@description('Name of the deploy managed identity provisioned in Phase 1.')
param deployIdentityName string

@description('Resource ID of the runtime managed identity provisioned in Phase 1.')
param runtimeIdentityResourceId string

@description('Resource group hosting the shared CAE managed environment.')
param sharedResourceGroupName string

@description('Name of the shared CAE managed environment.')
param caeName string

@description('Name of the n8n Container App.')
param n8nAppName string = 'ca-n8n-01-dev'

@description('Name of the Ollama Container App.')
param ollamaAppName string = 'ca-ollama-01-dev'

@description('Name of the Qdrant Container App.')
param qdrantAppName string = 'ca-qdrant-01-dev'

// ----- Existing references ----------------------------------------------

resource deployId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: deployIdentityName
}

resource kv 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

// Cross-RG reference to the shared CAE.
resource cae 'Microsoft.App/managedEnvironments@2024-10-02-preview' existing = {
  name: caeName
  scope: resourceGroup(sharedResourceGroupName)
}

// ----- Modules -----------------------------------------------------------

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    storageAccountName: storageAccountName
    deployPrincipalId: deployId.properties.principalId
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    postgresServerName: postgresServerName
    databaseName: databaseName
  }
}

module secretsBootstrap 'modules/secrets-bootstrap.bicep' = {
  name: 'secrets-bootstrap'
  params: {
    location: location
    tags: tags
    keyVaultName: keyVaultName
    deployIdentityResourceId: deployId.id
  }
}

// ----- Phase 4 modules ---------------------------------------------------

// CAE env-storage attachments live in the shared RG (cross-RG sub-deploy).
// Depends on `storage` so the n8n-shared share exists first.
module caeStorage 'modules/cae-storage.bicep' = {
  name: 'cae-storage'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    caeName: caeName
    storageAccountName: storageAccountName
    storageAccountResourceGroupName: resourceGroup().name
    storageAccountSubscriptionId: subscription().subscriptionId
  }
  dependsOn: [
    storage
  ]
}

module ollamaApp 'modules/ollama-app.bicep' = {
  name: 'ollama-app'
  params: {
    name: ollamaAppName
    location: location
    tags: tags
    environmentId: cae.id
  }
  dependsOn: [
    caeStorage
  ]
}

module qdrantApp 'modules/qdrant-app.bicep' = {
  name: 'qdrant-app'
  params: {
    name: qdrantAppName
    location: location
    tags: tags
    environmentId: cae.id
  }
  dependsOn: [
    caeStorage
  ]
}

module n8nApp 'modules/n8n-app.bicep' = {
  name: 'n8n-app'
  params: {
    name: n8nAppName
    location: location
    tags: tags
    environmentId: cae.id
    runtimeIdentityResourceId: runtimeIdentityResourceId
    keyVaultUri: kv.properties.vaultUri
    postgresFqdn: postgres.outputs.fqdn
    postgresDatabase: postgres.outputs.databaseName
    postgresUser: postgres.outputs.adminLogin
    ollamaHost: '${ollamaAppName}:11434'
  }
  dependsOn: [
    caeStorage
    secretsBootstrap
    ollamaApp
  ]
}

// ----- Outputs -----------------------------------------------------------

output storageAccountId string = storage.outputs.storageAccountId
output shareNames string[] = storage.outputs.shareNames
output postgresServerId string = postgres.outputs.serverId
output postgresFqdn string = postgres.outputs.fqdn
output postgresAdminLogin string = postgres.outputs.adminLogin
output postgresDatabaseName string = postgres.outputs.databaseName
output secretsBootstrapState string = secretsBootstrap.outputs.provisioningState

output caeStorageNames string[] = caeStorage.outputs.storageNames
output n8nFqdn string = n8nApp.outputs.fqdn
output ollamaInternalFqdn string = ollamaApp.outputs.fqdn
output qdrantInternalFqdn string = qdrantApp.outputs.fqdn
