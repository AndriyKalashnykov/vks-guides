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

Start with Prerequisites. Then install kubectl and the VCF CLI, in either order. Log in needs both. Then create the
vSphere Namespace (a vCenter administrator's task) and a VKS cluster in it. Harbor, ArgoCD, Gitea,
Tekton, monitoring, logging and observability are optional; monitoring needs Helm or ArgoCD, and observability needs
monitoring and Helm.

| guide | what it is |
|---|---|
| [Prerequisites](docs/PREREQS.md) | the small command-line tools the other guides use |
| [Install kubectl](docs/KUBECTL.md) | the Kubernetes command-line tool, for working with your clusters |
| [Install the VCF CLI](docs/VCF.md) | VMware's command-line tool, for logging in to the Supervisor and managing VKS clusters |
| [Log in to the Supervisor and a VKS cluster](docs/LOGIN.md) | your SSO login to the Supervisor, and the kubeconfig `kubectl` uses to reach your VKS cluster |
| [Create a vSphere Namespace](docs/NAMESPACE.md) | a vCenter administrator's vSphere Namespace for VKS clusters, and the check that it is ready |
| [Create a VKS cluster](docs/CLUSTER.md) | a VKS cluster made in the vSphere Client, checked, and deleted |
| [Install Harbor](docs/HARBOR.md) | a vCenter administrator's Harbor registry on the Supervisor, trusted by its VKS clusters |
| [Create a VKS cluster and deploy an app with ArgoCD](docs/ARGOCD.md) | the ArgoCD Service, a VKS cluster made from Git, and a test app ArgoCD keeps in sync |
| [Run Gitea in a VKS cluster](docs/GITEA.md) | a self-hosted Git server with a web page, in one pod of a VKS cluster, that other machines such as ArgoCD can clone from |
| [Run Tekton in a VKS cluster](docs/TEKTON.md) | a CI/CD engine that runs each build step as a pod, with a sample pipeline started by an HTTP request |
| [Run GitLab in a VKS cluster](docs/GITLAB.md) | GitLab Community Edition, Git and CI/CD in one product, in one pod of a VKS cluster, with a runner that runs each CI job as a pod; an alternative to Gitea and Tekton |
| [Build and deploy on every push](docs/CICD.md) | a push to a Git repository builds the image in the VKS cluster, pushes it to Harbor and has ArgoCD roll it out, with Gitea and Tekton or with GitLab |
| [Install Helm](docs/HELM.md) | the Kubernetes package manager, for installing charts such as the monitoring stack |
| [Monitor a VKS cluster](docs/MONITORING.md) | Prometheus, Alertmanager and Grafana in a VKS cluster, from the upstream kube-prometheus-stack chart, with Helm or ArgoCD |
| [Send a VKS cluster's logs to VCF Operations](docs/LOGGING.md) | Broadcom's Fluent Bit add-on, sending the cluster's logs over HTTPS to Log Management in VCF Operations |
| [See a VKS cluster's logs and traces in Grafana](docs/OBSERVABILITY.md) | Loki and Jaeger in the cluster, Broadcom's Fluent Bit add-on sending logs to Loki, a sample app with linked logs and traces, and the cluster in VCF Operations |

## Check what is installed

**Linux, macOS, WSL (bash or zsh):**

```sh
for t in curl tar unzip jq openssl kubectl vcf helm; do
  command -v "$t" >/dev/null 2>&1 && echo "ok       $t" || echo "MISSING  $t"
done
```

**Windows (PowerShell):**

```powershell
foreach ($t in 'kubectl', 'vcf', 'helm') {
  if (Get-Command $t -ErrorAction SilentlyContinue) { "ok       $t" } else { "MISSING  $t" }
}
```

**Expect:** an `ok` line for each tool (eight; three in PowerShell). `helm` is needed only for
monitoring.

**If not:** for `MISSING curl`, `tar`, `unzip`, `jq` or `openssl`, do [Prerequisites](docs/PREREQS.md);
for `kubectl`, [Install kubectl](docs/KUBECTL.md); for `vcf`, [Install the VCF CLI](docs/VCF.md); for
`helm`, [Install Helm](docs/HELM.md).

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1):

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Windows PowerShell 5.1 |
|---|---|---|---|---|
| [Prerequisites](docs/PREREQS.md) | — | part | — | — |
| [Install kubectl](docs/KUBECTL.md) | — | part | part | — |
| [Install the VCF CLI](docs/VCF.md) | part | part | part | part |
| [Log in](docs/LOGIN.md) | part | part | part | part |
| [Create a vSphere Namespace](docs/NAMESPACE.md) | ✅ | ✅ | — | ✅ |
| [Create a VKS cluster](docs/CLUSTER.md) | — | part | part | — |
| [Install Harbor](docs/HARBOR.md) | ✅ | part | — | — |
| [ArgoCD](docs/ARGOCD.md) | part | — | part | part |
| [Run Gitea](docs/GITEA.md) | part | part | part | part |
| [Run Tekton](docs/TEKTON.md) | part | part | ✅ | part |
| [Run GitLab](docs/GITLAB.md) | part | — | — | — |
| [CI/CD with Gitea and Tekton](docs/CICD.md) | part | — | — | — |
| [CI/CD with GitLab](docs/CICD.md) | part | — | — | — |
| [Install Helm](docs/HELM.md) | — | ✅ | ✅ | — |
| [Monitor a VKS cluster](docs/MONITORING.md) | — | part | part | — |
| [Send logs to VCF Operations](docs/LOGGING.md) | — | part | part | part |
| [Logs and traces in Grafana](docs/OBSERVABILITY.md) | — | part | part | — |

Earlier versions of these guides, on VCF 9.1.1 with VKS 3.7.2, from Linux and Windows on amd64 and
macOS on Apple silicon:

| guide | Ubuntu (bash, zsh) | Photon OS 5 (bash) | macOS 26 (bash, zsh) | Windows PowerShell 5.1 | WSL 2 Ubuntu (bash, as root) |
|---|---|---|---|---|---|
| [Prerequisites](docs/PREREQS.md) | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Install kubectl](docs/KUBECTL.md) | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Install the VCF CLI](docs/VCF.md) | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Log in](docs/LOGIN.md) | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Create a vSphere Namespace](docs/NAMESPACE.md) | ✅ | ✅ | part | ✅ | — |
| [Create a VKS cluster](docs/CLUSTER.md) | ✅ | ✅ | part | ✅ | — |
| [Install Harbor](docs/HARBOR.md) | ✅ | part | part | ✅ | — |
| [ArgoCD](docs/ARGOCD.md) | ✅ | part | ✅ | ✅ | — |
| [Run Gitea](docs/GITEA.md) | ✅ | ✅ | — | ✅ | ✅ |
| [Run Tekton](docs/TEKTON.md) | ✅ | ✅ | — | ✅ | — |
| [Run GitLab](docs/GITLAB.md) | ✅ | ✅ | — | ✅ | — |
| [CI/CD with Gitea and Tekton](docs/CICD.md) | part | — | — | part | — |
| [CI/CD with GitLab](docs/CICD.md) | — | part | — | part | — |
| [Install Helm](docs/HELM.md) | ✅ | ✅ | — | ✅ | — |
| [Monitor a VKS cluster](docs/MONITORING.md) | ✅ | part | — | part | — |
| [Send logs to VCF Operations](docs/LOGGING.md) | part | part | — | part | ✅ |
| [Logs and traces in Grafana](docs/OBSERVABILITY.md) | ✅ | part | — | part | — |

Windows was Windows Server 2025. Linux on arm64, Intel Macs and Windows on arm64 were not tested.

## License

[MIT](LICENSE)
