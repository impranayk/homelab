# homelab

One laptop, the whole production stack. This repository is the single source of truth for the
lab described in
[How I am turning my one laptop into a full AI and Kubernetes lab, layer by layer](https://drpranayjha.com/home-lab-blueprint-ai-kubernetes-one-laptop/).

**Rule:** nothing is installed by hand after bootstrap. Argo CD reads this repo and makes the
cluster match it. To add, remove or switch off a layer you edit a file here and push.

| Doc | What it is for |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | diagrams, what runs where, how a change reaches the cluster, secrets, budget |
| [docs/BUILD-LOG.md](docs/BUILD-LOG.md) | what actually happened per phase: steps, what broke, fixes, measurements |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | recovery procedures for every incident so far |

## Status

| Phase | What it adds | State | Landed |
|---|---|---|---|
| 1 Cluster and first app | k3d, ingress-nginx, cert-manager + lab CA, Argo CD, DrJhaGPT Pro | **Done** | 19 Sep 2026 |
| 2 Delivery | Gitea + Actions runner, pipeline (Gitleaks → build → Trivy → push), deploy by tag, Argo CD self-managed | **Done** | 20 Sep 2026 |
| 3 Observability | Prometheus, Grafana, Alertmanager, Loki, Alloy, Tempo, OTel collector, ntfy | **Done** (phone alerts and app traces pending) | 20 Sep 2026 |
| 4 Security | External Secrets, OpenBao, Keycloak, Kyverno, Trivy Operator, Falco | **Retrying**, one component at a time (first attempt hung the laptop) | |
| 5 AI platform | CloudNativePG + pgvector, MinIO, Ollama, LiteLLM, Langfuse, Open WebUI, Argo Workflows | Not started (values written, never run) | |
| 6 Day 2 | Longhorn, Velero, Argo Rollouts, Chaos Mesh, OpenCost, kube-bench, Cilium | Not started | |

Measured at rest: phases 1+2 ≈ 4.7 GB, phases 1-3 ≈ 6.3 GB across the three nodes, under a 12 GB WSL cap.

## Layout

```
bootstrap/                one-time scripts: docker, tools, cluster, Argo CD, secrets, CA trust, destroy
clusters/homelab/
  root.yaml               the app-of-apps Application that Argo CD starts from
  phases.yaml             ON/OFF switch per phase (this is the memory budget)
  components.yaml         every layer: chart, version, namespace, phase, wave, enabled, extras
  apps/                   tiny Helm chart that turns those two files into Applications
platform/phase-N-*/       one folder per component: values.yaml (+ extras/ plain manifests)
charts/streamlit-app/     shared Helm chart for the Streamlit apps
apps/<name>/              per-app values (and the Dockerfile to copy into the app repo)
.gitea/workflows/         CI for the app repos (build.yaml) and Renovate for this repo
secrets/                  gitignored <namespace>.<secret>.env files (21-gen-secrets.sh makes them)
docs/                     build log and runbook
```

## Phase 1: bootstrap

All commands in the Ubuntu (WSL2) shell. PowerShell only for the `.wslconfig` and `wsl` commands.

```bash
# once, from PowerShell: copy bootstrap/wslconfig.example to C:\Users\<you>\.wslconfig, then  wsl --shutdown
bootstrap/00-docker.sh       # Docker Engine inside Ubuntu (Docker Desktop is not used); reopen the shell after
bootstrap/00-tools.sh        # k3d, kubectl, helm, k9s, argocd CLI
bootstrap/01-cluster.sh      # inotify sysctls + 3-node k3d cluster + local registry
bootstrap/10-argocd.sh       # Argo CD + the root app (repo.url in components.yaml and root.yaml must be set)
bootstrap/21-gen-secrets.sh  # random platform passwords into secrets/, then put your API keys in secrets/apps.*.env
bootstrap/20-secrets.sh      # apply them as Kubernetes Secrets (files still containing REPLACE are skipped)
bootstrap/30-trust-ca.sh     # import the lab CA into Windows so every URL gets a green lock
```

First app image, by hand (from phase 2 on, the pipeline does this):

```bash
git clone https://github.com/impranayk/drjhagpt-ent.git ~/drjhagpt-ent
cp apps/drjhagpt-pro/Dockerfile ~/drjhagpt-ent/ && cd ~/drjhagpt-ent
printf '.git\n.streamlit/secrets.toml\n.env\n' > .dockerignore
docker build -t localhost:5111/drjhagpt-pro:dev . && docker push localhost:5111/drjhagpt-pro:dev
```

Done when `kubectl get nodes` shows three Ready nodes and https://drjhagpt.127.0.0.1.sslip.io
answers a question. Then prove the rule: change a value in `apps/drjhagpt-pro/values.yaml`, push,
and watch `kubectl -n argocd get app drjhagpt-pro -w` roll a new pod.

## Switching phases and components on

- **A phase:** edit `clusters/homelab/phases.yaml`, set `enabled: true`, commit, push. Argo CD polls
  every three minutes; to hurry it: `kubectl -n argocd annotate app root argocd.argoproj.io/refresh=normal --overwrite`.
  Set it back to `false` to prune the whole phase and get the RAM back.
- **A single component:** some entries in `components.yaml` carry `enabled: false` (all of phase 4
  except the secrets pair, `neevalay-studio`, `cilium`). Flip the one you want, commit, push.
- **Phase 4 order** (after the first attempt hung the laptop by starting everything at once):
  `external-secrets` + `openbao` → `keycloak` → `kyverno` → `kyverno-extras`, `kyverno-policies` →
  `trivy-operator` → `falco` last, alone.

## Phase 2: the Actions runner and the pipeline

Gitea must be running before its runner can register. Once https://gitea.127.0.0.1.sslip.io works:

```bash
TOKEN=$(kubectl -n gitea exec deploy/gitea -c gitea -- gitea --config /data/gitea/conf/app.ini actions generate-runner-token)
echo "runner-token=$TOKEN" > secrets/gitea.gitea-runner-token.env
bootstrap/20-secrets.sh
```

then set `enabled: true` on `gitea-runner` in `components.yaml`, commit, push. In Gitea, create the
repository `homelab/<app>` (push-to-create is off), add the app repo as a remote and push, copy
`.gitea/workflows/build.yaml` into the app repo. Every push then produces
`homelab-registry:5000/<app>:<short-sha>`; set that tag in `apps/<app>/values.yaml` to deploy it.

## Hostnames

Everything is `<name>.127.0.0.1.sslip.io`, resolves to the laptop with no DNS setup, and carries a
certificate from the `homelab-ca` ClusterIssuer.

| URL | What | Phase |
|---|---|---|
| https://argocd.127.0.0.1.sslip.io | Argo CD | 1 |
| https://drjhagpt.127.0.0.1.sslip.io | DrJhaGPT Pro | 1 |
| https://gitea.127.0.0.1.sslip.io | Gitea | 2 |
| https://grafana.127.0.0.1.sslip.io | Grafana | 3 |
| https://ntfy.127.0.0.1.sslip.io | ntfy | 3 |
| https://keycloak.127.0.0.1.sslip.io | Keycloak | 4 |
| https://openbao.127.0.0.1.sslip.io | OpenBao | 4 |
| https://chat.127.0.0.1.sslip.io | Open WebUI | 5 |
| https://langfuse.127.0.0.1.sslip.io | Langfuse | 5 |
| https://litellm.127.0.0.1.sslip.io | LiteLLM | 5 |
| https://longhorn.127.0.0.1.sslip.io | Longhorn | 6 |

## Notes

- Chart versions in `components.yaml` are pins (looked up on Artifact Hub, 19 Sep 2026). Renovate
  (`.gitea/workflows/renovate.yaml`) opens a PR when a newer one exists.
- No password or key is committed; the repository is public. Charts reference Secrets by name;
  `21-gen-secrets.sh` generates the platform passwords locally. Phase 4 moves them into OpenBao.
- The pipeline pushes to the cluster's k3d registry, not Gitea's: inside the runner's
  Docker-in-Docker the lab hostname resolves to 127.0.0.1. Harbor replaces the registry in phase 4.
- Cilium replaces flannel, which cannot be done on a running cluster. Uncomment the flannel lines in
  `bootstrap/k3d-homelab.yaml`, `90-destroy.sh`, `01-cluster.sh`; Argo CD rebuilds everything from here.
- Argo CD self-management: the component pins `releaseName: argocd` to match the bootstrap install.
  A mismatch here creates a second Argo CD (see the runbook, R5).
