FROM node:22-slim

# Pin Claude Code -- bump deliberately, not on every rebuild
ARG CLAUDE_CODE_VERSION=2.1.201
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# git for direct GitHub access (see squid.conf + AGENT_GITHUB_TOKEN), plus a
# fixed, user-independent Playwright toolkit: this installs the npm package
# AND the matching Chromium build into /opt/browser-driver (own node_modules,
# so ad-hoc driver scripts can `import { chromium } from 'playwright'` without
# ever touching a project's package.json), with the browser binary cached at
# PLAYWRIGHT_BROWSERS_PATH so it's readable regardless of which user runs.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /opt/browser-driver && \
    cd /opt/browser-driver && \
    npm init -y > /dev/null && \
    npm install playwright && \
    npx --no-install playwright install --with-deps chromium


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

# Global git hooks dir that auto-corrects a repo-local user.name/email
# override that doesn't match AGENT_GIT_NAME/AGENT_GIT_EMAIL (set globally by
# entrypoint.sh at runtime) -- otherwise a repo's own .git/config could
# silently hijack commit attribution.
# LIMITATIONS: core.hooksPath set globally here is shadowed by any repo that
# sets its own local core.hooksPath (e.g. Husky-managed JS repos) -- those
# repos won't get this protection. Also this only affects things going
# forward (new commits/checkouts) -- a repo already checked out with a bad
# override needs a fresh checkout, or a manual
# `git config --local --unset user.name/user.email`, to fix immediately.
RUN mkdir -p /home/claudeuser/.git-hooks && \
    printf '%s\n' \
      '#!/bin/sh' \
      '# Strip a repo-local user.name/user.email override if it does not' \
      '# match AGENT_GIT_NAME/AGENT_GIT_EMAIL, so commits fall back to the' \
      '# global identity instead of silently using a repo-local override.' \
      '' \
      'if [ -n "$AGENT_GIT_NAME" ]; then' \
      '  local_name=$(git config --local --get user.name 2>/dev/null)' \
      '  if [ -n "$local_name" ] && [ "$local_name" != "$AGENT_GIT_NAME" ]; then' \
      '    git config --local --unset-all user.name' \
      '  fi' \
      'fi' \
      '' \
      'if [ -n "$AGENT_GIT_EMAIL" ]; then' \
      '  local_email=$(git config --local --get user.email 2>/dev/null)' \
      '  if [ -n "$local_email" ] && [ "$local_email" != "$AGENT_GIT_EMAIL" ]; then' \
      '    git config --local --unset-all user.email' \
      '  fi' \
      'fi' \
      '' \
      'exit 0' \
      > /home/claudeuser/.git-hooks/fix-identity.sh && \
    printf '%s\n' '#!/bin/sh' 'exec "$(dirname "$0")/fix-identity.sh"' \
      > /home/claudeuser/.git-hooks/pre-commit && \
    printf '%s\n' '#!/bin/sh' 'exec "$(dirname "$0")/fix-identity.sh"' \
      > /home/claudeuser/.git-hooks/post-checkout && \
    chmod +x /home/claudeuser/.git-hooks/fix-identity.sh \
             /home/claudeuser/.git-hooks/pre-commit \
             /home/claudeuser/.git-hooks/post-checkout

# Register the hooks dir globally for the user that runs git commands.
RUN HOME=/home/claudeuser git config --global core.hooksPath /home/claudeuser/.git-hooks

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


# Global skill: teaches the agent to use the pre-installed /opt/browser-driver
# toolkit instead of npm-installing playwright inside whatever project it's
# testing (which dirties that project's package.json/lock for no reason).
RUN mkdir -p /home/claudeuser/.claude/skills/browser-driver && \
    cat > /home/claudeuser/.claude/skills/browser-driver/SKILL.md << 'EOF'
---
name: browser-driver
description: Drive a local dev server with headless Chromium via the pre-installed Playwright toolkit at /opt/browser-driver, for use when chromium-cli isn't available. Use whenever verifying a web app end-to-end in the browser.
---

## Toolkit location
Playwright + Chromium are pre-installed at build time in `/opt/browser-driver`
(own package.json + node_modules), browser cached at `/opt/ms-playwright`
(`$PLAYWRIGHT_BROWSERS_PATH`). Never `npm install playwright` inside a
project repo for this -- the toolkit already has it, and doing so dirties
that project's package.json/lock for no reason.

## How to drive a page
1. Start the target project's dev server in the background; poll with curl
    until it responds -- don't sleep-guess.
2. Write a one-off driver script INTO the toolkit dir, e.g.
    `/opt/browser-driver/drive-<project>.mjs` -- importing `{ chromium }`
    from 'playwright' resolves fine there since node_modules sits alongside it.
3. `node /opt/browser-driver/drive-<project>.mjs`
4. Screenshot at each step. Check for errors via `page.on('console')` /
    `page.on('pageerror')` before declaring success.
5. Leave or delete the one-off script -- it's outside any project's git
    history either way.

## Skeleton
```js
import { chromium } from 'playwright'
const browser = await chromium.launch({ args: ['--no-sandbox'] })
const page = await (await browser.newContext()).newPage()
await page.goto('http://localhost:PORT/')
// ...interact, screenshot...
await browser.close()
```
EOF



# Wrapper script
RUN echo '#!/bin/bash\nclaude --dangerously-skip-permissions "$@"' > /usr/local/bin/c && \
    chmod +x /usr/local/bin/c

RUN chown -R claudeuser:claudeuser /home/claudeuser /opt/browser-driver /opt/ms-playwright

# Runs gh/git auth against AGENT_GITHUB_TOKEN on container start (the token
# only exists at runtime via agent.env, not at build time).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER claudeuser
WORKDIR /workspace

ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]