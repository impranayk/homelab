#!/usr/bin/env bash
# Export the lab CA (made by cert-manager in phase 1) and import it into the Windows trust store,
# so Chrome/Edge on the laptop show a green lock for *.127.0.0.1.sslip.io.
set -euo pipefail
kubectl -n cert-manager wait --for=condition=Ready certificate/homelab-ca --timeout=120s
kubectl -n cert-manager get secret homelab-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/homelab-ca.crt
cp /tmp/homelab-ca.crt /mnt/c/Users/Public/homelab-ca.crt
echo "CA written to C:\\Users\\Public\\homelab-ca.crt"
echo "Importing into Windows (accept the UAC prompt)..."
powershell.exe -NoProfile -Command \
  "Start-Process certutil -ArgumentList '-addstore -f Root C:\\Users\\Public\\homelab-ca.crt' -Verb RunAs -Wait"
# Also trust it inside WSL for curl/argocd CLI
sudo cp /tmp/homelab-ca.crt /usr/local/share/ca-certificates/homelab-ca.crt && sudo update-ca-certificates >/dev/null
echo "done"
