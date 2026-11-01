# Kubeconfig files: what they hold, use, hand over, merge

> [!NOTE]
> **Official Kubernetes and Broadcom documentation (VCF 9.1) for this guide**
>
> - Kubernetes: [Organizing Cluster Access Using kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) (the `KUBECONFIG` list and how files merge), [Configure Access to Multiple Clusters](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)
> - Broadcom: [VCF CLI command reference: context](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/installing-and-using-vcf-cli-v9/command-reference2/system-commands%281%29/context2.html) (`vcf context create`), [VCF CLI command reference: cluster](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/installing-and-using-vcf-cli-v9/command-reference2/cluster2.html) (`vcf cluster kubeconfig get --export-file`)

A kubeconfig is the file kubectl reads to find a cluster and log in to it: the cluster's address,
its CA (so kubectl knows it is the real server), and a login. The login decides what the file is
worth: some files carry a key that works for anyone holding a copy, others only tell kubectl which
program to run for a sign-in. This guide lists the files the guides make, shows how to use them,
which ones may be handed over, and how to merge several into one.

## Prerequisites

- [kubectl](KUBECTL.md);
- at least one kubeconfig from the table below, for example from
  [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig).

The connections this guide needs, for a firewall (all TCP, besides DNS):

| from | to | port | for |
|---|---|---|---|
| your machine | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl to a VKS cluster ([Use a file](#2-use-a-file), [Merge files](#4-merge-files-into-kubeconfig-optional)) |
| your machine | the Supervisor's address | 443 | kubectl to the Supervisor, and the sign-in of files that run `vcf` |
| your browser (kubelogin: your machine) | Keycloak | 443 | the sign-in of files that run `vcf` or kubelogin |

## The files the guides make

| file | made by | its login | a copy lets anyone | works for | send it? |
|---|---|---|---|---|---|
| `~/.kube/supervisor.kubeconfig` | [LOGIN.md](LOGIN.md#create-supervisor-context-with-ca) (`vcf context create`) | your SSO token | act as you on the Supervisor | 10 hours | no |
| `~/.kube/<cluster>.kubeconfig` | [Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig), or [Download it](LOGIN.md#download-the-vks-clusters-kubeconfig-from-the-vsphere-client) | the cluster's administrator certificate and key | be the cluster's administrator | about a year from when the cluster made it | no |
| `~/<team>.kubeconfig` | [A ServiceAccount token](ACCESS.md#a-serviceaccount-token) | a ServiceAccount token | act as that ServiceAccount | `DAYS` (30 by default), or until the ServiceAccount is deleted | to the team only |
| `~/<person>.kubeconfig` | [A personal certificate](ACCESS.md#a-personal-certificate) | a certificate and key | act as that person | `DAYS` (30 by default); cannot be withdrawn | to that person only |
| `~/.kube/<cluster>-sso.kubeconfig` | [The person's own SSO account](ACCESS.md#the-persons-own-sso-account) | the person's SSO token | act as that person | 10 hours | no |
| `~/.kube/<cluster>-keycloak.kubeconfig` | [KEYCLOAK.md](KEYCLOAK.md#3-make-the-persons-kubeconfig-cluster-administrator) | none: runs kubelogin, which asks for a Keycloak sign-in | nothing without a Keycloak account | as long as the cluster's address and CA stay | yes |
| `~/<cluster>-keycloak-sv.kubeconfig` | [A Keycloak account through the Supervisor](ACCESS.md#4-make-the-groups-kubeconfig-and-hand-it-over-cluster-administrator) | none: runs `vcf pinniped-auth login`, which asks for a sign-in | nothing without an account | as long as the address and CA stay | yes |

Every file the guides write is readable only by you (Linux, macOS: `-rw-------`; Windows: your
user, `SYSTEM` and `Administrators`). The sign-ins of the last two rows are kept elsewhere, also readable only by you: kubelogin's in `~/.kube/cache/oidc-login`,
`vcf`'s in `~/.config/vcf/pinniped`. Those folders are never sent.

## 1. See what a file holds

This shows who may read the file and what kind of login it holds, without printing any secret.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
KUBECONFIG_FILE="$HOME/.kube/my-vks-cluster.kubeconfig"

ls -l "$KUBECONFIG_FILE" && kubectl --kubeconfig "$KUBECONFIG_FILE" config view | grep -E 'server:|token:|client-key-data:|command:|current-context:'
```

**Windows (PowerShell):**

```powershell
$KUBECONFIG_FILE = "$HOME\.kube\my-vks-cluster.kubeconfig"

icacls $KUBECONFIG_FILE
kubectl --kubeconfig $KUBECONFIG_FILE config view | Select-String -Pattern 'server:|token:|client-key-data:|command:|current-context:'
```

**Expect:** `-rw-------` and your user (Windows: only your user, `SYSTEM` and `Administrators`),
then the `server:` line and one of:
- `client-key-data: DATA+OMITTED`: a key; whoever has the file is that user;
- `token: REDACTED`: a token; whoever has the file is that user until the token ends;
- `command: vcf` or `command: kubectl`: no secret; the file asks for a sign-in. Before the first
  use of such a file from someone else, check that `server:` is the address you were told and the
  command is `vcf` or `kubectl`: a file can run any program.

**If not:** `-rw-r--r--` or more: run `chmod 600` on the file (Windows: see
[Hand a file over](#3-hand-a-file-over)). `No such file`: set `KUBECONFIG_FILE` to the file.

## 2. Use a file

Name the file with `--kubeconfig` in each command, or make it the default in this terminal, as in
[Use the VKS cluster](LOGIN.md#use-the-vks-cluster), with any file from the table.

A file with several contexts (a *context* is a saved "this cluster, as this user"), such as
`~/.kube/supervisor.kubeconfig` (`supervisor` and one `supervisor:<namespace>` per vSphere
Namespace) or a merged `~/.kube/config`, uses its current context. Pick another for one command
with `--context <name>`, or make it the current one with `kubectl config use-context <name>`,
which changes the file. `KUBECONFIG` may also list several files, separated by `:` (Windows: `;`);
kubectl then reads them together, the first file wins where two use the same name, and
`use-context` changes the first file.

## 3. Hand a file over

Send only a file whose *send it?* column in [the table](#the-files-the-guides-make) is not `no`. A
file with no secret (`yes`) may go by email or chat. A file with a token or a key (`to the team
only`, `to that person only`) goes only through a password manager's share or as an encrypted
file, never by email, chat or a shared folder; then delete your copy. The person saves it in their
`.kube` folder and makes it readable only by them:

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
HANDOUT="$HOME/.kube/team-a.kubeconfig"

chmod 600 "$HANDOUT" && ls -l "$HANDOUT"
```

**Windows (PowerShell):**

```powershell
$HANDOUT = "$HOME\.kube\team-a.kubeconfig"

icacls $HANDOUT /inheritance:r /grant:r "${env:USERNAME}:F"
icacls $HANDOUT
```

**Expect:** `-rw-------` and your user (Windows: `processed file: …`, `Successfully processed 1
files`, then only your user with `(F)`).

**If not:** `No such file` (Windows: `The system cannot find the file specified`): set `HANDOUT` to
the saved file.

A file that runs `vcf` needs the [VCF CLI](VCF.md) on the person's machine; one that runs
kubelogin needs [kubelogin](PREREQS.md#kubelogin-optional).

## 4. Merge files into `~/.kube/config` (optional)

Optional: tools that read only `~/.kube/config` see every cluster at once. This copies the files in
`FILES`, after your `~/.kube/config` if you have one, into a new file readable only by you, lists
its contexts, and only then replaces `~/.kube/config`, keeping the old one as
`~/.kube/config.before-merge`. It stops, changing nothing, when a file is missing or two files use
the same context name.

Merge VKS cluster files and hand-outs only. Not `~/.kube/supervisor.kubeconfig` or any file a `vcf`
login writes (`vcf context list`): `vcf` renews only its own file, so the copy stops working. The
copy does not follow later changes to a file: after a new file for the same cluster, delete its old
entries (`kubectl config delete-context <name>`, `delete-cluster`, `delete-user`) and merge again.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
FILES="$HOME/.kube/my-vks-cluster.kubeconfig:$HOME/.kube/my-other-cluster.kubeconfig"
KUBE_CONFIG="$HOME/.kube/config"

MISSING="$(printf '%s\n' "$FILES" | tr ':' '\n' | while IFS= read -r F; do if [ ! -s "$F" ]; then printf '%s ' "$F"; fi; done)"
if [ -f "$KUBE_CONFIG" ]; then LIST="$KUBE_CONFIG:$FILES"; else LIST="$FILES"; fi
SAME="$(printf '%s\n' "$LIST" | tr ':' '\n' | while IFS= read -r F; do kubectl --kubeconfig "$F" config get-contexts -o name 2>/dev/null; done | sort | uniq -d | tr '\n' ' ')"
rm -f "$KUBE_CONFIG.new"
if [ -n "$MISSING" ]; then
  echo "MISSING: $MISSING"
elif [ -n "$SAME" ]; then
  echo "SAME CONTEXT NAME IN TWO FILES: $SAME"
elif mkdir -p "$HOME/.kube" && ( umask 077; KUBECONFIG="$LIST" kubectl config view --flatten > "$KUBE_CONFIG.new" ) \
     && kubectl --kubeconfig "$KUBE_CONFIG.new" config get-contexts; then
  if [ -f "$KUBE_CONFIG" ]; then cp -p "$KUBE_CONFIG" "$KUBE_CONFIG.before-merge"; fi
  mv "$KUBE_CONFIG.new" "$KUBE_CONFIG" && echo "merged into $KUBE_CONFIG"
else
  rm -f "$KUBE_CONFIG.new"
  echo "FAILED: $KUBE_CONFIG is as it was (see the kubectl error above)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$FILES = "$HOME\.kube\my-vks-cluster.kubeconfig;$HOME\.kube\my-other-cluster.kubeconfig"
$KUBE_CONFIG = "$HOME\.kube\config"

$MISSING = @($FILES.Split(';') | Where-Object { -not (Test-Path $_ -PathType Leaf) })
if (Test-Path $KUBE_CONFIG) { $LIST = "$KUBE_CONFIG;$FILES" } else { $LIST = $FILES }
$SAME = @($LIST.Split(';') | ForEach-Object { kubectl --kubeconfig $_ config get-contexts -o name 2>$null } |
  Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Remove-Item -Force -ErrorAction SilentlyContinue "$KUBE_CONFIG.new"
if ($MISSING.Count -gt 0) { "MISSING: $MISSING" }
elseif ($SAME.Count -gt 0) { "SAME CONTEXT NAME IN TWO FILES: $SAME" }
else {
  New-Item -ItemType Directory -Force -Path (Split-Path $KUBE_CONFIG) | Out-Null
  $OLD_KUBECONFIG = $env:KUBECONFIG; $env:KUBECONFIG = $LIST
  $MERGED = kubectl config view --flatten; $OK = ($LASTEXITCODE -eq 0)
  $env:KUBECONFIG = $OLD_KUBECONFIG
  if ($OK) {
    Set-Content -Encoding ascii -Path "$KUBE_CONFIG.new" -Value $MERGED
    kubectl --kubeconfig "$KUBE_CONFIG.new" config get-contexts; $OK = ($LASTEXITCODE -eq 0)
  }
  if ($OK) {
    if (Test-Path $KUBE_CONFIG) { Copy-Item -Force $KUBE_CONFIG "$KUBE_CONFIG.before-merge" }
    Move-Item -Force "$KUBE_CONFIG.new" $KUBE_CONFIG
    "merged into $KUBE_CONFIG"
  } else {
    Remove-Item -Force -ErrorAction SilentlyContinue "$KUBE_CONFIG.new"
    "FAILED: $KUBE_CONFIG is as it was (see the kubectl error above)"
  }
}
```

</details>

**Expect:** the merged contexts, your old current context still marked `*` (the first file's wins),
then `merged into …/.kube/config`. Then `kubectl --context <name> get nodes` answers for each
cluster.

**If not:**
- `MISSING: …`: set `FILES` to files that exist (kubectl itself would skip a missing file without
  a word).
- `SAME CONTEXT NAME IN TWO FILES: …`: only the first file's would be kept. Rename it in one file
  (`kubectl --kubeconfig <file> config rename-context <old> <new>`), or, if it is already in
  `~/.kube/config`, delete it there as above, and run this again.
- To undo: `mv ~/.kube/config.before-merge ~/.kube/config` (Windows:
  `Move-Item -Force $HOME\.kube\config.before-merge $HOME\.kube\config`); if you had no
  `~/.kube/config` before, delete it instead. A second merge replaces `config.before-merge`.

Back to [README](../README.md).
