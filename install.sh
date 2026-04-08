#!/bin/bash

set -euo pipefail

# Trap to catch unexpected exits
trap 'echo "ERROR: Script exited unexpectedly at line $LINENO. Last command: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"
SERVICES_DIR="$SCRIPT_DIR/services"
INSTALLED_SERVICES=()

# Media directory configuration
TELEVISION_DOWNLOADS_DIR=""
TELEVISION_STAGING_DIR=""
TELEVISION_LIBRARY_DIR=""
MOVIE_DOWNLOADS_DIR=""
MOVIE_STAGING_DIR=""
MOVIE_LIBRARY_DIR=""

echo "=== Docker Services Installer ==="
echo

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "ERROR: Docker is not installed or not in PATH"
        echo "Please install Docker before running this script"
        echo "Visit: https://docs.docker.com/engine/install/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        echo "ERROR: Docker daemon is not running or user lacks permissions"
        echo "Please ensure Docker is running and your user is in the docker group"
        echo "Run: sudo usermod -aG docker \$USER && newgrp docker"
        exit 1
    fi

    echo "✓ Docker is available and running"
}

check_systemd() {
    if ! command -v systemctl &> /dev/null; then
        echo "ERROR: systemd is not available on this system"
        echo "This installer requires a Linux distribution with systemd"
        exit 1
    fi

    echo "✓ systemd is available"
}

check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        echo "WARNING: Running as root. This script will create systemd services."
    else
        echo "INFO: Running as non-root user. You may be prompted for sudo password."
    fi
}

get_host_ip() {
    local host_ip=""

    # Try different methods to get the host IP address
    # Method 1: Check default route
    if command -v ip &> /dev/null; then
        host_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
    fi

    # Method 2: Check hostname resolution
    if [[ -z "$host_ip" ]] && command -v hostname &> /dev/null; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # Method 3: Check network interfaces
    if [[ -z "$host_ip" ]] && command -v ip &> /dev/null; then
        host_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi

    # Method 4: Fallback using ifconfig if available
    if [[ -z "$host_ip" ]] && command -v ifconfig &> /dev/null; then
        host_ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
    fi

    # Default fallback
    if [[ -z "$host_ip" ]]; then
        host_ip="localhost"
    fi

    echo "$host_ip"
}

configure_media_directories() {
    echo
    echo "=== Media Directory Configuration ==="
    echo "Please specify the directories for media storage."
    echo "These will be used by media services like SABnzbd, Sonarr, Radarr, etc."
    echo

    # Ask for configuration mode
    local config_mode=""
    while [[ "${config_mode:-}" != "s" && "${config_mode:-}" != "i" ]]; do
        echo "Configuration mode:"
        echo "  [s] Simple - Set base directory for each media type (recommended)"
        echo "  [i] Individual - Set each subdirectory separately"
        echo -n "Choose configuration mode [s/i]: "
        read config_mode </dev/tty
        config_mode=$(echo "${config_mode:-}" | tr '[:upper:]' '[:lower:]')
        if [[ -z "${config_mode:-}" ]]; then
            config_mode="s"
        fi
        if [[ "${config_mode}" != "s" && "${config_mode}" != "i" ]]; then
            echo "  Error: Please enter 's' for Simple or 'i' for Individual."
        fi
    done

    echo

    if [[ "$config_mode" == "s" ]]; then
        # Simple mode - base directories with derived subdirectories
        echo "Simple Configuration Mode"
        echo "Enter base directories. Subdirectories (download, stage, library) will be created automatically."
        echo

        # Television base directory
        echo "Television Shows:"
        echo -n "  Base directory [/media/television]: "
        read television_base </dev/tty
        television_base="${television_base:-/media/television}"
        TELEVISION_DOWNLOADS_DIR="$television_base/download"
        TELEVISION_STAGING_DIR="$television_base/stage"
        TELEVISION_LIBRARY_DIR="$television_base/library"

        echo

        # Movies base directory
        echo "Movies:"
        echo -n "  Base directory [/media/movies]: "
        read movies_base </dev/tty
        movies_base="${movies_base:-/media/movies}"
        MOVIE_DOWNLOADS_DIR="$movies_base/download"
        MOVIE_STAGING_DIR="$movies_base/stage"
        MOVIE_LIBRARY_DIR="$movies_base/library"

    else
        # Individual mode - specify each directory separately
        echo "Individual Configuration Mode"
        echo "Specify each directory separately."
        echo

        # Television Shows configuration
        echo "Television Shows:"
        echo -n "  Download directory [/media/television/download]: "
        read TELEVISION_DOWNLOADS_DIR </dev/tty
        TELEVISION_DOWNLOADS_DIR="${TELEVISION_DOWNLOADS_DIR:-/media/television/download}"

        echo -n "  Stage directory [/media/television/stage]: "
        read TELEVISION_STAGING_DIR </dev/tty
        TELEVISION_STAGING_DIR="${TELEVISION_STAGING_DIR:-/media/television/stage}"

        echo -n "  Library directory [/media/television/library]: "
        read TELEVISION_LIBRARY_DIR </dev/tty
        TELEVISION_LIBRARY_DIR="${TELEVISION_LIBRARY_DIR:-/media/television/library}"

        echo

        # Movies configuration
        echo "Movies:"
        echo -n "  Download directory [/media/movies/download]: "
        read MOVIE_DOWNLOADS_DIR </dev/tty
        MOVIE_DOWNLOADS_DIR="${MOVIE_DOWNLOADS_DIR:-/media/movies/download}"

        echo -n "  Stage directory [/media/movies/stage]: "
        read MOVIE_STAGING_DIR </dev/tty
        MOVIE_STAGING_DIR="${MOVIE_STAGING_DIR:-/media/movies/stage}"

        echo -n "  Library directory [/media/movies/library]: "
        read MOVIE_LIBRARY_DIR </dev/tty
        MOVIE_LIBRARY_DIR="${MOVIE_LIBRARY_DIR:-/media/movies/library}"
    fi

    echo
    echo "Directory Configuration Summary:"
    echo "Television Shows:"
    echo "  Download:  $TELEVISION_DOWNLOADS_DIR"
    echo "  Stage:     $TELEVISION_STAGING_DIR"
    echo "  Library:   $TELEVISION_LIBRARY_DIR"
    echo "Movies:"
    echo "  Download:  $MOVIE_DOWNLOADS_DIR"
    echo "  Stage:     $MOVIE_STAGING_DIR"
    echo "  Library:   $MOVIE_LIBRARY_DIR"
}

create_media_directories() {
    echo
    echo "=== Directory Creation ==="

    # Collect all unique directories
    local -a all_dirs=(
        "$TELEVISION_DOWNLOADS_DIR"
        "$TELEVISION_STAGING_DIR"
        "$TELEVISION_LIBRARY_DIR"
        "$MOVIE_DOWNLOADS_DIR"
        "$MOVIE_STAGING_DIR"
        "$MOVIE_LIBRARY_DIR"
    )

    # Remove duplicates and check which don't exist
    local -a missing_dirs=()
    local -a unique_dirs=()

    for dir in "${all_dirs[@]}"; do
        # Check if already in unique_dirs array
        local found=false
        for unique_dir in "${unique_dirs[@]}"; do
            if [[ "$dir" == "$unique_dir" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == "false" ]]; then
            unique_dirs+=("$dir")
            if [[ ! -d "$dir" ]]; then
                missing_dirs+=("$dir")
            fi
        fi
    done

    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        echo "✓ All directories already exist."
        return 0
    fi

    echo "The following directories do not exist:"
    for dir in "${missing_dirs[@]}"; do
        echo "  - $dir"
    done

    echo
    local create_dirs=""
    while [[ "${create_dirs:-}" != "y" && "${create_dirs:-}" != "n" && "${create_dirs:-}" != "" ]]; do
        echo -n "Would you like to create these directories? [y/N]: "
        read create_dirs </dev/tty
        create_dirs=$(echo "${create_dirs:-}" | tr '[:upper:]' '[:lower:]')
    done

    # Default to 'n' if empty
    if [[ -z "$create_dirs" ]]; then
        create_dirs="n"
    fi

    if [[ "$create_dirs" == "y" ]]; then
        echo "Creating directories..."
        local created_count=0
        local failed_count=0

        for dir in "${missing_dirs[@]}"; do
            if mkdir -p "$dir" 2>/dev/null; then
                echo "✓ Created: $dir"
                ((created_count++))
            else
                echo "✗ Failed to create: $dir"
                ((failed_count++))
            fi
        done

        echo
        echo "Directory Creation Summary:"
        echo "  Created: $created_count"
        echo "  Failed: $failed_count"

        if [[ $failed_count -gt 0 ]]; then
            echo
            echo "⚠️  Some directories could not be created. Services may fail if these"
            echo "   directories are not created manually before starting services."
        fi
    else
        echo "Skipping directory creation."
        echo
        echo "⚠️  Note: Services may fail to start if the configured directories"
        echo "   do not exist. Please create them manually before starting services."
    fi
}

install_services() {
    if [[ ! -d "$SERVICES_DIR" ]]; then
        echo "ERROR: Services directory not found: $SERVICES_DIR"
        exit 1
    fi

    echo
    echo "=== Installing Services ==="

    local service_count=0
    local failed_count=0
    local -a installed_services=()

    for service_dir in "$SERVICES_DIR"/*; do
        if [[ -d "$service_dir" ]]; then
            local service_name=$(basename "$service_dir")
            local install_script="$service_dir/add.sh"

            echo
            echo "Installing service: $service_name"

            if [[ -f "$install_script" ]]; then
                # Export media directory variables for service scripts
                export TELEVISION_DOWNLOADS_DIR TELEVISION_STAGING_DIR TELEVISION_LIBRARY_DIR
                export MOVIE_DOWNLOADS_DIR MOVIE_STAGING_DIR MOVIE_LIBRARY_DIR

                echo "Running installation script for $service_name..."
                if bash "$install_script" 2>&1; then
                    echo "✓ Successfully installed: $service_name"
                    installed_services+=("bragi.$service_name")
                    ((service_count++))
                else
                    local exit_code=$?
                    echo "✗ Failed to install: $service_name (exit code: $exit_code)"
                    echo "  Installation script: $install_script"
                    echo "  Check the error output above for details"
                    ((failed_count++))
                fi
            else
                echo "✗ No add script found: $install_script"
                ((failed_count++))
            fi
        fi
    done

    echo
    echo "=== Installation Summary ==="
    echo "Services installed: $service_count"
    echo "Services failed: $failed_count"

    if [[ $service_count -eq 0 ]]; then
        echo
        echo "ERROR: No services were successfully installed."
        exit 1
    elif [[ $failed_count -gt 0 ]]; then
        echo
        echo "WARNING: Some services failed to install. Check the output above for details."
        echo "Continuing with successfully installed services."
    fi

    # Store installed services for later use
    INSTALLED_SERVICES=()
    if [[ ${#installed_services[@]} -gt 0 ]]; then
        INSTALLED_SERVICES=("${installed_services[@]}")
        echo "DEBUG: Stored ${#INSTALLED_SERVICES[@]} services for later use"
    else
        echo "DEBUG: No services were installed successfully"
    fi
    echo "DEBUG: Exiting install_services function"
}

enable_and_start_services() {
    if [[ ${#INSTALLED_SERVICES[@]} -eq 0 ]]; then
        echo "No services to start."
        return 0
    fi

    echo
    echo "=== Enabling and Starting Services ==="

    local enabled_count=0
    local started_count=0
    local failed_count=0

    for service in "${INSTALLED_SERVICES[@]}"; do
        echo
        echo "Enabling service: $service"
        if sudo systemctl enable "$service" &> /dev/null; then
            echo "✓ Enabled: $service"
            ((enabled_count++))
        else
            echo "✗ Failed to enable: $service"
            ((failed_count++))
            continue
        fi

        echo "Starting service: $service"
        if sudo systemctl start "$service" &> /dev/null; then
            echo "✓ Started: $service"
            ((started_count++))
        else
            echo "✗ Failed to start: $service"
            ((failed_count++))
        fi
    done

    echo
    echo "=== Service Startup Summary ==="
    echo "Services enabled: $enabled_count"
    echo "Services started: $started_count"
    echo "Services failed: $failed_count"

    if [[ $failed_count -gt 0 ]]; then
        echo
        echo "Some services failed to start. Check individual service status with:"
        echo "  sudo systemctl status <service-name>"
    fi
}

verify_services_running() {
    if [[ ${#INSTALLED_SERVICES[@]} -eq 0 ]]; then
        return 0
    fi

    echo
    echo "=== Verifying Services ==="
    echo "Waiting for services to initialize..."
    sleep 5

    local running_count=0
    local failed_count=0
    local max_attempts=12  # 60 seconds total (5 second intervals)
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        running_count=0
        failed_count=0

        echo
        echo "Verification attempt $attempt/$max_attempts:"

        for service in "${INSTALLED_SERVICES[@]}"; do
            if systemctl is-active "$service" &> /dev/null; then
                echo "✓ Running: $service"
                ((running_count++))
            else
                echo "⏳ Not ready: $service"
                ((failed_count++))
            fi
        done

        if [[ $failed_count -eq 0 ]]; then
            echo
            echo "✓ All services are running successfully!"
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            echo "Waiting 5 seconds before next check..."
            sleep 5
        fi

        ((attempt++))
    done

    echo
    echo "⚠️  Service verification completed with issues:"
    echo "Services running: $running_count"
    echo "Services not ready: $failed_count"
    echo
    echo "Services that are not ready may need additional time to start."
    echo "Check individual service status with:"
    echo "  sudo systemctl status <service-name>"
    echo "  docker logs <container-name>"

    return 1
}

display_service_urls() {
    if [[ ${#INSTALLED_SERVICES[@]} -eq 0 ]]; then
        return 0
    fi

    local host_ip=$(get_host_ip)
    echo
    echo "=== Service Web Interfaces ==="
    echo "Access your services at the following URLs:"
    echo

    for service in "${INSTALLED_SERVICES[@]}"; do
        local service_name="${service#bragi.}"  # Remove bragi. prefix
        local url=""

        case "$service_name" in
            "sabnzbd")
                url="http://$host_ip:8080"
                echo "  SABnzbd:  $url"
                ;;
            "sonarr")
                url="http://$host_ip:8989/sonarr"
                echo "  Sonarr:   $url"
                ;;
            "radarr")
                url="http://$host_ip:7878/radarr"
                echo "  Radarr:   $url"
                ;;
            *)
                echo "  $service_name: (check service documentation for port)"
                ;;
        esac
    done

    echo
    if [[ "$host_ip" != "localhost" ]]; then
        echo "Note: These URLs use the detected IP address ($host_ip)."
        echo "      You can also access services using 'localhost' from this machine."
    else
        echo "Note: Could not detect IP address. Services are accessible via localhost."
        echo "      From other machines, replace 'localhost' with this machine's IP address."
    fi
}

main() {
    echo "Checking prerequisites..."
    check_docker
    check_systemd
    check_permissions

    configure_media_directories
    create_media_directories

    echo "DEBUG: Starting service installation..."
    install_services
    echo "DEBUG: Service installation completed, starting service enablement..."
    enable_and_start_services
    echo "DEBUG: Service enablement completed, starting verification..."

    local verification_success=true
    if ! verify_services_running; then
        verification_success=false
    fi
    echo "DEBUG: Service verification completed"

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
