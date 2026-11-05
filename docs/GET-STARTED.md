# Getting started

The Supervisor is the Kubernetes control plane vCenter runs when Workload Management is on; a VKS
cluster is a set of VMs in a vSphere Namespace that runs your apps. kubectl is the command-line
tool for both, and a kubeconfig is the file that tells kubectl which one to reach and how to log in.
In every guide, *your machine* is the laptop, workstation or jump box where you paste the blocks.
Your logins and kubeconfigs stay on it; a step marked *(the person)* runs on that person's machine.

Do them in this order:

1. [Prerequisites](PREREQS.md) for your OS, on each machine where you paste blocks: the guides'
   blocks use its tools.
2. [Install kubectl](KUBECTL.md). Its *From the Supervisor* needs
   [NAMESPACE.md](NAMESPACE.md) step 1 (the Supervisor's address and vCenter's CA) and step 1 of
   [Create Supervisor context with CA](LOGIN.md#create-supervisor-context-with-ca) first.
3. [Install the VCF CLI](VCF.md), before or after kubectl.
4. A vSphere Namespace with a role for your user: [NAMESPACE.md](NAMESPACE.md) steps 1 to 4.
5. [Log in](LOGIN.md) to the Supervisor, up to and including
   [Check your vSphere Namespace](LOGIN.md#check-your-vsphere-namespace).
6. A VKS cluster: [CLUSTER.md](CLUSTER.md).
7. The VKS cluster's kubeconfig, one of
   [from the vSphere Client](LOGIN.md#download-the-vks-clusters-kubeconfig-from-the-vsphere-client)
   or [with kubectl](LOGIN.md#get-the-vks-clusters-kubeconfig), then
   [Use the VKS cluster](LOGIN.md#use-the-vks-cluster).
8. [Kubeconfig files](KUBECONFIG.md), when you hand a kubeconfig to someone; it also says how
   `vcf` and `kubectl` keep your logins.
9. [Install Helm](HELM.md), only for the guides that install apps with it.

| guide | what it is |
|---|---|
| [Prerequisites](PREREQS.md) | the small command-line tools the other guides use, and podman or docker for building images |
| [Install kubectl](KUBECTL.md) | the Kubernetes command-line tool, for working with your clusters |
| [Install the VCF CLI](VCF.md) | VMware's command-line tool, for logging in to the Supervisor and managing VKS clusters |
| [Log in to the Supervisor and a VKS cluster](LOGIN.md) | your SSO login to the Supervisor, and the kubeconfig `kubectl` uses to reach your VKS cluster |
| [Kubeconfig files](KUBECONFIG.md) | what each kubeconfig the guides make holds, which ones may be handed over, how to use and merge them, and how `vcf` and `kubectl` keep your logins |
| [Install Helm](HELM.md) | the Kubernetes package manager, for installing charts such as the monitoring stack |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1), on amd64 machines:

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Prerequisites](PREREQS.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Install kubectl](KUBECTL.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Install the VCF CLI](VCF.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Log in](LOGIN.md) | ✅ | ✅ | ✅ | part | ✅ | ✅ |
| [Kubeconfig files](KUBECONFIG.md) | ✅ | — | — | — | ✅ | — |
| [Install Helm](HELM.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

Not run with these versions: macOS, Debian, Windows 10 and 11, Arm machines.

Back to [README](../README.md).
