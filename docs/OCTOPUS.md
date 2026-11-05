# Run Octopus Deploy in a VKS cluster

> [!NOTE]
> **Official Broadcom, Octopus, Microsoft, cert-manager and Kubernetes documentation for this guide**
>
> - Broadcom: [Install an Add-on Using the VCF CLI](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/install-an-add-on-using-the-vcf-cli.html) (cert-manager)
> - Octopus: [Octopus Deploy Helm chart](https://github.com/OctopusDeploy/helm-charts/blob/main/charts/octopus-deploy/README.md), [SQL Server database](https://octopus.com/docs/installation/sql-database), [Performance](https://octopus.com/docs/administration/managing-infrastructure/performance) (sizing), [Master key](https://octopus.com/docs/security/data-encryption), [Environments](https://octopus.com/docs/infrastructure/environments), [Lifecycles](https://octopus.com/docs/releases/lifecycles), [Docker feeds](https://octopus.com/docs/packaging-applications/package-repositories/docker-registries)
> - Microsoft: [SQL Server on Linux containers](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-deployment), [Editions of SQL Server 2025](https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2025)
> - cert-manager: [CA issuer](https://cert-manager.io/docs/configuration/ca/), [SelfSigned issuer](https://cert-manager.io/docs/configuration/selfsigned/)
> - Kubernetes: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) (`restricted`)

Octopus Deploy is a server that releases software to environments such as dev, test and prod, in
order and with approvals. This runs Octopus Server, with Microsoft SQL Server Express for its
data, in a VKS cluster, gives its web page an HTTPS certificate and an address, and creates the
environments dev, test and prod with a lifecycle that promotes releases through them.

Octopus has two addresses: its web page and REST API on port 443 (`octopus-web`, behind a small
nginx that holds the certificate), and its gRPC port 8443 (`octopus-grpc`), which keeps Octopus's
own certificate and is used by Octopus agents such as the Argo CD gateway. Port 80 (plain HTTP) is
on neither.

Every password and key goes into a Kubernetes Secret (a store for passwords and keys inside the
cluster) through a pipe: none is shown or put on a command line, and none is saved in a file you
did not ask for (on Windows, the sign-in in steps 9 and 10 uses a temporary file that the block
deletes). Nothing secret goes into Helm.

Run the steps in order. Steps 11 to 13 are for later.

## Prerequisites

- a VKS cluster for Octopus, made as below;
- the [VCF CLI](VCF.md) with the context `SUPERVISOR_CONTEXT` ([LOGIN.md](LOGIN.md)),
  for the cert-manager add-on (step 2);
- [kubectl](KUBECTL.md), [Helm](HELM.md), and [jq, curl and openssl](PREREQS.md);
- two free load-balancer addresses, one for each Service (step 4);
- an Octopus licence key, saved as a file: sign up for the free licence
  ([Octopus pricing](https://octopus.com/pricing): 10 projects, 10 deployment targets, 5 tasks at a
  time, 1 space) and save the licence key text (it starts with `<License`) as
  `octopus-license.xml` in your home folder;
- for step 11 only: Nexus from [NEXUS.md](NEXUS.md), its `nexus-ca.pem`
  ([NEXUS.md step 7](NEXUS.md#7-save-nexuss-ca-and-check-its-address)) and the image it pushes
  ([NEXUS.md step 10](NEXUS.md#10-trust-nexus-and-push-an-image)).

Sizing. Octopus recommends, for a trial, 2 cores and 4 GB of memory for Octopus Server and 2 cores
and 4 GB for SQL Server Express
([Performance](https://octopus.com/docs/administration/managing-infrastructure/performance)). This
guide's manifests ask for 0.4 CPU and 2 GiB for Octopus (at most 3 GiB), 0.2 CPU and 2 GiB for SQL
Server (at most 3 GiB, of which SQL Server uses at most 2 GB) and a little for nginx, 0.65 CPU in all,
from what they used on VKS workers: Octopus typically 0.4 to 0.5 CPU, up to 1.4 while it deployed
many releases and 1.8 at its first start, and 1.1 GiB at most; SQL Server about 0.1 CPU, 0.8 CPU at
its first start, and 0.9 GiB. The smallest standard worker they fit on has 2 CPUs and 8 GB (for
example the VM class `best-effort-medium` or `guaranteed-medium`). Step 1 shows what is left on each worker. The
images are for amd64 nodes only, and need about 8 GiB of the worker's image disk.

The cluster for Octopus:

1. Its vSphere Namespace offers a VM class with at least 2 CPUs and 8 GB, such as
   `best-effort-medium` ([NAMESPACE.md step 8](NAMESPACE.md#8-check-the-namespace) lists them under
   `VM classes:`; a vCenter administrator adds one with [NAMESPACE.md step
   6](NAMESPACE.md#6-add-the-vm-classes)).
2. Create the cluster with
   [CLUSTER.md step 9](CLUSTER.md#9-create-the-cluster-with-kubectl-and-a-yaml-file), with that
   `vmClass`, one control-plane node and one worker (`replicas: 1` for both). Octopus's volumes take
   about 15 GiB (SQL Server 10 GiB, and Octopus's `package-repository-claim`, `artifacts-claim`,
   `task-log-claim`, `audit-log-claim` and its server log, 1 GiB each) on top of
   the nodes ([CLUSTER.md step 2](CLUSTER.md#2-choose-a-name-and-the-values)). A worker's image disk
   is about 15 GiB; when other applications share the worker, give it its own disk for container
   images with the `workers:` part in [CICD.md's Prerequisites](CICD.md#prerequisites).
3. Save its kubeconfig as `~/.kube/<cluster name>.kubeconfig`
   ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig)); it is `<file>` in the **If not:** lines.

SQL Server. Octopus supports SQL Server versions that have at least two years of support left
([SQL Server database](https://octopus.com/docs/installation/sql-database)), and the free Express
edition. This guide runs SQL Server 2025 Express (a database of up to 50 GB), in the cluster, with
its own volume.

The connections this guide needs, for a firewall (all TCP, besides DNS; for a registry, also
[its other hosts](PREREQS.md#registry-hosts-for-a-firewall)):

| from | to | port | for |
|---|---|---|---|
| your machine (laptop or jump box) | the Supervisor's address | 443 | the VCF CLI (step 2) |
| your machine (laptop or jump box) | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl and Helm (all steps) |
| your machine (laptop or jump box) | `ghcr.io` | 443 | the Octopus Helm chart (step 7) |
| the cluster's nodes | `projects.packages.broadcom.com` | 443 | the cert-manager add-on (step 2) |
| the cluster's nodes | `mcr.microsoft.com` | 443 | the SQL Server image (step 6) |
| the cluster's nodes | `docker.io` | 443 | the Octopus and nginx images (step 7) |
| your machine and your browser | `octopus-web`'s address (step 4) | 443 | Octopus's web page and REST API (steps 8 to 11) |
| Octopus agents (the Argo CD gateway) | `octopus-web`'s address and `octopus-grpc`'s address (step 4) | 443 and 8443 | Octopus's REST API and gRPC, only if you connect Argo CD later |
| the cluster's nodes | Nexus's address | 443 | the Docker feed (step 11) |
| the cluster's nodes | the hosts in [Octopus's outbound requests](https://octopus.com/docs/security/outbound-requests) | 443 | updates, step templates, telemetry (optional) |

## 1. Check the cluster

Run this first, to see whether the cluster can hold Octopus before you install anything. It only
reads: it checks that the nodes are ready, that the cluster has a default storage class (the
setting that gives pods, the containers that run in the cluster, their disks from vSphere storage)
and that no namespace `octopus` (a namespace inside the VKS cluster) exists yet, and it shows the
free memory, CPU and image disk on each worker. You get one line per worker to compare with what
Octopus needs: Octopus, SQL Server, nginx and the cert-manager add-on of step 2 ask for about 0.7
CPU and 4.3 GiB of memory (pods already in the namespaces `octopus` and `cert-manager` are not
counted as using any). Set `VKS_CLUSTER` to the name of Octopus's cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

WORKERS='!node-role.kubernetes.io/control-plane'
if ! command -v kubectl >/dev/null 2>&1; then echo "MISSING: kubectl (KUBECTL.md)"
elif ! command -v jq >/dev/null 2>&1; then echo "MISSING: jq (PREREQS.md)"
elif ! command -v helm >/dev/null 2>&1; then echo "MISSING: helm (HELM.md)"
elif [ ! -s "$VKS_KUBECONFIG" ]; then echo "MISSING: $VKS_KUBECONFIG (LOGIN.md)"
elif kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes -o wide \
     && N="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes -l "$WORKERS" --no-headers -o 'custom-columns=NAME:.metadata.name,MEM:.status.allocatable.memory,CPU:.status.allocatable.cpu')" \
     && P="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get pods -A --field-selector=status.phase!=Succeeded,status.phase!=Failed --no-headers -o 'custom-columns=NS:.metadata.namespace,NODE:.spec.nodeName,MEM:.spec.containers[*].resources.requests.memory,CPU:.spec.containers[*].resources.requests.cpu')" \
     && J="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get storageclass -o json)"; then
  [ -n "$N" ] || echo "NO WORKER: this cluster has no worker node"
  { printf '%s\n' "$P" | sed 's/^/P /'; printf '%s\n' "$N" | sed 's/^/N /'; } | awk '
    function b(v) { if (v ~ /Ki$/) return v * 1024; if (v ~ /Mi$/) return v * 1048576; if (v ~ /Gi$/) return v * 1073741824
      if (v ~ /k$/) return v * 1000; if (v ~ /M$/) return v * 1000000; if (v ~ /G$/) return v * 1000000000; return v + 0 }
    function c(v) { if (v ~ /m$/) return v / 1000; return v + 0 }
    $1 == "P" && $2 != "octopus" && $2 != "cert-manager" {
                n = split($4, a, ","); for (i = 1; i <= n; i++) if (a[i] != "<none>") r[$3] += b(a[i])
                n = split($5, a, ","); for (i = 1; i <= n; i++) if (a[i] != "<none>") q[$3] += c(a[i]) }
    $1 == "N" && NF == 4 { printf "%s %.1f %.2f\n", $2, (b($3) - r[$2]) / 1073741824, c($4) - q[$2] }' \
  | while read -r W M C; do
      D="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get --raw "/api/v1/nodes/$W/proxy/stats/summary" </dev/null | jq '.node.runtime.imageFs.availableBytes / 1073741824 | floor')"
      echo "worker $W: $M GiB memory free, $C CPU free, ${D:-?} GiB image disk free"
    done
  echo "default storage class: $(printf '%s' "$J" | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name] | if length == 0 then "NONE" else join(" ") end')"
  kubectl --kubeconfig "$VKS_KUBECONFIG" get namespace octopus 2>/dev/null && echo "NOTE: namespace octopus exists already"
else
  echo "FAILED: cannot read the cluster (see the error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$global:LASTEXITCODE = $null
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { "MISSING: kubectl (KUBECTL.md)"; $global:LASTEXITCODE = 1 }
elseif (-not (Get-Command helm -ErrorAction SilentlyContinue)) { "MISSING: helm (HELM.md)"; $global:LASTEXITCODE = 1 }
elseif (-not (Test-Path $VKS_KUBECONFIG)) { "MISSING: $VKS_KUBECONFIG (LOGIN.md)"; $global:LASTEXITCODE = 1 }
else { kubectl --kubeconfig $VKS_KUBECONFIG get nodes -o wide }
if ($LASTEXITCODE -eq 0) { $N = @(kubectl --kubeconfig $VKS_KUBECONFIG get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers -o 'custom-columns=NAME:.metadata.name,MEM:.status.allocatable.memory,CPU:.status.allocatable.cpu') }
if ($LASTEXITCODE -eq 0) { $P = @(kubectl --kubeconfig $VKS_KUBECONFIG get pods -A '--field-selector=status.phase!=Succeeded,status.phase!=Failed' --no-headers -o 'custom-columns=NS:.metadata.namespace,NODE:.spec.nodeName,MEM:.spec.containers[*].resources.requests.memory,CPU:.spec.containers[*].resources.requests.cpu') }
if ($LASTEXITCODE -eq 0) { $J = kubectl --kubeconfig $VKS_KUBECONFIG get storageclass -o json | Out-String }
if ($LASTEXITCODE -eq 0) {
  function B($v) { if ($v -cmatch '^([\d.]+)(Ki|Mi|Gi|k|M|G)?$') { [double]$Matches[1] * @{ '' = 1; 'Ki' = 1KB; 'Mi' = 1MB; 'Gi' = 1GB; 'k' = 1e3; 'M' = 1e6; 'G' = 1e9 }[[string]$Matches[2]] } else { 0 } }
  function C($v) { if ($v -cmatch '^([\d.]+)m$') { [double]$Matches[1] / 1000 } elseif ($v -cmatch '^[\d.]+$') { [double]$v } else { 0 } }
  if (-not $N) { "NO WORKER: this cluster has no worker node" }
  $R = @{}; $Q = @{}
  foreach ($l in $P) {
    $f = -split $l
    if ($f[0] -eq 'octopus' -or $f[0] -eq 'cert-manager') { continue }
    foreach ($c in ($f[2] -split ',')) { if ($c -and $c -ne '<none>') { $R[$f[1]] += (B $c) } }
    foreach ($c in ($f[3] -split ',')) { if ($c -and $c -ne '<none>') { $Q[$f[1]] += (C $c) } }
  }
  foreach ($l in $N) {
    $f = -split $l
    $S = kubectl --kubeconfig $VKS_KUBECONFIG get --raw "/api/v1/nodes/$($f[0])/proxy/stats/summary" | Out-String | ConvertFrom-Json
    $A = if ($S) { $S.node.runtime.imageFs.availableBytes }
    $DISK = if ($null -ne $A) { [math]::Floor($A / 1GB) } else { '?' }
    "worker $($f[0]): $([math]::Round(((B $f[1]) - $R[$f[0]]) / 1GB, 1)) GiB memory free, $([math]::Round((C $f[2]) - $Q[$f[0]], 2)) CPU free, $DISK GiB image disk free"
  }
  $D = @((ConvertFrom-Json $J).items | Where-Object { $_.metadata.annotations.'storageclass.kubernetes.io/is-default-class' -eq 'true' } | ForEach-Object { $_.metadata.name })
  "default storage class: $(if ($D.Count) { $D -join ' ' } else { 'NONE' })"
  kubectl --kubeconfig $VKS_KUBECONFIG get namespace octopus 2>$null
  if ($LASTEXITCODE -eq 0) { "NOTE: namespace octopus exists already" }
} else {
  "FAILED: cannot read the cluster (see the error above)"
}
```

</details>

**Expect:** each node `Ready`, a `worker …: … GiB memory free, … CPU free, … GiB image disk free`
line per worker, and `default storage class:` and a class name. Octopus, SQL Server, nginx and the
cert-manager add-on of step 2 need a worker with at least 0.7 CPU, 4.3 GiB memory and 8 GiB image
disk free.

**If not:**
- No worker with that much free: add a node pool with a larger VM class, or a worker with its own
  image disk (see "The cluster for Octopus" above).
- `? GiB image disk free`: the node's statistics could not be read (the error above says why; after
  `Forbidden`, your kubeconfig may not read them); ask the cluster's administrator whether a worker
  has 8 GiB free.
- `NO WORKER`: set the node pool's `replicas` to 1 ([CLUSTER.md](CLUSTER.md) step 10).
- `default storage class: NONE`: see [CLUSTER.md](CLUSTER.md) step 7.
- `NOTE: namespace octopus exists already`: Octopus may be installed; steps 3 to 7 keep what exists.

## 2. Install cert-manager

The certificate for Octopus's web page (step 5) comes from cert-manager, a Broadcom add-on of the
VKS cluster ([what add-ons are](ADDONS.md)). Run [KEYCLOAK-VKS.md step
2](KEYCLOAK-VKS.md#2-install-cert-manager) once, with `VKS_CLUSTER` changed from
`my-keycloak-cluster` to Octopus's cluster and `VKS_NAMESPACE` to its vSphere Namespace. When the
add-on is there already, it changes nothing. That block makes your Supervisor login the active one
for the VCF CLI and in its kubeconfig file, and that stays after it.

**Expect:** as in that step: `condition met` for the three cert-manager deployments, or
`cert-manager: already installed`.

## 3. Create the namespace and the Secrets

Run this once, before SQL Server and Octopus start (steps 6 and 7): they read their passwords, key
and licence from here. It creates the namespace `octopus` (a namespace inside the VKS cluster, not a
vSphere Namespace; it is not listed under Supervisor Management → Namespaces), which allows only
pods that follow the `restricted` Pod Security Standard (Kubernetes' strictest rules for what a
container may do), and in it seven Secrets: random passwords for SQL Server, Octopus's random master
key, Octopus's first user `admin` with the password you type, your licence from
`octopus-license.xml`, and how Octopus reaches its database. You get the namespace with its Secrets,
ready for steps 4 to 7; nothing prints a password or the key. Run again, it keeps every Secret that
exists (the list is below the **If not:**). Set `VKS_CLUSTER` in the second block to the name of
Octopus's cluster. First type the password for Octopus's user `admin`, on its own (it is not shown):

**Linux, macOS, WSL (bash or zsh):**

```sh
printf 'Octopus admin password: '; IFS= read -rs OCTOPUS_ADMIN_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$OCTOPUS_ADMIN_PASSWORD = Read-Host 'Octopus admin password' -AsSecureString
```

Then:

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OCTOPUS_LICENSE_FILE="$HOME/octopus-license.xml"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus "$@"; }
mk() { if kc get secret "$1" >/dev/null 2>&1; then echo "secret $1: exists, kept"; else kc create secret generic "$1" --from-file="$2=/dev/stdin" >/dev/null && echo "secret $1: created"; fi; }
pw() { printf 'A%sz' "$(openssl rand -hex 16)"; }
if ! command -v openssl >/dev/null 2>&1; then
  echo "MISSING: openssl (PREREQS.md)"
elif [ -z "${OCTOPUS_ADMIN_PASSWORD:-}" ]; then
  echo "STOPPED: type the admin password first (the line above)"
elif [ ! -s "$OCTOPUS_LICENSE_FILE" ] || ! grep -q '<License' "$OCTOPUS_LICENSE_FILE"; then
  echo "FAILED: $OCTOPUS_LICENSE_FILE is not an Octopus licence (it starts with <License)"
elif ! kubectl --kubeconfig "$VKS_KUBECONFIG" create namespace octopus --dry-run=client -o yaml \
       | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - >/dev/null \
     || ! kubectl --kubeconfig "$VKS_KUBECONFIG" label namespace octopus --overwrite \
       pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/audit=restricted \
       pod-security.kubernetes.io/warn=restricted; then
  echo "FAILED: no namespace octopus (see the error above)"
else
  pw | mk sql-sa password
  pw | mk sql-octopus password
  openssl rand -base64 16 | tr -d '\n' | mk octopus-masterkey secret
  printf '%s' admin | mk octopus-adminusername secret
  printf '%s' "$OCTOPUS_ADMIN_PASSWORD" | mk octopus-adminpassword secret
  base64 < "$OCTOPUS_LICENSE_FILE" | tr -d '\n' | mk octopus-licensekey secret
  if kc get secret octopus-connectionstring >/dev/null 2>&1; then
    echo "secret octopus-connectionstring: exists, kept"
  elif P="$(kc get secret sql-octopus -o jsonpath='{.data.password}' | base64 -d)" && [ -n "$P" ]; then
    printf 'Server=sql;Initial Catalog=OctopusDeploy;Persist Security Info=False;User ID=octopus;Password=%s;Encrypt=True;Connection Timeout=30;' "$P" \
      | mk octopus-connectionstring secret
  else
    echo "FAILED: no secret sql-octopus (see the error above)"
  fi
fi
unset P OCTOPUS_ADMIN_PASSWORD
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OCTOPUS_LICENSE_FILE = "$HOME\octopus-license.xml"

function kc { $input | kubectl --kubeconfig $VKS_KUBECONFIG -n octopus @args }
function b64($s) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)) }
function mk($name, $key, $value) {
  kc get secret $name 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { "secret ${name}: exists, kept"; return }
  @('apiVersion: v1', 'kind: Secret', 'metadata:', "  name: $name", 'data:', "  ${key}: $(b64 $value)") | kc create -f - | Out-Null
  if ($LASTEXITCODE -eq 0) { "secret ${name}: created" }
}
function rnd($n) { $B = New-Object byte[] $n; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($B); $B }
function pw { 'A' + ((rnd 16 | ForEach-Object { $_.ToString('x2') }) -join '') + 'z' }
$global:LASTEXITCODE = $null
if (-not $OCTOPUS_ADMIN_PASSWORD -or $OCTOPUS_ADMIN_PASSWORD.Length -eq 0) { "STOPPED: type the admin password first (the line above)" }
elseif (-not (Test-Path $OCTOPUS_LICENSE_FILE) -or -not (Select-String -Quiet -SimpleMatch '<License' $OCTOPUS_LICENSE_FILE)) { "FAILED: $OCTOPUS_LICENSE_FILE is not an Octopus licence (it starts with <License)" }
else {
  kubectl --kubeconfig $VKS_KUBECONFIG create namespace octopus --dry-run=client -o yaml | kubectl --kubeconfig $VKS_KUBECONFIG apply -f - | Out-Null
  kubectl --kubeconfig $VKS_KUBECONFIG label namespace octopus --overwrite pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/warn=restricted
  if ($LASTEXITCODE -ne 0) { "FAILED: no namespace octopus (see the error above)" }
  else {
    mk sql-sa password (pw)
    mk sql-octopus password (pw)
    mk octopus-masterkey secret ([Convert]::ToBase64String((rnd 16)))
    mk octopus-adminusername secret 'admin'
    mk octopus-adminpassword secret ([Net.NetworkCredential]::new('', $OCTOPUS_ADMIN_PASSWORD).Password)
    mk octopus-licensekey secret ([Convert]::ToBase64String([IO.File]::ReadAllBytes($OCTOPUS_LICENSE_FILE)))
    $B = kc get secret sql-octopus -o 'jsonpath={.data.password}'
    if ($LASTEXITCODE -eq 0 -and $B) {
      $P = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B))
      mk octopus-connectionstring secret "Server=sql;Initial Catalog=OctopusDeploy;Persist Security Info=False;User ID=octopus;Password=$P;Encrypt=True;Connection Timeout=30;"
      $P = $null
    } else { "FAILED: no secret sql-octopus (see the error above)" }
    $B = $null
  }
}
Remove-Variable -ErrorAction SilentlyContinue OCTOPUS_ADMIN_PASSWORD
```

</details>

**Expect:** `namespace/octopus labeled`, then seven `secret …: created` lines
(`namespace/octopus not labeled` and `exists, kept` when run again).

**If not:**
- `STOPPED: type the admin password first`: run the one-line block above, then this one, in the
  same terminal.
- `FAILED: … is not an Octopus licence`: save the licence key text from Octopus (it starts with
  `<License`) as that file.
- `Error from server (Forbidden)`: the kubeconfig is not the cluster's administrator file.
- To change the admin password later, use step 12; this step keeps the Secret that exists.

**The Secrets:**
- `sql-sa` and `sql-octopus`: random passwords for SQL Server's administrator `sa` and for the
  login `octopus` that Octopus uses (step 6);
- `octopus-masterkey`: Octopus's random master key, which encrypts the secrets in its database;
- `octopus-adminusername` and `octopus-adminpassword`: Octopus's first user, `admin`, with the
  password you type;
- `octopus-licensekey`: your licence;
- `octopus-connectionstring`: how Octopus reaches its database, with the `octopus` login.

A Secret that exists is kept: SQL Server keeps the passwords it was first given, and Octopus cannot
read its database with another master key.

## 4. Create the Services and get Octopus's addresses

Run this before step 5: the web page's certificate is made for the address this step gets. It
creates Octopus's two Services (a Service gives a set of pods one address that stays), which get
addresses from the Supervisor's load balancer: `octopus-web` on port 443 for the web page and REST
API, and `octopus-grpc` on port 8443 for gRPC. Octopus itself starts in step 7. You get Octopus's
two addresses, printed at the end. Run again, it changes nothing and prints the same addresses. Set
`VKS_CLUSTER` to the name of Octopus's cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

cat <<'EOF' | kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus apply -f -
apiVersion: v1
kind: Service
metadata:
  name: octopus-web
spec:
  type: LoadBalancer
  selector:
    app: octopus-proxy
  ports:
    - name: https
      port: 443
      targetPort: 8443
---
apiVersion: v1
kind: Service
metadata:
  name: octopus-grpc
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/component: octopus-server
    app.kubernetes.io/instance: octopus
    app.kubernetes.io/name: octopus-deploy
  ports:
    - name: grpc
      port: 8443
      targetPort: 8443
EOF
W=""; G=""
for i in $(seq 60); do
  W="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus get service octopus-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  G="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus get service octopus-grpc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  [ -n "$W" ] && [ -n "$G" ] && break
  sleep 5
done
if [ -n "$W" ] && [ -n "$G" ]; then
  echo "Octopus's web address: $W"
  echo "Octopus's gRPC address: $G"
else
  echo "FAILED: no load balancer address in 5 minutes"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

@'
apiVersion: v1
kind: Service
metadata:
  name: octopus-web
spec:
  type: LoadBalancer
  selector:
    app: octopus-proxy
  ports:
    - name: https
      port: 443
      targetPort: 8443
---
apiVersion: v1
kind: Service
metadata:
  name: octopus-grpc
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/component: octopus-server
    app.kubernetes.io/instance: octopus
    app.kubernetes.io/name: octopus-deploy
  ports:
    - name: grpc
      port: 8443
      targetPort: 8443
'@ | kubectl --kubeconfig $VKS_KUBECONFIG -n octopus apply -f -
$W = ''; $G = ''
foreach ($i in 1..60) {
  $W = kubectl --kubeconfig $VKS_KUBECONFIG -n octopus get service octopus-web -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
  $G = kubectl --kubeconfig $VKS_KUBECONFIG -n octopus get service octopus-grpc -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
  if ($W -and $G) { break }
  Start-Sleep 5
}
if ($W -and $G) { "Octopus's web address: $W"; "Octopus's gRPC address: $G" } else { "FAILED: no load balancer address in 5 minutes" }
```

</details>

**Expect:** `service/octopus-web created` and `service/octopus-grpc created` (`unchanged` when run
again), then `Octopus's web address:` and `Octopus's gRPC address:`, each with an IP address. Use
the web address as `OCTOPUS_ADDRESS` from here on.

**If not:** `FAILED: no load balancer address`: the cluster has no two free load balancer addresses.
With the Foundation Load Balancer, the vSphere Client shows the Supervisor's range (not which
addresses are free): **Supervisor Management** → **Supervisors** → your Supervisor → **Configure** →
**Supervisor** → **Network** → **Load Balancer** → **Virtual Server Network** → **VIEW DETAILS** →
**Virtual IP Address Range(s)**. With NSX or Avi, the range is in that load balancer's own
settings.

**If a Service is deleted:** an address stays while its Service exists; deleting a Service gives
its address back, and a new Service can get another one: then step 5, step 8 and every bookmark and
agent that uses the old address must change.

## 5. Make the web page's certificate

Run this after step 4, so that Octopus's web page answers over HTTPS with a certificate your
browser and agents can trust. It makes a CA (certificate authority: the issuer your browser trusts
in step 9) of your own with cert-manager, valid for 10 years, and from it a certificate for
Octopus's web address from step 4 and its in-cluster name `octopus-web.octopus.svc`. You get the
CA and the certificate in the namespace `octopus`: nginx serves the certificate from step 7 on,
and step 8 saves the CA. Run again, it keeps the CA. Set `VKS_CLUSTER` to the name of Octopus's
cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus get service octopus-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
if [ -z "$IP" ]; then
  echo "FAILED: the Service octopus-web has no address (step 4)"
else
cat <<EOF | kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus apply -f - \
  && kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus wait --for=condition=Ready certificate --all --timeout=3m
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: octopus-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: octopus-ca
spec:
  isCA: true
  commonName: Octopus CA
  duration: 87600h
  secretName: octopus-ca
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: octopus-selfsigned
    kind: Issuer
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: octopus-ca
spec:
  ca:
    secretName: octopus-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: octopus-tls
spec:
  secretName: octopus-tls
  commonName: ${IP}
  dnsNames:
    - octopus-web.octopus.svc
  ipAddresses:
    - ${IP}
  usages:
    - server auth
  issuerRef:
    name: octopus-ca
    kind: Issuer
EOF
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$global:LASTEXITCODE = $null
$IP = kubectl --kubeconfig $VKS_KUBECONFIG -n octopus get service octopus-web -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
if (-not $IP) { "FAILED: the Service octopus-web has no address (step 4)" }
else {
@"
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: octopus-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: octopus-ca
spec:
  isCA: true
  commonName: Octopus CA
  duration: 87600h
  secretName: octopus-ca
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: octopus-selfsigned
    kind: Issuer
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: octopus-ca
spec:
  ca:
    secretName: octopus-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: octopus-tls
spec:
  secretName: octopus-tls
  commonName: $IP
  dnsNames:
    - octopus-web.octopus.svc
  ipAddresses:
    - $IP
  usages:
    - server auth
  issuerRef:
    name: octopus-ca
    kind: Issuer
"@ | kubectl --kubeconfig $VKS_KUBECONFIG -n octopus apply -f -
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n octopus wait --for=condition=Ready certificate --all --timeout=3m }
}
```

</details>

**Expect:** four `created` lines (`unchanged` or `configured` when run again), then
`certificate.cert-manager.io/octopus-ca condition met` and `…/octopus-tls condition met`.

**If not:**
- `no matches for kind "Issuer"`: step 2 did not finish.
- `failed calling webhook "webhook.cert-manager.io"`: cert-manager is still starting. Wait a minute
  and run this block again.
- `timed out`: `kubectl --kubeconfig <file> -n octopus describe certificate octopus-tls` shows why.

**Renewal:** cert-manager renews the certificate before it ends; nginx picks the new one up within
about 6 minutes. The gRPC port keeps Octopus's own certificate.

## 6. Run SQL Server and create Octopus's database

Run this after step 3 and before step 7: Octopus keeps all its data in this database. It runs SQL
Server 2025 Express with a 10 GiB volume (a disk from the default storage class), waits until it
accepts logins, then creates the database `OctopusDeploy` and the login `octopus` that owns it.
Octopus uses that login, not `sa`. You get SQL Server running with Octopus's empty database. Run
again, it changes nothing and SQL Server keeps running. Set `VKS_CLUSTER` to the name of Octopus's
cluster. Running this block accepts Microsoft's licence terms for SQL Server Express
(`ACCEPT_EULA`).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SQL_IMAGE="mcr.microsoft.com/mssql/server:2025-CU10-ubuntu-22.04@sha256:6972fb831759433def6a34e107fa32a85230bff5af8014c6263fe4633ea9cc0f"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus "$@"; }
sq() { kc exec -i sql-0 -- sh -c 'SQLCMDPASSWORD="$MSSQL_SA_PASSWORD" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -h -1 -W'; }
cat <<EOF | kc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: sql
spec:
  selector:
    app: sql
  ports:
    - name: sql
      port: 1433
      targetPort: 1433
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: sql
spec:
  serviceName: sql
  replicas: 1
  selector:
    matchLabels:
      app: sql
  template:
    metadata:
      labels:
        app: sql
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: sql
          image: ${SQL_IMAGE}
          env:
            - name: ACCEPT_EULA
              value: "Y"
            - name: MSSQL_PID
              value: Express
            - name: MSSQL_MEMORY_LIMIT_MB
              value: "2048"
            - name: MSSQL_SA_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: sql-sa
                  key: password
          ports:
            - containerPort: 1433
          readinessProbe:
            tcpSocket:
              port: 1433
            periodSeconds: 10
          resources:
            requests:
              cpu: 200m
              memory: 2Gi
            limits:
              memory: 3Gi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
              add: ["NET_BIND_SERVICE"]
          volumeMounts:
            - name: data
              mountPath: /var/opt/mssql
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 1Gi
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
EOF
V=""
if kc rollout status statefulset/sql --timeout=10m; then
  for i in $(seq 30); do
    V="$(printf "SET NOCOUNT ON;\nSELECT CONVERT(varchar(60), SERVERPROPERTY('Edition')) + ' ' + CONVERT(varchar(30), SERVERPROPERTY('ProductVersion'));\nGO\n" | sq 2>/dev/null)" && break
    sleep 5
  done
fi
if [ -z "$V" ]; then
  echo "FAILED: SQL Server does not accept logins (see kubectl --kubeconfig '$VKS_KUBECONFIG' -n octopus describe pod sql-0 and its logs)"
elif ! P="$(kc get secret sql-octopus -o jsonpath='{.data.password}' | base64 -d)" || [ -z "$P" ]; then
  echo "FAILED: no secret sql-octopus (step 3)"
else
  echo "SQL Server: $V"
  printf "SET NOCOUNT ON;\nIF DB_ID('OctopusDeploy') IS NULL CREATE DATABASE OctopusDeploy;\nIF SUSER_ID('octopus') IS NULL CREATE LOGIN octopus WITH PASSWORD = '%s';\nALTER AUTHORIZATION ON DATABASE::OctopusDeploy TO octopus;\nSELECT 'database owner: ' + SUSER_SNAME(owner_sid) FROM sys.databases WHERE name = 'OctopusDeploy';\nGO\n" "$P" | sq
fi
unset P
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SQL_IMAGE = "mcr.microsoft.com/mssql/server:2025-CU10-ubuntu-22.04@sha256:6972fb831759433def6a34e107fa32a85230bff5af8014c6263fe4633ea9cc0f"

function kc { $input | kubectl --kubeconfig $VKS_KUBECONFIG -n octopus @args }
function sq { $input | kc exec -i sql-0 '--' sh -c 'SQLCMDPASSWORD="$MSSQL_SA_PASSWORD" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -h -1 -W' }
$global:LASTEXITCODE = $null
@"
apiVersion: v1
kind: Service
metadata:
  name: sql
spec:
  selector:
    app: sql
  ports:
    - name: sql
      port: 1433
      targetPort: 1433
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: sql
spec:
  serviceName: sql
  replicas: 1
  selector:
    matchLabels:
      app: sql
  template:
    metadata:
      labels:
        app: sql
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: sql
          image: $SQL_IMAGE
          env:
            - name: ACCEPT_EULA
              value: "Y"
            - name: MSSQL_PID
              value: Express
            - name: MSSQL_MEMORY_LIMIT_MB
              value: "2048"
            - name: MSSQL_SA_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: sql-sa
                  key: password
          ports:
            - containerPort: 1433
          readinessProbe:
            tcpSocket:
              port: 1433
            periodSeconds: 10
          resources:
            requests:
              cpu: 200m
              memory: 2Gi
            limits:
              memory: 3Gi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
              add: ["NET_BIND_SERVICE"]
          volumeMounts:
            - name: data
              mountPath: /var/opt/mssql
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 1Gi
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
"@ | kc apply -f -
$V = ''
kc rollout status statefulset/sql --timeout=10m
if ($LASTEXITCODE -eq 0) {
  foreach ($i in 1..30) {
    $V = "SET NOCOUNT ON;`nSELECT CONVERT(varchar(60), SERVERPROPERTY('Edition')) + ' ' + CONVERT(varchar(30), SERVERPROPERTY('ProductVersion'));`nGO`n" | sq 2>$null
    if ($LASTEXITCODE -eq 0 -and $V) { break }
    $V = ''; Start-Sleep 5
  }
}
$B = kc get secret sql-octopus -o 'jsonpath={.data.password}'
if (-not $V) { "FAILED: SQL Server does not accept logins (see kubectl --kubeconfig '$VKS_KUBECONFIG' -n octopus describe pod sql-0 and its logs)" }
elseif (-not $B) { "FAILED: no secret sql-octopus (step 3)" }
else {
  "SQL Server: $V"
  $P = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B))
  "SET NOCOUNT ON;`nIF DB_ID('OctopusDeploy') IS NULL CREATE DATABASE OctopusDeploy;`nIF SUSER_ID('octopus') IS NULL CREATE LOGIN octopus WITH PASSWORD = '$P';`nALTER AUTHORIZATION ON DATABASE::OctopusDeploy TO octopus;`nSELECT 'database owner: ' + SUSER_SNAME(owner_sid) FROM sys.databases WHERE name = 'OctopusDeploy';`nGO`n" | sq
  $P = $null
}
$B = $null
```

</details>

**Expect:** `service/sql created`, `statefulset.apps/sql created`, `partitioned roll out complete`,
then `SQL Server: Express Edition (64-bit) 17.0.…` and `database owner: octopus`. A second run
prints `service/sql unchanged`, `statefulset.apps/sql configured` (nothing changes; the pod keeps
running) and the same two lines.

**If not:**
- `CrashLoopBackOff` with `sqlservr: Operation not permitted` in `kubectl --kubeconfig <file> -n
  octopus logs sql-0`: the container lacks `NET_BIND_SERVICE`; run this block as it is.
- `ImagePullBackOff`: the nodes cannot reach or cannot download from `mcr.microsoft.com` (the image
  is about 640 MB; `kubectl --kubeconfig <file> -n octopus describe pod sql-0` shows the error; see
  the table above).
- `Pending` with `Insufficient memory`: the worker is too small (see the Prerequisites).
- `FAILED: SQL Server does not accept logins`: the log shows why; a `sa` password SQL Server
  refuses stops it at start (step 3 makes one it accepts).

**No password on a command line:** the SQL statements go to `sqlcmd` in the pod on its input, and
`sqlcmd` reads the `sa` password from the pod's own environment.

## 7. Run Octopus

Run this after steps 3 to 6 to start Octopus itself, and again after step 11. It writes a values
file, `~/.config/vks-guides/octopus/values.yaml`, for Octopus's Helm chart 1.18.0 (Helm installs an
application from a package, its chart; the values file holds this guide's settings and no secrets:
Octopus reads its passwords and keys from step 3's Secrets), installs or updates Octopus with it,
waits until Octopus is ready, then runs nginx in front of Octopus's web page with step 5's
certificate. You get Octopus running behind its web address; step 8 checks it. Run again, it keeps
Octopus's data and keys. Set `VKS_CLUSTER` to the name of Octopus's cluster. It accepts Octopus
Deploy's EULA (`acceptEula`) and gives the `admin` user the e-mail `admin@example.com`. The first
start takes several minutes: the nodes download a 1.6 GB image and Octopus creates its database
tables.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OCTOPUS_DIR="$HOME/.config/vks-guides/octopus"
CHART_VERSION="1.18.0"
OCTOPUS_TAG="2026.3.16049@sha256:63a4d70d3011e546e7950671c2cee16a4737a8617748d931719c3fa114ce559d"
PROXY_IMAGE="docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus "$@"; }
mkdir -p "$OCTOPUS_DIR"
cat > "$OCTOPUS_DIR/values.yaml" <<EOF
octopus:
  acceptEula: "Y"
  createSecrets: false
  image:
    repository: docker.io/octopusdeploy/octopusdeploy
    tag: "${OCTOPUS_TAG}"
  email: admin@example.com
  enableDockerInDocker: false
  service:
    type: ClusterIP
  resources:
    requests:
      cpu: 400m
      memory: 2Gi
    limits:
      memory: 3Gi
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 999
    runAsGroup: 999
    fsGroup: 999
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  serverConfigurationDirectory: /home/octopus/.octopus
  serverLogVolume:
    size: 1Gi
  extraVolumes:
    tmp:
      type: emptyDir
      mountPath: /tmp
      sizeLimit: 1Gi
    homeoctopus:
      type: emptyDir
      mountPath: /home/octopus
      sizeLimit: 2Gi
    octopushome:
      type: emptyDir
      mountPath: /home/octopus/.octopus
      sizeLimit: 10Mi
    octopusserver:
      type: emptyDir
      mountPath: /home/octopus/.octopus/OctopusServer/Server
      sizeLimit: 2Gi
    etcoctopus:
      type: emptyDir
      mountPath: /etc/octopus
      sizeLimit: 10Mi
    octopuslogs:
      type: emptyDir
      mountPath: /Octopus/Octopus/Logs
      sizeLimit: 500Mi
    octopusdiagnostics:
      type: emptyDir
      mountPath: /Octopus/.diagnostics
      sizeLimit: 100Mi
hooks:
  enableSelectorLabelsFix: false
EOF
h() { helm upgrade --install octopus oci://ghcr.io/octopusdeploy/octopusdeploy-helm --version "$CHART_VERSION" \
        --kubeconfig "$VKS_KUBECONFIG" -n octopus -f "$OCTOPUS_DIR/values.yaml" "$@" >/dev/null; }
R=""
if [ -s "$OCTOPUS_DIR/values-ca.yaml" ]; then h -f "$OCTOPUS_DIR/values-ca.yaml"; else h; fi
if [ $? -eq 0 ] && kc rollout status statefulset/octopus-octopus-deploy --timeout=15m; then R=true; fi
if [ "$R" != true ]; then
  echo "FAILED: Octopus is not ready (see kubectl --kubeconfig '$VKS_KUBECONFIG' -n octopus describe pod octopus-octopus-deploy-0)"
elif ! M="$(helm get manifest octopus --kubeconfig "$VKS_KUBECONFIG" -n octopus)"; then
  echo "FAILED: cannot read the Helm release (see the error above)"
else
  echo "Octopus is ready; Secrets in the Helm release: $(printf '%s\n' "$M" | grep -c '^kind: Secret') of $(printf '%s\n' "$M" | grep -c '^kind: ') objects"
  C="$(cat <<'EOF' | kc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: octopus-proxy
data:
  default.conf: |
    map $http_upgrade $connection_upgrade {
      default upgrade;
      '' close;
    }
    server {
      listen 8443 ssl;
      ssl_certificate /etc/octopus-tls/tls.crt;
      ssl_certificate_key /etc/octopus-tls/tls.key;
      client_max_body_size 0;
      location / {
        proxy_pass http://octopus-octopus-deploy.octopus.svc:80;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_cookie_flags ~ secure;
        proxy_read_timeout 900s;
      }
    }
  start.sh: |
    s="$(sha256sum /etc/octopus-tls/tls.crt)"
    (while sleep 300; do n="$(sha256sum /etc/octopus-tls/tls.crt)"; if [ "$n" = "$s" ]; then :; else nginx -t && nginx -s reload && s="$n"; fi; done) &
    exec nginx -g 'daemon off;'
EOF
)"
  echo "$C"
  cat <<EOF | kc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: octopus-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: octopus-proxy
  template:
    metadata:
      labels:
        app: octopus-proxy
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: proxy
          image: ${PROXY_IMAGE}
          command: ["/bin/sh", "/etc/nginx/conf.d/start.sh"]
          ports:
            - containerPort: 8443
          readinessProbe:
            tcpSocket:
              port: 8443
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: conf
              mountPath: /etc/nginx/conf.d
            - name: tls
              mountPath: /etc/octopus-tls
              readOnly: true
      volumes:
        - name: conf
          configMap:
            name: octopus-proxy
        - name: tls
          secret:
            secretName: octopus-tls
EOF
  case "$C" in *configured*) kc rollout restart deployment/octopus-proxy ;; esac
  kc rollout status deployment/octopus-proxy --timeout=5m
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OCTOPUS_DIR = "$HOME\.config\vks-guides\octopus"
$CHART_VERSION = "1.18.0"
$OCTOPUS_TAG = "2026.3.16049@sha256:63a4d70d3011e546e7950671c2cee16a4737a8617748d931719c3fa114ce559d"
$PROXY_IMAGE = "docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"

function kc { $input | kubectl --kubeconfig $VKS_KUBECONFIG -n octopus @args }
New-Item -ItemType Directory -Force -Path $OCTOPUS_DIR | Out-Null
[IO.File]::WriteAllText("$OCTOPUS_DIR\values.yaml", @"
octopus:
  acceptEula: "Y"
  createSecrets: false
  image:
    repository: docker.io/octopusdeploy/octopusdeploy
    tag: "$OCTOPUS_TAG"
  email: admin@example.com
  enableDockerInDocker: false
  service:
    type: ClusterIP
  resources:
    requests:
      cpu: 400m
      memory: 2Gi
    limits:
      memory: 3Gi
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 999
    runAsGroup: 999
    fsGroup: 999
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  serverConfigurationDirectory: /home/octopus/.octopus
  serverLogVolume:
    size: 1Gi
  extraVolumes:
    tmp:
      type: emptyDir
      mountPath: /tmp
      sizeLimit: 1Gi
    homeoctopus:
      type: emptyDir
      mountPath: /home/octopus
      sizeLimit: 2Gi
    octopushome:
      type: emptyDir
      mountPath: /home/octopus/.octopus
      sizeLimit: 10Mi
    octopusserver:
      type: emptyDir
      mountPath: /home/octopus/.octopus/OctopusServer/Server
      sizeLimit: 2Gi
    etcoctopus:
      type: emptyDir
      mountPath: /etc/octopus
      sizeLimit: 10Mi
    octopuslogs:
      type: emptyDir
      mountPath: /Octopus/Octopus/Logs
      sizeLimit: 500Mi
    octopusdiagnostics:
      type: emptyDir
      mountPath: /Octopus/.diagnostics
      sizeLimit: 100Mi
hooks:
  enableSelectorLabelsFix: false
"@)
$F = @('-f', "$OCTOPUS_DIR\values.yaml")
if (Test-Path "$OCTOPUS_DIR\values-ca.yaml") { $F += @('-f', "$OCTOPUS_DIR\values-ca.yaml") }
$R = ''
helm upgrade --install octopus oci://ghcr.io/octopusdeploy/octopusdeploy-helm --version $CHART_VERSION --kubeconfig $VKS_KUBECONFIG -n octopus @F | Out-Null
if ($LASTEXITCODE -eq 0) {
  kc rollout status statefulset/octopus-octopus-deploy --timeout=15m
  if ($LASTEXITCODE -eq 0) { $R = 'true' }
}
if ($R -eq 'true') { $M = helm get manifest octopus --kubeconfig $VKS_KUBECONFIG -n octopus; if ($LASTEXITCODE -ne 0) { $R = 'manifest' } }
if ($R -eq 'manifest') { "FAILED: cannot read the Helm release (see the error above)" }
elseif ($R -ne 'true') { "FAILED: Octopus is not ready (see kubectl --kubeconfig '$VKS_KUBECONFIG' -n octopus describe pod octopus-octopus-deploy-0)" }
else {
  "Octopus is ready; Secrets in the Helm release: $(@($M | Select-String '^kind: Secret').Count) of $(@($M | Select-String '^kind: ').Count) objects"
  $C = @'
apiVersion: v1
kind: ConfigMap
metadata:
  name: octopus-proxy
data:
  default.conf: |
    map $http_upgrade $connection_upgrade {
      default upgrade;
      '' close;
    }
    server {
      listen 8443 ssl;
      ssl_certificate /etc/octopus-tls/tls.crt;
      ssl_certificate_key /etc/octopus-tls/tls.key;
      client_max_body_size 0;
      location / {
        proxy_pass http://octopus-octopus-deploy.octopus.svc:80;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_cookie_flags ~ secure;
        proxy_read_timeout 900s;
      }
    }
  start.sh: |
    s="$(sha256sum /etc/octopus-tls/tls.crt)"
    (while sleep 300; do n="$(sha256sum /etc/octopus-tls/tls.crt)"; if [ "$n" = "$s" ]; then :; else nginx -t && nginx -s reload && s="$n"; fi; done) &
    exec nginx -g 'daemon off;'
'@ | kc apply -f -
  $C
@"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: octopus-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: octopus-proxy
  template:
    metadata:
      labels:
        app: octopus-proxy
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: proxy
          image: $PROXY_IMAGE
          command: ["/bin/sh", "/etc/nginx/conf.d/start.sh"]
          ports:
            - containerPort: 8443
          readinessProbe:
            tcpSocket:
              port: 8443
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: conf
              mountPath: /etc/nginx/conf.d
            - name: tls
              mountPath: /etc/octopus-tls
              readOnly: true
      volumes:
        - name: conf
          configMap:
            name: octopus-proxy
        - name: tls
          secret:
            secretName: octopus-tls
"@ | kc apply -f -
  if ("$C" -match 'configured') { kc rollout restart deployment/octopus-proxy }
  kc rollout status deployment/octopus-proxy --timeout=5m
}
```

</details>

**Expect:** `partitioned roll out complete`, `Octopus is ready; Secrets in the Helm release: 0 of 6
objects`, then `configmap/octopus-proxy created`, `deployment.apps/octopus-proxy created` and
`successfully rolled out`. Run again, it
prints `unchanged` for nginx and keeps Octopus's data and keys.

**If not:**
- `FAILED: Octopus is not ready`: `kubectl --kubeconfig <file> -n octopus describe pod
  octopus-octopus-deploy-0` and `kubectl --kubeconfig <file> -n octopus logs
  octopus-octopus-deploy-0` show why. `ImagePullBackOff`: the nodes cannot reach `docker.io`.
  `CreateContainerConfigError`: a Secret of step 3 is missing; run step 3 (for `ca-bundle`: the
  ConfigMap of step 11; run step 11, or delete `~/.config/vks-guides/octopus/values-ca.yaml` if you
  no longer use Nexus, then run step 7 again). A log line about the database: step 6 did not finish.
  The pod `Running` but `0/1` with only `Startup probe failed` events: Octopus is still starting;
  run step 7 again.
- The pod still in `CrashLoopBackOff` after step 7 ran with the fix: running step 7 again does not
  replace it; run `kubectl --kubeconfig <file> -n octopus delete pod octopus-octopus-deploy-0`, then
  step 7 again.
- `Error: … oci://ghcr.io/…`: this machine cannot reach `ghcr.io`.
- `secret "octopus-tls" not found` in `kubectl --kubeconfig <file> -n octopus describe pod -l
  app=octopus-proxy`: step 5 did not finish.

**How Octopus runs:** as a non-root user with a read-only file system, and without
Docker-in-Docker (so steps cannot run in containers on Octopus's built-in worker).

## 8. Save the CA

Run this after step 7, to get the file your browser and agents trust Octopus's web page with, and
to check that Octopus answers. It saves step 5's CA as `octopus-ca.pem` in your home folder (it
holds no secret), prints its fingerprint, and checks that Octopus answers on its web address and on
its gRPC port. You get `octopus-ca.pem` for step 9 and for every agent that connects to Octopus.
Run again, it saves the same CA again. Set `VKS_CLUSTER` to the name of Octopus's cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OCTOPUS_CA="$HOME/octopus-ca.pem"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus "$@"; }
IP="$(kc get service octopus-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
if kc get secret octopus-tls -o go-template='{{index .data "ca.crt" | base64decode}}' > "$OCTOPUS_CA.new" \
   && openssl x509 -in "$OCTOPUS_CA.new" -noout -subject -fingerprint -sha256; then
  mv "$OCTOPUS_CA.new" "$OCTOPUS_CA" && echo "saved $OCTOPUS_CA"
  curl -fsS --connect-timeout 20 --cacert "$OCTOPUS_CA" "https://${IP}/api" | grep -o '"Version": *"[^"]*"' \
    && echo "Octopus answers at https://${IP}"
  G="$(kc get service octopus-grpc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  if [ -z "$G" ]; then
    echo "FAILED: octopus-grpc has no address yet (step 4)"
  else
    curl -sSv -k --connect-timeout 20 --max-time 20 --http2 -o /dev/null "https://${G}:8443/" 2>&1 \
      | sed -n 's/^\* ALPN: server accepted /ALPN protocol: /p; s/^\*  *subject: /gRPC certificate: /p; s/^\*  *Server certificate: /gRPC certificate: /p'
  fi
else
  rm -f "$OCTOPUS_CA.new"; echo "FAILED: no CA read (see the error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OCTOPUS_CA = "$HOME\octopus-ca.pem"

function kc { kubectl --kubeconfig $VKS_KUBECONFIG -n octopus @args }
$global:LASTEXITCODE = $null
$IP = kc get service octopus-web -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
$B = kc get secret octopus-tls -o 'jsonpath={.data.ca\.crt}'
if ($LASTEXITCODE -eq 0 -and $B) {
  $PEM = [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($B))
  $C = New-Object Security.Cryptography.X509Certificates.X509Certificate2 (,[Text.Encoding]::ASCII.GetBytes($PEM))
  "subject=$($C.Subject)"
  "sha256 Fingerprint=$([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($C.RawData)).Replace('-', ':'))"
  Set-Content -Encoding ascii -NoNewline -Path $OCTOPUS_CA -Value $PEM
  "saved $OCTOPUS_CA"
  $A = curl.exe -fsS --connect-timeout 20 --ssl-no-revoke --cacert $OCTOPUS_CA --resolve "octopus-web.octopus.svc:443:$IP" https://octopus-web.octopus.svc/api
  if ($LASTEXITCODE -eq 0) { "Version: $((($A | Out-String) | ConvertFrom-Json).Version)"; "Octopus answers at https://$IP" }
  $G = kc get service octopus-grpc -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
  if (-not $G) { "FAILED: octopus-grpc has no address yet (step 4)" }
  else { try {
    $T = New-Object Net.Sockets.TcpClient($G, 8443)
    $T.ReceiveTimeout = 20000; $T.SendTimeout = 20000
    $S = New-Object Net.Security.SslStream($T.GetStream(), $false, { $true })
    $S.AuthenticateAsClient($G)
    "gRPC certificate: $($S.RemoteCertificate.Subject)"
    $T.Close()
  } catch { "FAILED: no TLS answer on ${G}:8443" } }
} else { "FAILED: no CA read (see the error above)" }
```

</details>

**Expect:** a `subject=` line with `Octopus CA`, a `sha256 Fingerprint=…` line, `saved
…/octopus-ca.pem`, a `"Version"` line with `2026.3.16049`, `Octopus answers at https://<address>`,
`ALPN protocol: h2` and a `gRPC certificate:` line naming `Octopus gRPC` (Windows: `Version:
2026.3.16049` and no ALPN line). The
gRPC port keeps Octopus's own certificate.

**If not:**
- `Connection refused` or a timeout: this machine cannot reach the web address on port 443, or nginx
  is not ready yet (step 7).
- `curl: (35)` right after step 7: Octopus's web address is not
  passing traffic to nginx yet; wait a minute and run step 8 again.
- `SSL certificate problem`: step 5 ran with another address; run steps 5 and 8 again.
- `CertGetNameString() failed to match` (Windows): the certificate is older than step 5's
  `octopus-web.octopus.svc` name; run step 5, wait 6 minutes for nginx to load it, then run step 8
  again.
- No `gRPC certificate:` line: this machine cannot reach `octopus-grpc`'s address on port 8443.

## 9. Sign in

Octopus's web page is `https://<OCTOPUS_ADDRESS>`; your browser warns that the connection is not
private until it trusts your CA. Run the line below once on the machine whose browser you sign in
with (copy `octopus-ca.pem` from step 8 there first; it holds no secret), so that the browser trusts
Octopus's web page. It adds `octopus-ca.pem` to your user's trusted CAs. You get Octopus's web page
in your browser with no warning. To skip this, check the fingerprint instead (below).

**macOS** (macOS asks for your password):

```sh
security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$HOME/octopus-ca.pem"
```

**Windows (PowerShell)** (Windows asks you to confirm with **Yes**):

```powershell
Import-Certificate -FilePath "$HOME\octopus-ca.pem" -CertStoreLocation Cert:\CurrentUser\Root
```

**Expect:** macOS: no output after your password. Windows: a line with the CA's thumbprint and
`CN=Octopus CA`. Then the browser opens Octopus's web page with no warning (restart the browser
first).

**If not:** `UI is not allowed in this operation` (Windows): run the line in PowerShell on the
desktop, not over a remote session, so Windows can ask for **Yes**. A missing `octopus-ca.pem`:
copy it from step 8 first.

Or, without trusting the CA, check the fingerprint (click **Not secure** left of the address, then
the certificate details: the issuer's SHA-256 fingerprint is the one step 8 printed) and then click
**Advanced** and **Proceed to … (unsafe)**, as in [HEADLAMP.md](HEADLAMP.md).

Sign in as `admin` with the password you typed in step 3:

![Octopus: Welcome! Please sign in, with Username and Password](img/octopus/01-sign-in.jpg)

Octopus opens on **Projects**. To see your licence's limits, click the gear (**Configuration**) at
the bottom left, then **License Usage**:

![License Usage Dashboard: Projects 0/10, Tenants 0/10, Machines 0/10, Users 1/10, Task Cap 0/5](img/octopus/02-license-usage.jpg)

Run this instead to check the sign-in and the licence from a terminal, without the web page. It
signs in as `admin` with the password in step 3's Secret (it is not shown) and changes nothing. You
get Octopus's version and the licence's limits. Set `VKS_CLUSTER` to the name of Octopus's cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OCTOPUS_CA="$HOME/octopus-ca.pem"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus "$@"; }
IP="$(kc get service octopus-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
U="https://${IP}/api"
if ! command -v jq >/dev/null 2>&1; then
  echo "MISSING: jq (PREREQS.md)"
elif [ ! -s "$OCTOPUS_CA" ]; then
  echo "MISSING: $OCTOPUS_CA (step 8)"
elif T="$(umask 077 && mktemp -d)"; then
  if kc get secret octopus-adminpassword -o jsonpath='{.data.secret}' | base64 -d \
       | jq -Rc '{Username: "admin", Password: ., RememberMe: false}' \
       | curl -fsS --connect-timeout 20 --cacert "$OCTOPUS_CA" -c "$T/jar" -o /dev/null \
           -H 'Content-Type: application/json' --data-binary @- "$U/users/login"; then
    X="$(awk '$6 ~ /^Octopus-Csrf-Token/ {print $7}' "$T/jar")"
    echo "version: $(curl -fsS --cacert "$OCTOPUS_CA" "$U" | jq -r .Version)"
    curl -fsS --cacert "$OCTOPUS_CA" -b "$T/jar" -H "X-Octopus-Csrf-Token: $X" "$U/licenses/licenses-current-status" \
      | jq -r '"licence compliant: \(.IsCompliant)", "limits: " + ([.Limits[] | "\(.Name) \(.EffectiveLimit)"] | join(", "))'
  else
    echo "FAILED: sign-in refused (see the error above)"
  fi
  rm -rf "$T"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OCTOPUS_CA = "$HOME\octopus-ca.pem"

function kc { kubectl --kubeconfig $VKS_KUBECONFIG -n octopus @args }
$IP = kc get service octopus-web -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
$U = 'https://octopus-web.octopus.svc/api'; $RV = '--resolve', "octopus-web.octopus.svc:443:$IP"
$T = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
if (-not (Test-Path $OCTOPUS_CA)) { "MISSING: $OCTOPUS_CA (step 8)" }
else {
  New-Item -ItemType Directory -Path $T | Out-Null
  try {
    $B = kc get secret octopus-adminpassword -o 'jsonpath={.data.secret}'
    $P = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B))
    [IO.File]::WriteAllText("$T\login.json", (@{ Username = 'admin'; Password = $P; RememberMe = $false } | ConvertTo-Json -Compress))
    $P = $null; $B = $null
    curl.exe -fsS --connect-timeout 20 --ssl-no-revoke --cacert $OCTOPUS_CA @RV -c "$T\jar" -o NUL -H 'Content-Type: application/json' --data-binary "@$T\login.json" "$U/users/login"
    if ($LASTEXITCODE -eq 0) {
      $X = (Select-String -Path "$T\jar" -Pattern 'Octopus-Csrf-Token\S*\s+(\S+)$').Matches[0].Groups[1].Value
      "version: $(((curl.exe -fsS --ssl-no-revoke --cacert $OCTOPUS_CA @RV $U) | Out-String | ConvertFrom-Json).Version)"
      $L = (curl.exe -fsS --ssl-no-revoke --cacert $OCTOPUS_CA @RV -b "$T\jar" -H "X-Octopus-Csrf-Token: $X" "$U/licenses/licenses-current-status") | Out-String | ConvertFrom-Json
      "licence compliant: $($L.IsCompliant)"
      "limits: " + (($L.Limits | ForEach-Object { "$($_.Name) $($_.EffectiveLimit)" }) -join ', ')
    } else { "FAILED: sign-in refused (see the error above)" }
  } finally { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $T }
}
```

</details>

**Expect:** in the browser, **Projects** after signing in, and on **License Usage** `Projects 0/10`
and `Users 1/10`; from the terminal, `version: 2026.3.16049`, `licence compliant: true` and
`limits: Spaces 1, Projects 10, Targets 10, Tasks 5, Tenants 10, Users 10, …`.

**If not:**
- `Projects 0` (or `Projects 0/0`): Octopus started without a licence; check `octopus-license.xml`,
  delete the Secret with `kubectl --kubeconfig <file> -n octopus delete secret octopus-licensekey`,
  run step 3 again, then restart Octopus with `kubectl --kubeconfig <file> -n octopus delete pod
  octopus-octopus-deploy-0`.
- `Invalid username or password` (browser) or `FAILED: sign-in refused`: the password is the one in
  step 3's Secret; a password changed in Octopus's web page goes back to it when the pod restarts.
  Change it with step 12.
- `curl: (35)` above `FAILED: sign-in refused`: the web address is not passing traffic yet (step 8);
  run step 9 again in a minute.

## 10. Create the environments and a lifecycle

An environment is where releases go (here dev, test and prod); a lifecycle is the order a release
moves through them. This creates the three environments, and a lifecycle `dev-test-prod` that
deploys each release to dev at once and to test and prod when someone promotes it.

In the web page, for each of `dev`, `test` and `prod`: **Infrastructure** → **Environments** →
**Add Environment** → **Environment**:

![Select Environment Type: Environment or Parent Environment](img/octopus/03-environment-type.jpg)

Type the name, then **Save**:

![Add Environment: the name qa typed, Cancel and Save](img/octopus/04-add-environment.jpg)

Then **Lifecycles** (under **Manage**) → **Add Lifecycle**: **Lifecycle name** `dev-test-prod`.
Under **Phases**, **Add Phase**, **Phase name** `dev`, **Add Environment**: pick `dev` and **Deploy
automatically to this environment as soon as the release enters this phase**, then **Ok**:

![Add Environment in a phase: Environment dev, deploy automatically or manually, Cancel and Ok](img/octopus/07-lifecycle-add-environment.jpg)

Add the phases `test` and `prod` the same way, leaving **Users will need to manually queue the
deployment to this environment**, then **Save**: `Lifecycle created`. The lists then show:

![Environments: dev, test and prod, each with 0 deployment targets](img/octopus/05-environments.jpg)

![Lifecycles: Default Lifecycle and dev-test-prod, with the phases dev, test and prod](img/octopus/06-lifecycles.jpg)

Run this instead to do the same from a terminal, for example to set up another Octopus the same
way. It signs in as `admin` with the password in step 3's Secret, creates the environments `dev`,
`test` and `prod` and the lifecycle `dev-test-prod`, and skips what exists. You get the same two
lists as in the web page above. Set `VKS_CLUSTER` to the name of Octopus's cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OCTOPUS_CA="$HOME/octopus-ca.pem"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus "$@"; }
IP="$(kc get service octopus-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
U="https://${IP}/api"
api() { curl -fsS --connect-timeout 20 --cacert "$OCTOPUS_CA" -b "$T/jar" -H "X-Octopus-Csrf-Token: $X" -H 'Content-Type: application/json' "$@"; }
if ! command -v jq >/dev/null 2>&1; then
  echo "MISSING: jq (PREREQS.md)"
elif [ ! -s "$OCTOPUS_CA" ]; then
  echo "MISSING: $OCTOPUS_CA (step 8)"
elif T="$(umask 077 && mktemp -d)"; then
  if kc get secret octopus-adminpassword -o jsonpath='{.data.secret}' | base64 -d \
       | jq -Rc '{Username: "admin", Password: .}' \
       | curl -fsS --connect-timeout 20 --cacert "$OCTOPUS_CA" -c "$T/jar" -o /dev/null \
           -H 'Content-Type: application/json' --data-binary @- "$U/users/login"; then
    X="$(awk '$6 ~ /^Octopus-Csrf-Token/ {print $7}' "$T/jar")"
    for E in dev test prod; do
      if api "$U/Spaces-1/environments/all" | jq -e --arg n "$E" 'any(.[]; .Name == $n)' >/dev/null; then
        echo "environment $E: exists"
      else
        jq -nc --arg n "$E" '{Name: $n}' | api --data-binary @- "$U/Spaces-1/environments" | jq -r '"environment \(.Name): created"'
      fi
    done
    if api "$U/Spaces-1/lifecycles/all" | jq -e 'any(.[]; .Name == "dev-test-prod")' >/dev/null; then
      echo "lifecycle dev-test-prod: exists"
    elif ENV="$(api "$U/Spaces-1/environments/all" | jq -c 'map({(.Name): .Id}) | add')"; then
      jq -nc --argjson e "$ENV" '{Name: "dev-test-prod", Phases: [
          {Name: "dev", AutomaticDeploymentTargets: [$e.dev], OptionalDeploymentTargets: [], MinimumEnvironmentsBeforePromotion: 0},
          {Name: "test", AutomaticDeploymentTargets: [], OptionalDeploymentTargets: [$e.test], MinimumEnvironmentsBeforePromotion: 0},
          {Name: "prod", AutomaticDeploymentTargets: [], OptionalDeploymentTargets: [$e.prod], MinimumEnvironmentsBeforePromotion: 0}]}' \
        | api --data-binary @- "$U/Spaces-1/lifecycles" | jq -r '"lifecycle \(.Name): created, phases " + ([.Phases[].Name] | join(","))'
    fi
  else
    echo "FAILED: sign-in refused (see the error above)"
  fi
  rm -rf "$T"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OCTOPUS_CA = "$HOME\octopus-ca.pem"

function kc { kubectl --kubeconfig $VKS_KUBECONFIG -n octopus @args }
$IP = kc get service octopus-web -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
$U = 'https://octopus-web.octopus.svc/api'; $RV = '--resolve', "octopus-web.octopus.svc:443:$IP"
$T = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
function api($path, $body) {
  $a = @('-fsS', '--connect-timeout', '20', '--ssl-no-revoke', '--cacert', $OCTOPUS_CA) + $RV + @('-b', "$T\jar", '-H', "X-Octopus-Csrf-Token: $X", '-H', 'Content-Type: application/json')
  if ($body) { [IO.File]::WriteAllText("$T\body.json", $body); $a += @('--data-binary', "@$T\body.json") }
  (curl.exe @a "$U/$path") | Out-String | ConvertFrom-Json
}
if (-not (Test-Path $OCTOPUS_CA)) { "MISSING: $OCTOPUS_CA (step 8)" }
else {
  New-Item -ItemType Directory -Path $T | Out-Null
  try {
    $B = kc get secret octopus-adminpassword -o 'jsonpath={.data.secret}'
    $P = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B))
    [IO.File]::WriteAllText("$T\login.json", (@{ Username = 'admin'; Password = $P } | ConvertTo-Json -Compress))
    $P = $null; $B = $null
    curl.exe -fsS --connect-timeout 20 --ssl-no-revoke --cacert $OCTOPUS_CA @RV -c "$T\jar" -o NUL -H 'Content-Type: application/json' --data-binary "@$T\login.json" "$U/users/login"
    if ($LASTEXITCODE -ne 0) { "FAILED: sign-in refused (see the error above)" }
    else {
      $X = (Select-String -Path "$T\jar" -Pattern 'Octopus-Csrf-Token\S*\s+(\S+)$').Matches[0].Groups[1].Value
      foreach ($E in 'dev', 'test', 'prod') {
        if ((api 'Spaces-1/environments/all').Name -contains $E) { "environment ${E}: exists" }
        else { $R = api 'Spaces-1/environments' (@{ Name = $E } | ConvertTo-Json -Compress); if ($R.Name) { "environment $($R.Name): created" } else { "FAILED: environment $E not created (see the error above)" } }
      }
      if ((api 'Spaces-1/lifecycles/all').Name -contains 'dev-test-prod') { "lifecycle dev-test-prod: exists" }
      else {
        $ID = @{}; foreach ($N in (api 'Spaces-1/environments/all')) { $ID[$N.Name] = $N.Id }
        $L = @{ Name = 'dev-test-prod'; Phases = @(
          @{ Name = 'dev'; AutomaticDeploymentTargets = @($ID['dev']); OptionalDeploymentTargets = @(); MinimumEnvironmentsBeforePromotion = 0 },
          @{ Name = 'test'; AutomaticDeploymentTargets = @(); OptionalDeploymentTargets = @($ID['test']); MinimumEnvironmentsBeforePromotion = 0 },
          @{ Name = 'prod'; AutomaticDeploymentTargets = @(); OptionalDeploymentTargets = @($ID['prod']); MinimumEnvironmentsBeforePromotion = 0 }) }
        $R = api 'Spaces-1/lifecycles' ($L | ConvertTo-Json -Depth 5 -Compress)
        if ($R.Name) { "lifecycle $($R.Name): created, phases $(($R.Phases | ForEach-Object { $_.Name }) -join ',')" } else { "FAILED: lifecycle not created (see the error above)" }
      }
    }
  } finally { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $T }
}
```

</details>

**Expect:** `environment dev: created`, the same for `test` and `prod`, then `lifecycle
dev-test-prod: created, phases dev,test,prod` (`exists` when run again).

**If not:** `FAILED: sign-in refused`: see step 9.

## 11. Trust Nexus and add it as a Docker feed (optional)

Run this only if Octopus deploys images from Nexus ([NEXUS.md](NEXUS.md)): Octopus checks Nexus's
certificate when it lists image tags, and does not trust Nexus's CA yet. It saves `nexus-ca.pem`
from [NEXUS.md step 7](NEXUS.md#7-save-nexuss-ca-and-check-its-address) as a ConfigMap (a store
for settings and files that are not secret, inside the cluster; here the certificate only, no
key), and writes a second values file, `values-ca.yaml`, that builds a CA bundle for Octopus when
it starts. You get Octopus ready to trust Nexus: then run step 7 again; it uses both values files,
and Octopus restarts once. Set `VKS_CLUSTER` to the name of Octopus's cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
OCTOPUS_DIR="$HOME/.config/vks-guides/octopus"
OCTOPUS_TAG="2026.3.16049@sha256:63a4d70d3011e546e7950671c2cee16a4737a8617748d931719c3fa114ce559d"
NEXUS_CA="$HOME/nexus-ca.pem"

if [ ! -s "$NEXUS_CA" ]; then
  echo "MISSING: $NEXUS_CA (NEXUS.md step 7)"
elif kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus create configmap nexus-ca --from-file=ca.crt="$NEXUS_CA" \
       --dry-run=client -o yaml | kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus apply -f - && mkdir -p "$OCTOPUS_DIR"; then
  cat > "$OCTOPUS_DIR/values-ca.yaml" <<EOF
octopus:
  extraVolumes:
    cabundle:
      type: emptyDir
      mountPath: /etc/octopus-ca
      sizeLimit: 10Mi
  containers:
    octopus:
      env:
        - name: SSL_CERT_FILE
          value: /etc/octopus-ca/bundle.pem
  spec:
    initContainers:
      - name: ca-bundle
        image: docker.io/octopusdeploy/octopusdeploy:${OCTOPUS_TAG}
        command:
          - sh
          - -c
          - cat /etc/ssl/certs/ca-certificates.crt > /etc/octopus-ca/bundle.pem && printf '%s\n' "\$EXTRA_CA" >> /etc/octopus-ca/bundle.pem && grep -c BEGIN /etc/octopus-ca/bundle.pem
        env:
          - name: EXTRA_CA
            valueFrom:
              configMapKeyRef:
                name: nexus-ca
                key: ca.crt
        securityContext:
          runAsNonRoot: true
          runAsUser: 999
          runAsGroup: 999
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
          seccompProfile:
            type: RuntimeDefault
        volumeMounts:
          - name: cabundle-volume
            mountPath: /etc/octopus-ca
EOF
  echo "wrote $OCTOPUS_DIR/values-ca.yaml: now run step 7 again"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$OCTOPUS_DIR = "$HOME\.config\vks-guides\octopus"
$OCTOPUS_TAG = "2026.3.16049@sha256:63a4d70d3011e546e7950671c2cee16a4737a8617748d931719c3fa114ce559d"
$NEXUS_CA = "$HOME\nexus-ca.pem"

$global:LASTEXITCODE = $null
if (-not (Test-Path $NEXUS_CA)) { "MISSING: $NEXUS_CA (NEXUS.md step 7)" }
else {
  kubectl --kubeconfig $VKS_KUBECONFIG -n octopus create configmap nexus-ca --from-file=ca.crt=$NEXUS_CA --dry-run=client -o yaml | kubectl --kubeconfig $VKS_KUBECONFIG -n octopus apply -f -
  if ($LASTEXITCODE -eq 0) {
    New-Item -ItemType Directory -Force -Path $OCTOPUS_DIR | Out-Null
    [IO.File]::WriteAllText("$OCTOPUS_DIR\values-ca.yaml", @"
octopus:
  extraVolumes:
    cabundle:
      type: emptyDir
      mountPath: /etc/octopus-ca
      sizeLimit: 10Mi
  containers:
    octopus:
      env:
        - name: SSL_CERT_FILE
          value: /etc/octopus-ca/bundle.pem
  spec:
    initContainers:
      - name: ca-bundle
        image: docker.io/octopusdeploy/octopusdeploy:$OCTOPUS_TAG
        command:
          - sh
          - -c
          - cat /etc/ssl/certs/ca-certificates.crt > /etc/octopus-ca/bundle.pem && printf '%s\n' "`$EXTRA_CA" >> /etc/octopus-ca/bundle.pem && grep -c BEGIN /etc/octopus-ca/bundle.pem
        env:
          - name: EXTRA_CA
            valueFrom:
              configMapKeyRef:
                name: nexus-ca
                key: ca.crt
        securityContext:
          runAsNonRoot: true
          runAsUser: 999
          runAsGroup: 999
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
          seccompProfile:
            type: RuntimeDefault
        volumeMounts:
          - name: cabundle-volume
            mountPath: /etc/octopus-ca
"@)
    "wrote $OCTOPUS_DIR\values-ca.yaml: now run step 7 again"
  }
}
```

</details>

**Expect:** `configmap/nexus-ca created` and `wrote …/values-ca.yaml: now run step 7 again`; after
step 7, `Octopus is ready`, and `kubectl --kubeconfig <file> -n octopus logs
octopus-octopus-deploy-0 -c ca-bundle` prints the number of CAs in the bundle (about 150).

Then add Nexus in the web page: **External Feeds** (under **Manage**) → **Add Feed** → **Feed
type** **Docker Container Registry**, **Feed name** `nexus`, **Feed url** `https://<NEXUS_REGISTRY>`
(it starts as `https://index.docker.io`: replace it), **Registry path** empty, **Credentials**
**Username and Password** with the pull user's name and password from
[NEXUS.md step 9](NEXUS.md#9-create-the-docker-repository-a-push-user-and-a-pull-user), then
**Save and test**:

![Create Feed: Feed type Docker Container Registry, Feed name, Feed url, Registry path](img/octopus/08-create-feed-docker.jpg)

**Save and test** opens **Test nexus**: type `apps/busybox` (the image
[NEXUS.md step 10](NEXUS.md#10-trust-nexus-and-push-an-image) pushed; `apps` is its `NEXUS_REPO`)
in **Package name** and click **Search**:

![Test nexus: Package name apps/busybox, Matching packages lists apps/busybox](img/octopus/09-test-feed.jpg)

**Expect:** **Matching packages** lists `apps/busybox`.

Octopus reads image tags as versions, so tag images with versions such as `1.0.0`. Name a package
by its full path in Nexus, `<NEXUS_REPO>/<image>` (for example `apps/busybox`).

**If not:**
- `The SSL connection could not be established, see inner exception. The remote certificate is
  invalid because of errors in the certificate chain: PartialChain`: Octopus does not trust
  Nexus's CA yet; run this step and step 7.
- `Error performing request to https://<NEXUS_REGISTRY>/v2/_catalog?n=100. The endpoint returned
  Not Found`: you searched a bare image name; search `<NEXUS_REPO>/<image>`.
- `MISSING: …nexus-ca.pem`: run NEXUS.md step 7 on this machine first.

## 12. Change the admin password

Run this to change the password of Octopus's user `admin` for good: Octopus sets `admin`'s password
from step 3's Secret each time it starts, so a password changed in the web page goes back at the
next restart. This replaces the Secret with the password you type and restarts Octopus (about a
minute). You then sign in with the new password. Set `VKS_CLUSTER` in the second block to the name
of Octopus's cluster. First type the new password, on its own (it is not shown):

**Linux, macOS, WSL (bash or zsh):**

```sh
printf 'New Octopus admin password: '; IFS= read -rs OCTOPUS_ADMIN_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$OCTOPUS_ADMIN_PASSWORD = Read-Host 'New Octopus admin password' -AsSecureString
```

Then:

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n octopus "$@"; }
if [ -z "${OCTOPUS_ADMIN_PASSWORD:-}" ]; then
  echo "STOPPED: type the new password first (the line above)"
elif printf '%s' "$OCTOPUS_ADMIN_PASSWORD" | kc create secret generic octopus-adminpassword --from-file=secret=/dev/stdin --dry-run=client -o yaml \
       | kc replace -f - \
     && kc delete pod octopus-octopus-deploy-0 && sleep 10 \
     && kc wait --for=condition=Ready pod/octopus-octopus-deploy-0 --timeout=10m; then
  echo "admin password: changed"
else
  echo "FAILED: see the error above"
fi
unset OCTOPUS_ADMIN_PASSWORD
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

function kc { $input | kubectl --kubeconfig $VKS_KUBECONFIG -n octopus @args }
$global:LASTEXITCODE = $null
if (-not $OCTOPUS_ADMIN_PASSWORD -or $OCTOPUS_ADMIN_PASSWORD.Length -eq 0) { "STOPPED: type the new password first (the line above)" }
else {
  $B = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Net.NetworkCredential]::new('', $OCTOPUS_ADMIN_PASSWORD).Password))
  @('apiVersion: v1', 'kind: Secret', 'metadata:', '  name: octopus-adminpassword', 'data:', "  secret: $B") | kc replace -f -
  $B = $null
  if ($LASTEXITCODE -eq 0) { kc delete pod octopus-octopus-deploy-0; Start-Sleep 10 }
  if ($LASTEXITCODE -eq 0) { kc wait --for=condition=Ready pod/octopus-octopus-deploy-0 --timeout=10m }
  if ($LASTEXITCODE -eq 0) { "admin password: changed" } else { "FAILED: see the error above" }
}
Remove-Variable -ErrorAction SilentlyContinue OCTOPUS_ADMIN_PASSWORD
```

</details>

**Expect:** `secret/octopus-adminpassword replaced`, `pod "octopus-octopus-deploy-0" deleted`,
`condition met`, then `admin password: changed`. Sign in with the new password.

**If not:**
- `STOPPED: type the new password first`: run the one-line block above, then this one, in the same
  terminal.
- `NotFound`: the Secret is not there; run step 3.
- `502 Bad Gateway` from the web page right after: Octopus is still starting; wait a few seconds.

## 13. Remove Octopus (optional)

Run this when you no longer need Octopus; to delete its cluster too, run this first, then
[CLUSTER.md step 8](CLUSTER.md#8-delete-the-cluster-optional). It removes Octopus and SQL Server and
deletes the namespace `octopus` with every Secret, the CA and the database, then waits until the
volumes are gone (SQL Server's, and Octopus's `package-repository-claim`, `artifacts-claim`,
`task-log-claim`, `audit-log-claim` and server log). Once the volumes are gone it also deletes step
11's `~/.config/vks-guides/octopus/values-ca.yaml`, whose ConfigMap goes with the namespace. You get
the cluster without Octopus: cert-manager stays; so do `octopus-ca.pem`, `values.yaml` and the CA
you trusted in step 9. Set `VKS_CLUSTER` to the name of Octopus's cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

helm uninstall octopus --kubeconfig "$VKS_KUBECONFIG" -n octopus
kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace octopus --wait --timeout=10m
for i in $(seq 60); do
  if ! V="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="octopus")]}{.metadata.name}{" "}{end}')"; then
    V="(the check failed, see the error above)"; break
  fi
  [ -z "$V" ] && break
  sleep 5
done
if [ -z "$V" ]; then rm -f "$HOME/.config/vks-guides/octopus/values-ca.yaml"; echo "Octopus's volumes are gone"; else echo "STILL THERE: $V"; fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-octopus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

helm uninstall octopus --kubeconfig $VKS_KUBECONFIG -n octopus
kubectl --kubeconfig $VKS_KUBECONFIG delete namespace octopus --wait --timeout=10m
foreach ($i in 1..60) {
  $global:LASTEXITCODE = $null
  $V = kubectl --kubeconfig $VKS_KUBECONFIG get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace==''octopus'')]}{.metadata.name}{'' ''}{end}'
  if ($LASTEXITCODE -ne 0) { $V = "(the check failed, see the error above)"; break }
  if (-not $V) { break }
  Start-Sleep 5
}
if (-not $V) { Remove-Item -Force -ErrorAction SilentlyContinue "$HOME\.config\vks-guides\octopus\values-ca.yaml"; "Octopus's volumes are gone" } else { "STILL THERE: $V" }
```

</details>

**Expect:** `release "octopus" uninstalled`, `namespace "octopus" deleted`, then `Octopus's volumes
are gone`. Run again, it prints `release: not found` and `namespaces "octopus" not found` first.

**If not:**
- `STILL THERE: …`: `kubectl --kubeconfig <file> describe pv <name>` shows why. Do not delete the
  cluster until it is gone.
- `STILL THERE: (the check failed …)`: kubectl could not read the cluster; the error above says why
  (`Unauthorized`: the file has expired, [get it again](LOGIN.md#get-the-vks-clusters-kubeconfig)).
  Then run the block again.

Back to [README](../README.md).
