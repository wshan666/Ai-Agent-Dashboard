# API v1

Base URL: your Dashboard server, for example `http://127.0.0.1:3456`.

If authentication is enabled, use either:

- Basic Auth with `DASHBOARD_AUTH_USER` and `DASHBOARD_AUTH_PASSWORD`.
- Bearer token with `DASHBOARD_API_TOKEN`.

## Health

```http
GET /api/health
```

Returns service status and whether auth is enabled.

## List Agents

```http
GET /api/v1/agents
Authorization: Bearer <DASHBOARD_API_TOKEN>
```

Response:

```json
{
  "object": "list",
  "data": [
    {
      "id": "codex-cli",
      "name": "Codex CLI",
      "type": "cli",
      "hostGroup": "local",
      "status": "unknown",
      "engineLabel": "Codex CLI",
      "modelLabel": "Codex default model"
    }
  ]
}
```

## Run Agent

```http
POST /api/v1/runs
Authorization: Bearer <DASHBOARD_API_TOKEN>
Content-Type: application/json
```

Request:

```json
{
  "agent_id": "codex-cli",
  "input": "Summarize this requirement and propose next steps.",
  "topic": "customer-onboarding",
  "metadata": {
    "customer_id": "demo"
  }
}
```

Response:

```json
{
  "id": "run-uuid",
  "object": "run",
  "status": "completed",
  "agent_id": "codex-cli",
  "agent_name": "Codex CLI",
  "topic": "customer-onboarding",
  "output": "...",
  "error": null,
  "latency_ms": 1200,
  "created_at": "2026-05-12T00:00:00.000Z"
}
```

## Notes

`/api/v1/runs` is intentionally small for the first public integration surface. Future versions should add asynchronous jobs, callbacks/webhooks, usage metering, team/workspace IDs, and billing identifiers.
