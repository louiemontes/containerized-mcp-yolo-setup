#!/bin/bash
set -e

# AGENT_GITHUB_TOKEN only exists at runtime (agent.env), not at image build
# time, so gh/git auth has to be wired up here rather than in the Dockerfile.
# `gh auth setup-git` registers gh as git's credential helper for
# github.com, giving both git-over-HTTPS and the gh CLI itself the token.
if [ -n "$AGENT_GITHUB_TOKEN" ]; then
  (echo "$AGENT_GITHUB_TOKEN" | gh auth login --hostname github.com --with-token && gh auth setup-git) \
    || echo "WARNING: gh auth login failed -- check AGENT_GITHUB_TOKEN in agent.env" >&2
else
  echo "WARNING: AGENT_GITHUB_TOKEN is empty -- git/gh GitHub auth will not work" >&2
fi

exec "$@"
