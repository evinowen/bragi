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

configure_sonarr_download_client() {
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
    {"name": "tvDirectory",        "value": "/downloads/television"},
    {"name": "tvCategory",         "value": ""},
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
    {"name": "movieDirectory",        "value": "/downloads/movies"},
    {"name": "movieCategory",         "value": ""},
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

    configure_sonarr_download_client
    configure_sonarr_remote_path_mapping
    configure_radarr_download_client
    configure_radarr_remote_path_mapping
}

main "$@"
