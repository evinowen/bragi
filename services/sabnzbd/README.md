# SABnzbd Service

SABnzbd is a free and easy binary newsreader that automates downloading from Usenet.

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

The service creates the following directories:

- `/opt/sabnzbd/config`: Configuration files
- `/opt/sabnzbd/downloads`: Completed downloads
- `/opt/sabnzbd/incomplete`: Incomplete downloads

### Network Access

- Web interface: http://localhost:8080

## Management

Start the service:
```bash
sudo systemctl start bragi.sabnzbd
```

Stop the service:
```bash
sudo systemctl stop bragi.sabnzbd
```

Enable autostart on boot:
```bash
sudo systemctl enable bragi.sabnzbd
```

Check service status:
```bash
sudo systemctl status bragi.sabnzbd
```

View logs:
```bash
docker logs bragi.sabnzbd
```

## Initial Setup

1. Start the service
2. Open http://localhost:8080 in your browser
3. Complete the initial setup wizard
4. Configure your Usenet providers and settings
