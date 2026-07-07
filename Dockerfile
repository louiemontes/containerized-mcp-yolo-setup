FROM node:22-slim

# Pin Claude Code -- bump deliberately, not on every rebuild
ARG CLAUDE_CODE_VERSION=2.1.201
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# git for direct GitHub access (see squid.conf + AGENT_GITHUB_TOKEN)
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Extra CLI tooling, plus GitHub CLI (not in Debian's default repos, so it's
# added via GitHub's own apt repo). Uses normal build-time internet -- this
# runs before the apt proxy below is configured, since "proxy" isn't
# resolvable/up during a plain `docker build`/`docker-compose build`.
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl python3 jq openssh-client && \
    mkdir -p -m 755 /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Runtime apt proxy: the sandbox network is internal-only once the container
# is up, so any apt-get the agent runs later needs to go through squid too.
RUN echo 'Acquire::http::Proxy "http://proxy:3128";\nAcquire::https::Proxy "http://proxy:3128";' \
      > /etc/apt/apt.conf.d/01proxy

ENV PATH="/usr/local/bin:${PATH}"

# quiet the datadog phone-home the squid logs caught
ENV DISABLE_TELEMETRY=1
ENV DISABLE_ERROR_REPORTING=1

# undici's fetch() only honors HTTP_PROXY/HTTPS_PROXY when this is set
ENV NODE_USE_ENV_PROXY=1

# Create a non-root user
RUN useradd -m -s /bin/bash claudeuser && \
    mkdir -p /home/claudeuser/.claude && \
    chown -R claudeuser:claudeuser /home/claudeuser

# Agent's git traffic goes through squid too. PAT auth (AGENT_GITHUB_TOKEN)
# needs an HTTPS remote -- SSH can't traverse an HTTP proxy and github.com
# over port 22 isn't on squid's allowlist anyway.
RUN HOME=/home/claudeuser git config --global http.proxy http://proxy:3128

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

# Agent commits are already attributed via AGENT_GIT_NAME/AGENT_GIT_EMAIL
# (see entrypoint.sh) -- don't also stamp them with a Co-Authored-By trailer.
RUN echo '{ \
  "includeCoAuthoredBy": false \
}' > /home/claudeuser/.claude/settings.json

# Wrapper script
RUN echo '#!/bin/bash\nclaude --dangerously-skip-permissions "$@"' > /usr/local/bin/c && \
    chmod +x /usr/local/bin/c

RUN chown -R claudeuser:claudeuser /home/claudeuser

# Runs gh/git auth against AGENT_GITHUB_TOKEN on container start (the token
# only exists at runtime via agent.env, not at build time).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER claudeuser
WORKDIR /workspace

ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]