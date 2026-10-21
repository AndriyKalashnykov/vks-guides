[![Hits](https://hits.sh/github.com/AndriyKalashnykov/vks-simple.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/vks-simple/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

# VMware VKS Jumpbox Setup

Install `kubectl` and the VCF CLI on the machine you use to reach VMware vSphere Kubernetes
Service (VKS), and log in to the Supervisor and your guest cluster, by pasting shell blocks.

## How to use

1. Open `bash` or `zsh`. On Windows, use Ubuntu in WSL 2 ([Prerequisites](PREREQS.md#windows)).
2. If a block starts with variables, set them. Then paste the whole block.
3. Compare the output with **Expect:**. If it differs, do what **If not:** says.

## Guides

Start with Prerequisites. Then install kubectl and the VCF CLI, in either order. Log in needs both.

| guide | what it is |
|---|---|
| [Prerequisites](PREREQS.md) | the small command-line tools the other guides use |
| [Install kubectl](KUBECTL.md) | the Kubernetes command-line tool, for working with your clusters |
| [Install the VCF CLI](VCF.md) | VMware's command-line tool, for logging in to the Supervisor and managing VKS clusters |
| [Log in to the Supervisor and a guest cluster](LOGIN.md) | your SSO login to the Supervisor, and the kubeconfig `kubectl` uses to reach your guest cluster |

## Check what is installed

```sh
for t in curl tar unzip jq openssl kubectl vcf; do
  command -v "$t" >/dev/null 2>&1 && echo "ok       $t" || echo "MISSING  $t"
done
```

**Expect:** seven `ok` lines. For a `MISSING` line, re-run that tool's guide.

## Tested

| platform | shells | what ran |
|---|---|---|
| Ubuntu (Linux amd64) | bash, zsh | Install kubectl: dl.k8s.io install (latest, `+vmware` suffix, `~/.local/bin` fallback) and its failure messages. Install the VCF CLI: the install logic, against stand-in tarballs. Log in: every block, against stand-in `vcf`, `kubectl` and vCenter download |

Not tested yet: macOS, Windows (WSL 2), Linux arm64, the Supervisor kubectl download, the real Broadcom VCF CLI
tarballs, and a login to a real Supervisor.

## License

[MIT](LICENSE)
