# Run Gitea in a VKS cluster

> [!NOTE]
> **Official Gitea, Git and Kubernetes documentation for this guide**
>
> - Gitea 28.2: [Installation with Docker (rootless)](https://docs.gitea.com/installation/install-with-docker-rootless/) (the image this guide runs), [Use environment variables to set up Gitea](https://docs.gitea.com/administration/config-cheat-sheet/#use-environment-variables-to-setup-gitea), [Configuration Cheat Sheet](https://docs.gitea.com/administration/config-cheat-sheet/)
> - Gitea 28.2: [Gitea Command Line](https://docs.gitea.com/administration/command-line/) (`gitea admin user`), [Push To Create](https://docs.gitea.com/usage/repository/push/)
> - Gitea: [Helm chart for Gitea](https://gitea.com/gitea/helm-gitea) (step 4, option B)
> - Git: [Install](https://git-scm.com/install/), [gitcredentials](https://git-scm.com/docs/gitcredentials) (why the push turns the credential helper off)
> - Kubernetes: [Enforce Pod Security Standards with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/), [Use Port Forwarding to Access Applications in a Cluster](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)

This runs Gitea 28.2.0, a Git server with a web page, in a VKS cluster: one pod, its data in
SQLite on a 5 GiB volume. Gitea is upstream; Broadcom does not support it. You reach it through
`kubectl port-forward`; step 8 also lets other machines (such as ArgoCD on the Supervisor) clone
from it over plain HTTP. Upgrades and backups are not covered.

The blocks keep their files in `~/.config/vks-guides/gitea` (PowerShell:
`$HOME\.config\vks-guides\gitea`).

## Prerequisites

- a VKS cluster with a default storage class ([CLUSTER.md](CLUSTER.md)) and its kubeconfig
  ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig));
- [kubectl](KUBECTL.md), [jq and openssl](PREREQS.md), [git](https://git-scm.com/install/), and for
  step 4 option B [Helm](HELM.md);
- for step 8, one free load-balancer address.

The connections this guide needs, for a firewall (all TCP, besides DNS; for a registry, also
the hosts in [Registry hosts](PREREQS.md#registry-hosts-for-a-firewall)):

| from | to | port | for |
|---|---|---|---|
| your machine | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl and Helm (all steps), and the port-forward to Gitea (steps 6 to 8) |
| the cluster's nodes | `docker.io` | 443 | Gitea's image (step 4) |
| your machine | `dl.gitea.com` | 443 | Gitea's Helm chart (step 4, option B) |
| ArgoCD, your machine, other machines that clone | Gitea's load-balancer address (step 8) | 3000 | cloning over plain HTTP |

## 1. Check the cluster

This checks that you can use the cluster before you install anything. It shows that git is
installed, that kubectl reaches your VKS cluster and its nodes are `Ready`, which storage class the
cluster uses by default (Gitea's volume comes from it), and that no `gitea` namespace exists yet.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

git --version
if kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes \
   && SC="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get storageclass -o json)" \
   && NS="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get namespace -o name)"; then
  echo "default storage class: $(printf '%s' "$SC" | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | "\(.metadata.name) (\(.volumeBindingMode), reclaim \(.reclaimPolicy))"] | if length == 0 then "NONE" else join(" ") end')"
  echo "gitea namespace: $(printf '%s\n' "$NS" | grep -cx 'namespace/gitea')"
else
  echo "FAILED: cannot read the cluster (see the error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

git --version
$global:LASTEXITCODE = $null
kubectl --kubeconfig $VKS_KUBECONFIG get nodes
if ($LASTEXITCODE -eq 0) { $SC = kubectl --kubeconfig $VKS_KUBECONFIG get storageclass -o json | Out-String }
if ($LASTEXITCODE -eq 0) { $NS = @(kubectl --kubeconfig $VKS_KUBECONFIG get namespace -o name) }
if ($LASTEXITCODE -eq 0) {
  $D = @((ConvertFrom-Json $SC).items | Where-Object { $_.metadata.annotations.'storageclass.kubernetes.io/is-default-class' -eq 'true' } | ForEach-Object { "$($_.metadata.name) ($($_.volumeBindingMode), reclaim $($_.reclaimPolicy))" })
  "default storage class: $(if ($D.Count) { $D -join ' ' } else { 'NONE' })"
  "gitea namespace: $(@($NS | Where-Object { $_ -ceq 'namespace/gitea' }).Count)"
} else {
  "FAILED: cannot read the cluster (see the error above)"
}
```

</details>

**Expect:** `git version 2.…`, each node `Ready`, `default storage class:` and a name, and
`gitea namespace: 0`.

**If not:**
- `git: command not found` (PowerShell: `The term 'git' is not recognized`): install git
  ([git-scm.com](https://git-scm.com/install/); on AlmaLinux 10, `sudo dnf install -y git`; on
  Photon OS 5, `sudo tdnf install -y git`), open a new terminal, and run this again. On macOS,
  `git` may open a dialog that installs the Command Line Tools; let it finish.
- `default storage class: NONE`: see [CLUSTER.md](CLUSTER.md) step 7.
- `gitea namespace: 1` before you ran step 2: the cluster already has a `gitea` namespace. Use
  another cluster, or remove it with step 9 if it is an earlier run of this guide.
- `FAILED: cannot read the cluster`: run
  [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig) first.

## 2. Create the namespace

This creates the namespace `gitea`, a separate area of the cluster for everything Gitea needs.
Gitea does not need root, so the namespace accepts only pods that run without admin rights (the
`restricted` level).

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: gitea
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

@'
apiVersion: v1
kind: Namespace
metadata:
  name: gitea
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
```

**Expect:** `namespace/gitea created` (`unchanged` on a second run).

**If not:** `Forbidden`: your kubeconfig is not the cluster's administrator; use the one from
[LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig).

## 3. Create Gitea's keys

Gitea needs two random keys: one to encrypt what it stores, one for its own internal calls. This
makes both and stores them in the cluster as the Secret `gitea-keys` (a Kubernetes object that
holds sensitive values). It never replaces them: with new keys, Gitea could not read what it
stored.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

K1="$(openssl rand -hex 32 | tr -d '\n' | base64 | tr -d '\n')"
K2="$(openssl rand -hex 32 | tr -d '\n' | base64 | tr -d '\n')"
if [ "${#K1}" -ne 88 ] || [ "${#K2}" -ne 88 ]; then
  echo "FAILED: could not make the keys (see the error above)"
else
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: gitea-keys\n  namespace: gitea\ndata:\n  secret-key: %s\n  internal-token: %s\n' "$K1" "$K2" \
    | kubectl --kubeconfig "$VKS_KUBECONFIG" create -f -
fi
unset K1 K2
kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea get secret gitea-keys -o json \
  | jq -r '"key lengths: \(.data["secret-key"] | @base64d | length) \(.data["internal-token"] | @base64d | length)"'
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$RNG = [Security.Cryptography.RandomNumberGenerator]::Create()
$K = foreach ($i in 1, 2) {
  $B = New-Object byte[] 32
  $RNG.GetBytes($B)
  [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes((-join ($B | ForEach-Object { $_.ToString('x2') }))))
}
"apiVersion: v1`nkind: Secret`nmetadata:`n  name: gitea-keys`n  namespace: gitea`ndata:`n  secret-key: $($K[0])`n  internal-token: $($K[1])`n" |
  kubectl --kubeconfig $VKS_KUBECONFIG create -f -
Remove-Variable K, B
$S = kubectl --kubeconfig $VKS_KUBECONFIG -n gitea get secret gitea-keys -o json | Out-String | ConvertFrom-Json
if ($S) { "key lengths: $([Convert]::FromBase64String($S.data.'secret-key').Length) $([Convert]::FromBase64String($S.data.'internal-token').Length)" }
Remove-Variable S
```

</details>

**Expect:** `secret/gitea-keys created`, then `key lengths: 64 64`. On a second run,
`Error from server (AlreadyExists)` and `key lengths: 64 64`: the keys you have are kept.

**If not:**
- `key lengths:` other than `64 64`: delete the Secret before step 4 (`kubectl --kubeconfig <the VKS
  kubeconfig> -n gitea delete secret gitea-keys`) and run this again. After step 4, run step 9
  and start again.
- `namespaces "gitea" not found`: run step 2 first.

## 4. Install Gitea

Install Gitea one of two ways, A or B; steps 5 to 9 are the same for both. Both run Gitea 28.2.0
with the same settings and the keys from step 3. To switch from one to the other later, run step 9,
then steps 2 and 3, first: they keep their data differently, and nothing carries over.

Both blocks read the cluster's Service address range, so that Gitea may call build tools inside the
cluster later ([CICD.md](CICD.md) step 7). On a cluster older than Kubernetes v1.33, which cannot
show it, set `SERVICE_RANGE` to the range the cluster was created with (CLUSTER.md:
`10.96.0.0/12`).

### A. With this guide's YAML (recommended)

> [!NOTE]
> **Why this is the default:** it needs only kubectl, and every setting is in the one manifest
> below. It runs one container, with no init containers, no extra Services and no chart defaults to
> switch off, and Gitea reads its settings from the manifest at every start, so a changed setting
> takes effect when you run this block again.

This starts Gitea in your VKS cluster. It creates:

- a 5 GiB volume, so your repositories survive a restart;
- Gitea itself: one pod that uses the keys from step 3;
- a Service: a fixed address for Gitea that only the cluster reaches (step 6 opens it to your
  machine).

It then waits until Gitea answers.

`SERVICE_RANGE`: leave it empty to read it from the cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SERVICE_RANGE=""

if [ -z "$SERVICE_RANGE" ]; then
  SERVICE_RANGE="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get servicecidr -o jsonpath='{.items[*].spec.cidrs[*]}')"
fi
ALLOWED="$(printf '%s\n' "$SERVICE_RANGE" | tr ' ,' '\n\n' | grep . | sed -e '/:/s/.*/[&]/' -e 's/$/:8080/' | paste -sd, -)"
if [ -z "$ALLOWED" ]; then
  echo "FAILED: no Service range; set SERVICE_RANGE to your cluster's (see above)"
else
sed "s|@ALLOWED_HOST_LIST@|$ALLOWED|" <<'EOF' | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-data
  namespace: gitea
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea
  namespace: gitea
  labels:
    app.kubernetes.io/name: gitea
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: gitea
  template:
    metadata:
      labels:
        app.kubernetes.io/name: gitea
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: gitea
          image: docker.io/gitea/gitea:28.2.0-rootless@sha256:94807314454f6525994a3b76286ba12bc7e7f8cd14f61d9e67431767f8103306
          env:
            - { name: GITEA__database__DB_TYPE, value: "sqlite3" }
            - { name: GITEA__database__PATH, value: "/var/lib/gitea/data/gitea.db" }
            - { name: GITEA__server__HTTP_PORT, value: "3000" }
            - { name: GITEA__server__ROOT_URL, value: "http://localhost:3300/" }
            - { name: GITEA__server__DISABLE_SSH, value: "true" }
            - { name: GITEA__security__INSTALL_LOCK, value: "true" }
            - { name: GITEA__security__MIN_PASSWORD_LENGTH, value: "16" }
            - { name: GITEA__security__ALLOWED_HOST_LIST, value: "@ALLOWED_HOST_LIST@" }
            - { name: GITEA__security__EGRESS_MODE, value: "lax" }
            - { name: GITEA__service__DISABLE_REGISTRATION, value: "true" }
            - { name: GITEA__repository__ENABLE_PUSH_CREATE_USER, value: "true" }
            - { name: GITEA__oauth2__ENABLED, value: "false" }
            - name: GITEA__security__SECRET_KEY
              valueFrom: { secretKeyRef: { name: gitea-keys, key: secret-key } }
            - name: GITEA__security__INTERNAL_TOKEN
              valueFrom: { secretKeyRef: { name: gitea-keys, key: internal-token } }
          ports:
            - { name: http, containerPort: 3000 }
          startupProbe:
            httpGet: { path: /api/healthz, port: http }
            periodSeconds: 5
            failureThreshold: 60
          readinessProbe:
            httpGet: { path: /api/healthz, port: http }
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /api/healthz, port: http }
            periodSeconds: 15
            timeoutSeconds: 5
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: "1", memory: 1Gi }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - { name: data, mountPath: /var/lib/gitea }
            - { name: config, mountPath: /etc/gitea }
            - { name: tmp, mountPath: /tmp }
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: gitea-data
        - name: config
          emptyDir: {}
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: gitea-http
  namespace: gitea
spec:
  selector:
    app.kubernetes.io/name: gitea
  ports:
    - { name: http, port: 3000, targetPort: http }
EOF
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea rollout status deployment/gitea --timeout=10m
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea get pvc,pods
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SERVICE_RANGE = ""                   # empty: read it from the cluster

if (-not $SERVICE_RANGE) {
  $SERVICE_RANGE = kubectl --kubeconfig $VKS_KUBECONFIG get servicecidr -o jsonpath='{.items[*].spec.cidrs[*]}'
}
$ALLOWED = (@("$SERVICE_RANGE" -split '[ ,]' | Where-Object { $_ }) | ForEach-Object { if ($_ -like '*:*') { "[${_}]:8080" } else { "${_}:8080" } }) -join ','
if (-not $ALLOWED) {
  "FAILED: no Service range; set SERVICE_RANGE to your cluster's (see above)"
} else {
@'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-data
  namespace: gitea
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea
  namespace: gitea
  labels:
    app.kubernetes.io/name: gitea
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: gitea
  template:
    metadata:
      labels:
        app.kubernetes.io/name: gitea
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: gitea
          image: docker.io/gitea/gitea:28.2.0-rootless@sha256:94807314454f6525994a3b76286ba12bc7e7f8cd14f61d9e67431767f8103306
          env:
            - { name: GITEA__database__DB_TYPE, value: "sqlite3" }
            - { name: GITEA__database__PATH, value: "/var/lib/gitea/data/gitea.db" }
            - { name: GITEA__server__HTTP_PORT, value: "3000" }
            - { name: GITEA__server__ROOT_URL, value: "http://localhost:3300/" }
            - { name: GITEA__server__DISABLE_SSH, value: "true" }
            - { name: GITEA__security__INSTALL_LOCK, value: "true" }
            - { name: GITEA__security__MIN_PASSWORD_LENGTH, value: "16" }
            - { name: GITEA__security__ALLOWED_HOST_LIST, value: "@ALLOWED_HOST_LIST@" }
            - { name: GITEA__security__EGRESS_MODE, value: "lax" }
            - { name: GITEA__service__DISABLE_REGISTRATION, value: "true" }
            - { name: GITEA__repository__ENABLE_PUSH_CREATE_USER, value: "true" }
            - { name: GITEA__oauth2__ENABLED, value: "false" }
            - name: GITEA__security__SECRET_KEY
              valueFrom: { secretKeyRef: { name: gitea-keys, key: secret-key } }
            - name: GITEA__security__INTERNAL_TOKEN
              valueFrom: { secretKeyRef: { name: gitea-keys, key: internal-token } }
          ports:
            - { name: http, containerPort: 3000 }
          startupProbe:
            httpGet: { path: /api/healthz, port: http }
            periodSeconds: 5
            failureThreshold: 60
          readinessProbe:
            httpGet: { path: /api/healthz, port: http }
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /api/healthz, port: http }
            periodSeconds: 15
            timeoutSeconds: 5
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: "1", memory: 1Gi }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - { name: data, mountPath: /var/lib/gitea }
            - { name: config, mountPath: /etc/gitea }
            - { name: tmp, mountPath: /tmp }
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: gitea-data
        - name: config
          emptyDir: {}
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: gitea-http
  namespace: gitea
spec:
  selector:
    app.kubernetes.io/name: gitea
  ports:
    - { name: http, port: 3000, targetPort: http }
'@.Replace('@ALLOWED_HOST_LIST@', $ALLOWED) | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
  kubectl --kubeconfig $VKS_KUBECONFIG -n gitea rollout status deployment/gitea --timeout=10m
  kubectl --kubeconfig $VKS_KUBECONFIG -n gitea get pvc,pods
}
```

</details>

**Expect:** `persistentvolumeclaim/gitea-data created`, `deployment.apps/gitea created`,
`service/gitea-http created`, then `deployment "gitea" successfully rolled out`, the claim
`Bound` and one pod `1/1 Running` (`unchanged` lines on a second run).

**If not:**
- `FAILED: no Service range`: the line above it says why; on Kubernetes older than v1.33
  (`the server doesn't have a resource type "servicecidr"`), set `SERVICE_RANGE`.
- `secret "gitea-keys" not found` in `kubectl --kubeconfig <the VKS kubeconfig> -n gitea describe
  pod` (the pod stays `CreateContainerConfigError`): run step 3.
- The claim stays `Pending`: the storage class cannot make the volume. `kubectl --kubeconfig <the
  VKS kubeconfig> -n gitea describe pvc gitea-data` says why; often the vSphere Namespace's
  storage limit is reached.
- The pod is `ErrImagePull` or `ImagePullBackOff`: `kubectl --kubeconfig <the VKS kubeconfig> -n
  gitea describe pod` says why: the nodes cannot reach `docker.io`, or `toomanyrequests`
  (Docker Hub's pull limit; wait and run this again).
- `timed out waiting for the condition`: run `kubectl --kubeconfig <the VKS kubeconfig> -n gitea
  logs deployment/gitea` and look for the first error.
- `spec.selector: … field is immutable`: Gitea was installed with B; run step 9, then steps 2 and
  3, first.

### B. With Gitea's Helm chart

This installs Gitea with its own Helm chart, 12.7.0, and values that make it the same Gitea as A.
It needs [Helm](HELM.md). The block writes the values to
`~/.config/vks-guides/gitea/values.yaml`, downloads the chart and checks its SHA-256, then installs
and waits for Gitea to answer.

> [!NOTE]
> **Limits of the Helm way:**
> - Chart 12.7.0 is built for Gitea 1.27; these values run Gitea 28.2.0, the image A uses.
>   `helm list` shows the chart's `1.27.0`.
> - Gitea keeps its settings in a file on the volume. A changed value takes effect when you run
>   this block again, but a value you remove stays set, and the keys from step 3 are read only at
>   the first start. To start over, run step 9.
> - The pod has three init containers, and the chart adds a Service `gitea-ssh` that nothing
>   answers.
> - Without these values the chart also installs a PostgreSQL cluster, a cache cluster and an
>   administrator with a published password; keep `-f values.yaml` on every run.

`SERVICE_RANGE`: leave it empty to read it from the cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GITEA_DIR="$HOME/.config/vks-guides/gitea"
CHART_SHA256="5881ef9c59400bee2d5547e77c4cd0efb925143c2f5d93fb4f38446db76b0167"
SERVICE_RANGE=""

if [ -z "$SERVICE_RANGE" ]; then
  SERVICE_RANGE="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get servicecidr -o jsonpath='{.items[*].spec.cidrs[*]}')"
fi
ALLOWED="$(printf '%s\n' "$SERVICE_RANGE" | tr ' ,' '\n\n' | grep . | sed -e '/:/s/.*/[&]/' -e 's/$/:8080/' | paste -sd, -)"
CHART="$GITEA_DIR/gitea-12.7.0.tgz"
URL="https://dl.gitea.com/charts/gitea-12.7.0.tgz"
mkdir -p "$GITEA_DIR"
[ -n "$ALLOWED" ] && sed "s|@ALLOWED_HOST_LIST@|$ALLOWED|" > "$GITEA_DIR/values.yaml" <<'EOF'
image:
  registry: docker.io
  repository: gitea/gitea
  tag: 28.2.0
  digest: sha256:94807314454f6525994a3b76286ba12bc7e7f8cd14f61d9e67431767f8103306
  rootless: true
strategy:
  type: Recreate
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
service:
  http:
    type: ClusterIP
    clusterIP: ""
    port: 3000
serviceAccount:
  create: true
  automountServiceAccountToken: false
persistence:
  claimName: gitea-data
  size: 5Gi
  annotations:
    helm.sh/resource-policy: null
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 1Gi
gitea:
  admin:
    username: ""
    password: ""
  config:
    database:
      DB_TYPE: sqlite3
    server:
      DOMAIN: localhost
      HTTP_PORT: 3000
      ROOT_URL: http://localhost:3300/
      DISABLE_SSH: true
    security:
      INSTALL_LOCK: true
      MIN_PASSWORD_LENGTH: 16
      ALLOWED_HOST_LIST: @ALLOWED_HOST_LIST@
      EGRESS_MODE: lax
    service:
      DISABLE_REGISTRATION: true
    repository:
      ENABLE_PUSH_CREATE_USER: true
    oauth2:
      ENABLED: false
  additionalConfigFromEnvs:
    - name: GITEA__SECURITY__SECRET_KEY
      valueFrom:
        secretKeyRef:
          name: gitea-keys
          key: secret-key
    - name: GITEA__SECURITY__INTERNAL_TOKEN
      valueFrom:
        secretKeyRef:
          name: gitea-keys
          key: internal-token
  podAnnotations:
    kubectl.kubernetes.io/default-container: gitea
  startupProbe:
    enabled: true
    tcpSocket: null
    httpGet:
      path: /api/healthz
      port: http
    initialDelaySeconds: 0
    periodSeconds: 5
    failureThreshold: 60
  readinessProbe:
    tcpSocket: null
    httpGet:
      path: /api/healthz
      port: http
    initialDelaySeconds: 0
    periodSeconds: 5
  livenessProbe:
    tcpSocket: null
    httpGet:
      path: /api/healthz
      port: http
    initialDelaySeconds: 0
    periodSeconds: 15
    timeoutSeconds: 5
valkey-cluster:
  enabled: false
valkey:
  enabled: false
postgresql-ha:
  enabled: false
postgresql:
  enabled: false
test:
  enabled: false
EOF
if [ -z "$ALLOWED" ]; then
  echo "FAILED: no Service range; set SERVICE_RANGE to your cluster's (see above)"
elif ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" "$URL"; then
  echo "FAILED: download of $URL"
elif [ "$( (sha256sum "$CHART.new" 2>/dev/null || shasum -a 256 "$CHART.new") | cut -d' ' -f1)" != "$CHART_SHA256" ]; then
  echo "FAILED: checksum mismatch for $URL"
else
  mv "$CHART.new" "$CHART"
  helm upgrade --install gitea "$CHART" --kubeconfig "$VKS_KUBECONFIG" -n gitea -f "$GITEA_DIR/values.yaml" --wait --timeout 10m >/dev/null \
    && helm list --kubeconfig "$VKS_KUBECONFIG" -n gitea \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea get pvc,pods
fi
rm -f "$CHART.new"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GITEA_DIR = "$HOME\.config\vks-guides\gitea"
$CHART_SHA256 = "5881ef9c59400bee2d5547e77c4cd0efb925143c2f5d93fb4f38446db76b0167"
$SERVICE_RANGE = ""                   # empty: read it from the cluster

if (-not $SERVICE_RANGE) {
  $SERVICE_RANGE = kubectl --kubeconfig $VKS_KUBECONFIG get servicecidr -o jsonpath='{.items[*].spec.cidrs[*]}'
}
$ALLOWED = (@("$SERVICE_RANGE" -split '[ ,]' | Where-Object { $_ }) | ForEach-Object { if ($_ -like '*:*') { "[${_}]:8080" } else { "${_}:8080" } }) -join ','
$CHART = "$GITEA_DIR\gitea-12.7.0.tgz"
$URL = "https://dl.gitea.com/charts/gitea-12.7.0.tgz"
New-Item -ItemType Directory -Force -Path $GITEA_DIR | Out-Null
$V = @'
image:
  registry: docker.io
  repository: gitea/gitea
  tag: 28.2.0
  digest: sha256:94807314454f6525994a3b76286ba12bc7e7f8cd14f61d9e67431767f8103306
  rootless: true
strategy:
  type: Recreate
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
service:
  http:
    type: ClusterIP
    clusterIP: ""
    port: 3000
serviceAccount:
  create: true
  automountServiceAccountToken: false
persistence:
  claimName: gitea-data
  size: 5Gi
  annotations:
    helm.sh/resource-policy: null
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 1Gi
gitea:
  admin:
    username: ""
    password: ""
  config:
    database:
      DB_TYPE: sqlite3
    server:
      DOMAIN: localhost
      HTTP_PORT: 3000
      ROOT_URL: http://localhost:3300/
      DISABLE_SSH: true
    security:
      INSTALL_LOCK: true
      MIN_PASSWORD_LENGTH: 16
      ALLOWED_HOST_LIST: @ALLOWED_HOST_LIST@
      EGRESS_MODE: lax
    service:
      DISABLE_REGISTRATION: true
    repository:
      ENABLE_PUSH_CREATE_USER: true
    oauth2:
      ENABLED: false
  additionalConfigFromEnvs:
    - name: GITEA__SECURITY__SECRET_KEY
      valueFrom:
        secretKeyRef:
          name: gitea-keys
          key: secret-key
    - name: GITEA__SECURITY__INTERNAL_TOKEN
      valueFrom:
        secretKeyRef:
          name: gitea-keys
          key: internal-token
  podAnnotations:
    kubectl.kubernetes.io/default-container: gitea
  startupProbe:
    enabled: true
    tcpSocket: null
    httpGet:
      path: /api/healthz
      port: http
    initialDelaySeconds: 0
    periodSeconds: 5
    failureThreshold: 60
  readinessProbe:
    tcpSocket: null
    httpGet:
      path: /api/healthz
      port: http
    initialDelaySeconds: 0
    periodSeconds: 5
  livenessProbe:
    tcpSocket: null
    httpGet:
      path: /api/healthz
      port: http
    initialDelaySeconds: 0
    periodSeconds: 15
    timeoutSeconds: 5
valkey-cluster:
  enabled: false
valkey:
  enabled: false
postgresql-ha:
  enabled: false
postgresql:
  enabled: false
test:
  enabled: false
'@
if ($ALLOWED) { [IO.File]::WriteAllText("$GITEA_DIR\values.yaml", ($V.Replace('@ALLOWED_HOST_LIST@', $ALLOWED) -replace "`r`n", "`n") + "`n") }
$global:LASTEXITCODE = $null
if ($ALLOWED) { curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" $URL }
if (-not $ALLOWED) {
  "FAILED: no Service range; set SERVICE_RANGE to your cluster's (see above)"
} elseif ($LASTEXITCODE -ne 0) {
  "FAILED: download of $URL"
} elseif ((Get-FileHash -Algorithm SHA256 "$CHART.new").Hash -ne $CHART_SHA256) {
  "FAILED: checksum mismatch for $URL"
} else {
  Move-Item -Force "$CHART.new" $CHART
  helm upgrade --install gitea $CHART --kubeconfig $VKS_KUBECONFIG -n gitea -f "$GITEA_DIR\values.yaml" --wait --timeout 10m | Out-Null
  if ($LASTEXITCODE -eq 0) { helm list --kubeconfig $VKS_KUBECONFIG -n gitea }
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n gitea get pvc,pods }
}
Remove-Item -Force -ErrorAction SilentlyContinue "$CHART.new"
```

</details>

**Expect:** a line for the release `gitea` with `STATUS deployed`, the claim `gitea-data` `Bound`
and one pod `1/1 Running`.

**If not:**
- `FAILED: no Service range`: the line above it says why; on Kubernetes older than v1.33
  (`the server doesn't have a resource type "servicecidr"`), set `SERVICE_RANGE`.
- `helm: command not found`: install Helm ([HELM.md](HELM.md)).
- `FAILED: download …`: this machine cannot reach `dl.gitea.com`.
- `FAILED: checksum mismatch …`: the download arrived damaged, or the chart was rebuilt. Do not
  install it; run the block again.
- `cannot be imported into the current release`: Gitea was installed with A; run step 9, then
  steps 2 and 3, first.
- `context deadline exceeded`: as A's **If not** above (`describe pod`, `describe pvc`, `logs`).

## 5. Create the administrator

This makes the user `gitea-admin` with a random password, printed once. Gitea asks for a new
password at the first login (step 6). Set `GITEA_ADMIN_EMAIL` to your email address; Gitea needs
one but sends no mail. Clear the terminal after step 6.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GITEA_ADMIN_EMAIL="you@example.com"

if ! U="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- gitea admin user list --admin)"; then
  echo "FAILED: cannot run gitea in the pod (see the error above)"
elif printf '%s\n' "$U" | awk '$2 == "gitea-admin" { f = 1 } END { exit !f }'; then
  echo "gitea-admin exists already: log in with the password you set in step 6"
else
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- gitea admin user create \
    --admin --username gitea-admin --email "$GITEA_ADMIN_EMAIL" \
    --random-password --random-password-length 20 --must-change-password
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$GITEA_ADMIN_EMAIL = "you@example.com"

$global:LASTEXITCODE = $null
$U = @(kubectl --kubeconfig $VKS_KUBECONFIG -n gitea exec deployment/gitea -- gitea admin user list --admin)
if ($LASTEXITCODE -ne 0) {
  "FAILED: cannot run gitea in the pod (see the error above)"
} elseif (@($U | Where-Object { (-split $_)[1] -ceq 'gitea-admin' }).Count) {
  "gitea-admin exists already: log in with the password you set in step 6"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG -n gitea exec deployment/gitea -- gitea admin user create `
    --admin --username gitea-admin --email $GITEA_ADMIN_EMAIL `
    --random-password --random-password-length 20 --must-change-password
}
```

</details>

**Expect:** `generated random password is '…'` and `New user 'gitea-admin' has been successfully
created!` (`gitea-admin exists already` on a second run).

**If not:**
- `gitea-admin exists already` and you lost the password: this sets a new random one and prints
  it (`new password: …`); then do step 6 again.

  **Linux, macOS, WSL (bash or zsh):**

  ```sh
  VKS_CLUSTER="my-vks-cluster"
  VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

  kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- sh -c 'P=$(head -c 15 /dev/urandom | base64); gitea admin user change-password --username gitea-admin --password $P --must-change-password && echo new password: $P'
  ```

  **Windows (PowerShell):**

  ```powershell
  $VKS_CLUSTER = "my-vks-cluster"
  $VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

  kubectl --kubeconfig $VKS_KUBECONFIG -n gitea exec deployment/gitea -- sh -c 'P=$(head -c 15 /dev/urandom | base64); gitea admin user change-password --username gitea-admin --password $P --must-change-password && echo new password: $P'
  ```
- `FAILED: cannot run gitea in the pod`: run step 4 first, and wait for
  `successfully rolled out`.

## 6. Open Gitea

Gitea has no address outside the cluster yet. This connects port 3300 on your machine to Gitea, so
you can open its web page at <http://localhost:3300>. It runs until you press **Ctrl+C**; keep it
running for steps 7 and 8.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea port-forward service/gitea-http 3300:3000
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG -n gitea port-forward service/gitea-http 3300:3000
```

1. Open <http://localhost:3300> and **Sign In** as `gitea-admin` with the password from step 5.
2. Gitea asks you to change it: type a new password of at least 16 characters twice and
   **Update Password**.

**Expect:** `Forwarding from 127.0.0.1:3300 -> 3000`, then Gitea's dashboard for `gitea-admin`.

**If not:**
- `address already in use`, or no `127.0.0.1` line: another program uses port 3300 (Gitea's links
  expect it); stop it and run this again.
- `Username or password is incorrect`: use the line under step 5's **If not**.
- `error: lost connection to pod`: Gitea restarted; run this block again.

## 7. Create a repository by pushing to it

Run this in a second terminal while step 6 runs. It makes a local repository with a README in
`~/.config/vks-guides/gitea/hello` and pushes it; Gitea creates the private repository
`gitea-admin/hello`. Git asks for the password you set in step 6. `credential.helper=` stops git
from saving it.

**Linux, macOS, WSL (bash or zsh):**

```sh
GITEA_ADMIN_EMAIL="you@example.com"
REPO="$HOME/.config/vks-guides/gitea/hello"

if ! git -C "$REPO" rev-parse -q --verify HEAD >/dev/null 2>&1; then
  mkdir -p "$REPO" && git -C "$REPO" init -q \
    && printf '# hello\n\nMy first repository in Gitea.\n' > "$REPO/README.md" \
    && git -C "$REPO" add README.md \
    && git -C "$REPO" -c user.name=gitea-admin -c user.email="$GITEA_ADMIN_EMAIL" -c commit.gpgsign=false commit -q -m "first commit"
fi
git -C "$REPO" -c credential.helper= push http://gitea-admin@localhost:3300/gitea-admin/hello.git HEAD:main
```

**Windows (PowerShell):**

```powershell
$GITEA_ADMIN_EMAIL = "you@example.com"
$REPO = "$HOME\.config\vks-guides\gitea\hello"

$global:LASTEXITCODE = $null
git -C $REPO rev-parse -q --verify HEAD 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  New-Item -ItemType Directory -Force -Path $REPO | Out-Null
  git -C $REPO init -q
  Set-Content -Encoding Ascii -Path "$REPO\README.md" -Value "# hello`r`n`r`nMy first repository in Gitea."
  git -C $REPO add README.md
  git -C $REPO -c user.name=gitea-admin -c user.email=$GITEA_ADMIN_EMAIL -c commit.gpgsign=false commit -q -m "first commit"
}
git -C $REPO -c credential.helper= push http://gitea-admin@localhost:3300/gitea-admin/hello.git HEAD:main
```

**Expect:** `Password for 'http://gitea-admin@localhost:3300':` (some git versions first ask
`Username for 'http://localhost:3300':`; type `gitea-admin`), then after the password
`* [new branch]      HEAD -> main` (`Everything up-to-date` on a second run).
<http://localhost:3300/gitea-admin/hello> shows the README and **Private**.

**If not:**
- `Authentication failed` with `remote: Update your password` before it: finish step 6's
  password change, then push again.
- `Authentication failed` alone: the password is wrong; push again.
- `Failed to connect to localhost port 3300` or `Empty reply from server`: step 6's port-forward
  is not running or lost Gitea; run step 6 again.

## 8. Let other machines clone (optional)

This puts Gitea on a load-balancer address, port 3000, so machines outside the cluster (ArgoCD on
the Supervisor) can clone public repositories without a login. **The address is plain HTTP and
anyone who reaches it can try passwords, and anyone between it and ArgoCD can change what is
cloned.** Use it for test repositories only. Never sign in, push or send a token through it; use
step 6's `localhost:3300` for that.

1. Make the repository public: at <http://localhost:3300/gitea-admin/hello/settings>, under
   **Danger Zone**, click **Make Public**, then **Make Public** in the dialog.
2. This gives Gitea the Service `gitea-public`, an address outside the cluster on port 3000. It
   waits for the address, prints the clone address, then lists `hello` without a login, which
   shows that other machines can clone it:

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: gitea-public
  namespace: gitea
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: gitea
  ports:
    - { name: http, port: 3000, targetPort: http }
EOF
IP=""
kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea get service gitea-public -o name && for i in $(seq 60); do
  IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea get service gitea-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  [ -n "$IP" ] && break
  sleep 5
done
if [ -z "$IP" ]; then
  echo "FAILED: no load-balancer address"
else
  echo "clone address: http://$IP:3000/gitea-admin/hello.git"
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote "http://$IP:3000/gitea-admin/hello.git"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

@'
apiVersion: v1
kind: Service
metadata:
  name: gitea-public
  namespace: gitea
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: gitea
  ports:
    - { name: http, port: 3000, targetPort: http }
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
$IP = $null
$global:LASTEXITCODE = $null
kubectl --kubeconfig $VKS_KUBECONFIG -n gitea get service gitea-public -o name
if ($LASTEXITCODE -eq 0) { foreach ($i in 1..60) {
  $IP = kubectl --kubeconfig $VKS_KUBECONFIG -n gitea get service gitea-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  if ($IP) { break }
  Start-Sleep -Seconds 5
} }
if (-not $IP) {
  "FAILED: no load-balancer address"
} else {
  "clone address: http://${IP}:3000/gitea-admin/hello.git"
  $env:GIT_TERMINAL_PROMPT = '0'
  git -c credential.helper= ls-remote "http://${IP}:3000/gitea-admin/hello.git"
  Remove-Item Env:GIT_TERMINAL_PROMPT
}
```

</details>

**Expect:** `service/gitea-public created` (`unchanged` on a second run), `service/gitea-public`,
`clone address: http://<address>:3000/gitea-admin/hello.git`, then two lines with the same 40 hex
characters, ending in `HEAD` and `refs/heads/main`.

**If not:**
- `FAILED: no load-balancer address`: if an error is printed above it, fix that first. Otherwise
  `kubectl --kubeconfig <the VKS kubeconfig> -n gitea describe service gitea-public` says why;
  often the Supervisor has no free load-balancer address (ask your vCenter administrator).
- `Failed to connect` or `timed out` after the clone address: the address is new; wait a minute
  and run this again.
- git asks for a username or password, or prints `terminal prompts disabled`: the repository is
  still private. Type nothing; cancel, then do 1.

## 9. Uninstall (optional)

**This deletes every repository in this Gitea.** Delete first any ArgoCD Application that clones
from it.

This deletes the namespace `gitea`, with Gitea, its keys and its volume. It then waits until the
cluster has removed the volume, and prints how many volumes are left.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace gitea --ignore-not-found --timeout=10m
N="unknown"
for i in $(seq 36); do
  if J="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get pv -o json)"; then
    N="$(printf '%s' "$J" | jq '[.items[] | select(.spec.claimRef.namespace == "gitea")] | length')"
    [ "$N" = 0 ] && break
  elif [ "$i" = 1 ]; then
    break
  fi
  sleep 5
done
echo "volumes left from gitea: $N"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG delete namespace gitea --ignore-not-found --timeout=10m
$N = 'unknown'
foreach ($i in 1..36) {
  $PV = kubectl --kubeconfig $VKS_KUBECONFIG get pv -o json | Out-String | ConvertFrom-Json
  if ($PV) {
    $N = @($PV.items | Where-Object { $_.spec.claimRef.namespace -ceq 'gitea' }).Count
    if ($N -eq 0) { break }
  } elseif ($i -eq 1) {
    break
  }
  Start-Sleep -Seconds 5
}
"volumes left from gitea: $N"
```

</details>

**Expect:** `namespace "gitea" deleted`, then, within a few minutes,
`volumes left from gitea: 0`.

**If not:**
- `volumes left from gitea: unknown`: kubectl could not read the volumes. Fix the error above
  (often an expired login: [LOGIN.md](LOGIN.md)), then run this again.
- `volumes left from gitea:` more than 0: the storage class keeps volumes (step 1 printed
  `reclaim Retain`). Delete them with `kubectl --kubeconfig <the VKS kubeconfig> delete pv <name>`
  when you no longer need the data.

The local repository stays in `~/.config/vks-guides/gitea/hello`; delete the folder if you do not
need it.

Back to [README](../README.md).
