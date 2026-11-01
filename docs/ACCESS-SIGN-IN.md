# Access and sign-in

These need a VKS cluster ([Namespaces and clusters](CLUSTERS.md)) and its administrator kubeconfig
([Log in](LOGIN.md)). Single sign-on uses an external identity provider: any OpenID Connect
(OIDC) provider your organization runs. These guides use Keycloak as the example provider; without
one, run it first ([Run an OIDC identity provider](KEYCLOAK-VKS.md)).

| guide | what it is |
|---|---|
| [Identity and access for VKS clusters](ACCESS.md) | the ways to give a person, team or tool access to a VKS cluster: a ServiceAccount token, a client certificate, a vCenter SSO account, or a group from the external identity provider through the Supervisor |
| [Run an OIDC identity provider in a VKS cluster](KEYCLOAK-VKS.md) | the example provider (Keycloak with PostgreSQL) in its own VKS cluster, with a certificate, a DNS name, a realm for VKS sign-ins, users and groups |
| [OIDC sign-in on one VKS cluster, without the Supervisor](KEYCLOAK.md) | a VKS cluster created to trust the identity provider directly; people need only kubectl and kubelogin |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1):

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows PowerShell 5.1 | WSL 2 Ubuntu (bash, as root) |
|---|---|---|---|---|---|---|
| [Identity and access for VKS clusters](ACCESS.md) | part | part | part | — | part | part |
| [Run an OIDC identity provider in a VKS cluster](KEYCLOAK-VKS.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [OIDC sign-in on one VKS cluster, without the Supervisor](KEYCLOAK.md) | ✅ | — | part | — | ✅ | — |

Back to [README](../README.md).
