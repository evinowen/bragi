#!/bin/bash

set -euo pipefail

trap 'echo "ERROR: Script exited unexpectedly at line $LINENO. Last command: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"
SERVICES_DIR="$SCRIPT_DIR/services"
INSTALLED_SERVICES=()

TELEVISION_DOWNLOADS_DIR=""
TELEVISION_STAGING_DIR=""
TELEVISION_LIBRARY_DIR=""
MOVIE_DOWNLOADS_DIR=""
MOVIE_STAGING_DIR=""
MOVIE_LIBRARY_DIR=""
MUSIC_DOWNLOADS_DIR=""
MUSIC_STAGING_DIR=""
MUSIC_LIBRARY_DIR=""

USENET_HOST=""
USENET_USERNAME=""
USENET_PASSWORD=""
USENET_SSL="yes"

ADMIN_USERNAME="admin"
ADMIN_PASSWORD=""

# shellcheck source=lib/prerequisites.sh
source "$SCRIPT_DIR/lib/prerequisites.sh"
# shellcheck source=lib/network.sh
source "$SCRIPT_DIR/lib/network.sh"
# shellcheck source=lib/credentials.sh
source "$SCRIPT_DIR/lib/credentials.sh"
# shellcheck source=lib/usenet.sh
source "$SCRIPT_DIR/lib/usenet.sh"
# shellcheck source=lib/media.sh
source "$SCRIPT_DIR/lib/media.sh"
# shellcheck source=lib/services.sh
source "$SCRIPT_DIR/lib/services.sh"

echo "=== Docker Services Installer ==="
echo

main() {
    echo "Checking prerequisites..."
    check_docker
    check_systemd
    check_permissions

    generate_credentials
    configure_usenet
    configure_media_directories
    create_media_directories
    create_docker_network

    select_services
    install_services
    enable_and_start_services

    local verification_success=true

    if ! verify_services_running; then
        verification_success=false
    fi

    configure_services

    echo
    echo "=== Installation Complete ==="

    if [[ "$verification_success" == "true" ]]; then
        echo "✓ All services have been installed and are running successfully!"
    else
        echo "⚠️  Services have been installed but some may need additional time to start."
    fi

    echo
    echo "Installed services:"

    for service in "${INSTALLED_SERVICES[@]}"; do
        echo "  - $service"
    done

    echo
    echo "Configured media directories:"
    echo "Television Shows:"
    echo "  Download:  $TELEVISION_DOWNLOADS_DIR"
    echo "  Stage:     $TELEVISION_STAGING_DIR"
    echo "  Library:   $TELEVISION_LIBRARY_DIR"
    echo "Movies:"
    echo "  Download:  $MOVIE_DOWNLOADS_DIR"
    echo "  Stage:     $MOVIE_STAGING_DIR"
    echo "  Library:   $MOVIE_LIBRARY_DIR"
    echo "Music:"
    echo "  Download:  $MUSIC_DOWNLOADS_DIR"
    echo "  Stage:     $MUSIC_STAGING_DIR"
    echo "  Library:   $MUSIC_LIBRARY_DIR"

    display_credentials
    display_service_urls

    echo
    echo "You can manage services using systemctl:"
    echo "  sudo systemctl start bragi.<service-name>"
    echo "  sudo systemctl stop bragi.<service-name>"
    echo "  sudo systemctl restart bragi.<service-name>"
    echo "  sudo systemctl status bragi.<service-name>"
    echo
    echo "Services are enabled to start automatically on boot."
}

main "$@"
