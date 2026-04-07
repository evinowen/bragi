#!/bin/bash

set -euo pipefail

SERVICE_NAME="bragi.sabnzbd"
CONTAINER_NAME="bragi.sabnzbd"
IMAGE="linuxserver/sabnzbd:latest"
SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

PUID=${PUID:-1000}
PGID=${PGID:-1000}
TZ=${TZ:-"UTC"}

DATA_DIR="/opt/sabnzbd"
CONFIG_DIR="$DATA_DIR/config"

# Use configured media directories from main installer
# Fall back to local directories if not provided
DOWNLOADS_DIR="${TELEVISION_DOWNLOADS_DIR:-$DATA_DIR/downloads}"
INCOMPLETE_DIR="$DATA_DIR/incomplete"

create_directories() {
    echo "Creating directories..."
    sudo mkdir -p "$CONFIG_DIR" "$DOWNLOADS_DIR" "$INCOMPLETE_DIR"
    sudo chown -R "$PUID:$PGID" "$DATA_DIR"
    echo "✓ Directories created"
}

copy_configuration_files() {
    echo "Copying default configuration files..."

    # Copy sabnzbd.ini if it doesn't already exist
    if [[ ! -f "$CONFIG_DIR/sabnzbd.ini" && -f "$SERVICE_DIR/sabnzbd.ini" ]]; then
        sudo cp "$SERVICE_DIR/sabnzbd.ini" "$CONFIG_DIR/sabnzbd.ini"
        sudo chown "$PUID:$PGID" "$CONFIG_DIR/sabnzbd.ini"
        echo "✓ Copied default sabnzbd.ini"
    else
        echo "- Configuration file already exists or template not found"
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
        --restart=unless-stopped \
        -e PUID="$PUID" \
        -e PGID="$PGID" \
        -e TZ="$TZ" \
        -p 8080:8080 \
        -v "$CONFIG_DIR:/config" \
        -v "$DOWNLOADS_DIR:/downloads" \
        -v "$INCOMPLETE_DIR:/incomplete-downloads" \
        "$IMAGE"
    echo "✓ Container created"
}

create_systemd_service() {
    echo "Creating systemd service..."

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Bragi SABnzbd Docker Container
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

    # Try different methods to get the host IP address
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
    echo "Installing SABnzbd service..."
    echo "Container: $CONTAINER_NAME"
    echo "Image: $IMAGE"
    echo "Data directory: $DATA_DIR"
    echo "Web interface: http://localhost:8080"
    echo

    create_directories
    copy_configuration_files
    pull_image
    stop_existing_container
    create_container
    create_systemd_service

    echo
    echo "✓ SABnzbd service installed successfully!"
    echo
    echo "To start the service:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo
    echo "To enable autostart on boot:"
    echo "  sudo systemctl enable $SERVICE_NAME"
    echo
    local host_ip=$(get_host_ip)
    echo "Web interface URLs:"
    echo "  http://localhost:8080 (from this machine)"
    echo "  http://$host_ip:8080 (from network)"
}

main "$@"
