# Agent Adapters

Adapters define how Dashboard talks to an agent.

Current adapters:

- `cli`: local command on the Dashboard machine.
- `ssh`: remote command through a configured SSH host.
- `docker`: remote Docker container through SSH.
- `http`: JSON HTTP API.

## Discovery

```http
GET /api/v1/adapters
Authorization: Bearer <DASHBOARD_API_TOKEN>
```

## Config Validation

```http
GET /api/v1/config/validate
Authorization: Bearer <DASHBOARD_API_TOKEN>
```

The response contains `ok`, `errors`, `warnings`, `agentCount`, and known adapter IDs.

## HTTP Agent

Example `Dashboard/config.json` entry:

```json
{
  "id": "http-demo",
  "name": "HTTP Demo Agent",
  "type": "http",
  "adapter": "http",
  "endpoint": "https://example.com/agent/run",
  "method": "POST",
  "tokenEnv": "HTTP_DEMO_AGENT_TOKEN",
  "headers": {
    "Authorization": "Bearer ${HTTP_DEMO_AGENT_TOKEN}"
  },
  "requestTemplate": {
    "input": "{{prompt}}"
  },
  "responsePath": "output",
  "chatTimeout": 120000
}
```

Environment:

```powershell
$env:HTTP_DEMO_AGENT_TOKEN = "your-token"
```

Request sent to the remote service.

Note: `{{prompt}}` is the compiled Dashboard prompt, including system identity and relevant context. Use `/api/v1/runs` metadata if you need to track your original business object IDs.

```json
{
  "input": "compiled prompt from Dashboard"
}
```

Response mapping:

- If `responsePath` is set, Dashboard reads that dotted path, for example `data.answer`.
- Otherwise Dashboard tries `output`, `text`, `message`, OpenAI-style `choices[0].message.content`, then falls back to raw JSON.

## Adapter Contract

All adapters should eventually normalize into:

```json
{
  "ok": true,
  "stdout": "agent output",
  "stderr": ""
}
```

That keeps chat, workflows, and `/api/v1/runs` independent from provider-specific details.
