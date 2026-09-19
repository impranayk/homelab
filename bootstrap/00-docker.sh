#!/usr/bin/env bash
# Docker Engine natively inside WSL2 Ubuntu (no Docker Desktop). Official apt repository.
# Ubuntu 24.04 on WSL 2.x runs systemd, so the docker service starts on its own.
set -euo pipefail

if command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1; then
  echo "docker already works: $(docker version --format '{{.Server.Version}}')"; exit 0
fi

sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker

echo
echo "Docker $(sudo docker version --format '{{.Server.Version}}') installed."
echo "Your user was added to the docker group: close this Ubuntu window, open it again, then run:"
echo "  docker run --rm hello-world"
