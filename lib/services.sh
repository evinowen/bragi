declare -A SERVICE_ENABLED

select_services() {
    echo
    echo "=== Service Selection ==="

    local -a available_services=()

    for service_dir in "$SERVICES_DIR"/*; do
        if [[ -d "$service_dir" ]]; then
            available_services+=("$(basename "$service_dir")")
        fi
    done

    for service in "${available_services[@]}"; do
        SERVICE_ENABLED[$service]="true"
    done

    local selection=""

    while [[ "$selection" != "a" && "$selection" != "c" ]]; do
        echo "Install options:"
        echo "  [a] All services (recommended)"
        echo "  [c] Choose services individually"
        echo -n "Install all services? [A/c]: "
        read selection </dev/tty
        selection=$(echo "${selection:-a}" | tr '[:upper:]' '[:lower:]')

        if [[ -z "$selection" ]]; then
            selection="a"
        fi

        if [[ "$selection" != "a" && "$selection" != "c" ]]; then
            echo "  Please enter 'a' for all or 'c' to choose individually."
        fi
    done

    if [[ "$selection" == "c" ]]; then
        echo
        echo "Select which services to install:"

        for service in "${available_services[@]}"; do
            local response=""

            while [[ "$response" != "y" && "$response" != "n" && "$response" != "" ]]; do
                echo -n "  Install $service? [Y/n]: "
                read response </dev/tty
                response=$(echo "${response:-y}" | tr '[:upper:]' '[:lower:]')
            done

            if [[ "$response" == "n" ]]; then
                SERVICE_ENABLED[$service]="false"
            fi
        done
    fi

    echo
    echo "Services selected:"

    for service in "${available_services[@]}"; do
        if [[ "${SERVICE_ENABLED[$service]:-true}" == "true" ]]; then
            echo "  ✓ $service"
        else
            echo "  - $service (disabled)"
        fi
    done
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

            if [[ "${SERVICE_ENABLED[$service_name]:-true}" == "false" ]]; then
                echo
                echo "Skipping disabled service: $service_name"
                continue
            fi

            echo
            echo "Installing service: $service_name"

            if [[ -f "$install_script" ]]; then
                export TELEVISION_DOWNLOADS_DIR TELEVISION_STAGING_DIR TELEVISION_LIBRARY_DIR
                export MOVIE_DOWNLOADS_DIR MOVIE_STAGING_DIR MOVIE_LIBRARY_DIR

                echo "Running installation script for $service_name..."

                if bash "$install_script" 2>&1; then
                    echo "✓ Successfully installed: $service_name"
                    installed_services+=("bragi.$service_name")
                    service_count=$((service_count + 1))
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

    INSTALLED_SERVICES=()

    if [[ ${#installed_services[@]} -gt 0 ]]; then
        INSTALLED_SERVICES=("${installed_services[@]}")
    fi
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
    local max_attempts=12
    local attempt=1
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

configure_services() {
    echo
    echo "=== Configuring Services ==="

    INDEXERS_JSON="${INDEXERS_JSON:-[]}"
    export ADMIN_USERNAME ADMIN_PASSWORD INDEXERS_JSON

    for service_dir in "$SERVICES_DIR"/*; do
        if [[ -d "$service_dir" ]]; then
            local configure_script="$service_dir/configure.sh"

            if [[ -f "$configure_script" ]]; then
                local service_name=$(basename "$service_dir")

                if [[ "${SERVICE_ENABLED[$service_name]:-true}" == "false" ]]; then
                    continue
                fi

                echo
                echo "Configuring service: $service_name"
                bash "$configure_script" 2>&1 || true
            fi
        fi
    done
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

    local has_nginx=false

    for service in "${INSTALLED_SERVICES[@]}"; do
        if [[ "${service#bragi.}" == "nginx" ]]; then
            has_nginx=true
            break
        fi
    done

    for service in "${INSTALLED_SERVICES[@]}"; do
        local service_name="${service#bragi.}"

        case "$service_name" in
            "nginx")
                echo "  Nginx:    http://$host_ip (reverse proxy)"
                ;;
            "sabnzbd")
                if [[ "$has_nginx" == "true" ]]; then
                    echo "  SABnzbd:      http://$host_ip/sabnzbd"
                else
                    echo "  SABnzbd:      http://$host_ip:8080"
                fi
                ;;
            "transmission")
                if [[ "$has_nginx" == "true" ]]; then
                    echo "  Transmission: http://$host_ip/transmission/web/"
                else
                    echo "  Transmission: http://$host_ip:9091/transmission/web/"
                fi
                ;;
            "sonarr")
                if [[ "$has_nginx" == "true" ]]; then
                    echo "  Sonarr:   http://$host_ip/sonarr"
                else
                    echo "  Sonarr:   http://$host_ip:8989/sonarr"
                fi
                ;;
            "radarr")
                if [[ "$has_nginx" == "true" ]]; then
                    echo "  Radarr:   http://$host_ip/radarr"
                else
                    echo "  Radarr:   http://$host_ip:7878/radarr"
                fi
                ;;
            "jellyfin")
                if [[ "$has_nginx" == "true" ]]; then
                    echo "  Jellyfin: http://$host_ip/jellyfin"
                else
                    echo "  Jellyfin: http://$host_ip:8096"
                fi
                ;;
            "plex")
                if [[ "$has_nginx" == "true" ]]; then
                    echo "  Plex:     http://$host_ip/plex/web"
                else
                    echo "  Plex:     http://$host_ip:32400/web"
                fi
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
