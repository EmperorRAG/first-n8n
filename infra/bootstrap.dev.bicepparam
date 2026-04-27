using './bootstrap.bicep'

param location = 'southafricanorth'
param workloadResourceGroupName = 'rg-n8n-01-dev'
param sharedResourceGroupName = 'rg-mcp-01-dev-southafricanorth'
param caeName = 'cae-mcp-01-dev-southafricanorth'

// CAF prefix `id` for managed identities (Q12).
param deployIdentityName = 'id-n8n-deploy-dev'
param runtimeIdentityName = 'id-n8n-runtime-dev'

// Globally-unique KV name (3-24 chars). Pin a constant value so re-runs
// don't churn; if the name is taken, change here once.
param keyVaultName = 'kv-n8n-01-dev-26070'

param githubRepository = 'EmperorRAG/first-n8n'
param githubEnvironment = 'dev'
