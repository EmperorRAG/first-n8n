// =====================================================================
// modules/rbac-cae.bicep
//
// Deployed at the SHARED RG scope (rg-mcp-01-dev-southafricanorth).
// Grants the deploy identity the minimum permissions to attach
// environment-storage definitions to the existing Container Apps
// Environment that lives in this RG and is owned by the MCP team.
//
// Two assignments per D10:
//  1. Built-in `Reader` on the shared RG so `existing` references resolve.
//  2. The narrow custom role (defined at subscription scope in
//     bootstrap.bicep) on the CAE resource itself.
// =====================================================================

targetScope = 'resourceGroup'

@description('Name of the existing Container Apps managed environment in this RG.')
param caeName string

@description('Principal (object) ID of the deploy managed identity to grant access to.')
param deployPrincipalId string

@description('Resource ID of the custom role definition (created at subscription scope).')
param caeStoragesRoleDefinitionId string

// Built-in role definition IDs (constants).
var readerRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
)

resource cae 'Microsoft.App/managedEnvironments@2024-10-02-preview' existing = {
  name: caeName
}

resource readerOnRg 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deployPrincipalId, 'Reader')
  properties: {
    roleDefinitionId: readerRoleDefinitionId
    principalId: deployPrincipalId
    principalType: 'ServicePrincipal'
    description: 'first-n8n deploy MI: Reader on shared CAE RG so cross-RG existing refs resolve.'
  }
}

resource caeStoragesOnCae 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cae
  name: guid(cae.id, deployPrincipalId, caeStoragesRoleDefinitionId)
  properties: {
    roleDefinitionId: caeStoragesRoleDefinitionId
    principalId: deployPrincipalId
    principalType: 'ServicePrincipal'
    description: 'first-n8n deploy MI: manage env-storages on shared CAE only.'
  }
}

output readerAssignmentId string = readerOnRg.id
output caeStoragesAssignmentId string = caeStoragesOnCae.id
