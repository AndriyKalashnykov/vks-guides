# vSphere Namespaces and VKS clusters

Create the vSphere Namespace (a vCenter administrator's task), then a VKS cluster in it. Add-ons and
a private container registry (Harbor) are optional.

| guide | what it is |
|---|---|
| [Create a vSphere Namespace](NAMESPACE.md) | a vCenter administrator's vSphere Namespace for VKS clusters, and the check that it is ready |
| [Create a VKS cluster](CLUSTER.md) | a VKS cluster made in the vSphere Client, checked, and deleted |
| [VKS add-ons](ADDONS.md) | what add-ons are, why to use them instead of installing software yourself, and how to list the catalog and what a cluster has |
| [Install Harbor](HARBOR.md) | a private container registry on the Supervisor, Broadcom's supported Harbor, installed by a vCenter administrator and trusted by its VKS clusters |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1):

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows PowerShell 5.1 | WSL 2 Ubuntu (bash, as root) |
|---|---|---|---|---|---|---|
| [Create a vSphere Namespace](NAMESPACE.md) | ✅ | ✅ | — | — | ✅ | ✅ |
| [Create a VKS cluster](CLUSTER.md) | ✅ | ✅ | ✅ | — | ✅ | part |
| [VKS add-ons](ADDONS.md) | ✅ | ✅ | — | — | ✅ | ✅ |
| [Install Harbor](HARBOR.md) | ✅ | ✅ | part | — | part | part |

Back to [README](../README.md).
