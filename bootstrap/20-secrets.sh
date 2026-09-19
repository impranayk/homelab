#!/usr/bin/env bash
# Phase 1-3 secrets: plain Kubernetes Secrets from gitignored env files.
# Phase 4 replaces these with ExternalSecrets backed by OpenBao.
#
#   secrets/drjhagpt-pro.env      GROQ_API_KEY=... SUPABASE_URL=... SUPABASE_KEY=... GEMINI_API_KEY=...
#   secrets/neevalay-studio.env
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl create namespace apps --dry-run=client -o yaml | kubectl apply -f -
for f in secrets/*.env; do
  [ -e "$f" ] || { echo "no secrets/*.env files found"; exit 1; }
  name=$(basename "$f" .env)
  kubectl -n apps create secret generic "${name}-env" --from-env-file="$f" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "secret apps/${name}-env applied"
done
