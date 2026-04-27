// =====================================================================
// bootstrap.bicep — subscription-scope, run ONCE per environment.
//
// Provisions:
//   - Custom role definition (CAE env-storages only) — at subscription
//     scope so it can be assigned cross-RG.
//   - Inside the workload RG (rg-n8n-01-dev): deploy MI (with GitHub
//     OIDC federated creds), runtime MI, Key Vault, and the RBAC needed
//     for both identities to function.
//   - Inside the shared RG (rg-mcp-01-dev-southafricanorth): Reader for
//     the deploy MI, plus the custom role assignment scoped to the CAE.
//
// Run once via:
//   az deployment sub create \
//     -l southafricanorth \
//     -f infra/bootstrap.bicep \
//     -p infra/bootstrap.dev.bicepparam
//
// Idempotent. Re-runs are safe (role assignment GUIDs are deterministic).
// =====================================================================

targetScope = 'subscription'

@description('Azure region for region-bound resources (identities, Key Vault).')
param location string = 'southafricanorth'

@description('Workload resource group (must already exist; create with `az group create`).')
param workloadResourceGroupName string

@description('Shared resource group containing the existing Container Apps managed environment owned by the MCP team. Read-only from this repo.')
param sharedResourceGroupName string

@description('Name of the existing Container Apps managed environment in the shared RG.')
param caeName string

@description('Name of the deploy user-assigned managed identity.')
param deployIdentityName string

@description('Name of the runtime user-assigned managed identity.')
param runtimeIdentityName string

@description('Globally-unique Key Vault name (3-24 chars).')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('GitHub repository in `owner/repo` form.')
param githubRepository string

@description('GitHub environment name used in the federated credential subject (e.g. `dev`).')
param githubEnvironment string = 'dev'

@description('Resource tags to apply to all created resources.')
param tags object = {
  workload: 'first-n8n'
  managedBy: 'bicep'
  env: githubEnvironment
}

// ----- Federated credential subjects -------------------------------------

var federatedSubjects = [
  'repo:${githubRepository}:environment:${githubEnvironment}'
  'repo:${githubRepository}:pull_request'
  'repo:${githubRepository}:ref:refs/heads/main'
]

// ----- Custom role definition (sub scope) --------------------------------
// Narrow role: manage env-storage child resources on a Container Apps
// managed environment. Scoped only to the shared CAE in assignableScopes.

var sharedRgId = subscriptionResourceId('Microsoft.Resources/resourceGroups', sharedResourceGroupName)
var sharedCaeResourceId = '${sharedRgId}/providers/Microsoft.App/managedEnvironments/${caeName}'

resource caeStoragesRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' = {
  name: guid(subscription().id, 'first-n8n-cae-storages-manager', sharedCaeResourceId)
  properties: {
    roleName: 'first-n8n CAE Env-Storages Manager (${githubEnvironment})'
    description: 'Manage Microsoft.App/managedEnvironments/storages child resources on a single shared CAE. Created by first-n8n bootstrap.'
    type: 'CustomRole'
    assignableScopes: [
      sharedCaeResourceId
    ]
    permissions: [
      {
        actions: [
          'Microsoft.App/managedEnvironments/read'
          'Microsoft.App/managedEnvironments/storages/read'
          'Microsoft.App/managedEnvironments/storages/write'
          'Microsoft.App/managedEnvironments/storages/delete'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

// Narrow role: create/read sub-deployments in the shared RG. Required so
// the deploy MI can run the cross-RG nested deployment that wires the
// CAE env-storage definitions. ARM enforces this at the RG scope of the
// nested deployment shell, separately from the action permissions on the
// resources inside it (which the CAE Env-Storages Manager role grants).
resource sharedRgDeploymentsRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' = {
  name: guid(subscription().id, 'first-n8n-shared-rg-deployments-writer', sharedRgId)
  properties: {
    roleName: 'first-n8n Shared-RG Deployments Writer (${githubEnvironment})'
    description: 'Create/read ARM sub-deployments in the shared RG. Created by first-n8n bootstrap.'
    type: 'CustomRole'
    assignableScopes: [
      sharedRgId
    ]
    permissions: [
      {
        actions: [
          'Microsoft.Resources/deployments/read'
          'Microsoft.Resources/deployments/write'
          'Microsoft.Resources/deployments/validate/action'
          'Microsoft.Resources/deployments/whatIf/action'
          'Microsoft.Resources/deployments/operations/read'
          'Microsoft.Resources/deployments/operationStatuses/read'
          'Microsoft.Resources/deployments/cancel/action'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

// ----- Workload-RG nested deployment ------------------------------------

module workload 'modules/workload-bootstrap.bicep' = {
  name: 'first-n8n-workload-bootstrap'
  scope: resourceGroup(workloadResourceGroupName)
  params: {
    location: location
    tags: tags
    deployIdentityName: deployIdentityName
    runtimeIdentityName: runtimeIdentityName
    keyVaultName: keyVaultName
    federatedSubjects: federatedSubjects
  }
}

// ----- Shared-RG nested deployment (cross-RG RBAC) -----------------------

module sharedRgRbac 'modules/rbac-cae.bicep' = {
  name: 'first-n8n-shared-rbac'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    caeName: caeName
    deployPrincipalId: workload.outputs.deployIdentityPrincipalId
    caeStoragesRoleDefinitionId: caeStoragesRole.id
    sharedRgDeploymentsRoleDefinitionId: sharedRgDeploymentsRole.id
  }
}

// ----- Outputs (consumed by the operator runbook) ------------------------

@description('Set as GitHub `dev` environment secret AZURE_CLIENT_ID.')
output deployIdentityClientId string = workload.outputs.deployIdentityClientId

@description('Set as GitHub `dev` environment secret AZURE_TENANT_ID.')
output azureTenantId string = subscription().tenantId

@description('Set as GitHub `dev` environment secret AZURE_SUBSCRIPTION_ID.')
output azureSubscriptionId string = subscription().subscriptionId

@description('Resource ID of the runtime identity (passed to main.bicep).')
output runtimeIdentityResourceId string = workload.outputs.runtimeIdentityResourceId

@description('Resource ID of the Key Vault (passed to main.bicep).')
output keyVaultResourceId string = workload.outputs.keyVaultResourceId

@description('Vault URI for KV secret references in Container Apps.')
output keyVaultUri string = workload.outputs.keyVaultUri

@description('Name of the custom CAE-storages role.')
output caeStoragesRoleName string = caeStoragesRole.name
