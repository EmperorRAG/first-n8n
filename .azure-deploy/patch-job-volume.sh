#!/usr/bin/env bash
# Adds an Azure Files volume mount to an existing container app JOB, idempotently.
# Usage: patch-job-volume.sh <job-name> <env-storage-name> <volume-name> <mount-path>
set -euo pipefail
JOB="$1"; ENVST="$2"; VOL="$3"; MOUNT="$4"
cd "$(dirname "$0")"
. ./env.sh
export MSYS_NO_PATHCONV=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

YAML_POSIX="$WORK/job.yaml"
YAML_WIN="$(cygpath -w "$YAML_POSIX")"

az containerapp job show -g "$RG" -n "$JOB" -o yaml > "$YAML_POSIX"

python - "$YAML_POSIX" "$ENVST" "$VOL" "$MOUNT" <<'PY'
import sys, yaml
path, envst, vol, mount = sys.argv[1:5]
with open(path) as f:
    doc = yaml.safe_load(f)
template = doc['properties']['template']
template.setdefault('volumes', [])
existing = next((v for v in template['volumes'] if v.get('name') == vol), None)
new_vol = {'name': vol, 'storageType': 'AzureFile', 'storageName': envst}
if existing:
    existing.update(new_vol)
else:
    template['volumes'].append(new_vol)
for c in template.get('containers', []):
    c.setdefault('volumeMounts', [])
    if not any(vm.get('volumeName') == vol for vm in c['volumeMounts']):
        c['volumeMounts'].append({'volumeName': vol, 'mountPath': mount})
with open(path, 'w') as f:
    yaml.safe_dump(doc, f, sort_keys=False)
PY

az containerapp job update -g "$RG" -n "$JOB" --yaml "$YAML_WIN" -o none
echo "[patch-job] $JOB: mounted $ENVST as $VOL at $MOUNT"
