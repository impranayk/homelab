#!/usr/bin/env bash
# Install Argo CD with Helm (once), then hand it the root app. After this, Argo CD manages itself.
set -euo pipefail
cd "$(dirname "$0")/.."

if grep -q 'REPLACE-WITH-YOUR-REPO' clusters/homelab/components.yaml; then
  echo "Edit clusters/homelab/components.yaml: set repo.url to this repository's clone URL first."; exit 1
fi

ARGO_VERSION=$(awk '/name: argo-cd$/{f=1} f&&/version:/{gsub(/"/,"",$2);print $2;exit}' clusters/homelab/components.yaml)
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "$ARGO_VERSION" \
  -f platform/phase-2-delivery/argo-cd/values.yaml \
  --wait --timeout 10m

kubectl apply -f clusters/homelab/root.yaml
kubectl apply -f bootstrap/argocd-repos.yaml

echo
echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo
echo "Until phase 1 has synced the ingress, reach the UI with:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:80   ->  http://localhost:8080"
echo "Afterwards: https://argocd.127.0.0.1.sslip.io"
