# Run Tekton in a VKS cluster

> [!NOTE]
> **Official Broadcom, Tekton and Kubernetes documentation for this guide**
>
> - Broadcom: [VMware vSphere Kubernetes Service 3.8 Release Notes](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-release-notes/vmware-tanzu-kubernetes-grid-service-38-release-notes.html) (the Helm-based add-ons, `vcf addon`), [VKS Add-ons Release Notes](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-addons-release-notes.html) (Tekton Operator version and support tier)
> - Tekton: [Tekton Operator](https://tekton.dev/docs/operator/), [TektonConfig](https://tekton.dev/docs/operator/tektonconfig/)
> - Tekton: [Install Tekton Pipelines](https://tekton.dev/docs/installation/pipelines/), [Install and set up Tekton Triggers](https://tekton.dev/docs/installation/triggers/), releases [Pipelines v1.17.1](https://github.com/tektoncd/pipeline/releases/tag/v1.17.1) and [Triggers v0.37.2](https://github.com/tektoncd/triggers/releases/tag/v0.37.2)
> - Tekton: [Tasks](https://tekton.dev/docs/pipelines/tasks/), [Pipelines](https://tekton.dev/docs/pipelines/pipelines/), [PipelineRuns](https://tekton.dev/docs/pipelines/pipelineruns/), [Additional Configuration Options](https://tekton.dev/docs/pipelines/additional-configs/) (restricted pod security)
> - Tekton: [EventListeners](https://tekton.dev/docs/triggers/eventlisteners/), [TriggerBindings](https://tekton.dev/docs/triggers/triggerbindings/), [TriggerTemplates](https://tekton.dev/docs/triggers/triggertemplates/)
> - Kubernetes: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/), [Use Port Forwarding to Access Applications in a Cluster](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)

This installs Tekton, a CI/CD engine that runs each step of a build as a pod, into a VKS cluster.
It then runs a two-task pipeline, and starts it again from an HTTP request through an
EventListener. Tekton's own `tkn` program is not needed.

Install Tekton one of two ways; a cluster has one or the other:

| | A: the VKS add-on (step 2) | B: Tekton's release files (step 3) |
|---|---|---|
| needs | VKS 3.8 or later, and a cluster on Kubernetes v1.33 to v1.37 | any VKS |
| installs | Tekton Operator 0.80.0, Pipelines 1.12.0, Triggers 0.36.0 | Pipelines 1.17.1, Triggers 0.37.2 |
| support | Broadcom supports installing and upgrading it; Tekton bugs and security fixes come from the Tekton project | none from Broadcom |
| nodes pull from | `projects.packages.broadcom.com` and `cgr.dev` | `ghcr.io` (and `pkg-containers.githubusercontent.com`) and `cgr.dev` |
| free CPU on the workers | about 400m | about 200m |

You need:

- a VKS cluster ([CLUSTER.md](CLUSTER.md)) and its kubeconfig
  ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig));
- [kubectl](KUBECTL.md), and [curl and jq](PREREQS.md);
- for A, the [VCF CLI](VCF.md) with the context `supervisor` ([LOGIN.md](LOGIN.md));
- for B, a machine that reaches `github.com` and `release-assets.githubusercontent.com`.

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
  if printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev'; then
    O="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd tektonconfigs.operator.tekton.dev -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace} {.metadata.deletionTimestamp}')"
    if [ "$O" = "vmware-system-helm " ]; then
      echo "Tekton: the VKS add-on"
    elif [ "${O%% *}" = vmware-system-helm ]; then
      echo "Tekton: parts of one"
    else
      echo "Tekton: a Tekton Operator that is not the VKS add-on"
    fi
  elif printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/tasks.tekton.dev'; then
    echo "Tekton: release files $(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd tasks.tekton.dev -o jsonpath='{.metadata.labels.pipeline\.tekton\.dev/release}')"
  elif printf '%s\n' "$C" | grep -q '\.tekton\.dev$'; then
    echo "Tekton: parts of one"
  else
    echo "Tekton: none"
  fi
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
  if ($C -contains 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev') {
    $O = kubectl --kubeconfig $VKS_KUBECONFIG get crd tektonconfigs.operator.tekton.dev -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace} {.metadata.deletionTimestamp}'
    if ($O -eq 'vmware-system-helm ') { "Tekton: the VKS add-on" }
    elseif ($O -like 'vmware-system-helm *') { "Tekton: parts of one" }
    else { "Tekton: a Tekton Operator that is not the VKS add-on" }
  } elseif ($C -contains 'customresourcedefinition.apiextensions.k8s.io/tasks.tekton.dev') {
    "Tekton: release files $(kubectl --kubeconfig $VKS_KUBECONFIG get crd tasks.tekton.dev -o jsonpath='{.metadata.labels.pipeline\.tekton\.dev/release}')"
  } elseif (@($C | Where-Object { $_ -match '\.tekton\.dev$' }).Count -gt 0) {
    "Tekton: parts of one"
  } else {
    "Tekton: none"
  }
} else {
  "FAILED: cannot read the cluster (see the error above)"
}
```

</details>

**Expect:** each node `Ready`, a `worker …: …m CPU free` line per worker, and `Tekton: none`.
A's pods ask for about 400m in all, B's for 200m, each at most 100m on one worker.

**If not:**
- Less free CPU: add a worker or use a larger VM class ([CLUSTER.md](CLUSTER.md)), or remove
  something you no longer need from the cluster.
- `Tekton: the VKS add-on`: A is installed; go on with step 2's second block. `Tekton: release
  files v1.17.1`: B is installed; go to step 4.
- `Tekton: a Tekton Operator that is not the VKS add-on`, another `release files` version, or
  `parts of one`: the cluster already has another Tekton, or what is left of one (step 7 removes
  what is left of A or B). Use another cluster; this guide does not cover it.
- `FAILED: cannot read the cluster`: run
  [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig) first.

## 2. Install Tekton with the VKS add-on (A)

Skip to step 3 for B. List the Tekton add-on releases your Supervisor offers:

**Linux, macOS, WSL (bash or zsh):**

```sh
vcf context use supervisor
vcf addon available-releases list --addon-name tekton-operator
```

**Windows (PowerShell):**

```powershell
vcf context use supervisor
vcf addon available-releases list --addon-name tekton-operator
```

**Expect:** a row with `ADDON-RELEASE-NAME` `tekton-operator.0.80.0-vmware.1-vks.1`. A
`failed to discover plugin sources …` line from `vcf context use` is harmless ([VCF.md](VCF.md)).

**If not:**
- No row: the Supervisor runs a VKS older than 3.8. Use B (step 3).
- `no current context set` or a login error: [renew the Supervisor login](LOGIN.md#renew-the-supervisor-login).

This installs the add-on on your cluster from the Supervisor, with its web exposure turned off
(it needs cert-manager and a Gateway), then waits for the operator's two pods. A second run
applies the settings again. Set `TEKTON_RELEASE` to the release name above.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEKTON_RELEASE="tekton-operator.0.80.0-vmware.1-vks.1"
TEKTON_DIR="$HOME/.config/vks-guides/tekton"

vcf context use supervisor
mkdir -p "$TEKTON_DIR"
printf 'helmValues:\n  exposure:\n    enabled: false\n' > "$TEKTON_DIR/addon-values.yaml"
if ! C="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)"; then
  echo "FAILED: cannot read the cluster (see the error above)"
elif printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/tasks.tekton.dev' \
     && ! printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev'; then
  echo "STOPPED: this cluster has Tekton from its release files (B)"
elif printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev' \
     && [ "$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd tektonconfigs.operator.tekton.dev -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')" != vmware-system-helm ]; then
  echo "STOPPED: this cluster has a Tekton Operator that is not the VKS add-on"
elif ! L="$(vcf addon install list --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" -o json)"; then
  echo "FAILED: the VCF CLI (see the error above)"
else
  OK=""
  if [ "$(printf '%s' "$L" | jq '[.[]? | select(.addonName == "tekton-operator")] | length')" = 1 ]; then
    vcf addon install update tekton-operator --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" \
      -f "$TEKTON_DIR/addon-values.yaml" -y && OK=1
  else
    vcf addon install create tekton-operator --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" \
      --addon-release-name "$TEKTON_RELEASE" -f "$TEKTON_DIR/addon-values.yaml" -y && OK=1
  fi
  D=""
  if [ -n "$OK" ]; then
    for i in $(seq 120); do
      D="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-operator get deployment -o name 2>/dev/null)"
      if [ -n "$D" ]; then break; fi
      sleep 5
    done
  fi
  if [ -z "$OK" ]; then
    echo "FAILED: the add-on (see the error above)"
  elif [ -z "$D" ]; then
    echo "FAILED: the add-on did not reach the cluster in 10 minutes"
  elif kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-operator wait --for=condition=Available deployment --all --timeout=10m; then
    kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-operator get pods
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$TEKTON_RELEASE = "tekton-operator.0.80.0-vmware.1-vks.1"
$TEKTON_DIR = "$HOME\.config\vks-guides\tekton"

vcf context use supervisor
New-Item -ItemType Directory -Force -Path $TEKTON_DIR | Out-Null
[IO.File]::WriteAllText("$TEKTON_DIR\addon-values.yaml", "helmValues:`n  exposure:`n    enabled: false`n")
$global:LASTEXITCODE = $null
$C = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name)
if ($LASTEXITCODE -ne 0) {
  "FAILED: cannot read the cluster (see the error above)"
} elseif ($C -contains 'customresourcedefinition.apiextensions.k8s.io/tasks.tekton.dev' -and
          $C -notcontains 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev') {
  "STOPPED: this cluster has Tekton from its release files (B)"
} elseif ($C -contains 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev' -and
          (kubectl --kubeconfig $VKS_KUBECONFIG get crd tektonconfigs.operator.tekton.dev -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}') -ne 'vmware-system-helm') {
  "STOPPED: this cluster has a Tekton Operator that is not the VKS add-on"
} else {
  $L = vcf addon install list --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE -o json | Out-String
  if ($LASTEXITCODE -ne 0) {
    "FAILED: the VCF CLI (see the error above)"
  } else {
    if (@(ConvertFrom-Json $L | ForEach-Object { $_ } | Where-Object { $_.addonName -eq 'tekton-operator' }).Count -eq 1) {
      vcf addon install update tekton-operator --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE -f "$TEKTON_DIR\addon-values.yaml" -y
    } else {
      vcf addon install create tekton-operator --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE --addon-release-name $TEKTON_RELEASE -f "$TEKTON_DIR\addon-values.yaml" -y
    }
    if ($LASTEXITCODE -ne 0) {
      "FAILED: the add-on (see the error above)"
    } else {
      $D = $null
      foreach ($i in 1..120) {
        $D = kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-operator get deployment -o name 2>$null
        if ($D) { break }
        Start-Sleep -Seconds 5
      }
      if (-not $D) {
        "FAILED: the add-on did not reach the cluster in 10 minutes"
      } else {
        kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-operator wait --for=condition=Available deployment --all --timeout=10m
        if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-operator get pods }
      }
    }
  }
}
```

</details>

**Expect:** `Addon 'tekton-operator' is being installed in the cluster …` (or `… is being updated`),
then two `deployment.apps/… condition met` lines and the pods `tekton-operator-…` (`2/2`) and
`tekton-operator-webhook-…` (`1/1`) `Running`.

**If not:**
- `STOPPED: … release files (B)`: B is installed; use it (step 4), or remove it first (step 7).
- `STOPPED: … not the VKS add-on`: someone else installed a Tekton Operator; use another cluster.
- `READY False` and the add-on's HelmRelease names the Kubernetes version: the cluster is older
  than v1.33; use B (step 3), after removing the add-on (step 7).
- `FAILED: the add-on did not reach the cluster`: run `vcf addon install list --cluster-name
  <cluster> -n <namespace>`; with `READY False`, `kubectl --kubeconfig <the VKS kubeconfig> -n
  vmware-system-helm get helmrelease` says why. The add-on retries every five minutes; run the
  block again.
- `FAILED: the add-on` with `Forbidden`: you need the edit or owner role on the vSphere Namespace.
- `FAILED: the VCF CLI`: [renew the Supervisor login](LOGIN.md#renew-the-supervisor-login).

This turns on Tekton Pipelines and Triggers: it tells the operator, through a TektonConfig, to
install them into `tekton-pipelines` without Tekton's other parts, and to secure the containers
Tekton adds to each run (step 4 needs that). It retries until the operator's webhook answers,
then waits for them.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEKTON_DIR="$HOME/.config/vks-guides/tekton"

mkdir -p "$TEKTON_DIR"
cat > "$TEKTON_DIR/tektonconfig.yaml" <<'EOF'
apiVersion: operator.tekton.dev/v1alpha1
kind: TektonConfig
metadata:
  name: config
spec:
  targetNamespace: tekton-pipelines
  profile: basic
  chain:
    disabled: true
  result:
    disabled: true
  pruner:
    disabled: true
  pipeline:
    set-security-context: true
EOF
OK=""
for i in $(seq 20); do
  if kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f "$TEKTON_DIR/tektonconfig.yaml" 2>/dev/null; then OK=1; break; fi
  sleep 15
done
if [ -z "$OK" ] && ! kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f "$TEKTON_DIR/tektonconfig.yaml"; then
  echo "FAILED: TektonConfig (see the error above)"
elif kubectl --kubeconfig "$VKS_KUBECONFIG" wait --for=condition=Ready tektonconfig/config --timeout=10m \
     && kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m; then
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-pipelines get pods
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
$Y = @'
apiVersion: operator.tekton.dev/v1alpha1
kind: TektonConfig
metadata:
  name: config
spec:
  targetNamespace: tekton-pipelines
  profile: basic
  chain:
    disabled: true
  result:
    disabled: true
  pruner:
    disabled: true
  pipeline:
    set-security-context: true
'@
[IO.File]::WriteAllText("$TEKTON_DIR\tektonconfig.yaml", ($Y -replace "`r`n", "`n") + "`n")
$OK = $false
foreach ($i in 1..20) {
  kubectl --kubeconfig $VKS_KUBECONFIG apply -f "$TEKTON_DIR\tektonconfig.yaml" 2>$null
  if ($LASTEXITCODE -eq 0) { $OK = $true; break }
  Start-Sleep -Seconds 15
}
if (-not $OK) { kubectl --kubeconfig $VKS_KUBECONFIG apply -f "$TEKTON_DIR\tektonconfig.yaml" }
if (-not $OK -and $LASTEXITCODE -ne 0) {
  "FAILED: TektonConfig (see the error above)"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG wait --for=condition=Ready tektonconfig/config --timeout=10m
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m }
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines get pods }
}
```

</details>

**Expect:** `tektonconfig.operator.tekton.dev/config created` (`unchanged` on a second run),
`condition met` lines, then eight pods `1/1 Running` in `tekton-pipelines`: the Pipelines
controller, events controller, remote resolvers and webhook, the operator's proxy webhook, and the
Triggers controller, webhook and core interceptors. Go to step 4.

**If not:**
- `FAILED: TektonConfig` with `failed calling webhook "…operator.tekton.dev"` or `Required value`:
  the operator did not answer within five minutes; run the add-on block above again, then this one.
- `timed out waiting for the condition`: run `kubectl --kubeconfig <the VKS kubeconfig> -n
  tekton-pipelines get pods`. `ErrImagePull`: the nodes cannot reach
  `projects.packages.broadcom.com`. `Pending`: not enough free CPU (step 1).

## 3. Install Tekton from its release files (B)

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

This installs Pipelines, waits for it, then installs Triggers and its interceptors and waits
again. Triggers is retried until the Pipelines webhook answers, which checks one of its settings,
and the interceptors until the Triggers webhook answers. It can take several minutes while the nodes pull the
images.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEKTON_DIR="$HOME/.config/vks-guides/tekton"

if ! C="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)"; then
  echo "FAILED: cannot read the cluster (see the error above)"
elif printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev'; then
  echo "STOPPED: this cluster has a Tekton Operator (A)"
elif ! kubectl --kubeconfig "$VKS_KUBECONFIG" apply --server-side -f "$TEKTON_DIR/tekton-pipelines-v1.17.1.yaml" >/dev/null \
   || ! kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m; then
  echo "FAILED: Tekton Pipelines (see the error above)"
else
  FAILED=""
  for F in tekton-triggers-v0.37.2.yaml tekton-interceptors-v0.37.2.yaml; do
    OK=""
    for i in $(seq 20); do
      if kubectl --kubeconfig "$VKS_KUBECONFIG" apply --server-side -f "$TEKTON_DIR/$F" >/dev/null 2>&1; then OK=1; break; fi
      sleep 15
    done
    if [ -z "$OK" ] && ! kubectl --kubeconfig "$VKS_KUBECONFIG" apply --server-side -f "$TEKTON_DIR/$F" >/dev/null; then
      echo "FAILED: $F (see the error above)"; FAILED=1; break
    fi
  done
  if [ -n "$FAILED" ]; then
    :
  elif kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m \
       && kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-pipelines-resolvers wait --for=condition=Available deployment --all --timeout=10m; then
    kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-pipelines get pods
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
$C = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name)
if ($LASTEXITCODE -ne 0) {
  "FAILED: cannot read the cluster (see the error above)"
} elseif ($C -contains 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev') {
  "STOPPED: this cluster has a Tekton Operator (A)"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG apply --server-side -f "$TEKTON_DIR\tekton-pipelines-v1.17.1.yaml" | Out-Null
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m }
  if ($LASTEXITCODE -ne 0) {
    "FAILED: Tekton Pipelines (see the error above)"
  } else {
    $FAILED = $false
    foreach ($F in 'tekton-triggers-v0.37.2.yaml', 'tekton-interceptors-v0.37.2.yaml') {
      $OK = $false
      foreach ($i in 1..20) {
        kubectl --kubeconfig $VKS_KUBECONFIG apply --server-side -f "$TEKTON_DIR\$F" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $OK = $true; break }
        Start-Sleep -Seconds 15
      }
      if (-not $OK) {
        kubectl --kubeconfig $VKS_KUBECONFIG apply --server-side -f "$TEKTON_DIR\$F" | Out-Null
        if ($LASTEXITCODE -ne 0) {
          "FAILED: $F (see the error above)"
          $FAILED = $true
          break
        }
      }
    }
    if (-not $FAILED) {
      kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m
      if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines-resolvers wait --for=condition=Available deployment --all --timeout=10m }
      if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-pipelines get pods }
    }
  }
}
```

</details>

**Expect:** `deployment.apps/… condition met` lines, then six pods `1/1 Running` in
`tekton-pipelines`: the Pipelines controller, events controller and webhook, and the Triggers
controller, webhook and core interceptors.

**If not:**
- `STOPPED: … Tekton Operator (A)`: use A (step 2's second block, then step 4).
- `timed out waiting for the condition`: run `kubectl --kubeconfig <the VKS kubeconfig> -n
  tekton-pipelines get pods`. `ErrImagePull` or `ImagePullBackOff`: the nodes cannot reach
  `ghcr.io`. `Pending`: not enough free CPU (step 1).
- `FAILED: tekton-triggers-…` or `FAILED: tekton-interceptors-…` with `failed calling webhook`:
  the Pipelines or Triggers webhook did not answer within five minutes; run `kubectl --kubeconfig
  <the VKS kubeconfig> -n tekton-pipelines get pods`, then run the block again.

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
if [ -z "$PR" ]; then
  echo "FAILED: no PipelineRun was created (see the error above)"
else
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
if (-not $PR) {
  "FAILED: no PipelineRun was created (see the error above)"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo get pipelinerun $PR
  if ($S -eq 'True') { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo logs -l "tekton.dev/pipelineRun=$PR,tekton.dev/pipelineTask=second" -c step-show }
}
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
- `FAILED: no PipelineRun was created`: see the error above it.
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

**Expect:** a `created` line for each of the eight objects (`unchanged` or `configured` on a second
run), then
`eventlistener.triggers.tekton.dev/hello condition met` and
`deployment "el-hello" successfully rolled out`.

**If not:**
- `timed out waiting for the condition`: run `kubectl --kubeconfig <the VKS kubeconfig> -n
  tekton-demo get pods`; a pod `el-hello-…` in `CrashLoopBackOff` right after installing Tekton is
  Triggers still starting. Run the wait line again in a minute.
- `namespaces "tekton-demo" not found`: run step 4 first.
- `clusterroles.rbac.authorization.k8s.io "tekton-triggers-eventlistener-roles" not found`: Tekton's
  install (step 2 or 3) did not finish.

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

**Expect:** `Forwarding from 127.0.0.1:8180 -> 8080` (and a `[::1]` line).

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
  if [ -z "$PR" ]; then
    echo "FAILED: no PipelineRun was started"
  else
    kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo get pipelinerun "$PR"
    [ "$S" = True ] && kubectl --kubeconfig "$VKS_KUBECONFIG" -n tekton-demo logs -l "tekton.dev/pipelineRun=$PR,tekton.dev/pipelineTask=second" -c step-show
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
  if (-not $PR) {
    "FAILED: no PipelineRun was started"
  } else {
    kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo get pipelinerun $PR
    if ($S -eq 'True') { kubectl --kubeconfig $VKS_KUBECONFIG -n tekton-demo logs -l "tekton.dev/pipelineRun=$PR,tekton.dev/pipelineTask=second" -c step-show }
  }
}
```

</details>

**Expect:** the EventListener's answer with an `eventID`, then a new `hello-run-…` with
`SUCCEEDED True`, then `received: Hello, Tekton Triggers`.

**If not:**
- `FAILED: the EventListener did not accept the request`: the port-forward is not running; start it
  again.
- `FAILED: no PipelineRun was started`: `kubectl --kubeconfig <the VKS kubeconfig> -n tekton-demo
  logs deployment/el-hello` says why.
- `SUCCEEDED False`: see step 4's **If not**.

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

**This deletes every Tekton task, pipeline and run in the cluster, in every namespace.** Each
block first checks that the cluster's Tekton is the one it removes and that no Tekton object
outside `tekton-demo` exists, and stops otherwise. Run step 6 first.

### With the VKS add-on (A)

This turns Pipelines and Triggers off and waits for them to go, removes the operator's webhook
set while the operator still runs (it is left behind otherwise), then removes the add-on and its
empty namespace.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

vcf context use supervisor
if ! C="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)" \
   || ! A="$(kubectl --kubeconfig "$VKS_KUBECONFIG" api-resources -o name)"; then
  echo "STOPPED: cannot read the cluster (see the error above)"
elif ! printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev'; then
  echo "The Tekton add-on is not installed"
elif [ "$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd tektonconfigs.operator.tekton.dev -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}')" != vmware-system-helm ]; then
  echo "STOPPED: this Tekton Operator is not the VKS add-on"
else
  L=""
  K="$(printf '%s\n' "$A" | grep '\.tekton\.dev$' | grep -v -e '^clusterinterceptors\.' -e '\.operator\.tekton\.dev$' | paste -sd, -)"
  if [ -n "$K" ] && ! L="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get "$K" -A --no-headers)"; then
    echo "STOPPED: cannot list the Tekton objects (see the error above)"
  elif U="$(printf '%s\n' "$L" | grep -v '^$' | grep -vc '^tekton-demo ')"; [ "$U" -gt 0 ]; then
    echo "STOPPED: $U Tekton objects outside tekton-demo use this Tekton"
  else
    kubectl --kubeconfig "$VKS_KUBECONFIG" delete tektonconfig config --ignore-not-found --timeout=5m
    N=unknown
    for i in $(seq 60); do
      if C="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)"; then
        N="$(printf '%s\n' "$C" | grep '\.tekton\.dev$' | grep -vc '\.operator\.tekton\.dev$')"
        if [ "$N" = 0 ]; then break; fi
      fi
      sleep 5
    done
    if [ "$N" != 0 ]; then
      echo "FAILED: $N Tekton CRDs still there after 5 minutes"
    elif ! W="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get tektoninstallersets -o name)"; then
      echo "FAILED: cannot list the operator's sets (see the error above)"
    else
      printf '%s\n' "$W" | grep '/validating-mutating-webhook-' | while read -r R; do
        kubectl --kubeconfig "$VKS_KUBECONFIG" delete "$R" --timeout=2m </dev/null
      done
      if ! W="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get tektoninstallersets -o name)" \
         || printf '%s\n' "$W" | grep -q '/validating-mutating-webhook-'; then
        echo "FAILED: the operator's webhook set is still there (see the error above)"
      elif ! vcf addon install delete tekton-operator --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" -y; then
        echo "FAILED: the add-on (see the error above)"
      else
        kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace tekton-operator --ignore-not-found --timeout=5m
        if C="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)"; then
          echo "Tekton CRDs left: $(printf '%s\n' "$C" | grep -c '\.tekton\.dev$')"
        else
          echo "FAILED: cannot read the cluster (see the error above)"
        fi
      fi
    fi
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

vcf context use supervisor
$global:LASTEXITCODE = $null
$C = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name)
if ($LASTEXITCODE -eq 0) { $A = @(kubectl --kubeconfig $VKS_KUBECONFIG api-resources -o name) }
if ($LASTEXITCODE -ne 0) {
  "STOPPED: cannot read the cluster (see the error above)"
} elseif ($C -notcontains 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev') {
  "The Tekton add-on is not installed"
} elseif ((kubectl --kubeconfig $VKS_KUBECONFIG get crd tektonconfigs.operator.tekton.dev -o jsonpath='{.metadata.labels.helm\.toolkit\.fluxcd\.io/namespace}') -ne 'vmware-system-helm') {
  "STOPPED: this Tekton Operator is not the VKS add-on"
} else {
  $L = @()
  $KINDS = @($A | Where-Object { $_ -match '\.tekton\.dev$' -and $_ -notmatch '^clusterinterceptors\.' -and $_ -notmatch '\.operator\.tekton\.dev$' }) -join ','
  $global:LASTEXITCODE = 0
  if ($KINDS) { $L = @(kubectl --kubeconfig $VKS_KUBECONFIG get $KINDS -A --no-headers) }
  if ($LASTEXITCODE -ne 0) {
    "STOPPED: cannot list the Tekton objects (see the error above)"
  } elseif (($U = @($L | Where-Object { $_ -and $_ -notmatch '^tekton-demo ' }).Count) -gt 0) {
    "STOPPED: $U Tekton objects outside tekton-demo use this Tekton"
  } else {
    kubectl --kubeconfig $VKS_KUBECONFIG delete tektonconfig config --ignore-not-found --timeout=5m
    $N = 'unknown'
    foreach ($i in 1..60) {
      $C = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name)
      if ($LASTEXITCODE -eq 0) {
        $N = @($C | Where-Object { $_ -match '\.tekton\.dev$' -and $_ -notmatch '\.operator\.tekton\.dev$' }).Count
        if ($N -eq 0) { break }
      }
      Start-Sleep -Seconds 5
    }
    if ($N -ne 0) {
      "FAILED: $N Tekton CRDs still there after 5 minutes"
    } else {
      $W = @(kubectl --kubeconfig $VKS_KUBECONFIG get tektoninstallersets -o name)
      if ($LASTEXITCODE -ne 0) {
        "FAILED: cannot list the operator's sets (see the error above)"
      } else {
        foreach ($R in @($W | Where-Object { $_ -match '/validating-mutating-webhook-' })) {
          kubectl --kubeconfig $VKS_KUBECONFIG delete $R --timeout=2m
        }
        $W = @(kubectl --kubeconfig $VKS_KUBECONFIG get tektoninstallersets -o name)
        if ($LASTEXITCODE -ne 0 -or @($W | Where-Object { $_ -match '/validating-mutating-webhook-' }).Count -gt 0) {
          "FAILED: the operator's webhook set is still there (see the error above)"
        } else {
          vcf addon install delete tekton-operator --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE -y
          if ($LASTEXITCODE -ne 0) {
            "FAILED: the add-on (see the error above)"
          } else {
            kubectl --kubeconfig $VKS_KUBECONFIG delete namespace tekton-operator --ignore-not-found --timeout=5m
            $C = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name)
            if ($LASTEXITCODE -eq 0) {
              "Tekton CRDs left: $(@($C | Where-Object { $_ -match '\.tekton\.dev$' }).Count)"
            } else {
              "FAILED: cannot read the cluster (see the error above)"
            }
          }
        }
      }
    }
  }
}
```

</details>

**Expect:** `No resources found` (when Tekton was on: no Tekton objects left), then
`tektonconfig.operator.tekton.dev "config" deleted`, `tektoninstallerset.operator.tekton.dev
"validating-mutating-webhook-…" deleted`, the add-on's `Waiting for deleting …` lines ending in
`Addon 'tekton-operator' installed in the cluster … has been deleted`, `namespace
"tekton-operator" deleted` and `Tekton CRDs left: 0`, in about two minutes. On a second run:
`The Tekton add-on is not installed`.

**If not:**
- `STOPPED: this Tekton Operator is not the VKS add-on`: someone else installed it; leave it.
- `STOPPED: … objects outside tekton-demo`: list them with `kubectl --kubeconfig <the VKS
  kubeconfig> get <kind> -A`; delete them first if they are yours.
- `Tekton CRDs left:` more than 0, or `FAILED: …`: see the error above it, and run the block
  again.
- `STOPPED: cannot read the cluster` with no other error: `kubectl --kubeconfig <the VKS
  kubeconfig> get apiservice` shows one that is not `True`; fix or remove it.
- `The Tekton add-on is not installed` but the namespace `tekton-operator` is still there (an
  earlier run stopped before its end): `kubectl --kubeconfig <the VKS kubeconfig> delete namespace
  tekton-operator`.

### From the release files (B)

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEKTON_DIR="$HOME/.config/vks-guides/tekton"

if ! C="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)" \
   || ! A="$(kubectl --kubeconfig "$VKS_KUBECONFIG" api-resources -o name)"; then
  echo "STOPPED: cannot read the cluster (see the error above)"
elif [ "$(printf '%s\n' "$C" | grep -c '\.tekton\.dev$')" = 0 ]; then
  echo "Tekton is not installed"
elif printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev'; then
  echo "STOPPED: this cluster has a Tekton Operator; for the VKS add-on, use the block above"
elif ! V="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd tasks.tekton.dev -o jsonpath='{.metadata.labels.pipeline\.tekton\.dev/release}')" \
     || [ "$V" != v1.17.1 ]; then
  echo "STOPPED: the Tekton here is '${V:-unknown}', not this guide's v1.17.1"
elif printf '%s\n' "$C" | grep -qx 'customresourcedefinition.apiextensions.k8s.io/eventlisteners.triggers.tekton.dev' \
     && { ! T="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd eventlisteners.triggers.tekton.dev -o jsonpath='{.metadata.labels.triggers\.tekton\.dev/release}')" \
          || [ "$T" != v0.37.2 ]; }; then
  echo "STOPPED: the Tekton Triggers here is '${T:-unknown}', not this guide's v0.37.2"
elif ! L="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get "$(printf '%s\n' "$A" | grep '\.tekton\.dev$' | grep -v '^clusterinterceptors\.' | paste -sd, -)" -A --no-headers)"; then
  echo "STOPPED: cannot list the Tekton objects (see the error above)"
elif U="$(printf '%s\n' "$L" | grep -v '^$' | grep -vc '^tekton-demo ')"; [ "$U" -gt 0 ]; then
  echo "STOPPED: $U Tekton objects outside tekton-demo use this Tekton"
else
  kubectl --kubeconfig "$VKS_KUBECONFIG" delete --ignore-not-found -f "$TEKTON_DIR/tekton-interceptors-v0.37.2.yaml" >/dev/null
  kubectl --kubeconfig "$VKS_KUBECONFIG" delete --ignore-not-found -f "$TEKTON_DIR/tekton-triggers-v0.37.2.yaml" >/dev/null
  kubectl --kubeconfig "$VKS_KUBECONFIG" delete --ignore-not-found -f "$TEKTON_DIR/tekton-pipelines-v1.17.1.yaml" >/dev/null
  kubectl --kubeconfig "$VKS_KUBECONFIG" wait --for=delete namespace/tekton-pipelines namespace/tekton-pipelines-resolvers --timeout=10m 2>/dev/null
  if C="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)"; then
    echo "Tekton CRDs left: $(printf '%s\n' "$C" | grep -c '\.tekton\.dev$')"
  else
    echo "FAILED: cannot read the cluster (see the error above)"
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
$C = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name)
if ($LASTEXITCODE -eq 0) { $A = @(kubectl --kubeconfig $VKS_KUBECONFIG api-resources -o name) }
if ($LASTEXITCODE -ne 0) {
  "STOPPED: cannot read the cluster (see the error above)"
} elseif (@($C | Where-Object { $_ -match '\.tekton\.dev$' }).Count -eq 0) {
  "Tekton is not installed"
} elseif ($C -contains 'customresourcedefinition.apiextensions.k8s.io/tektonconfigs.operator.tekton.dev') {
  "STOPPED: this cluster has a Tekton Operator; for the VKS add-on, use the block above"
} else {
  $V = kubectl --kubeconfig $VKS_KUBECONFIG get crd tasks.tekton.dev -o jsonpath='{.metadata.labels.pipeline\.tekton\.dev/release}'
  $VOK = ($LASTEXITCODE -eq 0 -and $V -eq 'v1.17.1')
  $T = 'v0.37.2'
  if ($C -contains 'customresourcedefinition.apiextensions.k8s.io/eventlisteners.triggers.tekton.dev') {
    $T = kubectl --kubeconfig $VKS_KUBECONFIG get crd eventlisteners.triggers.tekton.dev -o jsonpath='{.metadata.labels.triggers\.tekton\.dev/release}'
    if ($LASTEXITCODE -ne 0) { $T = $null }
  }
  if (-not $VOK) {
    "STOPPED: the Tekton here is '$(if ($V) { $V } else { 'unknown' })', not this guide's v1.17.1"
  } elseif ($T -ne 'v0.37.2') {
    "STOPPED: the Tekton Triggers here is '$(if ($T) { $T } else { 'unknown' })', not this guide's v0.37.2"
  } else {
    $KINDS = @($A | Where-Object { $_ -match '\.tekton\.dev$' -and $_ -notmatch '^clusterinterceptors\.' }) -join ','
    $L = @(kubectl --kubeconfig $VKS_KUBECONFIG get $KINDS -A --no-headers)
    if ($LASTEXITCODE -ne 0) {
      "STOPPED: cannot list the Tekton objects (see the error above)"
    } elseif (($U = @($L | Where-Object { $_ -and $_ -notmatch '^tekton-demo ' }).Count) -gt 0) {
      "STOPPED: $U Tekton objects outside tekton-demo use this Tekton"
    } else {
      kubectl --kubeconfig $VKS_KUBECONFIG delete --ignore-not-found -f "$TEKTON_DIR\tekton-interceptors-v0.37.2.yaml" | Out-Null
      kubectl --kubeconfig $VKS_KUBECONFIG delete --ignore-not-found -f "$TEKTON_DIR\tekton-triggers-v0.37.2.yaml" | Out-Null
      kubectl --kubeconfig $VKS_KUBECONFIG delete --ignore-not-found -f "$TEKTON_DIR\tekton-pipelines-v1.17.1.yaml" | Out-Null
      kubectl --kubeconfig $VKS_KUBECONFIG wait --for=delete namespace/tekton-pipelines namespace/tekton-pipelines-resolvers --timeout=10m 2>$null
      $C = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name)
      if ($LASTEXITCODE -eq 0) {
        "Tekton CRDs left: $(@($C | Where-Object { $_ -match '\.tekton\.dev$' }).Count)"
      } else {
        "FAILED: cannot read the cluster (see the error above)"
      }
    }
  }
}
```

</details>

**Expect:** `Tekton CRDs left: 0`, after the namespaces are gone (a few minutes). On a second run:
`Tekton is not installed`.

**If not:**
- `Tekton CRDs left:` more than 0: run step 3's first block on this machine (the delete needs its
  files), then this block again.
- `STOPPED: … Tekton Operator`: A is installed; use the block above.
- `STOPPED: the Tekton here is …` or `STOPPED: the Tekton Triggers here is …`: someone else
  installed this Tekton; leave it.
- `STOPPED: … objects outside tekton-demo`: list them with `kubectl --kubeconfig <the VKS
  kubeconfig> get <kind> -A`; delete them first if they are yours.
- `STOPPED: cannot …` or `FAILED: cannot …`: see the error above it, and run the block again.

Back to [README](../README.md).
