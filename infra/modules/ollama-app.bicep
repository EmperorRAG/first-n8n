// =====================================================================
// modules/ollama-app.bicep
//
// Ollama Container App (CPU profile). Internal ingress on :11434 for
// in-env consumers (the n8n app). Model cache persisted on the
// `ollama-models` Azure File share. Model pulls are handled by the
// Phase 5 `ollama-pull-job` — this app only serves.
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

@description('Container image.')
param image string = 'ollama/ollama:latest'

@description('CPU cores. Live config: 4.0.')
param cpu string = '4.0'

@description('Memory. Live config: 8.0Gi.')
param memory string = '8.0Gi'

@description('How long Ollama keeps models loaded in memory after the last request.')
param keepAlive string = '30m'

@description('Min replicas. Keep at 1 in dev: CAE internal ingress does not reliably activate scale-to-zero from in-env L4 connects (see ollama-pull-job notes), and Ollama is not HTTP-scaleable.')
param minReplicas int = 1

@description('Max replicas.')
param maxReplicas int = 1

resource app 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 11434
        transport: 'http'
        allowInsecure: true
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'ollama'
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            { name: 'OLLAMA_KEEP_ALIVE', value: keepAlive }
            { name: 'OLLAMA_HOST', value: '0.0.0.0:11434' }
          ]
          volumeMounts: [
            { volumeName: 'ollama-models', mountPath: '/root/.ollama' }
          ]
        }
      ]
      volumes: [
        {
          name: 'ollama-models'
          storageType: 'AzureFile'
          storageName: 'ollama-models'
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

@description('Resource ID of the Ollama Container App.')
output appId string = app.id

@description('Internal FQDN of the Ollama app (CAE-internal).')
output fqdn string = app.properties.configuration.ingress.fqdn
