# Build and deploy on every push

> [!NOTE]
> **Official documentation for this guide**
>
> - Harbor 2.15: [Create Project Robot Accounts](https://goharbor.io/docs/2.15.0/working-with-projects/project-configuration/create-robot-accounts/)
> - Argo CD 3.4: [Projects](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/projects/), [Automated Sync Policy](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/auto_sync/)
> - Kaniko: [osscontainertools/kaniko](https://github.com/osscontainertools/kaniko) (`--registry-certificate`, `--digest-file`)
> - Tekton: [Tasks](https://tekton.dev/docs/pipelines/tasks/), [PipelineRuns](https://tekton.dev/docs/pipelines/pipelineruns/), [EventListeners](https://tekton.dev/docs/triggers/eventlisteners/), [Interceptors](https://tekton.dev/docs/triggers/interceptors/)
> - Gitea 28.2: [Webhooks](https://docs.gitea.com/usage/repository/webhooks/), [API Usage](https://docs.gitea.com/development/api-usage), [Configuration Cheat Sheet](https://docs.gitea.com/administration/config-cheat-sheet) (`[security] ALLOWED_HOST_LIST`)
> - GitLab 19.5: [CI/CD YAML syntax](https://docs.gitlab.com/ci/yaml/), [Custom CI/CD configuration file](https://docs.gitlab.com/ci/pipelines/settings/), [Kubernetes executor](https://docs.gitlab.com/runner/executors/kubernetes/), [Feature flags](https://docs.gitlab.com/runner/configuration/feature-flags/), [Project access tokens](https://docs.gitlab.com/user/project/settings/project_access_tokens/)

This ties the other guides together. You push a change to an app's Git repository; the cluster
builds its image with Kaniko and pushes it to Harbor; the build writes the image's digest into a
second repository, `deploy`; ArgoCD on the Supervisor sees the new commit and rolls it out to the
VKS cluster. The app is [`argocd/test-web-apps`](../argocd/test-web-apps): a page that says
`test-web-apps v1`.

You can do it with Gitea and Tekton, or with GitLab. Steps 1, 2, 3, 5, 8 and 9 are the same; steps
4, 6 and 7 have a section for each.

| | With Gitea and Tekton | With GitLab |
|---|---|---|
| done first | [HARBOR.md](HARBOR.md) 1-9, [ARGOCD.md](ARGOCD.md) 3, 4 and 7, [GITEA.md](GITEA.md) 1-8, [TEKTON.md](TEKTON.md) 1-3 | [HARBOR.md](HARBOR.md) 1-9, [ARGOCD.md](ARGOCD.md) 3, 4 and 7, [GITLAB.md](GITLAB.md) 1-8 |
| builds in | namespace `cicd-ci` | namespace `gitlab-runner` (GitLab.md's runner) |
| writes back from | a Tekton Task with a Gitea bot user's token | a second, locked runner with a deploy token |
| starts on a push | a signed Gitea webhook (step 7) | by itself |

You need:

- the Harbor files from HARBOR.md in `~/.config/vks-guides/harbor` (PowerShell:
  `$HOME\.config\vks-guides\harbor`): `harbor-data-values.yml`, `harbor-ca.crt` and `secrets.env`;
- the VKS cluster from ARGOCD.md step 7, its kubeconfig ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig))
  and your Supervisor kubeconfig;
- the Git server's port-forward running in a second terminal ([GITEA.md](GITEA.md) step 6, or
  [GITLAB.md](GITLAB.md) step 5) and its load-balancer address ([GITEA.md](GITEA.md) step 8, or
  [GITLAB.md](GITLAB.md) step 7);
- [kubectl](KUBECTL.md), [jq and openssl](PREREQS.md) and git.

> [!WARNING]
> **For tests only.** ArgoCD reads `deploy` over plain HTTP, so anyone between the Git server and
> ArgoCD can change what is deployed into `cicd-demo`. The build runs the app's Dockerfile as root
> and can read the Harbor robot that pushes, which may push only to the project `cicd-demo`.

The blocks keep their files in `~/.config/vks-guides/cicd` (PowerShell:
`$HOME\.config\vks-guides\cicd`).

## 1. Check what is in place

**Linux, macOS, WSL (bash or zsh):**

```sh
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
  for N in gitea tekton-pipelines gitlab gitlab-runner cicd-demo; do
    echo "namespace ${N}: $(printf '%s\n' "$NS" | grep -cx "namespace/$N")"
  done
fi
```

**Windows (PowerShell):**

```powershell
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
    foreach ($N in 'gitea', 'tekton-pipelines', 'gitlab', 'gitlab-runner', 'cicd-demo') {
      "namespace ${N}: $(@($NS | Where-Object { $_ -ceq "namespace/$N" }).Count)"
    }
  }
}
```

**Expect:** `Harbor <name>: 200`, then `namespace cicd-demo: 0`, and with Gitea and Tekton
`namespace gitea: 1` and `namespace tekton-pipelines: 1`, or with GitLab `namespace gitlab: 1` and
`namespace gitlab-runner: 1`.

**If not:**
- `FAILED: … is missing`: run this on the machine where you did HARBOR.md, or copy that folder
  here.
- `Harbor <name>:` other than `200`: see [HARBOR.md](HARBOR.md) step 9.
- A `0` for your Git server or Tekton: do its guide first (the table above).
- `namespace cicd-demo: 1`: an earlier run of this guide is still there; remove it with step 9.

## 2. Create the namespaces

`cicd-demo` runs the app, restricted. The build runs the Dockerfile as root, so its namespace
allows baseline pods: `cicd-ci` with Gitea and Tekton, GITLAB.md's `gitlab-runner` with GitLab.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
CI_NAMESPACE="cicd-ci"

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

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$CI_NAMESPACE = "cicd-ci"

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

With GitLab, set `CI_NAMESPACE` to `gitlab-runner`, here and in step 3.

**Expect:** `namespace/cicd-demo created` and `namespace/cicd-ci created` (with GitLab,
`namespace/gitlab-runner unchanged`; `unchanged` on a second run).

## 3. Give the cluster two Harbor robots

This creates the private Harbor project `cicd-demo` and two robot accounts for 90 days: `push`,
for the build, and `pull`, for the app's nodes. Each robot's secret goes straight from Harbor into
a Kubernetes Secret and is never shown: `harbor-push` in the build namespace (a `config.json`, the
file Kaniko reads) and `harbor-pull` in `cicd-demo`. Harbor's CA goes in the ConfigMap `harbor-ca`
beside `harbor-push`. The block signs in to Harbor as `admin` with the password in HARBOR.md's
`secrets.env`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
CI_NAMESPACE="cicd-ci"
HARBOR_PROJECT="cicd-demo"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"

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
$CI_NAMESPACE = "cicd-ci"
$HARBOR_PROJECT = "cicd-demo"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor"

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
- `secrets "harbor-push" already exists` cannot happen here; `namespaces "…" not found`: run step 2
  first, then delete the robot as above and run this again.
- `project:` `401`: the password in `secrets.env` is not Harbor's `admin` password any more.
- In 90 days the robots expire and builds or pulls fail with `unauthorized`: delete both robots in
  Harbor and both Secrets (`kubectl --kubeconfig <the VKS kubeconfig> -n <namespace> delete secret
  harbor-push`), then run this again.

## 4. Create the repositories

Both ways create two repositories: `app`, with the Dockerfile and page from
[`argocd/test-web-apps`](../argocd/test-web-apps), and `deploy`, with the Deployment and Service
ArgoCD applies. Both are public, so the build and ArgoCD read them without a login. `deploy`
starts with the stock nginx image; the first build replaces it.

The block writes the files to `~/.config/vks-guides/cicd/app` and `~/.config/vks-guides/cicd/deploy`
first. Run it in the second terminal, with the port-forward running.

### With Gitea and Tekton

This adds the user `cicd-bot`, with no password anyone knows, who may write only to `deploy`,
and puts a token for it in the Secret `git-writeback` in `cicd-ci`. The admin password is needed
for Gitea's API; type it first:

**Linux, macOS, WSL (bash or zsh):**

```sh
printf 'gitea-admin password: '; IFS= read -rs GITEA_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$GITEA_PASSWORD = Read-Host 'gitea-admin password' -AsSecureString
```

Then, in the same terminal:

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

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
      for F in $(cd "$CICD_DIR/$R" && ls); do
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
        | jq -R '{apiVersion: "v1", kind: "Secret", metadata: {name: "git-writeback", namespace: "cicd-ci"},
                  stringData: {username: "cicd-bot", token: .}}' \
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
      Set-Content -Encoding ascii -Path $CFG -Value "user = `"gitea-admin:$P`""
      Remove-Variable P
      if ((curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' "$GITEA_URL/api/v1/user") -ne '200') {
        "FAILED: Gitea did not accept gitea-admin and this password, or the port-forward is not running"
      } else {
        foreach ($R in 'app', 'deploy') {
          Set-Content -Encoding ascii -Path $BODY -Value ('{"name":"' + $R + '","private":false,"default_branch":"main"}')
          "repository ${R}: $(curl.exe -sS --connect-timeout 20 --max-time 30 -K $CFG -o NUL -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary "@$BODY" "$GITEA_URL/api/v1/user/repos")"
          foreach ($F in (Get-ChildItem "$CICD_DIR\$R" -File | Sort-Object Name)) {
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

#4B#

## 5. Let ArgoCD deploy it

This creates, on the Supervisor, the ArgoCD project `cicd-demo`, which may read only `deploy` and
create only a Deployment and a Service in the namespace `cicd-demo` of your VKS cluster, and its
Application, which keeps that namespace in step with `deploy`. ArgoCD reads `deploy` over the Git
server's load-balancer address. ARGOCD.md's own project and app stay as they are.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GIT_SERVER="gitea"

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
    - name: ${VKS_CLUSTER}-${VKS_NAMESPACE}
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
    name: ${VKS_CLUSTER}-${VKS_NAMESPACE}
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
    - name: $VKS_CLUSTER-$VKS_NAMESPACE
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
    name: $VKS_CLUSTER-$VKS_NAMESPACE
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
created` and `application.argoproj.io/cicd-demo created` (`unchanged` on a second run). Within
about 3 minutes, the block below prints `Synced Healthy` and the app's page shows nginx's own
welcome page.

Check it with this block. It waits until ArgoCD has synced and the page shows `WANT`; steps 6
and 8 use it again with another `WANT`.

**Linux, macOS, WSL (bash or zsh):**

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
echo "ArgoCD: $(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get application cicd-demo -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}')"
echo "page at http://${IP:-?}/: ${V:-nothing}"
echo "image: $(kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-demo get deployment cicd-demo -o jsonpath='{.spec.template.spec.containers[0].image}')"
kubectl --kubeconfig "$VKS_KUBECONFIG" -n cicd-demo get pods --no-headers -o custom-columns=POD:.metadata.name,IMAGE:.status.containerStatuses[0].imageID
```

**Windows (PowerShell):**

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
"ArgoCD: $(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get application cicd-demo -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}')"
"page at http://$(if ($IP) { $IP } else { '?' })/: $(if ($V) { $V } else { 'nothing' })"
"image: $(kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-demo get deployment cicd-demo -o jsonpath='{.spec.template.spec.containers[0].image}')"
kubectl --kubeconfig $VKS_KUBECONFIG -n cicd-demo get pods --no-headers -o custom-columns=POD:.metadata.name,IMAGE:.status.containerStatuses[0].imageID
```

**If not:** 
- `ArgoCD: OutOfSync` or `Unknown`, with a message in ArgoCD's web page under **cicd-demo**:
  `repository not accessible` means the Supervisor cannot reach the address in `deploy
  repository:` (try it from your machine with `git ls-remote <address>`); `not permitted in project`
  means a file in `deploy` names another namespace or kind.
- `page at …: nothing` and pods `ErrImagePull`: see `kubectl --kubeconfig <the VKS kubeconfig> -n
  cicd-demo describe pods`; `unauthorized` points at `harbor-pull` (step 3), `x509` at the nodes'
  trust of Harbor ([HARBOR.md](HARBOR.md) step 8).
- `FAILED: no load-balancer address`: do GITEA.md step 8 or GITLAB.md step 7.

## 6. Build it once

### With Gitea and Tekton

This creates the Tasks and the Pipeline in `cicd-ci`, then runs it once.

- The Task `build` runs in one pod: a step clones `app` from Gitea inside the cluster, drops its
  `.git` folder, and Kaniko builds the image and pushes it to Harbor as `cicd-demo/test-web-apps`,
  tagged with the commit. Kaniko trusts Harbor through `harbor-ca` and signs in with `harbor-push`;
  this pod gets no Git credential.
- The Task `write-back` runs in a second pod with `git-writeback`: it checks that the digest from
  `build` is a digest, clones `deploy`, sets the image to that digest, and pushes as `cicd-bot`.

Each pod runs under its own ServiceAccount, with no Kubernetes token mounted.

Then run step 5's check with `WANT="test-web-apps v1"`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

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

### With GitLab

#6B#

## 7. Build on every push

### With Gitea and Tekton

This makes Gitea call Tekton on every push to `app`. It creates, in `cicd-ci`, an EventListener
that starts the pipeline only for a push to `main` signed with the secret in the Secret
`cicd-webhook`, and a network policy that lets only Gitea's pods reach it; then it adds the webhook
to `app` in Gitea with the same secret. Run it in the terminal where you typed the Gitea password
in step 4 (or type it again with the first block there).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

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
kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<EOF
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
@"
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata: {name: cicd-demo, namespace: cicd-ci}
spec:
  params:
    - {name: app-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/app.git"}
    - {name: deploy-url, value: "http://gitea-http.gitea.svc:3000/gitea-admin/deploy.git"}
    - {name: image, value: cicd-demo/test-web-apps}
    - {name: registry, value: "$HARBOR_FQDN"}
"@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
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
    Set-Content -Encoding ascii -Path $CFG -Value "user = `"gitea-admin:$P`""
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
  egress policy`: your Gitea predates GITEA.md's webhook setting; run GITEA.md step 4 again.
- `FAILED: no Gitea password …`: type it with step 4's first block, then run this again.

### With GitLab

Nothing to do: GitLab starts the pipeline on every push to `main` of `cicd/app`.

## 8. Change the page

Edit the page in `app` and push it. With Gitea, Gitea's webhook starts the pipeline; with GitLab,
GitLab does. The build writes the new digest into `deploy`, and ArgoCD rolls it out. Run this in
the second terminal; git asks for `gitea-admin`'s password (with GitLab, `root`'s).

**Linux, macOS, WSL (bash or zsh):**

```sh
GIT_SERVER="gitea"
APP_DIR="$HOME/.config/vks-guides/cicd/app-work"
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

**Windows (PowerShell):**

```powershell
$GIT_SERVER = "gitea"
$APP_DIR = "$HOME\.config\vks-guides\cicd\app-work"
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

**Expect:** after the password, `<old>..<new>  HEAD -> main`. With Gitea, within a minute
`kubectl --kubeconfig <the VKS kubeconfig> -n cicd-ci get pipelineruns` lists a new run that turns
`Succeeded`; with GitLab, `http://localhost:3400/cicd/app/-/pipelines` shows a new pipeline that
turns **Passed**. Then run step 5's check with `WANT="test-web-apps v2"`: within about 3 minutes
the page says `test-web-apps v2`, `image:` ends in a new `@sha256:…`, and every pod's image ID ends
in that digest.

**If not:**
- `Everything up-to-date`: the page already said v2; change `v2` to `v3` in the block and run it
  again.
- With Gitea, no new PipelineRun: see step 7's **If not**.
- The page still shows v1 after 5 minutes but the run succeeded: in ArgoCD's web page, open
  **cicd-demo** and click **Refresh**; ArgoCD checks `deploy` for changes every few minutes.

## 9. Clean up (optional)

This removes what this guide made: the Application (ArgoCD deletes the app with it) and its
project, the namespaces, the Harbor project with its robots and images, and the repositories. The
Git server, Tekton or the runner from the other guides stay. With Gitea, run it in the terminal
where you typed the Gitea password in step 4.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GIT_SERVER="gitea"
HARBOR_PROJECT="cicd-demo"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"
GITEA_URL="http://localhost:3300"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete application cicd-demo --ignore-not-found --timeout=5m \
  && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete appproject cicd-demo --ignore-not-found
kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace cicd-demo --ignore-not-found --timeout=10m
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
#9B-SH#
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
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete application cicd-demo --ignore-not-found --timeout=5m
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete appproject cicd-demo --ignore-not-found }
kubectl --kubeconfig $VKS_KUBECONFIG delete namespace cicd-demo --ignore-not-found --timeout=10m
if ($GIT_SERVER -eq 'gitea') {
  kubectl --kubeconfig $VKS_KUBECONFIG delete namespace cicd-ci --ignore-not-found --timeout=10m
  kubectl --kubeconfig $VKS_KUBECONFIG delete clusterrolebinding,clusterrole cicd-listener --ignore-not-found
  if (-not $GITEA_PASSWORD) {
    "skipped: Gitea repositories (no Gitea password in this terminal; type it with step 4's first block)"
  } else {
    $P = [Net.NetworkCredential]::new('', $GITEA_PASSWORD).Password.Replace('\', '\\').Replace('"', '\"')
    $CFG = [IO.Path]::GetTempFileName()
    try {
      Set-Content -Encoding ascii -Path $CFG -Value "user = `"gitea-admin:$P`""
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
#9B-PS#
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
```

</details>

**Expect:** `application.argoproj.io "cicd-demo" deleted`, `appproject.argoproj.io "cicd-demo"
deleted`, `namespace "cicd-demo" deleted`, then with Gitea `namespace "cicd-ci" deleted`,
`repository app: 204`, `repository deploy: 204` and `user cicd-bot: deleted`, and last
`Harbor cicd-demo/repositories/test-web-apps: 200` and `Harbor cicd-demo: 200`. On a second run
the deletes print nothing and Harbor prints `404`.

**If not:**
- `Harbor cicd-demo: 412`: the project still holds something; delete it in Harbor's web page
  (**Projects** → `cicd-demo`), then run this again.

The local folders stay in `~/.config/vks-guides/cicd`; delete it if you do not need it.

Back to [README](../README.md).
