#!/bin/bash

set -euo pipefail

TRANSMISSION_HOST="transmission.bragi"
TRANSMISSION_PORT=9091
TRANSMISSION_URL_BASE="/transmission/"

SONARR_API_KEY=$(grep -oP '<ApiKey>\K[^<]+' /opt/sonarr/config/config.xml 2>/dev/null || true)
SONARR_BASE_URL="http://localhost:8989/sonarr/api/v3"
RADARR_API_KEY=$(grep -oP '<ApiKey>\K[^<]+' /opt/radarr/config/config.xml 2>/dev/null || true)
RADARR_BASE_URL="http://localhost:7878/radarr/api/v3"

TRANSMISSION_USER="${ADMIN_USERNAME:-}"
TRANSMISSION_PASS="${ADMIN_PASSWORD:-}"

is_service_enabled() {
    [[ -z "${ENABLED_SERVICES:-}" ]] && return 0
    [[ " $ENABLED_SERVICES " == *" $1 "* ]]
}

wait_for_transmission() {
    local max_attempts=12
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "http://localhost:${TRANSMISSION_PORT}/transmission/web/" 2>/dev/null || true)
        if [[ "$status" == "200" || "$status" == "401" ]]; then
            return 0
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
    return 1
}

configure_transmission_download_dir() {
    echo "Configuring Transmission default download directory..."

    local auth_flag=()
    if [[ -n "$TRANSMISSION_USER" ]]; then
        auth_flag=(-u "${TRANSMISSION_USER}:${TRANSMISSION_PASS}")
    fi

    local session_id
    session_id=$(curl -s -i "${auth_flag[@]}" -X POST \
        -d '{"method":"session-get"}' \
        "http://localhost:${TRANSMISSION_PORT}/transmission/rpc" 2>/dev/null \
        | grep -i "^X-Transmission-Session-Id:" \
        | awk '{print $2}' \
        | tr -d '\r\n')

    if [[ -z "$session_id" ]]; then
        echo "⚠️  Failed to get Transmission session ID"
        return 1
    fi

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "${auth_flag[@]}" -X POST \
        -H "X-Transmission-Session-Id: ${session_id}" \
        -d '{"method":"session-set","arguments":{"download-dir":"/downloads"}}' \
        "http://localhost:${TRANSMISSION_PORT}/transmission/rpc")

    if [[ "$status" == "200" ]]; then
        echo "✓ Transmission download directory set to /downloads"
    else
        echo "⚠️  Failed to set Transmission download directory (HTTP $status)"
    fi
}

configure_sonarr_download_client() {
    if ! is_service_enabled sonarr; then
        echo "- Sonarr is disabled — skipping Sonarr download client configuration"
        return 0
    fi

    if [[ -z "$SONARR_API_KEY" ]]; then
        echo "- Sonarr API key not found — skipping Sonarr download client configuration"
        return 0
    fi

    echo "Configuring Transmission as download client in Sonarr..."
    local payload
    payload=$(printf '{
  "enable": true,
  "protocol": "torrent",
  "priority": 1,
  "removeCompletedDownloads": true,
  "removeFailedDownloads": true,
  "name": "Transmission",
  "fields": [
    {"name": "host",               "value": "%s"},
    {"name": "port",               "value": %d},
    {"name": "urlBase",            "value": "%s"},
    {"name": "username",           "value": "%s"},
    {"name": "password",           "value": "%s"},
    {"name": "tvDirectory",        "value": ""},
    {"name": "tvCategory",         "value": "television"},
    {"name": "tvImportedCategory", "value": ""},
    {"name": "recentTvPriority",   "value": 0},
    {"name": "olderTvPriority",    "value": 0},
    {"name": "addPaused",          "value": false},
    {"name": "useSsl",             "value": false}
  ],
  "implementationName": "Transmission",
  "implementation": "Transmission",
  "configContract": "TransmissionSettings",
  "tags": []
}' "$TRANSMISSION_HOST" "$TRANSMISSION_PORT" "$TRANSMISSION_URL_BASE" \
   "$TRANSMISSION_USER" "$TRANSMISSION_PASS")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "${SONARR_BASE_URL}/downloadclient" \
        -H "X-Api-Key: ${SONARR_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ Transmission configured as download client in Sonarr"
    else
        echo "⚠️  Failed to configure Transmission download client in Sonarr (HTTP $status)"
    fi
}

configure_sonarr_remote_path_mapping() {
    if ! is_service_enabled sonarr; then
        return 0
    fi

    if [[ -z "$SONARR_API_KEY" ]]; then
        return 0
    fi

    echo "Configuring Sonarr remote path mapping for Transmission..."
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "${SONARR_BASE_URL}/remotepathmapping" \
        -H "X-Api-Key: ${SONARR_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"host\": \"${TRANSMISSION_HOST}\", \"remotePath\": \"/downloads/television\", \"localPath\": \"/downloads\"}")

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ Sonarr remote path mapping configured for Transmission"
    else
        echo "⚠️  Failed to configure Sonarr remote path mapping for Transmission (HTTP $status)"
    fi
}

configure_radarr_download_client() {
    if ! is_service_enabled radarr; then
        echo "- Radarr is disabled — skipping Radarr download client configuration"
        return 0
    fi

    if [[ -z "$RADARR_API_KEY" ]]; then
        echo "- Radarr API key not found — skipping Radarr download client configuration"
        return 0
    fi

    echo "Configuring Transmission as download client in Radarr..."
    local payload
    payload=$(printf '{
  "enable": true,
  "protocol": "torrent",
  "priority": 1,
  "removeCompletedDownloads": true,
  "removeFailedDownloads": true,
  "name": "Transmission",
  "fields": [
    {"name": "host",                  "value": "%s"},
    {"name": "port",                  "value": %d},
    {"name": "urlBase",               "value": "%s"},
    {"name": "username",              "value": "%s"},
    {"name": "password",              "value": "%s"},
    {"name": "movieDirectory",        "value": ""},
    {"name": "movieCategory",         "value": "movies"},
    {"name": "movieImportedCategory", "value": ""},
    {"name": "recentMoviePriority",   "value": 0},
    {"name": "olderMoviePriority",    "value": 0},
    {"name": "addPaused",             "value": false},
    {"name": "useSsl",                "value": false}
  ],
  "implementationName": "Transmission",
  "implementation": "Transmission",
  "configContract": "TransmissionSettings",
  "tags": []
}' "$TRANSMISSION_HOST" "$TRANSMISSION_PORT" "$TRANSMISSION_URL_BASE" \
   "$TRANSMISSION_USER" "$TRANSMISSION_PASS")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "${RADARR_BASE_URL}/downloadclient" \
        -H "X-Api-Key: ${RADARR_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ Transmission configured as download client in Radarr"
    else
        echo "⚠️  Failed to configure Transmission download client in Radarr (HTTP $status)"
    fi
}

configure_radarr_remote_path_mapping() {
    if ! is_service_enabled radarr; then
        return 0
    fi

    if [[ -z "$RADARR_API_KEY" ]]; then
        return 0
    fi

    echo "Configuring Radarr remote path mapping for Transmission..."
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "${RADARR_BASE_URL}/remotepathmapping" \
        -H "X-Api-Key: ${RADARR_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"host\": \"${TRANSMISSION_HOST}\", \"remotePath\": \"/downloads/movies\", \"localPath\": \"/downloads\"}")

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ Radarr remote path mapping configured for Transmission"
    else
        echo "⚠️  Failed to configure Radarr remote path mapping for Transmission (HTTP $status)"
    fi
}

main() {
    echo "Waiting for Transmission..."
    if ! wait_for_transmission; then
        echo "⚠️  Transmission did not become ready — skipping configuration"
        exit 0
    fi
    echo "✓ Transmission is ready"

    configure_transmission_download_dir
    configure_sonarr_download_client
    configure_sonarr_remote_path_mapping
    configure_radarr_download_client
    configure_radarr_remote_path_mapping
}

main "$@"
