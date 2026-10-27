# Run GitLab in a VKS cluster

> [!NOTE]
> **Official GitLab, Git and Kubernetes documentation for this guide**
>
> - GitLab 19.5: [Install GitLab in a Docker container](https://docs.gitlab.com/install/docker/installation/) (the image this guide runs), [Configure GitLab running in a Docker container](https://docs.gitlab.com/install/docker/configuration/) (`GITLAB_OMNIBUS_CONFIG`), [Running GitLab in a memory-constrained environment](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/)
> - GitLab 19.5: [Reset a user's password](https://docs.gitlab.com/security/reset_user_password/) (`gitlab-rake`), [Sign-up restrictions](https://docs.gitlab.com/administration/settings/sign_up_restrictions/), [Create a project with git push](https://docs.gitlab.com/topics/git/project/), [Project visibility](https://docs.gitlab.com/user/public_access/)
> - GitLab Runner 19.5: [GitLab Runner Helm chart](https://docs.gitlab.com/runner/install/kubernetes/), [Kubernetes executor](https://docs.gitlab.com/runner/executors/kubernetes/), [Create a project runner with a runner authentication token](https://docs.gitlab.com/ci/runners/runners_scope/#create-a-project-runner-with-a-runner-authentication-token)
> - Git: [Install](https://git-scm.com/install/), [gitcredentials](https://git-scm.com/docs/gitcredentials) (why the push turns the credential helper off)
> - Kubernetes: [Enforce Pod Security Standards with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/), [Use Port Forwarding to Access Applications in a Cluster](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)

This runs GitLab Community Edition 19.5.1, a Git server with CI/CD, in a VKS cluster: one pod with
its own database, on a 20 GiB volume, and a GitLab Runner that runs each CI job as a pod. GitLab
CE is free; Broadcom does not support it. You reach it through `kubectl port-forward`; step 7 also
lets other machines (such as ArgoCD on the Supervisor) clone from it over plain HTTP. Upgrades and
backups are not covered.

> [!IMPORTANT]
> **One pod is for tests and demos.** GitLab supports its Docker image on a Docker host and, on
> Kubernetes, its [Helm chart](https://docs.gitlab.com/charts/), which needs PostgreSQL, Redis and
> object storage outside the cluster. For production, use one of those.

You need:

- a VKS cluster with a default storage class ([CLUSTER.md](CLUSTER.md)) and its kubeconfig
  ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig)), with a worker of at least 4 CPU and
  16 GiB memory (VM class `best-effort-large`): GitLab alone uses about 4 GiB;
- [kubectl](KUBECTL.md), [jq and openssl](PREREQS.md), [git](https://git-scm.com/install/), and for
  step 8 [Helm](HELM.md);
- nodes that reach `docker.io` and `registry.gitlab.com`;
- for step 7, one free load-balancer address.

Already run GitLab? Do steps 8 and 9 against it.

The blocks keep their files in `~/.config/vks-guides/gitlab` (PowerShell:
`$HOME\.config\vks-guides\gitlab`).

## 1. Check the cluster

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

git --version
if kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes \
   && N="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes -o json)" \
   && SC="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get storageclass -o json)" \
   && NS="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get namespace -o name)"; then
  printf '%s' "$N" | jq -r 'def gib: if endswith("Ki") then rtrimstr("Ki") | tonumber / 1048576 elif endswith("Mi") then rtrimstr("Mi") | tonumber / 1024 elif endswith("Gi") then rtrimstr("Gi") | tonumber else tonumber / 1073741824 end | floor;
    .items[] | "\(.metadata.name) (\(if .metadata.labels["node-role.kubernetes.io/control-plane"] == null then "worker" else "control plane" end)): \(.status.allocatable.cpu) CPU, \(.status.allocatable.memory | gib) GiB memory, \(.status.allocatable["ephemeral-storage"] | gib) GiB disk"'
  echo "default storage class: $(printf '%s' "$SC" | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | "\(.metadata.name) (\(.volumeBindingMode), reclaim \(.reclaimPolicy))"] | if length == 0 then "NONE" else join(" ") end')"
  echo "gitlab namespace: $(printf '%s\n' "$NS" | grep -cx 'namespace/gitlab')"
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
if ($LASTEXITCODE -eq 0) { $N = kubectl --kubeconfig $VKS_KUBECONFIG get nodes -o json | Out-String }
if ($LASTEXITCODE -eq 0) { $SC = kubectl --kubeconfig $VKS_KUBECONFIG get storageclass -o json | Out-String }
if ($LASTEXITCODE -eq 0) { $NS = @(kubectl --kubeconfig $VKS_KUBECONFIG get namespace -o name) }
if ($LASTEXITCODE -eq 0) {
  $GiB = { param($Q) if ($Q -match '^(\d+)Ki$') { [math]::Floor([double]$Matches[1] / 1MB) } elseif ($Q -match '^(\d+)Mi$') { [math]::Floor([double]$Matches[1] / 1KB) } elseif ($Q -match '^(\d+)Gi$') { [int]$Matches[1] } else { [math]::Floor([double]$Q / 1GB) } }
  foreach ($I in (ConvertFrom-Json $N).items) {
    $R = if ($I.metadata.labels.'node-role.kubernetes.io/control-plane' -eq $null) { 'worker' } else { 'control plane' }
    "$($I.metadata.name) (${R}): $($I.status.allocatable.cpu) CPU, $(& $GiB $I.status.allocatable.memory) GiB memory, $(& $GiB $I.status.allocatable.'ephemeral-storage') GiB disk"
  }
  $D = @((ConvertFrom-Json $SC).items | Where-Object { $_.metadata.annotations.'storageclass.kubernetes.io/is-default-class' -eq 'true' } | ForEach-Object { "$($_.metadata.name) ($($_.volumeBindingMode), reclaim $($_.reclaimPolicy))" })
  "default storage class: $(if ($D.Count) { $D -join ' ' } else { 'NONE' })"
  "gitlab namespace: $(@($NS | Where-Object { $_ -ceq 'namespace/gitlab' }).Count)"
} else {
  "FAILED: cannot read the cluster (see the error above)"
}
```

</details>

**Expect:** `git version 2.…`, each node `Ready`, at least one line `(worker): 4 CPU, 15 GiB
memory` or more, `default storage class:` and a name, and `gitlab namespace: 0`.

**If not:**
- `git: command not found` (PowerShell: `The term 'git' is not recognized`): install git
  ([git-scm.com](https://git-scm.com/install/); on Photon OS 5, `sudo tdnf install -y git`),
  open a new terminal, and run this again.
- No worker with 4 CPU and 15 GiB memory: GitLab will not start, or will be stopped when the node
  runs out of memory. Add a node pool with VM class `best-effort-large` ([CLUSTER.md](CLUSTER.md)).
- `default storage class: NONE`: see [CLUSTER.md](CLUSTER.md) step 7.
- `gitlab namespace: 1` before you ran step 2: the cluster already has a `gitlab` namespace. Use
  another cluster, or remove it with step 10 if it is an earlier run of this guide.
- `FAILED: cannot read the cluster`: run
  [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig) first.

## 2. Create the namespace

GitLab's image runs its services as root, so the namespace allows baseline pods, and warns about
anything that would not pass restricted.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: gitlab
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

@'
apiVersion: v1
kind: Namespace
metadata:
  name: gitlab
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
```

**Expect:** `namespace/gitlab created` (`unchanged` on a second run).

**If not:** `Forbidden`: your kubeconfig is not the cluster's administrator; use the one from
[LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig).

## 3. Install GitLab

This creates the volume, the GitLab StatefulSet and a Service that only the cluster reaches, waits
for GitLab to answer, then turns off sign-up, so only users you create can log in. The first start
downloads a 1.5 GB image and sets up the database: allow 5 to 15 minutes.

GitLab addresses itself as `http://gitlab.gitlab.svc.cluster.local`, its name inside the cluster,
so the runner (step 8) reaches it directly. Your browser reaches it through step 5's port-forward.
The settings run GitLab with less memory: one web process, ten background threads, and no
built-in Prometheus or agent server.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitlab-data
  namespace: gitlab
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitlab
  namespace: gitlab
  labels:
    app.kubernetes.io/name: gitlab
spec:
  serviceName: gitlab
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: gitlab
  template:
    metadata:
      labels:
        app.kubernetes.io/name: gitlab
    spec:
      automountServiceAccountToken: false
      enableServiceLinks: false
      terminationGracePeriodSeconds: 120
      containers:
        - name: gitlab
          image: docker.io/gitlab/gitlab-ce:19.5.1-ce.0@sha256:bb79dc86267c557fd11e7feb0cd9dd506dd02e991ecdd6cae11ca7d7e5d36fc3
          env:
            - { name: GITLAB_DISABLE_OPENSSH, value: "true" }
            - { name: GITLAB_SKIP_TAIL_LOGS, value: "true" }
            - name: GITLAB_OMNIBUS_CONFIG
              value: |
                external_url 'http://gitlab.gitlab.svc.cluster.local'
                puma['worker_processes'] = 0
                sidekiq['concurrency'] = 10
                prometheus_monitoring['enable'] = false
                gitlab_kas['enable'] = false
                gitlab_rails['store_initial_root_password'] = false
          ports:
            - { name: http, containerPort: 80 }
          startupProbe:
            exec: { command: ["curl", "-fsS", "--max-time", "5", "http://127.0.0.1/-/readiness"] }
            periodSeconds: 10
            timeoutSeconds: 10
            failureThreshold: 180
          readinessProbe:
            exec: { command: ["curl", "-fsS", "--max-time", "5", "http://127.0.0.1/-/readiness"] }
            periodSeconds: 15
            timeoutSeconds: 10
          livenessProbe:
            exec: { command: ["curl", "-fsS", "--max-time", "5", "http://127.0.0.1/-/liveness"] }
            periodSeconds: 20
            timeoutSeconds: 10
          resources:
            requests: { cpu: "1", memory: 4Gi }
            limits: { memory: 6Gi }
          volumeMounts:
            - { name: data, mountPath: /etc/gitlab, subPath: etc }
            - { name: data, mountPath: /var/opt/gitlab, subPath: opt }
            - { name: data, mountPath: /var/log/gitlab, subPath: log }
            - { name: shm, mountPath: /dev/shm }
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: gitlab-data
        - name: shm
          emptyDir: { medium: Memory, sizeLimit: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: gitlab
  namespace: gitlab
spec:
  selector:
    app.kubernetes.io/name: gitlab
  ports:
    - { name: http, port: 80, targetPort: http }
EOF
kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab rollout status statefulset/gitlab --timeout=30m \
  && kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab exec gitlab-0 -- gitlab-rails runner '::Gitlab::CurrentSettings.update!(signup_enabled: false); p signup_enabled: ::Gitlab::CurrentSettings.signup_enabled?'
kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab get pvc,pods
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
  name: gitlab-data
  namespace: gitlab
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitlab
  namespace: gitlab
  labels:
    app.kubernetes.io/name: gitlab
spec:
  serviceName: gitlab
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: gitlab
  template:
    metadata:
      labels:
        app.kubernetes.io/name: gitlab
    spec:
      automountServiceAccountToken: false
      enableServiceLinks: false
      terminationGracePeriodSeconds: 120
      containers:
        - name: gitlab
          image: docker.io/gitlab/gitlab-ce:19.5.1-ce.0@sha256:bb79dc86267c557fd11e7feb0cd9dd506dd02e991ecdd6cae11ca7d7e5d36fc3
          env:
            - { name: GITLAB_DISABLE_OPENSSH, value: "true" }
            - { name: GITLAB_SKIP_TAIL_LOGS, value: "true" }
            - name: GITLAB_OMNIBUS_CONFIG
              value: |
                external_url 'http://gitlab.gitlab.svc.cluster.local'
                puma['worker_processes'] = 0
                sidekiq['concurrency'] = 10
                prometheus_monitoring['enable'] = false
                gitlab_kas['enable'] = false
                gitlab_rails['store_initial_root_password'] = false
          ports:
            - { name: http, containerPort: 80 }
          startupProbe:
            exec: { command: ["curl", "-fsS", "--max-time", "5", "http://127.0.0.1/-/readiness"] }
            periodSeconds: 10
            timeoutSeconds: 10
            failureThreshold: 180
          readinessProbe:
            exec: { command: ["curl", "-fsS", "--max-time", "5", "http://127.0.0.1/-/readiness"] }
            periodSeconds: 15
            timeoutSeconds: 10
          livenessProbe:
            exec: { command: ["curl", "-fsS", "--max-time", "5", "http://127.0.0.1/-/liveness"] }
            periodSeconds: 20
            timeoutSeconds: 10
          resources:
            requests: { cpu: "1", memory: 4Gi }
            limits: { memory: 6Gi }
          volumeMounts:
            - { name: data, mountPath: /etc/gitlab, subPath: etc }
            - { name: data, mountPath: /var/opt/gitlab, subPath: opt }
            - { name: data, mountPath: /var/log/gitlab, subPath: log }
            - { name: shm, mountPath: /dev/shm }
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: gitlab-data
        - name: shm
          emptyDir: { medium: Memory, sizeLimit: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: gitlab
  namespace: gitlab
spec:
  selector:
    app.kubernetes.io/name: gitlab
  ports:
    - { name: http, port: 80, targetPort: http }
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab rollout status statefulset/gitlab --timeout=30m
if ($LASTEXITCODE -eq 0) {
  kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab exec gitlab-0 -- gitlab-rails runner '::Gitlab::CurrentSettings.update!(signup_enabled: false); p signup_enabled: ::Gitlab::CurrentSettings.signup_enabled?'
}
kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab get pvc,pods
```

</details>

**Expect:** a `Warning: would violate PodSecurity "restricted:latest"` line (GitLab runs as root;
baseline allows it), `persistentvolumeclaim/gitlab-data created`,
`statefulset.apps/gitlab created`, `service/gitlab created`, then
`statefulset rolling update complete`, `{:signup_enabled=>false}`, the claim `Bound` and the pod
`gitlab-0` `1/1 Running` (`unchanged` lines on a second run).

**If not:**
- The claim stays `Pending`: the storage class cannot make the volume. `kubectl --kubeconfig <the
  VKS kubeconfig> -n gitlab describe pvc gitlab-data` says why; often the vSphere Namespace's
  storage limit is reached.
- The pod is `Pending` with `Insufficient memory`: no worker has 4 GiB free; see step 1.
- The pod is `ErrImagePull` or `ImagePullBackOff`: `kubectl --kubeconfig <the VKS kubeconfig> -n
  gitlab describe pod gitlab-0` says why: the nodes cannot reach `docker.io`, `toomanyrequests`
  (Docker Hub's pull limit; wait and run this again), or `no space left on device` (the node's
  disk is too small for the image).
- The pod restarts with `OOMKilled`: the node has too little free memory; see step 1.
- `timed out waiting for the condition`: run `kubectl --kubeconfig <the VKS kubeconfig> -n gitlab
  logs gitlab-0` and look for the first error.

## 4. Set the root password

GitLab's administrator is `root`, and no one knows its password yet. This asks you for one, twice,
inside the GitLab pod; it is not shown, saved, or put on a command line. Use at least 8 characters
that are not a common word.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab exec -it gitlab-0 -- gitlab-rake "gitlab:password:reset[root]"
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab exec -it gitlab-0 -- gitlab-rake "gitlab:password:reset[root]"
```

**Expect:** after a few seconds `Enter password:`, then `Confirm password:`, then
`Password successfully updated for user with username root.`

**If not:**
- `Unable to update password of user with username root.` followed by a reason, such as
  `Password is too short` or `Password must not contain commonly used combinations`: run this
  again with another password.
- `Passwords do not match`: run this again.
- `pods "gitlab-0" not found` or `container not found`: run step 3 first.

You can run this again at any time to set a new root password.

## 5. Open GitLab

This forwards GitLab to port 3400 on this machine until you press **Ctrl+C**. Keep it running for
steps 6 to 9.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab port-forward service/gitlab 3400:80
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab port-forward service/gitlab 3400:80
```

Open <http://localhost:3400> and sign in as `root` with the password from step 4.

**Expect:** `Forwarding from 127.0.0.1:3400 -> 80`, then GitLab's home page for `root`. The sign-in
page has no **Register now** link.

**If not:**
- `address already in use`, or no `127.0.0.1` line: another program uses port 3400; stop it and
  run this again.
- `Invalid login or password`: set the password again with step 4.
- `error: lost connection to pod`: GitLab restarted; run this block again.

## 6. Create a project by pushing to it

Run this in a second terminal while step 5 runs. It makes a local repository with a README in
`~/.config/vks-guides/gitlab/hello` and pushes it; GitLab creates the private project
`root/hello`. Git asks for the root password. `credential.helper=` stops git from saving it. Set
`GITLAB_EMAIL` to your email address; it only labels the commit.

**Linux, macOS, WSL (bash or zsh):**

```sh
GITLAB_EMAIL="you@example.com"
REPO="$HOME/.config/vks-guides/gitlab/hello"

if ! git -C "$REPO" rev-parse -q --verify HEAD >/dev/null 2>&1; then
  mkdir -p "$REPO" && git -C "$REPO" init -q \
    && printf '# hello\n\nMy first project in GitLab.\n' > "$REPO/README.md" \
    && git -C "$REPO" add README.md \
    && git -C "$REPO" -c user.name=root -c user.email="$GITLAB_EMAIL" -c commit.gpgsign=false commit -q -m "first commit"
fi
git -C "$REPO" -c credential.helper= push http://root@localhost:3400/root/hello.git HEAD:main
```

**Windows (PowerShell):**

```powershell
$GITLAB_EMAIL = "you@example.com"
$REPO = "$HOME\.config\vks-guides\gitlab\hello"

$global:LASTEXITCODE = $null
git -C $REPO rev-parse -q --verify HEAD 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  New-Item -ItemType Directory -Force -Path $REPO | Out-Null
  git -C $REPO init -q
  Set-Content -Encoding Ascii -Path "$REPO\README.md" -Value "# hello`r`n`r`nMy first project in GitLab."
  git -C $REPO add README.md
  git -C $REPO -c user.name=root -c user.email=$GITLAB_EMAIL -c commit.gpgsign=false commit -q -m "first commit"
}
git -C $REPO -c credential.helper= push http://root@localhost:3400/root/hello.git HEAD:main
```

**Expect:** `Password for 'http://root@localhost:3400':` (some git versions first ask
`Username for 'http://localhost:3400':`; type `root`), then after the password
`remote: The private project root/hello was successfully created.` and
`* [new branch]      HEAD -> main` (`Everything up-to-date` on a second run).
<http://localhost:3400/root/hello> shows the README and a lock (**Private**).

**If not:**
- `HTTP Basic: Access denied`: the password is wrong; push again.
- `Failed to connect to localhost port 3400` or `Empty reply from server`: step 5's port-forward
  is not running or lost GitLab; run step 5 again.

## 7. Let other machines clone (optional)

This puts GitLab on a load-balancer address, port 80, so machines outside the cluster (ArgoCD on
the Supervisor) can clone public projects without a login. **The address is plain HTTP and anyone
who reaches it can try passwords, and anyone between it and ArgoCD can change what is cloned.**
Use it for test projects only. Never sign in, push or send a token through it; use step 5's
`localhost:3400` for that.

1. Make the project public: at <http://localhost:3400/root/hello/edit>, expand **Visibility,
   project features, permissions**, set **Project visibility** to **Public**, and click **Save
   changes**.
2. Create the Service `gitlab-public` and wait for its address:

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: gitlab-public
  namespace: gitlab
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: gitlab
  ports:
    - { name: http, port: 80, targetPort: http }
EOF
IP=""
kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab get service gitlab-public -o name && for i in $(seq 60); do
  IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab get service gitlab-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  [ -n "$IP" ] && break
  sleep 5
done
if [ -z "$IP" ]; then
  echo "FAILED: no load-balancer address"
else
  echo "clone address: http://$IP/root/hello.git"
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote "http://$IP/root/hello.git"
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
  name: gitlab-public
  namespace: gitlab
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: gitlab
  ports:
    - { name: http, port: 80, targetPort: http }
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
$IP = $null
$global:LASTEXITCODE = $null
kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab get service gitlab-public -o name
if ($LASTEXITCODE -eq 0) { foreach ($i in 1..60) {
  $IP = kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab get service gitlab-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  if ($IP) { break }
  Start-Sleep -Seconds 5
} }
if (-not $IP) {
  "FAILED: no load-balancer address"
} else {
  "clone address: http://${IP}/root/hello.git"
  $env:GIT_TERMINAL_PROMPT = '0'
  git -c credential.helper= ls-remote "http://${IP}/root/hello.git"
  Remove-Item Env:GIT_TERMINAL_PROMPT
}
```

</details>

**Expect:** `service/gitlab-public created` (`unchanged` on a second run), `service/gitlab-public`,
`clone address: http://<address>/root/hello.git`, then two lines with the same 40 hex characters,
ending in `HEAD` and `refs/heads/main`.

**If not:**
- `FAILED: no load-balancer address`: if an error is printed above it, fix that first. Otherwise
  `kubectl --kubeconfig <the VKS kubeconfig> -n gitlab describe service gitlab-public` says why;
  often the Supervisor has no free load-balancer address (ask your vCenter administrator).
- `Failed to connect` or `timed out` after the clone address: the address is new; wait a minute
  and run this again.
- `terminal prompts disabled` or `Authentication failed`: the project is still private; do 1.

## 8. Install a runner

GitLab runs CI jobs on runners. This installs one, GitLab Runner 19.5.1, in the namespace
`gitlab-runner`; it starts each job as a pod there. The runner takes only jobs from the project
`root/hello` that carry the tag `vks`.

1. In GitLab, open <http://localhost:3400/root/hello/-/runners/new>. Under **Tags** type `vks`,
   leave **Run untagged jobs** cleared, and click **Create runner**.
2. GitLab shows a **Runner authentication token** that starts with `glrt-`, once. Copy it.
3. In the terminal you will install from, run this and paste the token at the prompt (it is not
   shown):

   **Linux, macOS, WSL (bash or zsh):**

   ```sh
   printf 'Runner token: '; IFS= read -rs RUNNER_TOKEN; echo
   ```

   **Windows (PowerShell):**

   ```powershell
   $RUNNER_TOKEN = Read-Host 'Runner token' -AsSecureString
   ```

   **Expect:** a new prompt. The token stays in this terminal until the next block clears it.

4. In the same terminal, run the block below. It keeps the token only in the Secret
   `gitlab-runner-token`, downloads the runner's Helm chart 0.94.1 and checks its SHA-256, then
   installs it. Set `GITLAB_URL` to your GitLab's address if it is not the one from step 3.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
GITLAB_URL="http://gitlab.gitlab.svc.cluster.local"
GITLAB_DIR="$HOME/.config/vks-guides/gitlab"
CHART_SHA256="2403187ea4f50199814f22019b6a3a88b271dcfe67d26bd44c6d93b47065ffad"

CHART="$GITLAB_DIR/gitlab-runner-0.94.1.tgz"
URL="https://gitlab-charts.s3.amazonaws.com/gitlab-runner-0.94.1.tgz"
mkdir -p "$GITLAB_DIR"
cat > "$GITLAB_DIR/runner-values.yaml" <<'EOF'
image:
  registry: registry.gitlab.com
  repository: gitlab-org/gitlab-runner
  tag: alpine-v19.5.1@sha256:86a371df46b076bb4c510bca1751d428177d2567bd88e4047613bc7fa92d1a0e
rbac:
  create: true
  rules:
    - resources: ["events"]
      verbs: ["get", "list", "watch"]
    - resources: ["pods"]
      verbs: ["create", "delete", "get", "list", "watch"]
    - apiGroups: [""]
      resources: ["pods/attach", "pods/exec"]
      verbs: ["get", "create", "patch", "delete"]
    - apiGroups: [""]
      resources: ["pods/log"]
      verbs: ["get", "list"]
    - resources: ["secrets"]
      verbs: ["create", "delete", "get", "update"]
    - resources: ["serviceaccounts"]
      verbs: ["get"]
serviceAccount:
  create: true
podSecurityContext:
  runAsUser: 100
  fsGroup: 65533
  seccompProfile:
    type: RuntimeDefault
runners:
  secret: gitlab-runner-token
  config: |
    [[runners]]
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "docker.io/library/alpine:3.22.2@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412"
        helper_image = "registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.5.1@sha256:ca7cc8f66a6c6931281aa2ae974b62f80111a4f578cabc442b1d39388a0dee91"
        automount_service_account_token = false
        cpu_request = "500m"
        memory_request = "1Gi"
        memory_limit = "3Gi"
EOF
case "$RUNNER_TOKEN" in glrt-?*) BAD="" ;; *) BAD=1 ;; esac
[ -z "$(printf '%s' "$RUNNER_TOKEN" | LC_ALL=C tr -d 'A-Za-z0-9._-')" ] || BAD=1
if [ -n "$BAD" ]; then
  echo "FAILED: no runner token starting with glrt- in this terminal; do 3, then run this again"
elif ! printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: gitlab-runner\n  labels:\n    pod-security.kubernetes.io/enforce: baseline\n    pod-security.kubernetes.io/audit: restricted\n    pod-security.kubernetes.io/warn: restricted\n' \
    | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f -; then
  echo "FAILED: cannot create the namespace (see the error above)"
elif ! printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: gitlab-runner-token\n  namespace: gitlab-runner\nstringData:\n  runner-token: %s\n  runner-registration-token: ""\n' "$RUNNER_TOKEN" \
    | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f -; then
  echo "FAILED: cannot store the token (see the error above)"
elif ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" "$URL"; then
  echo "FAILED: download of $URL"
elif [ "$( (sha256sum "$CHART.new" 2>/dev/null || shasum -a 256 "$CHART.new") | cut -d' ' -f1)" != "$CHART_SHA256" ]; then
  echo "FAILED: checksum mismatch for $URL"
else
  mv "$CHART.new" "$CHART"
  helm upgrade --install gitlab-runner "$CHART" --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner -f "$GITLAB_DIR/runner-values.yaml" --set gitlabUrl="$GITLAB_URL" --wait --timeout 10m >/dev/null \
    && helm list --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitlab-runner get pods
fi
unset RUNNER_TOKEN
rm -f "$CHART.new"
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
$URL = "https://gitlab-charts.s3.amazonaws.com/gitlab-runner-0.94.1.tgz"
New-Item -ItemType Directory -Force -Path $GITLAB_DIR | Out-Null
$V = @'
image:
  registry: registry.gitlab.com
  repository: gitlab-org/gitlab-runner
  tag: alpine-v19.5.1@sha256:86a371df46b076bb4c510bca1751d428177d2567bd88e4047613bc7fa92d1a0e
rbac:
  create: true
  rules:
    - resources: ["events"]
      verbs: ["get", "list", "watch"]
    - resources: ["pods"]
      verbs: ["create", "delete", "get", "list", "watch"]
    - apiGroups: [""]
      resources: ["pods/attach", "pods/exec"]
      verbs: ["get", "create", "patch", "delete"]
    - apiGroups: [""]
      resources: ["pods/log"]
      verbs: ["get", "list"]
    - resources: ["secrets"]
      verbs: ["create", "delete", "get", "update"]
    - resources: ["serviceaccounts"]
      verbs: ["get"]
serviceAccount:
  create: true
podSecurityContext:
  runAsUser: 100
  fsGroup: 65533
  seccompProfile:
    type: RuntimeDefault
runners:
  secret: gitlab-runner-token
  config: |
    [[runners]]
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "docker.io/library/alpine:3.22.2@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412"
        helper_image = "registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.5.1@sha256:ca7cc8f66a6c6931281aa2ae974b62f80111a4f578cabc442b1d39388a0dee91"
        automount_service_account_token = false
        cpu_request = "500m"
        memory_request = "1Gi"
        memory_limit = "3Gi"
'@
[IO.File]::WriteAllText("$GITLAB_DIR\runner-values.yaml", ($V -replace "`r`n", "`n") + "`n")
$T = if ($RUNNER_TOKEN) { [Net.NetworkCredential]::new('', $RUNNER_TOKEN).Password }
$global:LASTEXITCODE = $null
if ($T -cnotmatch '^glrt-[A-Za-z0-9._-]+$') {
  "FAILED: no runner token starting with glrt- in this terminal; do 3, then run this again"
} else {
  "apiVersion: v1`nkind: Namespace`nmetadata:`n  name: gitlab-runner`n  labels:`n    pod-security.kubernetes.io/enforce: baseline`n    pod-security.kubernetes.io/audit: restricted`n    pod-security.kubernetes.io/warn: restricted`n" |
    kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
  if ($LASTEXITCODE -eq 0) {
    "apiVersion: v1`nkind: Secret`nmetadata:`n  name: gitlab-runner-token`n  namespace: gitlab-runner`nstringData:`n  runner-token: $T`n  runner-registration-token: `"`"`n" |
      kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
  }
  if ($LASTEXITCODE -ne 0) {
    "FAILED: cannot store the token (see the error above)"
  } else {
    curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" $URL
    if ($LASTEXITCODE -ne 0) {
      "FAILED: download of $URL"
    } elseif ((Get-FileHash -Algorithm SHA256 "$CHART.new").Hash -ne $CHART_SHA256) {
      "FAILED: checksum mismatch for $URL"
    } else {
      Move-Item -Force "$CHART.new" $CHART
      helm upgrade --install gitlab-runner $CHART --kubeconfig $VKS_KUBECONFIG -n gitlab-runner -f "$GITLAB_DIR\runner-values.yaml" --set gitlabUrl=$GITLAB_URL --wait --timeout 10m | Out-Null
      if ($LASTEXITCODE -eq 0) { helm list --kubeconfig $VKS_KUBECONFIG -n gitlab-runner }
      if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n gitlab-runner get pods }
    }
  }
}
Remove-Variable -ErrorAction SilentlyContinue RUNNER_TOKEN, T
Remove-Item -Force -ErrorAction SilentlyContinue "$CHART.new"
```

</details>

**Expect:** `namespace/gitlab-runner created`, `secret/gitlab-runner-token created` (`configured`
or `unchanged` on a second run), a line for the release `gitlab-runner` with `STATUS deployed`, and
one pod `1/1 Running`. Within a minute, <http://localhost:3400/root/hello/-/settings/ci_cd> under
**Runners** shows the runner with a green dot (online).

**If not:**
- `FAILED: no runner token …`: do 3 in this terminal, pasting the whole token from `glrt-` on.
  If you lost it, create another runner (1 and 2) and delete the old one on the same page.
- `helm: command not found`: install Helm ([HELM.md](HELM.md)).
- `FAILED: download …`: this machine cannot reach `gitlab-charts.s3.amazonaws.com`.
- `FAILED: checksum mismatch …`: the download arrived damaged, or the chart was rebuilt. Do not
  install it; run the block again.
- `context deadline exceeded`, or the runner stays offline: `kubectl --kubeconfig <the VKS
  kubeconfig> -n gitlab-runner logs deployment/gitlab-runner` says why. `403 Forbidden` there means
  the token is wrong or the runner was deleted in GitLab: do 1 and 2 again and run this again.

## 9. Run a pipeline

This adds a `.gitlab-ci.yml` with one job to `root/hello` and pushes it; GitLab starts a pipeline
and the runner runs the job as a pod. Run it in the second terminal, with step 5 running. Git asks
for the root password.

**Linux, macOS, WSL (bash or zsh):**

```sh
GITLAB_EMAIL="you@example.com"
REPO="$HOME/.config/vks-guides/gitlab/hello"

cat > "$REPO/.gitlab-ci.yml" <<'EOF'
hello:
  tags: [vks]
  script:
    - echo "hello from pod $HOSTNAME"
EOF
git -C "$REPO" add .gitlab-ci.yml \
  && { git -C "$REPO" diff --cached --quiet \
       || git -C "$REPO" -c user.name=root -c user.email="$GITLAB_EMAIL" -c commit.gpgsign=false commit -q -m "add a pipeline"; } \
  && git -C "$REPO" -c credential.helper= push http://root@localhost:3400/root/hello.git HEAD:main
```

**Windows (PowerShell):**

```powershell
$GITLAB_EMAIL = "you@example.com"
$REPO = "$HOME\.config\vks-guides\gitlab\hello"

[IO.File]::WriteAllText("$REPO\.gitlab-ci.yml", "hello:`n  tags: [vks]`n  script:`n    - echo `"hello from pod `$HOSTNAME`"`n")
$global:LASTEXITCODE = $null
git -C $REPO add .gitlab-ci.yml
if ($LASTEXITCODE -eq 0) {
  git -C $REPO diff --cached --quiet
  if ($LASTEXITCODE -ne 0) { git -C $REPO -c user.name=root -c user.email=$GITLAB_EMAIL -c commit.gpgsign=false commit -q -m "add a pipeline" }
  git -C $REPO -c credential.helper= push http://root@localhost:3400/root/hello.git HEAD:main
}
```

**Expect:** after the password, `main -> main`. At <http://localhost:3400/root/hello/-/pipelines>
the newest pipeline turns **Passed** within a minute or two; its job `hello` prints
`hello from pod runner-…` and `Job succeeded`.

**If not:**
- The pipeline stays **Pending** with `This job is stuck`: the runner is offline or lacks the tag
  `vks`; see step 8.
- The job fails with `ImagePullBackOff` or `pull access denied`: the nodes cannot reach
  `docker.io` or `registry.gitlab.com`.
- `Everything up-to-date` and no new pipeline: the file was pushed before. Run a pipeline again
  from the pipelines page with **New pipeline**, then **New pipeline**.

## 10. Uninstall (optional)

Uninstall the runner first, then GitLab. If your GitLab runs elsewhere, uninstall only the runner,
and delete the runner in GitLab at <http://localhost:3400/root/hello/-/settings/ci_cd> (your
GitLab's address), under **Runners**.

### The runner

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace gitlab-runner --ignore-not-found --timeout=10m
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG delete namespace gitlab-runner --ignore-not-found --timeout=10m
```

**Expect:** `namespace "gitlab-runner" deleted` (nothing on a second run).

### GitLab

**This deletes every project in this GitLab.** Delete first any ArgoCD Application that clones
from it.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace gitlab --ignore-not-found --timeout=10m
N="unknown"
for i in $(seq 36); do
  if J="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get pv -o json)"; then
    N="$(printf '%s' "$J" | jq '[.items[] | select(.spec.claimRef.namespace == "gitlab")] | length')"
    [ "$N" = 0 ] && break
  elif [ "$i" = 1 ]; then
    break
  fi
  sleep 5
done
echo "volumes left from gitlab: $N"
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG delete namespace gitlab --ignore-not-found --timeout=10m
$N = 'unknown'
foreach ($i in 1..36) {
  $PV = kubectl --kubeconfig $VKS_KUBECONFIG get pv -o json | Out-String | ConvertFrom-Json
  if ($PV) {
    $N = @($PV.items | Where-Object { $_.spec.claimRef.namespace -ceq 'gitlab' }).Count
    if ($N -eq 0) { break }
  } elseif ($i -eq 1) {
    break
  }
  Start-Sleep -Seconds 5
}
"volumes left from gitlab: $N"
```

**Expect:** `namespace "gitlab" deleted`, then, within a few minutes,
`volumes left from gitlab: 0`.

**If not:**
- `volumes left from gitlab: unknown`: kubectl could not read the volumes. Fix the error above
  (often an expired login: [LOGIN.md](LOGIN.md)), then run this again.
- `volumes left from gitlab:` more than 0: the storage class keeps volumes (step 1 printed
  `reclaim Retain`). Delete them with `kubectl --kubeconfig <the VKS kubeconfig> delete pv <name>`
  when you no longer need the data.

The local repository and the runner chart stay in `~/.config/vks-guides/gitlab`; delete the folder
if you do not need them.

Back to [README](../README.md).
