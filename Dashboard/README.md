# Dashboard

Node.js service for the AI Agent Dashboard.

## Run

```powershell
Copy-Item config.example.json config.json
npm install
npm start
```

For a protected deployment:

```powershell
$env:DASHBOARD_AUTH_USER = "admin"
$env:DASHBOARD_AUTH_PASSWORD = "change-me"
$env:DASHBOARD_API_TOKEN = "change-me-api-token"
npm start
```

Optional one-click launcher on Windows:

```powershell
.\one-click-start.bat
```

## Important Files

- `server.js`: Express API, agent execution, workflow orchestration, SSE stream, backups.
- `public/index.html`: single-page web UI.
- `.env.example`: environment variables for deploy-time configuration.
- `config.example.json`: safe starter config.
- `secrets.example.json`: shape of local host password storage.
- `scripts/`: local CLI wrappers and optional helper scripts.

## Integration API

- `GET /api/health`
- `GET /api/v1/agents`
- `POST /api/v1/runs`

See `../docs/API.md`.

## Private Runtime Files

The real `config.json`, `secrets.json`, logs, chat history, generated outputs, and backups are intentionally ignored by git.

## Notes

The Dashboard can execute local commands and remote SSH commands depending on `config.json`. Keep it on a trusted network and put authentication/reverse-proxy controls in front of it before exposing it beyond a private LAN.
