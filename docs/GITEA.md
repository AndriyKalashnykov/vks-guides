# Run Gitea in a VKS cluster

> [!NOTE]
> **Official Gitea, Git and Kubernetes documentation for this guide**
>
> - Gitea 28.2: [Installation with Docker (rootless)](https://docs.gitea.com/installation/install-with-docker-rootless/) (the image this guide runs), [Use environment variables to set up Gitea](https://docs.gitea.com/administration/config-cheat-sheet/#use-environment-variables-to-setup-gitea), [Configuration Cheat Sheet](https://docs.gitea.com/administration/config-cheat-sheet/)
> - Gitea 28.2: [Gitea Command Line](https://docs.gitea.com/administration/command-line/) (`gitea admin user`), [Push To Create](https://docs.gitea.com/usage/repository/push/)
> - Git: [Install](https://git-scm.com/install/), [gitcredentials](https://git-scm.com/docs/gitcredentials) (why the push turns the credential helper off)
> - Kubernetes: [Enforce Pod Security Standards with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/), [Use Port Forwarding to Access Applications in a Cluster](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)

This runs Gitea 28.2.0, a Git server with a web page, in a VKS cluster: one pod, its data in
SQLite on a 5 GiB volume. Gitea is upstream; Broadcom does not support it. You reach it through
`kubectl port-forward`; step 8 also lets other machines (such as ArgoCD on the Supervisor) clone
from it over plain HTTP. Upgrades and backups are not covered.

You need:

- a VKS cluster with a default storage class ([CLUSTER.md](CLUSTER.md)) and its kubeconfig
  ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig));
- [kubectl](KUBECTL.md), [jq and openssl](PREREQS.md), and [git](https://git-scm.com/install/);
- nodes that reach `docker.io`;
- for step 8, one free load-balancer address.

The blocks keep their files in `~/.config/vks-guides/gitea` (PowerShell:
`$HOME\.config\vks-guides\gitea`).

## 1. Check the cluster

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
  ([git-scm.com](https://git-scm.com/install/); on Photon OS 5, `sudo tdnf install -y git`), open
  a new terminal, and run this again. On macOS,
  `git` may open a dialog that installs the Command Line Tools; let it finish.
- `default storage class: NONE`: see [CLUSTER.md](CLUSTER.md) step 7.
- `gitea namespace: 1` before you ran step 2: the cluster already has a `gitea` namespace. Use
  another cluster, or remove it with step 9 if it is an earlier run of this guide.
- `FAILED: cannot read the cluster`: run
  [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig) first.

## 2. Create the namespace

Gitea runs as an ordinary user, so the namespace allows only restricted pods.

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

Gitea encrypts what it stores with a secret key, and signs calls between its own processes with an
internal token. This makes both, random, in the Secret `gitea-keys`. It never replaces them: a new
key would make what Gitea stored with the old one unreadable.

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

This creates the volume, the Gitea Deployment and a Service that only the cluster reaches, then
waits for Gitea to answer. Its web page addresses itself as `http://localhost:3300`, the port step
6 forwards. Passwords must be at least 16 characters.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
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
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

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
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
kubectl --kubeconfig $VKS_KUBECONFIG -n gitea rollout status deployment/gitea --timeout=10m
kubectl --kubeconfig $VKS_KUBECONFIG -n gitea get pvc,pods
```

</details>

**Expect:** `persistentvolumeclaim/gitea-data created`, `deployment.apps/gitea created`,
`service/gitea-http created`, then `deployment "gitea" successfully rolled out`, the claim
`Bound` and one pod `1/1 Running` (`unchanged` lines on a second run).

**If not:**
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

This forwards Gitea to port 3300 on this machine until you press **Ctrl+C**. Keep it running for
steps 7 and 8.

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
2. Create the Service `gitea-public` and wait for its address:

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

**Linux, macOS, WSL (bash or zsh):**

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

**Windows (PowerShell):**

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
