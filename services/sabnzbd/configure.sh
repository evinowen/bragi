#!/bin/bash

set -euo pipefail

API_KEY=$(grep -oP '^api_key\s*=\s*\K\S+' /opt/sabnzbd/config/sabnzbd.ini 2>/dev/null || true)
BASE_URL="http://localhost:8080/sabnzbd/api"

wait_for_api() {
    local max_attempts=12
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "${BASE_URL}?mode=version&output=json&apikey=${API_KEY}" 2>/dev/null || true)
        if [[ "$status" =~ ^2 ]]; then
            return 0
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
    return 1
}

configure_speed_limit() {
    local max_speed="${SABNZBD_MAX_DOWNLOAD_SPEED:-}"
    if [[ -z "$max_speed" ]]; then
        echo "- No download speed limit configured"
        return 0
    fi

    echo "Configuring SABnzbd download speed limit..."
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        "${BASE_URL}?mode=set_config&section=misc&keyword=speed_limit&value=${max_speed}&apikey=${API_KEY}")

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ SABnzbd download speed limit set to ${max_speed}"
    else
        echo "⚠️  Failed to configure download speed limit (HTTP $status)"
    fi
}

main() {
    if [[ -z "$API_KEY" ]]; then
        echo "⚠️  SABnzbd API key not found — skipping configuration"
        exit 0
    fi

    echo "Waiting for SABnzbd API..."
    if ! wait_for_api; then
        echo "⚠️  SABnzbd API did not become ready — skipping configuration"
        exit 0
    fi

    configure_speed_limit
}

main "$@"
