# Sonarr Service

Sonarr is a PVR for Usenet and BitTorrent users. It monitors multiple RSS feeds for new episodes of your favorite shows and grabs, sorts, and renames them.

## Installation

Run `add.sh` to install the service. It performs the following steps:

1. Creates required data directories (`/opt/sonarr/config`, downloads, staging, and library directories)
2. Copies a default `config.xml` to the config directory if one does not already exist
3. Generates a random API key and writes it into `config.xml`
4. Pulls the `linuxserver/sonarr:latest` Docker image
5. Stops and removes any existing `bragi.sonarr` container
6. Creates the Docker container with the appropriate volume mounts and network settings
7. Creates and registers a systemd service (`bragi.sonarr`) for container lifecycle management

After the container is started and verified by `install.sh`, `configure.sh` runs automatically and performs the following steps:

1. Waits for the Sonarr API to become available (up to 60 seconds)
2. Configures forms-based authentication with the provided admin credentials
3. Enables Kodi (XBMC) metadata output
4. Registers `/tv` as the root folder for television libraries
5. Configures SABnzbd (`sabnzbd.bragi:8080`) as the download client using the `television` category
6. Adds a remote path mapping so Sonarr can resolve SABnzbd's `/downloads/television` paths to its own `/downloads` mount

## Configuration

### Environment Variables

You can customize the installation by setting these environment variables before running the add script:

- `PUID`: User ID for file permissions (default: 1000)
- `PGID`: Group ID for file permissions (default: 1000)
- `TZ`: Timezone (default: UTC)

Example:
```bash
export PUID=1001
export PGID=1001
export TZ="UTC"
./add.sh
```

### Directories

The service uses the following directories:

- `/opt/sonarr/config`: Configuration files
- Configured Television downloads directory: Where downloaded files are located (mounted as `/downloads` in container)
- Configured Television staging directory: Temporary processing location (mounted as `/staging` in container)
- Configured Television storage directory: Final organized television library (mounted as `/tv` in container)

### Network Access

- Web interface: http://localhost:8989/sonarr

## Management

Start the service:
```bash
sudo systemctl start bragi.sonarr
```

Stop the service:
```bash
sudo systemctl stop bragi.sonarr
```

Enable autostart on boot:
```bash
sudo systemctl enable bragi.sonarr
```

Check service status:
```bash
sudo systemctl status bragi.sonarr
```

View logs:
```bash
docker logs bragi.sonarr
```

## Integration

Sonarr integrates with:
- **SABnzbd**: Configured automatically as a download client at `sabnzbd.bragi:8080`
- **Media servers**: Plex, Jellyfin, Emby
- **Notifications**: Discord, Slack, email, etc.
