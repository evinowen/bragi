#!/bin/bash

set -euo pipefail

BASE_URL="http://localhost:32400"

wait_for_plex() {
    local max_attempts=24
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "${BASE_URL}/identity" 2>/dev/null || true)

        if [[ "$status" == "200" ]]; then
            return 0
        fi

        sleep 5
        attempt=$((attempt + 1))
    done

    return 1
}

configure_libraries() {
    echo "Configuring Plex media libraries..."

    if python3 << PYEOF
import json, urllib.request, urllib.parse, sys

base_url = '${BASE_URL}'

try:
    req = urllib.request.Request(base_url + '/library/sections')
    with urllib.request.urlopen(req) as r:
        data = json.loads(r.read())

    existing = {d.get('title', '') for d in data.get('MediaContainer', {}).get('Directory', [])}

    for title, lib_type, agent, scanner, path in [
        ('Television', 'show', 'tv.plex.agents.series', 'Plex TV Series', '/media/television'),
        ('Movies', 'movie', 'tv.plex.agents.movie', 'Plex Movie', '/media/movies'),
        ('Music', 'artist', 'tv.plex.agents.music', 'Plex Music', '/media/music'),
    ]:
        if title in existing:
            print('- Library already exists: ' + title)
            continue

        params = urllib.parse.urlencode([
            ('name', title),
            ('type', lib_type),
            ('agent', agent),
            ('scanner', scanner),
            ('language', 'en-US'),
            ('location[]', path),
        ])
        req = urllib.request.Request(
            base_url + '/library/sections',
            data=params.encode(),
            headers={'Content-Type': 'application/x-www-form-urlencoded'},
            method='POST'
        )
        urllib.request.urlopen(req)
        print('Added library: ' + title + ' -> ' + path)

except Exception as e:
    print('Error: ' + str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        echo "✓ Plex media libraries configured"
    else
        echo "⚠️  Failed to configure Plex media libraries"
        echo "   Libraries can be added manually through the Plex web interface at ${BASE_URL}/web"
    fi
}

main() {
    echo "Waiting for Plex to become ready..."

    if ! wait_for_plex; then
        echo "⚠️  Plex did not become ready — skipping configuration"
        exit 0
    fi

    configure_libraries
    echo "✓ Plex configuration complete"
}

main "$@"
