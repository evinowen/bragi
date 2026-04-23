#!/bin/bash

set -euo pipefail

API_KEY=$(grep -oP '<ApiKey>\K[^<]+' /opt/sonarr/config/config.xml 2>/dev/null || true)
BASE_URL="http://localhost:8989/sonarr/api/v3"
SABNZBD_API_KEY=$(grep -oP '^api_key\s*=\s*\K\S+' /opt/sabnzbd/config/sabnzbd.ini 2>/dev/null || true)
SABNZBD_HOST="sabnzbd.bragi"

wait_for_api() {
    local max_attempts=12
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            -H "X-Api-Key: ${API_KEY}" "${BASE_URL}/system/status" 2>/dev/null || true)
        if [[ "$status" =~ ^2 ]]; then
            return 0
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
    return 1
}

configure_auth() {
    echo "Configuring Sonarr authentication..."
    if python3 << PYEOF
import json, urllib.request, sys

api_key = '${API_KEY}'
base_url = '${BASE_URL}'

try:
    req = urllib.request.Request(base_url + '/config/host', headers={'X-Api-Key': api_key})
    with urllib.request.urlopen(req) as r:
        config = json.loads(r.read())

    config['authenticationMethod'] = 'forms'
    config['authenticationRequired'] = 'disabledForLocalAddresses'
    config['username'] = '${ADMIN_USERNAME:-admin}'
    config['password'] = '${ADMIN_PASSWORD:-}'
    config['passwordConfirmation'] = '${ADMIN_PASSWORD:-}'

    data = json.dumps(config).encode()
    req = urllib.request.Request(
        base_url + '/config/host',
        data=data,
        headers={'X-Api-Key': api_key, 'Content-Type': 'application/json'},
        method='PUT'
    )
    with urllib.request.urlopen(req) as r:
        sys.exit(0)
except Exception as e:
    print('Error: ' + str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        echo "✓ Sonarr authentication configured"
    else
        echo "⚠️  Failed to configure Sonarr authentication"
    fi
}

configure_metadata() {
    echo "Configuring Sonarr metadata..."
    if python3 << PYEOF
import json, urllib.request, sys

api_key = '${API_KEY}'
base_url = '${BASE_URL}'

try:
    req = urllib.request.Request(base_url + '/metadata', headers={'X-Api-Key': api_key})
    with urllib.request.urlopen(req) as r:
        providers = json.loads(r.read())

    for provider in providers:
        if provider.get('implementation') == 'XbmcMetadata':
            provider['enable'] = True
            data = json.dumps(provider).encode()
            req = urllib.request.Request(
                base_url + '/metadata/' + str(provider['id']),
                data=data,
                headers={'X-Api-Key': api_key, 'Content-Type': 'application/json'},
                method='PUT'
            )
            with urllib.request.urlopen(req) as r:
                sys.exit(0)

    print('Kodi metadata provider not found', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print('Error: ' + str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        echo "✓ Sonarr Kodi metadata enabled"
    else
        echo "⚠️  Failed to configure Sonarr metadata"
    fi
}

configure_root_folder() {
    echo "Configuring Sonarr root folder..."
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "${BASE_URL}/rootfolder" \
        -H "X-Api-Key: ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d '{"path": "/tv"}')

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ Sonarr root folder configured (/tv)"
    else
        echo "⚠️  Failed to configure Sonarr root folder (HTTP $status)"
    fi
}

configure_download_client() {
    if [[ -z "$SABNZBD_API_KEY" ]]; then
        echo "⚠️  SABnzbd API key not found — skipping download client configuration"
        return 0
    fi

    echo "Configuring Sonarr download client..."
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
}' "$SABNZBD_HOST" "$SABNZBD_API_KEY")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "${BASE_URL}/downloadclient" \
        -H "X-Api-Key: ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if [[ "$status" =~ ^2 ]]; then
        echo "✓ SABnzbd configured as download client in Sonarr"
    else
        echo "⚠️  Failed to configure download client in Sonarr (HTTP $status)"
    fi
}

main() {
    if [[ -z "$API_KEY" ]]; then
        echo "⚠️  Sonarr API key not found — skipping configuration"
        exit 0
    fi

    echo "Waiting for Sonarr API..."
    if ! wait_for_api; then
        echo "⚠️  Sonarr API did not become ready — skipping configuration"
        exit 0
    fi

    configure_auth
    configure_metadata
    configure_root_folder
    configure_download_client
}

main "$@"
