# Send a VKS cluster's logs to VCF Operations

> [!NOTE]
> **Official Broadcom documentation (VCF 9.1 and 9.0) for this guide**
>
> - [Install Fluent Bit Addon using VCF CLI](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/installing-standard-packages-on-tkg-cluster-using-tkr-for-vsphere-8-x/install-fluent-bit/install-fluent-bit-addon.html) (VCF 9.0 page; there is no 9.1 copy)
> - [Fluent Bit Package Reference](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/installing-standard-packages-on-tkg-service-clusters/standard-package-reference/fluent-bit-package-reference.html) (the values and the CA Secret; VCF 9.0 page)
> - [VKS Add-ons Release Notes](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-addons-release-notes.html) (Fluent Bit versions and support tier)
> - [Log Collection Architecture](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/infrastructure-operations/log-analysis/centralized-log-collection-architecture.html) (Log Management in VCF Operations)
> - [Set up the Windows system to collect logs in VCF Operations](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/infrastructure-operations/log-analysis/overview-of-log-management-agents/install-fluent-bit-on-windows-server-for-vcf-operations-for-logs.html) (the Fluent Bit output this guide uses)
> - [Agent Authentication for Log Ingestion](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/infrastructure-operations/log-analysis/overview-of-log-management-agents/agent-authentication-for-log-ingestion.html)

This installs Broadcom's Fluent Bit add-on (Product tier) on a VKS cluster. It runs on every
node and sends the cluster's logs over HTTPS, with certificate verification, to Log Management
in VCF Operations, where they appear under **Operate** → **Logs**.

You need:

- the [VCF CLI](VCF.md) with its plugins, a [Supervisor login](LOGIN.md) and the VKS cluster's
  kubeconfig
  ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig));
- Log Management's DNS name and the CA certificate (PEM) that signed its certificate, from your
  VCF Operations administrator;
- ingestion authentication not enforced in Log Management (the default);
- nodes that reach Log Management on port 9543.

The blocks keep their files in `~/.config/vks-guides/logging` (PowerShell:
`$HOME\.config\vks-guides\logging`).

## 1. Find the Fluent Bit release

This lists the Fluent Bit releases the Supervisor offers and the add-ons the cluster already has.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"

vcf context use supervisor </dev/null
vcf addon available-releases list --addon-name fluent-bit
vcf addon install list --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE"
```

**Windows (PowerShell):**

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"

$null | vcf context use supervisor
vcf addon available-releases list --addon-name fluent-bit
vcf addon install list --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE
```

**Expect:** `Successfully activated context 'supervisor'`, then one or more releases named
`fluent-bit.kubernetes.vmware.com.<version>`; copy the newest one's name for step 4. The
cluster's list has no `fluent-bit`. A line `failed to discover plugin sources from the system
Harbor registry` may follow the context line; it does no harm here.

**If not:**
- `Unauthorized`, `Unable to read password from terminal` or `provide credentials`: your
  Supervisor login ended; run [Renew the Supervisor login](LOGIN.md#renew-the-supervisor-login).
- `context supervisor not found`: create the Supervisor context ([LOGIN.md](LOGIN.md)).
- The cluster's list already has `fluent-bit`: it is installed; to change where it sends logs,
  see step 7.

## 2. Check Log Management's certificate

Save the CA certificate as `~/.config/vks-guides/logging/logs-ca.crt` (PowerShell:
`$HOME\.config\vks-guides\logging\logs-ca.crt`). This prints its fingerprint for you to compare
with your administrator's, and checks that Log Management at its DNS name answers with a
certificate this CA signed for that name.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
LOGS_FQDN="logs.example.test"
LOGGING_DIR="$HOME/.config/vks-guides/logging"

CA="$LOGGING_DIR/logs-ca.crt"
if [ ! -s "$CA" ]; then
  echo "FAILED: not found: $CA"
elif ! openssl x509 -in "$CA" -noout -subject -fingerprint -sha256; then
  echo "FAILED: $CA is not a PEM certificate"
else
  H="$(curl -s --cacert "$CA" --connect-timeout 20 --max-time 30 -o /dev/null -w '%{http_code}' "https://${LOGS_FQDN}:9543/api/v2/events")"
  echo "Log Management at https://${LOGS_FQDN}:9543 with this CA: http=$H"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$LOGS_FQDN = "logs.example.test"
$LOGGING_DIR = "$HOME\.config\vks-guides\logging"

$CA = "$LOGGING_DIR\logs-ca.crt"
if (-not (Test-Path $CA)) {
  "FAILED: not found: $CA"
} else {
  try {
    $X = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $CA
    $F = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($X.RawData))
    "subject=$($X.Subject)"
    "sha256 Fingerprint=$($F.Replace('-', ':'))"
    $H = curl.exe -s --ssl-no-revoke --cacert $CA --connect-timeout 20 --max-time 30 -o NUL -w '%{http_code}' "https://${LOGS_FQDN}:9543/api/v2/events"
    "Log Management at https://${LOGS_FQDN}:9543 with this CA: http=$H"
  } catch {
    "FAILED: $CA is not a PEM certificate"
  }
}
```

</details>

**Expect:** the CA's `subject=` and `sha256 Fingerprint=…` (`SHA256 Fingerprint=` on macOS), then an `http=` code other than
`000`: the connection and the certificate are good, whatever the code.

**If not:** `http=000`: this machine cannot reach the name on port 9543, or Log Management's
certificate was not signed by this CA or not issued for this name. Run
`curl -v --cacert <the CA file> https://<the name>:9543/api/v2/events` and read the error; ask
your administrator for the right CA, or a certificate issued for the name.

## 3. Write the values

This writes `values.yaml` with the output from Broadcom's VCF 9.1 Fluent Bit example. The
add-on keeps its own inputs, filters and parsers.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
LOGS_FQDN="logs.example.test"
LOGGING_DIR="$HOME/.config/vks-guides/logging"

case "$LOGS_FQDN" in ""|logs.example.test) BAD_NAME=1 ;; *) BAD_NAME="" ;; esac
[ -z "$(printf '%s' "$LOGS_FQDN" | LC_ALL=C tr -d 'a-z0-9.-')" ] || BAD_NAME=1
if [ -n "$BAD_NAME" ]; then
  echo "NOT WRITTEN: set LOGS_FQDN to Log Management's DNS name"
else
  mkdir -p "$LOGGING_DIR"
  cat > "$LOGGING_DIR/values.yaml" <<EOF
fluent_bit:
  config:
    outputs: |
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
  echo "values: $LOGGING_DIR/values.yaml (Host ${LOGS_FQDN})"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$LOGS_FQDN = "logs.example.test"
$LOGGING_DIR = "$HOME\.config\vks-guides\logging"

if ($LOGS_FQDN -cnotmatch '^[a-z0-9.-]+$' -or $LOGS_FQDN -eq 'logs.example.test') {
  "NOT WRITTEN: set LOGS_FQDN to Log Management's DNS name"
} else {
  New-Item -ItemType Directory -Force -Path $LOGGING_DIR | Out-Null
  $V = @"
fluent_bit:
  config:
    outputs: |
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
  [IO.File]::WriteAllText("$LOGGING_DIR\values.yaml", ($V -replace "`r`n", "`n") + "`n")
  "values: $LOGGING_DIR\values.yaml (Host $LOGS_FQDN)"
}
```

</details>

**Expect:** `values: …values.yaml (Host <your Log Management name>)`.

## 4. Install the add-on

Set `FLUENT_BIT_RELEASE` to the release name from step 1.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
FLUENT_BIT_RELEASE="fluent-bit.kubernetes.vmware.com.5.1.2-vmware.1-vks.1"
LOGGING_DIR="$HOME/.config/vks-guides/logging"

vcf context use supervisor </dev/null
vcf addon install create fluent-bit --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" \
  --addon-release-name "$FLUENT_BIT_RELEASE" -f "$LOGGING_DIR/values.yaml" -y
```

**Windows (PowerShell):**

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$FLUENT_BIT_RELEASE = "fluent-bit.kubernetes.vmware.com.5.1.2-vmware.1-vks.1"
$LOGGING_DIR = "$HOME\.config\vks-guides\logging"

$null | vcf context use supervisor
vcf addon install create fluent-bit --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE --addon-release-name $FLUENT_BIT_RELEASE -f "$LOGGING_DIR\values.yaml" -y
```

**Expect:** the context lines from step 1, then `Addon 'fluent-bit' is being installed in the cluster …`.

**If not:**
- `not found` for the release: copy its name again from step 1.
- A login error (`Unauthorized`, `Unable to read password from terminal`,
  `provide credentials`) or `context supervisor not found`: as in step 1.

## 5. Give Fluent Bit the CA

The add-on creates the namespace `tanzu-system-logging` in the VKS cluster. This waits for it,
then stores the CA there as the Secret `tls-ca-cert`, which the Fluent Bit pods wait for.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
LOGGING_DIR="$HOME/.config/vks-guides/logging"

n=0
until kubectl --kubeconfig "$VKS_KUBECONFIG" get namespace tanzu-system-logging >/dev/null 2>&1 || [ "$n" -ge 40 ]; do
  sleep 15; n=$((n + 1))
done
if ! kubectl --kubeconfig "$VKS_KUBECONFIG" get namespace tanzu-system-logging >/dev/null 2>&1; then
  echo "FAILED: no namespace tanzu-system-logging after 10 minutes (step 4)"
elif kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging get secret tls-ca-cert 2>/dev/null \
     || kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging create secret generic tls-ca-cert \
          --from-file=tls_http.crt="$LOGGING_DIR/logs-ca.crt" --save-config; then
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging rollout status daemonset/fluent-bit --timeout=10m
else
  echo "FAILED: Secret not created (see the error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$LOGGING_DIR = "$HOME\.config\vks-guides\logging"

$global:LASTEXITCODE = $null
$n = 0
do {
  if ($n -gt 0) { Start-Sleep 15 }
  kubectl --kubeconfig $VKS_KUBECONFIG get namespace tanzu-system-logging 2>$null | Out-Null
  $n++
} until ($LASTEXITCODE -eq 0 -or $n -gt 40)
if ($LASTEXITCODE -ne 0) {
  "FAILED: no namespace tanzu-system-logging after 10 minutes (step 4)"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging get secret tls-ca-cert 2>$null
  if ($LASTEXITCODE -ne 0) {
    kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging create secret generic tls-ca-cert --from-file=tls_http.crt="$LOGGING_DIR\logs-ca.crt" --save-config
  }
  if ($LASTEXITCODE -eq 0) {
    kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging rollout status daemonset/fluent-bit --timeout=10m
  } else {
    "FAILED: Secret not created (see the error above)"
  }
}
```

</details>

**Expect:** `secret/tls-ca-cert created` (or, on a rerun, the existing `tls-ca-cert` listed), then
`daemon set "fluent-bit" successfully rolled out`.

**If not:** the rollout times out: run
`kubectl --kubeconfig <the VKS kubeconfig> -n tanzu-system-logging get pods` and `describe` the
one that is not `Running`.

## 6. Check that logs arrive

This runs a pod that writes a line with a unique word into the cluster's logs, and shows what
Fluent Bit reports about sending.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

WORD="vks-guides-$(date +%s)"
kubectl --kubeconfig "$VKS_KUBECONFIG" -n default delete pod log-check --ignore-not-found
kubectl --kubeconfig "$VKS_KUBECONFIG" -n default apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: log-check
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: log-check
      image: busybox:1.37
      args: ["echo", "$WORD"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF
echo "search for: $WORD"
sleep 30
kubectl --kubeconfig "$VKS_KUBECONFIG" -n default logs log-check
kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging logs daemonset/fluent-bit --since=5m | grep -E 'HTTP status|error|warn' | tail -5
kubectl --kubeconfig "$VKS_KUBECONFIG" -n default delete pod log-check
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$WORD = "vks-guides-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
kubectl --kubeconfig $VKS_KUBECONFIG -n default delete pod log-check --ignore-not-found
@"
apiVersion: v1
kind: Pod
metadata:
  name: log-check
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: log-check
      image: busybox:1.37
      args: ["echo", "$WORD"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
"@ | kubectl --kubeconfig $VKS_KUBECONFIG -n default apply -f -
"search for: $WORD"
Start-Sleep 30
kubectl --kubeconfig $VKS_KUBECONFIG -n default logs log-check
kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging logs daemonset/fluent-bit --since=5m | Select-String 'HTTP status|error|warn' | Select-Object -Last 5
kubectl --kubeconfig $VKS_KUBECONFIG -n default delete pod log-check
```

</details>

Then in VCF Operations, open **Operate** → **Logs**, set the time range to the last 15 minutes
and search for the word the block printed.

**Expect:** `pod/log-check created`, `search for: vks-guides-…`, the word itself (the pod's log),
Fluent Bit lines with `HTTP status=200`, and the word in **Operate** → **Logs** within a few
minutes.

**If not:**
- `HTTP status=401` or another `4xx`: Log Management refuses the logs; ask your administrator
  whether ingestion authentication is enforced (this guide needs it not enforced).
- `HTTP status=200` but the word is not in **Operate** → **Logs**: widen the time range; then ask
  your administrator whether ingestion authentication is enforced, which drops logs without a
  token.
- `no upstream connections available` or a `tls` error: the nodes cannot reach Log Management on
  port 9543, or the Secret holds the wrong CA (save the right one as step 2 says, then run step 7).
- The pod's log says `waiting to start`: the nodes cannot pull `busybox:1.37` from `docker.io`;
  the Fluent Bit lines still apply.

## 7. Change the destination (optional)

Run step 2 and step 3 with the new name, then this. It replaces the CA in the cluster, updates the
add-on and restarts Fluent Bit. If you did [OBSERVABILITY.md](OBSERVABILITY.md) step 5, run its
step 5 after this block, with `LOGS_FQDN` set to the new name; this block alone stops the logs to
Loki.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
LOGGING_DIR="$HOME/.config/vks-guides/logging"

CA="$LOGGING_DIR/logs-ca.crt"
if [ ! -s "$CA" ]; then
  echo "FAILED: not found: $CA (step 2)"
else
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging create secret generic tls-ca-cert \
    --from-file=tls_http.crt="$CA" --dry-run=client -o yaml \
    | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f -
  vcf context use supervisor </dev/null
  if vcf addon install update fluent-bit --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" \
       -f "$LOGGING_DIR/values.yaml" -y; then
    sleep 30
    kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging rollout restart daemonset/fluent-bit
    kubectl --kubeconfig "$VKS_KUBECONFIG" -n tanzu-system-logging rollout status daemonset/fluent-bit --timeout=10m
  else
    echo "FAILED: add-on update (see the error above)"
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
$LOGGING_DIR = "$HOME\.config\vks-guides\logging"

$CA = "$LOGGING_DIR\logs-ca.crt"
if (-not (Test-Path $CA)) {
  "FAILED: not found: $CA (step 2)"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging create secret generic tls-ca-cert --from-file=tls_http.crt="$CA" --dry-run=client -o yaml |
    kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
  $null | vcf context use supervisor
  vcf addon install update fluent-bit --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE -f "$LOGGING_DIR\values.yaml" -y
  if ($LASTEXITCODE -eq 0) {
    Start-Sleep 30
    kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging rollout restart daemonset/fluent-bit
    kubectl --kubeconfig $VKS_KUBECONFIG -n tanzu-system-logging rollout status daemonset/fluent-bit --timeout=10m
  } else {
    "FAILED: add-on update (see the error above)"
  }
}
```

</details>

**Expect:** `secret/tls-ca-cert configured` (or `unchanged`), the context lines
from step 1, `Addon 'fluent-bit' in the cluster … is being updated`, then
`daemon set "fluent-bit" successfully rolled out`. Wait a minute, as the pods may restart once more,
then run step 6 again.

**If not:**
- `FAILED: not found`: save the CA as step 2 says.
- `FAILED: add-on update`: the error above it says why.
- A login error (`Unauthorized`, `Unable to read password from terminal`,
  `provide credentials`) or `context supervisor not found`: as in step 1.

## 8. Uninstall (optional)

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"

vcf context use supervisor </dev/null
vcf addon install delete fluent-bit --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE" -y
```

**Windows (PowerShell):**

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"

$null | vcf context use supervisor
vcf addon install delete fluent-bit --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE -y
```

**Expect:** the context lines from step 1, then
`Addon 'fluent-bit' installed in the cluster … has been deleted`; the Fluent Bit pods go away
within a minute.

**If not:** a login error (`Unauthorized`, `Unable to read password from terminal`,
`provide credentials`) or `context supervisor not found`: as in step 1.

Back to [README](../README.md).
