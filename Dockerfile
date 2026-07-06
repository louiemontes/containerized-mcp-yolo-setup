FROM node:22-slim

# Pin Claude Code -- bump deliberately, not on every rebuild
ARG CLAUDE_CODE_VERSION=2.1.201
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

ENV PATH="/usr/local/bin:${PATH}"

# quiet the datadog phone-home the squid logs caught
ENV DISABLE_TELEMETRY=1
ENV DISABLE_ERROR_REPORTING=1

# Create a non-root user
RUN useradd -m -s /bin/bash claudeuser && \
    mkdir -p /home/claudeuser/.claude && \
    chown -R claudeuser:claudeuser /home/claudeuser

# Set up local stdio MCP server (npm ci = lockfile-exact install)
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY mcp-server.js ./

# .claude.json: onboarding complete + MCP config.
# RULE: stdio entries here must be credential-free (they share the agent's
# env). Anything holding a token lives in the mcp-gateway container and is
# registered here as "type": "http" only.
RUN echo '{ \
  "hasCompletedOnboarding": true, \
  "lastOnboardingVersion": "2.1.201", \
  "theme": "dark", \
  "mcpServers": { \
    "echo": { \
      "command": "node", \
      "args": ["/app/mcp-server.js"] \
    }, \
    "gh-gateway": { \
      "type": "http", \
      "url": "http://mcp-gateway:8000/mcp" \
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