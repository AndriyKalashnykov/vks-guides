[![Hits](https://hits.sh/github.com/AndriyKalashnykov/vks-simple.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/vks-simple/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

# VMware VKS Jumpbox Setup — Copy-Paste CLI Guides

Copy-paste shell blocks that set up a jumpbox for VMware vSphere Kubernetes Service (VKS):
`kubectl` and the VCF CLI (`vcf`). Each block declares its own variables at the top. There is no
Makefile, no mise and no env file. This repo is a minimal subset of
[golang-web/vks](https://github.com/AndriyKalashnykov/golang-web/tree/main/vks).

## How to use

- Paste each block into `bash` or `zsh` on Linux or macOS, in the order below.
- Edit the variables at the top of a block, then paste the whole block.
- **Expect:** after a block says what you should see; **If not:** says what to do.

## Prerequisites

| you need | for |
|---|---|
| `curl`, `tar`, `unzip`, `jq` | every guide; install with [Prerequisites](PREREQS.md) |
| a Broadcom support account that can download VMware vSphere Foundation 9 | [Install the VCF CLI](VCF.md) |
| network reach to dl.k8s.io (or to your Supervisor) | [Install kubectl](KUBECTL.md) |

## Steps

| # | guide | result |
|---|---|---|
| 1 | [Prerequisites](PREREQS.md) | `curl`, `tar`, `unzip`, `jq`; optional `sudo -v`; `~/.local/bin` on `PATH` |
| 2 | [Install kubectl](KUBECTL.md) | `kubectl` from dl.k8s.io (checksum-verified) or from the Supervisor; match the cluster's version |
| 3 | [Install the VCF CLI](VCF.md) | `vcf` and its plugins, from the Broadcom downloads |

Then check:

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

Not tested yet: macOS, Linux arm64, the Supervisor kubectl download, and the real Broadcom VCF CLI
tarballs.

## License

[MIT](LICENSE)
