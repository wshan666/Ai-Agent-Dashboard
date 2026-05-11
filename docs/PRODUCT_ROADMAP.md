# Product Roadmap

Goal: turn the current private multi-agent workspace into a deployable product that other teams can buy and operate.

## Positioning

AI Agent Dashboard is a control plane for multiple local, remote, and API-backed agents.

Core value:

- One place to register agents and see status.
- One place to run agent tasks through a stable API.
- Visible collaboration: chat, roundtable, workflow messages, large-screen status.
- Operational memory: history, lessons, artifacts, backups.

## Sellable MVP

Version `0.2` should be usable by another technical customer on their own machine or LAN.

Required:

- Auth-protected Dashboard.
- Clean install docs.
- Config templates without local secrets.
- Stable API v1 for listing agents and running one agent.
- Agent adapter model for CLI, SSH, Docker, and HTTP providers.
- Basic audit log for API runs.
- Exportable artifacts.

## Version Plan

### 0.2 Private Deploy

- Optional Basic Auth and API token.
- `/api/health`, `/api/v1/agents`, `/api/v1/runs`.
- Docs for API, security, and local deployment.
- iOS companion app points to configurable server.

### 0.3 Team Use

- SQLite/Postgres storage instead of JSON files.
- User/team/workspace model.
- Role-based access control.
- Async run queue with cancel/retry.
- Webhook callback after run completion.
- Agent adapter interface documented as a plugin contract.

### 0.4 Commercial Pilot

- License key or subscription check.
- Usage metering: runs, tokens/estimated cost, duration.
- Admin page for customers to add agents safely.
- Docker Compose deployment.
- Upgrade/migration scripts.
- Customer-facing onboarding guide.

### 1.0 Product

- Multi-tenant SaaS or self-hosted license edition.
- Billing integration.
- Marketplace-style agent templates.
- Observability dashboard.
- Backup/restore policy.
- Support bundle export for troubleshooting.

## Pricing Ideas

- Self-hosted personal/pro: one-time setup fee plus annual updates.
- Team self-hosted: per-seat or per-agent license.
- Managed SaaS: monthly workspace fee plus usage-based run volume.
- Custom enterprise: private deployment, integrations, support SLA.

## Immediate Engineering Priorities

1. Replace JSON persistence with a database.
2. Convert agent execution into adapters with a strict interface.
3. Add async job queue and run table.
4. Add audit logs and usage accounting.
5. Package with Docker Compose.
