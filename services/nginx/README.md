# Nginx Service

Nginx acts as a reverse proxy, routing incoming connections on port 80 to the appropriate backend service based on the URL path.

## Installation

Run `add.sh` to install the service. It performs the following steps:

1. Creates the config directory (`/opt/nginx/config`)
2. Copies `nginx.conf` to the config directory as `default.conf`
3. Pulls the `nginx:alpine` Docker image
4. Stops and removes any existing `bragi.nginx` container
5. Creates the Docker container, mounting the config and exposing port 80
6. Creates and registers a systemd service (`bragi.nginx`) for container lifecycle management

## Configuration

### Routing

| URL Path  | Backend                      | Port |
|-----------|------------------------------|------|
| /sonarr   | sonarr.bragi                 | 8989 |
| /radarr   | radarr.bragi                 | 7878 |
| /sabnzbd  | sabnzbd.bragi                | 8080 |

All routes forward the original `Host`, `X-Real-IP`, `X-Forwarded-For`, and `X-Forwarded-Proto` headers. Sonarr and Radarr routes also support WebSocket upgrades for real-time updates.

To modify routing, edit `/opt/nginx/config/default.conf` and restart the container:
```bash
sudo systemctl restart bragi.nginx
```

### Network Access

- Reverse proxy: http://localhost

## Management

Start the service:
```bash
sudo systemctl start bragi.nginx
```

Stop the service:
```bash
sudo systemctl stop bragi.nginx
```

Enable autostart on boot:
```bash
sudo systemctl enable bragi.nginx
```

Check service status:
```bash
sudo systemctl status bragi.nginx
```

View logs:
```bash
docker logs bragi.nginx
```
