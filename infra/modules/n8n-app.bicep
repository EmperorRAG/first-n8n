// =====================================================================
// modules/n8n-app.bicep
//
// The n8n Container App. Reuses the existing app `ca-n8n-01-dev` by
// name (Bicep upserts in place; revision rollback is the safety net).
//
// Secrets are sourced from Key Vault at runtime (D8) via the runtime
// managed identity. The deploy MI is *not* added — only the runtime MI
// has `Key Vault Secrets User` on the KV (Phase 1).
//
// Volumes:
//   - n8n-data   → /home/node/.n8n   (workflow + sqlite cache + data)
//   - n8n-shared → /data/shared      (matches local Compose)
// =====================================================================

targetScope = 'resourceGroup'

@description('Name of the Container App.')
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the cross-RG CAE managed environment.')
param environmentId string

@description('Resource ID of the runtime user-assigned MI (for KV secret refs).')
param runtimeIdentityResourceId string

@description('Key Vault URI (e.g. https://kv-n8n-01-dev-26070.vault.azure.net/).')
param keyVaultUri string

@description('Container image (e.g. n8nio/n8n:latest).')
param image string = 'n8nio/n8n:latest'

@description('Postgres FQDN.')
param postgresFqdn string

@description('Postgres database name.')
param postgresDatabase string = 'n8n'

@description('Postgres admin user.')
param postgresUser string = 'n8nadmin'

@description('Postgres port.')
param postgresPort int = 5432

@description('Internal Ollama host:port reachable from this app.')
param ollamaHost string = 'ca-ollama-01-dev'

@description('CPU cores.')
param cpu string = '1.0'

@description('Memory.')
param memory string = '2.0Gi'

@description('Min replicas.')
param minReplicas int = 0

@description('Max replicas.')
param maxReplicas int = 1

resource app 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentityResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 5678
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'n8n-encryption-key'
          keyVaultUrl: '${keyVaultUri}secrets/n8n-encryption-key'
          identity: runtimeIdentityResourceId
        }
        {
          name: 'n8n-jwt-secret'
          keyVaultUrl: '${keyVaultUri}secrets/n8n-jwt-secret'
          identity: runtimeIdentityResourceId
        }
        {
          name: 'pg-admin-password'
          keyVaultUrl: '${keyVaultUri}secrets/pg-admin-password'
          identity: runtimeIdentityResourceId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'n8n'
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            { name: 'DB_TYPE', value: 'postgresdb' }
            { name: 'DB_POSTGRESDB_HOST', value: postgresFqdn }
            { name: 'DB_POSTGRESDB_PORT', value: string(postgresPort) }
            { name: 'DB_POSTGRESDB_DATABASE', value: postgresDatabase }
            { name: 'DB_POSTGRESDB_USER', value: postgresUser }
            { name: 'DB_POSTGRESDB_PASSWORD', secretRef: 'pg-admin-password' }
            { name: 'DB_POSTGRESDB_SSL_ENABLED', value: 'true' }
            { name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'true' }
            { name: 'N8N_DIAGNOSTICS_ENABLED', value: 'false' }
            { name: 'N8N_PERSONALIZATION_ENABLED', value: 'false' }
            { name: 'N8N_ENCRYPTION_KEY', secretRef: 'n8n-encryption-key' }
            { name: 'N8N_USER_MANAGEMENT_JWT_SECRET', secretRef: 'n8n-jwt-secret' }
            { name: 'N8N_DEFAULT_BINARY_DATA_MODE', value: 'filesystem' }
            { name: 'N8N_PROXY_HOPS', value: '1' }
            { name: 'N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS', value: 'false' }
            { name: 'OLLAMA_HOST', value: ollamaHost }
            {
              name: 'WEBHOOK_URL'
              value: 'https://${name}.${reference(environmentId, '2024-10-02-preview').defaultDomain}/'
            }
          ]
          volumeMounts: [
            { volumeName: 'n8n-data', mountPath: '/home/node/.n8n' }
            { volumeName: 'n8n-shared', mountPath: '/data/shared' }
          ]
        }
      ]
      volumes: [
        {
          name: 'n8n-data'
          storageType: 'AzureFile'
          storageName: 'n8n-data'
        }
        {
          name: 'n8n-shared'
          storageType: 'AzureFile'
          storageName: 'n8n-shared'
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

@description('Resource ID of the n8n Container App.')
output appId string = app.id

@description('Public FQDN of the n8n app.')
output fqdn string = app.properties.configuration.ingress.fqdn
