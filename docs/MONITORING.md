# Monitor a VKS cluster with Prometheus and Grafana

> [!NOTE]
> **Official chart, Kubernetes and Broadcom documentation for this guide**
>
> - [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/README.md) (the chart this guide installs)
> - [Enforce Pod Security Standards with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)
> - [Use Port Forwarding to Access Applications in a Cluster](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) (Grafana)
> - [Prometheus Package Reference](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/prometheus-package-reference.html) (Broadcom's Prometheus add-on, the supported alternative)
> - [Observability on VKS](https://www.vmware.com/docs/observability-vks) and its [examples](https://github.com/vmware/vks-consumption-models/tree/main/observability-consumption-model) (VMware's design this guide follows)

This installs kube-prometheus-stack 92.11.0 into a VKS cluster: Prometheus 3.15.0, Alertmanager
0.34.1, Grafana 13.2.4, the Prometheus Operator 0.94.1, node-exporter 1.12.1 and
kube-state-metrics 2.20.0. The chart is upstream (prometheus-community); Broadcom does not
support it. Broadcom's supported metrics option is the Prometheus add-on, which has no Grafana.

You need:

- a VKS cluster with a default storage class ([CLUSTER.md](CLUSTER.md)), its kubeconfig
  ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig)) and [Helm](HELM.md);
- 20 GiB of storage for Prometheus, inside the vSphere Namespace's storage limit, if one is set;
- nodes that reach `quay.io`, `ghcr.io`, `registry.k8s.io` and `docker.io`, and a machine that
  reaches `github.com`.

The blocks keep their files in `~/.config/vks-guides/monitoring` (PowerShell:
`$HOME\.config\vks-guides\monitoring`).

## 1. Check the cluster

This checks the nodes and the default storage class, and that the cluster has no Prometheus
Operator yet (Broadcom's Prometheus add-on brings one).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

if kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes \
   && SC="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get storageclass -o json)" \
   && CRD="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get crd -o name)"; then
  echo "default storage class: $(printf '%s' "$SC" | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name] | if length == 0 then "NONE" else join(" ") end')"
  echo "Prometheus Operator CRDs: $(printf '%s\n' "$CRD" | grep -c 'monitoring\.coreos\.com$')"
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
if ($LASTEXITCODE -eq 0) {
  $D = @((ConvertFrom-Json $SC).items | Where-Object { $_.metadata.annotations.'storageclass.kubernetes.io/is-default-class' -eq 'true' } | ForEach-Object { $_.metadata.name })
  "default storage class: $(if ($D.Count) { $D -join ' ' } else { 'NONE' })"
  "Prometheus Operator CRDs: $(@($CRD | Where-Object { $_ -cmatch 'monitoring\.coreos\.com$' }).Count)"
} else {
  "FAILED: cannot read the cluster (see the error above)"
}
```

</details>

**Expect:** each node `Ready`, `default storage class:` and a name, and
`Prometheus Operator CRDs: 0`.

**If not:**
- `default storage class: NONE`: see [CLUSTER.md](CLUSTER.md) step 7.
- `Prometheus Operator CRDs:` more than 0: the cluster already runs a Prometheus Operator, for
  example Broadcom's add-on. Use that, or a cluster without one; this guide does not cover both.
- `FAILED: cannot read the cluster`: run
  [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig) first.

## 2. Create the namespace

node-exporter reads each node's host network, processes and files, so the namespace allows
privileged pods.

**Linux, macOS, WSL (bash or zsh):**

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

**Type the password.** Paste this line on its own, then type the password; nothing is shown as you
type (PowerShell shows `*`).

**Linux, macOS, WSL (bash or zsh):**

```sh
printf 'Grafana admin password: '; IFS= read -rs GRAFANA_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$GRAFANA_PASSWORD = Read-Host -AsSecureString 'Grafana admin password'
```

**Save it in the cluster.** This writes it into the Secret `grafana-admin`, from standard input,
never on a command line.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

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

This downloads the chart, checks its SHA-256 and writes `values.yaml`: Grafana uses the Secret
from step 3, Prometheus keeps its data on a volume of `PROMETHEUS_STORAGE` from the default
storage class, and the chart skips etcd, the scheduler, the controller manager and kube-proxy,
whose metrics VKS does not publish.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
CHART_VERSION="92.11.0"
CHART_SHA256="c357a259965187edcbed86591461bfbd56997591afba09be3a49a09b2bec8a2c"
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
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: ${PROMETHEUS_STORAGE}
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeControllerManager:
  enabled: false
kubeProxy:
  enabled: false
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
$CHART_VERSION = "92.11.0"
$CHART_SHA256 = "c357a259965187edcbed86591461bfbd56997591afba09be3a49a09b2bec8a2c"
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
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: $PROMETHEUS_STORAGE
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeControllerManager:
  enabled: false
kubeProxy:
  enabled: false
"@
  [IO.File]::WriteAllText("$MONITORING_DIR\values.yaml", ($V -replace "`r`n", "`n") + "`n")
  "chart: $CHART"
  "values: $MONITORING_DIR\values.yaml"
}
Remove-Item -Force -ErrorAction SilentlyContinue "$CHART.new"
```

</details>

**Expect:** `chart: …kube-prometheus-stack-92.11.0.tgz` and `values: …values.yaml`.

**If not:**
- `FAILED: download …`: this machine cannot reach `github.com`, or `CHART_VERSION` names a
  release that does not exist.
- `FAILED: checksum mismatch …`: the download arrived damaged, or that release was rebuilt. Do
  not install it; run the block again.

## 5. Install

This installs the chart as release `prometheus` and waits until Prometheus and Alertmanager are
running (a few minutes; the first run downloads the images).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
CHART_VERSION="92.11.0"
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
$CHART_VERSION = "92.11.0"
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
      kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring get prometheus,alertmanager -o jsonpath='{range .items[*]}{.kind}: {range .status.conditions[*]}{.type}={.status} {.message}; {end}{"\n"}{end}'
    }
  }
}
```

</details>

**Expect:** `STATUS: deployed`, both `condition met`, every pod `Running`, and the Prometheus
volume `Bound`. Ignore the commands in Helm's notes that read the password from
`prometheus-grafana`: the password is the one from step 3.

**If not:**
- `FAILED: helm install` under `violates PodSecurity`: run step 2 first.
- `FAILED: Prometheus or Alertmanager is not running`: the line under it says why. A volume that
  stays `Pending` means no default storage class or no room under the vSphere Namespace's
  storage limit ([NAMESPACE.md](NAMESPACE.md) step 7).
- A pod in `ImagePullBackOff`: the nodes cannot reach the registry in its image name
  (`kubectl --kubeconfig <the VKS kubeconfig> -n monitoring describe pod <name>`).

## 6. Check that Prometheus collects

This asks Prometheus, through the cluster's API server, how many of its targets answer.

**Linux, macOS, WSL (bash or zsh):**

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

**Expect:** `up N of N`, the same number twice, and no `down:` line.

**If not:** a `down:` line names the target and its error. Right after step 5, wait a minute and
run this again.

## 7. Open Grafana

This forwards Grafana to port 3000 on this machine until you press **Ctrl+C**.

**Linux, macOS, WSL (bash or zsh):**

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
- `address already in use`: another program uses port 3000; change both `3000`s (`3001:80`) and
  open that port.
- The login fails after you set a new password in step 3: Grafana reads it when it starts. Run
  `kubectl --kubeconfig <the VKS kubeconfig> -n monitoring rollout restart deployment/prometheus-grafana`,
  then log in again.

## 8. Uninstall (optional)

**This deletes Prometheus's data and the Grafana password.** It removes the release, a Service the
Prometheus Operator left in `kube-system`, and the namespace. The chart's CRDs stay (see below).

**Linux, macOS, WSL (bash or zsh):**

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

**Delete the CRDs** only if step 1 printed `Prometheus Operator CRDs: 0`: this deletes every
ServiceMonitor, PrometheusRule and other object of these kinds in the cluster.

**Linux, macOS, WSL (bash or zsh):**

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

Back to [README](../README.md).
