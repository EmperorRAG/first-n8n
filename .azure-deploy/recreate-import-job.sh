#!/usr/bin/env bash
# Recreates the n8n import job from scratch with a clean YAML spec
# (workaround: az 2.85's --command/--args mis-parses comma-separated args,
# and `job update --yaml` merges rather than replaces lists).
set -euo pipefail
cd "$(dirname "$0")"
. ./env.sh
export MSYS_NO_PATHCONV=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
YAML="$WORK/job.yaml"
YAMLW="$(cygpath -w "$YAML")"

cat > "$YAML" <<EOF
location: South Africa North
properties:
  environmentId: ${ACA_ENV_ID}
  configuration:
    triggerType: Manual
    replicaTimeout: 600
    replicaRetryLimit: 1
    manualTriggerConfig:
      parallelism: 1
      replicaCompletionCount: 1
    secrets:
      - name: db-password
        value: ${PG_PASSWORD}
      - name: n8n-encryption-key
        value: ${N8N_ENCRYPTION_KEY}
      - name: n8n-jwt-secret
        value: ${N8N_JWT_SECRET}
  template:
    containers:
      - name: ${JOB_IMPORT}
        image: n8nio/n8n:latest
        resources:
          cpu: 0.5
          memory: 1.0Gi
        command:
          - /bin/sh
        args:
          - "-c"
          - "n8n import:credentials --separate --input=/demo-data/credentials && n8n import:workflow --separate --input=/demo-data/workflows"
        env:
          - { name: DB_TYPE, value: postgresdb }
          - { name: DB_POSTGRESDB_HOST, value: ${PG_HOST} }
          - { name: DB_POSTGRESDB_PORT, value: "5432" }
          - { name: DB_POSTGRESDB_DATABASE, value: ${PG_DB} }
          - { name: DB_POSTGRESDB_USER, value: ${PG_ADMIN} }
          - { name: DB_POSTGRESDB_PASSWORD, secretRef: db-password }
          - { name: DB_POSTGRESDB_SSL_ENABLED, value: "true" }
          - { name: DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED, value: "true" }
          - { name: N8N_ENCRYPTION_KEY, secretRef: n8n-encryption-key }
          - { name: N8N_USER_MANAGEMENT_JWT_SECRET, secretRef: n8n-jwt-secret }
        volumeMounts:
          - { volumeName: demo-data, mountPath: /demo-data }
    volumes:
      - { name: demo-data, storageType: AzureFile, storageName: ${ENVST_DEMO} }
EOF

echo "[recreate] deleting old job"
az containerapp job delete -g "$RG" -n "$JOB_IMPORT" --yes -o none 2>/dev/null || true
echo "[recreate] creating from YAML"
az containerapp job create -g "$RG" -n "$JOB_IMPORT" --yaml "$YAMLW" -o none
echo "[recreate] command/args now:"
az containerapp job show -g "$RG" -n "$JOB_IMPORT" --query "properties.template.containers[0].{cmd:command, args:args}" -o json
