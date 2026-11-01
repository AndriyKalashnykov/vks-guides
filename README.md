[![Hits](https://hits.sh/github.com/AndriyKalashnykov/vks-guides.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/vks-guides/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/license/MIT)

# VMware VKS How-to Guides

Step-by-step guides for VMware vSphere Kubernetes Service (VKS) on VCF 9.1. They are written for
vCenter administrators who are new to VKS and Kubernetes, and use standard Kubernetes terms, so
Kubernetes engineers can use them as a reference too.

## Before you start: install the prerequisites

On each machine where you will paste the blocks, do [Prerequisites](docs/PREREQS.md) for its OS,
then run its [Check](docs/PREREQS.md#check), which lists any missing tool. Without these tools the
guides' blocks stop, or take the wrong branch. On Windows, Prerequisites is also where you choose
PowerShell or WSL 2. Then do [Getting started](docs/GET-STARTED.md) (kubectl, the VCF CLI, logging
in): most guides need it too.

## About VKS and these guides

**What VKS is.** VKS runs conformant Kubernetes clusters, built from upstream Kubernetes
releases, on vSphere. The Supervisor is a Kubernetes control plane that vSphere runs on your
vSphere clusters, managed from vCenter. On it you create vSphere Namespaces and set, for each one,
its CPU, memory and storage limits, the VM classes and storage policies it may use, and who may
use it. A vSphere Namespace is a namespace on the Supervisor, not inside a VKS cluster. In it you
declare VKS clusters. The Supervisor is their Cluster API management cluster: it creates their
control-plane and worker nodes as VMs, scales them, and rolls out a new Kubernetes version when
you change it.

**Why use it.** Teams get their own Kubernetes clusters on demand, while you keep vSphere's resource
limits, vCenter SSO and storage policies. Broadcom supports the Kubernetes releases; for a VKS
add-on it supports either the software or only its packaging and upgrades ([VKS
add-ons](docs/ADDONS.md)). Where a guide installs open-source software that Broadcom does not
support, it says so (such as Prometheus, Gitea, GitLab and Kaniko). Tools a guide downloads for your
own machine from their own projects (Helm, kubelogin, podman, docker), and the sample apps and test
images the guides run, are not Broadcom's either.

**What the guides cover**, from an empty workstation to apps running on a VKS cluster: install
kubectl, the VCF CLI and Helm, log in with vCenter SSO and manage kubeconfig files; give people
access with Kubernetes RBAC and an external OIDC identity provider; create a vSphere Namespace and a
VKS cluster, install add-ons, and run a private container registry (Harbor) on the Supervisor; build
container images and run them from the registry; deploy from Git with ArgoCD and build on every push
(Gitea and Tekton, or GitLab); browse a cluster in a web console (Headlamp), monitor it with
Prometheus and Grafana, forward its logs to VCF Operations, and see its logs and traces in Grafana
(Loki, Jaeger).

**How each guide works.** It opens with the official Broadcom or upstream docs it follows, and what
you need first: earlier guides, tools, and, where it needs them, the rights and the network
connections to allow. Steps in the vSphere Client are shown with screenshots. Command-line steps are
blocks you paste into bash, zsh or Windows PowerShell. After each step, **Expect:** shows what
success looks like and **If not:** says what to do.

## How to use

1. Do the steps in order. Where a block comes in versions for different shells, paste the one for
   yours: **Linux, macOS, WSL (bash or zsh)** or **Windows (PowerShell)**. On Windows, a block with
   no PowerShell version runs in WSL 2 ([Prerequisites](docs/PREREQS.md#windows)).
2. If a block starts with variables, set them first.
3. Compare the output with the **Expect:** line under the block; if it differs, do what **If not:** says.

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

## License

[MIT](LICENSE)
