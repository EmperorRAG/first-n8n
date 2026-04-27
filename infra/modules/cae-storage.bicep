// =====================================================================
// modules/cae-storage.bicep
//
// Attaches Azure File shares to the shared Container Apps managed
// environment (CAE) as `Microsoft.App/managedEnvironments/storages`.
//
// This module is invoked from main.bicep with
//   `scope: resourceGroup(sharedResourceGroupName)`
// because the CAE lives in the shared RG (`rg-mcp-01-dev-southafricanorth`)
// while the storage account lives in the workload RG (`rg-n8n-01-dev`).
//
// The deploy MI must hold the bootstrap-provisioned custom role
// (`managedEnvironments/storages/*`) on the CAE plus `Reader` on the
// shared RG (D10) for this to succeed.
//
// Account key is fetched via cross-RG `listKeys` against the storage
// account resource ID. The key never leaves the ARM template runtime;
// it is stored as a CAE secret and consumed by the apps via volumes.
// =====================================================================

targetScope = 'resourceGroup'

@description('Name of the existing CAE managed environment in this RG.')
param caeName string

@description('Storage account name (lives in the workload RG).')
param storageAccountName string

@description('Resource group of the storage account (the workload RG).')
param storageAccountResourceGroupName string

@description('Subscription ID of the storage account (defaults to current).')
param storageAccountSubscriptionId string = subscription().subscriptionId

@description('File shares to attach. Each item: { name, accessMode } where accessMode is `ReadWrite` or `ReadOnly`.')
param shareSpecs object[] = [
  { name: 'n8n-data', accessMode: 'ReadWrite' }
  { name: 'n8n-demo-data', accessMode: 'ReadWrite' }
  { name: 'n8n-shared', accessMode: 'ReadWrite' }
  { name: 'ollama-models', accessMode: 'ReadWrite' }
  { name: 'qdrant-data', accessMode: 'ReadWrite' }
]

resource cae 'Microsoft.App/managedEnvironments@2024-10-02-preview' existing = {
  name: caeName
}

var storageAccountId = resourceId(
  storageAccountSubscriptionId,
  storageAccountResourceGroupName,
  'Microsoft.Storage/storageAccounts',
  storageAccountName
)

resource envStorages 'Microsoft.App/managedEnvironments/storages@2024-10-02-preview' = [
  for s in shareSpecs: {
    parent: cae
    name: s.name
    properties: {
      azureFile: {
        accountName: storageAccountName
        accountKey: listKeys(storageAccountId, '2023-05-01').keys[0].value
        shareName: s.name
        accessMode: s.accessMode
      }
    }
  }
]

@description('Resource ID of the CAE (cross-RG, returned for downstream wiring).')
output caeResourceId string = cae.id

@description('Names of the env-storage attachments (matches share names by convention).')
output storageNames string[] = [for s in shareSpecs: s.name]
