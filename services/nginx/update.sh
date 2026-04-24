#!/bin/bash

set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

source "$SERVICE_DIR/add.sh"

echo "Updating Nginx..."
pull_image
sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
stop_existing_container
create_container
sudo systemctl start "$SERVICE_NAME"
echo
echo "✓ Nginx updated successfully!"
