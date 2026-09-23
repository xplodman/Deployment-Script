---
name: deploy-script
description: How to reach a project's remote environments (production, staging, ...) — run commands on the server, query its MySQL database, read logs, sync files, and pull/push databases — using the project's deploy_rsync.sh. Use whenever the user asks about a server, environment, remote logs, remote config, or production/staging data in a project that has deploy_rsync.sh at its root.
---

# Project deploy script (deploy_rsync.sh)

Projects using this have `deploy_rsync.sh` and `required_scripts/` at their root.
All connection details (SSH host/key/password, DB host/user/password) live in
`required_scripts/credentials.sh`. The script handles auth, so you never need
the secrets yourself.

## Hard rules

- **Never read, cat, grep, or print `required_scripts/credentials.sh`**, and never
  echo its variables. Secrets must not enter the conversation. Use the script instead.
- **Always run from the project root** (the script sources `required_scripts/` by relative path).
- **Never bypass the script's `[y/N]` confirmation prompts** (no `yes |`, `echo y |`,
  heredocs). Your shell has no TTY, so prompted actions will cancel themselves. That is
  intended. For those, give the user the command to run with the `!` prefix.
- Treat `production` as read-only unless the user explicitly asks for a change in this turn.

## Discover environments

```bash
bash deploy_rsync.sh --help     # prints available actions + environment names
```

## Read-only access (safe for you to run directly)

Run a one-off command on the server. It starts in the site directory, runs with no
TTY, then exits:

```bash
bash deploy_rsync.sh --ssh <env> "ls -la"
bash deploy_rsync.sh --ssh <env> "tail -n 100 storage/logs/laravel.log"
bash deploy_rsync.sh --ssh <env> "git log --oneline -5"
```

Don't read the remote `.env` or other config files that hold secrets. If you need a
remote config value, ask the user.

Run a one-off SQL query against the env's database. The output is tab-separated:

```bash
bash deploy_rsync.sh --db <env> "SHOW TABLES"
bash deploy_rsync.sh --db <env> "DESCRIBE users"
bash deploy_rsync.sh --db <env> "SELECT id, email, created_at FROM users ORDER BY id DESC LIMIT 20"
```

- Always use `LIMIT` on SELECTs against large tables.
- For writes (`UPDATE`/`DELETE`/`INSERT`/`ALTER`/`DROP`), show the exact query and get
  explicit user approval first, even on staging. On production, prefer to hand the user
  the command instead of running it.
- Don't dump full rows of sensitive tables (passwords, tokens, personal data) into the chat.
  Select only the columns you need.

With no command argument, `--ssh` and `--db` open interactive shells. Those don't work
from your Bash tool, so always pass a command.

## Actions that prompt, or change things (the user runs these)

Give the user these to run as `! bash deploy_rsync.sh ...`:

| Action | Effect |
|---|---|
| `--upload <env> [path...]` | rsync local → env (dry run + confirm, deletes stale files in scope) |
| `--download <env> [path...]` | rsync env → local (dry run + confirm) |
| `--download-db <env>` | dump env DB into `local_db_dir` as `<db>.sql.gz` (no prompt; safe to run yourself if asked) |
| `--import-db <env>` | drop + recreate the local DB from the downloaded dump (prompts) |
| `--upload-db <env>` | **replace** the env DB with the local DB (prompts) |
| `--clone-db <src> <dest>` | **replace** the dest DB with the src DB (prompts) |
| `--download-mongo-db <env>` | drop the local Mongo DB and clone the env's into it (prompts) |

To work on real data locally, the usual flow is: `--download-db <env>`, then the user runs
`! bash deploy_rsync.sh --import-db <env>`, then you query the local DB.
