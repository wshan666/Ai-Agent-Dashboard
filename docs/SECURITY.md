# Security Notes

This repo is intended to stay private.

Even in a private repo:

- Do not commit API keys, webhooks, SSH passwords, chat history, logs, backups, or generated artifacts.
- Use `Dashboard/config.example.json` and keep the real `Dashboard/config.json` local.
- Use `Dashboard/secrets.json` for local host passwords and keep it out of git.
- Rotate any credential that was ever stored in an earlier local snapshot or shared in chat.
- Treat Dashboard endpoints as trusted-admin endpoints. Several routes can execute commands, modify files, restore backups, or call external services.

Before exposing Dashboard outside a private LAN, add authentication, CSRF protection for mutating routes, upload limits/type validation, audit logging, and a reverse proxy with TLS.
