# Log in to the Supervisor and a VKS cluster

## Who are you? Start here

| you | read |
|---|---|
| You administer vCenter, or have **Can edit** or **Owner** on a vSphere Namespace, and log in yourself | [Log in to the Supervisor and a VKS cluster](SUPERVISOR-LOGIN.md) |
| You give people or tools access to a VKS cluster | [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md), starting at [which way for which customer](ADMIN-GRANT-ACCESS.md#which-way-for-which-customer); for a group in your organization's identity provider, [Give an identity provider group access to VKS clusters](ADMIN-GRANT-ACCESS-IDP.md) |
| You have your own vCenter SSO account and were given access | [Log in to a VKS cluster you were given access to](USER-LOGIN.md) |
| An administrator sent you a kubeconfig file | [See what the file holds](KUBECONFIG.md#1-see-what-a-file-holds) and [use it](KUBECONFIG.md#2-use-a-file); the step for your kind of file: a [ServiceAccount token](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-cluster-administrator-then-the-team-or-tool), a token for the whole cluster ([administrator token](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-on-another-machine-cluster-administrator-then-the-tool-or-person); ask your administrator if you are not sure), a [personal certificate](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-cluster-administrator-then-the-person); a file that runs `vcf` or `kubectl` to sign in (no secret in it): the identity provider row below |
| You sign in with your organization's identity provider | through the Supervisor: [log in](ADMIN-GRANT-ACCESS-IDP.md#5-log-in-the-person) and [log out](ADMIN-GRANT-ACCESS-IDP.md#6-log-out-the-person); on one cluster that trusts it directly: [log in](KEYCLOAK.md#4-log-in-the-person) and [log out](KEYCLOAK.md#5-log-out-the-person) |

## Where the old guide went

This guide moved to [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md). Its sections:

- [Prerequisites](SUPERVISOR-LOGIN.md#prerequisites)
- [Create Supervisor context with CA](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca)
- [Create Supervisor context without CA](SUPERVISOR-LOGIN.md#create-supervisor-context-without-ca)
  - [Alternative: trust the Supervisor's own certificate](SUPERVISOR-LOGIN.md#alternative-trust-the-supervisors-own-certificate)
- [Check your vSphere Namespace](SUPERVISOR-LOGIN.md#check-your-vsphere-namespace)
- [Download the VKS cluster's kubeconfig from the vSphere Client](SUPERVISOR-LOGIN.md#download-the-vks-clusters-kubeconfig-from-the-vsphere-client)
- [Get the VKS cluster's kubeconfig](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig)
- [Use the VKS cluster](SUPERVISOR-LOGIN.md#use-the-vks-cluster)
  - [Make it the default in this terminal](SUPERVISOR-LOGIN.md#make-it-the-default-in-this-terminal)
  - [Name the kubeconfig in each command](SUPERVISOR-LOGIN.md#name-the-kubeconfig-in-each-command)
- [Match kubectl to the cluster's version (optional)](SUPERVISOR-LOGIN.md#match-kubectl-to-the-clusters-version-optional)
- [Access for other people (optional)](SUPERVISOR-LOGIN.md#access-for-other-people-optional)
- [Renew the Supervisor login](SUPERVISOR-LOGIN.md#renew-the-supervisor-login)
- [Log out](SUPERVISOR-LOGIN.md#log-out)
