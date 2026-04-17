#!/bin/bash

set -euo pipefail

# ============================================================
# Bragi Installation Test Script
#
# Creates a GCP Compute Engine instance, runs the bragi
# installer non-interactively via expect, and verifies that
# all services were installed and are running successfully.
#
# Usage:
#   export GCP_PROJECT_ID=your-project-id
#   ./test.sh
#
# Environment variables:
#   GCP_PROJECT_ID   - GCP project ID (required)
#   GCP_ZONE         - Compute zone (required)
#   GCP_MACHINE_TYPE - Machine type (default: e2-standard-2)
#   SKIP_CLEANUP     - Set to 'true' to keep the instance after the test
#   SETUP_FIREWALL   - Set to 'true' to create firewall rules for SSH and service ports
# ============================================================

# --- Configuration ---
if [[ -f "$(dirname "${BASH_SOURCE[0]:-$0}")/test.env" ]]; then
    set -a
    source "$(dirname "${BASH_SOURCE[0]:-$0}")/test.env"
    set +a
fi

PROJECT_ID="${GCP_PROJECT_ID:-}"
ZONE="${GCP_ZONE:-}"
MACHINE_TYPE="${GCP_MACHINE_TYPE:-e2-standard-2}"
INSTANCE_NAME="bragi-test-$(date +%s)"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"
DISK_SIZE="30GB"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
SETUP_FIREWALL="${SETUP_FIREWALL:-false}"

PASS=0
FAIL=0
INSTANCE_CREATED=false
INSTANCE_IP=""
NETWORK_TAG="bragi-test"
WORK_DIR="$(mktemp -d)"
SSH_KEY="$WORK_DIR/id_rsa"
SSH_USER="bragi"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Logging ---
log()         { echo -e "${CYAN}[TEST]${NC}  $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC}  $*"; PASS=$((PASS + 1)); }
log_failure() { echo -e "${RED}[FAIL]${NC}  $*"; FAIL=$((FAIL + 1)); }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

# --- Cleanup ---
cleanup() {
    rm -rf "$WORK_DIR"

    if [[ "$INSTANCE_CREATED" == "true" ]]; then
        if [[ "$SKIP_CLEANUP" == "true" ]]; then
            log_warn "SKIP_CLEANUP=true — instance '$INSTANCE_NAME' left running in zone $ZONE"
            log_warn "Delete it with:"
            log_warn "  gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID"
        else
            log "Deleting test instance: $INSTANCE_NAME"
            gcloud compute instances delete "$INSTANCE_NAME" \
                --zone="$ZONE" \
                --project="$PROJECT_ID" \
                --quiet 2>/dev/null || true
            log "Instance deleted"
        fi
    fi
}

trap cleanup EXIT

# --- SSH helpers ---
ssh_cmd() {
    ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 \
        -o BatchMode=yes \
        "${SSH_USER}@${INSTANCE_IP}" "$@"
}

scp_to() {
    local local_path="$1"
    local remote_path="$2"
    scp -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        "$local_path" "${SSH_USER}@${INSTANCE_IP}:${remote_path}"
}

generate_ssh_key() {
    log "Generating temporary SSH key pair..."
    ssh-keygen -t rsa -b 2048 -f "$SSH_KEY" -N "" -q
    log "SSH key generated"
}

inject_ssh_key() {
    local pub_key
    pub_key="$(cat "${SSH_KEY}.pub")"
    log "Injecting SSH public key into instance metadata..."
    gcloud compute instances add-metadata "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --metadata="ssh-keys=${SSH_USER}:${pub_key}" \
        --quiet
    log "SSH key injected"
}

# --- Prerequisites ---
check_prerequisites() {
    log "Checking local prerequisites..."

    if ! command -v gcloud &>/dev/null; then
        echo "ERROR: gcloud CLI is not installed."
        echo "  Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    if [[ -z "$PROJECT_ID" ]]; then
        echo "ERROR: GCP_PROJECT_ID is not set."
        echo "  export GCP_PROJECT_ID=your-project-id"
        exit 1
    fi

    log "Project:      $PROJECT_ID"
    log "Zone:         $ZONE"
    log "Machine type: $MACHINE_TYPE"
    log "Instance:     $INSTANCE_NAME"
}

# --- Firewall setup ---
ensure_firewall_rule() {
    local rule_name="$1"
    local ports="$2"

    if gcloud compute firewall-rules describe "$rule_name" \
        --project="$PROJECT_ID" &>/dev/null; then
        log "Firewall rule '$rule_name' already exists, skipping"
        return
    fi

    log "Creating firewall rule '$rule_name' ($ports)..."
    gcloud compute firewall-rules create "$rule_name" \
        --project="$PROJECT_ID" \
        --direction=INGRESS \
        --action=ALLOW \
        --rules="$ports" \
        --source-ranges=0.0.0.0/0 \
        --target-tags="$NETWORK_TAG" \
        --quiet
    log "Firewall rule '$rule_name' created"
}

setup_firewall() {
    if [[ "$SETUP_FIREWALL" != "true" ]]; then
        return
    fi

    ensure_firewall_rule "bragi-test-ssh"      "tcp:22"
    ensure_firewall_rule "bragi-test-services" "tcp:8080,tcp:8989,tcp:7878"
}

# --- Create the VM ---
create_instance() {
    log "Creating Compute Engine instance: $INSTANCE_NAME"

    if gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" &>/dev/null; then
        log "Instance '$INSTANCE_NAME' already exists, reusing it"
    else
        gcloud compute instances create "$INSTANCE_NAME" \
        --project="$PROJECT_ID" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --image-family="$IMAGE_FAMILY" \
        --image-project="$IMAGE_PROJECT" \
        --boot-disk-size="$DISK_SIZE" \
        --boot-disk-type="pd-standard" \
        --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY \
        --scopes="cloud-platform" \
        --tags="$NETWORK_TAG" \
        --metadata="enable-oslogin=false" \
        --quiet
    fi

    INSTANCE_CREATED=true

    INSTANCE_IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
    log "Instance created:"
    log "  Name:       $INSTANCE_NAME"
    log "  Public IP:  $INSTANCE_IP"
    log "  Zone:       $ZONE"
    log "  Machine:    $MACHINE_TYPE"

    inject_ssh_key
    log "Waiting for SSH to become available..."

    local attempt=1
    local max_attempts=24
    until ssh_cmd "echo ssh-ready" &>/dev/null; do
        if [[ $attempt -ge $max_attempts ]]; then
            echo "ERROR: SSH not available after $((max_attempts * 10)) seconds"
            exit 1
        fi
        log "SSH not yet ready (attempt $attempt/$max_attempts)..."
        sleep 10
        attempt=$((attempt + 1))
    done

    log "SSH is ready"
    log "Waiting for cloud-init to complete..."
    ssh_cmd "cloud-init status --wait" &>/dev/null || true
    log "Instance is ready"
}

# --- Write helper scripts ---
write_scripts() {
    # setup.sh: installs Docker, git, and expect
    cat > "$WORK_DIR/setup.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq || apt-get update -qq
apt-get install -y -qq git expect

# Install Docker via the official convenience script
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
EOF

    # run_install.sh: clones the repo and drives install.sh with expect.
    # install.sh reads from /dev/tty, so expect is required to supply answers.
    # Answers given: simple mode, default TV and movie directories, create dirs = y.
    cat > "$WORK_DIR/run_install.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

cd /root
git clone https://github.com/evinowen/bragi.git
cd bragi
chmod +x install.sh

expect - << 'EXPECT'
set timeout 1200
log_user 1

spawn bash /root/bragi/install.sh

expect {
    -re {Choose configuration mode \[s/i\]:} {
        send "s\r"
        exp_continue
    }
    -re {Base directory \[/media/television\]:} {
        send "\r"
        exp_continue
    }
    -re {Base directory \[/media/movies\]:} {
        send "\r"
        exp_continue
    }
    -re {Would you like to create these directories\? \[y/N\]:} {
        send "y\r"
        exp_continue
    }
    eof
}

set wait_result [wait]
set exit_code [lindex $wait_result 3]
exit $exit_code
EXPECT
EOF

    # verify.sh: checks services, containers, and directories.
    # Prints structured PASS:/FAIL: lines that the parent script parses.
    cat > "$WORK_DIR/verify.sh" << 'EOF'
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

# Systemd unit files exist
for svc in sabnzbd sonarr radarr; do
    check "Unit file exists: bragi.$svc.service" \
        test -f "/etc/systemd/system/bragi.$svc.service"
done

# Services are enabled for boot
for svc in sabnzbd sonarr radarr; do
    check "Service enabled: bragi.$svc" \
        bash -c "systemctl is-enabled bragi.$svc 2>/dev/null | grep -qx 'enabled'"
done

# Services are active
for svc in sabnzbd sonarr radarr; do
    check "Service active: bragi.$svc" \
        bash -c "systemctl is-active bragi.$svc 2>/dev/null | grep -qx 'active'"
done

# Docker containers exist
for container in sabnzbd sonarr radarr; do
    check "Docker container exists: bragi.$container" \
        bash -c "docker ps -a --format '{{.Names}}' | grep -qx 'bragi.$container'"
done

# Service data directories exist
for dir in /opt/sabnzbd /opt/sonarr /opt/radarr; do
    check "Data directory exists: $dir" test -d "$dir"
done

# Media directories were created
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

# HTTP endpoints return 200
check_http() {
    local description="$1"
    local url="$2"
    local max_attempts=12
    local attempt=1
    local status

    while [[ $attempt -le $max_attempts ]]; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url")
        if [[ "$status" == "200" ]]; then
            pass "$description"
            return
        fi
        sleep 5
        attempt=$((attempt + 1))
    done

    fail "$description (got HTTP $status after $((max_attempts * 5))s)"
}

check_http "HTTP 200: SABnzbd"  "http://localhost:8080"
check_http "HTTP 200: Sonarr"   "http://localhost:8989/sonarr"
check_http "HTTP 200: Radarr"   "http://localhost:7878/radarr"
EOF
}

# --- Install dependencies on the VM ---
install_dependencies() {
    log "Installing Docker, git, and expect on the instance..."
    scp_to "$WORK_DIR/setup.sh" "/tmp/setup.sh"
    ssh_cmd "sudo bash /tmp/setup.sh"
    log "Dependencies installed"
}

# --- Run the bragi installer ---
run_installer() {
    log "Running bragi installer (this may take several minutes while images pull)..."
    scp_to "$WORK_DIR/run_install.sh" "/tmp/run_install.sh"
    ssh_cmd "sudo bash /tmp/run_install.sh"
    log "Installer finished"
}

# --- Verify the installation ---
verify_installation() {
    log "Verifying installation..."
    scp_to "$WORK_DIR/verify.sh" "/tmp/verify.sh"

    local output
    if output=$(ssh_cmd "sudo bash /tmp/verify.sh" 2>&1); then
        echo "$output"
        while IFS= read -r line; do
            if [[ "$line" == PASS:* ]]; then
                log_success "${line#PASS: }"
            elif [[ "$line" == FAIL:* ]]; then
                log_failure "${line#FAIL: }"
            fi
        done <<< "$output"
    else
        log_failure "Verification script failed to run on remote instance"
    fi
}

# --- Summary ---
report_results() {
    echo
    echo "========================================"
    echo "          Test Results Summary"
    echo "========================================"
    echo -e "  ${GREEN}Passed: $PASS${NC}"
    echo -e "  ${RED}Failed: $FAIL${NC}"
    echo "========================================"

    if [[ $FAIL -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed — bragi installed successfully.${NC}\n"
        exit 0
    else
        echo -e "\n${RED}$FAIL test(s) failed. Review output above for details.${NC}\n"
        exit 1
    fi
}

# --- Main ---
main() {
    check_prerequisites
    setup_firewall
    generate_ssh_key
    write_scripts
    create_instance
    install_dependencies
    run_installer
    verify_installation
    report_results
}

main "$@"
