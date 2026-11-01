# Access and sign-in

These need a VKS cluster ([Namespaces and clusters](CLUSTERS.md)) and its administrator kubeconfig
([Log in](LOGIN.md)). Run Keycloak in a VKS cluster comes before either Keycloak way.

| guide | what it is |
|---|---|
| [Give a person or team access to a VKS cluster](ACCESS.md) | a ServiceAccount token, a personal certificate, the person's own SSO account, or a Keycloak group through the Supervisor |
| [Run Keycloak in a VKS cluster](KEYCLOAK-VKS.md) | Keycloak with PostgreSQL in its own VKS cluster, with a certificate, a name, a realm for VKS logins and the people in it |
| [Log in to a VKS cluster with Keycloak](KEYCLOAK.md) | a person's Keycloak user on a VKS cluster made for it, with only kubectl and kubelogin on their machine |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1):

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows PowerShell 5.1 | WSL 2 Ubuntu (bash, as root) |
|---|---|---|---|---|---|---|
| [Give access](ACCESS.md) | part | part | part | — | part | part |
| [Run Keycloak in a VKS cluster](KEYCLOAK-VKS.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Log in with Keycloak](KEYCLOAK.md) | ✅ | — | part | — | ✅ | — |

Back to [README](../README.md).
