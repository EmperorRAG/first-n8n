// =====================================================================
// modules/storage.bicep
//
// Manages the existing storage account (`stn8n01dev2262613750`) and
// declares the file shares used by the n8n workload. The account itself
// is referenced as `existing` (it was created by the legacy bash flow
// in §6 and reused per D2). Shares are managed declaratively — the four
// pre-existing shares are no-op; `n8n-shared` is added (D5).
//
// Also assigns `Storage File Data Privileged Contributor` on the
// account scope to the deploy MI so Phase 3's GHA workflow can use
// `az storage file upload-batch --auth-mode login` without account keys.
// =====================================================================

targetScope = 'resourceGroup'

@description('Name of the existing storage account.')
param storageAccountName string

@description('Principal ID of the deploy managed identity (granted Storage File Data Privileged Contributor).')
param deployPrincipalId string

@description('File shares to ensure exist on the account.')
param shareSpecs object[] = [
  { name: 'n8n-data', quota: 5 }
  { name: 'n8n-demo-data', quota: 1 }
  { name: 'n8n-shared', quota: 1 }
  { name: 'ollama-models', quota: 20 }
  { name: 'qdrant-data', quota: 5 }
]

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' existing = {
  parent: sa
  name: 'default'
}

resource shares 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = [
  for s in shareSpecs: {
    parent: fileServices
    name: s.name
    properties: {
      shareQuota: s.quota
      enabledProtocols: 'SMB'
      accessTier: 'TransactionOptimized'
    }
  }
]

// Storage File Data Privileged Contributor — required for `az storage
// file upload-batch --auth-mode login` against SMB shares.
var storageFileDataPrivilegedContributorId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '69566ab7-960f-475b-8e7c-b3118f30c6bd'
)

resource deployFilePrivilegedContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sa
  name: guid(sa.id, deployPrincipalId, 'StorageFileDataPrivilegedContributor')
  properties: {
    roleDefinitionId: storageFileDataPrivilegedContributorId
    principalId: deployPrincipalId
    principalType: 'ServicePrincipal'
    description: 'first-n8n deploy MI: upload demo-data via OIDC.'
  }
}

@description('Resource ID of the storage account.')
output storageAccountId string = sa.id

@description('Names of the managed file shares.')
output shareNames string[] = [for s in shareSpecs: s.name]
