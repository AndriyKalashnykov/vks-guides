# GitOps and CI/CD

ArgoCD first. For build and deploy on every push, use Gitea and Tekton, or GitLab instead of both.
Octopus Deploy, for releases promoted through dev, test and prod, comes after ArgoCD; its step 11
uses Nexus, so do Nexus before it.

| guide | what it is |
|---|---|
| [Create a VKS cluster and deploy an app with ArgoCD](ARGOCD.md) | the ArgoCD Service, a VKS cluster made from Git, and a test app ArgoCD keeps in sync |
| [Run Nexus Repository in a VKS cluster](NEXUS.md) | Nexus Repository Community Edition with PostgreSQL in a VKS cluster: a Docker registry on one HTTPS address, with a push user and a pull user, that VKS clusters pull from |
| [Run Gitea in a VKS cluster](GITEA.md) | a self-hosted Git server with a web page, in one pod of a VKS cluster, that other machines such as ArgoCD can clone from |
| [Run Tekton in a VKS cluster](TEKTON.md) | a CI/CD engine that runs each build step as a pod, with a sample pipeline started by an HTTP request |
| [Run GitLab in a VKS cluster](GITLAB.md) | GitLab Community Edition, Git and CI/CD in one product, in one pod of a VKS cluster, with a runner that runs each CI job as a pod; an alternative to Gitea and Tekton |
| [Build and deploy on every push](CICD.md) | a push to a Git repository builds the image in the VKS cluster, pushes it to the container registry (Harbor) and has ArgoCD roll it out, with Gitea and Tekton or with GitLab |
| [Run Octopus Deploy in a VKS cluster](OCTOPUS.md) | a release server that promotes releases through dev, test and prod, with SQL Server Express, in a VKS cluster |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1), on amd64 machines:

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [ArgoCD](ARGOCD.md) | ✅ | part | ✅ | — | ✅ | ✅ |
| [Run Nexus](NEXUS.md) | — | — | — | — | — | — |
| [Run Gitea](GITEA.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Run Tekton](TEKTON.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Run GitLab](GITLAB.md) | part | ✅ | part | — | part | — |
| [CI/CD with Gitea and Tekton](CICD.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [CI/CD with GitLab](CICD.md) | part | ✅ | — | — | — | — |
| [Run Octopus Deploy](OCTOPUS.md) | part | — | — | — | — | — |

Not run with these versions: macOS, Debian, Windows 10 and 11, Arm machines.

Back to [README](../README.md).
