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
   [NAMESPACE.md](NAMESPACE.md#1-find-the-supervisors-address-and-vcenters-ca) step 1 (the Supervisor's address and vCenter's CA) and step 1 of
   [Create Supervisor context with CA](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca) first.
3. [Install the VCF CLI](VCF.md), before or after kubectl.
4. A vSphere Namespace with a role for your user: [NAMESPACE.md](NAMESPACE.md) steps 1 to 4.
5. [Log in](SUPERVISOR-LOGIN.md) to the Supervisor, up to and including
   [Check your vSphere Namespace](SUPERVISOR-LOGIN.md#check-your-vsphere-namespace).
6. A VKS cluster: [CLUSTER.md](CLUSTER.md).
7. The VKS cluster's kubeconfig, one of
   [from the vSphere Client](SUPERVISOR-LOGIN.md#download-the-vks-clusters-kubeconfig-from-the-vsphere-client)
   or [with kubectl](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig), then
   [Use the VKS cluster](SUPERVISOR-LOGIN.md#use-the-vks-cluster).
8. [Kubeconfig files](KUBECONFIG.md), when you hand a kubeconfig to someone; it also says how
   `vcf` and `kubectl` keep your logins.
9. [Install Helm](HELM.md), only for the guides that install apps with it.

Given access to a VKS cluster by its administrator? You need only Prerequisites and kubectl, then one
guide: with your own SSO account, the VCF CLI and
[Log in to a VKS cluster you were given access to](USER-LOGIN.md); with a kubeconfig file you were
sent, [Use a kubeconfig file you were given](USER-KUBECONFIG.md); with your organization's identity
provider, [Sign in with your organization's identity provider](USER-IDP-LOGIN.md) (its part A, a file
that runs `vcf`, needs the VCF CLI too; part B needs kubelogin).

| guide | what it is |
|---|---|
| [Prerequisites](PREREQS.md) | the small command-line tools the other guides use, and podman or docker for building images |
| [Install kubectl](KUBECTL.md) | the Kubernetes command-line tool, for working with your clusters |
| [Install the VCF CLI](VCF.md) | VMware's command-line tool, for logging in to the Supervisor and managing VKS clusters |
| [Log in to the Supervisor and a VKS cluster](SUPERVISOR-LOGIN.md) | your SSO login to the Supervisor, and the kubeconfig `kubectl` uses to reach your VKS cluster |
| [Log in to a VKS cluster you were given access to](USER-LOGIN.md) | for a person a VKS cluster's administrator gave access: the login with their own SSO user, and using it |
| [Use a kubeconfig file you were given](USER-KUBECONFIG.md) | for a person or a tool sent a file with a token or a certificate: check it, use it, what to do when it stops working or leaks |
| [Sign in with your organization's identity provider](USER-IDP-LOGIN.md) | for a person whose identity provider group was given access: trust the CAs, sign in in a browser, log out |
| [Kubeconfig files](KUBECONFIG.md) | what each kubeconfig the guides make holds, which ones may be handed over, how to use and merge them, and how `vcf` and `kubectl` keep your logins |
| [Install Helm](HELM.md) | the Kubernetes package manager, for installing charts such as the monitoring stack |

## Tested on

Where each guide in this group was run, on which OS and with which versions: [Tested on](TESTED.md#getting-started).

Back to [README](../README.md).
