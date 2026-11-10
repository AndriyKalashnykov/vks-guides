# Container images

A container image is a packaged app that a VKS cluster runs, a bit like a VM template for one
program. A registry stores the images, and the cluster downloads them from it. The guides use
Harbor, Broadcom's supported registry, as the example; another OCI registry works the same way.

Before either guide, Harbor must be installed and checked: [HARBOR.md](HARBOR.md) steps 1 to 11,
done by you or your Harbor administrator (step 11 checks that your VKS cluster can pull from it). Then pick one: the full guide (podman or docker, every OS) or the short
docker-on-Linux version.

| guide | what it is |
|---|---|
| [Build a container image, push it to a registry and run it in a VKS cluster](IMAGE.md) | a test app built with podman or docker, pushed to a Harbor project, and run in a VKS cluster from there |
| [Build a container image with docker, push it and run it (short version)](IMAGE-DOCKER.md) | the same with docker on Linux only, in the fewest commands, for a public or a private project |

## Tested on

Where each guide in this group was run, on which OS and with which versions: [Tested on](TESTED.md#container-images).

Back to [README](../README.md).
