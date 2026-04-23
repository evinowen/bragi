#!/bin/bash

set -euo pipefail

SERVICE_NAME="bragi.nginx"
CONTAINER_NAME="bragi.nginx"
IMAGE="nginx:alpine"
SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

DATA_DIR="/opt/nginx"
CONFIG_DIR="$DATA_DIR/config"

create_directories() {
    echo "Creating directories..."
    sudo mkdir -p "$CONFIG_DIR"
    echo "✓ Directories created"
}

copy_configuration_files() {
    echo "Copying default configuration files..."

    if [[ -f "$SERVICE_DIR/nginx.conf" ]]; then
        sudo cp "$SERVICE_DIR/nginx.conf" "$CONFIG_DIR/default.conf"
        echo "✓ Copied nginx.conf"
    else
        echo "✗ nginx.conf template not found"
        exit 1
    fi
}

pull_image() {
    echo "Pulling Docker image: $IMAGE"
    docker pull "$IMAGE"
    echo "✓ Image pulled"
}

stop_existing_container() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Stopping existing container..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        echo "✓ Existing container removed"
    fi
}

create_container() {
    echo "Creating Docker container..."
    docker create \
        --name="$CONTAINER_NAME" \
        --hostname="nginx.bragi" \
        --network="bragi" \
        --restart=unless-stopped \
        -p 80:80 \
        -v "$CONFIG_DIR/default.conf:/etc/nginx/conf.d/default.conf:ro" \
        "$IMAGE"
    echo "✓ Container created"
}

create_systemd_service() {
    echo "Creating systemd service..."

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Bragi Nginx Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start ${CONTAINER_NAME}
ExecStop=/usr/bin/docker stop ${CONTAINER_NAME}
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    echo "✓ Systemd service created"
}

get_host_ip() {
    local host_ip=""

    if command -v ip &> /dev/null; then
        host_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
    fi

    if [[ -z "$host_ip" ]] && command -v hostname &> /dev/null; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    if [[ -z "$host_ip" ]] && command -v ip &> /dev/null; then
        host_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi

    if [[ -z "$host_ip" ]]; then
        host_ip="localhost"
    fi

    echo "$host_ip"
}

main() {
    echo "Installing Nginx service..."
    echo "Container: $CONTAINER_NAME"
    echo "Image: $IMAGE"
    echo "Config directory: $CONFIG_DIR"
    echo

    create_directories
    copy_configuration_files
    pull_image
    stop_existing_container
    create_container
    create_systemd_service

    echo
    echo "✓ Nginx service installed successfully!"
    echo
    echo "To start the service:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo
    echo "To enable autostart on boot:"
    echo "  sudo systemctl enable $SERVICE_NAME"
    echo
    local host_ip=$(get_host_ip)
    echo "Reverse proxy URLs:"
    echo "  http://localhost/sonarr (from this machine)"
    echo "  http://localhost/radarr (from this machine)"
    echo "  http://localhost/sabnzbd (from this machine)"
    echo "  http://$host_ip/sonarr (from network)"
    echo "  http://$host_ip/radarr (from network)"
    echo "  http://$host_ip/sabnzbd (from network)"
}

main "$@"
