# Log in to the Supervisor and a VKS cluster

## Who are you? Start here

| you | read |
|---|---|
| You administer vCenter, or have **Can edit** or **Owner** on a vSphere Namespace, and log in yourself | [Log in to the Supervisor and a VKS cluster](SUPERVISOR-LOGIN.md) |
| You give people or tools access to a VKS cluster | [Give people and tools access to a VKS cluster](ADMIN-GRANT-ACCESS.md), starting at [which way for which customer](ADMIN-GRANT-ACCESS.md#which-way-for-which-customer); for a group in your organization's identity provider, [Give an identity provider group access to VKS clusters](ADMIN-GRANT-ACCESS-IDP.md) |
| You have your own vCenter SSO account and were given access | [Log in to a VKS cluster you were given access to](USER-LOGIN.md) |
| An administrator sent you a kubeconfig file | [Use a kubeconfig file you were given](USER-KUBECONFIG.md) (a token or a certificate); a file that runs `vcf` or `kubectl` to sign in (no secret in it): the identity provider row below |
| You sign in with your organization's identity provider | [Sign in with your organization's identity provider](USER-IDP-LOGIN.md): through the Supervisor (part A) or on one cluster that trusts it directly (part B); its [step 1](USER-IDP-LOGIN.md#1-which-file-you-have) says which |
| A tool or pipeline was given a token file | [Use a kubeconfig file you were given](USER-KUBECONFIG.md), and its [CI pipeline](USER-KUBECONFIG.md#a-ci-pipeline) section |

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
