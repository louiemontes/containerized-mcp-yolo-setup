#!/usr/bin/env node
// Credential-isolating MCP gateway.
// This container holds the secrets. The agent container only gets a URL.
// The agent can INVOKE these tools but can never READ the token --
import express from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from "zod";

const GITHUB_TOKEN = process.env.AGENT_GITHUB_TOKEN;
if (!GITHUB_TOKEN) {
  console.error(
    "WARNING: AGENT_GITHUB_TOKEN is empty -- gateway will boot but tools will refuse. Check .env",
  );
}

function buildServer() {
  const server = new McpServer({ name: "gh-gateway", version: "1.0.0" });

  // Example tool: deliberately narrow and read-only.
  // Add more tools here; keep each one as small as you can live with.
  server.registerTool(
    "list_my_repos",
    {
      description: "List the authenticated user's GitHub repos (read-only)",
      inputSchema: {
        limit: z.number().int().min(1).max(30).default(10),
      },
    },
    async ({ limit }) => {
      if (!GITHUB_TOKEN) {
        return {
          content: [
            { type: "text", text: "Gateway has no AGENT_GITHUB_TOKEN set." },
          ],
        };
      }
      const resp = await fetch(
        `https://api.github.com/user/repos?per_page=${limit}&sort=updated`,
        {
          headers: {
            Authorization: `Bearer ${GITHUB_TOKEN}`,
            Accept: "application/vnd.github+json",
            "User-Agent": "mcp-gateway",
          },
        },
      );
      if (!resp.ok) {
        return {
          content: [{ type: "text", text: `GitHub API error: ${resp.status}` }],
        };
      }
      const repos = await resp.json();
      const lines = repos.map(
        (r) => `${r.full_name}${r.private ? " (private)" : ""}`,
      );
      return {
        content: [{ type: "text", text: lines.join("\n") || "(no repos)" }],
      };
    },
  );

  return server;
}

const app = express();
app.use(express.json());

// Stateless streamable-HTTP: fresh server+transport per request.
app.post("/mcp", async (req, res) => {
  const server = buildServer();
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
  });
  res.on("close", () => {
    transport.close();
    server.close();
  });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
});

app.get("/healthz", (_req, res) => res.send("ok"));

app.listen(8000, () => console.log("mcp-gateway listening on :8000"));
