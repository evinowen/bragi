check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "ERROR: Docker is not installed or not in PATH"
        echo "Please install Docker before running this script"
        echo "Visit: https://docs.docker.com/engine/install/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        echo "ERROR: Docker daemon is not running or user lacks permissions"
        echo "Please ensure Docker is running and your user is in the docker group"
        echo "Run: sudo usermod -aG docker \$USER && newgrp docker"
        exit 1
    fi

    echo "✓ Docker is available and running"
}

check_systemd() {
    if ! command -v systemctl &> /dev/null; then
        echo "ERROR: systemd is not available on this system"
        echo "This installer requires a Linux distribution with systemd"
        exit 1
    fi

    echo "✓ systemd is available"
}

check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        echo "WARNING: Running as root. This script will create systemd services."
    else
        echo "INFO: Running as non-root user. You may be prompted for sudo password."
    fi
}
