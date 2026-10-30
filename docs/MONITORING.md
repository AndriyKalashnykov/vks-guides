# Monitor a VKS cluster with Prometheus and Grafana

> [!NOTE]
> **Official chart, Kubernetes and Broadcom documentation for this guide**
>
> - [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/README.md) (the chart this guide installs)
> - [Enforce Pod Security Standards with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)
> - [Use Port Forwarding to Access Applications in a Cluster](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) (Grafana)
> - [Prometheus Package Reference](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/prometheus-package-reference.html) (Broadcom's Prometheus add-on, the supported alternative; VCF 9.0 page, there is no 9.1 copy)
> - Argo CD 3.4: [Helm](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/helm/), [Sync Options](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/sync-options/) (Server-Side Apply), [Automated Sync Policy](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/auto_sync/) (step 9)
> - [Observability on VKS](https://www.vmware.com/docs/observability-vks) and its [examples](https://github.com/vmware/vks-consumption-models/tree/main/observability-consumption-model) (VMware's design this guide follows)

This installs kube-prometheus-stack 92.13.1 into a VKS cluster: Prometheus 3.15.0, Alertmanager
0.34.1, Grafana 13.2.4, the Prometheus Operator 0.94.1, node-exporter 1.12.1 and
kube-state-metrics 2.20.0. The chart is upstream (prometheus-community); Broadcom does not
support it. Broadcom's supported metrics option is the Prometheus add-on, which has no Grafana.

Steps 4 and 5 install with Helm; step 9 installs with ArgoCD instead.

The blocks keep their files in `~/.config/vks-guides/monitoring` (PowerShell:
`$HOME\.config\vks-guides\monitoring`).

## Prerequisites

- a VKS cluster with a default storage class ([CLUSTER.md](CLUSTER.md)), its kubeconfig
  ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig)) and [Helm](HELM.md), or for step 9 the
  ArgoCD of [ARGOCD.md](ARGOCD.md) and your [Supervisor login](LOGIN.md);
- [kubectl](KUBECTL.md), [curl and jq](PREREQS.md);
- 20 GiB of storage for Prometheus, inside the vSphere Namespace's storage limit, if one is set.

The connections this guide needs, for a firewall (all TCP, besides DNS; for a registry, also
the hosts in [Registry hosts](PREREQS.md#registry-hosts-for-a-firewall)):

| from | to | port | for |
|---|---|---|---|
| your machine | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl and Helm (all steps), Grafana through `localhost:3000` (step 7) |
| the cluster's nodes | `quay.io`, `ghcr.io`, `registry.k8s.io`, `docker.io` | 443 | the images |
| your machine | `github.com`, `release-assets.githubusercontent.com` | 443 | the chart, with Helm (step 4) |
| your machine | the Supervisor's address | 443 | kubectl, with ArgoCD (steps 9, 10) |
| ArgoCD, on the Supervisor | `prometheus-community.github.io`, `github.com`, `release-assets.githubusercontent.com` | 443 | the chart, with ArgoCD (step 9) |
| ArgoCD, on the Supervisor | the VKS cluster's API address | 6443 | installing into the cluster, with ArgoCD (step 9) |

## 1. Check the cluster

This checks that the cluster is ready for this guide:

- its nodes are up;
- it has a default storage class, which gives Prometheus a disk for its data;
- it runs no Prometheus yet, which would clash with this one. VCF Operations' own monitoring
  add-on runs no full Prometheus, so it is fine.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

if kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes \
   && SC="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get storageclass -o json)" \
   && CRD="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)" \
   && SRV="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get deployments,statefulsets -A -o name)"; then
  echo "default storage class: $(printf '%s' "$SC" | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name] | if length == 0 then "NONE" else join(" ") end')"
  echo "Prometheus Operator CRDs: $(printf '%s\n' "$CRD" | grep -c 'monitoring\.coreos\.com$')"
  echo "Prometheus server workloads: $(printf '%s\n' "$SRV" | grep -c 'prometheus-server$')"
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

$global:LASTEXITCODE = $null
kubectl --kubeconfig $VKS_KUBECONFIG get nodes
if ($LASTEXITCODE -eq 0) { $SC = kubectl --kubeconfig $VKS_KUBECONFIG get storageclass -o json | Out-String }
if ($LASTEXITCODE -eq 0) { $CRD = @(kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name) }
if ($LASTEXITCODE -eq 0) { $SRV = @(kubectl --kubeconfig $VKS_KUBECONFIG get deployments,statefulsets -A -o name) }
if ($LASTEXITCODE -eq 0) {
  $D = @((ConvertFrom-Json $SC).items | Where-Object { $_.metadata.annotations.'storageclass.kubernetes.io/is-default-class' -eq 'true' } | ForEach-Object { $_.metadata.name })
  "default storage class: $(if ($D.Count) { $D -join ' ' } else { 'NONE' })"
  "Prometheus Operator CRDs: $(@($CRD | Where-Object { $_ -cmatch 'monitoring\.coreos\.com$' }).Count)"
  "Prometheus server workloads: $(@($SRV | Where-Object { $_ -cmatch 'prometheus-server$' }).Count)"
} else {
  "FAILED: cannot read the cluster (see the error above)"
}
```

</details>

**Expect:** each node `Ready`, `default storage class:` and a name,
`Prometheus Operator CRDs: 0` and `Prometheus server workloads: 0`.

**If not:**
- `default storage class: NONE`: see [CLUSTER.md](CLUSTER.md) step 7.
- `Prometheus Operator CRDs:` or `Prometheus server workloads:` more than 0, before you ran
  this guide's step 5 or 9: the cluster already runs a Prometheus. Use it, or a cluster without
  one; this guide does not cover both.
- `FAILED: cannot read the cluster`: run
  [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig) first.

## 2. Create the namespace

This creates the namespace `monitoring`, which holds everything this guide installs. One part,
node-exporter, reads each node's own CPU, memory and disk figures; that needs extra rights, so
this namespace allows them.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
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
  name: monitoring
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
```

**Expect:** `namespace/monitoring created` (`configured` or `unchanged` on a second run).

**If not:** `Forbidden`: your kubeconfig is not the cluster's administrator; use the one from
[LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig).

## 3. Set Grafana's admin password

**Type the password.** Choose the password you will log in to Grafana with, as `admin` (step 7).
Paste this line on its own, then type it; nothing is shown as you type (PowerShell shows `*`).

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
printf 'Grafana admin password: '; IFS= read -rs GRAFANA_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$GRAFANA_PASSWORD = Read-Host -AsSecureString 'Grafana admin password'
```

**Save it in the cluster.** Grafana reads its admin password from the cluster, so this stores it
there as `grafana-admin`, a Kubernetes Secret (an object that holds private data in the cluster).
It replaces any earlier one, then forgets the password in this terminal. The password never
appears on a command line, where other users of this machine could see it.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

if [ -z "$GRAFANA_PASSWORD" ]; then
  echo "FAILED: no password in this terminal; run the line under Type the password"
elif kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring delete secret grafana-admin --ignore-not-found \
     && printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: grafana-admin\n  namespace: monitoring\ndata:\n  admin-user: %s\n  admin-password: %s\n' \
          "$(printf 'admin' | base64 | tr -d '\n')" "$(printf '%s' "$GRAFANA_PASSWORD" | base64 | tr -d '\n')" \
        | kubectl --kubeconfig "$VKS_KUBECONFIG" create -f -; then
  unset GRAFANA_PASSWORD
else
  echo "FAILED: Secret not saved (see the error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$global:LASTEXITCODE = $null
if (-not $GRAFANA_PASSWORD -or $GRAFANA_PASSWORD.Length -eq 0) {
  "FAILED: no password in this terminal; run the line under Type the password"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring delete secret grafana-admin --ignore-not-found
  if ($LASTEXITCODE -eq 0) {
    $U = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin'))
    $P = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Net.NetworkCredential]::new('', $GRAFANA_PASSWORD).Password))
    "apiVersion: v1`nkind: Secret`nmetadata:`n  name: grafana-admin`n  namespace: monitoring`ndata:`n  admin-user: $U`n  admin-password: $P`n" |
      kubectl --kubeconfig $VKS_KUBECONFIG create -f -
    Remove-Variable P
  }
  if ($LASTEXITCODE -eq 0) { Remove-Variable GRAFANA_PASSWORD } else { "FAILED: Secret not saved (see the error above)" }
}
```

</details>

**Expect:** `secret/grafana-admin created` (after `secret "grafana-admin" deleted` on a second
run).

**If not:**
- `FAILED: no password in this terminal`: run the line under **Type the password**, then this
  block again.
- `namespaces "monitoring" not found`: run step 2 first.

Grafana's login name is `admin`. Anyone who can read Secrets in `monitoring` can read the
password.

## 4. Download the chart and write the values

This gets the installer for Prometheus and Grafana (a Helm chart) and writes the settings step 5
installs it with. It:

- downloads the chart and checks that the file is exactly the one published;
- writes `values.yaml`, in which:
  - Grafana uses the password from step 3;
  - Prometheus keeps its data on a disk of `PROMETHEUS_STORAGE` and deletes the oldest data
    when the disk is about 80% full;
  - parts of the cluster that VKS does not let you monitor are left out, so they do not show
    as errors;
  - names and network settings are changed to work beside VCF Operations' own monitoring and
    through the VKS node firewall.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
CHART_VERSION="92.13.1"
CHART_SHA256="4d2ef1a537c2e42765e795afe62baac08d97f3377715b39e00077a46d33f4219"
PROMETHEUS_STORAGE="20Gi"
MONITORING_DIR="$HOME/.config/vks-guides/monitoring"

CHART="$MONITORING_DIR/kube-prometheus-stack-${CHART_VERSION}.tgz"
URL="https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-${CHART_VERSION}/kube-prometheus-stack-${CHART_VERSION}.tgz"
mkdir -p "$MONITORING_DIR"
if ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" "$URL"; then
  echo "FAILED: download of $URL"
elif [ "$( (sha256sum "$CHART.new" 2>/dev/null || shasum -a 256 "$CHART.new") | cut -d' ' -f1)" != "$CHART_SHA256" ]; then
  echo "FAILED: checksum mismatch for $URL"
else
  mv "$CHART.new" "$CHART"
  cat > "$MONITORING_DIR/values.yaml" <<EOF
grafana:
  admin:
    existingSecret: grafana-admin
prometheus:
  prometheusSpec:
    retentionPercentage: 80
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: ${PROMETHEUS_STORAGE}
kube-state-metrics:
  fullnameOverride: monitoring-kube-state-metrics
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeControllerManager:
  enabled: false
kubeProxy:
  enabled: false
prometheus-node-exporter:
  hostNetwork: false
  prometheus:
    monitor:
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_node_name]
          targetLabel: instance
EOF
  echo "chart: $CHART"
  echo "values: $MONITORING_DIR/values.yaml"
fi
rm -f "$CHART.new"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$CHART_VERSION = "92.13.1"
$CHART_SHA256 = "4d2ef1a537c2e42765e795afe62baac08d97f3377715b39e00077a46d33f4219"
$PROMETHEUS_STORAGE = "20Gi"
$MONITORING_DIR = "$HOME\.config\vks-guides\monitoring"

$global:LASTEXITCODE = $null
$CHART = "$MONITORING_DIR\kube-prometheus-stack-$CHART_VERSION.tgz"
$URL = "https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-$CHART_VERSION/kube-prometheus-stack-$CHART_VERSION.tgz"
New-Item -ItemType Directory -Force -Path $MONITORING_DIR | Out-Null
curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" $URL
if ($LASTEXITCODE -ne 0) {
  "FAILED: download of $URL"
} elseif ((Get-FileHash -Algorithm SHA256 "$CHART.new").Hash -ne $CHART_SHA256) {
  "FAILED: checksum mismatch for $URL"
} else {
  Move-Item -Force "$CHART.new" $CHART
  $V = @"
grafana:
  admin:
    existingSecret: grafana-admin
prometheus:
  prometheusSpec:
    retentionPercentage: 80
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: $PROMETHEUS_STORAGE
kube-state-metrics:
  fullnameOverride: monitoring-kube-state-metrics
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeControllerManager:
  enabled: false
kubeProxy:
  enabled: false
prometheus-node-exporter:
  hostNetwork: false
  prometheus:
    monitor:
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_node_name]
          targetLabel: instance
"@
  [IO.File]::WriteAllText("$MONITORING_DIR\values.yaml", ($V -replace "`r`n", "`n") + "`n")
  "chart: $CHART"
  "values: $MONITORING_DIR\values.yaml"
}
Remove-Item -Force -ErrorAction SilentlyContinue "$CHART.new"
```

</details>

**Expect:** `chart: …kube-prometheus-stack-92.13.1.tgz` and `values: …values.yaml`.

**If not:**
- `FAILED: download …`: this machine cannot reach `github.com` or
  `release-assets.githubusercontent.com`, or `CHART_VERSION` names a release that does not exist.
- `FAILED: checksum mismatch …`: the download arrived damaged, or that release was rebuilt. Do
  not install it; run the block again.

## 5. Install

**Run this first.** An older version of this guide created permissions that VCF Operations' own
monitoring may now use. This finds them and marks them, so the install below does not delete
them. On most clusters it prints `nothing to keep` and changes nothing.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

if ! OWNER="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get clusterrolebinding prometheus-kube-state-metrics \
     --ignore-not-found -o jsonpath='{.subjects[0].namespace}')"; then
  echo "FAILED: cannot read the cluster (see the error above)"
elif [ "$OWNER" = "tanzu-system-monitoring" ]; then
  kubectl --kubeconfig "$VKS_KUBECONFIG" annotate clusterrole/prometheus-kube-state-metrics \
    clusterrolebinding/prometheus-kube-state-metrics helm.sh/resource-policy=keep --overwrite
else
  echo "nothing to keep"
fi
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$global:LASTEXITCODE = $null
$OWNER = kubectl --kubeconfig $VKS_KUBECONFIG get clusterrolebinding prometheus-kube-state-metrics --ignore-not-found -o jsonpath='{.subjects[0].namespace}'
if ($LASTEXITCODE -ne 0) {
  "FAILED: cannot read the cluster (see the error above)"
} elseif ($OWNER -eq 'tanzu-system-monitoring') {
  kubectl --kubeconfig $VKS_KUBECONFIG annotate clusterrole/prometheus-kube-state-metrics clusterrolebinding/prometheus-kube-state-metrics helm.sh/resource-policy=keep --overwrite
} else {
  "nothing to keep"
}
```

**Expect:** `nothing to keep`, or `clusterrole.rbac.authorization.k8s.io/prometheus-kube-state-metrics
annotated` and the same for the `clusterrolebinding`.

**If not:** `FAILED: cannot read the cluster`: run
[Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig) first.

This installs Prometheus, Grafana and the rest with Helm, under the name `prometheus`. It waits
until Prometheus and Alertmanager (which sends alerts) run, then lists the pods and Prometheus's
disk. The first run takes a few minutes, while the nodes download the images.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
CHART_VERSION="92.13.1"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
MONITORING_DIR="$HOME/.config/vks-guides/monitoring"

CHART="$MONITORING_DIR/kube-prometheus-stack-${CHART_VERSION}.tgz"
if [ ! -s "$CHART" ] || [ ! -s "$MONITORING_DIR/values.yaml" ]; then
  echo "FAILED: $CHART or values.yaml is missing (step 4)"
elif ! helm upgrade --install prometheus "$CHART" --kubeconfig "$VKS_KUBECONFIG" -n monitoring \
       -f "$MONITORING_DIR/values.yaml" --wait --timeout 15m; then
  echo "FAILED: helm install (see the error above)"
elif kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring wait --for=condition=Available --timeout=10m \
       prometheus/prometheus-kube-prometheus-prometheus alertmanager/prometheus-kube-prometheus-alertmanager; then
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring get pods,pvc
else
  echo "FAILED: Prometheus or Alertmanager is not running"
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring get prometheus,alertmanager \
    -o jsonpath='{range .items[*]}{.kind}: {range .status.conditions[*]}{.type}={.status} {.message}; {end}{"\n"}{end}'
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$CHART_VERSION = "92.13.1"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$MONITORING_DIR = "$HOME\.config\vks-guides\monitoring"

$global:LASTEXITCODE = $null
$CHART = "$MONITORING_DIR\kube-prometheus-stack-$CHART_VERSION.tgz"
if (-not (Test-Path $CHART) -or -not (Test-Path "$MONITORING_DIR\values.yaml")) {
  "FAILED: $CHART or values.yaml is missing (step 4)"
} else {
  helm upgrade --install prometheus $CHART --kubeconfig $VKS_KUBECONFIG -n monitoring -f "$MONITORING_DIR\values.yaml" --wait --timeout 15m
  if ($LASTEXITCODE -ne 0) {
    "FAILED: helm install (see the error above)"
  } else {
    kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring wait --for=condition=Available --timeout=10m prometheus/prometheus-kube-prometheus-prometheus alertmanager/prometheus-kube-prometheus-alertmanager
    if ($LASTEXITCODE -eq 0) {
      kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring get pods,pvc
    } else {
      "FAILED: Prometheus or Alertmanager is not running"
      kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring get prometheus,alertmanager -o jsonpath='{range .items[*]}{.kind}: {range .status.conditions[*]}{.type}={.status} {.message}; {end}{''\n''}{end}'
    }
  }
}
```

</details>

**Expect:** `STATUS: deployed`, both `condition met`, every pod `Running`, and the Prometheus
volume `Bound`. Ignore the two password commands in Helm's notes: the password is the one from
step 3. Helm may also print lines with `Warning: event bookmark expired` or
`watch ended with error`; they do no harm when `STATUS: deployed` and both `condition met`
follow.

**If not:**
- `FAILED: helm install` after `namespaces "monitoring" not found`, or after
  `would violate PodSecurity` and `context deadline exceeded`: run step 2, then this block again.
- `FAILED: helm install` after `ClusterRole "prometheus-kube-state-metrics" … exists and cannot be
  imported`: your `values.yaml` is from before kube-state-metrics was renamed. Run step 4, then
  this block again.
- `FAILED: Prometheus or Alertmanager is not running`: the line under it says why. A volume that
  stays `Pending` means no default storage class or no room under the vSphere Namespace's
  storage limit ([NAMESPACE.md](NAMESPACE.md) step 7).
- A pod in `ImagePullBackOff`: the nodes cannot reach the registry in its image name
  (`kubectl --kubeconfig <the VKS kubeconfig> -n monitoring describe pod <name>`).

## 6. Check that Prometheus collects

This checks that Prometheus collects metrics: it asks Prometheus how many of the things it
measures (nodes, pods, cluster services) answer, and names any that do not.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" get --raw /api/v1/namespaces/monitoring/services/prometheus-kube-prometheus-prometheus:9090/proxy/api/v1/targets \
  | jq -r '.data.activeTargets | "up \(map(select(.health == "up")) | length) of \(length)", (.[] | select(.health != "up") | "down: \(.labels.job) \(.lastError)")'
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$T = (kubectl --kubeconfig $VKS_KUBECONFIG get --raw /api/v1/namespaces/monitoring/services/prometheus-kube-prometheus-prometheus:9090/proxy/api/v1/targets | Out-String | ConvertFrom-Json).data.activeTargets
"up $(@($T | Where-Object { $_.health -eq 'up' }).Count) of $(@($T).Count)"
$T | Where-Object { $_.health -ne 'up' } | ForEach-Object { "down: $($_.labels.job) $($_.lastError)" }
```

**Expect:** `up N of N`, the same number twice and above 0 (22 on a cluster with one control
plane node and two workers), and no `down:` line.

**If not:** a `down:` line names the target and its error. Right after step 5 or 9, wait a minute
and run this again.

## 7. Open Grafana

Grafana runs inside the cluster and has no address you can open. This connects it to
<http://localhost:3000> on your machine while the command runs. Leave it running while you use
Grafana; press **Ctrl+C** to stop.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring port-forward service/prometheus-grafana 3000:80
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring port-forward service/prometheus-grafana 3000:80
```

Open <http://localhost:3000>, log in as `admin` with the password from step 3, and open
**Dashboards** → **Kubernetes / Compute Resources / Cluster**.

**Expect:** `Forwarding from 127.0.0.1:3000 -> 3000`, then the dashboard with CPU and memory
graphs for the cluster.

**If not:**
- `address already in use`, or no `127.0.0.1` line: another program uses port 3000; change both
  `3000`s (`3001:80`) and open that port.
- The login fails after you set a new password in step 3: Grafana reads it when it starts. Run
  `kubectl --kubeconfig <the VKS kubeconfig> -n monitoring rollout restart deployment/prometheus-grafana`,
  then log in again.

## 8. Uninstall with Helm (optional)

This removes what step 5 installed. **It deletes Prometheus's data and the Grafana password.**
For an install with ArgoCD, use step 10. First run the first block of step 5 again, so the
permissions VCF Operations' monitoring uses are not deleted too. This block removes the Helm
install, one item it leaves in `kube-system`, and the namespace `monitoring`. The new object
types the chart added stay; the next block removes them.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

helm uninstall prometheus --kubeconfig "$VKS_KUBECONFIG" -n monitoring
kubectl --kubeconfig "$VKS_KUBECONFIG" -n kube-system delete service prometheus-kube-prometheus-kubelet --ignore-not-found
kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace monitoring --ignore-not-found
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

helm uninstall prometheus --kubeconfig $VKS_KUBECONFIG -n monitoring
kubectl --kubeconfig $VKS_KUBECONFIG -n kube-system delete service prometheus-kube-prometheus-kubelet --ignore-not-found
kubectl --kubeconfig $VKS_KUBECONFIG delete namespace monitoring --ignore-not-found
```

**Expect:** `release "prometheus" uninstalled`, `service "prometheus-kube-prometheus-kubelet"
deleted` and `namespace "monitoring" deleted`.

**If not:** `Release not loaded`: it was already uninstalled; the other lines print nothing.

**Delete the Prometheus object types.** The chart added new kinds of objects to the cluster
(CRDs), such as ServiceMonitor, and they stay after the uninstall. This deletes them, and every
object of those kinds in the cluster. Run it only if step 1 printed
`Prometheus Operator CRDs: 0`; otherwise something else in the cluster uses them.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name | grep 'monitoring\.coreos\.com$' \
  | while read -r C; do kubectl --kubeconfig "$VKS_KUBECONFIG" delete "$C"; done
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG get crd -o name | Where-Object { $_ -cmatch 'monitoring\.coreos\.com$' } | ForEach-Object { kubectl --kubeconfig $VKS_KUBECONFIG delete $_ }
```

**Expect:** ten `customresourcedefinition.apiextensions.k8s.io "….monitoring.coreos.com" deleted`
lines.

## 9. Install with ArgoCD (instead of steps 4 and 5)

This installs the same Prometheus and Grafana as steps 4 and 5, but through the ArgoCD of
[ARGOCD.md](ARGOCD.md), which then keeps them installed and puts back anything that changes. You
need that guide's steps 1 to 4 and 7 (the VKS cluster added to ArgoCD), this guide's steps 1 to
3, and a Supervisor that reaches `prometheus-community.github.io`, `github.com` and
`release-assets.githubusercontent.com`. On this path the chart's checksum is not checked. If an
older version of this guide was installed, VCF Operations' monitoring may lose some permissions
for up to 10 minutes; it then restores them.

This makes sure the names this step uses are free, so you do not overwrite someone else's
install: the ArgoCD project `monitoring`, the ArgoCD Application `prometheus`, and a Helm install
named `prometheus` in the cluster.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get appproject monitoring
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get applications.argoproj.io prometheus
kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring get secret -l owner=helm,name=prometheus
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get appproject monitoring
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get applications.argoproj.io prometheus
kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring get secret -l owner=helm,name=prometheus
```

**Expect:** two `Error from server (NotFound): …` lines, then `No resources found in monitoring
namespace.`

**If not:**
- A project or Application is listed: someone else uses ArgoCD for this; ask them.
- A Secret is listed: the chart is installed with Helm (step 5). Use that, or remove it with
  step 8 first.

This tells ArgoCD to install Prometheus and Grafana in your VKS cluster. It creates:

- the ArgoCD project `monitoring`, which limits what ArgoCD may create there (the namespaces
  `monitoring` and `kube-system`, and the chart's cluster-wide objects);
- the ArgoCD Application `prometheus`: the install itself, with the settings of step 4.

ArgoCD starts at once and puts back anything later changed or deleted in the cluster; to change
a setting, edit it here and run the block again. Anyone who can edit the Application can still
change anything in the cluster. Set `ARGOCD_DESTINATION` to the VKS cluster's name in ArgoCD
(**Settings** → **Clusters**; `<cluster>-<namespace>` after [ARGOCD.md](ARGOCD.md) step 7).

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
ARGOCD_DESTINATION="my-vks-cluster-my-namespace"
CHART_VERSION="92.13.1"
PROMETHEUS_STORAGE="20Gi"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: monitoring
spec:
  description: kube-prometheus-stack into ${ARGOCD_DESTINATION}
  sourceRepos:
    - https://prometheus-community.github.io/helm-charts
  destinations:
    - name: ${ARGOCD_DESTINATION}
      namespace: monitoring
    - name: ${ARGOCD_DESTINATION}
      namespace: kube-system
  clusterResourceWhitelist:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
    - group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: monitoring
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: "${CHART_VERSION}"
    helm:
      releaseName: prometheus
      valuesObject:
        grafana:
          admin:
            existingSecret: grafana-admin
        prometheus:
          prometheusSpec:
            retentionPercentage: 80
            storageSpec:
              volumeClaimTemplate:
                spec:
                  accessModes:
                    - ReadWriteOnce
                  resources:
                    requests:
                      storage: ${PROMETHEUS_STORAGE}
        kube-state-metrics:
          fullnameOverride: monitoring-kube-state-metrics
        kubeEtcd:
          enabled: false
        kubeScheduler:
          enabled: false
        kubeControllerManager:
          enabled: false
        kubeProxy:
          enabled: false
        prometheus-node-exporter:
          hostNetwork: false
          prometheus:
            monitor:
              relabelings:
                - sourceLabels: [__meta_kubernetes_pod_node_name]
                  targetLabel: instance
  destination:
    name: ${ARGOCD_DESTINATION}
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 10
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
    syncOptions:
      - ServerSideApply=true
EOF
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$ARGOCD_DESTINATION = "my-vks-cluster-my-namespace"
$CHART_VERSION = "92.13.1"
$PROMETHEUS_STORAGE = "20Gi"

@"
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: monitoring
spec:
  description: kube-prometheus-stack into ${ARGOCD_DESTINATION}
  sourceRepos:
    - https://prometheus-community.github.io/helm-charts
  destinations:
    - name: ${ARGOCD_DESTINATION}
      namespace: monitoring
    - name: ${ARGOCD_DESTINATION}
      namespace: kube-system
  clusterResourceWhitelist:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
    - group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: monitoring
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: "${CHART_VERSION}"
    helm:
      releaseName: prometheus
      valuesObject:
        grafana:
          admin:
            existingSecret: grafana-admin
        prometheus:
          prometheusSpec:
            retentionPercentage: 80
            storageSpec:
              volumeClaimTemplate:
                spec:
                  accessModes:
                    - ReadWriteOnce
                  resources:
                    requests:
                      storage: ${PROMETHEUS_STORAGE}
        kube-state-metrics:
          fullnameOverride: monitoring-kube-state-metrics
        kubeEtcd:
          enabled: false
        kubeScheduler:
          enabled: false
        kubeControllerManager:
          enabled: false
        kubeProxy:
          enabled: false
        prometheus-node-exporter:
          hostNetwork: false
          prometheus:
            monitor:
              relabelings:
                - sourceLabels: [__meta_kubernetes_pod_node_name]
                  targetLabel: instance
  destination:
    name: ${ARGOCD_DESTINATION}
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 10
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
    syncOptions:
      - ServerSideApply=true
"@ | kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE apply -f -
```

</details>

**Expect:** `appproject.argoproj.io/monitoring created` and
`application.argoproj.io/prometheus created`, after a `Warning:` about the finalizer name (as in
[ARGOCD.md](ARGOCD.md) step 6). `configured` or `unchanged` on your first run: someone else made
them; stop and ask them.

This shows the Application, then waits until Prometheus and Alertmanager are running. Run it a
minute after the block above; the first install takes a few minutes.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get applications.argoproj.io prometheus \
  -o jsonpath='{.status.sync.status}  {.status.health.status}  {.status.operationState.phase}{"\n"}{.status.operationState.message}{"\n"}{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
if kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring wait --for=condition=Available --timeout=10m \
     prometheus/prometheus-kube-prometheus-prometheus alertmanager/prometheus-kube-prometheus-alertmanager; then
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring get pods,pvc
else
  echo "FAILED: Prometheus or Alertmanager is not running"
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

$global:LASTEXITCODE = $null
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get applications.argoproj.io prometheus -o jsonpath='{.status.sync.status}  {.status.health.status}  {.status.operationState.phase}{''\n''}{.status.operationState.message}{''\n''}{range .status.conditions[*]}{.type}: {.message}{''\n''}{end}'
kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring wait --for=condition=Available --timeout=10m prometheus/prometheus-kube-prometheus-prometheus alertmanager/prometheus-kube-prometheus-alertmanager
if ($LASTEXITCODE -eq 0) {
  kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring get pods,pvc
} else {
  "FAILED: Prometheus or Alertmanager is not running"
}
```

</details>

**Expect:** `Synced  Healthy  Succeeded` and `successfully synced (no more tasks)`, both
`condition met`, every pod `Running`, and the Prometheus volume `Bound`. Then do steps 6 and 7.

**If not:**
- `InvalidSpecError` with `there are no clusters with this name`, `is not permitted in project` or
  `do not match any of the allowed destinations`: `ARGOCD_DESTINATION` is not the name ArgoCD
  shows. Run the block above again with the right name; it prints `configured` this time.
- `ComparisonError` or a message with `failed to fetch chart` or a timeout: the Supervisor cannot
  reach the hosts above. Behind a proxy, see the proxy line in [ARGOCD.md](ARGOCD.md) step 6.
- No such error, and `Running` or `OutOfSync` on the first line, `Retrying attempt #…`,
  `prometheuses… not found` or `doesn't have a resource type "prometheus"`: the install is still
  going (a first attempt can fail and is tried again); run the block again in a minute.
- `Failed` with a message: the message says what failed. ArgoCD tries up to ten times; to try
  again after that, click the tile in the ArgoCD page, then **SYNC** and **SYNCHRONIZE**.
- `FAILED: Prometheus or Alertmanager is not running`: as in step 5.

## 10. Uninstall with ArgoCD (optional)

**This deletes Prometheus's data and the Grafana password.** It deletes the Application (and
with it what ArgoCD installed) and the project, then a Service the Prometheus Operator left in
`kube-system`, and the namespace. The chart's CRDs stay; to delete them, see step 8.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

if kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete applications.argoproj.io prometheus --ignore-not-found --timeout=5m \
   && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete appproject monitoring --ignore-not-found; then
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n kube-system delete service prometheus-kube-prometheus-kubelet --ignore-not-found
  kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace monitoring --ignore-not-found
fi
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$global:LASTEXITCODE = $null
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete applications.argoproj.io prometheus --ignore-not-found --timeout=5m
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete appproject monitoring --ignore-not-found }
if ($LASTEXITCODE -eq 0) {
  kubectl --kubeconfig $VKS_KUBECONFIG -n kube-system delete service prometheus-kube-prometheus-kubelet --ignore-not-found
  kubectl --kubeconfig $VKS_KUBECONFIG delete namespace monitoring --ignore-not-found
}
```

**Expect:** `application.argoproj.io "prometheus" deleted`, `appproject.argoproj.io "monitoring"
deleted`, `service "prometheus-kube-prometheus-kubelet" deleted` and `namespace "monitoring"
deleted`. Newer kubectl adds `from <namespace> namespace` to each `deleted` line.

**If not:** `timed out waiting`: ArgoCD cannot reach the VKS cluster. In the ArgoCD page, delete
the Application with **Non-cascading**. If the VKS cluster is gone, stop here. Otherwise run this
block again, then delete what the chart left outside the namespace:
`kubectl --kubeconfig <the VKS kubeconfig> delete clusterrole,clusterrolebinding,mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/instance=prometheus`
and
`kubectl --kubeconfig <the VKS kubeconfig> -n kube-system delete service -l app.kubernetes.io/instance=prometheus`.

Back to [README](../README.md).
