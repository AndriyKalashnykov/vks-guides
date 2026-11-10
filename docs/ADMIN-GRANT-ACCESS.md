# Give people and tools access to a VKS cluster

Your internal customers (application developers, testers, DevOps engineers and their pipelines)
work in a VKS cluster with kubectl, the Kubernetes command-line tool. This guide gives each of them
their own access, with only the rights they need, so that you never send the cluster's
administrator kubeconfig and can take each access away on its own.

Words like *vSphere Namespace*, *ServiceAccount* and *RoleBinding* are explained in the
[Glossary](GLOSSARY.md).

<a id="which-way-for-which-customer"></a>

**Which way for which customer:**

| your customer | the way | why this way | page to send them |
|---|---|---|---|
| a developer, tester or DevOps engineer with a vCenter SSO account | [The person's own SSO account](#the-persons-own-sso-account) | they log in as themselves; you send no secret; you take it away in vCenter and the cluster | [USER-LOGIN.md](USER-LOGIN.md) |
| people in your organization's identity provider (Keycloak in this guide) with no vCenter account | [A group from an external identity provider, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md) (its own guide) | you give rights once, to a group; the identity provider decides who is in it; one file with no secret serves the whole group | [USER-IDP-LOGIN.md](USER-IDP-LOGIN.md): steps 1 and 2, then part A ([step 3](USER-IDP-LOGIN.md#3-sign-in-through-the-supervisor)) |
| a CI pipeline, a deployment tool, or a team that shares one login, in one namespace (or, with `"*"`, the whole cluster) | [A ServiceAccount token](#a-serviceaccount-token) | no person's account; works unattended for the days you set; deleting it stops every copy | a team: [USER-KUBECONFIG.md](USER-KUBECONFIG.md); a tool: [USER-KUBECONFIG.md, A CI pipeline](USER-KUBECONFIG.md#a-ci-pipeline); with `"*"` and `edit`, also [step 5](USER-KUBECONFIG.md#5-check-that-a-whole-cluster-file-can-change-things-whole-cluster-file-only) |
| a tool or a person that needs the whole cluster | [An administrator ServiceAccount token (whole cluster)](#an-administrator-serviceaccount-token-whole-cluster) | send it instead of the administrator kubeconfig: this one can be taken away | [USER-KUBECONFIG.md](USER-KUBECONFIG.md), with [step 5](USER-KUBECONFIG.md#5-check-that-a-whole-cluster-file-can-change-things-whole-cluster-file-only) |
| one person with no SSO or identity provider account, for a limited time | [A personal certificate](#a-personal-certificate) | needs nothing but kubectl; it cannot be withdrawn before it ends, so keep `DAYS` as short as the work allows | [USER-KUBECONFIG.md](USER-KUBECONFIG.md) |
| people in an identity provider that is not registered on the Supervisor | [An external identity provider on one cluster](KEYCLOAK.md) (its own guide) | a new cluster (VKS 3.8) is created to trust the provider; people need kubectl and kubelogin | [USER-IDP-LOGIN.md](USER-IDP-LOGIN.md): steps 1 and 2, then part B ([step 5](USER-IDP-LOGIN.md#5-sign-in-with-kubelogin)) |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/access/which-way-in-dark.svg">
  <img src="img/access/which-way-in-light.svg" width="1200" alt="A chart for vCenter administrators that picks the way to give someone access to a VKS cluster. Find the row that fits. 1: a tool or a person that must be able to do everything in the cluster gets an administrator token. 2: a pipeline, a tool or a team sharing one login in one namespace gets a ServiceAccount token. 3: a person with a vCenter SSO account uses their own account. 4: people in an identity provider registered on the Supervisor use their group through the Supervisor. 5: people in a provider that is not registered use the provider on one new cluster (a dashed row). 6: one person with no SSO or identity provider account, for a limited time, gets a personal certificate; deleting its binding stops its rights, but the certificate itself cannot be withdrawn. 7: never send the cluster&#x27;s built-in administrator file; send the row 1 token only if they need everything. Each row shows who sets it up, what the person installs, how long it lasts, how it is taken away and what you send. A band at the top warns that Can edit or Owner on the vSphere Namespace makes someone administrator of every VKS cluster in it and lets them download the file you never send, and that logins they made keep working when the role goes; rows 3 and 4 need a role from you, row 5 a new cluster. A strip explains one namespace versus the whole cluster, where edit gives cluster-admin and view read-only access to every namespace. Footnotes and a legend explain how each way is taken away.">
</picture>

These ways give access to the cluster through kubectl. Add-ons with a web page have their own
sign-in: Headlamp takes the person's SSO login or a token
([HEADLAMP.md steps 6 to 8](HEADLAMP.md#6-log-in-with-your-own-sso-user)); ArgoCD, Harbor and
Grafana have their own sign-in; their guides set up only the `admin` user
([ARGOCD.md step 4](ARGOCD.md#4-log-in-to-the-argocd-web-page),
[HARBOR.md step 9](HARBOR.md#9-save-harbors-ca-and-log-in),
[MONITORING.md step 3](MONITORING.md#3-set-grafanas-admin-password)). For tools, Harbor has robot
accounts ([HARBOR.md step 10](HARBOR.md#10-create-a-project-and-a-robot-account)).

Who does what:

| role | who it is | does here |
|---|---|---|
| cluster administrator | holds the VKS cluster's administrator kubeconfig ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#vks-cluster)) | gives rights inside the cluster, makes the files and sends them |
| vCenter administrator | administers vCenter and the Supervisor | gives roles on the vSphere Namespace |
| the person | gets the access | logs in ([USER-LOGIN.md](USER-LOGIN.md)), signs in with an identity provider ([USER-IDP-LOGIN.md](USER-IDP-LOGIN.md)), or uses the file they were sent ([USER-KUBECONFIG.md](USER-KUBECONFIG.md)) |
| a tool | a CI/CD pipeline, a deployment tool or a script, with no person behind it | uses the token file it was given ([USER-KUBECONFIG.md](USER-KUBECONFIG.md#a-ci-pipeline)); makes no login of its own and never renews; the cluster administrator renews the file before it ends |

**The ways:**

- [Their own SSO account](#the-persons-own-sso-account): [role](#1-give-the-person-a-role-on-the-vsphere-namespace-vcenter-administrator) → [rights](#2-give-the-person-rights-inside-the-cluster-cluster-administrator) → they [log in](#3-log-in-with-the-vcf-cli-the-person) → [take away](#5-take-it-away-cluster-administrator-vcenter-administrator)
- [A group from an identity provider](ADMIN-GRANT-ACCESS-IDP.md) (its own guide): [provider name](ADMIN-GRANT-ACCESS-IDP.md#1-read-the-provider-name-and-prefix-vcenter-administrator) → [role](ADMIN-GRANT-ACCESS-IDP.md#2-give-the-group-a-role-on-the-vsphere-namespace-vcenter-administrator) → [rights](ADMIN-GRANT-ACCESS-IDP.md#3-give-the-group-rights-inside-the-vks-cluster-cluster-administrator) → [kubeconfig](ADMIN-GRANT-ACCESS-IDP.md#4-make-the-groups-kubeconfig-and-hand-it-over-cluster-administrator) → they [sign in](USER-IDP-LOGIN.md#1-which-file-you-have) → [take away](ADMIN-GRANT-ACCESS-IDP.md#8-take-the-groups-access-away-cluster-administrator-vcenter-administrator)
- [A ServiceAccount token](#a-serviceaccount-token): [make](#1-make-the-serviceaccount-token-and-its-file-cluster-administrator) → [hand over](#2-hand-it-over-and-use-it-cluster-administrator-then-the-team-or-tool) → [renew](#3-renew-the-serviceaccount-token-cluster-administrator) → [take away](#4-take-the-serviceaccount-token-away-cluster-administrator)
- [An administrator token (whole cluster)](#an-administrator-serviceaccount-token-whole-cluster): [make](#1-make-the-administrator-token-and-its-file-cluster-administrator) → [hand over](#2-hand-it-over-and-use-it-on-another-machine-cluster-administrator-then-the-tool-or-person) → [renew](#3-renew-the-administrator-token-cluster-administrator) → [take away](#4-take-the-administrator-token-away-cluster-administrator)
- [A personal certificate](#a-personal-certificate): [make](#1-make-the-certificate-and-its-file-cluster-administrator) → [hand over](#2-hand-it-over-and-use-it-cluster-administrator-then-the-person) → [renew](#3-renew-the-certificate-cluster-administrator) → [take away](#4-take-the-certificate-away-cluster-administrator)

Compare the ways:

| way | set up by | they need | lasts | to take it away |
|---|---|---|---|---|
| [The person's own SSO account](#the-persons-own-sso-account) | the vCenter administrator, then the cluster administrator | kubectl, and the VCF CLI or the kubectl vSphere plugin | 10 hours per login | delete the person's RoleBinding and their role on the vSphere Namespace; with `edit`, ServiceAccount tokens and workloads they made keep working: delete the workloads, re-create ServiceAccounts with rights, restart what uses them; with **Can edit** or **Owner**: also logins they made |
| [A group from an external identity provider, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md) (its own guide) | the identity provider's, vCenter and cluster administrators | kubectl and the VCF CLI | while the person's sign-in lasts | disable the user in the identity provider, or delete the group's RoleBinding (with `"*"`: its ClusterRoleBinding) and its role on the vSphere Namespace; with `edit`, ServiceAccount tokens and workloads members made keep working: delete the workloads, re-create ServiceAccounts with rights, restart what uses them; with `"*"` and `edit`, or **Can edit**: also logins they made |
| [A ServiceAccount token](#a-serviceaccount-token) | the cluster administrator | kubectl | the days you set | delete the ServiceAccount: every copy stops (with `"*"`: also its ClusterRoleBinding; with `"*"` and `edit`, not logins the holder made); with `edit`, tokens and workloads the team made keep working: delete the workloads, re-create ServiceAccounts with rights, restart what uses them |
| [An administrator ServiceAccount token (whole cluster)](#an-administrator-serviceaccount-token-whole-cluster) | the cluster administrator | kubectl | the days you set (365 for a year), or until you take it away | delete its ClusterRoleBinding, token Secret and ServiceAccount: every copy stops (not logins the holder made) |
| [A personal certificate](#a-personal-certificate) | the cluster administrator | kubectl | the days you set | cannot be withdrawn: delete its RoleBinding (with `"*"`: ClusterRoleBinding) and never bind its name again; with `edit`, ServiceAccount tokens and workloads they made keep working: delete the workloads, re-create ServiceAccounts with rights, restart what uses them; with `"*"` and `edit`: also logins they made |
| [An external identity provider on one cluster](KEYCLOAK.md) (its own guide) | the identity provider's and cluster administrators | kubectl and kubelogin | while the person's sign-in lasts | delete the group's RoleBinding; with `edit`, ServiceAccount tokens and workloads members made keep working: delete the workloads, re-create ServiceAccounts with rights, restart what uses them |

The SSO way hands out no kubeconfig: the person's login writes their own. The group way hands out a file
with no secret, which only tells kubectl where to sign in. The two ServiceAccount ways and the
personal certificate hand out a file that works for whoever holds a copy. Which file holds what,
how to hand it over, use and merge it: [KUBECONFIG.md](KUBECONFIG.md).

## Prerequisites

- cluster administrator: the VKS cluster's administrator kubeconfig
  ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig)) and [kubectl](KUBECTL.md); for a personal
  certificate also openssl ([PREREQS.md](PREREQS.md); on Windows, run it in WSL);
- vCenter administrator (SSO way): the vCenter CA
  ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca), step 1);
- the person or tool: [kubectl](KUBECTL.md) (every way); for the SSO way, what
  [USER-LOGIN.md](USER-LOGIN.md#prerequisites) lists; for a file you send, what
  [USER-KUBECONFIG.md](USER-KUBECONFIG.md#prerequisites) lists.

The connections this guide needs, for a firewall (all TCP, besides DNS):

| from | to | port | for |
|---|---|---|---|
| the cluster administrator's machine | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl as the cluster's administrator (every way) |
| the person's or tool's machine | the VKS cluster's API address | 6443 | kubectl with the file you sent (the token and certificate ways) |

For the SSO way, the person's connections are in [USER-LOGIN.md](USER-LOGIN.md#prerequisites).

## The person's own SSO account

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/access/way-sso-dark.svg">
  <img src="img/access/way-sso-light.svg" width="1200" alt="The person&#x27;s own SSO account: the vCenter administrator gives the person&#x27;s SSO user Can view on the vSphere Namespace, which lets them log in, and the cluster administrator gives that name edit in one namespace inside the VKS cluster; the person logs in with the VCF CLI, which writes their own kubeconfig, so no secret is sent. Taking it away deletes the RoleBinding, which stops it at once, and removes the role in vCenter; if the person still has rights, they have them through a group with Can edit or Owner, and logins they made as an administrator keep working.">
</picture>

Pick this for people who have a vCenter SSO account. They log in as themselves with the VCF CLI,
and the login writes their own kubeconfig: you send them names and the vCenter CA, not a
kubeconfig. The vCenter administrator lets them log in (step 1), the cluster administrator gives
them rights inside the cluster (step 2), then the person logs in (step 3) and uses the cluster
(step 4) with [USER-LOGIN.md](USER-LOGIN.md). A login lasts 10 hours. Without the VCF CLI, people
log in with the kubectl vSphere plugin instead
([USER-LOGIN.md](USER-LOGIN.md#the-kubectl-vsphere-plugin-instead-of-the-vcf-cli-optional-and-deprecated)).

### 1. Give the person a role on the vSphere Namespace (vCenter administrator)

Give the person's SSO user the **Can view** role (**Namespaces View**) on the vSphere Namespace
([NAMESPACE.md](NAMESPACE.md#4-give-users-a-role) step 4). Not **Can edit** or **Owner**: those make them an
administrator of every VKS cluster in the namespace. Then send the person the Supervisor's
address, the vSphere Namespace's and the cluster's names, and the vCenter CA file
([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca), step 1), and send the cluster
administrator the person's SSO user name exactly as vCenter lists it, letter case included
(step 2).

### 2. Give the person rights inside the cluster (cluster administrator)

Do this before the person logs in: the role from step 1 lets them log in, but gives no rights
inside the VKS cluster. It makes the namespace `VKS_CLUSTER_NAMESPACE` inside the VKS cluster (a
folder for the team's workloads, not the vSphere Namespace) if it is not there, and a RoleBinding
(the record that gives a name a role in one namespace) that gives the name `edit`: create, change
and delete most things in it. The person can then deploy in that namespace: send them its name
([USER-LOGIN.md step 3](USER-LOGIN.md#3-use-the-login)). Run it once per person; for the same name again it answers `already exists`.

Set `VKS_CLUSTER` to the cluster's name (`ADMIN_KUBECONFIG` is then its administrator kubeconfig
from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig); change it if you saved that file
elsewhere), `VKS_CLUSTER_NAMESPACE` to the team's namespace (one namespace: an empty value or `"*"` stops
the block; with their SSO account, a person gets the whole cluster only from **Can edit** on the vSphere Namespace, which makes
them administrator of every VKS cluster in it, so step 1 does not give it), and `SSO_USER` to the person's SSO user
name exactly as vCenter lists it, letter case included: logins ignore letter case, the cluster does
not (vCenter's own `administrator@vsphere.local` is `sso:Administrator@vsphere.local` there), and
a name in other letter case gets no rights.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SSO_USER="Alice@vsphere.local"
VKS_CLUSTER_NAMESPACE="team-a"

SSO_NAME="sso:${SSO_USER}"
B="$(printf '%s' "$SSO_NAME" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9.\n' '-')-edit"
if [ -z "$VKS_CLUSTER_NAMESPACE" ] || [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
  echo "STOPPED: VKS_CLUSTER_NAMESPACE must name one namespace here: '$VKS_CLUSTER_NAMESPACE'; nothing was changed"
else
  if ! kubectl --kubeconfig "$ADMIN_KUBECONFIG" get namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null 2>&1; then kubectl --kubeconfig "$ADMIN_KUBECONFIG" create namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null; fi
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "$B" --clusterrole=edit --user="$SSO_NAME"
fi
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SSO_USER = "Alice@vsphere.local"
$VKS_CLUSTER_NAMESPACE = "team-a"

$SSO_NAME = "sso:$SSO_USER"
$B = ($SSO_NAME.ToLower() -replace '[^a-z0-9.]', '-') + '-edit'
if (-not $VKS_CLUSTER_NAMESPACE -or $VKS_CLUSTER_NAMESPACE -eq '*') {
  "STOPPED: VKS_CLUSTER_NAMESPACE must name one namespace here: '$VKS_CLUSTER_NAMESPACE'; nothing was changed"
} else {
  kubectl --kubeconfig $ADMIN_KUBECONFIG get namespace $VKS_CLUSTER_NAMESPACE 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { kubectl --kubeconfig $ADMIN_KUBECONFIG create namespace $VKS_CLUSTER_NAMESPACE | Out-Null }
  kubectl --kubeconfig $ADMIN_KUBECONFIG -n $VKS_CLUSTER_NAMESPACE create rolebinding $B --clusterrole=edit "--user=$SSO_NAME"
}
```

**Expect:** `rolebinding.rbac.authorization.k8s.io/sso-alice-vsphere.local-edit created`. The
person's check in [USER-LOGIN.md step 3](USER-LOGIN.md#3-use-the-login) then answers `yes`.

**If not:** `STOPPED: …`: set `VKS_CLUSTER_NAMESPACE` to one namespace and run the block again.
`already exists`: a binding of that name is there, perhaps for the name in other letter
case. `kubectl --kubeconfig <admin file> -n team-a get rolebinding <name> -o
jsonpath='{.subjects[0].name}'` must print `sso:` and `SSO_USER` letter for letter; if not, delete that
binding and run this again.

### 3. Log in with the VCF CLI (the person)

Send the person [USER-LOGIN.md](USER-LOGIN.md) and the names from step 1; they log in with its
[step 2](USER-LOGIN.md#2-log-in-with-the-vcf-cli).

### 4. Use the login (the person)

The person uses the login with [USER-LOGIN.md](USER-LOGIN.md)'s
[step 3](USER-LOGIN.md#3-use-the-login), which also checks their rights from step 2.

### 5. Take it away (cluster administrator, vCenter administrator)

- Cluster administrator: delete the RoleBinding from step 2 (`kubectl --kubeconfig <admin file> -n
  team-a delete rolebinding sso-alice-vsphere.local-edit`); it stops at once.
- vCenter administrator: remove the person's role on the vSphere Namespace
  ([NAMESPACE.md](NAMESPACE.md#4-give-users-a-role) step 4), and disable the SSO user if they should lose vCenter as
  well.

If the person's check in [USER-LOGIN.md step 3](USER-LOGIN.md#3-use-the-login) still answers `yes`
afterwards, they also have rights through a group: a group with **Can edit** or **Owner** on the
vSphere Namespace is an administrator of every VKS cluster in it. Take the person out of that group, or take the group's role away in vCenter. Logins they made as an administrator keep working.

With `edit`, the person could make tokens for any ServiceAccount in that namespace and start workloads there; those keep working: delete those workloads, re-create every ServiceAccount there that has rights, and restart the workloads that use those ServiceAccounts.

<a id="the-kubectl-vsphere-plugin-instead-of-the-vcf-cli-optional-and-deprecated"></a>
<a id="1-windows-and-macos-trust-the-vcenter-ca-the-person-once"></a>
<a id="2-install-the-kubectl-vsphere-plugin-the-person-once"></a>
<a id="3-log-in-with-the-plugin-the-person"></a>

Without the VCF CLI, the person logs in with the kubectl vSphere plugin (optional and deprecated):
[USER-LOGIN.md](USER-LOGIN.md#the-kubectl-vsphere-plugin-instead-of-the-vcf-cli-optional-and-deprecated).

## A ServiceAccount token

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/access/way-serviceaccount-dark.svg">
  <img src="img/access/way-serviceaccount-light.svg" width="1200" alt="A ServiceAccount token: the cluster administrator alone makes a login that belongs to no person, with the ServiceAccount in its own namespace SA_NAMESPACE, where the team has no rights (with &quot;*&quot; it has), and its RoleBinding in the team&#x27;s namespace VKS_CLUSTER_NAMESPACE; with &quot;*&quot; the login gets the whole cluster, cluster-admin with edit or read-only with view. Taking it away deletes the ServiceAccount, its bindings and, for one namespace, the token Secrets in it, so every copy of the file stops, but tokens and workloads the team made keep working, and with &quot;*&quot; and edit so do logins made with it as a cluster administrator.">
</picture>

Pick this for a CI pipeline, a deployment tool, or a team that shares one login, in one namespace (or,
with `"*"`, the whole cluster).
The file holds a token for a ServiceAccount (a login inside the cluster that belongs to no person):
whoever has a copy acts in the cluster as that ServiceAccount
(`system:serviceaccount:kubeconfig-access:cicd-account`), not as a person. Removing or disabling an SSO
or identity provider user does not take it away; only deleting the ServiceAccount does (step 4).

The ServiceAccount lives in its own namespace inside the VKS cluster, `SA_NAMESPACE`, where the
team has no rights (so it cannot make more tokens for it), and gets its role in `VKS_CLUSTER_NAMESPACE`.
Pick `DAYS` as short as the work allows: 120 by default; the cluster does not shorten it. Never give `edit` on a namespace that holds software with wider rights (step
4 says why).

<a id="make-it"></a>

<a id="1-make-the-teams-token-and-its-file-cluster-administrator"></a>

### 1. Make the ServiceAccount token and its file (cluster administrator)

Do this when a team or a tool needs its own login to one namespace inside the VKS cluster (or, with
`"*"`, the whole cluster: below; a namespace is a folder
for the team's workloads, not a vSphere Namespace).

It makes, inside the cluster: that namespace if it is not there; a ServiceAccount for the team (a
login that belongs to no person) in the namespace `SA_NAMESPACE`; and a RoleBinding (the record
that gives a login a role in one namespace) that lets it deploy (`edit`) or only read (`view`) in
the team's namespace. It then makes a token, the key of that login, valid for the days you set,
writes it into a kubeconfig file readable only by you, and shows when the token ends, which login
it is and what it may do.

You then have one file, `SERVICE_ACCOUNT_KUBECONFIG`, for that team or tool: send it to them (step 2). Run it
again for the same team and it writes a new file with a new token in its place; copies of the old
file keep working until the old token ends (step 3). Run it with another `ROLE` and it replaces the
binding of the same kind and prints `removed …`: with a namespace, `-edit` and `-view` in that
namespace; with `"*"`, the `-cluster-admin` and `-view` ClusterRoleBindings. A run with a namespace
leaves the login's ClusterRoleBindings, and a `"*"` run its RoleBindings: step 4 deletes both kinds.

With `VKS_CLUSTER_NAMESPACE="*"` the login gets the whole cluster instead, and the block prints a
`WARNING`: with `ROLE="edit"`, `cluster-admin` (a ClusterRoleBinding named
`<SERVICE_ACCOUNT_NAME>-cluster-admin`, the same name the [administrator
token](#an-administrator-serviceaccount-token-whole-cluster) uses); with `ROLE="view"`, read-only (a
ClusterRoleBinding `<SERVICE_ACCOUNT_NAME>-view` to the built-in `view` role): it reads every
namespace, pod logs included (they can hold credentials), but not Secrets or nodes. Use `"*"` for a
whole-cluster login that must end after `DAYS`; for one that never ends, use the administrator
token. A cluster administrator (`"*"` with `edit`) can make other logins that keep working after
step 4. An empty `VKS_CLUSTER_NAMESPACE`, a `ROLE` other than `edit` or `view`, or `DAYS` that is
not a whole number of days, stops the block before it changes anything.

Set `VKS_CLUSTER` to the cluster's name (`ADMIN_KUBECONFIG` is then its administrator kubeconfig
from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig); change it if you saved that file
elsewhere), `SERVICE_ACCOUNT_NAME` to a name for the team or tool, `VKS_CLUSTER_NAMESPACE` to its namespace (or `"*"`
for the whole cluster), `ROLE` to `edit` or `view`, and `DAYS` to the days (above).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SERVICE_ACCOUNT_NAME="cicd-account"
VKS_CLUSTER_NAMESPACE="team-a"
SA_NAMESPACE="kubeconfig-access"
ROLE="edit"
DAYS="120"
SERVICE_ACCOUNT_KUBECONFIG="$HOME/${VKS_CLUSTER}-${SERVICE_ACCOUNT_NAME}.kubeconfig"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
kf() { kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" "$@"; }
TOKEN=""
case "$ROLE" in
  edit|view) ROLE_OK="yes" ;;
  *) ROLE_OK="no" ;;
esac
if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set the namespace, or "*" for the whole cluster (cluster-admin with edit, read-only with view); nothing was changed'
elif [ "$ROLE_OK" = "no" ]; then
  echo 'STOPPED: ROLE is edit or view; nothing was changed'
elif ! [ "$DAYS" -ge 1 ] 2>/dev/null || [ "${DAYS#0}" != "$DAYS" ] || [ "$DAYS" -gt 36500 ]; then
  echo "STOPPED: DAYS is a number of days, 1 to 36500: $DAYS; nothing was changed"
else
if ! adm get namespace "$SA_NAMESPACE" >/dev/null 2>&1; then adm create namespace "$SA_NAMESPACE" >/dev/null; fi
adm -n "$SA_NAMESPACE" create serviceaccount "$SERVICE_ACCOUNT_NAME" --dry-run=client -o yaml | adm apply -f - >/dev/null
if [ "$VKS_CLUSTER_NAMESPACE" = "*" ] && [ "$ROLE" = "edit" ]; then
  echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": ${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME} gets cluster-admin on the whole cluster"
  O="$(adm delete clusterrolebinding "${SERVICE_ACCOUNT_NAME}-view" --ignore-not-found)"
  if [ -n "$O" ]; then echo "removed ClusterRoleBinding ${SERVICE_ACCOUNT_NAME}-view"; fi
  adm create clusterrolebinding "${SERVICE_ACCOUNT_NAME}-cluster-admin" --clusterrole=cluster-admin \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  CTX_NS="default"
elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
  echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": ${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME} gets read access to every namespace, pod logs included (they can hold credentials); not Secrets, not nodes"
  O="$(adm delete clusterrolebinding "${SERVICE_ACCOUNT_NAME}-cluster-admin" --ignore-not-found)"
  if [ -n "$O" ]; then echo "removed ClusterRoleBinding ${SERVICE_ACCOUNT_NAME}-cluster-admin"; fi
  adm create clusterrolebinding "${SERVICE_ACCOUNT_NAME}-view" --clusterrole=view \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  CTX_NS="default"
else
  if ! adm get namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null 2>&1; then adm create namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null; fi
  OTHER="view"; if [ "$ROLE" = "view" ]; then OTHER="edit"; fi
  O="$(adm -n "$VKS_CLUSTER_NAMESPACE" delete rolebinding "${SERVICE_ACCOUNT_NAME}-${OTHER}" --ignore-not-found)"
  if [ -n "$O" ]; then echo "removed RoleBinding ${SERVICE_ACCOUNT_NAME}-${OTHER} in ${VKS_CLUSTER_NAMESPACE}"; fi
  adm -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "${SERVICE_ACCOUNT_NAME}-${ROLE}" --clusterrole="$ROLE" \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  CTX_NS="$VKS_CLUSTER_NAMESPACE"
fi
TOKEN="$(adm -n "$SA_NAMESPACE" create token "$SERVICE_ACCOUNT_NAME" --duration="$((DAYS * 24))h")"
SERVER="$(adm config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
CA="$(adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
if [ -n "$TOKEN" ] && [ -n "$SERVER" ] && [ -n "$CA" ]; then
  rm -f "$SERVICE_ACCOUNT_KUBECONFIG"
  ( umask 077
    printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    token: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\n    namespace: %s\ncurrent-context: %s\n' \
      "$SERVICE_ACCOUNT_NAME" "$SERVER" "$CA" "$SERVICE_ACCOUNT_NAME" "$TOKEN" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" "$CTX_NS" "$SERVICE_ACCOUNT_NAME" > "$SERVICE_ACCOUNT_KUBECONFIG" )
  P="$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+')"
  while [ $(( ${#P} % 4 )) -ne 0 ]; do P="$P="; done
  EXP="$(printf '%s' "$P" | base64 -d 2>/dev/null | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
  S=""; if [ -n "$EXP" ]; then S=$(( EXP - $(date +%s) )); fi
  if [ -z "$S" ]; then echo "token ends in: unknown"
  elif [ "$S" -le 0 ]; then echo "token ends: it has ended"
  elif [ "$S" -ge 86400 ]; then echo "token ends in: $(( S / 86400 )) days"
  else echo "token ends in: $(( S / 3600 )) hours"; fi
  echo "acts as: $(kf auth whoami -o jsonpath='{.status.userInfo.username}')"
  if [ "$VKS_CLUSTER_NAMESPACE" = "*" ] && [ "$ROLE" = "edit" ]; then
    echo "everything in every namespace: $(kf auth can-i '*' '*' --all-namespaces)"
  elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
    echo "list pods in kube-system: $(kf auth can-i list pods -n kube-system)"
    echo "list namespaces: $(kf auth can-i list namespaces)"
    echo "get secrets in kube-system: $(kf auth can-i get secrets -n kube-system)"
    echo "list nodes: $(kf auth can-i list nodes)"
    echo "create deployments in default: $(kf auth can-i create deployments -n default)"
  else
    echo "create deployments in $VKS_CLUSTER_NAMESPACE: $(kf auth can-i create deployments)"
    echo "list pods in kube-system: $(kf auth can-i list pods -n kube-system)"
  fi
else
  echo "FAILED: no token, server or CA read (see the kubectl errors above)"
fi
fi
unset TOKEN
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SERVICE_ACCOUNT_NAME = "cicd-account"
$VKS_CLUSTER_NAMESPACE = "team-a"
$SA_NAMESPACE = "kubeconfig-access"
$ROLE = "edit"
$DAYS = 120
$SERVICE_ACCOUNT_KUBECONFIG = "$HOME\${VKS_CLUSTER}-${SERVICE_ACCOUNT_NAME}.kubeconfig"

function adm { $input | kubectl --kubeconfig $ADMIN_KUBECONFIG @args }
function kf { kubectl --kubeconfig $SERVICE_ACCOUNT_KUBECONFIG @args }
$TOKEN = ""
if (-not $VKS_CLUSTER_NAMESPACE) {
  'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set the namespace, or "*" for the whole cluster (cluster-admin with edit, read-only with view); nothing was changed'
} elseif (-not ($ROLE -ceq 'edit' -or $ROLE -ceq 'view')) {
  'STOPPED: ROLE is edit or view; nothing was changed'
} elseif ("$DAYS" -notmatch '^[1-9][0-9]{0,4}$' -or [int]"$DAYS" -gt 36500) {
  "STOPPED: DAYS is a number of days, 1 to 36500: $DAYS; nothing was changed"
} else {
kubectl --kubeconfig $ADMIN_KUBECONFIG get namespace $SA_NAMESPACE 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { adm create namespace $SA_NAMESPACE | Out-Null }
adm -n $SA_NAMESPACE create serviceaccount $SERVICE_ACCOUNT_NAME --dry-run=client -o yaml | adm apply -f - | Out-Null
if ($VKS_CLUSTER_NAMESPACE -eq '*' -and $ROLE -ceq 'edit') {
  "WARNING: VKS_CLUSTER_NAMESPACE is `"*`": ${SA_NAMESPACE}:$SERVICE_ACCOUNT_NAME gets cluster-admin on the whole cluster"
  $O = adm delete clusterrolebinding "$SERVICE_ACCOUNT_NAME-view" --ignore-not-found
  if ($O) { "removed ClusterRoleBinding $SERVICE_ACCOUNT_NAME-view" }
  adm create clusterrolebinding "$SERVICE_ACCOUNT_NAME-cluster-admin" --clusterrole=cluster-admin "--serviceaccount=${SA_NAMESPACE}:$SERVICE_ACCOUNT_NAME" --dry-run=client -o yaml | adm apply -f - | Out-Null
  $CTX_NS = "default"
} elseif ($VKS_CLUSTER_NAMESPACE -eq '*') {
  "WARNING: VKS_CLUSTER_NAMESPACE is `"*`": ${SA_NAMESPACE}:$SERVICE_ACCOUNT_NAME gets read access to every namespace, pod logs included (they can hold credentials); not Secrets, not nodes"
  $O = adm delete clusterrolebinding "$SERVICE_ACCOUNT_NAME-cluster-admin" --ignore-not-found
  if ($O) { "removed ClusterRoleBinding $SERVICE_ACCOUNT_NAME-cluster-admin" }
  adm create clusterrolebinding "$SERVICE_ACCOUNT_NAME-view" --clusterrole=view "--serviceaccount=${SA_NAMESPACE}:$SERVICE_ACCOUNT_NAME" --dry-run=client -o yaml | adm apply -f - | Out-Null
  $CTX_NS = "default"
} else {
  kubectl --kubeconfig $ADMIN_KUBECONFIG get namespace $VKS_CLUSTER_NAMESPACE 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { adm create namespace $VKS_CLUSTER_NAMESPACE | Out-Null }
  $OTHER = 'view'; if ($ROLE -ceq 'view') { $OTHER = 'edit' }
  $O = adm -n $VKS_CLUSTER_NAMESPACE delete rolebinding "$SERVICE_ACCOUNT_NAME-$OTHER" --ignore-not-found
  if ($O) { "removed RoleBinding $SERVICE_ACCOUNT_NAME-$OTHER in $VKS_CLUSTER_NAMESPACE" }
  adm -n $VKS_CLUSTER_NAMESPACE create rolebinding "$SERVICE_ACCOUNT_NAME-$ROLE" "--clusterrole=$ROLE" "--serviceaccount=${SA_NAMESPACE}:$SERVICE_ACCOUNT_NAME" --dry-run=client -o yaml | adm apply -f - | Out-Null
  $CTX_NS = $VKS_CLUSTER_NAMESPACE
}
$TOKEN = adm -n $SA_NAMESPACE create token $SERVICE_ACCOUNT_NAME "--duration=$([int]$DAYS * 24)h"
$SERVER = adm config view --minify -o jsonpath='{.clusters[0].cluster.server}'
$CA = adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
if ($TOKEN -and $SERVER -and $CA) {
  Set-Content -Encoding ascii -Path $SERVICE_ACCOUNT_KUBECONFIG -Value @(
    'apiVersion: v1', 'kind: Config', 'clusters:', "- name: $SERVICE_ACCOUNT_NAME", '  cluster:', "    server: $SERVER",
    "    certificate-authority-data: $CA", 'users:', "- name: $SERVICE_ACCOUNT_NAME", '  user:', "    token: $TOKEN",
    'contexts:', "- name: $SERVICE_ACCOUNT_NAME", '  context:', "    cluster: $SERVICE_ACCOUNT_NAME", "    user: $SERVICE_ACCOUNT_NAME", "    namespace: $CTX_NS",
    "current-context: $SERVICE_ACCOUNT_NAME")
  $P = $TOKEN.Split('.')[1].Replace('-', '+').Replace('_', '/'); while ($P.Length % 4) { $P += '=' }
  $EXP = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($P)) | ConvertFrom-Json).exp
  $S = $EXP - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  if ($S -le 0) { "token ends: it has ended" } elseif ($S -ge 86400) { "token ends in: $([math]::Floor($S / 86400)) days" } else { "token ends in: $([math]::Floor($S / 3600)) hours" }
  "acts as: $(kf auth whoami -o jsonpath='{.status.userInfo.username}')"
  if ($VKS_CLUSTER_NAMESPACE -eq '*' -and $ROLE -ceq 'edit') {
    "everything in every namespace: $(kf auth can-i '*' '*' --all-namespaces)"
  } elseif ($VKS_CLUSTER_NAMESPACE -eq '*') {
    "list pods in kube-system: $(kf auth can-i list pods -n kube-system)"
    "list namespaces: $(kf auth can-i list namespaces)"
    "get secrets in kube-system: $(kf auth can-i get secrets -n kube-system)"
    "list nodes: $(kf auth can-i list nodes)"
    "create deployments in default: $(kf auth can-i create deployments -n default)"
  } else {
    "create deployments in ${VKS_CLUSTER_NAMESPACE}: $(kf auth can-i create deployments)"
    "list pods in kube-system: $(kf auth can-i list pods -n kube-system)"
  }
} else {
  "FAILED: no token, server or CA read (see the kubectl errors above)"
}
}
Remove-Variable TOKEN
```

</details>

**Expect:** `token ends in: 119 days` or `120 days` (for `DAYS="120"`; `23 hours` for `DAYS="1"`),
`acts as: system:serviceaccount:kubeconfig-access:cicd-account`, `create deployments in team-a: yes`
(`no` with `ROLE="view"`) and `list pods in kube-system: no`. With `VKS_CLUSTER_NAMESPACE="*"`: the
`WARNING` line first; with `ROLE="edit"`, `everything in every namespace: yes`; with `ROLE="view"`,
`list pods in kube-system: yes`, `list namespaces: yes`, `get secrets in kube-system: no`,
`list nodes: no` and `create deployments in default: no`. A re-run with another `ROLE` also prints
`removed …` for the binding it replaced, and the checks then match the new `ROLE`.

**If not:**
- `FAILED: …` with `Forbidden` or `Unauthorized` above it: `ADMIN_KUBECONFIG` is not the cluster's
  administrator file, or it has expired; get it again.
- `STOPPED: …`: set `VKS_CLUSTER_NAMESPACE` (a namespace, or `"*"`), `ROLE` (`edit` or `view`, in
  small letters) or `DAYS` (a whole number of days, 1 to 36500, with no leading 0) and run the block
  again.
- `list pods in kube-system: yes` with a namespace: an earlier `"*"` run left the login's
  ClusterRoleBinding (`<SERVICE_ACCOUNT_NAME>-cluster-admin` or `<SERVICE_ACCOUNT_NAME>-view`); remove
  only it with `kubectl --kubeconfig "$ADMIN_KUBECONFIG" delete clusterrolebinding
  <SERVICE_ACCOUNT_NAME>-cluster-admin <SERVICE_ACCOUNT_NAME>-view --ignore-not-found`.
- `create deployments in default: yes` with `"*"` and `view`: an earlier run with
  `VKS_CLUSTER_NAMESPACE="default"` and `edit` left a RoleBinding there; remove only it with
  `kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n default delete rolebinding <SERVICE_ACCOUNT_NAME>-edit`.
- A `yes` where `no` is expected: an older binding for that login is still there: find it with
  `kubectl --kubeconfig "$ADMIN_KUBECONFIG" get rolebindings,clusterrolebindings -A -o wide | grep <SERVICE_ACCOUNT_NAME>`
  and delete it.

### 2. Hand it over and use it (cluster administrator, then the team or tool)

Send `SERVICE_ACCOUNT_KUBECONFIG` to the team as a secret: whoever has a copy acts as the ServiceAccount
([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over)), with the namespace `VKS_CLUSTER_NAMESPACE` (with
`"*"`: that it is the whole cluster, read-only with `view`), the day the token ends and the cluster's address (the file's
`server:` line). The team or tool saves, checks and uses it with
[USER-KUBECONFIG.md](USER-KUBECONFIG.md).

<a id="renew-it"></a>

<a id="3-renew-the-teams-token-cluster-administrator"></a>

### 3. Renew the ServiceAccount token (cluster administrator)

Run the block in step 1 again before the token ends, with the same values, and send the team the new
file. The old file keeps working until its own end; to stop it sooner, take the access away and make
a new one.

<a id="take-it-away"></a>

<a id="4-take-the-teams-token-away-cluster-administrator"></a>

### 4. Take the ServiceAccount token away (cluster administrator)

Do this when the team or tool should lose its access, or a copy of the file may have leaked. It
deletes the team's ServiceAccount and **every ServiceAccount token Secret (a stored token that does
not end) in `VKS_CLUSTER_NAMESPACE`, also those the team did not make** (with `edit`, the team could have
made lasting ones). Every copy of the file then answers `Unauthorized` within about 15 seconds, and
making a ServiceAccount of the same name again does not bring the copies back. It deletes the
login's ClusterRoleBindings (`-cluster-admin` and `-view`, whichever an earlier `"*"` run made) and, in
the namespace, its RoleBindings (`-edit` and `-view`), whatever `ROLE` step 1 used; the team's
namespace stays: delete it when the team's work in it is no longer needed. With `"*"`, the token
Secrets are not swept. It then says `FAILED` if a RoleBinding in any namespace still names the login
(a `VKS_CLUSTER_NAMESPACE` other than step 1's deletes nothing there), asks the
cluster whether that login may still list pods in every namespace (and, with a namespace, in it) and
checks that the ServiceAccount is gone; with `"*"` and `edit`, logins made with it as a cluster
administrator keep working. An empty `VKS_CLUSTER_NAMESPACE` stops the block before it deletes
anything. Set `SERVICE_ACCOUNT_NAME`, `VKS_CLUSTER_NAMESPACE`, `SA_NAMESPACE`, `VKS_CLUSTER` and
`ADMIN_KUBECONFIG` to what step 1 used.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SERVICE_ACCOUNT_NAME="cicd-account"
VKS_CLUSTER_NAMESPACE="team-a"
SA_NAMESPACE="kubeconfig-access"

if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set it to what step 1 used (a namespace, or "*"); nothing was deleted'
else
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" delete clusterrolebinding "${SERVICE_ACCOUNT_NAME}-cluster-admin" "${SERVICE_ACCOUNT_NAME}-view" --ignore-not-found
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$SA_NAMESPACE" delete serviceaccount "$SERVICE_ACCOUNT_NAME"
  if [ "$VKS_CLUSTER_NAMESPACE" != "*" ]; then
    kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$VKS_CLUSTER_NAMESPACE" delete rolebinding "${SERVICE_ACCOUNT_NAME}-edit" "${SERVICE_ACCOUNT_NAME}-view" --ignore-not-found
    kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$VKS_CLUSTER_NAMESPACE" delete secret --field-selector type=kubernetes.io/service-account-token
    echo "may still list pods in ${VKS_CLUSTER_NAMESPACE}: $(kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$VKS_CLUSTER_NAMESPACE" auth can-i list pods --as="system:serviceaccount:${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}")"
  fi
  if RB="$(kubectl --kubeconfig "$ADMIN_KUBECONFIG" get rolebindings -A --no-headers -o 'custom-columns=NS:.metadata.namespace,N:.metadata.name,S:.subjects[*].name')"; then
    LEFT="$(printf '%s\n' "$RB" | awk -v n="$SERVICE_ACCOUNT_NAME" '{k = split($3, s, ","); for (i = 1; i <= k; i++) if (s[i] == n) print $1 "/" $2}')"
    if [ -n "$LEFT" ]; then echo "FAILED: a RoleBinding still names ${SERVICE_ACCOUNT_NAME}: $LEFT (step 1 used that namespace: run this block again with it, which also deletes the token Secrets there)"; fi
  else
    echo "FAILED: the RoleBindings could not be read (see the error above)"
  fi
  echo "may still list pods in every namespace: $(kubectl --kubeconfig "$ADMIN_KUBECONFIG" auth can-i list pods --all-namespaces --as="system:serviceaccount:${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}")"
  O="$(kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$SA_NAMESPACE" get serviceaccount "$SERVICE_ACCOUNT_NAME" -o name 2>&1)"
  case "$O" in
    *NotFound*) echo "ServiceAccount gone: every copy of the file answers Unauthorized within about 15 seconds" ;;
    *) echo "FAILED: the ServiceAccount is still there, or could not be read: $O" ;;
  esac
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SERVICE_ACCOUNT_NAME = "cicd-account"
$VKS_CLUSTER_NAMESPACE = "team-a"
$SA_NAMESPACE = "kubeconfig-access"

if (-not $VKS_CLUSTER_NAMESPACE) {
  'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set it to what step 1 used (a namespace, or "*"); nothing was deleted'
} else {
  kubectl --kubeconfig $ADMIN_KUBECONFIG delete clusterrolebinding "$SERVICE_ACCOUNT_NAME-cluster-admin" "$SERVICE_ACCOUNT_NAME-view" --ignore-not-found
  kubectl --kubeconfig $ADMIN_KUBECONFIG -n $SA_NAMESPACE delete serviceaccount $SERVICE_ACCOUNT_NAME
  if ($VKS_CLUSTER_NAMESPACE -ne '*') {
    kubectl --kubeconfig $ADMIN_KUBECONFIG -n $VKS_CLUSTER_NAMESPACE delete rolebinding "$SERVICE_ACCOUNT_NAME-edit" "$SERVICE_ACCOUNT_NAME-view" --ignore-not-found
    kubectl --kubeconfig $ADMIN_KUBECONFIG -n $VKS_CLUSTER_NAMESPACE delete secret --field-selector type=kubernetes.io/service-account-token
    "may still list pods in ${VKS_CLUSTER_NAMESPACE}: $(kubectl --kubeconfig $ADMIN_KUBECONFIG -n $VKS_CLUSTER_NAMESPACE auth can-i list pods "--as=system:serviceaccount:${SA_NAMESPACE}:$SERVICE_ACCOUNT_NAME")"
  }
  $global:LASTEXITCODE = $null
  $RB = kubectl --kubeconfig $ADMIN_KUBECONFIG get rolebindings -A --no-headers -o 'custom-columns=NS:.metadata.namespace,N:.metadata.name,S:.subjects[*].name'
  if ($LASTEXITCODE -ne 0) {
    'FAILED: the RoleBindings could not be read (see the error above)'
  } else {
    $LEFT = @($RB | Where-Object { (($_ -split '\s+')[2] -split ',') -contains $SERVICE_ACCOUNT_NAME } | ForEach-Object { $f = $_ -split '\s+'; "$($f[0])/$($f[1])" })
    if ($LEFT.Count) { "FAILED: a RoleBinding still names ${SERVICE_ACCOUNT_NAME}: $($LEFT -join ' ') (step 1 used that namespace: run this block again with it, which also deletes the token Secrets there)" }
  }
  "may still list pods in every namespace: $(kubectl --kubeconfig $ADMIN_KUBECONFIG auth can-i list pods --all-namespaces "--as=system:serviceaccount:${SA_NAMESPACE}:$SERVICE_ACCOUNT_NAME")"
  $O = (kubectl --kubeconfig $ADMIN_KUBECONFIG -n $SA_NAMESPACE get serviceaccount $SERVICE_ACCOUNT_NAME -o name 2>&1) -join ' '
  if ($O -match 'NotFound') {
    'ServiceAccount gone: every copy of the file answers Unauthorized within about 15 seconds'
  } else {
    "FAILED: the ServiceAccount is still there, or could not be read: $O"
  }
}
```

</details>

**Expect:** `serviceaccount "cicd-account" deleted from kubeconfig-access namespace` (older kubectl:
`serviceaccount "cicd-account" deleted`), `rolebinding.rbac.authorization.k8s.io "cicd-account-edit"
deleted` (or `-view`), then a `deleted` line for each token Secret in `team-a`, or `No resources
found`, and `may still list pods in team-a: no`. With `VKS_CLUSTER_NAMESPACE="*"`:
`clusterrolebinding.rbac.authorization.k8s.io "cicd-account-cluster-admin" deleted` (or
`"cicd-account-view"`), the ServiceAccount line. In both cases `may still list pods in every
namespace: no` and `ServiceAccount gone: …`.

**If not:**
- `Error from server (NotFound)`: the ServiceAccount is already gone, or `SERVICE_ACCOUNT_NAME` or `SA_NAMESPACE`
  is not what step 1 used.
- `FAILED: the ServiceAccount is still there …`: read the error in that line (`Forbidden`: `ADMIN_KUBECONFIG` is
  not the cluster's administrator file) and run the block again.
- `FAILED: a RoleBinding still names …`: step 1 used that namespace (`VKS_CLUSTER_NAMESPACE` was `"*"`
  or another namespace, so nothing there was deleted); run the block again with it.
- `may still list pods …: yes`: another binding gives that login rights; find it with
  `kubectl --kubeconfig "$ADMIN_KUBECONFIG" get rolebindings,clusterrolebindings -A -o wide | grep "$SERVICE_ACCOUNT_NAME"` and delete it.

**What keeps working:** tokens the team made with `kubectl create token`, and workloads it started:
delete the team's workloads, and delete and re-create any ServiceAccount in `VKS_CLUSTER_NAMESPACE` that
has rights, then restart the workloads that use them. So never give `edit` on a namespace that holds software with wider rights.

## An administrator ServiceAccount token (whole cluster)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/access/way-admin-token-dark.svg">
  <img src="img/access/way-admin-token-light.svg" width="1200" alt="An administrator ServiceAccount token: the cluster administrator makes a ServiceAccount in SA_NAMESPACE and a ClusterRoleBinding that gives it cluster-admin on the whole VKS cluster, so whoever has a copy of the file can do everything in it; send this, never the cluster&#x27;s administrator kubeconfig, because this one can be taken away. Taking it away deletes the ClusterRoleBinding, the token Secret and the ServiceAccount, but other logins the holder made with it keep working, and after a leak only a new cluster is certain to be clean.">
</picture>

Pick this when a tool, a pipeline or a person needs the whole cluster: send this, never the
cluster's administrator kubeconfig, because this one can be taken away. The file holds a token for
a ServiceAccount (a login inside the cluster that belongs to no person) with `cluster-admin` on the
whole VKS cluster: whoever has a copy can do everything in it.

- It lasts `DAYS` days (365 for a year), or with `DAYS="never"` until you take it away; the cluster
  does not shorten either.
- Taking it away stops this file only. With `cluster-admin`, the holder can make other logins of
  their own (another ServiceAccount, or a certificate signed with the cluster's keys) that keep
  working; after a file may have leaked, only a new cluster is certain to be clean.
- vCenter does not see what it does; the cluster's own audit log on its control-plane node does, as
  `system:serviceaccount:kubeconfig-access:<name>`.

<a id="make-the-administrator-token"></a>

### 1. Make the administrator token and its file (cluster administrator)

Do this when a tool or a person needs the whole VKS cluster.

It makes, inside the cluster, the namespace `SA_NAMESPACE` if it is not there, a ServiceAccount (a
login that belongs to no person) in it, and a ClusterRoleBinding `<SERVICE_ACCOUNT_NAME>-cluster-admin` (the
record that gives a login a role in the whole cluster) that gives it `cluster-admin`, the role for
everything. It then makes a token, the key of that login, valid for the days you set, or with
`DAYS="never"` a token Secret `<SERVICE_ACCOUNT_NAME>-token` that does not expire; writes it into a kubeconfig
file readable only by you; and shows when the token ends, which login it is and what it may do.

You then have one file, `SERVICE_ACCOUNT_KUBECONFIG`, for that tool or person: send it (step 2). Run it again
with days and it writes a new file with a new token; copies of the old file keep working until the
old token ends. With `never` it gives the same token (step 3).

Set `VKS_CLUSTER` to the cluster's name (`ADMIN_KUBECONFIG` is then its administrator kubeconfig
from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig); change it if you saved that file
elsewhere), `SERVICE_ACCOUNT_NAME` to a name for the tool or person, `SA_NAMESPACE` to the namespace that
holds the ServiceAccount (made if it is not there), and `DAYS` to 1 to 36500 days (365 for a year) or `never`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SERVICE_ACCOUNT_NAME="cluster-admin-ci"
SA_NAMESPACE="kubeconfig-access"
DAYS="365"
SERVICE_ACCOUNT_KUBECONFIG="$HOME/${VKS_CLUSTER}-${SERVICE_ACCOUNT_NAME}.kubeconfig"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
TOKEN=""
if [ "$DAYS" != "never" ] && { ! [ "$DAYS" -ge 1 ] 2>/dev/null || [ "${DAYS#0}" != "$DAYS" ] || [ "$DAYS" -gt 36500 ]; }; then
  echo "STOPPED: DAYS is a number of days, 1 to 36500, or never: $DAYS"
else
  if ! adm get namespace "$SA_NAMESPACE" >/dev/null 2>&1; then adm create namespace "$SA_NAMESPACE" >/dev/null; fi
  adm -n "$SA_NAMESPACE" create serviceaccount "$SERVICE_ACCOUNT_NAME" --dry-run=client -o yaml | adm apply -f - >/dev/null
  adm create clusterrolebinding "${SERVICE_ACCOUNT_NAME}-cluster-admin" --clusterrole=cluster-admin \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  if [ "$DAYS" = "never" ]; then
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s-token\n  namespace: %s\n  annotations:\n    kubernetes.io/service-account.name: %s\ntype: kubernetes.io/service-account-token\n' \
      "$SERVICE_ACCOUNT_NAME" "$SA_NAMESPACE" "$SERVICE_ACCOUNT_NAME" | adm apply -f - >/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10; do
      TOKEN="$(adm -n "$SA_NAMESPACE" get secret "${SERVICE_ACCOUNT_NAME}-token" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null)"
      if [ -n "$TOKEN" ]; then break; fi
      sleep 2
    done
    if [ -z "$TOKEN" ]; then adm -n "$SA_NAMESPACE" delete secret "${SERVICE_ACCOUNT_NAME}-token" --ignore-not-found >/dev/null; fi
  else
    TOKEN="$(adm -n "$SA_NAMESPACE" create token "$SERVICE_ACCOUNT_NAME" --duration="$((DAYS * 24))h")"
  fi
  SERVER="$(adm config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
  CA="$(adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  if [ -n "$TOKEN" ] && [ -n "$SERVER" ] && [ -n "$CA" ]; then
    rm -f "$SERVICE_ACCOUNT_KUBECONFIG"
    ( umask 077
      printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    token: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\ncurrent-context: %s\n' \
        "$SERVICE_ACCOUNT_NAME" "$SERVER" "$CA" "$SERVICE_ACCOUNT_NAME" "$TOKEN" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" > "$SERVICE_ACCOUNT_KUBECONFIG" )
    P="$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+')"
    while [ $(( ${#P} % 4 )) -ne 0 ]; do P="$P="; done
    EXP="$(printf '%s' "$P" | base64 -d 2>/dev/null | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
    S=""; if [ -n "$EXP" ]; then S=$(( EXP - $(date +%s) )); fi
    if [ -n "$S" ] && [ "$S" -ge 86400 ]; then echo "token ends in: $(( S / 86400 )) days"
    elif [ -n "$S" ] && [ "$S" -le 0 ]; then echo "token ends: it has ended"
    elif [ -n "$S" ]; then echo "token ends in: $(( S / 3600 )) hours"
    elif [ "$DAYS" = "never" ]; then echo "token ends: never (until you take it away)"
    else echo "token ends in: unknown"; fi
    echo "acts as: $(kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')"
    echo "everything in every namespace: $(kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" auth can-i '*' '*' --all-namespaces)"
  else
    echo "FAILED: no token, server or CA read (see the kubectl errors above)"
  fi
fi
unset TOKEN
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SERVICE_ACCOUNT_NAME = "cluster-admin-ci"
$SA_NAMESPACE = "kubeconfig-access"
$DAYS = "365"
$SERVICE_ACCOUNT_KUBECONFIG = "$HOME\${VKS_CLUSTER}-${SERVICE_ACCOUNT_NAME}.kubeconfig"

function adm { $input | kubectl --kubeconfig $ADMIN_KUBECONFIG @args }
$TOKEN = $null; $B = $null
if ($DAYS -ne "never" -and ("$DAYS" -notmatch '^[1-9][0-9]{0,4}$' -or [int]"$DAYS" -gt 36500)) {
  "STOPPED: DAYS is a number of days, 1 to 36500, or never: $DAYS"
} else {
  kubectl --kubeconfig $ADMIN_KUBECONFIG get namespace $SA_NAMESPACE 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { adm create namespace $SA_NAMESPACE | Out-Null }
  adm -n $SA_NAMESPACE create serviceaccount $SERVICE_ACCOUNT_NAME --dry-run=client -o yaml | adm apply -f - | Out-Null
  adm create clusterrolebinding "$SERVICE_ACCOUNT_NAME-cluster-admin" "--clusterrole=cluster-admin" "--serviceaccount=${SA_NAMESPACE}:$SERVICE_ACCOUNT_NAME" --dry-run=client -o yaml | adm apply -f - | Out-Null
  if ($DAYS -eq "never") {
    @('apiVersion: v1', 'kind: Secret', 'metadata:', "  name: $SERVICE_ACCOUNT_NAME-token", "  namespace: $SA_NAMESPACE", '  annotations:',
      "    kubernetes.io/service-account.name: $SERVICE_ACCOUNT_NAME", 'type: kubernetes.io/service-account-token') | adm apply -f - | Out-Null
    foreach ($i in 1..10) {
      $B = adm -n $SA_NAMESPACE get secret "$SERVICE_ACCOUNT_NAME-token" -o jsonpath='{.data.token}' 2>$null
      if ($B) { $TOKEN = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B)); break }
      Start-Sleep 2
    }
    if (-not $TOKEN) { adm -n $SA_NAMESPACE delete secret "$SERVICE_ACCOUNT_NAME-token" --ignore-not-found | Out-Null }
  } else {
    $TOKEN = adm -n $SA_NAMESPACE create token $SERVICE_ACCOUNT_NAME "--duration=$([int]$DAYS * 24)h"
  }
  $SERVER = adm config view --minify -o jsonpath='{.clusters[0].cluster.server}'
  $CA = adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
  if ($TOKEN -and $SERVER -and $CA) {
    Set-Content -Encoding ascii -Path $SERVICE_ACCOUNT_KUBECONFIG -Value @(
      'apiVersion: v1', 'kind: Config', 'clusters:', "- name: $SERVICE_ACCOUNT_NAME", '  cluster:', "    server: $SERVER",
      "    certificate-authority-data: $CA", 'users:', "- name: $SERVICE_ACCOUNT_NAME", '  user:', "    token: $TOKEN",
      'contexts:', "- name: $SERVICE_ACCOUNT_NAME", '  context:', "    cluster: $SERVICE_ACCOUNT_NAME", "    user: $SERVICE_ACCOUNT_NAME", "current-context: $SERVICE_ACCOUNT_NAME")
    $P = $TOKEN.Split('.')[1].Replace('-', '+').Replace('_', '/'); while ($P.Length % 4) { $P += '=' }
    $EXP = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($P)) | ConvertFrom-Json).exp
    if ($EXP) { $S = $EXP - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); if ($S -le 0) { "token ends: it has ended" } elseif ($S -ge 86400) { "token ends in: $([math]::Floor($S / 86400)) days" } else { "token ends in: $([math]::Floor($S / 3600)) hours" } } elseif ($DAYS -eq "never") { "token ends: never (until you take it away)" } else { "token ends in: unknown" }
    "acts as: $(kubectl --kubeconfig $SERVICE_ACCOUNT_KUBECONFIG auth whoami -o jsonpath='{.status.userInfo.username}')"
    "everything in every namespace: $(kubectl --kubeconfig $SERVICE_ACCOUNT_KUBECONFIG auth can-i '*' '*' --all-namespaces)"
  } else {
    "FAILED: no token, server or CA read (see the kubectl errors above)"
  }
}
Remove-Variable TOKEN, B
```

</details>

**Expect:** `token ends in: 364 days` or `365 days` (for `DAYS="365"`; `23 hours` for `DAYS="1"`; `token ends: never (until you
take it away)` for `DAYS="never"`), `acts as: system:serviceaccount:kubeconfig-access:cluster-admin-ci`
and `everything in every namespace: yes`.

**If not:**
- `STOPPED: DAYS is …`: set `DAYS` to a whole number of days from 1 to 36500, with no leading 0, or to `never`.
- `FAILED: …` with `Forbidden` or `Unauthorized` above it: `ADMIN_KUBECONFIG` is not the cluster's
  administrator file, or it has expired; get it again.
- `FAILED: …` with no error above it, for `DAYS="never"`: the cluster did not fill the token Secret
  within 20 seconds; run the block again.

<a id="use-the-administrator-token"></a>

### 2. Hand it over and use it on another machine (cluster administrator, then the tool or person)

Send `SERVICE_ACCOUNT_KUBECONFIG` as a secret ([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over)), with
the day the token ends (with `DAYS="never"`: that it does not end) and the cluster's address (the
file's `server:` line). The tool or person saves, checks and uses it with
[USER-KUBECONFIG.md](USER-KUBECONFIG.md), whose
[step 5](USER-KUBECONFIG.md#5-check-that-a-whole-cluster-file-can-change-things-whole-cluster-file-only)
checks that the file can create, change and delete in the cluster.

### 3. Renew the administrator token (cluster administrator)

A token with days: run step 1 again before it ends, with the same values, and send the new file;
the old one keeps working until its own end. A token with `DAYS="never"` needs no renewal: step 1
run again gives the same token. Every older token keeps working until its own end, a `never` one
until step 4, also after you switch `DAYS` to a number: to stop it, take the access away (step 4)
and make a new one.

<a id="take-the-administrator-token-away"></a>

### 4. Take the administrator token away (cluster administrator)

Do this when the tool or person should lose the cluster, or a copy of the file may have leaked. It
deletes the ClusterRoleBinding (the file loses its rights at once), the token Secret and the
ServiceAccount, then tries your copy of the file 20 seconds later. Every copy then answers
`Unauthorized`; other logins the holder made with it keep working (see the start of this way).
Run again, it deletes only what is left. Set `VKS_CLUSTER`, `ADMIN_KUBECONFIG`, `SERVICE_ACCOUNT_NAME` and
`SA_NAMESPACE` to what step 1 used.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SERVICE_ACCOUNT_NAME="cluster-admin-ci"
SA_NAMESPACE="kubeconfig-access"
SERVICE_ACCOUNT_KUBECONFIG="$HOME/${VKS_CLUSTER}-${SERVICE_ACCOUNT_NAME}.kubeconfig"

kubectl --kubeconfig "$ADMIN_KUBECONFIG" delete clusterrolebinding "${SERVICE_ACCOUNT_NAME}-cluster-admin" --ignore-not-found
kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$SA_NAMESPACE" delete secret "${SERVICE_ACCOUNT_NAME}-token" --ignore-not-found
kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$SA_NAMESPACE" delete serviceaccount "$SERVICE_ACCOUNT_NAME" --ignore-not-found
sleep 20; kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" get namespaces
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SERVICE_ACCOUNT_NAME = "cluster-admin-ci"
$SA_NAMESPACE = "kubeconfig-access"
$SERVICE_ACCOUNT_KUBECONFIG = "$HOME\${VKS_CLUSTER}-${SERVICE_ACCOUNT_NAME}.kubeconfig"

kubectl --kubeconfig $ADMIN_KUBECONFIG delete clusterrolebinding "$SERVICE_ACCOUNT_NAME-cluster-admin" --ignore-not-found
kubectl --kubeconfig $ADMIN_KUBECONFIG -n $SA_NAMESPACE delete secret "$SERVICE_ACCOUNT_NAME-token" --ignore-not-found
kubectl --kubeconfig $ADMIN_KUBECONFIG -n $SA_NAMESPACE delete serviceaccount $SERVICE_ACCOUNT_NAME --ignore-not-found
Start-Sleep 20; kubectl --kubeconfig $SERVICE_ACCOUNT_KUBECONFIG get namespaces
```

**Expect:** a `deleted` line for each that existed (the Secret only with `DAYS="never"`), then
`error: You must be logged in to the server (Unauthorized)`.

**If not:**
- `Forbidden` or `Unauthorized` on the delete lines: `ADMIN_KUBECONFIG` is not the cluster's
  administrator file, or it has expired; get it again and run the block again.
- The last command lists namespaces: wait a minute and run it again; if it still does, check that
  `SERVICE_ACCOUNT_NAME` and `SA_NAMESPACE` are what step 1 used.
- `no such file or directory` on the last line: your copy is gone or has another name; the deletes
  above did the work.

## A personal certificate

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/access/way-certificate-dark.svg">
  <img src="img/access/way-certificate-light.svg" width="1200" alt="A personal certificate: the cluster administrator has the cluster sign a certificate for a new name and gives that name edit or view in one namespace inside the VKS cluster (with &quot;*&quot; the whole cluster: cluster-admin with edit, read-only with view), for one person with no SSO or identity provider account, for a limited time. Taking it away deletes the name&#x27;s RoleBindings and ClusterRoleBindings so the name has no rights, but the certificate cannot be withdrawn and keeps proving the name until its end date, so that name is never given rights again.">
</picture>

Pick this for one person with no SSO or identity provider account, for a limited time. The file holds a
key and a certificate signed by the cluster: whoever has a copy acts as that person, with kubectl
alone. A certificate cannot be withdrawn before it ends: taking it away removes the rights of its
name, and that name is never given rights again.

### 1. Make the certificate and its file (cluster administrator)

Do this when such a person needs access (on Windows, in WSL).

It makes a key (the secret that proves who holds the file) and a certificate signing request: a
request to the cluster to sign a certificate for a new name, `PERSON` plus the date and time (for
example `alice-20261029223015`), valid for `DAYS` days. It approves the request, so the cluster
signs it, then deletes the request. It makes the namespace `VKS_CLUSTER_NAMESPACE` inside the VKS cluster
if it is not there, and a RoleBinding (the record that gives a name a role in one namespace) that
gives that name `ROLE` in it: `edit` to deploy, `view` to read only; then it writes the kubeconfig,
key included, readable only by you. With `VKS_CLUSTER_NAMESPACE="*"` it gives the name the whole
cluster instead and prints a `WARNING`: with `ROLE="edit"`, `cluster-admin` (a ClusterRoleBinding
`<name>-cluster-admin`), only for a person who must administer the cluster; with `ROLE="view"`,
read-only (a ClusterRoleBinding `<name>-view` to the built-in `view` role): it reads every namespace,
pod logs included (they can hold credentials), but not Secrets or nodes. A cluster administrator
(`"*"` with `edit`) can make other logins (ServiceAccount tokens, certificates) that keep working after
step 4, and this certificate cannot be withdrawn before its end date. An empty `VKS_CLUSTER_NAMESPACE`,
or a `ROLE` other than `edit` or `view`, stops the block before it changes anything.

You then have one file, `PERSON_KUBECONFIG`, for that person: send it (step 2). Each run makes a
new name, so that you can take each certificate away alone; an older name keeps its rights until
step 4.

Set `VKS_CLUSTER` to the cluster's name (`ADMIN_KUBECONFIG` is then its administrator kubeconfig
from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig); change it if you saved that file
elsewhere), `PERSON` to a short name for the person, `VKS_CLUSTER_NAMESPACE` to their namespace (or
`"*"` for the whole cluster), `ROLE` to `edit` or `view`, and `DAYS` to as few days as they need (120
by default).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
PERSON="alice"
VKS_CLUSTER_NAMESPACE="team-a"
ROLE="edit"
DAYS="120"
PERSON_KUBECONFIG="$HOME/${VKS_CLUSTER}-${PERSON}.kubeconfig"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
kf() { kubectl --kubeconfig "$PERSON_KUBECONFIG" "$@"; }
case "$ROLE" in
  edit|view) ROLE_OK="yes" ;;
  *) ROLE_OK="no" ;;
esac
if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set the namespace, or "*" for the whole cluster (cluster-admin with edit, read-only with view); nothing was changed'
elif [ "$ROLE_OK" = "no" ]; then
  echo 'STOPPED: ROLE is edit or view; nothing was changed'
elif ! [ "$DAYS" -ge 1 ] 2>/dev/null || [ "${DAYS#0}" != "$DAYS" ] || [ "$DAYS" -gt 366 ]; then
  echo "STOPPED: DAYS is a number of days, 1 to 366: $DAYS; nothing was changed"
else
NAME="${PERSON}-$(date +%Y%m%d%H%M%S)"
CSR="kubeconfig-${NAME}"
adm delete csr "$CSR" --ignore-not-found >/dev/null
TMP="$(mktemp -d)"
openssl req -new -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -subj "/CN=${NAME}" -out "$TMP/csr.pem" 2>/dev/null
REQ="$(base64 < "$TMP/csr.pem" | tr -d '\n')"
printf 'apiVersion: certificates.k8s.io/v1\nkind: CertificateSigningRequest\nmetadata:\n  name: %s\nspec:\n  request: %s\n  signerName: kubernetes.io/kube-apiserver-client\n  expirationSeconds: %s\n  usages: [client auth]\n' \
  "$CSR" "$REQ" "$((DAYS * 86400))" | adm create -f - >/dev/null
if [ "$(adm get csr "$CSR" -o jsonpath='{.spec.request}')" = "$REQ" ]; then adm certificate approve "$CSR" >/dev/null; fi
CERT=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  CERT="$(adm get csr "$CSR" -o jsonpath='{.status.certificate}')"
  [ -n "$CERT" ] && break
  sleep 2
done
SERVER="$(adm config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
CA="$(adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
adm get csr "$CSR" -o go-template='{{.status.certificate | base64decode}}' > "$TMP/cert.pem" 2>/dev/null
if [ -n "$CERT" ] && [ -n "$SERVER" ] && [ -n "$CA" ] \
   && [ "$(openssl x509 -in "$TMP/cert.pem" -noout -pubkey)" = "$(openssl pkey -in "$TMP/key.pem" -pubout)" ]; then
  if [ "$VKS_CLUSTER_NAMESPACE" = "*" ] && [ "$ROLE" = "edit" ]; then
    echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": ${NAME} gets cluster-admin on the whole cluster"
    adm create clusterrolebinding "${NAME}-cluster-admin" --clusterrole=cluster-admin --user="$NAME" >/dev/null
    CTX_NS="default"
  elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
    echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": ${NAME} gets read access to every namespace, pod logs included (they can hold credentials); not Secrets, not nodes"
    adm create clusterrolebinding "${NAME}-view" --clusterrole=view --user="$NAME" >/dev/null
    CTX_NS="default"
  else
    if ! adm get namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null 2>&1; then adm create namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null; fi
    adm -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "${NAME}-${ROLE}" --clusterrole="$ROLE" --user="$NAME" >/dev/null
    CTX_NS="$VKS_CLUSTER_NAMESPACE"
  fi
  rm -f "$PERSON_KUBECONFIG"
  ( umask 077
    printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    client-certificate-data: %s\n    client-key-data: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\n    namespace: %s\ncurrent-context: %s\n' \
      "$NAME" "$SERVER" "$CA" "$NAME" "$CERT" "$(base64 < "$TMP/key.pem" | tr -d '\n')" \
      "$NAME" "$NAME" "$NAME" "$CTX_NS" "$NAME" > "$PERSON_KUBECONFIG" )
  openssl x509 -in "$TMP/cert.pem" -noout -subject -enddate
  if [ "$VKS_CLUSTER_NAMESPACE" = "*" ] && [ "$ROLE" = "edit" ]; then
    echo "everything in every namespace: $(kf auth can-i '*' '*' --all-namespaces)"
  elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
    echo "list pods in kube-system: $(kf auth can-i list pods -n kube-system)"
    echo "list namespaces: $(kf auth can-i list namespaces)"
    echo "get secrets in kube-system: $(kf auth can-i get secrets -n kube-system)"
    echo "list nodes: $(kf auth can-i list nodes)"
    echo "create deployments in default: $(kf auth can-i create deployments -n default)"
  else
    echo "create deployments in $VKS_CLUSTER_NAMESPACE: $(kf auth can-i create deployments)"
  fi
else
  echo "FAILED: no matching certificate, server or CA (see the kubectl errors above)"
fi
adm delete csr "$CSR" --ignore-not-found >/dev/null; rm -rf "$TMP"
fi
```

</details>

**Expect:** `subject=CN=alice-…` (or `subject=CN = alice-…`, `subject= /CN=alice-…`), `notAfter=` about `DAYS` days from
now (the cluster signs for at most a year), and `create deployments in team-a: yes` (`no` with
`ROLE="view"`). With `VKS_CLUSTER_NAMESPACE="*"` the `WARNING` line first; with `ROLE="edit"`,
`everything in every namespace: yes`; with `ROLE="view"`, `list pods in kube-system: yes`,
`list namespaces: yes`, `get secrets in kube-system: no`, `list nodes: no` and
`create deployments in default: no`. Write down the name: you need it to take the access away.

**If not:** `FAILED: …` with `Forbidden` or `Unauthorized` above it: `ADMIN_KUBECONFIG` is not the
cluster's administrator file, or it has expired. `STOPPED: …`: set `VKS_CLUSTER_NAMESPACE` to the person's
namespace (or `"*"` for the whole cluster), `ROLE` to `edit` or `view` (in small letters), or `DAYS` to a
whole number of days from 1 to 366 (the cluster signs for at most a year), and run the block again.
A `yes` where `no` is expected: another binding gives the name rights (`kubectl --kubeconfig
"$ADMIN_KUBECONFIG" get rolebindings,clusterrolebindings -A -o wide | grep <name>`); delete it.

### 2. Hand it over and use it (cluster administrator, then the person)

Send `PERSON_KUBECONFIG` to the person as a secret: it holds their key
([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over)), with the namespace `VKS_CLUSTER_NAMESPACE` (with
`"*"`: that it is the whole cluster, read-only with `view`), the `notAfter` date from step 1 and the cluster's address (the
file's `server:` line). They save, check and use it with [USER-KUBECONFIG.md](USER-KUBECONFIG.md).

### 3. Renew the certificate (cluster administrator)

A certificate cannot be renewed: before it ends, run step 1 again (it makes a new name), send the
new file, and take the old name's rights away (step 4).

### 4. Take the certificate away (cluster administrator)

Do this when the person should lose access, or has a new certificate from step 3. It deletes the
name's ClusterRoleBindings (`-cluster-admin` and `-view`, whichever step 1 made with
`VKS_CLUSTER_NAMESPACE="*"`) and, in the namespace, its RoleBindings (`-edit` and `-view`), whatever
`ROLE` step 1 used, then says `FAILED` if a RoleBinding in any namespace still names it (a
`VKS_CLUSTER_NAMESPACE` other than step 1's deletes nothing there) and asks the cluster whether that
name may still list pods in every namespace (and, with a namespace, in it); nothing
else changes. The
name then has no rights, but the certificate keeps proving the name until its end date (`notAfter`),
so never give that name rights again. With `edit`, tokens they made for any ServiceAccount in `VKS_CLUSTER_NAMESPACE`, and
workloads they started, keep working: delete those workloads, re-create every ServiceAccount there that has rights, and restart the workloads that use those ServiceAccounts. With `"*"` and `edit`, logins made with it as a cluster administrator keep working. Set `NAME` to the name from step 1's `subject=` line, and
`VKS_CLUSTER`, `ADMIN_KUBECONFIG` and `VKS_CLUSTER_NAMESPACE` to what step 1 used.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
NAME="alice-20261029223015"
VKS_CLUSTER_NAMESPACE="team-a"

if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set it to what step 1 used (a namespace, or "*"); nothing was changed'
else
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" delete clusterrolebinding "${NAME}-cluster-admin" "${NAME}-view" --ignore-not-found
  if [ "$VKS_CLUSTER_NAMESPACE" != "*" ]; then
    kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$VKS_CLUSTER_NAMESPACE" delete rolebinding "${NAME}-edit" "${NAME}-view" --ignore-not-found
    echo "${NAME} may still list pods in ${VKS_CLUSTER_NAMESPACE}: $(kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$VKS_CLUSTER_NAMESPACE" auth can-i list pods --as="$NAME")"
  fi
  if RB="$(kubectl --kubeconfig "$ADMIN_KUBECONFIG" get rolebindings -A --no-headers -o 'custom-columns=NS:.metadata.namespace,N:.metadata.name,S:.subjects[*].name')"; then
    LEFT="$(printf '%s\n' "$RB" | awk -v n="$NAME" '{k = split($3, s, ","); for (i = 1; i <= k; i++) if (s[i] == n) print $1 "/" $2}')"
    if [ -n "$LEFT" ]; then echo "FAILED: ${NAME} still has a RoleBinding: $LEFT (run this block again with that namespace)"; fi
  else
    echo "FAILED: the RoleBindings could not be read (see the error above)"
  fi
  echo "${NAME} may still list pods in every namespace: $(kubectl --kubeconfig "$ADMIN_KUBECONFIG" auth can-i list pods --all-namespaces --as="$NAME")"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$NAME = "alice-20261029223015"
$VKS_CLUSTER_NAMESPACE = "team-a"

if (-not $VKS_CLUSTER_NAMESPACE) {
  'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set it to what step 1 used (a namespace, or "*"); nothing was changed'
} else {
  kubectl --kubeconfig $ADMIN_KUBECONFIG delete clusterrolebinding "$NAME-cluster-admin" "$NAME-view" --ignore-not-found
  if ($VKS_CLUSTER_NAMESPACE -ne '*') {
    kubectl --kubeconfig $ADMIN_KUBECONFIG -n $VKS_CLUSTER_NAMESPACE delete rolebinding "$NAME-edit" "$NAME-view" --ignore-not-found
    "$NAME may still list pods in ${VKS_CLUSTER_NAMESPACE}: $(kubectl --kubeconfig $ADMIN_KUBECONFIG -n $VKS_CLUSTER_NAMESPACE auth can-i list pods "--as=$NAME")"
  }
  $global:LASTEXITCODE = $null
  $RB = kubectl --kubeconfig $ADMIN_KUBECONFIG get rolebindings -A --no-headers -o 'custom-columns=NS:.metadata.namespace,N:.metadata.name,S:.subjects[*].name'
  if ($LASTEXITCODE -ne 0) {
    'FAILED: the RoleBindings could not be read (see the error above)'
  } else {
    $LEFT = @($RB | Where-Object { (($_ -split '\s+')[2] -split ',') -contains $NAME } | ForEach-Object { $f = $_ -split '\s+'; "$($f[0])/$($f[1])" })
    if ($LEFT.Count) { "FAILED: $NAME still has a RoleBinding: $($LEFT -join ' ') (run this block again with that namespace)" }
  }
  "$NAME may still list pods in every namespace: $(kubectl --kubeconfig $ADMIN_KUBECONFIG auth can-i list pods --all-namespaces "--as=$NAME")"
}
```

</details>

**Expect:** `rolebinding.rbac.authorization.k8s.io "alice-20261029223015-edit" deleted` (or `-view`;
newer kubectl: `… deleted from team-a namespace`) and `alice-20261029223015 may still list pods in
team-a: no`; with `VKS_CLUSTER_NAMESPACE="*"`,
`clusterrolebinding.rbac.authorization.k8s.io "alice-20261029223015-cluster-admin" deleted` (or
`-view`). Then `alice-20261029223015 may still list pods in every namespace: no`.

**If not:** no `deleted` line: the binding is already gone, or `NAME` or
`VKS_CLUSTER_NAMESPACE` is not what step 1 printed and used. `may still …: yes`:
another binding gives that name rights; find it with `kubectl --kubeconfig "$ADMIN_KUBECONFIG" get
rolebindings,clusterrolebindings -A -o wide | grep "$NAME"` and delete it. `FAILED: … still has a RoleBinding: team-a/…`:
step 1 used that namespace (`VKS_CLUSTER_NAMESPACE` was `"*"` or another namespace, so nothing there
was deleted); run the block again with it.

## Glossary

The words used here are explained in the [Glossary](GLOSSARY.md).

## References

**Official Broadcom documentation (VCF 9.1), Kubernetes documentation and vCenter API reference for this guide**

- [Connect to the VKS Cluster Control Plane as a Kubernetes Administrator](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/configuring-identity-and-access-for-tkg-service-clusters/connect-to-the-tkg-service-cluster-control-plane-as-a-kubernetes-administrator.html) (the administrator kubeconfig)
- [Configure vSphere Namespace Permissions for vCenter Single Sign-On Users and Groups](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service/configuring-vsphere-namespaces-for-hosting-tkg-service-clusters/configure-vsphere-namespace-persmissions-for-vcenter-sso-users-and-groups.html)
- Broadcom KB 423015: [Generate Non-Expiring Token in TKG cluster](https://knowledge.broadcom.com/external/article/423015/generate-nonexpiring-token-in-tkg-cluste.html) (written for Supervisor 8.x; the administrator ServiceAccount token)
- Kubernetes: [Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/) (ServiceAccount tokens, client certificates), [Certificates and Certificate Signing Requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/), [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) (the `edit` and `view` roles)

Back to [README](../README.md).
