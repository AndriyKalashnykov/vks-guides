[![Hits](https://hits.sh/github.com/AndriyKalashnykov/vks-guides.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/vks-guides/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

# VMware VKS How-to Guides

Install `kubectl` and the VCF CLI on the machine you use to reach VMware vSphere Kubernetes
Service (VKS), and log in to the Supervisor and your VKS cluster, by pasting shell blocks.

## How to use

1. **Linux, macOS:** open `bash` or `zsh`. **Windows:** open PowerShell and use the
   **Windows (PowerShell)** blocks, or use Ubuntu in WSL 2 ([Prerequisites](docs/PREREQS.md#windows)).
2. If a block starts with variables, set them. Then paste the whole block.
3. Compare the output with **Expect:**. If it differs, do what **If not:** says.

## Guides

Start with Prerequisites. Then install kubectl and the VCF CLI, in either order. Log in needs both.

| guide | what it is |
|---|---|
| [Prerequisites](docs/PREREQS.md) | the small command-line tools the other guides use |
| [Install kubectl](docs/KUBECTL.md) | the Kubernetes command-line tool, for working with your clusters |
| [Install the VCF CLI](docs/VCF.md) | VMware's command-line tool, for logging in to the Supervisor and managing VKS clusters |
| [Log in to the Supervisor and a VKS cluster](docs/LOGIN.md) | your SSO login to the Supervisor, and the kubeconfig `kubectl` uses to reach your VKS cluster |

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

Not tested anywhere: renewing a login that has already expired.

## License

[MIT](LICENSE)
