// =====================================================================
// modules/identity.bicep
//
// Wraps the AVM user-assigned managed identity module and (optionally)
// attaches GitHub OIDC federated credentials. Used twice from
// bootstrap.bicep: once for the deploy identity (with federated creds),
// once for the runtime identity (no federated creds).
// =====================================================================

@description('Name of the user-assigned managed identity.')
@minLength(3)
@maxLength(128)
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('GitHub OIDC federated credential subjects to attach. Empty array means no federated creds (used for the runtime identity).')
param federatedSubjects string[] = []

// Federated credentials child names must be unique per identity and <=64
// chars. Derive a stable short name from the subject so re-runs don't churn.
// Computed name length is always 19 ('gh-' + 16); BCP335 false positive.
var fedCreds = [
  for s in federatedSubjects: {
    #disable-next-line BCP335
    name: 'gh-${take(uniqueString(s), 16)}'
    audiences: ['api://AzureADTokenExchange']
    issuer: 'https://token.actions.githubusercontent.com'
    subject: s
  }
]

module mi 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'mi-${name}'
  params: {
    name: name
    location: location
    tags: tags
    federatedIdentityCredentials: fedCreds
  }
}

@description('Resource ID of the managed identity.')
output id string = mi.outputs.resourceId

@description('Name of the managed identity.')
output name string = mi.outputs.name

@description('Client (application) ID — used for AZURE_CLIENT_ID GitHub secret.')
output clientId string = mi.outputs.clientId

@description('Service-principal object ID — used for role assignments.')
output principalId string = mi.outputs.principalId
