# Containerized Claude Code with MCP

Sandboxed Claude Code environment with MCP server support.

## Prerequisites

### Docker & Docker Compose

You need Docker installed and running on your machine:

- **Mac/Windows**: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- **Linux**: [Docker Engine](https://docs.docker.com/engine/install/) + [Docker Compose](https://docs.docker.com/compose/install/)

Verify installation:

```bash
docker --version
docker-compose --version
```

### Anthropic API Key

You need an API key from Anthropic Console (not a Claude subscription):

1. Go to [Anthropic Console](https://console.anthropic.com/)
2. Sign up or log in
3. Navigate to [API Keys](https://console.anthropic.com/settings/keys)
4. Click "Create Key"
5. Copy your key (starts with `sk-ant-...`)

**Note**: This uses pay-as-you-go API billing, not your Claude.ai subscription. Make sure to monitor usage in the console to avoid unexpected charges.

**WARNING**: Never share or check in your API key. Treat it like a password.

**BIGGER WARNING**: This setup bypasses all permissions for Claude inside the container. Do not run this on a production machine or with sensitive data. Use at your own risk.

**_EVEN BIGGER WARNING_**: Set a limit on your API key in the Anthropic Console to prevent runaway costs. For example, set a daily limit of $5 or 1000 tokens.

## Setup

1. Fill out the two env files (both gitignored) following the examples:

```bash
agent.env
gateway.env
```

- `agent.env` is loaded into the **claude-code** container. The agent can
  read and act on anything in here with full agency (it runs with
  `--dangerously-skip-permissions`) -- only put secrets you're fine
  giving it maximum opportunity with, like your `ANTHROPIC_API_KEY` or a
  fine-grained GitHub PAT scoped to a specific repo. Fill in
  `ANTHROPIC_API_KEY` here (see [API Keys](https://console.anthropic.com/settings/keys)).
  Also set `AGENT_GIT_NAME`/`AGENT_GIT_EMAIL` -- these become the container's
  `git config --global user.name`/`user.email` at startup, so commits the
  agent makes are attributed to it rather than to you.
- `gateway.env` is loaded into the **mcp-gateway** container only. The
  agent ideally never sees these values directly -- it can only call the narrow
  tools defined in `gateway/server.js`, which use the secret on the
  agent's behalf.

2. Add alias to `.zshrc`:

```bash
alias cdev='docker-compose down && docker-compose build && docker-compose up -d && docker-compose exec claude-code bash'
```

3. Reload your shell:

```bash
source ~/.zshrc
```

4. Clone this repo and run:

```bash
cdev
```

5. Inside container:

```bash
c  # Starts Claude Code
```

6. Say "Yes" to API key prompt (one time per rebuild)

## Features

- ✅ Isolated sandbox (only accesses `./workspace` directory)
- ✅ MCP gateway example (`gateway/server.js`) for credential-isolated tool calls
- ✅ Permissions bypassed via `--dangerously-skip-permissions`
- ✅ Non-root user for security
- ✅ One-command rebuild and exec

## Testing MCP

Inside Claude Code:

```
/mcp   # View MCP servers
```

## Adding More MCP Servers

Edit the `mcpServers` section in Dockerfile's `.claude.json` creation. For a
server that needs a secret, add a tool to `gateway/server.js` instead so the
credential never reaches the agent container directly.
