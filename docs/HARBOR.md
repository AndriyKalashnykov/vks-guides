# Install Harbor on the Supervisor

You install Harbor in the vSphere Client; the blocks before and after need
[kubectl](KUBECTL.md), [jq, curl and openssl](PREREQS.md) and a [Supervisor login](SUPERVISOR-LOGIN.md).
Written for VCF 9.1.1 and Harbor Service 2.15.2 on a Supervisor with vSphere Distributed Switch
networking and the Foundation Load Balancer (not NSX). Upgrading Harbor is not covered.

**Installing or uninstalling Harbor updates every node of every VKS cluster on this
Supervisor**: VKS replaces some nodes and updates others in place, restarting their container
runtimes. Do it before you create VKS clusters, or in a maintenance window.

The blocks keep their files in `~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT>` (PowerShell:
`$HOME\.config\vks-guides\harbor-<SUPERVISOR_CONTEXT>`). Run them all on the same machine. Each
Supervisor gets its own folder, named after `SUPERVISOR_CONTEXT`. `SUPERVISOR_CONTEXT` is the name
of your Supervisor login from [SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca) (`supervisor`
unless you chose another); every block sets it, keep the same value in all of them.

## Prerequisites

- a vCenter administrator's SSO user (it may manage Supervisor Services and read Secrets, Kubernetes'
  stored passwords and keys, on the Supervisor), with a [Supervisor login](SUPERVISOR-LOGIN.md) ([VCF CLI](VCF.md));
- a Broadcom support account that can download **vSphere Supervisor Services**;
- [kubectl](KUBECTL.md), [jq, curl and openssl](PREREQS.md); for step 13 on Windows, `openssl.exe`
  from [Git for Windows](https://git-scm.com/install/);
- for step 10's podman or docker login (optional): [podman or docker](PREREQS.md#podman-and-docker-optional);
- for step 11: a VKS cluster ([CLUSTER.md](CLUSTER.md)) and its kubeconfig
  ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig));
- a storage class with room for Harbor's five volumes: 58 GiB (about 62 GB) with step 4's sizes (images 50Gi,
  Trivy 5Gi, three of 1Gi; more if you raise them), and one free load-balancer address;
- someone who can create a DNS record.

The connections this guide needs, for a firewall (all TCP, besides DNS; for a registry, also
the hosts in [Registry hosts](PREREQS.md#registry-hosts-for-a-firewall)):

| from | to | port | for |
|---|---|---|---|
| your browser | `support.broadcom.com` | 443 | downloading the Harbor files (step 2) |
| your browser | vCenter (the vSphere Client) | 443 | registering, installing, changing and removing Harbor (steps 5, 6, 12 to 14) |
| your machine (laptop or jump box) | the Supervisor's address | 443 | kubectl with the Supervisor kubeconfig (steps 1, 4, 6 to 9, 12 to 14, and *Bind the moved files*) |
| the Supervisor | `projects.packages.broadcom.com` | 443 | Harbor's images (step 6) |
| the Supervisor | `ghcr.io` | 443 | Harbor's scanner, Trivy: its vulnerability data |
| your machine and your browser | Harbor's address | 443 | checks, API calls, web page, podman or docker login (steps 7, 9, 10) |
| your machine (laptop or jump box) | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl (step 11) |
| the VKS cluster's nodes | Harbor's address | 443 | pulling images from Harbor (step 11) |

Decide before you install:

- the secrets: step 3;
- the volumes' storage classes and sizes: step 4's optional part;
- your organization's certificate: step 13; request it early, it takes time. To install with
  it, run step 13 *Write the certificate into the file* between step 4 and step 5.

If the folder `~/.config/vks-guides/harbor` (Windows: `$HOME\.config\vks-guides\harbor`) already
exists on this machine, run
[Files from an earlier version of this guide](#files-from-an-earlier-version-of-this-guide-optional)
first.

## 1. Check the Supervisor

Run this first, before you install, and again whenever you come back to this guide. It asks the
Supervisor, with your Supervisor login's file (`~/.kube/<SUPERVISOR_CONTEXT>.kubeconfig`, from
[SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md)), whether it already runs a Harbor, and changes nothing there. On this
machine it saves the Supervisor's ID in `supervisor-uid` (every later block checks it, so one
Supervisor's files are never used on another) and, if no Harbor runs, leaves a small note: step 14
reads that note before you uninstall, so you never remove a Harbor that someone else installed.
You get one line saying whether a Harbor runs on this Supervisor, and one saying what was
recorded. Set `SUPERVISOR_CONTEXT` to your Supervisor login's name (`supervisor` unless you chose
another).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
N="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -n "$REC" ] && [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC, Harbor ${N:-none}); set another SUPERVISOR_CONTEXT"
elif [ -z "$REC" ] && { [ -e "$HARBOR_DIR/secrets.env" ] || [ -e "$HARBOR_DIR/harbor-data-values.yml" ]; }; then
  echo "FAILED: $HARBOR_DIR holds Harbor files of an unknown Supervisor (hostname: ${N:-none}); if they belong to this Supervisor, bind them: see Files from an earlier version"
elif ! H="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o name)"; then
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
else
  MARK="$HARBOR_DIR/none-before-$SUP"
  if [ -z "$REC" ] && ! { mkdir -p "$HARBOR_DIR" && printf '%s\n' "$SUP" > "$HARBOR_DIR/supervisor-uid"; }; then
    rm -f "$HARBOR_DIR/supervisor-uid"
    echo "FAILED: cannot write $HARBOR_DIR (see the error above)"
  elif [ -z "$H" ] && [ ! -e "$MARK" ] && ! : > "$MARK"; then
    echo "FAILED: cannot write $HARBOR_DIR (see the error above)"
  else
    echo "Harbor on this Supervisor: ${H:-none}"
    if [ -e "$MARK" ]; then
      echo "recorded: this Supervisor had no Harbor when you began"
    else
      echo "recorded: nothing (a Harbor was already here)"
    fi
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$N = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
if ($LASTEXITCODE -ne 0 -or -not $SUP) {
  "FAILED: cannot read the Supervisor (see the error above)"
} elseif ($REC -and $REC -cne $SUP) {
  "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC, Harbor $(if ($N) { $N } else { 'none' })); set another SUPERVISOR_CONTEXT"
} elseif (-not $REC -and ((Test-Path "$HARBOR_DIR\secrets.env") -or (Test-Path "$HARBOR_DIR\harbor-data-values.yml"))) {
  "FAILED: $HARBOR_DIR holds Harbor files of an unknown Supervisor (hostname: $(if ($N) { $N } else { 'none' })); if they belong to this Supervisor, bind them: see Files from an earlier version"
} else {
  $H = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name
  if ($LASTEXITCODE -ne 0) {
    "FAILED: cannot list the Supervisor's namespaces (see the error above)"
  } else {
    $MARK = "$HARBOR_DIR\none-before-$SUP"
    $OK = $false
    try {
      if (-not $REC) {
        New-Item -ItemType Directory -Force -Path $HARBOR_DIR -ErrorAction Stop | Out-Null
        Set-Content -Encoding ascii -Path "$HARBOR_DIR\supervisor-uid" -Value $SUP -ErrorAction Stop
      }
      if (-not $H -and -not (Test-Path $MARK)) {
        New-Item -ItemType File -Path $MARK -ErrorAction Stop | Out-Null
      }
      $OK = $true
    } catch {
      if (-not "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()) {
        Remove-Item -LiteralPath "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue
      }
      "FAILED: cannot write $HARBOR_DIR ($($_.Exception.Message))"
    }
    if ($OK) {
      "Harbor on this Supervisor: $(if ($H) { $H -join ' ' } else { 'none' })"
      if (Test-Path $MARK) {
        "recorded: this Supervisor had no Harbor when you began"
      } else {
        "recorded: nothing (a Harbor was already here)"
      }
    }
  }
}
```

</details>

**Expect:** `Harbor on this Supervisor: none`, then
`recorded: this Supervisor had no Harbor when you began`. When you come back after installing:
`Harbor on this Supervisor: namespace/svc-harbor-…` (the namespace on the Supervisor that holds
Harbor; the vSphere Client lists it with the vSphere Namespaces), then
`recorded: this Supervisor had no Harbor when you began`: this Harbor is yours; go on at the step
you need.

**If not:**
- `FAILED: …` under `Unauthorized`: run [Renew the Supervisor login](SUPERVISOR-LOGIN.md#renew-the-supervisor-login).
  Under `Forbidden`: log in as a vCenter administrator.
- `namespace/svc-harbor-…` and `recorded: nothing …`: this Supervisor already runs a Harbor that
  you did not install. Use it, and do not install a second one.
- `FAILED: … belongs to another Supervisor (…)`:
  - If you disabled and enabled this Supervisor again, the folder belongs to the old one. Move it
    aside (`mv ~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT> ~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT>.old-<date>`;
    PowerShell: `Rename-Item $HOME\.config\vks-guides\harbor-<SUPERVISOR_CONTEXT> harbor-<SUPERVISOR_CONTEXT>.old-<date>`)
    and run this block again. Delete the `.old-<date>` folder later, only once you know its Harbor is gone.
  - Otherwise this folder holds the files of the Supervisor that this context name was used for
    before. Log in to this Supervisor under another name
    ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca)) and set `SUPERVISOR_CONTEXT` to it in
    every block.
- `FAILED: … holds Harbor files of an unknown Supervisor (…)`: the folder has Harbor's files but
  no `supervisor-uid`; nothing was written. If its hostname is this Supervisor's Harbor, run
  [Bind the moved files to this Supervisor](#bind-the-moved-files-to-this-supervisor); otherwise
  set another `SUPERVISOR_CONTEXT`.
- `FAILED: cannot write …`: the folder cannot be made or written (a file of that name, or no
  permission); fix that and run the block again.

## 2. Download the Harbor files

Download two files from Broadcom into `Downloads`. Tick **"I agree to the Terms and
Conditions"** if the page shows it, or the download icon does nothing.

| file | where to click |
|---|---|
| `supervisor-service-harbor-legacy-v2.15.2+vmware.1-vks.1-25639075.yml` | [Harbor 2.15.2](https://support.broadcom.com/group/ecx/productfiles?subFamily=vSphere%20Supervisor%20Services&displayGroup=Harbor&release=2.15.2&os=&servicePk=545829&language=EN) → *Installation Package Manifest (VCF 9.0 or older and disconnected/airgapped VCF 9.1)* |
| `supervisor-service-harbor-data-values-v2.15.2.yml` | [Harbor 2.15.2](https://support.broadcom.com/group/ecx/productfiles?subFamily=vSphere%20Supervisor%20Services&displayGroup=Harbor&release=2.15.2&os=&servicePk=545829&language=EN) → the row with this file name |

Take the manifest with **legacy** in its name: it downloads Harbor from
`projects.packages.broadcom.com`. The other one needs a VCF Software Depot and is not covered.
Do not put these files into a Git repository; they are licensed to your Broadcom account.

Run this after both downloads, before any later step uses the files. It checks that you
downloaded the right two files and that they are not damaged, and changes nothing. You get a
checksum (a fingerprint of the file's content) for each one; compare them with the lines below.
If you saved the files somewhere else than `Downloads`, set `HARBOR_MANIFEST` and
`HARBOR_VALUES_TEMPLATE` to where they are.

**Linux, macOS, WSL (bash or zsh):**

```sh
HARBOR_MANIFEST="$HOME/Downloads/supervisor-service-harbor-legacy-v2.15.2+vmware.1-vks.1-25639075.yml"
HARBOR_VALUES_TEMPLATE="$HOME/Downloads/supervisor-service-harbor-data-values-v2.15.2.yml"

for f in "$HARBOR_MANIFEST" "$HARBOR_VALUES_TEMPLATE"; do
  if [ -f "$f" ]; then
    printf '%s  %s\n' "$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | awk '{print $1}')" "$(basename "$f")"
  else
    echo "Not found: $f"
  fi
done
```

**Windows (PowerShell):**

```powershell
$HARBOR_MANIFEST = "$HOME\Downloads\supervisor-service-harbor-legacy-v2.15.2+vmware.1-vks.1-25639075.yml"
$HARBOR_VALUES_TEMPLATE = "$HOME\Downloads\supervisor-service-harbor-data-values-v2.15.2.yml"

foreach ($f in $HARBOR_MANIFEST, $HARBOR_VALUES_TEMPLATE) {
  if (Test-Path -LiteralPath $f) {
    "$((Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLower())  $(Split-Path -Leaf $f)"
  } else {
    "Not found: $f"
  }
}
```

**Expect:** these two lines:

```text
77115ad171c571a9e76ad234ca8fc9198aebdfc0db90e5244830603b52914902  supervisor-service-harbor-legacy-v2.15.2+vmware.1-vks.1-25639075.yml
52167e43d58bad377c7f10dde87bb9b8e27faacacd9a3d9e1810cb8815f53805  supervisor-service-harbor-data-values-v2.15.2.yml
```

**If not:**
- `Not found: …`: the file is not in `Downloads` under that name. Set the variable to where it
  is.
- `d26fcbf774df52db4963bd34d43c3ac000c6d537a5cb98c81bf0b504fda4ab6e`: that is the manifest
  without **legacy** in its name; download the other one.
- Any other checksum: a damaged or wrong download. Delete it and download it again.

## 3. Make the secrets file

Harbor is installed with seven passwords and keys: its `admin` password, its database password,
and keys Harbor uses inside itself. Run this step for any Harbor that is not a test, before step 4:
if you skip it, Harbor gets Broadcom's public default values (step 4's table lists them, and step 4
saves them in `secrets.env`, so the later steps work the same). Decide before step 6, because the
admin password, the database password and `secretKey` cannot be changed after the install. If you
change your mind after step 4, run step 4 again.

This block makes seven random values and saves them in `secrets.env`, in this guide's folder on
this machine (on Linux, macOS and WSL, readable only by you); it changes nothing on the
Supervisor. A file that exists is kept, so running it again changes nothing. Nothing secret is
printed: you get one line that counts the values, for step 4 to put into Harbor's configuration.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

SECRETS="$HARBOR_DIR/secrets.env"
if [ ! -s "$HARBOR_DIR/supervisor-uid" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
else
  if grep -q "^HARBOR_SECRET_KEY='0123456789ABCDEF'\$" "$SECRETS" 2>/dev/null; then
    echo "kept the existing $SECRETS (Broadcom's default values; for random ones, before step 6 delete it, run this block again, then step 4)"
  elif [ -e "$SECRETS" ]; then
    echo "kept the existing $SECRETS"
  else
    ( umask 077
      { printf "HARBOR_ADMIN_PASSWORD='A%sz'\n" "$(openssl rand -hex 12)"
        printf "HARBOR_SECRET_KEY='%s'\n" "$(openssl rand -hex 8)"
        printf "HARBOR_DB_PASSWORD='%s'\n" "$(openssl rand -hex 16)"
        printf "HARBOR_CORE_SECRET='%s'\n" "$(openssl rand -hex 16)"
        printf "HARBOR_XSRF_KEY='%s'\n" "$(openssl rand -hex 16)"
        printf "HARBOR_JOBSERVICE_SECRET='%s'\n" "$(openssl rand -hex 16)"
        printf "HARBOR_REGISTRY_SECRET='%s'\n" "$(openssl rand -hex 16)"
      } > "$SECRETS" )
  fi
  awk -F "'" '/^HARBOR_/ { n++; if ($2 !~ /^[A-Za-z0-9-]+$/) bad++ } /^HARBOR_SECRET_KEY=/ { k = length($2) } /^HARBOR_XSRF_KEY=/ { x = length($2) } END { printf "secrets file: %d values, %d not letters, digits or -, secretKey %d characters, xsrfKey %d characters\n", n, bad, k, x }' "$SECRETS"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$SECRETS = "$HARBOR_DIR\secrets.env"
function New-Hex($n) {
  $b = New-Object byte[] $n
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  ($b | ForEach-Object { $_.ToString('x2') }) -join ''
}
if (-not ((Get-Item -LiteralPath "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue).Length -gt 0)) {
  "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
} else {
  if (Test-Path $SECRETS) {
    if (@(Get-Content $SECRETS) -ccontains "HARBOR_SECRET_KEY='0123456789ABCDEF'") {
      "kept the existing $SECRETS (Broadcom's default values; for random ones, before step 6 delete it, run this block again, then step 4)"
    } else {
      "kept the existing $SECRETS"
    }
  } else {
    Set-Content -Encoding ascii -Path $SECRETS -Value @(
      "HARBOR_ADMIN_PASSWORD='A$(New-Hex 12)z'"
      "HARBOR_SECRET_KEY='$(New-Hex 8)'"
      "HARBOR_DB_PASSWORD='$(New-Hex 16)'"
      "HARBOR_CORE_SECRET='$(New-Hex 16)'"
      "HARBOR_XSRF_KEY='$(New-Hex 16)'"
      "HARBOR_JOBSERVICE_SECRET='$(New-Hex 16)'"
      "HARBOR_REGISTRY_SECRET='$(New-Hex 16)'"
    )
  }
  $S = @{}; $BAD = 0
  foreach ($l in Get-Content $SECRETS) {
    if ($l -cmatch "^(HARBOR_[A-Z_]+)='(.*)'$") {
      $k = $Matches[1]; $v = $Matches[2]; $S[$k] = $v
      if ($v -cnotmatch '^[A-Za-z0-9-]+$') { $BAD++ }
    }
  }
  "secrets file: $($S.Count) values, $BAD not letters, digits or -, secretKey $("$($S['HARBOR_SECRET_KEY'])".Length) characters, xsrfKey $("$($S['HARBOR_XSRF_KEY'])".Length) characters"
}
```

</details>

**Expect:** `secrets file: 7 values, 0 not letters, digits or -, secretKey 16 characters, xsrfKey 32 characters`,
after `kept the existing …` when the file was there.

**If not:**
- `FAILED: … has no supervisor-uid`: run step 1 first, with the same `SUPERVISOR_CONTEXT`.
- Other numbers: the file was edited or cut short. If no Harbor was installed with it yet, delete
  it, run the block again, then step 4.

**Your own admin password:** to use it instead, change `HARBOR_ADMIN_PASSWORD` in `secrets.env`
before step 4, using only letters, digits and `-`: step 4 refuses any other character.

**Keep this file, and a copy where you keep passwords, for as long as this Harbor exists**: any
later change to its configuration must send the same seven values (with another
`HARBOR_SECRET_KEY` Harbor can no longer read what it encrypted). vCenter shows the configuration
to everyone who may manage Supervisor Services.

## 4. Write the configuration file

### Choose the storage class

Harbor keeps its data on five disks (volumes). A storage class is a kind of vSphere storage that
the Supervisor offers for such disks, named after a vCenter storage policy (the vSphere Client
lists the policies: [NAMESPACE.md step 2](NAMESPACE.md#2-find-the-storage-policies-and-the-vm-classes)).
Run this before *Write the file*, to pick the storage class for Harbor's disks. It lists the
storage classes the Supervisor offers, and changes nothing. You get their names: set one of them
as `HARBOR_STORAGE_CLASS` in the next block.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get storageclass -o custom-columns=NAME:.metadata.name --no-headers
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get storageclass -o custom-columns=NAME:.metadata.name --no-headers
```

**Expect:** one name per line, for example `wcp-vmfs`.

**If not:** `error: You must be logged in to the server (Unauthorized)`: run [Renew the
Supervisor login](SUPERVISOR-LOGIN.md#renew-the-supervisor-login), then the block again.

### Write the file

Harbor's configuration file is Broadcom's file with only these fields changed:

| field in Broadcom's file | Broadcom's value | set to |
|---|---|---|
| `hostname` | `yourdomain.com` | `HARBOR_FQDN` |
| `enableNginxLoadBalancer`, `enableContourHttpProxy` | `false`, `true` | `true`, `false`: Harbor gets its own load-balancer address |
| `harborAdminPassword` | `Harbor12345` | the value in `secrets.env` (step 3); kept if you skipped step 3 |
| `secretKey` | `0123456789ABCDEF` | the value in `secrets.env`; kept if you skipped step 3 |
| `database.password` | `change-it` | the value in `secrets.env`; kept if you skipped step 3 |
| `core.secret` | `change-it` | the value in `secrets.env`; kept if you skipped step 3 |
| `core.xsrfKey` | `0123456789ABCDEF0123456789ABCDEF` | the value in `secrets.env`; kept if you skipped step 3 |
| `jobservice.secret` | `change-it` | the value in `secrets.env`; kept if you skipped step 3 |
| `registry.secret` | `change-it` | the value in `secrets.env`; kept if you skipped step 3 |
| `storageClass` of the five volumes | `insert-storage-class-name-here` | `HARBOR_STORAGE_CLASS` |
| the registry volume's `size` | `10Gi` | `HARBOR_REGISTRY_SIZE` |

Run this after step 3 (or instead of it, for a test) and before step 6. It writes Harbor's
configuration file, `harbor-data-values.yml`, in this guide's folder on this machine, from
Broadcom's file and `secrets.env`; nothing changes on the Supervisor yet. Set at the top:

- `HARBOR_FQDN`: Harbor's DNS name. To change it later, see step 12.
- `HARBOR_STORAGE_CLASS`: a name from the list above.
- `HARBOR_REGISTRY_SIZE`: the volume for your images. `10Gi` fills up in regular use, and this
  guide does not cover growing it.
- `HARBOR_VALUES_TEMPLATE`: only if Broadcom's data values file is not in `Downloads`.

You get the changed fields and counts; you paste this file into the vSphere Client when you
install Harbor in step 6. The block checks the file first, and deletes it if anything came out
wrong. Running it again writes the file anew from Broadcom's file: if you ran the optional block
below or step 13's *Write the certificate into the file*, run them again after it.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
HARBOR_FQDN="harbor.example.test"
HARBOR_STORAGE_CLASS="my-storage-class"
HARBOR_REGISTRY_SIZE="50Gi"
HARBOR_VALUES_TEMPLATE="$HOME/Downloads/supervisor-service-harbor-data-values-v2.15.2.yml"
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

SECRETS="$HARBOR_DIR/secrets.env"
VALUES="$HARBOR_DIR/harbor-data-values.yml"
WANT=52167e43d58bad377c7f10dde87bb9b8e27faacacd9a3d9e1810cb8815f53805
GOT="$( (sha256sum "$HARBOR_VALUES_TEMPLATE" 2>/dev/null || shasum -a 256 "$HARBOR_VALUES_TEMPLATE" 2>/dev/null) | awk '{print $1}')"
case "$HARBOR_FQDN" in ""|harbor.example.test) BAD_NAME=1 ;; *) BAD_NAME="" ;; esac
[ -z "$(printf '%s' "$HARBOR_FQDN" | LC_ALL=C tr -d 'a-z0-9.-')" ] || BAD_NAME=1
case "$HARBOR_STORAGE_CLASS" in ""|my-storage-class) BAD_SC=1 ;; *) BAD_SC="" ;; esac
[ -z "$(printf '%s' "$HARBOR_STORAGE_CLASS" | LC_ALL=C tr -d 'a-z0-9.-')" ] || BAD_SC=1
case "$HARBOR_REGISTRY_SIZE" in "") BAD_SIZE=1 ;; *) BAD_SIZE="" ;; esac
[ -z "$(printf '%s' "$HARBOR_REGISTRY_SIZE" | LC_ALL=C tr -d '0-9A-Za-z')" ] || BAD_SIZE=1
if [ -n "$BAD_NAME" ]; then
  echo "NOT WRITTEN: set HARBOR_FQDN to this Harbor's DNS name"
elif [ -n "$BAD_SC" ] || [ -n "$BAD_SIZE" ]; then
  echo "NOT WRITTEN: set HARBOR_STORAGE_CLASS to a name from the list, and HARBOR_REGISTRY_SIZE"
elif [ ! -s "$HARBOR_DIR/supervisor-uid" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ -e "$SECRETS" ] && [ "$(grep -c -E "^HARBOR_[A-Z_]+='[A-Za-z0-9-]+'\$" "$SECRETS")" != 7 ]; then
  echo "NOT WRITTEN: $SECRETS is not as step 3 writes it"
elif [ "$GOT" != "$WANT" ]; then
  echo "NOT WRITTEN: $HARBOR_VALUES_TEMPLATE is missing or not the 2.15.2 file (step 2)"
else
  if [ ! -e "$SECRETS" ]; then
    mkdir -p "$HARBOR_DIR"
    ( umask 077
      printf "%s\n" "HARBOR_ADMIN_PASSWORD='Harbor12345'" "HARBOR_SECRET_KEY='0123456789ABCDEF'" \
        "HARBOR_DB_PASSWORD='change-it'" "HARBOR_CORE_SECRET='change-it'" "HARBOR_XSRF_KEY='0123456789ABCDEF0123456789ABCDEF'" \
        "HARBOR_JOBSERVICE_SECRET='change-it'" "HARBOR_REGISTRY_SECRET='change-it'" > "$SECRETS" )
    echo "no secrets file: Broadcom's default values (admin password Harbor12345), saved in $SECRETS"
  fi
  rm -f "$VALUES"
  ( umask 077
    set -a; . "$SECRETS"; set +a
    awk -v fqdn="$HARBOR_FQDN" -v sc="$HARBOR_STORAGE_CLASS" -v size="$HARBOR_REGISTRY_SIZE" '
      function q(v) { return "\"" v "\"" }
      /^[A-Za-z][A-Za-z0-9_]*:/     { top = $1; sub(/:.*/, "", top); k4 = "" }
      /^    [A-Za-z][A-Za-z0-9_]*:/ { k4 = $1; sub(/:.*/, "", k4) }
      /^hostname:/                { print "hostname: " fqdn; next }
      /^enableNginxLoadBalancer:/ { print "enableNginxLoadBalancer: true"; next }
      /^enableContourHttpProxy:/  { print "enableContourHttpProxy: false"; next }
      /^harborAdminPassword:/     { print "harborAdminPassword: " q(ENVIRON["HARBOR_ADMIN_PASSWORD"]); next }
      /^secretKey:/               { print "secretKey: " q(ENVIRON["HARBOR_SECRET_KEY"]); next }
      /^  password:/ && top == "database"   { print "  password: " q(ENVIRON["HARBOR_DB_PASSWORD"]); next }
      /^  secret:/   && top == "core"       { print "  secret: " q(ENVIRON["HARBOR_CORE_SECRET"]); next }
      /^  xsrfKey:/  && top == "core"       { print "  xsrfKey: " q(ENVIRON["HARBOR_XSRF_KEY"]); next }
      /^  secret:/   && top == "jobservice" { print "  secret: " q(ENVIRON["HARBOR_JOBSERVICE_SECRET"]); next }
      /^  secret:/   && top == "registry"   { print "  secret: " q(ENVIRON["HARBOR_REGISTRY_SECRET"]); next }
      /^ +storageClass:/          { sub(/storageClass:.*/, "storageClass: " q(sc)); print; next }
      /^      size:/ && top == "persistence" && k4 == "registry" { print "      size: " size; next }
      { print }
    ' "$HARBOR_VALUES_TEMPLATE" > "$VALUES" )
  NAME="$(sed -n 's/^hostname: //p' "$VALUES")"
  LEFT="$(grep -c -E 'yourdomain\.com|insert-storage-class-name-here' "$VALUES")"
  SEC="$(grep -c -E '^(harborAdminPassword|secretKey|  password|  secret|  xsrfKey): "[A-Za-z0-9-]+"$' "$VALUES")"
  SC="$(grep -c -F "storageClass: \"$HARBOR_STORAGE_CLASS\"" "$VALUES")"
  SIZE="$(awk '/^[A-Za-z][A-Za-z0-9_]*:/ { top = $1; k4 = "" } /^    [A-Za-z][A-Za-z0-9_]*:/ { k4 = $1 } /^      size:/ && top == "persistence:" && k4 == "registry:" { print $2 }' "$VALUES")"
  grep -E '^(hostname|enableNginxLoadBalancer|enableContourHttpProxy):' "$VALUES"
  echo "storage class fields set: $SC of 5"
  echo "registry volume: ${SIZE:-not found}"
  echo "secret fields set: $SEC of 7"
  echo "placeholders left: $LEFT"
  if [ -z "$NAME" ] || [ "$NAME" != "$HARBOR_FQDN" ] || [ "$LEFT" != 0 ] || [ "$SEC" != 7 ] || [ "$SC" != 5 ] || [ "$SIZE" != "$HARBOR_REGISTRY_SIZE" ]; then
    rm -f "$VALUES"
    echo "FAILED: the file did not come out as expected and was deleted"
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$HARBOR_FQDN = "harbor.example.test"
$HARBOR_STORAGE_CLASS = "my-storage-class"
$HARBOR_REGISTRY_SIZE = "50Gi"
$HARBOR_VALUES_TEMPLATE = "$HOME\Downloads\supervisor-service-harbor-data-values-v2.15.2.yml"
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$SECRETS = "$HARBOR_DIR\secrets.env"
$VALUES = "$HARBOR_DIR\harbor-data-values.yml"
$WANT = '52167e43d58bad377c7f10dde87bb9b8e27faacacd9a3d9e1810cb8815f53805'
$GOT = if (Test-Path -LiteralPath $HARBOR_VALUES_TEMPLATE) { (Get-FileHash -Algorithm SHA256 -LiteralPath $HARBOR_VALUES_TEMPLATE).Hash.ToLower() } else { '' }
$S = @{}
if (Test-Path $SECRETS) {
  foreach ($l in Get-Content $SECRETS) { if ($l -cmatch "^(HARBOR_[A-Z_]+)='([A-Za-z0-9-]+)'$") { $S[$Matches[1]] = $Matches[2] } }
}
if ($HARBOR_FQDN -cnotmatch '^[a-z0-9.-]+$' -or $HARBOR_FQDN -eq 'harbor.example.test') {
  "NOT WRITTEN: set HARBOR_FQDN to this Harbor's DNS name"
} elseif ($HARBOR_STORAGE_CLASS -cnotmatch '^[a-z0-9.-]+$' -or $HARBOR_STORAGE_CLASS -eq 'my-storage-class' -or $HARBOR_REGISTRY_SIZE -cnotmatch '^[0-9A-Za-z]+$') {
  "NOT WRITTEN: set HARBOR_STORAGE_CLASS to a name from the list, and HARBOR_REGISTRY_SIZE"
} elseif (-not ((Get-Item -LiteralPath "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue).Length -gt 0)) {
  "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
} elseif ((Test-Path $SECRETS) -and $S.Count -ne 7) {
  "NOT WRITTEN: $SECRETS is not as step 3 writes it"
} elseif ($GOT -ne $WANT) {
  "NOT WRITTEN: $HARBOR_VALUES_TEMPLATE is missing or not the 2.15.2 file (step 2)"
} else {
  if (-not (Test-Path $SECRETS)) {
    New-Item -ItemType Directory -Force -Path $HARBOR_DIR | Out-Null
    Set-Content -Encoding ascii -Path $SECRETS -Value @(
      "HARBOR_ADMIN_PASSWORD='Harbor12345'", "HARBOR_SECRET_KEY='0123456789ABCDEF'", "HARBOR_DB_PASSWORD='change-it'",
      "HARBOR_CORE_SECRET='change-it'", "HARBOR_XSRF_KEY='0123456789ABCDEF0123456789ABCDEF'",
      "HARBOR_JOBSERVICE_SECRET='change-it'", "HARBOR_REGISTRY_SECRET='change-it'")
    foreach ($l in Get-Content $SECRETS) { if ($l -cmatch "^(HARBOR_[A-Z_]+)='([A-Za-z0-9-]+)'$") { $S[$Matches[1]] = $Matches[2] } }
    "no secrets file: Broadcom's default values (admin password Harbor12345), saved in $SECRETS"
  }
  $top = ''; $k4 = ''
  $OUT = foreach ($l in [IO.File]::ReadAllLines($HARBOR_VALUES_TEMPLATE)) {
    if ($l -cmatch '^([A-Za-z][A-Za-z0-9_]*):') { $top = $Matches[1]; $k4 = '' }
    if ($l -cmatch '^    ([A-Za-z][A-Za-z0-9_]*):') { $k4 = $Matches[1] }
    if ($l -cmatch '^hostname:') { "hostname: $HARBOR_FQDN" } elseif ($l -cmatch '^enableNginxLoadBalancer:') { 'enableNginxLoadBalancer: true' } elseif ($l -cmatch '^enableContourHttpProxy:') { 'enableContourHttpProxy: false' } elseif ($l -cmatch '^harborAdminPassword:') { "harborAdminPassword: `"$($S['HARBOR_ADMIN_PASSWORD'])`"" } elseif ($l -cmatch '^secretKey:') { "secretKey: `"$($S['HARBOR_SECRET_KEY'])`"" } elseif ($l -cmatch '^  password:' -and $top -ceq 'database') { "  password: `"$($S['HARBOR_DB_PASSWORD'])`"" } elseif ($l -cmatch '^  secret:' -and $top -ceq 'core') { "  secret: `"$($S['HARBOR_CORE_SECRET'])`"" } elseif ($l -cmatch '^  xsrfKey:' -and $top -ceq 'core') { "  xsrfKey: `"$($S['HARBOR_XSRF_KEY'])`"" } elseif ($l -cmatch '^  secret:' -and $top -ceq 'jobservice') { "  secret: `"$($S['HARBOR_JOBSERVICE_SECRET'])`"" } elseif ($l -cmatch '^  secret:' -and $top -ceq 'registry') { "  secret: `"$($S['HARBOR_REGISTRY_SECRET'])`"" } elseif ($l -cmatch '^ +storageClass:') { $l.Substring(0, $l.IndexOf('storageClass:')) + "storageClass: `"$HARBOR_STORAGE_CLASS`"" } elseif ($l -cmatch '^      size:' -and $top -ceq 'persistence' -and $k4 -ceq 'registry') { "      size: $HARBOR_REGISTRY_SIZE" } else { $l }
  }
  [IO.File]::WriteAllText($VALUES, (($OUT -join "`n") + "`n"))
  $TXT = [IO.File]::ReadAllLines($VALUES)
  $NAME = "$(($TXT | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
  $LEFT = @($TXT | Where-Object { $_ -cmatch 'yourdomain\.com|insert-storage-class-name-here' }).Count
  $SEC = @($TXT | Where-Object { $_ -cmatch '^(harborAdminPassword|secretKey|  password|  secret|  xsrfKey): "[A-Za-z0-9-]+"$' }).Count
  $SC = @($TXT | Where-Object { $_.Contains("storageClass: `"$HARBOR_STORAGE_CLASS`"") }).Count
  $top = ''; $k4 = ''; $SIZE = ''
  foreach ($l in $TXT) {
    if ($l -cmatch '^([A-Za-z][A-Za-z0-9_]*):') { $top = $Matches[1]; $k4 = '' }
    if ($l -cmatch '^    ([A-Za-z][A-Za-z0-9_]*):') { $k4 = $Matches[1] }
    if ($l -cmatch '^      size: (.*)$' -and $top -ceq 'persistence' -and $k4 -ceq 'registry') { $SIZE = $Matches[1] }
  }
  $TXT | Where-Object { $_ -cmatch '^(hostname|enableNginxLoadBalancer|enableContourHttpProxy):' }
  "storage class fields set: $SC of 5"
  "registry volume: $(if ($SIZE) { $SIZE } else { 'not found' })"
  "secret fields set: $SEC of 7"
  "placeholders left: $LEFT"
  if (-not $NAME -or $NAME -cne $HARBOR_FQDN -or $LEFT -ne 0 -or $SEC -ne 7 -or $SC -ne 5 -or $SIZE -cne $HARBOR_REGISTRY_SIZE) {
    Remove-Item -Force $VALUES
    "FAILED: the file did not come out as expected and was deleted"
  }
}
```

</details>

**Expect:** with your own name and size:

```text
hostname: harbor.example.test
enableNginxLoadBalancer: true
enableContourHttpProxy: false
storage class fields set: 5 of 5
registry volume: 50Gi
secret fields set: 7 of 7
placeholders left: 0
```

If you skipped step 3, a `no secrets file: Broadcom's default values …` line comes first.

**If not:**
- `NOT WRITTEN: …`: set the value it names, or do the step it names, then run the block again.
- `FAILED: … has no supervisor-uid`: run step 1 first, with the same `SUPERVISOR_CONTEXT`.
- `FAILED: the file did not come out …`: the data values are laid out differently from the
  2.15.2 file. Do not install with a file this block refused.

The file holds the secrets in clear text: do not share or commit it.

### Choose each volume's storage class and size (optional)

The block in *Write the file* put all five of Harbor's disks on `HARBOR_STORAGE_CLASS`, with
Broadcom's sizes (`1Gi` each for the job log, the database and Redis, Harbor's cache; `5Gi` for
Trivy, the image scanner) and the registry at `HARBOR_REGISTRY_SIZE`. Skip this unless you want
one of them on another storage class or at another size. Run it after *Write the file* and before
step 6: after the install Harbor cannot change a disk's class, nor the size of the database,
Redis or Trivy disk. This block changes only the lines of the disks you set at its top, in
`harbor-data-values.yml` on this machine: set a storage class (a name from the list above) or a
size (such as `20Gi`), and leave the others `""`. You get each disk's class and size, and how many
lines changed.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
HARBOR_REGISTRY_STORAGE_CLASS=""
HARBOR_JOBSERVICE_STORAGE_CLASS=""
HARBOR_JOBSERVICE_SIZE=""
HARBOR_DATABASE_STORAGE_CLASS=""
HARBOR_DATABASE_SIZE=""
HARBOR_REDIS_STORAGE_CLASS=""
HARBOR_REDIS_SIZE=""
HARBOR_TRIVY_STORAGE_CLASS=""
HARBOR_TRIVY_SIZE=""
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

VALUES="$HARBOR_DIR/harbor-data-values.yml"
BAD=""
for v in "$HARBOR_REGISTRY_STORAGE_CLASS" "$HARBOR_JOBSERVICE_STORAGE_CLASS" "$HARBOR_DATABASE_STORAGE_CLASS" \
         "$HARBOR_REDIS_STORAGE_CLASS" "$HARBOR_TRIVY_STORAGE_CLASS"; do
  [ -z "$(printf '%s' "$v" | LC_ALL=C tr -d 'a-z0-9.-')" ] || BAD=1
done
for v in "$HARBOR_JOBSERVICE_SIZE" "$HARBOR_DATABASE_SIZE" "$HARBOR_REDIS_SIZE" "$HARBOR_TRIVY_SIZE"; do
  [ -z "$v" ] || printf '%s\n' "$v" | grep -qE '^[1-9][0-9]*(Mi|Gi|Ti)$' || BAD=1
done
if [ ! -s "$VALUES" ]; then
  echo "NOT WRITTEN: $VALUES is missing (Write the file)"
elif [ -n "$BAD" ]; then
  echo "NOT WRITTEN: a storage class is not a name from the list, or a size is not like 2Gi"
else
  rm -f "$VALUES.new"
  ( umask 077
    awk -v c_registry="$HARBOR_REGISTRY_STORAGE_CLASS" \
        -v c_jobservice="$HARBOR_JOBSERVICE_STORAGE_CLASS" -v s_jobservice="$HARBOR_JOBSERVICE_SIZE" \
        -v c_database="$HARBOR_DATABASE_STORAGE_CLASS" -v s_database="$HARBOR_DATABASE_SIZE" \
        -v c_redis="$HARBOR_REDIS_STORAGE_CLASS" -v s_redis="$HARBOR_REDIS_SIZE" \
        -v c_trivy="$HARBOR_TRIVY_STORAGE_CLASS" -v s_trivy="$HARBOR_TRIVY_SIZE" '
      BEGIN { c["registry"] = c_registry; c["jobservice"] = c_jobservice; s["jobservice"] = s_jobservice
              c["database"] = c_database; s["database"] = s_database; c["redis"] = c_redis
              s["redis"] = s_redis; c["trivy"] = c_trivy; s["trivy"] = s_trivy }
      /^[A-Za-z][A-Za-z0-9_]*:/     { top = $1; sub(/:.*/, "", top); k4 = "" }
      /^    [A-Za-z][A-Za-z0-9_]*:/ { k4 = $1; sub(/:.*/, "", k4) }
      top == "persistence" && /^ +storageClass:/ && c[k4] != "" { sub(/storageClass:.*/, "storageClass: \"" c[k4] "\"") }
      top == "persistence" && /^ +size:/ && s[k4] != ""         { sub(/size:.*/, "size: " s[k4]) }
      { print }
    ' "$VALUES" > "$VALUES.new" )
  awk '
    /^[A-Za-z][A-Za-z0-9_]*:/     { top = $1; sub(/:.*/, "", top); k4 = "" }
    /^    [A-Za-z][A-Za-z0-9_]*:/ { k4 = $1; sub(/:.*/, "", k4) }
    top == "persistence" && /^ +storageClass:/ { v = $2; gsub(/"/, "", v); c[k4] = v }
    top == "persistence" && /^ +size:/         { s[k4] = $2 }
    END { n = split("registry jobservice database redis trivy", k, " ")
          for (i = 1; i <= n; i++) printf "%-11s %s %s\n", k[i] ":", c[k[i]], s[k[i]] }
  ' "$VALUES.new"
  N="$(diff "$VALUES" "$VALUES.new" | grep -c '^>')"
  if [ "$(grep -c -E '^ +(storageClass|size):' "$VALUES.new")" != 10 ] || [ "$(wc -l < "$VALUES.new")" != "$(wc -l < "$VALUES")" ]; then
    rm -f "$VALUES.new"
    echo "FAILED: the file did not come out as expected; $VALUES is as it was"
  else
    mv "$VALUES.new" "$VALUES"
    echo "lines changed: $N"
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$HARBOR_REGISTRY_STORAGE_CLASS = ""
$HARBOR_JOBSERVICE_STORAGE_CLASS = ""
$HARBOR_JOBSERVICE_SIZE = ""
$HARBOR_DATABASE_STORAGE_CLASS = ""
$HARBOR_DATABASE_SIZE = ""
$HARBOR_REDIS_STORAGE_CLASS = ""
$HARBOR_REDIS_SIZE = ""
$HARBOR_TRIVY_STORAGE_CLASS = ""
$HARBOR_TRIVY_SIZE = ""
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$VALUES = "$HARBOR_DIR\harbor-data-values.yml"
$C = @{ registry = $HARBOR_REGISTRY_STORAGE_CLASS; jobservice = $HARBOR_JOBSERVICE_STORAGE_CLASS
        database = $HARBOR_DATABASE_STORAGE_CLASS; redis = $HARBOR_REDIS_STORAGE_CLASS; trivy = $HARBOR_TRIVY_STORAGE_CLASS }
$S = @{ jobservice = $HARBOR_JOBSERVICE_SIZE; database = $HARBOR_DATABASE_SIZE; redis = $HARBOR_REDIS_SIZE; trivy = $HARBOR_TRIVY_SIZE }
$BAD = @($C.Values | Where-Object { $_ -and $_ -cnotmatch '^[a-z0-9.-]+$' }).Count + @($S.Values | Where-Object { $_ -and $_ -cnotmatch '^[1-9][0-9]*(Mi|Gi|Ti)$' }).Count
if (-not (Test-Path $VALUES)) {
  "NOT WRITTEN: $VALUES is missing (Write the file)"
} elseif ($BAD -gt 0) {
  "NOT WRITTEN: a storage class is not a name from the list, or a size is not like 2Gi"
} else {
  $IN = [IO.File]::ReadAllLines($VALUES); $top = ''; $k4 = ''
  $OUT = foreach ($l in $IN) {
    if ($l -cmatch '^([A-Za-z][A-Za-z0-9_]*):') { $top = $Matches[1]; $k4 = '' }
    if ($l -cmatch '^    ([A-Za-z][A-Za-z0-9_]*):') { $k4 = $Matches[1] }
    if ($top -eq 'persistence' -and $l -cmatch '^( +)storageClass:' -and $C[$k4]) { "$($Matches[1])storageClass: `"$($C[$k4])`"" } elseif ($top -eq 'persistence' -and $l -cmatch '^( +)size:' -and $S[$k4]) { "$($Matches[1])size: $($S[$k4])" } else { $l }
  }
  $top = ''; $k4 = ''; $GOT = @{}
  foreach ($l in $OUT) {
    if ($l -cmatch '^([A-Za-z][A-Za-z0-9_]*):') { $top = $Matches[1]; $k4 = '' }
    if ($l -cmatch '^    ([A-Za-z][A-Za-z0-9_]*):') { $k4 = $Matches[1] }
    if ($top -eq 'persistence' -and $l -cmatch '^ +(storageClass|size): *"?([^"]*)"?$') { $GOT["$k4 $($Matches[1])"] = $Matches[2] }
  }
  foreach ($k in 'registry', 'jobservice', 'database', 'redis', 'trivy') { "{0,-11} {1} {2}" -f "${k}:", $GOT["$k storageClass"], $GOT["$k size"] }
  $N = @(for ($i = 0; $i -lt $IN.Count; $i++) { if ($IN[$i] -cne $OUT[$i]) { $i } }).Count
  if ($GOT.Count -ne 10 -or $OUT.Count -ne $IN.Count) {
    "FAILED: the file did not come out as expected; $VALUES is as it was"
  } else {
    [IO.File]::WriteAllText($VALUES, ($OUT -join "`n") + "`n")
    "lines changed: $N"
  }
}
```

</details>

**Expect:** one line per volume with its class and size, for example `trivy:      wcp-vmfs 20Gi`,
then `lines changed:` and the number of values you set (`0` when all are `""`).

**If not:**
- `NOT WRITTEN: …`: set the value it names, or do the step it names, then run the block again.
- `FAILED: …`: the file is laid out differently from step 4's; run *Write the file* again first.

To install with your organization's certificate, run step 13 *Write the certificate into the file*
now (step 13 *Request the certificate* first if you have no certificate yet), then go on with
step 5.

## 5. Register the service with vCenter

Done once per vCenter. If a **Harbor** card is already on the page in the first picture, skip to
step 6.

1. Open the vSphere Client. From the menu (☰, top left) choose **Supervisor Management**, then
   the **Services** tab.
2. On the **Add New Service** card click **ADD**.

   ![The Services tab of Supervisor Management, with the Add New Service card and its ADD button](img/harbor/01-services-add.png)

3. In the **New Service** window click **UPLOAD** and choose the manifest with **legacy** in its
   name. The window shows *YAML was uploaded successfully*, name **Harbor**, ID
   `harbor.tanzu.vmware.com`, version `2.15.2+vmware.1-vks.1`.

   ![The New Service window after the upload, showing the file name and the service details](img/harbor/02-new-service-uploaded.png)

4. Click **FINISH**.

**Expect:** a green line saying the service is registered, and a **Harbor** card with **Active
Versions 1** and **Supervisors 0**.

![The Services tab after registration, with the green success line and the Harbor card](img/harbor/03-registered.png)

**If not:** no **ADD** button, or the upload is refused: your user may not manage Supervisor
Services. An error naming the YAML: you chose the wrong file.

## 6. Install the service on your Supervisor

No VKS clusters yet: skip *Record the VKS cluster machines* here and step 8.

### Record the VKS cluster machines

Installing Harbor makes VKS update every node of your VKS clusters (a node is one of the VMs a VKS
cluster runs on; VKS calls it a machine), so that they trust Harbor. Run this right before you
install, once for each vSphere Namespace (the namespace in vCenter) that holds VKS clusters. It
saves the current list of machines in that vSphere Namespace in a file on this machine, and changes
nothing on the Supervisor. Set `VSPHERE_NAMESPACE` to that vSphere Namespace's name. You get the number
of machines recorded; step 8 compares against this record to show when every node has been updated.
Running it again for the same vSphere Namespace replaces its record, so run it again only right
before an install or step 13's change, never while the nodes are being updated.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VSPHERE_NAMESPACE="my-namespace"
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif ! kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace "$VSPHERE_NAMESPACE" >/dev/null; then
  echo "FAILED: cannot read the namespace $VSPHERE_NAMESPACE (see the error above)"
elif ! M="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VSPHERE_NAMESPACE" get machines.cluster.x-k8s.io -o jsonpath="{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=='UpToDate')].status} {.status.conditions[?(@.type=='UpToDate')].lastTransitionTime}{'\n'}{end}")"; then
  echo "FAILED: cannot list the machines in $VSPHERE_NAMESPACE (see the error above)"
elif [ -z "$M" ]; then
  echo "no machines in $VSPHERE_NAMESPACE: nothing to record"
else
  mkdir -p "$HARBOR_DIR"
  printf '%s\n' "$M" > "$HARBOR_DIR/machines-$VSPHERE_NAMESPACE.before"
  echo "recorded $(printf '%s\n' "$M" | grep -c .) machines in $VSPHERE_NAMESPACE"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VSPHERE_NAMESPACE = "my-namespace"
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace $VSPHERE_NAMESPACE | Out-Null
if (-not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } elseif (-not $REC) { "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first" } elseif ($REC -cne $SUP) { "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT" } elseif ($LASTEXITCODE -ne 0) { "FAILED: cannot read the namespace $VSPHERE_NAMESPACE (see the error above)" } else {
  $M = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VSPHERE_NAMESPACE get machines.cluster.x-k8s.io -o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type==''UpToDate'')].status} {.status.conditions[?(@.type==''UpToDate'')].lastTransitionTime}{''\n''}{end}'
  if ($LASTEXITCODE -ne 0) { "FAILED: cannot list the machines in $VSPHERE_NAMESPACE (see the error above)" } elseif (-not ($M | Where-Object { $_ })) { "no machines in ${VSPHERE_NAMESPACE}: nothing to record" } else {
    New-Item -ItemType Directory -Force -Path $HARBOR_DIR | Out-Null
    Set-Content -Encoding ascii -Path "$HARBOR_DIR\machines-$VSPHERE_NAMESPACE.before" -Value $M
    "recorded $(@($M | Where-Object { $_ }).Count) machines in $VSPHERE_NAMESPACE"
  }
}
```

</details>

**Expect:** `recorded <n> machines in <your namespace>`, one for each node of its VKS clusters.

**If not:**
- `FAILED: … has no supervisor-uid …`: run step 1 first. `FAILED: … belongs to another
  Supervisor (…)`: see step 1's **If not**.
- Other `FAILED: …` lines: as in [NAMESPACE.md](NAMESPACE.md#8-check-the-namespace) (`NotFound`,
  `Forbidden`, `Unauthorized`).

### Copy the configuration

Run this right before *Install it*. It checks that this guide's folder belongs to this
Supervisor, then copies `harbor-data-values.yml` to the clipboard of this machine, without showing
it; nothing else changes. You get `copied to the clipboard`, ready to paste into the vSphere Client
in *Install it*. The file holds Harbor's passwords: if your desktop keeps a clipboard history,
switch it off for this step.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

VALUES="$HARBOR_DIR/harbor-data-values.yml"
REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif [ ! -s "$VALUES" ]; then
  echo "Nothing copied: $VALUES is missing (step 4)"
elif command -v pbcopy >/dev/null 2>&1; then
  pbcopy < "$VALUES" && echo "copied to the clipboard" || echo "FAILED: nothing copied (no desktop session here?)"
elif command -v wl-copy >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  wl-copy --type text/plain < "$VALUES" && echo "copied to the clipboard" || echo "FAILED: nothing copied (no desktop session here?)"
elif command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard < "$VALUES" && echo "copied to the clipboard" || echo "FAILED: nothing copied (no desktop session here?)"
else
  echo "No clipboard program here: open $VALUES in an editor on the machine with the browser, and copy everything"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$VALUES = "$HARBOR_DIR\harbor-data-values.yml"
$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
if ($LASTEXITCODE -ne 0 -or -not $SUP) {
  "FAILED: cannot read the Supervisor (see the error above)"
} elseif (-not $REC) {
  "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
} elseif ($REC -cne $SUP) {
  "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
} elseif (-not (Test-Path $VALUES)) {
  "Nothing copied: $VALUES is missing (step 4)"
} else {
  try { Set-Clipboard -Value ([IO.File]::ReadAllText($VALUES)) -ErrorAction Stop; "copied to the clipboard" } catch { "FAILED: nothing copied (no desktop session here?)" }
}
```

</details>

**Expect:** `copied to the clipboard`.

**If not:**
- `FAILED: …` under `Unauthorized`: run [Renew the Supervisor login](SUPERVISOR-LOGIN.md#renew-the-supervisor-login).
  `FAILED: … has no supervisor-uid …`: run step 1 first. `FAILED: … belongs to another
  Supervisor (…)`: see step 1's **If not**. Nothing was copied.
- `No clipboard program here: …`: on a Debian or Ubuntu desktop install one (`sudo apt-get
  install -y wl-clipboard`, or `xclip` on X11) and run the block again; on AlmaLinux, which ships
  neither, open the file in an editor as below.
- `FAILED: nothing copied …`, or a terminal on another machine than the browser (over `ssh`):
  open the file in an editor on the browser's machine instead; do not send it through chat or
  mail. Keep the editor open until you have pasted (on Linux the copy is lost when it closes).

### Install it

1. On the **Harbor** card click **ACTIONS**, then **Manage Service**.

   ![The Harbor card with its ACTIONS menu open: Manage Service, Add New Version, Manage Versions, Edit, Delete](img/harbor/04-service-actions.png)

2. **Configure:** leave **Install Version** at `2.15.2+vmware.1-vks.1`, select your Supervisor,
   click **NEXT**.

   ![The Manage: Harbor window, Configure step, with the Supervisor selected](img/harbor/05-install-configure.png)

3. **Validate:** wait for *Validation completed successfully*, with **Compatibility Check** and
   **Signature Verification** both **Pass**. Click **NEXT**.

   ![The Validate step: Compatibility Check Pass and Signature Verification Pass](img/harbor/06-install-validate.png)

4. **Review:** click into the **YAML Service Config** box and paste. Check the `hostname:` line
   near the top against your Harbor name. Click **FINISH**.

   ![The Review step: the YAML Service Config box shows the top of the configuration, with the hostname line](img/harbor/07-install-review.png)

5. Open the **Supervisors** tab, and in your Supervisor's row click **View** in the **Services**
   column. Wait until the **Harbor** row shows **Configured**: a few minutes. The refresh arrow
   at the top reloads the list.

**Expect:** **Harbor**, **Configured**, `2.15.2+vmware.1-vks.1`, **Trusted**. Step 7 waits until
Harbor answers.

![The Supervisor's installed services, with Harbor Configured](img/harbor/08-installed.png)

**If not:**
- A failed check in **Validate**: the message beside it says why.
- An error that says the namespace *is in terminating status*: a Harbor uninstalled a moment
  ago is still being removed. Wait some minutes and install again.
- **Configuring** for more than 30 minutes, or an error naming an image: the Supervisor cannot
  reach `projects.packages.broadcom.com`. An error naming `depot.kube-system.svc`: you
  registered the manifest without **legacy** (step 2).

### Empty the clipboard

Run this right after *Install it*, whether the install worked or not: the clipboard still holds
Harbor's passwords. It empties the clipboard of this machine and changes nothing else. You get
`clipboard emptied` once the passwords are gone from it.

**Linux, macOS, WSL (bash or zsh):**

```sh
if command -v pbcopy >/dev/null 2>&1; then
  pbcopy < /dev/null && echo "clipboard emptied" || echo "FAILED: clipboard not emptied"
elif command -v wl-copy >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  wl-copy --clear && echo "clipboard emptied" || echo "FAILED: clipboard not emptied"
elif command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard < /dev/null && echo "clipboard emptied" || echo "FAILED: clipboard not emptied"
else
  echo "No clipboard program here: copy any other text on the machine with the browser"
fi
```

**Windows (PowerShell):**

```powershell
try { Set-Clipboard -Value ' ' -ErrorAction Stop; "clipboard emptied" } catch { "FAILED: clipboard not emptied" }
```

**Expect:** `clipboard emptied`.

**If not:** `FAILED: …` or `No clipboard program here`: copy any other text on the machine with the
browser.

## 7. Find Harbor's address and get a DNS record

### Find the address and wait for Harbor

Harbor gets its own IP address on your network. The vSphere Client shows it: **Supervisor
Management** → **Namespaces** → the `svc-harbor-…` namespace → **Network** → **Services**, in the
**External IPs** column of `harbor-nginx`.

![The svc-harbor namespace's Network tab, Services: harbor-nginx is the only LoadBalancer, with its address under External IPs](img/harbor/11-nginx-external-ip.png)

Run this once step 6 shows **Configured**, before you ask for a DNS record (none is needed yet).
It finds the same address on the Supervisor and waits until Harbor answers on it (it tries every
15 seconds, for up to 20 minutes); it changes nothing. You get Harbor's namespace on the
Supervisor (`svc-harbor-…`), its address, and the DNS record to ask for in the next step.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif [ -z "$HARBOR_FQDN" ]; then
  echo "FAILED: no hostname in $HARBOR_DIR/harbor-data-values.yml (step 4)"
elif ! NS="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o jsonpath='{.items[*].metadata.name}')"; then
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
elif [ -z "$NS" ] || [ "$NS" != "${NS#* }" ]; then
  echo "FAILED: Harbor namespaces on this Supervisor: '${NS}' (expected exactly one)"
else
  IP=""; H=000; n=0
  until [ "$H" = 200 ] || [ "$n" -ge 80 ]; do
    [ "$n" -eq 0 ] || sleep 15
    n=$((n + 1))
    IP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get service harbor-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
    [ -z "$IP" ] || H="$(curl -sk --connect-timeout 10 --max-time 20 --resolve "${HARBOR_FQDN}:443:${IP}" -o /dev/null -w '%{http_code}' "https://${HARBOR_FQDN}/api/v2.0/health")"
  done
  echo "Harbor namespace: $NS"
  echo "Harbor address:   ${IP:-none yet}"
  echo "Harbor answers:   http=$H"
  echo "DNS record to ask for:  $HARBOR_FQDN  A  ${IP:-<no address yet>}"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
$VALUES = "$HARBOR_DIR\harbor-data-values.yml"
$HARBOR_FQDN = if (Test-Path $VALUES) { "$((Get-Content $VALUES | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')" } else { '' }
if (-not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } elseif (-not $REC) { "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first" } elseif ($REC -cne $SUP) { "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT" } elseif (-not $HARBOR_FQDN) { "FAILED: no hostname in $VALUES (step 4)" } else {
  $NS = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name
  if ($LASTEXITCODE -ne 0) { "FAILED: cannot list the Supervisor's namespaces (see the error above)" } elseif (@($NS).Count -ne 1) { "FAILED: Harbor namespaces on this Supervisor: '$($NS -join ' ')' (expected exactly one)" } else {
    $NS = $NS -replace '^namespace/', ''
    $IP = ''; $H = '000'; $n = 0
    while ($H -ne '200' -and $n -lt 80) {
      if ($n -gt 0) { Start-Sleep -Seconds 15 }
      $n++
      $IP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS get service harbor-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
      if ($IP) { $H = if ((curl.exe -sk --connect-timeout 10 --max-time 20 --resolve "${HARBOR_FQDN}:443:$IP" -o NUL -D - --suppress-connect-headers "https://$HARBOR_FQDN/api/v2.0/health" | Out-String) -match '(?s).*HTTP/\S+ (\d{3})') { $Matches[1] } else { '000' } }
    }
    "Harbor namespace: $NS"
    "Harbor address:   $(if ($IP) { $IP } else { 'none yet' })"
    "Harbor answers:   http=$H"
    "DNS record to ask for:  $HARBOR_FQDN  A  $(if ($IP) { $IP } else { '<no address yet>' })"
  }
}
```

</details>

**Expect:** a namespace such as `svc-harbor-…`, an IP address, `http=200`, and the DNS record to
ask for. The block may take 20 minutes before it gives up; Ctrl+C stops it.

**If not:**
- `FAILED: … has no supervisor-uid …`: run step 1 first. `FAILED: … belongs to another
  Supervisor (…)`: see step 1's **If not**.
- `FAILED: Harbor namespaces …: ''`: the service is not installed (step 6).
- `Harbor address:   none yet`: the Supervisor has no free load-balancer address, or Harbor's
  pods (Harbor's running containers) never started.
- An address but `http=000` or `http=503`: Harbor's pods are not all running. To see which, run
  the block below: it lists Harbor's pods and its five volumes (disks) in Harbor's namespace on the
  Supervisor, and changes nothing. A volume that stays `Pending` means a wrong storage class or no
  room on its storage: uninstall (step 14), fix it in step 4, install again (this updates every
  VKS node twice).

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"

if ! NS="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o jsonpath='{.items[*].metadata.name}')"; then
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
elif [ -z "$NS" ] || [ "$NS" != "${NS#* }" ]; then
  echo "FAILED: Harbor namespaces on this Supervisor: '${NS}' (expected exactly one)"
else
  kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get pods,persistentvolumeclaims
fi
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"

$global:LASTEXITCODE = $null
$NS = @(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name)
if ($LASTEXITCODE -ne 0) { "FAILED: cannot list the Supervisor's namespaces (see the error above)" } elseif ($NS.Count -ne 1) { "FAILED: Harbor namespaces on this Supervisor: '$($NS -join ' ')' (expected exactly one)" } else { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n ($NS[0] -replace '^namespace/', '') get pods,persistentvolumeclaims }
```

**Expect:** every pod `Running` or `Completed`, and five volumes `Bound`.

**If not:**
- `FAILED: cannot list …` under `Unauthorized`: run [Renew the Supervisor
  login](SUPERVISOR-LOGIN.md#renew-the-supervisor-login), then the block again.
- `FAILED: Harbor namespaces …: ''`: the service is not installed (step 6); two names: see *Fix
  common problems*.
- A volume that stays `Pending`: as in the list above the block.
- Pods that are not `Running` (for example `PodVMAnnotationsMissing`, `ErrImageRefsMissing`,
  `ProviderFailed`, `NotFound`) whose name differs from a `Running` pod's only in its last five
  characters: leftovers from an earlier restart, not the cause. Harbor is fine when *Find the
  address and wait for Harbor* gives `http=200` and `kubectl --kubeconfig <the Supervisor
  kubeconfig> -n <the namespace> get deployments,statefulsets` shows, on every line, the two numbers
  under `READY` equal. A pod that is not `Running` and differs from the `Running` pod of the same
  deployment in more than its last five characters is not a leftover: `kubectl --kubeconfig <the
  Supervisor kubeconfig> -n <the namespace> describe pod <its name>` shows why it did not start.

### Get a DNS record

Ask whoever runs your DNS for the **A record** the block printed, in a zone your machine and the
VKS cluster nodes both use (a `hosts` file line does not reach the nodes).

### Check the DNS record

Run this once the DNS record exists, before you use Harbor's name. It checks that, from this
machine, Harbor's name leads to the address Harbor has on the Supervisor, and changes nothing. You
get `DNS is right` with the name and the address. Step 11 checks that the VKS cluster nodes reach
Harbor by this name.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif ! NS="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o jsonpath='{.items[*].metadata.name}')"; then
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
elif [ -z "$NS" ] || [ "$NS" != "${NS#* }" ]; then
  echo "FAILED: Harbor namespaces on this Supervisor: '${NS}' (expected exactly one)"
else
  IP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get service harbor-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  GOT="$(curl -sk --connect-timeout 10 --max-time 20 -o /dev/null -w '%{remote_ip}' "https://${HARBOR_FQDN}/api/v2.0/health")"
  if [ -n "$HARBOR_FQDN" ] && [ -n "$IP" ] && [ "$GOT" = "$IP" ]; then
    echo "DNS is right: $HARBOR_FQDN is $IP"
  else
    echo "DNS is NOT right: '${HARBOR_FQDN}' leads to '${GOT:-nothing}', Harbor is at '${IP:-unknown}'"
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
$NS = @(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name)
if (-not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } elseif (-not $REC) { "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first" } elseif ($REC -cne $SUP) { "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT" } elseif ($LASTEXITCODE -ne 0) { "FAILED: cannot list the Supervisor's namespaces (see the error above)" } elseif ($NS.Count -ne 1) { "FAILED: Harbor namespaces on this Supervisor: '$($NS -join ' ')' (expected exactly one)" } else {
  $NS = $NS[0] -replace '^namespace/', ''
  $IP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS get service harbor-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  $GOT = curl.exe -sk --connect-timeout 10 --max-time 20 -o NUL -w '%{remote_ip}' "https://$HARBOR_FQDN/api/v2.0/health"
  if ($HARBOR_FQDN -and $IP -and $GOT -eq $IP) {
    "DNS is right: $HARBOR_FQDN is $IP"
  } else {
    "DNS is NOT right: '$HARBOR_FQDN' leads to '$GOT', Harbor is at '$IP'"
  }
}
```

</details>

**Expect:** `DNS is right: <your Harbor name> is <the address>`.

**If not:** `leads to 'nothing'` (PowerShell: `''`): the name does not resolve yet; a new record
can take some minutes. Another address: the record is wrong or old, or a company proxy is in the
way. `Harbor is at 'unknown'`: Harbor has no load-balancer address (see *Find the address and wait
for Harbor* above).
`FAILED: cannot list …` under `Unauthorized`: renew the Supervisor login. `FAILED: Harbor
namespaces …: ''`: Harbor is not installed; two names: see *Fix common problems*.
`FAILED: … has no supervisor-uid …`: run step 1 first. `FAILED: … belongs to another Supervisor
(…)`: see step 1's **If not**.

## 8. Check that the VKS cluster nodes were updated

Your VKS cluster nodes can pull images from Harbor only after VKS has updated them to trust Harbor.
Run this after the install, for each vSphere Namespace you recorded in step 6, until all its
machines are updated. It lists the machines (nodes) in that vSphere Namespace and counts how many
were updated since step 6's record; it changes nothing. Set `VSPHERE_NAMESPACE` to that vSphere
Namespace's name. You get the list of machines, then `machines updated: <n> of <n>`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VSPHERE_NAMESPACE="my-namespace"
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

BEFORE="$HARBOR_DIR/machines-$VSPHERE_NAMESPACE.before"
REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif [ ! -s "$BEFORE" ]; then
  echo "FAILED: no record $BEFORE (Record the VKS cluster machines, step 6)"
elif ! kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace "$VSPHERE_NAMESPACE" >/dev/null; then
  echo "FAILED: cannot read the namespace $VSPHERE_NAMESPACE (see the error above)"
elif ! M="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VSPHERE_NAMESPACE" get machines.cluster.x-k8s.io -o jsonpath="{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=='UpToDate')].status} {.status.conditions[?(@.type=='UpToDate')].lastTransitionTime}{'\n'}{end}")"; then
  echo "FAILED: cannot list the machines in $VSPHERE_NAMESPACE (see the error above)"
else
  kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VSPHERE_NAMESPACE" get machines.cluster.x-k8s.io
  echo "machines updated: $(printf '%s\n' "$M" | grep -v -x -F -f "$BEFORE" | grep -c ' True ') of $(printf '%s\n' "$M" | grep -c .)"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VSPHERE_NAMESPACE = "my-namespace"
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
$BEFORE = "$HARBOR_DIR\machines-$VSPHERE_NAMESPACE.before"
if (-not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } elseif (-not $REC) { "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first" } elseif ($REC -cne $SUP) { "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT" } elseif (-not (Test-Path $BEFORE)) { "FAILED: no record $BEFORE (Record the VKS cluster machines, step 6)" } else {
  kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace $VSPHERE_NAMESPACE | Out-Null
  if ($LASTEXITCODE -ne 0) { "FAILED: cannot read the namespace $VSPHERE_NAMESPACE (see the error above)" } else {
    $M = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VSPHERE_NAMESPACE get machines.cluster.x-k8s.io -o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type==''UpToDate'')].status} {.status.conditions[?(@.type==''UpToDate'')].lastTransitionTime}{''\n''}{end}'
    if ($LASTEXITCODE -ne 0) { "FAILED: cannot list the machines in $VSPHERE_NAMESPACE (see the error above)" } else {
      kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VSPHERE_NAMESPACE get machines.cluster.x-k8s.io
      $OLD = @(Get-Content $BEFORE | Where-Object { $_ })
      $NOW = @($M | Where-Object { $_ })
      "machines updated: $(@($NOW | Where-Object { ($OLD -cnotcontains $_) -and ($_ -cmatch ' True ') }).Count) of $($NOW.Count)"
    }
  }
}
```

</details>

**Expect:** the first number climbs while the nodes are updated; the second moves too, while new
nodes come up and old ones go. At the end: `machines updated: <n> of <n>` with as many machines
as you recorded, each `Running` with `READY` and `UP-TO-DATE` `True`. The total can differ from
the record if the Cluster Autoscaler add-on (it adds and removes nodes by load) added or removed
a node.

**If not:**
- `FAILED: … has no supervisor-uid …`: run step 1 first. `FAILED: … belongs to another
  Supervisor (…)`: see step 1's **If not**.
- The first number stays below the second for more than 30 minutes after Harbor answers (step
  7): those nodes may not trust Harbor's CA. Step 11 shows whether they can pull.
- A machine stays `Provisioning` or `Deleting`: the namespace has no room for one more node
  (**Capacity and Usage**, [NAMESPACE.md](NAMESPACE.md#7-set-a-storage-limit-optional-and-check-the-status)).

## 9. Save Harbor's CA and log in

### Save the CA

Harbor proves who it is with a certificate. Harbor signs that certificate itself, with its own
certificate authority (CA), which no machine trusts yet. `curl`, podman, docker and browsers need
the CA's file to trust Harbor; the next blocks use it, and IMAGE.md copies it (step 1). Run this
once DNS is right (step 7), and again after step 12 or 13.

This block:

- reads the CA from the Supervisor, where Harbor keeps it in a Secret (a stored object that also
  holds Harbor's private key, which the block does not print or keep);
- checks that Harbor, at its DNS name, answers with a certificate this CA signed;
- only then saves the CA as `harbor-ca.crt` in this guide's folder on this machine, replacing an
  earlier one; it changes nothing on the Supervisor.

You get the CA's name and fingerprint, which everyone who uses this Harbor can compare. It needs a
user who may read Secrets in Harbor's namespace on the Supervisor.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
CA="$HARBOR_DIR/harbor-ca.crt"
REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif [ -z "$HARBOR_FQDN" ]; then
  echo "FAILED: no hostname in $HARBOR_DIR/harbor-data-values.yml (step 4)"
elif ! NS="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o jsonpath='{.items[*].metadata.name}')"; then
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
elif [ -z "$NS" ] || [ "$NS" != "${NS#* }" ]; then
  echo "FAILED: Harbor namespaces on this Supervisor: '${NS}' (expected exactly one)"
elif ! S="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get secret -l managed-by=vmware-vRegistry -o name)"; then
  echo "FAILED: no CA certificate read (see the error above)"
elif [ "$(printf '%s\n' "$S" | grep -c .)" != 1 ]; then
  echo "FAILED: expected one Secret labeled managed-by=vmware-vRegistry in $NS, found: ${S:-none}"
elif ! kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get "$S" -o go-template='{{with index .data "ca.crt"}}{{base64decode .}}{{end}}' > "$CA.new" \
     || ! openssl x509 -in "$CA.new" -noout -subject -fingerprint -sha256; then
  rm -f "$CA.new"
  echo "FAILED: no CA certificate read (see the error above)"
else
  H="$(curl -s --cacert "$CA.new" --connect-timeout 20 --max-time 30 -o /dev/null -w '%{http_code}' "https://${HARBOR_FQDN}")"
  echo "Harbor at https://$HARBOR_FQDN with this CA: http=$H"
  if [ "$H" = 200 ]; then mv "$CA.new" "$CA" && echo "kept $CA"; else rm -f "$CA.new"; fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
$CA = "$HARBOR_DIR\harbor-ca.crt"
$NS = @(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name)
if (-not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } elseif (-not $REC) { "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first" } elseif ($REC -cne $SUP) { "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT" } elseif (-not $HARBOR_FQDN) { "FAILED: no hostname in $HARBOR_DIR\harbor-data-values.yml (step 4)" } elseif ($LASTEXITCODE -ne 0) { "FAILED: cannot list the Supervisor's namespaces (see the error above)" } elseif ($NS.Count -ne 1) { "FAILED: Harbor namespaces on this Supervisor: '$($NS -join ' ')' (expected exactly one)" } else {
  $NS = $NS[0] -replace '^namespace/', ''
  $S = @(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS get secret -l managed-by=vmware-vRegistry -o name)
  if ($LASTEXITCODE -ne 0) { "FAILED: no CA certificate read (see the error above)" } elseif ($S.Count -ne 1) { "FAILED: expected one Secret labeled managed-by=vmware-vRegistry in $NS, found: $(if ($S.Count) { $S -join ' ' } else { 'none' })" } else {
    $B64 = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS get $S[0] -o jsonpath='{.data.ca\.crt}'
    try {
      $PEM = [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String("$B64"))
      Set-Content -Encoding ascii -Path "$CA.new" -Value $PEM
      $X = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 "$CA.new"
      $F = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($X.RawData))
      "subject=$($X.Subject)"
      "sha256 Fingerprint=$($F.Replace('-', ':'))"
      $H = if ((curl.exe -s --ssl-no-revoke --cacert "$CA.new" --connect-timeout 20 --max-time 30 -o NUL -D - --suppress-connect-headers "https://$HARBOR_FQDN" | Out-String) -match '(?s).*HTTP/\S+ (\d{3})') { $Matches[1] } else { '000' }
      "Harbor at https://$HARBOR_FQDN with this CA: http=$H"
      if ($H -eq '200') { Move-Item -Force "$CA.new" $CA; "kept $CA" } else { Remove-Item -Force "$CA.new" }
    } catch {
      Remove-Item -Force -ErrorAction SilentlyContinue "$CA.new"
      "FAILED: no CA certificate read (see the error above)"
    }
  }
}
```

</details>

**Expect:** a `subject=` line naming Harbor's CA, `sha256 Fingerprint=…` (`SHA256 Fingerprint=`
on macOS), `Harbor at https://<your Harbor name> with this CA: http=200`, then `kept …`.

**If not:**
- `FAILED: … has no supervisor-uid …`: run step 1 first. `FAILED: … belongs to another
  Supervisor (…)`: see step 1's **If not**.
- `FAILED: no CA certificate read`, under `Forbidden`: your user may not read Secrets in Harbor's
  namespace; a vCenter administrator must run this block. Under `Could not find certificate`
  (PowerShell: no error above it): the Secret has no `ca.crt`, and VKS clusters cannot trust
  Harbor either
  ([Broadcom KB 441275](https://knowledge.broadcom.com/external/article/441275/error-failed-to-call-extension-handler-g.html)).
- `found: none`: Harbor is still being installed (step 6) or reconfigured (**FINISH** a moment
  ago: run it again in a minute), or `tlsSecretLabels` was changed in
  `harbor-data-values.yml`. Two or more names: stop; this guide cannot tell which is Harbor's.
- `http=000`: the name does not resolve or answer (step 7, *Check the DNS record*), or Harbor
  answered with a certificate this CA did not sign: the name leads to another server. The `curl`
  error is not shown; nothing was kept.

### Log in as admin

Run this after *Save the CA*, to make sure the admin password works before the next blocks use it.
It logs in to Harbor's API (the way programs such as `curl` talk to Harbor, at the same address as
its web page) as `admin` with the password from `secrets.env`, using `harbor-ca.crt` to trust
Harbor, and asks who you are; nothing changes in Harbor. You get your user name and whether it is an
administrator. The next blocks log in the same way to create a project and a robot account.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
if [ -z "$HARBOR_FQDN" ] || [ ! -s "$HARBOR_DIR/harbor-ca.crt" ] || [ ! -r "$HARBOR_DIR/secrets.env" ]; then
  echo "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
else
  CFG="$(mktemp)"
  ( . "$HARBOR_DIR/secrets.env"
    P="$(printf '%s' "$HARBOR_ADMIN_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf 'user = "admin:%s"\n' "$P" > "$CFG" )
  curl -sS --cacert "$HARBOR_DIR/harbor-ca.crt" --connect-timeout 20 --max-time 30 -K "$CFG" "https://${HARBOR_FQDN}/api/v2.0/users/current" \
    | jq -r 'if .username then "logged in as \(.username), administrator: \(.sysadmin_flag)" else "ERROR \(.errors[0].code): \(.errors[0].message)" end'
  rm -f "$CFG"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
$S = @{}
foreach ($l in Get-Content "$HARBOR_DIR\secrets.env" -ErrorAction SilentlyContinue) { if ($l -cmatch "^(HARBOR_[A-Z_]+)='(.*)'$") { $S[$Matches[1]] = $Matches[2] } }
if (-not $HARBOR_FQDN -or -not (Test-Path "$HARBOR_DIR\harbor-ca.crt") -or -not $S['HARBOR_ADMIN_PASSWORD']) {
  "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
} else {
  $P = $S['HARBOR_ADMIN_PASSWORD'].Replace('\', '\\').Replace('"', '\"')
  $CFG = [IO.Path]::GetTempFileName()
  try {
    Set-Content -Encoding ascii -Path $CFG -Value "user = `"admin:$P`""
    $R = curl.exe -sS --ssl-no-revoke --cacert "$HARBOR_DIR\harbor-ca.crt" --connect-timeout 20 --max-time 30 -K $CFG "https://$HARBOR_FQDN/api/v2.0/users/current" | Out-String | ConvertFrom-Json
    if ($R.username) { "logged in as $($R.username), administrator: $($R.sysadmin_flag)" } else { "ERROR $($R.errors[0].code): $($R.errors[0].message)" }
  } finally {
    Remove-Item -Force $CFG
  }
}
```

</details>

**Expect:** `logged in as admin, administrator: true` (PowerShell: `True`).

**If not:**
- `FAILED: … is missing`: run the step that writes it (4, 9, or 3 then 4; `secrets.env` comes from step 4 if you skipped step 3).
- `ERROR UNAUTHORIZED`: this Harbor was installed with another admin password than the one in
  `secrets.env`, or someone changed it in Harbor since.
- A `curl:` error that the name does not match (`no alternative certificate subject name
  matches`; PowerShell: `failed to match connection hostname`): the name leads to another
  server (step 7, *Check the DNS record*), or Harbor's hostname is no longer the one in
  `harbor-data-values.yml`.
- Any other `curl:` certificate error: run step 7's *Check the DNS record* first; a name that
  leads to another server can also give this (PowerShell: `UNTRUSTED_ROOT`). If DNS is right,
  `harbor-ca.crt` is not this Harbor's; run *Save the CA* again.

### Log in with a browser (optional)

Harbor's web page is `https://<your Harbor name>`. The browser warns about Harbor's certificate
until Harbor's CA (`harbor-ca.crt` in `~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT>`, saved
in *Save the CA*) is in its trust store:
- Linux: Firefox: **Settings** → **Privacy & Security** → **View Certificates** → **Authorities**
  → **Import**, tick **Trust this CA to identify websites**. Chrome: **Settings** → **Privacy and
  security** → **Security** → **Manage certificates**, import it as a trusted certificate.
- macOS: Safari and Chrome refuse the page even then: the certificate is valid for ten years, and
  macOS accepts at most 825 days from a private CA. Use your organization's certificate (step 13).
- Windows: double-click `harbor-ca.crt` → **Install Certificate** → **Current User** → **Place all
  certificates in the following store** → **Trusted Root Certification Authorities** → **Finish**
  → **Yes**. Chrome and Edge use it after a restart.

Run this when you want to log in to Harbor's web page as `admin`. It prints the admin password
from `secrets.env` **on your screen**, and changes nothing: run it only when nobody can see the
screen, then clear the terminal. You get the password to type on Harbor's login page, with the
user name `admin`.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

( . "$HARBOR_DIR/secrets.env" && printf '%s\n' "$HARBOR_ADMIN_PASSWORD" )
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

(Get-Content "$HARBOR_DIR\secrets.env" | Where-Object { $_ -cmatch "^HARBOR_ADMIN_PASSWORD='" }) -creplace "^HARBOR_ADMIN_PASSWORD='(.*)'$", '$1'
```

**Expect:** the password, on a line of its own. After logging in, **Projects** lists `library`
and your projects.

**If not:** the page does not open: run step 7's *Check the DNS record*. `Invalid user name or
password`: see *Log in as admin* above.

## 10. Create a project and a robot account

### Create the project

In Harbor, images live in projects: folders, each with its own access rules. Run this
after *Log in as admin*, once for each project you want. It creates a project for your images in
Harbor (nothing changes on the Supervisor or in vCenter). Set:

- `HARBOR_PROJECT`: its name, in lower-case letters, digits and `-`;
- `HARBOR_PROJECT_PUBLIC`: `"false"` for a **private** project, where only logged-in users can
  pull, so a VKS cluster needs a stored login (a pull secret); `"true"` for a **public** one, where
  anyone who reaches Harbor can pull. Pushing always needs a login.

You get the project's name and whether it is public; running it again with the same name leaves the
project as it is. To click instead, use **In Harbor's web page** after this block's **If not:**.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
HARBOR_PROJECT="my-project"
HARBOR_PROJECT_PUBLIC="false"
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
if ! command -v jq >/dev/null 2>&1; then
  echo "MISSING: jq (PREREQS.md)"
elif [ -z "$HARBOR_FQDN" ] || [ ! -s "$HARBOR_DIR/harbor-ca.crt" ] || [ ! -r "$HARBOR_DIR/secrets.env" ]; then
  echo "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
elif [ "$HARBOR_PROJECT_PUBLIC" != "true" ] && [ "$HARBOR_PROJECT_PUBLIC" != "false" ]; then
  echo "FAILED: HARBOR_PROJECT_PUBLIC must be true or false"
else
  CFG="$(mktemp)"
  ( . "$HARBOR_DIR/secrets.env"
    P="$(printf '%s' "$HARBOR_ADMIN_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf 'user = "admin:%s"\n' "$P" > "$CFG" )
  jq -nc --arg p "$HARBOR_PROJECT" --arg pub "$HARBOR_PROJECT_PUBLIC" '{project_name: $p, metadata: {public: $pub}}' \
    | curl -sS --cacert "$HARBOR_DIR/harbor-ca.crt" --connect-timeout 20 --max-time 30 -K "$CFG" \
        -X POST -H 'Content-Type: application/json' --data-binary @- \
        -o /dev/null -w 'create project: http=%{http_code}\n' "https://${HARBOR_FQDN}/api/v2.0/projects"
  curl -sS --cacert "$HARBOR_DIR/harbor-ca.crt" --connect-timeout 20 --max-time 30 -K "$CFG" -H 'X-Is-Resource-Name: true' \
      "https://${HARBOR_FQDN}/api/v2.0/projects/${HARBOR_PROJECT}" \
    | jq -r 'if .name then "project \(.name), public: \(.metadata.public)" else "ERROR \(.errors[0].code): \(.errors[0].message)" end'
  rm -f "$CFG"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$HARBOR_PROJECT = "my-project"
$HARBOR_PROJECT_PUBLIC = "false"
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
$S = @{}
foreach ($l in Get-Content "$HARBOR_DIR\secrets.env" -ErrorAction SilentlyContinue) { if ($l -cmatch "^(HARBOR_[A-Z_]+)='(.*)'$") { $S[$Matches[1]] = $Matches[2] } }
if (-not $HARBOR_FQDN -or -not (Test-Path "$HARBOR_DIR\harbor-ca.crt") -or -not $S['HARBOR_ADMIN_PASSWORD']) {
  "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
} elseif ($HARBOR_PROJECT -cnotmatch '^[a-z0-9][a-z0-9._-]*$') {
  "FAILED: HARBOR_PROJECT may hold only lower-case letters, digits, '.', '_' and '-'"
} elseif ($HARBOR_PROJECT_PUBLIC -cnotmatch '^(true|false)$') {
  "FAILED: HARBOR_PROJECT_PUBLIC must be true or false"
} else {
  $P = $S['HARBOR_ADMIN_PASSWORD'].Replace('\', '\\').Replace('"', '\"')
  $CFG = [IO.Path]::GetTempFileName(); $BODY = [IO.Path]::GetTempFileName()
  try {
    Set-Content -Encoding ascii -Path $CFG -Value "user = `"admin:$P`""
    Set-Content -Encoding ascii -Path $BODY -Value ('{"project_name":"' + $HARBOR_PROJECT + '","metadata":{"public":"' + $HARBOR_PROJECT_PUBLIC + '"}}')
    $H = if ((curl.exe -sS --ssl-no-revoke --cacert "$HARBOR_DIR\harbor-ca.crt" --connect-timeout 20 --max-time 30 -K $CFG `
      -X POST -H 'Content-Type: application/json' --data-binary "@$BODY" `
      -o NUL -D - --suppress-connect-headers "https://$HARBOR_FQDN/api/v2.0/projects" | Out-String) -match '(?s).*HTTP/\S+ (\d{3})') { $Matches[1] } else { '000' }
    "create project: http=$H"
    $R = curl.exe -sS --ssl-no-revoke --cacert "$HARBOR_DIR\harbor-ca.crt" --connect-timeout 20 --max-time 30 -K $CFG -H 'X-Is-Resource-Name: true' `
      "https://$HARBOR_FQDN/api/v2.0/projects/$HARBOR_PROJECT" | Out-String | ConvertFrom-Json
    if ($R.name) { "project $($R.name), public: $($R.metadata.public)" } else { "ERROR $($R.errors[0].code): $($R.errors[0].message)" }
  } finally {
    Remove-Item -Force $CFG, $BODY
  }
}
```

</details>

**Expect:** `create project: http=201`, or `http=409` when the project already exists (it is left
as it is), then `project my-project, public: false` (`true` for a public project).

**If not:** `http=401`: see *Log in as admin*. `http=400`: Harbor refused the name; use lower-case
letters and digits.

**In Harbor's web page** the same is **Projects** → **NEW PROJECT**, with **Public** ticked or not
under **Access Level**, then **OK**.

![Harbor's New Project window with the name my-project and Public ticked](img/harbor/12-new-project-public.png)

### Create a robot account

A robot account is a login for tools rather than people. Run this after *Create the project*, to
get a login that you use instead of `admin` to push images, and for a VKS cluster's pull secret.
It creates, in Harbor, a robot named `push` that may push to and pull from this project only, for
90 days. Set `HARBOR_PROJECT` to the project's name. You get the robot's name and secret; Harbor
shows the secret only once. Running it again for the same project fails with `ERROR CONFLICT`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
HARBOR_PROJECT="my-project"
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
if ! command -v jq >/dev/null 2>&1; then
  echo "MISSING: jq (PREREQS.md)"
elif [ -z "$HARBOR_FQDN" ] || [ ! -s "$HARBOR_DIR/harbor-ca.crt" ] || [ ! -r "$HARBOR_DIR/secrets.env" ]; then
  echo "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
else
  CFG="$(mktemp)"
  ( . "$HARBOR_DIR/secrets.env"
    P="$(printf '%s' "$HARBOR_ADMIN_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf 'user = "admin:%s"\n' "$P" > "$CFG" )
  jq -nc --arg p "$HARBOR_PROJECT" '{name: "push", duration: 90, level: "project",
      permissions: [{kind: "project", namespace: $p,
        access: [{resource: "repository", action: "push"}, {resource: "repository", action: "pull"},
                 {resource: "artifact", action: "read"}, {resource: "artifact", action: "list"}]}]}' \
    | curl -sS --cacert "$HARBOR_DIR/harbor-ca.crt" --connect-timeout 20 --max-time 30 -K "$CFG" \
        -X POST -H 'Content-Type: application/json' --data-binary @- "https://${HARBOR_FQDN}/api/v2.0/robots" \
    | jq -r 'if .errors then "ERROR \(.errors[0].code): \(.errors[0].message)" else "name:   \(.name)\nsecret: \(.secret)" end'
  rm -f "$CFG"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$HARBOR_PROJECT = "my-project"
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
$S = @{}
foreach ($l in Get-Content "$HARBOR_DIR\secrets.env" -ErrorAction SilentlyContinue) { if ($l -cmatch "^(HARBOR_[A-Z_]+)='(.*)'$") { $S[$Matches[1]] = $Matches[2] } }
if (-not $HARBOR_FQDN -or -not (Test-Path "$HARBOR_DIR\harbor-ca.crt") -or -not $S['HARBOR_ADMIN_PASSWORD']) {
  "FAILED: harbor-data-values.yml, harbor-ca.crt or secrets.env is missing in $HARBOR_DIR"
} elseif ($HARBOR_PROJECT -cnotmatch '^[a-z0-9][a-z0-9._-]*$') {
  "FAILED: HARBOR_PROJECT may hold only lower-case letters, digits, '.', '_' and '-'"
} else {
  $P = $S['HARBOR_ADMIN_PASSWORD'].Replace('\', '\\').Replace('"', '\"')
  $CFG = [IO.Path]::GetTempFileName(); $BODY = [IO.Path]::GetTempFileName()
  try {
    Set-Content -Encoding ascii -Path $CFG -Value "user = `"admin:$P`""
    Set-Content -Encoding ascii -Path $BODY -Value ('{"name":"push","duration":90,"level":"project","permissions":[{"kind":"project","namespace":"' + $HARBOR_PROJECT + '","access":[{"resource":"repository","action":"push"},{"resource":"repository","action":"pull"},{"resource":"artifact","action":"read"},{"resource":"artifact","action":"list"}]}]}')
    $R = curl.exe -sS --ssl-no-revoke --cacert "$HARBOR_DIR\harbor-ca.crt" --connect-timeout 20 --max-time 30 -K $CFG `
      -X POST -H 'Content-Type: application/json' --data-binary "@$BODY" "https://$HARBOR_FQDN/api/v2.0/robots" | Out-String | ConvertFrom-Json
    if ($R.errors) { "ERROR $($R.errors[0].code): $($R.errors[0].message)" } else { "name:   $($R.name)"; "secret: $($R.secret)" }
  } finally {
    Remove-Item -Force $CFG, $BODY
  }
}
```

</details>

**Expect:** `name:   robot$<your project>+push` and `secret: …`. Harbor shows the secret only
once: keep both where you keep passwords. The `$` is part of the name.

**If not:**
- `ERROR CONFLICT`: a robot named `push` exists in this project. Use its secret, or delete it in
  Harbor's web page (**Projects** → your project → **Robot Accounts**) and run the block again.
- `ERROR UNAUTHORIZED`: see *Log in as admin*.

**In Harbor's web page** the same is a robot account that you then give permissions on your
project: **Administration** → **Robot Accounts** → **NEW ROBOT ACCOUNT**.

1. **Basic Information**: a name and how many days it lasts, then **NEXT**.

   ![The first page of Create System Robot Account, with the name my-project-push and 30 days](img/harbor/13-robot-name.png)

2. **Select System Permissions**: tick nothing, then **NEXT**.
3. **Select Project Permissions**: tick your project, open its **PERMISSION(S)** list and tick
   **Repository** → **Pull** and **Push**, and **Artifact** → **List** and **Read** (for a robot
   that only pulls, IMAGE.md step 5: only **Repository** → **Pull**). Click outside the list,
   then **FINISH**.

   ![Select Project Permissions with my-project ticked and its list showing Pull, Push, List and Read ticked](img/harbor/14-robot-project-permissions.png)

4. Harbor shows the robot's secret once: copy it, or **EXPORT TO FILE**, and keep it where you
   keep passwords.

   ![The window that shows the new robot's name and secret](img/harbor/15-robot-secret.png)

Its name is `robot$` and the name you typed (here `robot$my-project-push`), not
`robot$<your project>+push`.

### Log in with podman or docker (optional)

This needs [IMAGE.md step 1](IMAGE.md#1-get-harbors-ca) (copy the CA) and
[step 2](IMAGE.md#2-trust-harbors-ca) (make your engine trust Harbor's CA), from the next group,
[Container images](IMAGES.md): skip it now and come back after them. Run it to check, before you
push images, that podman or docker on this machine can log in to Harbor. The blocks below log in
as `admin` and as the robot account, and log out again, so no login stays saved on this machine.
In each, set `CONTAINER_ENGINE` to `podman` or `docker`.

This one logs in as `admin`, with the password from `secrets.env`. You get `Login Succeeded`, then
a logout line.

**Linux, macOS, WSL (bash or zsh):**

```sh
CONTAINER_ENGINE="podman"
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
if [ -z "$HARBOR_FQDN" ] || [ ! -r "$HARBOR_DIR/secrets.env" ]; then
  echo "FAILED: harbor-data-values.yml or secrets.env is missing in $HARBOR_DIR"
elif ( . "$HARBOR_DIR/secrets.env"; printf '%s\n' "$HARBOR_ADMIN_PASSWORD" ) | "$CONTAINER_ENGINE" login -u admin --password-stdin "$HARBOR_FQDN"; then
  "$CONTAINER_ENGINE" logout "$HARBOR_FQDN"
fi
```

**Windows (PowerShell):**

```powershell
$CONTAINER_ENGINE = "podman"
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
$S = @{}
foreach ($l in Get-Content "$HARBOR_DIR\secrets.env" -ErrorAction SilentlyContinue) { if ($l -cmatch "^(HARBOR_[A-Z_]+)='(.*)'$") { $S[$Matches[1]] = $Matches[2] } }
if (-not $HARBOR_FQDN -or -not $S['HARBOR_ADMIN_PASSWORD']) { "FAILED: harbor-data-values.yml or secrets.env is missing in $HARBOR_DIR" } else {
  $S['HARBOR_ADMIN_PASSWORD'] | & $CONTAINER_ENGINE login -u admin --password-stdin $HARBOR_FQDN
  if ($LASTEXITCODE -eq 0) { & $CONTAINER_ENGINE logout $HARBOR_FQDN }
}
```

To check the robot account, run this line and type the robot's secret at its prompt. The secret is
not shown, and it stays only in this terminal. You get no other output; the next block uses the
secret.

**Linux, macOS, WSL (bash or zsh):**

```sh
printf 'Robot secret: '; IFS= read -rs HARBOR_ROBOT_SECRET; echo
```

**Windows (PowerShell):**

```powershell
$HARBOR_ROBOT_SECRET = Read-Host -AsSecureString 'Robot secret'
```

Run this in the same terminal, right after the line above. It logs in to Harbor as the robot,
which proves its name and secret work. It then logs out, so no login stays saved on this machine,
and forgets the secret you typed. Set `HARBOR_ROBOT` to the robot's name from *Create a robot
account*, and keep it in single quotes: the `$` is part of the name. You get `Login Succeeded`,
then a logout line.

**Linux, macOS, WSL (bash or zsh):**

```sh
CONTAINER_ENGINE="podman"
HARBOR_ROBOT='robot$my-project+push'
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
if [ -z "$HARBOR_FQDN" ] || [ -z "$HARBOR_ROBOT_SECRET" ]; then
  echo "FAILED: no $HARBOR_DIR/harbor-data-values.yml, or no robot secret in this terminal (run the line above)"
elif printf '%s\n' "$HARBOR_ROBOT_SECRET" | "$CONTAINER_ENGINE" login -u "$HARBOR_ROBOT" --password-stdin "$HARBOR_FQDN"; then
  "$CONTAINER_ENGINE" logout "$HARBOR_FQDN"
fi
unset HARBOR_ROBOT_SECRET
```

**Windows (PowerShell):**

```powershell
$CONTAINER_ENGINE = "podman"
$HARBOR_ROBOT = 'robot$my-project+push'
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
if (-not $HARBOR_FQDN -or -not $HARBOR_ROBOT_SECRET -or $HARBOR_ROBOT_SECRET.Length -eq 0) { "FAILED: no $HARBOR_DIR\harbor-data-values.yml, or no robot secret in this terminal (run the line above)" } else {
  $B = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($HARBOR_ROBOT_SECRET)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($B) | & $CONTAINER_ENGINE login -u $HARBOR_ROBOT --password-stdin $HARBOR_FQDN }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($B) }
  if ($LASTEXITCODE -eq 0) { & $CONTAINER_ENGINE logout $HARBOR_FQDN }
}
Remove-Variable -ErrorAction SilentlyContinue HARBOR_ROBOT_SECRET
```

**Expect:** `Login Succeeded` (docker without a credential helper first warns that the login is stored unencrypted),
then `Removed login credentials for <your Harbor name>` (docker:
`Removing login credentials for …`).

**If not:**
- `x509: certificate signed by unknown authority`: do [IMAGE.md step 1](IMAGE.md#1-get-harbors-ca)
  and [step 2](IMAGE.md#2-trust-harbors-ca) for your OS and engine.
- `unauthorized` (podman: `invalid username/password`) as `admin`: see *Log in as admin*. As the
  robot: its name or secret is wrong, or it has expired. A robot made in Harbor's web page is
  `robot$<the name you typed>`.
- `FAILED: harbor-data-values.yml or secrets.env is missing …`: run steps 3 and 4 with the same
  `SUPERVISOR_CONTEXT`.
- `FAILED: no …harbor-data-values.yml, or no robot secret …`: run step 4, or type the secret
  again (the line above the block), then run the block in the same terminal.

To build an image, push it to this project and run it in a VKS cluster, see [IMAGE.md](IMAGE.md).

## 11. Check that a VKS cluster can pull from Harbor

Run this after step 8 shows every node updated, before you run your own images from Harbor, and
again for each VKS cluster. It checks that your VKS cluster's nodes can reach Harbor and trust its
certificate. The block:

- starts a small test pod (a running container) in the cluster's `default` namespace (inside the
  VKS cluster, not a vSphere Namespace), from an image that does not exist in your project;
- reads why the cluster could not get the image, then deletes the pod, so nothing is left behind.

An answer such as *not found*, *unauthorized* or *access denied* is the good result: the nodes
reached Harbor and trusted it. Any other answer names the problem. Set `VKS_CLUSTER` to the VKS
cluster's name and `HARBOR_PROJECT` to your project. The block uses the cluster's kubeconfig (the
file that lets kubectl reach it), `~/.kube/<VKS_CLUSTER>.kubeconfig`, from
[SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
HARBOR_PROJECT="my-project"
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
if [ -z "$HARBOR_FQDN" ] || [ ! -s "$VKS_KUBECONFIG" ]; then
  echo "FAILED: $HARBOR_DIR/harbor-data-values.yml or $VKS_KUBECONFIG is missing"
else
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n default delete pod harbor-pull-check --ignore-not-found >/dev/null
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n default apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: harbor-pull-check
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: check
    image: ${HARBOR_FQDN}/${HARBOR_PROJECT}/pull-check:none
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
EOF
  M=""; n=0
  until [ -n "$M" ] || [ "$n" -ge 18 ]; do
    n=$((n + 1)); sleep 5
    M="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n default get events --field-selector involvedObject.name=harbor-pull-check,reason=Failed -o jsonpath='{.items[*].message}')"
  done
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n default delete pod harbor-pull-check --ignore-not-found >/dev/null
  case "$M" in
    "")               echo "NO ANSWER: the cluster reported no pull attempt in 90 seconds" ;;
    *"no such host"*) echo "DNS: the nodes cannot resolve $HARBOR_FQDN" ;;
    *"certificate is valid for"*|*"not valid for any names"*)
                      echo "NAME: the certificate at $HARBOR_FQDN is not for that name" ;;
    *"unknown authority"*) echo "CA: the nodes do not trust the certificate of $HARBOR_FQDN" ;;
    *x509*)           echo "OTHER: $M" ;;
    *"not found"*|*"access denied"*|*nauthorized*|*insufficient_scope*)
                      echo "OK: the nodes resolve $HARBOR_FQDN and trust its certificate" ;;
    *)                echo "OTHER: $M" ;;
  esac
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$HARBOR_PROJECT = "my-project"
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
if (-not $HARBOR_FQDN -or -not (Test-Path $VKS_KUBECONFIG)) {
  "FAILED: $HARBOR_DIR\harbor-data-values.yml or $VKS_KUBECONFIG is missing"
} else {
  kubectl --kubeconfig $VKS_KUBECONFIG -n default delete pod harbor-pull-check --ignore-not-found | Out-Null
  @"
apiVersion: v1
kind: Pod
metadata:
  name: harbor-pull-check
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: check
    image: $HARBOR_FQDN/$HARBOR_PROJECT/pull-check:none
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
"@ | kubectl --kubeconfig $VKS_KUBECONFIG -n default apply -f -
  $M = ''; $n = 0
  while (-not $M -and $n -lt 18) {
    $n++; Start-Sleep -Seconds 5
    $M = "$(kubectl --kubeconfig $VKS_KUBECONFIG -n default get events --field-selector involvedObject.name=harbor-pull-check,reason=Failed -o jsonpath='{.items[*].message}')"
  }
  kubectl --kubeconfig $VKS_KUBECONFIG -n default delete pod harbor-pull-check --ignore-not-found | Out-Null
  if (-not $M) { "NO ANSWER: the cluster reported no pull attempt in 90 seconds" } elseif ($M -like '*no such host*') { "DNS: the nodes cannot resolve $HARBOR_FQDN" } elseif ($M -like '*certificate is valid for*' -or $M -like '*not valid for any names*') {
    "NAME: the certificate at $HARBOR_FQDN is not for that name"
  } elseif ($M -like '*unknown authority*') { "CA: the nodes do not trust the certificate of $HARBOR_FQDN" } elseif ($M -like '*x509*') { "OTHER: $M" } elseif ($M -like '*not found*' -or $M -like '*access denied*' -or $M -like '*nauthorized*' -or $M -like '*insufficient_scope*') {
    "OK: the nodes resolve $HARBOR_FQDN and trust its certificate"
  } else { "OTHER: $M" }
}
```

</details>

**Expect:** `pod/harbor-pull-check created`, then within a minute
`OK: the nodes resolve <your Harbor name> and trust its certificate`.

**If not:**
- `FAILED: … is missing`: run step 4, or SUPERVISOR-LOGIN.md's
  [Get the VKS cluster's kubeconfig](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig).
- `DNS: …`: the DNS server the nodes use does not have the record (step 7).
- `NAME: …`: the address answers with a certificate for another name: the DNS server the nodes
  use leads to another server (step 7's check uses your machine's DNS, not theirs), or Harbor's
  hostname is no longer the one in `harbor-data-values.yml`.
- `CA: …`: the nodes are still being updated (step 8): run this again when that is over. Or the
  cluster is under another Supervisor, which this guide does not cover.
- `OTHER: …` with `i/o timeout` or `connection refused`: the nodes resolve the name but cannot
  reach the address: a network or firewall matter.
- `OTHER: …` with `certificate has expired`: Harbor's certificate is out of date, or a node's
  clock is wrong.
- `NO ANSWER: …`: run `kubectl --kubeconfig <the VKS kubeconfig> -n default get events` and read
  the last lines.

Harbor is ready. Next: [IMAGE.md](IMAGE.md).

## 12. Change Harbor's hostname (optional)

No VKS node is updated: Harbor keeps its CA. But from the restart at the end of this step,
everything that uses the old name fails: image names, pull secrets, `podman login` and
`docker login`, CI and ArgoCD sources. Do this in a maintenance window, and change
them to the new name.

1. Get a DNS record for the new name with Harbor's address (step 7).
2. Write the new name into `harbor-data-values.yml` with the block below. With your
   organization's certificate (step 13), you need one for the new name: after that block, move
   the old `harbor.key` and `harbor.csr` out of your home folder, run step 13 *Request the
   certificate*, and when the certificate is back, step 13 *Write the certificate into the file*.
   Then, in item 3 below, replace the whole **YAML Service Config** box with the file (copy it with
   step 6 *Copy the configuration*) instead of changing only the `hostname:` line.
3. In the vSphere Client, select the Supervisor, then **Configure** → **Supervisor Services** →
   **Overview**. Select **Harbor**, click **MANAGE**, keep the installed version, click **NEXT**
   twice. In **YAML Service Config**, change only the `hostname:` line to the new name, then click
   **FINISH**. The box shows Harbor's passwords (and your key with step 13): do not share your
   screen. If you pasted the file, then step 6 *Empty the clipboard*.
4. Restart Harbor's web server with the second block below: until then it serves the
   certificate for the old name.
5. Run step 9 (*Save the CA* checks Harbor at the new name; the CA is unchanged) and step 11
   again.

### Write the new name into the file

Run this as item 2 above, once the DNS record for the new name exists. It changes the `hostname:`
line in `harbor-data-values.yml` on this machine to the new name; no other line changes, and
nothing changes on the Supervisor until item 3. Set `HARBOR_NEW_FQDN` to the new name. You get the
new `hostname:` line; the later blocks read Harbor's name from this file. Running it again with the
same name changes nothing.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
HARBOR_NEW_FQDN="harbor2.example.test"
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

VALUES="$HARBOR_DIR/harbor-data-values.yml"
case "$HARBOR_NEW_FQDN" in ""|harbor2.example.test) BAD_NAME=1 ;; *) BAD_NAME="" ;; esac
[ -z "$(printf '%s' "$HARBOR_NEW_FQDN" | LC_ALL=C tr -d 'a-z0-9.-')" ] || BAD_NAME=1
if [ -n "$BAD_NAME" ]; then
  echo "NOT WRITTEN: set HARBOR_NEW_FQDN to Harbor's new DNS name"
elif [ "$(grep -c '^hostname: ' "$VALUES" 2>/dev/null)" != 1 ]; then
  echo "NOT WRITTEN: no single hostname line in $VALUES (step 4)"
elif grep -q -x -F "hostname: $HARBOR_NEW_FQDN" "$VALUES"; then
  echo "NOT CHANGED: $VALUES already has this name"
else
  rm -f "$VALUES.new"
  ( umask 077; sed "s/^hostname: .*/hostname: $HARBOR_NEW_FQDN/" "$VALUES" > "$VALUES.new" )
  N="$(diff "$VALUES" "$VALUES.new" | grep -c '^>')"
  if [ "$N" = 1 ] && grep -q -x -F "hostname: $HARBOR_NEW_FQDN" "$VALUES.new"; then
    mv "$VALUES.new" "$VALUES"
    grep '^hostname: ' "$VALUES"
    echo "lines changed: $N"
  else
    rm -f "$VALUES.new"
    echo "FAILED: the file did not come out as expected and was not changed"
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$HARBOR_NEW_FQDN = "harbor2.example.test"
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$VALUES = "$HARBOR_DIR\harbor-data-values.yml"
$TXT = if (Test-Path $VALUES) { [IO.File]::ReadAllLines($VALUES) } else { @() }
$OLD = @($TXT | Where-Object { $_ -cmatch '^hostname: ' })
if ($HARBOR_NEW_FQDN -cnotmatch '^[a-z0-9.-]+$' -or $HARBOR_NEW_FQDN -eq 'harbor2.example.test') {
  "NOT WRITTEN: set HARBOR_NEW_FQDN to Harbor's new DNS name"
} elseif ($OLD.Count -ne 1) {
  "NOT WRITTEN: no single hostname line in $VALUES (step 4)"
} elseif ($OLD[0] -ceq "hostname: $HARBOR_NEW_FQDN") {
  "NOT CHANGED: $VALUES already has this name"
} else {
  $OUT = foreach ($l in $TXT) { if ($l -cmatch '^hostname: ') { "hostname: $HARBOR_NEW_FQDN" } else { $l } }
  [IO.File]::WriteAllText("$VALUES.new", (($OUT -join "`n") + "`n"))
  $NEW = [IO.File]::ReadAllLines("$VALUES.new")
  $N = 0
  for ($i = 0; $i -lt $TXT.Count; $i++) { if ($TXT[$i] -cne $NEW[$i]) { $N++ } }
  if ($NEW.Count -eq $TXT.Count -and $N -eq 1) {
    Move-Item -Force "$VALUES.new" $VALUES
    $NEW | Where-Object { $_ -cmatch '^hostname: ' }
    "lines changed: $N"
  } else {
    Remove-Item -Force "$VALUES.new"
    "FAILED: the file did not come out as expected and was not changed"
  }
}
```

</details>

**Expect:** `hostname: <the new name>` and `lines changed: 1`.

**If not:**
- `NOT WRITTEN: …`: set the value it names, or do the step it names, then run the block again.
- `FAILED: …`: the file is laid out differently from what step 4 writes; it was not changed.

### Restart Harbor's web server

Run this as item 4 above, after **FINISH**. It waits until Harbor's certificate is for the new name
(a minute or less), then deletes Harbor's web server pod in Harbor's namespace on the Supervisor;
the pod starts again by itself with that certificate. Pushes and pulls fail while it restarts. You
get `certificate for <the new name>: yes`, then Harbor's web server running again. Then do item 5.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml")"
REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif [ -z "$HARBOR_FQDN" ]; then
  echo "FAILED: no hostname in $HARBOR_DIR/harbor-data-values.yml (step 4)"
elif ! NS="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o jsonpath='{.items[*].metadata.name}')"; then
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
elif [ -z "$NS" ] || [ "$NS" != "${NS#* }" ]; then
  echo "FAILED: Harbor namespaces on this Supervisor: '${NS}' (expected exactly one)"
elif ! S="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get secret -l managed-by=vmware-vRegistry -o name)" \
     || [ "$(printf '%s\n' "$S" | grep -c .)" != 1 ]; then
  echo "FAILED: expected one Secret labeled managed-by=vmware-vRegistry in $NS, found: ${S:-none}"
else
  OK=""; n=0
  until [ -n "$OK" ] || [ "$n" -ge 40 ]; do
    [ "$n" -eq 0 ] || sleep 15
    n=$((n + 1))
    kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get "$S" -o go-template='{{with index .data "tls.crt"}}{{base64decode .}}{{end}}' \
      | openssl x509 -noout -text 2>/dev/null | tr ',' '\n' | sed 's/^ *//' | grep -q -x -F -e "DNS:$HARBOR_FQDN" -e "DNS:*.${HARBOR_FQDN#*.}" && OK=1
  done
  if [ -z "$OK" ]; then
    echo "FAILED: after 10 minutes Harbor's certificate is still not for $HARBOR_FQDN"
  else
    echo "certificate for $HARBOR_FQDN: yes"
    kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" delete pod -l app=harbor,component=nginx \
      && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" rollout status deployment/harbor-nginx --timeout=300s \
      || echo "FAILED: restart (see the error above)"
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
$HARBOR_FQDN = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
$NS = @(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name)
if (-not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } elseif (-not $REC) { "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first" } elseif ($REC -cne $SUP) { "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT" } elseif (-not $HARBOR_FQDN) { "FAILED: no hostname in $HARBOR_DIR\harbor-data-values.yml (step 4)" } elseif ($LASTEXITCODE -ne 0) { "FAILED: cannot list the Supervisor's namespaces (see the error above)" } elseif ($NS.Count -ne 1) { "FAILED: Harbor namespaces on this Supervisor: '$($NS -join ' ')' (expected exactly one)" } else {
  $NS = $NS[0] -replace '^namespace/', ''
  $S = @(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS get secret -l managed-by=vmware-vRegistry -o name)
  if ($LASTEXITCODE -ne 0 -or $S.Count -ne 1) {
    "FAILED: expected one Secret labeled managed-by=vmware-vRegistry in $NS, found: $(if ($S.Count) { $S -join ' ' } else { 'none' })"
  } else {
    $TMP = [IO.Path]::GetTempFileName()
    $OK = $false; $n = 0
    while (-not $OK -and $n -lt 40) {
      if ($n -gt 0) { Start-Sleep 15 }
      $n++
      $B64 = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS get $S[0] -o jsonpath='{.data.tls\.crt}'
      try {
        [IO.File]::WriteAllBytes($TMP, [Convert]::FromBase64String("$B64"))
        $X = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $TMP
        $WILD = '*.' + ($HARBOR_FQDN -replace '^[^.]*\.', '')
        $WANT = [BitConverter]::ToString([byte[]](@(0x82, $HARBOR_FQDN.Length) + [Text.Encoding]::ASCII.GetBytes($HARBOR_FQDN)))
        $WANT2 = [BitConverter]::ToString([byte[]](@(0x82, $WILD.Length) + [Text.Encoding]::ASCII.GetBytes($WILD)))
        if ($X.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' -and ([BitConverter]::ToString($_.RawData).Contains($WANT) -or [BitConverter]::ToString($_.RawData).Contains($WANT2)) }) { $OK = $true }
      } catch { }
    }
    Remove-Item -Force -ErrorAction SilentlyContinue $TMP
    if (-not $OK) { "FAILED: after 10 minutes Harbor's certificate is still not for $HARBOR_FQDN" } else {
      "certificate for ${HARBOR_FQDN}: yes"
      kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS delete pod -l app=harbor,component=nginx
      if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS rollout status deployment/harbor-nginx --timeout=300s }
      if ($LASTEXITCODE -ne 0) { "FAILED: restart (see the error above)" }
    }
  }
}
```

</details>

**Expect:** `certificate for <the new name>: yes`, `pod "harbor-nginx-…" deleted` (newer
kubectl: `… deleted from <Harbor's namespace> namespace`), then
`deployment "harbor-nginx" successfully rolled out` (Harbor's web server runs again).

**If not:**
- `FAILED: after 10 minutes …`: **FINISH** did not apply the new name, or the name in the file is
  not the one you typed in the vSphere Client: compare them and do step 3 again.
- `FAILED: restart` under `Forbidden`: your user may not delete pods in Harbor's namespace; a
  vCenter administrator must run this block.
- Other `FAILED: …` lines: as in step 9's **If not**.
- Step 9 then prints `http=000` although the DNS record is right: Harbor still serves the old
  certificate; run this block again.

## 13. Use your organization's certificate (optional)

Harbor makes its own CA and a ten-year certificate unless you give it yours. Give it yours when
browsers and tools must trust Harbor through your organization's CA. Safari and Chrome on macOS
also need a certificate valid for 825 days or less, which Harbor's own is not.

You need three PEM files (text files that start with `-----BEGIN`), from your certificate team
or, for the key, made by *Request the certificate* below:

- the server certificate for `HARBOR_FQDN` (a subject alternative name `DNS:<HARBOR_FQDN>` or a
  wildcard such as `DNS:*.<its domain>`, usage
  *TLS Web Server Authentication*), followed by any intermediate CA certificates;
- its private key, not protected by a passphrase;
- the root CA certificate that signed them. VKS gives it to every VKS cluster's nodes.

Nothing renews this certificate: before it expires, get a new one and do this step again.

Ask for the certificate early: *Request the certificate* below makes the request, and your
certificate team may take days.

- **Before the install:** run *Write the certificate into the file* below after step 4, then go
  on with step 5.
- **On an installed Harbor:** this replaces Harbor's CA. VKS gives the new CA to every node of
  every VKS cluster on the Supervisor, replacing some nodes and updating others in place, and
  pulls from Harbor fail on some nodes until that ends. Do it in a
  maintenance window:
  1. Step 6 *Record the VKS cluster machines*.
  2. *Write the certificate into the file* below.
  3. In the vSphere Client, select the Supervisor, then **Configure** → **Supervisor Services** →
     **Overview**. Select **Harbor**, click **MANAGE**, keep the installed version, click **NEXT**
     twice. In **YAML Service Config**, replace everything with the file (step 6 *Copy the
     configuration*), then click **FINISH**. The box shows Harbor's passwords and your key: do not
     share your screen. Then step 6 *Empty the clipboard*.
  4. *Restart Harbor's web server* below.
  5. Steps 8, 9 and 11, then [IMAGE.md steps 1 and 2](IMAGE.md#1-get-harbors-ca) on every
     machine that pushes or pulls.

To go back to Harbor's own certificate, set the three variables `HARBOR_TLS_CRT`,
`HARBOR_TLS_KEY` and `HARBOR_CA_CRT` to `""` and do the same. Harbor
then serves its earlier CA again.

### Request the certificate

Skip this if your certificate team gives you all three files. Otherwise run it once, early, to get
what your certificate team signs. It makes Harbor's private key, `harbor.key`, and a certificate
request, `harbor.csr`, for the name in step 4's file, both in your home folder; nothing changes on
the Supervisor. You get the request's name lines and the file to send. The key stays with you:
send only `harbor.csr` to your certificate team and ask for two PEM files back:

- the server certificate, followed by any intermediate CA certificates: save it as `harbor.crt`
  in your home folder;
- the root CA certificate that signed it: save it as `harbor-root-ca.crt` there.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
HARBOR_TLS_KEY="$HOME/harbor.key"
HARBOR_CSR="$HOME/harbor.csr"
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null | tr -d '\r')"
TMP="$(mktemp -d)"
if [ -z "$HARBOR_FQDN" ]; then
  echo "FAILED: no hostname in $HARBOR_DIR/harbor-data-values.yml (step 4)"
elif [ -e "$HARBOR_TLS_KEY" ]; then
  echo "NOT WRITTEN: $HARBOR_TLS_KEY already exists; use it with its certificate, or move it away first"
else
  CN="$HARBOR_FQDN"; [ "${#CN}" -le 64 ] || CN="${HARBOR_FQDN%%.*}"
  printf '[req]\nprompt = no\ndistinguished_name = dn\nreq_extensions = ext\n[dn]\nCN = %s\n[ext]\nsubjectAltName = DNS:%s\nextendedKeyUsage = serverAuth\n' \
    "$CN" "$HARBOR_FQDN" > "$TMP/req.cnf"
  if ( umask 077; openssl req -new -newkey rsa:2048 -nodes -keyout "$HARBOR_TLS_KEY" -out "$HARBOR_CSR" -config "$TMP/req.cnf" 2>"$TMP/err" ); then
    openssl req -in "$HARBOR_CSR" -noout -subject
    openssl req -in "$HARBOR_CSR" -noout -text | grep -A1 'Subject Alternative Name' | tail -n 1 | sed 's/^ *//'
    echo "send this file: $HARBOR_CSR"
  else
    rm -f "$HARBOR_TLS_KEY" "$HARBOR_CSR"
    cat "$TMP/err"
    echo "FAILED: openssl could not make the request (see the lines above)"
  fi
fi
rm -rf "$TMP"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

This runs `openssl.exe` from [Git for Windows](https://git-scm.com/install/), as the next block
does.

```powershell
$HARBOR_TLS_KEY = "$HOME\harbor.key"
$HARBOR_CSR = "$HOME\harbor.csr"
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

if (-not (Get-Command openssl.exe -ErrorAction SilentlyContinue)) { $env:Path += ';C:\Program Files\Git\usr\bin' }
$VALUES = "$HARBOR_DIR\harbor-data-values.yml"
$HARBOR_FQDN = if (Test-Path $VALUES) { "$((Get-Content $VALUES | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')" } else { '' }
if (-not $HARBOR_FQDN) { "FAILED: no hostname in $HARBOR_DIR\harbor-data-values.yml (step 4)" } elseif (-not (Get-Command openssl.exe -ErrorAction SilentlyContinue)) { 'FAILED: openssl.exe not found (install Git for Windows)' } elseif (Test-Path $HARBOR_TLS_KEY) { "NOT WRITTEN: $HARBOR_TLS_KEY already exists; use it with its certificate, or move it away first" } else {
  $CNF = [IO.Path]::GetTempFileName()
  $CN = if ($HARBOR_FQDN.Length -le 64) { $HARBOR_FQDN } else { $HARBOR_FQDN.Split('.')[0] }
  [IO.File]::WriteAllText($CNF, "[req]`nprompt = no`ndistinguished_name = dn`nreq_extensions = ext`n[dn]`nCN = $CN`n[ext]`nsubjectAltName = DNS:$HARBOR_FQDN`nextendedKeyUsage = serverAuth`n")
  $global:LASTEXITCODE = $null
  $ERRF = [IO.Path]::GetTempFileName()
  openssl.exe req -new -newkey rsa:2048 -nodes -keyout $HARBOR_TLS_KEY -out $HARBOR_CSR -config $CNF 2>$ERRF
  if ($LASTEXITCODE -eq 0) {
    openssl.exe req -in $HARBOR_CSR -noout -subject
    ((openssl.exe req -in $HARBOR_CSR -noout -text) -match '^\s*DNS:' | Select-Object -First 1).Trim()
    "send this file: $HARBOR_CSR"
  } else {
    Remove-Item -Force -ErrorAction SilentlyContinue $HARBOR_TLS_KEY, $HARBOR_CSR
    Get-Content $ERRF
    'FAILED: openssl could not make the request (see the lines above)'
  }
  Remove-Item -Force $CNF, $ERRF
}
```

</details>

**Expect:** a `subject=` line with your Harbor name (only its first part if the name is longer
than 64 characters), `DNS:<HARBOR_FQDN>`, and
`send this file: …harbor.csr`.

**If not:**
- `NOT WRITTEN: … already exists`: a key from an earlier request is there. If its certificate is
  still on its way, wait for it; to start over, move `harbor.key` and `harbor.csr` elsewhere.
- `FAILED: no hostname …`: do step 4 first.
- `FAILED: openssl …`: the lines above it say why. `openssl.exe not found`: install Git for
  Windows. If your team requires a larger key, change `rsa:2048`.

When the two files are back, the next block checks that `harbor.crt` belongs to `harbor.key`.

### Write the certificate into the file

Run this when you have the three files: before the install, after step 4; on an installed Harbor,
as item 2 above. It checks that the certificate is for Harbor's name, for a web server, not
expired, matches the key and is signed through the root CA, and only then writes the three files
into `harbor-data-values.yml` on this machine; nothing changes on the Supervisor until you paste
the file into the vSphere Client. It needs `openssl`. Set `HARBOR_TLS_CRT`, `HARBOR_TLS_KEY` and
`HARBOR_CA_CRT` to the server certificate, its key and the root CA (the names *Request the
certificate* uses are already set). You get the certificate's name and end date, then the three
fields it wrote.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
HARBOR_TLS_CRT="$HOME/harbor.crt"
HARBOR_TLS_KEY="$HOME/harbor.key"
HARBOR_CA_CRT="$HOME/harbor-root-ca.crt"
SUPERVISOR_CONTEXT="supervisor"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

VALUES="$HARBOR_DIR/harbor-data-values.yml"
HARBOR_FQDN="$(sed -n 's/^hostname: //p' "$VALUES" 2>/dev/null)"
TMP="$(mktemp -d)"
ERR=""
if [ -z "$HARBOR_FQDN" ]; then
  ERR="no hostname in $VALUES (step 4)"
elif [ -n "$HARBOR_TLS_CRT$HARBOR_TLS_KEY$HARBOR_CA_CRT" ]; then
  for f in "$HARBOR_TLS_CRT" "$HARBOR_TLS_KEY" "$HARBOR_CA_CRT"; do { [ -f "$f" ] && [ -s "$f" ]; } || ERR="not found: $f"; done
  if [ -z "$ERR" ]; then
    ( umask 077
      tr -d '\r' < "$HARBOR_TLS_CRT" | sed -n '/^-----BEGIN CERTIFICATE-----$/,/^-----END CERTIFICATE-----$/p' > "$TMP/tls.crt"
      tr -d '\r' < "$HARBOR_CA_CRT" | sed -n '/^-----BEGIN CERTIFICATE-----$/,/^-----END CERTIFICATE-----$/p' > "$TMP/ca.crt"
      tr -d '\r' < "$HARBOR_TLS_KEY" | sed -n '/^-----BEGIN .*PRIVATE KEY-----$/,/^-----END .*PRIVATE KEY-----$/p' > "$TMP/tls.key"
      awk '/^-----BEGIN CERTIFICATE-----/ { n++ } { print > (n == 1 ? "'"$TMP"'/leaf.crt" : "'"$TMP"'/chain.crt") }' "$TMP/tls.crt" )
    touch "$TMP/chain.crt"
    if grep -q 'PRIVATE KEY' "$HARBOR_TLS_CRT" "$HARBOR_CA_CRT"; then
      ERR="a private key is in $HARBOR_TLS_CRT or $HARBOR_CA_CRT: give it only in HARBOR_TLS_KEY"
    elif ! grep -q '^-----BEGIN CERTIFICATE-----' "$TMP/leaf.crt" 2>/dev/null; then
      ERR="no PEM certificate in $HARBOR_TLS_CRT"
    elif ! grep -q '^-----BEGIN .*PRIVATE KEY-----' "$TMP/tls.key" || grep -q 'ENCRYPTED' "$TMP/tls.key"; then
      ERR="$HARBOR_TLS_KEY is not a PEM private key without a passphrase"
    elif [ "$(grep -c '^-----BEGIN CERTIFICATE-----' "$TMP/ca.crt")" != 1 ]; then
      ERR="$HARBOR_CA_CRT must hold exactly one PEM certificate, the root CA"
    elif ! openssl x509 -in "$TMP/leaf.crt" -noout -text | tr ',' '\n' | sed 's/^ *//' | grep -q -x -F -e "DNS:$HARBOR_FQDN" -e "DNS:*.${HARBOR_FQDN#*.}"; then
      ERR="the certificate is not for $HARBOR_FQDN (no DNS:$HARBOR_FQDN)"
    elif ! openssl x509 -in "$TMP/leaf.crt" -noout -text | grep -q 'TLS Web Server Authentication'; then
      ERR="the certificate is not for TLS Web Server Authentication"
    elif ! openssl x509 -in "$TMP/leaf.crt" -noout -checkend 0 >/dev/null; then
      ERR="the certificate has expired"
    elif [ "$(openssl x509 -in "$TMP/leaf.crt" -noout -pubkey | openssl sha256)" != "$(openssl pkey -in "$TMP/tls.key" -pubout | openssl sha256)" ]; then
      ERR="$HARBOR_TLS_KEY is not the key of $HARBOR_TLS_CRT"
    elif ! openssl verify -CAfile "$TMP/ca.crt" -untrusted "$TMP/chain.crt" "$TMP/leaf.crt" >/dev/null 2>&1 \
         && ! openssl verify -CAfile "$TMP/ca.crt" "$TMP/leaf.crt" >/dev/null 2>&1; then
      ERR="$HARBOR_CA_CRT and the intermediates in $HARBOR_TLS_CRT do not verify the certificate"
    fi
  fi
fi
if [ -n "$ERR" ]; then
  echo "NOT WRITTEN: $ERR"
else
  [ -s "$TMP/leaf.crt" ] && openssl x509 -in "$TMP/leaf.crt" -noout -subject -enddate
  rm -f "$VALUES.new"
  ( umask 077
    awk -v d="$TMP" '
      /^[A-Za-z][A-Za-z0-9_]*:/ { top = $1; skip = 0 }
      skip && /^    [-A-Za-z0-9+\/= ]+$/ { next }
      { skip = 0 }
      top == "tlsCertificate:" && /^  (tls\.crt|tls\.key|ca\.crt):/ {
        k = $1; sub(/:$/, "", k); f = d "/" k; skip = 1
        if ((getline line < f) > 0) { print "  " k ": |"; do print "    " line; while ((getline line < f) > 0) }
        else print "  " k ":"
        close(f); next }
      { print }
    ' "$VALUES" > "$VALUES.new" )
  N="$(grep -c -E '^  (tls\.crt|tls\.key|ca\.crt):' "$VALUES.new")"
  if [ "$N" != 3 ] || [ "$(grep -c -E '^(hostname|tlsCertificate):' "$VALUES.new")" != 2 ]; then
    rm -f "$VALUES.new"
    echo "FAILED: the file did not come out as expected; $VALUES is as it was"
  else
    mv "$VALUES.new" "$VALUES"
    grep -E '^  (tls\.crt|tls\.key|ca\.crt):' "$VALUES"
  fi
fi
rm -rf "$TMP"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

Windows PowerShell 5.1 cannot read PEM keys: this block runs `openssl.exe`, which comes with
[Git for Windows](https://git-scm.com/install/) (`C:\Program Files\Git\usr\bin`).

```powershell
$HARBOR_TLS_CRT = "$HOME\harbor.crt"
$HARBOR_TLS_KEY = "$HOME\harbor.key"
$HARBOR_CA_CRT = "$HOME\harbor-root-ca.crt"
$SUPERVISOR_CONTEXT = "supervisor"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$VALUES = "$HARBOR_DIR\harbor-data-values.yml"
$HARBOR_FQDN = if (Test-Path $VALUES) { "$((Get-Content $VALUES | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')" } else { '' }
if (-not (Get-Command openssl.exe -ErrorAction SilentlyContinue)) { $env:Path += ';C:\Program Files\Git\usr\bin' }
$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null
$ERR = ''
function Pem($f) { (([IO.File]::ReadAllText($f) -replace "`r", '') | Select-String -AllMatches '(?ms)^-----BEGIN [^\n]*-----\n.*?\n-----END [^\n]*-----$').Matches | ForEach-Object { $_.Value } }
if (-not $HARBOR_FQDN) { $ERR = "no hostname in $VALUES (step 4)" } elseif (-not (Get-Command openssl.exe -ErrorAction SilentlyContinue)) { $ERR = 'openssl.exe not found (install Git for Windows)' } elseif ("$HARBOR_TLS_CRT$HARBOR_TLS_KEY$HARBOR_CA_CRT") {
  foreach ($f in $HARBOR_TLS_CRT, $HARBOR_TLS_KEY, $HARBOR_CA_CRT) { if (-not (Test-Path $f -PathType Leaf) -or (Get-Item $f).Length -eq 0) { $ERR = "not found: $f" } }
  if (-not $ERR) {
    $CRT = @(Pem $HARBOR_TLS_CRT | Where-Object { $_ -clike '-----BEGIN CERTIFICATE-----*' })
    $KEY = @(Pem $HARBOR_TLS_KEY | Where-Object { $_ -cmatch '^-----BEGIN [A-Z ]*PRIVATE KEY-----' })
    $CA = @(Pem $HARBOR_CA_CRT | Where-Object { $_ -clike '-----BEGIN CERTIFICATE-----*' })
    [IO.File]::WriteAllText("$TMP\leaf.crt", "$($CRT[0])`n")
    [IO.File]::WriteAllText("$TMP\chain.crt", (($CRT | Select-Object -Skip 1) -join "`n") + "`n")
    [IO.File]::WriteAllText("$TMP\tls.key", "$($KEY[0])`n")
    [IO.File]::WriteAllText("$TMP\ca.crt", "$($CA[0])`n")
    $TEXT = (openssl.exe x509 -in "$TMP\leaf.crt" -noout -text 2>$null) -join "`n"
    if (([IO.File]::ReadAllText($HARBOR_TLS_CRT) + [IO.File]::ReadAllText($HARBOR_CA_CRT)) -cmatch 'PRIVATE KEY') { $ERR = "a private key is in $HARBOR_TLS_CRT or ${HARBOR_CA_CRT}: give it only in HARBOR_TLS_KEY" } elseif ($CRT.Count -lt 1) { $ERR = "no PEM certificate in $HARBOR_TLS_CRT" } elseif ($KEY.Count -ne 1 -or $KEY[0] -cmatch 'ENCRYPTED') { $ERR = "$HARBOR_TLS_KEY is not a PEM private key without a passphrase" } elseif ($CA.Count -ne 1) { $ERR = "$HARBOR_CA_CRT must hold exactly one PEM certificate, the root CA" } elseif (-not (($TEXT -split '[,\n]' | ForEach-Object { $_.Trim() }) -ceq "DNS:$HARBOR_FQDN") -and -not (($TEXT -split '[,\n]' | ForEach-Object { $_.Trim() }) -ceq ('DNS:*.' + ($HARBOR_FQDN -replace '^[^.]*\.', '')))) { $ERR = "the certificate is not for $HARBOR_FQDN (no DNS:$HARBOR_FQDN)" } elseif ($TEXT -notmatch 'TLS Web Server Authentication') { $ERR = 'the certificate is not for TLS Web Server Authentication' } elseif ($(openssl.exe x509 -in "$TMP\leaf.crt" -noout -checkend 0 | Out-Null; $LASTEXITCODE) -ne 0) { $ERR = 'the certificate has expired' } elseif ("$(openssl.exe x509 -in "$TMP\leaf.crt" -noout -pubkey)" -cne "$(openssl.exe pkey -in "$TMP\tls.key" -pubout)") { $ERR = "$HARBOR_TLS_KEY is not the key of $HARBOR_TLS_CRT" } elseif ($(openssl.exe verify -CAfile "$TMP\ca.crt" -untrusted "$TMP\chain.crt" "$TMP\leaf.crt" 2>&1 | Out-Null; $LASTEXITCODE) -ne 0 -and
            $(openssl.exe verify -CAfile "$TMP\ca.crt" "$TMP\leaf.crt" 2>&1 | Out-Null; $LASTEXITCODE) -ne 0) {
      $ERR = "$HARBOR_CA_CRT and the intermediates in $HARBOR_TLS_CRT do not verify the certificate" }
  }
}
if ($ERR) { "NOT WRITTEN: $ERR" } else {
  $NEW = @{ 'tls.crt' = @($CRT); 'tls.key' = @($KEY); 'ca.crt' = @($CA) }
  if (-not "$HARBOR_TLS_CRT$HARBOR_TLS_KEY$HARBOR_CA_CRT") { $NEW = @{ 'tls.crt' = @(); 'tls.key' = @(); 'ca.crt' = @() } } else { openssl.exe x509 -in "$TMP\leaf.crt" -noout -subject -enddate }
  $top = ''; $skip = $false
  $OUT = foreach ($l in [IO.File]::ReadAllLines($VALUES)) {
    if ($l -cmatch '^([A-Za-z][A-Za-z0-9_]*):') { $top = $Matches[1]; $skip = $false }
    if ($skip -and $l -cmatch '^    [-A-Za-z0-9+/= ]+$') { continue }
    $skip = $false
    if ($top -eq 'tlsCertificate' -and $l -cmatch '^  (tls\.crt|tls\.key|ca\.crt):') {
      $k = $Matches[1]; $skip = $true
      if ($NEW[$k].Count) { "  ${k}: |"; ($NEW[$k] -join "`n") -split "`n" | ForEach-Object { "    $_" } } else { "  ${k}:" }
    } else { $l }
  }
  if (@($OUT | Where-Object { $_ -cmatch '^  (tls\.crt|tls\.key|ca\.crt):' }).Count -ne 3) {
    "FAILED: the file did not come out as expected; $VALUES is as it was"
  } else {
    [IO.File]::WriteAllText($VALUES, ($OUT -join "`n") + "`n")
    $OUT | Where-Object { $_ -cmatch '^  (tls\.crt|tls\.key|ca\.crt):' }
  }
}
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TMP
```

</details>

**Expect:** the certificate's `subject=` and `notAfter=`, then `tls.crt: |`, `tls.key: |` and
`ca.crt: |`. With the three variables `""`: `tls.crt:`, `tls.key:` and `ca.crt:` only.

**If not:** `NOT WRITTEN: …` names the file or check that failed; the file is as it was. A
certificate refused for its name (`no DNS:…`) or its usage (`TLS Web Server Authentication`): ask
your certificate team for a TLS server certificate with `DNS:<HARBOR_FQDN>`. Do not
paste a file this block refused into the vSphere Client: a wrong `ca.crt` stops VKS cluster
creation and updates on the whole Supervisor.

### Restart Harbor's web server

Run this on an installed Harbor as item 4 above, after **FINISH**: Harbor's web server keeps
serving the old certificate until it restarts. This waits until Harbor has stored the new
certificate (a minute or less): yours, or Harbor's own if you went back. It then deletes Harbor's
web server pod in Harbor's namespace on the Supervisor; the pod starts again by itself and serves
the new one. Pushes and pulls fail while it restarts. You get the certificate's issuer, then
Harbor's web server running again. Then do item 5.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

VALUES="$HARBOR_DIR/harbor-data-values.yml"
WANT="$(awk '/^  tls\.crt: \|/ { f = 1; next } f && /^    / { sub(/^    /, ""); print; next } { f = 0 }' "$VALUES" 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 2>/dev/null)"
REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif [ ! -r "$VALUES" ]; then
  echo "FAILED: no $VALUES (step 4)"
elif ! NS="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o jsonpath='{.items[*].metadata.name}')"; then
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
elif [ -z "$NS" ] || [ "$NS" != "${NS#* }" ]; then
  echo "FAILED: Harbor namespaces on this Supervisor: '${NS}' (expected exactly one)"
elif ! S="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get secret -l managed-by=vmware-vRegistry -o name)" \
     || [ "$(printf '%s\n' "$S" | grep -c .)" != 1 ]; then
  echo "FAILED: expected one Secret labeled managed-by=vmware-vRegistry in $NS, found: ${S:-none}"
else
  OK=""; n=0
  until [ -n "$OK" ] || [ "$n" -ge 40 ]; do
    [ "$n" -eq 0 ] || sleep 15
    n=$((n + 1))
    C="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" get "$S" -o go-template='{{with index .data "tls.crt"}}{{base64decode .}}{{end}}')"
    GOT="$(printf '%s\n' "$C" | openssl x509 -noout -fingerprint -sha256 2>/dev/null)"
    ISSUER="$(printf '%s\n' "$C" | openssl x509 -noout -issuer 2>/dev/null)"
    if [ -n "$WANT" ]; then
      [ "$GOT" = "$WANT" ] && OK=1
    else
      printf '%s\n' "$ISSUER" | grep -q 'CN *= *Harbor CA$' && OK=1
    fi
  done
  if [ -z "$OK" ]; then
    echo "FAILED: after 10 minutes Harbor's Secret does not hold the certificate from the file"
  else
    echo "Harbor's certificate: $ISSUER"
    kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" delete pod -l app=harbor,component=nginx \
      && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$NS" rollout status deployment/harbor-nginx --timeout=300s \
      || echo "FAILED: restart (see the error above)"
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
$VALUES = "$HARBOR_DIR\harbor-data-values.yml"
$WANT = ''; $f = $false
foreach ($l in $(if (Test-Path $VALUES) { [IO.File]::ReadAllLines($VALUES) })) {
  if ($l -ceq '  tls.crt: |') { $f = $true; continue }
  if ($f -and $l -cmatch '^    (.*)$') { $WANT += $Matches[1] + "`n" } else { $f = $false }
}
function Body($t) { if ("$t" -cmatch '(?s)-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----') { $Matches[1] -replace '\s', '' } else { '' } }
$WANT = Body $WANT
$NS = @(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name)
if (-not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } elseif (-not $REC) { "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first" } elseif ($REC -cne $SUP) { "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT" } elseif (-not (Test-Path $VALUES)) { "FAILED: no $VALUES (step 4)" } elseif ($LASTEXITCODE -ne 0) { "FAILED: cannot list the Supervisor's namespaces (see the error above)" } elseif ($NS.Count -ne 1) { "FAILED: Harbor namespaces on this Supervisor: '$($NS -join ' ')' (expected exactly one)" } else {
  $NS = $NS[0] -replace '^namespace/', ''
  $S = @(kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS get secret -l managed-by=vmware-vRegistry -o name)
  if ($LASTEXITCODE -ne 0 -or $S.Count -ne 1) {
    "FAILED: expected one Secret labeled managed-by=vmware-vRegistry in $NS, found: $(if ($S.Count) { $S -join ' ' } else { 'none' })"
  } else {
    $OK = $false; $n = 0; $ISSUER = ''
    while (-not $OK -and $n -lt 40) {
      if ($n -gt 0) { Start-Sleep 15 }
      $n++
      $B64 = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS get $S[0] -o jsonpath='{.data.tls\.crt}'
      try {
        $GOT = Body ([Text.Encoding]::ASCII.GetString([Convert]::FromBase64String("$B64")))
        $ISSUER = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 (,[Convert]::FromBase64String($GOT))).Issuer
        if ($WANT) { $OK = ($GOT -ceq $WANT) } else { $OK = ($ISSUER -cmatch 'CN=Harbor CA$') }
      } catch { }
    }
    if (-not $OK) { "FAILED: after 10 minutes Harbor's Secret does not hold the certificate from the file" } else {
      "Harbor's certificate: issuer=$ISSUER"
      kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS delete pod -l app=harbor,component=nginx
      if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $NS rollout status deployment/harbor-nginx --timeout=300s }
      if ($LASTEXITCODE -ne 0) { "FAILED: restart (see the error above)" }
    }
  }
}
```

</details>

**Expect:** `Harbor's certificate:` with your CA as issuer (Harbor's own certificate: `CN = Harbor CA`
/ `CN=Harbor CA`), `pod "harbor-nginx-…" deleted` (newer kubectl: `… deleted from <Harbor's
namespace> namespace`), then `deployment "harbor-nginx" successfully
rolled out` (Harbor's web server runs again).

**If not:**
- `FAILED: after 10 minutes …`: **FINISH** did not apply the file: check that you pasted all of
  it, and look at Harbor's state under **Configure** → **Supervisor Services**.
- `FAILED: restart` under `Forbidden`: your user may not delete pods in Harbor's namespace; a
  vCenter administrator must run this block.
- Other `FAILED: …` lines: as in step 9's **If not**.

## 14. Uninstall Harbor (optional)

**Uninstalling destroys everything this Harbor holds**: every image, project and robot account.
A new install starts empty, with a new address and a new CA. **It also updates every node of
every VKS cluster on this Supervisor** again.

### Check that it is yours

**Only uninstall a Harbor you installed.** Run this before *Uninstall it*. It looks for the note
that step 1 left on this machine, and changes nothing. You get `MAY UNINSTALL` only if this
Supervisor had no Harbor when you began; otherwise `DO NOT UNINSTALL` (`NOTHING TO UNINSTALL`
when this Supervisor has no Harbor).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif ! H="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o name)"; then
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
elif [ -z "$H" ]; then
  echo "NOTHING TO UNINSTALL: this Supervisor has no Harbor"
elif [ -z "$REC" ]; then
  echo "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first"
elif [ "$REC" != "$SUP" ]; then
  echo "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT"
elif [ -e "$HARBOR_DIR/none-before-$SUP" ]; then
  echo "MAY UNINSTALL: this Supervisor had no Harbor when you began"
else
  echo "DO NOT UNINSTALL: this machine has no record that this Supervisor had no Harbor before yours"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
if ($LASTEXITCODE -ne 0 -or -not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } elseif (-not ($H = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name) -and $LASTEXITCODE -ne 0) { "FAILED: cannot list the Supervisor's namespaces (see the error above)" } elseif (-not $H) { "NOTHING TO UNINSTALL: this Supervisor has no Harbor" } elseif (-not $REC) { "FAILED: $HARBOR_DIR has no supervisor-uid: run step 1 first" } elseif ($REC -cne $SUP) { "FAILED: $HARBOR_DIR belongs to another Supervisor ($REC); set another SUPERVISOR_CONTEXT" } elseif (Test-Path "$HARBOR_DIR\none-before-$SUP") { "MAY UNINSTALL: this Supervisor had no Harbor when you began" } else { "DO NOT UNINSTALL: this machine has no record that this Supervisor had no Harbor before yours" }
```

</details>

**Expect:** `MAY UNINSTALL: this Supervisor had no Harbor when you began`.

**If not:**
- `NOTHING TO UNINSTALL`: there is no Harbor on this Supervisor; skip *Uninstall it*.
- `DO NOT UNINSTALL: …`: stop. A Harbor was there when you began, or you began on another
  machine.
- `FAILED: … belongs to another Supervisor (…)` or `… has no supervisor-uid …`: stop; this
  folder's notes are not this Supervisor's (see step 1's **If not**).

The record proves only what step 1 saw, not who installed the Harbor there now: if you are not
sure it is yours, ask before you click.

### Uninstall it

1. Run [Record the VKS cluster machines](#record-the-vks-cluster-machines) for each vSphere
   Namespace with VKS clusters.
2. In the vSphere Client: **Supervisor Management** → **Supervisors** → **View** in your
   Supervisor's **Services** column. Select **Harbor**, click **UNINSTALL**, then **UNINSTALL**
   in the window that asks *Are you sure…*. The row shows **Removing**, then disappears.

   ![The Supervisor's installed services with Harbor selected and the UNINSTALL confirmation window](img/harbor/09-uninstall.png)

On the Supervisor, Harbor runs in its own namespace (`svc-harbor-…`). Run this after the row
disappears: until that namespace is gone, Harbor is still being removed, and a new install fails.
It lists the Harbor namespaces left on the Supervisor and changes nothing. Run it again until it
prints `none`: a few minutes.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"

if H="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o name)"; then
  echo "Harbor namespaces left: ${H:-none}"
else
  echo "FAILED: cannot list the Supervisor's namespaces (see the error above)"
fi
```

**Windows (PowerShell):**

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"

$global:LASTEXITCODE = $null
$H = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name
if ($LASTEXITCODE -eq 0) { "Harbor namespaces left: $(if ($H) { $H -join ' ' } else { 'none' })" } else { "FAILED: cannot list the Supervisor's namespaces (see the error above)" }
```

**Expect:** `Harbor namespaces left: none`.

**If not:** a name: the namespace is still being deleted. Wait before you install again. Do not
force its deletion by hand.

Then run [step 8](#8-check-that-the-vks-cluster-nodes-were-updated) until it shows
`machines updated: <n> of <n>`. The nodes start to update some minutes after the namespace is
gone. **If not:** still `0` 30 minutes after the namespace is gone: the nodes were not updated;
go on. Stuck above `0` but below the total: see step 8's **If not**.

### Remove the service from vCenter

Only if no Supervisor of this vCenter will run Harbor again, and only for a service you
registered. This removes it for every Supervisor.

1. On the **Services** tab, on the **Harbor** card, click **ACTIONS** → **Delete**. The **Delete
   Harbor** window has three sections and a **DELETE** button that stays grey until they are
   done.

   ![The Delete Harbor window after the uninstall: section 1 Deactivate service with CONFIRM, section 2 Uninstall all versions from Supervisors with a green tick, section 3 Delete all versions of the Service with CONFIRM and the version table showing 0 Supervisors, and a grey DELETE button](img/harbor/10-delete-wizard.png)

2. Check section **2. Uninstall all versions from Supervisors**: it must have a green tick, and
   the table under section 3 must show `0` under **Supervisors**. **Otherwise stop and close the
   window**: Harbor still runs on a Supervisor, and going on uninstalls it there, with
   everything it holds.
3. Click **CONFIRM** under **1. Deactivate service**, then **CONFIRM** under **3. Delete all
   versions of the Service**, then **DELETE**.

**Expect:** *'Harbor' successfully deleted.* The card disappears when the page is
reloaded.

### Delete what this guide wrote

Run this last, once Harbor is uninstalled. It deletes this guide's folder for this Supervisor on
this machine (`~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT>`), only when no Harbor is on the
Supervisor: with that folder go Harbor's passwords (`secrets.env`) and CA (`harbor-ca.crt`). Step
13's files in your home folder stay. You get `deleted …`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

REC="$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')"
if ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "Nothing deleted: cannot read the Supervisor (see the error above)"
elif [ -z "$REC" ]; then
  echo "Nothing deleted: $HARBOR_DIR has no supervisor-uid (step 1)"
elif [ "$REC" != "$SUP" ]; then
  echo "Nothing deleted: $HARBOR_DIR belongs to another Supervisor ($REC)"
elif ! H="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace -l appplatform.vmware.com/serviceId=harbor -o name)"; then
  echo "Nothing deleted: cannot list the Supervisor's namespaces (see the error above)"
elif [ -n "$H" ]; then
  echo "Nothing deleted: a Harbor is still on the Supervisor $REC ($H)"
else
  rm -rf "$HARBOR_DIR" && echo "deleted $HARBOR_DIR"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$REC = "$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()
$SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
if ($LASTEXITCODE -ne 0 -or -not $SUP) { "Nothing deleted: cannot read the Supervisor (see the error above)" } elseif (-not $REC) { "Nothing deleted: $HARBOR_DIR has no supervisor-uid (step 1)" } elseif ($REC -cne $SUP) { "Nothing deleted: $HARBOR_DIR belongs to another Supervisor ($REC)" } else {
  $H = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace -l appplatform.vmware.com/serviceId=harbor -o name
  if ($LASTEXITCODE -ne 0) { "Nothing deleted: cannot list the Supervisor's namespaces (see the error above)" } elseif ($H) { "Nothing deleted: a Harbor is still on the Supervisor $REC ($($H -join ' '))" } else { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $HARBOR_DIR; "deleted $HARBOR_DIR" }
}
```

</details>

**Expect:** `deleted …`.

**If not:**
- `Nothing deleted: a Harbor is still …`: these files belong to it; keep them.
- `Nothing deleted: … belongs to another Supervisor (…)`: the folder belongs to the Supervisor
  that this context name was used for before, or to this Supervisor before it was deployed again
  (a new UID). To free the name, move it aside
  (`mv ~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT> ~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT>.old-<date>`;
  PowerShell: `Rename-Item $HOME\.config\vks-guides\harbor-<SUPERVISOR_CONTEXT> harbor-<SUPERVISOR_CONTEXT>.old-<date>`).
  Delete the `.old-<date>` folder only once you know its Harbor is gone.
- `Nothing deleted: … has no supervisor-uid`: step 1 was not run with this `SUPERVISOR_CONTEXT`;
  move the folder aside the same way.

**DNS record:** ask for Harbor's DNS record to be removed too.

If you trusted Harbor's CA for podman or docker, [IMAGE.md step 8](IMAGE.md#8-remove-it-optional)
says how to stop.

## Fix common problems

| symptom | fix |
|---|---|
| `error: You must be logged in to the server (Unauthorized)`, or a block says Harbor is not installed right after it was | Run [Renew the Supervisor login](SUPERVISOR-LOGIN.md#renew-the-supervisor-login), then the block again. |
| `Harbor namespaces on this Supervisor: '<two names>'` | One of them is still being removed after an uninstall: wait, then run the block again. |
| **Validate** shows **Signature Verification** failed | The manifest is not Broadcom's file, or was edited: download it again (step 2). |
| The paste into **YAML Service Config** is one long line, or the install fails with a YAML error | The clipboard lost the line breaks (some remote-desktop programs do that). Open `harbor-data-values.yml` in an editor on the browser's machine and copy from there. |
| Every push and pull fails after Harbor was installed again | A new install has a new address, a new CA and an empty registry: change the DNS record, run steps 9 and 10 again. |
| `blob upload invalid` on push | The registry volume is full. In Harbor's web page delete what you do not need, then **Administration** → **Clean Up** → **Garbage Collection**. |
| Scans fail or never finish | Trivy downloads its data from `ghcr.io`. Without that access scans fail; pushes and pulls still work. |

## Files from an earlier version of this guide (optional)

Only if `~/.config/vks-guides/harbor` (PowerShell `$HOME\.config\vks-guides\harbor`) exists on
this machine. Run it before step 1.

An earlier version kept the files in that folder. This moves it, on this machine, to the
Supervisor's own folder, and changes nothing on the Supervisor. Set `SUPERVISOR_CONTEXT` to your
login's name for the Supervisor that Harbor runs on. You get `moved to …` (with the Supervisor it
recorded, when step 1's note is in the folder), or `nothing to move`.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
OLD="$HOME/.config/vks-guides/harbor"
SUPERVISOR_CONTEXT="supervisor"
NEW="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

if [ ! -d "$OLD" ]; then
  echo "nothing to move"
elif [ -e "$NEW" ]; then
  echo "FAILED: $NEW exists; nothing moved"
elif ! mv "$OLD" "$NEW"; then
  echo "FAILED: nothing moved (see the error above)"
else
  M="$(ls "$NEW" | grep '^none-before-')"
  if [ -z "$M" ] || [ "$(printf '%s\n' "$M" | grep -c .)" != 1 ]; then
    echo "moved to $NEW; bind it: Bind the moved files to this Supervisor"
  elif ! printf '%s\n' "${M#none-before-}" > "$NEW/supervisor-uid"; then
    rm -f "$NEW/supervisor-uid"
    echo "moved to $NEW, but FAILED: cannot write $NEW/supervisor-uid (see the error above)"
  else
    echo "moved to $NEW, recorded Supervisor ${M#none-before-}"
  fi
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$OLD = "$HOME\.config\vks-guides\harbor"
$SUPERVISOR_CONTEXT = "supervisor"
$NEW = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

if (-not (Test-Path -LiteralPath $OLD -PathType Container)) { "nothing to move" } elseif (Test-Path -LiteralPath $NEW) { "FAILED: $NEW exists; nothing moved" } else {
  $MOVED = $false
  try {
    Move-Item -LiteralPath $OLD -Destination $NEW -ErrorAction Stop
    $MOVED = $true
  } catch {
    "FAILED: nothing moved ($($_.Exception.Message))"
  }
  if ($MOVED) {
    $M = @(Get-ChildItem -Name -LiteralPath $NEW | Where-Object { $_ -clike 'none-before-*' })
    if ($M.Count -ne 1) {
      "moved to $NEW; bind it: Bind the moved files to this Supervisor"
    } else {
      $U = $M[0].Substring(12)
      try {
        Set-Content -Encoding ascii -Path "$NEW\supervisor-uid" -Value $U -ErrorAction Stop
        "moved to $NEW, recorded Supervisor $U"
      } catch {
        Remove-Item -LiteralPath "$NEW\supervisor-uid" -ErrorAction SilentlyContinue
        "moved to $NEW, but FAILED: cannot write $NEW\supervisor-uid ($($_.Exception.Message))"
      }
    }
  }
}
```

</details>

**Expect:** `nothing to move`, or `moved to …, recorded Supervisor <uid>`. Then run step 1; skip
the next section unless step 1 sends you there.

**If not:**
- `FAILED: … exists; nothing moved`: if `harbor-<SUPERVISOR_CONTEXT>` holds only `supervisor-uid`
  (and maybe a `none-before-…` file), step 1 made it: rename it (`mv` it to
  `harbor-<SUPERVISOR_CONTEXT>.old-<date>`, a name that does not exist yet; PowerShell
  `Rename-Item`) and run this block again. Otherwise compare the `hostname:` line of each folder's
  `harbor-data-values.yml` with the Harbor in the vSphere Client, and keep the matching one.
- `FAILED: nothing moved (see the error above)`: the error names the cause (often no permission);
  fix it and run the block again.
- `moved to …; bind it: …` (no single note from step 1, or several): run
  [Bind the moved files to this Supervisor](#bind-the-moved-files-to-this-supervisor) below.
- `moved to …, but FAILED: cannot write …`: the files were moved; fix the cause the error names,
  then run [Bind the moved files to this Supervisor](#bind-the-moved-files-to-this-supervisor).

### Bind the moved files to this Supervisor

Run this when step 1 or the block above tells you to bind the files, and only for files that
belong to the Supervisor this login reaches. The first run prints the Harbor hostname in the files
and writes nothing. If that is the Harbor of this Supervisor, put that name in the block's first
line (`BIND_HOSTNAME`) and run the block again: it records the Supervisor's ID in
`supervisor-uid`, on this machine only. You get `bound …`; then run step 1.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
BIND_HOSTNAME=""
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
HARBOR_DIR="$HOME/.config/vks-guides/harbor-${SUPERVISOR_CONTEXT}"

N="$(sed -n 's/^hostname: //p' "$HARBOR_DIR/harbor-data-values.yml" 2>/dev/null | tr -d '\r')"
if [ ! -d "$HARBOR_DIR" ]; then
  echo "FAILED: $HARBOR_DIR does not exist; nothing to bind"
elif [ -n "$(cat "$HARBOR_DIR/supervisor-uid" 2>/dev/null | tr -d '\r')" ]; then
  echo "FAILED: $HARBOR_DIR already has a supervisor-uid; nothing changed"
elif [ -z "$BIND_HOSTNAME" ] || [ "$BIND_HOSTNAME" != "${N:-none}" ]; then
  echo "hostname in these files: ${N:-none}; if that is the Harbor of the Supervisor this login reaches, put BIND_HOSTNAME=\"${N:-none}\" in this block's first line and run the block again"
elif ! SUP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace kube-system -o jsonpath='{.metadata.uid}')" || [ -z "$SUP" ]; then
  echo "FAILED: cannot read the Supervisor (see the error above)"
elif ! printf '%s\n' "$SUP" > "$HARBOR_DIR/supervisor-uid"; then
  rm -f "$HARBOR_DIR/supervisor-uid"
  echo "FAILED: cannot write $HARBOR_DIR (see the error above)"
else
  echo "bound $HARBOR_DIR to the Supervisor $SUP"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$BIND_HOSTNAME = ""
$SUPERVISOR_CONTEXT = "supervisor"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\${SUPERVISOR_CONTEXT}.kubeconfig"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor-${SUPERVISOR_CONTEXT}"

$global:LASTEXITCODE = $null
$N = "$((Get-Content "$HARBOR_DIR\harbor-data-values.yml" -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^hostname: ' }) -replace '^hostname: ', '')".Trim()
if (-not $N) { $N = "none" }
if (-not (Test-Path -LiteralPath $HARBOR_DIR -PathType Container)) { "FAILED: $HARBOR_DIR does not exist; nothing to bind" } elseif ("$(Get-Content -Raw "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue)".Trim()) { "FAILED: $HARBOR_DIR already has a supervisor-uid; nothing changed" } elseif (-not $BIND_HOSTNAME -or $BIND_HOSTNAME -cne $N) {
  "hostname in these files: ${N}; if that is the Harbor of the Supervisor this login reaches, put `$BIND_HOSTNAME = `"${N}`" in this block's first line and run the block again"
} else {
  $SUP = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace kube-system -o jsonpath='{.metadata.uid}'
  if ($LASTEXITCODE -ne 0 -or -not $SUP) { "FAILED: cannot read the Supervisor (see the error above)" } else {
    try {
      Set-Content -Encoding ascii -Path "$HARBOR_DIR\supervisor-uid" -Value $SUP -ErrorAction Stop
      "bound $HARBOR_DIR to the Supervisor $SUP"
    } catch {
      Remove-Item -LiteralPath "$HARBOR_DIR\supervisor-uid" -ErrorAction SilentlyContinue
      "FAILED: cannot write $HARBOR_DIR ($($_.Exception.Message))"
    }
  }
}
```

</details>

**Expect:** first run: `hostname in these files: <your Harbor's name>; …`. Second run, with
`BIND_HOSTNAME` set to that name: `bound … to the Supervisor <uid>`. Then run step 1.

**If not:**
- The hostname is not this Supervisor's Harbor: the folder belongs to another Supervisor. Log in
  to that one under its own `SUPERVISOR_CONTEXT` ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#create-supervisor-context-with-ca)),
  or move the folder aside (`mv ~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT> ~/.config/vks-guides/harbor-<SUPERVISOR_CONTEXT>.old-<date>`;
  PowerShell: `Rename-Item $HOME\.config\vks-guides\harbor-<SUPERVISOR_CONTEXT> harbor-<SUPERVISOR_CONTEXT>.old-<date>`).
- `FAILED: … already has a supervisor-uid`: the folder is bound already; run step 1, and see its
  **If not** if it says the folder belongs to another Supervisor.
- `FAILED: cannot read the Supervisor`: as in step 1's **If not**.
- `FAILED: cannot write …`: fix the cause the error names and run the block again.

## References

**Official Broadcom documentation (VCF 9.1) and Harbor documentation for this guide**

- [Install Harbor as a Supervisor Service](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/using-harbor-as-vcf-service/installing-and-configuring-harbor-and-contour/install-harbor-as-a-supervisor-service.html)
- [Supervisor Services: how to find and install them](https://github.com/vsphere-tmm/Supervisor-Services/blob/main/README.md) (the `legacy` manifest)
- [Add a Supervisor Service to vCenter](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-supervisor-services-with-vsphere-iaas-control-plane/supervisor-service-life-cycle-management-and-consumption/add-a-vsphere-services-to-vcenter-server.html)
- [Map the Harbor FQDN to the Ingress IP Address](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/using-harbor-as-vcf-service/installing-and-configuring-harbor-and-contour/map-the-harbor-fqdn-to-the-envoy-ingress-ip-address.html)
- [Using Harbor as a Private Registry](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/using-private-registries-with-tkg-service-clusters/install-the-harbor-supervisor-service.html) (the node update)
- [Configure a Docker Client with the Harbor Registry Certificate](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/using-private-registries-with-tkg-service-clusters/configure-a-docker-client-with-the-harbor-registry-certificate.html) (docker login with Harbor's CA)
- Harbor 2.15: [Create Projects](https://goharbor.io/docs/2.15.0/working-with-projects/create-projects/), [Create Project Robot Accounts](https://goharbor.io/docs/2.15.0/working-with-projects/project-configuration/create-robot-accounts/), [Garbage Collection](https://goharbor.io/docs/2.15.0/administration/garbage-collection/)
- [Uninstall a Supervisor Service from a Supervisor](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-supervisor-services-with-vsphere-iaas-control-plane/supervisor-service-life-cycle-management-and-consumption/uninstall-a-supervisor-service-version-from-a-supervisor.html)
- [Delete a Supervisor Service](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-supervisor-services-with-vsphere-iaas-control-plane/supervisor-service-life-cycle-management-and-consumption/delete-a-vsphere-service.html)
- [Supervisor Service Supported Input Parameters and Day 2 Alternations](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/using-harbor-as-vcf-service/using-harbor-as-a-vcf-service/supervisor-service-supported-input-parameters-and-day-2-alternations.html) (what each value allows after install)

Back to [README](../README.md).
