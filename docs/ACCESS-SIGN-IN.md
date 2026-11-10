# Identity and access

These need a VKS cluster ([vSphere Namespaces and VKS clusters](CLUSTERS.md)) and its
administrator kubeconfig ([SUPERVISOR-LOGIN.md, VKS cluster](SUPERVISOR-LOGIN.md#vks-cluster)); the people you give access use one
of three guides: [USER-LOGIN.md](USER-LOGIN.md) (their own SSO account),
[USER-KUBECONFIG.md](USER-KUBECONFIG.md) (a file you sent, with a token or a certificate) or
[USER-IDP-LOGIN.md](USER-IDP-LOGIN.md) (an identity provider group). Single sign-on uses an external identity provider:
any OpenID Connect (OIDC) provider your organization runs. These guides use Keycloak as the example
provider; without one, run it first ([Run an OIDC identity provider](KEYCLOAK-VKS.md)). For sign-in
through the Supervisor, register it there ([its step 11](KEYCLOAK-VKS.md#11-register-keycloak-with-the-supervisor-optional)) before
[ADMIN-GRANT-ACCESS-IDP.md](ADMIN-GRANT-ACCESS-IDP.md).

Not sure which way fits your customer? The picture in
[Which way for which customer](ADMIN-GRANT-ACCESS.md#which-way-for-which-customer) picks it.

| guide | what it is |
|---|---|
| [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md) | which way for which customer, and how to give a person, team or tool access to a VKS cluster and take it away: their vCenter SSO account, a ServiceAccount token or a personal certificate (each for one namespace or the whole cluster) |
| [Give an identity provider group access to VKS clusters, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md) | a group from the external identity provider signs in to every VKS cluster of the Supervisor with a browser; one kubeconfig with no secret for the whole group |
| [Run an OIDC identity provider in a VKS cluster](KEYCLOAK-VKS.md) | the example provider (Keycloak with PostgreSQL) in its own VKS cluster, with a certificate, a DNS name, a realm for VKS sign-ins, users and groups, and its registration on the Supervisor (step 11) |
| [OIDC sign-in on one VKS cluster, without the Supervisor](KEYCLOAK.md) | a VKS cluster created to trust the identity provider directly; people need only kubectl and kubelogin |

## Tested on

Where each guide in this group was run, on which OS and with which versions: [Tested on](TESTED.md#identity-and-access).

Back to [README](../README.md).
