#!/bin/bash

set -euo pipefail

SERVICE_NAME="bragi.transmission"
CONTAINER_NAME="bragi.transmission"
IMAGE="linuxserver/transmission:latest"
SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

PUID=${PUID:-1000}
PGID=${PGID:-1000}
TZ=${TZ:-"UTC"}

DATA_DIR="/opt/transmission"
CONFIG_DIR="$DATA_DIR/config"
WATCH_DIR="$DATA_DIR/watch"

TELEVISION_DOWNLOADS="${TELEVISION_DOWNLOADS_DIR:-$DATA_DIR/downloads/television}"
MOVIE_DOWNLOADS="${MOVIE_DOWNLOADS_DIR:-$DATA_DIR/downloads/movies}"

create_directories() {
    echo "Creating directories..."
    sudo mkdir -p "$CONFIG_DIR" "$WATCH_DIR" "$TELEVISION_DOWNLOADS" "$MOVIE_DOWNLOADS"
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
        --hostname="transmission.bragi" \
        --network="bragi" \
        --restart=unless-stopped \
        -e PUID="$PUID" \
        -e PGID="$PGID" \
        -e TZ="$TZ" \
        -e USER="${ADMIN_USERNAME:-}" \
        -e PASS="${ADMIN_PASSWORD:-}" \
        -e PEERPORT=51413 \
        -p 9091:9091 \
        -p 51413:51413 \
        -p 51413:51413/udp \
        -v "$CONFIG_DIR:/config" \
        -v "$TELEVISION_DOWNLOADS:/downloads/television" \
        -v "$MOVIE_DOWNLOADS:/downloads/movies" \
        -v "$WATCH_DIR:/watch" \
        "$IMAGE"
    echo "✓ Container created"
}

create_systemd_service() {
    echo "Creating systemd service..."

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Bragi Transmission Docker Container
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
    echo "Installing Transmission service..."
    echo "Container: $CONTAINER_NAME"
    echo "Image: $IMAGE"
    echo "Data directory: $DATA_DIR"
    echo "Television downloads: $TELEVISION_DOWNLOADS"
    echo "Movie downloads: $MOVIE_DOWNLOADS"
    echo "Web interface: http://localhost:9091/transmission/web/"
    echo

    create_directories
    pull_image
    stop_existing_container
    create_container
    create_systemd_service

    echo
    echo "✓ Transmission service installed successfully!"
    echo
    echo "To start the service:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo
    echo "To enable autostart on boot:"
    echo "  sudo systemctl enable $SERVICE_NAME"
    echo
    local host_ip=$(get_host_ip)
    echo "Web interface URLs:"
    echo "  http://localhost:9091/transmission/web/ (from this machine)"
    echo "  http://$host_ip:9091/transmission/web/ (from network)"
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
