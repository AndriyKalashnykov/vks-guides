[![Hits](https://hits.sh/github.com/AndriyKalashnykov/vks-simple.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/vks-simple/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

# VMware VKS Jumpbox Setup — Copy-Paste CLI Guides

Copy-paste shell blocks that set up a jumpbox for VMware vSphere Kubernetes Service (VKS):
`kubectl` and the VCF CLI (`vcf`). Each block declares its own variables at the top. There is no
Makefile, no mise and no env file. This repo is a minimal subset of
[golang-web/vks](https://github.com/AndriyKalashnykov/golang-web/tree/main/vks).

## How to use

- Paste each block into `bash` or `zsh` on Linux, macOS, or Windows (WSL 2).
- Edit the variables at the top of a block, then paste the whole block.
- **Expect:** after a block says what you should see; **If not:** says what to do.

## Prerequisites

| you need | for |
|---|---|
| `curl`, `tar`, `unzip`, `jq` | every guide; install with [Prerequisites](PREREQS.md) |
| a Broadcom support account that can download VMware vSphere Foundation 9 | [Install the VCF CLI](VCF.md) |
| network reach to dl.k8s.io (or to your Supervisor) | [Install kubectl](KUBECTL.md) |

## Guides

Each guide stands alone. Use the ones you need, in any order, and skip any tool you already have.

| guide | what it is |
|---|---|
| [Prerequisites](PREREQS.md) | the small command-line tools the other guides use |
| [Install kubectl](KUBECTL.md) | the Kubernetes command-line tool, for working with your clusters |
| [Install the VCF CLI](VCF.md) | VMware's command-line tool, for logging in to the Supervisor and managing VKS clusters |

## Check what is installed

```sh
for t in curl tar unzip jq kubectl vcf; do
  command -v "$t" >/dev/null 2>&1 && echo "ok       $t" || echo "MISSING  $t"
done
```

**Expect:** six `ok` lines. For a `MISSING` line, re-run that tool's guide.

## Tested

| platform | shells | what ran |
|---|---|---|
| Ubuntu (Linux amd64) | bash, zsh | KUBECTL.md: dl.k8s.io install (latest, `+vmware` suffix, `~/.local/bin` fallback) and failure paths; VCF.md: install logic against stand-in tarballs |

Not tested yet: macOS, Windows (WSL 2), Linux arm64, the Supervisor kubectl download, and the real Broadcom VCF CLI
tarballs.

## License

[MIT](LICENSE)
