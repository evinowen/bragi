#!/bin/bash

ENABLED_SERVICES=(__ENABLED_SERVICES__)

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; }

check() {
    local description="$1"
    shift
    if "$@" &>/dev/null; then
        pass "$description"
    else
        fail "$description"
    fi
}

is_enabled() {
    local svc="$1"
    for s in "${ENABLED_SERVICES[@]}"; do
        [[ "$s" == "$svc" ]] && return 0
    done
    return 1
}

check_http() {
    local description="$1"
    local url="$2"
    local attempt=1
    local status

    while [[ $attempt -le 12 ]]; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -L "$url")
        if [[ "$status" == "200" ]]; then
            pass "$description"
            return
        fi
        sleep 5
        attempt=$((attempt + 1))
    done

    fail "$description (got HTTP $status after 60s)"
}

for svc in "${ENABLED_SERVICES[@]}"; do
    check "Unit file exists: bragi.$svc.service" \
        test -f "/etc/systemd/system/bragi.$svc.service"
done

for svc in "${ENABLED_SERVICES[@]}"; do
    check "Service enabled: bragi.$svc" \
        bash -c "systemctl is-enabled bragi.$svc 2>/dev/null | grep -qx 'enabled'"
done

for svc in "${ENABLED_SERVICES[@]}"; do
    check "Service active: bragi.$svc" \
        bash -c "systemctl is-active bragi.$svc 2>/dev/null | grep -qx 'active'"
done

for svc in "${ENABLED_SERVICES[@]}"; do
    check "Docker container exists: bragi.$svc" \
        bash -c "docker ps -a --format '{{.Names}}' | grep -qx 'bragi.$svc'"
done

for svc in "${ENABLED_SERVICES[@]}"; do
    check "Data directory exists: /opt/$svc" test -d "/opt/$svc"
done

for dir in \
    /media/television/download \
    /media/television/stage \
    /media/television/library \
    /media/movies/download \
    /media/movies/stage \
    /media/movies/library
do
    check "Media directory exists: $dir" test -d "$dir"
done

nginx_enabled=false
is_enabled nginx && nginx_enabled=true

for svc in "${ENABLED_SERVICES[@]}"; do
    case "$svc" in
        sabnzbd)
            check_http "HTTP 200: SABnzbd"          "http://localhost:8080"
            if [[ "$nginx_enabled" == "true" ]]; then
                check_http "HTTP 200: Nginx -> SABnzbd"  "http://localhost/sabnzbd"
            fi
            ;;
        sonarr)
            check_http "HTTP 200: Sonarr"           "http://localhost:8989/sonarr"
            if [[ "$nginx_enabled" == "true" ]]; then
                check_http "HTTP 200: Nginx -> Sonarr"   "http://localhost/sonarr"
            fi
            ;;
        radarr)
            check_http "HTTP 200: Radarr"           "http://localhost:7878/radarr"
            if [[ "$nginx_enabled" == "true" ]]; then
                check_http "HTTP 200: Nginx -> Radarr"   "http://localhost/radarr"
            fi
            ;;
        jellyfin)
            check_http "HTTP 200: Jellyfin"         "http://localhost:8096/jellyfin/health"
            if [[ "$nginx_enabled" == "true" ]]; then
                check_http "HTTP 200: Nginx -> Jellyfin" "http://localhost/jellyfin/health"
            fi
            ;;
    esac
done
