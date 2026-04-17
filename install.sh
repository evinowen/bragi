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

# Usenet server configuration
USENET_HOST=""
USENET_USERNAME=""
USENET_PASSWORD=""
USENET_SSL="yes"

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

configure_usenet() {
    echo
    echo "=== Usenet Server Configuration ==="
    echo "Enter your Usenet provider connection details."
    echo "These will be configured automatically in SABnzbd."
    echo

    echo -n "  Server host: "
    read USENET_HOST </dev/tty

    echo -n "  Username: "
    read USENET_USERNAME </dev/tty

    echo -n "  Password: "
    read -s USENET_PASSWORD </dev/tty
    echo

    echo -n "  Enable SSL? [Y/n]: "
    read usenet_ssl_input </dev/tty
    if [[ "${usenet_ssl_input:-}" =~ ^[Nn]$ ]]; then
        USENET_SSL="no"
    else
        USENET_SSL="yes"
    fi

    echo
    echo "Usenet Configuration Summary:"
    echo "  Host:    $USENET_HOST"
    echo "  Login:   $USENET_USERNAME"
    echo "  SSL:     $USENET_SSL"

    export USENET_HOST USENET_USERNAME USENET_PASSWORD USENET_SSL
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
                created_count=$((created_count + 1))
            else
                echo "✗ Failed to create: $dir"
                failed_count=$((failed_count + 1))
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

    echo "DEBUG: Initialized service_count=$service_count, failed_count=$failed_count"

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
                    echo "DEBUG: Adding bragi.$service_name to installed_services array"
                    installed_services+=("bragi.$service_name")
                    echo "DEBUG: Incrementing service_count from $service_count"
                    service_count=$((service_count + 1))
                    echo "DEBUG: service_count is now $service_count"
                else
                    local exit_code=$?
                    echo "✗ Failed to install: $service_name (exit code: $exit_code)"
                    echo "  Installation script: $install_script"
                    echo "  Check the error output above for details"
                    failed_count=$((failed_count + 1))
                fi
            else
                echo "✗ No add script found: $install_script"
                failed_count=$((failed_count + 1))
            fi
        else
            echo "DEBUG: Skipping non-directory: $service_dir"
        fi
        echo "DEBUG: Completed processing $service_dir, continuing to next service..."
    done
    echo "DEBUG: Finished processing all services in loop"

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
            enabled_count=$((enabled_count + 1))
        else
            echo "✗ Failed to enable: $service"
            failed_count=$((failed_count + 1))
            continue
        fi

        echo "Starting service: $service"
        if sudo systemctl start "$service" &> /dev/null; then
            echo "✓ Started: $service"
            started_count=$((started_count + 1))
        else
            echo "✗ Failed to start: $service"
            failed_count=$((failed_count + 1))
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

    # Track services that have been restarted to avoid infinite restart loops
    local -A restart_attempts=()

    while [[ $attempt -le $max_attempts ]]; do
        running_count=0
        failed_count=0

        echo
        echo "Verification attempt $attempt/$max_attempts:"

        for service in "${INSTALLED_SERVICES[@]}"; do
            local service_state=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")

            case "$service_state" in
                "active")
                    echo "✓ Running: $service"
                    running_count=$((running_count + 1))
                    ;;
                "activating")
                    echo "⏳ Starting: $service (activating)"
                    failed_count=$((failed_count + 1))
                    ;;
                "inactive"|"failed"|"unknown")
                    # Check if we've already tried to restart this service
                    if [[ -z "${restart_attempts[$service]:-}" ]]; then
                        echo "🔄 Restarting: $service (state: $service_state)"
                        if sudo systemctl restart "$service" &>/dev/null; then
                            echo "   Restart command sent for $service"
                            restart_attempts[$service]=1
                        else
                            echo "   Failed to restart $service"
                        fi
                    else
                        echo "✗ Failed: $service (state: $service_state, restart attempted)"
                    fi
                    failed_count=$((failed_count + 1))
                    ;;
                *)
                    echo "❓ Unknown state: $service ($service_state)"
                    failed_count=$((failed_count + 1))
                    ;;
            esac
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

        attempt=$((attempt + 1))
    done

    echo
    echo "⚠️  Service verification completed with issues:"
    echo "Services running: $running_count"
    echo "Services not ready: $failed_count"
    echo
    echo "Services that failed to start:"
    for service in "${INSTALLED_SERVICES[@]}"; do
        local service_state=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
        if [[ "$service_state" != "active" ]]; then
            echo "  - $service (state: $service_state)"
        fi
    done
    echo
    echo "Check individual service status with:"
    echo "  sudo systemctl status <service-name>"
    echo "  docker logs <container-name>"

    return 1
}

configure_download_clients() {
    echo
    echo "=== Configuring Download Clients ==="

    local sabnzbd_api_key
    sabnzbd_api_key=$(grep -oP '^api_key\s*=\s*\K\S+' /opt/sabnzbd/config/sabnzbd.ini 2>/dev/null || true)

    if [[ -z "$sabnzbd_api_key" ]]; then
        echo "⚠️  SABnzbd API key not found — skipping download client configuration"
        return 0
    fi

    local docker_gateway
    docker_gateway=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")

    configure_sonarr_download_client "$sabnzbd_api_key" "$docker_gateway"
    configure_radarr_download_client "$sabnzbd_api_key" "$docker_gateway"
}

wait_for_api() {
    local url="$1"
    local api_key="$2"
    local max_attempts=12
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            -H "X-Api-Key: ${api_key}" "$url" 2>/dev/null || true)
        if [[ "$status" =~ ^2 ]]; then
            return 0
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
    return 1
}

configure_sonarr_download_client() {
    local sabnzbd_api_key="$1"
    local sabnzbd_host="$2"

    local sonarr_api_key
    sonarr_api_key=$(grep -oP '<ApiKey>\K[^<]+' /opt/sonarr/config/config.xml 2>/dev/null || true)

    if [[ -z "$sonarr_api_key" ]]; then
        echo "⚠️  Sonarr API key not found — skipping"
        return 0
    fi

    echo "Waiting for Sonarr API..."
    if ! wait_for_api "http://localhost:8989/sonarr/api/v3/system/status" "$sonarr_api_key"; then
        echo "⚠️  Sonarr API did not become ready — skipping download client configuration"
        return 0
    fi

    local payload
    payload=$(printf '{
  "enable": true,
  "protocol": "usenet",
  "priority": 1,
  "removeCompletedDownloads": true,
  "removeFailedDownloads": true,
  "name": "SABnzbd",
  "fields": [
    {"name": "host", "value": "%s"},
    {"name": "port", "value": 8080},
    {"name": "apiKey", "value": "%s"},
    {"name": "tvCategory", "value": "television"},
    {"name": "recentTvPriority", "value": 0},
    {"name": "olderTvPriority", "value": 0},
    {"name": "useSsl", "value": false}
  ],
  "implementationName": "SABnzbd",
  "implementation": "Sabnzbd",
  "configContract": "SabnzbdSettings",
  "tags": []
}' "$sabnzbd_host" "$sabnzbd_api_key")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "http://localhost:8989/sonarr/api/v3/downloadclient" \
        -H "X-Api-Key: ${sonarr_api_key}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ SABnzbd configured as download client in Sonarr"
    else
        echo "⚠️  Failed to configure download client in Sonarr (HTTP $status)"
    fi
}

configure_radarr_download_client() {
    local sabnzbd_api_key="$1"
    local sabnzbd_host="$2"

    local radarr_api_key
    radarr_api_key=$(grep -oP '<ApiKey>\K[^<]+' /opt/radarr/config/config.xml 2>/dev/null || true)

    if [[ -z "$radarr_api_key" ]]; then
        echo "⚠️  Radarr API key not found — skipping"
        return 0
    fi

    echo "Waiting for Radarr API..."
    if ! wait_for_api "http://localhost:7878/radarr/api/v3/system/status" "$radarr_api_key"; then
        echo "⚠️  Radarr API did not become ready — skipping download client configuration"
        return 0
    fi

    local payload
    payload=$(printf '{
  "enable": true,
  "protocol": "usenet",
  "priority": 1,
  "removeCompletedDownloads": true,
  "removeFailedDownloads": true,
  "name": "SABnzbd",
  "fields": [
    {"name": "host", "value": "%s"},
    {"name": "port", "value": 8080},
    {"name": "apiKey", "value": "%s"},
    {"name": "movieCategory", "value": "movies"},
    {"name": "recentMoviePriority", "value": 0},
    {"name": "olderMoviePriority", "value": 0},
    {"name": "useSsl", "value": false}
  ],
  "implementationName": "SABnzbd",
  "implementation": "Sabnzbd",
  "configContract": "SabnzbdSettings",
  "tags": []
}' "$sabnzbd_host" "$sabnzbd_api_key")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "http://localhost:7878/radarr/api/v3/downloadclient" \
        -H "X-Api-Key: ${radarr_api_key}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ SABnzbd configured as download client in Radarr"
    else
        echo "⚠️  Failed to configure download client in Radarr (HTTP $status)"
    fi
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

    configure_usenet
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

    configure_download_clients

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
