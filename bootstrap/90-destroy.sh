#!/usr/bin/env bash
# Throw the cluster away. The repo is the source of truth, so this is cheap.
set -euo pipefail
k3d cluster delete homelab
echo "gone. bootstrap/01-cluster.sh && bootstrap/10-argocd.sh to rebuild."
