// =====================================================================
// modules/qdrant-app.bicep
//
// Qdrant Container App. Internal ingress on :6333. Vector data
// persisted on the `qdrant-data` Azure File share.
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
param image string = 'qdrant/qdrant:latest'

@description('CPU cores. Live config: 0.5.')
param cpu string = '0.5'

@description('Memory. Live config: 1.0Gi.')
param memory string = '1.0Gi'

@description('Min replicas.')
param minReplicas int = 0

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
        targetPort: 6333
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
          name: 'qdrant'
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          volumeMounts: [
            { volumeName: 'qdrant-data', mountPath: '/qdrant/storage' }
          ]
        }
      ]
      volumes: [
        {
          name: 'qdrant-data'
          storageType: 'AzureFile'
          storageName: 'qdrant-data'
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

@description('Resource ID of the Qdrant Container App.')
output appId string = app.id

@description('Internal FQDN of the Qdrant app (CAE-internal).')
output fqdn string = app.properties.configuration.ingress.fqdn
