# Radarr Service

Radarr is a movie collection manager for Usenet and BitTorrent users. It monitors multiple RSS feeds for new movies and interfaces with clients and indexers to grab, sort, and rename them.

## Installation

Run `add.sh` to install the service. It performs the following steps:

1. Creates required data directories (`/opt/radarr/config`, downloads, staging, and library directories)
2. Copies a default `config.xml` to the config directory if one does not already exist
3. Generates a random API key and writes it into `config.xml`
4. Pulls the `linuxserver/radarr:latest` Docker image
5. Stops and removes any existing `bragi.radarr` container
6. Creates the Docker container with the appropriate volume mounts and network settings
7. Creates and registers a systemd service (`bragi.radarr`) for container lifecycle management

After the container is started and verified by `install.sh`, `configure.sh` runs automatically and performs the following steps:

1. Waits for the Radarr API to become available (up to 60 seconds)
2. Configures forms-based authentication with the provided admin credentials
3. Enables Kodi (XBMC) metadata output
4. Registers `/movies` as the root folder for the movie library
5. Configures SABnzbd (`sabnzbd.bragi:8080`) as the download client using the `movies` category
6. Adds a remote path mapping so Radarr can resolve SABnzbd's `/downloads/movies` paths to its own `/downloads` mount

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

- `/opt/radarr/config`: Configuration files
- Configured Movie downloads directory: Where downloaded files are located (mounted as `/downloads` in container)
- Configured Movie staging directory: Temporary processing location (mounted as `/staging` in container)
- Configured Movie storage directory: Final organized movie library (mounted as `/movies` in container)

### Network Access

- Web interface: http://localhost:7878/radarr

## Management

Start the service:
```bash
sudo systemctl start bragi.radarr
```

Stop the service:
```bash
sudo systemctl stop bragi.radarr
```

Enable autostart on boot:
```bash
sudo systemctl enable bragi.radarr
```

Check service status:
```bash
sudo systemctl status bragi.radarr
```

View logs:
```bash
docker logs bragi.radarr
```

## Integration

Radarr integrates with:
- **SABnzbd**: Configured automatically as a download client at `sabnzbd.bragi:8080`
- **Media servers**: Plex, Jellyfin, Emby
- **Notifications**: Discord, Slack, email, etc.
