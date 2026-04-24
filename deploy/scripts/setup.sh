#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq || apt-get update -qq
apt-get install -y -qq git expect

curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
