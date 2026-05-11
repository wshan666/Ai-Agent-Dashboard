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

## List Adapters

```http
GET /api/v1/adapters
Authorization: Bearer <DASHBOARD_API_TOKEN>
```

Returns supported adapter types and required fields.

## Validate Config

```http
GET /api/v1/config/validate
Authorization: Bearer <DASHBOARD_API_TOKEN>
```

Use this before selling/deploying a customer instance. It catches duplicate agent IDs, missing fields, unsupported adapters, and missing host groups.

## Create Run

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
  "async": true,
  "metadata": {
    "customer_id": "demo"
  }
}
```

When `async` is `true`, the API returns immediately with HTTP `202`:

```json
{
  "id": "run-uuid",
  "object": "run",
  "status": "queued",
  "agent_id": "codex-cli",
  "agent_name": "Codex CLI",
  "topic": "customer-onboarding",
  "output": "",
  "error": null,
  "metadata": {
    "customer_id": "demo"
  },
  "created_at": "2026-05-12T00:00:00.000Z"
}
```

When `async` is omitted or false, the API waits for the agent and returns the final run:

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

## Create Collaboration

```http
POST /api/v1/collaborations
Authorization: Bearer <DASHBOARD_API_TOKEN>
Content-Type: application/json
```

Request:

```json
{
  "agent_ids": ["research-http", "writer-http"],
  "input": "Create a deployment plan for a customer agent workspace.",
  "topic": "customer-deploy",
  "mode": "parallel",
  "summarizer_agent_id": "writer-http",
  "async": true,
  "metadata": {
    "workspace_id": "demo"
  }
}
```

Fields:

- `agent_ids`: required array with at least two enabled agents.
- `input` or `message`: required user task.
- `mode`: `parallel` or `sequential`; defaults to `parallel`.
- `summarizer_agent_id`: optional enabled agent that receives all agent outputs and produces the final summary.
- `async`: defaults to `true` for collaborations.

Queued response:

```json
{
  "id": "run-uuid",
  "object": "run",
  "kind": "collaboration",
  "status": "queued",
  "agent_ids": ["research-http", "writer-http"],
  "topic": "customer-deploy",
  "output": "",
  "error": null,
  "created_at": "2026-05-12T00:00:00.000Z"
}
```

Completed runs include agent-level responses:

```json
{
  "id": "run-uuid",
  "object": "run",
  "kind": "collaboration",
  "status": "completed",
  "responses": [
    {
      "agent_id": "research-http",
      "agent_name": "Research Agent",
      "status": "completed",
      "output": "..."
    }
  ],
  "output": "..."
}
```

## Get Run

```http
GET /api/v1/runs/{run_id}
Authorization: Bearer <DASHBOARD_API_TOKEN>
```

Use `?include_input=1` to include the original input. By default only a short `input_preview` is returned.

## List Runs

```http
GET /api/v1/runs?limit=50&status=completed&agent_id=codex-cli
Authorization: Bearer <DASHBOARD_API_TOKEN>
```

Filters are optional.

## Cancel Run

```http
POST /api/v1/runs/{run_id}/cancel
Authorization: Bearer <DASHBOARD_API_TOKEN>
```

Queued runs are cancelled immediately. Running CLI/SSH work cannot always be interrupted safely yet, so running runs are marked with `cancellation_requested`.

## Notes

Runs and collaborations are stored in `DASHBOARD_SHARED_OUT/api_runs.json`; audit events are appended to `DASHBOARD_SHARED_OUT/api_audit.jsonl`.

Future versions should add callbacks/webhooks, usage metering, team/workspace IDs, and billing identifiers.
