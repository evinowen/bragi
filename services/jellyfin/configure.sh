#!/bin/bash

set -euo pipefail

BASE_URL="http://localhost:8096"

wait_for_service() {
    local max_attempts=24
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "${BASE_URL}/health" 2>/dev/null || true)

        if [[ "$status" == "200" ]]; then
            return 0
        fi

        sleep 5
        attempt=$((attempt + 1))
    done

    return 1
}

complete_startup_wizard() {
    echo "Completing Jellyfin startup wizard..."

    if python3 << PYEOF
import json, urllib.request, sys

base_url = '${BASE_URL}'
admin_username = '${ADMIN_USERNAME:-admin}'
admin_password = '${ADMIN_PASSWORD:-}'

try:
    data = json.dumps({"MetadataCountryCode": "US", "PreferredMetadataLanguage": "en", "UICulture": "en-US"}).encode()
    req = urllib.request.Request(
        base_url + '/Startup/Configuration',
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    urllib.request.urlopen(req)

    data = json.dumps({"Name": admin_username, "Password": admin_password}).encode()
    req = urllib.request.Request(
        base_url + '/Startup/User',
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    urllib.request.urlopen(req)

    data = json.dumps({"EnableRemoteAccess": True, "EnableAutomaticPortMapping": False}).encode()
    req = urllib.request.Request(
        base_url + '/Startup/RemoteAccess',
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    urllib.request.urlopen(req)

    req = urllib.request.Request(
        base_url + '/Startup/Complete',
        data=b'',
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    urllib.request.urlopen(req)

    sys.exit(0)
except Exception as e:
    print('Error: ' + str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        echo "✓ Startup wizard completed"
    else
        echo "⚠️  Failed to complete startup wizard"
        return 1
    fi
}

configure_base_url() {
    echo "Configuring Jellyfin base URL..."

    if python3 << PYEOF
import json, urllib.request, sys

base_url = '${BASE_URL}'
admin_username = '${ADMIN_USERNAME:-admin}'
admin_password = '${ADMIN_PASSWORD:-}'
auth_header = 'MediaBrowser Client="Bragi", Device="bragi-setup", DeviceId="bragi-configure", Version="1.0"'

try:
    data = json.dumps({"Username": admin_username, "Pw": admin_password}).encode()
    req = urllib.request.Request(
        base_url + '/Users/AuthenticateByName',
        data=data,
        headers={'Content-Type': 'application/json', 'Authorization': auth_header},
        method='POST'
    )
    with urllib.request.urlopen(req) as r:
        auth = json.loads(r.read())

    token = auth['AccessToken']
    auth_token_header = auth_header + ', Token="' + token + '"'

    req = urllib.request.Request(
        base_url + '/System/Configuration/network',
        headers={'Authorization': auth_token_header}
    )
    with urllib.request.urlopen(req) as r:
        network_config = json.loads(r.read())

    network_config['BaseUrl'] = '/jellyfin'

    data = json.dumps(network_config).encode()
    req = urllib.request.Request(
        base_url + '/System/Configuration/network',
        data=data,
        headers={'Content-Type': 'application/json', 'Authorization': auth_token_header},
        method='POST'
    )
    urllib.request.urlopen(req)

    sys.exit(0)
except Exception as e:
    print('Error: ' + str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        echo "✓ Jellyfin base URL configured (/jellyfin)"
    else
        echo "⚠️  Failed to configure Jellyfin base URL"
    fi
}

main() {
    echo "Waiting for Jellyfin..."

    if ! wait_for_service; then
        echo "⚠️  Jellyfin did not become ready — skipping configuration"
        exit 0
    fi

    if ! complete_startup_wizard; then
        echo "⚠️  Startup wizard failed — skipping remaining configuration"
        exit 0
    fi

    configure_base_url

    echo "Restarting Jellyfin to apply base URL..."
    sudo systemctl restart bragi.jellyfin
    sleep 20
    echo "✓ Jellyfin configuration complete"
}

main "$@"
