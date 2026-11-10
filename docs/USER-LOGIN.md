# Log in to a VKS cluster you were given access to

The administrator of a VKS cluster gave you access to it with your own vCenter SSO user. You log in
with the VCF CLI, which writes your own kubeconfig, then work with kubectl in the namespace you were
given. A login lasts 10 hours; your rights stay until the administrator takes them away.

Not an SSO user? [Who are you? Start here](LOGIN.md#who-are-you-start-here) sends you to the guide
for a kubeconfig file you were sent, or for your organization's identity provider.

The steps:

1. [What to ask your administrator for](#1-what-to-ask-your-administrator-for)
2. [Log in with the VCF CLI](#2-log-in-with-the-vcf-cli)
3. [Use the login](#3-use-the-login)
4. [When the login ends](#4-when-the-login-ends)

Without the VCF CLI: [the kubectl vSphere plugin](#the-kubectl-vsphere-plugin-instead-of-the-vcf-cli-optional-and-deprecated)
instead of step 2 (optional and deprecated).

## Prerequisites

- [kubectl](KUBECTL.md) and the [VCF CLI](VCF.md); for the optional plugin instead, curl and unzip
  (Photon OS: bsdtar) ([PREREQS.md](PREREQS.md));
- the names and the file from [step 1](#1-what-to-ask-your-administrator-for);
- rights given by the cluster's administrator
  ([ADMIN-GRANT-ACCESS.md](ADMIN-GRANT-ACCESS.md#the-persons-own-sso-account), steps 1 and 2).

The connections this guide needs, for a firewall (all TCP, besides DNS):

| from | to | port | for |
|---|---|---|---|
| your machine (laptop or jump box) | the Supervisor's address | 443 | the login ([step 2](#2-log-in-with-the-vcf-cli)) and the plugin download ([plugin step 2](#2-install-the-kubectl-vsphere-plugin-the-person-once)) |
| your machine (laptop or jump box) | the VKS cluster's API address (in your kubeconfig) | 6443 | kubectl with your login ([step 3](#3-use-the-login)) |
| your machine (laptop or jump box) | vCenter | 443 | only to fetch the vCenter CA yourself ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca), step 1) |

## 1. What to ask your administrator for

Ask your administrators for (the vCenter administrator sends the first three and your SSO user name as
vCenter lists it, the cluster administrator your namespace):

- the Supervisor's IP address or DNS name;
- the vSphere Namespace's name and the VKS cluster's name;
- the vCenter CA file (optional but recommended: with it the login checks that it talks to your
  real Supervisor); save it as `~/.kube/vcenter-ca.pem`;
- the name of your namespace inside the VKS cluster (a folder for your team's workloads, not the
  vSphere Namespace);
- your SSO user name exactly as vCenter lists it, letter case included: the cluster administrator gives
  that name rights, and you log in with it.

Other ways in:

- Your identity provider group was given access: sign in with
  [USER-IDP-LOGIN.md](USER-IDP-LOGIN.md) instead.
- You were sent a kubeconfig file (a token or a certificate): use it with
  [USER-KUBECONFIG.md](USER-KUBECONFIG.md).
- You have **Can edit** or **Owner** on the vSphere Namespace: you are a cluster administrator,
  and [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md) applies too.

## 2. Log in with the VCF CLI

You need the [VCF CLI](VCF.md). The vCenter CA from [step 1](#1-what-to-ask-your-administrator-for)
is optional but recommended: with it the login checks that it talks to your real Supervisor;
without it (`SUPERVISOR_CA=""` below) it does not check, so someone between you and the Supervisor
could capture your password.

Type your SSO password first, so that it never shows on the screen or in the shell's history. This
line only keeps it in this terminal; nothing else changes. You then have the password ready for the
next block, which uses it and removes it.

**Linux, macOS, WSL (bash or zsh):**

<!-- lab-step: user-vcf-password -->
```sh
printf 'SSO password: '; IFS= read -rs SSO_PASSWORD; echo
```

**Windows (PowerShell):**

<!-- lab-step: user-vcf-password-windows -->
```powershell
$SSO_PASSWORD = Read-Host 'SSO password' -AsSecureString
```

Then run this in the same terminal to log in, and again whenever kubectl answers `Unauthorized`,
10 hours after a login; a new login is written to the same file. It logs you in to the VKS cluster
as `SSO_USER` through the Supervisor and writes the login to your own kubeconfig
`VKS_USER_KUBECONFIG` (the file kubectl reads to reach the cluster), readable only by you, then
prints the name the cluster knows you by. You then use the cluster with that file (step 3).

Set `SUPERVISOR_ENDPOINT` to the Supervisor's IP address or DNS name, `SUPERVISOR_CA` to the
vCenter CA file from step 1, or to `""` when you do not have it (the block then prints a `WARNING`
and does not check the Supervisor's certificate), `SSO_USER` to your full SSO user name, and
`VSPHERE_NAMESPACE` (the vSphere Namespace) and `VKS_CLUSTER` to the names from step 1.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

<!-- lab-step: user-vcf-login -->
```sh
SUPERVISOR_ENDPOINT="10.0.0.10"
SUPERVISOR_CA="$HOME/.kube/vcenter-ca.pem"
SSO_USER="alice@vsphere.local"
VSPHERE_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_USER_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}-${SSO_USER}.kubeconfig"

case "$SSO_USER" in */*|*\\*|*:*) SSO_USER_OK="" ;; *@*) SSO_USER_OK="yes" ;; *) SSO_USER_OK="" ;; esac
if [ -n "$SUPERVISOR_CA" ]; then TLS="--ca-certificate=$SUPERVISOR_CA"; else TLS="--insecure-skip-tls-verify"; fi
if [ -z "$SSO_USER_OK" ]; then
  printf '%s\n' "STOPPED: SSO_USER is the full SSO user name, such as alice@vsphere.local: $SSO_USER"
elif [ -z "$SSO_PASSWORD" ]; then
  echo "FAILED: no password in this terminal; run the password line above"
elif [ -n "$SUPERVISOR_CA" ] && { [ ! -f "$SUPERVISOR_CA" ] || [ ! -s "$SUPERVISOR_CA" ]; }; then
  echo "FAILED: not found: $SUPERVISOR_CA"
elif { [ -n "$SUPERVISOR_CA" ] || echo "WARNING: SUPERVISOR_CA is empty: the Supervisor's certificate is not checked"; } \
     && mkdir -p "$HOME/.kube" && ( umask 077; : >> "$VKS_USER_KUBECONFIG" ) && chmod 600 "$VKS_USER_KUBECONFIG" \
     && { KUBECONFIG="$VKS_USER_KUBECONFIG" vcf context delete "${VKS_CLUSTER}-${SSO_USER}" -y --skip-delete-kubeconfig-context </dev/null >/dev/null 2>&1; true; } \
     && KUBECONFIG="$VKS_USER_KUBECONFIG" VCF_CLI_VSPHERE_PASSWORD="$SSO_PASSWORD" \
        vcf context create "${VKS_CLUSTER}-${SSO_USER}" --type k8s --endpoint "https://${SUPERVISOR_ENDPOINT}" \
          --username "$SSO_USER" --auth-type basic "$TLS" --skip-create-related-contexts \
          --workload-cluster-name "$VKS_CLUSTER" --workload-cluster-namespace "$VSPHERE_NAMESPACE" </dev/null \
     && kubectl --kubeconfig "$VKS_USER_KUBECONFIG" config use-context "${VKS_CLUSTER}-${SSO_USER}:${VKS_CLUSTER}" >/dev/null; then
  echo "logged in as: $(kubectl --kubeconfig "$VKS_USER_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')"
else
  echo "FAILED: login (see the error above)"
fi
unset SSO_PASSWORD
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

<!-- lab-step: user-vcf-login-windows -->
```powershell
$SUPERVISOR_ENDPOINT = "10.0.0.10"
$SUPERVISOR_CA = "$HOME\.kube\vcenter-ca.pem"
$SSO_USER = "alice@vsphere.local"
$VSPHERE_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_USER_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}-${SSO_USER}.kubeconfig"

if ($SSO_USER -notmatch '^[^/\\:]*@[^/\\:]*\z') {
  "STOPPED: SSO_USER is the full SSO user name, such as alice@vsphere.local: ${SSO_USER}"
} elseif (-not $SSO_PASSWORD -or $SSO_PASSWORD.Length -eq 0) {
  "FAILED: no password in this PowerShell; run the password line above"
} elseif ($SUPERVISOR_CA -and (-not (Test-Path $SUPERVISOR_CA -PathType Leaf) -or (Get-Item $SUPERVISOR_CA).Length -eq 0)) {
  "FAILED: not found: $SUPERVISOR_CA"
} else {
  if ($SUPERVISOR_CA) { $TLS = "--ca-certificate=$SUPERVISOR_CA" } else {
    $TLS = "--insecure-skip-tls-verify"
    "WARNING: SUPERVISOR_CA is empty: the Supervisor's certificate is not checked"
  }
  New-Item -ItemType Directory -Force -Path "$HOME\.kube" | Out-Null
  $OLD_KUBECONFIG = $env:KUBECONFIG; $env:KUBECONFIG = $VKS_USER_KUBECONFIG
  try {
    $null | vcf context delete "${VKS_CLUSTER}-${SSO_USER}" -y --skip-delete-kubeconfig-context 2>&1 | Out-Null
    $env:VCF_CLI_VSPHERE_PASSWORD = [Net.NetworkCredential]::new('', $SSO_PASSWORD).Password
    $global:LASTEXITCODE = $null
    $null | vcf context create "${VKS_CLUSTER}-${SSO_USER}" --type k8s --endpoint "https://$SUPERVISOR_ENDPOINT" `
      --username $SSO_USER --auth-type basic $TLS --skip-create-related-contexts `
      --workload-cluster-name $VKS_CLUSTER --workload-cluster-namespace $VSPHERE_NAMESPACE
    $OK = $LASTEXITCODE -eq 0
  } finally {
    Remove-Item Env:VCF_CLI_VSPHERE_PASSWORD -ErrorAction SilentlyContinue; $env:KUBECONFIG = $OLD_KUBECONFIG
  }
  if ($OK) {
    kubectl --kubeconfig $VKS_USER_KUBECONFIG config use-context "${VKS_CLUSTER}-${SSO_USER}:${VKS_CLUSTER}" | Out-Null
    "logged in as: $(kubectl --kubeconfig $VKS_USER_KUBECONFIG auth whoami -o jsonpath='{.status.userInfo.username}')"
  } else {
    "FAILED: login (see the error above)"
  }
}
Remove-Variable SSO_PASSWORD -ErrorAction SilentlyContinue
```

</details>

**Expect:** with `SUPERVISOR_CA=""` first `WARNING: SUPERVISOR_CA is empty …`; then `Successfully
logged in to Kubernetes cluster <cluster>`, the contexts `<cluster>-<SSO_USER>` and
`<cluster>-<SSO_USER>:<cluster>`, and `logged in as: sso:…` (SSO writes the name in its own letter case,
for example `sso:Alice@vsphere.local`).

**If not:**
- `STOPPED: SSO_USER is …`: set `SSO_USER` to the full name with `@` and the domain, then run the
  password line and this block again.
- `FAILED: no password …`: run the password line, then this block.
- `FAILED: not found: …`: save the vCenter CA file from your administrator first
  ([step 1](#1-what-to-ask-your-administrator-for)), or set `SUPERVISOR_CA=""`.
- `invalid or missing credentials`: check `SSO_USER`, then run the password line and this block
  again. Mind the lock-out.
- `x509: certificate signed by unknown authority`: `SUPERVISOR_CA` is not the vCenter CA.
- `Invalid vSphere Supervisor endpoint`: check `SUPERVISOR_ENDPOINT` and that this machine reaches
  it on port 443.
- `Login failed: bad request`: check `VKS_CLUSTER` and `VSPHERE_NAMESPACE`.
- After fixing a value, run the password line and this block again.
- `Initialization done!` and lines about plugins on the first run: harmless.

Then use the cluster: [step 3](#3-use-the-login).

## 3. Use the login

Run this in each new terminal where you use the cluster, after step 2. Plain `kubectl` reads
only `~/.kube/config`; your login is in its own file, `~/.kube/<cluster>-<SSO_USER>.kubeconfig`.
This points `KUBECONFIG` at that file for this terminal, so every `kubectl` command in it uses your
login ([KUBECONFIG.md](KUBECONFIG.md#2-use-a-file)), then shows who you are and whether you may
deploy in the namespace you were given. Set `SSO_USER` and `VKS_CLUSTER` as in your login, and
`VKS_CLUSTER_NAMESPACE` to that namespace (if you were given the whole cluster, any namespace, for example
`default`).

**Linux, macOS, WSL (bash or zsh):**

```sh
SSO_USER="alice@vsphere.local"
VKS_CLUSTER="my-vks-cluster"
VKS_CLUSTER_NAMESPACE="team-a"

export KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}-${SSO_USER}.kubeconfig"
kubectl auth whoami
kubectl -n "$VKS_CLUSTER_NAMESPACE" auth can-i create deployments
```

**Windows (PowerShell):**

```powershell
$SSO_USER = "alice@vsphere.local"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_CLUSTER_NAMESPACE = "team-a"

$env:KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}-${SSO_USER}.kubeconfig"
kubectl auth whoami
kubectl -n $VKS_CLUSTER_NAMESPACE auth can-i create deployments
```

**Expect:** `Username` with your `sso:…` name, then `yes`. Then use `kubectl -n team-a …` in this
terminal.

**If not:**
- `connection refused` to `localhost:8080`: the file is not there; check `SSO_USER` and
  `VKS_CLUSTER` against your login (`ls ~/.kube`).
- `no`: you have no rights in that namespace yet: the cluster administrator has not given them
  ([ADMIN-GRANT-ACCESS.md step 2](ADMIN-GRANT-ACCESS.md#2-give-the-person-rights-inside-the-cluster-cluster-administrator)),
  or bound a name that differs from the `Username` above (often only in letter case). Send them that
  exact name.
- `Unauthorized`: the login ended (10 hours after it). Log in again (step 2), then run this again.
  Your rights stay.

## 4. When the login ends

A login lasts 10 hours. When kubectl answers `Unauthorized`, run the password line and the block of
[step 2](#2-log-in-with-the-vcf-cli) again: a new login is written to the same file. Your rights
stay: you need nothing new from your administrator. In a new terminal, run
[step 3](#3-use-the-login) as before.

## The kubectl vSphere plugin instead of the VCF CLI (optional and deprecated)

<details>
<summary><b>The plugin steps</b></summary>

Only for people who log in without the VCF CLI. The kubectl vSphere plugin is a program that logs
kubectl in through the Supervisor; Broadcom replaced it with the VCF CLI, but it still works on 9.1
([KB 435399](https://knowledge.broadcom.com/external/article/435399)). The Supervisor serves it only
as an amd64 build (Apple silicon and Windows on Arm would need x64 emulation; not tested). It
replaces [step 2](#2-log-in-with-the-vcf-cli) of this guide; steps 1, 3 and 4 stay the same.

### 1. Windows and macOS: trust the vCenter CA (the person, once)

Do this once on Windows or macOS, before steps 2 and 3 below, and before a browser sign-in through the
Supervisor ([USER-IDP-LOGIN.md step 3](USER-IDP-LOGIN.md#3-sign-in-through-the-supervisor)): there the browser, the plugin, and on Windows the download in step 2,
check the Supervisor's certificate against your user's trusted CAs, not `SUPERVISOR_CA`. It adds
the vCenter CA from [step 1](#1-what-to-ask-your-administrator-for) above, saved as `~/.kube/vcenter-ca.pem`, to your user's trusted CAs. You then
trust certificates the vCenter CA signed, the Supervisor's among them, as this user. Windows asks
you to confirm with **Yes**; on macOS, run the line under **macOS** below instead:

**Windows (PowerShell):**

<!-- lab-step: vcenter-ca-windows -->
```powershell
Import-Certificate -FilePath "$HOME\.kube\vcenter-ca.pem" -CertStoreLocation Cert:\CurrentUser\Root
```

**Expect:** a line with the CA's thumbprint and its name (`CN=CA` for vCenter's own CA).

**If not:** `UI is not allowed in this operation`: this PowerShell has no desktop to ask on (for
example over SSH). Run the line in Windows PowerShell on the desktop.

**macOS** (not tested): run
`security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db ~/.kube/vcenter-ca.pem`.

### 2. Install the kubectl vSphere plugin (the person, once)

Do this once (on Windows and macOS, step 1 first). It downloads the plugin from the Supervisor,
checking the Supervisor's certificate against the vCenter CA
(from your administrator, [step 1](#1-what-to-ask-your-administrator-for); on Windows, the trusted
CA from plugin step 1), runs it to check that it starts, and only then installs it into
`INSTALL_DIR`. You then have the `kubectl-vsphere` command for step 3; running this again replaces
the installed plugin.

Set `SUPERVISOR_ENDPOINT` to the Supervisor's IP address or DNS name and `SUPERVISOR_CA` to the
vCenter CA file from step 1.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

<!-- lab-step: user-plugin-install -->
```sh
SUPERVISOR_ENDPOINT="10.0.0.10"
SUPERVISOR_CA="$HOME/.kube/vcenter-ca.pem"
INSTALL_DIR="$HOME/.local/bin"

case "$(uname -s)" in Darwin) OS=darwin ;; *) OS=linux ;; esac
TMP="$(mktemp -d)"
if curl -fsS --connect-timeout 20 --speed-time 60 --cacert "$SUPERVISOR_CA" -o "$TMP/plugin.zip" \
     "https://${SUPERVISOR_ENDPOINT}/wcp/plugin/${OS}-amd64/vsphere-plugin.zip" \
   && { if command -v unzip >/dev/null 2>&1 || ! command -v bsdtar >/dev/null 2>&1; then unzip -q -o "$TMP/plugin.zip" -d "$TMP"; else bsdtar -xf "$TMP/plugin.zip" -C "$TMP"; fi; } \
   && "$TMP/bin/kubectl-vsphere" version; then
  mkdir -p "$INSTALL_DIR" && install -m 755 "$TMP/bin/kubectl-vsphere" "$INSTALL_DIR/kubectl-vsphere" \
    && echo "installed $INSTALL_DIR/kubectl-vsphere"
else
  echo "FAILED: no working plugin from https://${SUPERVISOR_ENDPOINT} (see the error above)"
fi
rm -rf "$TMP"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_ENDPOINT = "10.0.0.10"
$INSTALL_DIR = "$env:LOCALAPPDATA\Programs\vks-tools"

$ProgressPreference = 'SilentlyContinue'
if ([Net.ServicePointManager]::SecurityProtocol -ne 'SystemDefault') { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 'Tls12' }
$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null
$global:LASTEXITCODE = 1
try {
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri "https://$SUPERVISOR_ENDPOINT/wcp/plugin/windows-amd64/vsphere-plugin.zip" -OutFile "$TMP\plugin.zip"
  Expand-Archive -Path "$TMP\plugin.zip" -DestinationPath $TMP; & "$TMP\bin\kubectl-vsphere.exe" version
} catch { $_.Exception.Message }
if ($LASTEXITCODE -eq 0) {
  New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
  Copy-Item -Force "$TMP\bin\kubectl-vsphere.exe" "$INSTALL_DIR\kubectl-vsphere.exe"
  "installed $INSTALL_DIR\kubectl-vsphere.exe"
} else {
  "FAILED: no working plugin from https://$SUPERVISOR_ENDPOINT (see the error above)"
}
Remove-Item -Recurse -Force $TMP
```

</details>

**Expect:** `kubectl-vsphere: version …`, then `installed …`.

**If not:** `FAILED: …` after `curl: (60)` (Windows: `Could not establish trust relationship`):
`SUPERVISOR_CA` is not the vCenter CA, or on Windows the step above was not done; after
`curl: (22) … 404` (Windows: `(404) Not Found`): there is no build for this machine.

### 3. Log in with the plugin (the person)

Do this to log in with the plugin, and again whenever kubectl answers `Unauthorized`, 10 hours
after a login; a new login is written to the same file. It logs you in to the VKS cluster as
`SSO_USER` and writes the login to your own kubeconfig `VKS_USER_KUBECONFIG`, readable only by
you, then prints the name the cluster knows you by. On Linux, macOS and WSL it asks for the SSO
password. You then use the cluster with that file
([step 3 above](#3-use-the-login)).

Set `SUPERVISOR_ENDPOINT` to the Supervisor's IP address or DNS name, `SUPERVISOR_CA` to the
vCenter CA file from step 1, `SSO_USER` to your full SSO user name, and `VSPHERE_NAMESPACE` (the
vSphere Namespace) and `VKS_CLUSTER` to the names from step 1.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

<!-- lab-step: user-plugin-login -->
```sh
SUPERVISOR_ENDPOINT="10.0.0.10"
SUPERVISOR_CA="$HOME/.kube/vcenter-ca.pem"
SSO_USER="alice@vsphere.local"
VSPHERE_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_USER_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}-${SSO_USER}.kubeconfig"

case "$SSO_USER" in */*|*\\*|*:*) SSO_USER_OK="" ;; *@*) SSO_USER_OK="yes" ;; *) SSO_USER_OK="" ;; esac
if [ -z "$SSO_USER_OK" ]; then
  printf '%s\n' "STOPPED: SSO_USER is the full SSO user name, such as alice@vsphere.local: $SSO_USER"
else
  mkdir -p "$HOME/.kube" && ( umask 077; : >> "$VKS_USER_KUBECONFIG" ) && chmod 600 "$VKS_USER_KUBECONFIG"
  ( printf 'SSO password: '; IFS= read -rs P; echo
    KUBECONFIG="$VKS_USER_KUBECONFIG" SSL_CERT_FILE="$SUPERVISOR_CA" KUBECTL_VSPHERE_PASSWORD="$P" \
      "$HOME/.local/bin/kubectl-vsphere" login --server "$SUPERVISOR_ENDPOINT" --vsphere-username "$SSO_USER" \
      --tanzu-kubernetes-cluster-namespace "$VSPHERE_NAMESPACE" --tanzu-kubernetes-cluster-name "$VKS_CLUSTER" ) \
    && chmod 600 "$VKS_USER_KUBECONFIG" \
    && kubectl --kubeconfig "$VKS_USER_KUBECONFIG" config use-context "$VKS_CLUSTER" >/dev/null \
    && echo "logged in as: $(kubectl --kubeconfig "$VKS_USER_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')" \
    || echo "FAILED: the login did not work (see the error above); nothing was changed"
fi
```

</details>

On Windows, type the password first, so that it never shows on the screen. This line only keeps it
in this PowerShell; nothing else changes. You then have it ready for the next block, which uses it
and removes it:

**Windows (PowerShell):**

```powershell
$SSO_PASSWORD = Read-Host 'SSO password' -AsSecureString
```

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_ENDPOINT = "10.0.0.10"
$SSO_USER = "alice@vsphere.local"
$VSPHERE_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-vks-cluster"
$VKS_USER_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}-${SSO_USER}.kubeconfig"

if ($SSO_USER -notmatch '^[^/\\:]*@[^/\\:]*\z') {
  "STOPPED: SSO_USER is the full SSO user name, such as alice@vsphere.local: ${SSO_USER}"
} elseif (-not $SSO_PASSWORD -or $SSO_PASSWORD.Length -eq 0) {
  "FAILED: no password in this PowerShell; run the password line above"
} else {
  New-Item -ItemType Directory -Force -Path "$HOME\.kube" | Out-Null
  $OLD_KUBECONFIG = $env:KUBECONFIG; $env:KUBECONFIG = $VKS_USER_KUBECONFIG
  try {
    $env:KUBECTL_VSPHERE_PASSWORD = [Net.NetworkCredential]::new('', $SSO_PASSWORD).Password
    $global:LASTEXITCODE = $null
    kubectl-vsphere login --server $SUPERVISOR_ENDPOINT --vsphere-username $SSO_USER `
      --tanzu-kubernetes-cluster-namespace $VSPHERE_NAMESPACE --tanzu-kubernetes-cluster-name $VKS_CLUSTER
    $LOGIN_RC = $LASTEXITCODE
  } finally {
    Remove-Item Env:KUBECTL_VSPHERE_PASSWORD -ErrorAction SilentlyContinue; $env:KUBECONFIG = $OLD_KUBECONFIG
  }
  if ($LOGIN_RC -ne 0) {
    "FAILED: the login did not work (see the error above); nothing was changed"
  } else {
    kubectl --kubeconfig $VKS_USER_KUBECONFIG config use-context $VKS_CLUSTER | Out-Null
    if ($LASTEXITCODE -eq 0) { "logged in as: $(kubectl --kubeconfig $VKS_USER_KUBECONFIG auth whoami -o jsonpath='{.status.userInfo.username}')" }
  }
}
Remove-Variable SSO_PASSWORD -ErrorAction SilentlyContinue
```

</details>

**Expect:** `Logged in successfully.`, the contexts it made, and `logged in as: sso:…` (SSO
writes the name in its own letter case, for example `sso:Alice@vsphere.local`).

**If not:**
- `STOPPED: SSO_USER is …`: set `SSO_USER` to the full name with `@` and the domain, then run this
  block again.
- `x509: certificate signed by unknown authority`: `SUPERVISOR_CA` is not the vCenter CA (Windows
  and macOS: the CA step above was not done).
- `FAILED: no password …` (Windows): run the password line, then this block.
- `Login failed: bad request`, then `no context exists with the name`: check `VKS_CLUSTER` and
  `VSPHERE_NAMESPACE`. A cluster with the same name as its vSphere Namespace can also hide one of the
  two contexts
  ([Broadcom KB 435635](https://knowledge.broadcom.com/external/article/435635)).
- `FAILED: the login did not work …`, or any other login error above it: check `SSO_USER`, then run
  this block again (Windows: the password line first) and type the password carefully. Mind the
  lock-out.
- `logged in as:` with `Unauthorized`: the login did not work; see the error above it.

</details>

## References

**Official Broadcom documentation (VCF 9.1) for this guide**

- [Log in to a VKS Cluster Using vCenter SSO Credentials](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/configuring-identity-and-access-for-tkg-service-clusters/connecting-to-vsphere-with-tanzu-clusters/connect-to-a-tkg-service-cluster-as-a-vcenter-single-sign-on-user-with-kubectl/log-in-using-credentials.html)
- [Configure vSphere Namespace Permissions for vCenter Single Sign-On Users and Groups](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service/configuring-vsphere-namespaces-for-hosting-tkg-service-clusters/configure-vsphere-namespace-persmissions-for-vcenter-sso-users-and-groups.html) (the role your administrator gives you)
- [VCF CLI command reference: context](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/installing-and-using-vcf-cli-v9/command-reference2/system-commands%281%29/context2.html) (create)
- Broadcom [KB 435399](https://knowledge.broadcom.com/external/article/435399) and [KB 435635](https://knowledge.broadcom.com/external/article/435635) (the kubectl vSphere plugin)

Back to [README](../README.md).
