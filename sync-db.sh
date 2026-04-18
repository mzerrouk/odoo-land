#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────
#  sync-db.sh
#
#  Restores a local Odoo.sh backup zip into the local Docker stack.
#  - Drops and recreates the local database
#  - Restores filestore (attachments, images)
#  - Neutralizes the DB for safe local development
#    (disables mail, crons, payments, resets URL, etc.)
#
#  Usage:   bash sync-db.sh /path/to/backup.zip
#  Prereq:  Docker stack must be running (setup-odoo-local.sh done)
# ─────────────────────────────────────────────────────────────────

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

log()    { echo -e "${GREEN}[✔]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✘]${NC} $1"; exit 1; }
header() { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

# ─────────────────────────────────────────────────────────────────
#  LOAD .env  (single source of truth)
# ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  error ".env not found at $ENV_FILE\n\n  Run:  cp .env.example .env\n  Then fill in your settings."
fi

set -a
# shellcheck source=.env
source "$ENV_FILE"
set +a

log "Config loaded from .env"

# ── Apply defaults ─────────────────────────────────────────────
PROJECT_DIR="${PROJECT_DIR:-odoo-local}"
LOCAL_DB_USER="${LOCAL_DB_USER:-odoo}"
LOCAL_DB_NAME="${LOCAL_DB_NAME:-odoo}"
ODOO_PORT="${ODOO_PORT:-8070}"

# ─────────────────────────────────────────────────────────────────
#  RESOLVE DOCKER COMPOSE LOCATION
# ─────────────────────────────────────────────────────────────────

COMPOSE_DIR="${SCRIPT_DIR}/${PROJECT_DIR}"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"

if [ ! -f "$COMPOSE_FILE" ]; then
  error "docker-compose.yml not found at $COMPOSE_FILE\n  Have you run: bash setup-odoo-local.sh ?"
fi

# All docker compose commands will run from the compose file's directory
docker_compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$COMPOSE_DIR" "$@"
}

EXTRACT_DIR="/tmp/odoo_backup_extract_$$"

# ─────────────────────────────────────────────────────────────────
#  CHECK ARGUMENT
# ─────────────────────────────────────────────────────────────────

BACKUP_ZIP="$1"

if [ -z "$BACKUP_ZIP" ]; then
  error "No backup file provided.\n  Usage: bash sync-db.sh /path/to/backup.zip"
fi

if [ ! -f "$BACKUP_ZIP" ]; then
  error "File not found: $BACKUP_ZIP"
fi

BACKUP_ZIP="$(cd "$(dirname "$BACKUP_ZIP")" && pwd)/$(basename "$BACKUP_ZIP")"

# ─────────────────────────────────────────────────────────────────
#  CONFIRM
# ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  sync-db: backup → local Docker${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Backup   : ${BOLD}$BACKUP_ZIP${NC}"
echo -e "  Database : ${BOLD}$LOCAL_DB_NAME${NC}"
echo -e "  Project  : ${BOLD}$COMPOSE_DIR${NC}"
echo ""
warn "This will WIPE your local DB and replace it with backup data!"
echo ""
read -r -p "Are you sure? (yes/no): " CONFIRM
[ "$CONFIRM" != "yes" ] && echo "Aborted." && exit 0

# ─────────────────────────────────────────────────────────────────
#  DEPENDENCY CHECKS
# ─────────────────────────────────────────────────────────────────

command -v unzip >/dev/null 2>&1 || error "unzip not found — install with: apt install unzip"
docker_compose ps --services >/dev/null 2>&1 || error "Docker stack is not reachable. Run: bash setup-odoo-local.sh"

# ─────────────────────────────────────────────────────────────────
#  EXTRACT BACKUP ZIP
# ─────────────────────────────────────────────────────────────────

header "Extracting backup"

rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
unzip -q "$BACKUP_ZIP" -d "$EXTRACT_DIR"

# Standard Odoo backup structure: dump.sql + filestore/
DUMP_FILE="$EXTRACT_DIR/dump.sql"
FILESTORE_DIR="$EXTRACT_DIR/filestore"

[ ! -f "$DUMP_FILE" ] && error "dump.sql not found in zip — is this a valid Odoo backup?\n  Expected: dump.sql + filestore/ inside the zip."

DUMP_SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
log "Extracted dump.sql (${DUMP_SIZE})"

# ─────────────────────────────────────────────────────────────────
#  STOP ODOO (keep DB running)
# ─────────────────────────────────────────────────────────────────

header "Stopping Odoo service"
docker_compose stop odoo
log "Odoo stopped"

# ─────────────────────────────────────────────────────────────────
#  WAIT FOR POSTGRESQL
# ─────────────────────────────────────────────────────────────────

docker_compose start db 2>/dev/null || true

log "Waiting for PostgreSQL to be ready..."
until docker_compose exec -T db pg_isready -U "$LOCAL_DB_USER" >/dev/null 2>&1; do
  sleep 1
done
log "PostgreSQL ready"

# ─────────────────────────────────────────────────────────────────
#  RESTORE DATABASE
# ─────────────────────────────────────────────────────────────────

header "Restoring database"

docker_compose exec -T db psql -U "$LOCAL_DB_USER" \
  -c "DROP DATABASE IF EXISTS ${LOCAL_DB_NAME};" postgres

docker_compose exec -T db psql -U "$LOCAL_DB_USER" \
  -c "CREATE DATABASE ${LOCAL_DB_NAME};" postgres

docker_compose exec -T db psql -U "$LOCAL_DB_USER" "$LOCAL_DB_NAME" < "$DUMP_FILE"

log "Database restored ✓"

# ─────────────────────────────────────────────────────────────────
#  RESTORE FILESTORE
# ─────────────────────────────────────────────────────────────────

if [ -d "$FILESTORE_DIR" ]; then
  header "Restoring filestore (attachments & images)"

  # --all is required: the Odoo container is stopped at this point,
  # and `docker compose ps -q` without --all only lists running containers.
  ODOO_CONTAINER=$(docker_compose ps -q --all odoo)

  if [ -z "$ODOO_CONTAINER" ]; then
    error "Could not find Odoo container ID. Make sure the stack was started at least once (make up)."
  fi

  log "Copying filestore and fixing permissions..."
  # The Odoo container is stopped, so we start a temporary one sharing its volumes
  docker run --rm -u root --volumes-from "$ODOO_CONTAINER" \
    -v "${FILESTORE_DIR}:/tmp/filestore" \
    "odoo:${ODOO_VERSION:-16.0}" bash -c "mkdir -p /var/lib/odoo/filestore/${LOCAL_DB_NAME} && cp -a /tmp/filestore/. /var/lib/odoo/filestore/${LOCAL_DB_NAME}/ && chown -R odoo:odoo /var/lib/odoo/"

  log "Filestore restored ✓"
else
  warn "No filestore/ found in backup — skipping (attachments will be missing)"
fi



# ─────────────────────────────────────────────────────────────────
#  NEUTRALIZE DB FOR LOCAL DEVELOPMENT
# ─────────────────────────────────────────────────────────────────

header "Neutralizing DB for local development"

docker_compose exec -T db psql -U "$LOCAL_DB_USER" "$LOCAL_DB_NAME" <<SQL

-- ── Email ────────────────────────────────────────────────────────
-- Disable all outgoing mail servers (prevents sending real emails)
UPDATE ir_mail_server SET active = false;
-- Disable incoming mail fetchers
UPDATE fetchmail_server SET active = false WHERE active = true;

-- ── Scheduled Actions (Crons) ────────────────────────────────────
-- Disable all cron jobs (prevents background jobs from running)
UPDATE ir_cron SET active = false;

-- ── Payment Providers ────────────────────────────────────────────
-- Disable all live payment providers
UPDATE payment_provider SET state = 'disabled'
  WHERE state IN ('enabled', 'test');

-- ── Base URL ──────────────────────────────────────────────────────
-- Set the web base URL to local (needed for links, assets, etc.)
UPDATE ir_config_parameter
  SET value = 'http://localhost:${ODOO_PORT}'
  WHERE key = 'web.base.url';

-- Fix PDF styling: wkhtmltopdf must use internal port 8069 inside Docker
INSERT INTO ir_config_parameter (key, value)
  VALUES ('report.url', 'http://localhost:8069')
  ON CONFLICT (key) DO UPDATE SET value = 'http://localhost:8069';

-- Freeze base URL to prevent Odoo from auto-updating it
INSERT INTO ir_config_parameter (key, value)
  VALUES ('web.base.url.freeze', 'True')
  ON CONFLICT (key) DO UPDATE SET value = 'True';

-- Also reset the CDN url if set
UPDATE ir_config_parameter
  SET value = ''
  WHERE key = 'web.base.url.cdn';

-- ── Odoo.sh / Cloud-specific Settings ───────────────────────────
-- Remove database expiration lock (Odoo.sh adds this)
DELETE FROM ir_config_parameter
  WHERE key = 'database.expiration_date';

-- Disable Odoo push notification keys (Odoo Cloud specific)
UPDATE ir_config_parameter
  SET value = ''
  WHERE key LIKE 'odoo_ocn%';

-- Remove IAP tokens to avoid hitting production services
UPDATE ir_config_parameter
  SET value = ''
  WHERE key LIKE 'iap.%';

SQL

log "DB neutralized — mail, crons, payments, cloud services disabled ✓"

# ─────────────────────────────────────────────────────────────────
#  CLEANUP TEMP FILES
# ─────────────────────────────────────────────────────────────────

rm -rf "$EXTRACT_DIR"
log "Temp files cleaned up"

# ─────────────────────────────────────────────────────────────────
#  RESTART ODOO
# ─────────────────────────────────────────────────────────────────

header "Restarting Odoo"
docker_compose start odoo
log "Odoo started"

# ─────────────────────────────────────────────────────────────────
#  DONE
# ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  ✅  DB restored from backup!${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  🌐  http://localhost:${ODOO_PORT}"
echo ""
echo -e "  ${YELLOW}Useful make commands:${NC}"
echo -e "  make logs              # stream Odoo logs"
echo -e "  make restart           # restart Odoo"
echo -e "  make psql              # open PostgreSQL prompt"
echo -e "  make shell             # open bash inside the container"
echo ""
