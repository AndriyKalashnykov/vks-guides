[![Hits](https://hits.sh/github.com/AndriyKalashnykov/vks-guides.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/vks-guides/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/license/MIT)

# VMware VKS How-to Guides

Copy-paste guides for VMware vSphere Kubernetes Service (VKS) on VCF 9.1, from an empty machine
to apps running on a VKS cluster: install `kubectl` and the VCF CLI, log in to the Supervisor,
create a vSphere Namespace and a VKS cluster, run Harbor as the clusters' private registry,
deploy clusters and apps from Git with ArgoCD, monitor a cluster with Prometheus and Grafana,
send its logs to VCF Operations, and see its logs and traces in Grafana.
Each command-line step is a block for bash, zsh or Windows PowerShell, with the output to expect
and what to do if it differs.

## How to use

1. **Linux, macOS:** open `bash` or `zsh`. **Windows:** open PowerShell and use the
   **Windows (PowerShell)** blocks, or use Ubuntu in WSL 2 ([Prerequisites](docs/PREREQS.md#windows)).
2. If a block starts with variables, set them. Then paste the whole block.
3. Compare the output with **Expect:**. If it differs, do what **If not:** says.

## Guides

The guides are in six groups. Start with Get started, then Namespaces and clusters; the other
groups are optional, in any order once you have a VKS cluster. Each group's page lists its guides,
the order to follow and where each was tested.

| group | what it is for |
|---|---|
| [Get started](docs/GET-STARTED.md) | tools, login, kubeconfig files |
| [Access and sign-in](docs/ACCESS-SIGN-IN.md) | give others access, Keycloak sign-in |
| [Namespaces and clusters](docs/CLUSTERS.md) | vSphere Namespace, VKS cluster, add-ons, Harbor |
| [Images](docs/IMAGES.md) | build, push and run an image from Harbor |
| [GitOps and CI/CD](docs/GITOPS-CICD.md) | ArgoCD, Gitea, Tekton, GitLab, build and deploy on push |
| [Operate and observe](docs/OPERATE.md) | web console, monitoring, logs and traces |

## Check what is installed

To see which tools this machine already has, and which install guides to do, run
[Prerequisites: Check](docs/PREREQS.md#check).

## License

[MIT](LICENSE)
