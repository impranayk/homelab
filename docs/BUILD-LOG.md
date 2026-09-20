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

1. **Cap the Linux VM and install Ubuntu (PowerShell).** Wrote `.wslconfig` with 12 GB, 6 threads, 4 GB swap and `autoMemoryReclaim=gradual`. Updated WSL, then installed the distro; the 24.04 name is only accepted after the update.

        wsl --update
        wsl --install -d Ubuntu-24.04
        wsl --set-default Ubuntu-24.04; wsl --shutdown

2. **Docker Engine inside Ubuntu.** Docker Desktop failed with *"Unexpected WSL error ... provisioning docker WSL distros"* (too old for WSL 2.7). Quit it and installed the engine natively. The `docker` group only applies to a new shell.

        bootstrap/00-docker.sh
        newgrp docker
        docker run --rm hello-world

3. **Clone the repo and fix the script bits.** Committed from Windows, the scripts had lost their executable bit.

        git clone https://github.com/impranayk/homelab.git ~/homelab && cd ~/homelab
        chmod +x bootstrap/*.sh
        git update-index --chmod=+x bootstrap/*.sh     # so it never recurs

4. **Tools.** k3d, kubectl, helm, k9s and the argocd CLI.

        bootstrap/00-tools.sh

5. **Cluster.** One server, two agents, ports 80/443 mapped to the laptop, a registry at `localhost:5111` (in-cluster `homelab-registry:5000`), Traefik disabled so ingress comes from Git. Three nodes Ready in 63 seconds.

        bootstrap/01-cluster.sh
        kubectl get nodes

6. **Argo CD and the root app.** Helm installs Argo CD once; the root Application points it at this repo. Within two minutes it had installed cert-manager, the CA and ingress-nginx on its own. The app stayed Degraded, waiting for its Secret and image.

        bootstrap/10-argocd.sh
        kubectl -n argocd get applications -w

7. **Secrets.** Random platform passwords are generated locally; the app's real keys go into one env file in `KEY=value` form (Streamlit Cloud shows them as TOML with quotes; the quotes must go). Files still containing `REPLACE` are skipped.

        bootstrap/21-gen-secrets.sh
        nano secrets/apps.drjhagpt-pro-env.env
        bootstrap/20-secrets.sh

8. **The first image, by hand.** Cloned the app repo inside Ubuntu (GitHub login reused from the Windows Git Credential Manager), added the Dockerfile and a `.dockerignore`, built and pushed. The waiting pod pulled it and went Running. The app reads its keys from environment variables, so no `secrets.toml` was needed.

        git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
        git clone https://github.com/impranayk/drjhagpt-ent.git ~/drjhagpt-ent
        cp ~/homelab/apps/drjhagpt-pro/Dockerfile ~/drjhagpt-ent/ && cd ~/drjhagpt-ent
        printf '.git\n.streamlit/secrets.toml\n.env\n' > .dockerignore
        docker build --build-arg APP_FILE=streamlit_app.py -t localhost:5111/drjhagpt-pro:dev .
        docker push localhost:5111/drjhagpt-pro:dev
        kubectl -n apps get pods -w

9. **Trust the lab CA.** Exports the CA certificate from the cluster and installs it in the Windows root store (UAC prompt). Green lock on every lab URL, and login works against the same Supabase project as the live app.

        bootstrap/30-trust-ca.sh

10. **The one-rule test.** Added `LAB_PHASE: "1"` under `env:` in `apps/drjhagpt-pro/values.yaml`, committed, pushed. Argo CD went Synced → OutOfSync → Progressing → Healthy and the new pod carried the variable. Nothing was applied by hand.

        git add -A && git commit -m "drjhagpt-pro: add LAB_PHASE env" && git push
        kubectl -n argocd get app drjhagpt-pro -w
        kubectl -n apps exec deploy/drjhagpt-pro -- printenv LAB_PHASE      # prints 1

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

1. **Switch phase 2 on.** One line in `phases.yaml`, push, refresh the root app. Two new Applications: `argo-cd` (self-management) and `gitea`.

        sed -i 's/"2": { enabled: false }/"2": { enabled: true }/' clusters/homelab/phases.yaml
        git add -A && git commit -m "phase 2 on" && git push
        kubectl -n argocd annotate app root argocd.argoproj.io/refresh=normal --overwrite

2. **Gitea would not render.** Argo CD reported *"The actions sub-chart has been outsourced to a dedicated chart"*: chart 12 moved the runner out, and it bundles Bitnami Postgres/Valkey images whose old tags are no longer served. Rewrote the values for a laptop: SQLite, in-memory cache and session, level queue, bleve indexer, all four database sub-charts off, `Recreate` strategy, unlimited body size on the ingress for image pushes. Gitea came up. Logged in as `homelab` with the generated password.

        kubectl -n argocd get app gitea -o jsonpath='{.status.conditions}'
        grep password secrets/gitea.gitea-admin.env

3. **The Actions runner.** Added the `gitea-runner` component (chart `actions` 0.1.2). It needs a registration token from the running Gitea; stored it as a secret, switched the component on. The pod reached `2/2` (runner + Docker-in-Docker) and appeared in Site Administration → Runners as Idle, label `ubuntu-latest`.

        TOKEN=$(kubectl -n gitea exec deploy/gitea -c gitea -- gitea --config /data/gitea/conf/app.ini actions generate-runner-token)
        echo "runner-token=$TOKEN" > secrets/gitea.gitea-runner-token.env && bootstrap/20-secrets.sh
        sed -i '/name: gitea-runner/,/chart:/ s/enabled: false/enabled: true/' clusters/homelab/components.yaml
        git add -A && git commit -m "gitea-runner on" && git push

4. **The app repo into Gitea.** Created `homelab/drjhagpt-pro` in the Gitea UI first (push-to-create is off), then pushed the existing clone to it: 554 MB, mostly index data and history.

        cd ~/drjhagpt-ent
        git remote add gitea https://gitea.127.0.0.1.sslip.io/homelab/drjhagpt-pro.git
        git push gitea main

5. **The pipeline.** Two repository secrets in Gitea (`REGISTRY_USER`, `REGISTRY_TOKEN`), the workflow file copied into the app repo, pushed. That push queued the first run.

        mkdir -p ~/drjhagpt-ent/.gitea/workflows && cp ~/homelab/.gitea/workflows/build.yaml ~/drjhagpt-ent/.gitea/workflows/
        git add .gitea Dockerfile .dockerignore && git commit -m "ci: gitea actions build" && git push gitea main

6. **A stranger on the runner.** Run #1 was the app repo's existing GitHub test workflow (`.github/workflows/ci.yml`, pytest and a retrieval eval); Gitea Actions runs those too. It held the single runner for 14 minutes. Cancelled it and made the job GitHub-only.

        # in .github/workflows/ci.yml, at job level, above runs-on:
        if: github.server_url == 'https://github.com'

7. **Run #2: three gates passed, the push failed.** Gitleaks clean, build 1m48s, Trivy 1m07s with no CRITICAL findings, then *"dial tcp 127.0.0.1:80: connect: connection refused"*. Inside Docker-in-Docker the lab hostname resolves to the DinD container itself. Changed the workflow to push to the cluster registry (pods can resolve it because k3d puts it in CoreDNS), gave DinD `--insecure-registry=homelab-registry:5000`, dropped the login step.

8. **Run #4 green end to end.** Image `homelab-registry:5000/drjhagpt-pro:528603c` in the registry.

9. **Deploy by tag, and the first bad deploy.** Set `image.tag: 528603c` in the app values, pushed. The new pod crash-looped: *"File does not exist: app.py"*. The Dockerfile copied into the app repo before the entry-file fix still defaulted to `app.py`. With `Recreate`, the app was down until the next commit. Copied the corrected Dockerfile (run #5 green), set `image.tag: c49e633`, pod Running, image confirmed.

        kubectl -n apps logs deploy/drjhagpt-pro --tail=5
        sed -i 's/^  tag: 528603c$/  tag: c49e633/' apps/drjhagpt-pro/values.yaml && git add -A && git commit -m "deploy c49e633" && git push
        kubectl -n apps get deploy drjhagpt-pro -o jsonpath='{.spec.template.spec.containers[0].image}'

10. **A cached wrong password.** One `git push gitea` failed to authenticate because the Windows credential manager had stored a bad password for the Gitea host. Cleared it and pushed again.

        printf 'protocol=https\nhost=gitea.127.0.0.1.sslip.io\n' | git credential reject

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

1. **Switch phase 3 on.** Same one-line change in `phases.yaml`. Six Applications appeared.

        sed -i 's/"3": { enabled: false }/"3": { enabled: true }/' clusters/homelab/phases.yaml
        git add -A && git commit -m "phase 3 on" && git push
        kubectl -n argocd annotate app root argocd.argoproj.io/refresh=normal --overwrite

2. **First look at the pods.** Two crashing (`ntfy-alertmanager` in Error, `opentelemetry-collector` in CrashLoopBackOff), Alloy ×3 still creating, Prometheus, Grafana, Loki, Tempo and ntfy coming up.

        kubectl -n monitoring get pods

3. **Read the two crash logs.** The ntfy bridge said *"line 7: quoted string not allowed after atom"*: it reads scfg directives, not YAML. Rewrote its ConfigMap and mount path. The OTel collector said *"'exporters' unknown type: prometheus"*: the `-k8s` image is a slim build without that exporter. Switched to `otel/opentelemetry-collector-contrib`. Both Running after the next sync.

        kubectl -n monitoring logs deploy/ntfy-alertmanager --tail=15
        kubectl -n monitoring logs deploy/opentelemetry-collector --tail=15

4. **A hook that looked stuck.** `kube-prometheus-stack` sat at *"waiting for completion of hook admission-create"* for a couple of minutes after the Job had already completed. It resolved on its own.

5. **Alloy's config syntax.** *"expected TERMINATOR, got ILLEGAL"*: the configuration language wants one attribute per line, no `;`. Rewrote it. The crash-looping pods did not pick up the new ConfigMap until deleted; then `2/2` on all three nodes.

        kubectl -n monitoring logs ds/alloy -c alloy --tail=15
        kubectl -n monitoring delete pod -l app.kubernetes.io/name=alloy

6. **Grafana.** Up at https://grafana.127.0.0.1.sslip.io with the generated admin password. Edge said "Not secure" although the `grafana-tls` certificate was Ready: the browser had kept a connection open from before the certificate existed. Restarting the browser fixed it.

        kubectl -n monitoring get certificate
        grep admin-password secrets/monitoring.grafana-admin.env

7. **First Loki query, first real find.** Explore → Loki → `{namespace="apps"}`: 496 lines in an hour, all *"failed to create fsnotify watcher: too many open files"*, steadily, for hours.

8. **Wrong fix first.** Blamed Streamlit's development file watcher, set `STREAMLIT_SERVER_FILE_WATCHER_TYPE=none` in the chart, redeployed. The histogram did not change. Wrong hypothesis, discarded. (The env stays in the chart; it is right for a container, just not the cause.)

9. **Right fix.** The line is the kubelet's, emitted into the log stream Alloy tails through the API. The WSL kernel ships `fs.inotify.max_user_instances=128`; three nodes plus a log shipper exhaust it. Raised it on the Ubuntu host, persisted it, and added it to `bootstrap/01-cluster.sh`. The histogram went flat at 03:58.

        sudo sysctl -w fs.inotify.max_user_instances=8192 fs.inotify.max_user_watches=1048576
        printf 'fs.inotify.max_user_instances=8192\nfs.inotify.max_user_watches=1048576\n' | sudo tee /etc/sysctl.d/99-homelab.conf
        kubectl -n apps logs deploy/drjhagpt-pro --since=60s | grep -c fsnotify      # 0

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

1. **All eight at once.** Set `"4": { enabled: true }`, pushed. Pods started. Within minutes the laptop stopped responding. Hard reboot.

2. **The cluster came back by itself.** Docker starts with Ubuntu, the k3d containers restart with Docker. Switched phase 4 off in Git immediately, before everything finished restarting.

        docker ps --format '{{.Names}} {{.Status}}' && kubectl get nodes && free -g
        sed -i 's/"4": { enabled: true }/"4": { enabled: false }/' clusters/homelab/phases.yaml
        git add -A && git commit -m "phase 4 off (memory)" && git push

3. **What was eating the machine.** Keycloak at 1188m CPU and 527 MiB during JVM start-up; Trivy about to launch a scan job per image; and two Argo CD application controllers in the list, `argocd-application-controller-0` and `argo-cd-argocd-application-controller-0`. There should be one.

        kubectl top nodes && kubectl top pods -A --sort-by=memory | head -15

4. **A second, complete Argo CD.** Server, repo-server, redis, applicationset controller and controller, all duplicated under `argo-cd-argocd-*`. Cause: the self-managing Application rendered with Helm release name `argo-cd` (the component name) while the bootstrap had installed release `argocd`. It had been running since phase 2 and explained the OutOfSync flapping I had waved away. Deleted the duplicate workloads, then its Services and one ConfigMap.

        kubectl -n argocd get sts,deploy -o name
        kubectl -n argocd delete sts,deploy,svc -l app.kubernetes.io/instance=argo-cd
        kubectl -n argocd delete cm argo-cd-argocd-redis-health-configmap

5. **The API stopped answering.** `kubectl` timed out with memory fine (5 GB free, no swap). Kyverno's admission controller was still `PodInitializing` but its nine webhooks were registered, so every API write waited on a webhook that could not answer. Deleting the webhooks helped only briefly: Kyverno re-creates them while it runs. Scaled Kyverno and Keycloak to zero, then removed the webhooks for good.

        kubectl -n kyverno scale deploy --all --replicas=0 && kubectl -n keycloak scale sts --all --replicas=0
        kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l webhook.kyverno.io/managed-by=kyverno

6. **Every Application `Unknown`.** The root app's condition told the story in four acts: *"dial tcp 10.43.190.59:8081: connection refused"* (the deleted duplicate repo-server Service; restarted the controller) → *"name resolver error: produced zero addresses"* (the shared `argocd-cmd-params-cm` had been overwritten by the duplicate with `repo.server: argo-cd-argocd-repo-server:8081` and `redis.server: argo-cd-argocd-redis:6379`; patched it back, restarted controller, server and applicationset controller) → *"failed to get git client ... lookup argo-cd-argocd-redis"* (the repo-server had not been restarted; restarted it) → *"failed to list refs ... Client.Timeout"* (the repo-server was just slow after restarting; a `git ls-remote` from inside the pod worked).

        kubectl -n argocd get app root -o jsonpath='{.status.conditions}'
        kubectl -n argocd patch cm argocd-cmd-params-cm --type merge -p '{"data":{"repo.server":"argocd-repo-server:8081","redis.server":"argocd-redis:6379"}}'
        kubectl -n argocd rollout restart sts/argocd-application-controller
        kubectl -n argocd rollout restart deploy/argocd-server deploy/argocd-applicationset-controller deploy/argocd-repo-server
        kubectl -n argocd annotate app root argocd.argoproj.io/refresh=hard --overwrite

7. **Argo CD pruned phase 4 itself.** Root went OutOfSync/Progressing with no error and removed the eight Applications. Deleted the empty namespaces by hand (Argo CD never deletes namespaces). Memory back to 2.2 + 2.3 + 3.2 GB.

        kubectl delete ns external-secrets keycloak kyverno trivy-system

8. **What changed in the repo.** `releaseName: argocd` on the `argo-cd` component (the template now honours it); every phase-4 component individually `enabled: false` except the secrets pair; Keycloak JVM capped at 384 MB with a 640 MiB limit; Kyverno webhooks `failurePolicy: Ignore`; Argo CD repo-server limit 1 GiB (it had been OOM-killed ten times during the reboot storm); three PrometheusRules in `kube-prometheus-stack/extras/homelab-rules.yaml`, the first one named `DuplicateArgoCDController`.

### Second attempt, planned order

1. `external-secrets` + `openbao` (on by default now): init and unseal OpenBao, move the app keys in,
   replace the plain Secrets with `ExternalSecret`s.
2. `keycloak`: realm `homelab`, clients for Argo CD, Grafana, Gitea; single login.
3. `kyverno`, then `kyverno-extras` and `kyverno-policies`: Audit first, Enforce once the apps pass.
4. `trivy-operator` with `scanJobsConcurrentLimit: 1`.
5. `falco` last, alone, watched: its eBPF driver on the WSL kernel is the least-tested piece.
6. Harbor as the registry, so the pipeline pushes to a registry that scans on push.
