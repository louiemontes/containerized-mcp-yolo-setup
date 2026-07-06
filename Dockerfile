FROM node:22-slim

# Pin Claude Code -- bump deliberately, not on every rebuild
ARG CLAUDE_CODE_VERSION=2.1.201
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# git for direct GitHub access (see squid.conf + AGENT_GITHUB_TOKEN)
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/bin:${PATH}"

# quiet the datadog phone-home the squid logs caught
ENV DISABLE_TELEMETRY=1
ENV DISABLE_ERROR_REPORTING=1

# Create a non-root user
RUN useradd -m -s /bin/bash claudeuser && \
    mkdir -p /home/claudeuser/.claude && \
    chown -R claudeuser:claudeuser /home/claudeuser

# .claude.json: onboarding complete + MCP config.
# RULE: stdio entries here must be credential-free (they share the agent's
# env), EXCEPT AGENT_GITHUB_TOKEN which the agent is trusted with directly
# (fine-grained PAT, egress gated by squid.conf). Any other secret belongs
# in the mcp-gateway container and gets registered here as "type": "http".
RUN echo '{ \
  "hasCompletedOnboarding": true, \
  "lastOnboardingVersion": "2.1.201", \
  "theme": "dark", \
  "mcpServers": { \
    "example-gateway": { \
      "type": "http", \
      "url": "http://mcp-gateway:8000/mcp" \
    } \
  } \
}' > /home/claudeuser/.claude.json

# Wrapper script
RUN echo '#!/bin/bash\nclaude --dangerously-skip-permissions "$@"' > /usr/local/bin/c && \
    chmod +x /usr/local/bin/c

RUN chown -R claudeuser:claudeuser /home/claudeuser

USER claudeuser
WORKDIR /workspace

CMD ["tail", "-f", "/dev/null"]