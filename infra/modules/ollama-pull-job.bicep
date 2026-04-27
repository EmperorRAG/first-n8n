// =====================================================================
// modules/ollama-pull-job.bicep
//
// Container Apps Job that triggers an Ollama model pull via the
// `/api/pull` REST endpoint of the in-env `ca-ollama-01-dev` app.
//
// Manual trigger only; invocation happens once after fresh provision
// (Phase 6 `infra-deploy.yml`) or whenever the model needs to be
// re-pulled. Persisted on the `ollama-models` Azure File share via the
// Ollama app's volume — this job does NOT mount the share itself; it
// only kicks the running Ollama server to download into its own volume.
//
// `--fail-with-body` returns non-zero on HTTP >= 400 so the job's
// execution status reflects pull errors. Streaming JSON response is
// piped to stdout for log visibility.
// =====================================================================

targetScope = 'resourceGroup'

@description('Name of the Container App job (e.g. caj-ollama-pull-01-dev).')
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the cross-RG CAE managed environment.')
param environmentId string

@description('Container image. `curlimages/curl` is ~5 MiB and ships only curl.')
param image string = 'curlimages/curl:latest'

@description('Internal Ollama host:port reachable from this job (CAE-internal).')
param ollamaHost string = 'ca-ollama-01-dev:11434'

@description('Model name to pull (Ollama registry tag).')
param modelName string = 'llama3.2'

@description('CPU cores. Tiny — the job only POSTs and waits.')
param cpu string = '0.25'

@description('Memory.')
param memory string = '0.5Gi'

@description('Per-execution timeout in seconds. Cold pull of llama3.2 (~2 GB) is slow on CPU profiles.')
param replicaTimeout int = 1800

@description('Max retries per replica.')
param replicaRetryLimit int = 1

resource job 'Microsoft.App/jobs@2024-10-02-preview' = {
  name: name
  location: location
  tags: tags
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
    }
    template: {
      containers: [
        {
          name: 'ollama-pull'
          image: image
          command: [
            '/bin/sh'
          ]
          args: [
            '-c'
            'curl --fail-with-body -sS -X POST http://${ollamaHost}/api/pull -H "Content-Type: application/json" -d "{\\"name\\":\\"${modelName}\\",\\"stream\\":false}"'
          ]
          resources: {
            cpu: json(cpu)
            memory: memory
          }
        }
      ]
    }
  }
}

@description('Resource ID of the pull job.')
output jobId string = job.id

@description('Name of the pull job (handy for `az containerapp job start`).')
output jobName string = job.name
