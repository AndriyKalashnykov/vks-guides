# Create a VKS cluster and deploy an app with ArgoCD

> [!NOTE]
> **Official Broadcom documentation (VCF 9.1), Argo CD and Kubernetes documentation for this guide**
>
> - [Installing and Configuring the Argo CD Service in VCF and vSphere](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/using-argo-cd-service.html)
> - [Add a Supervisor Service to vCenter](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-supervisor-services-with-vsphere-iaas-control-plane/supervisor-service-life-cycle-management-and-consumption/add-a-vsphere-services-to-vcenter-server.html)
> - [Install a Supervisor Service on a Supervisor](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-supervisor-services-with-vsphere-iaas-control-plane/supervisor-service-life-cycle-management-and-consumption/install-a-supervisor-service-on-supervisors.html)
> - [Deploy an Argo CD Instance on a Supervisor without VCF Automation](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/using-argo-cd-service/deploying-and-managing-an-argo-cd-instance-as-a-supervisor-service/deploy-and-argo-cd-instance-on-a-supervisor-without-vcf-automation.html)
> - [Add and Manage a vSphere Namespace in an Argo CD Instance by Using kubectl](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/using-argo-cd-service/deploying-and-managing-an-argo-cd-instance-as-a-supervisor-service/register-a-vsphere-namespace-as-a-target-cluster-in-argo-cd-supervisor-service/manage-a-vsphere-namespace-in-an-argo-cd-instance-on-supervisor-service-using-kubect.html)
> - [Register and Manage VKS Clusters in an Argo CD Instance by Using kubectl](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/using-argo-cd-service/deploying-and-managing-an-argo-cd-instance-as-a-supervisor-service/create-a-cluster-by-argocd.html)
> - [Uninstall a Supervisor Service from a Supervisor](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-supervisor-services-with-vsphere-iaas-control-plane/supervisor-service-life-cycle-management-and-consumption/uninstall-a-supervisor-service-version-from-a-supervisor.html)
> - [Argo CD Service API](https://developer.broadcom.com/xapis/argocd-service-api/latest/api-docs.html) (the `ArgoCD` and `ManagedEntity` fields)
> - [Supervisor Services: how to find and install them](https://github.com/vsphere-tmm/Supervisor-Services/blob/main/README.md) (the `legacy` manifest)
> - Argo CD 3.4: [Declarative Setup](https://argo-cd.readthedocs.io/en/release-3.4/operator-manual/declarative-setup/), [Automated Sync Policy](https://argo-cd.readthedocs.io/en/release-3.4/user-guide/auto_sync/)
> - Kubernetes: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

ArgoCD keeps what is in a Git folder applied to a destination. On a Supervisor it is the ArgoCD
Service: a vCenter administrator installs the service once, then a vSphere Namespace runs its own
ArgoCD (an *instance*). In this guide ArgoCD creates a VKS cluster from the chart in
[`argocd/guest-cluster`](../argocd/guest-cluster), then deploys the app in
[`argocd/test-web-apps`](../argocd/test-web-apps) into that cluster and keeps it in sync.

Needs [kubectl](KUBECTL.md), `jq` and `openssl` ([Prerequisites](PREREQS.md)), a
[Supervisor login](LOGIN.md) and a [vSphere Namespace](NAMESPACE.md) with the **Namespaces Edit**
role for your SSO user. Steps 2 and 10 need a vCenter administrator. Written for ArgoCD Service
1.2.0 on VCF 9.1.1 with VKS 3.7. The Supervisor must reach `github.com`.

`ARGOCD_NAMESPACE` is the vSphere Namespace that runs ArgoCD, `VKS_NAMESPACE` the one that holds
the VKS cluster. They can be the same namespace.

## 1. Check for an ArgoCD you have

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get argocdversion argocd-supported-versions -o name
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get argocd -o jsonpath='{range .items[*]}{"ArgoCD instance: "}{.metadata.name}{"  "}{.status.phase}{"  https://"}{.status.externalIP}{"\n"}{end}'
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret --ignore-not-found -o name
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get argocdversion argocd-supported-versions -o name
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get argocd -o jsonpath='{range .items[*]}{''ArgoCD instance: ''}{.metadata.name}{''  ''}{.status.phase}{''  https://''}{.status.externalIP}{''\n''}{end}'
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret --ignore-not-found -o name
```

**Expect:** three lines: `argocdversion…/argocd-supported-versions` (the service is installed),
`ArgoCD instance: <name>  Ready  https://<address>` (your namespace runs ArgoCD), and
`secret/argocd-initial-admin-secret`. With all three, go to
[step 4](#4-log-in-to-the-argocd-web-page).

**If not:**
- `the server doesn't have a resource type "argocdversion"`: the service is not installed. Do
  step 2 (a vCenter administrator).
- The first line only: the service is installed and your namespace has no instance. Go to
  [step 3](#3-create-the-argocd-instance).
- No `secret/…` line: someone changed the admin password and removed the first one. Ask them for
  the login.
- `Forbidden`: your SSO user has no **Namespaces Edit** role on the namespace.
  `Unauthorized`: run [Renew the Supervisor login](LOGIN.md#renew-the-supervisor-login).

## 2. Install the ArgoCD Service (vCenter administrator)

Needs the privileges **Manage Supervisor Services** and **Manage Supervisor Services on
Supervisors**.

1. Download the service manifest: [Broadcom support](https://support.broadcom.com/group/ecx/downloads)
   → **My Downloads** → search **vSphere Supervisor Services** → **ArgoCD Service** → **1.2.0**.
   Tick **I agree to the Terms and Conditions** if the page shows it. Take release 1.2.0 even
   when a newer one is listed. Broadcom offers two manifests, which differ only in where the
   Supervisor downloads ArgoCD from:
   - `supervisor-service-argocd-1.2.0-25642124.yml` (*Internet Connected VCF 9.1 and newer*):
     from the VCF Software Depot (`depot.kube-system.svc`). For a VCF 9.1 with a depot.
   - `supervisor-service-argocd-legacy-1.2.0-25642124.yml` (*VCF 9.0 or older and
     disconnected/airgapped VCF 9.1*): from `projects.packages.broadcom.com`. For a Supervisor
     without a depot.

This prints the file's checksum. Set `MANIFEST` to the file you downloaded.

**Linux, macOS, WSL (bash or zsh):**

```sh
MANIFEST="$HOME/Downloads/supervisor-service-argocd-legacy-1.2.0-25642124.yml"

if [ ! -f "$MANIFEST" ]; then
  echo "FAILED: not found: $MANIFEST"
else
  sha256sum "$MANIFEST" 2>/dev/null || shasum -a 256 "$MANIFEST"
fi
```

**Windows (PowerShell):**

```powershell
$MANIFEST = "$HOME\Downloads\supervisor-service-argocd-legacy-1.2.0-25642124.yml"

if (-not (Test-Path $MANIFEST)) {
  "FAILED: not found: $MANIFEST"
} else {
  "$((Get-FileHash -Algorithm SHA256 $MANIFEST).Hash.ToLower())  $MANIFEST"
}
```

**Expect:** the value the download page shows as **SHA2**:

| file | SHA-256 |
|---|---|
| `supervisor-service-argocd-1.2.0-25642124.yml` | `ac936c659338b91c2a5e5451cecc50c89e178c2e512c21b93b6714dbeb5263b9` |
| `supervisor-service-argocd-legacy-1.2.0-25642124.yml` | `e4f0d0bb85bc4c63d32ab52d0e39bb40b322dcecbbc4e5f29587f8ef765eb7f1` |

**If not:** `FAILED: not found`: set `MANIFEST` to where the browser saved the file. A different
checksum: delete the file and download it again; do not use it.

2. In the vSphere Client (`https://<your vCenter>/ui`): menu (☰) → **Supervisor Management** →
   **Services**. Skip to 4 if an **ArgoCD Service** card is there.
3. On the **Add New Service** card click **ADD**, then **UPLOAD**, and choose the manifest. The
   window shows **ArgoCD Service**, `argocd-service.vsphere.vmware.com`, `1.2.0-25642124`. Click
   **FINISH**.

   ![The New Service window after the upload: ArgoCD Service, argocd-service.vsphere.vmware.com, version 1.2.0-25642124, and FINISH](img/argocd/01-new-service-uploaded.png)

   The page shows *Service 'ArgoCD Service' is successfully registered* and an **ArgoCD
   Service** card.

   ![The Services tab with the green registered line and the ArgoCD Service card with its ACTIONS menu](img/argocd/02-registered.png)

4. On the **ArgoCD Service** card click **ACTIONS** → **Manage Service**. Leave **Install
   Version** at `1.2.0-25642124`, select your Supervisor, click **NEXT**. Wait for
   **Compatibility Check** and **Signature Verification** to **Pass**, click **NEXT**. Leave
   **YAML Service Config** empty, click **FINISH**.

   ![The Manage: ArgoCD Service window, Configure step: Install Version 1.2.0-25642124 and the Supervisor selected](img/argocd/03-install-configure.png)

   ![The Review step with the YAML Service Config box empty and FINISH](img/argocd/04-install-review.png)

5. **Supervisors** tab → your Supervisor's row → **View** in the **Services** column.

**Expect:** **ArgoCD Service**, **Configured**, `1.2.0-25642124`, after about a minute.

![The Supervisor's installed services with ArgoCD Service Configured, version 1.2.0-25642124](img/argocd/05-installed.png)

**If not:**
- No **ADD** button, or the upload is refused: your user lacks **Manage Supervisor Services**.
- An error naming the YAML: wrong file; do not edit the manifest.
- **Configuring** for more than 10 minutes: the Supervisor cannot download ArgoCD. With the
  `legacy` file, allow `projects.packages.broadcom.com`; with the other, check the VCF Software
  Depot, or uninstall (step 10) and install the `legacy` file.

## 3. Create the ArgoCD instance

This lists the ArgoCD versions the service offers:

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get argocdversion argocd-supported-versions -o jsonpath='{range .spec.versions[*]}{.version}{"  "}{.description}{"\n"}{end}'
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get argocdversion argocd-supported-versions -o jsonpath='{range .spec.versions[*]}{.version}{''  ''}{.description}{''\n''}{end}'
```

**Expect:** lines such as `3.4.4+vmware.1-vks.1  Recommended version.`

**If not:** `the server doesn't have a resource type "argocdversion"`: step 2 is not finished.

This creates the instance `argocd-1`. Set `ARGOCD_VERSION` to the first *Recommended* version.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
ARGOCD_VERSION="3.4.4+vmware.1-vks.1"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" apply -f - <<EOF
apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
kind: ArgoCD
metadata:
  name: argocd-1
spec:
  version: "${ARGOCD_VERSION}"
EOF
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$ARGOCD_VERSION = "3.4.4+vmware.1-vks.1"

@"
apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
kind: ArgoCD
metadata:
  name: argocd-1
spec:
  version: "${ARGOCD_VERSION}"
"@ | kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE apply -f -
```

**Expect:** `argocd.argocd-service.vsphere.vmware.com/argocd-1 created`. Then run step 1's block
every half minute until it shows `Ready` and an address: one to two minutes.

**If not:**
- `Forbidden`: your SSO user has no **Namespaces Edit** role on the namespace.
- Not `Ready` after 10 minutes: `kubectl --kubeconfig <supervisor.kubeconfig> -n <namespace>
  describe argocd argocd-1` shows why. No address: the Supervisor has no free load-balancer
  address.

## 4. Log in to the ArgoCD web page

ArgoCD made its own certificate, so the browser cannot check it. This prints the certificate's
fingerprint and the first `admin` password. Clear the terminal afterwards. Set `ARGOCD_INSTANCE` to
the instance's name from step 1.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
ARGOCD_INSTANCE="argocd-1"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get argocd "$ARGOCD_INSTANCE" -o jsonpath='https://{.status.externalIP}{"\n"}'
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get secret argocd-secret -o go-template='{{index .data "tls.crt" | base64decode}}' | openssl x509 -noout -fingerprint -sha256
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}{{"\n"}}'
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$ARGOCD_INSTANCE = "argocd-1"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get argocd $ARGOCD_INSTANCE -o jsonpath='https://{.status.externalIP}{''\n''}'
$CRT = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get secret argocd-secret -o jsonpath='{.data.tls\.crt}'
if ($LASTEXITCODE -eq 0 -and $CRT) {
  $X = [Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($CRT))
  $H = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($X.RawData))
  "sha256 Fingerprint=$($H.Replace('-', ':'))"
}
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}'
```

**Expect:** `https://<address>`, `sha256 Fingerprint=…` (`SHA256 Fingerprint=` on macOS), then the
password on a line of its own.

1. Open the address in your browser. It warns, for example *Your connection is not private*.
2. Open the certificate (Chrome: **Not secure** → **Certificate details**). Compare its
   **SHA-256** fingerprint of the **Certificate** (not the **Public Key**) with the printed one,
   ignoring colons and upper/lower case.
3. Only if they match: go on (Chrome: **Advanced** → **Proceed to …**) and log in as `admin` with
   the printed password.

**Expect:** the **Applications** page, *No applications available to you just yet*.

**If not:**
- Different fingerprints: something between you and ArgoCD replaces certificates (a company
  proxy), or the address is another server. Do not type the password.
- `secrets "argocd-initial-admin-secret" not found`: someone changed the admin password and
  removed the first one. Ask them for it.

This guide needs no `argocd` program; Broadcom's build is on the same download page.

## 5. Let ArgoCD manage your vSphere Namespace

**Whoever can log in to this ArgoCD as `admin` can then do everything Namespaces Edit allows in
`VKS_NAMESPACE`**: create and delete VKS clusters and VMs, and read every VKS cluster's
kubeconfig. Share the `admin` login only with people who may do that.

This gives ArgoCD's account `argocd-k8s-sa` the `edit` role in `VKS_NAMESPACE` and makes that
namespace an ArgoCD destination named after it, for the project `vks-clusters` of step 6.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argocd-k8s-sa-edit
  namespace: ${VKS_NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: argocd-k8s-sa
    namespace: ${ARGOCD_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
---
apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
kind: ManagedEntity
metadata:
  name: ns-${VKS_NAMESPACE}
  namespace: ${ARGOCD_NAMESPACE}
spec:
  argoCDProject: vks-clusters
  targetRef:
    apiGroup: ""
    kind: Namespace
    name: ${VKS_NAMESPACE}
EOF
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"

@"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argocd-k8s-sa-edit
  namespace: ${VKS_NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: argocd-k8s-sa
    namespace: ${ARGOCD_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
---
apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
kind: ManagedEntity
metadata:
  name: ns-${VKS_NAMESPACE}
  namespace: ${ARGOCD_NAMESPACE}
spec:
  argoCDProject: vks-clusters
  targetRef:
    apiGroup: ""
    kind: Namespace
    name: ${VKS_NAMESPACE}
"@ | kubectl --kubeconfig $SUPERVISOR_KUBECONFIG apply -f -
```

</details>

**Expect:** `rolebinding…/argocd-k8s-sa-edit created` and `managedentity…/ns-<namespace>
created` (`configured` or `unchanged` on a second run). This lists the destinations:

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get managedentity
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get managedentity
```

**Expect:** `ns-<namespace>` with `PHASE` `Ready`. In the ArgoCD page, **Settings** →
**Clusters** lists the namespace at `https://kubernetes.default.svc/?context=<namespace>`, status
**Unknown** until an Application uses it (picture in step 7).

**If not:** not `Ready` after a minute:
`kubectl --kubeconfig <supervisor.kubeconfig> -n <ArgoCD namespace> describe managedentity
ns-<namespace>` names the failed condition. `MissingRoleBinding`: the RoleBinding was not
created.

## 6. Create a VKS cluster with ArgoCD

This creates the project `vks-clusters`: Applications in it may read only this repository, write
only to `VKS_NAMESPACE`, and create only VKS clusters.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: vks-clusters
spec:
  description: VKS clusters from vks-guides into ${VKS_NAMESPACE}
  sourceRepos:
    - https://github.com/AndriyKalashnykov/vks-guides.git
  destinations:
    - name: ${VKS_NAMESPACE}
      namespace: ${VKS_NAMESPACE}
  namespaceResourceWhitelist:
    - group: cluster.x-k8s.io
      kind: Cluster
EOF
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"

@"
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: vks-clusters
spec:
  description: VKS clusters from vks-guides into ${VKS_NAMESPACE}
  sourceRepos:
    - https://github.com/AndriyKalashnykov/vks-guides.git
  destinations:
    - name: ${VKS_NAMESPACE}
      namespace: ${VKS_NAMESPACE}
  namespaceResourceWhitelist:
    - group: cluster.x-k8s.io
      kind: Cluster
"@ | kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE apply -f -
```

</details>

**Expect:** `appproject.argoproj.io/vks-clusters created`.

This lists what the cluster can use: Kubernetes versions (as the Supervisor stores them, without
the `-vkr.N` ending), cluster classes, VM classes and storage classes.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
VKS_NAMESPACE="my-namespace"

echo "Kubernetes versions:"
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get kr -o json \
  | jq -r '.items[] | select([.status.conditions[]? | select(.type == "Ready" or .type == "Compatible") | .status] | length == 2 and all(. == "True")) | .spec.version | sub("-vkr[.][0-9]+$"; "")'
echo "Cluster classes:"
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n vmware-system-vks-public get clusterclass -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
echo "VM classes:"
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get virtualmachineclass --no-headers
echo "Storage classes:"
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get storagepolicyquota \
  -o jsonpath='{range .items[*].status.total[*]}{.storageClassName}{"\n"}{end}' | sort -u
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$VKS_NAMESPACE = "my-namespace"

"Kubernetes versions:"
$J = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get kr -o json
if ($LASTEXITCODE -eq 0) {
  ($J | Out-String | ConvertFrom-Json).items | Where-Object {
    @($_.status.conditions | Where-Object { ($_.type -eq 'Ready' -or $_.type -eq 'Compatible') -and $_.status -eq 'True' }).Count -eq 2
  } | ForEach-Object { $_.spec.version -replace '-vkr\.[0-9]+$', '' }
}
"Cluster classes:"
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n vmware-system-vks-public get clusterclass -o jsonpath='{range .items[*]}{.metadata.name}{''\n''}{end}'
"VM classes:"
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get virtualmachineclass --no-headers
"Storage classes:"
$J = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get storagepolicyquota -o json
if ($LASTEXITCODE -eq 0) {
  ($J | Out-String | ConvertFrom-Json).items | ForEach-Object { $_.status.total } |
    ForEach-Object { $_.storageClassName } | Sort-Object -Unique
}
```

</details>

**Expect:** under each heading at least one line, for example `v1.36.2+vmware.2`,
`builtin-generic-v3.7.0`, `best-effort-small  2  4Gi …`, `wcp-vmfs`.

**If not:** an empty list or `Forbidden`: run [Check the namespace](NAMESPACE.md#8-check-the-namespace).

Choose a name no cluster in `VKS_NAMESPACE` has: lower-case letters, digits and `-`, starting with
a letter. ArgoCD would take over an existing cluster of that name, and deleting the Application
would delete it. This checks that nothing has the name now:

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get clusters.cluster.x-k8s.io "$VKS_CLUSTER"
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get applications.argoproj.io "$VKS_CLUSTER"
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get clusters.cluster.x-k8s.io $VKS_CLUSTER
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get applications.argoproj.io $VKS_CLUSTER
```

**Expect:** two `Error from server (NotFound): …` lines.

**If not:** a cluster or Application is listed: choose another `VKS_CLUSTER`.

This creates the Application. ArgoCD renders the chart with your values; it applies nothing until
you sync. Set the four values from the lists above.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
K8S_VERSION="v1.36.2+vmware.2"
CLUSTER_CLASS="builtin-generic-v3.7.0"
VM_CLASS="best-effort-small"
STORAGE_CLASS="wcp-vmfs"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${VKS_CLUSTER}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: vks-clusters
  source:
    repoURL: https://github.com/AndriyKalashnykov/vks-guides.git
    targetRevision: "173fba41691ffd7c0379443a6ca2fb014a3205d8"
    path: argocd/guest-cluster
    helm:
      valuesObject:
        name: "${VKS_CLUSTER}"
        kubernetesVersion: "${K8S_VERSION}"
        clusterClass: "${CLUSTER_CLASS}"
        vmClass: "${VM_CLASS}"
        storageClass: "${STORAGE_CLASS}"
  destination:
    name: ${VKS_NAMESPACE}
    namespace: ${VKS_NAMESPACE}
EOF
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$K8S_VERSION = "v1.36.2+vmware.2"
$CLUSTER_CLASS = "builtin-generic-v3.7.0"
$VM_CLASS = "best-effort-small"
$STORAGE_CLASS = "wcp-vmfs"

@"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${VKS_CLUSTER}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: vks-clusters
  source:
    repoURL: https://github.com/AndriyKalashnykov/vks-guides.git
    targetRevision: "173fba41691ffd7c0379443a6ca2fb014a3205d8"
    path: argocd/guest-cluster
    helm:
      valuesObject:
        name: "${VKS_CLUSTER}"
        kubernetesVersion: "${K8S_VERSION}"
        clusterClass: "${CLUSTER_CLASS}"
        vmClass: "${VM_CLASS}"
        storageClass: "${STORAGE_CLASS}"
  destination:
    name: ${VKS_NAMESPACE}
    namespace: ${VKS_NAMESPACE}
"@ | kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE apply -f -
```

</details>

**Expect:** `application.argoproj.io/<cluster> created`, after a `Warning:` about the finalizer
name (harmless: it is Argo CD's documented name). In the ArgoCD page, a tile named after the
cluster: **Missing** and **OutOfSync**.

![The Applications page: a cluster already synced, Healthy and Synced, and a new one, Missing and OutOfSync](img/argocd/06-applications.png)

**If not:**
- `application destination … is not permitted in project`: create the project above.
- The tile shows `ComparisonError` with `repository not accessible` or a timeout: the Supervisor
  cannot reach `github.com`. Behind a proxy, add it to the instance:
  `kubectl --kubeconfig <supervisor.kubeconfig> -n <ArgoCD namespace> patch argocd argocd-1
  --type merge -p '{"spec":{"repo":{"proxy":{"httpsProxy":"http://<proxy>:<port>"}}}}'`.
- `set kubernetesVersion` or another `set …`: that value is empty.

Now look at it, then sync:

1. Click the tile, then **DIFF**. The right half shows, in green, the `Cluster` with your
   values. The left half must be empty.

   ![The DIFF tab: the left half empty, the right half in green with the Cluster: builtin-generic-v3.7.0, best-effort-small, wcp-vmfs and v1.36.2+vmware.2](img/argocd/07-diff.png)

2. Close it, click **SYNC**, then **SYNCHRONIZE**.

   ![The SYNC panel: SYNCHRONIZE at the top, the pinned revision, and the Cluster ticked under SYNCHRONIZE RESOURCES](img/argocd/08-sync.png)

This shows the Application and the cluster. Run it again every few minutes; VKS builds the cluster
in 5 to 10 minutes.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get applications.argoproj.io "$VKS_CLUSTER" -o jsonpath='{.status.sync.status}  {.status.health.status}{"\n"}'
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get clusters.cluster.x-k8s.io "$VKS_CLUSTER"
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get applications.argoproj.io $VKS_CLUSTER -o jsonpath='{.status.sync.status}  {.status.health.status}{''\n''}'
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get clusters.cluster.x-k8s.io $VKS_CLUSTER
```

**Expect:** `Synced  Healthy`, and the cluster with `AVAILABLE` `True`.

**If not:**
- A left half that is not empty in the DIFF: a cluster of that name exists. Do not sync; delete
  the Application in the ArgoCD page with **Non-cascading** and choose another name.
- `OutOfSync` right after a sync: `K8S_VERSION` has a `-vkr.N` ending. Run the Application block
  again without it.
- `Progressing` after 30 minutes: `kubectl --kubeconfig <supervisor.kubeconfig> -n <namespace>
  describe clusters.cluster.x-k8s.io <cluster>` shows what it waits for (a VM class too small, a
  namespace without room).

ArgoCD changes this cluster only when you click **SYNC**; it does not recreate a cluster deleted
elsewhere. To use the cluster, run [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig).

## 7. Add the VKS cluster to ArgoCD

This lets ArgoCD deploy into the VKS cluster, for the project `test-web-apps` of step 8. It binds
`argocd-k8s-sa` to `argocd-manage-vks`, which may only read VKS clusters and their logins, and
asks the ArgoCD Service to register the cluster. Nothing is installed on the cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
ROLE="argocd-manage-vks"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argocd-k8s-sa-vks
  namespace: ${VKS_NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: argocd-k8s-sa
    namespace: ${ARGOCD_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${ROLE}
---
apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
kind: ManagedEntity
metadata:
  name: vks-${VKS_NAMESPACE}-${VKS_CLUSTER}
  namespace: ${ARGOCD_NAMESPACE}
spec:
  argoCDProject: test-web-apps
  targetRef:
    apiGroup: cluster.x-k8s.io
    kind: Cluster
    name: ${VKS_CLUSTER}
    namespace: ${VKS_NAMESPACE}
EOF
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$ROLE = "argocd-manage-vks"

@"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argocd-k8s-sa-vks
  namespace: ${VKS_NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: argocd-k8s-sa
    namespace: ${ARGOCD_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${ROLE}
---
apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
kind: ManagedEntity
metadata:
  name: vks-${VKS_NAMESPACE}-${VKS_CLUSTER}
  namespace: ${ARGOCD_NAMESPACE}
spec:
  argoCDProject: test-web-apps
  targetRef:
    apiGroup: cluster.x-k8s.io
    kind: Cluster
    name: ${VKS_CLUSTER}
    namespace: ${VKS_NAMESPACE}
"@ | kubectl --kubeconfig $SUPERVISOR_KUBECONFIG apply -f -
```

</details>

**Expect:** `rolebinding…/argocd-k8s-sa-vks created` and `managedentity…/vks-<namespace>-<cluster>
created`.

**If not:**
- `clusterroles.rbac.authorization.k8s.io "argocd-manage-vks" not found`: set `ROLE="edit"` and
  run the block again.
- `Forbidden` on the RoleBinding: your role may not grant `ROLE`. Ask a vCenter administrator to
  run the block.

ArgoCD stores the VKS cluster's administrator certificate for this destination. This shows the
destinations and the date that certificate ends:

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get managedentity
CERT="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get secret "cls-vks-${VKS_NAMESPACE}-${VKS_CLUSTER}" \
  -o go-template='{{.data.config | base64decode}}' | jq -r '.tlsClientConfig.certData // empty | @base64d')"
if [ -z "$CERT" ]; then
  echo "No certificate stored for ${VKS_CLUSTER}-${VKS_NAMESPACE} (see the error above)"
else
  printf '%s\n' "$CERT" | openssl x509 -noout -subject -enddate
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get managedentity
$C = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get secret "cls-vks-${VKS_NAMESPACE}-${VKS_CLUSTER}" `
  -o go-template='{{.data.config | base64decode}}'
$D = if ($LASTEXITCODE -eq 0 -and $C) { ($C | Out-String | ConvertFrom-Json).tlsClientConfig.certData }
if (-not $D) {
  "No certificate stored for ${VKS_CLUSTER}-${VKS_NAMESPACE} (see the error above)"
} else {
  $X = [Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($D))
  "subject=$($X.Subject)"
  "notAfter=$($X.NotAfter.ToUniversalTime().ToString('u'))"
}
```

</details>

**Expect:** `ns-<namespace>` and `vks-<namespace>-<cluster>`, both `Ready`; then `subject=…` and
`notAfter=…`, about a year from now. In the ArgoCD page, **Settings** → **Clusters** lists
`<cluster>-<namespace>` at `https://<address>:6443`.

![Settings, Clusters: the VKS cluster at https://192.168.101.134:6443 with status Unknown, and the namespace with status Successful](img/argocd/09-clusters.png)

**If not:**
- Not `Ready`: `kubectl --kubeconfig <supervisor.kubeconfig> -n <ArgoCD namespace> describe
  managedentity vks-<namespace>-<cluster>` names the failed condition. `MissingRoleBinding`: the
  RoleBinding above is missing.
- `secrets "cls-vks-…" not found`: `kubectl --kubeconfig <supervisor.kubeconfig> -n <ArgoCD
  namespace> get secret -l argocd.argoproj.io/secret-type=cluster` lists the stored destinations.

After `notAfter`, ArgoCD cannot reach the cluster. Before that date, run the registration block
again.

## 8. Deploy the test app

The app in [`argocd/test-web-apps`](../argocd/test-web-apps) is an unprivileged nginx: 5 replicas
on port 8080, behind a `LoadBalancer` Service on port 80, in the namespace `test-web-apps`. This
creates its project, which may create only that namespace, a Deployment and a Service on this VKS
cluster, and its Application. ArgoCD syncs it at once and puts back anything changed or deleted on
the cluster.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: test-web-apps
spec:
  description: test-web-apps from vks-guides into ${VKS_CLUSTER}
  sourceRepos:
    - https://github.com/AndriyKalashnykov/vks-guides.git
  destinations:
    - name: ${VKS_CLUSTER}-${VKS_NAMESPACE}
      namespace: test-web-apps
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceWhitelist:
    - group: apps
      kind: Deployment
    - group: ""
      kind: Service
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-web-apps
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: test-web-apps
  source:
    repoURL: https://github.com/AndriyKalashnykov/vks-guides.git
    targetRevision: "173fba41691ffd7c0379443a6ca2fb014a3205d8"
    path: argocd/test-web-apps
  destination:
    name: ${VKS_CLUSTER}-${VKS_NAMESPACE}
    namespace: test-web-apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"

@"
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: test-web-apps
spec:
  description: test-web-apps from vks-guides into ${VKS_CLUSTER}
  sourceRepos:
    - https://github.com/AndriyKalashnykov/vks-guides.git
  destinations:
    - name: ${VKS_CLUSTER}-${VKS_NAMESPACE}
      namespace: test-web-apps
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceWhitelist:
    - group: apps
      kind: Deployment
    - group: ""
      kind: Service
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-web-apps
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: test-web-apps
  source:
    repoURL: https://github.com/AndriyKalashnykov/vks-guides.git
    targetRevision: "173fba41691ffd7c0379443a6ca2fb014a3205d8"
    path: argocd/test-web-apps
  destination:
    name: ${VKS_CLUSTER}-${VKS_NAMESPACE}
    namespace: test-web-apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
"@ | kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE apply -f -
```

</details>

**Expect:** `appproject.argoproj.io/test-web-apps created` and
`application.argoproj.io/test-web-apps created`, after the same finalizer `Warning:` as in step 6.

This checks the app. It needs the VKS cluster's kubeconfig from
[Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig). Run it again until
the Deployment shows `5/5`: a minute or two.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get applications.argoproj.io test-web-apps -o jsonpath='{.status.sync.status}  {.status.health.status}{"\n"}'
kubectl --kubeconfig "$VKS_KUBECONFIG" -n test-web-apps get deployment test-web-apps
IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n test-web-apps get service test-web-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')"
if [ -z "$IP" ]; then
  echo "No address yet: run this block again in a minute"
else
  curl -s -o /dev/null --connect-timeout 20 -w "http://${IP}/ answers %{http_code}\n" "http://${IP}/"
fi
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE get applications.argoproj.io test-web-apps -o jsonpath='{.status.sync.status}  {.status.health.status}{''\n''}'
kubectl --kubeconfig $VKS_KUBECONFIG -n test-web-apps get deployment test-web-apps
$IP = kubectl --kubeconfig $VKS_KUBECONFIG -n test-web-apps get service test-web-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}'
if (-not $IP) {
  "No address yet: run this block again in a minute"
} else {
  curl.exe -s -o NUL --connect-timeout 20 -w "http://${IP}/ answers %{http_code}\n" "http://${IP}/"
}
```

**Expect:** `Synced  Healthy`, then `test-web-apps   5/5   5   5`, then
`http://<address>/ answers 200`. In the ArgoCD page, `test-web-apps` is **Healthy** and
**Synced**, with its namespace, Service and Deployment.

![The test-web-apps Application: Healthy, Synced, auto sync enabled, and its ns, svc and deploy](img/argocd/10-test-web-apps.png)

**If not:**
- `application destination … is not permitted in project`: step 7 is not done, or its destination
  has another name (**Settings** → **Clusters** shows it).
- `OutOfSync` with `ComparisonError`: see the proxy line in step 6.
- `0/5` with `ErrImagePull` or `ImagePullBackOff` (`kubectl --kubeconfig <cluster.kubeconfig> -n
  test-web-apps get pods`): the cluster cannot pull from `docker.io`. Copy the image into a
  registry it can reach and change `image:` in a copy of the folder in your own repository.
- `No address yet` for more than 5 minutes: the Supervisor has no free load-balancer address.
- `answers 000`: this machine cannot reach the address.

## 9. Clean up (optional)

Do these in order: an Application can be deleted only while ArgoCD still reaches its
destination, and deleting an Application deletes what it created.

This deletes the test app and its namespace on the VKS cluster:

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete applications.argoproj.io test-web-apps --timeout=5m \
  && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete appproject test-web-apps
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete applications.argoproj.io test-web-apps --timeout=5m
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete appproject test-web-apps }
```

**Expect:** `application.argoproj.io "test-web-apps" deleted`, then
`appproject.argoproj.io "test-web-apps" deleted`. Newer kubectl adds `from <namespace>
namespace` to each `deleted` line.

**If not:** `timed out waiting`: ArgoCD cannot reach the VKS cluster (step 7's certificate ended,
or the cluster is gone). In the ArgoCD page, delete the Application with **Non-cascading**.

This removes the VKS cluster from ArgoCD's destinations, then deletes the cluster:

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete managedentity "vks-${VKS_NAMESPACE}-${VKS_CLUSTER}" --ignore-not-found
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" delete rolebinding argocd-k8s-sa-vks --ignore-not-found
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete applications.argoproj.io "$VKS_CLUSTER" --wait=false
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete managedentity "vks-${VKS_NAMESPACE}-${VKS_CLUSTER}" --ignore-not-found
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE delete rolebinding argocd-k8s-sa-vks --ignore-not-found
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete applications.argoproj.io $VKS_CLUSTER --wait=false
```

**Expect:** three `… deleted` lines. Then run the name check of step 6 every few minutes until it
prints two `NotFound` lines.

This deletes the project, the namespace destination and the instance. Skip it if the instance was
there before you started.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_NAMESPACE="my-namespace"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete appproject vks-clusters --ignore-not-found
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete managedentity "ns-${VKS_NAMESPACE}" --ignore-not-found
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" delete rolebinding argocd-k8s-sa-edit --ignore-not-found
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete argocd argocd-1 --ignore-not-found
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" delete secret argocd-initial-admin-secret argocd-redis --ignore-not-found
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$ARGOCD_NAMESPACE = "my-namespace"
$VKS_NAMESPACE = "my-namespace"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete appproject vks-clusters --ignore-not-found
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete managedentity "ns-${VKS_NAMESPACE}" --ignore-not-found
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE delete rolebinding argocd-k8s-sa-edit --ignore-not-found
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete argocd argocd-1 --ignore-not-found
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $ARGOCD_NAMESPACE delete secret argocd-initial-admin-secret argocd-redis --ignore-not-found
```

**Expect:** up to six `… deleted` lines.

## 10. Remove the ArgoCD Service (vCenter administrator)

Only if step 2 installed it. Uninstalling removes every ArgoCD instance on the Supervisor. This
lists them:

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get argocd -A
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get argocd -A
```

**Expect:** `No resources found`.

**If not:** a list: do not go on until their owners have deleted them. `Forbidden`: a vCenter
administrator must run this.

1. vSphere Client: **Supervisor Management** → **Supervisors** → **View** in your Supervisor's
   **Services** column. Select **ArgoCD Service**, click **UNINSTALL**, then **UNINSTALL** again.
2. Only if no other Supervisor uses it: **Services** tab → **ArgoCD Service** card → **ACTIONS**
   → **Delete**. Click **CONFIRM** under *1. Deactivate service*, **CONFIRM** under *3. Delete
   all versions of the Service*, then **DELETE**.

**Expect:** the row disappears from the Supervisor's services; after 2, *'ArgoCD Service'
successfully deleted.*

Back to [README](../README.md).
