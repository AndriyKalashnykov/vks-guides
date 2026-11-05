# VKS add-ons

> [!NOTE]
> **Official Broadcom documentation (VCF 9.1, VKS 3.8) for this guide**
>
> - [Managing Add-ons in VKS Clusters](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters.html) and its [Core Add-ons](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/core-addons.html) page
> - [Create a New AddonRepository Install Version](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/managing-add-ons-in-vks-clusters/creating-and-updating-addonrepositoryinstalls/create-a-new-addonrepository-install-version-for-vks-37-and-later.html) (add-ons from your own registry)
> - [VKS Add-ons Release Notes](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-addons-release-notes.html) (the list, support tiers and compatibility)
> - [VCF CLI command reference: addon](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-0/building-your-cloud-applications/getting-started-with-the-tools-for-building-applications/installing-and-using-vcf-cli-v9/command-reference2/addon.html) (VCF 9.0 page; there is no 9.1 copy)

A VKS cluster is a set of virtual machines that runs Kubernetes. On its own it runs apps, but most
teams also need common software beside them: a way to reach apps by name (ingress), certificates,
logs, metrics, backups, a service mesh, a web console. **Add-ons** are that software, packaged and
tested by Broadcom for VKS. You pick one from a catalog on the Supervisor and install it into a VKS
cluster with one VCF CLI command; the Supervisor then installs it, keeps it to the configuration
you gave, and removes it when you ask. This guide only lists them; the guides in
[Add-ons in these guides](#add-ons-in-these-guides) install the ones they need,
most with `vcf addon install create …`.

If you know vSphere: a vSphere Supervisor Service (such as [Harbor](HARBOR.md)) runs on the
Supervisor, for all vSphere Namespaces. An add-on runs inside one VKS cluster, for the apps in that
cluster. Harbor is also an add-on: that is a separate registry inside one VKS cluster, not the
Supervisor Service.

The steps:

1. [See the catalog](#1-see-the-catalog): the add-ons you can install.
2. [See what a cluster has](#2-see-what-a-cluster-has): the add-ons a VKS cluster already runs.

## Prerequisites

- for steps 1 and 2: the [VCF CLI](VCF.md) with your Supervisor login (the VCF CLI context
  `SUPERVISOR_CONTEXT`, made in [LOGIN.md](LOGIN.md)).
- for step 2: a VKS cluster ([CLUSTER.md](CLUSTER.md)), and the names of its vSphere Namespace and
  of the cluster.

The connections this guide needs, for a firewall (all TCP, besides DNS):

| from | to | port | for |
|---|---|---|---|
| your machine (laptop or jump box) | the Supervisor's address | 443 | the VCF CLI (steps [1](#1-see-the-catalog) and [2](#2-see-what-a-cluster-has)) |

## Why use an add-on instead of installing the software yourself

Anyone with the cluster's administrator kubeconfig (the file that lets kubectl reach the cluster)
can also install the same software straight into the cluster with Helm (a package installer for
Kubernetes) or `kubectl`. With an add-on instead:

| | add-on | installed yourself |
|---|---|---|
| Support | Broadcom supports it ("Product" tier), or only its packaging, signing and upgrades ("Ecosystem" tier) | you support it; Broadcom does not support it |
| Versions | tested with the cluster's Kubernetes version | you check compatibility |
| Cluster upgrades | VKS checks every add-on first and moves it to a compatible release; with none, it refuses the upgrade | you find out after the upgrade |
| Who installs it | anyone who may edit the vSphere Namespace, from the Supervisor with `vcf addon`; no login to the cluster | someone logged in to the cluster, with Helm or `kubectl` |
| Where it comes from | Broadcom's registry, or your own copy of it for a site without internet | wherever the Helm package (chart) points |
| What is installed | one command lists it for each cluster | you keep track |

Install software yourself when the catalog does not have it, or not in the version or with the
settings you need: [MONITORING.md](MONITORING.md) installs the upstream Prometheus stack with Helm
for that reason.

## Two kinds of add-ons

- **Core add-ons** come with every VKS cluster: the cluster network (Antrea or Calico,
  kube-proxy), the link to vSphere for VMs and disks (vSphere CPI and CSI), name lookup
  (CoreDNS), Metrics Server, sign-in (Pinniped and the guest cluster auth service),
  kapp-controller, secretgen-controller and the Gateway API. VKS installs and upgrades them; you
  do nothing.
- **Catalog add-ons** are the ones you choose. In VKS 3.8 they are, by support tier (your
  Supervisor's catalog can be shorter):

| tier | add-ons |
|---|---|
| Product: supported by Broadcom | AKO, cert-manager, Cluster Autoscaler, External DNS, External Secrets, Fluent Bit, Gatekeeper, Harbor, Helm Controller, Istio, Multus, NFS Client, Policy Bundle, Prometheus, Telegraf, Vault Injector, Velero, vSphere PV CSI Webhook, Whereabouts, Windows GMSA Webhook |
| Ecosystem: Broadcom supports only its packaging, signing and upgrades | Cilium, Contour, Headlamp, SR-IOV Network Device Plugin, Tekton Operator |

## Add-ons in these guides

| guide | add-on | what it is for |
|---|---|---|
| [Run Tekton in a VKS cluster](TEKTON.md), option A | Tekton Operator | a CI/CD engine |
| [Run an OIDC identity provider in a VKS cluster](KEYCLOAK-VKS.md), step 2 | cert-manager | Keycloak's HTTPS certificate |
| [Run Nexus Repository in a VKS cluster](NEXUS.md) | cert-manager; Contour if you choose | Nexus's HTTPS certificate, access by name |
| [Send a VKS cluster's logs to VCF Operations](LOGGING.md) | Fluent Bit | send the cluster's logs out |
| [See a VKS cluster's logs and traces in Grafana](OBSERVABILITY.md) | Fluent Bit | send the logs to Loki |
| [Headlamp: a web console for a VKS cluster](HEADLAMP.md) | Headlamp, cert-manager; Contour and Prometheus if you choose | a web page for the cluster, its plugins, access by name |
| [Run Octopus Deploy in a VKS cluster](OCTOPUS.md), step 2 | cert-manager | the HTTPS certificate of Octopus's web page |
| [OBSERVABILITY.md, step 11](OBSERVABILITY.md#11-let-vcf-operations-collect-the-clusters-kubernetes-metrics-optional) | Telegraf, Prometheus | metrics for VCF Operations; a cluster label installs them |

## 1. See the catalog

Run this before you choose an add-on, to see which ones your Supervisor offers. It lists the
add-ons in your Supervisor's catalog, with a short description of each; it switches the VCF CLI to
your Supervisor login and changes nothing on the Supervisor or the cluster. You then have the
add-on names, such as `cert-manager`, that the other guides install. It needs the
[VCF CLI](VCF.md) and a [Supervisor login](LOGIN.md).

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_CONTEXT="supervisor"
VCF_USE="$(vcf context use "$SUPERVISOR_CONTEXT" </dev/null 2>&1)"
if ! printf '%s\n' "$VCF_USE" | grep -qF "Successfully activated context '${SUPERVISOR_CONTEXT}'"; then
  printf '%s\n' "$VCF_USE"
  echo "FAILED: the VCF CLI is not on context ${SUPERVISOR_CONTEXT}: log in or renew (LOGIN.md), then run this again"
else
  vcf addon available list
fi
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$VCF_USE = ($null | vcf context use $SUPERVISOR_CONTEXT 2>&1 | ForEach-Object { "$_" }) -join "`n"
if (-not $VCF_USE.Contains("Successfully activated context '${SUPERVISOR_CONTEXT}'")) {
  $VCF_USE
  "FAILED: the VCF CLI is not on context ${SUPERVISOR_CONTEXT}: log in or renew (LOGIN.md), then run this again"
} else {
  vcf addon available list
}
```

**Expect:** a table of add-on names and descriptions, for example `cert-manager  Certificate
management` and `headlamp  Web UI for Kubernetes (Headlamp).`.

**If not:** `Unable to read password from terminal` (Windows: `The handle is invalid`): your login
has ended; [renew it](LOGIN.md#renew-the-supervisor-login) and run this again.

## 2. See what a cluster has

Run this before you install an add-on that a guide needs, to see whether the cluster already has
it, and again after, to see that it is ready. Set `VKS_NAMESPACE` and `VKS_CLUSTER` to your
vSphere Namespace and VKS cluster; the block lists the add-ons installed in that cluster beyond its
core add-ons. It switches the VCF CLI to your Supervisor login and changes nothing on the
Supervisor or the cluster. You then have a row per add-on: whether it is ready, and whether you
may remove or upgrade it with `vcf addon`.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
SUPERVISOR_CONTEXT="supervisor"

VCF_USE="$(vcf context use "$SUPERVISOR_CONTEXT" </dev/null 2>&1)"
if ! printf '%s\n' "$VCF_USE" | grep -qF "Successfully activated context '${SUPERVISOR_CONTEXT}'"; then
  printf '%s\n' "$VCF_USE"
  echo "FAILED: the VCF CLI is not on context ${SUPERVISOR_CONTEXT}: log in or renew (LOGIN.md), then run this again"
else
  vcf addon install list --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE"
fi
```

**Windows (PowerShell):**

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$SUPERVISOR_CONTEXT = "supervisor"

$VCF_USE = ($null | vcf context use $SUPERVISOR_CONTEXT 2>&1 | ForEach-Object { "$_" }) -join "`n"
if (-not $VCF_USE.Contains("Successfully activated context '${SUPERVISOR_CONTEXT}'")) {
  $VCF_USE
  "FAILED: the VCF CLI is not on context ${SUPERVISOR_CONTEXT}: log in or renew (LOGIN.md), then run this again"
} else {
  vcf addon install list --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE
}
```

**Expect:** a row per add-on with `READY  True`. `DELETE/UPGRADE` is `NotAllowed` for the ones VKS
installs from the Supervisor (such as `helm-controller`): this command cannot remove or upgrade
them. It is `Allowed` for the ones you or another namespace user installed with
`vcf addon install`. A new
cluster may show only `NotAllowed` rows. The core add-ons are not listed; `--show-internal` adds
them.

**If not:** `Unable to read password from terminal` (Windows: `The handle is invalid`): [renew your
login](LOGIN.md#renew-the-supervisor-login) and run this again. A `READY` that stays `False`:
`vcf addon install get <name> --cluster-name <your cluster> -n <your vSphere Namespace>` shows
why.

Back to [README](../README.md).
