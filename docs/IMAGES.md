# Images

These need Harbor ([vSphere Namespaces and VKS clusters](CLUSTERS.md)). Pick one: the full guide
(podman or docker, every OS) or the short docker-on-Linux version.

| guide | what it is |
|---|---|
| [Build an image, push it to Harbor and run it](IMAGE.md) | a test app built with podman or docker, pushed to a Harbor project, and run in a VKS cluster from there |
| [Build an image with docker, push it to Harbor and run it (short version)](IMAGE-DOCKER.md) | the same with docker on Linux only, in the fewest commands, for a public or a private project |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1):

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows PowerShell 5.1 | WSL 2 Ubuntu (bash, as root) |
|---|---|---|---|---|---|---|
| [Build an image, push it to Harbor and run it](IMAGE.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Build an image with docker (short version)](IMAGE-DOCKER.md) | ✅ | — | — | — | — | ✅ |

Back to [README](../README.md).
