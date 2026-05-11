# AI Agent Dashboard

Private multi-agent collaboration workspace.

This repository contains two parts:

- `Dashboard/`: Node.js + Express web dashboard for agent status, chat, roundtable, workflow execution, backups, and large-screen visualization.
- `AgentApp/`: iOS companion app built with SwiftUI and WKWebView/native screens. It connects to a running Dashboard server.

Productization docs:

- `docs/API.md`: stable integration API v1.
- `docs/SECURITY.md`: security notes before deployment.
- `docs/PRODUCT_ROADMAP.md`: path from private deploy to commercial product.

## Quick Start

```powershell
cd Dashboard
Copy-Item config.example.json config.json
npm install
npm start
```

Open `http://127.0.0.1:3456`.

For LAN/mobile access, set the server URL in the iOS app profile tab. The Dashboard also supports:

- `DASHBOARD_PUBLIC_BASE_URL`: externally reachable base URL, for example `http://192.168.1.100:3456`.
- `DASHBOARD_SHARED_OUT`: directory used for generated files and artifacts.
- `NETEASE_API_BASE`: optional local Netease API service for music search/lyrics.
- `DASHSCOPE_API_KEY`: optional Qwen vision script key.
- `DEEPSEEK_API_KEY`: optional DeepSeek script key.
- `DASHBOARD_AUTH_USER` / `DASHBOARD_AUTH_PASSWORD`: optional Basic Auth.
- `DASHBOARD_API_TOKEN`: optional Bearer/API token for API clients.

Health check:

```powershell
Invoke-RestMethod http://127.0.0.1:3456/api/health
```

Generic API:

```powershell
$headers = @{ Authorization = "Bearer $env:DASHBOARD_API_TOKEN" }
Invoke-RestMethod http://127.0.0.1:3456/api/v1/agents -Headers $headers
```

Create an asynchronous run:

```powershell
$body = @{
  agent_id = "codex-cli"
  input = "Draft a short launch checklist."
  async = $true
} | ConvertTo-Json
Invoke-RestMethod http://127.0.0.1:3456/api/v1/runs -Headers $headers -Method Post -ContentType "application/json" -Body $body
```

## Local Configuration

Do not commit runtime secrets or local state. Keep these files local:

- `Dashboard/config.json`
- `Dashboard/secrets.json`
- `Dashboard/chat_log.json`
- `Dashboard/agent_lessons.json`
- `Dashboard/dev_progress.json`
- `Dashboard/backups/`
- `Dashboard/output/`

Use `Dashboard/config.example.json` and `Dashboard/secrets.example.json` as templates.

## iOS Build

The existing GitHub Action builds `AgentApp` with XcodeGen on macOS and uploads an unsigned IPA artifact. For local development:

```bash
cd AgentApp
xcodegen generate
open AgentApp.xcodeproj
```

## Current Status

This is still an active prototype. The repo is structured for private collaboration, not public distribution. Before any public release, add authentication, audit dangerous endpoints, and rotate all credentials used in earlier local experiments.
