# Build and deploy on every push

> [!NOTE]
> **Official documentation for this guide**
>
> - VKS 3.8: [Using builtin-generic-v3.8.0 Cluster Class with 3.8.0 and Later](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/provisioning-tkg-service-clusters/using-the-cluster-v1beta1-api/using-the-versioned-clusterclass/usingbuiltingenericv380clusterclasswith380andlater.html) (`volumes`), [ClusterClass Variable Overrides](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/provisioning-tkg-service-clusters/using-the-cluster-v1beta1-api/using-the-versioned-clusterclass/clusterclass-variable-overrides.html), [KB 408602: Increase ephemeral storage on VKS nodes](https://knowledge.broadcom.com/external/article/408602/increase-ephemeral-storage-on-vsphere-ku.html)
> - Harbor 2.15: [Create Project Robot Accounts](https://goharbor.io/docs/2.15.0/working-with-projects/project-configuration/create-robot-accounts/)
> - Argo CD 3.4: [Projects](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/projects/), [Automated Sync Policy](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/auto_sync/)
> - Kaniko: [osscontainertools/kaniko](https://github.com/osscontainertools/kaniko) (`--registry-certificate`, `--digest-file`)
> - Tekton: [Tasks](https://tekton.dev/docs/pipelines/tasks/), [PipelineRuns](https://tekton.dev/docs/pipelines/pipelineruns/), [EventListeners](https://tekton.dev/docs/triggers/eventlisteners/), [Interceptors](https://tekton.dev/docs/triggers/interceptors/)
> - Gitea 28.2: [Webhooks](https://docs.gitea.com/usage/repository/webhooks/), [API Usage](https://docs.gitea.com/development/api-usage), [Configuration Cheat Sheet](https://docs.gitea.com/administration/config-cheat-sheet) (`[security] ALLOWED_HOST_LIST`)
> - GitLab 19.5: [CI/CD YAML syntax](https://docs.gitlab.com/ci/yaml/), [Custom CI/CD configuration file](https://docs.gitlab.com/ci/pipelines/settings/), [Kubernetes executor](https://docs.gitlab.com/runner/executors/kubernetes/), [Feature flags](https://docs.gitlab.com/runner/configuration/feature-flags/), [Project access tokens](https://docs.gitlab.com/user/project/settings/project_access_tokens/)

This ties the other guides together. You push a change to an app's Git repository; the cluster
builds its image with Kaniko and pushes it to Harbor; the build writes the image's digest (its
unique `sha256:` fingerprint) into a second repository, `deploy`; ArgoCD on the Supervisor sees the
new commit and rolls it out to the VKS cluster. The app is
[`argocd/test-web-apps`](../argocd/test-web-apps): a page that says `test-web-apps v1`.

You can do it with Gitea and Tekton, or with GitLab. Steps 4, 6 and 7 have a section for each; the
other steps are the same, and where their blocks set `GIT_SERVER="gitea"`, change it to
`GIT_SERVER="gitlab"` with GitLab.

| | With Gitea and Tekton | With GitLab |
|---|---|---|
| done first | [HARBOR.md](HARBOR.md) 1-9, [ARGOCD.md](ARGOCD.md) 3, 4 and 7, [GITEA.md](GITEA.md) 1-8, [TEKTON.md](TEKTON.md) 1 and 2 (A) or 1 and 3 (B) | [HARBOR.md](HARBOR.md) 1-9, [ARGOCD.md](ARGOCD.md) 3, 4 and 7, [GITLAB.md](GITLAB.md) 1-8 |
| builds in | namespace `cicd-ci` | namespace `gitlab-runner` (GITLAB.md's runner) |
| writes back from | a Tekton Task with a Gitea bot user's token | a second, locked runner with a deploy token |
| starts on a push | a signed Gitea webhook (step 7) | by itself |

You need:

- the Harbor files from HARBOR.md in `~/.config/vks-guides/harbor` (PowerShell:
  `$HOME\.config\vks-guides\harbor`): `harbor-data-values.yml`, `harbor-ca.crt` and `secrets.env`;
- the VKS cluster from ARGOCD.md step 7, its kubeconfig ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig))
  and your Supervisor kubeconfig;
- with GitLab, a worker with its own disk for container images: on a `best-effort-large` worker's
  15 GiB disk, GitLab and the build filled it and GitLab was evicted. A worker made with this node
  pool in the cluster's file ([CLUSTER.md](CLUSTER.md) step 9) has room:

  ```yaml
          - class: node-pool
            name: node-pool-gitlab
            replicas: 1
            variables:
              overrides:
                - name: vmClass
                  value: best-effort-large
                - name: volumes
                  value:
                    - name: containerd
                      mountPath: /var/lib/containerd
                      capacity: 40Gi
                      storageClass: wcp-vmfs    # your storage class
  ```

- the Git server's port-forward running in its own terminal ([GITEA.md](GITEA.md) step 6, or
  [GITLAB.md](GITLAB.md) step 5) and its load-balancer address ([GITEA.md](GITEA.md) step 8, or
  [GITLAB.md](GITLAB.md) step 7). Run this guide's blocks in one other terminal.
- [kubectl](KUBECTL.md), [jq and openssl](PREREQS.md) and git.

> [!WARNING]
> **For tests only.** ArgoCD reads `deploy` over plain HTTP, so anyone between the Git server and
> ArgoCD can change what is deployed into `cicd-demo`, and run pods there that read the Harbor
> robot that pulls. The build runs the app's Dockerfile as root and can read the Harbor robot that
> pushes, which may push only to the project `cicd-demo`. With GitLab, every job on GITLAB.md's
> runner can read that robot, and the build can read its job's token while the job runs.

The blocks keep their files in `~/.config/vks-guides/cicd` (PowerShell:
`$HOME\.config\vks-guides\cicd`).

## 1. Check what is in place

This checks that the other guides' parts are in place. It shows whether Harbor answers, which of
the namespaces `gitea`, `gitlab`, `gitlab-runner` and `cicd-demo` exist, whether Tekton Triggers is
installed, and which clusters ArgoCD on the Supervisor can deploy to.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null)"
if [ -z "$HARBOR_FQDN" ] || [ ! -s "$HARBOR_DIR/harbor-ca.crt" ] || [ ! -r "$HARBOR_DIR/secrets.env" ]; then
  echo "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
elif ! NS="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get namespace -o name)"; then
  echo "FAILED: cannot read the cluster (see the error above)"
else
  echo "Harbor ${HARBOR_FQDN}: $(curl -sS --cacert "$HARBOR_DIR/harbor-ca.crt" --connect-timeout 20 --max-time 30 -o /dev/null -w '%{http_code}' "https://${HARBOR_FQDN}/api/v2.0/ping")"
  for N in gitea gitlab gitlab-runner cicd-demo; do
    echo "namespace ${N}: $(printf '%s\n' "$NS" | grep -cx "namespace/$N")"
  done
  T="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get clusterinterceptor/github clusterinterceptor/cel clusterrole/tekton-triggers-eventlistener-roles -o name 2>/dev/null)"
  echo "Tekton Triggers objects: $(printf '%s\n' "$T" | grep -c .)"
  echo "ArgoCD destinations: $(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get secret -l argocd.argoproj.io/secret-type=cluster -o json \
    | jq -r '[.items[].data.name // empty | @base64d] | join(" ")')"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor"

$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')"
$global:LASTEXITCODE = $null
if (-not $HARBOR_FQDN -or -not (Test-Path "$HARBOR_DIR\harbor-ca.crt") -or -not (Test-Path "$HARBOR_DIR\secrets.env")) {
  "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
} else {
  $NS = @(kubectl --kubeconfig $VKS_KUBECONFIG get namespace -o name)
  if ($LASTEXITCODE -ne 0) {
    "FAILED: cannot read the cluster (see the error above)"
  } else {
    "Harbor ${HARBOR_FQDN}: $(curl.exe -sS --ssl-no-revoke --cacert "$HARBOR_DIR\harbor-ca.crt" --connect-timeout 20 --max-time 30 -o NUL -w '%{http_code}' "https://$HARBOR_FQDN/api/v2.0/ping")"
    foreach ($N in 'gitea', 'gitlab', 'gitlab-runner', 'cicd-demo') {
      "namespace ${N}: $(@($NS | Where-Object { $_ -ceq "namespace/$N" }).Count)"
    }
    $T = @(kubectl --kubeconfig $VKS_KUBECONFIG get clusterinterceptor/github clusterinterceptor/cel clusterrole/tekton-triggers-eventlistener-roles -o name 2>$null)
    "Tekton Triggers objects: $(@($T | Where-Object { $_ }).Count)"
    $C = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get secret -l argocd.argoproj.io/secret-type=cluster -o json | Out-String | ConvertFrom-Json
    "ArgoCD destinations: $(@($C.items | Where-Object { $_.data.name } | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.data.name)) }) -join ' ')"
  }
}
```

</details>

**Expect:** `Harbor <name>: 200`, then `namespace cicd-demo: 0`, and with Gitea and Tekton
`namespace gitea: 1` and `Tekton Triggers objects: 3`, or with GitLab `namespace gitlab: 1` and
`namespace gitlab-runner: 1`, and `ArgoCD destinations:` with `<your cluster>-<its vSphere
Namespace>` among the names.

**If not:**
- `FAILED: … is missing`: run this on the machine where you did HARBOR.md, or copy that folder
  here.
- `Harbor <name>:` other than `200`: see [HARBOR.md](HARBOR.md) step 9.
- A `0` for your Git server, or `Tekton Triggers objects:` under 3 with Gitea and Tekton: do its
  guide first (the table above); for Tekton, [TEKTON.md](TEKTON.md) step 1, then step 2 (A) or
  step 3 (B).
- `namespace cicd-demo: 1`: an earlier run of this guide is still there; remove it with step 9.
- `ArgoCD destinations:` empty, or an error before it: log in again ([LOGIN.md](LOGIN.md)), or add
  the cluster with [ARGOCD.md](ARGOCD.md) step 7. If the cluster is there under another name, put
  that name in step 5's `DESTINATION`.

## 2. Create the namespaces

This creates two namespaces:

- `cicd-demo`, where the app runs; it accepts only pods without admin rights;
- the build namespace: `cicd-ci` with Gitea and Tekton, GITLAB.md's `gitlab-runner` with GitLab.
  It allows root, because the build runs the app's Dockerfile as root.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GIT_SERVER="gitea"

case "$GIT_SERVER" in gitea) CI_NAMESPACE="cicd-ci" ;; *) CI_NAMESPACE="gitlab-runner" ;; esac
kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: cicd-demo
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${CI_NAMESPACE}
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GIT_SERVER = "gitea"

$CI_NAMESPACE = if ($GIT_SERVER -eq 'gitea') { 'cicd-ci' } else { 'gitlab-runner' }
@"
apiVersion: v1
kind: Namespace
metadata:
  name: cicd-demo
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: $CI_NAMESPACE
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
"@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
```

</details>

**Expect:** `namespace/cicd-demo created` and `namespace/cicd-ci created` (with GitLab,
`namespace/gitlab-runner unchanged`; `unchanged` on a second run).

## 3. Give the cluster two Harbor robots

The build must push images to Harbor, and the app must pull them. This gives each its own Harbor
login. It signs in to Harbor as `admin` (password from HARBOR.md's `secrets.env`) and creates:

- the private Harbor project `cicd-demo`, for the app's images;
- two robot accounts, logins for programs, valid for 90 days: `push` for the build, `pull` for the
  app;
- in the cluster, the Secrets `harbor-push` (build namespace) and `harbor-pull` (`cicd-demo`) with
  those logins; they go straight from Harbor into the Secrets and are never shown;
- the ConfigMap `harbor-ca` with Harbor's certificate, so the build trusts Harbor.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GIT_SERVER="gitea"
HARBOR_PROJECT="cicd-demo"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"

case "$GIT_SERVER" in gitea) CI_NAMESPACE="cicd-ci" ;; *) CI_NAMESPACE="gitlab-runner" ;; esac
HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null)"
if [ -z "$HARBOR_FQDN" ] || [ ! -s "$HARBOR_DIR/harbor-ca.crt" ] || [ ! -r "$HARBOR_DIR/secrets.env" ]; then
  echo "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
else
  CFG="$(mktemp)"
  ( . "$HARBOR_DIR/secrets.env"
    P="$(printf '%s' "$HARBOR_ADMIN_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf 'user = "admin:%s"\n' "$P" > "$CFG" )
  jq -nc --arg p "$HARBOR_PROJECT" '{project_name: $p, metadata: {public: "false"}}' \
    | curl -sS --cacert "$HARBOR_DIR/harbor-ca.crt" --connect-timeout 20 --max-time 30 -K "$CFG" -o /dev/null -w 'project: %{http_code}\n' \
        -X POST -H 'Content-Type: application/json' --data-binary @- "https://${HARBOR_FQDN}/api/v2.0/projects"
  for R in push pull; do
    if [ "$R" = push ]; then
      NS="$CI_NAMESPACE"; A='[{"resource":"repository","action":"push"},{"resource":"repository","action":"pull"}]'
    else
      NS="cicd-demo"; A='[{"resource":"repository","action":"pull"}]'
    fi
    if kubectl --kubeconfig "$VKS_KUBECONFIG" -n "$NS" get secret "harbor-$R" -o name >/dev/null 2>&1; then
      echo "kept: secret harbor-$R in $NS"
      continue
    fi
    J="$(jq -nc --arg r "$R" --arg p "$HARBOR_PROJECT" --argjson a "$A" '{name: $r, duration: 90, level: "project",
          permissions: [{kind: "project", namespace: $p, access: $a}]}' \
      | curl -sS --cacert "$HARBOR_DIR/harbor-ca.crt" --connect-timeout 20 --max-time 30 -K "$CFG" \
          -X POST -H 'Content-Type: application/json' --data-binary @- "https://${HARBOR_FQDN}/api/v2.0/robots")"
    if ! printf '%s' "$J" | jq -e '.secret' >/dev/null 2>&1; then
      echo "FAILED: robot $R: $(printf '%s' "$J" | jq -r '.errors[0] | "\(.code) \(.message)"' 2>/dev/null)"
    else
      printf '%s' "$J" | jq --arg h "$HARBOR_FQDN" --arg ns "$NS" --arg r "$R" '
          ({auths: {($h): {auth: ("\(.name):\(.secret)" | @base64)}}} | tojson | @base64) as $c
          | {apiVersion: "v1", kind: "Secret", metadata: {name: "harbor-\($r)", namespace: $ns}}
            + if $r == "push" then {type: "Opaque", data: {"config.json": $c}}
              else {type: "kubernetes.io/dockerconfigjson", data: {".dockerconfigjson": $c}} end' \
        | kubectl --kubeconfig "$VKS_KUBECONFIG" create -f -
    fi
  done
  J=""
  rm -f "$CFG"
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n "$CI_NAMESPACE" create configmap harbor-ca \
    --from-file=ca.crt="$HARBOR_DIR/harbor-ca.crt" --dry-run=client -o yaml \
    | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f -
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GIT_SERVER = "gitea"
$HARBOR_PROJECT = "cicd-demo"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor"

$CI_NAMESPACE = if ($GIT_SERVER -eq 'gitea') { 'cicd-ci' } else { 'gitlab-runner' }
$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')"
$S = @{}
foreach ($l in Get-Content "$HARBOR_DIR\secrets.env" -ErrorAction SilentlyContinue) { if ($l -cmatch "^(HARBOR_[A-Z_]+)='(.*)'$") { $S[$Matches[1]] = $Matches[2] } }
if (-not $HARBOR_FQDN -or -not (Test-Path "$HARBOR_DIR\harbor-ca.crt") -or -not $S['HARBOR_ADMIN_PASSWORD']) {
  "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
} else {
  $P = $S['HARBOR_ADMIN_PASSWORD'].Replace('\', '\\').Replace('"', '\"')
  $CFG = [IO.Path]::GetTempFileName(); $BODY = [IO.Path]::GetTempFileName()
  try {
    Set-Content -Encoding ascii -Path $CFG -Value "user = `"admin:$P`""
    Set-Content -Encoding ascii -Path $BODY -Value ('{"project_name":"' + $HARBOR_PROJECT + '","metadata":{"public":"false"}}')
    "project: $(curl.exe -sS --ssl-no-revoke --cacert "$HARBOR_DIR\harbor-ca.crt" --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' `
      -X POST -H 'Content-Type: application/json' --data-binary "@$BODY" "https://$HARBOR_FQDN/api/v2.0/projects")"
    foreach ($R in 'push', 'pull') {
      if ($R -eq 'push') { $NS = $CI_NAMESPACE; $A = '[{"resource":"repository","action":"push"},{"resource":"repository","action":"pull"}]' }
      else { $NS = 'cicd-demo'; $A = '[{"resource":"repository","action":"pull"}]' }
      kubectl --kubeconfig $VKS_KUBECONFIG -n $NS get secret "harbor-$R" -o name 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { "kept: secret harbor-$R in $NS"; continue }
      Set-Content -Encoding ascii -Path $BODY -Value ('{"name":"' + $R + '","duration":90,"level":"project","permissions":[{"kind":"project","namespace":"' + $HARBOR_PROJECT + '","access":' + $A + '}]}')
      $J = curl.exe -sS --ssl-no-revoke --cacert "$HARBOR_DIR\harbor-ca.crt" --connect-timeout 20 --max-time 30 -K $CFG `
        -X POST -H 'Content-Type: application/json' --data-binary "@$BODY" "https://$HARBOR_FQDN/api/v2.0/robots" | Out-String | ConvertFrom-Json
      if (-not $J.secret) {
        "FAILED: robot ${R}: $($J.errors[0].code) $($J.errors[0].message)"
      } else {
        $C = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(
          (@{ auths = @{ $HARBOR_FQDN = @{ auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($J.name):$($J.secret)")) } } } | ConvertTo-Json -Depth 4 -Compress)))
        $Y = if ($R -eq 'push') { "type: Opaque`ndata:`n  config.json: $C" } else { "type: kubernetes.io/dockerconfigjson`ndata:`n  .dockerconfigjson: $C" }
        "apiVersion: v1`nkind: Secret`nmetadata:`n  name: harbor-$R`n  namespace: $NS`n$Y`n" | kubectl --kubeconfig $VKS_KUBECONFIG create -f -
      }
    }
  } finally {
    Remove-Item -Force $CFG, $BODY
    Remove-Variable -ErrorAction SilentlyContinue J, C, Y, P
  }
  kubectl --kubeconfig $VKS_KUBECONFIG -n $CI_NAMESPACE create configmap harbor-ca --from-file=ca.crt="$HARBOR_DIR\harbor-ca.crt" --dry-run=client -o yaml |
    kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
}
```

</details>

**Expect:** `project: 201`, `secret/harbor-push created`, `secret/harbor-pull created` and
`configmap/harbor-ca created`. On a second run: `project: 409`, `kept: secret harbor-push …`,
`kept: secret harbor-pull …` and `configmap/harbor-ca unchanged`.

**If not:**
- `FAILED: robot push: CONFLICT …` (or `pull`): the robot exists in Harbor but its Secret is gone,
  and Harbor shows a robot's secret only once. In Harbor's web page, **Projects** → `cicd-demo` →
  **Robot Accounts**, delete the robot, then run this again.
- `namespaces "…" not found`: run step 2 first, then delete the robot as above and run this again.
- `project:` `401`: the password in `secrets.env` is not Harbor's `admin` password any more.
- In 90 days the robots expire and builds or pulls fail with `unauthorized`: delete both robots in
  Harbor and both Secrets (`kubectl --kubeconfig <the VKS kubeconfig> -n <cicd-ci or gitlab-runner>
  delete secret harbor-push` and `… -n cicd-demo delete secret harbor-pull`), then run this again.

## 4. Create the repositories

Both ways create two repositories: `app`, with the Dockerfile and page from
[`argocd/test-web-apps`](../argocd/test-web-apps), and `deploy`, with the Deployment and Service
ArgoCD applies. Both are public, so the build and ArgoCD read them without a login. `deploy`
starts with the stock nginx image; the first build replaces it.

### With Gitea and Tekton

The next block signs in to Gitea as `gitea-admin`. Type that password first; it stays in this
terminal only, and is not shown or saved:

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
printf 'gitea-admin password: '; IFS= read -rs GITEA_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$GITEA_PASSWORD = Read-Host 'gitea-admin password' -AsSecureString
```

Then, in the same terminal, this creates two repositories in Gitea, through GITEA.md step 6's
port-forward:

- `app`, with the app's Dockerfile and page;
- `deploy`, with the files that tell the cluster how to run the app; ArgoCD reads them (step 5).

Copies of the files stay in `~/.config/vks-guides/cicd`. It also creates the user `cicd-bot`, whose
password no one knows and who may write only to `deploy`, and stores a token for it in the Secret
`git-writeback` in `cicd-ci`. The build uses that token to write the new image into `deploy`.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GITEA_URL="http://localhost:3300"
CICD_DIR="$HOME/.config/vks-guides/cicd"

mkdir -p "$CICD_DIR/app" "$CICD_DIR/deploy"
cat > "$CICD_DIR/app/Dockerfile" <<'EOF'
FROM docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
EOF
cat > "$CICD_DIR/app/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>test-web-apps</title></head>
<body>
<h1>test-web-apps v1</h1>
</body>
</html>
EOF
cat > "$CICD_DIR/deploy/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cicd-demo
  namespace: cicd-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: cicd-demo
  template:
    metadata:
      labels:
        app.kubernetes.io/name: cicd-demo
    spec:
      automountServiceAccountToken: false
      imagePullSecrets:
        - name: harbor-pull
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: nginx
          image: docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
          ports:
            - name: http
              containerPort: 8080
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests: { cpu: 50m, memory: 32Mi }
            limits: { cpu: 250m, memory: 128Mi }
          readinessProbe:
            httpGet: { path: /, port: http }
          volumeMounts:
            - { name: tmp, mountPath: /tmp }
      volumes:
        - name: tmp
          emptyDir: { sizeLimit: 64Mi }
EOF
cat > "$CICD_DIR/deploy/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: cicd-demo
  namespace: cicd-demo
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: cicd-demo
  ports:
    - { name: http, port: 80, targetPort: http }
EOF
if [ -z "$GITEA_PASSWORD" ]; then
  echo "FAILED: no password in this terminal; type it first (the block above), then run this again"
elif ! kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- gitea admin user list >/dev/null; then
  echo "FAILED: cannot run gitea in the pod (see the error above)"
else
  CFG="$(mktemp)"
  P="$(printf '%s' "$GITEA_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf 'user = "gitea-admin:%s"\n' "$P" > "$CFG"
  P=""
  api() { curl -sS --connect-timeout 20 --max-time 30 -K "$CFG" -H 'Content-Type: application/json' "$@"; }
  if [ "$(api -o /dev/null -w '%{http_code}' "$GITEA_URL/api/v1/user")" != 200 ]; then
    echo "FAILED: Gitea did not accept gitea-admin and this password, or the port-forward is not running"
  else
    for R in app deploy; do
      echo "repository $R: $(api -o /dev/null -w '%{http_code}' -X POST -d "{\"name\":\"$R\",\"private\":false,\"default_branch\":\"main\"}" "$GITEA_URL/api/v1/user/repos")"
      for F in Dockerfile index.html deployment.yaml service.yaml; do
        [ -f "$CICD_DIR/$R/$F" ] || continue
        jq -n --arg c "$(base64 < "$CICD_DIR/$R/$F" | tr -d '\n')" --arg f "$F" '{content: $c, message: "add \($f)", branch: "main"}' \
          | api -o /dev/null -w "  $F: %{http_code}\n" -X POST --data-binary @- "$GITEA_URL/api/v1/repos/gitea-admin/$R/contents/$F"
      done
    done
    if ! kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- gitea admin user list | awk '$2 == "cicd-bot" { f = 1 } END { exit !f }'; then
      kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- gitea admin user create \
        --username cicd-bot --email cicd-bot@localhost --random-password --must-change-password=false >/dev/null \
        && echo "user cicd-bot: created"
    fi
    echo "cicd-bot writes deploy: $(api -o /dev/null -w '%{http_code}' -X PUT -d '{"permission":"write"}' "$GITEA_URL/api/v1/repos/gitea-admin/deploy/collaborators/cicd-bot")"
    if kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-ci get secret git-writeback -o name >/dev/null 2>&1; then
      echo "kept: secret git-writeback in cicd-ci"
    else
      kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- gitea admin user generate-access-token \
          --username cicd-bot --token-name "cicd-writeback-$(date +%s)" --scopes write:repository --raw \
        | tr -d '\r\n' \
        | jq -R 'if test("^[0-9a-f]{40}$") then {apiVersion: "v1", kind: "Secret", metadata: {name: "git-writeback", namespace: "cicd-ci"},
                  stringData: {username: "cicd-bot", token: .}} else error("Gitea did not return a token") end' \
        | kubectl --kubeconfig "$VKS_KUBECONFIG" create -f -
    fi
  fi
  rm -f "$CFG"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GITEA_URL = "http://localhost:3300"
$CICD_DIR = "$HOME\.config\vks-guides\cicd"

$FILES = @{
  'app\Dockerfile' = @'
FROM docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
'@
  'app\index.html' = @'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>test-web-apps</title></head>
<body>
<h1>test-web-apps v1</h1>
</body>
</html>
'@
  'deploy\deployment.yaml' = @'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cicd-demo
  namespace: cicd-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: cicd-demo
  template:
    metadata:
      labels:
        app.kubernetes.io/name: cicd-demo
    spec:
      automountServiceAccountToken: false
      imagePullSecrets:
        - name: harbor-pull
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: nginx
          image: docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
          ports:
            - name: http
              containerPort: 8080
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests: { cpu: 50m, memory: 32Mi }
            limits: { cpu: 250m, memory: 128Mi }
          readinessProbe:
            httpGet: { path: /, port: http }
          volumeMounts:
            - { name: tmp, mountPath: /tmp }
      volumes:
        - name: tmp
          emptyDir: { sizeLimit: 64Mi }
'@
  'deploy\service.yaml' = @'
apiVersion: v1
kind: Service
metadata:
  name: cicd-demo
  namespace: cicd-demo
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: cicd-demo
  ports:
    - { name: http, port: 80, targetPort: http }
'@
}
foreach ($F in $FILES.Keys) {
  New-Item -ItemType Directory -Force -Path (Split-Path "$CICD_DIR\$F") | Out-Null
  [IO.File]::WriteAllText("$CICD_DIR\$F", ($FILES[$F] -replace "`r`n", "`n") + "`n")
}
$global:LASTEXITCODE = $null
if (-not $GITEA_PASSWORD) {
  "FAILED: no password in this terminal; type it first (the block above), then run this again"
} else {
  $U = @(kubectl --kubeconfig $VKS_KUBECONFIG -n gitea exec deployment/gitea -- gitea admin user list)
  if ($LASTEXITCODE -ne 0) {
    "FAILED: cannot run gitea in the pod (see the error above)"
  } else {
    $P = [Net.NetworkCredential]::new('', $GITEA_PASSWORD).Password.Replace('\', '\\').Replace('"', '\"')
    $CFG = [IO.Path]::GetTempFileName(); $BODY = [IO.Path]::GetTempFileName()
    try {
      [IO.File]::WriteAllText($CFG, "user = `"gitea-admin:$P`"`n", (New-Object Text.UTF8Encoding $false))
      Remove-Variable P
      if ((curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' "$GITEA_URL/api/v1/user") -ne '200') {
        "FAILED: Gitea did not accept gitea-admin and this password, or the port-forward is not running"
      } else {
        foreach ($R in 'app', 'deploy') {
          Set-Content -Encoding ascii -Path $BODY -Value ('{"name":"' + $R + '","private":false,"default_branch":"main"}')
          "repository ${R}: $(curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary "@$BODY" "$GITEA_URL/api/v1/user/repos")"
          foreach ($F in (Get-Item "$CICD_DIR\$R\*" -Include Dockerfile, index.html, deployment.yaml, service.yaml)) {
            $C = [Convert]::ToBase64String([IO.File]::ReadAllBytes($F.FullName))
            Set-Content -Encoding ascii -Path $BODY -Value ('{"content":"' + $C + '","message":"add ' + $F.Name + '","branch":"main"}')
            "  $($F.Name): $(curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary "@$BODY" "$GITEA_URL/api/v1/repos/gitea-admin/$R/contents/$($F.Name)")"
          }
        }
        if (-not @($U | Where-Object { (-split $_)[1] -ceq 'cicd-bot' }).Count) {
          kubectl --kubeconfig $VKS_KUBECONFIG -n gitea exec deployment/gitea -- gitea admin user create `
            --username cicd-bot --email cicd-bot@localhost --random-password --must-change-password=false | Out-Null
          if ($LASTEXITCODE -eq 0) { "user cicd-bot: created" }
        }
        Set-Content -Encoding ascii -Path $BODY -Value '{"permission":"write"}'
        "cicd-bot writes deploy: $(curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary "@$BODY" "$GITEA_URL/api/v1/repos/gitea-admin/deploy/collaborators/cicd-bot")"
        kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-ci get secret git-writeback -o name 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
          "kept: secret git-writeback in cicd-ci"
        } else {
          $T = (kubectl --kubeconfig $VKS_KUBECONFIG -n gitea exec deployment/gitea -- gitea admin user generate-access-token `
            --username cicd-bot --token-name "cicd-writeback-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" --scopes write:repository --raw | Out-String).Trim()
          if ($T -cmatch '^[0-9a-f]{40}$') {
            "apiVersion: v1`nkind: Secret`nmetadata:`n  name: git-writeback`n  namespace: cicd-ci`nstringData:`n  username: cicd-bot`n  token: $T`n" |
              kubectl --kubeconfig $VKS_KUBECONFIG create -f -
          } else {
            "FAILED: Gitea did not return a token (see the error above)"
          }
          Remove-Variable T
        }
      }
    } finally {
      Remove-Item -Force $CFG, $BODY
    }
  }
}
```

</details>

**Expect:** `repository app: 201`, `Dockerfile: 201`, `index.html: 201`, `repository deploy: 201`,
`deployment.yaml: 201`, `service.yaml: 201`, `user cicd-bot: created`, `cicd-bot writes deploy:
204` and `secret/git-writeback created`. On a second run the repositories and files print `409`
and `422`, and `kept: secret git-writeback in cicd-ci`.

**If not:**
- `FAILED: Gitea did not accept …`: type the password again (the first block), check that GITEA.md
  step 6's port-forward is running, then run this again.

### With GitLab

This creates, inside GitLab, the public group `cicd` with three projects:

- `app` (public): the app's Dockerfile and page;
- `deploy` (public): the files that tell the cluster how to run the app; ArgoCD reads them
  (step 5);
- `ci` (private): the pipeline, `.gitlab-ci.yml`, which `app` builds with.

The pipeline sits apart from `app`, so someone who may push to `app` cannot change it. Give your
developers the Developer role on `cicd/app` and the Reporter role on `cicd/ci`. Nobody may
force-push to a project's `main`. The block runs inside GitLab's pod, so no GitLab token reaches
this machine; it takes about a minute.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null)"
if [ -z "$HARBOR_FQDN" ]; then
  echo "FAILED: no hostname in $HARBOR_DIR/harbor-data-values.yml"
else
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab exec -i gitlab-0 -- env HARBOR_FQDN="$HARBOR_FQDN" gitlab-rails runner - <<'EOF'
root = User.find_by_username('root')
registry = ENV.fetch('HARBOR_FQDN')
group = Group.find_by_full_path('cicd')
if group
  puts 'group cicd: kept'
else
  r = Groups::CreateService.new(root, name: 'cicd', path: 'cicd', visibility_level: Gitlab::VisibilityLevel::PUBLIC,
    organization_id: Organizations::Organization.default_organization.id).execute
  group = r.respond_to?(:payload) ? r.payload[:group] : r
  raise "group cicd: #{group.errors.full_messages.join(', ')}" unless group&.persisted?
  puts 'group cicd: created'
end
files = {
  'app' => {
    'Dockerfile' => <<~'TXT',
      FROM docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
      COPY index.html /usr/share/nginx/html/index.html
      EXPOSE 8080
    TXT
    'index.html' => <<~'TXT',
      <!doctype html>
      <html lang="en">
      <head><meta charset="utf-8"><title>test-web-apps</title></head>
      <body>
      <h1>test-web-apps v1</h1>
      </body>
      </html>
    TXT
  },
  'ci' => {
    '.gitlab-ci.yml' => <<~'TXT',
      stages: [build, writeback]

      build:
        stage: build
        tags: [vks]
        image:
          name: ghcr.io/osscontainertools/kaniko:v1.29.0-debug@sha256:350929376b8a69afb1d8b362086c809e4ef6799fa1bcb317c2806ae1447b3845
          entrypoint: [""]
        rules:
          - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
        script:
          - /kaniko/executor
            --context "$CI_PROJECT_DIR"
            --dockerfile "$CI_PROJECT_DIR/Dockerfile"
            --destination "HARBOR_FQDN/cicd-demo/test-web-apps:$CI_COMMIT_SHA"
            --registry-certificate "HARBOR_FQDN=/run/ca/ca.crt"
            --digest-file "$CI_PROJECT_DIR/digest"
        artifacts:
          paths: [digest]
          expire_in: 1 day

      writeback:
        stage: writeback
        tags: [writeback]
        image:
          name: docker.io/alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0
          entrypoint: [""]
        needs:
          - job: build
            artifacts: true
        variables:
          GIT_STRATEGY: none
        resource_group: deploy
        cache: []
        rules:
          - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
        script:
          - |
            set -eu
            D="$(tr -d ' \t\r\n' < digest)"
            if printf '%s\n' "$D" | grep -Eqx 'sha256:[0-9a-f]{64}'; then :; else echo "refused: the digest is not sha256:<64 hex>"; exit 1; fi
            IMAGE="HARBOR_FQDN/cicd-demo/test-web-apps@$D"
            export HOME=/tmp/wb
            unset GIT_CONFIG_GLOBAL
            M="$(git ls-remote --exit-code http://gitlab.gitlab.svc.cluster.local/cicd/app.git refs/heads/main)" || { echo "FAILED: cannot read cicd/app's main"; exit 1; }
            [ "${M%%[[:space:]]*}" = "$CI_COMMIT_SHA" ] || { echo "skipped: cicd/app has moved on from $CI_COMMIT_SHA"; exit 0; }
            umask 077
            mkdir -p "$HOME"
            printf 'http://writeback:%s@gitlab.gitlab.svc.cluster.local\n' "$(tr -d ' \t\r\n' < /run/deploy/token)" > "$HOME/.git-credentials"
            git -c core.hooksPath=/dev/null clone -q http://gitlab.gitlab.svc.cluster.local/cicd/deploy.git "$HOME/deploy"
            cd "$HOME/deploy"
            sed -i "s|^\( *\)image: .*|\1image: $IMAGE|" deployment.yaml
            if git diff --quiet; then echo "unchanged: deployment.yaml already uses $IMAGE"; exit 0; fi
            git -c user.name=writeback -c user.email=writeback@noreply.invalid commit -q -am "test-web-apps $CI_COMMIT_SHORT_SHA"
            git -c core.hooksPath=/dev/null -c credential.helper= -c credential.helper="store --file=$HOME/.git-credentials" push -q origin HEAD:main
            echo "wrote $IMAGE"
    TXT
  },
  'deploy' => {
    'deployment.yaml' => <<~'TXT',
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: cicd-demo
        namespace: cicd-demo
      spec:
        replicas: 2
        selector:
          matchLabels:
            app.kubernetes.io/name: cicd-demo
        template:
          metadata:
            labels:
              app.kubernetes.io/name: cicd-demo
          spec:
            automountServiceAccountToken: false
            imagePullSecrets:
              - name: harbor-pull
            securityContext:
              runAsNonRoot: true
              runAsUser: 101
              runAsGroup: 101
              seccompProfile:
                type: RuntimeDefault
            containers:
              - name: nginx
                image: docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
                ports:
                  - name: http
                    containerPort: 8080
                securityContext:
                  allowPrivilegeEscalation: false
                  readOnlyRootFilesystem: true
                  capabilities:
                    drop: ["ALL"]
                resources:
                  requests: { cpu: 50m, memory: 32Mi }
                  limits: { cpu: 250m, memory: 128Mi }
                readinessProbe:
                  httpGet: { path: /, port: http }
                volumeMounts:
                  - { name: tmp, mountPath: /tmp }
            volumes:
              - name: tmp
                emptyDir: { sizeLimit: 64Mi }
    TXT
    'service.yaml' => <<~'TXT',
      apiVersion: v1
      kind: Service
      metadata:
        name: cicd-demo
        namespace: cicd-demo
      spec:
        type: LoadBalancer
        selector:
          app.kubernetes.io/name: cicd-demo
        ports:
          - { name: http, port: 80, targetPort: http }
    TXT
  },
}
files.each do |name, content|
  p = Project.find_by_full_path("cicd/#{name}")
  if p
    puts "project cicd/#{name}: kept"
  else
    p = Projects::CreateService.new(root, name: name, path: name, namespace_id: group.id,
      visibility_level: name == 'ci' ? Gitlab::VisibilityLevel::PRIVATE : Gitlab::VisibilityLevel::PUBLIC).execute
    raise "project cicd/#{name}: #{p.errors.full_messages.join(', ')}" unless p.persisted?
    puts "project cicd/#{name}: created"
  end
  if p.repository.exists? && !p.repository.empty?
    puts "  files: kept"
  else
    actions = content.map { |f, c| { action: :create, file_path: f, content: c.delete("\r").gsub('HARBOR_FQDN', registry) } }
    p.repository.commit_files(root, branch_name: 'main', message: 'first commit', actions: actions)
    puts "  files: #{content.keys.join(' ')}"
  end
  p.change_head('main')
  ProtectedBranch.where(project: p, name: 'main').destroy_all
  ProtectedBranches::CreateService.new(p, root, name: 'main', allow_force_push: false,
    push_access_levels_attributes: [{ access_level: Gitlab::Access::DEVELOPER }],
    merge_access_levels_attributes: [{ access_level: Gitlab::Access::MAINTAINER }]).execute
end
app = Project.find_by_full_path('cicd/app')
app.update!(ci_config_path: '.gitlab-ci.yml@cicd/ci')
app.ci_cd_settings.update!(pipeline_variables_minimum_override_role: 'no_one_allowed')
Project.find_by_full_path('cicd/ci').project_feature.update!(builds_access_level: ProjectFeature::DISABLED)
puts "cicd/app builds with #{app.reload.ci_config_path}"
EOF
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor"

$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')"
if (-not $HARBOR_FQDN) {
  "FAILED: no hostname in $HARBOR_DIR\harbor-data-values.yml"
} else {
  @'
root = User.find_by_username('root')
registry = ENV.fetch('HARBOR_FQDN')
group = Group.find_by_full_path('cicd')
if group
  puts 'group cicd: kept'
else
  r = Groups::CreateService.new(root, name: 'cicd', path: 'cicd', visibility_level: Gitlab::VisibilityLevel::PUBLIC,
    organization_id: Organizations::Organization.default_organization.id).execute
  group = r.respond_to?(:payload) ? r.payload[:group] : r
  raise "group cicd: #{group.errors.full_messages.join(', ')}" unless group&.persisted?
  puts 'group cicd: created'
end
files = {
  'app' => {
    'Dockerfile' => <<~'TXT',
      FROM docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
      COPY index.html /usr/share/nginx/html/index.html
      EXPOSE 8080
    TXT
    'index.html' => <<~'TXT',
      <!doctype html>
      <html lang="en">
      <head><meta charset="utf-8"><title>test-web-apps</title></head>
      <body>
      <h1>test-web-apps v1</h1>
      </body>
      </html>
    TXT
  },
  'ci' => {
    '.gitlab-ci.yml' => <<~'TXT',
      stages: [build, writeback]

      build:
        stage: build
        tags: [vks]
        image:
          name: ghcr.io/osscontainertools/kaniko:v1.29.0-debug@sha256:350929376b8a69afb1d8b362086c809e4ef6799fa1bcb317c2806ae1447b3845
          entrypoint: [""]
        rules:
          - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
        script:
          - /kaniko/executor
            --context "$CI_PROJECT_DIR"
            --dockerfile "$CI_PROJECT_DIR/Dockerfile"
            --destination "HARBOR_FQDN/cicd-demo/test-web-apps:$CI_COMMIT_SHA"
            --registry-certificate "HARBOR_FQDN=/run/ca/ca.crt"
            --digest-file "$CI_PROJECT_DIR/digest"
        artifacts:
          paths: [digest]
          expire_in: 1 day

      writeback:
        stage: writeback
        tags: [writeback]
        image:
          name: docker.io/alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0
          entrypoint: [""]
        needs:
          - job: build
            artifacts: true
        variables:
          GIT_STRATEGY: none
        resource_group: deploy
        cache: []
        rules:
          - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
        script:
          - |
            set -eu
            D="$(tr -d ' \t\r\n' < digest)"
            if printf '%s\n' "$D" | grep -Eqx 'sha256:[0-9a-f]{64}'; then :; else echo "refused: the digest is not sha256:<64 hex>"; exit 1; fi
            IMAGE="HARBOR_FQDN/cicd-demo/test-web-apps@$D"
            export HOME=/tmp/wb
            unset GIT_CONFIG_GLOBAL
            M="$(git ls-remote --exit-code http://gitlab.gitlab.svc.cluster.local/cicd/app.git refs/heads/main)" || { echo "FAILED: cannot read cicd/app's main"; exit 1; }
            [ "${M%%[[:space:]]*}" = "$CI_COMMIT_SHA" ] || { echo "skipped: cicd/app has moved on from $CI_COMMIT_SHA"; exit 0; }
            umask 077
            mkdir -p "$HOME"
            printf 'http://writeback:%s@gitlab.gitlab.svc.cluster.local\n' "$(tr -d ' \t\r\n' < /run/deploy/token)" > "$HOME/.git-credentials"
            git -c core.hooksPath=/dev/null clone -q http://gitlab.gitlab.svc.cluster.local/cicd/deploy.git "$HOME/deploy"
            cd "$HOME/deploy"
            sed -i "s|^\( *\)image: .*|\1image: $IMAGE|" deployment.yaml
            if git diff --quiet; then echo "unchanged: deployment.yaml already uses $IMAGE"; exit 0; fi
            git -c user.name=writeback -c user.email=writeback@noreply.invalid commit -q -am "test-web-apps $CI_COMMIT_SHORT_SHA"
            git -c core.hooksPath=/dev/null -c credential.helper= -c credential.helper="store --file=$HOME/.git-credentials" push -q origin HEAD:main
            echo "wrote $IMAGE"
    TXT
  },
  'deploy' => {
    'deployment.yaml' => <<~'TXT',
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: cicd-demo
        namespace: cicd-demo
      spec:
        replicas: 2
        selector:
          matchLabels:
            app.kubernetes.io/name: cicd-demo
        template:
          metadata:
            labels:
              app.kubernetes.io/name: cicd-demo
          spec:
            automountServiceAccountToken: false
            imagePullSecrets:
              - name: harbor-pull
            securityContext:
              runAsNonRoot: true
              runAsUser: 101
              runAsGroup: 101
              seccompProfile:
                type: RuntimeDefault
            containers:
              - name: nginx
                image: docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
                ports:
                  - name: http
                    containerPort: 8080
                securityContext:
                  allowPrivilegeEscalation: false
                  readOnlyRootFilesystem: true
                  capabilities:
                    drop: ["ALL"]
                resources:
                  requests: { cpu: 50m, memory: 32Mi }
                  limits: { cpu: 250m, memory: 128Mi }
                readinessProbe:
                  httpGet: { path: /, port: http }
                volumeMounts:
                  - { name: tmp, mountPath: /tmp }
            volumes:
              - name: tmp
                emptyDir: { sizeLimit: 64Mi }
    TXT
    'service.yaml' => <<~'TXT',
      apiVersion: v1
      kind: Service
      metadata:
        name: cicd-demo
        namespace: cicd-demo
      spec:
        type: LoadBalancer
        selector:
          app.kubernetes.io/name: cicd-demo
        ports:
          - { name: http, port: 80, targetPort: http }
    TXT
  },
}
files.each do |name, content|
  p = Project.find_by_full_path("cicd/#{name}")
  if p
    puts "project cicd/#{name}: kept"
  else
    p = Projects::CreateService.new(root, name: name, path: name, namespace_id: group.id,
      visibility_level: name == 'ci' ? Gitlab::VisibilityLevel::PRIVATE : Gitlab::VisibilityLevel::PUBLIC).execute
    raise "project cicd/#{name}: #{p.errors.full_messages.join(', ')}" unless p.persisted?
    puts "project cicd/#{name}: created"
  end
  if p.repository.exists? && !p.repository.empty?
    puts "  files: kept"
  else
    actions = content.map { |f, c| { action: :create, file_path: f, content: c.delete("\r").gsub('HARBOR_FQDN', registry) } }
    p.repository.commit_files(root, branch_name: 'main', message: 'first commit', actions: actions)
    puts "  files: #{content.keys.join(' ')}"
  end
  p.change_head('main')
  ProtectedBranch.where(project: p, name: 'main').destroy_all
  ProtectedBranches::CreateService.new(p, root, name: 'main', allow_force_push: false,
    push_access_levels_attributes: [{ access_level: Gitlab::Access::DEVELOPER }],
    merge_access_levels_attributes: [{ access_level: Gitlab::Access::MAINTAINER }]).execute
end
app = Project.find_by_full_path('cicd/app')
app.update!(ci_config_path: '.gitlab-ci.yml@cicd/ci')
app.ci_cd_settings.update!(pipeline_variables_minimum_override_role: 'no_one_allowed')
Project.find_by_full_path('cicd/ci').project_feature.update!(builds_access_level: ProjectFeature::DISABLED)
puts "cicd/app builds with #{app.reload.ci_config_path}"
'@ | kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab exec -i gitlab-0 -- env HARBOR_FQDN=$HARBOR_FQDN gitlab-rails runner -
}
```

</details>

**Expect:** `group cicd: created`, `project cicd/app: created`, `files: Dockerfile index.html`,
`project cicd/ci: created`, `files: .gitlab-ci.yml`, `project cicd/deploy: created`,
`files: deployment.yaml service.yaml` and `cicd/app builds with .gitlab-ci.yml@cicd/ci`. On a
second run the group, the projects and their files say `kept`.

**If not:**
- `pods "gitlab-0" not found`: do GITLAB.md steps 1 to 4 first.
- A Ruby error such as `… (RuntimeError)`: the line names what GitLab refused; fix it in GitLab's web
  page, or delete the group `cicd` there, then run this again.

## 5. Let ArgoCD deploy it

This tells ArgoCD on the Supervisor to deploy the app from `deploy`. It creates:

- the ArgoCD project `cicd-demo`: ArgoCD may only read `deploy`, and create only the app and its
  address in the namespace `cicd-demo` of your VKS cluster;
- the Application `cicd-demo`, which applies every new commit in `deploy` to that namespace.

ArgoCD reads `deploy` through the Git server's load-balancer address. ARGOCD.md's own project and
app stay as they are.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GIT_SERVER="gitea"
DESTINATION="${VKS_CLUSTER}-${VKS_NAMESPACE}"

case "$GIT_SERVER" in
  gitea) IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea get service gitea-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
         REPO="http://${IP}:3000/gitea-admin/deploy.git" ;;
  *)     IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab get service gitlab-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
         REPO="http://${IP}/cicd/deploy.git" ;;
esac
if [ -z "$IP" ]; then
  echo "FAILED: no load-balancer address for $GIT_SERVER; do GITEA.md step 8 or GITLAB.md step 7"
else
  echo "deploy repository: $REPO"
  kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: cicd-demo
spec:
  description: cicd-demo from ${GIT_SERVER} into ${VKS_CLUSTER}
  sourceRepos:
    - ${REPO}
  destinations:
    - name: ${DESTINATION}
      namespace: cicd-demo
  clusterResourceWhitelist: []
  namespaceResourceWhitelist:
    - group: apps
      kind: Deployment
    - group: ""
      kind: Service
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cicd-demo
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: cicd-demo
  source:
    repoURL: ${REPO}
    targetRevision: main
    path: .
  destination:
    name: ${DESTINATION}
    namespace: cicd-demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GIT_SERVER = "gitea"
$DESTINATION = "${VKS_CLUSTER}-${VKS_NAMESPACE}"

if ($GIT_SERVER -eq 'gitea') {
  $IP = kubectl --kubeconfig $VKS_KUBECONFIG -n gitea get service gitea-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  $REPO = "http://${IP}:3000/gitea-admin/deploy.git"
} else {
  $IP = kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab get service gitlab-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  $REPO = "http://${IP}/cicd/deploy.git"
}
if (-not $IP) {
  "FAILED: no load-balancer address for $GIT_SERVER; do GITEA.md step 8 or GITLAB.md step 7"
} else {
  "deploy repository: $REPO"
  @"
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: cicd-demo
spec:
  description: cicd-demo from $GIT_SERVER into $VKS_CLUSTER
  sourceRepos:
    - $REPO
  destinations:
    - name: $DESTINATION
      namespace: cicd-demo
  clusterResourceWhitelist: []
  namespaceResourceWhitelist:
    - group: apps
      kind: Deployment
    - group: ""
      kind: Service
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cicd-demo
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: cicd-demo
  source:
    repoURL: $REPO
    targetRevision: main
    path: .
  destination:
    name: $DESTINATION
    namespace: cicd-demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
"@ | kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE apply -f -
}
```

</details>

**Expect:** `deploy repository: http://<address>…/deploy.git`, `appproject.argoproj.io/cicd-demo
created`, a `Warning:` about the finalizer's name (as in ARGOCD.md step 8), and
`application.argoproj.io/cicd-demo created` (`unchanged` on a second run). Within about 5 minutes,
the block below prints `Synced Healthy` and the app's page shows nginx's own welcome page.

This block checks the app. It waits up to 10 minutes for the app's page to show `WANT`, then prints
ArgoCD's status, the page, the image the app should run, and the image each pod runs. Steps 6 and 8
run it again with another `WANT`.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
WANT="Welcome to nginx"

V=""
for i in $(seq 60); do
  IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-demo get service cicd-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
  [ -n "$IP" ] && V="$(curl -s --connect-timeout 5 --max-time 10 "http://$IP/" | sed -n 's|.*<h1>\(.*\)</h1>.*|\1|p')"
  case "$V" in "$WANT"*) break ;; esac
  sleep 10
done
echo "ArgoCD: $(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get applications.argoproj.io cicd-demo -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}')"
echo "page at http://${IP:-?}/: ${V:-nothing}"
echo "image: $(kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-demo get deployment cicd-demo -o jsonpath='{.spec.template.spec.containers[0].image}')"
kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-demo get pods --no-headers -o 'custom-columns=POD:.metadata.name,IMAGE:.status.containerStatuses[0].imageID'
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$WANT = "Welcome to nginx"

$V = $null; $IP = $null
foreach ($i in 1..60) {
  $IP = kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-demo get service cicd-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
  if ($IP) {
    $H = curl.exe -s --connect-timeout 5 --max-time 10 "http://$IP/" | Out-String
    $V = if ($H -match '<h1>(.*)</h1>') { $Matches[1] } else { $null }
  }
  if ($V -and $V.StartsWith($WANT)) { break }
  Start-Sleep -Seconds 10
}
"ArgoCD: $(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get applications.argoproj.io cicd-demo -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}')"
"page at http://$(if ($IP) { $IP } else { '?' })/: $(if ($V) { $V } else { 'nothing' })"
"image: $(kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-demo get deployment cicd-demo -o jsonpath='{.spec.template.spec.containers[0].image}')"
kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-demo get pods --no-headers -o 'custom-columns=POD:.metadata.name,IMAGE:.status.containerStatuses[0].imageID'
```

</details>

**If not:** 
- `there are no clusters with this name` in ArgoCD's web page under **cicd-demo**: set
  `DESTINATION` to a name from step 1's `ArgoCD destinations:` and run this again.
- `ArgoCD: OutOfSync` or `Unknown`, with a message in ArgoCD's web page under **cicd-demo**:
  `repository not accessible` means the Supervisor cannot reach the address in `deploy
  repository:` (try it from your machine with `git ls-remote <address>`); `not permitted in project`
  means a file in `deploy` names another namespace or kind.
- `page at …: nothing` and pods `ErrImagePull`: see `kubectl --kubeconfig <the VKS kubeconfig> -n
  cicd-demo describe pods`; `unauthorized` points at `harbor-pull` (step 3), `x509` at the nodes'
  trust of Harbor ([HARBOR.md](HARBOR.md) steps 8 and 11).
- `FAILED: no load-balancer address`: do GITEA.md step 8 or GITLAB.md step 7.

## 6. Build it once

### With Gitea and Tekton

This sets up the build in `cicd-ci` and runs it once, to show that the whole chain works. The build
has two parts, each in its own pod:

- `build` gets `app` from Gitea, builds the image with Kaniko (a tool that builds images inside the
  cluster), and pushes it to Harbor with the `push` robot from step 3;
- `write-back` writes the new image's digest into `deploy` as `cicd-bot`, so ArgoCD rolls it out.

If someone pushed to `app` while the build ran, `write-back` leaves `deploy` to that newer build.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: {name: cicd-build, namespace: cicd-ci}
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: cicd-writeback, namespace: cicd-ci}
automountServiceAccountToken: false
---
apiVersion: tekton.dev/v1
kind: Task
metadata: {name: build, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, type: string}
    - {name: image, type: string}
    - {name: registry, type: string}
  results:
    - name: commit
    - name: digest
  volumes:
    - name: src
      emptyDir: {}
    - name: push
      secret: {secretName: harbor-push}
    - name: ca
      configMap: {name: harbor-ca}
  steps:
    - name: clone
      image: docker.io/alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0
      env:
        - {name: HOME, value: /tmp}
        - {name: URL, value: $(params.app-url)}
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 65532
        capabilities: {drop: ["ALL"]}
        seccompProfile: {type: RuntimeDefault}
      volumeMounts:
        - {name: src, mountPath: /src}
      script: |
        #!/bin/sh
        set -eu
        git clone -q --depth 1 "$URL" /src/app
        git -C /src/app rev-parse HEAD | tr -d '\n' > "$(results.commit.path)"
        rm -rf /src/app/.git
        echo "cloned $(cat "$(results.commit.path)")"
    - name: kaniko
      image: ghcr.io/osscontainertools/kaniko:v1.29.0-debug@sha256:350929376b8a69afb1d8b362086c809e4ef6799fa1bcb317c2806ae1447b3845
      volumeMounts:
        - {name: src, mountPath: /src}
        - {name: push, mountPath: /kaniko/.docker, readOnly: true}
        - {name: ca, mountPath: /run/ca, readOnly: true}
      env:
        - {name: REGISTRY, value: $(params.registry)}
        - {name: IMAGE, value: $(params.image)}
      script: |
        #!/busybox/sh
        set -eu
        export SSL_CERT_DIR=/kaniko/ssl/certs
        /kaniko/executor --context=/src/app --dockerfile=/src/app/Dockerfile \
          --destination="${REGISTRY}/${IMAGE}:$(cat "$(results.commit.path)")" \
          --registry-certificate="${REGISTRY}=/run/ca/ca.crt" \
          --digest-file="$(results.digest.path)"
---
apiVersion: tekton.dev/v1
kind: Task
metadata: {name: write-back, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, type: string}
    - {name: deploy-url, type: string}
    - {name: image, type: string}
    - {name: registry, type: string}
    - {name: digest, type: string}
    - {name: commit, type: string}
  volumes:
    - name: token
      secret: {secretName: git-writeback}
  stepTemplate:
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 65532
      capabilities: {drop: ["ALL"]}
      seccompProfile: {type: RuntimeDefault}
  steps:
    - name: write-back
      image: docker.io/alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0
      env:
        - {name: HOME, value: /tmp}
        - {name: GIT_CONFIG_NOSYSTEM, value: "1"}
        - {name: APP_URL, value: $(params.app-url)}
        - {name: URL, value: $(params.deploy-url)}
        - {name: IMAGE, value: $(params.registry)/$(params.image)}
        - {name: DIGEST, value: $(params.digest)}
        - {name: COMMIT, value: $(params.commit)}
      volumeMounts:
        - {name: token, mountPath: /run/git, readOnly: true}
      script: |
        #!/bin/sh
        set -eu
        DIGEST="$(printf '%s' "$DIGEST" | tr -d '[:space:]')"
        printf '%s\n' "$DIGEST" | grep -Eqx 'sha256:[0-9a-f]{64}' || { echo "refused: not a digest"; exit 1; }
        printf '%s\n' "$COMMIT" | grep -Eqx '[0-9a-f]{40}' || { echo "refused: not a commit"; exit 1; }
        M="$(git ls-remote --exit-code "$APP_URL" refs/heads/main)" || { echo "FAILED: cannot read app's main"; exit 1; }
        [ "${M%%[[:space:]]*}" = "$COMMIT" ] || { echo "skipped: app has moved on from ${COMMIT}"; exit 0; }
        H="${URL#http://}"; H="${H%%/*}"
        U="$(cat /run/git/username)"
        printf 'http://%s:%s@%s\n' "$U" "$(cat /run/git/token)" "$H" > /tmp/cred
        set -- -c core.hooksPath=/dev/null -c credential.helper= -c "credential.helper=store --file=/tmp/cred"
        git "$@" clone -q --depth 1 "$URL" /tmp/deploy
        sed -i "s|^\( *image: \).*|\1${IMAGE}@${DIGEST}|" /tmp/deploy/deployment.yaml
        if git -C /tmp/deploy diff --quiet; then echo "deploy already at ${DIGEST}"; rm -f /tmp/cred; exit 0; fi
        git -C /tmp/deploy "$@" -c user.name="$U" -c user.email="$U@localhost" commit -qam "app ${COMMIT}: ${DIGEST}"
        git -C /tmp/deploy "$@" push -q origin HEAD
        rm -f /tmp/cred
        echo "deploy now at ${IMAGE}@${DIGEST}"
---
apiVersion: tekton.dev/v1
kind: Pipeline
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, type: string}
    - {name: deploy-url, type: string}
    - {name: image, type: string}
    - {name: registry, type: string}
  tasks:
    - name: build
      taskRef: {name: build}
      params:
        - {name: app-url, value: $(params.app-url)}
        - {name: image, value: $(params.image)}
        - {name: registry, value: $(params.registry)}
    - name: write-back
      taskRef: {name: write-back}
      params:
        - {name: app-url, value: $(params.app-url)}
        - {name: deploy-url, value: $(params.deploy-url)}
        - {name: image, value: $(params.image)}
        - {name: registry, value: $(params.registry)}
        - {name: digest, value: $(tasks.build.results.digest)}
        - {name: commit, value: $(tasks.build.results.commit)}
EOF
HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null)"
if [ -z "$HARBOR_FQDN" ]; then
  echo "FAILED: no hostname in $HARBOR_DIR/harbor-data-values.yml"
elif PR="$(kubectl --kubeconfig "$VKS_KUBECONFIG" create -o name -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: cicd-demo-
  namespace: cicd-ci
spec:
  pipelineRef: {name: cicd-demo}
  params:
    - {name: app-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/app.git"}
    - {name: deploy-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/deploy.git"}
    - {name: image, value: cicd-demo/test-web-apps}
    - {name: registry, value: "${HARBOR_FQDN}"}
  taskRunSpecs:
    - {pipelineTaskName: build, serviceAccountName: cicd-build}
    - {pipelineTaskName: write-back, serviceAccountName: cicd-writeback}
EOF
)"; then
  echo "started $PR"
  for i in $(seq 90); do
    ST="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-ci get "$PR" -o jsonpath='{.status.conditions[0].status}')"
    [ "$ST" = True ] || [ "$ST" = False ] && break
    sleep 10
  done
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-ci get "$PR" -o jsonpath='{.status.conditions[0].reason}: {.status.conditions[0].message}{"\n"}'
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-ci logs -l "tekton.dev/pipelineRun=${PR#*/},tekton.dev/pipelineTask=write-back" -c step-write-back --tail=1
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor"

@'
apiVersion: v1
kind: ServiceAccount
metadata: {name: cicd-build, namespace: cicd-ci}
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: cicd-writeback, namespace: cicd-ci}
automountServiceAccountToken: false
---
apiVersion: tekton.dev/v1
kind: Task
metadata: {name: build, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, type: string}
    - {name: image, type: string}
    - {name: registry, type: string}
  results:
    - name: commit
    - name: digest
  volumes:
    - name: src
      emptyDir: {}
    - name: push
      secret: {secretName: harbor-push}
    - name: ca
      configMap: {name: harbor-ca}
  steps:
    - name: clone
      image: docker.io/alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0
      env:
        - {name: HOME, value: /tmp}
        - {name: URL, value: $(params.app-url)}
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 65532
        capabilities: {drop: ["ALL"]}
        seccompProfile: {type: RuntimeDefault}
      volumeMounts:
        - {name: src, mountPath: /src}
      script: |
        #!/bin/sh
        set -eu
        git clone -q --depth 1 "$URL" /src/app
        git -C /src/app rev-parse HEAD | tr -d '\n' > "$(results.commit.path)"
        rm -rf /src/app/.git
        echo "cloned $(cat "$(results.commit.path)")"
    - name: kaniko
      image: ghcr.io/osscontainertools/kaniko:v1.29.0-debug@sha256:350929376b8a69afb1d8b362086c809e4ef6799fa1bcb317c2806ae1447b3845
      volumeMounts:
        - {name: src, mountPath: /src}
        - {name: push, mountPath: /kaniko/.docker, readOnly: true}
        - {name: ca, mountPath: /run/ca, readOnly: true}
      env:
        - {name: REGISTRY, value: $(params.registry)}
        - {name: IMAGE, value: $(params.image)}
      script: |
        #!/busybox/sh
        set -eu
        export SSL_CERT_DIR=/kaniko/ssl/certs
        /kaniko/executor --context=/src/app --dockerfile=/src/app/Dockerfile \
          --destination="${REGISTRY}/${IMAGE}:$(cat "$(results.commit.path)")" \
          --registry-certificate="${REGISTRY}=/run/ca/ca.crt" \
          --digest-file="$(results.digest.path)"
---
apiVersion: tekton.dev/v1
kind: Task
metadata: {name: write-back, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, type: string}
    - {name: deploy-url, type: string}
    - {name: image, type: string}
    - {name: registry, type: string}
    - {name: digest, type: string}
    - {name: commit, type: string}
  volumes:
    - name: token
      secret: {secretName: git-writeback}
  stepTemplate:
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 65532
      capabilities: {drop: ["ALL"]}
      seccompProfile: {type: RuntimeDefault}
  steps:
    - name: write-back
      image: docker.io/alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0
      env:
        - {name: HOME, value: /tmp}
        - {name: GIT_CONFIG_NOSYSTEM, value: "1"}
        - {name: APP_URL, value: $(params.app-url)}
        - {name: URL, value: $(params.deploy-url)}
        - {name: IMAGE, value: $(params.registry)/$(params.image)}
        - {name: DIGEST, value: $(params.digest)}
        - {name: COMMIT, value: $(params.commit)}
      volumeMounts:
        - {name: token, mountPath: /run/git, readOnly: true}
      script: |
        #!/bin/sh
        set -eu
        DIGEST="$(printf '%s' "$DIGEST" | tr -d '[:space:]')"
        printf '%s\n' "$DIGEST" | grep -Eqx 'sha256:[0-9a-f]{64}' || { echo "refused: not a digest"; exit 1; }
        printf '%s\n' "$COMMIT" | grep -Eqx '[0-9a-f]{40}' || { echo "refused: not a commit"; exit 1; }
        M="$(git ls-remote --exit-code "$APP_URL" refs/heads/main)" || { echo "FAILED: cannot read app's main"; exit 1; }
        [ "${M%%[[:space:]]*}" = "$COMMIT" ] || { echo "skipped: app has moved on from ${COMMIT}"; exit 0; }
        H="${URL#http://}"; H="${H%%/*}"
        U="$(cat /run/git/username)"
        printf 'http://%s:%s@%s\n' "$U" "$(cat /run/git/token)" "$H" > /tmp/cred
        set -- -c core.hooksPath=/dev/null -c credential.helper= -c "credential.helper=store --file=/tmp/cred"
        git "$@" clone -q --depth 1 "$URL" /tmp/deploy
        sed -i "s|^\( *image: \).*|\1${IMAGE}@${DIGEST}|" /tmp/deploy/deployment.yaml
        if git -C /tmp/deploy diff --quiet; then echo "deploy already at ${DIGEST}"; rm -f /tmp/cred; exit 0; fi
        git -C /tmp/deploy "$@" -c user.name="$U" -c user.email="$U@localhost" commit -qam "app ${COMMIT}: ${DIGEST}"
        git -C /tmp/deploy "$@" push -q origin HEAD
        rm -f /tmp/cred
        echo "deploy now at ${IMAGE}@${DIGEST}"
---
apiVersion: tekton.dev/v1
kind: Pipeline
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, type: string}
    - {name: deploy-url, type: string}
    - {name: image, type: string}
    - {name: registry, type: string}
  tasks:
    - name: build
      taskRef: {name: build}
      params:
        - {name: app-url, value: $(params.app-url)}
        - {name: image, value: $(params.image)}
        - {name: registry, value: $(params.registry)}
    - name: write-back
      taskRef: {name: write-back}
      params:
        - {name: app-url, value: $(params.app-url)}
        - {name: deploy-url, value: $(params.deploy-url)}
        - {name: image, value: $(params.image)}
        - {name: registry, value: $(params.registry)}
        - {name: digest, value: $(tasks.build.results.digest)}
        - {name: commit, value: $(tasks.build.results.commit)}
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')"
$global:LASTEXITCODE = $null
if (-not $HARBOR_FQDN) {
  "FAILED: no hostname in $HARBOR_DIR\harbor-data-values.yml"
} else {
  $PR = @"
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: cicd-demo-
  namespace: cicd-ci
spec:
  pipelineRef: {name: cicd-demo}
  params:
    - {name: app-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/app.git"}
    - {name: deploy-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/deploy.git"}
    - {name: image, value: cicd-demo/test-web-apps}
    - {name: registry, value: "$HARBOR_FQDN"}
  taskRunSpecs:
    - {pipelineTaskName: build, serviceAccountName: cicd-build}
    - {pipelineTaskName: write-back, serviceAccountName: cicd-writeback}
"@ | kubectl --kubeconfig $VKS_KUBECONFIG create -o name -f -
  if ($LASTEXITCODE -eq 0) {
    "started $PR"
    foreach ($i in 1..90) {
      $ST = kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-ci get $PR -o jsonpath='{.status.conditions[0].status}'
      if ($ST -eq 'True' -or $ST -eq 'False') { break }
      Start-Sleep -Seconds 10
    }
    kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-ci get $PR -o jsonpath='{.status.conditions[0].reason}: {.status.conditions[0].message}'
    ""
    kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-ci logs -l "tekton.dev/pipelineRun=$($PR -replace '^.*/', ''),tekton.dev/pipelineTask=write-back" -c step-write-back --tail=1
  }
}
```

</details>

**Expect:** the `created` (or `unchanged`/`configured`) lines, `started pipelinerun.tekton.dev/cicd-demo-<x>`,
then within a few minutes `Succeeded: Tasks Completed: 2 (Failed: 0, Cancelled 0), Skipped: 0` and
`deploy now at <Harbor>/cicd-demo/test-web-apps@sha256:…`. Then run step 5's check with
`WANT="test-web-apps v1"`. A second run builds again and writes the new digest. If someone pushed to
`app` while it ran, the last line is `skipped: app has moved on …` and that push's run updates
`deploy`.

**If not:**
- `Failed: …`: `kubectl --kubeconfig <the VKS kubeconfig> -n cicd-ci logs -l
  tekton.dev/pipelineTask=build --all-containers` shows the build's log. `x509: certificate signed
  by unknown authority` on your Harbor means `harbor-ca` is missing in `cicd-ci`; on
  `index.docker.io`, the `kaniko` step lacks its `SSL_CERT_DIR` line (run this block again).
  `UNAUTHORIZED` means `harbor-push` is missing or expired (step 3); `toomanyrequests` is Docker
  Hub's pull limit (wait and run this again).
- `Failed` in `write-back` with `Authentication failed`: `git-writeback` is wrong; delete it
  (`kubectl --kubeconfig <the VKS kubeconfig> -n cicd-ci delete secret git-writeback`) and run step 4
  again.
- `FAILED: cannot read app's main`: the write-back could not reach Gitea; check that Gitea runs
  (`kubectl --kubeconfig <the VKS kubeconfig> -n gitea get pods`) and run this again.
- No `Succeeded` or `Failed` after 15 minutes: `kubectl --kubeconfig <the VKS kubeconfig> -n cicd-ci
  get pods` shows a pod `Pending` or `ImagePullBackOff`; `describe` it.

### With GitLab

This prepares GitLab's runners for the build, then runs the pipeline once:

- GITLAB.md step 8's runner also takes jobs from `cicd/app`. It is installed again so that its jobs
  get Harbor's certificate and the `push` robot from step 3.
- A second runner, `gitlab-writeback`, is the only one that may write to `deploy`. It takes only the
  write-back job, and gets a token that may push to `cicd/deploy` for 30 days.

GitLab makes the runner and the token itself; they go straight into the cluster and are never shown.
The block needs the runner chart and `runner-values.yaml` from GITLAB.md step 8. It prints each
job's result.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GITLAB_URL="http://gitlab.gitlab.svc.cluster.local"
GITLAB_DIR="$HOME/.config/vks-guides/gitlab"
CHART_SHA256="2403187ea4f50199814f22019b6a3a88b271dcfe67d26bd44c6d93b47065ffad"

CHART="$GITLAB_DIR/gitlab-runner-0.94.1.tgz"
mkdir -p "$GITLAB_DIR"
cat > "$GITLAB_DIR/cicd-build-values.yaml" <<'EOF'
runners:
  config: |
    [[runners]]
      [runners.feature_flags]
        FF_GIT_URLS_WITHOUT_TOKENS = true
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "docker.io/library/alpine:3.22.2@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412"
        helper_image = "registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.5.1@sha256:ca7cc8f66a6c6931281aa2ae974b62f80111a4f578cabc442b1d39388a0dee91"
        automount_service_account_token = false
        cpu_request = "500m"
        memory_request = "1Gi"
        memory_limit = "3Gi"
        [[runners.kubernetes.volumes.secret]]
          name = "harbor-push"
          mount_path = "/kaniko/.docker"
          read_only = true
        [[runners.kubernetes.volumes.config_map]]
          name = "harbor-ca"
          mount_path = "/run/ca"
          read_only = true
EOF
cat > "$GITLAB_DIR/cicd-writeback-values.yaml" <<'EOF'
concurrent: 1
podSecurityContext:
  runAsUser: 100
  fsGroup: 65533
  seccompProfile:
    type: RuntimeDefault
runners:
  secret: gitlab-writeback-token
  config: |
    [[runners]]
      [runners.feature_flags]
        FF_GIT_URLS_WITHOUT_TOKENS = true
      [runners.kubernetes]
        namespace = "gitlab-writeback"
        image = "docker.io/alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0"
        helper_image = "registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.5.1@sha256:ca7cc8f66a6c6931281aa2ae974b62f80111a4f578cabc442b1d39388a0dee91"
        automount_service_account_token = false
        cpu_request = "100m"
        memory_request = "128Mi"
        memory_limit = "512Mi"
        allow_privilege_escalation = false
        cap_drop = ["ALL"]
        [runners.kubernetes.pod_security_context]
          run_as_non_root = true
          run_as_user = 1000
          run_as_group = 1000
          fs_group = 1000
          [runners.kubernetes.pod_security_context.seccomp_profile]
            type = "RuntimeDefault"
        [[runners.kubernetes.volumes.secret]]
          name = "deploy-token"
          mount_path = "/run/deploy"
          read_only = true
EOF
gitlab_rails() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab exec -i gitlab-0 -- gitlab-rails runner - 2>/dev/null | tail -1 | tr -d '\r\n'; }
if [ "$( (sha256sum "$CHART" 2>/dev/null || shasum -a 256 "$CHART" 2>/dev/null) | cut -d' ' -f1)" != "$CHART_SHA256" ] || [ ! -s "$GITLAB_DIR/runner-values.yaml" ]; then
  echo "FAILED: no runner chart or runner-values.yaml in $GITLAB_DIR; do GITLAB.md step 8 first"
else
  kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: gitlab-writeback
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF
  echo "build runners for cicd/app: $(echo "app = Project.find_by_full_path('cicd/app'); root = User.find_by_username('root')
    rs = Ci::Runner.project_type.tagged_with('vks').to_a; rs.each { |r| r.assign_to(app, root) unless r.projects.include?(app) }
    puts rs.size" | gitlab_rails)"
  for T in gitlab-writeback-token deploy-token; do
    if kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-writeback get secret "$T" -o name >/dev/null 2>&1; then
      echo "kept: secret $T in gitlab-writeback"
      continue
    fi
    if [ "$T" = deploy-token ]; then
      R="deploy = Project.find_by_full_path('cicd/deploy'); root = User.find_by_username('root')
        r = ResourceAccessTokens::CreateService.new(root, deploy, name: 'writeback', scopes: [:write_repository],
          access_level: Gitlab::Access::DEVELOPER, expires_at: 30.days.from_now.to_date).execute
        print r.payload[:access_token].token"
      K=token
    else
      R="r = Ci::Runners::CreateRunnerService.new(user: User.find_by_username('root'), params: { runner_type: 'project_type',
          scope: Project.find_by_full_path('cicd/app'), tag_list: ['writeback'], run_untagged: false, locked: true,
          access_level: 'ref_protected', description: 'cicd-writeback' }).execute
        print r.payload[:runner].token"
      K=runner-token
    fi
    printf '%s' "$R" | gitlab_rails \
      | jq -R --arg n "$T" --arg k "$K" 'if test("^gl[a-z]+-[A-Za-z0-9._-]+$") then
          {apiVersion: "v1", kind: "Secret", metadata: {name: $n, namespace: "gitlab-writeback"},
           stringData: ({($k): .} + if $k == "runner-token" then {"runner-registration-token": ""} else {} end)}
          else error("GitLab did not return a token") end' \
      | kubectl --kubeconfig "$VKS_KUBECONFIG" create -f -
  done
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-writeback get secret gitlab-writeback-token deploy-token -o name >/dev/null \
    && helm upgrade --install gitlab-runner "$CHART" --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner -f "$GITLAB_DIR/runner-values.yaml" -f "$GITLAB_DIR/cicd-build-values.yaml" --set gitlabUrl="$GITLAB_URL" >/dev/null \
    && helm upgrade --install gitlab-writeback "$CHART" --kubeconfig "$VKS_KUBECONFIG" -n gitlab-writeback -f "$GITLAB_DIR/runner-values.yaml" -f "$GITLAB_DIR/cicd-writeback-values.yaml" --set gitlabUrl="$GITLAB_URL" >/dev/null \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner rollout restart deployment/gitlab-runner \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-writeback rollout restart deployment/gitlab-writeback-gitlab-runner \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner rollout status deployment/gitlab-runner --timeout=5m \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-writeback rollout status deployment/gitlab-writeback-gitlab-runner --timeout=5m \
    && sleep 30 \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab exec -i gitlab-0 -- gitlab-rails runner - 2>/dev/null <<'EOF'
app = Project.find_by_full_path('cicd/app')
pl = Ci::CreatePipelineService.new(app, User.find_by_username('root'), ref: 'main').execute(:web).payload
puts "pipeline #{pl.id}: started"
t = Time.now
sleep 5 until pl.reload.complete? || Time.now - t > 900
puts "pipeline #{pl.id}: #{pl.status}"
pl.builds.sort_by(&:id).each do |b|
  l = b.trace.raw.to_s.gsub(/\e\[[0-9;]*[A-Za-z]/, '').lines.grep(/Pushed |wrote |unchanged:|refused:|skipped:|FAILED:|fatal:|ERROR/).last.to_s
  puts "#{b.name}: #{b.status} #{l[/(Pushed|wrote|unchanged:|refused:|skipped:|FAILED:|fatal:|ERROR).*/]}"
end
EOF
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GITLAB_URL = "http://gitlab.gitlab.svc.cluster.local"
$GITLAB_DIR = "$HOME\.config\vks-guides\gitlab"
$CHART_SHA256 = "2403187ea4f50199814f22019b6a3a88b271dcfe67d26bd44c6d93b47065ffad"

$CHART = "$GITLAB_DIR\gitlab-runner-0.94.1.tgz"
New-Item -ItemType Directory -Force -Path $GITLAB_DIR | Out-Null
$BV = @'
runners:
  config: |
    [[runners]]
      [runners.feature_flags]
        FF_GIT_URLS_WITHOUT_TOKENS = true
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "docker.io/library/alpine:3.22.2@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412"
        helper_image = "registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.5.1@sha256:ca7cc8f66a6c6931281aa2ae974b62f80111a4f578cabc442b1d39388a0dee91"
        automount_service_account_token = false
        cpu_request = "500m"
        memory_request = "1Gi"
        memory_limit = "3Gi"
        [[runners.kubernetes.volumes.secret]]
          name = "harbor-push"
          mount_path = "/kaniko/.docker"
          read_only = true
        [[runners.kubernetes.volumes.config_map]]
          name = "harbor-ca"
          mount_path = "/run/ca"
          read_only = true
'@
$WV = @'
concurrent: 1
podSecurityContext:
  runAsUser: 100
  fsGroup: 65533
  seccompProfile:
    type: RuntimeDefault
runners:
  secret: gitlab-writeback-token
  config: |
    [[runners]]
      [runners.feature_flags]
        FF_GIT_URLS_WITHOUT_TOKENS = true
      [runners.kubernetes]
        namespace = "gitlab-writeback"
        image = "docker.io/alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0"
        helper_image = "registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.5.1@sha256:ca7cc8f66a6c6931281aa2ae974b62f80111a4f578cabc442b1d39388a0dee91"
        automount_service_account_token = false
        cpu_request = "100m"
        memory_request = "128Mi"
        memory_limit = "512Mi"
        allow_privilege_escalation = false
        cap_drop = ["ALL"]
        [runners.kubernetes.pod_security_context]
          run_as_non_root = true
          run_as_user = 1000
          run_as_group = 1000
          fs_group = 1000
          [runners.kubernetes.pod_security_context.seccomp_profile]
            type = "RuntimeDefault"
        [[runners.kubernetes.volumes.secret]]
          name = "deploy-token"
          mount_path = "/run/deploy"
          read_only = true
'@
[IO.File]::WriteAllText("$GITLAB_DIR\cicd-build-values.yaml", ($BV -replace "`r`n", "`n") + "`n")
[IO.File]::WriteAllText("$GITLAB_DIR\cicd-writeback-values.yaml", ($WV -replace "`r`n", "`n") + "`n")
function Invoke-GitLabRails($Ruby) { ($Ruby | kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab exec -i gitlab-0 -- gitlab-rails runner - 2>$null | Select-Object -Last 1 | Out-String).Trim() }
if (-not (Test-Path $CHART) -or (Get-FileHash -Algorithm SHA256 $CHART).Hash -ne $CHART_SHA256 -or -not (Test-Path "$GITLAB_DIR\runner-values.yaml") -or (Get-Item "$GITLAB_DIR\runner-values.yaml").Length -eq 0) {
  "FAILED: no runner chart or runner-values.yaml in $GITLAB_DIR; do GITLAB.md step 8 first"
} else {
  "apiVersion: v1`nkind: Namespace`nmetadata:`n  name: gitlab-writeback`n  labels:`n    pod-security.kubernetes.io/enforce: restricted`n    pod-security.kubernetes.io/audit: restricted`n    pod-security.kubernetes.io/warn: restricted`n" |
    kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
  "build runners for cicd/app: $(Invoke-GitLabRails "app = Project.find_by_full_path('cicd/app'); root = User.find_by_username('root')`nrs = Ci::Runner.project_type.tagged_with('vks').to_a; rs.each { |r| r.assign_to(app, root) unless r.projects.include?(app) }`nputs rs.size")"
  foreach ($T in 'gitlab-writeback-token', 'deploy-token') {
    $global:LASTEXITCODE = $null
    kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-writeback get secret $T -o name 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { "kept: secret $T in gitlab-writeback"; continue }
    if ($T -eq 'deploy-token') {
      $V = Invoke-GitLabRails "deploy = Project.find_by_full_path('cicd/deploy'); root = User.find_by_username('root')`nr = ResourceAccessTokens::CreateService.new(root, deploy, name: 'writeback', scopes: [:write_repository], access_level: Gitlab::Access::DEVELOPER, expires_at: 30.days.from_now.to_date).execute`nprint r.payload[:access_token].token"
      $D = "  token: $V"
    } else {
      $V = Invoke-GitLabRails "r = Ci::Runners::CreateRunnerService.new(user: User.find_by_username('root'), params: { runner_type: 'project_type', scope: Project.find_by_full_path('cicd/app'), tag_list: ['writeback'], run_untagged: false, locked: true, access_level: 'ref_protected', description: 'cicd-writeback' }).execute`nprint r.payload[:runner].token"
      $D = "  runner-token: $V`n  runner-registration-token: `"`""
    }
    if ($V -cmatch '^gl[a-z]+-[A-Za-z0-9._-]+$') {
      "apiVersion: v1`nkind: Secret`nmetadata:`n  name: $T`n  namespace: gitlab-writeback`nstringData:`n$D`n" | kubectl --kubeconfig $VKS_KUBECONFIG create -f -
    } else {
      "FAILED: GitLab did not return a token for $T"
    }
    Remove-Variable V, D
  }
  kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-writeback get secret gitlab-writeback-token deploy-token -o name | Out-Null
  if ($LASTEXITCODE -eq 0) { helm upgrade --install gitlab-runner $CHART --kubeconfig $VKS_KUBECONFIG -n gitlab-runner -f "$GITLAB_DIR\runner-values.yaml" -f "$GITLAB_DIR\cicd-build-values.yaml" --set gitlabUrl=$GITLAB_URL | Out-Null }
  if ($LASTEXITCODE -eq 0) { helm upgrade --install gitlab-writeback $CHART --kubeconfig $VKS_KUBECONFIG -n gitlab-writeback -f "$GITLAB_DIR\runner-values.yaml" -f "$GITLAB_DIR\cicd-writeback-values.yaml" --set gitlabUrl=$GITLAB_URL | Out-Null }
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-runner rollout restart deployment/gitlab-runner }
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-writeback rollout restart deployment/gitlab-writeback-gitlab-runner }
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-runner rollout status deployment/gitlab-runner --timeout=5m }
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-writeback rollout status deployment/gitlab-writeback-gitlab-runner --timeout=5m }
  if ($LASTEXITCODE -eq 0) {
    Start-Sleep -Seconds 30
    @'
app = Project.find_by_full_path('cicd/app')
pl = Ci::CreatePipelineService.new(app, User.find_by_username('root'), ref: 'main').execute(:web).payload
puts "pipeline #{pl.id}: started"
t = Time.now
sleep 5 until pl.reload.complete? || Time.now - t > 900
puts "pipeline #{pl.id}: #{pl.status}"
pl.builds.sort_by(&:id).each do |b|
  l = b.trace.raw.to_s.gsub(/\e\[[0-9;]*[A-Za-z]/, '').lines.grep(/Pushed |wrote |unchanged:|refused:|skipped:|FAILED:|fatal:|ERROR/).last.to_s
  puts "#{b.name}: #{b.status} #{l[/(Pushed|wrote|unchanged:|refused:|skipped:|FAILED:|fatal:|ERROR).*/]}"
end
'@ | kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab exec -i gitlab-0 -- gitlab-rails runner - 2>$null
  }
}
```

</details>

**Expect:** `namespace/gitlab-writeback created`, `build runners for cicd/app: 1`,
`secret/gitlab-writeback-token created`, `secret/deploy-token created`, the two `restarted` and
`successfully rolled out` lines, then `pipeline <n>: started`, `pipeline <n>: success`,
`build: success Pushed <Harbor>/cicd-demo/test-web-apps@sha256:…` and
`writeback: success wrote <Harbor>/cicd-demo/test-web-apps@sha256:…`, the same digest. On a second
run: `kept: secret …` and `writeback: success unchanged: …` or a new digest.

Then run step 5's check with `WANT="test-web-apps v1"`.

**If not:**
- `FAILED: no runner chart or runner-values.yaml …`: run this on the machine where you did
  GITLAB.md step 8, or do that step here.
- `build runners for cicd/app: 0`: no runner has the tag `vks`; do GITLAB.md step 8.
- `build: failed`: `http://localhost:3400/cicd/app/-/jobs` shows the log. `waiting for pod running:
  timed out` means `harbor-push` or `harbor-ca` is missing in `gitlab-runner` (step 3 with
  `GIT_SERVER="gitlab"`); `UNAUTHORIZED` means the push robot expired (step 3).
- `writeback: success skipped: cicd/app has moved on …`: someone pushed meanwhile; that push's
  pipeline updates `deploy`. `writeback: failed FAILED: cannot read cicd/app's main`: the job could
  not reach GitLab; run this again.
- `secrets "deploy-token" not found` (or `gitlab-writeback-token`) and nothing after it: GitLab did
  not return a token; the line before says why. Run this again.
- `writeback: failed` with `not allowed to push`: `deploy-token` expired (30 days). Delete it
  (`kubectl --kubeconfig <the VKS kubeconfig> -n gitlab-writeback delete secret deploy-token`) and
  run this again.
- `pipeline <n>: pending` or `created` after 15 minutes: a runner is offline; see GITLAB.md step 8.

## 7. Build on every push

### With Gitea and Tekton

This makes every push to `app` start a build. It creates:

- in `cicd-ci`, a listener that starts the build when Gitea reports a push to `main`;
- a random shared secret in the Secret `cicd-webhook`; the listener ignores messages not signed
  with it;
- a rule that lets only Gitea reach the listener;
- in Gitea, a webhook on `app` that calls the listener on every push.

Run it in the terminal where you typed the Gitea password in step 4 (or type it again with the
first block there).

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GITEA_URL="http://localhost:3300"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"

HOOK="http://el-cicd-demo.cicd-ci.svc.cluster.local:8080"
HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null)"
kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: {name: cicd-listener, namespace: cicd-ci}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: cicd-listener, namespace: cicd-ci}
subjects: [{kind: ServiceAccount, name: cicd-listener, namespace: cicd-ci}]
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: tekton-triggers-eventlistener-roles}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: cicd-listener}
rules:
  - apiGroups: ["triggers.tekton.dev"]
    resources: ["clusterinterceptors", "clustertriggerbindings"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: cicd-listener}
subjects: [{kind: ServiceAccount, name: cicd-listener, namespace: cicd-ci}]
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cicd-listener}
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  params:
    - name: app-url
    - name: deploy-url
    - name: image
    - name: registry
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata: {generateName: cicd-demo-}
      spec:
        pipelineRef: {name: cicd-demo}
        params:
          - {name: app-url, value: $(tt.params.app-url)}
          - {name: deploy-url, value: $(tt.params.deploy-url)}
          - {name: image, value: $(tt.params.image)}
          - {name: registry, value: $(tt.params.registry)}
        taskRunSpecs:
          - {pipelineTaskName: build, serviceAccountName: cicd-build}
          - {pipelineTaskName: write-back, serviceAccountName: cicd-writeback}
---
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  serviceAccountName: cicd-listener
  triggers:
    - name: push-to-main
      interceptors:
        - ref: {name: github, kind: ClusterInterceptor}
          params:
            - name: secretRef
              value: {secretName: cicd-webhook, secretKey: token}
            - name: eventTypes
              value: ["push"]
        - ref: {name: cel, kind: ClusterInterceptor}
          params:
            - name: filter
              value: body.ref == 'refs/heads/main'
      bindings: [{ref: cicd-demo}]
      template: {ref: cicd-demo}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: cicd-listener, namespace: cicd-ci}
spec:
  podSelector: {matchLabels: {eventlistener: cicd-demo}}
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: gitea}}
EOF
[ -n "$HARBOR_FQDN" ] || echo "FAILED: no hostname in $HARBOR_DIR/harbor-data-values.yml"
[ -n "$HARBOR_FQDN" ] && kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<EOF
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/app.git"}
    - {name: deploy-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/deploy.git"}
    - {name: image, value: cicd-demo/test-web-apps}
    - {name: registry, value: "${HARBOR_FQDN}"}
EOF
if ! kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-ci get secret cicd-webhook -o name >/dev/null 2>&1; then
  openssl rand -hex 20 | tr -d '\n' \
    | jq -R '{apiVersion: "v1", kind: "Secret", metadata: {name: "cicd-webhook", namespace: "cicd-ci"}, stringData: {token: .}}' \
    | kubectl --kubeconfig "$VKS_KUBECONFIG" create -f -
fi
if [ -z "$GITEA_PASSWORD" ]; then
  echo "FAILED: no Gitea password in this terminal; type it (step 4), then run this again"
else
  CFG="$(mktemp)"
  P="$(printf '%s' "$GITEA_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf 'user = "gitea-admin:%s"\n' "$P" > "$CFG"
  P=""
  api() { curl -sS --connect-timeout 20 --max-time 30 -K "$CFG" -H 'Content-Type: application/json' "$@"; }
  for ID in $(api "$GITEA_URL/api/v1/repos/gitea-admin/app/hooks" | jq -r --arg u "$HOOK" '.[]? | select(.config.url == $u) | .id'); do
    api -o /dev/null -X DELETE "$GITEA_URL/api/v1/repos/gitea-admin/app/hooks/$ID" && echo "replaced webhook $ID"
  done
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-ci get secret cicd-webhook -o jsonpath='{.data.token}' | openssl base64 -d -A \
    | jq -R --arg u "$HOOK" '{type: "gitea", active: true, events: ["push"], branch_filter: "main",
                             config: {url: $u, content_type: "json", secret: .}}' \
    | api -o /dev/null -w 'webhook: %{http_code}\n' -X POST --data-binary @- "$GITEA_URL/api/v1/repos/gitea-admin/app/hooks"
  rm -f "$CFG"
fi
kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-ci wait --for=condition=Ready eventlistener/cicd-demo --timeout=5m
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GITEA_URL = "http://localhost:3300"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor"

$HOOK = "http://el-cicd-demo.cicd-ci.svc.cluster.local:8080"
$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')"
@'
apiVersion: v1
kind: ServiceAccount
metadata: {name: cicd-listener, namespace: cicd-ci}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: cicd-listener, namespace: cicd-ci}
subjects: [{kind: ServiceAccount, name: cicd-listener, namespace: cicd-ci}]
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: tekton-triggers-eventlistener-roles}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: cicd-listener}
rules:
  - apiGroups: ["triggers.tekton.dev"]
    resources: ["clusterinterceptors", "clustertriggerbindings"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: cicd-listener}
subjects: [{kind: ServiceAccount, name: cicd-listener, namespace: cicd-ci}]
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cicd-listener}
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  params:
    - name: app-url
    - name: deploy-url
    - name: image
    - name: registry
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata: {generateName: cicd-demo-}
      spec:
        pipelineRef: {name: cicd-demo}
        params:
          - {name: app-url, value: $(tt.params.app-url)}
          - {name: deploy-url, value: $(tt.params.deploy-url)}
          - {name: image, value: $(tt.params.image)}
          - {name: registry, value: $(tt.params.registry)}
        taskRunSpecs:
          - {pipelineTaskName: build, serviceAccountName: cicd-build}
          - {pipelineTaskName: write-back, serviceAccountName: cicd-writeback}
---
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  serviceAccountName: cicd-listener
  triggers:
    - name: push-to-main
      interceptors:
        - ref: {name: github, kind: ClusterInterceptor}
          params:
            - name: secretRef
              value: {secretName: cicd-webhook, secretKey: token}
            - name: eventTypes
              value: ["push"]
        - ref: {name: cel, kind: ClusterInterceptor}
          params:
            - name: filter
              value: body.ref == 'refs/heads/main'
      bindings: [{ref: cicd-demo}]
      template: {ref: cicd-demo}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: cicd-listener, namespace: cicd-ci}
spec:
  podSelector: {matchLabels: {eventlistener: cicd-demo}}
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: gitea}}
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
if (-not $HARBOR_FQDN) { "FAILED: no hostname in $HARBOR_DIR\harbor-data-values.yml" } else { @"
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/app.git"}
    - {name: deploy-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/deploy.git"}
    - {name: image, value: cicd-demo/test-web-apps}
    - {name: registry, value: "$HARBOR_FQDN"}
"@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f - }
$global:LASTEXITCODE = $null
kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-ci get secret cicd-webhook -o name 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  $B = New-Object byte[] 20
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($B)
  "apiVersion: v1`nkind: Secret`nmetadata:`n  name: cicd-webhook`n  namespace: cicd-ci`nstringData:`n  token: $(-join ($B | ForEach-Object { $_.ToString('x2') }))`n" |
    kubectl --kubeconfig $VKS_KUBECONFIG create -f -
  Remove-Variable B
}
if (-not $GITEA_PASSWORD) {
  "FAILED: no Gitea password in this terminal; type it (step 4), then run this again"
} else {
  $P = [Net.NetworkCredential]::new('', $GITEA_PASSWORD).Password.Replace('\', '\\').Replace('"', '\"')
  $CFG = [IO.Path]::GetTempFileName(); $BODY = [IO.Path]::GetTempFileName()
  try {
    [IO.File]::WriteAllText($CFG, "user = `"gitea-admin:$P`"`n", (New-Object Text.UTF8Encoding $false))
    Remove-Variable P
    $H = curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG "$GITEA_URL/api/v1/repos/gitea-admin/app/hooks" | Out-String | ConvertFrom-Json
    foreach ($ID in @($H | Where-Object { $_.config.url -ceq $HOOK } | ForEach-Object { $_.id })) {
      curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -X DELETE "$GITEA_URL/api/v1/repos/gitea-admin/app/hooks/$ID"
      "replaced webhook $ID"
    }
    $W = [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String((kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-ci get secret cicd-webhook -o jsonpath='{.data.token}')))
    Set-Content -Encoding ascii -Path $BODY -Value ('{"type":"gitea","active":true,"events":["push"],"branch_filter":"main","config":{"url":"' + $HOOK + '","content_type":"json","secret":"' + $W + '"}}')
    Remove-Variable W
    "webhook: $(curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary "@$BODY" "$GITEA_URL/api/v1/repos/gitea-admin/app/hooks")"
  } finally {
    Remove-Item -Force $CFG, $BODY
  }
}
kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-ci wait --for=condition=Ready eventlistener/cicd-demo --timeout=5m
```

</details>

**Expect:** the `created` (or `unchanged`) lines, `secret/cicd-webhook created` (nothing on a second
run), `webhook: 201` (after `replaced webhook <n>` on a second run) and
`eventlistener.triggers.tekton.dev/cicd-demo condition met`.

**If not:**
- After step 8's push, no new PipelineRun, and Gitea's log
  (`kubectl --kubeconfig <the VKS kubeconfig> -n gitea logs deployment/gitea`) says `denied by
  egress policy`: your Gitea predates GITEA.md's webhook setting; run GITEA.md step 4 again (it
  reads the cluster's Service range).
- `FAILED: no Gitea password …`: type it with step 4's first block, then run this again.
- `Failed to connect to localhost port 3300`: the port-forward stopped (its terminal says `lost
  connection to pod`; it can drop while idle). Start GITEA.md step 6 again, then run this again.

### With GitLab

Nothing to do: GitLab starts the pipeline on every push to `main` of `cicd/app`.

## 8. Change the page

This changes the app's page from v1 to v2 and pushes it, to show the chain working on its own. It
keeps a copy of `app` in `~/.config/vks-guides/cicd/app-gitea` (or `app-gitlab`). The push starts a
build, the build writes the new image into `deploy`, and ArgoCD rolls it out. Git asks for
`gitea-admin`'s password (with GitLab, `root`'s).

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
GIT_SERVER="gitea"
APP_DIR="$HOME/.config/vks-guides/cicd/app-$GIT_SERVER"
EMAIL="you@example.com"

case "$GIT_SERVER" in
  gitea) URL="http://gitea-admin@localhost:3300/gitea-admin/app.git" ;;
  *)     URL="http://root@localhost:3400/cicd/app.git" ;;
esac
if [ -d "$APP_DIR/.git" ] || git clone -q "$URL" "$APP_DIR"; then
  git -C "$APP_DIR" -c credential.helper= pull -q --ff-only "$URL" main
  sed 's/test-web-apps v[0-9]*/test-web-apps v2/' "$APP_DIR/index.html" > "$APP_DIR/index.html.new" \
    && mv "$APP_DIR/index.html.new" "$APP_DIR/index.html"
  git -C "$APP_DIR" diff --quiet \
    || git -C "$APP_DIR" -c user.name=cicd -c user.email="$EMAIL" -c commit.gpgsign=false commit -qam "page v2"
  git -C "$APP_DIR" -c credential.helper= push "$URL" HEAD:main
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$GIT_SERVER = "gitea"
$APP_DIR = "$HOME\.config\vks-guides\cicd\app-$GIT_SERVER"
$EMAIL = "you@example.com"

$URL = if ($GIT_SERVER -eq 'gitea') { "http://gitea-admin@localhost:3300/gitea-admin/app.git" } else { "http://root@localhost:3400/cicd/app.git" }
$global:LASTEXITCODE = 0
if (-not (Test-Path "$APP_DIR\.git")) { git clone -q $URL $APP_DIR }
if ($LASTEXITCODE -eq 0) {
  git -C $APP_DIR -c credential.helper= pull -q --ff-only $URL main
  $H = [IO.File]::ReadAllText("$APP_DIR\index.html") -replace 'test-web-apps v[0-9]*', 'test-web-apps v2'
  [IO.File]::WriteAllText("$APP_DIR\index.html", $H)
  git -C $APP_DIR diff --quiet
  if ($LASTEXITCODE -ne 0) { git -C $APP_DIR -c user.name=cicd -c user.email=$EMAIL -c commit.gpgsign=false commit -qam "page v2" }
  git -C $APP_DIR -c credential.helper= push $URL HEAD:main
}
```

</details>

**Expect:** after the password, `<old>..<new>  HEAD -> main`. With Gitea, within a minute
`kubectl --kubeconfig <the VKS kubeconfig> -n cicd-ci get pipelineruns` lists a new run that turns
`Succeeded`; with GitLab, `http://localhost:3400/cicd/app/-/pipelines` shows a new pipeline that
turns **Passed**. Then run step 5's check with `WANT="test-web-apps v2"`: within about 10 minutes
the page says `test-web-apps v2`, `image:` ends in a new `@sha256:…`, and every pod's image ID ends
in that digest.

**If not:**
- `Failed to connect to localhost port 3300` (or `3400`): the port-forward stopped; start GITEA.md
  step 6 (or GITLAB.md step 5) again, then run this again.
- `Everything up-to-date`: the page already said v2; change `v2` to `v3` in the block and run it
  again.
- With Gitea, no new PipelineRun: see step 7's **If not**.
- The page still shows v1 but `image:` ends in the new digest: the new pods are still starting;
  run step 5's check again.
- The page still shows v1 after 10 minutes but the run succeeded: in ArgoCD's web page, open
  **cicd-demo** and click **Refresh** → **Hard Refresh**; ArgoCD checks `deploy` only every few
  minutes.
- `Not possible to fast-forward`: the repository was made again; delete
  `~/.config/vks-guides/cicd/app-gitea` (or `app-gitlab`) and run this again.

## 9. Clean up (optional)

This removes what this guide made: the Application (ArgoCD deletes the app with it) and its
project, the namespaces, the Harbor project with its robots and images, and the repositories. The
Git server, Tekton or the runner from the other guides stay. With Gitea, run it in the terminal
where you typed the Gitea password in step 4.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GIT_SERVER="gitea"
HARBOR_PROJECT="cicd-demo"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"
GITEA_URL="http://localhost:3300"

if ! kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete applications.argoproj.io cicd-demo --ignore-not-found --timeout=5m; then
  echo "FAILED: the Application is still there; nothing else deleted"
else
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete appprojects.argoproj.io cicd-demo --ignore-not-found
kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace cicd-demo --ignore-not-found --timeout=10m
rm -rf "$HOME/.config/vks-guides/cicd/app-$GIT_SERVER"
case "$GIT_SERVER" in
  gitea)
    kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace cicd-ci --ignore-not-found --timeout=10m
    kubectl --kubeconfig "$VKS_KUBECONFIG" delete clusterrolebinding,clusterrole cicd-listener --ignore-not-found
    if [ -z "$GITEA_PASSWORD" ]; then
      echo "skipped: Gitea repositories (no Gitea password in this terminal; type it with step 4's first block)"
    else
      CFG="$(mktemp)"
      P="$(printf '%s' "$GITEA_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      printf 'user = "gitea-admin:%s"\n' "$P" > "$CFG"
      P=""
      for R in app deploy; do
        curl -sS --connect-timeout 20 --max-time 30 -K "$CFG" -o /dev/null -w "repository $R: %{http_code}\n" \
          -X DELETE "$GITEA_URL/api/v1/repos/gitea-admin/$R"
      done
      rm -f "$CFG"
    fi
    kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- gitea admin user delete --username cicd-bot --purge 2>/dev/null \
      && echo "user cicd-bot: deleted"
    ;;
  *)
    helm uninstall gitlab-writeback --kubeconfig "$VKS_KUBECONFIG" -n gitlab-writeback 2>/dev/null
    kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace gitlab-writeback --ignore-not-found --timeout=10m
    if [ -s "$HOME/.config/vks-guides/gitlab/runner-values.yaml" ] && [ -s "$HOME/.config/vks-guides/gitlab/gitlab-runner-0.94.1.tgz" ] \
       && helm upgrade gitlab-runner "$HOME/.config/vks-guides/gitlab/gitlab-runner-0.94.1.tgz" --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner \
          -f "$HOME/.config/vks-guides/gitlab/runner-values.yaml" --reuse-values >/dev/null; then
      echo "runner gitlab-runner: back to GITLAB.md step 8's settings"
      kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner delete secret harbor-push --ignore-not-found
      kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner delete configmap harbor-ca --ignore-not-found
    else
      echo "FAILED: could not put the runner back (needs runner-values.yaml and the chart from GITLAB.md step 8); harbor-push and harbor-ca kept"
    fi
    printf '%s\n' "Ci::Runner.where(description: 'cicd-writeback').each(&:destroy)" \
      "g = Group.find_by_full_path('cicd'); puts(g ? (Groups::DestroyService.new(g, User.find_by_username('root')).execute && 'group cicd: deleted') : 'group cicd: none')" \
      | kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab exec -i gitlab-0 -- gitlab-rails runner - 2>&1 | grep -v '^\s*from '

    ;;
esac
HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null)"
if [ -z "$HARBOR_FQDN" ] || [ ! -s "$HARBOR_DIR/harbor-ca.crt" ] || [ ! -r "$HARBOR_DIR/secrets.env" ]; then
  echo "skipped: Harbor (harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR)"
else
  CFG="$(mktemp)"
  ( . "$HARBOR_DIR/secrets.env"
    P="$(printf '%s' "$HARBOR_ADMIN_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf 'user = "admin:%s"\n' "$P" > "$CFG" )
  for U in "projects/$HARBOR_PROJECT/repositories/test-web-apps" "projects/$HARBOR_PROJECT"; do
    curl -sS --cacert "$HARBOR_DIR/harbor-ca.crt" --connect-timeout 20 --max-time 30 -K "$CFG" -o /dev/null \
      -w "Harbor ${U#projects/}: %{http_code}\n" -X DELETE "https://${HARBOR_FQDN}/api/v2.0/$U"
  done
  rm -f "$CFG"
fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GIT_SERVER = "gitea"
$HARBOR_PROJECT = "cicd-demo"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor"
$GITEA_URL = "http://localhost:3300"

$global:LASTEXITCODE = $null
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete applications.argoproj.io cicd-demo --ignore-not-found --timeout=5m
if ($LASTEXITCODE -ne 0) {
  "FAILED: the Application is still there; nothing else deleted"
} else {
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete appprojects.argoproj.io cicd-demo --ignore-not-found
kubectl --kubeconfig $VKS_KUBECONFIG delete namespace cicd-demo --ignore-not-found --timeout=10m
Remove-Item -Recurse -Force "$HOME\.config\vks-guides\cicd\app-$GIT_SERVER" -ErrorAction SilentlyContinue
if ($GIT_SERVER -eq 'gitea') {
  kubectl --kubeconfig $VKS_KUBECONFIG delete namespace cicd-ci --ignore-not-found --timeout=10m
  kubectl --kubeconfig $VKS_KUBECONFIG delete clusterrolebinding,clusterrole cicd-listener --ignore-not-found
  if (-not $GITEA_PASSWORD) {
    "skipped: Gitea repositories (no Gitea password in this terminal; type it with step 4's first block)"
  } else {
    $P = [Net.NetworkCredential]::new('', $GITEA_PASSWORD).Password.Replace('\', '\\').Replace('"', '\"')
    $CFG = [IO.Path]::GetTempFileName()
    try {
      [IO.File]::WriteAllText($CFG, "user = `"gitea-admin:$P`"`n", (New-Object Text.UTF8Encoding $false))
      Remove-Variable P
      foreach ($R in 'app', 'deploy') {
        "repository ${R}: $(curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' -X DELETE "$GITEA_URL/api/v1/repos/gitea-admin/$R")"
      }
    } finally {
      Remove-Item -Force $CFG
    }
  }
  kubectl --kubeconfig $VKS_KUBECONFIG -n gitea exec deployment/gitea -- gitea admin user delete --username cicd-bot --purge 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { "user cicd-bot: deleted" }
} else {
  helm uninstall gitlab-writeback --kubeconfig $VKS_KUBECONFIG -n gitlab-writeback 2>$null
  kubectl --kubeconfig $VKS_KUBECONFIG delete namespace gitlab-writeback --ignore-not-found --timeout=10m
  if ((Test-Path "$HOME\.config\vks-guides\gitlab\runner-values.yaml") -and (Test-Path "$HOME\.config\vks-guides\gitlab\gitlab-runner-0.94.1.tgz")) {
    helm upgrade gitlab-runner "$HOME\.config\vks-guides\gitlab\gitlab-runner-0.94.1.tgz" --kubeconfig $VKS_KUBECONFIG -n gitlab-runner `
      -f "$HOME\.config\vks-guides\gitlab\runner-values.yaml" --reuse-values | Out-Null
  } else { $global:LASTEXITCODE = 1 }
  if ($LASTEXITCODE -eq 0) {
    "runner gitlab-runner: back to GITLAB.md step 8's settings"
    kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-runner delete secret harbor-push --ignore-not-found
    kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-runner delete configmap harbor-ca --ignore-not-found
  } else {
    "FAILED: could not put the runner back (needs runner-values.yaml and the chart from GITLAB.md step 8); harbor-push and harbor-ca kept"
  }
  "Ci::Runner.where(description: 'cicd-writeback').each(&:destroy)`ng = Group.find_by_full_path('cicd'); puts(g ? (Groups::DestroyService.new(g, User.find_by_username('root')).execute && 'group cicd: deleted') : 'group cicd: none')" |
    kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab exec -i gitlab-0 -- gitlab-rails runner - 2>&1 | Where-Object { "$_" -notmatch '^\s*from ' }
}
$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')"
$S = @{}
foreach ($l in Get-Content "$HARBOR_DIR\secrets.env" -ErrorAction SilentlyContinue) { if ($l -cmatch "^(HARBOR_[A-Z_]+)='(.*)'$") { $S[$Matches[1]] = $Matches[2] } }
if (-not $HARBOR_FQDN -or -not (Test-Path "$HARBOR_DIR\harbor-ca.crt") -or -not $S['HARBOR_ADMIN_PASSWORD']) {
  "skipped: Harbor (harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR)"
} else {
  $P = $S['HARBOR_ADMIN_PASSWORD'].Replace('\', '\\').Replace('"', '\"')
  $CFG = [IO.Path]::GetTempFileName()
  try {
    Set-Content -Encoding ascii -Path $CFG -Value "user = `"admin:$P`""
    foreach ($U in "projects/$HARBOR_PROJECT/repositories/test-web-apps", "projects/$HARBOR_PROJECT") {
      "Harbor $($U -replace '^projects/', ''): $(curl.exe -sS --ssl-no-revoke --cacert "$HARBOR_DIR\harbor-ca.crt" --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' -X DELETE "https://$HARBOR_FQDN/api/v2.0/$U")"
    }
  } finally {
    Remove-Item -Force $CFG
    Remove-Variable P, S
  }
}
}
```

</details>

**Expect:** `application.argoproj.io "cicd-demo" deleted`, `appproject.argoproj.io "cicd-demo"
deleted`, `namespace "cicd-demo" deleted`, then with Gitea `namespace "cicd-ci" deleted`,
`repository app: 204`, `repository deploy: 204` and `user cicd-bot: deleted`, or with GitLab
`release "gitlab-writeback" uninstalled`, `namespace "gitlab-writeback" deleted`, `runner
gitlab-runner: back to GITLAB.md step 8's settings`, the `harbor-push` and `harbor-ca` deletes and
`group cicd: deleted`; and last
`Harbor cicd-demo/repositories/test-web-apps: 200` and `Harbor cicd-demo: 200`. On a second run:
with Gitea `repository app: 404` and `repository deploy: 404`; with GitLab `runner gitlab-runner:
back to …` and `group cicd: none`; Harbor `404`.

**If not:**
- `FAILED: could not put the runner back`: do GITLAB.md step 8 again, then delete `harbor-push` and
  `harbor-ca` in `gitlab-runner` (`kubectl --kubeconfig <the VKS kubeconfig> -n gitlab-runner delete
  secret harbor-push` and `… delete configmap harbor-ca`); step 3 would otherwise keep the expired
  robot.
- `FAILED: the Application is still there` after `timed out waiting for the condition`: ArgoCD
  cannot reach the cluster or cannot delete the app. See [ARGOCD.md](ARGOCD.md) step 9's **If not**,
  then run this again.
- `Harbor cicd-demo: 412`: the project still holds something; delete it in Harbor's web page
  (**Projects** → `cicd-demo`), then run this again.

The local folders stay in `~/.config/vks-guides/cicd`; delete it if you do not need it.

Back to [README](../README.md).
