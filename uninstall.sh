#!/bin/bash
set -e

if [[ "${BASH_SOURCE[0]}" == "" || "${BASH_SOURCE[0]}" == "bash" ]]; then
    DIR="$PWD/free-edu-server"
else
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null || echo ".")" && pwd)"
fi

if [ ! -d "$DIR" ]; then
    echo "Directory $DIR not found. Please run uninstall from the correct location."
    exit 1
fi

cd "$DIR"


echo "=== Uninstalling Services and Configurations ==="
echo "Note: Docker/Docker-Compose (Pre-install) will NOT be uninstalled."

# Bring down services
DB_YML="$DIR/db/docker-compose-db.yml"
IDE_YML="$DIR/ide/docker-compose-ide.yml"
SSH_YML="$DIR/ssh/docker-compose-ttyd.yml"

if [ -f "$DB_YML" ] && command -v docker-compose &> /dev/null; then
    docker-compose -f "$DB_YML" down || true
fi

if [ -f "$IDE_YML" ] && command -v docker-compose &> /dev/null; then
    docker-compose -f "$IDE_YML" down || true
fi

if [ -f "$SSH_YML" ] && command -v docker-compose &> /dev/null; then
    docker-compose -f "$SSH_YML" down || true
fi

# Remove Nginx configuration
NGINX_DIR="$DIR/nginx"
if [ -x "$NGINX_DIR/uninstall-nginx.sh" ]; then
    "$NGINX_DIR/uninstall-nginx.sh"
else
    echo "Warning: $NGINX_DIR/uninstall-nginx.sh not found or not executable. Skipping Nginx cleanup."
fi

echo "Uninstallation of configurations complete."
