#!/usr/bin/env node
// Credential-isolating MCP gateway.
// This container holds the secrets. The agent container only gets a URL.
// The agent can INVOKE these tools but can never READ the token --
//
// GitHub access is handled separately: the agent container talks to
// GitHub directly through the squid proxy using AGENT_GITHUB_TOKEN (a
// fine-grained PAT). Use this gateway for any *other* third-party API
// where you'd rather keep the credential out of the agent entirely.
import express from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from "zod";

const EXAMPLE_API_KEY = process.env.EXAMPLE_API_KEY;
if (!EXAMPLE_API_KEY) {
  console.error(
    "WARNING: EXAMPLE_API_KEY is empty -- gateway will boot but tools will refuse. Check gateway.env",
  );
}

function buildServer() {
  const server = new McpServer({ name: "example-gateway", version: "1.0.0" });

  // Placeholder tool: swap "api.example-widgets.com" for a real third-party
  // API. Add more tools here; keep each one as small as you can live with.
  server.registerTool(
    "get_widget_status",
    {
      description: "Look up a widget's status from the example third-party API (read-only)",
      inputSchema: {
        widgetId: z.string().min(1),
      },
    },
    async ({ widgetId }) => {
      if (!EXAMPLE_API_KEY) {
        return {
          content: [
            { type: "text", text: "Gateway has no EXAMPLE_API_KEY set." },
          ],
        };
      }
      const resp = await fetch(
        `https://api.example-widgets.com/v1/widgets/${encodeURIComponent(widgetId)}`,
        {
          headers: {
            Authorization: `Bearer ${EXAMPLE_API_KEY}`,
            Accept: "application/json",
            "User-Agent": "mcp-gateway",
          },
        },
      );
      if (!resp.ok) {
        return {
          content: [
            { type: "text", text: `Example API error: ${resp.status}` },
          ],
        };
      }
      const widget = await resp.json();
      return {
        content: [{ type: "text", text: JSON.stringify(widget) }],
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
