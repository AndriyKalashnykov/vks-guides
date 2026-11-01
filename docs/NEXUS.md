# Run Nexus Repository in a VKS cluster

> [!NOTE]
> **Official Broadcom, Sonatype, cert-manager and Kubernetes documentation for this guide**
>
> - Broadcom: [Install an Add-on Using the VCF CLI](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/install-an-add-on-using-the-vcf-cli.html) (cert-manager), [Cluster with Additional Trusted CA Certificates](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/provisioning-tkg-service-clusters/using-the-cluster-v1beta1-api/using-the-versioned-clusterclass/v1beta1-example-cluster-with-additional-trusted-ca-certificates-for-ssl-tls.html), [KB 448189](https://knowledge.broadcom.com/external/article/448189/ssltls-server-certificates-specified-in.html) (trust the CA, not the server certificate)
> - Sonatype: [System requirements](https://help.sonatype.com/en/sonatype-nexus-repository-system-requirements.html), [Install with a PostgreSQL database](https://help.sonatype.com/en/install-nexus-repository-with-a-postgresql-database.html), [Docker registry](https://help.sonatype.com/en/docker-registry.html) (path-based routing), [Docker reverse proxy strategies](https://help.sonatype.com/en/docker-repository-reverse-proxy-strategies.html), [EULA REST API](https://help.sonatype.com/en/eula-rest-api.html), [Security Management API](https://help.sonatype.com/en/security-management-api.html), [Repositories API](https://help.sonatype.com/en/repositories-api.html), [Backup and restore](https://help.sonatype.com/en/backup-and-restore.html), [3.87.0 release notes](https://help.sonatype.com/en/sonatype-nexus-repository-3-87-0-release-notes.html) (Community Edition limits)
> - cert-manager: [CA issuer](https://cert-manager.io/docs/configuration/ca/), [SelfSigned issuer](https://cert-manager.io/docs/configuration/selfsigned/)
> - Kubernetes: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) (`restricted`), [Pull an Image from a Private Registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

Nexus Repository is a server for packages and container images. This runs Nexus Repository
Community Edition, with a PostgreSQL database for its data, in a VKS cluster, gives it an HTTPS
certificate and an address, creates a Docker repository with a user that may push and one that may
only pull, and lets VKS clusters pull images from it.

> [!NOTE]
> **Why plain manifests, not Helm.** Sonatype's maintained chart,
> [nxrm-ha](https://github.com/sonatype/nxrm3-ha-repository/blob/main/nxrm-ha/README.md), is for the
> paid Pro edition; the old chart is [unsupported](https://github.com/sonatype/nxrm3-helm-repository).

Nexus is reached at one address, `NEXUS_REGISTRY`: its load balancer IP address (step 4), or a DNS
name you point at it. Every block, image name and VKS cluster uses that same value. Images are
named `<NEXUS_REGISTRY>/<repository>/<image>:<tag>`, all on port 443 (Sonatype's path-based
routing). The registry-wide image list (`/v2/_catalog`) is not available this way: tools that list
all images, such as a search box in a deployment tool, find nothing, while each repository's own
list works.

Run the steps in order. Who does what:

- a vCenter administrator: the VM class for the cluster (Prerequisites);
- you, the administrator of Nexus's cluster: steps 1 to 9, 12 and 13;
- everyone who pushes images: step 10;
- the administrator of each VKS cluster that pulls from Nexus: step 11.

## Prerequisites

- a VKS cluster for Nexus, made as below;
- the [VCF CLI](VCF.md) with the context `supervisor` ([LOGIN.md](LOGIN.md)), for the cert-manager
  add-on (step 2), and the Supervisor kubeconfig `~/.kube/supervisor.kubeconfig` for step 11;
- [kubectl](KUBECTL.md), [jq, curl and openssl](PREREQS.md), and
  [podman or docker](PREREQS.md#podman-and-docker-optional) for step 10;
- one free load-balancer address, for Nexus (step 4).

Sizing. Sonatype recommends, for its smallest profile (XS, up to 100 requests a second),
4 vCPUs and 16 GiB of memory for Nexus, with at most two-thirds of the memory given to Nexus
([System requirements](https://help.sonatype.com/en/sonatype-nexus-repository-system-requirements.html)):
the VM class `best-effort-large` (4 CPUs, 16 GB). This guide's manifests ask for 0.5 CPU and
3 GiB for Nexus (at most 4 GiB), 0.1 CPU and 512 MiB for PostgreSQL (at most 1 GiB) and a little
for nginx, so by those requests the smallest worker they fit on is `best-effort-medium` (2 CPUs,
8 GB).
<!-- TODO-MEASURE: VKS lab numbers (kubectl top, worker allocatable, esxi host memory) on best-effort-medium -->
The Community Edition stops adding new components above 40,000 components or 100,000 requests a
day ([3.87.0 release notes](https://help.sonatype.com/en/sonatype-nexus-repository-3-87-0-release-notes.html)).

The cluster for Nexus:

1. Its vSphere Namespace offers the VM class `best-effort-medium` or larger
   ([NAMESPACE.md step 8](NAMESPACE.md#8-check-the-namespace) lists them under `VM classes:`; a
   vCenter administrator adds one with [NAMESPACE.md step 6](NAMESPACE.md#6-add-the-vm-classes)).
2. Create the cluster with
   [CLUSTER.md step 9](CLUSTER.md#9-create-the-cluster-with-kubectl-and-a-yaml-file), with that
   `vmClass`, one control-plane node and one worker (`replicas: 1` for both). Nexus's volumes take
   25 GB (20 GB for images, 5 GB for PostgreSQL) on top of the nodes
   ([CLUSTER.md step 2](CLUSTER.md#2-choose-a-name-and-the-values)).
   <!-- TODO-MEASURE: namespace storage used by the cluster plus volumes, and during an update -->
   To change its size later, see [CLUSTER.md step 10](CLUSTER.md#10-resize-the-cluster-optional).
3. Save its kubeconfig as `~/.kube/<cluster name>.kubeconfig`
   ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig)).

The connections this guide needs, for a firewall (all TCP, besides DNS; for a registry, also
[its other hosts](PREREQS.md#registry-hosts-for-a-firewall)):

| from | to | port | for |
|---|---|---|---|
| your machine | the Supervisor's address | 443 | the VCF CLI (step 2), kubectl with the Supervisor kubeconfig (step 11) |
| your machine | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl (steps 1 to 8, 12 and 13) |
| your machine | each pulling VKS cluster's API address (its kubeconfig) | 6443 | the Secret and the test pod (step 11) |
| the cluster's nodes | `projects.packages.broadcom.com` | 443 | the cert-manager add-on (step 2) |
| the cluster's nodes | `docker.io` | 443 | the Nexus, PostgreSQL and TLS proxy images (step 6) |
| your machine | Nexus's address (step 4) | 443 | Nexus's REST API (steps 7 to 9), login and push (step 10) |
| your machine | `docker.io` | 443 | the test image (step 10) |
| the nodes of the VKS clusters that pull from Nexus | Nexus's address | 443 | pulling images (step 11) |

## 1. Check the cluster

This checks that the nodes are ready, that the cluster has a default storage class, and how much
memory the workers can give pods. Nexus, PostgreSQL and the TLS proxy ask for about 3.6 GiB of it.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

if ! command -v kubectl >/dev/null 2>&1; then echo "MISSING: kubectl (KUBECTL.md)"
elif ! command -v jq >/dev/null 2>&1; then echo "MISSING: jq (PREREQS.md)"
elif [ ! -s "$VKS_KUBECONFIG" ]; then echo "MISSING: $VKS_KUBECONFIG (LOGIN.md)"
elif kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes -o wide && J="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get storageclass -o json)"; then
  echo "default storage class: $(printf '%s' "$J" | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name] | if length == 0 then "NONE" else join(" ") end')"
  kubectl --kubeconfig "$VKS_KUBECONFIG" get nodes -l '!node-role.kubernetes.io/control-plane' \
    -o custom-columns='WORKER:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory'
  kubectl --kubeconfig "$VKS_KUBECONFIG" get namespace nexus 2>/dev/null && echo "NOTE: namespace nexus exists already"
else
  echo "FAILED: cannot read the cluster (see the error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$global:LASTEXITCODE = $null
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { "MISSING: kubectl (KUBECTL.md)"; $global:LASTEXITCODE = 1 }
elseif (-not (Test-Path $VKS_KUBECONFIG)) { "MISSING: $VKS_KUBECONFIG (LOGIN.md)"; $global:LASTEXITCODE = 1 }
else { kubectl --kubeconfig $VKS_KUBECONFIG get nodes -o wide }
if ($LASTEXITCODE -eq 0) { $J = kubectl --kubeconfig $VKS_KUBECONFIG get storageclass -o json | Out-String }
if ($LASTEXITCODE -eq 0) {
  $D = @((ConvertFrom-Json $J).items | Where-Object { $_.metadata.annotations.'storageclass.kubernetes.io/is-default-class' -eq 'true' } | ForEach-Object { $_.metadata.name })
  "default storage class: $(if ($D.Count) { $D -join ' ' } else { 'NONE' })"
  kubectl --kubeconfig $VKS_KUBECONFIG get nodes -l '!node-role.kubernetes.io/control-plane' -o 'custom-columns=WORKER:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory'
  kubectl --kubeconfig $VKS_KUBECONFIG get namespace nexus 2>$null
  if ($LASTEXITCODE -eq 0) { "NOTE: namespace nexus exists already" }
} else {
  "FAILED: cannot read the cluster (see the error above)"
}
```

</details>

**Expect:** each node `Ready`, `default storage class:` and a class name, and a worker with
`MEMORY` of about `6197436Ki` for `best-effort-medium`.

**If not:** `default storage class: NONE`: give the cluster a default class as in
[CLUSTER.md](CLUSTER.md), step 9's `defaultStorageClass`. A worker with less than about
`4500000Ki`: Nexus does not fit; use a larger VM class. `NOTE: namespace nexus exists already`:
Nexus may be installed; steps 3 to 6 keep what exists.
<!-- TODO-MEASURE: the worker memory threshold (about 4500000Ki) Nexus, PostgreSQL and nginx need on VKS -->

## 2. Install cert-manager

Nexus's HTTPS certificate (step 5) comes from cert-manager, a Broadcom add-on of the VKS cluster
([what add-ons are](ADDONS.md)). Run
[KEYCLOAK-VKS.md step 2](KEYCLOAK-VKS.md#2-install-cert-manager) once, with `VKS_CLUSTER` set to
Nexus's cluster and `VKS_NAMESPACE` to its vSphere Namespace. When the add-on is there already, it
changes nothing.

**Expect:** as in that step: `condition met` for the three cert-manager deployments, or
`cert-manager: already installed`.

## 3. Create the namespace and the database password

This creates the namespace `nexus`, which allows only pods that follow the `restricted` Pod
Security Standard, and a Secret with a random password for PostgreSQL. Nothing prints the password.
A Secret that exists is kept: PostgreSQL keeps the password it was first given.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" "$@"; }
command -v kubectl >/dev/null 2>&1 || echo "MISSING: kubectl (KUBECTL.md)"
kc create namespace nexus --dry-run=client -o yaml | kc apply -f - >/dev/null \
  && kc label namespace nexus --overwrite pod-security.kubernetes.io/enforce=restricted \
       pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/warn=restricted
P=
if kc -n nexus get secret nexus-db >/dev/null 2>&1; then
  echo "secret nexus-db: exists, kept"
elif ! P="$(openssl rand -hex 24)" || [ ${#P} -ne 48 ]; then
  echo "FAILED: no password made: openssl (PREREQS.md)"
else
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: nexus-db\nstringData:\n  username: nexus\n  password: %s\n' "$P" \
    | kc -n nexus create -f -
fi
unset P
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

function kc { $input | kubectl --kubeconfig $VKS_KUBECONFIG @args }
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { "MISSING: kubectl (KUBECTL.md)" }
kc create namespace nexus --dry-run=client -o yaml | kc apply -f - | Out-Null
kc label namespace nexus --overwrite pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/warn=restricted
kc -n nexus get secret nexus-db 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  "secret nexus-db: exists, kept"
} else {
  $B = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($B)
  $P = ($B | ForEach-Object { $_.ToString('x2') }) -join ''
  @('apiVersion: v1', 'kind: Secret', 'metadata:', '  name: nexus-db', 'stringData:', '  username: nexus', "  password: $P") | kc -n nexus create -f -
  Remove-Variable P
}
```

</details>

**Expect:** `namespace/nexus labeled` (or `not labeled` when run again), then
`secret/nexus-db created` (or `exists, kept`).

**If not:** `Error from server (Forbidden)`: the kubeconfig is not the cluster's administrator file.

## 4. Create the Service and get Nexus's address

This creates Nexus's Service, which gets an address from the Supervisor's load balancer, port 443,
and prints that address. Nexus itself starts in step 6. The address stays while the Service exists;
deleting the Service gives its address back, and a new Service can get another one: then step 5,
step 7 and every image name, login and VKS cluster that uses the old address must change.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

cat <<'EOF' | kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nexus
spec:
  type: LoadBalancer
  selector:
    app: nexus
  ports:
    - name: https
      port: 443
      targetPort: 8443
EOF
IP=""
for i in $(seq 60); do
  IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus get service nexus -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  [ -n "$IP" ] && break
  sleep 5
done
if [ -n "$IP" ]; then echo "Nexus's address: $IP"; else echo "FAILED: no load balancer address in 5 minutes"; fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

@'
apiVersion: v1
kind: Service
metadata:
  name: nexus
spec:
  type: LoadBalancer
  selector:
    app: nexus
  ports:
    - name: https
      port: 443
      targetPort: 8443
'@ | kubectl --kubeconfig $VKS_KUBECONFIG -n nexus apply -f -
$IP = ''
foreach ($i in 1..60) {
  $IP = kubectl --kubeconfig $VKS_KUBECONFIG -n nexus get service nexus -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
  if ($IP) { break }
  Start-Sleep 5
}
if ($IP) { "Nexus's address: $IP" } else { "FAILED: no load balancer address in 5 minutes" }
```

</details>

**Expect:** `service/nexus created` (`unchanged` when run again), then `Nexus's address:` and an IP
address. Use it as `NEXUS_REGISTRY` from here on, or create a DNS record (type A) for a name with
this address, in the DNS that your machine, the pushers' machines and the VKS cluster nodes use,
and use the name.

**If not:** `FAILED: no load balancer address`: the cluster has no free load balancer address; ask
your vSphere administrator.

## 5. Make Nexus's certificate

This makes a CA (certificate authority) of your own with cert-manager, valid for 10 years, and from
it a certificate for Nexus's address from step 4, for `NEXUS_REGISTRY` when it is a DNS name, and
for Nexus's name inside the cluster. cert-manager renews the certificate before it ends; the TLS
proxy picks the new one up within about 6 minutes, without restarting Nexus. The CA itself is renewed
with a new key after about 6.5 years: then hand out the new CA (steps 7, 10 and 11) again.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
NEXUS_REGISTRY="192.168.10.50"

IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus get service nexus -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
NAMES="    - nexus.nexus.svc"
if printf '%s\n' "$NEXUS_REGISTRY" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then IS_IP=1; else IS_IP=""; NAMES="    - ${NEXUS_REGISTRY}
${NAMES}"; fi
if [ -z "$IP" ]; then
  echo "FAILED: the Service nexus has no address (step 4)"
elif [ -n "$IS_IP" ] && [ "$NEXUS_REGISTRY" != "$IP" ]; then
  echo "STOPPED: NEXUS_REGISTRY is $NEXUS_REGISTRY, but Nexus's address is $IP"
else
cat <<EOF | kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus apply -f - \
  && kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus wait --for=condition=Ready certificate --all --timeout=3m
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: nexus-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nexus-ca
spec:
  isCA: true
  commonName: Nexus CA
  duration: 87600h
  secretName: nexus-ca
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: nexus-selfsigned
    kind: Issuer
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: nexus-ca
spec:
  ca:
    secretName: nexus-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nexus-tls
spec:
  secretName: nexus-tls
  commonName: ${NEXUS_REGISTRY}
  ipAddresses:
    - ${IP}
  dnsNames:
${NAMES}
  usages:
    - server auth
  issuerRef:
    name: nexus-ca
    kind: Issuer
EOF
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$NEXUS_REGISTRY = "192.168.10.50"

$global:LASTEXITCODE = $null
$IP = kubectl --kubeconfig $VKS_KUBECONFIG -n nexus get service nexus -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
$IS_IP = $NEXUS_REGISTRY -match '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
$NAMES = if ($IS_IP) { "    - nexus.nexus.svc" } else { "    - $NEXUS_REGISTRY`n    - nexus.nexus.svc" }
if (-not $IP) { "FAILED: the Service nexus has no address (step 4)" }
elseif ($IS_IP -and $NEXUS_REGISTRY -ne $IP) { "STOPPED: NEXUS_REGISTRY is $NEXUS_REGISTRY, but Nexus's address is $IP" }
else {
@"
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: nexus-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nexus-ca
spec:
  isCA: true
  commonName: Nexus CA
  duration: 87600h
  secretName: nexus-ca
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: nexus-selfsigned
    kind: Issuer
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: nexus-ca
spec:
  ca:
    secretName: nexus-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nexus-tls
spec:
  secretName: nexus-tls
  commonName: $NEXUS_REGISTRY
  ipAddresses:
    - $IP
  dnsNames:
$NAMES
  usages:
    - server auth
  issuerRef:
    name: nexus-ca
    kind: Issuer
"@ | kubectl --kubeconfig $VKS_KUBECONFIG -n nexus apply -f -
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n nexus wait --for=condition=Ready certificate --all --timeout=3m }
}
```

</details>

**Expect:** four `created` lines (`configured` or `unchanged` when run again), then
`certificate.cert-manager.io/nexus-ca condition met` and `…/nexus-tls condition met`.

**If not:**
- `no matches for kind "Issuer"`: step 2 did not finish.
- `failed calling webhook "webhook.cert-manager.io"`: cert-manager is still starting. Wait a minute
  and run this block again.
- `STOPPED: NEXUS_REGISTRY is …`: set `NEXUS_REGISTRY` to the address step 4 printed, or to a DNS
  name.
- `timed out`: `kubectl -n nexus describe certificate nexus-tls` shows why.

## 6. Run PostgreSQL and Nexus

This runs PostgreSQL with a 5 GB volume, waits until it is ready, then runs Nexus with a 20 GB
volume for its images and files, and next to it a small nginx web server that takes HTTPS on
Nexus's address and passes it on to Nexus. Nexus takes a few minutes to start the first time.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
NEXUS_IMAGE="docker.io/sonatype/nexus3:3.97.3@sha256:4b9a0efb605808c15927c751107b3f3308ae306c4b22715c96bf9bbabbb0e736"
POSTGRES_IMAGE="docker.io/library/postgres:18.6@sha256:3a4264520e121176619f54ff867d12774bc81e95e7b84db58d63bccdb6144b81"
PROXY_IMAGE="docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"

cat <<'EOF' | kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nexus-proxy
data:
  default.conf: |
    server {
      listen 8443 ssl;
      ssl_certificate /etc/nexus-tls/tls.crt;
      ssl_certificate_key /etc/nexus-tls/tls.key;
      client_max_body_size 0;
      proxy_request_buffering off;
      proxy_buffering off;
      location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 900s;
      }
    }
  start.sh: |
    s="$(sha256sum /etc/nexus-tls/tls.crt)"
    (while sleep 300; do n="$(sha256sum /etc/nexus-tls/tls.crt)"; if [ "$n" = "$s" ]; then :; else nginx -t && nginx -s reload && s="$n"; fi; done) &
    exec nginx -g 'daemon off;'
EOF
cat <<EOF | kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus apply -f -
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: postgres
          image: ${POSTGRES_IMAGE}
          args: ["-c", "max_connections=200"]
          env:
            - name: POSTGRES_DB
              value: nexus
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: nexus-db
                  key: username
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nexus-db
                  key: password
          ports:
            - containerPort: 5432
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "nexus", "-d", "nexus"]
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              memory: 1Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
EOF
if ! kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus rollout status statefulset/postgres --timeout=10m; then
  echo "FAILED: PostgreSQL did not start (see above)"
else
cat <<EOF | kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: nexus
spec:
  serviceName: nexus
  replicas: 1
  selector:
    matchLabels:
      app: nexus
  template:
    metadata:
      labels:
        app: nexus
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 200
        runAsGroup: 200
        fsGroup: 200
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: nexus
          image: ${NEXUS_IMAGE}
          env:
            - name: INSTALL4J_ADD_VM_PARAMS
              value: "-Xms1g -Xmx2g -XX:MaxDirectMemorySize=512m -Djava.util.prefs.userRoot=/nexus-data/javaprefs"
            - name: NEXUS_DATASTORE_NEXUS_JDBCURL
              value: jdbc:postgresql://postgres:5432/nexus
            - name: NEXUS_DATASTORE_NEXUS_USERNAME
              valueFrom:
                secretKeyRef:
                  name: nexus-db
                  key: username
            - name: NEXUS_DATASTORE_NEXUS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nexus-db
                  key: password
          ports:
            - containerPort: 8081
          startupProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
            periodSeconds: 10
            failureThreshold: 60
          livenessProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
            periodSeconds: 30
            failureThreshold: 6
          readinessProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
          resources:
            requests:
              cpu: 500m
              memory: 3Gi
            limits:
              memory: 4Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: data
              mountPath: /nexus-data
        - name: proxy
          image: ${PROXY_IMAGE}
          command: ["/bin/sh", "/etc/nginx/conf.d/start.sh"]
          ports:
            - containerPort: 8443
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              memory: 128Mi
          securityContext:
            runAsUser: 101
            runAsGroup: 101
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: proxy-conf
              mountPath: /etc/nginx/conf.d
            - name: tls
              mountPath: /etc/nexus-tls
              readOnly: true
      volumes:
        - name: proxy-conf
          configMap:
            name: nexus-proxy
        - name: tls
          secret:
            secretName: nexus-tls
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
EOF
kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus rollout status statefulset/nexus --timeout=15m
kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus exec postgres-0 -- psql -U nexus -d nexus -tA \
  -c "select 'database owner: ' || pg_get_userbyid(datdba) from pg_database where datname='nexus'" \
  -c "select 'pg_trgm: ' || extversion from pg_extension where extname='pg_trgm'"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$NEXUS_IMAGE = "docker.io/sonatype/nexus3:3.97.3@sha256:4b9a0efb605808c15927c751107b3f3308ae306c4b22715c96bf9bbabbb0e736"
$POSTGRES_IMAGE = "docker.io/library/postgres:18.6@sha256:3a4264520e121176619f54ff867d12774bc81e95e7b84db58d63bccdb6144b81"
$PROXY_IMAGE = "docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"

$global:LASTEXITCODE = $null
@'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nexus-proxy
data:
  default.conf: |
    server {
      listen 8443 ssl;
      ssl_certificate /etc/nexus-tls/tls.crt;
      ssl_certificate_key /etc/nexus-tls/tls.key;
      client_max_body_size 0;
      proxy_request_buffering off;
      proxy_buffering off;
      location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 900s;
      }
    }
  start.sh: |
    s="$(sha256sum /etc/nexus-tls/tls.crt)"
    (while sleep 300; do n="$(sha256sum /etc/nexus-tls/tls.crt)"; if [ "$n" = "$s" ]; then :; else nginx -t && nginx -s reload && s="$n"; fi; done) &
    exec nginx -g 'daemon off;'
'@ | kubectl --kubeconfig $VKS_KUBECONFIG -n nexus apply -f -
@"
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: postgres
          image: $POSTGRES_IMAGE
          args: ["-c", "max_connections=200"]
          env:
            - name: POSTGRES_DB
              value: nexus
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: nexus-db
                  key: username
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nexus-db
                  key: password
          ports:
            - containerPort: 5432
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "nexus", "-d", "nexus"]
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              memory: 1Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
"@ | kubectl --kubeconfig $VKS_KUBECONFIG -n nexus apply -f -
kubectl --kubeconfig $VKS_KUBECONFIG -n nexus rollout status statefulset/postgres --timeout=10m
if ($LASTEXITCODE -ne 0) { "FAILED: PostgreSQL did not start (see above)" } else {
@"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: nexus
spec:
  serviceName: nexus
  replicas: 1
  selector:
    matchLabels:
      app: nexus
  template:
    metadata:
      labels:
        app: nexus
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 200
        runAsGroup: 200
        fsGroup: 200
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: nexus
          image: $NEXUS_IMAGE
          env:
            - name: INSTALL4J_ADD_VM_PARAMS
              value: "-Xms1g -Xmx2g -XX:MaxDirectMemorySize=512m -Djava.util.prefs.userRoot=/nexus-data/javaprefs"
            - name: NEXUS_DATASTORE_NEXUS_JDBCURL
              value: jdbc:postgresql://postgres:5432/nexus
            - name: NEXUS_DATASTORE_NEXUS_USERNAME
              valueFrom:
                secretKeyRef:
                  name: nexus-db
                  key: username
            - name: NEXUS_DATASTORE_NEXUS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nexus-db
                  key: password
          ports:
            - containerPort: 8081
          startupProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
            periodSeconds: 10
            failureThreshold: 60
          livenessProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
            periodSeconds: 30
            failureThreshold: 6
          readinessProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
          resources:
            requests:
              cpu: 500m
              memory: 3Gi
            limits:
              memory: 4Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: data
              mountPath: /nexus-data
        - name: proxy
          image: $PROXY_IMAGE
          command: ["/bin/sh", "/etc/nginx/conf.d/start.sh"]
          ports:
            - containerPort: 8443
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              memory: 128Mi
          securityContext:
            runAsUser: 101
            runAsGroup: 101
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: proxy-conf
              mountPath: /etc/nginx/conf.d
            - name: tls
              mountPath: /etc/nexus-tls
              readOnly: true
      volumes:
        - name: proxy-conf
          configMap:
            name: nexus-proxy
        - name: tls
          secret:
            secretName: nexus-tls
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
"@ | kubectl --kubeconfig $VKS_KUBECONFIG -n nexus apply -f -
kubectl --kubeconfig $VKS_KUBECONFIG -n nexus rollout status statefulset/nexus --timeout=15m
kubectl --kubeconfig $VKS_KUBECONFIG -n nexus exec postgres-0 -- psql -U nexus -d nexus -tA -c "select 'database owner: ' || pg_get_userbyid(datdba) from pg_database where datname='nexus'" -c "select 'pg_trgm: ' || extversion from pg_extension where extname='pg_trgm'"
}
```

</details>

**Expect:** `created` lines, `partitioned roll out complete` for PostgreSQL and then for Nexus, then
`database owner: nexus` and `pg_trgm:` with a version such as `1.6` (Nexus adds it at its first
start). A second run prints `unchanged` or `statefulset.apps/… configured` with no change: nothing
restarts.

**If not:**
- `FAILED: PostgreSQL did not start` or a timeout: `kubectl -n nexus describe pod -l app=postgres`
  (or `-l app=nexus`) shows the reason. `ImagePullBackOff`: the nodes cannot reach `docker.io`
  (see the table above). `Pending` with `Insufficient memory`: the worker is too small (see the
  Prerequisites).
- `secret "nexus-tls" not found` in `describe pod -l app=nexus`: step 5 did not finish; run it,
  then this block again.
- Nexus restarts with `too many clients already` in `kubectl -n nexus logs postgres-0`: PostgreSQL
  runs without `max_connections=200`; run this block again.
- `pg_trgm:` with nothing after it: Nexus has not finished its first start; run the last line again
  in a minute.

## 7. Save Nexus's CA and check its address

This saves the CA from step 5 as `nexus-ca.pem` in your home folder, prints its fingerprint, and
checks that Nexus answers on `NEXUS_REGISTRY` with a certificate from that CA. Everyone who pushes
needs this file (step 10), and so does each VKS cluster that pulls (step 11). It holds no secret.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
NEXUS_REGISTRY="192.168.10.50"
NEXUS_CA="$HOME/nexus-ca.pem"

if kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus get secret nexus-tls \
     -o go-template='{{index .data "ca.crt" | base64decode}}' > "$NEXUS_CA.new" \
   && openssl x509 -in "$NEXUS_CA.new" -noout -subject -fingerprint -sha256; then
  mv "$NEXUS_CA.new" "$NEXUS_CA" && echo "saved $NEXUS_CA"
  curl -fsS --connect-timeout 20 --cacert "$NEXUS_CA" -o /dev/null "https://${NEXUS_REGISTRY}/service/rest/v1/status/writable" \
    && echo "Nexus answers at https://${NEXUS_REGISTRY}"
else
  rm -f "$NEXUS_CA.new"; echo "FAILED: no CA read (see the error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$NEXUS_REGISTRY = "192.168.10.50"
$NEXUS_CA = "$HOME\nexus-ca.pem"

$global:LASTEXITCODE = $null
$B = kubectl --kubeconfig $VKS_KUBECONFIG -n nexus get secret nexus-tls -o 'jsonpath={.data.ca\.crt}'
if ($LASTEXITCODE -eq 0 -and $B) {
  $PEM = [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($B))
  $C = New-Object Security.Cryptography.X509Certificates.X509Certificate2 (,[Text.Encoding]::ASCII.GetBytes($PEM))
  "subject=$($C.Subject)"
  "sha256 Fingerprint=$([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($C.RawData)).Replace('-', ':'))"
  Set-Content -Encoding ascii -NoNewline -Path $NEXUS_CA -Value $PEM
  "saved $NEXUS_CA"
  curl.exe -fsS --connect-timeout 20 --ssl-no-revoke --cacert $NEXUS_CA "https://$NEXUS_REGISTRY/service/rest/v1/status/writable"
  if ($LASTEXITCODE -eq 0) { "Nexus answers at https://$NEXUS_REGISTRY" }
} else {
  "FAILED: no CA read (see the error above)"
}
```

</details>

**Expect:** a `subject=` line with `Nexus CA`, a `sha256 Fingerprint=…` line, `saved …/nexus-ca.pem`,
then `Nexus answers at https://<NEXUS_REGISTRY>`.

**If not:**
- `Could not resolve host`: the DNS record for `NEXUS_REGISTRY` is missing, or not yet seen by this
  machine.
- `SSL: no alternative certificate subject name matches` or `SSL certificate problem`:
  `NEXUS_REGISTRY` is not the value step 5 was run with.
- `The requested URL returned error: 503`: Nexus is still starting; run the block again in a
  minute.
- `Connection refused` or a timeout: this machine cannot reach Nexus's address on port 443.
- `Connection refused` or SSL errors after it worked: the address changed; run step 4, then steps
  5, 7, 10 and 11 with the new address.
- `CERT_TRUST_REVOCATION_STATUS_UNKNOWN` (Windows): `curl.exe` without `--ssl-no-revoke`; a CA of
  your own publishes no revocation list.

## 8. Sign in for the first time

Nexus starts with the user `admin` and a random first password in its volume. This changes the
password to one you type, accepts the Community Edition's end-user license agreement
([EULA](https://links.sonatype.com/products/nxrm/ce-eula); read it first: running this block
agrees to it), turns on Docker logins (the `DockerToken` realm), and turns off anonymous access, so
that only users who log in can read or push. The password is passed to curl in a file only you can
read, which is deleted at the end; it is never shown or saved.

Type the new password for `admin`, on its own (it is not shown):

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
printf 'New admin password: '; IFS= read -rs NEXUS_ADMIN_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$NEXUS_ADMIN_PASSWORD = Read-Host 'New admin password' -AsSecureString
```

Then:

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
NEXUS_REGISTRY="192.168.10.50"
NEXUS_CA="$HOME/nexus-ca.pem"

U="https://${NEXUS_REGISTRY}/service/rest/v1"
cfg() { printf 'user = "admin:%s"\n' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')" > "$T/admin.cfg"; }
nx() { curl -fsS --connect-timeout 20 --cacert "$NEXUS_CA" -K "$T/admin.cfg" "$@"; }
if [ -z "${NEXUS_ADMIN_PASSWORD:-}" ]; then
  echo "STOPPED: type the new admin password first (the line above)"
elif [ ! -s "$NEXUS_CA" ]; then
  echo "MISSING: $NEXUS_CA (step 7)"
elif T="$(umask 077 && mktemp -d)"; then
  P0="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus exec nexus-0 -c nexus -- cat /nexus-data/admin.password 2>/dev/null)"
  if [ -n "$P0" ]; then
    cfg "$P0"
    printf '%s' "$NEXUS_ADMIN_PASSWORD" | nx -X PUT -H 'Content-Type: text/plain' --data-binary @- \
      "$U/security/users/admin/change-password" && echo "admin password: changed"
  else
    echo "admin password: changed before (no first password in the pod)"
  fi
  cfg "$NEXUS_ADMIN_PASSWORD"
  E="$(nx "$U/system/eula")" && printf '%s' "$E" | jq -c '.accepted = true' \
    | nx -X POST -H 'Content-Type: application/json' --data-binary @- "$U/system/eula"
  printf '["NexusAuthenticatingRealm","DockerToken"]' \
    | nx -X PUT -H 'Content-Type: application/json' --data-binary @- "$U/security/realms/active"
  printf '{"enabled":false,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' \
    | nx -X PUT -H 'Content-Type: application/json' --data-binary @- "$U/security/anonymous" >/dev/null
  echo "EULA accepted: $(nx "$U/system/eula" | jq -r .accepted)"
  echo "realms: $(nx "$U/security/realms/active" | jq -c .)"
  echo "anonymous access: $(nx "$U/security/anonymous" | jq -r .enabled)"
  rm -rf "$T"
fi
unset P0 NEXUS_ADMIN_PASSWORD
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$NEXUS_REGISTRY = "192.168.10.50"
$NEXUS_CA = "$HOME\nexus-ca.pem"

$U = "https://$NEXUS_REGISTRY/service/rest/v1"
$T = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
$OutputEncoding = New-Object Text.UTF8Encoding $false
function cfg($p) { [IO.File]::WriteAllText("$T\admin.cfg", "user = `"admin:$($p.Replace('\', '\\').Replace('"', '\"'))`"`n") }
function nx { $input | curl.exe -fsS --connect-timeout 20 --ssl-no-revoke --cacert $NEXUS_CA -K "$T\admin.cfg" @args }
if (-not $NEXUS_ADMIN_PASSWORD -or $NEXUS_ADMIN_PASSWORD.Length -eq 0) { "STOPPED: type the new admin password first (the line above)" }
elseif (-not (Test-Path $NEXUS_CA)) { "MISSING: $NEXUS_CA (step 7)" }
else {
  New-Item -ItemType Directory -Path $T | Out-Null
  try {
    $NEW = [Net.NetworkCredential]::new('', $NEXUS_ADMIN_PASSWORD).Password
    $P0 = kubectl --kubeconfig $VKS_KUBECONFIG -n nexus exec nexus-0 -c nexus -- cat /nexus-data/admin.password 2>$null
    if ($P0) {
      cfg "$P0"
      $NEW | nx -X PUT -H 'Content-Type: text/plain' -d '@-' "$U/security/users/admin/change-password"
      if ($LASTEXITCODE -eq 0) { "admin password: changed" }
    } else { "admin password: changed before (no first password in the pod)" }
    cfg $NEW
    nx -o "$T\eula.json" "$U/system/eula"
    if ($LASTEXITCODE -eq 0) {
      ([IO.File]::ReadAllText("$T\eula.json") -replace '"accepted"\s*:\s*false', '"accepted":true') |
        nx -X POST -H 'Content-Type: application/json' -d '@-' "$U/system/eula"
    }
    '["NexusAuthenticatingRealm","DockerToken"]' | nx -X PUT -H 'Content-Type: application/json' -d '@-' "$U/security/realms/active"
    '{"enabled":false,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' | nx -X PUT -H 'Content-Type: application/json' -d '@-' "$U/security/anonymous" | Out-Null
    "EULA accepted: $((nx "$U/system/eula" | Out-String | ConvertFrom-Json).accepted)"
    "realms: $((nx "$U/security/realms/active" | Out-String | ConvertFrom-Json) -join ',')"
    "anonymous access: $((nx "$U/security/anonymous" | Out-String | ConvertFrom-Json).enabled)"
  } finally { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $T; $NEW = $null; $P0 = $null }
}
Remove-Variable -ErrorAction SilentlyContinue NEXUS_ADMIN_PASSWORD
```

</details>

**Expect:** `admin password: changed` (or `changed before` when run again), then
`EULA accepted: true`, `realms: ["NexusAuthenticatingRealm","DockerToken"]` (PowerShell:
`NexusAuthenticatingRealm,DockerToken`) and `anonymous access: false`.

**If not:**
- `STOPPED: type the new admin password first`: run the one-line block above, then this one, in
  the same terminal.
- `The requested URL returned error: 401` after `changed before`: the password you typed is not
  `admin`'s current password. When run again, type the password you set the first time.
- `The requested URL returned error: 400` at the password change: Nexus refused the password; type
  a longer one and run both blocks again.
- `MISSING: …nexus-ca.pem` or `SSL certificate problem`: run step 7 first.

## 9. Create the Docker repository, a push user and a pull user

This creates a Docker repository `NEXUS_REPO` with path-based routing (images named
`<NEXUS_REGISTRY>/<NEXUS_REPO>/<image>:<tag>`), where a tag, once pushed, cannot be pushed again
with other content. It then creates two users with passwords you type: `NEXUS_PUSH_USER`, who may read and push in
that repository only (for you and your builds), and `NEXUS_PULL_USER`, who may only read it (for
the VKS clusters, step 11). It skips what exists.

Type `admin`'s password, then the push user's and the pull user's (none is shown):

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
printf 'admin password: '; IFS= read -rs NEXUS_ADMIN_PASSWORD; echo; printf 'Push user password: '; IFS= read -rs NEXUS_PUSH_PASSWORD; echo; printf 'Pull user password: '; IFS= read -rs NEXUS_PULL_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$NEXUS_ADMIN_PASSWORD = Read-Host 'admin password' -AsSecureString; $NEXUS_PUSH_PASSWORD = Read-Host 'Push user password' -AsSecureString; $NEXUS_PULL_PASSWORD = Read-Host 'Pull user password' -AsSecureString
```

Then:

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
NEXUS_REGISTRY="192.168.10.50"
NEXUS_CA="$HOME/nexus-ca.pem"
NEXUS_REPO="apps"
NEXUS_PUSH_USER="apps-push"
NEXUS_PULL_USER="apps-pull"

U="https://${NEXUS_REGISTRY}/service/rest/v1"
V="nx-repository-view-docker-${NEXUS_REPO}"
nx() { curl -fsS --connect-timeout 20 --cacert "$NEXUS_CA" -K "$T/admin.cfg" "$@"; }
if [ -z "${NEXUS_ADMIN_PASSWORD:-}" ] || [ -z "${NEXUS_PUSH_PASSWORD:-}" ] || [ -z "${NEXUS_PULL_PASSWORD:-}" ]; then
  echo "STOPPED: type the three passwords first (the line above)"
elif T="$(umask 077 && mktemp -d)"; then
  printf 'user = "admin:%s"\n' "$(printf '%s' "$NEXUS_ADMIN_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')" > "$T/admin.cfg"
  if nx -o /dev/null "$U/repositories/docker/hosted/$NEXUS_REPO" 2>/dev/null; then
    echo "repository $NEXUS_REPO: exists"
  else
    jq -n --arg n "$NEXUS_REPO" '{name: $n, online: true,
        storage: {blobStoreName: "default", strictContentTypeValidation: true, writePolicy: "allow_once"},
        docker: {v1Enabled: false, forceBasicAuth: false, pathEnabled: true}}' \
      | nx -X POST -H 'Content-Type: application/json' --data-binary @- "$U/repositories/docker/hosted" \
      && echo "repository $NEXUS_REPO: created"
  fi
  for K in push pull; do
    if [ "$K" = push ]; then N="$NEXUS_PUSH_USER"; P="$NEXUS_PUSH_PASSWORD"; A="read browse add edit"; else N="$NEXUS_PULL_USER"; P="$NEXUS_PULL_PASSWORD"; A="read browse"; fi
    R="${NEXUS_REPO}-${K}"
    if nx -o /dev/null "$U/security/roles/$R" 2>/dev/null; then
      echo "role $R: exists"
    else
      jq -n --arg r "$R" --arg v "$V" --arg a "$A" '{id: $r, name: $r, description: ("Docker repository " + $v),
          privileges: [$a | split(" ")[] | ($v + "-" + .)], roles: []}' \
        | nx -X POST -H 'Content-Type: application/json' --data-binary @- "$U/security/roles" >/dev/null \
        && echo "role $R: created"
    fi
    if nx "$U/security/users?userId=$N" | jq -e --arg u "$N" 'any(.[]; .userId == $u)' >/dev/null; then
      echo "user $N: exists (password not changed)"
    else
      PW="$P" jq -n --arg u "$N" --arg r "$R" --arg k "$K" \
        '{userId: $u, firstName: $u, lastName: $k, emailAddress: ($u + "@example.com"), password: env.PW, status: "active", roles: [$r]}' \
        | nx -X POST -H 'Content-Type: application/json' --data-binary @- "$U/security/users" >/dev/null \
        && echo "user $N: created"
    fi
  done
  echo "repository: $(nx "$U/repositories/docker/hosted/$NEXUS_REPO" | jq -c '{pathEnabled: .docker.pathEnabled, writePolicy: .storage.writePolicy}')"
  echo "push role: $(nx "$U/security/roles/${NEXUS_REPO}-push" | jq -c .privileges)"
  echo "pull role: $(nx "$U/security/roles/${NEXUS_REPO}-pull" | jq -c .privileges)"
  rm -rf "$T"
fi
unset NEXUS_ADMIN_PASSWORD NEXUS_PUSH_PASSWORD NEXUS_PULL_PASSWORD
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$NEXUS_REGISTRY = "192.168.10.50"
$NEXUS_CA = "$HOME\nexus-ca.pem"
$NEXUS_REPO = "apps"
$NEXUS_PUSH_USER = "apps-push"
$NEXUS_PULL_USER = "apps-pull"

$U = "https://$NEXUS_REGISTRY/service/rest/v1"
$V = "nx-repository-view-docker-$NEXUS_REPO"
$T = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
$OutputEncoding = New-Object Text.UTF8Encoding $false
function nx { $input | curl.exe -fsS --connect-timeout 20 --ssl-no-revoke --cacert $NEXUS_CA -K "$T\admin.cfg" @args }
if (-not $NEXUS_ADMIN_PASSWORD -or -not $NEXUS_PUSH_PASSWORD -or -not $NEXUS_PULL_PASSWORD -or $NEXUS_PUSH_PASSWORD.Length -eq 0 -or $NEXUS_PULL_PASSWORD.Length -eq 0) { "STOPPED: type the three passwords first (the line above)" }
else {
  New-Item -ItemType Directory -Path $T | Out-Null
  try {
    $A = [Net.NetworkCredential]::new('', $NEXUS_ADMIN_PASSWORD).Password
    [IO.File]::WriteAllText("$T\admin.cfg", "user = `"admin:$($A.Replace('\', '\\').Replace('"', '\"'))`"`n")
    nx -o "$T\r.json" "$U/repositories/docker/hosted/$NEXUS_REPO" 2>$null
    if ($LASTEXITCODE -eq 0) { "repository ${NEXUS_REPO}: exists" } else {
      @{ name = $NEXUS_REPO; online = $true
         storage = @{ blobStoreName = 'default'; strictContentTypeValidation = $true; writePolicy = 'allow_once' }
         docker = @{ v1Enabled = $false; forceBasicAuth = $false; pathEnabled = $true } } | ConvertTo-Json -Compress |
        nx -X POST -H 'Content-Type: application/json' -d '@-' "$U/repositories/docker/hosted"
      if ($LASTEXITCODE -eq 0) { "repository ${NEXUS_REPO}: created" }
    }
    foreach ($K in 'push', 'pull') {
      if ($K -eq 'push') { $N = $NEXUS_PUSH_USER; $P = $NEXUS_PUSH_PASSWORD; $AC = 'read', 'browse', 'add', 'edit' }
      else { $N = $NEXUS_PULL_USER; $P = $NEXUS_PULL_PASSWORD; $AC = 'read', 'browse' }
      $R = "$NEXUS_REPO-$K"
      nx -o "$T\r.json" "$U/security/roles/$R" 2>$null
      if ($LASTEXITCODE -eq 0) { "role ${R}: exists" } else {
        @{ id = $R; name = $R; description = "Docker repository $V"
           privileges = @($AC | ForEach-Object { "$V-$_" }); roles = @() } | ConvertTo-Json -Compress |
          nx -X POST -H 'Content-Type: application/json' -d '@-' "$U/security/roles" | Out-Null
        if ($LASTEXITCODE -eq 0) { "role ${R}: created" }
      }
      if (@(nx "$U/security/users?userId=$N" | Out-String | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.userId -ceq $N }).Count) {
        "user ${N}: exists (password not changed)"
      } else {
        @{ userId = $N; firstName = $N; lastName = $K; emailAddress = "$N@example.com"
           password = [Net.NetworkCredential]::new('', $P).Password; status = 'active'; roles = @($R) } | ConvertTo-Json -Compress |
          nx -X POST -H 'Content-Type: application/json' -d '@-' "$U/security/users" | Out-Null
        if ($LASTEXITCODE -eq 0) { "user ${N}: created" }
      }
    }
    $J = nx "$U/repositories/docker/hosted/$NEXUS_REPO" | Out-String | ConvertFrom-Json
    "repository: pathEnabled $($J.docker.pathEnabled), writePolicy $($J.storage.writePolicy)"
    "push role: $((nx "$U/security/roles/$NEXUS_REPO-push" | Out-String | ConvertFrom-Json).privileges -join ',')"
    "pull role: $((nx "$U/security/roles/$NEXUS_REPO-pull" | Out-String | ConvertFrom-Json).privileges -join ',')"
  } finally { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $T; $A = $null }
}
Remove-Variable -ErrorAction SilentlyContinue NEXUS_ADMIN_PASSWORD, NEXUS_PUSH_PASSWORD, NEXUS_PULL_PASSWORD
```

</details>

**Expect:** `repository apps: created`, then `role apps-push: created`, `user apps-push: created`,
`role apps-pull: created`, `user apps-pull: created` (`exists` for what was there), then
`repository:` with `pathEnabled` `true` and `writePolicy` `ALLOW_ONCE`, `push role:` with the four
`nx-repository-view-docker-apps-…` privileges (`read`, `browse`, `add`, `edit`) and `pull role:` with
`read` and `browse`.

**If not:**
- `The requested URL returned error: 401`: the `admin` password is wrong (step 8).
- `The requested URL returned error: 400` at the repository: `NEXUS_REPO` holds characters other
  than letters, digits, `-`, `_` and `.`.
- `repository:` with `pathEnabled` `null`: the repository was made without path-based routing (for
  example in the web page). Delete it in **Settings** → **Repositories** and run this block again.

## 10. Trust Nexus and push an image

podman and docker check Nexus's certificate first; until they trust Nexus's CA, `login` and `push`
stop with `x509: certificate signed by unknown authority`. Each person who pushes does this once on
their machine, with `nexus-ca.pem` from step 7.

### Trust Nexus's CA

**Linux, podman** (no `sudo` needed):

```sh
NEXUS_REGISTRY="192.168.10.50"
NEXUS_CA="$HOME/nexus-ca.pem"

mkdir -p "$HOME/.config/containers/certs.d/$NEXUS_REGISTRY" \
  && cp "$NEXUS_CA" "$HOME/.config/containers/certs.d/$NEXUS_REGISTRY/ca.crt" && echo "podman trusts $NEXUS_REGISTRY"
```

**Linux, docker** (run it as a block of its own: it uses `sudo`; podman reads this folder too).
docker 29.5 or newer reads the CA at once; older docker needs a restart of the docker service:

```sh
NEXUS_REGISTRY="192.168.10.50"
sudo install -D -m 0644 "$HOME/nexus-ca.pem" "/etc/docker/certs.d/$NEXUS_REGISTRY/ca.crt" && echo "docker trusts $NEXUS_REGISTRY"
```

**macOS:** add the CA to your login keychain (macOS asks for your password), then as in
[IMAGE.md step 2](IMAGE.md#2-trust-harbors-ca): podman `podman machine set --import-native-ca`,
Colima its own `certs.d`, Docker Desktop a restart.

```sh
security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$HOME/nexus-ca.pem"
```

**Windows (PowerShell):** add the CA to your user's trusted root CAs (Windows asks you to confirm
with **Yes**), then podman `podman machine set --import-native-ca` (machine stopped), or quit and
start Docker Desktop:

```powershell
Import-Certificate -FilePath "$HOME\nexus-ca.pem" -CertStoreLocation Cert:\CurrentUser\Root
```

**Expect:** `podman trusts <NEXUS_REGISTRY>` or `docker trusts <NEXUS_REGISTRY>`; macOS: no output;
Windows: a line with the CA's thumbprint and `CN=Nexus CA`.

**If not:** `Permission denied` at the docker line: run it as a user who may use `sudo`. A missing
`nexus-ca.pem` (`No such file`): run step 7 first.

### Push an image

This copies a small public image, `busybox`, into your repository as
`<NEXUS_REGISTRY>/<NEXUS_REPO>/busybox:1.37.0`: it logs in as the push user, pushes, and logs out,
so the login is not left on this machine. Set `CONTAINER_ENGINE` to `podman` or `docker`. Type the
push user's password first (it is not shown):

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
printf 'Push user password: '; IFS= read -rs NEXUS_PUSH_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$NEXUS_PUSH_PASSWORD = Read-Host 'Push user password' -AsSecureString
```

Then:

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
CONTAINER_ENGINE="podman"
NEXUS_REGISTRY="192.168.10.50"
NEXUS_REPO="apps"
NEXUS_PUSH_USER="apps-push"

SRC="docker.io/library/busybox:1.37.0"
IMG="${NEXUS_REGISTRY}/${NEXUS_REPO}/busybox:1.37.0"
if [ -z "${NEXUS_PUSH_PASSWORD:-}" ]; then
  echo "STOPPED: type the push user's password first (the line above)"
elif "$CONTAINER_ENGINE" pull --platform linux/amd64 "$SRC" && "$CONTAINER_ENGINE" tag "$SRC" "$IMG" \
     && printf '%s\n' "$NEXUS_PUSH_PASSWORD" | "$CONTAINER_ENGINE" login -u "$NEXUS_PUSH_USER" --password-stdin "$NEXUS_REGISTRY"; then
  "$CONTAINER_ENGINE" push "$IMG" && echo "pushed: $IMG"
  "$CONTAINER_ENGINE" logout "$NEXUS_REGISTRY"
fi
unset NEXUS_PUSH_PASSWORD
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$CONTAINER_ENGINE = "podman"
$NEXUS_REGISTRY = "192.168.10.50"
$NEXUS_REPO = "apps"
$NEXUS_PUSH_USER = "apps-push"

$SRC = "docker.io/library/busybox:1.37.0"
$IMG = "$NEXUS_REGISTRY/$NEXUS_REPO/busybox:1.37.0"
$global:LASTEXITCODE = $null
if (-not $NEXUS_PUSH_PASSWORD -or $NEXUS_PUSH_PASSWORD.Length -eq 0) { "STOPPED: type the push user's password first (the line above)" }
else {
  & $CONTAINER_ENGINE pull --platform linux/amd64 $SRC
  if ($LASTEXITCODE -eq 0) { & $CONTAINER_ENGINE tag $SRC $IMG }
  if ($LASTEXITCODE -eq 0) { [Net.NetworkCredential]::new('', $NEXUS_PUSH_PASSWORD).Password | & $CONTAINER_ENGINE login -u $NEXUS_PUSH_USER --password-stdin $NEXUS_REGISTRY }
  if ($LASTEXITCODE -eq 0) {
    & $CONTAINER_ENGINE push $IMG
    if ($LASTEXITCODE -eq 0) { "pushed: $IMG" }
    & $CONTAINER_ENGINE logout $NEXUS_REGISTRY
  }
}
Remove-Variable -ErrorAction SilentlyContinue NEXUS_PUSH_PASSWORD
```

</details>

<!-- TODO-MEASURE: docker (daemon) login + push from a walkbox to the LB IP; WWW-Authenticate realm = https://<LB IP>/repository/apps/v2/token -->
<!-- TODO-MEASURE: docker push of the multi-arch busybox pulled with the platform option linux/amd64 has not been run -->

**Expect:** the pull, `Login Succeeded`, the push, `pushed: <NEXUS_REGISTRY>/apps/busybox:1.37.0`,
then `Removed login credentials for …` (docker: `Removing login credentials for …`).

**If not:**
- `x509: certificate signed by unknown authority`: trust the CA for your OS and engine (above).
- `unauthorized` (podman: `invalid username/password`): the push user's name or password is wrong
  (step 9).
- `denied` or `insufficient_scope`: the user may not push to this repository (step 9's role), or
  `NEXUS_REPO` is not the repository's name.
- `redeploy is not allowed` or `cannot be updated`: this tag was pushed before; tags in this
  repository cannot be replaced. Push with a new tag.

## 11. Let VKS clusters pull from Nexus

A VKS cluster's nodes pull images themselves, so they must trust Nexus's CA, and, because anonymous
access is off, each namespace needs a login for Nexus. Run this for each VKS cluster that pulls
from Nexus, including Nexus's own cluster if it runs images from Nexus.

### Make the nodes trust Nexus's CA

VKS adds a CA to every node from a Secret in the vSphere Namespace, named
`<cluster>-user-trusted-ca-secret`, that the cluster's `osConfiguration` setting points at. This
creates that Secret on the Supervisor with `nexus-ca.pem` (Broadcom requires the CA, base64-encoded
twice in the Secret, and not the server's own certificate:
[KB 448189](https://knowledge.broadcom.com/external/article/448189/ssltls-server-certificates-specified-in.html)).
It needs the **Edit** role on the vSphere Namespace.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
NEXUS_CA="$HOME/nexus-ca.pem"
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

S="${VKS_CLUSTER}-user-trusted-ca-secret"
if ! openssl x509 -in "$NEXUS_CA" -noout -subject; then
  echo "FAILED: $NEXUS_CA is not a certificate (step 7)"
elif kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get secret "$S" >/dev/null 2>&1; then
  echo "STOPPED: the Secret $S exists already; add a key to it (below)"
else
  B="$(base64 < "$NEXUS_CA" | tr -d '\n')" && [ -n "$B" ] \
    && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" create secret generic "$S" --from-literal=nexus-ca="$B"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$NEXUS_CA = "$HOME\nexus-ca.pem"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$S = "$VKS_CLUSTER-user-trusted-ca-secret"
$global:LASTEXITCODE = $null
$PEM = Get-Content -Raw -ErrorAction SilentlyContinue $NEXUS_CA
if (-not $PEM -or $PEM -notmatch 'BEGIN CERTIFICATE') { "FAILED: $NEXUS_CA is not a certificate (step 7)" }
else {
  kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get secret $S 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { "STOPPED: the Secret $S exists already; add a key to it (below)" }
  else {
    $B = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($PEM))
    kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE create secret generic $S "--from-literal=nexus-ca=$B"
  }
}
```

</details>

**Expect:** `subject=CN = Nexus CA` (newer OpenSSL: `subject=CN=Nexus CA`; Linux), then
`secret/my-vks-cluster-user-trusted-ca-secret created`.

**If not:**
- `forbidden`: you need the **Edit** role on the vSphere Namespace.
- `STOPPED: the Secret … exists already`: add Nexus's CA to it under a new key, as below, and use
  that key in the cluster's `secretRef`.

**Add a key to the Secret, or change the CA later.** VKS does not watch the Secret. To add Nexus's
CA to an existing Secret, or to change the CA later (a new Nexus, or step 5's CA renewed), keep the
Secret's name: add the CA under a new key (`nexus-ca-2`, then `nexus-ca-3`, …) and point the
cluster's `secretRef.key` at it with `kubectl edit cluster`; that changes the Cluster and starts the
node update (below).
<!-- TODO-MEASURE: on VKS 3.8, that a new key in the same Secret plus a secretRef.key change rolls the nodes with the new CA -->

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
NEXUS_CA="$HOME/nexus-ca.pem"
NEXUS_CA_KEY="nexus-ca-2"
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

S="${VKS_CLUSTER}-user-trusted-ca-secret"
if ! openssl x509 -in "$NEXUS_CA" -noout -subject; then
  echo "FAILED: $NEXUS_CA is not a certificate (step 7)"
elif B="$(base64 < "$NEXUS_CA" | tr -d '\n' | base64 | tr -d '\n')" && [ -n "$B" ]; then
  kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" patch secret "$S" --type merge -p "{\"data\":{\"$NEXUS_CA_KEY\":\"$B\"}}"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$NEXUS_CA = "$HOME\nexus-ca.pem"
$NEXUS_CA_KEY = "nexus-ca-2"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$S = "$VKS_CLUSTER-user-trusted-ca-secret"
$T = Join-Path $env:TEMP "nexus-ca-patch.json"
$PEM = Get-Content -Raw -ErrorAction SilentlyContinue $NEXUS_CA
if (-not $PEM -or $PEM -notmatch 'BEGIN CERTIFICATE') { "FAILED: $NEXUS_CA is not a certificate (step 7)" }
else {
  $B = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($PEM))))
  '{"data":{"' + $NEXUS_CA_KEY + '":"' + $B + '"}}' | Set-Content -Encoding ascii $T
  kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE patch secret $S --type merge --patch-file $T
  Remove-Item -Force -ErrorAction SilentlyContinue $T
}
```

</details>

**Expect:** `subject=CN = Nexus CA` (newer OpenSSL: `subject=CN=Nexus CA`; Linux), then
`secret/my-vks-cluster-user-trusted-ca-secret patched`.

**If not:** `not found`: the Secret does not exist; run the block before this one instead.
`forbidden`: you need the **Edit** role on the vSphere Namespace.

Then point the cluster at it.

**A new cluster:** add these lines under `variables:` in `cluster.yaml`
([CLUSTER.md step 9](CLUSTER.md#9-create-the-cluster-with-kubectl-and-a-yaml-file)), with your
cluster's name in `name:`, and create the cluster as that step says:

```yaml
      - name: osConfiguration
        value:
          trust:
            additionalTrustedCAs:
              - caCert:
                  secretRef:
                    name: my-vks-cluster-user-trusted-ca-secret
                    key: nexus-ca
```

**An existing cluster:** this adds the same setting. VKS replaces some nodes and updates others in
place, so pods move. On Nexus's own cluster, Nexus is unavailable until its node is back: do that
cluster last. A cluster made by [ARGOCD.md](ARGOCD.md): its chart has no setting for this. The
patch below works, but ArgoCD then shows the cluster OutOfSync, and a later SYNC removes the
setting and updates the nodes again; do not sync that Application afterwards.
<!-- TODO-MEASURE: on VKS 3.8, how the nodes roll after the edit (control plane replaced, workers in place?) and how long -->

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

S="${VKS_CLUSTER}-user-trusted-ca-secret"
P='[{"op":"add","path":"/spec/topology/variables/-","value":{"name":"osConfiguration","value":{"trust":{"additionalTrustedCAs":[{"caCert":{"secretRef":{"name":"'"$S"'","key":"nexus-ca"}}}]}}}}]'
if ! J="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get cluster "$VKS_CLUSTER" -o json)"; then
  echo "FAILED: cannot read the cluster (see the error above)"
elif printf '%s' "$J" | jq -e '[.spec.topology.variables[]? | select(.name == "osConfiguration")] | length > 0' >/dev/null; then
  echo "STOPPED: the cluster has an osConfiguration setting already; add the caCert to it by hand (kubectl edit cluster)"
else
  kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" patch cluster "$VKS_CLUSTER" --type json -p "$P" --dry-run=server >/dev/null \
    && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" patch cluster "$VKS_CLUSTER" --type json -p "$P"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$S = "$VKS_CLUSTER-user-trusted-ca-secret"
$T = Join-Path $env:TEMP "nexus-trust-patch.json"
'[{"op":"add","path":"/spec/topology/variables/-","value":{"name":"osConfiguration","value":{"trust":{"additionalTrustedCAs":[{"caCert":{"secretRef":{"name":"' + $S + '","key":"nexus-ca"}}}]}}}}]' | Set-Content -Encoding ascii $T
$global:LASTEXITCODE = $null
$J = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get cluster $VKS_CLUSTER -o json | Out-String
if ($LASTEXITCODE -ne 0) { "FAILED: cannot read the cluster (see the error above)" }
elseif (@((ConvertFrom-Json $J).spec.topology.variables | Where-Object { $_.name -eq 'osConfiguration' }).Count) {
  "STOPPED: the cluster has an osConfiguration setting already; add the caCert to it by hand (kubectl edit cluster)"
} else {
  kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE patch cluster $VKS_CLUSTER --type json --patch-file $T --dry-run=server | Out-Null
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE patch cluster $VKS_CLUSTER --type json --patch-file $T }
}
Remove-Item -Force -ErrorAction SilentlyContinue $T
```

</details>

**Expect:** `cluster.cluster.x-k8s.io/my-vks-cluster patched`. Then wait until the cluster is
`Ready` again ([CLUSTER.md step 6](CLUSTER.md#6-wait-for-the-cluster)) and every machine of the
cluster shows the new configuration.
<!-- TODO-MEASURE: the check that every machine has the new configuration; candidate: the Cluster's ControlPlaneMachinesUpToDate and WorkerMachinesUpToDate conditions (not run) -->

**If not:**
- `STOPPED: … osConfiguration setting already`: the cluster trusts another CA already; add a
  second `- caCert:` entry under its `additionalTrustedCAs` with `kubectl edit cluster`, with this
  Secret's name and Nexus's key (`nexus-ca`, or the key you added above).
- `admission webhook … denied`: the cluster class refuses the variable; send the error to the
  vSphere administrator.

### Check that a cluster can pull

This stores the pull user's login (step 9; it may only read) in the namespace `default` of the VKS
cluster as the Secret `nexus-pull`, keyed by exactly `NEXUS_REGISTRY` (as in the image names), and
runs a test pod with the image from step 10. Type the pull user's password first (it is not shown):

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
printf 'Pull user password: '; IFS= read -rs NEXUS_PULL_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$NEXUS_PULL_PASSWORD = Read-Host 'Pull user password' -AsSecureString
```

Then:

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
NEXUS_REGISTRY="192.168.10.50"
NEXUS_REPO="apps"
NEXUS_PULL_USER="apps-pull"

VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n default "$@"; }
if [ -z "${NEXUS_PULL_PASSWORD:-}" ]; then
  echo "STOPPED: type the pull user's password first (the line above)"
elif PW="$NEXUS_PULL_PASSWORD" jq -n --arg h "$NEXUS_REGISTRY" --arg u "$NEXUS_PULL_USER" \
    '{apiVersion: "v1", kind: "Secret", type: "kubernetes.io/dockerconfigjson", metadata: {name: "nexus-pull"},
      data: {".dockerconfigjson": ({auths: {($h): {username: $u, password: env.PW,
        auth: ("\($u):\(env.PW)" | @base64)}}} | tojson | @base64)}}' | kc apply -f -; then
  kc delete pod nexus-pull-check --ignore-not-found >/dev/null
  kc apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nexus-pull-check
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  imagePullSecrets:
    - name: nexus-pull
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: check
      image: ${NEXUS_REGISTRY}/${NEXUS_REPO}/busybox:1.37.0
      command: ["true"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF
  M=""; PH=""; n=0
  until [ -n "$M" ] || [ "$PH" = Succeeded ] || [ "$n" -ge 24 ]; do
    n=$((n + 1)); sleep 5
    PH="$(kc get pod nexus-pull-check -o jsonpath='{.status.phase}')"
    M="$(kc get events --field-selector involvedObject.name=nexus-pull-check,reason=Failed -o jsonpath='{.items[*].message}')"
  done
  kc delete pod nexus-pull-check --ignore-not-found >/dev/null
  case "$PH:$M" in
    Succeeded:*)       echo "OK: the cluster pulled ${NEXUS_REGISTRY}/${NEXUS_REPO}/busybox:1.37.0" ;;
    *"unknown authority"*) echo "CA: the nodes do not trust Nexus's CA yet" ;;
    *"certificate is valid for"*|*"cannot validate certificate"*|*"doesn't contain any IP SANs"*)
                       echo "NAME: Nexus's certificate is not for $NEXUS_REGISTRY (step 5)" ;;
    *"no such host"*)  echo "DNS: the nodes cannot resolve $NEXUS_REGISTRY" ;;
    *nauthorized*|*"access denied"*|*denied*) echo "LOGIN: Nexus refused the login in the Secret nexus-pull" ;;
    *"not found"*)     echo "IMAGE: no such image in Nexus (step 10)" ;;
    *:)                echo "NO ANSWER: the cluster reported nothing in 2 minutes" ;;
    *)                 echo "OTHER: $M" ;;
  esac
fi
unset NEXUS_PULL_PASSWORD
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$NEXUS_REGISTRY = "192.168.10.50"
$NEXUS_REPO = "apps"
$NEXUS_PULL_USER = "apps-pull"

$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
function kc { $input | kubectl --kubeconfig $VKS_KUBECONFIG -n default @args }
$global:LASTEXITCODE = $null
if (-not $NEXUS_PULL_PASSWORD -or $NEXUS_PULL_PASSWORD.Length -eq 0) { "STOPPED: type the pull user's password first (the line above)" }
else {
  $P = [Net.NetworkCredential]::new('', $NEXUS_PULL_PASSWORD).Password
  $AUTH = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${NEXUS_PULL_USER}:$P"))
  $CFG = @{ auths = @{ $NEXUS_REGISTRY = @{ username = $NEXUS_PULL_USER; password = $P; auth = $AUTH } } } | ConvertTo-Json -Depth 5 -Compress
  @{ apiVersion = 'v1'; kind = 'Secret'; type = 'kubernetes.io/dockerconfigjson'; metadata = @{ name = 'nexus-pull' }
     data = @{ '.dockerconfigjson' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CFG)) } } | ConvertTo-Json -Depth 5 | kc apply -f -
  $P = $null; $AUTH = $null; $CFG = $null
  if ($LASTEXITCODE -eq 0) {
    kc delete pod nexus-pull-check --ignore-not-found | Out-Null
    @"
apiVersion: v1
kind: Pod
metadata:
  name: nexus-pull-check
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  imagePullSecrets:
    - name: nexus-pull
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: check
      image: $NEXUS_REGISTRY/$NEXUS_REPO/busybox:1.37.0
      command: ["true"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
"@ | kc apply -f -
    $M = ''; $PH = ''; $n = 0
    while (-not $M -and $PH -ne 'Succeeded' -and $n -lt 24) {
      $n++; Start-Sleep -Seconds 5
      $PH = kc get pod nexus-pull-check -o 'jsonpath={.status.phase}'
      $M = "$(kc get events --field-selector involvedObject.name=nexus-pull-check,reason=Failed -o 'jsonpath={.items[*].message}')"
    }
    kc delete pod nexus-pull-check --ignore-not-found | Out-Null
    if ($PH -eq 'Succeeded') { "OK: the cluster pulled $NEXUS_REGISTRY/$NEXUS_REPO/busybox:1.37.0" }
    elseif ($M -like '*unknown authority*') { "CA: the nodes do not trust Nexus's CA yet" }
    elseif ($M -like '*certificate is valid for*' -or $M -like '*cannot validate certificate*' -or $M -like "*doesn't contain any IP SANs*") { "NAME: Nexus's certificate is not for $NEXUS_REGISTRY (step 5)" }
    elseif ($M -like '*no such host*') { "DNS: the nodes cannot resolve $NEXUS_REGISTRY" }
    elseif ($M -like '*nauthorized*' -or $M -like '*denied*') { "LOGIN: Nexus refused the login in the Secret nexus-pull" }
    elseif ($M -like '*not found*') { "IMAGE: no such image in Nexus (step 10)" }
    elseif (-not $M) { "NO ANSWER: the cluster reported nothing in 2 minutes" }
    else { "OTHER: $M" }
  }
}
Remove-Variable -ErrorAction SilentlyContinue NEXUS_PULL_PASSWORD
```

</details>

<!-- TODO-MEASURE: node pull on VKS 3.8 from a second cluster and from Nexus's own cluster (LB IP from inside the serving cluster); exact containerd messages for the case arms -->

**Expect:** `secret/nexus-pull created` (or `configured`), `pod/nexus-pull-check created`, then
`OK: the cluster pulled <NEXUS_REGISTRY>/apps/busybox:1.37.0`. An app in the namespace uses the
login with `imagePullSecrets: [{name: nexus-pull}]` in its pod spec; for another namespace, run
this block with `-n default` changed.

**If not:**
- `CA: …`: the nodes are still being updated (wait until every machine has the new configuration,
  above), or the cluster does not point at the Secret (above).
- `NAME: …`: `NEXUS_REGISTRY` is not the value step 5 was run with.
- `DNS: …`: the DNS server the nodes use does not have the record for `NEXUS_REGISTRY`.
- `LOGIN: …`: the pull user's name or password is wrong, or the Secret's key is not exactly
  `NEXUS_REGISTRY`.
- `OTHER: …` with `i/o timeout` or `connection refused`: the nodes cannot reach Nexus's address on
  port 443: a network or firewall matter.

## 12. Back up Nexus

Sonatype backs up the database with PostgreSQL's own tools and the files at about the same time
([Backup and restore](https://help.sonatype.com/en/backup-and-restore.html)). This copies, to a
new folder in your home: a dump of the database, Nexus's images and files (`blobs`), and Nexus's
node identity (`keystores`), then checks the copy. Make sure your machine has room for the `blobs`
folder; step 9's repository can hold up to 20 GB. Run it when nobody pushes and no cleanup or
compact task runs.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

D="$HOME/nexus-backup-$(date +%Y%m%d-%H%M%S)"
kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n nexus "$@"; }
N="?"; L="?"
if mkdir -p "$D" \
   && kc exec postgres-0 -- sh -c 'pg_dump -U "$POSTGRES_USER" -d nexus -Fc -f /tmp/nexus-db.dump' \
   && kc cp postgres-0:/tmp/nexus-db.dump "$D/nexus-db.dump" \
   && kc cp -c nexus nexus-0:/nexus-data/blobs "$D/blobs" \
   && kc cp -c nexus nexus-0:/nexus-data/keystores "$D/keystores" \
   && F="$(kc exec nexus-0 -c nexus -- find /nexus-data/blobs -type f)" \
   && N="$(printf '%s\n' "$F" | grep -c .)" && L="$(find "$D/blobs" -type f | grep -c .)" \
   && [ -s "$D/nexus-db.dump" ] && [ -e "$D/keystores/node" ] && [ "$L" -ge "$N" ]; then
  du -sh "$D"/* && echo "backed up to $D ($L of $N blob files)"
else
  echo "FAILED: the backup in $D is not complete ($L of $N blob files; see the error above)"
fi
kc exec postgres-0 -- rm -f /tmp/nexus-db.dump
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$D = "$HOME\nexus-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
function kc { kubectl --kubeconfig $VKS_KUBECONFIG -n nexus @args }
New-Item -ItemType Directory -Force -Path $D | Out-Null
Push-Location $D
$global:LASTEXITCODE = $null
kc exec postgres-0 -- sh -c 'pg_dump -U "$POSTGRES_USER" -d nexus -Fc -f /tmp/nexus-db.dump'
if ($LASTEXITCODE -eq 0) { kc cp postgres-0:/tmp/nexus-db.dump nexus-db.dump }
if ($LASTEXITCODE -eq 0) { kc cp -c nexus nexus-0:/nexus-data/blobs blobs }
if ($LASTEXITCODE -eq 0) { kc cp -c nexus nexus-0:/nexus-data/keystores keystores }
$N = '?'; $L = '?'
if ($LASTEXITCODE -eq 0) { $N = @(kc exec nexus-0 -c nexus -- find /nexus-data/blobs -type f).Count }
if ($LASTEXITCODE -eq 0) { $L = @(Get-ChildItem -Recurse -File blobs -ErrorAction SilentlyContinue).Count }
if ($LASTEXITCODE -eq 0 -and (Test-Path nexus-db.dump) -and (Get-Item nexus-db.dump).Length -gt 0 -and (Test-Path keystores\node) -and $L -ge $N) {
  Get-ChildItem | ForEach-Object { "{0} {1:N0} MB" -f $_.Name, ((Get-ChildItem -Recurse -File $_.FullName | Measure-Object Length -Sum).Sum / 1MB) }
  "backed up to $D ($L of $N blob files)"
} else { "FAILED: the backup in $D is not complete ($L of $N blob files; see the error above)" }
Pop-Location
kc exec postgres-0 -- rm -f /tmp/nexus-db.dump
```

</details>

<!-- TODO-MEASURE: backup on VKS (kubectl cp of blobs with tar in the alpine image, size/time), and a restore into a fresh namespace before the guide states one -->

**Expect:** a size line for `blobs`, `keystores` and `nexus-db.dump`, then `backed up to …` with
the same number twice in `(… of … blob files)`. Two `tar: Removing leading` lines from kubectl are
harmless.

**If not:** `FAILED: …`: run the block again; a folder from a failed run is not a backup (kubectl
copies nothing and still succeeds when a path in the pod is missing, so the block counts the
files). Keep
backups somewhere other than this machine as well. Restoring is not covered here yet.

## 13. Remove Nexus (optional)

This deletes the namespace `nexus` with Nexus, PostgreSQL, every image and user, and the CA, then
waits until the volumes are gone. VKS clusters that pull from Nexus can no longer do so; a new CA
made by step 5 is a different CA. cert-manager stays, and so do the Secrets and `osConfiguration`
settings of step 11 (removing them updates the nodes again). To delete Nexus's cluster too, run
this first and [CLUSTER.md step 8](CLUSTER.md#8-delete-the-cluster-optional) after it: a volume
still in use when the cluster goes is left behind in the vSphere Namespace and stops its removal.
Also left: `nexus-ca.pem`, the backups, the CA you trusted in step 10, and the Secret `nexus-pull`
in each cluster from step 11.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-nexus-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$VKS_KUBECONFIG" delete namespace nexus --wait --timeout=10m
V="(not checked)"
for i in $(seq 60); do
  if ! V="$(kubectl --kubeconfig "$VKS_KUBECONFIG" get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="nexus")]}{.metadata.name}{" "}{end}')"; then
    V="(the check failed, see the error above)"; break
  fi
  [ -z "$V" ] && break
  sleep 5
done
if [ -z "$V" ]; then echo "Nexus's volumes are gone"; else echo "STILL THERE: $V"; fi
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-nexus-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $VKS_KUBECONFIG delete namespace nexus --wait --timeout=10m
$V = "(not checked)"
foreach ($i in 1..60) {
  $global:LASTEXITCODE = $null
  $V = kubectl --kubeconfig $VKS_KUBECONFIG get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace==''nexus'')]}{.metadata.name}{'' ''}{end}'
  if ($LASTEXITCODE -ne 0) { $V = "(the check failed, see the error above)"; break }
  if (-not $V) { break }
  Start-Sleep 5
}
if (-not $V) { "Nexus's volumes are gone" } else { "STILL THERE: $V" }
```

**Expect:** `namespace "nexus" deleted`, then `Nexus's volumes are gone`. Run again, it prints
`namespaces "nexus" not found` first.

**If not:** `STILL THERE: …`: `kubectl --kubeconfig <file> describe pv <name>` shows why. Do not
delete the cluster until it is gone.

## Reach Nexus by a DNS name through Contour (optional)

(not tested with Nexus) With DNS names, the Contour add-on can take Nexus's HTTPS on a shared address instead of its own
load balancer: install Contour as in
[HEADLAMP.md step 10](HEADLAMP.md#10-reach-headlamp-by-a-dns-name-through-contour-optional), and
give Nexus an HTTPProxy for its name with `timeoutPolicy` `response: infinity` and
`idle: infinity` (Contour's default of 15 seconds breaks large pushes and pulls). The nodes of every
VKS cluster that pulls must then resolve that name.

Back to [README](../README.md).
