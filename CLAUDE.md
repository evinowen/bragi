# Claude Context - Bragi Repository

This file contains important context and guidelines for Claude when working on the Bragi repository.

## Repository Overview

**Repository Name**: bragi
**GitHub**: https://github.com/evinowen/bragi
**Purpose**: Docker container management system with systemd integration for Linux
**Target OS**: Ubuntu (and other systemd-based Linux distributions)

## Repository Structure

```
bragi/
├── install.sh                   # Main installation script (keep as install.sh)
├── services/                    # Services directory
│   └── {service-name}/         # Individual service directories
│       ├── add.sh              # Service installation script (always named add.sh)
│       ├── README.md           # Service-specific documentation
│       └── ...                 # Service configuration files
├── README.md                   # Main repository documentation
└── CLAUDE.md                   # This context file
```

## Key Architecture Decisions

### Naming Conventions
- **Main script**: `install.sh` (at repository root)
- **Service scripts**: `add.sh` (in each service directory)
- **Service names**: `bragi.{service-name}` (e.g., bragi.sabnzbd)
- **Container names**: `bragi.{service-name}` (same as service names)
- This distinction is intentional - the main script "installs" the entire system, while individual services are "added"

### Timezone Standard
- **All services use UTC timezone by default**
- Default: `TZ=${TZ:-"UTC"}`
- Documentation should reference UTC as the default
- Users can override with environment variables if needed

### Directory Structure
- Services are stored in `/opt/{service-name}/` on the target system
- Each service gets its own subdirectory under `/opt/`
- Common subdirectories: `config/`, `downloads/`, `data/`, etc.

### User/Group IDs
- Default PUID: 1000
- Default PGID: 1000
- Always configurable via environment variables

## Service Development Guidelines

### Required Files for Each Service

1. **add.sh** - Must include:
   - Shebang: `#!/bin/bash`
   - Error handling: `set -euo pipefail`
   - Environment variables with defaults (PUID, PGID, TZ)
   - Functions: create_directories, copy_configuration_files, pull_image, stop_existing_container, create_container, create_systemd_service
   - Proper error messages and success confirmations

2. **README.md** - Must include:
   - Service description
   - Environment variables section
   - Directory structure
   - Network access information (ports)
   - Management commands (systemctl examples)
   - Initial setup instructions

3. **Configuration Files** - Should include:
   - Default configuration files for the service
   - Sensible default settings that work out of the box
   - Comments explaining key settings
   - Integration-ready configurations (e.g., correct ports, directories)

### Service Script Template Structure

```bash
#!/bin/bash

set -euo pipefail

SERVICE_NAME="bragi.service-name"
CONTAINER_NAME="bragi.service-name"
IMAGE="vendor/image:tag"
SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" &> /dev/null && pwd)"

PUID=${PUID:-1000}
PGID=${PGID:-1000}
TZ=${TZ:-"UTC"}

DATA_DIR="/opt/{service-name}"
CONFIG_DIR="$DATA_DIR/config"

# Use configured media directories from main installer
# Fall back to local directories if not provided
DOWNLOADS_DIR="${TELEVISION_DOWNLOADS_DIR:-$DATA_DIR/downloads}"
# Additional directory variables...

create_directories() {
    # Create and set permissions for data directories
}

copy_configuration_files() {
    # Copy default configuration files to config directory
    # Only copy if files don't already exist
    # Set proper ownership and permissions
}

pull_image() {
    # Pull the Docker image
}

stop_existing_container() {
    # Stop and remove existing container if it exists
}

create_container() {
    # Create the Docker container with proper configuration
}

create_systemd_service() {
    # Create systemd service file for container management
}

get_host_ip() {
    # Detect host IP address using multiple methods
    # Returns "localhost" if detection fails
}

main() {
    # Orchestrate the installation process
    # Call functions in order: create_directories, copy_configuration_files, etc.
    # Display both localhost and network URLs at completion
}

main "$@"
```

### Systemd Service Template

```ini
[Unit]
Description=Bragi {Service Name} Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start bragi.{service-name}
ExecStop=/usr/bin/docker stop bragi.{service-name}
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

## Docker Container Conventions

### Common Configuration
- Always use `--restart=unless-stopped`
- Use LinuxServer.io images when available (format: `linuxserver/{service}:latest`)
- Standard environment variables: PUID, PGID, TZ
- Volume mounting pattern: `{host-path}:{container-path}`

### Port Management
- Document all exposed ports in service README
- Use standard ports when possible
- Include port information in installation success message

### Configuration File Management

Each service should include default configuration files to provide a good out-of-the-box experience:

**Configuration File Types:**
- **SABnzbd**: `sabnzbd.ini` - INI format with sections for servers, categories, switches
- **Sonarr**: `config.xml` - XML format with application settings, media management, quality profiles
- **Radarr**: `config.xml` - XML format similar to Sonarr but for movies

**Configuration Copy Process:**
- Configuration files are stored alongside the service's `add.sh` script
- Files are copied to the container's config directory only if they don't already exist
- Proper ownership (PUID:PGID) is set after copying
- If files already exist (from previous installations), they are left untouched

**Configuration File Guidelines:**
- Use sensible defaults that work without additional configuration
- Set correct ports that match the container port mappings
- Configure directories to match the container volume mounts
- Include comments explaining important settings
- Disable features that require external setup (like notifications) by default
- Enable security features where appropriate

**Implementation Pattern:**
```bash
copy_configuration_files() {
    echo "Copying default configuration files..."

    if [[ ! -f "$CONFIG_DIR/config.xml" && -f "$SERVICE_DIR/config.xml" ]]; then
        sudo cp "$SERVICE_DIR/config.xml" "$CONFIG_DIR/config.xml"
        sudo chown "$PUID:$PGID" "$CONFIG_DIR/config.xml"
        echo "✓ Copied default config.xml"
    else
        echo "- Configuration file already exists or template not found"
    fi
}
```

## Installation Flow

The main `install.sh` script follows this process:

1. **Prerequisites Check**: Verifies Docker and systemd availability
2. **Media Directory Configuration**: Prompts user for TV and Movie directory paths (downloads, staging, storage)
3. **Directory Creation**: Offers to create missing directories (defaults to no)
4. **Service Discovery**: Scans the `services/` directory for available services
5. **Service Installation**: Executes each service's `add.sh` script to create containers and systemd services
6. **Service Activation**: Automatically enables all installed services for autostart on boot
7. **Service Startup**: Starts all installed services
8. **Verification**: Waits up to 60 seconds (12 attempts at 5-second intervals) to verify all services are running
9. **URL Display**: Shows web interface URLs with detected host IP address
10. **Completion Report**: Provides summary of installation success, service status, and configured directories

### Media Directory Configuration

The installer prompts users to configure six directory paths for media management:

**Television Shows:**
- **Downloads**: Where files are initially downloaded (e.g., `/media/downloads/television`)
- **Staging**: Temporary processing location (e.g., `/media/staging/television`)
- **Storage**: Final organized library (e.g., `/media/television`)

**Movies:**
- **Downloads**: Where files are initially downloaded (e.g., `/media/downloads/movies`)
- **Staging**: Temporary processing location (e.g., `/media/staging/movies`)
- **Storage**: Final organized library (e.g., `/media/movies`)

**Directory Creation Behavior:**
- The installer checks if configured directories exist
- If missing directories are found, user is prompted to create them
- Default response is "No" - directories are not created automatically
- User can choose to create all missing directories at once
- If directories are not created, services may fail to start until they're created manually

**Environment Variables:**
- Directory paths are exported as environment variables to service installation scripts
- Services can use these paths or fall back to default locations
- Current variables: `TELEVISION_DOWNLOADS_DIR`, `TELEVISION_STAGING_DIR`, `TELEVISION_STORAGE_DIR`, `MOVIE_DOWNLOADS_DIR`, `MOVIE_STAGING_DIR`, `MOVIE_STORAGE_DIR`

### Service Startup Behavior

- All successfully installed services are automatically enabled for boot startup
- All services are started immediately after installation
- The installer waits and verifies that services are actually running
- If a service fails to start within 60 seconds, it's reported but doesn't fail the entire installation
- Users get clear feedback about which services are running vs. which may need troubleshooting

### Service URL Display

After services are successfully started and verified, the installer displays web interface URLs:

**IP Address Detection:**
- Uses multiple methods to detect the host's IP address
- Primary method: `ip route get 8.8.8.8` (most reliable)
- Fallback methods: `hostname -I`, network interface parsing
- Final fallback: Uses "localhost" if IP detection fails

**URL Format:**
- Shows both localhost and network-accessible URLs
- Example output:
  ```
  === Service Web Interfaces ===
  Access your services at the following URLs:

    SABnzbd:  http://192.168.1.100:8080
    Sonarr:   http://192.168.1.100:8989
    Radarr:   http://192.168.1.100:7878

  Note: These URLs use the detected IP address (192.168.1.100).
        You can also access services using 'localhost' from this machine.
  ```

**Service-Specific URLs:**
- Each service includes both localhost and network URLs in its completion message
- Individual service installations also show appropriate URLs

## Update and Maintenance Procedures

### Adding a New Service

1. Create directory: `mkdir -p services/{service-name}`
2. Create `add.sh` script using the template above
3. Make executable: `chmod +x services/{service-name}/add.sh`
4. Create service-specific `README.md`
5. Test installation process
6. Update main README.md to list the new service

### Modifying Existing Services

1. Always test changes in a clean environment
2. Ensure backwards compatibility with existing installations
3. Update service README.md if configuration changes
4. Verify systemd service creation still works

### Documentation Updates

- Keep main README.md current with available services
- Update service-specific README.md when configuration changes
- Ensure all examples use UTC timezone
- Verify GitHub URLs point to `evinowen/bragi`

## Common Pitfalls to Avoid

1. **Don't change naming conventions** - install.sh vs add.sh distinction and bragi prefix are important
2. **Don't forget bragi prefix** - All services and containers must be prefixed with "bragi."
3. **Don't use non-UTC timezones in defaults** - Always default to UTC
4. **Don't forget executable permissions** - Scripts must be executable
5. **Don't skip systemd service creation** - This is core functionality
6. **Don't hardcode paths** - Use variables for flexibility
7. **Don't ignore error handling** - Always use `set -euo pipefail`
8. **Don't forget trailing blank lines** - All files must end with a blank line (POSIX compliance)
9. **Don't use bare BASH_SOURCE** - Always use `${BASH_SOURCE[0]:-$0}` for compatibility with `set -u`

## Testing Checklist

When adding or modifying services:

- [ ] Script is executable
- [ ] All required functions are present
- [ ] Error handling is implemented
- [ ] Directory creation works
- [ ] Docker image pulls successfully
- [ ] Container creation works
- [ ] Systemd service is created correctly
- [ ] Service can be started/stopped with systemctl
- [ ] Documentation is complete and accurate
- [ ] Timezone defaults to UTC
- [ ] GitHub references point to evinowen/bragi
- [ ] Service names use bragi prefix (bragi.service-name)
- [ ] Container names use bragi prefix (bragi.service-name)
- [ ] Service starts successfully and passes verification check
- [ ] Service is enabled for autostart on boot
- [ ] Configuration files are created with sensible defaults
- [ ] Configuration files have proper ownership and permissions
- [ ] Service displays both localhost and network URLs upon completion
- [ ] URLs use detected IP address when possible
- [ ] All files end with a blank line (POSIX compliance)

## Repository Maintenance Commands

```bash
# Make all scripts executable
find . -name "*.sh" -exec chmod +x {} \;

# Check for hardcoded timezone references
grep -r "America\|Europe\|Asia" services/ --exclude-dir=.git

# Verify script naming convention
find services/ -name "install.sh" # Should return nothing
find services/ -name "add.sh"     # Should list all service scripts

# Check for files missing trailing blank lines
find . -type f \( -name "*.sh" -o -name "*.md" -o -name "*.ini" -o -name "*.xml" \) -exec sh -c 'if [ "$(tail -c1 "$1")" != "" ]; then echo "$1 missing trailing newline"; fi' _ {} \;

# Test main installer (dry run concept)
./install.sh # Run in test environment
```

## Integration Notes

- Repository works with any systemd-based Linux distribution
- Primary target: Ubuntu
- Requires Docker to be pre-installed
- Supports both root and non-root execution (with sudo)
- All services become standard systemd services
- No special tools or dependencies beyond Docker and systemd
