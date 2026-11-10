# Tested on

Where each guide was run, by group; each group's page lists its guides and the order to follow.

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1), on amd64 machines:

## Getting started

Group page: [Getting started](GET-STARTED.md).

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Prerequisites](PREREQS.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Install kubectl](KUBECTL.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Install the VCF CLI](VCF.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Log in to the Supervisor and a VKS cluster](SUPERVISOR-LOGIN.md) | ✅ | ✅ | ✅ | part | ✅ | ✅ |
| [Log in to a VKS cluster you were given access to](USER-LOGIN.md) | part | — | — | — | — | — |
| [Use a kubeconfig file you were given](USER-KUBECONFIG.md) | — | — | — | — | — | — |
| [Sign in with your organization's identity provider](USER-IDP-LOGIN.md) | — | — | — | — | — | — |
| [Kubeconfig files](KUBECONFIG.md) | ✅ | — | — | — | ✅ | — |
| [Install Helm](HELM.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## Identity and access

Group page: [Identity and access](ACCESS-SIGN-IN.md).

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md) | part | part | part | — | part | part |
| [Give an identity provider group access to VKS clusters, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md) | part | — | — | — | — | — |
| [Run an OIDC identity provider in a VKS cluster](KEYCLOAK-VKS.md) | part | part | part | — | part | part |
| [OIDC sign-in on one VKS cluster, without the Supervisor](KEYCLOAK.md) | ✅ | — | part | — | ✅ | — |

## vSphere Namespaces and VKS clusters

Group page: [vSphere Namespaces and VKS clusters](CLUSTERS.md).

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Create a vSphere Namespace](NAMESPACE.md) | ✅ | ✅ | — | — | ✅ | ✅ |
| [Install Harbor](HARBOR.md) | ✅ | ✅ | part | — | part | part |
| [Create a VKS cluster](CLUSTER.md) | ✅ | ✅ | ✅ | — | ✅ | part |
| [VKS add-ons](ADDONS.md) | ✅ | ✅ | — | — | ✅ | ✅ |

## Container images

Group page: [Container images](IMAGES.md).

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Build a container image, push it to a registry and run it in a VKS cluster](IMAGE.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Build a container image with docker, push it and run it (short version)](IMAGE-DOCKER.md) | ✅ | — | — | — | — | ✅ |

## GitOps and CI/CD

Group page: [GitOps and CI/CD](GITOPS-CICD.md).

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [ArgoCD](ARGOCD.md) | part | part | part | — | part | part |
| [Run Nexus](NEXUS.md) | — | — | — | — | — | — |
| [Run Gitea](GITEA.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Run Tekton](TEKTON.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Run GitLab](GITLAB.md) | part | ✅ | part | — | part | — |
| [CI/CD with Gitea and Tekton](CICD.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [CI/CD with GitLab](CICD.md) | part | ✅ | — | — | — | — |
| [Run Octopus Deploy](OCTOPUS.md) | part | — | — | — | — | — |

## Operations and observability

Group page: [Operations and observability](OPERATE.md).

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Headlamp](HEADLAMP.md) | part | part | — | — | part | part |
| [Monitor a VKS cluster](MONITORING.md) | part | part | part | — | part | part |
| [Send logs to VCF Operations](LOGGING.md) | part | part | part | — | part | — |
| [Logs and traces in Grafana](OBSERVABILITY.md) | part | ✅ | part | — | part | part |

Not run with these versions: macOS, Debian, Windows 10 and 11, Arm machines.

Back to [README](../README.md).
