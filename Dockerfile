FROM node:22-slim

# Pin Claude Code -- bump deliberately, not on every rebuild
ARG CLAUDE_CODE_VERSION=2.1.201
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

ENV PATH="/usr/local/bin:${PATH}"

# Create a non-root user
RUN useradd -m -s /bin/bash claudeuser && \
    mkdir -p /home/claudeuser/.claude && \
    chown -R claudeuser:claudeuser /home/claudeuser

# Set up MCP server (npm ci = lockfile-exact install)
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY mcp-server.js ./

# .claude.json: onboarding complete + MCP config.
# NOTE: no credentialed MCP servers here. If you add one, its token is
# readable by anything Claude runs -- pair it with the egress allowlist
# in squid.conf and a minimally-scoped token, or don't add it at all.
RUN echo '{ \
  "hasCompletedOnboarding": true, \
  "lastOnboardingVersion": "2.1.201", \
  "theme": "dark", \
  "mcpServers": { \
    "echo": { \
      "command": "node", \
      "args": ["/app/mcp-server.js"] \
    } \
  } \
}' > /home/claudeuser/.claude.json

# Wrapper script
RUN echo '#!/bin/bash\nclaude --dangerously-skip-permissions "$@"' > /usr/local/bin/c && \
    chmod +x /usr/local/bin/c

RUN chown -R claudeuser:claudeuser /home/claudeuser /app

USER claudeuser
WORKDIR /workspace

CMD ["tail", "-f", "/dev/null"]
