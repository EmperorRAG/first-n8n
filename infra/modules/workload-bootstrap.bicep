// =====================================================================
// modules/workload-bootstrap.bicep
//
// Deployed at the WORKLOAD RG scope (rg-n8n-01-dev). Creates the deploy
// identity (with GitHub OIDC federated creds), the runtime identity,
// the Key Vault, and all RBAC needed for them to function:
//   - Deploy MI    : Contributor on this RG, Key Vault Secrets Officer on KV
//   - Runtime MI   : Key Vault Secrets User on KV
// =====================================================================

targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Name of the deploy managed identity.')
param deployIdentityName string

@description('Name of the runtime managed identity.')
param runtimeIdentityName string

@description('Globally-unique Key Vault name.')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('GitHub OIDC federated credential subjects to attach to the deploy identity.')
param federatedSubjects string[]

// ----- Identities --------------------------------------------------------

module deployId '../modules/identity.bicep' = {
  name: 'id-deploy'
  params: {
    name: deployIdentityName
    location: location
    tags: tags
    federatedSubjects: federatedSubjects
  }
}

module runtimeId '../modules/identity.bicep' = {
  name: 'id-runtime'
  params: {
    name: runtimeIdentityName
    location: location
    tags: tags
    // No federated credentials on the runtime identity — it's used by
    // the Container Apps to resolve KV references at runtime.
    federatedSubjects: []
  }
}

// ----- Key Vault (with role assignments) ---------------------------------

// Built-in role definition IDs.
var roleDefIds = {
  contributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  rbacAdministrator: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'f58310d9-a9f6-439a-9e8d-f62e7b41a168' // Role Based Access Control Administrator
  )
  kvSecretsOfficer: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  )
  kvSecretsUser: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '4633458b-17de-408a-b874-0445c86b69e6'
  )
}

module kv '../modules/key-vault.bicep' = {
  name: 'kv'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    roleAssignments: [
      {
        roleDefinitionIdOrName: roleDefIds.kvSecretsOfficer
        principalId: deployId.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: roleDefIds.kvSecretsUser
        principalId: runtimeId.outputs.principalId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

// ----- Workload-RG-scope role assignment ---------------------------------

resource deployContributorOnRg 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Use the identity NAME (a parameter, known at start of deployment)
  // rather than the principalId (a cross-module output, only known after
  // deploymentStart) — required by BCP120.
  name: guid(resourceGroup().id, deployIdentityName, 'Contributor')
  properties: {
    roleDefinitionId: roleDefIds.contributor
    principalId: deployId.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'first-n8n deploy MI: Contributor on workload RG.'
  }
}

// Contributor explicitly excludes Microsoft.Authorization/*/Write, but
// main.bicep needs to create role assignments inside this RG (e.g.
// Storage File Data Privileged Contributor for the deploy MI on the
// storage account, used for keyless `az storage file upload-batch`).
// Grant RBAC Administrator (assignment-only, cannot mutate anything
// else) on the RG so those nested assignments can be authored.
resource deployRbacAdminOnRg 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deployIdentityName, 'RBACAdministrator')
  properties: {
    roleDefinitionId: roleDefIds.rbacAdministrator
    principalId: deployId.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'first-n8n deploy MI: assign roles on resources in workload RG.'
  }
}

// ----- Outputs -----------------------------------------------------------

output deployIdentityResourceId string = deployId.outputs.id
output deployIdentityPrincipalId string = deployId.outputs.principalId
output deployIdentityClientId string = deployId.outputs.clientId
output runtimeIdentityResourceId string = runtimeId.outputs.id
output runtimeIdentityPrincipalId string = runtimeId.outputs.principalId
output runtimeIdentityClientId string = runtimeId.outputs.clientId
output keyVaultResourceId string = kv.outputs.id
output keyVaultName string = kv.outputs.name
output keyVaultUri string = kv.outputs.vaultUri
