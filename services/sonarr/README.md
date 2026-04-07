# Sonarr Service

Sonarr is a PVR for Usenet and BitTorrent users. It monitors multiple RSS feeds for new episodes of your favorite shows and grabs, sorts, and renames them.

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
- Configured Television downloads directory: Where downloaded files are located
- Configured Television staging directory: Temporary processing location
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

## Initial Setup

1. Start the service
2. Open http://localhost:8989/sonarr in your browser
3. Complete the initial setup wizard
4. Configure your indexers and download clients
5. Add television series to monitor

## Integration

Sonarr integrates well with:
- **SABnzbd**: For Usenet downloading
- **Download clients**: qBittorrent, Transmission, etc.
- **Media servers**: Plex, Jellyfin, Emby
- **Notifications**: Discord, Slack, email, etc.

Configure download client to point to your SABnzbd instance at `http://localhost:8080`.
