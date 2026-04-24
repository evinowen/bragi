#!/bin/bash

set -euo pipefail

SERVICE_NAME="bragi.jellyfin"
CONTAINER_NAME="bragi.jellyfin"
IMAGE="jellyfin/jellyfin:latest"
SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

PUID=${PUID:-1000}
PGID=${PGID:-1000}
TZ=${TZ:-"UTC"}

DATA_DIR="/opt/jellyfin"
CONFIG_DIR="$DATA_DIR/config"
CACHE_DIR="$DATA_DIR/cache"

TELEVISION_DIR="${TELEVISION_LIBRARY_DIR:-$DATA_DIR/television}"
MOVIE_DIR="${MOVIE_LIBRARY_DIR:-$DATA_DIR/movies}"

create_directories() {
    echo "Creating directories..."
    sudo mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
    sudo chown -R "$PUID:$PGID" "$DATA_DIR"
    echo "✓ Directories created"
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
        --hostname="jellyfin.bragi" \
        --network="bragi" \
        --restart=unless-stopped \
        --user "$PUID:$PGID" \
        -e TZ="$TZ" \
        -p 8096:8096 \
        -v "$CONFIG_DIR:/config" \
        -v "$CACHE_DIR:/cache" \
        -v "$TELEVISION_DIR:/media/television:ro" \
        -v "$MOVIE_DIR:/media/movies:ro" \
        "$IMAGE"
    echo "✓ Container created"
}

create_systemd_service() {
    echo "Creating systemd service..."

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Bragi Jellyfin Docker Container
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
    echo "Installing Jellyfin service..."
    echo "Container: $CONTAINER_NAME"
    echo "Image: $IMAGE"
    echo "Config directory: $CONFIG_DIR"
    echo "Cache directory: $CACHE_DIR"
    echo "Television library: $TELEVISION_DIR (read-only)"
    echo "Movie library: $MOVIE_DIR (read-only)"
    echo

    create_directories
    pull_image
    stop_existing_container
    create_container
    create_systemd_service

    echo
    echo "✓ Jellyfin service installed successfully!"
    echo
    echo "To start the service:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo
    echo "To enable autostart on boot:"
    echo "  sudo systemctl enable $SERVICE_NAME"
    echo
    local host_ip=$(get_host_ip)
    echo "Web interface URLs:"
    echo "  http://localhost/jellyfin (from this machine)"
    echo "  http://$host_ip/jellyfin (from network)"
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
