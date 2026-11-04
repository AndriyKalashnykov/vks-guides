# Container images

A container image is a packaged app that a VKS cluster runs, a bit like a VM template for one
program. A registry stores the images, and the cluster downloads them from it. The guides use
Harbor, Broadcom's supported registry, as the example; another OCI registry works the same way.

Before either guide: [Install Harbor](HARBOR.md), steps 1 to 11 (step 11 checks that your VKS
cluster can pull from it). Then pick one: the full guide (podman or docker, every OS) or the short
docker-on-Linux version.

| guide | what it is |
|---|---|
| [Build a container image, push it to a registry and run it in a VKS cluster](IMAGE.md) | a test app built with podman or docker, pushed to a Harbor project, and run in a VKS cluster from there |
| [Build a container image with docker, push it and run it (short version)](IMAGE-DOCKER.md) | the same with docker on Linux only, in the fewest commands, for a public or a private project |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1), on amd64 machines:

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Build a container image, push it to a registry and run it in a VKS cluster](IMAGE.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Build a container image with docker, push it and run it (short version)](IMAGE-DOCKER.md) | ✅ | — | — | — | — | ✅ |

Not run with these versions: macOS, Debian, Windows 10 and 11, Arm machines.

Back to [README](../README.md).
