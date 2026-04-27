#!/usr/bin/env bash
# Rewrites the import job's command/args to a properly structured list
# (workaround for the --command/--args parsing bug in az 2.85).
set -euo pipefail
cd "$(dirname "$0")"
. ./env.sh
export MSYS_NO_PATHCONV=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
YAML="$WORK/job.yaml"
YAMLW="$(cygpath -w "$YAML")"

az containerapp job show -g "$RG" -n "$JOB_IMPORT" -o yaml > "$YAML"

python - "$YAML" <<'PY'
import sys, yaml
p = sys.argv[1]
with open(p) as f:
    d = yaml.safe_load(f)
c = d["properties"]["template"]["containers"][0]
c["command"] = ["/bin/sh"]
c["args"] = [
    "-c",
    "n8n import:credentials --separate --input=/demo-data/credentials && "
    "n8n import:workflow --separate --input=/demo-data/workflows",
]
with open(p, "w") as f:
    yaml.safe_dump(d, f, sort_keys=False)
PY

az containerapp job update -g "$RG" -n "$JOB_IMPORT" --yaml "$YAMLW" -o none
echo "[fix] command/args rewritten:"
az containerapp job show -g "$RG" -n "$JOB_IMPORT" --query "properties.template.containers[0].{cmd:command, args:args}" -o json
