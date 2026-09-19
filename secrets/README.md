Gitignored. `bootstrap/21-gen-secrets.sh` writes one file per Secret here, named
`<namespace>.<secret-name>.env`; `bootstrap/20-secrets.sh` applies them (files that
still contain `REPLACE` are skipped).

| File | Secret | Used by |
|---|---|---|
| gitea.gitea-admin.env | gitea/gitea-admin | Gitea first admin (phase 2) |
| monitoring.grafana-admin.env | monitoring/grafana-admin | Grafana login (phase 3) |
| keycloak.keycloak-admin.env | keycloak/keycloak-admin | Keycloak bootstrap admin (phase 4) |
| ai.minio-root.env | ai/minio-root (+ velero, longhorn-system copies) | MinIO, Velero, Longhorn backups |
| ai.langfuse-secrets.env | ai/langfuse-secrets | Langfuse, ClickHouse, Redis (phase 5) |
| ai.litellm-env.env | ai/litellm-env | LiteLLM master key + provider keys, Open WebUI |
| apps.drjhagpt-pro-env.env | apps/drjhagpt-pro-env | DrJhaGPT Pro |
| apps.neevalay-studio-env.env | apps/neevalay-studio-env | Neevalay Studio |

Phase 4 moves these into OpenBao and replaces the Secrets with ExternalSecrets.
