# Runbook

Things that went wrong once and how they were fixed. Written so the next time takes minutes,
not an evening. All commands run in the Ubuntu (WSL) shell unless marked PowerShell.

## R1. Laptop hung or rebooted: is the cluster back?

```bash
docker ps --format '{{.Names}} {{.Status}}'      # 5 containers: serverlb, server-0, agent-0, agent-1, homelab-registry
kubectl get nodes                                 # 3 Ready
free -g                                           # ~11 GB total, swap 0 used
kubectl top nodes                                 # after ~2 min
```

The k3d containers restart with Docker; Docker starts with Ubuntu (systemd). Expect 2-3 minutes of
high CPU while every pod restarts. If the API times out, see R3 before assuming memory.

## R2. Too much running: park a phase

```bash
sed -i 's/"N": { enabled: true }/"N": { enabled: false }/' clusters/homelab/phases.yaml
git add -A && git commit -m "phase N off" && git push
kubectl -n argocd annotate app root argocd.argoproj.io/refresh=normal --overwrite
```

Argo CD prunes every Application in that phase. Namespaces stay (Argo CD never deletes
namespaces); remove them by hand if you want them gone: `kubectl delete ns <name>`.

## R3. `kubectl` times out: admission webhook lockout

Symptom: `Error from server (Timeout): request did not complete within requested timeout`, while
`docker ps` and `free` are fine. A webhook (Kyverno) is registered but its pod is not answering.

```bash
kubectl -n kyverno scale deploy --all --replicas=0 --request-timeout=60s     # stop it re-creating webhooks
kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration \
  -l webhook.kyverno.io/managed-by=kyverno --request-timeout=60s
```

Kyverno re-creates its webhooks every few minutes while it runs, so scale it to zero first.
The chart values now set `failurePolicy: Ignore`, so a not-ready Kyverno no longer blocks the API.

## R4. Argo CD shows `Unknown` for every Application

Check the root app's condition; it names the cause:

```bash
kubectl -n argocd get app root -o jsonpath='{.status.conditions}'; echo
kubectl -n argocd get pods
```

Seen so far:

| Message | Cause | Fix |
|---|---|---|
| `dial tcp 10.43.x.x:8081: connection refused` | controller holding a connection to a Service that was deleted | restart the controller: `kubectl -n argocd rollout restart sts/argocd-application-controller` |
| `name resolver error: produced zero addresses` | `argocd-cmd-params-cm` points at a repo-server/redis name that does not exist | see R5 |
| `failed to get git client ... lookup argo-cd-argocd-redis` | repo-server still has the old redis address | `kubectl -n argocd rollout restart deploy/argocd-repo-server` |
| `failed to list refs ... Client.Timeout` | repo-server just restarted and is slow, or no egress | `kubectl -n argocd exec deploy/argocd-repo-server -c repo-server -- git ls-remote https://github.com/impranayk/homelab.git HEAD` |

Force a re-evaluation after any fix:

```bash
kubectl -n argocd annotate app root argocd.argoproj.io/refresh=hard --overwrite
```

## R5. Two Argo CDs (self-management release-name mismatch)

Symptom: `kubectl -n argocd get sts,deploy` lists both `argocd-*` and `argo-cd-argocd-*`; two
application controllers in `kubectl top pods -A`; Applications flap OutOfSync/Synced.

Cause: the `argo-cd` component rendered with Helm release name `argo-cd` while the bootstrap
installed release `argocd`. Fixed in `components.yaml` with `releaseName: argocd`. If it recurs:

```bash
kubectl -n argocd delete sts,deploy,svc -l app.kubernetes.io/instance=argo-cd     # the duplicate set only
kubectl -n argocd delete cm argo-cd-argocd-redis-health-configmap
kubectl -n argocd patch cm argocd-cmd-params-cm --type merge \
  -p '{"data":{"repo.server":"argocd-repo-server:8081","redis.server":"argocd-redis:6379"}}'
kubectl -n argocd rollout restart sts/argocd-application-controller
kubectl -n argocd rollout restart deploy/argocd-server deploy/argocd-applicationset-controller deploy/argocd-repo-server
```

Do not delete ConfigMaps by that label: `argocd-cm`, `argocd-rbac-cm` etc. have fixed names and the
duplicate release overwrote them in place; the real Application rewrites them from Git.

## R6. Pod logs full of `failed to create fsnotify watcher: too many open files`

That line is the kubelet's, not the application's. The WSL kernel ships
`fs.inotify.max_user_instances=128`; three nodes plus a log shipper exhaust it.

```bash
sudo sysctl -w fs.inotify.max_user_instances=8192 fs.inotify.max_user_watches=1048576
printf 'fs.inotify.max_user_instances=8192\nfs.inotify.max_user_watches=1048576\n' | sudo tee /etc/sysctl.d/99-homelab.conf
```

`bootstrap/01-cluster.sh` now does this before creating the cluster.

## R7. A pod does not pick up a changed ConfigMap

Crash-looping pods, and DaemonSet pods in general, need a restart to read new config:

```bash
kubectl -n <ns> delete pod -l app.kubernetes.io/name=<name>
```

## R8. Pipeline push fails with `connection refused` to gitea.127.0.0.1.sslip.io

Inside the runner's Docker-in-Docker, that hostname resolves to 127.0.0.1 (the DinD container
itself). The workflow pushes to `homelab-registry:5000` instead; DinD has
`--insecure-registry=homelab-registry:5000` in `platform/phase-2-delivery/gitea-runner/values.yaml`.

## R9. New image crash-loops right after a deploy

Check the log first; the two seen so far:

```bash
kubectl -n apps logs deploy/drjhagpt-pro --tail=20
```

- `File does not exist: app.py` → the Dockerfile's entry file; it is `streamlit_app.py` (build arg `APP_FILE`).
- `envFrom` secret missing → `bootstrap/20-secrets.sh` was not run, or the env file still has `REPLACE` values.

Roll back by reverting the tag commit in Git; Argo CD restores the previous pod.

## R10. Git pushes to Gitea fail to authenticate

The Windows Git Credential Manager cached a wrong password for the Gitea host:

```bash
printf 'protocol=https\nhost=gitea.127.0.0.1.sslip.io\n' | git credential reject
```

## R11. Browser says "Not secure" although the certificate is Ready

The browser kept a connection from before cert-manager issued the certificate. Close the browser
completely and reopen. Firefox needs `security.enterprise_roots.enabled = true` to use the
Windows trust store; Edge and Chrome use it by default.

## R12. Rebuild from nothing

```bash
bootstrap/90-destroy.sh
bootstrap/01-cluster.sh && bootstrap/10-argocd.sh && bootstrap/20-secrets.sh && bootstrap/30-trust-ca.sh
```

Then rebuild and push the app image (or let the pipeline do it once phase 2 is up). Everything
else comes from Git.
