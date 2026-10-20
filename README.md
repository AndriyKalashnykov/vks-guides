# vks-simple

Copy-paste CLI guides for working with VMware vSphere Kubernetes Service (VKS). A minimal subset
of [golang-web/vks](https://github.com/AndriyKalashnykov/golang-web/tree/main/vks).

## How to use

- Each guide is a list of shell blocks. Paste them into `bash` or `zsh` on Linux or macOS.
- Each block sets the variables it needs at the top. Edit them, then paste the whole block.
- No Makefile, no mise, no env file to source: a block depends only on the tools it names.
- **Expect:** after a block says what you should see; **If not:** says what to do.

## Guides

| guide | what it does |
|---|---|
| [PREREQS.md](PREREQS.md) | `curl`, `tar`, `unzip`, `jq`; `sudo` and `PATH` notes |
| [KUBECTL.md](KUBECTL.md) | install `kubectl` from dl.k8s.io or from the Supervisor, and match the cluster's version |
| [VCF.md](VCF.md) | install the VCF CLI (`vcf`) and its plugins from the Broadcom downloads |

## Check

```sh
for t in curl tar unzip jq kubectl vcf; do
  command -v "$t" >/dev/null 2>&1 && echo "ok       $t" || echo "MISSING  $t"
done
```

**Expect:** six `ok` lines. For a `MISSING` line, see the guide above for that tool.

## License

[MIT](LICENSE)
