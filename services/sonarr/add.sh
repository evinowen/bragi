#!/bin/bash

set -euo pipefail

SERVICE_NAME="bragi.sonarr"
CONTAINER_NAME="bragi.sonarr"
IMAGE="linuxserver/sonarr:latest"
SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

PUID=${PUID:-1000}
PGID=${PGID:-1000}
TZ=${TZ:-"UTC"}

DATA_DIR="/opt/sonarr"
CONFIG_DIR="$DATA_DIR/config"

# Use configured media directories from main installer
# Fall back to local directories if not provided
DOWNLOADS_DIR="${TELEVISION_DOWNLOADS_DIR:-$DATA_DIR/download}"
STAGING_DIR="${TELEVISION_STAGING_DIR:-$DATA_DIR/stage}"
TELEVISION_DIR="${TELEVISION_LIBRARY_DIR:-$DATA_DIR/television}"

create_directories() {
    echo "Creating directories..."
    sudo mkdir -p "$CONFIG_DIR" "$DOWNLOADS_DIR" "$STAGING_DIR" "$TELEVISION_DIR"
    sudo chown -R "$PUID:$PGID" "$DATA_DIR"
    if [[ "$DOWNLOADS_DIR" != "$DATA_DIR/downloads" ]]; then
        sudo chown -R "$PUID:$PGID" "$DOWNLOADS_DIR"
    fi
    if [[ "$STAGING_DIR" != "$DATA_DIR/staging" ]]; then
        sudo chown -R "$PUID:$PGID" "$STAGING_DIR"
    fi
    if [[ "$TELEVISION_DIR" != "$DATA_DIR/television" ]]; then
        sudo chown -R "$PUID:$PGID" "$TELEVISION_DIR"
    fi
    echo "✓ Directories created"
}

copy_configuration_files() {
    echo "Copying default configuration files..."

    if [[ ! -f "$CONFIG_DIR/config.xml" && -f "$SERVICE_DIR/config.xml" ]]; then
        sudo cp "$SERVICE_DIR/config.xml" "$CONFIG_DIR/config.xml"
        sudo chown "$PUID:$PGID" "$CONFIG_DIR/config.xml"
        echo "✓ Copied default config.xml"
    else
        echo "- Configuration file already exists or template not found"
    fi
}

generate_api_key() {
    local api_key
    api_key=$(openssl rand -hex 16)
    sudo sed -i "s|<ApiKey>.*</ApiKey>|<ApiKey>${api_key}</ApiKey>|" "$CONFIG_DIR/config.xml"
    sudo chown "$PUID:$PGID" "$CONFIG_DIR/config.xml"
    echo "✓ API key generated"
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
        --hostname="sonarr.bragi" \
        --network="bragi" \
        --restart=unless-stopped \
        -e PUID="$PUID" \
        -e PGID="$PGID" \
        -e TZ="$TZ" \
        -p 8989:8989 \
        -v "$CONFIG_DIR:/config" \
        -v "$DOWNLOADS_DIR:/downloads" \
        -v "$STAGING_DIR:/staging" \
        -v "$TELEVISION_DIR:/tv" \
        "$IMAGE"
    echo "✓ Container created"
}

create_systemd_service() {
    echo "Creating systemd service..."

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Bragi Sonarr Docker Container
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
    echo "Installing Sonarr service..."
    echo "Container: $CONTAINER_NAME"
    echo "Image: $IMAGE"
    echo "Data directory: $DATA_DIR"
    echo "Downloads: $DOWNLOADS_DIR"
    echo "Staging: $STAGING_DIR"
    echo "Television library: $TELEVISION_DIR"
    echo "Web interface: http://localhost:8989/sonarr"
    echo

    create_directories
    copy_configuration_files
    generate_api_key
    pull_image
    stop_existing_container
    create_container
    create_systemd_service

    echo
    echo "✓ Sonarr service installed successfully!"
    echo
    echo "To start the service:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo
    echo "To enable autostart on boot:"
    echo "  sudo systemctl enable $SERVICE_NAME"
    echo
    local host_ip=$(get_host_ip)
    echo "Web interface URLs:"
    echo "  http://localhost:8989/sonarr (from this machine)"
    echo "  http://$host_ip:8989/sonarr (from network)"
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
