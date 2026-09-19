#!/usr/bin/env bash
# Creates every Kubernetes Secret the charts reference, from gitignored env files.
# Convention:  secrets/<namespace>.<secret-name>.env  ->  Secret <secret-name> in <namespace>
# Generate the platform passwords once with bootstrap/21-gen-secrets.sh; add your API keys by hand.
# Phase 4 moves all of this into OpenBao + ExternalSecrets.
set -euo pipefail
cd "$(dirname "$0")/.."

shopt -s nullglob
files=(secrets/*.*.env)
[ ${#files[@]} -gt 0 ] || { echo "no secrets/<namespace>.<name>.env files; run bootstrap/21-gen-secrets.sh"; exit 1; }

for f in "${files[@]}"; do
  base=$(basename "$f" .env)
  ns=${base%%.*}; name=${base#*.}
  if grep -q '=REPLACE$' "$f"; then echo "skip  $f (still has REPLACE values)"; continue; fi
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ns" create secret generic "$name" --from-env-file="$f" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "ok    $ns/$name"
done

# Velero and Longhorn want the MinIO credentials in their own namespaces, in their own shapes
if [ -f secrets/ai.minio-root.env ]; then
  # shellcheck disable=SC1091
  source secrets/ai.minio-root.env
  kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n velero create secret generic minio-credentials \
    --from-literal=cloud="[default]
aws_access_key_id=${rootUser}
aws_secret_access_key=${rootPassword}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n longhorn-system create secret generic minio-credentials \
    --from-literal=AWS_ACCESS_KEY_ID="$rootUser" --from-literal=AWS_SECRET_ACCESS_KEY="$rootPassword" \
    --from-literal=AWS_ENDPOINTS=http://minio.ai.svc:9000 --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "ok    velero/minio-credentials, longhorn-system/minio-credentials"
fi
