generate_credentials() {
    ADMIN_PASSWORD=$(openssl rand -hex 8)
    echo "✓ Admin credentials generated"
}

display_credentials() {
    echo
    echo "=== Admin Credentials ==="
    echo "  Username: $ADMIN_USERNAME"
    echo "  Password: $ADMIN_PASSWORD"
    echo
    echo "Use these credentials to log in to Sonarr and Radarr."
}
