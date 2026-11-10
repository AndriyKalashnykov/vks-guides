# Grant an identity provider group access to VKS clusters, through the Supervisor

## Who are you? Start here

| you | read |
|---|---|
| You administer vCenter, or have **Can edit** or **Owner** on a vSphere Namespace, and log in yourself | [Log in to the Supervisor and a VKS cluster](SUPERVISOR-LOGIN.md) |
| You give people or tools access to a VKS cluster | [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md), starting at [which way for which customer](ADMIN-GRANT-ACCESS.md#which-way-for-which-customer), whose table also names the page to send each person; for a group in your organization's identity provider, [Give an identity provider group access to VKS clusters](ADMIN-GRANT-ACCESS-IDP.md) |
| You have your own vCenter SSO account and were given access | [Log in to a VKS cluster you were given access to](USER-LOGIN.md) |
| An administrator sent you a kubeconfig file | [Use a kubeconfig file you were given](USER-KUBECONFIG.md) (a token or a certificate); a file that runs `vcf` or `kubectl` to sign in (no secret in it): the identity provider row below |
| You sign in with your organization's identity provider | [Sign in with your organization's identity provider](USER-IDP-LOGIN.md): through the Supervisor (part A) or on one cluster that trusts it directly (part B); its [step 1](USER-IDP-LOGIN.md#1-which-file-you-have) says which |
| A tool or pipeline was given a token file | [Use a kubeconfig file you were given](USER-KUBECONFIG.md), and its [CI pipeline](USER-KUBECONFIG.md#a-ci-pipeline) section |

## Where the old guide went

This guide moved to [ADMIN-GRANT-ACCESS-IDP.md](ADMIN-GRANT-ACCESS-IDP.md). Its sections:

- [Prerequisites](ADMIN-GRANT-ACCESS-IDP.md#prerequisites)
- [1. Read the provider name and prefix (vCenter administrator)](ADMIN-GRANT-ACCESS-IDP.md#1-read-the-provider-name-and-prefix-vcenter-administrator)
- [2. Give the group a role on the vSphere Namespace (vCenter administrator)](ADMIN-GRANT-ACCESS-IDP.md#2-give-the-group-a-role-on-the-vsphere-namespace-vcenter-administrator)
- [3. Give the group rights inside the VKS cluster (cluster administrator)](ADMIN-GRANT-ACCESS-IDP.md#3-give-the-group-rights-inside-the-vks-cluster-cluster-administrator)
- [4. Make the group's kubeconfig and hand it over (cluster administrator)](ADMIN-GRANT-ACCESS-IDP.md#4-make-the-groups-kubeconfig-and-hand-it-over-cluster-administrator)
- [5. Log in (the person)](USER-IDP-LOGIN.md#3-sign-in-through-the-supervisor)
- [6. Log out (the person)](USER-IDP-LOGIN.md#4-log-out-part-a)
- [7. Take one person's access away (identity provider's administrator)](ADMIN-GRANT-ACCESS-IDP.md#7-take-one-persons-access-away-identity-providers-administrator)
- [8. Take the group's access away (cluster administrator, vCenter administrator)](ADMIN-GRANT-ACCESS-IDP.md#8-take-the-groups-access-away-cluster-administrator-vcenter-administrator)
