# Self-hosted AI + MCP Starter Kit

A local AI and workflow automation environment with MCP (Model Context Protocol) integration, forked from the [n8n-io/self-hosted-ai-starter-kit](https://github.com/n8n-io/self-hosted-ai-starter-kit).

This stack extends the original starter kit with a dockerized MCP server ([coffee-mate](../first-mcp)), demonstrating how n8n can use MCP tools via an AI Agent workflow.

### What's included

✅ [**Self-hosted n8n**](https://n8n.io/) - Low-code platform with over 400
integrations and advanced AI components

✅ [**Ollama**](https://ollama.com/) - Cross-platform LLM platform to install
and run the latest local LLMs

✅ [**Qdrant**](https://qdrant.tech/) - Open-source, high performance vector
store with a comprehensive API

✅ [**PostgreSQL**](https://www.postgresql.org/) - Persistent data storage for n8n

✅ **Coffee Mate MCP Server** - TypeScript MCP server exposing coffee data tools, connected to n8n via SSE transport

## Prerequisites

- Docker Desktop
- Both `first-n8n` and `first-mcp` directories must exist as siblings (e.g. under the same parent folder)

## Installation

```bash
cp .env.example .env   # Update secrets and passwords inside
```

### Running with Docker Compose

#### CPU (no GPU)

```bash
docker compose --profile cpu up --build
```

> Use `--build` to rebuild the MCP server image when `first-mcp` source changes.

#### Nvidia GPU

```bash
docker compose --profile gpu-nvidia up --build
```

> [!NOTE]
> If you have not used your Nvidia GPU with Docker before, please follow the
> [Ollama Docker instructions](https://github.com/ollama/ollama/blob/main/docs/docker.md).

#### AMD GPU (Linux)

```bash
docker compose --profile gpu-amd up --build
```

#### Mac / Apple Silicon

Mac cannot expose GPU to Docker. Either use CPU mode above, or run Ollama locally and set `OLLAMA_HOST=host.docker.internal:11434` in your `.env` file, then:

```bash
docker compose up --build
```

## Quick start

1. Open <http://localhost:5678/> in your browser to set up n8n (first time only).
2. Two workflows are available:
   - **Demo workflow**: <http://localhost:5678/workflow/srOnR8PAY3u4RSwb> — basic Chat → Ollama chain
   - **Coffee MCP Agent**: <http://localhost:5678/workflow/mCpC0ffeeMateW0rk> — AI Agent using MCP tools
3. If this is the first time running, wait for Ollama to finish downloading Llama3.2. Check progress with `docker logs ollama-pull-llama`.

### Configuring the MCP credential (first time only)

The Coffee MCP Agent workflow needs an MCP credential configured in the n8n UI:

1. Open the **Coffee MCP Agent** workflow
2. Click the **MCP Client Tool** node
3. Set the SSE endpoint to `http://coffee-mate-mcp:3001/sse`
4. Set authentication to **None**
5. Save the credential and the workflow

Test by clicking **Chat** and asking: "What coffees do you have?"

## Services

| Service | Port | Description |
|---------|------|-------------|
| n8n | `5678` | Workflow editor and runner |
| coffee-mate-mcp | `3001` | MCP server (SSE transport) |
| Ollama | `11434` | LLM inference |
| Qdrant | `6333` | Vector database |
| PostgreSQL | — | n8n backend database |

## Tips & tricks

### Accessing local files

The `./shared` folder is mounted to `/data/shared` inside the n8n container. Use this path in nodes that interact with the local filesystem:

- [Read/Write Files from Disk](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.filesreadwrite/)
- [Local File Trigger](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.localfiletrigger/)
- [Execute Command](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.executecommand/)

### Full reset

To wipe all data and start fresh:

```bash
docker compose --profile cpu down -v
docker compose --profile cpu up --build
```

## Recommended reading

- [AI agents for developers: from theory to practice with n8n](https://blog.n8n.io/ai-agents/)
- [Tutorial: Build an AI workflow in n8n](https://docs.n8n.io/advanced-ai/intro-tutorial/)
- [Langchain Concepts in n8n](https://docs.n8n.io/advanced-ai/langchain/langchain-n8n/)
- [Demonstration of key differences between agents and chains](https://docs.n8n.io/advanced-ai/examples/agent-chain-comparison/)

## 📜 License

This project is licensed under the Apache License 2.0 - see the
[LICENSE](LICENSE) file for details.

## 💬 Support

Join the conversation in the [n8n Forum](https://community.n8n.io/).
