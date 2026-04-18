#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────
#  Odoo.sh → Local Docker Setup Script
#
#  - Loads ALL config from .env (single source of truth)
#  - Rsyncs source from Odoo.sh (enterprise, themes, user addons)
#  - Generates odoo.conf + docker-compose.yml
#  - Starts Docker containers
#
#  Usage:  bash setup-odoo-local.sh
#  Prereq: copy .env.example → .env and fill in your values
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
  error ".env not found at $ENV_FILE\n\n  Run:  cp .env.example .env\n  Then fill in your SSH credentials and settings."
fi

# Export all vars from .env so child processes (docker compose) inherit them
set -a
# shellcheck source=.env
source "$ENV_FILE"
set +a

log "Config loaded from .env"

# ── Apply defaults for optional vars ──────────────────────────────
ODOO_VERSION="${ODOO_VERSION:-16.0}"
PROJECT_DIR="${PROJECT_DIR:-odoo-local}"
REMOTE_SRC="${REMOTE_SRC:-/home/odoo/src}"
LOCAL_DB_USER="${LOCAL_DB_USER:-odoo}"
LOCAL_DB_PASSWORD="${LOCAL_DB_PASSWORD:-odoo}"
LOCAL_DB_NAME="${LOCAL_DB_NAME:-odoo}"
ODOO_PORT="${ODOO_PORT:-8070}"
ADMIN_PASSWD="${ADMIN_PASSWD:-admin}"
SYNC_ODOO_CORE="${SYNC_ODOO_CORE:-false}"

# ─────────────────────────────────────────────────────────────────
#  VALIDATE REQUIRED VARIABLES
# ─────────────────────────────────────────────────────────────────

header "Validating configuration"
[ -z "$SSH_USER" ] && error "SSH_USER is not set in .env"
[ -z "$SSH_HOST" ] && error "SSH_HOST is not set in .env"

log "SSH target : ${SSH_USER}@${SSH_HOST}:${REMOTE_SRC}"
log "Odoo image : odoo:${ODOO_VERSION}"
log "Local port : ${ODOO_PORT}"
log "Project dir: ${SCRIPT_DIR}/${PROJECT_DIR}"

# ─────────────────────────────────────────────────────────────────
#  DEPENDENCY CHECKS
# ─────────────────────────────────────────────────────────────────

header "Checking dependencies"

command -v rsync  >/dev/null 2>&1 || error "rsync not found — install with: apt install rsync"
command -v docker >/dev/null 2>&1 || error "docker is not installed"
command -v unzip  >/dev/null 2>&1 || error "unzip not found — install with: apt install unzip"
docker compose version >/dev/null 2>&1 || error "docker compose (v2) is not available"

log "rsync, docker, docker compose, unzip — OK"

# ─────────────────────────────────────────────────────────────────
#  CREATE PROJECT FOLDER
# ─────────────────────────────────────────────────────────────────

header "Setting up project directory"

mkdir -p "${SCRIPT_DIR}/${PROJECT_DIR}"
cd "${SCRIPT_DIR}/${PROJECT_DIR}"

log "Working in: $(pwd)"

# ─────────────────────────────────────────────────────────────────
#  RSYNC SOURCE FILES FROM ODOO.SH
# ─────────────────────────────────────────────────────────────────

header "Syncing source files from Odoo.sh"
warn "This may take several minutes on first run..."

# ── rsync_folder: strips .git (read-only source folders) ──────────
rsync_folder() {
  local name=$1
  log "Syncing ${name}/ ..."
  rsync -az --progress \
    --exclude='.git' \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='.sass-cache' \
    -e "ssh" \
    "${SSH_USER}@${SSH_HOST}:${REMOTE_SRC}/${name}/" \
    "./${name}/"
}

# ── rsync_user: keeps .git + fixes Odoo.sh worktree reference ────
# Odoo.sh stores user/ as a git worktree: .git is a FILE pointing to
# an absolute server path that doesn't exist locally.
# Strategy after rsync:
#   1. Detect the worktree file
#   2. Replace with a real git repo (init + remote + fetch)
#   3. Set the tracking branch WITHOUT checkout (avoids overwrite errors)
#      using: branch + symbolic-ref + reset
#      → working tree files stay as-is, but git now knows which
#        files are modified vs. in sync with origin/USER_BRANCH
rsync_user() {
  log "Syncing user/ (preserving .git) ..."
  rsync -az --progress \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='.sass-cache' \
    -e "ssh" \
    "${SSH_USER}@${SSH_HOST}:${REMOTE_SRC}/user/" \
    "./user/"

  # ── Detect and fix Odoo.sh worktree .git file ─────────────────
  if [ -f "./user/.git" ]; then
    warn "Detected Odoo.sh git worktree (user/.git is a file — server path, not usable locally)"

    if [ -z "$USER_REPO" ]; then
      warn "USER_REPO not set in .env — cannot re-initialize git."
      warn "Add USER_REPO=git@github.com:your-org/your-modules.git to enable make user-* commands."
      rm -f "./user/.git"
      git -C "./user" init -q
      return
    fi

    log "Re-initializing user/ git repo..."
    rm -f "./user/.git"
    git -C "./user" init -q
    git -C "./user" remote add origin "$USER_REPO" 2>/dev/null || \
      git -C "./user" remote set-url origin "$USER_REPO"

    log "Fetching from $USER_REPO ..."
    if ! git -C "./user" fetch --quiet origin; then
      warn "Could not fetch from $USER_REPO. Remote is set — try: make user-pull"
      return
    fi

    # ── Set tracking branch without checkout ──────────────────────
    # We cannot use `git checkout -b branch origin/branch` because all
    # working tree files are "untracked" and git refuses to overwrite them.
    # Instead: create the branch pointer, point HEAD at it, then reset
    # the index — files stay in place, git computes real diffs.
    local branch="${USER_BRANCH:-}"
    if [ -z "$branch" ]; then
      # Auto-detect from remote HEAD
      branch=$(git -C "./user" remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
      [ -z "$branch" ] && branch="main"
      warn "USER_BRANCH not set in .env — defaulting to remote HEAD: $branch"
    fi

    if git -C "./user" ls-remote --exit-code origin "$branch" >/dev/null 2>&1; then
      git -C "./user" branch "$branch" "origin/$branch" 2>/dev/null || \
        git -C "./user" branch -f "$branch" "origin/$branch"
      git -C "./user" symbolic-ref HEAD "refs/heads/$branch"
      git -C "./user" reset --quiet
      log "user/ tracking branch: $branch → origin/$branch ✓"
    else
      warn "Branch '$branch' not found on remote. Available branches:"
      git -C "./user" branch -r | sed 's|origin/||' | sed 's/^/    /'
      warn "Set USER_BRANCH=<branch> in .env and re-run: make setup"
    fi

  elif [ -d "./user/.git" ]; then
    # Already a proper local git repo — just update remote & pull
    git -C "./user" remote set-url origin "$USER_REPO" 2>/dev/null || true
    log "user/ synced — existing git repo updated ✓"
  fi
}


if [ "$SYNC_ODOO_CORE" = "true" ]; then
  warn "SYNC_ODOO_CORE=true — syncing Odoo core (large, can take 10+ min)..."
  rsync_folder "odoo"
  log "Odoo core synced"
else
  warn "SYNC_ODOO_CORE=false — skipping odoo/ core (Docker image will be used instead)"
fi

rsync_folder "enterprise"
rsync_folder "themes"
rsync_user   # keeps .git → fixed from Odoo.sh worktree to real repo

log "All source files synced ✓"


# ─────────────────────────────────────────────────────────────────
#  GENERATE odoo.conf
# ─────────────────────────────────────────────────────────────────

header "Generating odoo.conf"

cat > odoo.conf <<EOF
[options]
addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons/enterprise,/mnt/extra-addons/themes,/mnt/extra-addons/user
db_host = db
db_port = 5432
db_user = ${LOCAL_DB_USER}
db_password = ${LOCAL_DB_PASSWORD}
db_name = ${LOCAL_DB_NAME}
http_port = 8069
data_dir = /var/lib/odoo
admin_passwd = ${ADMIN_PASSWD}

; ── Dev Settings ────────────────────────────────────────────
; workers = 0  → single-threaded mode (required for pdb / breakpoints)
workers = 0
; log_level = debug  → verbose output for development
log_level = debug
; dev_mode = reload,xml  → auto-reload on Python/XML file changes
dev_mode = reload,xml
EOF

log "odoo.conf generated"

# ─────────────────────────────────────────────────────────────────
#  GENERATE docker-compose.yml
# ─────────────────────────────────────────────────────────────────

header "Generating docker-compose.yml"

cat > docker-compose.yml <<'EOF'
# ──────────────────────────────────────────────────────────────
#  Auto-generated by setup-odoo-local.sh
#  All variables are resolved from ../.env (project root)
#  Do not edit manually — re-run setup-odoo-local.sh to regenerate
# ──────────────────────────────────────────────────────────────
services:
  db:
    image: postgres:15
    restart: unless-stopped
    env_file:
      - ../.env
    environment:
      POSTGRES_USER: ${LOCAL_DB_USER:-odoo}
      POSTGRES_PASSWORD: ${LOCAL_DB_PASSWORD:-odoo}
      POSTGRES_DB: ${LOCAL_DB_NAME:-odoo}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${LOCAL_DB_USER:-odoo}"]
      interval: 5s
      timeout: 5s
      retries: 10

  odoo:
    image: odoo:${ODOO_VERSION:-16.0}
    command: >
      bash -c 'if [ -n "$$EXTRA_PIP_PACKAGES" ]; then pip3 install --no-cache-dir --break-system-packages $$EXTRA_PIP_PACKAGES; fi; exec /entrypoint.sh odoo'
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "${ODOO_PORT:-8070}:8069"
    volumes:
      - ./enterprise:/mnt/extra-addons/enterprise
      - ./themes:/mnt/extra-addons/themes
      - ./user:/mnt/extra-addons/user
      - ./odoo.conf:/etc/odoo/odoo.conf
      - odoo-data:/var/lib/odoo
    env_file:
      - ../.env
    environment:
      HOST: db
      USER: ${LOCAL_DB_USER:-odoo}
      PASSWORD: ${LOCAL_DB_PASSWORD:-odoo}

volumes:
  pgdata:
  odoo-data:
EOF

log "docker-compose.yml generated"

# ─────────────────────────────────────────────────────────────────
#  START CONTAINERS
# ─────────────────────────────────────────────────────────────────

header "Starting Docker containers"
docker compose up -d
log "All containers started"

# ── FIX PERMISSIONS (Final Solution) ───────────────────────────
# Some Odoo versions (16.0 vs 18.0) use different UIDs for the odoo user.
# We force the correct ownership on the data volume to avoid 500 errors.
log "Ensuring correct volume permissions..."
docker compose exec -T -u root odoo chown -R odoo:odoo /var/lib/odoo
log "Permissions fixed ✓"

# ─────────────────────────────────────────────────────────────────
#  DONE
# ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  ✅  Setup complete! Odoo is starting...${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  🌐  URL:      ${BOLD}http://localhost:${ODOO_PORT}${NC}"
echo -e "  🔑  Admin:    ${BOLD}${ADMIN_PASSWD}${NC}"
echo ""
echo -e "  ${YELLOW}Next step — restore production DB:${NC}"
echo -e "  ${BOLD}make sync-db BACKUP=/path/to/backup.zip${NC}"
echo ""
echo -e "  ${YELLOW}Useful make commands:${NC}"
echo -e "  make logs              # stream Odoo logs"
echo -e "  make restart           # restart Odoo after code change"
echo -e "  make shell             # open bash inside the container"
echo -e "  make psql              # open PostgreSQL prompt"
echo -e "  make stop              # stop containers (keep data)"
echo -e "  make down              # stop and remove containers"
echo -e "  make reset-db          # ⚠️  wipe all data + fresh start"
echo ""
