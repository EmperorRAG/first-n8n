# Project Guidelines

Operational notes for humans and coding agents working in this repo. User-facing setup lives in [README.md](README.md); this file captures conventions, gotchas, and how-to-extend guidance.

## Architecture

Docker Compose stack forked from [n8n-io/self-hosted-ai-starter-kit](https://github.com/n8n-io/self-hosted-ai-starter-kit), extended with an MCP server. All services run on the `demo` Docker network.

| Service | Port | Notes |
|---|---|---|
| `postgres` | — | n8n backend; healthcheck via `pg_isready`. |
| `n8n-import` | — | One-shot importer; runs `n8n import:credentials` + `n8n import:workflow` from `/demo-data` and exits. |
| `n8n` | `5678` | Depends on `postgres` healthy, `n8n-import` completed, `coffee-mate-mcp` healthy. |
| `qdrant` | `6333` | Vector DB. |
| `ollama-{cpu,gpu,gpu-amd}` | `11434` | Profile-gated; only one runs at a time. |
| `ollama-pull-llama-*` | — | Profile-gated init container; pulls `llama3.2`. |
| `coffee-mate-mcp` | `3001` | Built from sibling `../first-mcp`; serves `/sse` (MCP) and `/health`. |

Ollama profiles: `cpu`, `gpu-nvidia`, `gpu-amd`. Mac/Apple-Silicon runs without a profile and points n8n at host Ollama via `OLLAMA_HOST=host.docker.internal:11434`.

## Repository layout

```text
.
├── docker-compose.yml          # All services
├── .env.example                # Template (.env is gitignored)
├── README.md                   # User-facing setup
├── AGENTS.md                   # This file
├── CONTRIBUTING.md             # Upstream vision (kept as-is)
├── assets/n8n-demo.gif
├── shared/                     # → /data/shared in the n8n container
├── n8n/demo-data/
│   ├── workflows/              # Auto-imported on every startup
│   └── credentials/            # Pre-encrypted with the .env.example demo key
└── infra/                      # Azure Bicep IaC + GitHub Actions deploy workflows
```

## Build and Run

```bash
cp .env.example .env                          # First time only
docker compose --profile cpu up --build       # CPU mode (use --build when ../first-mcp source changes)
docker compose --profile cpu up --build -d    # Detached
docker compose --profile cpu down -v          # Stop and remove all volumes (full reset)

# Mac / Apple Silicon — Ollama runs natively on host
# Set OLLAMA_HOST=host.docker.internal:11434 in .env, then:
docker compose up --build
```

## Conventions

### Workflows

- JSON files in [`n8n/demo-data/workflows/`](n8n/demo-data/workflows) — auto-imported on every startup, idempotent by `id`.
- Schema essentials:
  - `id` — canonical key. Pick a unique 16-char string. Re-using an `id` overwrites.
  - `name` — display name in the n8n UI.
  - `nodes[].id` / `nodes[].name` — `connections` is keyed by node **`name`**, so renaming a node means updating `connections` too.
  - `connections.<NodeName>.<output>[i][j]` — adjacency list; `output` is `main`, `ai_languageModel`, `ai_tool`, etc.
  - `nodes[].position` — `[x, y]`. Existing layouts use ~220 px grid spacing; match it for visual consistency.
  - `versionId` — arbitrary string; bump when you change a workflow you've already imported.
  - `meta.templateCredsSetupCompleted: true` — keep this set so n8n doesn't show the template-setup banner.
  - Reference shipped credentials by their IDs (see below).

### Credentials

- JSON files in [`n8n/demo-data/credentials/`](n8n/demo-data/credentials) — auto-imported on every startup.
- The two shipped credentials are **pre-encrypted with the upstream demo key (`super-secret-key`)**:
  - `xHuYe0MDGOs9IpBW` — `ollamaApi` — *Local Ollama service*
  - `sFfERYppMeBnFNeA` — `qdrantApi` — *Local Qdrant Api database*
- They only decrypt when `N8N_ENCRYPTION_KEY` in `.env` matches the value used to encrypt them. **Do not change the key after first boot** — if you do, recreate the credentials in the UI or re-export them from a dev n8n that uses the new key.
- **MCP / SSE credentials cannot be pre-encrypted in JSON.** Users create the MCP credential in the n8n UI after first boot (steps in README.md).

### Secrets and environment

- `.env` is gitignored. Never commit it.
- `.env.example` is the canonical template; keep it in sync with any new variables consumed by `docker-compose.yml`.

### Shared files

`./shared` mounts to `/data/shared` inside the n8n container. Use that path in nodes that touch the local filesystem.

## Workflows reference

| ID | Name | Pipeline |
|---|---|---|
| `srOnR8PAY3u4RSwb` | Demo workflow | Chat Trigger → Basic LLM Chain ← Ollama Chat Model (`llama3.2:latest`) |
| `mCpC0ffeeMateW0rk` | Coffee MCP Agent | Chat Trigger → AI Agent (typeVersion 1.7) ← Ollama Chat Model + MCP Client Tool (SSE → `coffee-mate-mcp:3001/sse` locally; `${MCP_URL}` — path `/mcp`, not `/sse` — in Azure) |

The Coffee MCP Agent's `MCP Client Tool` node intentionally has **no** `credentials` block in JSON — it must be configured via the UI on first run. The SSE endpoint differs by environment: local Compose uses Docker DNS (`http://coffee-mate-mcp:3001/sse`); the Azure deployment currently resolves to `https://ca-mcp-01-dev-southafricanorth.greengrass-f377fe8c.southafricanorth.azurecontainerapps.io/mcp` (path is `/mcp`, not `/sse`).

## How to add a new workflow

1. Build the workflow in n8n locally and export it (`Settings → Download`).
2. Save the JSON to `n8n/demo-data/workflows/<id>.json`. Pick a unique 16-char `id` and use it for both the filename and the `id` field.
3. Reference any shipped credentials by their existing IDs (`xHuYe0MDGOs9IpBW` for Ollama, `sFfERYppMeBnFNeA` for Qdrant). For MCP/SSE, leave `credentials` empty and document the manual UI step.
4. Set `meta.templateCredsSetupCompleted: true`.
5. Restart the stack (or just the `n8n-import` container) to import.

## How to add a new credential

- **Encryptable types (Ollama, Qdrant, HTTP, etc.)**: export the credential JSON from a dev n8n instance that uses the **same** `N8N_ENCRYPTION_KEY` as `.env.example`, then drop the file into `n8n/demo-data/credentials/`. Re-import on next startup.
- **MCP / SSE**: not supported via pre-encrypted JSON. Document the manual UI step in README.md instead.

## Adding a new Azure resource (Bicep module)

Azure resources live under [infra/](infra/) and are deployed via the GitHub Actions workflows in [.github/workflows/](.github/workflows/). Authoritative plan and phase status: [infra/MIGRATION-PLAN.md](infra/MIGRATION-PLAN.md).

- **Where modules live:** one file per logical component under [infra/modules/](infra/modules/). Wire it into [infra/main.bicep](infra/main.bicep) — never hand-roll resources directly in `main.bicep`. Parameter values live in [infra/main.dev.bicepparam](infra/main.dev.bicepparam).
- **AVM-first:** prefer Azure Verified Modules (`br/public:avm/...`) over hand-written `Microsoft.*` resource declarations. Only drop down to a raw resource when AVM does not cover it (current example: [infra/modules/cae-storage.bicep](infra/modules/cae-storage.bicep), where `Microsoft.App/managedEnvironments/storages` is unavailable as AVM and uses `listKeys` for the storage key).
- **Naming:** follow the existing convention — `{type-prefix}-{workload}-{instance}-{env}` (e.g. `ca-n8n-01-dev`, `caj-ollama-pull-01-dev`, `psql-n8n-01-dev-26070`). Region suffix only for shared cross-RG resources (e.g. `cae-mcp-01-dev-southafricanorth`).
- **Secrets:** never inline secret values. Add them to Key Vault and reference them via `keyVaultUrl` + `identity` on the Container App secret block (see [infra/modules/n8n-app.bicep](infra/modules/n8n-app.bicep) and [infra/modules/n8n-import-job.bicep](infra/modules/n8n-import-job.bicep)). The runtime MI (`id-n8n-runtime-dev`) already has `Key Vault Secrets User` on the workload KV.
- **Cross-RG resources:** use a sub-deployment scoped to the target RG (see how `cae-storage` deploys into `rg-mcp-01-dev-southafricanorth` from `main.bicep`). The deploy MI has Reader on the shared RG plus the custom `CAE Storage Contributor` role on the CAE.
- **What the PR workflow checks:** [`infra-pr.yml`](.github/workflows/infra-pr.yml) runs `az bicep build`, `az bicep lint`, and `az deployment group what-if` against `rg-n8n-01-dev` and posts the diff as a sticky PR comment. It is read-only — no Azure changes happen on a PR. Treat the what-if comment as the design review.
- **What the deploy workflow does:** [`infra-deploy.yml`](.github/workflows/infra-deploy.yml) runs on push to `main` or manual dispatch: Bicep deploy → demo-data upload → import job → Ollama pull job → `/healthz` smoke. If a new module needs a post-deploy job (analogous to import or pull), add it to `infra-deploy.yml`'s job graph.
- **What the drift workflow does:** [`infra-drift.yml`](.github/workflows/infra-drift.yml) runs Mondays 14:00 UTC (and on manual dispatch): a read-only `az deployment group what-if` against `main`. The run fails on any `Modify` or `Delete` delta (Azure state diverged from Bicep). `Create` deltas are surfaced but don't fail the run — they mean a Bicep change is pending deploy. Full diff is in the run's Job Summary.
- **Local dev impact:** none expected. The Bicep stack is Azure-only; [docker-compose.yml](docker-compose.yml) is the source of truth for local development and must keep working unchanged.

## Testing changes

- **Compose / workflows / credentials**: `docker compose --profile cpu config` to validate the compose file parses; `docker compose --profile cpu up --build` to verify boot, model pull, workflow import, and that the Coffee MCP Agent reaches `coffee-mate-mcp` once the credential is configured.
- **Bicep**: `az bicep build --file infra/main.bicep` and `az bicep lint --file infra/main.bicep` locally; the `infra-pr.yml` workflow runs both plus `what-if` on every PR.
- There are no unit tests in this repo.
