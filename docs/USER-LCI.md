# Use your vSphere Namespace in the web page

Your vCenter administrator gave your own vCenter SSO user a role on a
[vSphere Namespace](GLOSSARY.md) (the place on the Supervisor that holds your team's VMs and
Kubernetes clusters). You open the Local Consumption Interface, a web page on the Supervisor, with
the link they send you, sign in, and see what the namespace holds: VMs, VKS clusters (Kubernetes
clusters), containers, VM images, network services and volumes. With **Can edit** you also create
and delete VKS clusters, VMs, volumes and containers there, and download a cluster's
[kubeconfig](GLOSSARY.md) (the file kubectl uses to reach a cluster); with **Can view** you only
look. Nothing to install besides, on Linux, `certutil` for step 2, and kubectl to use a kubeconfig
you download there. The screenshots are from VCF 9.1.1; your names differ.

Not an SSO user? [Who are you? Start here](LOGIN.md#who-are-you-start-here) sends you to the guide
for your way in.

The steps:

1. [What to ask your administrator for](#1-what-to-ask-your-administrator-for)
2. [Trust the vCenter CA in your browser (once)](#2-trust-the-vcenter-ca-in-your-browser-once)
3. [Open the link and sign in](#3-open-the-link-and-sign-in)
4. [What you see](#4-what-you-see)
5. [Create, use and delete a VKS cluster (Can edit)](#5-create-use-and-delete-a-vks-cluster-can-edit)
6. [Create and delete VMs, volumes and containers (Can edit)](#6-create-and-delete-vms-volumes-and-containers-can-edit)
7. [Log out](#7-log-out)

## Prerequisites

- a browser; on Linux also `certutil`
  ([USER-IDP-LOGIN.md step 2](USER-IDP-LOGIN.md#2-trust-the-cas-once-on-the-machine-whose-browser-you-sign-in-with)
  says how to install it);
- with **Can edit**, to use a kubeconfig you download: [kubectl](KUBECTL.md);
- the link, your SSO user name and the vCenter CA file from [step 1](#1-what-to-ask-your-administrator-for);
- a role on the vSphere Namespace given by the vCenter administrator
  ([ADMIN-GRANT-ACCESS.md](ADMIN-GRANT-ACCESS.md#1b-let-the-person-use-the-web-page-vcenter-administrator-optional)).

The connections this guide needs, for a firewall (all TCP, besides DNS):

| from | to | port | for |
|---|---|---|---|
| your machine (laptop or jump box) | the Supervisor's address | 443 | the web page ([step 3](#3-open-the-link-and-sign-in)) |
| your machine (laptop or jump box) | the VKS cluster's API address (in the kubeconfig) | 6443 | kubectl with a downloaded kubeconfig ([step 5](#5-create-use-and-delete-a-vks-cluster-can-edit)) |
| the Supervisor | the registry of a container's image (for example `docker.io`, [Registry hosts](PREREQS.md#registry-hosts-for-a-firewall)) | 443 | pulling a container's image ([step 6](#6-create-and-delete-vms-volumes-and-containers-can-edit)) |

## 1. What to ask your administrator for

Ask your vCenter administrator for:

- the link to your vSphere Namespace's page, in the form
  `https://<Supervisor address>/appplatform0/#/namespaces/<vSphere Namespace>`;
- your SSO user name, for example `Alice@vsphere.local`;
- the vCenter CA file (not needed if your browser already trusts it: with it your browser checks
  that it talks to your real Supervisor); save it as `~/.kube/vcenter-ca.pem`;
- which role you have: **Can view**, **Can edit** or **Owner**.

Use the link with your namespace's name in it. The page's address without it,
`https://<Supervisor address>/appplatform0/`, first lists every vSphere Namespace on the Supervisor,
which only an administrator may do: you sign in and get a red bar with no text.

## 2. Trust the vCenter CA in your browser (once)

The CA (certificate authority) file lets your browser check that the page is your real
Supervisor. Run only the vCenter CA lines for your OS in
[USER-IDP-LOGIN.md step 2](USER-IDP-LOGIN.md#2-trust-the-cas-once-on-the-machine-whose-browser-you-sign-in-with),
with the vCenter CA file, `~/.kube/vcenter-ca.pem`: on Linux the block after *For part A, also the
vCenter CA*; on macOS, WSL and Windows the block for your OS, with `CA_FILE` set to that file. Skip
its identity provider's CA. Done once, it serves that guide too.

**Expect:** after you restart the browser, the page in step 3 opens with no certificate warning.

**If not:** a warning that the connection is not private: the CA is not trusted yet, or it is not the
CA of this Supervisor. Ask the vCenter administrator for the right file, and do not click through the
warning.

## 3. Open the link and sign in

1. Open the link from step 1. The page **VMware Local Consumption Interface** asks for a user name and
   a password.

   ![The sign-in page of the VMware Local Consumption Interface: the fields Enter username and Enter password, and the LOGIN button](img/user-lci/01-login.jpg)

2. Type your SSO user name and your vCenter password, and click **LOGIN**.

**Expect:** your namespace's page, with your user name at the top right
([step 4](#4-what-you-see)).

**If not:**

- A red bar with no text: the address lacks your namespace's name (it must end in
  `#/namespaces/<vSphere Namespace>`). Open the link from step 1; if the bar stays, ask the vCenter
  administrator to check the link and your role.
- **Unable to login: Internal server error**: type the user name again by hand; a password manager
  may have put a space in front of it.
- Sign-in refused: check the user name and password before you try again; failed sign-ins lock your
  SSO account for a while.

## 4. What you see

![The namespace page of the Local Consumption Interface: cards for Virtual Machine, Kubernetes, Container, Virtual Machine Image, Network and Volume, with GO TO SERVICE and create links, and the signed-in user at the top right](img/user-lci/02-overview.jpg)

One card per service in your vSphere Namespace: **Virtual Machine**, **Kubernetes** (VKS clusters),
**Container**, **Virtual Machine Image**, **Network** and **Volume**. **GO TO SERVICE** opens its
list. What your role lets you do here:

| on this page | Can view | Can edit or Owner |
|---|---|---|
| see the cards and their lists | yes | yes |
| create and delete VKS clusters ([step 5](#5-create-use-and-delete-a-vks-cluster-can-edit)) | no | yes |
| download a VKS cluster's administrator kubeconfig | no | yes |
| create and delete VMs, volumes and containers ([step 6](#6-create-and-delete-vms-volumes-and-containers-can-edit)) | no | yes |

On VCF 9.1.1, **Owner** gives the same rights here as **Can edit**.

The browser holds one sign-in for this page: signing in as another user in another tab replaces it
in every tab.

With **Can view** you see the cards, and the create links are there too, but a create ends in a red
bar on the page's last button (**FINISH**, **DEPLOY VM** or **CREATE CONTAINER INSTANCE**):

![The review page of New Kubernetes Cluster with a red bar: clusters.cluster.x-k8s.io is forbidden, the user cannot create resource clusters in the namespace](img/user-lci/03-view-create-forbidden.jpg)

`clusters.cluster.x-k8s.io is forbidden: User "sso:…" cannot create resource "clusters" …`: you have
**Can view**. Ask the vCenter administrator for **Can edit** if you need to create.

The page shows what is in the vSphere Namespace, not the workloads inside a VKS cluster. To work
inside a cluster you were given access to, log in with [USER-LOGIN.md](USER-LOGIN.md).

## 5. Create, use and delete a VKS cluster (Can edit)

**Can edit** makes you an administrator of every VKS cluster in the vSphere Namespace.

- **Create:** on the **Kubernetes** card click **CREATE CLUSTER**, keep **Default Configuration**,
  click **NEXT**, then **FINISH**. The cluster's list opens; the cluster turns **Available** after a
  few minutes. For your own name, VM class and node counts choose **Custom Configuration**:
  [CLUSTER.md steps 4 and 5](CLUSTER.md#4-fill-in-the-create-page) show that page.
- **Use:** in the cluster's list (**GO TO SERVICE** on the **Kubernetes** card), the **⋮** menu of a
  cluster has **Download Kubeconfig File**. The
  file is the cluster's administrator kubeconfig: keep it to yourself and never send it
  ([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over)); to give someone access, see
  [ADMIN-GRANT-ACCESS.md](ADMIN-GRANT-ACCESS.md). It works for up to a year, also after your role
  is taken away; when it answers `Unauthorized`, download it again while you still have the role
  ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#download-the-vks-clusters-kubeconfig-from-the-vsphere-client)
  says what to do if the new file does too).
  The browser saves it as `<cluster name>-kubeconfig.yaml`, the same file as the vSphere Client's:
  run the block after the download in
  [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#download-the-vks-clusters-kubeconfig-from-the-vsphere-client), which
  moves it to `~/.kube/<cluster name>.kubeconfig`, readable only by you, then
  [Use the VKS cluster](SUPERVISOR-LOGIN.md#use-the-vks-cluster).
- **Delete:** the same **⋮** menu has **Delete**; confirm with **DELETE**. The page says
  **Cluster … is being deleted** and the cluster leaves the list when its VMs are gone.

**Expect:** a new cluster **Available** in the list; a deleted one gone from it.

**If not:** a cluster that does not turn **Available**: [CLUSTER.md step 6](CLUSTER.md#6-wait-for-the-cluster)
says what to look at; send its output to the vCenter administrator.

## 6. Create and delete VMs, volumes and containers (Can edit)

Each card's create link opens a page with the choices filled in; the **Kubernetes Resource YAML**
pane on the right shows what it will create.

- **VM:** on the **Virtual Machine** card click **CREATE VM**, keep **Deploy from OVF**, click
  **NEXT**, choose a **VM Image** and a **VM Class**, click **REVIEW AND CONFIRM**, then **DEPLOY VM**.
  The VM turns **Ready** and **Powered On** after a few minutes; the first VM from an image takes
  longer while the image is copied.
- **Volume:** on the **Volume** card click **NEW VOLUME**, set the **Capacity**, click **NEXT**,
  then **FINISH**. The volume turns **Bound**.
- **Container:** on the **Container** card click **CREATE NEW INSTANCE**, type the **Primary
  Container Image** (for example `docker.io/library/nginx:1.27-alpine`), click **NEXT** twice, then
  **CREATE CONTAINER INSTANCE**. It turns **Ready** when its pod runs.
- **Delete:** in each list, the **⋮** menu of a row has **Delete**; confirm with **DELETE**. For a
  VM, tick the box to also delete its persistent volumes if you want them gone.

**Expect:** the new VM, volume or container in its list; a deleted one gone from it.

**If not:**

- **Unable to proceed with Create VM because the namespace is missing the following resources: VM
  Images**: the vSphere Namespace has no content library with VM images. Ask the vCenter
  administrator to add one.
- `… is forbidden: User "sso:…" cannot create resource …`: you have **Can view**.
- A container that stays **Not Ready**: its image cannot be pulled; use an image from a registry the
  Supervisor reaches, such as your organization's own.

## 7. Log out

Click your user name at the top right, then **Log out**. If a create page is open, **Discard
Changes** asks first: click **DISCARD**.

**Expect:** the sign-in page. It no longer holds your namespace's name: to sign in again, open the
link from step 1.

**If not:** a red bar with no text after you signed in on that page: open the link from step 1 again.

## References

**Official Broadcom documentation (VCF 9.1) for this guide**

- [Access the IaaS Services Console or Local Consumption Interface](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/access-the-iaas-services-console-or-local-consumption-interface.html)
- [Configure vSphere Namespace Permissions for vCenter Single Sign-On Users and Groups](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service/configuring-vsphere-namespaces-for-hosting-tkg-service-clusters/configure-vsphere-namespace-persmissions-for-vcenter-sso-users-and-groups.html) (the role your administrator gives you)
- [Local Consumption Interface release notes](https://vsphere-tmm.github.io/Supervisor-Services/consumption-interface/Release_Notes_9_1_3.html)

Back to [README](../README.md).
