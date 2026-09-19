#!/usr/bin/env bash
# Create the 3-node k3d cluster from bootstrap/k3d-homelab.yaml.
set -euo pipefail
cd "$(dirname "$0")/.."

k3d cluster create --config bootstrap/k3d-homelab.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes -o wide
echo
echo "Cluster up. Registry: push to localhost:5111, pull in-cluster as homelab-registry:5000"
