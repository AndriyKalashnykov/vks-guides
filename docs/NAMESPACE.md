# Create a vSphere Namespace

> [!NOTE]
> **Official Broadcom documentation (VCF 9.1) for this guide**
>
> - [Download and install vCenter Server root certificates](https://knowledge.broadcom.com/external/article/330833/download-and-install-vcenter-server-root.html) (Broadcom KB 330833)
> - [Using VM Classes with VKS Clusters](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service/configuring-vsphere-namespaces-for-hosting-tkg-service-clusters/using-vm-classes-with-tkg-service-clusters.html)
> - [Create and Configure a vSphere Namespace on the Supervisor](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/vsphere-supervisor-installation-and-configuration/configuring-and-managing-vsphere-namespaces/create-and-configure-a-vsphere-namespace.html)
> - [Configure vSphere Namespace Permissions for vCenter Single Sign-On Users and Groups](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service/configuring-vsphere-namespaces-for-hosting-tkg-service-clusters/configure-vsphere-namespace-persmissions-for-vcenter-sso-users-and-groups.html)
> - [Configure a vSphere Namespace for VKS Clusters](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service/configuring-vsphere-namespaces-for-hosting-tkg-service-clusters/configure-a-vsphere-namespace-for-hosting-tkg-service-clusters.html) (storage, VM classes, limits)
> - [Using Storage Classes for Persistent Volumes](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/deploying-workloads-on-tkg-service-clusters/storage-concepts-for-tkg-service-clusters/using-storage-classes-for-persistent-volumes.html) (the `-latebinding` class)
> - [Associate a VM Class with a Namespace Using the vSphere Client](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/provision-and-manage-virtual-machines/deploying-and-managing-virtual-machines-in-vsphere-iaas-control-plane/working-with-vm-classes-in-vsphere-with-tanzu/associate-a-vm-class-with-a-namespace-in-vsphere-with-tanzu.html)
> - [Verify vSphere Namespace Readiness for Hosting VKS Clusters](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service/configuring-vsphere-namespaces-for-hosting-tkg-service-clusters/verify-vsphere-namespace-readiness-for-hosting-tkg-service-clusters.html)
> - [Remove a vSphere Namespace from Supervisor](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/vsphere-supervisor-installation-and-configuration/configuring-and-managing-vsphere-namespaces/services-and-workloads-remove-a-vsphere-namespace.html)

You create the namespace in the vSphere Client, give users a role in it, and add a storage
policy and VM classes. Steps 2 to 7 are clicks. Step 1 has a block that needs
[unzip and openssl](PREREQS.md); steps 8 and 9 use a terminal and need [kubectl](KUBECTL.md),
[jq](PREREQS.md) and a [Supervisor login](LOGIN.md). The names are
those of the vSphere Client for VCF 9.1.1, on a Supervisor with vSphere Distributed Switch
networking. The screenshots show example names; yours differ.

You need a vCenter user who may create vSphere Namespaces (a vCenter administrator) and a
Supervisor that is running. If you only use a namespace someone else made, go to
[Check the namespace](#8-check-the-namespace).

## 1. Find the Supervisor's address and vCenter's CA

1. Open the vSphere Client (`https://<your vCenter>/ui`) and log in. From the menu (☰, top
   left) choose **Supervisor Management**, then the **Supervisors** tab.
2. Find your Supervisor's row. **Config Status** must show **Running**. The **Control Plane Node
   Address** column holds the Supervisor's address: that is `SUPERVISOR_ENDPOINT` in
   [LOGIN.md](LOGIN.md).

   ![The Supervisors tab of Supervisor Management: one row, Config Status Running, and the Control Plane Node Address column](img/namespace/01-supervisors.jpg)

3. Open `https://<your vCenter>/` (without `/ui`). In the grey box on the right, under **For
   Developers**, click **Download trusted root CA certificates**. The browser saves
   `download.zip`.

   ![vCenter's start page: the grey box on the right, with Download trusted root CA certificates as the last link under For Developers](img/namespace/02-vcenter-ca.jpg)

This prints the fingerprint of each CA in that file. These are the fingerprints LOGIN.md's
[Create Supervisor context with CA](LOGIN.md#create-supervisor-context-with-ca) asks you to
compare. They are worth trusting only if the browser showed no certificate warning for vCenter;
otherwise the download is no safer than LOGIN.md's own.

**Linux, macOS, WSL (bash or zsh):**

```sh
CA_ZIP="$HOME/Downloads/download.zip"

TMP="$(mktemp -d)"
if ! unzip -oqj "$CA_ZIP" 'certs/lin/*.0' -d "$TMP"; then
  echo "FAILED: no CA certificate in $CA_ZIP"
else
  for f in "$TMP"/*.0; do openssl x509 -in "$f" -noout -subject -fingerprint -sha256; done
fi
rm -rf "$TMP"
```

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$CA_ZIP = "$HOME\Downloads\download.zip"

$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null
Expand-Archive -Force -Path $CA_ZIP -DestinationPath $TMP -ErrorAction SilentlyContinue
$CERTS = Get-ChildItem -Path "$TMP\certs\win" -Filter '*.0.crt' -ErrorAction SilentlyContinue
if (-not $CERTS) {
  "FAILED: no CA certificate in $CA_ZIP"
} else {
  foreach ($C in $CERTS) {
    $X = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $C.FullName
    $H = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($X.RawData))
    "subject=$($X.Subject)"
    "sha256 Fingerprint=$($H.Replace('-', ':'))"
  }
}
Remove-Item -Recurse -Force $TMP
```

</details>

**Expect:** for each CA, a `subject=` line and a `sha256 Fingerprint=…` line
(`SHA256 Fingerprint=` on macOS).

**If not:**
- **Config Status** is not **Running**: the Supervisor is not ready, and no namespace can be
  created on it yet.
- `FAILED: no CA certificate …` or `cannot find …`: the file is not in `Downloads` under that
  name. Set `CA_ZIP` to where the browser saved it. Under `unzip: command not found`: install
  unzip ([PREREQS.md](PREREQS.md)).

## 2. Find the storage policies and the VM classes

A namespace needs one storage policy and at least one VM class (a node size).

1. From the menu (☰) choose **Policies and Profiles**, then **VM Storage Policies**. Note the
   name of one policy. Do not choose one with **Encryption** in its name unless vCenter has a
   key provider.

   ![Policies and Profiles with VM Storage Policies selected in the list on the left, and the policies by name](img/namespace/03-storage-policies.jpg)

2. From the menu (☰) choose **Supervisor Management**, then the **Services** tab. On the **VM
   Service** card click **MANAGE**, then **VM Classes**. Each card shows a class's name, CPUs
   and memory. Note the classes your VKS clusters' nodes will use. `best-effort-small` (2 CPUs,
   4 GB) is the smallest that runs a VKS cluster's control plane.

   ![The VM Service page, VM Classes: one card per class with its name, CPUs, memory, reservation, and how many namespaces and VMs use it](img/namespace/04-vm-classes.jpg)

**Expect:** one storage policy name and one or more VM class names.

**If not:** no **VM Service** card: the Supervisor has no VM Service, and no VKS cluster can be
built on it.

## 3. Create the namespace

1. From the menu (☰) choose **Supervisor Management**. On the **Namespaces** tab click **NEW
   NAMESPACE**.

   ![The Namespaces tab of Supervisor Management: the buttons NEW NAMESPACE and REMOVE above the list](img/namespace/05-namespaces-new.jpg)

2. **1 Location:** click your Supervisor, then **NEXT**.
3. **2 Configuration:**
   - **Name:** lower-case letters, digits and `-`, not used by another namespace. It cannot be
     changed later.
   - **Default Network:** leave the network that is already chosen.
   - **Additional Networks:** leave it at *-- Select Network --*.
   - **Description:** who made the namespace and why. Step 9 reads it before anything is
     deleted.

   Click **NEXT**.

   ![The Create Namespace window, step 2 Configuration, filled in: Name, Default Network, Additional Networks and Description](img/namespace/06-new-namespace.png)

4. **3 Add Zones:** leave the zone that is ticked, click **NEXT**.
5. **4 Review:** check the values, click **FINISH**.

**Expect:** the namespace's **Summary** page, with *Your namespace <name> has been successfully
created.* The **Status** card shows **Config Status** **Running** and **Kubernetes Status**
**Active**; the **Storage** card has the button **ADD STORAGE**; the **VM Service** card shows
*0 Associated VM Classes* and the link **ADD VM CLASS**.

![The Summary page of a new namespace: the panel that it was created, Config Status Running, Kubernetes Status Active, and the Storage and VM Service cards still empty](img/namespace/07-summary-new.jpg)

**If not:**
- **NEW NAMESPACE** is missing or grey: your user may not create namespaces, or no Supervisor
  is running (step 1).
- An error about the name: a namespace has that name, or it has a character that is not
  allowed.
- On a Supervisor with NSX, **2 Configuration** asks for more network values: take what your
  network administrator names.

## 4. Give users a role

You need nothing here for yourself as a vCenter administrator: the **Permissions** tab already
lists your user. Do this to let another SSO user work in the namespace.

1. Open the namespace's **Permissions** tab and click **ADD**.
2. Choose the **Domain** (`vsphere.local` for a user made in vCenter) and type the user's name
   in **User/Group**.
3. Choose the **Role**: **Namespaces View**, **Namespaces Edit** or **Namespaces Owner**. A user
   who creates VKS clusters needs **Namespaces Edit**.
4. Leave **Propagate to children** ticked and click **OK**.

   ![The Add Permission window: Domain, User/Group, Role, and the ticked box Propagate to children](img/namespace/08-add-permissions.png)

**Expect:** a new row on the **Permissions** tab with the user and the role.

**If not:** the user is not found: it is in another **Domain**.

## 5. Add a storage policy

1. On the **Summary** page, in the **Storage** card, click **ADD STORAGE**.
2. Tick the policy from step 2, one with room for the disks of every node of your VKS clusters,
   and click **OK**.

   ![The Select Storage Policies window: the columns Storage Policy, Total Capacity and Available Capacity, with one policy ticked](img/namespace/09-add-storage.jpg)

**Expect:** after a few seconds, the **Storage** card shows *Storage Policies 1* and the policy's name, and its link
reads **EDIT STORAGE**. The namespace now offers a storage class named after the policy, and a
second one ending in `-latebinding`.

## 6. Add the VM classes

1. In the **VM Service** card click **ADD VM CLASS**.
2. Tick the classes from step 2 and click **OK**. The table shows ten classes per page.

   ![The Add VM Class window: the table of VM classes with CPU and Memory, and two classes ticked](img/namespace/10-add-vm-class.jpg)

   The yellow line about *Instance Storage* is a note, not an error.

**Expect:** the **VM Service** card shows the number of classes you ticked (*2 Associated VM
Classes*, for example), and its link reads **MANAGE VM CLASSES**.

A VKS cluster needs no content library in the namespace: do not click **ADD CONTENT LIBRARY**.

## 7. Check the status

Leave **Capacity and Usage** at *No limit*, or click **EDIT LIMITS** and leave room for every
node of the VKS clusters you will create.

![The Summary page of the finished namespace: Config Status Running, Kubernetes Status Active, the Storage card with one policy, the VM Service card with 2 Associated VM Classes](img/namespace/11-summary-running.jpg)

**Expect:** **Config Status** **Running** and **Kubernetes Status** **Active**, the policy's
name in **Storage**, and your VM classes counted in **VM Service**.

**If not:** a status other than **Running** after some minutes: the card's message says why.

## 8. Check the namespace

Log in to the Supervisor first ([LOGIN.md](LOGIN.md)). If you were logged in before the
namespace existed, or before your user got its role, [log out](LOGIN.md#log-out) and log in
again.

This checks that the namespace exists and that your user may create VKS clusters in it.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_NAMESPACE="my-namespace"
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace "$VKS_NAMESPACE" \
  && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" auth can-i create clusters.cluster.x-k8s.io
```

**Windows (PowerShell):**

```powershell
$VKS_NAMESPACE = "my-namespace"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$global:LASTEXITCODE = $null
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace $VKS_NAMESPACE
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE auth can-i create clusters.cluster.x-k8s.io }
```

**Expect:** your namespace, `Active`, then `yes`.

**If not:**
- `NotFound`: check `VKS_NAMESPACE`.
- `Forbidden`, or `no`: check `VKS_NAMESPACE` (a user who is not a vCenter administrator gets
  `Forbidden` for a name that does not exist); if it is right, your SSO user has no
  **Namespaces Edit** role on the namespace (step 4).
- `Unauthorized`: run [Renew the Supervisor login](LOGIN.md#renew-the-supervisor-login).

This lists what the namespace offers a VKS cluster: VM classes, storage classes, Kubernetes
releases and cluster classes.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_NAMESPACE="my-namespace"
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

if ! kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace "$VKS_NAMESPACE" >/dev/null; then
  echo "FAILED: cannot read the namespace $VKS_NAMESPACE (see the error above)"
else
  echo "VM classes:"
  kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get virtualmachineclass --no-headers
  echo "Storage classes:"
  kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get storagepolicyquota \
    -o jsonpath='{range .items[*].status.total[*]}{.storageClassName}{"\n"}{end}' | sort -u
  if J="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get kr -o json)"; then
    echo "Kubernetes releases ready to use: $(printf '%s' "$J" | jq '[.items[] | select([.status.conditions[]? | select(.type == "Ready" or .type == "Compatible") | .status] | length == 2 and all(. == "True"))] | length')"
  else
    echo "Kubernetes releases ready to use: unknown (see the error above)"
  fi
  if J="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n vmware-system-vks-public get clusterclass -o name)"; then
    echo "Cluster classes: $(printf '%s\n' "$J" | grep -c .)"
  else
    echo "Cluster classes: unknown (see the error above)"
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_NAMESPACE = "my-namespace"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$global:LASTEXITCODE = $null
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace $VKS_NAMESPACE | Out-Null
if ($LASTEXITCODE -ne 0) {
  "FAILED: cannot read the namespace $VKS_NAMESPACE (see the error above)"
} else {
  "VM classes:"
  kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get virtualmachineclass --no-headers
  "Storage classes:"
  $J = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get storagepolicyquota -o json
  if ($LASTEXITCODE -eq 0) {
    ($J | Out-String | ConvertFrom-Json).items | ForEach-Object { $_.status.total } |
      ForEach-Object { $_.storageClassName } | Sort-Object -Unique
  }
  $J = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get kr -o json
  if ($LASTEXITCODE -eq 0) {
    $READY = ($J | Out-String | ConvertFrom-Json).items | Where-Object {
      @($_.status.conditions | Where-Object { ($_.type -eq 'Ready' -or $_.type -eq 'Compatible') -and $_.status -eq 'True' }).Count -eq 2
    }
    "Kubernetes releases ready to use: $(@($READY).Count)"
  } else {
    "Kubernetes releases ready to use: unknown (see the error above)"
  }
  $J = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n vmware-system-vks-public get clusterclass -o name
  if ($LASTEXITCODE -eq 0) {
    "Cluster classes: $(@($J | Where-Object { $_ }).Count)"
  } else {
    "Cluster classes: unknown (see the error above)"
  }
}
```

</details>

**Expect:** at least one line under `VM classes:` (a name with its CPUs and memory), at least
one name under `Storage classes:`, then `Kubernetes releases ready to use:` and
`Cluster classes:`, each with a number above 0.

**If not:**
- `FAILED: cannot read the namespace …`: as in the block above (`NotFound`, `Forbidden`,
  `Unauthorized`).
- An error with `Forbidden` above a line, or `unknown`: your user may not read that. Ask a
  vCenter administrator for the **Namespaces Edit** role (step 4); the number is not the cause.
- Nothing after `Kubernetes releases ready to use:`, under `jq: command not found`: install jq
  ([PREREQS.md](PREREQS.md)).
- `No resources found` under `VM classes:`: add a VM class (step 6).
- Nothing under `Storage classes:`, with no error: add a storage policy (step 5).
- `Kubernetes releases ready to use: 0`: on a Supervisor switched on minutes ago, wait ten
  minutes and run the block again. If it stays 0, the Supervisor's Kubernetes content library
  has not synchronized, or holds no release this Supervisor can use.
- `Cluster classes: 0`: the **Kubernetes Service** is not running on this Supervisor: your
  Supervisor → **Configure** → **Supervisor Services** → **Overview**.

## 9. Remove the namespace (optional)

**Remove only a namespace you created, and only when it holds nothing you want to keep.**
Broadcom asks you to delete its VKS clusters, VMs and vSphere Pods first; the window that asks
you to confirm says the same.

This lists the VKS clusters, VMs, volumes and pods left in it:

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_NAMESPACE="my-namespace"
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace "$VKS_NAMESPACE" \
  && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get clusters.cluster.x-k8s.io,virtualmachines,persistentvolumeclaims,pods
```

**Windows (PowerShell):**

```powershell
$VKS_NAMESPACE = "my-namespace"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$global:LASTEXITCODE = $null
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace $VKS_NAMESPACE
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get clusters.cluster.x-k8s.io,virtualmachines,persistentvolumeclaims,pods }
```

**Expect:** your namespace, `Active`, then `No resources found in <your namespace> namespace.`

**If not:**
- `NotFound`: check `VKS_NAMESPACE`. Do not remove a namespace you cannot see here.
- A VKS cluster, VM, volume or pod is listed: delete it first ([CLUSTER.md](CLUSTER.md) deletes a
  VKS cluster). A deleted cluster leaves its apps' volumes here; see
  [Delete the cluster](CLUSTER.md#8-delete-the-cluster-optional).

Then, in the vSphere Client:

1. **Supervisor Management** → **Namespaces**. Read the namespace's **Description**: it must be
   the text you typed in step 3. If it is not, stop.
2. Select the row with the round button at its left and click **REMOVE**.

   ![The Namespaces tab with one namespace selected by its round button, its Description readable, and the REMOVE button above the list](img/namespace/12-remove.jpg)

3. The window **Delete | <your namespace>** opens. Read the name in its title, then click the red
   **DELETE**.

   ![The window Delete | namespace, with its warning and the buttons CANCEL and DELETE](img/namespace/13-remove-confirm.jpg)

**Expect:** the row's **Config Status** shows **Removing**, then the row disappears.

**If not:** the row stays **Removing** for more than 15 minutes: something in the namespace does
not end. Do not create a namespace of the same name meanwhile.

Back to [README](../README.md).
