configure_usenet() {
    echo
    echo "=== Usenet Server Configuration ==="
    echo "Enter your Usenet provider connection details."
    echo "These will be configured automatically in SABnzbd."
    echo

    echo -n "  Server host: "
    read USENET_HOST </dev/tty

    echo -n "  Usenet username: "
    read USENET_USERNAME </dev/tty

    echo -n "  Usenet password: "
    read -s USENET_PASSWORD </dev/tty
    echo

    echo -n "  Enable SSL? [Y/n]: "
    read usenet_ssl_input </dev/tty

    if [[ "${usenet_ssl_input:-}" =~ ^[Nn]$ ]]; then
        USENET_SSL="no"
    else
        USENET_SSL="yes"
    fi

    echo
    echo "Usenet Configuration Summary:"
    echo "  Host:    $USENET_HOST"
    echo "  Login:   $USENET_USERNAME"
    echo "  SSL:     $USENET_SSL"

    export USENET_HOST USENET_USERNAME USENET_PASSWORD USENET_SSL
}
