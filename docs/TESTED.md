# Tested on

Where each guide was run, by group; each group's page lists its guides and the order to follow.

✅ every block run, with each result its **Expect:** names for the guide's path and each "run it again"
the text asks for; "part" some of that run; — not run; n/a the guide does not apply there (the reason is
under the table). A guide with no blocks: ✅ every step clicked, "part" some steps clicked, in Chrome on
that OS. A block counts as run when its current text was pasted into an interactive shell (Windows: run
as a `.ps1` file in PowerShell 5.1) and its output matched its **Expect:**.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1), on amd64 machines.
Not run with these versions: macOS, Debian, Windows 10 and 11, Arm machines.

## Getting started

Group page: [Getting started](GET-STARTED.md).

| guide | Ubuntu (bash) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Prerequisites](PREREQS.md) | ✅ | ✅ | ✅ | ✅ | ✅ | part |
| [Install kubectl](KUBECTL.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Install the VCF CLI](VCF.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Log in to the Supervisor and a VKS cluster](SUPERVISOR-LOGIN.md) | part | part | part | part | part | part |
| [Log in to a VKS cluster you were given access to](USER-LOGIN.md) | ✅ | ✅ | ✅ | ✅ | part | part |
| [Use your vSphere Namespace in the web page](USER-LCI.md) | part | — | — | — | — | n/a |
| [Use a kubeconfig file you were given](USER-KUBECONFIG.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Sign in with your organization's identity provider](USER-IDP-LOGIN.md) | part | part | part | part | part | part |
| [Kubeconfig files](KUBECONFIG.md) | ✅ | ✅ | ✅ | ✅ | ✅ | part |
| [Install Helm](HELM.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

n/a: USER-LCI is a web page; WSL has no browser of its own (use the Windows column).

## Identity and access

Group page: [Identity and access](ACCESS-SIGN-IN.md).

| guide | Ubuntu (bash) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md) | part | part | part | part | part | part |
| [Give an identity provider group access to VKS clusters, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| [Run an OIDC identity provider in a VKS cluster](KEYCLOAK-VKS.md) | ✅ | ✅ | ✅ | ✅ | — | — |
| [OIDC sign-in on one VKS cluster, without the Supervisor](KEYCLOAK.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## vSphere Namespaces and VKS clusters

Group page: [vSphere Namespaces and VKS clusters](CLUSTERS.md).

| guide | Ubuntu (bash) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Create a vSphere Namespace](NAMESPACE.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Install Harbor](HARBOR.md) | part | — | — | — | — | — |
| [Create a VKS cluster](CLUSTER.md) | part | part | part | part | part | part |
| [VKS add-ons](ADDONS.md) | ✅ | ✅ | ✅ | ✅ | part | part |

## Container images

Group page: [Container images](IMAGES.md).

| guide | Ubuntu (bash) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Build a container image, push it to a registry and run it in a VKS cluster](IMAGE.md) | part | part | part | part | — | — |
| [Build a container image with docker, push it and run it (short version)](IMAGE-DOCKER.md) | ✅ | ✅ | ✅ | ✅ | n/a | — |

n/a: IMAGE-DOCKER is a docker-on-Linux walkthrough with no PowerShell blocks.

## GitOps and CI/CD

Group page: [GitOps and CI/CD](GITOPS-CICD.md).

| guide | Ubuntu (bash) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [ArgoCD](ARGOCD.md) | part | — | — | — | — | — |
| [Run Nexus](NEXUS.md) | part | part | part | part | part | part |
| [Run Gitea](GITEA.md) | part | part | part | part | — | part |
| [Run Tekton](TEKTON.md) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Run GitLab](GITLAB.md) | part | — | — | — | — | — |
| [CI/CD with Gitea and Tekton](CICD.md) | — | — | — | — | — | — |
| [CI/CD with GitLab](CICD.md) | — | — | — | — | — | — |
| [Run Octopus Deploy](OCTOPUS.md) | part | part | part | part | part | part |
| [Promote releases with Octopus and ArgoCD](CD-OCTOPUS.md) | part | part | part | part | part | part |

## Operations and observability

Group page: [Operations and observability](OPERATE.md).

| guide | Ubuntu (bash) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Headlamp](HEADLAMP.md) | part | part | part | part | part | — |
| [Monitor a VKS cluster](MONITORING.md) | ✅ | ✅ | ✅ | ✅ | — | — |
| [Send logs to VCF Operations](LOGGING.md) | — | — | — | — | — | — |
| [Logs and traces in Grafana](OBSERVABILITY.md) | part | part | part | part | — | — |

Back to [README](../README.md).
