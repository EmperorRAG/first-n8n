# Migration plan — `first-n8n` Azure side → Bicep + GitHub Actions

> **Status:** plan approved decisions captured (D1–D10, Q11–Q16). Ready to start Phase 0.
> **Scope:** Azure-side IaC only. Local Docker Compose (`docker-compose.yml`, `.env.example`, `n8n/demo-data/`, `shared/`) is untouched semantically.
> **Source-of-truth for current behaviour:** the seven scripts under [.azure-deploy/](../.azure-deploy/). They are deprecated as of this plan and deleted in Phase 8.

---

## Section 1 — Inventory

Disposition: **Reuse** = import existing live resource, preserve data; **Fresh** = Bicep creates new; **External** = `existing` reference, never mutated; **N/A** = not an Azure resource (workflow step). API versions are *target candidates*; pinned exactly when the module is written.

| # | Logical resource / step | Current name | Disposition | Module strategy | API version target |
|---|---|---|---|---|---|
| 1  | Resource group (workload) | `rg-n8n-01-dev` | Reuse | Out-of-band (`az group create`, idempotent) | `2024-11-01` |
| 2  | User-assigned MI (deploy) | — | Fresh — bootstrap | `avm/res/managed-identity/user-assigned-identity` | `2024-11-30` |
| 3  | Federated credentials × 3 (`environment:dev`, `pull_request`, `ref:refs/heads/main`) | — | Fresh — bootstrap | Custom child on the deploy MI (no AVM) | `2024-11-30` |
| 4  | RBAC: deploy MI → workload RG (`Contributor`) | — | Fresh — bootstrap | `Microsoft.Authorization/roleAssignments` | `2022-04-01` |
| 5  | Custom role: `managedEnvironments/storages/*` on shared CAE | — | Fresh — bootstrap (D10) | `Microsoft.Authorization/roleDefinitions` (subscription scope) | `2022-05-01-preview` |
| 6  | RBAC: deploy MI → custom role (CAE scope) + `Reader` (shared RG scope) | — | Fresh — bootstrap (D10) | `Microsoft.Authorization/roleAssignments` | `2022-04-01` |
| 7  | Key Vault | — | Fresh | `avm/res/key-vault/vault` (RBAC mode) | `2024-11-01` |
| 8  | KV secret seeders (`pg-admin-password`, `n8n-encryption-key`, `n8n-jwt-secret`) | — | Fresh (D6 = deploymentScripts) | `Microsoft.Resources/deploymentScripts` (Azure CLI image, runs `openssl rand` + `az kv secret set`, **once**, idempotent) | `2023-08-01` |
| 9  | User-assigned MI (runtime) | — | Fresh | `avm/res/managed-identity/user-assigned-identity` | `2024-11-30` |
| 10 | RBAC: runtime MI → KV (`Key Vault Secrets User`) | — | Fresh | `Microsoft.Authorization/roleAssignments` | `2022-04-01` |
| 11 | RBAC: deploymentScripts MI → KV (`Key Vault Secrets Officer`) | — | Fresh | `Microsoft.Authorization/roleAssignments` | `2022-04-01` |
| 12 | Storage account | `stn8n01dev2262613750` | **Reuse (D2)** | `avm/res/storage/storage-account`, name passed as parameter; first deploy uses `existing` for the account, AVM for shares-as-children | `2024-01-01` |
| 13 | File share `n8n-data` (5 GiB) | exists | Reuse | AVM sub-module | `2024-01-01` |
| 14 | File share `qdrant-data` (5 GiB) | exists | Reuse | AVM sub-module | `2024-01-01` |
| 15 | File share `ollama-models` (20 GiB) — `llama3.2` cached | exists | Reuse | AVM sub-module | `2024-01-01` |
| 16 | File share `n8n-demo-data` (1 GiB) | exists | Reuse | AVM sub-module | `2024-01-01` |
| 17 | File share `n8n-shared` (1 GiB) for `/data/shared` | — | **Fresh (D5)** | AVM sub-module | `2024-01-01` |
| 18 | CAE managed environment | `cae-mcp-01-dev-southafricanorth` | **External** | `existing` reference; cross-RG | `2024-10-02-preview` |
| 19 | CAE env-storage `n8n-data` | exists | Reuse | Cross-RG sub-module (`scope: resourceGroup('rg-mcp-01-dev-southafricanorth')`) on the external CAE | `2024-10-02-preview` |
| 20 | CAE env-storage `qdrant-data` | exists | Reuse | same | `2024-10-02-preview` |
| 21 | CAE env-storage `ollama-models` | exists | Reuse | same | `2024-10-02-preview` |
| 22 | CAE env-storage `n8n-demo-data` | exists | Reuse | same | `2024-10-02-preview` |
| 23 | CAE env-storage `n8n-shared` | — | Fresh (D5) | same | `2024-10-02-preview` |
| 24 | Postgres Flexible Server | `psql-n8n-01-dev-26070` | **Reuse (D3)** | `avm/res/db-for-postgre-sql/flexible-server`; existing-server import via parameterised name | `2024-08-01` |
| 25 | Postgres database `n8n` | exists | Reuse | AVM sub-resource | `2024-08-01` |
| 26 | Postgres firewall rule `AllowAllAzureServices` (D7) | exists | Reuse (kept per D7) | AVM sub-resource | `2024-08-01` |
| 27 | Container App: n8n | `ca-n8n-01-dev` | Reuse (in-place via Bicep) | `avm/res/app/container-app` wrapped by `modules/n8n-app.bicep`; runtime MI + KV refs (D8) | `2024-10-02-preview` |
| 28 | Container App: Ollama (CPU) | `ca-ollama-01-dev` | Reuse | `avm/res/app/container-app` wrapped by `modules/ollama-app.bicep` | `2024-10-02-preview` |
| 29 | Container App: Qdrant | `ca-qdrant-01-dev` | Reuse | `avm/res/app/container-app` wrapped by `modules/qdrant-app.bicep` | `2024-10-02-preview` |
| 30 | Container App Job: n8n import | `caj-n8n-import-01-dev` | Reuse (Bicep replaces YAML-merge bug surface) | `avm/res/app/job` wrapped by `modules/n8n-import-job.bicep` | `2024-10-02-preview` |
| 31 | Container App Job: Ollama model pull | — | **Fresh (D4 = a)** | `avm/res/app/job` wrapped by `modules/ollama-pull-job.bicep` | `2024-10-02-preview` |
| 32 | Demo data upload (`az storage file upload-batch`) | manual today | N/A — `infra-deploy.yml` step | — | — |
| 33 | Import job invocation + poll | manual today | N/A — `infra-deploy.yml` step | — | — |
| 34 | Ollama model-pull job invocation + poll | manual today | N/A — `infra-deploy.yml` step (D4) | — | — |
| 35 | GitHub `dev` environment + secrets (`AZURE_CLIENT_ID`, `_TENANT_ID`, `_SUBSCRIPTION_ID`) | — | Fresh — out-of-band `gh` CLI in Phase 1 README | — | — |
| 36 | `infra-pr.yml` (lint + what-if + PR comment) | — | Fresh | new file | — |
| 37 | `infra-deploy.yml` (deploy + upload + invoke jobs) | — | Fresh | new file | — |
| 38 | `infra-drift.yml` (scheduled what-if) | — | Fresh (Phase 9) | new file | — |
| 39 | `bootstrap.bicep` (sub-scope: items 2–6, plus KV provisioning hand-off) | — | Fresh (D9) | new file, run once via `az deployment sub create` | — |
| 40 | Legacy `.azure-deploy/*.sh` (7 files) + `secrets.sh` | exist | **Delete (Phase 8)** | — | — |

---

## Section 2 — Architecture decisions

| ID | Decision | Choice | Rationale / consequence |
|----|----------|--------|-------------------------|
| D1 | n8n encryption key | **B — fresh strong random in KV; users recreate Ollama + Qdrant creds in UI on first boot** | Symmetric with the existing MCP-credential UX. Strongest posture. The two pre-encrypted JSONs in `n8n/demo-data/credentials/` will not decrypt under the Azure key — README must call this out for the Azure flow only. |
| D2 | Storage account | **Reuse `stn8n01dev2262613750`** | Preserves cached `llama3.2` (~2 GB), uploaded demo data, n8n state. Bicep declares the account with `existing` for the parent resource; share definitions are AVM sub-modules. Drift on the account itself (tags, network rules) reconciles on first deploy. |
| D3 | Postgres server | **Reuse `psql-n8n-01-dev-26070`** | Preserves anything created in the live n8n UI. Same `existing` pattern. Admin password stays in KV; first deploy does not rotate the password (rotation is Phase 7). |
| D4 | Ollama model pull | **(a) Container App Job `caj-ollama-pull-01-dev`, invoked from `infra-deploy.yml`** | Declarative, idempotent (Ollama no-ops if model is cached), runs only on deploy. Job uses an Alpine-curl image and POSTs `{"name":"llama3.2"}` to `http://ca-ollama-01-dev:11434/api/pull`. Job is parameterised on model name. |
| D5 | `/data/shared` parity | **Yes — add `n8n-shared` share + env-storage + n8n volume mount** | Mirrors local; preserves workflow parity (`Read/Write Files from Disk`, `Local File Trigger`, `Execute Command` nodes). Cost: one extra share + env-storage def. Empty at provision time. |
| D6 | First-run secret seeding | **C — `Microsoft.Resources/deploymentScripts` inside Bicep** | Fully declarative, no out-of-band workflow logic. Heavy (spawns MI + storage + ACI per run); we mitigate by guarding with `forceUpdateTag` pinned to a constant so the script runs **once** and is a no-op thereafter. Script uses `--query` against KV first, only sets if missing. |
| D7 | Postgres networking | **Public + retain `AllowAllAzureServices`** | Accepted broader posture for the POC. Documented in plan as a future-tightening item; once VNet integration on the shared CAE is on the table, switch to private endpoint. |
| D8 | Container App secret strategy | **Runtime Key Vault references (`keyVaultUrl` + runtime MI)** | Enables KV rotation without app redeploy. Phase 7 cutover relies on this. Requires runtime MI grant (`Key Vault Secrets User`) before app revisions can resolve secrets — sequence enforced in module dependency graph. |
| D9 | Deploy-identity bootstrap | **`bootstrap.bicep` at subscription scope** | Reproducible, version-controlled. Run once: `az deployment sub create -l southafricanorth -f infra/bootstrap.bicep -p infra/bootstrap.dev.bicepparam`. Idempotent. |
| D10 | Cross-RG role on `rg-mcp-01-dev-southafricanorth` | **Custom role + `Reader`** | Custom role definition: actions = `Microsoft.App/managedEnvironments/storages/*`, scoped to the CAE resource ID. `Reader` on the shared RG so the deploy MI can resolve the CAE via `existing`. Requires `Microsoft.Authorization/roleDefinitions/write` at sub scope at bootstrap time — operator must have Owner on the subscription for the one-time bootstrap. |

| ID | Confirmed answer |
|----|------------------|
| Q11 | GitHub environment name = **`dev`** |
| Q12 | MI prefix = **`id-n8n-deploy-dev`** / **`id-n8n-runtime-dev`** (CAF standard) |
| Q13 | **No approval gate** on `dev` — auto-deploy on push to `main` |
| Q14 | `MCP_URL` defaults to `https://ca-mcp-01-dev-southafricanorth.greengrass-f377fe8c.southafricanorth.azurecontainerapps.io/mcp` |
| Q15 | Rotate exposed secrets in **Phase 7 cutover** |
| Q16 | Extend `.gitignore` in **Phase 0** with `*.secrets`, `.env.*` (+ `!.env.example` re-include), `.azure/`, `infra/.bicep/`, `*.bicepparam.local` |

---

## Section 3 — Phased execution plan

Each phase: **Goal · Files touched · Validation · Rollback**. Commits are conventional (`feat(infra):`, `chore(ci):`, `docs:`).

### Phase 0 — Repo hygiene & deprecation notices

- **Goal:** Mark legacy scripts deprecated, tighten `.gitignore`, prepare repo for IaC files. No Azure changes.
- **Files:**
  - Modify: [.gitignore](../.gitignore) — add `*.secrets`, `.env.*` with `!.env.example`, `.azure/`, `infra/.bicep/`, `*.bicepparam.local`.
  - Modify: [AGENTS.md](../AGENTS.md) — add a "DEPRECATED" admonition at the top of the `.azure-deploy/` section pointing to `infra/`.
  - Modify: [README.md](../README.md) — same admonition on the "Azure Container Apps deployment (work-in-progress)" section.
  - Create: [infra/.gitkeep](../infra/.gitkeep) so the directory is a known thing before code lands.
- **Validation:**
  - `git status` — only the four files above changed.
  - `git check-ignore -v secrets.sh .env.local foo.secrets infra/.bicep/main.json` — all reported ignored.
- **Rollback:** revert the commit.

### Phase 1 — Bootstrap (identity, RBAC, Key Vault scaffold)

- **Goal:** Stand up the deploy MI, federated credentials, custom role, RBAC, Key Vault, and runtime MI. Run **once per environment** by an operator with Owner on the subscription.
- **Files:**
  - Create: [infra/bootstrap.bicep](../infra/bootstrap.bicep) — subscription-scope; nested deployments to (a) `rg-n8n-01-dev` for deploy MI + runtime MI + KV + RBAC, (b) `rg-mcp-01-dev-southafricanorth` for the custom role assignment on the CAE.
  - Create: [infra/bootstrap.dev.bicepparam](../infra/bootstrap.dev.bicepparam) — env name, GitHub repo (`EmperorRAG/first-n8n`), workload RG name, shared RG name, CAE name.
  - Create: [infra/modules/identity.bicep](../infra/modules/identity.bicep) — wraps `avm/res/managed-identity/user-assigned-identity` + federated credentials children.
  - Create: [infra/modules/key-vault.bicep](../infra/modules/key-vault.bicep) — wraps `avm/res/key-vault/vault` (RBAC mode, soft-delete on, purge protection on).
  - Create: [infra/modules/rbac-cae.bicep](../infra/modules/rbac-cae.bicep) — custom role definition + assignment scoped to the CAE resource ID; deployed at `resourceGroup('rg-mcp-01-dev-southafricanorth')` scope.
  - Create: [docs/bootstrap.md](../docs/bootstrap.md) — operator runbook including the `gh` CLI commands to set environment secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) on the `dev` GitHub environment.
- **Validation:**
  - `az deployment sub validate -l southafricanorth -f infra/bootstrap.bicep -p infra/bootstrap.dev.bicepparam` → succeeds.
  - `az deployment sub create ...` → all resources show in portal.
  - `az ad app federated-credential list --id <deploy-mi-clientId>` → 3 entries.
  - From a workflow_dispatch test branch: trigger a no-op job that runs `azure/login@v2` with OIDC → succeeds.
  - `az role assignment list --assignee <deploy-mi-principalId> --all -o table` → Contributor on workload RG, Reader on shared RG, custom role on CAE.
- **Rollback:** `az deployment sub create` with a stripped-down template, or manual deletion of MIs + KV + role definition. Bootstrap is the only sub-scope deploy and is opt-in.

### Phase 2 — Stateful resources (storage account + Postgres)

- **Goal:** Bring `stn8n01dev2262613750` and `psql-n8n-01-dev-26070` under Bicep management. Reuse existing.
- **Files:**
  - Create: [infra/main.bicep](../infra/main.bicep) — RG-scope entry point. Initially provisions only storage + Postgres modules.
  - Create: [infra/main.dev.bicepparam](../infra/main.dev.bicepparam) — populates `storageAccountName`, `postgresServerName`, `keyVaultName`, `caeResourceId`, `mcpUrl`, runtime MI name.
  - Create: [infra/modules/storage.bicep](../infra/modules/storage.bicep) — wraps `avm/res/storage/storage-account`; iterates `shareNames` array to create the five shares (D5 = yes).
  - Create: [infra/modules/postgres.bicep](../infra/modules/postgres.bicep) — wraps `avm/res/db-for-postgre-sql/flexible-server`; admin password sourced from KV via `getSecret()` referencing the seeded secret.
  - Create: [infra/modules/secrets-bootstrap.bicep](../infra/modules/secrets-bootstrap.bicep) — `Microsoft.Resources/deploymentScripts` (D6); generates `pg-admin-password`, `n8n-encryption-key`, `n8n-jwt-secret` if missing in KV. `forceUpdateTag = 'v1'` (constant) so it runs once.
- **Validation:**
  - PR what-if (Phase 6 not yet wired — run manually): `az deployment group what-if -g rg-n8n-01-dev -f infra/main.bicep -p infra/main.dev.bicepparam` shows storage + Postgres as **Ignore** (existing, unchanged) plus deploymentScript as **Create**.
  - `az deployment group create ...` → success.
  - `az keyvault secret list --vault-name <kv> -o table` → 3 secrets present.
  - `az postgres flexible-server show -g rg-n8n-01-dev -n psql-n8n-01-dev-26070 --query "{state:state}"` → `Ready`.
  - n8n app still up at the existing FQDN (no app-level changes yet).
- **Rollback:** if drift breaks the app, redeploy the legacy bash flow's `01-init-secrets.sh` + `secrets.sh` values. KV deploymentScript is idempotent — re-running won't overwrite.

### Phase 3 — Demo-data upload mechanism

- **Goal:** Replace the manual `az storage file upload-batch` with an automated step. Validate independently of the import job so failures here don't cascade.
- **Files:**
  - Create: [.github/workflows/_demo-data-upload.yml](../.github/workflows/_demo-data-upload.yml) — reusable workflow (callable). Inputs: `share-name`, `local-path`. Steps: `azure/login@v2` (OIDC) → `az storage file upload-batch --account-name <storage> --destination <share> --source n8n/demo-data --auth-mode login --pattern '*.json'`. Uses runtime MI? **No** — the deploy MI runs the workflow; `Storage File Data SMB Share Contributor` role on the storage account scope must be added to the deploy MI in Phase 1's RBAC list (amend `bootstrap.bicep`).
  - Modify: [infra/bootstrap.bicep](../infra/bootstrap.bicep) — add `Storage File Data SMB Share Contributor` (or `Storage File Data Privileged Contributor` for via REST upload-batch) on the storage account scope to deploy MI. **Note:** because the storage account exists outside bootstrap's scope, the role assignment is deployed in `main.bicep` instead, gated on Phase 2's storage module output. → cross-reference: amend Phase 1 only if we precreate the role; else add to Phase 2's `main.bicep`.
- **Validation:**
  - Trigger the reusable workflow from a one-shot caller: `gh workflow run _demo-data-upload.yml`.
  - `az storage file list --account-name <storage> --share-name n8n-demo-data --auth-mode login -o table` → workflow JSON files present.
  - Re-run the workflow — succeeds, files overwritten (idempotent).
- **Rollback:** delete the reusable workflow file. Existing files on the share remain.

### Phase 4 — CAE storage attachments + the three Container Apps

- **Goal:** Attach env-storages to the existing CAE (cross-RG) and bring the three apps under Bicep. Reuse all three. Wire runtime MI + KV refs (D8). No model pull yet, no import job yet.
- **Files:**
  - Create: [infra/modules/cae-storage.bicep](../infra/modules/cae-storage.bicep) — `Microsoft.App/managedEnvironments/storages`; module is invoked from `main.bicep` with `scope: resourceGroup('rg-mcp-01-dev-southafricanorth')`. Iterates the five shares.
  - Create: [infra/modules/n8n-app.bicep](../infra/modules/n8n-app.bicep) — wraps `avm/res/app/container-app`; `userAssignedIdentities` includes the runtime MI; secrets section uses `keyVaultUrl` for `n8n-encryption-key`, `n8n-jwt-secret`, `pg-admin-password`. Volumes: `n8n-data` → `/home/node/.n8n`, `n8n-shared` → `/data/shared`. Env vars: DB_*, N8N_*, OLLAMA_HOST, MCP_URL (passthrough), WEBHOOK_URL = `https://${fqdn}/`.
  - Create: [infra/modules/ollama-app.bicep](../infra/modules/ollama-app.bicep) — internal ingress :11434, CPU `2.0`, memory `4.0Gi` (right-sized for `llama3.2` on CPU; parameterised). Volume: `ollama-models` → `/root/.ollama`.
  - Create: [infra/modules/qdrant-app.bicep](../infra/modules/qdrant-app.bicep) — internal ingress :6333. Volume: `qdrant-data` → `/qdrant/storage`.
  - Modify: [infra/main.bicep](../infra/main.bicep) — wire modules, declare cross-RG sub-deployment for `cae-storage`.
- **Validation:**
  - `az deployment group what-if` shows env-storage attachments as **NoChange** (already exist) and the three apps as **Modify** (now under Bicep).
  - After deploy: `az containerapp revision list -g rg-n8n-01-dev -n ca-n8n-01-dev -o table` shows new revision active and healthy.
  - `curl https://${N8N_FQDN}/healthz` → `200`.
  - n8n logs show no KV-resolution errors.
- **Rollback:** Container Apps support revision rollback — `az containerapp revision activate --revision <previous>` instantly reverts.

### Phase 5 — Import job + Ollama pull job

- **Goal:** Bring the import job under Bicep (eliminating the YAML-merge bug surface). Add the Ollama pull job. Both are manual-trigger; invocation is in Phase 6.
- **Files:**
  - Create: [infra/modules/n8n-import-job.bicep](../infra/modules/n8n-import-job.bicep) — wraps `avm/res/app/job`; mounts `n8n-demo-data` at `/demo-data`; same secrets/env as n8n app; `command: ['/bin/sh']`, `args: ['-c', 'n8n import:credentials --separate --input=/demo-data/credentials && n8n import:workflow --separate --input=/demo-data/workflows']`. Bicep generates ARM JSON directly — none of the `--command/--args` CSV-parsing or `--yaml` merge bugs in `az` 2.85 apply.
  - Create: [infra/modules/ollama-pull-job.bicep](../infra/modules/ollama-pull-job.bicep) — `avm/res/app/job`; image `curlimages/curl:latest`; `args: ['-fsSL', '-X', 'POST', 'http://${ollamaInternalFqdn}:11434/api/pull', '-d', '{"name":"${modelName}"}']`. Parameter `modelName` defaults to `llama3.2`.
  - Modify: [infra/main.bicep](../infra/main.bicep) — wire both jobs.
- **Validation:**
  - `az containerapp job show -g rg-n8n-01-dev -n caj-n8n-import-01-dev --query "properties.template.containers[0].args"` → 2-element list (the bug is gone).
  - Manual: `az containerapp job start ... && az containerapp job execution show ...` → `Succeeded`. Logs show `Successfully imported 2 credentials.` + `Successfully imported 2 workflows.`
  - Manual: `az containerapp job start -n caj-ollama-pull-01-dev ...` → `Succeeded`. `ollama list` from inside the Ollama app shows `llama3.2`.
- **Rollback:** delete jobs; legacy `recreate-import-job.sh` flow still works during Phases 0–7 because the legacy scripts haven't been deleted yet.

### Phase 6 — GitHub Actions workflows

- **Goal:** Replace manual `az deployment group create` with the production workflows. PR what-if + comment, push-to-main deploy + demo-data upload + job invocations.
- **Files:**
  - Create: [.github/workflows/infra-pr.yml](../.github/workflows/infra-pr.yml) — `pull_request` to `main`, paths `infra/**` + `n8n/demo-data/**`. `permissions: id-token: write, contents: read, pull-requests: write`. Steps: checkout → `azure/login@v2` (subject `pull_request`) → `az bicep build` + `az bicep lint` → `az deployment group what-if` → post the diff as a PR comment using `actions/github-script`. Comment includes a "Known what-if noise" footer (`reference()`, `listKeys()`, secure parameters).
  - Create: [.github/workflows/infra-deploy.yml](../.github/workflows/infra-deploy.yml) — `push` to `main` (paths filter) + `workflow_dispatch`. Targets `dev` environment (no approval per Q13). Steps: checkout → `azure/login@v2` (subject `environment:dev`) → `azure/arm-deploy@v2` (deploy `infra/main.bicep` against `rg-n8n-01-dev`) → call `_demo-data-upload.yml` (Phase 3) → `az containerapp job start` for the import job + poll until `Succeeded` or fail the workflow → same for the Ollama pull job → final smoke step: `curl --fail https://${N8N_FQDN}/healthz`.
  - Modify: [README.md](../README.md) — replace the "Azure Container Apps deployment (work-in-progress)" section with a new "Azure deployment (Bicep + GitHub Actions)" section. Document: how to bootstrap (one-time), how to deploy via PR/push, where secrets live, the surviving manual steps (recreate Ollama+Qdrant creds in n8n UI per D1; configure MCP credential per existing flow; MCP endpoint = `${MCP_URL}` not `/sse`).
  - Modify: [AGENTS.md](../AGENTS.md) — add an "Adding a new resource module" subsection: where modules live, AVM-first preference, naming conventions, what the PR workflow checks.
- **Validation:**
  - Open a PR that touches `infra/main.bicep` (e.g. add a tag) → PR comment appears within ~3 min with what-if output → no Azure changes.
  - Merge the PR → `infra-deploy.yml` runs end-to-end → green.
  - Manual `workflow_dispatch` of `infra-deploy.yml` → green.
- **Rollback:** disable the workflows (`gh workflow disable`); resume `az` CLI from the legacy scripts.

### Phase 7 — Cutover (rotate exposed secrets, validate clean deploy)

- **Goal:** Rotate the three exposed secret values now that runtime KV refs (D8) make rotation a metadata operation. Validate that a deploy from a *clean* state still works (we don't actually destroy and re-deploy — we exercise the workflow end-to-end).
- **Files:** none new.
- **Steps:**
  1. Operator runs `az keyvault secret set --vault-name <kv> -n n8n-encryption-key --value "$(openssl rand -hex 32)"`. Same for `n8n-jwt-secret`. **Important:** rotating `n8n-encryption-key` invalidates *any* credentials currently encrypted in the n8n DB. After this, the user must recreate the Ollama + Qdrant creds in n8n UI (per D1, this was already an expected step).
  2. Rotate `pg-admin-password`: (a) `az postgres flexible-server update -g rg-n8n-01-dev -n psql-n8n-01-dev-26070 --admin-password "$(openssl rand -base64 32)"`, (b) write the new value to KV. The runtime MI's KV reference picks up on the next n8n revision restart.
  3. Trigger a fresh `infra-deploy.yml` run via `workflow_dispatch` to force n8n + import-job revisions to refresh and pull the new secrets.
  4. Smoke test: log into the n8n UI, recreate Ollama + Qdrant creds, configure MCP credential at `${MCP_URL}`, run both demo workflows. Both must execute end-to-end successfully.
  5. Operator confirms in writing that the old `secrets.sh` values can be considered burned.
- **Validation:**
  - n8n logs show successful Postgres connection with new password.
  - `Demo workflow` returns an LLM response.
  - `Coffee MCP Agent` returns a coffee-related tool call result.
- **Rollback:** restore previous KV secret versions (`az keyvault secret set --version`); roll back Postgres admin password.

### Phase 8 — Cleanup

- **Goal:** Delete the deprecated bash and reduce the surface area to one IaC story.
- **Files:**
  - Delete: [.azure-deploy/01-init-secrets.sh](../.azure-deploy/01-init-secrets.sh)
  - Delete: [.azure-deploy/env.sh](../.azure-deploy/env.sh)
  - Delete: [.azure-deploy/fix-job-args.sh](../.azure-deploy/fix-job-args.sh)
  - Delete: [.azure-deploy/patch-job-volume.sh](../.azure-deploy/patch-job-volume.sh)
  - Delete: [.azure-deploy/patch-volume.sh](../.azure-deploy/patch-volume.sh)
  - Delete: [.azure-deploy/recreate-import-job.sh](../.azure-deploy/recreate-import-job.sh)
  - Delete: [.azure-deploy/secrets.sh](../.azure-deploy/secrets.sh) (operator deletes locally; ensure it never enters git history — it never has, per `.gitignore`)
  - Delete: [.azure-deploy/](../.azure-deploy/) directory (now empty)
  - Modify: [README.md](../README.md) — remove the "Script catalog" + "Typical run order" sections wholesale.
  - Modify: [AGENTS.md](../AGENTS.md) — remove the `.azure-deploy/` script catalog section; keep the "Workflows reference" table and the "How to add a new workflow / credential" sections (still valid).
- **Validation:**
  - `git log --diff-filter=D --name-only` shows the eight files removed.
  - PR what-if on a noop change still works (workflows do not depend on the deleted files).
  - End-to-end deploy still works.
- **Rollback:** revert the commit; the eight files come back. (They're in git history regardless of deletion.)

### Phase 9 — Post-migration: drift detection

- **Goal:** Detect manual changes made via portal/CLI between deploys.
- **Files:**
  - Create: [.github/workflows/infra-drift.yml](../.github/workflows/infra-drift.yml) — `schedule: cron 0 14 * * 1` (Mondays 14:00 UTC) + `workflow_dispatch`. Runs `az deployment group what-if` against `main` and posts the result as a Job Summary; fails the workflow if any change is **Modify** or **Delete** (i.e. drift exists).
- **Validation:**
  - Manually drift one tag via `az tag update`, run the workflow → fails with the drift item highlighted.
  - Re-deploy via `infra-deploy.yml` → drift workflow next run is green.
- **Rollback:** disable the workflow.

---

## Section 4 — File-by-file deliverable list

Grouped by phase. **C** = create, **M** = modify, **D** = delete.

### Phase 0

- M [.gitignore](../.gitignore) — add `*.secrets`, `.env.*` + `!.env.example`, `.azure/`, `infra/.bicep/`, `*.bicepparam.local`.
- M [AGENTS.md](../AGENTS.md) — DEPRECATED admonition on `.azure-deploy/` section.
- M [README.md](../README.md) — DEPRECATED admonition on Azure section.
- C [infra/.gitkeep](../infra/.gitkeep) — placeholder.

### Phase 1

- C [infra/bootstrap.bicep](../infra/bootstrap.bicep) — sub-scope; deploys deploy MI, runtime MI, KV, federated creds, custom role, RBAC.
- C [infra/bootstrap.dev.bicepparam](../infra/bootstrap.dev.bicepparam) — env-specific values.
- C [infra/modules/identity.bicep](../infra/modules/identity.bicep) — UAMI + federated credentials (AVM wrapper).
- C [infra/modules/key-vault.bicep](../infra/modules/key-vault.bicep) — KV in RBAC mode (AVM wrapper).
- C [infra/modules/rbac-cae.bicep](../infra/modules/rbac-cae.bicep) — custom role definition + assignment.
- C [docs/bootstrap.md](../docs/bootstrap.md) — operator runbook (one-time).

### Phase 2

- C [infra/main.bicep](../infra/main.bicep) — RG-scope entry point (storage + Postgres only at this point).
- C [infra/main.dev.bicepparam](../infra/main.dev.bicepparam) — dev environment params.
- C [infra/modules/storage.bicep](../infra/modules/storage.bicep) — storage account + 5 shares (AVM wrapper).
- C [infra/modules/postgres.bicep](../infra/modules/postgres.bicep) — Postgres Flexible Server + db + firewall (AVM wrapper).
- C [infra/modules/secrets-bootstrap.bicep](../infra/modules/secrets-bootstrap.bicep) — `deploymentScripts` resource that seeds the 3 KV secrets (D6).

### Phase 3

- C [.github/workflows/_demo-data-upload.yml](../.github/workflows/_demo-data-upload.yml) — reusable workflow for `az storage file upload-batch`.
- M [infra/main.bicep](../infra/main.bicep) — add role assignment for deploy MI on storage account (`Storage File Data Privileged Contributor`).

### Phase 4

- C [infra/modules/cae-storage.bicep](../infra/modules/cae-storage.bicep) — env-storage attachments on the external CAE (cross-RG).
- C [infra/modules/n8n-app.bicep](../infra/modules/n8n-app.bicep) — n8n Container App (AVM wrapper, runtime MI, KV refs).
- C [infra/modules/ollama-app.bicep](../infra/modules/ollama-app.bicep) — Ollama CPU Container App (AVM wrapper).
- C [infra/modules/qdrant-app.bicep](../infra/modules/qdrant-app.bicep) — Qdrant Container App (AVM wrapper).
- M [infra/main.bicep](../infra/main.bicep) — wire the three apps + cae-storage cross-RG module.

### Phase 5

- C [infra/modules/n8n-import-job.bicep](../infra/modules/n8n-import-job.bicep) — import job (AVM wrapper).
- C [infra/modules/ollama-pull-job.bicep](../infra/modules/ollama-pull-job.bicep) — model-pull job (AVM wrapper).
- M [infra/main.bicep](../infra/main.bicep) — wire both jobs.

### Phase 6

- C [.github/workflows/infra-pr.yml](../.github/workflows/infra-pr.yml) — lint + what-if + PR comment.
- C [.github/workflows/infra-deploy.yml](../.github/workflows/infra-deploy.yml) — deploy + upload + invoke jobs + smoke.
- M [README.md](../README.md) — replace "Azure Container Apps deployment (work-in-progress)" with the new IaC narrative.
- M [AGENTS.md](../AGENTS.md) — add "Adding a new resource module" subsection.

### Phase 7

- *(no file changes; runtime secret rotations + smoke testing only)*

### Phase 8

- D [.azure-deploy/01-init-secrets.sh](../.azure-deploy/01-init-secrets.sh)
- D [.azure-deploy/env.sh](../.azure-deploy/env.sh)
- D [.azure-deploy/fix-job-args.sh](../.azure-deploy/fix-job-args.sh)
- D [.azure-deploy/patch-job-volume.sh](../.azure-deploy/patch-job-volume.sh)
- D [.azure-deploy/patch-volume.sh](../.azure-deploy/patch-volume.sh)
- D [.azure-deploy/recreate-import-job.sh](../.azure-deploy/recreate-import-job.sh)
- D [.azure-deploy/secrets.sh](../.azure-deploy/secrets.sh)
- D [.azure-deploy/](../.azure-deploy/) (now empty)
- M [README.md](../README.md) — remove script catalog + typical run order.
- M [AGENTS.md](../AGENTS.md) — remove `.azure-deploy/` script catalog.

### Phase 9

- C [.github/workflows/infra-drift.yml](../.github/workflows/infra-drift.yml) — scheduled drift detection.

---

## Section 5 — Open questions for me

All previously open questions answered (D1–D10, Q11–Q16). **No remaining blockers for Phase 0.**

If anything below diverges from your intent during execution, I'll stop and propose an amendment per the working agreement:

- D6's `deploymentScripts` choice means a transient ACI + storage account spin up under your subscription each time it runs. The constant `forceUpdateTag` keeps it to one execution unless you change the tag — surface this in code review when the module lands.
- D7's `AllowAllAzureServices` rule will be flagged by `azqr` and similar tools. Documented as accepted risk.

---

## Section 6 — Estimated effort

Hours assume a moderately experienced Azure/Bicep operator with this plan in hand and AVM modules behaving normally.

| Phase | Estimate | Notes |
|-------|----------|-------|
| 0 — Hygiene | 0.5 h | Mechanical edits. |
| 1 — Bootstrap | 3 h | Most of the time is in the federated-credentials + custom-role + cross-RG RBAC trio; a lot of doc-checking. |
| 2 — Stateful (storage + Postgres) | 2 h | Reuse-existing wrinkles; verifying what-if shows no destructive ops. |
| 3 — Demo-data upload | 1 h | Reusable workflow + role assignment. |
| 4 — CAE attachments + 3 apps | 4 h | Cross-RG sub-deployment is the trickiest piece; runtime KV refs need careful sequencing. |
| 5 — Two jobs | 1.5 h | Mostly straightforward once the apps are in place. |
| 6 — Workflows | 3 h | PR-comment plumbing, end-to-end testing on a real PR. |
| 7 — Cutover | 1.5 h | Sequential; manual UI work for credentials. |
| 8 — Cleanup | 0.5 h | Mechanical. |
| 9 — Drift workflow | 1 h | One file. |
| **Total** | **~18 h** | Spread across multiple sessions; roughly two solid days. |

---

## Section 7 — Out of scope (explicitly)

This migration deliberately does **not** do any of the following. If any of these become required later, they're separate plans.

- Modify [docker-compose.yml](../docker-compose.yml), [n8n/demo-data/](../n8n/demo-data/), [shared/](../shared/), [assets/](../assets/), [.env.example](../.env.example), or [CONTRIBUTING.md](../CONTRIBUTING.md) — semantically. Comment-only edits in compose are acceptable if needed for clarity.
- Migrate or modify the `../first-mcp` repository.
- Add VNet integration to the existing shared CAE (would require coordination with the MCP team).
- Add GPU support for Ollama (`southafricanorth` does not have ACA serverless GPU SKUs).
- Add multi-environment support beyond `dev` (the `main.<env>.bicepparam` pattern is in place; `staging`/`prod` files are a future change).
- Add monitoring, alerting, or backup beyond what's on by default. (Postgres has 7-day automated backups by default, which is acceptable for a POC; KV has soft-delete + purge protection enabled in the module.)
- Tighten the Postgres firewall (D7 deferred).
- Re-encrypt the bundled `n8n/demo-data/credentials/*.json` for the Azure key (D1 = B; users recreate in UI).
- Anything related to costs / cost alerts.
- Production-shape concerns: WAF, custom domain, TLS cert lifecycle, log archival to immutable storage, audit log forwarding, compliance baselines.

---

> Approve the plan and I'll start Phase 0 in the next reply.
