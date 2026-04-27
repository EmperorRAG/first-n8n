# Bootstrap runbook — `infra/bootstrap.bicep`

> **Run once per environment by an operator with `Owner` on the subscription.** The bootstrap creates a custom role definition (requires `Microsoft.Authorization/roleDefinitions/write` at subscription scope) plus all the identities, Key Vault, and RBAC the GitHub Actions workflows depend on.

## What it provisions

| Scope | Resource |
|---|---|
| Subscription | Custom role: `first-n8n CAE Env-Storages Manager (dev)` — actions limited to `Microsoft.App/managedEnvironments/storages/*` + read; assignable only on the shared CAE. |
| `rg-n8n-01-dev` | User-assigned MI `id-n8n-deploy-dev` (with 3 GitHub OIDC federated credentials) |
| `rg-n8n-01-dev` | User-assigned MI `id-n8n-runtime-dev` (no federated creds; used by the Container Apps for runtime KV refs) |
| `rg-n8n-01-dev` | Key Vault `kv-n8n-01-dev-26070` (RBAC mode, soft-delete + purge protection on) |
| `rg-n8n-01-dev` | Role assignments: deploy MI = `Contributor`, deploy MI = `Key Vault Secrets Officer`, runtime MI = `Key Vault Secrets User` |
| `rg-mcp-01-dev-southafricanorth` | Role assignments on the shared CAE: deploy MI = `Reader` (RG scope) + custom role (CAE scope) |

## Prerequisites

- Azure CLI 2.60+ (`az --version`)
- Logged in as an account with **Owner** on subscription `e056e3bc-66a6-4bcc-a192-a903bfcb9f5d`
- The workload RG `rg-n8n-01-dev` already exists (created by the legacy flow this session). If starting clean: `az group create -n rg-n8n-01-dev -l southafricanorth`.
- The shared CAE `cae-mcp-01-dev-southafricanorth` exists and you have at least `Reader` on it.

## Run

```bash
az login
az account set --subscription e056e3bc-66a6-4bcc-a192-a903bfcb9f5d

# Validate first
az deployment sub validate \
  --location southafricanorth \
  --template-file infra/bootstrap.bicep \
  --parameters infra/bootstrap.dev.bicepparam

# What-if (preview)
az deployment sub what-if \
  --location southafricanorth \
  --template-file infra/bootstrap.bicep \
  --parameters infra/bootstrap.dev.bicepparam

# Deploy
az deployment sub create \
  --name first-n8n-bootstrap-dev \
  --location southafricanorth \
  --template-file infra/bootstrap.bicep \
  --parameters infra/bootstrap.dev.bicepparam
```

## Capture outputs and set GitHub secrets

```bash
# Capture outputs
OUT=$(az deployment sub show --name first-n8n-bootstrap-dev --query properties.outputs -o json)
CLIENT_ID=$(echo "$OUT" | jq -r '.deployIdentityClientId.value')
TENANT_ID=$(echo "$OUT" | jq -r '.azureTenantId.value')
SUB_ID=$(echo "$OUT"   | jq -r '.azureSubscriptionId.value')

echo "AZURE_CLIENT_ID=$CLIENT_ID"
echo "AZURE_TENANT_ID=$TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$SUB_ID"
```

Then create the GitHub `dev` environment and seed the secrets (`gh` CLI):

```bash
# Create the environment if it doesn't exist
gh api -X PUT "repos/EmperorRAG/first-n8n/environments/dev"

# Set environment secrets (Q13: no required reviewers — auto-deploy on push to main)
gh secret set AZURE_CLIENT_ID       --env dev --body "$CLIENT_ID"
gh secret set AZURE_TENANT_ID       --env dev --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --env dev --body "$SUB_ID"
```

## Validation

```bash
# 3 federated credentials on the deploy identity
az identity federated-credential list \
  -g rg-n8n-01-dev -n id-n8n-deploy-dev -o table
# Expect: gh-<hash> entries for environment:dev, pull_request, ref:refs/heads/main

# Role assignments for the deploy MI
DEPLOY_PID=$(az identity show -g rg-n8n-01-dev -n id-n8n-deploy-dev --query principalId -o tsv)
az role assignment list --assignee "$DEPLOY_PID" --all -o table
# Expect:
#   Contributor                                         on rg-n8n-01-dev
#   Key Vault Secrets Officer                           on the KV
#   Reader                                              on rg-mcp-01-dev-southafricanorth
#   first-n8n CAE Env-Storages Manager (dev)            on the shared CAE

# Runtime MI
RUNTIME_PID=$(az identity show -g rg-n8n-01-dev -n id-n8n-runtime-dev --query principalId -o tsv)
az role assignment list --assignee "$RUNTIME_PID" --all -o table
# Expect: Key Vault Secrets User on the KV
```

## OIDC smoke test (from a throwaway branch)

After GitHub secrets are set, push a branch with a one-shot workflow:

```yaml
name: oidc-smoke
on: { workflow_dispatch: {} }
permissions: { id-token: write, contents: read }
jobs:
  smoke:
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: azure/login@v2
        with:
          client-id:       ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - run: az account show
```

Triggered via `gh workflow run oidc-smoke.yml --ref <branch>`. A green run proves the federated credential trust is working end-to-end.

## Re-running

The bootstrap is idempotent. Re-run any time to reconcile drift; role assignment GUIDs are deterministic so duplicates won't be created. Changing identity or KV names creates new resources — old ones are not deleted automatically.

## Rollback

```bash
# Remove the role assignments (otherwise the MI deletion leaves orphaned references)
az role assignment delete --assignee "$DEPLOY_PID" --all
az role assignment delete --assignee "$RUNTIME_PID" --all

# Delete the custom role
az role definition delete --name "first-n8n CAE Env-Storages Manager (dev)"

# Delete the identities and KV (KV needs purge after delete due to purge protection)
az identity delete -g rg-n8n-01-dev -n id-n8n-deploy-dev
az identity delete -g rg-n8n-01-dev -n id-n8n-runtime-dev
az keyvault delete -g rg-n8n-01-dev -n kv-n8n-01-dev-26070
# NOTE: purge protection blocks purge for 7 days. Plan accordingly.
```
