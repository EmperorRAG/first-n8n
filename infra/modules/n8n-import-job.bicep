// =====================================================================
// modules/n8n-import-job.bicep
//
// Container Apps Job that imports n8n credentials + workflows from the
// `n8n-demo-data` Azure File share into the Postgres-backed n8n DB.
//
// Manual trigger only (`triggerType: Manual`); invocation happens from
// `infra-deploy.yml` (Phase 6) after a workflow/credential change.
//
// Bicep emits ARM JSON directly — none of the `az 2.85` `--command`/
// `--args` CSV-parse or `--yaml` list-merge bugs from the legacy
// `recreate-import-job.sh` / `fix-job-args.sh` flow apply here.
//
// Same secrets/env as the n8n app (KV-ref via runtime MI, D8) so the
// job uses the same encryption key / JWT secret / DB password.
// =====================================================================

targetScope = 'resourceGroup'

@description('Name of the Container App job (e.g. caj-n8n-import-01-dev).')
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

@description('Container image — same n8n image as the app so CLI versions match.')
param image string = 'n8nio/n8n:latest'

@description('Postgres FQDN.')
param postgresFqdn string

@description('Postgres database name.')
param postgresDatabase string = 'n8n'

@description('Postgres admin user.')
param postgresUser string = 'n8nadmin'

@description('Postgres port.')
param postgresPort int = 5432

@description('CPU cores.')
param cpu string = '0.5'

@description('Memory.')
param memory string = '1.0Gi'

@description('Per-execution timeout in seconds.')
param replicaTimeout int = 600

@description('Max retries per replica.')
param replicaRetryLimit int = 1

resource job 'Microsoft.App/jobs@2024-10-02-preview' = {
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
      triggerType: 'Manual'
      replicaTimeout: replicaTimeout
      replicaRetryLimit: replicaRetryLimit
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
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
          name: 'n8n-import'
          image: image
          command: [
            '/bin/sh'
          ]
          args: [
            '-c'
            'n8n import:credentials --separate --input=/demo-data/credentials && n8n import:workflow --separate --input=/demo-data/workflows'
          ]
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
            { name: 'N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS', value: 'false' }
          ]
          volumeMounts: [
            { volumeName: 'n8n-demo-data', mountPath: '/demo-data' }
          ]
        }
      ]
      volumes: [
        {
          name: 'n8n-demo-data'
          storageType: 'AzureFile'
          storageName: 'n8n-demo-data'
        }
      ]
    }
  }
}

@description('Resource ID of the import job.')
output jobId string = job.id

@description('Name of the import job (handy for `az containerapp job start`).')
output jobName string = job.name
