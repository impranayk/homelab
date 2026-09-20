# Build log

What actually happened, phase by phase, with the commands, so it can be repeated or understood
later. Dates are when the phase landed on the laptop. The blog post carries the same log with
screenshots: https://drpranayjha.com/home-lab-blueprint-ai-kubernetes-one-laptop/

---

## Phase 1: cluster and first app (19 Sep 2026, one evening)

**Outcome:** a three-node Kubernetes cluster on the laptop, Argo CD reading this repository from
GitHub, DrJhaGPT Pro running behind ingress with a certificate from the lab's own CA, and one
proven Git-only change.

### What went in

| Component | Version | Purpose | Where |
|---|---|---|---|
| WSL2 + Ubuntu 24.04 | WSL 2.7.14, kernel 6.18 | the Linux VM everything runs in | `bootstrap/wslconfig.example` |
| Docker Engine | from Docker's apt repo | container runtime, natively in Ubuntu | `bootstrap/00-docker.sh` |
| k3d / k3s | k3s v1.35.5 | 1 server + 2 agents as containers, ports 80/443, local registry | `bootstrap/k3d-homelab.yaml`, `01-cluster.sh` |
| Argo CD | chart 10.9.2 | GitOps controller, app-of-apps | `bootstrap/10-argocd.sh`, `clusters/homelab/` |
| ingress-nginx | chart 4.15.1 | the front door | `platform/phase-1-cluster/ingress-nginx` |
| cert-manager + lab CA | chart 1.21.2 | certificates for every hostname | `platform/phase-1-cluster/cert-manager` (+ `extras/ca-issuer.yaml`) |
| drjhagpt-pro | Streamlit app | the first workload | `charts/streamlit-app`, `apps/drjhagpt-pro` |

### Steps, in order

1. **Windows (PowerShell):** wrote `C:\Users\<me>\.wslconfig` (12 GB, 6 threads, 4 GB swap,
   `autoMemoryReclaim=gradual`). `wsl --update` took WSL from 2.1.5 to 2.7.14; only after that did
   `wsl --install -d Ubuntu-24.04` accept the distro name. `wsl --set-default Ubuntu-24.04`, `wsl --shutdown`.
2. **Docker Desktop failed** with "Unexpected WSL error ... provisioning docker WSL distros" (too
   old for WSL 2.7). Quit it and ran `bootstrap/00-docker.sh` (Docker Engine in Ubuntu, user added to
   the `docker` group; `newgrp docker` was needed in the same session). `docker run --rm hello-world` passed.
3. `git clone https://github.com/impranayk/homelab.git ~/homelab`. The scripts had lost their
   executable bit (committed from Windows): `chmod +x bootstrap/*.sh` locally, then
   `git update-index --chmod=+x bootstrap/*.sh` in the repo so it never recurs.
4. `bootstrap/00-tools.sh`: k3d, kubectl, helm, k9s, argocd CLI.
5. `bootstrap/01-cluster.sh`: cluster `homelab` created in 63 s. Three nodes Ready. Registry at
   `localhost:5111` from the laptop, `homelab-registry:5000` from inside the cluster. Traefik disabled
   so ingress comes from Git.
6. `bootstrap/10-argocd.sh`: `helm install` of Argo CD, then `kubectl apply -f clusters/homelab/root.yaml`
   and `bootstrap/argocd-repos.yaml`. Within two minutes Argo CD had installed cert-manager, the CA
   (`cert-manager-extras`) and ingress-nginx from GitHub. `drjhagpt-pro` sat Degraded, waiting for its
   Secret and image.
7. `bootstrap/21-gen-secrets.sh` generated random platform passwords into `secrets/*.env`. Put the
   app's real keys (Groq, Supabase, Gemini, the website token) into `secrets/apps.drjhagpt-pro-env.env`
   in `KEY=value` form (Streamlit Cloud shows them as TOML `KEY = "value"`; the quotes must go).
   `bootstrap/20-secrets.sh` created the Kubernetes Secrets; files still containing `REPLACE` are skipped.
8. Image: `git clone` of the app repo inside Ubuntu (GitHub credentials via the Windows Git
   Credential Manager: `git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"`),
   copied in `apps/drjhagpt-pro/Dockerfile`, wrote a `.dockerignore` (`.git`, `.env`, secrets), then
   `docker build --build-arg APP_FILE=streamlit_app.py -t localhost:5111/drjhagpt-pro:dev .` and
   `docker push`. The waiting pod pulled it and went `1/1 Running`. The app reads its keys from
   environment variables; no `secrets.toml` was needed.
9. `bootstrap/30-trust-ca.sh`: exported the CA from the `homelab-ca` Secret, `certutil -addstore Root`
   on Windows (UAC prompt). https://drjhagpt.127.0.0.1.sslip.io with a green lock; login works
   against the same Supabase project as the live app.
10. **The one-rule test:** added `LAB_PHASE: "1"` under `env:` in `apps/drjhagpt-pro/values.yaml`,
    committed, pushed. `kubectl -n argocd get app drjhagpt-pro -w` showed Synced → OutOfSync →
    Progressing → Healthy; `kubectl -n apps exec deploy/drjhagpt-pro -- printenv LAB_PHASE` printed `1`.

### What broke and the fix

| Symptom | Cause | Fix |
|---|---|---|
| `Invalid distribution name: 'Ubuntu-24.04'` | WSL 2.1.5's catalogue only had generic `Ubuntu` | `wsl --update` first |
| `wsl: Sparse VHD support is currently disabled` | WSL 2.7 disabled `sparseVhd` (corruption risk) | removed the line from `.wslconfig` |
| Docker Desktop "Unexpected WSL error" | old Docker Desktop vs new WSL | native Docker Engine (`00-docker.sh`) |
| `permission denied ... docker.sock` after install | group membership not in the current shell | `newgrp docker` (or reopen) |
| `bootstrap/00-docker.sh: Permission denied` | executable bit lost in a Windows commit | `chmod +x`, then `git update-index --chmod=+x` |
| `git commit` refused: "Author identity unknown" | fresh Ubuntu | `git config --global user.name/user.email` (GitHub address) |

### Verified by

`kubectl get nodes` (3 Ready), `kubectl -n argocd get applications` (root, cert-manager,
cert-manager-extras, ingress-nginx, drjhagpt-pro all Synced/Healthy), the app answering a question
at its lab URL, and the `LAB_PHASE` round trip.

---

## Phase 2: delivery (20 Sep 2026)

**Outcome:** the app's source lives in the lab's own Gitea; a pipeline in the cluster scans,
builds, scans and pushes the image; the running version is chosen by a tag in this repository.

### What went in

| Component | Version | Purpose | Where |
|---|---|---|---|
| Argo CD (self-managed) | chart 10.9.2 | Argo CD now manages its own Helm release | `platform/phase-2-delivery/argo-cd` |
| Gitea | chart 12.7.0 | git hosting, registry (unused for now), Actions | `platform/phase-2-delivery/gitea` |
| Gitea Actions runner | chart `actions` 0.1.2 | runs CI jobs, with a Docker-in-Docker sidecar | `platform/phase-2-delivery/gitea-runner` |
| build workflow | | Gitleaks → docker build → Trivy → push | `.gitea/workflows/build.yaml` (copied into the app repo) |

### Steps, in order

1. `phases.yaml` `"2": { enabled: true }`, push, refresh root. Two Applications appeared.
2. `gitea` went `Unknown` with a ComparisonError: *"The actions sub-chart has been outsourced to a
   dedicated chart"*. Chart 12 also bundles Bitnami Postgres and Valkey whose old image tags are no
   longer served. Rewrote the values: `DB_TYPE: sqlite3`, `session`/`cache` in memory, `queue` level,
   bleve indexer, all four database sub-charts `enabled: false`, `strategy: Recreate` (one pod on one
   PVC), `proxy-body-size: "0"` on the ingress for image pushes. Gitea came up; logged in as `homelab`
   with the generated password.
3. Runner: added the `gitea-runner` component (chart `actions`). Generated the registration token
   from the running Gitea (`kubectl -n gitea exec deploy/gitea -c gitea -- gitea --config /data/gitea/conf/app.ini actions generate-runner-token`),
   stored it as `secrets/gitea.gitea-runner-token.env`, applied with `20-secrets.sh`, set the component
   `enabled: true`. Pod `gitea-runner-runner-0` reached `2/2`; Site Administration → Runners showed it
   Idle with label `ubuntu-latest`.
4. App repo into Gitea: created `homelab/drjhagpt-pro` in the UI (push-to-create is off), then
   `git remote add gitea https://gitea.127.0.0.1.sslip.io/homelab/drjhagpt-pro.git && git push gitea main`
   (554 MB, mostly index data and history).
5. Repository secrets `REGISTRY_USER` / `REGISTRY_TOKEN` in Gitea; copied `build.yaml` into the app
   repo's `.gitea/workflows/` and pushed. That push triggered the first run.
6. Run #1 turned out to be the app repo's existing `.github/workflows/ci.yml` (pytest + retrieval
   eval), which Gitea Actions also executes. It held the single runner for 14 minutes. Cancelled it,
   and added a job-level `if: github.server_url == 'https://github.com'` so it is skipped on Gitea.
7. Run #2: Gitleaks clean, build 1m48s, Trivy 1m07s with no CRITICAL findings, **push failed**:
   `dial tcp 127.0.0.1:80: connect: connection refused`. Inside DinD, `gitea.127.0.0.1.sslip.io`
   resolves to the DinD container itself. Changed the workflow to push to `homelab-registry:5000`
   (resolvable from pods because k3d injects it into CoreDNS) and gave DinD
   `--insecure-registry=homelab-registry:5000`; dropped the login step (the k3d registry has no auth).
8. Run #4 green end to end; image `homelab-registry:5000/drjhagpt-pro:528603c`.
9. Deploy by tag: `image.tag: 528603c` in `apps/drjhagpt-pro/values.yaml`, push. The new pod went
   `CrashLoopBackOff`: `File does not exist: app.py`. The Dockerfile copied into the app repo before
   the entry-file fix still defaulted to `app.py`. Because the strategy is `Recreate`, the app was down
   until the fix. Copied the corrected Dockerfile, pushed (run #5 green), set `image.tag: c49e633`,
   pod `1/1 Running`; `kubectl get deploy -o jsonpath=...image` confirmed the pipeline-built image.
10. `git push gitea` once failed to authenticate: the credential manager had cached a wrong password.
    `printf 'protocol=https\nhost=gitea.127.0.0.1.sslip.io\n' | git credential reject`, then push.

### What broke and the fix

| Symptom | Cause | Fix |
|---|---|---|
| Gitea ComparisonError about `check-actions-not-present.yaml` | chart 12 moved the runner out | separate `gitea-runner` component |
| Bitnami Postgres/Valkey images not pullable | Bitnami stopped serving old tags | SQLite + memory cache for the lab |
| `Push to create is not enabled` (403) | repo did not exist in Gitea | create it in the UI first |
| Build queued at 0 s for 7+ minutes | single runner busy with the GitHub test workflow | cancel; `if: github.server_url == ...` |
| Push: `connection refused` to 127.0.0.1:80 | lab hostname resolves to DinD itself | push to `homelab-registry:5000`, `--insecure-registry` |
| New pod `CrashLoopBackOff`, `app.py` missing | stale Dockerfile default | `ARG APP_FILE=streamlit_app.py` |
| `Authentication failed` on `git push gitea` | wrong cached credential | `git credential reject` |

### Measured

`kubectl top nodes` after phases 1+2: 1555 + 850 + 3852 MiB ≈ **4.7 GB** across the three nodes.
The Docker-in-Docker sidecar in the runner is the unexpected item.

---

## Phase 3: observability (20 Sep 2026)

**Outcome:** metrics, logs and dashboards for everything in the cluster; alert rules evaluating;
one real problem found and fixed from a log query.

### What went in

| Component | Version | Purpose | Where |
|---|---|---|---|
| kube-prometheus-stack | chart 91.4.1 | Prometheus (2-day retention), Alertmanager, Grafana, exporters | `platform/phase-3-observe/kube-prometheus-stack` |
| Loki | chart 7.3.0 | log store, single-binary, filesystem, 48 h | `.../loki` |
| Alloy | chart 1.12.1 | DaemonSet that tails every pod's log into Loki | `.../alloy` |
| Tempo | chart 1.24.4 | trace store | `.../tempo` |
| OpenTelemetry collector | chart 0.173.1 | OTLP in, Tempo + Prometheus out | `.../opentelemetry-collector` |
| ntfy + ntfy-alertmanager | plain manifests | push notifications, Alertmanager bridge | `.../ntfy/extras/ntfy.yaml` |

### Steps, in order

1. `phases.yaml` `"3": { enabled: true }`, push, refresh root. Six Applications appeared.
2. First look at `kubectl -n monitoring get pods`: `ntfy-alertmanager` in `Error`,
   `opentelemetry-collector` in `CrashLoopBackOff`, `alloy` ×3 `ContainerCreating`, Prometheus,
   Grafana, Loki, Tempo, ntfy coming up.
3. Logs: the ntfy bridge said *"line 7: quoted string not allowed after atom"*: it reads scfg
   (directive syntax), not YAML. Rewrote the ConfigMap (`http-address`, `ntfy { base-url, topic }`,
   `labels { severity "critical" { priority 5 } }`) and the mount path.
   The OTel collector said *"'exporters' unknown type: prometheus"*: the `-k8s` image is a slim build.
   Switched to `otel/opentelemetry-collector-contrib`.
4. `kube-prometheus-stack` sat at "waiting for completion of hook admission-create" for a couple of
   minutes after the Job had already completed; it resolved on its own.
5. Alloy crash-looped: *"expected TERMINATOR, got ILLEGAL"*. Its config language wants one attribute
   per line, no `;`. Rewrote the config. The pods did not pick up the new ConfigMap until deleted
   (`kubectl -n monitoring delete pod -l app.kubernetes.io/name=alloy`); then `2/2` on all three nodes.
6. Grafana at https://grafana.127.0.0.1.sslip.io. Edge said "Not secure" although
   `kubectl -n monitoring get certificate` showed `grafana-tls` Ready: the browser had kept a
   connection open from before the certificate existed. Restarting Edge fixed it.
7. **Explore → Loki → `{namespace="apps"}`:** 496 lines in an hour, all
   `failed to create fsnotify watcher: too many open files`, steadily, for hours.
   - First diagnosis: Streamlit's development file watcher. Set `STREAMLIT_SERVER_FILE_WATCHER_TYPE=none`
     in the chart, redeployed. The histogram did not change. Wrong.
   - Second look: the message is the **kubelet's**, emitted into the log stream that Alloy tails
     through the API. Cause: WSL's `fs.inotify.max_user_instances=128`, exhausted by three nodes
     plus a log shipper.
   - Fix on the Ubuntu host: `sysctl -w fs.inotify.max_user_instances=8192 fs.inotify.max_user_watches=1048576`,
     persisted in `/etc/sysctl.d/99-homelab.conf`, added to `bootstrap/01-cluster.sh`.
   - `kubectl -n apps logs deploy/drjhagpt-pro --since=60s | grep -c fsnotify` → `0`; the Loki
     histogram went flat at 03:58. The Streamlit env stays in the chart as good practice for containers.

### What broke and the fix

| Symptom | Cause | Fix |
|---|---|---|
| ntfy bridge `Error` | config written as YAML | scfg directives, key `config`, `--config /etc/ntfy-alertmanager/config` |
| OTel collector `CrashLoopBackOff` | `-k8s` image lacks the Prometheus exporter | `-contrib` image |
| Alloy `CrashLoopBackOff` | River syntax (`;` on one line) | one attribute per line; delete pods to reload |
| Grafana "Not secure" in Edge | stale connection with nginx's placeholder cert | restart the browser |
| fsnotify spam in every pod log | WSL inotify limit (kubelet message) | sysctl on the host; in `01-cluster.sh` |

### Still open from phase 3

- Phone alerts: the ntfy bridge points at the in-cluster ntfy, which the phone cannot reach.
  Switch `base-url` to `https://ntfy.sh` with an unguessable topic (see the comment in `ntfy.yaml`).
- Traces: the collector and Tempo are up; the app does not send any yet (OpenTelemetry SDK, ~10 lines).

### Measured

Phases 1-3 at rest: ≈ **6.3 GB** across the three nodes.

---

## Phase 4: security, first attempt (20 Sep 2026)

**Outcome:** the laptop hung; recovered; three root causes found; the phase is being brought back
one component at a time.

### What was switched on at once

external-secrets 2.10.0, OpenBao 0.29.5, Keycloak (keycloakx 7.3.2), Kyverno 3.9.1 + the three house
policies + the pod-security baseline, Trivy Operator 0.36.0, Falco 9.1.0. Eight Applications in one
push.

### What happened, in order

1. `phases.yaml` `"4": { enabled: true }`, push. Pods started. Within minutes the laptop stopped
   responding. Hard reboot.
2. After the reboot, `docker ps` showed all five containers up and `kubectl get nodes` three Ready:
   the cluster restarts with Docker, which starts with Ubuntu. Set `"4": { enabled: false }` and
   pushed immediately, before everything finished restarting.
3. `kubectl top pods -A --sort-by=memory` while things restarted: Keycloak at **1188m CPU / 527 MiB**
   (JVM start-up); Trivy operator 238 MiB and about to launch a scan job per image; and **two** Argo CD
   application controllers: `argocd-application-controller-0` and `argo-cd-argocd-application-controller-0`.
4. `kubectl -n argocd get sts,deploy`: a complete second Argo CD (`argo-cd-argocd-server`,
   `-repo-server`, `-redis`, `-applicationset-controller`, `-application-controller`). Cause: the
   self-managing `argo-cd` Application rendered with Helm release name `argo-cd` (the component
   name) while `bootstrap/10-argocd.sh` had installed release `argocd`. The duplicate had been running
   since phase 2 and explained the OutOfSync flapping. Deleted its StatefulSet and Deployments
   (`-l app.kubernetes.io/instance=argo-cd`), later its Services and the one leftover ConfigMap.
5. `kubectl` started timing out (`context deadline exceeded`) with memory fine (5 GB free, no
   swap). `kubectl get pods -A | grep -v Running` had shown `kyverno-admission-controller` in
   `PodInitializing`; its nine webhooks were registered, so every API write waited on a webhook that
   could not answer. Deleting the webhooks helped only briefly: two came back within minutes because
   Kyverno re-creates them. Scaled the Kyverno Deployments and the Keycloak StatefulSet to zero, then
   deleted the webhooks for good.
6. Every Application showed `Unknown`. The root app's condition, in sequence:
   *`dial tcp 10.43.190.59:8081: connection refused`* (the deleted duplicate repo-server Service; fixed
   by restarting the controller) → *`name resolver error: produced zero addresses`* (the shared
   `argocd-cmd-params-cm` had `repo.server: argo-cd-argocd-repo-server:8081` and
   `redis.server: argo-cd-argocd-redis:6379`, written by the duplicate; patched back to
   `argocd-repo-server:8081` / `argocd-redis:6379`, restarted controller, server, applicationset
   controller) → *`failed to get git client ... lookup argo-cd-argocd-redis`* (the repo-server had not
   been restarted; restarted it) → *`failed to list refs ... Client.Timeout`* (the repo-server was just
   slow after restarting; `git ls-remote` from inside the pod worked).
7. `root` went `OutOfSync / Progressing` with no error and pruned the phase-4 Applications. Deleted
   the empty namespaces by hand (Argo CD never deletes namespaces). `kubectl top nodes` back to
   2.2 + 2.3 + 3.2 GB.
8. Repository changes from the incident: `releaseName: argocd` on the `argo-cd` component (the
   template now honours `.releaseName`); every phase-4 component individually `enabled: false`
   except the secrets pair; Keycloak JVM `-Xmx384m` and a 640 MiB limit; Kyverno webhooks
   `failurePolicy: Ignore`; Argo CD repo-server limit 1 GiB (it had been OOM-killed ten times during
   the reboot storm); three PrometheusRules in `kube-prometheus-stack/extras/homelab-rules.yaml`,
   including `DuplicateArgoCDController`.

### Second attempt, planned order

1. `external-secrets` + `openbao` (on by default now): init and unseal OpenBao, move the app keys in,
   replace the plain Secrets with `ExternalSecret`s.
2. `keycloak`: realm `homelab`, clients for Argo CD, Grafana, Gitea; single login.
3. `kyverno`, then `kyverno-extras` and `kyverno-policies`: Audit first, Enforce once the apps pass.
4. `trivy-operator` with `scanJobsConcurrentLimit: 1`.
5. `falco` last, alone, watched: its eBPF driver on the WSL kernel is the least-tested piece.
6. Harbor as the registry, so the pipeline pushes to a registry that scans on push.
