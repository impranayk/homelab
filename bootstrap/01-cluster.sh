#!/usr/bin/env bash
# Create the 3-node k3d cluster from bootstrap/k3d-homelab.yaml.
set -euo pipefail
cd "$(dirname "$0")/.."

# Kernel limits: WSL ships fs.inotify.max_user_instances=128, which three k3s nodes plus a log
# shipper exhaust ("failed to create fsnotify watcher: too many open files" in every pod's log).
sudo sysctl -q -w fs.inotify.max_user_instances=8192 fs.inotify.max_user_watches=1048576
printf 'fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
' | sudo tee /etc/sysctl.d/99-homelab.conf >/dev/null

k3d cluster create --config bootstrap/k3d-homelab.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes -o wide
echo
echo "Cluster up. Registry: push to localhost:5111, pull in-cluster as homelab-registry:5000"
