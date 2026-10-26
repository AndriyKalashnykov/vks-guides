# Plan: self-hosted Git (Gitea) and a CI/CD demo in vks-guides

Status: plan for the owner, 2026-10-26. Nothing built yet. Raw research and adversary verdicts:
the raw research output (kept locally, not committed) (5 research facets, 1 planner, 3 adversaries:
vks-adversary, adversary-docker, adversary-security-secrets, all CLEAR-WITH-CHANGES).

## Shape (owner's requirement)

Standalone guides, each usable on its own like HARBOR.md and ARGOCD.md today, plus one guide that
ties them together:

| guide | stands alone | what it does |
|---|---|---|
| HARBOR.md | exists | Harbor Supervisor Service, CA, project, robot |
| ARGOCD.md | exists | ArgoCD Service, VKS cluster, test app from GitHub (unchanged; one cross-link added) |
| GITEA.md | new | Gitea in a VKS cluster: install, log in, create a repo, push to it, uninstall |
| TEKTON.md | new | Tekton Pipelines + Triggers in a VKS cluster: install, run a sample Task, uninstall |
| CICD.md | new, overarching | weaves Harbor + ArgoCD + Gitea + Tekton for test-web-apps: seed repos in Gitea, ArgoCD syncs from Gitea, Tekton builds the image with Kaniko, pushes to Harbor, writes the tag back, a Gitea push triggers it all; links to the four guides' steps and adds only the glue |

## Decision matrix (weights set by the lead)

guide fit 0.25, lab footprint 0.20, works under VKS/PSA 0.15, reuse of vks-airgap-cicd 0.15,
upstream health 0.15, free licence 0.10.

| option | total |
|---|---|
| Gitea + Tekton + Kaniko (osscontainertools fork, free ghcr image) | **4.00** |
| Gitea + Tekton + Kaniko v1.24.0 (archived upstream) | 3.55 |
| Gitea + Tekton + BuildKit rootless (needs a privileged namespace) | 3.55 |
| Gitea + Gitea Actions, kubernetes mode | 3.30 |
| Gitea + Gitea Actions with DinD (privileged; PSA dry run refused it, MEASURED) | 3.00 |
| GitLab CE + Runner (documented floor 8 vCPU / 16-30 GB; lab-gc1 has about 2.1 vCPU / 3.7 GiB free, MEASURED) | 2.30 |

## Recommended stack

- **Gitea** rootless, one Deployment, SQLite on a PVC, namespace PSA restricted, LoadBalancer
  Service, plain HTTP on port 3000. Plain Deployment, not the Helm chart (chart 12.7.0 fails PSA
  restricted with defaults and pulls frozen Bitnami images, MEASURED).
- **Tekton** Pipelines v1.17.1 + Triggers v0.37.2 from pinned release assets, no Dashboard.
- **Kaniko** osscontainertools fork, digest-pinned; CI namespace PSA baseline (Kaniko builds as
  root).
- **Harbor** Supervisor Service from HARBOR.md, by FQDN, CA via `--registry-certificate`.
- **ArgoCD** Supervisor Service from ARGOCD.md, Application pointing at the Gitea LB address.

## Changes the adversaries forced (all accepted)

1. Security (3 BLOCKERs):
   - The build step runs the repo's Dockerfile as root, so it must see no Git credential. Only the
     write-back Task mounts the Gitea token, in its own pod.
   - The write-back token belongs to a non-admin bot user with Write on the deploy repo only,
     scope `write:repository`; the admin token never leaves the reader's workstation.
   - The CI/CD AppProject allows no cluster-scoped kinds; the reader creates the app namespace
     (PSA restricted) with kubectl, so a changed deploy repo cannot relabel it privileged.
2. Every credentialed call to Gitea (UI login, token creation, seed push) goes through
   `kubectl port-forward`; the plain-HTTP LB address serves only ArgoCD's anonymous clone of a
   public deploy repo.
3. Gitea gets a generated SECRET_KEY and INTERNAL_TOKEN from a Secret (otherwise it uses its
   public default key).
4. The webhook is signed; lab RED: an unsigned and a wrongly signed POST start no PipelineRun.
5. Harbor: a second, pull-only robot for the app namespace (the push robot stays in the CI
   namespace), or a public demo project; both 90-day expiries and their renewal stated.
6. The write-back pins `tag@sha256:digest` from Kaniko's digest file; the lab test compares the
   running pod's imageID with it.
7. Tekton YAML goes in quoted heredocs (`<<'EOF'`, `@' '@`) so `$(params.x)` is not expanded by the
   shell; guide variables are passed as PipelineRun params.
8. The CI/CD demo uses its own namespace and Application name, so it does not fight ARGOCD.md
   step 8's GitHub-deployed test-web-apps.
9. The robot name `robot$<project>+push` is built inside the block (literal `$`).

## Dockerfile (argocd/test-web-apps/)

```dockerfile
FROM docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
```

plus `index.html` with one line the demo edits (`test-web-apps v1`). There is no Dockerfile to copy
today: the app runs the stock image. deployment.yaml and the GitHub path stay unchanged.

## Phases (each a PR, each lab-tested before merge)

0. **Lab spikes, no PR** (announce to the nested-vsphere-lab session; ask it for free LB VIPs):
   - A: Gitea Running on lab-gc1 under PSA restricted.
   - B: the ArgoCD repo-server on the Supervisor clones from the Gitea LB address
     (inferred from vks-airgap-cicd B165, not yet run on this lab).
   - C: Kaniko pushes to Harbor, five arms: without the CA flag it fails with x509; with it, the
     pushed digest equals Harbor's; the docker.io base pull works from a pod; nodes pull the
     private image with the pull secret; HARBOR.md step 11 passes on lab-gc1.
   - D: Tekton + Gitea + one build fit lab-gc1's headroom (measure node requests).
1. Dockerfile + index.html (local build, run read-only as uid 101, curl shows v1).
2. GITEA.md (standalone).
3. TEKTON.md (standalone).
4. CICD.md part 1: seed Gitea from a workstation clone, ArgoCD syncs from Gitea, a manual
   PipelineRun builds, pushes to Harbor and writes the digest back; page shows v1 from Harbor.
5. CICD.md part 2: signed webhook, edit index.html to v2 in Gitea, page shows v2; RED tests;
   teardown; README rows and Platforms record.

Each in bash, zsh and Windows PowerShell 5.1 on the lab, as ARGOCD.md was.

## Phase 0 results (2026-10-26, 5:04–5:14 PM EDT, lab-gc1 + argocd-1, all MEASURED)

Owner chose the recommendations (Tekton + Kaniko, lab-gc1 as is, HTTP + port-forward, pull-only
robot, Gitea 28.2.0, baseline CI namespace). Harbor project spike-cicd + push and pull-only robots
were created by the nested-vsphere-lab session with the owner's approval.

- A Gitea 28.2.0-rootless (`@sha256:94807314…3306`), plain Deployment, readOnlyRootFilesystem,
  PSA restricted: Running, LB 192.168.101.141:3000. Trap: SECRET_KEY / INTERNAL_TOKEN from
  `openssl rand -hex` keep a trailing newline and every git push fails ("pre-receive hook
  declined", `invalid header field value for "X-Gitea-Internal-Auth"`); generate them with
  `| tr -d '\n'`. `[webhook].ALLOWED_HOST_LIST` is deprecated in 28; use `[security]` only.
- B ArgoCD Service repo-server cloned http://<gitea-vip>:3000/<org>/<repo>.git (public):
  Synced/Healthy at a 40-hex revision; AppProject with an empty clusterResourceWhitelist worked.
- C Kaniko osscontainertools v1.29.0-debug (`@sha256:35092937…3845`) in a baseline namespace:
  without `--registry-certificate` -> `x509: certificate signed by unknown authority`; with it ->
  pushed, Harbor API digest = Kaniko's; docker.io base pulled from the pod.
- C4/C5 nodes pulled the private image with the pull-only robot (dockerconfigjson Secret);
  5/5 pods' imageID = pushed digest; page served from the Harbor image.
- D Tekton Pipelines v1.17.1 + Triggers v0.37.2 (release files sha256 0055828f…71ce,
  c4113c01…d426, cf2a59a9…baa): +~200m CPU / 200Mi; workers at 58–59% CPU, 35–52% memory requested
  with Gitea + app running; set-security-context=true by default, TaskRun Succeeded in a
  restricted namespace. Triggers controller/webhook restarted twice at startup, then stable.
- E Gitea webhook to a ClusterIP URL delivered with `[security] ALLOWED_HOST_LIST=private`.
- Cleanup: everything deleted; lab session asked to delete the Harbor project and robots.

Other pins: alpine/git v2.54.0 `@sha256:e8ceedc7…8ec0`, yq 4.53.6 `@sha256:cfc4eee6…5b23`.

## Owner decisions (answered: all recommendations)

1. Tekton + Kaniko, GitLab CE dropped (too big for a VKS lab cluster). Agree?
2. Cluster size: lab-gc1's 2 small workers have about 2.1 vCPU / 3.7 GiB free. Test there and
   state the floor, or create a bigger cluster for the demo?
3. Gitea over plain HTTP on its LB address (anonymous read only) + port-forward for everything
   credentialed, or HTTPS with a self-signed CA (ArgoCD's CA ConfigMap is owned by kapp and
   probably reverted; needs its own lab test)?
4. Harbor: pull-only robot (recommended) or a public demo project?
5. Gitea 28.2.0 (latest, never run on VKS) or 1.27.2 (lab-proven in vks-airgap-cicd)?
6. A PSA baseline CI namespace in a customer guide (Kaniko needs root): acceptable?
