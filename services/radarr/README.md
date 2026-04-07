# Radarr Service

Radarr is a movie collection manager for Usenet and BitTorrent users. It monitors multiple RSS feeds for new movies and interfaces with clients and indexers to grab, sort, and rename them.

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
- Configured Movie downloads directory: Where downloaded files are located
- Configured Movie staging directory: Temporary processing location
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

## Initial Setup

1. Start the service
2. Open http://localhost:7878/radarr in your browser
3. Complete the initial setup wizard
4. Configure your indexers and download clients
5. Add movies to monitor

## Integration

Radarr integrates well with:
- **SABnzbd**: For Usenet downloading
- **Download clients**: qBittorrent, Transmission, etc.
- **Media servers**: Plex, Jellyfin, Emby
- **Notifications**: Discord, Slack, email, etc.

Configure download client to point to your SABnzbd instance at `http://localhost:8080`.
