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

1. Set your Anthropic API key in `.zshrc` (or `.bashrc`):

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

2. Reload your shell:

```bash
source ~/.zshrc
```

3. Add alias to `.zshrc`:

```bash
alias cdev='docker-compose down && docker-compose build && docker-compose up -d && docker-compose exec claude-code bash'
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
- ✅ MCP server example (echo tool)
- ✅ Permissions bypassed via `--dangerously-skip-permissions`
- ✅ Non-root user for security
- ✅ One-command rebuild and exec

## Testing MCP

Inside Claude Code:

```
/mcp                           # View MCP servers
Use the echo tool to say hi!   # Test the echo tool
```

## Adding More MCP Servers

Edit the `mcpServers` section in Dockerfile's `.claude.json` creation.
