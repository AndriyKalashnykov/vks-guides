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
you gave, and removes it when you ask.

If you know vSphere: a vSphere Supervisor Service (such as [Harbor](HARBOR.md)) runs on the
Supervisor, for all vSphere Namespaces. An add-on runs inside one VKS cluster, for the apps in that
cluster. Harbor is also an add-on: that is a separate registry inside one VKS cluster, not the
Supervisor Service.

## Why use an add-on instead of installing the software yourself

Anyone with the cluster's administrator kubeconfig can also install the same software straight into
the cluster with Helm or `kubectl`. With an add-on instead:

| | add-on | installed yourself |
|---|---|---|
| Support | Broadcom supports it ("Product" tier), or only its packaging, signing and upgrades ("Ecosystem" tier) | you support it; Broadcom does not support it |
| Versions | tested with the cluster's Kubernetes version | you check compatibility |
| Cluster upgrades | VKS checks every add-on first and moves it to a compatible release; with none, it refuses the upgrade | you find out after the upgrade |
| Who installs it | anyone who may edit the vSphere Namespace, from the Supervisor with `vcf addon`; no login to the cluster | someone logged in to the cluster, with Helm or `kubectl` |
| Where it comes from | Broadcom's registry, or your own copy of it for a site without internet | wherever the chart points |
| What is installed | one command lists it for each cluster | you keep track |

Install software yourself when the catalog does not have it, or not in the version or with the
settings you need: [MONITORING.md](MONITORING.md) installs the upstream Prometheus stack with Helm
for that reason.

## Two kinds of add-ons

- **Core add-ons** come with every VKS cluster: its network (Antrea or Calico, kube-proxy), its
  link to vSphere (vSphere CPI and CSI), CoreDNS, Metrics Server, its logins (Pinniped and the
  guest cluster auth service), kapp-controller, secretgen-controller and the Gateway API. VKS
  installs and upgrades them.
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
| [Send a VKS cluster's logs to VCF Operations](LOGGING.md) | Fluent Bit | send the cluster's logs out |
| [See a VKS cluster's logs and traces in Grafana](OBSERVABILITY.md) | Fluent Bit | send the logs to Loki |
| [OBSERVABILITY.md, step 11](OBSERVABILITY.md#11-let-vcf-operations-collect-the-clusters-kubernetes-metrics-optional) | Telegraf, Prometheus | metrics for VCF Operations; a cluster label installs them |

## See the catalog

This lists the add-ons your Supervisor offers, with a short description of each. It needs the
[VCF CLI](VCF.md) and a [Supervisor login](LOGIN.md).

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
vcf context use supervisor </dev/null
vcf addon available list
```

**Windows (PowerShell):**

```powershell
$null | vcf context use supervisor
vcf addon available list
```

**Expect:** a table of add-on names and descriptions, for example `cert-manager  Certificate
management` and `headlamp  Web UI for Kubernetes (Headlamp).`. A `failed to discover plugin sources
…` line from `vcf context use` is harmless ([VCF.md](VCF.md)).

**If not:** `Unable to read password from terminal`: your login has ended;
[renew it](LOGIN.md#renew-the-supervisor-login) and run this again.

## See what a cluster has

This lists the add-ons installed in your VKS cluster, apart from the core ones.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"

vcf context use supervisor </dev/null
vcf addon install list --cluster-name "$VKS_CLUSTER" -n "$VKS_NAMESPACE"
```

**Windows (PowerShell):**

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"

$null | vcf context use supervisor
vcf addon install list --cluster-name $VKS_CLUSTER -n $VKS_NAMESPACE
```

**Expect:** a row per add-on with `READY  True`. `DELETE/UPGRADE` is `NotAllowed` for the ones VKS
installs for every cluster from the Supervisor (such as `helm-controller`): this command cannot
remove or upgrade them. It is `Allowed` for the ones installed from your vSphere Namespace. A new
cluster may show only `NotAllowed` rows. The core add-ons are not listed; `--show-internal` adds
them.

**If not:** `Unable to read password from terminal`: [renew your login](LOGIN.md#renew-the-supervisor-login)
and run this again. A `READY` that stays `False`: `vcf addon install get <name> --cluster-name
"$VKS_CLUSTER" -n "$VKS_NAMESPACE"` shows why.

Back to [README](../README.md).
