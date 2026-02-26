# Odoo Local Dev Toolkit

> 🌐 [العربية](README.ar.md)

Mirror your **Odoo.sh project** to a local Docker environment in one command.

> All configuration lives in a single `.env` file — copy it and you're done.

---

## ⚡ Quick Start

```bash
# 1. Configure (once)
cp .env.example .env
#    → fill in SSH_USER, SSH_HOST, USER_REPO, USER_BRANCH

# 2. Sync + start
make setup

# 3. Restore a production backup (optional)
make sync-db BACKUP=/path/to/backup.zip
```

Odoo → **http://localhost:8070**

---

## 🔑 `.env` — the only file you edit

| Variable | Example | Notes |
|---|---|---|
| `SSH_USER` | `12345678` | Odoo.sh numeric user ID |
| `SSH_HOST` | `myproject.odoo.com` | Odoo.sh project domain |
| `ODOO_VERSION` | `16.0` | Must match your Odoo.sh version |
| `ODOO_PORT` | `8070` | Local port for Odoo |
| `USER_REPO` | `git@github.com:org/repo.git` | Your custom modules repo |
| `USER_BRANCH` | `main` | Branch to track locally |
| `ADMIN_PASSWD` | `admin` | Odoo master password |
| `LOCAL_DB_NAME` | `odoo` | Local PostgreSQL database |
| `SYNC_ODOO_CORE` | `false` | Sync Odoo core source (~1.5 GB) |

---

## 🛠️ All Commands

```bash
make setup                          # Rsync from Odoo.sh + start Docker
make sync-db BACKUP=backup.zip      # Restore backup (wipes local DB)

make up / down / stop / restart     # Container lifecycle
make reset-db                       # ⚠️  Wipe all data + fresh start

make logs                           # Follow Odoo logs
make shell                          # Bash inside Odoo container
make psql                           # PostgreSQL prompt
make update MODULE=my_module        # Update a specific module
make open                           # Open browser

make user-status                    # git status of custom modules
make user-push MSG='fix: ...'       # Commit + push custom modules
make user-pull                      # Pull latest from remote

make test                           # ✅ Full environment health check
make check-env                      # Print current config
```

---

## 🏗️ How It Works

```
your-project/
├── .env                    ← single source of truth (gitignored)
├── .env.example            ← template (copy this)
├── Makefile                ← all commands
├── setup-odoo-local.sh     ← rsync + generate configs + start Docker
├── sync-db.sh              ← restore backup + neutralize DB
└── odoo-local/             ← created on first run
    ├── docker-compose.yml  ← generated (do not edit)
    ├── odoo.conf           ← generated (do not edit)
    ├── enterprise/         ← synced, gitignored
    ├── themes/             ← synced, gitignored
    └── user/               ← your modules repo (.git preserved)
```

**Two repos, one workflow:**
- This toolkit repo → push your scripts/config
- `odoo-local/user/` → your Odoo modules (`make user-push`)

---

## �️ What `sync-db` Does Automatically

Restores the backup then neutralizes it for local dev:
- Disables outgoing mail, cron jobs, and payment providers
- Resets `web.base.url` to `http://localhost:PORT`
- Removes cloud expiry locks, IAP tokens, push notification keys

---

## � Dev Mode (pre-configured)

```ini
workers = 0        ; single-threaded → pdb/breakpoints work
log_level = debug  ; verbose output
dev_mode = reload,xml  ; auto-reload on file change
```

---

## 🔁 Reuse for Another Project

```bash
cp setup-odoo-local.sh sync-db.sh .env.example .gitignore Makefile /new-project/
cd /new-project && cp .env.example .env
# edit .env → make setup
```

---

## Prerequisites

`docker` + `docker compose v2` · `rsync` · `unzip` · SSH key on Odoo.sh

---

## License

MIT
