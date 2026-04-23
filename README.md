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

`deploy.py` validates the full installation by spinning up a temporary GCP Compute Engine instance, running the bragi installer non-interactively, and verifying that all services and containers are correctly installed and running. The instance is automatically deleted when the test completes.

### What the test does

1. Creates an Ubuntu VM on GCP Compute Engine
2. Installs Docker, git, and `expect` on the VM
3. Clones the bragi repository and runs `install.sh` non-interactively using `expect`
4. Verifies that all systemd unit files exist and services are enabled and active
5. Verifies that all Docker containers exist and data/media directories were created
6. Deletes the VM and reports a pass/fail summary

### Configuration

Create a `deploy.yaml` file in the repository root to configure the deployment:

```yaml
gcp_project_id: your-project-id
gcp_zone: us-west1-a
setup_firewall: true
skip_cleanup: false

usenet:
  host: news.example.com
  username: youruser
  password: yourpassword
  ssl: true

indexers:
  - name: MyIndexer
    url: https://api.myindexer.com
    api_key: abc123
```

`deploy.yaml` is excluded from version control via `.gitignore` — do not commit it.

| Key               | Description                                                             |
|-------------------|-------------------------------------------------------------------------|
| `gcp_project_id`  | GCP project to create the test VM in                                    |
| `gcp_zone`        | Compute Engine zone for the VM                                          |
| `gcp_machine_type`| Machine type (default: `e2-standard-2`)                                 |
| `skip_cleanup`    | Set to `true` to keep the VM after the test                             |
| `setup_firewall`  | Set to `true` to create firewall rules for SSH and service ports        |
| `usenet`          | Usenet provider credentials passed to SABnzbd                           |
| `indexers`        | List of Newznab indexers to configure in Sonarr and Radarr              |

Each entry in `indexers` supports the following fields:

| Field             | Required | Description                                                                          |
|-------------------|----------|--------------------------------------------------------------------------------------|
| `name`            | yes      | Display name for the indexer                                                         |
| `url`             | yes      | Base URL of the indexer (e.g. `https://api.nzbgeek.info`)                            |
| `api_key`         | yes      | API key issued by the indexer; use `""` for indexers that don't require one          |
| `television`      | yes      | `true` to add this indexer to Sonarr                                                 |
| `movies`          | yes      | `true` to add this indexer to Radarr                                                 |
| `api_path`        | no       | API path on the indexer host (default: `/api`)                                       |
| `categories`      | no       | Newznab category IDs to search; overrides the service default (see table below)      |
| `anime_categories`| no       | Anime-specific category IDs for Sonarr (Sonarr only, default: `[]`)                  |

#### Newznab Categories

| ID   | Category           | ID   | Category           |
|------|--------------------|------|--------------------|
| 2000 | Movies             | 5000 | TV                 |
| 2010 | Movies/Foreign     | 5010 | TV/WEB-DL          |
| 2020 | Movies/Other       | 5020 | TV/Foreign         |
| 2030 | Movies/SD          | 5030 | TV/SD              |
| 2040 | Movies/HD          | 5040 | TV/HD              |
| 2045 | Movies/UHD         | 5045 | TV/UHD             |
| 2050 | Movies/BluRay      | 5050 | TV/Other           |
| 2060 | Movies/3D          | 5060 | TV/Sport           |
|      |                    | 5070 | TV/Anime           |
|      |                    | 5080 | TV/Documentary     |

**Defaults** — when `categories` is not specified, each service uses a sensible default:
- Sonarr: `[5030, 5040]` (TV/SD and TV/HD)
- Radarr: `[2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060]` (all Movies subcategories)

Indexers that use a non-standard API path or anime-only categories (like Anime Tosho) should override these explicitly. See `deploy.yaml.example` for an example.

### Prerequisites

Install `pyyaml` if not already available:

```bash
pip3 install pyyaml
```

Ensure the [gcloud CLI](https://cloud.google.com/sdk/docs/install) is installed and authenticated.

### Running the test

```bash
python3 deploy.py
```

To keep the VM running after the test (useful for debugging), set `skip_cleanup: true` in `deploy.yaml`.

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
