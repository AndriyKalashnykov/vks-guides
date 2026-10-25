# See a VKS cluster's logs and traces in Grafana

> [!NOTE]
> **Official chart, tool and Broadcom documentation for this guide**
>
> - [Loki Helm chart](https://github.com/grafana-community/helm-charts/tree/main/charts/loki) and [Install the monolithic Helm chart](https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/) (Loki)
> - [Jaeger Helm chart](https://github.com/jaegertracing/helm-charts/tree/main/charts/jaeger) and [Jaeger configuration](https://www.jaegertracing.io/docs/2.20/deployment/configuration/) (traces)
> - [Fluent Bit Loki output](https://docs.fluentbit.io/manual/pipeline/outputs/loki) and Broadcom's [Fluent Bit Package Reference](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/fluent-bit-package-reference.html) (VCF 9.0 page; there is no 9.1 copy)
> - Grafana: [Provision data sources](https://grafana.com/docs/grafana/latest/administration/provisioning/#data-sources), [Loki data source](https://grafana.com/docs/grafana/latest/datasources/loki/configure-loki-data-source/), [Jaeger data source](https://grafana.com/docs/grafana/latest/datasources/jaeger/configure/)
> - [podinfo](https://github.com/stefanprodan/podinfo) (the sample app)
> - [Observability on VKS](https://www.vmware.com/docs/observability-vks) and its [examples](https://github.com/vmware/vks-consumption-models/tree/main/observability-consumption-model) (VMware's design this guide follows)

This adds logs and traces to the Grafana of [MONITORING.md](MONITORING.md) and runs a sample app
that produces all three signals:

| signal | collected by | stored in | where you look |
|---|---|---|---|
| metrics | Prometheus (MONITORING.md) | Prometheus | Grafana |
| logs | Broadcom's Fluent Bit add-on | Loki 3.7.9 | Grafana, with a link to the trace |
| traces | the app, over OTLP | Jaeger 2.20.0 | Grafana, with a link to the logs |
| the cluster and its node VMs | the vSphere Supervisor integration | VCF Operations | VCF Operations |

Loki and Jaeger keep their data inside the cluster. The Loki and Jaeger charts are upstream;
Broadcom does not support them.

You need:

- MONITORING.md steps 1 to 7, or steps 1 to 3 and 9;
- the [VCF CLI](VCF.md) with its plugins and a [Supervisor login](LOGIN.md), for the Fluent Bit
  add-on;
- 10 GiB more storage for Loki, inside the vSphere Namespace's storage limit, if one is set;
- nodes that reach `docker.io` and `ghcr.io`, and a machine that reaches `github.com` and
  `release-assets.githubusercontent.com`.

The blocks keep their files in `~/.config/vks-guides/observability` (PowerShell:
`$HOME\.config\vks-guides\observability`).

## 1. Check the cluster

This checks that Grafana from MONITORING.md runs with its data source loader, and whether the
Fluent Bit add-on is already installed.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

echo "Grafana data source loader: $(kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring get deployment prometheus-grafana \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="grafana-sc-datasources")].name}')"
echo "Fluent Bit add-on: $(kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging get daemonset fluent-bit -o name 2>/dev/null)"
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

"Grafana data source loader: $(kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring get deployment prometheus-grafana -o jsonpath='{.spec.template.spec.containers[?(@.name==\"grafana-sc-datasources\")].name}')"
"Fluent Bit add-on: $(kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging get daemonset fluent-bit -o name 2>$null)"
```

**Expect:** `Grafana data source loader: grafana-sc-datasources`, and `Fluent Bit add-on:` with
nothing after it, or `daemonset.apps/fluent-bit` if you did [LOGGING.md](LOGGING.md).

**If not:** `deployments.apps "prometheus-grafana" not found`: do MONITORING.md first.

## 2. Create the namespaces

`observability` holds Loki and Jaeger, `podinfo` the sample app. Both keep the cluster's default
pod security, `restricted`.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" create namespace observability
kubectl --kubeconfig "$VKS_KUBECONFIG" create namespace podinfo
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG create namespace observability
kubectl --kubeconfig $VKS_KUBECONFIG create namespace podinfo
```

**Expect:** `namespace/observability created` and `namespace/podinfo created`.

**If not:** `AlreadyExists`: the namespace is there from an earlier run; go on.

## 3. Install Loki

This downloads the chart, checks its SHA-256, writes `loki-values.yaml` and installs Loki as one
pod with a volume of `LOKI_STORAGE` from the default storage class. Loki deletes logs older than
`LOKI_RETENTION`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
CHART_VERSION="19.3.0"
CHART_SHA256="585d12a053a00851728e01382f59724e40237008874ae3d4939bd27a2c749b0a"
LOKI_STORAGE="10Gi"
LOKI_RETENTION="168h"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OBSERVABILITY_DIR="$HOME/.config/vks-guides/observability"

CHART="$OBSERVABILITY_DIR/loki-${CHART_VERSION}.tgz"
URL="https://github.com/grafana-community/helm-charts/releases/download/loki-${CHART_VERSION}/loki-${CHART_VERSION}.tgz"
mkdir -p "$OBSERVABILITY_DIR"
if ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" "$URL"; then
  echo "FAILED: download of $URL"
elif [ "$( (sha256sum "$CHART.new" 2>/dev/null || shasum -a 256 "$CHART.new") | cut -d' ' -f1)" != "$CHART_SHA256" ]; then
  echo "FAILED: checksum mismatch for $URL"
else
  mv "$CHART.new" "$CHART"
  cat > "$OBSERVABILITY_DIR/loki-values.yaml" <<EOF
deploymentMode: Monolithic
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
  limits_config:
    retention_period: ${LOKI_RETENTION}
  compactor:
    retention_enabled: true
    delete_request_store: filesystem
singleBinary:
  replicas: 1
  persistence:
    size: ${LOKI_STORAGE}
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 1Gi
gateway:
  enabled: false
chunksCache:
  enabled: false
resultsCache:
  enabled: false
lokiCanary:
  enabled: false
test:
  enabled: false
backend:
  replicas: 0
read:
  replicas: 0
write:
  replicas: 0
sidecar:
  rules:
    enabled: false
rbac:
  namespaced: true
EOF
  if helm upgrade --install loki "$CHART" --kubeconfig "$VKS_KUBECONFIG" -n observability \
       -f "$OBSERVABILITY_DIR/loki-values.yaml" --wait --timeout 10m; then
    kubectl --kubeconfig "$VKS_KUBECONFIG" -n observability get pods,pvc
  else
    echo "FAILED: helm install (see the error above)"
  fi
fi
rm -f "$CHART.new"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$CHART_VERSION = "19.3.0"
$CHART_SHA256 = "585d12a053a00851728e01382f59724e40237008874ae3d4939bd27a2c749b0a"
$LOKI_STORAGE = "10Gi"
$LOKI_RETENTION = "168h"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OBSERVABILITY_DIR = "$HOME\.config\vks-guides\observability"

$global:LASTEXITCODE = $null
$CHART = "$OBSERVABILITY_DIR\loki-$CHART_VERSION.tgz"
$URL = "https://github.com/grafana-community/helm-charts/releases/download/loki-$CHART_VERSION/loki-$CHART_VERSION.tgz"
New-Item -ItemType Directory -Force -Path $OBSERVABILITY_DIR | Out-Null
curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" $URL
if ($LASTEXITCODE -ne 0) {
  "FAILED: download of $URL"
} elseif ((Get-FileHash -Algorithm SHA256 "$CHART.new").Hash -ne $CHART_SHA256) {
  "FAILED: checksum mismatch for $URL"
} else {
  Move-Item -Force "$CHART.new" $CHART
  $V = @"
deploymentMode: Monolithic
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
  limits_config:
    retention_period: $LOKI_RETENTION
  compactor:
    retention_enabled: true
    delete_request_store: filesystem
singleBinary:
  replicas: 1
  persistence:
    size: $LOKI_STORAGE
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 1Gi
gateway:
  enabled: false
chunksCache:
  enabled: false
resultsCache:
  enabled: false
lokiCanary:
  enabled: false
test:
  enabled: false
backend:
  replicas: 0
read:
  replicas: 0
write:
  replicas: 0
sidecar:
  rules:
    enabled: false
rbac:
  namespaced: true
"@
  [IO.File]::WriteAllText("$OBSERVABILITY_DIR\loki-values.yaml", ($V -replace "`r`n", "`n") + "`n")
  helm upgrade --install loki $CHART --kubeconfig $VKS_KUBECONFIG -n observability -f "$OBSERVABILITY_DIR\loki-values.yaml" --wait --timeout 10m
  if ($LASTEXITCODE -eq 0) {
    kubectl --kubeconfig $VKS_KUBECONFIG -n observability get pods,pvc
  } else {
    "FAILED: helm install (see the error above)"
  }
}
Remove-Item -Force -ErrorAction SilentlyContinue "$CHART.new"
```

</details>

**Expect:** `STATUS: deployed`, pod `loki-0` `1/1 Running` and its volume `storage-loki-0`
`Bound`.

**If not:**
- `FAILED: download …`: this machine cannot reach `github.com` or
  `release-assets.githubusercontent.com`.
- `FAILED: checksum mismatch …`: the download arrived damaged, or that release was rebuilt. Do
  not install it; run the block again.
- `FAILED: helm install` after `namespaces "observability" not found`: run step 2.
- The volume stays `Pending`: no default storage class, or no room under the vSphere
  Namespace's storage limit ([NAMESPACE.md](NAMESPACE.md) step 7).

## 4. Install Jaeger

This downloads the chart, checks its SHA-256, writes `jaeger-values.yaml` and installs Jaeger
2.20.0 as one pod. It keeps up to 10,000 traces in memory, so a restart empties it. Jaeger 2.21
and later dropped the API that Grafana's Jaeger data source calls, which is why this pins 2.20.0.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
CHART_VERSION="4.13.1"
CHART_SHA256="fc16f5b68572ccd0f9164219759f1102834cee6145d754ba5718596f81a5170b"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OBSERVABILITY_DIR="$HOME/.config/vks-guides/observability"

CHART="$OBSERVABILITY_DIR/jaeger-${CHART_VERSION}.tgz"
URL="https://github.com/jaegertracing/helm-charts/releases/download/jaeger-${CHART_VERSION}/jaeger-${CHART_VERSION}.tgz"
mkdir -p "$OBSERVABILITY_DIR"
if ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" "$URL"; then
  echo "FAILED: download of $URL"
elif [ "$( (sha256sum "$CHART.new" 2>/dev/null || shasum -a 256 "$CHART.new") | cut -d' ' -f1)" != "$CHART_SHA256" ]; then
  echo "FAILED: checksum mismatch for $URL"
else
  mv "$CHART.new" "$CHART"
  cat > "$OBSERVABILITY_DIR/jaeger-values.yaml" <<'EOF'
jaeger:
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      memory: 512Mi
userconfig:
  service:
    extensions: [jaeger_storage, jaeger_query, healthcheckv2]
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [jaeger_storage_exporter]
      logs:
        receivers: [otlp]
        exporters: [nop]
  extensions:
    jaeger_query:
      storage:
        traces: memstore
    jaeger_storage:
      backends:
        memstore:
          memory:
            max_traces: 10000
    healthcheckv2:
      use_v2: true
      http:
        endpoint: 0.0.0.0:13133
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
  processors:
    batch:
  exporters:
    jaeger_storage_exporter:
      trace_storage: memstore
    nop:
EOF
  if helm upgrade --install jaeger "$CHART" --kubeconfig "$VKS_KUBECONFIG" -n observability \
       -f "$OBSERVABILITY_DIR/jaeger-values.yaml" --wait --timeout 10m; then
    kubectl --kubeconfig "$VKS_KUBECONFIG" -n observability get pods
  else
    echo "FAILED: helm install (see the error above)"
  fi
fi
rm -f "$CHART.new"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$CHART_VERSION = "4.13.1"
$CHART_SHA256 = "fc16f5b68572ccd0f9164219759f1102834cee6145d754ba5718596f81a5170b"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OBSERVABILITY_DIR = "$HOME\.config\vks-guides\observability"

$global:LASTEXITCODE = $null
$CHART = "$OBSERVABILITY_DIR\jaeger-$CHART_VERSION.tgz"
$URL = "https://github.com/jaegertracing/helm-charts/releases/download/jaeger-$CHART_VERSION/jaeger-$CHART_VERSION.tgz"
New-Item -ItemType Directory -Force -Path $OBSERVABILITY_DIR | Out-Null
curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$CHART.new" $URL
if ($LASTEXITCODE -ne 0) {
  "FAILED: download of $URL"
} elseif ((Get-FileHash -Algorithm SHA256 "$CHART.new").Hash -ne $CHART_SHA256) {
  "FAILED: checksum mismatch for $URL"
} else {
  Move-Item -Force "$CHART.new" $CHART
  $V = @'
jaeger:
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      memory: 512Mi
userconfig:
  service:
    extensions: [jaeger_storage, jaeger_query, healthcheckv2]
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [jaeger_storage_exporter]
      logs:
        receivers: [otlp]
        exporters: [nop]
  extensions:
    jaeger_query:
      storage:
        traces: memstore
    jaeger_storage:
      backends:
        memstore:
          memory:
            max_traces: 10000
    healthcheckv2:
      use_v2: true
      http:
        endpoint: 0.0.0.0:13133
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
  processors:
    batch:
  exporters:
    jaeger_storage_exporter:
      trace_storage: memstore
    nop:
'@
  [IO.File]::WriteAllText("$OBSERVABILITY_DIR\jaeger-values.yaml", ($V -replace "`r`n", "`n") + "`n")
  helm upgrade --install jaeger $CHART --kubeconfig $VKS_KUBECONFIG -n observability -f "$OBSERVABILITY_DIR\jaeger-values.yaml" --wait --timeout 10m
  if ($LASTEXITCODE -eq 0) {
    kubectl --kubeconfig $VKS_KUBECONFIG -n observability get pods
  } else {
    "FAILED: helm install (see the error above)"
  }
}
Remove-Item -Force -ErrorAction SilentlyContinue "$CHART.new"
```

</details>

**Expect:** `STATUS: deployed`, and pods `jaeger-…` and `loki-0` `1/1 Running`.

**If not:** as in step 3.

## 5. Send the logs to Loki

This writes `fluent-bit-values.yaml` and installs Broadcom's Fluent Bit add-on, or updates it
if you did [LOGGING.md](LOGGING.md). Fluent Bit sends every container's log lines to Loki,
labelled `namespace`, `pod`, `container` and `node`. If you did LOGGING.md, set `LOGS_FQDN` to
Log Management's DNS name from its step 3, and Fluent Bit keeps sending everything there too;
otherwise leave it empty. Set `FLUENT_BIT_RELEASE` as in LOGGING.md step 1.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
FLUENT_BIT_RELEASE="fluent-bit.kubernetes.vmware.com.5.0.9-vmware.1-vks.1"
LOGS_FQDN=""
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OBSERVABILITY_DIR="$HOME/.config/vks-guides/observability"

V="$OBSERVABILITY_DIR/fluent-bit-values.yaml"
mkdir -p "$OBSERVABILITY_DIR"
{
  cat <<'EOF'
fluent_bit:
  config:
    outputs: |
      [OUTPUT]
        Name        loki
        Match       kube.*
        Host        loki.observability.svc.cluster.local
        Port        3100
        Labels      job=fluent-bit, namespace=$namespace_name, pod=$pod_name, container=$container_name, node=$host
        Line_Format json
        Remove_Keys k8s, text
EOF
  if [ -n "$LOGS_FQDN" ]; then
    cat <<EOF
      [OUTPUT]
        Name             http
        Match            *
        Host             ${LOGS_FQDN}
        Port             9543
        URI              /api/v2/events
        Format           json
        Json_date_key    timestamp
        Json_date_format epoch_ms
        Header           Content-Type application/json
        tls              On
        tls.verify       On
        tls.ca_file      /etc/ssl/certs/tls_http.crt
  daemonset:
    secretName: tls-ca-cert
EOF
  fi
} > "$V"
vcf context use supervisor
if kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging get daemonset fluent-bit >/dev/null 2>&1; then
  vcf addon install update fluent-bit --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" -f "$V" -y \
    && sleep 30 \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging rollout restart daemonset/fluent-bit \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging rollout status daemonset/fluent-bit --timeout=10m
elif [ -n "$LOGS_FQDN" ]; then
  echo "FAILED: LOGS_FQDN is set but the add-on is not installed; do LOGGING.md first, or leave LOGS_FQDN empty"
elif vcf addon install create fluent-bit --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" \
       --addon-release-name "$FLUENT_BIT_RELEASE" -f "$V" -y; then
  n=0
  until kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging get daemonset fluent-bit >/dev/null 2>&1 || [ "$n" -ge 40 ]; do
    sleep 15; n=$((n + 1))
  done
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging rollout status daemonset/fluent-bit --timeout=10m
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$FLUENT_BIT_RELEASE = "fluent-bit.kubernetes.vmware.com.5.0.9-vmware.1-vks.1"
$LOGS_FQDN = ""
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OBSERVABILITY_DIR = "$HOME\.config\vks-guides\observability"

$global:LASTEXITCODE = $null
$V = "$OBSERVABILITY_DIR\fluent-bit-values.yaml"
New-Item -ItemType Directory -Force -Path $OBSERVABILITY_DIR | Out-Null
$T = @'
fluent_bit:
  config:
    outputs: |
      [OUTPUT]
        Name        loki
        Match       kube.*
        Host        loki.observability.svc.cluster.local
        Port        3100
        Labels      job=fluent-bit, namespace=$namespace_name, pod=$pod_name, container=$container_name, node=$host
        Line_Format json
        Remove_Keys k8s, text
'@
if ($LOGS_FQDN) {
  $T += "`n" + @"
      [OUTPUT]
        Name             http
        Match            *
        Host             $LOGS_FQDN
        Port             9543
        URI              /api/v2/events
        Format           json
        Json_date_key    timestamp
        Json_date_format epoch_ms
        Header           Content-Type application/json
        tls              On
        tls.verify       On
        tls.ca_file      /etc/ssl/certs/tls_http.crt
  daemonset:
    secretName: tls-ca-cert
"@
}
[IO.File]::WriteAllText($V, ($T -replace "`r`n", "`n") + "`n")
vcf context use supervisor
kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging get daemonset fluent-bit 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  vcf addon install update fluent-bit --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE -f $V -y
  if ($LASTEXITCODE -eq 0) {
    Start-Sleep 30
    kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging rollout restart daemonset/fluent-bit
    kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging rollout status daemonset/fluent-bit --timeout=10m
  }
} elseif ($LOGS_FQDN) {
  "FAILED: LOGS_FQDN is set but the add-on is not installed; do LOGGING.md first, or leave LOGS_FQDN empty"
} else {
  vcf addon install create fluent-bit --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE --addon-release-name $FLUENT_BIT_RELEASE -f $V -y
  if ($LASTEXITCODE -eq 0) {
    $n = 0
    do {
      if ($n -gt 0) { Start-Sleep 15 }
      kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging get daemonset fluent-bit 2>$null | Out-Null
      $n++
    } until ($LASTEXITCODE -eq 0 -or $n -gt 40)
    kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging rollout status daemonset/fluent-bit --timeout=10m
  }
}
```

</details>

**Expect:** the context lines from LOGGING.md step 1, then `Addon 'fluent-bit' is being
installed in the cluster …` (or `… is being updated`), then
`daemon set "fluent-bit" successfully rolled out`.

**If not:**
- `not found` for the release: copy its name again from LOGGING.md step 1.
- `Unauthorized` or `context supervisor not found`: as in LOGGING.md step 1.
- The rollout times out: run
  `kubectl --kubeconfig <the VKS kubeconfig> -n tanzu-system-logging get pods` and `describe` the
  one that is not `Running`.

Fluent Bit's own log shows `error opening plugin /path/to/out_gstdout.so` and, right after it
starts, `paused (mem buf overlimit …)`. Both come with the add-on and do no harm.

If you run LOGGING.md step 7 later, it sends logs only to Log Management again; run this step
after it.

## 6. Run the sample app

This runs podinfo 6.15.0 with a ServiceMonitor, so Prometheus scrapes it, and a second pod that
calls podinfo every two seconds, half the calls ending in an error. podinfo writes a JSON log
line with a trace ID for each call and sends the trace to Jaeger.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
  namespace: podinfo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: podinfo
  template:
    metadata:
      labels:
        app: podinfo
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.15.0@sha256:ec73780a8425f59ea49f5bc8cdff0d598805a224fbaa1f86c67a244f250fa9da
          command: ["./podinfo", "--port=9898", "--level=debug", "--otel-service-name=podinfo"]
          env:
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: http://jaeger.observability.svc.cluster.local:4317
          ports:
            - name: http
              containerPort: 9898
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
---
apiVersion: v1
kind: Service
metadata:
  name: podinfo
  namespace: podinfo
  labels:
    app: podinfo
spec:
  selector:
    app: podinfo
  ports:
    - name: http
      port: 9898
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loadgen
  namespace: podinfo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loadgen
  template:
    metadata:
      labels:
        app: loadgen
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: loadgen
          image: ghcr.io/stefanprodan/podinfo:6.15.0@sha256:ec73780a8425f59ea49f5bc8cdff0d598805a224fbaa1f86c67a244f250fa9da
          command: ["sh", "-c", "while true; do curl -s -o /dev/null http://podinfo.podinfo:9898/; curl -s -o /dev/null http://podinfo.podinfo:9898/status/500; sleep 2; done"]
          resources:
            requests:
              cpu: 5m
              memory: 16Mi
            limits:
              memory: 64Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: podinfo
  namespace: podinfo
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: podinfo
  endpoints:
    - port: http
      path: /metrics
EOF
kubectl --kubeconfig "$VKS_KUBECONFIG" -n podinfo rollout status deployment/podinfo deployment/loadgen --timeout=5m
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

@'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
  namespace: podinfo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: podinfo
  template:
    metadata:
      labels:
        app: podinfo
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.15.0@sha256:ec73780a8425f59ea49f5bc8cdff0d598805a224fbaa1f86c67a244f250fa9da
          command: ["./podinfo", "--port=9898", "--level=debug", "--otel-service-name=podinfo"]
          env:
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: http://jaeger.observability.svc.cluster.local:4317
          ports:
            - name: http
              containerPort: 9898
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
---
apiVersion: v1
kind: Service
metadata:
  name: podinfo
  namespace: podinfo
  labels:
    app: podinfo
spec:
  selector:
    app: podinfo
  ports:
    - name: http
      port: 9898
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loadgen
  namespace: podinfo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loadgen
  template:
    metadata:
      labels:
        app: loadgen
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: loadgen
          image: ghcr.io/stefanprodan/podinfo:6.15.0@sha256:ec73780a8425f59ea49f5bc8cdff0d598805a224fbaa1f86c67a244f250fa9da
          command: ["sh", "-c", "while true; do curl -s -o /dev/null http://podinfo.podinfo:9898/; curl -s -o /dev/null http://podinfo.podinfo:9898/status/500; sleep 2; done"]
          resources:
            requests:
              cpu: 5m
              memory: 16Mi
            limits:
              memory: 64Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: podinfo
  namespace: podinfo
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: podinfo
  endpoints:
    - port: http
      path: /metrics
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
kubectl --kubeconfig $VKS_KUBECONFIG -n podinfo rollout status deployment/podinfo deployment/loadgen --timeout=5m
```

</details>

**Expect:** `deployment.apps/podinfo created`, `service/podinfo created`,
`deployment.apps/loadgen created`, `servicemonitor.monitoring.coreos.com/podinfo created`, then
both deployments `successfully rolled out`.

**If not:**
- `namespaces "podinfo" not found`: run step 2.
- `no matches for kind "ServiceMonitor"`: do MONITORING.md first.
- A pod in `ImagePullBackOff`: the nodes cannot reach `ghcr.io`.

## 7. Check that the signals arrive

Wait a minute after step 6. This asks Prometheus, Loki and Jaeger, through the cluster's API
server, what they have from podinfo.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

P=/api/v1/namespaces
echo "Prometheus targets up: $(kubectl --kubeconfig "$VKS_KUBECONFIG" get --raw "$P/monitoring/services/prometheus-kube-prometheus-prometheus:9090/proxy/api/v1/query?query=up%7Bnamespace%3D%22podinfo%22%7D" | jq -r '[.data.result[] | select(.value[1] == "1")] | length')"
echo "Loki log streams: $(kubectl --kubeconfig "$VKS_KUBECONFIG" get --raw "$P/observability/services/loki:3100/proxy/loki/api/v1/series?match%5B%5D=%7Bnamespace%3D%22podinfo%22%7D" | jq -r '.data | length')"
echo "Jaeger services: $(kubectl --kubeconfig "$VKS_KUBECONFIG" get --raw "$P/observability/services/jaeger:16686/proxy/api/services" | jq -r '.data | join(" ")')"
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$P = "/api/v1/namespaces"
$R = kubectl --kubeconfig $VKS_KUBECONFIG get --raw "$P/monitoring/services/prometheus-kube-prometheus-prometheus:9090/proxy/api/v1/query?query=up%7Bnamespace%3D%22podinfo%22%7D" | Out-String | ConvertFrom-Json
"Prometheus targets up: $(@($R.data.result | Where-Object { $_.value[1] -eq '1' }).Count)"
$R = kubectl --kubeconfig $VKS_KUBECONFIG get --raw "$P/observability/services/loki:3100/proxy/loki/api/v1/series?match%5B%5D=%7Bnamespace%3D%22podinfo%22%7D" | Out-String | ConvertFrom-Json
"Loki log streams: $(@($R.data).Count)"
$R = kubectl --kubeconfig $VKS_KUBECONFIG get --raw "$P/observability/services/jaeger:16686/proxy/api/services" | Out-String | ConvertFrom-Json
"Jaeger services: $($R.data -join ' ')"
```

**Expect:** `Prometheus targets up: 1`, `Loki log streams:` 1 or more, and `Jaeger services:` with
`podinfo` in the list.

**If not:**
- `Prometheus targets up: 0`: wait a minute and run it again.
- `Loki log streams: 0`: step 5 did not finish; run its `rollout status` line again.
- `Jaeger services:` without `podinfo`: check podinfo's log for `failed to export`
  (`kubectl --kubeconfig <the VKS kubeconfig> -n podinfo logs deployment/podinfo`).

## 8. Add Loki and Jaeger to Grafana

This adds the data sources `Loki` and `Jaeger` to Grafana. A ConfigMap carries them; Grafana
loads it within a minute, without a restart. Each log line with a trace ID links to its trace,
and each trace links to its log lines.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: observability-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  observability.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        uid: loki
        access: proxy
        url: http://loki.observability.svc.cluster.local:3100
        jsonData:
          derivedFields:
            - name: TraceID
              datasourceUid: jaeger
              matcherRegex: 'trace_id\\?":\\?"(\w+)'
              url: '$${__value.raw}'
              urlDisplayLabel: View trace
      - name: Jaeger
        type: jaeger
        uid: jaeger
        access: proxy
        url: http://jaeger.observability.svc.cluster.local:16686
        jsonData:
          tracesToLogsV2:
            datasourceUid: loki
            spanStartTimeShift: '-5m'
            spanEndTimeShift: '5m'
            customQuery: true
            query: '{job="fluent-bit"} |= "$${__trace.traceId}"'
EOF
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

@'
apiVersion: v1
kind: ConfigMap
metadata:
  name: observability-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  observability.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        uid: loki
        access: proxy
        url: http://loki.observability.svc.cluster.local:3100
        jsonData:
          derivedFields:
            - name: TraceID
              datasourceUid: jaeger
              matcherRegex: 'trace_id\\?":\\?"(\w+)'
              url: '$${__value.raw}'
              urlDisplayLabel: View trace
      - name: Jaeger
        type: jaeger
        uid: jaeger
        access: proxy
        url: http://jaeger.observability.svc.cluster.local:16686
        jsonData:
          tracesToLogsV2:
            datasourceUid: loki
            spanStartTimeShift: '-5m'
            spanEndTimeShift: '5m'
            customQuery: true
            query: '{job="fluent-bit"} |= "$${__trace.traceId}"'
'@ | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
```

**Expect:** `configmap/observability-datasources created`.

**If not:** `namespaces "monitoring" not found`: do MONITORING.md first.

## 9. Look in Grafana

Run MONITORING.md step 7 to open Grafana, then:

1. **Connections** → **Data sources** lists `Loki` and `Jaeger`. Open each and click **Test**.

   ![Grafana data sources](img/observability/01-grafana-data-sources.jpg)

2. **Explore**, data source **Loki**, query `{container="podinfo"}`, **Run query**. Click a line,
   then under **Links** click **View trace**.

   ![A podinfo log line with its trace link](img/observability/02-grafana-log-trace-link.jpg)

   ![The trace opened from the log line](img/observability/03-grafana-log-to-trace.jpg)

3. In the trace, click the `podinfo` span, then **Related logs**.

   ![The log line opened from the trace](img/observability/04-grafana-trace-related-logs.jpg)

4. **Explore**, data source **Prometheus**, query
   `sum by (status) (rate(http_requests_total{namespace="podinfo"}[5m]))`, **Run query**.

   ![podinfo requests by status](img/observability/05-grafana-prometheus-podinfo.jpg)

**Expect:** Loki `Data source successfully connected` and Jaeger `Data source is working`; log
lines from podinfo whose **View trace** opens a trace of two spans; **Related logs** shows the line
with that trace ID; and two series, `200` and `500`.

**If not:**
- `Loki` or `Jaeger` missing: wait a minute after step 8, then reload the page.
- Jaeger's test says `404 Not Found`: Jaeger is 2.21 or later; install the chart version from
  step 4.

## 10. See the cluster in VCF Operations

VCF Operations shows the VKS cluster and its node VMs through its vSphere Supervisor
integration; nothing runs in the cluster for it. In VCF Operations:

1. In the search box at the top, type the cluster's name; under **VKS Cluster**, click it. This
   opens **Operate** → **Inventory** on the cluster's **Summary**.

   ![Search for the VKS cluster](img/observability/06-ops-search.jpg)

   ![The VKS cluster in VCF Operations](img/observability/07-ops-vks-cluster.jpg)

2. In the tree on the left, expand **Virtual Machine**, click a node, then **Details**.

   ![A node VM in VCF Operations](img/observability/08-ops-node-vm.jpg)

3. Open **Metrics**, type `Usage` in the metric search, and double-click **CPU** →
   **Usage (MHz)** and **Memory** → **Usage (%)**.

   ![A node VM's CPU and memory](img/observability/09-ops-node-vm-metrics.jpg)

**Expect:** the search lists the cluster under **VKS Cluster**, its resource pool, its node VMs
and the nodes' volumes; each node VM `Powered On` with its CPU and memory use, and both charts.
The cluster's own CPU, memory and pod counts stay empty: `No data to display` and `0`.

**If not:**
- **Home** and the **Inventory** tree show nothing (`No results found`): use the search box.
- The search finds no **VKS Cluster**: ask your VCF Operations administrator to turn on
  **Enable vSphere Supervisor Collection** on the vCenter account (**Administration** →
  **Integrations** → **Accounts**).

## 11. Uninstall (optional)

**This deletes the logs in Loki and the traces in Jaeger.** It removes the sample app, the data
sources (Grafana restarts to drop them), Jaeger, Loki and its volume, and the namespaces.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace podinfo --ignore-not-found
kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring delete configmap observability-datasources --ignore-not-found
kubectl --kubeconfig "$VKS_KUBECONFIG" -n monitoring rollout restart deployment/prometheus-grafana
helm uninstall jaeger loki --kubeconfig "$VKS_KUBECONFIG" -n observability
kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace observability --ignore-not-found
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG delete namespace podinfo --ignore-not-found
kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring delete configmap observability-datasources --ignore-not-found
kubectl --kubeconfig $VKS_KUBECONFIG -n monitoring rollout restart deployment/prometheus-grafana
helm uninstall jaeger loki --kubeconfig $VKS_KUBECONFIG -n observability
kubectl --kubeconfig $VKS_KUBECONFIG delete namespace observability --ignore-not-found
```

**Expect:** `namespace "podinfo" deleted`, `configmap "observability-datasources" deleted …`,
`deployment.apps/prometheus-grafana restarted`, `release "jaeger" uninstalled`, `release "loki" uninstalled` and
`namespace "observability" deleted`.

**If not:** `Release not loaded`: it was already uninstalled.

Then, for Fluent Bit: if you did LOGGING.md, run its step 7 to send logs only to Log
Management; otherwise remove the add-on with LOGGING.md step 8.

Back to [README](../README.md).
