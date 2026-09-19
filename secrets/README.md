Gitignored. One env file per app, consumed by bootstrap/20-secrets.sh:

    drjhagpt-pro.env
    neevalay-studio.env
    litellm.env          (phase 5: GROQ_API_KEY, GEMINI_API_KEY, LITELLM_MASTER_KEY)

Phase 4 moves these into OpenBao and replaces the Secrets with ExternalSecrets.
