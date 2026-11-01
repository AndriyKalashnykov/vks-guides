[![Hits](https://hits.sh/github.com/AndriyKalashnykov/vks-guides.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/vks-guides/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/license/MIT)

# VMware VKS How-to Guides

Copy-paste guides for VMware vSphere Kubernetes Service (VKS) on VCF 9.1, from an empty machine
to apps running on a VKS cluster: install `kubectl` and the VCF CLI, log in to the Supervisor,
create a vSphere Namespace and a VKS cluster, run a private container registry (Harbor),
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

The guides are in six groups. Start with Getting started, then vSphere Namespaces and VKS clusters;
the other groups are optional, in any order once you have a VKS cluster. Each group's page lists
its guides, the order to follow and where each was tested.

| group | what it is for |
|---|---|
| [Getting started](docs/GET-STARTED.md) | client tools (kubectl, VCF CLI, Helm), Supervisor and VKS cluster login, kubeconfig management |
| [Identity and access](docs/ACCESS-SIGN-IN.md) | Kubernetes RBAC, vCenter SSO, and single sign-on through an external OIDC identity provider (Keycloak example) |
| [vSphere Namespaces and VKS clusters](docs/CLUSTERS.md) | vSphere Namespace and VKS cluster provisioning, cluster add-ons, private container registry (Harbor) |
| [Container images](docs/IMAGES.md) | build OCI container images, push them to a private registry, deploy them to a VKS cluster |
| [GitOps and CI/CD](docs/GITOPS-CICD.md) | GitOps continuous delivery (ArgoCD), self-hosted Git (Gitea, GitLab), CI pipelines (Tekton, GitLab CI), build and deploy on every push |
| [Operations and observability](docs/OPERATE.md) | cluster web UI (Headlamp), metrics and alerting (Prometheus, Grafana), log forwarding (VCF Operations), logs and distributed tracing (Loki, Jaeger) |

## Check what is installed

To see which tools this machine already has, and which install guides to do, run
[Prerequisites: Check](docs/PREREQS.md#check).

## License

[MIT](LICENSE)
