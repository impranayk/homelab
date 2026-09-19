#!/usr/bin/env bash
# Generates random passwords for every platform component into secrets/ (gitignored).
# Safe to re-run: existing files are kept. API keys for the apps are NOT generated; add them by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p secrets
rnd() { openssl rand -hex "${1:-16}"; }
mk() {
  local f="secrets/$1.env"; shift
  if [ -e "$f" ]; then echo "keep  $f"; return; fi
  printf '%s\n' "$@" > "$f"; echo "made  $f"
}

mk gitea.gitea-admin          "username=homelab" "password=$(rnd)"
mk monitoring.grafana-admin   "admin-user=admin" "admin-password=$(rnd)"
mk keycloak.keycloak-admin    "password=$(rnd)"
mk ai.minio-root              "rootUser=homelab" "rootPassword=$(rnd)"
mk ai.langfuse-secrets        "nextauth-secret=$(rnd 32)" "salt=$(rnd 32)" "encryption-key=$(rnd 32)" \
                              "clickhouse-password=$(rnd)" "redis-password=$(rnd)"
mk ai.litellm-env             "LITELLM_MASTER_KEY=sk-$(rnd 24)" "GROQ_API_KEY=REPLACE" "GEMINI_API_KEY=REPLACE"
mk apps.drjhagpt-pro-env      "GROQ_API_KEY=REPLACE" "GEMINI_API_KEY=REPLACE" "SUPABASE_URL=REPLACE" "SUPABASE_KEY=REPLACE"
mk apps.neevalay-studio-env   "GROQ_API_KEY=REPLACE" "SUPABASE_URL=REPLACE" "SUPABASE_KEY=REPLACE"
echo
echo "Edit the REPLACE values in secrets/apps.*.env and secrets/ai.litellm-env.env, then run bootstrap/20-secrets.sh"
