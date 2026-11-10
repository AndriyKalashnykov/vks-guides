# vSphere Namespaces and VKS clusters

Do [Getting started](GET-STARTED.md) steps 1 to 5 first (the tools, a vSphere Namespace, the
Supervisor login). If you will use a private container registry (Harbor), install it next
([HARBOR.md](HARBOR.md) steps 1 to 10): installing it updates every node of every VKS cluster. Then
create a VKS cluster, and run HARBOR.md step 11 on it. Add-ons are optional.

| guide | what it is |
|---|---|
| [Create a vSphere Namespace](NAMESPACE.md) | a vCenter administrator's vSphere Namespace for VKS clusters, and the check that it is ready |
| [Install Harbor](HARBOR.md) | a private container registry on the Supervisor, Broadcom's supported Harbor, installed by a vCenter administrator and trusted by its VKS clusters |
| [Create a VKS cluster](CLUSTER.md) | a VKS cluster made in the vSphere Client, checked, and deleted |
| [VKS add-ons](ADDONS.md) | what add-ons are, why to use them instead of installing software yourself, and how to list the catalog and what a cluster has |

## Tested on

Where each guide in this group was run, on which OS and with which versions: [Tested on](TESTED.md#vsphere-namespaces-and-vks-clusters).

Back to [README](../README.md).
