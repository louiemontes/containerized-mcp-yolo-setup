FROM node:22-slim

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Ensure npm global bin is in PATH
ENV PATH="/usr/local/bin:${PATH}"

# Create a non-root user
RUN useradd -m -s /bin/bash claudeuser && \
    mkdir -p /home/claudeuser/.claude && \
    chown -R claudeuser:claudeuser /home/claudeuser

# Set up MCP server
WORKDIR /app
COPY package.json ./
RUN npm install
COPY mcp-server.js ./

# Create .claude.json with onboarding complete and MCP configs
RUN echo '{ \
  "hasCompletedOnboarding": true, \
  "lastOnboardingVersion": "2.1.39", \
  "theme": "dark", \
  "mcpServers": { \
    "echo": { \
      "command": "node", \
      "args": ["/app/mcp-server.js"] \
    }, \
    "github": { \
      "command": "npx", \
      "args": ["-y", "@modelcontextprotocol/server-github"], \
      "env": { \
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${AGENT_GITHUB_TOKEN}" \
      } \
    } \
  } \
}' > /home/claudeuser/.claude.json

# Create wrapper script
RUN echo '#!/bin/bash\nclaude --dangerously-skip-permissions "$@"' > /usr/local/bin/c && \
    chmod +x /usr/local/bin/c

# Fix permissions
RUN chown -R claudeuser:claudeuser /home/claudeuser /app

USER claudeuser
WORKDIR /workspace

CMD ["tail", "-f", "/dev/null"]