# Getting started

Start with [Prerequisites](PREREQS.md) for your OS: every command-line block in the guides needs its
tools, so do it first on each machine where you paste blocks. Then install kubectl and the VCF CLI,
in either order; Log in needs both. Helm is needed only by the guides that install apps with it.

| guide | what it is |
|---|---|
| [Prerequisites](PREREQS.md) | the small command-line tools the other guides use, and podman or docker for building images |
| [Install kubectl](KUBECTL.md) | the Kubernetes command-line tool, for working with your clusters |
| [Install the VCF CLI](VCF.md) | VMware's command-line tool, for logging in to the Supervisor and managing VKS clusters |
| [Log in to the Supervisor and a VKS cluster](LOGIN.md) | your SSO login to the Supervisor, and the kubeconfig `kubectl` uses to reach your VKS cluster |
| [Kubeconfig files](KUBECONFIG.md) | what each kubeconfig the guides make holds, which ones may be handed over, and how to use and merge them |
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
