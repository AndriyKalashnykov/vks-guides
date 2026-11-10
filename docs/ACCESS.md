# Grant access to VKS clusters

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

This guide moved: the administrator's part to [ADMIN-GRANT-ACCESS.md](ADMIN-GRANT-ACCESS.md), the
person's login to [USER-LOGIN.md](USER-LOGIN.md). Its sections:

- [Prerequisites](ADMIN-GRANT-ACCESS.md#prerequisites)
- [The person's own SSO account](ADMIN-GRANT-ACCESS.md#the-persons-own-sso-account)
  - [1. Give the person a role on the vSphere Namespace (vCenter administrator)](ADMIN-GRANT-ACCESS.md#1-give-the-person-a-role-on-the-vsphere-namespace-vcenter-administrator)
  - [2. Give the person rights inside the cluster (cluster administrator)](ADMIN-GRANT-ACCESS.md#2-give-the-person-rights-inside-the-cluster-cluster-administrator)
  - [3. Log in with the VCF CLI (the person)](USER-LOGIN.md#2-log-in-with-the-vcf-cli)
  - [4. Use the login (the person)](USER-LOGIN.md#3-use-the-login)
  - [5. Take it away (cluster administrator, vCenter administrator)](ADMIN-GRANT-ACCESS.md#5-take-it-away-cluster-administrator-vcenter-administrator)
- [The kubectl vSphere plugin instead of the VCF CLI (optional and deprecated)](USER-LOGIN.md#the-kubectl-vsphere-plugin-instead-of-the-vcf-cli-optional-and-deprecated)
  - [1. Windows and macOS: trust the vCenter CA (the person, once)](USER-LOGIN.md#1-windows-and-macos-trust-the-vcenter-ca-the-person-once)
  - [2. Install the kubectl vSphere plugin (the person, once)](USER-LOGIN.md#2-install-the-kubectl-vsphere-plugin-the-person-once)
  - [3. Log in with the plugin (the person)](USER-LOGIN.md#3-log-in-with-the-plugin-the-person)
- [A ServiceAccount token](ADMIN-GRANT-ACCESS.md#a-serviceaccount-token)
  - [1. Make the ServiceAccount token and its file (cluster administrator)](ADMIN-GRANT-ACCESS.md#1-make-the-serviceaccount-token-and-its-file-cluster-administrator)
  - [2. Hand it over and use it (cluster administrator, then the team or tool)](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-cluster-administrator-then-the-team-or-tool)
  - [3. Renew the ServiceAccount token (cluster administrator)](ADMIN-GRANT-ACCESS.md#3-renew-the-serviceaccount-token-cluster-administrator)
  - [4. Take the ServiceAccount token away (cluster administrator)](ADMIN-GRANT-ACCESS.md#4-take-the-serviceaccount-token-away-cluster-administrator)
- [An administrator ServiceAccount token (whole cluster)](ADMIN-GRANT-ACCESS.md#an-administrator-serviceaccount-token-whole-cluster)
  - [1. Make the administrator token and its file (cluster administrator)](ADMIN-GRANT-ACCESS.md#1-make-the-administrator-token-and-its-file-cluster-administrator)
  - [2. Hand it over and use it on another machine (cluster administrator, then the tool or person)](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-on-another-machine-cluster-administrator-then-the-tool-or-person)
  - [3. Renew the administrator token (cluster administrator)](ADMIN-GRANT-ACCESS.md#3-renew-the-administrator-token-cluster-administrator)
  - [4. Take the administrator token away (cluster administrator)](ADMIN-GRANT-ACCESS.md#4-take-the-administrator-token-away-cluster-administrator)
- [A personal certificate](ADMIN-GRANT-ACCESS.md#a-personal-certificate)
  - [1. Make the certificate and its file (cluster administrator)](ADMIN-GRANT-ACCESS.md#1-make-the-certificate-and-its-file-cluster-administrator)
  - [2. Hand it over and use it (cluster administrator, then the person)](ADMIN-GRANT-ACCESS.md#2-hand-it-over-and-use-it-cluster-administrator-then-the-person)
  - [3. Renew the certificate (cluster administrator)](ADMIN-GRANT-ACCESS.md#3-renew-the-certificate-cluster-administrator)
  - [4. Take the certificate away (cluster administrator)](ADMIN-GRANT-ACCESS.md#4-take-the-certificate-away-cluster-administrator)
