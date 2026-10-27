# Run Tekton in a VKS cluster

> [!NOTE]
> **Official Tekton and Kubernetes documentation for this guide**
>
> - Tekton: [Install Tekton Pipelines](https://tekton.dev/docs/installation/pipelines/), [Install and set up Tekton Triggers](https://tekton.dev/docs/installation/triggers/), releases [Pipelines v1.17.1](https://github.com/tektoncd/pipeline/releases/tag/v1.17.1) and [Triggers v0.37.2](https://github.com/tektoncd/triggers/releases/tag/v0.37.2)
> - Tekton: [Tasks](https://tekton.dev/docs/pipelines/tasks/), [Pipelines](https://tekton.dev/docs/pipelines/pipelines/), [PipelineRuns](https://tekton.dev/docs/pipelines/pipelineruns/), [Additional Configuration Options](https://tekton.dev/docs/pipelines/additional-configs/) (restricted pod security)
> - Tekton: [EventListeners](https://tekton.dev/docs/triggers/eventlisteners/), [TriggerBindings](https://tekton.dev/docs/triggers/triggerbindings/), [TriggerTemplates](https://tekton.dev/docs/triggers/triggertemplates/)
> - Kubernetes: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/), [Use Port Forwarding to Access Applications in a Cluster](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)

This installs Tekton Pipelines 1.17.1 and Tekton Triggers 0.37.2, a CI/CD engine that runs each
step of a build as a pod, into a VKS cluster. It then runs a two-task pipeline, and starts it again
from an HTTP request through an EventListener. Tekton is upstream; Broadcom does not support it.
Everything here uses `kubectl`; Tekton's own `tkn` program is not needed.

You need:

- a VKS cluster ([CLUSTER.md](CLUSTER.md)) and its kubeconfig
  ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig));
- [kubectl](KUBECTL.md), and [curl and jq](PREREQS.md);
- about 200m of free CPU on the workers, at least 100m on one worker for each of Tekton's two
  pods that ask for CPU (step 1 shows it);
- nodes that reach `ghcr.io` (and `pkg-containers.githubusercontent.com`) for Tekton's images and
  `cgr.dev` for the demo's; a machine that reaches `github.com` and
  `release-assets.githubusercontent.com`.

The blocks keep their files in `~/.config/vks-guides/tekton` (PowerShell:
`$HOME\.config\vks-guides\tekton`).

## 1. Check the cluster

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

if kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes \
   && N="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers -o 'custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu')" \
   && P="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get pods -A --field-selector=status.phase!=Succeeded,status.phase!=Failed --no-headers -o 'custom-columns=NODE:.spec.nodeName,CPU:.spec.containers[*].resources.requests.cpu')" \
   && C="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)"; then
  { printf '%s\n' "$P" | sed 's/^/P /'; printf '%s\n' "$N" | sed 's/^/N /'; } | awk '
    function m(v) { if (v ~ /m$/) return substr(v, 1, length(v) - 1) + 0; return v * 1000 }
    $1 == "P" { n = split($3, a, ","); for (i = 1; i <= n; i++) if (a[i] != "<none>") r[$2] += m(a[i]) }
    $1 == "N" { printf "worker %s: %dm CPU free\n", $2, m($3) - r[$2] }'
  echo "Tekton installed: $(printf '%s\n' "$C" | grep -c '\.tekton\.dev$')"
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

function M($v) { if ($v -like '*m') { [double]$v.TrimEnd('m') } else { [double]$v * 1000 } }
$global:LASTEXITCODE = $null
kubectl --kubeconfig $VKS_KUBECONFIG get nodes
if ($LASTEXITCODE -eq 0) { $N = @(kubectl --kubeconfig $VKS_KUBECONFIG get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers -o 'custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu') }
if ($LASTEXITCODE -eq 0) { $P = @(kubectl --kubeconfig $VKS_KUBECONFIG get pods -A --field-selector=status.phase!=Succeeded,status.phase!=Failed --no-headers -o 'custom-columns=NODE:.spec.nodeName,CPU:.spec.containers[*].resources.requests.cpu') }
if ($LASTEXITCODE -eq 0) { $C = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name) }
if ($LASTEXITCODE -eq 0) {
  $R = @{}
  foreach ($l in $P) {
    $f = -split $l
    foreach ($c in ($f[1] -split ',')) { if ($c -and $c -ne '<none>') { $R[$f[0]] += (M $c) } }
  }
  foreach ($l in $N) { $f = -split $l; "worker $($f[0]): $((M $f[1]) - $R[$f[0]])m CPU free" }
  "Tekton installed: $(@($C | Where-Object { $_ -match '\.tekton\.dev$' }).Count)"
} else {
  "FAILED: cannot read the cluster (see the error above)"
}
```

</details>

**Expect:** each node `Ready`, a `worker …: …m CPU free` line per worker, and
`Tekton installed: 0`. Tekton needs 100m free on a worker for each of its two pods: one worker
with 200m, or two with 100m each.

**If not:**
- Less free CPU: add a worker or use a larger VM class ([CLUSTER.md](CLUSTER.md)), or remove
  something you no longer need from the cluster.
- `Tekton installed:` more than 0: the cluster already has Tekton. Use it, or another cluster;
  this guide does not cover both.
- `FAILED: cannot read the cluster`: run
  [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig) first.

## 2. Download Tekton

This downloads the three release files and checks their SHA-256.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
TEKTON_DIR="$HOME/.config/vks-guides/tekton"

mkdir -p "$TEKTON_DIR"
while read -r NAME SUM URL; do
  if ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$TEKTON_DIR/$NAME.new" "$URL"; then
    echo "FAILED: download of $URL"
  elif [ "$( (sha256sum "$TEKTON_DIR/$NAME.new" 2>/dev/null || shasum -a 256 "$TEKTON_DIR/$NAME.new") | cut -d' ' -f1)" != "$SUM" ]; then
    echo "FAILED: checksum mismatch for $URL"
  else
    mv "$TEKTON_DIR/$NAME.new" "$TEKTON_DIR/$NAME" && echo "ok $NAME"
  fi
  rm -f "$TEKTON_DIR/$NAME.new"
done <<'EOF'
tekton-pipelines-v1.17.1.yaml 0055828f2bb1db912afab833df6034b7577541b1d34c4cb66e302e0075ac71ce https://github.com/tektoncd/pipeline/releases/download/v1.17.1/release.yaml
tekton-triggers-v0.37.2.yaml c4113c01e977e313d0223b2a0eab5ba0f9be01c618cb0421b5c0a9fc9d46d426 https://github.com/tektoncd/triggers/releases/download/v0.37.2/release.yaml
tekton-interceptors-v0.37.2.yaml cf2a59a98817d97c8112138186b4a8ca4f90a84a80748dc77db348aa080c5baa https://github.com/tektoncd/triggers/releases/download/v0.37.2/interceptors.yaml
EOF
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$TEKTON_DIR = "$HOME\.config\vks-guides\tekton"

New-Item -ItemType Directory -Force -Path $TEKTON_DIR | Out-Null
$FILES = @(
  @('tekton-pipelines-v1.17.1.yaml', '0055828f2bb1db912afab833df6034b7577541b1d34c4cb66e302e0075ac71ce', 'https://github.com/tektoncd/pipeline/releases/download/v1.17.1/release.yaml'),
  @('tekton-triggers-v0.37.2.yaml', 'c4113c01e977e313d0223b2a0eab5ba0f9be01c618cb0421b5c0a9fc9d46d426', 'https://github.com/tektoncd/triggers/releases/download/v0.37.2/release.yaml'),
  @('tekton-interceptors-v0.37.2.yaml', 'cf2a59a98817d97c8112138186b4a8ca4f90a84a80748dc77db348aa080c5baa', 'https://github.com/tektoncd/triggers/releases/download/v0.37.2/interceptors.yaml')
)
foreach ($F in $FILES) {
  $NAME, $SUM, $URL = $F
  $global:LASTEXITCODE = $null
  curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$TEKTON_DIR\$NAME.new" $URL
  if ($LASTEXITCODE -ne 0) {
    "FAILED: download of $URL"
  } elseif ((Get-FileHash -Algorithm SHA256 "$TEKTON_DIR\$NAME.new").Hash -ne $SUM) {
    "FAILED: checksum mismatch for $URL"
  } else {
    Move-Item -Force "$TEKTON_DIR\$NAME.new" "$TEKTON_DIR\$NAME"
    "ok $NAME"
  }
  Remove-Item -Force -ErrorAction SilentlyContinue "$TEKTON_DIR\$NAME.new"
}
```

</details>

**Expect:** `ok tekton-pipelines-v1.17.1.yaml`, `ok tekton-triggers-v0.37.2.yaml` and
`ok tekton-interceptors-v0.37.2.yaml`.

**If not:**
- `FAILED: download …`: this machine cannot reach `github.com` or
  `release-assets.githubusercontent.com`.
- `FAILED: checksum mismatch …`: the download arrived damaged, or the release was rebuilt. Do not
  install it; run the block again.

## 3. Install Tekton

This installs Pipelines, waits for it, then installs Triggers and its interceptors and waits
again. Triggers restarts a few times until its interceptors are in; that is expected. It can take
several minutes while the nodes pull the images.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEKTON_DIR="$HOME/.config/vks-guides/tekton"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" "$@"; }
if ! kc apply --server-side -f "$TEKTON_DIR/tekton-pipelines-v1.17.1.yaml" >/dev/null \
   || ! kc -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m \
   || ! kc apply --server-side -f "$TEKTON_DIR/tekton-triggers-v0.37.2.yaml" >/dev/null; then
  echo "FAILED: Tekton Pipelines or Triggers (see the error above)"
else
  OK=""
  for i in $(seq 20); do
    if kc apply --server-side -f "$TEKTON_DIR/tekton-interceptors-v0.37.2.yaml" >/dev/null 2>&1; then OK=1; break; fi
    sleep 15
  done
  if [ -z "$OK" ]; then
    kc apply --server-side -f "$TEKTON_DIR/tekton-interceptors-v0.37.2.yaml" >/dev/null
    echo "FAILED: Tekton interceptors (see the error above)"
  elif kc -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m \
       && kc -n tekton-pipelines-resolvers wait --for=condition=Available deployment --all --timeout=10m; then
    kc -n tekton-pipelines get pods
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$TEKTON_DIR = "$HOME\.config\vks-guides\tekton"

$global:LASTEXITCODE = $null
kubectl --kubeconfig $VKS_KUBECONFIG apply --server-side -f "$TEKTON_DIR\tekton-pipelines-v1.17.1.yaml" | Out-Null
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m }
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG apply --server-side -f "$TEKTON_DIR\tekton-triggers-v0.37.2.yaml" | Out-Null }
if ($LASTEXITCODE -ne 0) {
  "FAILED: Tekton Pipelines or Triggers (see the error above)"
} else {
  $OK = $false
  foreach ($i in 1..20) {
    kubectl --kubeconfig $VKS_KUBECONFIG apply --server-side -f "$TEKTON_DIR\tekton-interceptors-v0.37.2.yaml" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $OK = $true; break }
    Start-Sleep -Seconds 15
  }
  if (-not $OK) {
    kubectl --kubeconfig $VKS_KUBECONFIG apply --server-side -f "$TEKTON_DIR\tekton-interceptors-v0.37.2.yaml" | Out-Null
    "FAILED: Tekton interceptors (see the error above)"
  } else {
    kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m
    if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines-resolvers wait --for=condition=Available deployment --all --timeout=10m }
    if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines get pods }
  }
}
```

</details>

**Expect:** `deployment.apps/… condition met` lines, then six pods `1/1 Running` in
`tekton-pipelines`: the Pipelines controller, events controller and webhook, and the Triggers
controller, webhook and core interceptors.

**If not:**
- `timed out waiting for the condition`: run `kubectl --kubeconfig <the VKS kubeconfig> -n
  tekton-pipelines get pods`. `ErrImagePull` or `ImagePullBackOff`: the nodes cannot reach
  `ghcr.io`. `Pending`: not enough free CPU (step 1).
- `FAILED: Tekton interceptors`: the Triggers webhook did not come up; run the block again.

## 4. Run a pipeline

This creates the namespace `tekton-demo` (restricted pods only), two Tasks and a Pipeline that
passes the first Task's result to the second, then runs it once and shows the second Task's
output. Tekton secures the containers it adds itself; each Task's `stepTemplate` secures its own
steps.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: tekton-demo
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: say-hello
  namespace: tekton-demo
spec:
  params:
    - name: who
      type: string
  results:
    - name: greeting
  stepTemplate:
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 65532
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
  steps:
    - name: greet
      image: cgr.dev/chainguard/busybox@sha256:19f02276bf8dbdd62f069b922f10c65262cc34b710eea26ff928129a736be791
      env:
        - name: WHO
          value: $(params.who)
      script: |
        #!/bin/sh
        printf 'Hello, %s' "$WHO" | tee $(results.greeting.path)
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: show-it
  namespace: tekton-demo
spec:
  params:
    - name: text
      type: string
  stepTemplate:
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 65532
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
  steps:
    - name: show
      image: cgr.dev/chainguard/busybox@sha256:19f02276bf8dbdd62f069b922f10c65262cc34b710eea26ff928129a736be791
      env:
        - name: TEXT
          value: $(params.text)
      script: |
        #!/bin/sh
        echo "received: $TEXT"
---
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: hello
  namespace: tekton-demo
spec:
  params:
    - name: who
      type: string
      default: VKS
  tasks:
    - name: first
      taskRef:
        name: say-hello
      params:
        - name: who
          value: $(params.who)
    - name: second
      taskRef:
        name: show-it
      params:
        - name: text
          value: $(tasks.first.results.greeting)
EOF
PR="$(kubectl --kubeconfig "$VKS_KUBECONFIG" create -o jsonpath='{.metadata.name}' -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: hello-run-
  namespace: tekton-demo
spec:
  pipelineRef:
    name: hello
EOF
)"
S="Unknown"
for i in $(seq 60); do
  [ -n "$PR" ] || break
  S="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo get pipelinerun "$PR" -o jsonpath='{.status.conditions[0].status}')"
  [ "$S" = True ] || [ "$S" = False ] && break
  sleep 5
done
kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo get pipelinerun "$PR"
[ "$S" = True ] && kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo logs -l "tekton.dev/pipelineRun=$PR,tekton.dev/pipelineTask=second" -c step-show
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

@'
apiVersion: v1
kind: Namespace
metadata:
  name: tekton-demo
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: say-hello
  namespace: tekton-demo
spec:
  params:
    - name: who
      type: string
  results:
    - name: greeting
  stepTemplate:
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 65532
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
  steps:
    - name: greet
      image: cgr.dev/chainguard/busybox@sha256:19f02276bf8dbdd62f069b922f10c65262cc34b710eea26ff928129a736be791
      env:
        - name: WHO
          value: $(params.who)
      script: |
        #!/bin/sh
        printf 'Hello, %s' "$WHO" | tee $(results.greeting.path)
---
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: show-it
  namespace: tekton-demo
spec:
  params:
    - name: text
      type: string
  stepTemplate:
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 65532
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
  steps:
    - name: show
      image: cgr.dev/chainguard/busybox@sha256:19f02276bf8dbdd62f069b922f10c65262cc34b710eea26ff928129a736be791
      env:
        - name: TEXT
          value: $(params.text)
      script: |
        #!/bin/sh
        echo "received: $TEXT"
---
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: hello
  namespace: tekton-demo
spec:
  params:
    - name: who
      type: string
      default: VKS
  tasks:
    - name: first
      taskRef:
        name: say-hello
      params:
        - name: who
          value: $(params.who)
    - name: second
      taskRef:
        name: show-it
      params:
        - name: text
          value: $(tasks.first.results.greeting)
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
$PR = @'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: hello-run-
  namespace: tekton-demo
spec:
  pipelineRef:
    name: hello
'@ | kubectl --kubeconfig $VKS_KUBECONFIG create -o jsonpath='{.metadata.name}' -f -
$S = 'Unknown'
foreach ($i in 1..60) {
  if (-not $PR) { break }
  $S = kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo get pipelinerun $PR -o jsonpath='{.status.conditions[0].status}'
  if ($S -eq 'True' -or $S -eq 'False') { break }
  Start-Sleep -Seconds 5
}
kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo get pipelinerun $PR
if ($S -eq 'True') { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo logs -l "tekton.dev/pipelineRun=$PR,tekton.dev/pipelineTask=second" -c step-show }
```

</details>

**Expect:** `namespace/tekton-demo created`, `task.tekton.dev/say-hello created`,
`task.tekton.dev/show-it created` and `pipeline.tekton.dev/hello created` (`unchanged` or
`configured` on a second run), then the run with `SUCCEEDED True` and `REASON Succeeded`, then
`received: Hello, VKS`.

**If not:**
- `SUCCEEDED False`: `kubectl --kubeconfig <the VKS kubeconfig> -n tekton-demo get taskruns` names
  the task run that failed, and `kubectl --kubeconfig <the VKS kubeconfig> -n tekton-demo describe
  taskrun <name>` says why. `violates PodSecurity "restricted…"`: a step lacks the `stepTemplate`
  above. `ErrImagePull`: the nodes cannot reach `cgr.dev`.
- `SUCCEEDED Unknown` after five minutes: the pods are still `Pending` or pulling; run
  `kubectl --kubeconfig <the VKS kubeconfig> -n tekton-demo get pods` and look at the reason.
- `failed calling webhook "…tekton.dev"`: Tekton is still starting; wait a minute and run the
  block again.

Every run stays, with its pods, until you delete it:
`kubectl --kubeconfig <the VKS kubeconfig> -n tekton-demo delete pipelinerun <name>`.

## 5. Start the pipeline from an HTTP request

An EventListener receives a JSON request and starts the pipeline with a value from it. This
creates it with the permissions Triggers needs: a namespace role from the Triggers install, and a
cluster role of its own that only reads Tekton's cluster-wide trigger settings. A network policy
drops requests from other pods, so only your port-forward reaches it.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hello-listener
  namespace: tekton-demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: hello-listener
  namespace: tekton-demo
subjects:
  - kind: ServiceAccount
    name: hello-listener
    namespace: tekton-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-eventlistener-roles
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-demo-listener
rules:
  - apiGroups: ["triggers.tekton.dev"]
    resources: ["clusterinterceptors", "clustertriggerbindings"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-demo-listener
subjects:
  - kind: ServiceAccount
    name: hello-listener
    namespace: tekton-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-demo-listener
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: hello
  namespace: tekton-demo
spec:
  params:
    - name: who
      value: $(body.who)
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: hello
  namespace: tekton-demo
spec:
  params:
    - name: who
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata:
        generateName: hello-run-
      spec:
        pipelineRef:
          name: hello
        params:
          - name: who
            value: $(tt.params.who)
---
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: hello
  namespace: tekton-demo
spec:
  serviceAccountName: hello-listener
  triggers:
    - name: hello
      bindings:
        - ref: hello
      template:
        ref: hello
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: hello-listener
  namespace: tekton-demo
spec:
  podSelector:
    matchLabels:
      eventlistener: hello
  policyTypes: ["Ingress"]
EOF
kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo wait --for=condition=Ready eventlistener/hello --timeout=5m \
  && kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo rollout status deployment/el-hello --timeout=5m
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

@'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hello-listener
  namespace: tekton-demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: hello-listener
  namespace: tekton-demo
subjects:
  - kind: ServiceAccount
    name: hello-listener
    namespace: tekton-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-eventlistener-roles
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-demo-listener
rules:
  - apiGroups: ["triggers.tekton.dev"]
    resources: ["clusterinterceptors", "clustertriggerbindings"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-demo-listener
subjects:
  - kind: ServiceAccount
    name: hello-listener
    namespace: tekton-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-demo-listener
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: hello
  namespace: tekton-demo
spec:
  params:
    - name: who
      value: $(body.who)
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: hello
  namespace: tekton-demo
spec:
  params:
    - name: who
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata:
        generateName: hello-run-
      spec:
        pipelineRef:
          name: hello
        params:
          - name: who
            value: $(tt.params.who)
---
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: hello
  namespace: tekton-demo
spec:
  serviceAccountName: hello-listener
  triggers:
    - name: hello
      bindings:
        - ref: hello
      template:
        ref: hello
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: hello-listener
  namespace: tekton-demo
spec:
  podSelector:
    matchLabels:
      eventlistener: hello
  policyTypes: ["Ingress"]
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
$global:LASTEXITCODE = $null
kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo wait --for=condition=Ready eventlistener/hello --timeout=5m
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo rollout status deployment/el-hello --timeout=5m }
```

</details>

**Expect:** a `created` line for each of the eight objects (`unchanged` on a second run), then
`eventlistener.triggers.tekton.dev/hello condition met` and
`deployment "el-hello" successfully rolled out`.

**If not:**
- `timed out waiting for the condition`: run `kubectl --kubeconfig <the VKS kubeconfig> -n
  tekton-demo get pods`; a pod `el-hello-…` in `CrashLoopBackOff` right after step 3 is Triggers
  still starting. Run the wait line again in a minute.
- `clusterroles.rbac.authorization.k8s.io "tekton-triggers-eventlistener-roles" not found`: step 3
  did not finish.

**Forward the EventListener.** Keep this running, in a terminal of its own, until step 6.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo port-forward service/el-hello 8180:8080
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo port-forward service/el-hello 8180:8080
```

**Expect:** `Forwarding from 127.0.0.1:8180 -> 8080`.

**If not:** `address already in use`: another program uses port 8180; stop it and run this again.

**Send a request.** In a second terminal, this sends `{"who": "Tekton Triggers"}`, waits for the
run it starts and shows its output.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEKTON_DIR="$HOME/.config/vks-guides/tekton"

mkdir -p "$TEKTON_DIR"
printf '{"who": "Tekton Triggers"}\n' > "$TEKTON_DIR/request.json"
if ! R="$(curl -fsS --connect-timeout 20 -H 'Content-Type: application/json' --data-binary "@$TEKTON_DIR/request.json" http://localhost:8180)"; then
  echo "FAILED: the EventListener did not accept the request"
else
  echo "$R"
  ID="$(printf '%s' "$R" | jq -r '.eventID')"
  PR=""; S="Unknown"
  for i in $(seq 60); do
    PR="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo get pipelineruns -l "triggers.tekton.dev/triggers-eventid=$ID" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
    [ -n "$PR" ] && S="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo get pipelinerun "$PR" -o jsonpath='{.status.conditions[0].status}')"
    [ "$S" = True ] || [ "$S" = False ] && break
    sleep 5
  done
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo get pipelinerun "$PR"
  [ "$S" = True ] && kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo logs -l "tekton.dev/pipelineRun=$PR,tekton.dev/pipelineTask=second" -c step-show
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$TEKTON_DIR = "$HOME\.config\vks-guides\tekton"

New-Item -ItemType Directory -Force -Path $TEKTON_DIR | Out-Null
[IO.File]::WriteAllText("$TEKTON_DIR\request.json", '{"who": "Tekton Triggers"}')
$global:LASTEXITCODE = $null
$R = curl.exe -fsS --connect-timeout 20 -H 'Content-Type: application/json' --data-binary "@$TEKTON_DIR\request.json" http://localhost:8180
if ($LASTEXITCODE -ne 0) {
  "FAILED: the EventListener did not accept the request"
} else {
  $R
  $ID = (ConvertFrom-Json ($R -join '')).eventID
  $PR = $null; $S = 'Unknown'
  foreach ($i in 1..60) {
    $PR = kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo get pipelineruns -l "triggers.tekton.dev/triggers-eventid=$ID" -o jsonpath='{.items[0].metadata.name}' 2>$null
    if ($PR) { $S = kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo get pipelinerun $PR -o jsonpath='{.status.conditions[0].status}' }
    if ($S -eq 'True' -or $S -eq 'False') { break }
    Start-Sleep -Seconds 5
  }
  kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo get pipelinerun $PR
  if ($S -eq 'True') { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo logs -l "tekton.dev/pipelineRun=$PR,tekton.dev/pipelineTask=second" -c step-show }
}
```

</details>

**Expect:** the EventListener's answer with an `eventID`, then a new `hello-run-…` with
`SUCCEEDED True`, then `received: Hello, Tekton Triggers`.

**If not:**
- `FAILED: the EventListener did not accept the request`: the port-forward is not running; start it
  again. An `HTTP 400` above it: the request file is not valid JSON.
- No run, or `SUCCEEDED False`: see step 4's **If not**.

## 6. Remove the demo (optional)

Stop the port-forward with **Ctrl+C** first. This deletes the namespace `tekton-demo`, with every
run and pod in it, and the demo's cluster role and binding.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace tekton-demo --ignore-not-found --timeout=10m
kubectl --kubeconfig "$VKS_KUBECONFIG" delete clusterrolebinding tekton-demo-listener --ignore-not-found
kubectl --kubeconfig "$VKS_KUBECONFIG" delete clusterrole tekton-demo-listener --ignore-not-found
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG delete namespace tekton-demo --ignore-not-found --timeout=10m
kubectl --kubeconfig $VKS_KUBECONFIG delete clusterrolebinding tekton-demo-listener --ignore-not-found
kubectl --kubeconfig $VKS_KUBECONFIG delete clusterrole tekton-demo-listener --ignore-not-found
```

**Expect:** `namespace "tekton-demo" deleted`, `clusterrolebinding… "tekton-demo-listener"
deleted` and `clusterrole… "tekton-demo-listener" deleted`.

## 7. Uninstall Tekton (optional)

**This deletes every Tekton task, pipeline and run in the cluster, in every namespace.** It first
checks that the cluster's Tekton is this guide's and that nothing outside `tekton-demo` uses it,
and stops otherwise. Run step 6 first.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEKTON_DIR="$HOME/.config/vks-guides/tekton"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" "$@"; }
V="$(kc -n tekton-pipelines get deployment tekton-pipelines-controller -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}')"
U="$(kc get tasks,pipelines,pipelineruns,taskruns,eventlisteners -A --no-headers 2>/dev/null | grep -vc '^tekton-demo ')"
if [ "$V" != v1.17.1 ]; then
  echo "STOPPED: the Tekton here is '${V:-none}', not this guide's v1.17.1"
elif [ "$U" -gt 0 ]; then
  echo "STOPPED: $U Tekton objects outside tekton-demo use this Tekton"
else
  kc delete --ignore-not-found -f "$TEKTON_DIR/tekton-interceptors-v0.37.2.yaml" >/dev/null
  kc delete --ignore-not-found -f "$TEKTON_DIR/tekton-triggers-v0.37.2.yaml" >/dev/null
  kc delete --ignore-not-found -f "$TEKTON_DIR/tekton-pipelines-v1.17.1.yaml" >/dev/null
  kc wait --for=delete namespace/tekton-pipelines namespace/tekton-pipelines-resolvers --timeout=10m 2>/dev/null
  echo "Tekton CRDs left: $(kc get crd -o name | grep -c '\.tekton\.dev$')"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$TEKTON_DIR = "$HOME\.config\vks-guides\tekton"

$V = kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines get deployment tekton-pipelines-controller -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}'
$U = @(kubectl --kubeconfig $VKS_KUBECONFIG get tasks,pipelines,pipelineruns,taskruns,eventlisteners -A --no-headers 2>$null | Where-Object { $_ -notmatch '^tekton-demo ' }).Count
if ($V -ne 'v1.17.1') {
  "STOPPED: the Tekton here is '$(if ($V) { $V } else { 'none' })', not this guide's v1.17.1"
} elseif ($U -gt 0) {
  "STOPPED: $U Tekton objects outside tekton-demo use this Tekton"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG delete --ignore-not-found -f "$TEKTON_DIR\tekton-interceptors-v0.37.2.yaml" | Out-Null
  kubectl --kubeconfig $VKS_KUBECONFIG delete --ignore-not-found -f "$TEKTON_DIR\tekton-triggers-v0.37.2.yaml" | Out-Null
  kubectl --kubeconfig $VKS_KUBECONFIG delete --ignore-not-found -f "$TEKTON_DIR\tekton-pipelines-v1.17.1.yaml" | Out-Null
  kubectl --kubeconfig $VKS_KUBECONFIG wait --for=delete namespace/tekton-pipelines namespace/tekton-pipelines-resolvers --timeout=10m 2>$null
  "Tekton CRDs left: $(@(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name | Where-Object { $_ -match '\.tekton\.dev$' }).Count)"
}
```

</details>

**Expect:** `Tekton CRDs left: 0`, after the namespaces are gone (a few minutes).

**If not:**
- `STOPPED: the Tekton here is 'none'`: Tekton is already uninstalled.
- `STOPPED: the Tekton here is …` with a version: someone else installed this Tekton; leave it.
- `STOPPED: … objects outside tekton-demo`: list them with `kubectl --kubeconfig <the VKS
  kubeconfig> get tasks,pipelines,pipelineruns,taskruns,eventlisteners -A`; delete them first if
  they are yours.

Back to [README](../README.md).
