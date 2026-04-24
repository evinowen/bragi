get_host_ip() {
    local host_ip=""

    if command -v ip &> /dev/null; then
        host_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
    fi

    if [[ -z "$host_ip" ]] && command -v hostname &> /dev/null; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    if [[ -z "$host_ip" ]] && command -v ip &> /dev/null; then
        host_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi

    if [[ -z "$host_ip" ]] && command -v ifconfig &> /dev/null; then
        host_ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
    fi

    if [[ -z "$host_ip" ]]; then
        host_ip="localhost"
    fi

    echo "$host_ip"
}

create_docker_network() {
    echo
    echo "=== Creating Docker Network ==="

    if docker network inspect bragi &>/dev/null; then
        echo "- Docker network 'bragi' already exists"
    else
        docker network create bragi
        echo "✓ Docker network 'bragi' created"
    fi
}
