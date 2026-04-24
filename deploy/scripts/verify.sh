#!/bin/bash

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

for svc in nginx sabnzbd sonarr radarr jellyfin; do
    check "Unit file exists: bragi.$svc.service" \
        test -f "/etc/systemd/system/bragi.$svc.service"
done

for svc in nginx sabnzbd sonarr radarr jellyfin; do
    check "Service enabled: bragi.$svc" \
        bash -c "systemctl is-enabled bragi.$svc 2>/dev/null | grep -qx 'enabled'"
done

for svc in nginx sabnzbd sonarr radarr jellyfin; do
    check "Service active: bragi.$svc" \
        bash -c "systemctl is-active bragi.$svc 2>/dev/null | grep -qx 'active'"
done

for container in nginx sabnzbd sonarr radarr jellyfin; do
    check "Docker container exists: bragi.$container" \
        bash -c "docker ps -a --format '{{.Names}}' | grep -qx 'bragi.$container'"
done

for dir in /opt/nginx /opt/sabnzbd /opt/sonarr /opt/radarr /opt/jellyfin; do
    check "Data directory exists: $dir" test -d "$dir"
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

check_http "HTTP 200: SABnzbd"           "http://localhost:8080"
check_http "HTTP 200: Sonarr"            "http://localhost:8989/sonarr"
check_http "HTTP 200: Radarr"            "http://localhost:7878/radarr"
check_http "HTTP 200: Jellyfin"          "http://localhost:8096/jellyfin/health"
check_http "HTTP 200: Nginx -> SABnzbd"  "http://localhost/sabnzbd"
check_http "HTTP 200: Nginx -> Sonarr"   "http://localhost/sonarr"
check_http "HTTP 200: Nginx -> Radarr"   "http://localhost/radarr"
check_http "HTTP 200: Nginx -> Jellyfin" "http://localhost/jellyfin/health"
