# Give people and tools access to a VKS cluster

> [!NOTE]
> **Official Broadcom documentation (VCF 9.1), Kubernetes documentation and vCenter API reference for this guide**
>
> - [Connect to the VKS Cluster Control Plane as a Kubernetes Administrator](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/configuring-identity-and-access-for-tkg-service-clusters/connect-to-the-tkg-service-cluster-control-plane-as-a-kubernetes-administrator.html) (the administrator kubeconfig)
> - [Configure vSphere Namespace Permissions for vCenter Single Sign-On Users and Groups](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service/configuring-vsphere-namespaces-for-hosting-tkg-service-clusters/configure-vsphere-namespace-persmissions-for-vcenter-sso-users-and-groups.html)
> - Broadcom KB 423015: [Generate Non-Expiring Token in TKG cluster](https://knowledge.broadcom.com/external/article/423015/generate-nonexpiring-token-in-tkg-cluste.html) (written for Supervisor 8.x; the administrator ServiceAccount token)
> - Kubernetes: [Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/) (ServiceAccount tokens, client certificates), [Certificates and Certificate Signing Requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/), [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) (the `edit` and `view` roles)

Your internal customers (application developers, testers, DevOps engineers and their pipelines)
work in a VKS cluster with kubectl, the Kubernetes command-line tool. This guide gives each of them
their own access, with only the rights they need, so that you never send the cluster's
administrator kubeconfig and can take each access away on its own.

Words like *vSphere Namespace*, *ServiceAccount* and *RoleBinding* are explained in the
[Glossary](#glossary).

**Which way for which customer:**

| your customer | the way | why this way |
|---|---|---|
| a developer, tester or DevOps engineer with a vCenter SSO account | [The person's own SSO account](#the-persons-own-sso-account) | they log in as themselves; you send no secret; you take it away in vCenter and the cluster |
| people in your organization's identity provider (Keycloak in this guide) with no vCenter account | [A group from an external identity provider, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md#prerequisites) (its own guide) | you give rights once, to a group; the identity provider decides who is in it; one file with no secret serves the whole group |
| a CI pipeline, a deployment tool, or a team that shares one login, in one namespace | [A ServiceAccount token](#a-serviceaccount-token) | no person's account; works unattended for the days you set; deleting it stops every copy |
| a tool or a person that needs the whole cluster | [An administrator ServiceAccount token (whole cluster)](#an-administrator-serviceaccount-token-whole-cluster) | send it instead of the administrator kubeconfig: this one can be taken away |
| one person with no SSO or identity provider account, for a few days | [A personal certificate](#a-personal-certificate) | needs nothing but kubectl; it cannot be withdrawn before it ends, so keep it short |
| people in an identity provider that is not registered on the Supervisor | [An external identity provider on one cluster](KEYCLOAK.md#prerequisites) (its own guide) | a new cluster (VKS 3.8) is created to trust the provider; people need kubectl and kubelogin |

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
| the person | gets the access | logs in ([USER-LOGIN.md](USER-LOGIN.md)), or uses the file they were sent |
| a tool | a CI/CD pipeline, a deployment tool or a script, with no person behind it | uses the token file it was given; makes no login of its own and never renews; the cluster administrator renews the file before it ends |

**The ways:**

- [Their own SSO account](#the-persons-own-sso-account): [role](#1-give-the-person-a-role-on-the-vsphere-namespace-vcenter-administrator) → [rights](#2-give-the-person-rights-inside-the-cluster-cluster-administrator) → they [log in](#3-log-in-with-the-vcf-cli-the-person) → [take away](#5-take-it-away-cluster-administrator-vcenter-administrator)
- [A group from an identity provider](ADMIN-GRANT-ACCESS-IDP.md#prerequisites) (its own guide): [provider name](ADMIN-GRANT-ACCESS-IDP.md#1-read-the-provider-name-and-prefix-vcenter-administrator) → [role](ADMIN-GRANT-ACCESS-IDP.md#2-give-the-group-a-role-on-the-vsphere-namespace-vcenter-administrator) → [rights](ADMIN-GRANT-ACCESS-IDP.md#3-give-the-group-rights-inside-the-vks-cluster-cluster-administrator) → [kubeconfig](ADMIN-GRANT-ACCESS-IDP.md#4-make-the-groups-kubeconfig-and-hand-it-over-cluster-administrator) → they [log in](ADMIN-GRANT-ACCESS-IDP.md#5-log-in-the-person) → [take away](ADMIN-GRANT-ACCESS-IDP.md#8-take-the-groups-access-away-cluster-administrator-vcenter-administrator)
- [A ServiceAccount token](#a-serviceaccount-token): [make](#1-make-the-teams-token-and-its-file-cluster-administrator) → [hand over](#2-hand-it-over-and-use-it-cluster-administrator-then-the-team-or-tool) → [renew](#3-renew-the-teams-token-cluster-administrator) → [take away](#4-take-the-teams-token-away-cluster-administrator)
- [An administrator token (whole cluster)](#an-administrator-serviceaccount-token-whole-cluster): [make](#1-make-the-administrator-token-and-its-file-cluster-administrator) → [hand over](#2-hand-it-over-and-use-it-on-another-machine-cluster-administrator-then-the-tool-or-person) → [renew](#3-renew-the-administrator-token-cluster-administrator) → [take away](#4-take-the-administrator-token-away-cluster-administrator)
- [A personal certificate](#a-personal-certificate): [make](#1-make-the-certificate-and-its-file-cluster-administrator) → [hand over](#2-hand-it-over-and-use-it-cluster-administrator-then-the-person) → [renew](#3-renew-the-certificate-cluster-administrator) → [take away](#4-take-the-certificate-away-cluster-administrator)

Compare the ways:

| way | set up by | they need | lasts | to take it away |
|---|---|---|---|---|
| [The person's own SSO account](#the-persons-own-sso-account) | the vCenter administrator, then the cluster administrator | kubectl, and the VCF CLI or the kubectl vSphere plugin | 10 hours per login | delete the person's RoleBinding and their role on the vSphere Namespace |
| [A group from an external identity provider, through the Supervisor](ADMIN-GRANT-ACCESS-IDP.md#prerequisites) (its own guide) | the identity provider's, vCenter and cluster administrators | kubectl and the VCF CLI | while the person's sign-in lasts | disable the user in the identity provider, or delete the group's RoleBinding and its role on the vSphere Namespace |
| [A ServiceAccount token](#a-serviceaccount-token) | the cluster administrator | kubectl | the days you set | delete the ServiceAccount: every copy stops |
| [An administrator ServiceAccount token (whole cluster)](#an-administrator-serviceaccount-token-whole-cluster) | the cluster administrator | kubectl | the days you set (365 for a year), or until you take it away | delete its ClusterRoleBinding, token Secret and ServiceAccount: every copy stops (not logins the holder made) |
| [A personal certificate](#a-personal-certificate) | the cluster administrator | kubectl | the days you set | cannot be withdrawn: delete its RoleBinding and never bind its name again |
| [An external identity provider on one cluster](KEYCLOAK.md#prerequisites) (its own guide) | the identity provider's and cluster administrators | kubectl and kubelogin | while the person's sign-in lasts | delete the group's RoleBinding |

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
  [USER-LOGIN.md](USER-LOGIN.md#prerequisites) lists.

The connections this guide needs, for a firewall (all TCP, besides DNS):

| from | to | port | for |
|---|---|---|---|
| the cluster administrator's machine | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl as the cluster's administrator (every way) |
| the person's or tool's machine | the VKS cluster's API address | 6443 | kubectl with the file you sent (the token and certificate ways) |

For the SSO way, the person's connections are in [USER-LOGIN.md](USER-LOGIN.md#prerequisites).

## The person's own SSO account

Pick this for people who have a vCenter SSO account. They log in as themselves with the VCF CLI,
and the login writes their own kubeconfig: you send them names and the vCenter CA, not a
kubeconfig. The vCenter administrator lets them log in (step 1), the cluster administrator gives
them rights inside the cluster (step 2), then the person logs in (step 3) and uses the cluster
(step 4) with [USER-LOGIN.md](USER-LOGIN.md). A login lasts 10 hours. Without the VCF CLI, people
log in with the kubectl vSphere plugin instead
([USER-LOGIN.md](USER-LOGIN.md#the-kubectl-vsphere-plugin-instead-of-the-vcf-cli-optional-and-deprecated)).

### 1. Give the person a role on the vSphere Namespace (vCenter administrator)

Give the person's SSO user the **Can view** role (**Namespaces View**) on the vSphere Namespace
([NAMESPACE.md](NAMESPACE.md) step 4). Not **Can edit** or **Owner**: those make them an
administrator of every VKS cluster in the namespace. Then send the person the Supervisor's
address, the vSphere Namespace's and the cluster's names, and the vCenter CA file
([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca), step 1), and send the cluster
administrator the person's SSO user name exactly as vCenter lists it, letter case included
(step 2).

### 2. Give the person rights inside the cluster (cluster administrator)

Do this before the person logs in: the role from step 1 lets them log in, but gives no rights
inside the VKS cluster. It makes the namespace `TEAM_NAMESPACE` inside the VKS cluster (a
folder for the team's workloads, not the vSphere Namespace) if it is not there, and a RoleBinding
(the record that gives a name a role in one namespace) that gives the name `edit`: create, change
and delete most things in it. The person can then deploy in that namespace: send them its name
([USER-LOGIN.md step 3](USER-LOGIN.md#3-use-the-login)). Run it once per person; for the same name again it answers `already exists`.

Set `VKS_CLUSTER` to the cluster's name (`ADMIN_KUBECONFIG` is then its administrator kubeconfig
from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig); change it if you saved that file
elsewhere), `TEAM_NAMESPACE` to the team's namespace, and `SSO_USER` to the person's SSO user
name exactly as vCenter lists it, letter case included: logins ignore letter case, the cluster does
not (vCenter's own `administrator@vsphere.local` is `sso:Administrator@vsphere.local` there), and
a name in other letter case gets no rights.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SSO_USER="Alice@vsphere.local"
TEAM_NAMESPACE="team-a"

SSO_NAME="sso:${SSO_USER}"
B="$(printf '%s' "$SSO_NAME" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9.\n' '-')-edit"
kubectl --kubeconfig "$ADMIN_KUBECONFIG" create namespace "$TEAM_NAMESPACE" --dry-run=client -o yaml | kubectl --kubeconfig "$ADMIN_KUBECONFIG" apply -f - >/dev/null
kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$TEAM_NAMESPACE" create rolebinding "$B" --clusterrole=edit --user="$SSO_NAME"
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SSO_USER = "Alice@vsphere.local"
$TEAM_NAMESPACE = "team-a"

$SSO_NAME = "sso:$SSO_USER"
$B = ($SSO_NAME.ToLower() -replace '[^a-z0-9.]', '-') + '-edit'
kubectl --kubeconfig $ADMIN_KUBECONFIG create namespace $TEAM_NAMESPACE --dry-run=client -o yaml | kubectl --kubeconfig $ADMIN_KUBECONFIG apply -f - | Out-Null
kubectl --kubeconfig $ADMIN_KUBECONFIG -n $TEAM_NAMESPACE create rolebinding $B --clusterrole=edit "--user=$SSO_NAME"
```

**Expect:** `rolebinding.rbac.authorization.k8s.io/sso-alice-vsphere.local-edit created`. The
person's check in [USER-LOGIN.md step 3](USER-LOGIN.md#3-use-the-login) then answers `yes`.

**If not:** `already exists`: a binding of that name is there, perhaps for the name in other letter
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
  ([NAMESPACE.md](NAMESPACE.md) step 4), and disable the SSO user if they should lose vCenter as
  well.

If the person's check in [USER-LOGIN.md step 3](USER-LOGIN.md#3-use-the-login) still answers `yes`
afterwards, they also have rights through a group: a group with **Can edit** or **Owner** on the
vSphere Namespace is an administrator of every VKS cluster in it. Take the person out of that group, or take the group's role away in vCenter.

<a id="the-kubectl-vsphere-plugin-instead-of-the-vcf-cli-optional-and-deprecated"></a>
<a id="1-windows-and-macos-trust-the-vcenter-ca-the-person-once"></a>
<a id="2-install-the-kubectl-vsphere-plugin-the-person-once"></a>
<a id="3-log-in-with-the-plugin-the-person"></a>

Without the VCF CLI, the person logs in with the kubectl vSphere plugin (optional and deprecated):
[USER-LOGIN.md](USER-LOGIN.md#the-kubectl-vsphere-plugin-instead-of-the-vcf-cli-optional-and-deprecated).

## A ServiceAccount token

Pick this for a CI pipeline, a deployment tool, or a team that shares one login, in one namespace.
The file holds a token for a ServiceAccount (a login inside the cluster that belongs to no person):
whoever has a copy acts in the cluster as that ServiceAccount
(`system:serviceaccount:kubeconfig-access:team-a`), not as a person. Removing or disabling an SSO
or identity provider user does not take it away; only deleting the ServiceAccount does (step 4).

The ServiceAccount lives in its own namespace inside the VKS cluster, `SA_NAMESPACE`, where the
team has no rights (so it cannot make more tokens for it), and gets its role in `TEAM_NAMESPACE`.
Pick `DAYS` as short as the work allows: 30 by default, never more than 90 for a team; the cluster
does not shorten it. Never give `edit` on a namespace that holds software with wider rights (step
4 says why).

<a id="make-it"></a>

### 1. Make the team's token and its file (cluster administrator)

Do this when a team or a tool needs its own login to one namespace inside the VKS cluster (a folder
for the team's workloads, not a vSphere Namespace).

It makes, inside the cluster: that namespace if it is not there; a ServiceAccount for the team (a
login that belongs to no person) in the namespace `SA_NAMESPACE`; and a RoleBinding (the record
that gives a login a role in one namespace) that lets it deploy (`edit`) or only read (`view`) in
the team's namespace. It then makes a token, the key of that login, valid for the days you set,
writes it into a kubeconfig file readable only by you, and shows when the token ends, which login
it is and what it may do.

You then have one file, `TEAM_KUBECONFIG`, for that team or tool: send it to them (step 2). Run it
again for the same team and it writes a new file with a new token in its place; copies of the old
file keep working until the old token ends (step 3). A changed `ROLE` adds a second RoleBinding and
keeps the old one: delete `<TEAM>-<old role>` first.

Set `VKS_CLUSTER` to the cluster's name (`ADMIN_KUBECONFIG` is then its administrator kubeconfig
from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig); change it if you saved that file
elsewhere), `TEAM` to a name for the team or tool, `TEAM_NAMESPACE` to its namespace, `ROLE` to
`edit` or `view`, and `DAYS` to the days (above).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEAM="team-a"
TEAM_NAMESPACE="team-a"
SA_NAMESPACE="kubeconfig-access"
ROLE="edit"
DAYS="30"
TEAM_KUBECONFIG="$HOME/${VKS_CLUSTER}-${TEAM}.kubeconfig"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
for NS in "$SA_NAMESPACE" "$TEAM_NAMESPACE"; do
  adm create namespace "$NS" --dry-run=client -o yaml | adm apply -f - >/dev/null
done
adm -n "$SA_NAMESPACE" create serviceaccount "$TEAM" --dry-run=client -o yaml | adm apply -f - >/dev/null
adm -n "$TEAM_NAMESPACE" create rolebinding "${TEAM}-${ROLE}" --clusterrole="$ROLE" \
  --serviceaccount="${SA_NAMESPACE}:${TEAM}" --dry-run=client -o yaml | adm apply -f - >/dev/null
TOKEN="$(adm -n "$SA_NAMESPACE" create token "$TEAM" --duration="$((DAYS * 24))h")"
SERVER="$(adm config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
CA="$(adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
if [ -n "$TOKEN" ] && [ -n "$SERVER" ] && [ -n "$CA" ]; then
  rm -f "$TEAM_KUBECONFIG"
  ( umask 077
    printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    token: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\n    namespace: %s\ncurrent-context: %s\n' \
      "$TEAM" "$SERVER" "$CA" "$TEAM" "$TOKEN" "$TEAM" "$TEAM" "$TEAM" "$TEAM_NAMESPACE" "$TEAM" > "$TEAM_KUBECONFIG" )
  P="$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+')"
  while [ $(( ${#P} % 4 )) -ne 0 ]; do P="$P="; done
  EXP="$(printf '%s' "$P" | base64 -d 2>/dev/null | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
  if [ -n "$EXP" ]; then echo "token ends in: $(( (EXP - $(date +%s)) / 86400 )) days"; else echo "token ends in: unknown"; fi
  echo "acts as: $(kubectl --kubeconfig "$TEAM_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')"
  echo "create deployments in $TEAM_NAMESPACE: $(kubectl --kubeconfig "$TEAM_KUBECONFIG" auth can-i create deployments)"
  echo "list pods in kube-system: $(kubectl --kubeconfig "$TEAM_KUBECONFIG" auth can-i list pods -n kube-system)"
else
  echo "FAILED: no token, server or CA read (see the kubectl errors above)"
fi
unset TOKEN
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$TEAM = "team-a"
$TEAM_NAMESPACE = "team-a"
$SA_NAMESPACE = "kubeconfig-access"
$ROLE = "edit"
$DAYS = 30
$TEAM_KUBECONFIG = "$HOME\${VKS_CLUSTER}-${TEAM}.kubeconfig"

function adm { $input | kubectl --kubeconfig $ADMIN_KUBECONFIG @args }
foreach ($NS in $SA_NAMESPACE, $TEAM_NAMESPACE) { adm create namespace $NS --dry-run=client -o yaml | adm apply -f - | Out-Null }
adm -n $SA_NAMESPACE create serviceaccount $TEAM --dry-run=client -o yaml | adm apply -f - | Out-Null
adm -n $TEAM_NAMESPACE create rolebinding "$TEAM-$ROLE" "--clusterrole=$ROLE" "--serviceaccount=${SA_NAMESPACE}:$TEAM" --dry-run=client -o yaml | adm apply -f - | Out-Null
$TOKEN = adm -n $SA_NAMESPACE create token $TEAM "--duration=$($DAYS * 24)h"
$SERVER = adm config view --minify -o jsonpath='{.clusters[0].cluster.server}'
$CA = adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
if ($TOKEN -and $SERVER -and $CA) {
  Set-Content -Encoding ascii -Path $TEAM_KUBECONFIG -Value @(
    'apiVersion: v1', 'kind: Config', 'clusters:', "- name: $TEAM", '  cluster:', "    server: $SERVER",
    "    certificate-authority-data: $CA", 'users:', "- name: $TEAM", '  user:', "    token: $TOKEN",
    'contexts:', "- name: $TEAM", '  context:', "    cluster: $TEAM", "    user: $TEAM", "    namespace: $TEAM_NAMESPACE",
    "current-context: $TEAM")
  $P = $TOKEN.Split('.')[1].Replace('-', '+').Replace('_', '/'); while ($P.Length % 4) { $P += '=' }
  $EXP = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($P)) | ConvertFrom-Json).exp
  "token ends in: $([math]::Floor(($EXP - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) / 86400)) days"
  "acts as: $(kubectl --kubeconfig $TEAM_KUBECONFIG auth whoami -o jsonpath='{.status.userInfo.username}')"
  "create deployments in ${TEAM_NAMESPACE}: $(kubectl --kubeconfig $TEAM_KUBECONFIG auth can-i create deployments)"
  "list pods in kube-system: $(kubectl --kubeconfig $TEAM_KUBECONFIG auth can-i list pods -n kube-system)"
} else {
  "FAILED: no token, server or CA read (see the kubectl errors above)"
}
Remove-Variable TOKEN
```

</details>

**Expect:** `token ends in: 29 days` or `30 days` (for `DAYS="30"`),
`acts as: system:serviceaccount:kubeconfig-access:team-a`, `create deployments in team-a: yes`
(`no` with `ROLE="view"`) and `list pods in kube-system: no`.

**If not:**
- `FAILED: …` with `Forbidden` or `Unauthorized` above it: `ADMIN_KUBECONFIG` is not the cluster's
  administrator file, or it has expired; get it again.
- `may not specify a duration less than 10 minutes`: `DAYS` is 0 or empty; set it to 1 or more.

### 2. Hand it over and use it (cluster administrator, then the team or tool)

Send `TEAM_KUBECONFIG` to the team as a secret: whoever has a copy acts as the ServiceAccount
([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over)). The team saves it in their `.kube` folder,
readable only by them, and uses it with `--kubeconfig` or `KUBECONFIG`
([KUBECONFIG.md](KUBECONFIG.md#2-use-a-file)). It needs only [kubectl](KUBECTL.md) and a way to
the cluster's API address on port 6443 (the file's `server:` line): no password, SSO account or
VCF CLI. Its commands act in `TEAM_NAMESPACE` unless they name another namespace. For a pipeline,
store the file as one of the pipeline's secrets.

<a id="renew-it"></a>

### 3. Renew the team's token (cluster administrator)

Run the block in step 1 again before the token ends, with the same values, and send the team the new
file. The old file keeps working until its own end; to stop it sooner, take the access away and make
a new one.

<a id="take-it-away"></a>

### 4. Take the team's token away (cluster administrator)

Do this when the team or tool should lose its access, or a copy of the file may have leaked. It
deletes the team's ServiceAccount and **every ServiceAccount token Secret (a stored token that does
not end) in `TEAM_NAMESPACE`, also those the team did not make** (with `edit`, the team could have
made lasting ones). Every copy of the file then answers `Unauthorized` within about 15 seconds, and
making a ServiceAccount of the same name again does not bring the copies back. The team's
RoleBinding and namespace stay; delete the namespace when the team's work in it is no longer needed.
Set `TEAM`, `TEAM_NAMESPACE`, `SA_NAMESPACE`, `VKS_CLUSTER` and `ADMIN_KUBECONFIG` to what step 1
used.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
TEAM="team-a"
TEAM_NAMESPACE="team-a"
SA_NAMESPACE="kubeconfig-access"

kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$SA_NAMESPACE" delete serviceaccount "$TEAM"
kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$TEAM_NAMESPACE" delete secret --field-selector type=kubernetes.io/service-account-token
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$TEAM = "team-a"
$TEAM_NAMESPACE = "team-a"
$SA_NAMESPACE = "kubeconfig-access"

kubectl --kubeconfig $ADMIN_KUBECONFIG -n $SA_NAMESPACE delete serviceaccount $TEAM
kubectl --kubeconfig $ADMIN_KUBECONFIG -n $TEAM_NAMESPACE delete secret --field-selector type=kubernetes.io/service-account-token
```

**Expect:** `serviceaccount "team-a" deleted from kubeconfig-access namespace` (older kubectl:
`serviceaccount "team-a" deleted`), then a `deleted` line for each token Secret in `team-a`, or
`No resources found`.

**If not:**
- `Error from server (NotFound)`: the ServiceAccount is already gone, or `TEAM` or `SA_NAMESPACE`
  is not what step 1 used.

**What keeps working:** tokens the team made with `kubectl create token`, and workloads it started:
delete the team's workloads, and delete and re-create any ServiceAccount in `TEAM_NAMESPACE` that
has rights. So never give `edit` on a namespace that holds software with wider rights.

## An administrator ServiceAccount token (whole cluster)

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
login that belongs to no person) in it, and a ClusterRoleBinding `<SA_NAME>-cluster-admin` (the
record that gives a login a role in the whole cluster) that gives it `cluster-admin`, the role for
everything. It then makes a token, the key of that login, valid for the days you set, or with
`DAYS="never"` a token Secret `<SA_NAME>-token` that does not expire; writes it into a kubeconfig
file readable only by you; and shows when the token ends, which login it is and what it may do.

You then have one file, `SA_KUBECONFIG`, for that tool or person: send it (step 2). Run it again
with days and it writes a new file with a new token; copies of the old file keep working until the
old token ends. With `never` it gives the same token (step 3).

Set `VKS_CLUSTER` to the cluster's name (`ADMIN_KUBECONFIG` is then its administrator kubeconfig
from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig); change it if you saved that file
elsewhere), `SA_NAME` to a name for the tool or person, and `DAYS` to 1 to 36500 days (365 for a
year) or `never`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SA_NAME="cluster-admin-ci"
SA_NAMESPACE="kubeconfig-access"
DAYS="365"
SA_KUBECONFIG="$HOME/${VKS_CLUSTER}-${SA_NAME}.kubeconfig"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
TOKEN=""
if [ "$DAYS" != "never" ] && { ! [ "$DAYS" -ge 1 ] 2>/dev/null || [ "${DAYS#0}" != "$DAYS" ] || [ "$DAYS" -gt 36500 ]; }; then
  echo "STOPPED: DAYS is a number of days, 1 to 36500, or never: $DAYS"
else
  adm create namespace "$SA_NAMESPACE" --dry-run=client -o yaml | adm apply -f - >/dev/null
  adm -n "$SA_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | adm apply -f - >/dev/null
  adm create clusterrolebinding "${SA_NAME}-cluster-admin" --clusterrole=cluster-admin \
    --serviceaccount="${SA_NAMESPACE}:${SA_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  if [ "$DAYS" = "never" ]; then
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s-token\n  namespace: %s\n  annotations:\n    kubernetes.io/service-account.name: %s\ntype: kubernetes.io/service-account-token\n' \
      "$SA_NAME" "$SA_NAMESPACE" "$SA_NAME" | adm apply -f - >/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10; do
      TOKEN="$(adm -n "$SA_NAMESPACE" get secret "${SA_NAME}-token" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null)"
      if [ -n "$TOKEN" ]; then break; fi
      sleep 2
    done
    if [ -z "$TOKEN" ]; then adm -n "$SA_NAMESPACE" delete secret "${SA_NAME}-token" --ignore-not-found >/dev/null; fi
  else
    TOKEN="$(adm -n "$SA_NAMESPACE" create token "$SA_NAME" --duration="$((DAYS * 24))h")"
  fi
  SERVER="$(adm config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
  CA="$(adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  if [ -n "$TOKEN" ] && [ -n "$SERVER" ] && [ -n "$CA" ]; then
    rm -f "$SA_KUBECONFIG"
    ( umask 077
      printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    token: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\ncurrent-context: %s\n' \
        "$SA_NAME" "$SERVER" "$CA" "$SA_NAME" "$TOKEN" "$SA_NAME" "$SA_NAME" "$SA_NAME" "$SA_NAME" > "$SA_KUBECONFIG" )
    P="$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+')"
    while [ $(( ${#P} % 4 )) -ne 0 ]; do P="$P="; done
    EXP="$(printf '%s' "$P" | base64 -d 2>/dev/null | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
    if [ -n "$EXP" ]; then echo "token ends in: $(( (EXP - $(date +%s)) / 86400 )) days"
    elif [ "$DAYS" = "never" ]; then echo "token ends: never (until you take it away)"
    else echo "token ends in: unknown"; fi
    echo "acts as: $(kubectl --kubeconfig "$SA_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')"
    echo "everything in every namespace: $(kubectl --kubeconfig "$SA_KUBECONFIG" auth can-i '*' '*' --all-namespaces)"
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
$SA_NAME = "cluster-admin-ci"
$SA_NAMESPACE = "kubeconfig-access"
$DAYS = "365"
$SA_KUBECONFIG = "$HOME\${VKS_CLUSTER}-${SA_NAME}.kubeconfig"

function adm { $input | kubectl --kubeconfig $ADMIN_KUBECONFIG @args }
$TOKEN = $null; $B = $null
if ($DAYS -ne "never" -and ("$DAYS" -notmatch '^[1-9][0-9]{0,4}$' -or [int]"$DAYS" -gt 36500)) {
  "STOPPED: DAYS is a number of days, 1 to 36500, or never: $DAYS"
} else {
  adm create namespace $SA_NAMESPACE --dry-run=client -o yaml | adm apply -f - | Out-Null
  adm -n $SA_NAMESPACE create serviceaccount $SA_NAME --dry-run=client -o yaml | adm apply -f - | Out-Null
  adm create clusterrolebinding "$SA_NAME-cluster-admin" "--clusterrole=cluster-admin" "--serviceaccount=${SA_NAMESPACE}:$SA_NAME" --dry-run=client -o yaml | adm apply -f - | Out-Null
  if ($DAYS -eq "never") {
    @('apiVersion: v1', 'kind: Secret', 'metadata:', "  name: $SA_NAME-token", "  namespace: $SA_NAMESPACE", '  annotations:',
      "    kubernetes.io/service-account.name: $SA_NAME", 'type: kubernetes.io/service-account-token') | adm apply -f - | Out-Null
    foreach ($i in 1..10) {
      $B = adm -n $SA_NAMESPACE get secret "$SA_NAME-token" -o jsonpath='{.data.token}' 2>$null
      if ($B) { $TOKEN = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B)); break }
      Start-Sleep 2
    }
    if (-not $TOKEN) { adm -n $SA_NAMESPACE delete secret "$SA_NAME-token" --ignore-not-found | Out-Null }
  } else {
    $TOKEN = adm -n $SA_NAMESPACE create token $SA_NAME "--duration=$([int]$DAYS * 24)h"
  }
  $SERVER = adm config view --minify -o jsonpath='{.clusters[0].cluster.server}'
  $CA = adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
  if ($TOKEN -and $SERVER -and $CA) {
    Set-Content -Encoding ascii -Path $SA_KUBECONFIG -Value @(
      'apiVersion: v1', 'kind: Config', 'clusters:', "- name: $SA_NAME", '  cluster:', "    server: $SERVER",
      "    certificate-authority-data: $CA", 'users:', "- name: $SA_NAME", '  user:', "    token: $TOKEN",
      'contexts:', "- name: $SA_NAME", '  context:', "    cluster: $SA_NAME", "    user: $SA_NAME", "current-context: $SA_NAME")
    $P = $TOKEN.Split('.')[1].Replace('-', '+').Replace('_', '/'); while ($P.Length % 4) { $P += '=' }
    $EXP = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($P)) | ConvertFrom-Json).exp
    if ($EXP) { "token ends in: $([math]::Floor(($EXP - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) / 86400)) days" }
    elseif ($DAYS -eq "never") { "token ends: never (until you take it away)" }
    else { "token ends in: unknown" }
    "acts as: $(kubectl --kubeconfig $SA_KUBECONFIG auth whoami -o jsonpath='{.status.userInfo.username}')"
    "everything in every namespace: $(kubectl --kubeconfig $SA_KUBECONFIG auth can-i '*' '*' --all-namespaces)"
  } else {
    "FAILED: no token, server or CA read (see the kubectl errors above)"
  }
}
Remove-Variable TOKEN, B
```

</details>

**Expect:** `token ends in: 364 days` or `365 days` (for `DAYS="365"`; `token ends: never (until you
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

Send `SA_KUBECONFIG` as a secret ([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over)). The file
needs no password, no SSO account and no VCF CLI: only [kubectl](KUBECTL.md) and a way to the
cluster's API address on port 6443 (the file's `server:` line). Save it in your `.kube` folder under
the name it came with, `<cluster>-<SA_NAME>.kubeconfig` (for example
`my-vks-cluster-cluster-admin-ci.kubeconfig`; Windows: `$HOME\.kube\…`).

Run this once on the machine that received the file, before a tool relies on it. It makes the file
readable only by you and shows who it acts as. It then creates a test namespace `CHECK_NAMESPACE`
inside the cluster with a ConfigMap (a small object that holds settings) in it, changes the
ConfigMap and reads it back, then deletes that namespace again. You then know the file can create,
change and delete in the cluster; afterwards use it with `--kubeconfig` or `KUBECONFIG`
([KUBECONFIG.md](KUBECONFIG.md#2-use-a-file)). Set `VKS_CLUSTER` and `SA_NAME` to the names the
cluster administrator used, as in the file's name.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
SA_NAME="cluster-admin-ci"
SA_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}-${SA_NAME}.kubeconfig"
CHECK_NAMESPACE="access-check"

k() { kubectl --kubeconfig "$SA_KUBECONFIG" "$@"; }
chmod 600 "$SA_KUBECONFIG"
echo "acts as: $(k auth whoami -o jsonpath='{.status.userInfo.username}')"
k create namespace "$CHECK_NAMESPACE"
k -n "$CHECK_NAMESPACE" create configmap check --from-literal=step=created --save-config
k -n "$CHECK_NAMESPACE" create configmap check --from-literal=step=updated --dry-run=client -o yaml | k apply -f -
echo "read back: $(k -n "$CHECK_NAMESPACE" get configmap check -o jsonpath='{.data.step}')"
k delete namespace "$CHECK_NAMESPACE"
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$SA_NAME = "cluster-admin-ci"
$SA_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}-${SA_NAME}.kubeconfig"
$CHECK_NAMESPACE = "access-check"

function k { $input | kubectl --kubeconfig $SA_KUBECONFIG @args }
icacls $SA_KUBECONFIG /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null
"acts as: $(k auth whoami -o jsonpath='{.status.userInfo.username}')"
k create namespace $CHECK_NAMESPACE
k -n $CHECK_NAMESPACE create configmap check --from-literal=step=created --save-config
k -n $CHECK_NAMESPACE create configmap check --from-literal=step=updated --dry-run=client -o yaml | k apply -f -
"read back: $(k -n $CHECK_NAMESPACE get configmap check -o jsonpath='{.data.step}')"
k delete namespace $CHECK_NAMESPACE
```

**Expect:** `acts as: system:serviceaccount:kubeconfig-access:cluster-admin-ci`,
`namespace/access-check created`, `configmap/check created`, `configmap/check configured`,
`read back: updated`, then `namespace "access-check" deleted`.

**If not:**
- `Unable to connect to the server` or `i/o timeout`: this machine cannot reach the `server:`
  address on port 6443 (Prerequisites, firewall).
- `x509: certificate signed by unknown authority`: the file was changed, is for another cluster, or
  a proxy between this machine and the cluster replaces the certificate; ask for the file again, or
  reach the cluster without the proxy.
- `Unauthorized`: the access was taken away, or a token with days has ended; ask for a new file.
- `already exists`: a test namespace of that name is there; set `CHECK_NAMESPACE` to another name.
- `No such file` (Windows: `cannot find`): set `VKS_CLUSTER` and `SA_NAME` to the names in the saved
  file's name.

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
Run again, it deletes only what is left. Set `VKS_CLUSTER`, `ADMIN_KUBECONFIG`, `SA_NAME` and
`SA_NAMESPACE` to what step 1 used.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SA_NAME="cluster-admin-ci"
SA_NAMESPACE="kubeconfig-access"
SA_KUBECONFIG="$HOME/${VKS_CLUSTER}-${SA_NAME}.kubeconfig"

kubectl --kubeconfig "$ADMIN_KUBECONFIG" delete clusterrolebinding "${SA_NAME}-cluster-admin" --ignore-not-found
kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$SA_NAMESPACE" delete secret "${SA_NAME}-token" --ignore-not-found
kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$SA_NAMESPACE" delete serviceaccount "$SA_NAME" --ignore-not-found
sleep 20; kubectl --kubeconfig "$SA_KUBECONFIG" get namespaces
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$SA_NAME = "cluster-admin-ci"
$SA_NAMESPACE = "kubeconfig-access"
$SA_KUBECONFIG = "$HOME\${VKS_CLUSTER}-${SA_NAME}.kubeconfig"

kubectl --kubeconfig $ADMIN_KUBECONFIG delete clusterrolebinding "$SA_NAME-cluster-admin" --ignore-not-found
kubectl --kubeconfig $ADMIN_KUBECONFIG -n $SA_NAMESPACE delete secret "$SA_NAME-token" --ignore-not-found
kubectl --kubeconfig $ADMIN_KUBECONFIG -n $SA_NAMESPACE delete serviceaccount $SA_NAME --ignore-not-found
Start-Sleep 20; kubectl --kubeconfig $SA_KUBECONFIG get namespaces
```

**Expect:** a `deleted` line for each that existed (the Secret only with `DAYS="never"`), then
`error: You must be logged in to the server (Unauthorized)`.

**If not:**
- `Forbidden` or `Unauthorized` on the delete lines: `ADMIN_KUBECONFIG` is not the cluster's
  administrator file, or it has expired; get it again and run the block again.
- The last command lists namespaces: wait a minute and run it again; if it still does, check that
  `SA_NAME` and `SA_NAMESPACE` are what step 1 used.
- `no such file or directory` on the last line: your copy is gone or has another name; the deletes
  above did the work.

## A personal certificate

Pick this for one person with no SSO or identity provider account, for a few days. The file holds a
key and a certificate signed by the cluster: whoever has a copy acts as that person, with kubectl
alone. A certificate cannot be withdrawn before it ends: taking it away removes the rights of its
name, and that name is never given rights again.

### 1. Make the certificate and its file (cluster administrator)

Do this when such a person needs access (on Windows, in WSL).

It makes a key (the secret that proves who holds the file) and a certificate signing request: a
request to the cluster to sign a certificate for a new name, `PERSON` plus the date and time (for
example `alice-20261029223015`), valid for `DAYS` days. It approves the request, so the cluster
signs it, then deletes the request. It makes the namespace `TEAM_NAMESPACE` inside the VKS cluster
if it is not there, and a RoleBinding (the record that gives a name a role in one namespace) that
gives that name `edit` in it, and writes the kubeconfig, key included, readable only by you.

You then have one file, `PERSON_KUBECONFIG`, for that person: send it (step 2). Each run makes a
new name, so that you can take each certificate away alone; an older name keeps its rights until
step 4.

Set `VKS_CLUSTER` to the cluster's name (`ADMIN_KUBECONFIG` is then its administrator kubeconfig
from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig); change it if you saved that file
elsewhere), `PERSON` to a short name for the person, `TEAM_NAMESPACE` to their namespace, and
`DAYS` to as few days as they need.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
PERSON="alice"
TEAM_NAMESPACE="team-a"
DAYS="30"
PERSON_KUBECONFIG="$HOME/${VKS_CLUSTER}-${PERSON}.kubeconfig"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
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
  adm create namespace "$TEAM_NAMESPACE" --dry-run=client -o yaml | adm apply -f - >/dev/null
  adm -n "$TEAM_NAMESPACE" create rolebinding "${NAME}-edit" --clusterrole=edit --user="$NAME" >/dev/null
  rm -f "$PERSON_KUBECONFIG"
  ( umask 077
    printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    client-certificate-data: %s\n    client-key-data: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\n    namespace: %s\ncurrent-context: %s\n' \
      "$NAME" "$SERVER" "$CA" "$NAME" "$CERT" "$(base64 < "$TMP/key.pem" | tr -d '\n')" \
      "$NAME" "$NAME" "$NAME" "$TEAM_NAMESPACE" "$NAME" > "$PERSON_KUBECONFIG" )
  openssl x509 -in "$TMP/cert.pem" -noout -subject -enddate
  echo "create deployments in $TEAM_NAMESPACE: $(kubectl --kubeconfig "$PERSON_KUBECONFIG" auth can-i create deployments)"
else
  echo "FAILED: no matching certificate, server or CA (see the kubectl errors above)"
fi
adm delete csr "$CSR" --ignore-not-found >/dev/null; rm -rf "$TMP"
```

</details>

**Expect:** `subject=CN=alice-…` (or `subject=CN = alice-…`, `subject= /CN=alice-…`), `notAfter=` about `DAYS` days from
now (the cluster signs for at most a year), and `create deployments in team-a: yes`. Write down the
name: you need it to take the access away.

**If not:** `FAILED: …` with `Forbidden` or `Unauthorized` above it: `ADMIN_KUBECONFIG` is not the
cluster's administrator file, or it has expired.

### 2. Hand it over and use it (cluster administrator, then the person)

Send `PERSON_KUBECONFIG` to the person as a secret: it holds their key
([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over)). They save it in their `.kube` folder, readable
only by them, and use it with `--kubeconfig` or `KUBECONFIG`
([KUBECONFIG.md](KUBECONFIG.md#2-use-a-file)): they need only [kubectl](KUBECTL.md), no password.
Its commands act in `TEAM_NAMESPACE` unless they name another namespace.

### 3. Renew the certificate (cluster administrator)

A certificate cannot be renewed: before it ends, run step 1 again (it makes a new name), send the
new file, and take the old name's rights away (step 4).

### 4. Take the certificate away (cluster administrator)

Do this when the person should lose access, or has a new certificate from step 3. It deletes the
RoleBinding of the name from step 1; nothing else changes. That name then has no rights in
`TEAM_NAMESPACE`, but the certificate keeps proving the name until its end date (`notAfter`), so
never give that name rights again. Set `NAME` to the name from step 1's `subject=` line, and
`VKS_CLUSTER`, `ADMIN_KUBECONFIG` and `TEAM_NAMESPACE` to what step 1 used.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
NAME="alice-20261029223015"
TEAM_NAMESPACE="team-a"

kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$TEAM_NAMESPACE" delete rolebinding "${NAME}-edit"
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$ADMIN_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$NAME = "alice-20261029223015"
$TEAM_NAMESPACE = "team-a"

kubectl --kubeconfig $ADMIN_KUBECONFIG -n $TEAM_NAMESPACE delete rolebinding "$NAME-edit"
```

**Expect:** `rolebinding.rbac.authorization.k8s.io "alice-20261029223015-edit" deleted` (newer
kubectl: `… deleted from team-a namespace`).

**If not:** `Error from server (NotFound)`: the RoleBinding is already gone, or `NAME` or
`TEAM_NAMESPACE` is not what step 1 printed and used.

## Glossary

**The words used here** (more in [KUBECONFIG.md](KUBECONFIG.md#the-words-used-here)):

| word | what it is |
|---|---|
| vSphere Namespace | the vCenter object on the Supervisor that holds VKS clusters; you give people roles on it in vCenter (**Can view**, **Can edit**, **Owner**) |
| namespace | a folder inside one VKS cluster for a team's workloads, made with kubectl; not the vSphere Namespace |
| kubeconfig | a file that tells kubectl the cluster's address and the login to use; a *context* in it pairs the two (the team and certificate files also name a namespace) |
| ServiceAccount | a login that lives inside the cluster, not an SSO or identity provider user; here for a tool, a team, or a person who needs the whole cluster |
| token | the key of one login, written into the kubeconfig: whoever holds a copy is that login |
| `cluster-admin` | the built-in role for everything in the cluster |
| `edit` | the built-in role to create, change and delete most things in one namespace, its Secrets included; it can act as any ServiceAccount there, but cannot change who has rights |
| `view` | the built-in role to read most things in one namespace, but not Secrets or who has rights |
| RoleBinding, ClusterRoleBinding | what gives a user, a group or a ServiceAccount a role: in one namespace, or in the whole cluster |

Back to [README](../README.md).
