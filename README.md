# Containerized Claude Code with MCP

Sandboxed Claude Code environment with MCP server support.

## Setup

1. Set your Anthropic API key in `.zshrc`:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

2. Add alias to `.zshrc`:

```bash
alias cdev='docker-compose down && docker-compose build && docker-compose up -d && docker-compose exec claude-code bash'
```

3. Run:

```bash
cdev
```

4. Inside container:

```bash
c  # Starts Claude Code
```

5. Say "Yes" to API key prompt (one time per rebuild)

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
