// =====================================================================
// main.bicep
//
// Workload-RG-scope entry point for the dev environment. Phase 2
// scope: stateful layer (storage shares + Postgres firewall + KV
// secret seeding). Container Apps + jobs are added in Phases 4–5.
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

// ----- Existing references ----------------------------------------------

resource deployId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: deployIdentityName
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

// ----- Outputs -----------------------------------------------------------

output storageAccountId string = storage.outputs.storageAccountId
output shareNames string[] = storage.outputs.shareNames
output postgresServerId string = postgres.outputs.serverId
output postgresFqdn string = postgres.outputs.fqdn
output postgresAdminLogin string = postgres.outputs.adminLogin
output postgresDatabaseName string = postgres.outputs.databaseName
output secretsBootstrapState string = secretsBootstrap.outputs.provisioningState
