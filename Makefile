# ══════════════════════════════════════════════════════════════════
#  Odoo Local Dev — Makefile
#  All config comes from .env (single source of truth)
#  Run `make help` to see all available commands
# ══════════════════════════════════════════════════════════════════

# ── Load .env if it exists ────────────────────────────────────────
-include .env
export

# ── Defaults (override in .env) ───────────────────────────────────
PROJECT_DIR  ?= odoo-local
ODOO_VERSION ?= 16.0
ODOO_PORT    ?= 8070
LOCAL_DB_USER  ?= odoo
LOCAL_DB_NAME  ?= odoo
SSH_USER     ?=
SSH_HOST     ?=
USER_REPO    ?=
USER_BRANCH  ?=

# ── User module repo path ────────────────────────────────────────
# odoo-local/user/ is your own git repo (separate from this sky repo).
# It keeps its .git after rsync so you can push modules independently.
USER_DIR     := $(PROJECT_DIR)/user

# ── Internal variables ────────────────────────────────────────────
# NOTE: Do NOT name this COMPOSE_FILE — that is a reserved Docker Compose env var.
# Using COMPOSE_YML to avoid the collision (global `export` would break child docker compose calls).
COMPOSE_YML  := $(PROJECT_DIR)/docker-compose.yml
COMPOSE      := docker compose -f $(COMPOSE_YML) --project-directory $(PROJECT_DIR)
BOLD         := \033[1m
GREEN        := \033[0;32m
YELLOW       := \033[1;33m
RED          := \033[0;31m
NC           := \033[0m

# Default target
.DEFAULT_GOAL := help

# Prevent make from treating targets as files
.PHONY: help setup sync-db up down restart stop logs logs-db \
        shell psql update reset-db test check-env open \
        user-status user-log user-diff user-push user-pull

# ══════════════════════════════════════════════════════════════════
#  HELP
# ══════════════════════════════════════════════════════════════════

help:
	@echo ""
	@echo "$(BOLD)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BOLD)  Odoo Local Dev — Available Commands$(NC)"
	@echo "$(BOLD)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(BOLD)  SETUP$(NC)"
	@echo "    make setup              Sync source from Odoo.sh + start containers"
	@echo "    make sync-db BACKUP=.. Restore a backup zip (wipes local DB)"
	@echo ""
	@echo "$(BOLD)  CONTAINERS$(NC)"
	@echo "    make up                 Start all containers (detached)"
	@echo "    make down               Stop and remove containers"
	@echo "    make stop               Stop containers (keep data)"
	@echo "    make restart            Restart the Odoo container"
	@echo "    make reset-db           ⚠️  Wipe ALL data and restart fresh"
	@echo ""
	@echo "$(BOLD)  DEVELOPMENT$(NC)"
	@echo "    make logs               Follow Odoo logs (Ctrl+C to exit)"
	@echo "    make logs-db            Follow PostgreSQL logs"
	@echo "    make shell              Open bash shell inside Odoo container"
	@echo "    make psql               Open PostgreSQL prompt"
	@echo "    make update MODULE=..   Update a specific Odoo module"
	@echo "    make open               Open Odoo in the browser"
	@echo ""
	@echo "$(BOLD)  DIAGNOSTICS$(NC)"
	@echo "    make test               Check that everything is configured correctly"
	@echo "    make check-env          Show current .env configuration"
	@echo ""
	@echo "$(BOLD)  USER REPO  (odoo-local/user/ — your custom modules)$(NC)"
	@echo "    make user-status        git status of your custom modules repo"
	@echo "    make user-log           git log (last 10 commits)"
	@echo "    make user-diff          git diff (unstaged changes)"
	@echo "    make user-pull          git pull latest from remote"
	@echo "    make user-push          git add -A + commit + push"
	@echo ""
	@echo "$(BOLD)  EXAMPLES$(NC)"
	@echo "    make sync-db BACKUP=~/Downloads/backup.zip"
	@echo "    make update MODULE=sale"
	@echo "    make user-push MSG='fix: barcode column display'"
	@echo ""

# ══════════════════════════════════════════════════════════════════
#  SETUP
# ══════════════════════════════════════════════════════════════════

setup: _require-env
	@echo "$(BOLD)▶  Running full setup...$(NC)"
	@bash setup-odoo-local.sh

sync-db: _require-env _require-compose
	@if [ -z "$(BACKUP)" ]; then \
		echo "$(RED)[✘]$(NC) Missing BACKUP argument."; \
		echo "    Usage: make sync-db BACKUP=/path/to/backup.zip"; \
		exit 1; \
	fi
	@echo "$(BOLD)▶  Restoring database from: $(BACKUP)$(NC)"
	@bash sync-db.sh "$(BACKUP)"

# ══════════════════════════════════════════════════════════════════
#  CONTAINER LIFECYCLE
# ══════════════════════════════════════════════════════════════════

up: _require-compose
	@echo "$(BOLD)▶  Starting containers...$(NC)"
	@$(COMPOSE) up -d
	@echo "$(GREEN)[✔]$(NC) Odoo running at http://localhost:$(ODOO_PORT)"

down: _require-compose
	@echo "$(BOLD)▶  Stopping and removing containers...$(NC)"
	@$(COMPOSE) down

stop: _require-compose
	@echo "$(BOLD)▶  Stopping containers (data preserved)...$(NC)"
	@$(COMPOSE) stop

restart: _require-compose
	@echo "$(BOLD)▶  Restarting Odoo...$(NC)"
	@$(COMPOSE) restart odoo
	@echo "$(GREEN)[✔]$(NC) Odoo restarted — http://localhost:$(ODOO_PORT)"

reset-db: _require-compose
	@echo "$(RED)$(BOLD)[⚠] WARNING: This will WIPE all local data (DB + filestore)!$(NC)"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted." && exit 1)
	@$(COMPOSE) down -v
	@$(COMPOSE) up -d
	@echo "$(GREEN)[✔]$(NC) Fresh stack started — http://localhost:$(ODOO_PORT)"

# ══════════════════════════════════════════════════════════════════
#  DEVELOPMENT UTILITIES
# ══════════════════════════════════════════════════════════════════

logs: _require-compose
	@$(COMPOSE) logs -f --tail=100 odoo

logs-db: _require-compose
	@$(COMPOSE) logs -f --tail=50 db

shell: _require-compose
	@echo "$(BOLD)▶  Opening shell in Odoo container...$(NC)"
	@$(COMPOSE) exec odoo bash

psql: _require-compose
	@echo "$(BOLD)▶  Connecting to PostgreSQL (db: $(LOCAL_DB_NAME))...$(NC)"
	@$(COMPOSE) exec db psql -U $(LOCAL_DB_USER) $(LOCAL_DB_NAME)

update: _require-compose
	@if [ -z "$(MODULE)" ]; then \
		echo "$(RED)[✘]$(NC) Missing MODULE argument."; \
		echo "    Usage: make update MODULE=my_module"; \
		exit 1; \
	fi
	@echo "$(BOLD)▶  Updating module: $(MODULE)$(NC)"
	@$(COMPOSE) exec odoo odoo -u $(MODULE) -d $(LOCAL_DB_NAME) --stop-after-init
	@echo "$(GREEN)[✔]$(NC) Module '$(MODULE)' updated"

open:
	@echo "$(BOLD)▶  Opening http://localhost:$(ODOO_PORT) ...$(NC)"
	@xdg-open http://localhost:$(ODOO_PORT) 2>/dev/null || \
	 open http://localhost:$(ODOO_PORT) 2>/dev/null || \
	 echo "$(YELLOW)[!]$(NC) Could not auto-open browser. Go to: http://localhost:$(ODOO_PORT)"

# ══════════════════════════════════════════════════════════════════
#  DIAGNOSTICS
# ══════════════════════════════════════════════════════════════════

test:
	@echo ""
	@echo "$(BOLD)━━━ Environment Test ━━━$(NC)"
	@echo ""
	@# ── .env ──────────────────────────────────────────────────────
	@if [ -f .env ]; then \
		echo "$(GREEN)[✔]$(NC) .env file found"; \
	else \
		echo "$(RED)[✘]$(NC) .env not found — run: cp .env.example .env"; \
		exit 1; \
	fi
	@# ── SSH vars ──────────────────────────────────────────────────
	@if [ -z "$(SSH_USER)" ] || [ -z "$(SSH_HOST)" ]; then \
		echo "$(RED)[✘]$(NC) SSH_USER or SSH_HOST not set in .env"; \
	else \
		echo "$(GREEN)[✔]$(NC) SSH target: $(SSH_USER)@$(SSH_HOST)"; \
	fi
	@# ── Dependencies ──────────────────────────────────────────────
	@command -v rsync  >/dev/null 2>&1 && echo "$(GREEN)[✔]$(NC) rsync found"        || echo "$(RED)[✘]$(NC) rsync not found — apt install rsync"
	@command -v unzip  >/dev/null 2>&1 && echo "$(GREEN)[✔]$(NC) unzip found"        || echo "$(RED)[✘]$(NC) unzip not found — apt install unzip"
	@command -v docker >/dev/null 2>&1 && echo "$(GREEN)[✔]$(NC) docker found"       || echo "$(RED)[✘]$(NC) docker not found"
	@docker compose version >/dev/null 2>&1 && echo "$(GREEN)[✔]$(NC) docker compose v2 found" || echo "$(RED)[✘]$(NC) docker compose v2 not found"
	@# ── compose file ──────────────────────────────────────────────
	@if [ -f "$(COMPOSE_YML)" ]; then \
		echo "$(GREEN)[✔]$(NC) $(COMPOSE_YML) exists"; \
	else \
		echo "$(YELLOW)[!]$(NC) $(COMPOSE_YML) not found — run: make setup"; \
	fi
	@# ── containers ────────────────────────────────────────────────
	@if [ -f "$(COMPOSE_YML)" ]; then \
		DB_STATUS=$$($(COMPOSE) ps -q db 2>/dev/null | head -1); \
		ODOO_STATUS=$$($(COMPOSE) ps -q odoo 2>/dev/null | head -1); \
		if [ -n "$$DB_STATUS" ]; then \
			echo "$(GREEN)[✔]$(NC) PostgreSQL container: running"; \
		else \
			echo "$(RED)[✘]$(NC) PostgreSQL container: not running — run: make up"; \
		fi; \
		if [ -n "$$ODOO_STATUS" ]; then \
			echo "$(GREEN)[✔]$(NC) Odoo container: running"; \
		else \
			echo "$(RED)[✘]$(NC) Odoo container: not running — run: make up"; \
		fi; \
	fi
	@# ── HTTP check ────────────────────────────────────────────────
	@if curl -s -o /dev/null -w "%{http_code}" http://localhost:$(ODOO_PORT)/web/health 2>/dev/null | grep -q "200"; then \
		echo "$(GREEN)[✔]$(NC) Odoo HTTP health check: OK (http://localhost:$(ODOO_PORT))"; \
	else \
		echo "$(YELLOW)[!]$(NC) Odoo not responding on port $(ODOO_PORT) (may still be starting)"; \
	fi
	@# ── SSH connectivity ──────────────────────────────────────────
	@if [ -n "$(SSH_USER)" ] && [ -n "$(SSH_HOST)" ]; then \
		if ssh -o ConnectTimeout=5 -o BatchMode=yes $(SSH_USER)@$(SSH_HOST) "echo ok" >/dev/null 2>&1; then \
			echo "$(GREEN)[✔]$(NC) SSH to $(SSH_HOST): OK"; \
		else \
			echo "$(YELLOW)[!]$(NC) SSH to $(SSH_HOST): failed (check SSH key in Odoo.sh settings)"; \
		fi; \
	fi
	@echo ""
	@echo "$(GREEN)$(BOLD)━━━ Test complete ━━━$(NC)"
	@echo ""

check-env:
	@echo ""
	@echo "$(BOLD)━━━ Current Configuration (.env) ━━━$(NC)"
	@echo ""
	@echo "  ODOO_VERSION  = $(ODOO_VERSION)"
	@echo "  PROJECT_DIR   = $(PROJECT_DIR)"
	@echo "  ODOO_PORT     = $(ODOO_PORT)"
	@echo "  SSH_USER      = $(SSH_USER)"
	@echo "  SSH_HOST      = $(SSH_HOST)"
	@echo "  REMOTE_SRC    = $(REMOTE_SRC)"
	@echo "  SYNC_ODOO_CORE= $(SYNC_ODOO_CORE)"
	@echo "  LOCAL_DB_USER = $(LOCAL_DB_USER)"
	@echo "  LOCAL_DB_NAME = $(LOCAL_DB_NAME)"
	@echo "  ADMIN_PASSWD  = $(ADMIN_PASSWD)"
	@echo ""
	@echo "  USER_REPO     = $(USER_REPO)"
	@echo "  USER_BRANCH   = $(USER_BRANCH)"
	@echo ""
	@if [ -f "$(COMPOSE_YML)" ]; then \
		echo "  Compose file  : $(COMPOSE_YML) $(GREEN)[found]$(NC)"; \
	else \
		echo "  Compose file  : $(COMPOSE_YML) $(YELLOW)[not found — run make setup]$(NC)"; \
	fi
	@echo ""

# ══════════════════════════════════════════════════════════════════
#  INTERNAL GUARDS
# ══════════════════════════════════════════════════════════════════

_require-env:
	@if [ ! -f .env ]; then \
		echo "$(RED)[✘]$(NC) .env file not found."; \
		echo "    Run: cp .env.example .env  then fill in your values."; \
		exit 1; \
	fi

_require-compose:
	@if [ ! -f "$(COMPOSE_YML)" ]; then \
		echo "$(RED)[✘]$(NC) $(COMPOSE_YML) not found."; \
		echo "    Run: make setup  to generate it."; \
		exit 1; \
	fi

_require-user-git:
	@if [ ! -e "$(USER_DIR)/.git" ]; then \
		echo "$(RED)[✘]$(NC) $(USER_DIR)/.git not found."; \
		echo "    Run: make setup  (rsync fixes Odoo.sh worktree + sets USER_REPO remote)"; \
		exit 1; \
	fi

# ══════════════════════════════════════════════════════════════════
#  USER REPO  (odoo-local/user/ — your custom Odoo modules)
#
#  This is a SEPARATE git repo from the sky toolkit repo.
#  rsync preserves its .git so you can commit + push independently.
#  The sky .gitignore ignores odoo-local/user/ entirely.
# ══════════════════════════════════════════════════════════════════

user-status: _require-user-git
	@echo "$(BOLD)▶  git status — $(USER_DIR)$(NC)"
	@git -C $(USER_DIR) status

user-log: _require-user-git
	@echo "$(BOLD)▶  git log (last 10) — $(USER_DIR)$(NC)"
	@git -C $(USER_DIR) log --oneline --graph --decorate -10 2>/dev/null || \
		echo "$(YELLOW)[!]$(NC) No commits yet in this repo."

user-diff: _require-user-git
	@echo "$(BOLD)▶  git diff — $(USER_DIR)$(NC)"
	@git -C $(USER_DIR) diff

user-pull: _require-user-git
	@echo "$(BOLD)▶  git pull — $(USER_DIR)$(NC)"
	@git -C $(USER_DIR) pull

user-push: _require-user-git
	@if [ -z "$(MSG)" ]; then \
		echo "$(RED)[✘]$(NC) Missing commit message."; \
		echo "    Usage: make user-push MSG='your commit message'"; \
		exit 1; \
	fi
	@echo "$(BOLD)▶  Staging all changes in $(USER_DIR)...$(NC)"
	@git -C $(USER_DIR) add -A
	@git -C $(USER_DIR) commit -m "$(MSG)"
	@echo "$(BOLD)▶  Pushing to remote...$(NC)"
	@git -C $(USER_DIR) push
	@echo "$(GREEN)[✔]$(NC) Pushed: $(MSG)"
