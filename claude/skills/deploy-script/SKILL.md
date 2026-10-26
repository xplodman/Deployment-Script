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

- **Never read, cat, grep, or print `required_scripts/credentials.sh`**, and never echo its variables. Secrets must not enter the conversation. Use the script instead.
- **Always run from the project root** (the script sources `required_scripts/` by relative path).
- **Never bypass `[y/N]` prompts** (no `yes |`, `echo y |`, heredocs). Your shell has no TTY, so prompted actions will cancel themselves — that's intended. Give the user the command to run in their own terminal. The `!` prefix also has no TTY. The exceptions are `--upload`/`--download` (use `--dry-run`/`--yes`), `--import-db` (use `--yes`), and `--download-mongo-db` (use `--yes`).
- Treat `production` as read-only unless the user explicitly asks for a change in this turn.

## Discover environments

```bash
bash deploy_rsync.sh --help     # prints available actions + environment names
```

## Read-only access (safe for you to run directly)

Run a one-off command on the server (starts in site directory, no TTY, exits):

```bash
bash deploy_rsync.sh --ssh <env> "ls -la"
bash deploy_rsync.sh --ssh <env> "tail -n 100 storage/logs/laravel.log"
bash deploy_rsync.sh --ssh <env> "git log --oneline -5"
```

Don't read the remote `.env` or config files that hold secrets. If you need a remote config value, ask the user.

Run a one-off SQL query (tab-separated output):

```bash
bash deploy_rsync.sh --db <env> "SHOW TABLES"
bash deploy_rsync.sh --db <env> "DESCRIBE users"
bash deploy_rsync.sh --db <env> "SELECT id, email, created_at FROM users ORDER BY id DESC LIMIT 20"
```

- Always use `LIMIT` on SELECTs against large tables.
- For writes (`UPDATE`/`DELETE`/`INSERT`/`ALTER`/`DROP`): show the exact query, get explicit user approval first (even on staging). On production, hand the command to the user instead of running it.
- Don't dump full rows of sensitive tables (passwords, tokens, PII) — select only needed columns.

With no command argument, `--ssh` and `--db` open interactive shells — those need a TTY so always pass a command from your Bash tool.

## Deploy flow (`--upload` / `--download`): you run it, the user approves in chat

When the user says "deploy" / "upload X to `<env>`" / "pull X from `<env>`":

1. **Dry run** (nothing transferred):
   ```bash
   bash deploy_rsync.sh --upload <env> --dry-run [--skip-ignore] [path...]
   ```
2. **Report the changes.** Read the itemized lines: `<f` = file sent (`+++++++++` = new), `>f` = file received, `cd+++` = new dir, `*deleting` = file removed on destination. List by category, call out any deletions, give totals. If nothing would transfer, say it's in sync and stop.
3. **Ask** "Deploy these changes to `<env>`?" and wait. Only an explicit yes in the user's next message counts. Don't carry approval to a later deploy or treat "deploy" in the original request as the yes.
4. **Deploy** (only if nothing changed locally since the dry run; if it did, dry-run again and re-ask):
   ```bash
   bash deploy_rsync.sh --upload <env> --yes [--skip-ignore] [path...]
   ```
   Report the result including any post-upload command output (`special_commands_after_upload_to_environment`).

Same flow for `--download`. For `production`, always scope to specific paths unless the user explicitly asks for a full-site sync. If the dry run shows deletions not mentioned by the user, call them out before asking.

**Flags for `--upload`/`--download`** (anywhere after `env`, combinable):

| Flag | Effect |
|---|---|
| `--dry-run` | Preview only — shows changes, transfers nothing, then stops |
| `--yes` | Skip the confirmation prompt (use after user approves in chat) |
| `--skip-ignore` | Bypass `rsync.ignore` exclusions — transfers all files including normally-excluded ones |
| `path...` | One or more relative paths to scope the sync to; `--del` only removes stale files inside those paths |

## Database actions

`--download-db <env>` is safe to run yourself — no prompt, dumps the env DB to `local_db_dir/<db>.sql.gz`.
Dumps larger than `db_split_threshold` (default 60 MB, configurable in credentials.sh) are automatically split into `.sql.gz.part-*` files and auto-merged on import.

To work on real data locally:
1. `bash deploy_rsync.sh --download-db <env>` (you can run this)
2. User runs `! bash deploy_rsync.sh --import-db <env>` (prompts; or pass `--yes` to skip)
3. Query the local DB

## Other prompted/destructive actions (give these to the user to run)

| Action | Effect |
|---|---|
| `--upload <env> [flags] [path...]` | rsync local → env (dry run + confirm, `--del` in scope). Prefer the deploy flow above |
| `--download <env> [flags] [path...]` | rsync env → local. Prefer the deploy flow above |
| `--download-db <env>` | Dump env MySQL DB → `local_db_dir/<db>.sql.gz` (no prompt) |
| `--import-db <env> [--yes]` | Drop + recreate local DB from downloaded dump; runs `special_commands_after_import_db_locally` SQL after |
| `--upload-db <env>` | **Replace** env DB with local DB (prompts) |
| `--clone-db <src> <dest>` | **Replace** dest env DB with src env DB, env-to-env direct (prompts) |
| `--download-mongo-db <env> [--yes]` | Drop local MongoDB and clone env's into it; requires `<env>_mongo_uri/db` + `local_mongo_uri/db` set in credentials |
