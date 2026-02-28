#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMPOSE_FILE="$DIR/docker-compose-https.yml"

if [ -f "$COMPOSE_FILE" ] && command -v docker-compose &> /dev/null; then
    docker-compose -f "$COMPOSE_FILE" down || true
fi

# Clean up local generated files and directories
if [ -f "$DIR/free-edu-server.conf" ]; then
    rm -f "$DIR/free-edu-server.conf"
fi

if [ -f "$DIR/free-edu-server.conf.bak" ]; then
    rm -f "$DIR/free-edu-server.conf.bak"
fi

if [ -d "$DIR/letsencrypt" ]; then
    sudo rm -rf "$DIR/letsencrypt" || true
fi

if [ -d "$DIR/certbot-www" ]; then
    sudo rm -rf "$DIR/certbot-www" || true
fi

echo "Nginx docker tear-down complete."
