# homelab

One laptop, the whole production stack. This repository is the single source of
truth for the lab described in
[How I am turning my one laptop into a full AI and Kubernetes lab, layer by layer](https://drpranayjha.com/home-lab-blueprint-ai-kubernetes-one-laptop/).

Rule: nothing is installed by hand after bootstrap. Argo CD reads this repo and
makes the cluster match it. To add, remove or switch off a layer you edit a file
here and push.

## Layout

```
bootstrap/                one-time scripts: cluster, Argo CD, secrets, CA trust
clusters/homelab/
  root.yaml               the app-of-apps Application that Argo CD starts from
  phases.yaml             ON/OFF switch per phase (this is the memory budget)
  apps/                   tiny Helm chart that turns components.yaml into Applications
  components.yaml         every layer: chart, version, namespace, phase, wave
platform/phase-N-*/       one folder per component: values.yaml (+ extras/ manifests)
charts/streamlit-app/     shared Helm chart for the Streamlit apps
apps/<name>/              per-app values (and the Dockerfile to copy into the app repo)
.gitea/workflows/         CI for phase 2 (build, Gitleaks, Trivy, push, Renovate)
secrets/                  gitignored <namespace>.<secret>.env files (21-gen-secrets.sh makes them)
```

## Phase 1: cluster and first app

```bash
# inside WSL2 Ubuntu, Docker running
cp bootstrap/wslconfig.example /mnt/c/Users/$USER_WIN/.wslconfig   # once, then wsl --shutdown
bootstrap/00-tools.sh        # k3d, kubectl, helm, k9s, argocd CLI
bootstrap/01-cluster.sh      # 3-node k3d cluster + local registry
bootstrap/10-argocd.sh       # Argo CD + the root app (edit clusters/homelab/components.yaml repo.url first)
bootstrap/21-gen-secrets.sh  # random platform passwords into secrets/, then add your API keys
bootstrap/20-secrets.sh      # apply them as Kubernetes Secrets
bootstrap/30-trust-ca.sh     # import the lab CA into Windows so every URL gets a green lock
```

Build and push the first app image to the k3d registry:

```bash
docker build -t localhost:5111/drjhagpt-pro:dev /path/to/drjhagpt-enterprise
docker push localhost:5111/drjhagpt-pro:dev
```

Done when `kubectl get nodes` shows three Ready nodes and
https://drjhagpt.127.0.0.1.sslip.io answers a question.

## Switching phases on

Edit `clusters/homelab/phases.yaml`, set `enabled: true` for the phase, push.
Argo CD picks it up within three minutes (or press Refresh on the root app).
Set it back to `false` to scale that whole phase to zero and get the RAM back.

| Phase | Folder | Adds |
|---|---|---|
| 1 | platform/phase-1-cluster | ingress-nginx, cert-manager + lab CA, the apps |
| 2 | platform/phase-2-delivery | Gitea (+ Actions runner, registry), Argo CD self-managed |
| 3 | platform/phase-3-observe | kube-prometheus-stack, Loki, Alloy, Tempo, OTel collector, ntfy |
| 4 | platform/phase-4-secure | Keycloak, OpenBao, External Secrets, Kyverno, Trivy Operator, Falco |
| 5 | platform/phase-5-ai | CloudNativePG + pgvector, MinIO, Ollama, LiteLLM, Langfuse, Open WebUI, Argo Workflows |
| 6 | platform/phase-6-day2 | Longhorn, Velero, Argo Rollouts, Chaos Mesh, OpenCost, kube-bench, Cilium |

## Hostnames

Everything is `<name>.127.0.0.1.sslip.io` and resolves to the laptop with no DNS
setup. TLS comes from cert-manager using the `homelab-ca` ClusterIssuer
(`platform/phase-1-cluster/cert-manager/extras/ca-issuer.yaml`).

| URL | What |
|---|---|
| https://argocd.127.0.0.1.sslip.io | Argo CD |
| https://drjhagpt.127.0.0.1.sslip.io | DrJhaGPT Pro |
| https://gitea.127.0.0.1.sslip.io | Gitea (phase 2) |
| https://grafana.127.0.0.1.sslip.io | Grafana (phase 3) |
| https://keycloak.127.0.0.1.sslip.io | Keycloak (phase 4) |
| https://openbao.127.0.0.1.sslip.io | OpenBao (phase 4) |
| https://chat.127.0.0.1.sslip.io | Open WebUI (phase 5) |
| https://langfuse.127.0.0.1.sslip.io | Langfuse (phase 5) |
| https://litellm.127.0.0.1.sslip.io | LiteLLM (phase 5) |
| https://longhorn.127.0.0.1.sslip.io | Longhorn (phase 6) |

## Notes

- Chart versions in `components.yaml` are pins. Renovate (phase 2 workflow)
  opens a PR when a newer one exists.
- Cilium replaces flannel, which cannot be done on a running cluster. When you
  reach phase 6, uncomment the flannel lines in `bootstrap/k3d-homelab.yaml`,
  run `bootstrap/90-destroy.sh` then `01-cluster.sh` again. Argo CD rebuilds
  everything from this repo; that is the point of the exercise.
- No password or key is committed. Charts reference Secrets by name
  (`existingSecret`); `bootstrap/21-gen-secrets.sh` generates the platform
  passwords locally and `20-secrets.sh` applies them. Phase 4 replaces them with
  ExternalSecrets backed by OpenBao.
