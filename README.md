# Docker Services Manager

A repository for managing Docker containers as systemd services on Linux systems. This tool automates the installation and configuration of Docker-based services with proper systemd integration.

## Features

- Automatic Docker availability checking
- Systemd service creation for Docker containers
- Modular service architecture
- Support for any Linux distribution with systemd
- Automated installation process

## Prerequisites

- Linux system with systemd
- Docker installed and running
- User with sudo privileges (or run as root)

## Quick Start

### Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/evinowen/bragi.git && cd bragi && chmod +x install.sh && ./install.sh
```

## How It Works

### Repository Structure

```
.
├── install.sh              # Main installation script
├── services/               # Services directory
│   └── servicename/        # Individual service directory
│       ├── add.sh          # Service installation script
│       ├── README.md       # Service documentation
│       └── ...             # Service-specific files
└── README.md              # This file
```

### Installation Process

1. **Prerequisites Check**: Verifies Docker is installed and running
2. **Service Discovery**: Scans the `services/` directory for available services
3. **Service Installation**: Executes each service's `install.sh` script
4. **Systemd Integration**: Creates systemd service files for container management

### Service Architecture

Each service in the `services/` directory contains:

- `add.sh`: Installation script that:
  - Pulls the required Docker image
  - Creates the Docker container with appropriate configuration
  - Generates a systemd service file
  - Sets up any required directories and permissions

- `README.md`: Documentation specific to the service

- Additional files: Any configuration files, scripts, or resources needed by the service

## Available Services

### SABnzbd

Binary newsreader for automated Usenet downloading.

- **Container**: `linuxserver/sabnzbd:latest`
- **Web Interface**: http://localhost:8080
- **Data Directory**: `/opt/sabnzbd/`

See [services/sabnzbd/README.md](services/sabnzbd/README.md) for detailed configuration.

### Sonarr

Television series collection manager for Usenet and BitTorrent users.

- **Container**: `linuxserver/sonarr:latest`
- **Web Interface**: http://localhost:8989/sonarr
- **Data Directory**: `/opt/sonarr/`
- **Uses**: Television directories for downloads, staging, and storage

See [services/sonarr/README.md](services/sonarr/README.md) for detailed configuration.

### Radarr

Movie collection manager for Usenet and BitTorrent users.

- **Container**: `linuxserver/radarr:latest`
- **Web Interface**: http://localhost:7878/radarr
- **Data Directory**: `/opt/radarr/`
- **Uses**: Movie directories for downloads, staging, and storage

See [services/radarr/README.md](services/radarr/README.md) for detailed configuration.

## Managing Services

### Starting Services

```bash
sudo systemctl start bragi.<service-name>
```

### Stopping Services

```bash
sudo systemctl stop bragi.<service-name>
```

### Restarting Services

```bash
sudo systemctl restart bragi.<service-name>
```

### Checking Status

```bash
sudo systemctl status bragi.<service-name>
```

### Enable Autostart on Boot

```bash
sudo systemctl enable bragi.<service-name>
```

### Disable Autostart

```bash
sudo systemctl disable bragi.<service-name>
```

## Adding New Services

To add a new service to this repository:

1. Create a directory under `services/` with your service name
2. Create an `add.sh` script that:
   - Pulls the required Docker image
   - Creates and configures the container
   - Creates a systemd service file
   - Sets up any required directories
3. Make the script executable: `chmod +x services/yourservice/add.sh`
4. Create a `README.md` documenting the service configuration
5. Test the installation process

### Service Install Script Template

```bash
#!/bin/bash

set -euo pipefail

SERVICE_NAME="bragi.your-service"
CONTAINER_NAME="bragi.your-service"
IMAGE="your/image:latest"

create_container() {
    echo "Creating Docker container..."
    docker create \\
        --name="$CONTAINER_NAME" \\
        --restart=unless-stopped \\
        -p 8080:8080 \\
        "$IMAGE"
    echo "✓ Container created"
}

create_systemd_service() {
    echo "Creating systemd service..."

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Bragi Your Service Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start ${CONTAINER_NAME}
ExecStop=/usr/bin/docker stop ${CONTAINER_NAME}
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    echo "✓ Systemd service created"
}

main() {
    echo "Installing your service..."
    create_container
    create_systemd_service
    echo "✓ Service installed successfully!"
}

main "$@"
```

## Testing

`deploy.sh` validates the full installation by spinning up a temporary GCP Compute Engine instance, running the bragi installer non-interactively, and verifying that all services and containers are correctly installed and running. The instance is automatically deleted when the test completes.

### What the test does

1. Creates an Ubuntu VM on GCP Compute Engine
2. Installs Docker, git, and `expect` on the VM
3. Clones the bragi repository and runs `install.sh` non-interactively using `expect`
4. Verifies that all systemd unit files exist and services are enabled and active
5. Verifies that all Docker containers exist and data/media directories were created
6. Deletes the VM and reports a pass/fail summary

### Configuration

Create a `deploy.env` file in the repository root to configure the test environment:

```bash
GCP_PROJECT_ID=your-project-id
GCP_ZONE=us-west1-a
```

`deploy.env` is excluded from version control via `.gitignore` — do not commit it.

The following environment variables are supported:

| Variable         | Description                              |
|------------------|------------------------------------------|
| `GCP_PROJECT_ID` | GCP project to create the test VM in     |
| `GCP_ZONE`       | Compute Engine zone for the VM           |
| `GCP_MACHINE_TYPE` | Machine type (default: `e2-standard-2`) |
| `SKIP_CLEANUP`   | Set to `true` to keep the VM after the test |
| `SETUP_FIREWALL` | Set to `true` to create firewall rules for SSH (22) and service ports (8080, 8989, 7878) if they don't exist |

### Running the test

Ensure the [gcloud CLI](https://cloud.google.com/sdk/docs/install) is installed and authenticated, then run:

```bash
./deploy.sh
```

`deploy.sh` automatically loads `deploy.env` if it exists. You can also pass variables inline:

```bash
GCP_PROJECT_ID=your-project-id GCP_ZONE=us-west1-a ./deploy.sh
```

To keep the VM running after the test (useful for debugging):

```bash
SKIP_CLEANUP=true ./deploy.sh
```

## Troubleshooting

### Docker Not Found

```
ERROR: Docker is not installed or not in PATH
```

Install Docker following the official documentation: https://docs.docker.com/engine/install/

### Docker Daemon Not Running

```
ERROR: Docker daemon is not running or user lacks permissions
```

Start the Docker service:
```bash
sudo systemctl start docker
```

Add your user to the docker group:
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Permission Denied

If you get permission errors, ensure your user has sudo privileges or run the installer as root.

### Service Failed to Start

Check the service status and logs:
```bash
sudo systemctl status bragi.<service-name>
docker logs bragi.<container-name>
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add your service following the guidelines above
4. Test thoroughly
5. Submit a pull request

## License

This project is open source. Please check the LICENSE file for details.

## Support

For issues and feature requests, please use the GitHub issue tracker.
