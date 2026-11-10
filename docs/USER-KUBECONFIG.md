# Use a kubeconfig file you were given

An administrator sent you a kubeconfig file with a token or a certificate in it, for you or for a
tool. With it, kubectl works on one VKS cluster: no password, SSO account or VCF CLI. Whoever has a
copy of the file is you to the cluster, so keep it like a password.

Not your case? Your own vCenter SSO account: [USER-LOGIN.md](USER-LOGIN.md). A file that runs
`vcf` or `kubectl` to sign in with a browser: [USER-IDP-LOGIN.md](USER-IDP-LOGIN.md).

The steps:

1. [What to ask your administrator for](#1-what-to-ask-your-administrator-for)
2. [Save the file and check it](#2-save-the-file-and-check-it)
3. [Use the file](#3-use-the-file)
4. [When it stops working](#4-when-it-stops-working)
5. [Check that a whole-cluster file can change things](#5-check-that-a-whole-cluster-file-can-change-things-whole-cluster-file-only) (whole-cluster file only)
6. [Done, or the file leaked](#6-done-or-the-file-leaked)

For a pipeline: [A CI pipeline](#a-ci-pipeline).

## Prerequisites

- [Prerequisites](PREREQS.md) for your OS, and [kubectl](KUBECTL.md); openssl
  ([PREREQS.md](PREREQS.md)) shows a certificate's end date in step 2 (on Windows, PowerShell
  shows it without openssl);
- the file and the names from [step 1](#1-what-to-ask-your-administrator-for).

The connections this guide needs, for a firewall (all TCP, besides DNS):

| from | to | port | for |
|---|---|---|---|
| your machine (laptop or jump box), or the pipeline's runner | the VKS cluster's API address (the file's `server:` line) | 6443 | kubectl with the file (steps 2 to 5) |

## 1. What to ask your administrator for

- the file, sent through a password manager's share or as an encrypted file, never by email, chat
  or a shared folder ([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over));
- your namespace inside the VKS cluster (a folder for your team's workloads, not the vSphere
  Namespace), or that the file is for the whole cluster, and whether it may change things or only read;
- the day it ends (or that it does not end);
- the cluster's address, to check the file's `server:` line against in step 2.

You need no vCenter CA: the file holds the cluster's CA.

## 2. Save the file and check it

Save the file in your `.kube` folder, for example as `my-vks-cluster-alice-20261110.kubeconfig`
(Windows: `$HOME\.kube\…`). Run this once after saving it, before you or a tool rely on it. It makes
the file readable only by you, shows its server and its kind of login without printing any secret,
when it ends, who it acts as, what it may do in your namespace and whether it may read the whole
cluster, then lists the pods there. It
changes nothing on the cluster. Set `KUBECONFIG_FILE` to the saved file and `VKS_CLUSTER_NAMESPACE`
to your namespace (for a whole-cluster file, any namespace, for example `default`).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
KUBECONFIG_FILE="$HOME/.kube/my-vks-cluster-alice-20261110.kubeconfig"
VKS_CLUSTER_NAMESPACE="team-a"

k() { kubectl --kubeconfig "$KUBECONFIG_FILE" "$@"; }
if [ ! -s "$KUBECONFIG_FILE" ]; then
  echo "MISSING: $KUBECONFIG_FILE"
elif ! VIEW="$(k config view --minify)"; then
  echo "FAILED: kubectl cannot read $KUBECONFIG_FILE (see the error above)"
else
  chmod 600 "$KUBECONFIG_FILE" && ls -l "$KUBECONFIG_FILE"
  printf '%s\n' "$VIEW" | grep -E 'server:|token:|client-key-data:|command:|namespace:'
  case "$VIEW" in
    *"command:"*) KIND="sign-in" ;;
    *"client-key-data:"*) KIND="certificate" ;;
    *"token:"*) KIND="token" ;;
    *) KIND="" ;;
  esac
  if [ "$KIND" = "sign-in" ]; then
    echo "STOPPED: this file signs in with a browser: use USER-IDP-LOGIN.md"
  elif [ -z "$KIND" ]; then
    echo "FAILED: no token, certificate or sign-in command in this file; ask your administrator for it again"
  else
    if [ "$KIND" = "certificate" ] && ! command -v openssl >/dev/null 2>&1; then
      echo "MISSING: openssl (PREREQS.md): the certificate's end date is not shown"
    elif [ "$KIND" = "certificate" ]; then
      k config view --minify --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -subject -enddate
    else
      T="$(k config view --minify --raw -o jsonpath='{.users[0].user.token}')"
      P="$(printf '%s' "$T" | cut -d. -f2 | tr '_-' '/+')"
      while [ $(( ${#P} % 4 )) -ne 0 ]; do P="$P="; done
      EXP="$(printf '%s' "$P" | base64 -d 2>/dev/null | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
      S=""; if [ -n "$EXP" ]; then S=$(( EXP - $(date +%s) )); fi
      if [ -z "$S" ]; then echo "token ends: no end date in the token (ask your administrator)"
      elif [ "$S" -le 0 ]; then echo "token ends: it has ended"
      elif [ "$S" -ge 86400 ]; then echo "token ends in: $(( S / 86400 )) days"
      else echo "token ends in: $(( S / 3600 )) hours"; fi
      unset T P
    fi
    if ! WHO="$(k auth whoami -o jsonpath='{.status.userInfo.username}')"; then
      echo "FAILED: kubectl could not ask the cluster who you are (see the error above)"
    else
      echo "acts as: $WHO"
      echo "create deployments in $VKS_CLUSTER_NAMESPACE: $(k -n "$VKS_CLUSTER_NAMESPACE" auth can-i create deployments)"
      echo "list pods in every namespace: $(k auth can-i list pods --all-namespaces)"
      k -n "$VKS_CLUSTER_NAMESPACE" get pods
    fi
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$KUBECONFIG_FILE = "$HOME\.kube\my-vks-cluster-alice-20261110.kubeconfig"
$VKS_CLUSTER_NAMESPACE = "team-a"

& {
  if (-not (Test-Path $KUBECONFIG_FILE -PathType Leaf)) { "MISSING: $KUBECONFIG_FILE"; return }
  $global:LASTEXITCODE = $null
  $VIEW = (kubectl --kubeconfig $KUBECONFIG_FILE config view --minify) -join "`n"
  if ($LASTEXITCODE -ne 0) { "FAILED: kubectl cannot read $KUBECONFIG_FILE (see the error above)"; return }
  icacls $KUBECONFIG_FILE /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null
  icacls $KUBECONFIG_FILE
  $VIEW -split "`n" | Select-String -Pattern 'server:|token:|client-key-data:|command:|namespace:'
  if ($VIEW -match 'command:') { "STOPPED: this file signs in with a browser: use USER-IDP-LOGIN.md"; return }
  if ($VIEW -match 'client-key-data:') {
    $B = kubectl --kubeconfig $KUBECONFIG_FILE config view --minify --raw -o jsonpath='{.users[0].user.client-certificate-data}'
    if ($B) {
      $C = New-Object Security.Cryptography.X509Certificates.X509Certificate2 (,[Convert]::FromBase64String($B))
      "subject=$($C.Subject)"
      "notAfter=$($C.NotAfter.ToString('yyyy-MM-dd HH:mm'))"
    } else {
      "FAILED: no certificate read from $KUBECONFIG_FILE"
    }
  } elseif ($VIEW -match 'token:') {
    $T = kubectl --kubeconfig $KUBECONFIG_FILE config view --minify --raw -o jsonpath='{.users[0].user.token}'
    $EXP = $null
    try {
      $P = $T.Split('.')[1].Replace('-', '+').Replace('_', '/'); while ($P.Length % 4) { $P += '=' }
      $EXP = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($P)) | ConvertFrom-Json).exp
    } catch { $EXP = $null }
    if ($EXP) {
      $S = $EXP - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      if ($S -le 0) { "token ends: it has ended" } elseif ($S -ge 86400) { "token ends in: $([math]::Floor($S / 86400)) days" } else { "token ends in: $([math]::Floor($S / 3600)) hours" }
    } else { "token ends: no end date in the token (ask your administrator)" }
  } else {
    "FAILED: no token, certificate or sign-in command in this file; ask your administrator for it again"
    return
  }
  $global:LASTEXITCODE = $null
  $WHO = kubectl --kubeconfig $KUBECONFIG_FILE auth whoami -o jsonpath='{.status.userInfo.username}'
  if ($LASTEXITCODE -ne 0) { "FAILED: kubectl could not ask the cluster who you are (see the error above)"; return }
  "acts as: $WHO"
  "create deployments in ${VKS_CLUSTER_NAMESPACE}: $(kubectl --kubeconfig $KUBECONFIG_FILE -n $VKS_CLUSTER_NAMESPACE auth can-i create deployments)"
  "list pods in every namespace: $(kubectl --kubeconfig $KUBECONFIG_FILE auth can-i list pods --all-namespaces)"
  kubectl --kubeconfig $KUBECONFIG_FILE -n $VKS_CLUSTER_NAMESPACE get pods
}
```

</details>

**Expect:** `-rw-------` and your user (Windows: only your user with `(F)`); the `server:` line with
the address you were sent; then one of `token: REDACTED` (a token: `token ends in: … days`, or
`… hours` under a day) or `client-key-data: DATA+OMITTED` (a certificate: `subject=CN=…` and
`notAfter=…`), and a `namespace:` line if the file names one. Then `acts as: …`,
`create deployments in team-a: yes` (`no` with a read-only file), `list pods in every namespace: no`
for a file for one namespace (`yes` for a whole-cluster file; a read-only whole-cluster file shows
`create deployments …: no` and `list pods in every namespace: yes`), and the pods there or
`No resources found in team-a namespace.`

**If not:**
- `MISSING: …`: set `KUBECONFIG_FILE` to the saved file.
- `MISSING: openssl …`: install it ([PREREQS.md](PREREQS.md)) to see the end date; the rest of
  the check still runs.
- `server:` is not the address you were sent: do not use the file; ask your administrator.
- `STOPPED: this file signs in with a browser`: use [USER-IDP-LOGIN.md](USER-IDP-LOGIN.md).
- `Unable to connect to the server`, `The connection to the server … was refused` or `i/o timeout`,
  then `FAILED: kubectl could not ask the cluster who you are`: this machine cannot reach the `server:` address on port
  6443 (Prerequisites, firewall), or the cluster is down.
- `x509: certificate signed by unknown authority`: the file was changed, is for another cluster, or
  a proxy between this machine and the cluster replaces the certificate; ask for the file again, or
  reach the cluster without the proxy.
- `Unauthorized`, then `FAILED: kubectl could not ask the cluster who you are`: the file no longer works
  ([step 4](#4-when-it-stops-working)).
- `token ends: it has ended`: ask for a new file ([step 4](#4-when-it-stops-working)).
- `list pods in every namespace` is not what your administrator said (a file for one namespace
  answering `yes`, or a whole-cluster file `no`): tell your administrator before you rely on it.
- `no`, or `Forbidden` on the pods: the file has no rights in that namespace
  ([step 4](#4-when-it-stops-working)).

## 3. Use the file

Name the file in each command with `--kubeconfig`, or run this in each new terminal: it points
`KUBECONFIG` at the file for this terminal, so every `kubectl` command in it uses the file. Commands
act in the file's own namespace (its `namespace:` line in step 2, or `default`) unless they name
another with `-n`. To list several files, separate them with `:` (Windows: `;`); how kubectl then
reads them: [KUBECONFIG.md](KUBECONFIG.md#2-use-a-file). Set `KUBECONFIG_FILE` to the saved file.

**Linux, macOS, WSL (bash or zsh):**

```sh
KUBECONFIG_FILE="$HOME/.kube/my-vks-cluster-alice-20261110.kubeconfig"

export KUBECONFIG="$KUBECONFIG_FILE"
kubectl auth whoami
kubectl get pods
```

**Windows (PowerShell):**

```powershell
$KUBECONFIG_FILE = "$HOME\.kube\my-vks-cluster-alice-20261110.kubeconfig"

$env:KUBECONFIG = $KUBECONFIG_FILE
kubectl auth whoami
kubectl get pods
```

**Expect:** `Username` with the name step 2 showed after `acts as:`, then the pods in the file's
namespace (or `No resources found …`).

**If not:** `connection refused` to `localhost:8080`: the file is not there; check
`KUBECONFIG_FILE` (`ls ~/.kube`). Any other error: as in step 2.

## 4. When it stops working

kubectl answers `error: You must be logged in to the server (Unauthorized)` when the file no longer
proves who you are, and `Forbidden` (or `no` from `auth can-i`) when it does, but has no rights for
what you asked. Step 2 shows which kind of file you have:

| your file (step 2 shows) | `Unauthorized` means | `Forbidden` means |
|---|---|---|
| a token, `token ends in: … days` or `… hours` (a whole-cluster file can have an end date too) | the token ended, or your administrator took the access away: ask for a new file | its rights were changed, or you asked outside its namespace (below) |
| a token, `token ends: no end date …` (an administrator token made to never end) | your administrator took the access away: ask for a new file | — |
| a certificate, `notAfter=…` | it is past its end date (`notAfter`): ask for a new file | its rights were taken away, or moved to your new certificate: use the new file |
| a file that signs in with a browser | the cluster does not accept the sign-in: [USER-IDP-LOGIN.md step 7](USER-IDP-LOGIN.md#7-forbidden-or-no-sign-in) (when the sign-in ends, the browser opens again instead) | you are not in the group, or the group has no rights: [USER-IDP-LOGIN.md step 7](USER-IDP-LOGIN.md#7-forbidden-or-no-sign-in) |

`Forbidden` only in another namespace: your file acts in its own namespace; ask for that one with
`-n`. To list what the file may do in a namespace:
`kubectl --kubeconfig <file> auth can-i --list -n team-a`.

Send your administrator, without the file: the file's name, the `acts as:` line from step 2, the
error line, the namespace, and when it began.

## 5. Check that a whole-cluster file can change things (whole-cluster file only)

Only for a whole-cluster file that may change things (an administrator token, or a ServiceAccount
token or certificate made with `"*"` and `edit`), once on the machine that received it, before a tool
relies on it; skip it for a read-only whole-cluster file (made with `"*"` and `view`), where its
`Forbidden` is expected. It makes the file readable only by you and shows who it acts as. It
then creates a test namespace `CHECK_NAMESPACE` inside the cluster with a ConfigMap (a small object
that holds settings) in it, changes the ConfigMap and reads it back, then deletes that namespace
again; if it could not create the namespace, it deletes nothing. You then know the file can create,
change and delete in the cluster. Set `KUBECONFIG_FILE` to the saved file.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
KUBECONFIG_FILE="$HOME/.kube/my-vks-cluster-alice-20261110.kubeconfig"
CHECK_NAMESPACE="access-check"

k() { kubectl --kubeconfig "$KUBECONFIG_FILE" "$@"; }
chmod 600 "$KUBECONFIG_FILE"
echo "acts as: $(k auth whoami -o jsonpath='{.status.userInfo.username}')"
if k create namespace "$CHECK_NAMESPACE"; then
  k -n "$CHECK_NAMESPACE" create configmap check --from-literal=step=created --save-config
  k -n "$CHECK_NAMESPACE" create configmap check --from-literal=step=updated --dry-run=client -o yaml | k apply -f -
  echo "read back: $(k -n "$CHECK_NAMESPACE" get configmap check -o jsonpath='{.data.step}')"
  k delete namespace "$CHECK_NAMESPACE"
else
  echo "STOPPED: $CHECK_NAMESPACE was not made by this run, so it is not deleted (see the error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$KUBECONFIG_FILE = "$HOME\.kube\my-vks-cluster-alice-20261110.kubeconfig"
$CHECK_NAMESPACE = "access-check"

function k { $input | kubectl --kubeconfig $KUBECONFIG_FILE @args }
icacls $KUBECONFIG_FILE /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null
"acts as: $(k auth whoami -o jsonpath='{.status.userInfo.username}')"
$global:LASTEXITCODE = $null
k create namespace $CHECK_NAMESPACE
if ($LASTEXITCODE -eq 0) {
  k -n $CHECK_NAMESPACE create configmap check --from-literal=step=created --save-config
  k -n $CHECK_NAMESPACE create configmap check --from-literal=step=updated --dry-run=client -o yaml | k apply -f -
  "read back: $(k -n $CHECK_NAMESPACE get configmap check -o jsonpath='{.data.step}')"
  k delete namespace $CHECK_NAMESPACE
} else {
  "STOPPED: $CHECK_NAMESPACE was not made by this run, so it is not deleted (see the error above)"
}
```

</details>

**Expect:** `acts as: system:serviceaccount:kubeconfig-access:cluster-admin-ci` (the name your
administrator chose), `namespace/access-check created`, `configmap/check created`,
`configmap/check configured`, `read back: updated`, then `namespace "access-check" deleted`.

**If not:**
- `AlreadyExists`, then `STOPPED: …`: a namespace of that name is there; set `CHECK_NAMESPACE` to
  another name.
- `Forbidden`, then `STOPPED: …`: the file is not for the whole cluster, or it is read-only (`view`);
  skip this step.
- `Unauthorized`: [step 4](#4-when-it-stops-working).
- `No such file` (Windows: `cannot find`): set `KUBECONFIG_FILE` to the saved file.

## 6. Done, or the file leaked

When you no longer need the file, delete it, and every copy of it (a backup, a pipeline's secret).
Deleting your copy does not take the access away: every other copy keeps working. If a copy may have
leaked, tell your administrator at once:

- a token: ask them to take the access away (they delete its ServiceAccount): every copy then stops;
- a certificate: it cannot be withdrawn before its end date; they take away the rights of its name.

This deletes the file on this machine. Set `KUBECONFIG_FILE` to the file.

**Linux, macOS, WSL (bash or zsh):**

```sh
KUBECONFIG_FILE="$HOME/.kube/my-vks-cluster-alice-20261110.kubeconfig"

rm -f "$KUBECONFIG_FILE"
if [ -e "$KUBECONFIG_FILE" ]; then echo "FAILED: still there: $KUBECONFIG_FILE"; else echo "deleted $KUBECONFIG_FILE"; fi
```

**Windows (PowerShell):**

```powershell
$KUBECONFIG_FILE = "$HOME\.kube\my-vks-cluster-alice-20261110.kubeconfig"

Remove-Item -Force -ErrorAction SilentlyContinue $KUBECONFIG_FILE
if (Test-Path $KUBECONFIG_FILE) { "FAILED: still there: $KUBECONFIG_FILE" } else { "deleted $KUBECONFIG_FILE" }
```

**Expect:** `deleted …`. In a terminal where step 3 set `KUBECONFIG`, kubectl then answers
`connection refused` to `localhost:8080` until you close it.

**If not:** `FAILED: still there: …`: the error above says why (often: the file is open in another
program); close it and run this again.

## A CI pipeline

Store the file as one of the pipeline's secret variables (a file-type secret where the CI system has
one), never in the repository. Keep it out of the job's logs: never print the file or the secret,
and do not trace the commands of a step that reads it. Name the namespace in each command
(`kubectl -n team-a …`) or rely on the file's own `namespace:` line (step 2). Before the end date
step 2 shows, ask your administrator for the new file and replace the secret; after it, the job
fails with `Unauthorized`.

## References

- Kubernetes: [Organizing Cluster Access Using kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) (the `KUBECONFIG` list and how files merge), [Configure Access to Multiple Clusters](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)
- Kubernetes: [Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/) (ServiceAccount tokens, client certificates), [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) (`Forbidden`: the `edit` and `view` roles)

Back to [README](../README.md).
