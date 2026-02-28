#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

domain_name=$1
adminer_port=$2
jupyter_port=$3
code_port=$4
ttyd_port=$5

if [ -z "$domain_name" ]; then
    echo "Usage: $0 <domain_name> <adminer_port> <jupyter_port> <code_port> <ttyd_port>"
    exit 1
fi

CONF_TEMPLATE="$DIR/free-edu-server.conf.template"
CONF_FILE="$DIR/free-edu-server.conf"

if [ ! -f "$CONF_TEMPLATE" ]; then
    echo "Error: Template file $CONF_TEMPLATE not found."
    exit 1
fi

cp "$CONF_TEMPLATE" "$CONF_FILE"
sed -i.bak -e "s/{{DOMAIN_NAME}}/$domain_name/g" \
           -e "s/{{ADMINER_PORT}}/$adminer_port/g" \
           -e "s/{{JUPYTER_PORT}}/$jupyter_port/g" \
           -e "s/{{CODE_PORT}}/$code_port/g" \
           -e "s/{{TTYD_PORT}}/$ttyd_port/g" "$CONF_FILE"
rm -f "${CONF_FILE}.bak"

# Start Nginx via Docker
COMPOSE_FILE="$DIR/docker-compose-https.yml"

echo "Building and starting Nginx via docker-compose..."
# Start Nginx container (this will build the edu-nginx-certbot image)
docker-compose -f "$COMPOSE_FILE" build
docker-compose -f "$COMPOSE_FILE" up -d

# Wait a brief moment to ensure container stands up
sleep 2

docker ps | grep edu_nginx || echo "Warning: edu_nginx container may have failed to start."

read -p "Do you want to run Certbot to configure HTTPS now? (y/n) [n]: " run_certbot
if [[ "$run_certbot" == "y" || "$run_certbot" == "Y" ]]; then
    # Run certbot inside the running nginx container. 
    # The --nginx plugin will modify the mapped free-edu-server.conf automatically.
    docker exec -it edu_nginx certbot --nginx -d $domain_name
    
    # Reload nginx configuration explicitly after certbot returns
    docker exec edu_nginx nginx -s reload || true
fi
