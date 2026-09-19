#!/usr/bin/env bash
# CLI tooling inside WSL2 Ubuntu. Safe to re-run.
set -euo pipefail

echo "--- k3d"
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "--- kubectl"
KVER=$(curl -Ls https://dl.k8s.io/release/stable.txt)
curl -Lo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl

echo "--- helm"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "--- k9s"
curl -sL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz | tar xz -C /tmp k9s
sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s

echo "--- argocd cli"
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd

echo "--- done"
k3d version; kubectl version --client; helm version --short; k9s version --short; argocd version --client --short
