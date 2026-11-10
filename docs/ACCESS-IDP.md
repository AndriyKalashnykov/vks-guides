# Grant an identity provider group access to VKS clusters, through the Supervisor

## Who are you? Start here

| you | read |
|---|---|
| You administer vCenter or the Supervisor and log in yourself | [Log in to the Supervisor and a VKS cluster](SUPERVISOR-LOGIN.md) |
| You give people or tools access to a VKS cluster | [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md), starting at [which way for which customer](ADMIN-GRANT-ACCESS.md#which-way-for-which-customer); for a group in your organization's identity provider, [Give an identity provider group access to VKS clusters](ADMIN-GRANT-ACCESS-IDP.md) |
| You have your own vCenter SSO account and were given access | [Log in to a VKS cluster you were given access to](USER-LOGIN.md) |
| An administrator sent you a kubeconfig file | [See what the file holds](KUBECONFIG.md#1-see-what-a-file-holds) and [use it](KUBECONFIG.md#2-use-a-file); the step for your kind of file: a [ServiceAccount token](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-cluster-administrator-then-the-team-or-tool), an [administrator token](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-on-another-machine-cluster-administrator-then-the-tool-or-person), a [personal certificate](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-cluster-administrator-then-the-person) |
| You sign in with your organization's identity provider | through the Supervisor: [log in](ADMIN-GRANT-ACCESS-IDP.md#5-log-in-the-person) and [log out](ADMIN-GRANT-ACCESS-IDP.md#6-log-out-the-person); on one cluster that trusts it directly: [log in](KEYCLOAK.md#4-log-in-the-person) and [log out](KEYCLOAK.md#5-log-out-the-person) |

Every access and sign-in guide: [Identity and access](ACCESS-SIGN-IN.md).

## Where the old guide went

This guide moved to [ADMIN-GRANT-ACCESS-IDP.md](ADMIN-GRANT-ACCESS-IDP.md). Its sections:

- [Prerequisites](ADMIN-GRANT-ACCESS-IDP.md#prerequisites)
- [1. Read the provider name and prefix (vCenter administrator)](ADMIN-GRANT-ACCESS-IDP.md#1-read-the-provider-name-and-prefix-vcenter-administrator)
- [2. Give the group a role on the vSphere Namespace (vCenter administrator)](ADMIN-GRANT-ACCESS-IDP.md#2-give-the-group-a-role-on-the-vsphere-namespace-vcenter-administrator)
- [3. Give the group rights inside the VKS cluster (cluster administrator)](ADMIN-GRANT-ACCESS-IDP.md#3-give-the-group-rights-inside-the-vks-cluster-cluster-administrator)
- [4. Make the group's kubeconfig and hand it over (cluster administrator)](ADMIN-GRANT-ACCESS-IDP.md#4-make-the-groups-kubeconfig-and-hand-it-over-cluster-administrator)
- [5. Log in (the person)](ADMIN-GRANT-ACCESS-IDP.md#5-log-in-the-person)
- [6. Log out (the person)](ADMIN-GRANT-ACCESS-IDP.md#6-log-out-the-person)
- [7. Take one person's access away (identity provider's administrator)](ADMIN-GRANT-ACCESS-IDP.md#7-take-one-persons-access-away-identity-providers-administrator)
- [8. Take the group's access away (cluster administrator, vCenter administrator)](ADMIN-GRANT-ACCESS-IDP.md#8-take-the-groups-access-away-cluster-administrator-vcenter-administrator)
