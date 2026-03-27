# Project Guidelines

## Architecture

Docker Compose stack forked from [n8n-io/self-hosted-ai-starter-kit](https://github.com/n8n-io/self-hosted-ai-starter-kit), extended with MCP server integration. All services run on the `demo` Docker network.

Services:

- **n8n** (`:5678`) — workflow automation platform
- **PostgreSQL** — n8n backend database
- **Ollama** (`:11434`) — local LLM inference (`llama3.2`)
- **Qdrant** (`:6333`) — vector database
- **coffee-mate-mcp** (`:3001`) — MCP server built from sibling `../first-mcp` directory

Ollama profiles: `cpu`, `gpu-nvidia`, `gpu-amd`.

## Build and Run

```bash
cp .env.example .env                          # First time only
docker compose --profile cpu up --build       # CPU mode (use --build when first-mcp source changes)
docker compose --profile cpu up --build -d    # Detached mode
docker compose --profile cpu down -v          # Stop and remove volumes (full reset)
```

## Conventions

- **Workflows**: JSON files in `n8n/demo-data/workflows/` — auto-imported on every startup (idempotent by ID)
- **Credentials**: JSON files in `n8n/demo-data/credentials/` — auto-imported on every startup
- **Environment**: Configure via `.env` (copy from `.env.example`). Key vars: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY`
- **Shared files**: `./shared/` mounts to `/data/shared` inside the n8n container
- **MCP service**: `coffee-mate-mcp` is built from `../first-mcp` — projects must be sibling directories
- **MCP credentials**: Cannot be pre-encrypted in JSON; create MCP SSE credentials via the n8n UI after first boot

## Workflows

| ID | Name | Description |
|----|------|-------------|
| `srOnR8PAY3u4RSwb` | Demo workflow | Basic Chat Trigger → LLM Chain → Ollama |
| `mCpC0ffeeMateW0rk` | Coffee MCP Agent | Chat Trigger → AI Agent with Ollama + MCP Client Tool |
