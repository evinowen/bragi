#!/usr/bin/env python3
"""Bragi deployment script — provisions a GCP VM, installs bragi, and verifies all services."""

import atexit
import base64
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit('ERROR: pyyaml is required. Install with: pip3 install pyyaml')

# ── Constants ─────────────────────────────────────────────────────────────────

SCRIPT_DIR    = Path(__file__).parent
CONFIG_FILE   = SCRIPT_DIR / 'deploy.yaml'
IMAGE_FAMILY  = 'ubuntu-2204-lts'
IMAGE_PROJECT = 'ubuntu-os-cloud'
DISK_SIZE     = '30GB'
NETWORK_TAG   = 'bragi-test'
SSH_USER      = 'bragi'

# Resolve external executables once at startup so .cmd/.bat wrappers are found
# correctly on Windows without needing shell=True.
def _require(name):
    path = shutil.which(name)
    if path is None:
        sys.exit(f'ERROR: {name!r} not found on PATH.')
    return path

GCLOUD      = _require('gcloud')
SSH         = _require('ssh')
SCP         = _require('scp')
SSH_KEYGEN  = _require('ssh-keygen')

RED    = '\033[0;31m'
GREEN  = '\033[0;32m'
YELLOW = '\033[1;33m'
CYAN   = '\033[0;36m'
NC     = '\033[0m'

# ── State ─────────────────────────────────────────────────────────────────────

pass_count       = 0
fail_count       = 0
instance_created = False
instance_name    = f'bragi-test-{int(time.time())}'
instance_ip      = ''
work_dir         = Path(tempfile.mkdtemp())
ssh_key          = work_dir / 'id_rsa'

# ── Config ────────────────────────────────────────────────────────────────────

project_id   = ''
zone         = ''
machine_type = 'e2-standard-2'
skip_cleanup = False
do_firewall  = False
usenet_host  = ''
usenet_user  = ''
usenet_pass  = ''
usenet_ssl   = True
indexers     = []

# ── Logging ───────────────────────────────────────────────────────────────────

def log(msg):
    print(f'{CYAN}[DEPLOY]{NC}  {msg}', flush=True)

def log_warn(msg):
    print(f'{YELLOW}[WARN]{NC}  {msg}', flush=True)

def log_success(msg):
    global pass_count
    pass_count += 1
    print(f'{GREEN}[PASS]{NC}  {msg}', flush=True)

def log_failure(msg):
    global fail_count
    fail_count += 1
    print(f'{RED}[FAIL]{NC}  {msg}', flush=True)

# ── Subprocess helpers ────────────────────────────────────────────────────────

def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)

def run_output(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip()

def ssh(args, **kwargs):
    base = [
        SSH, '-i', str(ssh_key),
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        '-o', 'ConnectTimeout=30',
        '-o', 'BatchMode=yes',
        f'{SSH_USER}@{instance_ip}',
    ]
    return subprocess.run(base + args, **kwargs)

def scp_to(local, remote):
    run([
        SCP, '-i', str(ssh_key),
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        '-o', 'BatchMode=yes',
        str(local), f'{SSH_USER}@{instance_ip}:{remote}',
    ])

# ── Config loading ────────────────────────────────────────────────────────────

def load_config():
    global project_id, zone, machine_type, skip_cleanup, do_firewall
    global usenet_host, usenet_user, usenet_pass, usenet_ssl, indexers

    if not CONFIG_FILE.exists():
        sys.exit(f'ERROR: {CONFIG_FILE} not found.')

    with open(CONFIG_FILE) as f:
        cfg = yaml.safe_load(f)

    project_id   = cfg.get('gcp_project_id', '')
    zone         = cfg.get('gcp_zone', '')
    machine_type = cfg.get('gcp_machine_type', 'e2-standard-2')
    skip_cleanup = cfg.get('skip_cleanup', False)
    do_firewall  = cfg.get('setup_firewall', False)

    usenet       = cfg.get('usenet', {})
    usenet_host  = usenet.get('host', '')
    usenet_user  = usenet.get('username', '')
    usenet_pass  = usenet.get('password', '')
    usenet_ssl   = usenet.get('ssl', True)

    indexers     = cfg.get('indexers', [])

# ── Cleanup ───────────────────────────────────────────────────────────────────

def cleanup():
    shutil.rmtree(work_dir, ignore_errors=True)
    if instance_created:
        if skip_cleanup:
            log_warn(f"skip_cleanup=true — instance '{instance_name}' left running in zone {zone}")
            log_warn('Delete it with:')
            log_warn(f'  gcloud compute instances delete {instance_name} --zone={zone} --project={project_id}')
        else:
            log(f'Deleting instance: {instance_name}')
            subprocess.run([
                GCLOUD, 'compute', 'instances', 'delete', instance_name,
                f'--zone={zone}', f'--project={project_id}', '--quiet',
            ], capture_output=True)
            log('Instance deleted')

atexit.register(cleanup)

# ── Prerequisites ─────────────────────────────────────────────────────────────

def check_prerequisites():
    log('Checking local prerequisites...')
    if not project_id:
        sys.exit('ERROR: gcp_project_id is not set in deploy.yaml.')
    log(f'Project:      {project_id}')
    log(f'Zone:         {zone}')
    log(f'Machine type: {machine_type}')
    log(f'Instance:     {instance_name}')
    log(f'Indexers:     {len(indexers)}')

# ── Firewall ──────────────────────────────────────────────────────────────────

def ensure_firewall_rule(name, ports):
    result = subprocess.run(
        [GCLOUD, 'compute', 'firewall-rules', 'describe', name, f'--project={project_id}'],
        capture_output=True,
    )
    if result.returncode == 0:
        log(f"Firewall rule '{name}' already exists, skipping")
        return
    log(f"Creating firewall rule '{name}' ({ports})...")
    run([
        GCLOUD, 'compute', 'firewall-rules', 'create', name,
        f'--project={project_id}',
        '--direction=INGRESS', '--action=ALLOW',
        f'--rules={ports}',
        '--source-ranges=0.0.0.0/0',
        f'--target-tags={NETWORK_TAG}',
        '--quiet',
    ])
    log(f"Firewall rule '{name}' created")

def setup_firewall():
    if not do_firewall:
        return
    ensure_firewall_rule('bragi-test-ssh',      'tcp:22')
    ensure_firewall_rule('bragi-test-services', 'tcp:8080,tcp:8989,tcp:7878')
    ensure_firewall_rule('bragi-test-http',     'tcp:80')

# ── SSH key ───────────────────────────────────────────────────────────────────

def generate_ssh_key():
    log('Generating temporary SSH key pair...')
    run([SSH_KEYGEN, '-t', 'rsa', '-b', '2048', '-f', str(ssh_key), '-N', '', '-q'])
    log('SSH key generated')

def inject_ssh_key():
    pub_key = (ssh_key.parent / (ssh_key.name + '.pub')).read_text().strip()
    log('Injecting SSH public key into instance metadata...')
    run([
        GCLOUD, 'compute', 'instances', 'add-metadata', instance_name,
        f'--zone={zone}', f'--project={project_id}',
        f'--metadata=ssh-keys={SSH_USER}:{pub_key}',
        '--quiet',
    ])
    log('SSH key injected')

# ── Instance ──────────────────────────────────────────────────────────────────

def create_instance():
    global instance_created, instance_ip

    log(f'Creating Compute Engine instance: {instance_name}')
    existing = subprocess.run(
        [GCLOUD, 'compute', 'instances', 'describe', instance_name,
         f'--zone={zone}', f'--project={project_id}'],
        capture_output=True,
    )
    if existing.returncode != 0:
        run([
            GCLOUD, 'compute', 'instances', 'create', instance_name,
            f'--project={project_id}', f'--zone={zone}',
            f'--machine-type={machine_type}',
            f'--image-family={IMAGE_FAMILY}',
            f'--image-project={IMAGE_PROJECT}',
            f'--boot-disk-size={DISK_SIZE}',
            '--boot-disk-type=pd-standard',
            '--network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY',
            '--scopes=cloud-platform',
            f'--tags={NETWORK_TAG}',
            '--metadata=enable-oslogin=false',
            '--quiet',
        ])

    instance_created = True
    instance_ip = run_output([
        GCLOUD, 'compute', 'instances', 'describe', instance_name,
        f'--zone={zone}', f'--project={project_id}',
        '--format=get(networkInterfaces[0].accessConfigs[0].natIP)',
    ])
    log('Instance created:')
    log(f'  Name:       {instance_name}')
    log(f'  Public IP:  {instance_ip}')
    log(f'  Zone:       {zone}')
    log(f'  Machine:    {machine_type}')

    inject_ssh_key()
    log('Waiting for SSH to become available...')
    for attempt in range(1, 25):
        if ssh(['echo', 'ssh-ready'], capture_output=True).returncode == 0:
            break
        log(f'SSH not yet ready (attempt {attempt}/24)...')
        time.sleep(10)
    else:
        sys.exit('ERROR: SSH not available after 240 seconds')

    log('SSH is ready')
    log('Waiting for cloud-init to complete...')
    ssh(['cloud-init', 'status', '--wait'], capture_output=True)
    log('Instance is ready')

# ── Helper scripts ────────────────────────────────────────────────────────────

# Template for run_install.sh — uses __PLACEHOLDERS__ to avoid f-string/bash conflicts.
_RUN_INSTALL_TEMPLATE = r"""#!/bin/bash
set -euo pipefail

export INDEXERS_JSON="$(echo '__INDEXERS_B64__' | base64 -d)"

cd /root
git clone https://github.com/evinowen/bragi.git
cd bragi
chmod +x install.sh

expect - << 'EXPECT'
set timeout 1200
log_user 1

spawn bash /root/bragi/install.sh

expect {
    -re {Server host:} {
        send "__USENET_HOST__\r"
        exp_continue
    }
    -re {Usenet username:} {
        send "__USENET_USER__\r"
        exp_continue
    }
    -re {Usenet password:} {
        send "__USENET_PASS__\r"
        exp_continue
    }
    -re {Enable SSL\? \[Y/n\]:} {
        send "__SSL_RESPONSE__\r"
        exp_continue
    }
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
"""

_SETUP_SH = r"""#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq || apt-get update -qq
apt-get install -y -qq git expect

curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
"""

_VERIFY_SH = r"""#!/bin/bash

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

for svc in nginx sabnzbd sonarr radarr; do
    check "Unit file exists: bragi.$svc.service" \
        test -f "/etc/systemd/system/bragi.$svc.service"
done

for svc in nginx sabnzbd sonarr radarr; do
    check "Service enabled: bragi.$svc" \
        bash -c "systemctl is-enabled bragi.$svc 2>/dev/null | grep -qx 'enabled'"
done

for svc in nginx sabnzbd sonarr radarr; do
    check "Service active: bragi.$svc" \
        bash -c "systemctl is-active bragi.$svc 2>/dev/null | grep -qx 'active'"
done

for container in nginx sabnzbd sonarr radarr; do
    check "Docker container exists: bragi.$container" \
        bash -c "docker ps -a --format '{{.Names}}' | grep -qx 'bragi.$container'"
done

for dir in /opt/nginx /opt/sabnzbd /opt/sonarr /opt/radarr; do
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

check_http "HTTP 200: SABnzbd"          "http://localhost:8080"
check_http "HTTP 200: Sonarr"           "http://localhost:8989/sonarr"
check_http "HTTP 200: Radarr"           "http://localhost:7878/radarr"
check_http "HTTP 200: Nginx -> SABnzbd" "http://localhost/sabnzbd"
check_http "HTTP 200: Nginx -> Sonarr"  "http://localhost/sonarr"
check_http "HTTP 200: Nginx -> Radarr"  "http://localhost/radarr"
"""


def _write_script(path, content):
    """Write a shell script with Unix line endings regardless of host platform."""
    with open(path, 'w', newline='\n') as f:
        f.write(content.lstrip('\n'))

def write_scripts():
    _write_script(work_dir / 'setup.sh', _SETUP_SH)

    indexers_b64 = base64.b64encode(json.dumps(indexers).encode()).decode()
    ssl_response = '' if usenet_ssl else 'n'
    run_install = (
        _RUN_INSTALL_TEMPLATE
        .replace('__INDEXERS_B64__', indexers_b64)
        .replace('__USENET_HOST__', usenet_host)
        .replace('__USENET_USER__', usenet_user)
        .replace('__USENET_PASS__', usenet_pass)
        .replace('__SSL_RESPONSE__', ssl_response)
    )
    _write_script(work_dir / 'run_install.sh', run_install)

    _write_script(work_dir / 'verify.sh', _VERIFY_SH)

# ── Phases ────────────────────────────────────────────────────────────────────

def install_dependencies():
    log('Installing Docker, git, and expect on the instance...')
    scp_to(work_dir / 'setup.sh', '/tmp/setup.sh')
    ssh(['sudo', 'bash', '/tmp/setup.sh'])
    log('Dependencies installed')

def run_installer():
    log('Running bragi installer (this may take several minutes while images pull)...')
    scp_to(work_dir / 'run_install.sh', '/tmp/run_install.sh')
    ssh(['sudo', 'bash', '/tmp/run_install.sh'])
    log('Installer finished')

def verify_installation():
    log('Verifying installation...')
    scp_to(work_dir / 'verify.sh', '/tmp/verify.sh')
    result = ssh(['sudo', 'bash', '/tmp/verify.sh'], capture_output=True, text=True)
    for line in result.stdout.splitlines():
        print(line)
        if line.startswith('PASS: '):
            log_success(line[6:])
        elif line.startswith('FAIL: '):
            log_failure(line[6:])

def report_results():
    print()
    print('========================================')
    print('          Test Results Summary')
    print('========================================')
    print(f'  {GREEN}Passed: {pass_count}{NC}')
    print(f'  {RED}Failed: {fail_count}{NC}')
    print('========================================')

    if fail_count == 0:
        print(f'\n{GREEN}All tests passed — bragi installed successfully.{NC}\n')
        print('=== Service Web Interfaces ===')
        print(f'  SABnzbd:  http://{instance_ip}/sabnzbd')
        print(f'  Sonarr:   http://{instance_ip}/sonarr')
        print(f'  Radarr:   http://{instance_ip}/radarr')
        print()
        sys.exit(0)
    else:
        print(f'\n{RED}{fail_count} test(s) failed. Review output above for details.{NC}\n')
        sys.exit(1)

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    load_config()
    check_prerequisites()
    setup_firewall()
    generate_ssh_key()
    write_scripts()
    create_instance()
    install_dependencies()
    run_installer()
    verify_installation()
    report_results()


if __name__ == '__main__':
    main()
