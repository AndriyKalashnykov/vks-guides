# Identity and access

These need a VKS cluster ([vSphere Namespaces and VKS clusters](CLUSTERS.md)) and its
administrator kubeconfig ([SUPERVISOR-LOGIN.md, VKS cluster](SUPERVISOR-LOGIN.md#vks-cluster)); the people you give access log in with
[USER-LOGIN.md](USER-LOGIN.md). Single sign-on uses an external identity provider:
any OpenID Connect (OIDC) provider your organization runs. These guides use Keycloak as the example
provider; without one, run it first ([Run an OIDC identity provider](KEYCLOAK-VKS.md)). For sign-in
through the Supervisor, register it there ([its step 11](KEYCLOAK-VKS.md#11-register-keycloak-with-the-supervisor-optional)) before
[ADMIN-GRANT-ACCESS-IDP.md](ADMIN-GRANT-ACCESS-IDP.md).

| guide | what it is |
|---|---|
| [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md) | which way for which customer, and how to give a person, team or tool access to a VKS cluster and take it away: their vCenter SSO account, a ServiceAccount token (one namespace or the whole cluster), or a personal certificate |
| [Give an identity provider group access to VKS clusters, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md) | a group from the external identity provider signs in to every VKS cluster of the Supervisor with a browser; one kubeconfig with no secret for the whole group |
| [Run an OIDC identity provider in a VKS cluster](KEYCLOAK-VKS.md) | the example provider (Keycloak with PostgreSQL) in its own VKS cluster, with a certificate, a DNS name, a realm for VKS sign-ins, users and groups, and its registration on the Supervisor (step 11) |
| [OIDC sign-in on one VKS cluster, without the Supervisor](KEYCLOAK.md) | a VKS cluster created to trust the identity provider directly; people need only kubectl and kubelogin |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1), on amd64 machines:

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows Server 2025 (PowerShell 5.1) | WSL 2 Ubuntu on Windows Server 2025 (bash, as root) |
|---|---|---|---|---|---|---|
| [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md) | part | part | part | — | part | part |
| [Give an identity provider group access to VKS clusters, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md) | part | — | — | — | — | — |
| [Run an OIDC identity provider in a VKS cluster](KEYCLOAK-VKS.md) | part | part | part | — | part | part |
| [OIDC sign-in on one VKS cluster, without the Supervisor](KEYCLOAK.md) | ✅ | — | part | — | ✅ | — |

Not run with these versions: macOS, Debian, Windows 10 and 11, Arm machines.

Back to [README](../README.md).
