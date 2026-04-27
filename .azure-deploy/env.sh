# Auto-generated deployment variables for n8n → ACA POC.
# DO NOT COMMIT. Contains generated secrets.

# --- Identifiers ---
export SUB_ID="e056e3bc-66a6-4bcc-a192-a903bfcb9f5d"
export ACA_ENV_NAME="cae-mcp-01-dev-southafricanorth"
export ACA_ENV_RG="rg-mcp-01-dev-southafricanorth"
export TENANT_ID="efd4c4ff-cad1-4214-a064-5ebe38bf247b"
export MCP_URL="https://ca-mcp-01-dev-southafricanorth.greengrass-f377fe8c.southafricanorth.azurecontainerapps.io/mcp"

export LOCATION="southafricanorth"
export RG="rg-n8n-01-dev"

# --- Storage / shares ---
# STORAGE_ACCT must be globally unique, lowercase, <=24 chars, alphanumeric.
# Filled in by 01-vars.sh on first run if empty.
: "${STORAGE_ACCT:=}"
export SHARE_N8N="n8n-data"
export SHARE_QDRANT="qdrant-data"
export SHARE_OLLAMA="ollama-models"
export SHARE_DEMO="n8n-demo-data"

export ENVST_N8N="n8n-data"
export ENVST_QDRANT="qdrant-data"
export ENVST_OLLAMA="ollama-models"
export ENVST_DEMO="n8n-demo-data"

# --- Container apps + job ---
export APP_N8N="ca-n8n-01-dev"
export APP_OLLAMA="ca-ollama-01-dev"
export APP_QDRANT="ca-qdrant-01-dev"
export JOB_IMPORT="caj-n8n-import-01-dev"

export OLLAMA_INTERNAL_URL="http://${APP_OLLAMA}:11434"
export QDRANT_INTERNAL_URL="http://${APP_QDRANT}:6333"

# --- Postgres ---
# PG_SERVER is generated once and persisted to .azure-deploy/secrets.sh.
export PG_ADMIN="n8nadmin"
export PG_DB="n8n"
export PG_SKU="Standard_B1ms"
export PG_TIER="Burstable"
export PG_VERSION="16"

# --- Pull persisted secrets / generated values if present ---
SECRETS_FILE="$(dirname "${BASH_SOURCE[0]}")/secrets.sh"
if [ -f "$SECRETS_FILE" ]; then
  # shellcheck disable=SC1090
  . "$SECRETS_FILE"
fi

# Derived
if [ -n "${PG_SERVER:-}" ]; then
  export PG_HOST="${PG_SERVER}.postgres.database.azure.com"
fi
