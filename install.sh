#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. OS check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_LIKE=$ID_LIKE
else
    echo "Linux OS not detected properly."
    exit 1
fi

echo "Detected OS: $OS"

# 2. Pre-install (Docker, Docker-Compose, Nginx, Certbot)
echo "=== Installing Pre-requisites (Docker, Docker-Compose, Nginx, Certbot) ==="
if [[ "$OS" == "ubuntu" || "$OS_LIKE" == *"ubuntu"* || "$OS_LIKE" == *"debian"* ]]; then
    # Install for Ubuntu/Debian
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    if ! command -v docker &> /dev/null; then
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update -y
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
elif [[ "$OS" == "centos" || "$OS_LIKE" == *"rhel"* || "$OS_LIKE" == *"fedora"* || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
    sudo dnf install -y yum-utils || sudo yum install -y yum-utils
    sudo dnf install -y epel-release || sudo yum install -y epel-release
    if ! command -v docker &> /dev/null; then
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    sudo systemctl start docker
    sudo systemctl enable docker
else
    echo "Unsupported OS: $OS"
    exit 1
fi

# Add current user to docker group if not root
if [ "$EUID" -ne 0 ]; then
    sudo usermod -aG docker $(whoami) || true
fi

# Alias for docker-compose if needed
if ! command -v docker-compose &> /dev/null; then
    sudo tee /usr/local/bin/docker-compose >/dev/null << 'EOF'
#!/usr/bin/env bash
docker compose "$@"
EOF
    sudo chmod +x /usr/local/bin/docker-compose
fi

# 3. YML Preferences Prompt
echo "=== Configuration Setup ==="

# Define DB_YML, IDE_YML, SSH_YML
DB_YML="$DIR/db/docker-compose-db.yml"
IDE_YML="$DIR/ide/docker-compose-ide.yml"
SSH_YML="$DIR/ssh/docker-compose-ttyd.yml"

# Helper function
prompt_replace() {
    local prompt_msg=$1
    local default_val=$2
    local file=$3
    local prefix=$4
    local match_str=$5
    
    read -p "$prompt_msg [$default_val]: " user_val
    user_val=${user_val:-$default_val}
    
    # E.g., match POSTGRES_USER: and replace the whole line
    sed -i.bak -E "s/^[[:space:]]*${match_str}.*/${prefix}${user_val}/g" "$file"
}

if [ -f "$DB_YML" ]; then
    echo "[PostgreSQL Configuration]"
    prompt_replace "Enter PostgreSQL USER name" "dbuser" "$DB_YML" "      POSTGRES_USER: " "POSTGRES_USER:"
    prompt_replace "Enter PostgreSQL PASSWORD" "dbpass" "$DB_YML" "      POSTGRES_PASSWORD: " "POSTGRES_PASSWORD:"
    prompt_replace "Enter PostgreSQL DB name" "postgres_db" "$DB_YML" "      POSTGRES_DB: " "POSTGRES_DB:"
    read -p "Enter PostgreSQL external port [5432]: " pg_port
    pg_port=${pg_port:-5432}
    sed -i.bak -E "s/^[[:space:]]*-[[:space:]]*\"[0-9]+:5432\"/      - \"$pg_port:5432\"/g" "$DB_YML"

    echo "[MariaDB Configuration]"
    prompt_replace "Enter MariaDB ROOT PASSWORD" "rootpass" "$DB_YML" "      MYSQL_ROOT_PASSWORD: " "MYSQL_ROOT_PASSWORD:"
    prompt_replace "Enter MariaDB USER name" "dbuser" "$DB_YML" "      MYSQL_USER: " "MYSQL_USER:"
    prompt_replace "Enter MariaDB PASSWORD" "dbpass" "$DB_YML" "      MYSQL_PASSWORD: " "MYSQL_PASSWORD:"
    prompt_replace "Enter MariaDB DB name" "mariadb_db" "$DB_YML" "      MYSQL_DATABASE: " "MYSQL_DATABASE:"
    read -p "Enter MariaDB external port [3306]: " maria_port
    maria_port=${maria_port:-3306}
    sed -i.bak -E "s/^[[:space:]]*-[[:space:]]*\"[0-9]+:3306\"/      - \"$maria_port:3306\"/g" "$DB_YML"
    
    read -p "Enter Adminer external port [50081]: " adminer_port
    adminer_port=${adminer_port:-50081}
    sed -i.bak -E "s/^[[:space:]]*-[[:space:]]*\"[0-9]+:8080\"/      - \"$adminer_port:8080\"/g" "$DB_YML"
fi

if [ -f "$IDE_YML" ]; then
    echo "[IDE Configuration]"
    prompt_replace "Enter Jupyter Token" "your-jupyter-token" "$IDE_YML" "    command: start-notebook.sh --NotebookApp.token='" "'?" "command: start-notebook.sh --NotebookApp.token"  # this sed logic can be tricky, using custom sed
    
    read -p "Enter Jupyter Token [your-jupyter-token]: " jupyter_token
    jupyter_token=${jupyter_token:-"your-jupyter-token"}
    sed -i.bak -E "s/^[[:space:]]*command: start-notebook.sh --NotebookApp.token=.*/    command: start-notebook.sh --NotebookApp.token='${jupyter_token}'/g" "$IDE_YML"
    
    read -p "Enter Jupyter external port [50888]: " jupyter_port
    jupyter_port=${jupyter_port:-50888}
    sed -i.bak -E "s/^[[:space:]]*-[[:space:]]*\"[0-9]+:8888\"/      - \"$jupyter_port:8888\"/g" "$IDE_YML"

    prompt_replace "Enter Code-Server Password" "\"your-codeserver-password\"" "$IDE_YML" "      PASSWORD: " "PASSWORD:"
    read -p "Enter Code-Server external port [50080]: " code_port
    code_port=${code_port:-50080}
    sed -i.bak -E "s/^[[:space:]]*-[[:space:]]*\"[0-9]+:8080\"/      - \"$code_port:8080\"/g" "$IDE_YML"
fi

if [ -f "$SSH_YML" ]; then
    echo "[SSH (ttyd) Configuration]"
    prompt_replace "Enter ttyd User name" "ttyuser" "$SSH_YML" "      - HTTP_USERNAME=" "- HTTP_USERNAME="
    prompt_replace "Enter ttyd Password" "ttypass" "$SSH_YML" "      - HTTP_PASSWORD=" "- HTTP_PASSWORD="
    read -p "Enter ttyd external port [50082]: " ttyd_port
    ttyd_port=${ttyd_port:-50082}
    sed -i.bak -E "s/^[[:space:]]*-[[:space:]]*\"[0-9]+:7681\"/      - \"$ttyd_port:7681\"/g" "$SSH_YML"
fi

# Cleanup
find "$DIR" -name "*.bak" -type f -delete 2>/dev/null || true

# 4. Nginx configuration added to /nginx dir
echo "=== Nginx & Certbot SSL ==="
read -p "Enter your domain name for HTTPS (e.g. dev.example.com): " domain_name
domain_name=${domain_name:-dev.example.com}

NGINX_DIR="$DIR/nginx"
if [ -x "$NGINX_DIR/setup-nginx.sh" ]; then
    "$NGINX_DIR/setup-nginx.sh" "$domain_name" "${adminer_port:-50081}" "${jupyter_port:-50888}" "${code_port:-50080}" "${ttyd_port:-50082}"
else
    echo "Warning: $NGINX_DIR/setup-nginx.sh not found or not executable. Please check the nginx folder."
fi

# 6. Select Service and Start
echo "=== Start Services ==="
echo "Select the services you want to start: 'db', 'ssh', 'ide', or 'all'"
read -p "Services to start [all]: " svc

svc=${svc:-all}

if [[ "$svc" == *"all"* ]]; then
    svc="db ide ssh"
fi

if [[ "$svc" == *"db"* && -f "$DB_YML" ]]; then
    echo "Starting db..."
    docker-compose -f "$DB_YML" up -d
fi

if [[ "$svc" == *"ide"* && -f "$IDE_YML" ]]; then
    echo "Starting ide..."
    docker-compose -f "$IDE_YML" up -d
fi

if [[ "$svc" == *"ssh"* && -f "$SSH_YML" ]]; then
    echo "Starting ssh..."
    docker-compose -f "$SSH_YML" up -d
fi

echo "Done!"
