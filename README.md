[![Hits](https://hits.sh/github.com/AndriyKalashnykov/vks-guides.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/vks-guides/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/license/MIT)

# VMware VKS How-to Guides

Copy-paste guides for VMware vSphere Kubernetes Service (VKS) on VCF 9.1, from an empty machine
to apps running on a VKS cluster: install `kubectl` and the VCF CLI, log in to the Supervisor,
create a vSphere Namespace and a VKS cluster, run Harbor as the clusters' private registry, and
deploy clusters and apps from Git with ArgoCD. Each command-line step is a block for bash, zsh
or Windows PowerShell, with the output to expect and what to do if it differs.

## How to use

1. **Linux, macOS:** open `bash` or `zsh`. **Windows:** open PowerShell and use the
   **Windows (PowerShell)** blocks, or use Ubuntu in WSL 2 ([Prerequisites](docs/PREREQS.md#windows)).
2. If a block starts with variables, set them. Then paste the whole block.
3. Compare the output with **Expect:**. If it differs, do what **If not:** says.

## Guides

Start with Prerequisites. Then install kubectl and the VCF CLI, in either order. Log in needs both. Then create the
vSphere Namespace (a vCenter administrator's task) and a VKS cluster in it. Harbor and ArgoCD are optional.

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

## Check what is installed

**Linux, macOS, WSL (bash or zsh):**

```sh
for t in curl tar unzip jq openssl kubectl vcf; do
  command -v "$t" >/dev/null 2>&1 && echo "ok       $t" || echo "MISSING  $t"
done
```

**Windows (PowerShell):**

```powershell
foreach ($t in 'kubectl', 'vcf') {
  if (Get-Command $t -ErrorAction SilentlyContinue) { "ok       $t" } else { "MISSING  $t" }
}
```

**Expect:** an `ok` line for each tool (seven; two in PowerShell).

**If not:** for `MISSING curl`, `tar`, `unzip`, `jq` or `openssl`, do [Prerequisites](docs/PREREQS.md);
for `kubectl`, [Install kubectl](docs/KUBECTL.md); for `vcf`, [Install the VCF CLI](docs/VCF.md).

## Platforms

Run against the Broadcom 9.1.1.0100 files and a vSphere 9.1.1 Supervisor with a VKS cluster.

| OS | shell | tested |
|---|---|---|
| Ubuntu, amd64 | bash, zsh | ✅ |
| Linux, arm64 | bash, zsh | ❌ |
| macOS 26, arm64 (Apple silicon) | bash 3.2, zsh 5.9 | ✅ |
| macOS, amd64 (Intel) | bash, zsh | ❌ |
| Windows Server 2025, amd64 | Windows PowerShell 5.1 | ✅ |
| Windows Server 2025, amd64, WSL 2 Ubuntu | bash, as root | ✅ except the password login |
| Windows, arm64 | Windows PowerShell 5.1; bash in WSL 2 | ❌ |

NAMESPACE.md, CLUSTER.md, HARBOR.md and ARGOCD.md were run on 2026-10-23 with VKS 3.7.2, the
Harbor Supervisor Service 2.15.2 and the ArgoCD Service 1.2.0, on Ubuntu (bash, zsh), macOS 26
(bash 3.2, zsh 5.9) and Windows PowerShell 5.1, not in WSL; most blocks as an SSO user whose only
role was **Namespaces Edit**. Harbor was installed and uninstalled twice, and the VKS cluster
nodes were updated each time; ArgoCD's certificate renewal (step 7) was run with an app deployed.
On macOS and in PowerShell, HARBOR.md's admin password blocks ran against a stand-in server. Its
clipboard blocks ran in a Linux desktop session (Wayland) and in PowerShell, and on macOS only
without a desktop session. ARGOCD.md's web-page steps were done in Chrome.

Renewing a login that had already expired was run on macOS (zsh) only.

## License

[MIT](LICENSE)
