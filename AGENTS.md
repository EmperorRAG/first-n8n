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
└── .azure-deploy/              # Bash + az CLI utilities for ACA deployment
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

- `.env` and `.azure-deploy/secrets.sh` are gitignored. Never commit them.
- `.env.example` is the canonical template; keep it in sync with any new variables consumed by `docker-compose.yml`.
- `.azure-deploy/01-init-secrets.sh` regenerates `secrets.sh` idempotently; safe to re-run.

### Shared files

`./shared` mounts to `/data/shared` inside the n8n container. Use that path in nodes that touch the local filesystem.

## Workflows reference

| ID | Name | Pipeline |
|---|---|---|
| `srOnR8PAY3u4RSwb` | Demo workflow | Chat Trigger → Basic LLM Chain ← Ollama Chat Model (`llama3.2:latest`) |
| `mCpC0ffeeMateW0rk` | Coffee MCP Agent | Chat Trigger → AI Agent (typeVersion 1.7) ← Ollama Chat Model + MCP Client Tool (SSE → `coffee-mate-mcp:3001/sse` locally; `${MCP_URL}` — path `/mcp`, not `/sse` — in Azure) |

The Coffee MCP Agent's `MCP Client Tool` node intentionally has **no** `credentials` block in JSON — it must be configured via the UI on first run. The SSE endpoint differs by environment: local Compose uses Docker DNS (`http://coffee-mate-mcp:3001/sse`); the Azure deployment uses `MCP_URL` from [.azure-deploy/env.sh](.azure-deploy/env.sh), which today resolves to `https://ca-mcp-01-dev-southafricanorth.greengrass-f377fe8c.southafricanorth.azurecontainerapps.io/mcp`.

## How to add a new workflow

1. Build the workflow in n8n locally and export it (`Settings → Download`).
2. Save the JSON to `n8n/demo-data/workflows/<id>.json`. Pick a unique 16-char `id` and use it for both the filename and the `id` field.
3. Reference any shipped credentials by their existing IDs (`xHuYe0MDGOs9IpBW` for Ollama, `sFfERYppMeBnFNeA` for Qdrant). For MCP/SSE, leave `credentials` empty and document the manual UI step.
4. Set `meta.templateCredsSetupCompleted: true`.
5. Restart the stack (or just the `n8n-import` container) to import.

## How to add a new credential

- **Encryptable types (Ollama, Qdrant, HTTP, etc.)**: export the credential JSON from a dev n8n instance that uses the **same** `N8N_ENCRYPTION_KEY` as `.env.example`, then drop the file into `n8n/demo-data/credentials/`. Re-import on next startup.
- **MCP / SSE**: not supported via pre-encrypted JSON. Document the manual UI step in README.md instead.

## Azure Container Apps deployment (`.azure-deploy/`)

These scripts are **partial deployment helpers**, not a one-command deploy. They assume an existing ACA managed environment, Postgres Flexible Server, storage account, and a remote `coffee-mate-mcp` Container App (URL hard-coded as `MCP_URL` in `env.sh`).

### Prerequisites

- `az` CLI (workarounds target known quirks in `az` 2.85).
- Bash; on Windows use Git Bash or WSL — scripts call `cygpath`.
- Python 3 with `PyYAML` (used by the YAML-patching scripts).
- `openssl` (used by `01-init-secrets.sh`).

### Script catalog

| Script | Role | Notes |
|---|---|---|
| `env.sh` | Sources defaults | Subscription, RG (`rg-n8n-01-dev`), region (`southafricanorth`), app/job/share names, `MCP_URL`. Sources `secrets.sh` if present and derives `PG_HOST`. |
| `01-init-secrets.sh` | Generate secrets | Writes `N8N_ENCRYPTION_KEY`, `N8N_JWT_SECRET`, `PG_PASSWORD`, `PG_SERVER`, `STORAGE_ACCT` into `secrets.sh`. Idempotent — keeps existing values. |
| `recreate-import-job.sh` | Create import job | Deletes and recreates `caj-n8n-import-01-dev` from inline YAML. Workaround for `az containerapp job update --yaml` merging list fields instead of replacing. |
| `fix-job-args.sh` | Patch import job | In-place fix that rewrites the existing job's `command`/`args` via YAML round-trip. Workaround for `az` 2.85 mis-parsing comma-separated `--command`/`--args`. |
| `patch-volume.sh` | Mount Azure Files on a Container App | `patch-volume.sh APP ENVST VOL MOUNT`. Idempotent. |
| `patch-job-volume.sh` | Mount Azure Files on a Container App job | Same shape, targets jobs. |
| `secrets.sh` | Generated secrets | Gitignored. Created by `01-init-secrets.sh`. Never commit. |

### Typical run order

```bash
cd .azure-deploy
./01-init-secrets.sh
./recreate-import-job.sh
./patch-job-volume.sh "$JOB_IMPORT" "$ENVST_DEMO" demo-data /demo-data
./patch-volume.sh    "$APP_N8N"     "$ENVST_N8N"     n8n-data    /home/node/.n8n
./patch-volume.sh    "$APP_QDRANT"  "$ENVST_QDRANT"  qdrant-data /qdrant/storage
./patch-volume.sh    "$APP_OLLAMA"  "$ENVST_OLLAMA"  ollama-models /root/.ollama
```

Provisioning the ACA managed environment, Postgres Flexible Server, storage account, file shares, and Container Apps themselves is **not** automated by these scripts and currently happens out of band.

## Testing changes

- **Compose / workflows / credentials**: `docker compose --profile cpu config` to validate the compose file parses; `docker compose --profile cpu up --build` to verify boot, model pull, workflow import, and that the Coffee MCP Agent reaches `coffee-mate-mcp` once the credential is configured.
- **Bash scripts**: `bash -n .azure-deploy/*.sh` for syntax; `shellcheck .azure-deploy/*.sh` if available.
- There are no unit tests in this repo.
