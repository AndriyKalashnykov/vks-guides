# Install the VCF CLI and its plugins

> [!NOTE]
> **Official Broadcom documentation (VCF 9.1.1) for this guide**
>
> - [Installing the VCF CLI](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/installing-and-using-vcf-cli-v9/installing-the-vcf-cli-in-internet-connected-environments/install-the-vcf-cli%283%29.html) (install the downloaded binary)
> - [VCF CLI `context` commands](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/installing-and-using-vcf-cli-v9/command-reference2/system-commands%281%29/context2.html) (how contexts use kubeconfig files)
> - [Connect to the VKS Cluster Control Plane as a Kubernetes Administrator](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/configuring-identity-and-access-for-tkg-service-clusters/connect-to-the-tkg-service-cluster-control-plane-as-a-kubernetes-administrator.html) and [Log in to a VKS Cluster Using vCenter Single Sign-On Credentials](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/configuring-identity-and-access-for-tkg-service-clusters/connecting-to-vsphere-with-tanzu-clusters/connect-to-a-tkg-service-cluster-as-a-vcenter-single-sign-on-user-with-kubectl/log-in-using-credentials.html) (the two ways to log in to a VKS cluster)
> - [Installing the VCF CLI in Internet Restricted Environments](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/installing-and-using-vcf-cli-v9/installing-the-vcf-cli-in-internet-connected-environments/installing-the-vcf-cli-in-internet-restricted-environments%282%29.html) (the download and the plugin bundle)

`vcf` is VMware's command-line tool; you use it to [log in to the Supervisor](LOGIN.md) (the
Kubernetes control plane that vCenter runs when Workload Management is enabled; it holds your
vSphere Namespaces). The plugin bundle adds its other commands (`vcf cluster`, `vcf addon`, …).
Download two files from Broadcom, then run the install block; it needs no internet access.

## Prerequisites

- a Broadcom support account with access to your company's VMware downloads ([Download](#download));
- [tar](PREREQS.md) (Linux, macOS);
- for [the check of your contexts](#what-a-login-creates-and-when-it-matters) only:
  [kubectl](KUBECTL.md) and [jq](PREREQS.md).

The connections this guide needs, for a firewall (all TCP, besides DNS):

| from | to | port | for |
|---|---|---|---|
| your browser | `support.broadcom.com` | 443 | Download |

## Download

You need a Broadcom support account with access to your company's VMware downloads (ask your
vSphere administrator for access, or for the two files). Download both files for your platform:
`Linux_AMD64` (most PCs; `uname -m` prints `x86_64`), `Linux_ARM64`, `Darwin_ARM64` or
`Darwin_AMD64` (macOS), or for Windows PowerShell `Windows_AMD64` or `Windows_ARM64` (`.zip`
instead of `.tar.gz`). In WSL 2, take `Linux_AMD64` (`Linux_ARM64` on an
Arm PC). On a machine without a browser, download them on another one and copy both to
`DOWNLOAD_DIR`.

| file | where to click | direct link |
|---|---|---|
| `VCF-Consumption-CLI-<platform>-9.1.1.0100.25746586.tar.gz` | [My Downloads](https://support.broadcom.com/group/ecx/downloads) → VMware vSphere Foundation → VMware vSphere Foundation 9 → 9.1.1.0100 → **VCF Consumption CLI** | [VCF CLI](https://support.broadcom.com/group/ecx/productfiles?displayGroup=VMware%20vSphere%20Foundation%209&release=9.1.1.0100&os=&servicePk=547810&language=EN&groupId=545612&viewGroup=true) |
| `VCF-Consumption-CLI-PluginBundle-<platform>-9.1.1.0200.25839222.tar.gz` | [My Downloads](https://support.broadcom.com/group/ecx/downloads) → VMware vSphere Foundation → VMware vSphere Foundation 9 → 9.1.1.0200 → **VCF Consumption CLI Plugins** | [VCF CLI plugins](https://support.broadcom.com/group/ecx/productfiles?displayGroup=VMware%20vSphere%20Foundation%209&release=9.1.1.0200&os=&servicePk=548172&language=EN&groupId=545621&viewGroup=true) |

- With a VMware Cloud Foundation account, click VMware Cloud Foundation → VMware Cloud Foundation
  9 instead, then for each file the release whose file names match the table. Until you pick the
  release, the page reads "No data found".
- Tick **"I agree to the Terms and Conditions"**. The checkbox stays greyed out until you open
  both Terms links, and until it is ticked the download icon does nothing.
- Take the row for your platform, not the files without one (`…-Binaries-…`, plain
  `…-PluginBundle-…`, `…-OCI-…`).
- Copy the **SHA2** value of each file (its SHA-256 checksum: 64 letters and digits); the install
  block checks them.
- Take the files whose names contain `9.1.1.0100.25746586` (the CLI) and `9.1.1.0200.25839222`
  (the plugins), the names the install block expects; the two come from different releases. The
  plugins' VKS plugins (`addon`, `cluster`, …) are v3.8.0, for VKS 3.8 (the bundle also carries
v3.7.2).

## Install

This checks the two files you downloaded against their SHA2 values, installs `vcf`, then installs
its plugins from the bundle. If a file does not match, it installs nothing.

1. Copy the block for your OS into a text editor.
2. Paste the two SHA2 values between the quotes on its first two lines.
3. If the files are not in `~/Downloads`, change `DOWNLOAD_DIR` (in WSL, see
   [PREREQS.md](PREREQS.md#wsl-2-with-ubuntu)).
4. Paste the whole block into the terminal. Values you set in the terminal before do not count:
   the block's first lines set them again.

`vcf` goes into `INSTALL_DIR`, or into `~/.local/bin` if that folder needs `sudo` and `sudo` would
ask for a password (see [PREREQS.md](PREREQS.md#sudo-optional)).

`VCF_CLI_SHA256` and `VCF_PLUGINS_SHA256`: the SHA2 values of the two files, from the download page.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VCF_CLI_SHA256=""
VCF_PLUGINS_SHA256=""
DOWNLOAD_DIR="$HOME/Downloads"
INSTALL_DIR="/usr/local/bin"
VCF_CLI_VERSION="9.1.1.0100.25746586"
VCF_PLUGINS_VERSION="9.1.1.0200.25839222"

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)  P=Linux_AMD64 ;;
  Linux/aarch64) P=Linux_ARM64 ;;
  Darwin/arm64)  P=Darwin_ARM64 ;;
  Darwin/x86_64) P=Darwin_AMD64 ;;
  *)             P=unsupported ;;
esac
CLI_TGZ="$DOWNLOAD_DIR/VCF-Consumption-CLI-${P}-${VCF_CLI_VERSION}.tar.gz"
PLUGINS_TGZ="$DOWNLOAD_DIR/VCF-Consumption-CLI-PluginBundle-${P}-${VCF_PLUGINS_VERSION}.tar.gz"
CLI_SUM="$( (sha256sum "$CLI_TGZ" 2>/dev/null || shasum -a 256 "$CLI_TGZ" 2>/dev/null) | cut -d' ' -f1)"
PLUGINS_SUM="$( (sha256sum "$PLUGINS_TGZ" 2>/dev/null || shasum -a 256 "$PLUGINS_TGZ" 2>/dev/null) | cut -d' ' -f1)"
TMP="$(mktemp -d)"

if [ ! -f "$CLI_TGZ" ] || [ ! -f "$PLUGINS_TGZ" ]; then
  [ -f "$CLI_TGZ" ]     || echo "FAILED: not found: $CLI_TGZ"
  [ -f "$PLUGINS_TGZ" ] || echo "FAILED: not found: $PLUGINS_TGZ"
elif [ -z "$VCF_CLI_SHA256" ] || [ -z "$VCF_PLUGINS_SHA256" ]; then
  echo "FAILED: set VCF_CLI_SHA256 and VCF_PLUGINS_SHA256 from the download page"
elif [ "$CLI_SUM" != "$(printf '%s' "$VCF_CLI_SHA256" | tr -d '[:space:]' | tr 'A-F' 'a-f')" ] \
     || [ "$PLUGINS_SUM" != "$(printf '%s' "$VCF_PLUGINS_SHA256" | tr -d '[:space:]' | tr 'A-F' 'a-f')" ]; then
  echo "FAILED: checksum mismatch; nothing installed"
  echo "  CLI     $CLI_SUM"
  echo "  plugins $PLUGINS_SUM"
elif ! tar -xzf "$CLI_TGZ" -C "$TMP" || ! mv "$TMP"/vcf-cli-* "$TMP/vcf" \
     || ! mkdir "$TMP/plugins" || ! tar -xzf "$PLUGINS_TGZ" -C "$TMP/plugins"; then
  echo "FAILED: could not unpack the downloads"
else
  echo "checksums OK"
  if { mkdir -p "$INSTALL_DIR" 2>/dev/null && [ -w "$INSTALL_DIR" ] && install -m 0755 "$TMP/vcf" "$INSTALL_DIR/vcf"; } \
     || { sudo -n install -d "$INSTALL_DIR" 2>/dev/null && sudo -n install -m 0755 "$TMP/vcf" "$INSTALL_DIR/vcf"; }; then
    DEST="$INSTALL_DIR"
  else
    DEST="$HOME/.local/bin"; mkdir -p "$DEST" && install -m 0755 "$TMP/vcf" "$DEST/vcf"
    echo "note: $INSTALL_DIR needs sudo; installed into $DEST"
  fi
  case ":$PATH:" in *":$DEST:"*) ;; *) PATH="$DEST:$PATH"; echo "note: $DEST added to PATH for this terminal only (see PREREQS.md)";; esac
  hash -r 2>/dev/null
  "$DEST/vcf" plugin install all --local-source "$TMP/plugins" || echo "FAILED: plugin install (vcf itself is installed)"
  "$DEST/vcf" version | head -1
  "$DEST/vcf" plugin list
  [ "$(command -v vcf)" = "$DEST/vcf" ] || echo "WARNING: 'vcf' on PATH is $(command -v vcf)"
fi; rm -rf "$TMP"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VCF_CLI_SHA256 = ""                     # SHA2 of the CLI file from the download page
$VCF_PLUGINS_SHA256 = ""                 # SHA2 of the plugin bundle from the download page
$DOWNLOAD_DIR = "$HOME\Downloads"
$INSTALL_DIR = "$env:LOCALAPPDATA\Programs\vks-tools"
$VCF_CLI_VERSION = "9.1.1.0100.25746586"
$VCF_PLUGINS_VERSION = "9.1.1.0200.25839222"

$global:LASTEXITCODE = $null
$P = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'Windows_ARM64' } else { 'Windows_AMD64' }
$CLI_ZIP = "$DOWNLOAD_DIR\VCF-Consumption-CLI-$P-$VCF_CLI_VERSION.zip"
$PLUGINS_ZIP = "$DOWNLOAD_DIR\VCF-Consumption-CLI-PluginBundle-$P-$VCF_PLUGINS_VERSION.zip"
$CLI_SUM = if (Test-Path $CLI_ZIP) { (Get-FileHash -Algorithm SHA256 $CLI_ZIP).Hash.ToLower() }
$PLUGINS_SUM = if (Test-Path $PLUGINS_ZIP) { (Get-FileHash -Algorithm SHA256 $PLUGINS_ZIP).Hash.ToLower() }
$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null

if (-not $CLI_SUM -or -not $PLUGINS_SUM) {
  if (-not $CLI_SUM) { "FAILED: not found: $CLI_ZIP" }
  if (-not $PLUGINS_SUM) { "FAILED: not found: $PLUGINS_ZIP" }
} elseif (-not $VCF_CLI_SHA256 -or -not $VCF_PLUGINS_SHA256) {
  "FAILED: set VCF_CLI_SHA256 and VCF_PLUGINS_SHA256 from the download page"
} elseif ($CLI_SUM -ne $VCF_CLI_SHA256.Trim() -or $PLUGINS_SUM -ne $VCF_PLUGINS_SHA256.Trim()) {
  "FAILED: checksum mismatch; nothing installed"
  "  CLI     $CLI_SUM"
  "  plugins $PLUGINS_SUM"
} else {
  Expand-Archive -Force -Path $CLI_ZIP -DestinationPath "$TMP\cli" -ErrorAction SilentlyContinue
  Expand-Archive -Force -Path $PLUGINS_ZIP -DestinationPath "$TMP\plugins" -ErrorAction SilentlyContinue
  $EXE = Get-ChildItem -Recurse -Path "$TMP\cli" -Filter 'vcf-cli-*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $EXE -or -not (Test-Path "$TMP\plugins\*")) {
    "FAILED: could not unpack the downloads"
  } else {
    "checksums OK"
    New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
    Copy-Item -Force $EXE.FullName "$INSTALL_DIR\vcf.exe"
    $USER_PATH = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (("$USER_PATH" -split ';') -notcontains $INSTALL_DIR) {
      $NEW_PATH = @("$USER_PATH".TrimEnd(';'), $INSTALL_DIR) | Where-Object { $_ }
      [Environment]::SetEnvironmentVariable('Path', ($NEW_PATH -join ';'), 'User')
      "note: $INSTALL_DIR added to your PATH"
    }
    if (($env:Path -split ';') -notcontains $INSTALL_DIR) { $env:Path = "$INSTALL_DIR;$env:Path" }
    & "$INSTALL_DIR\vcf.exe" plugin install all --local-source "$TMP\plugins"
    if ($LASTEXITCODE -ne 0) { "FAILED: plugin install (vcf itself is installed)" }
    & "$INSTALL_DIR\vcf.exe" version | Select-Object -First 1
    & "$INSTALL_DIR\vcf.exe" plugin list
    $FOUND = (Get-Command vcf -ErrorAction SilentlyContinue).Source
    if ($FOUND -ne "$INSTALL_DIR\vcf.exe") { "WARNING: 'vcf' on PATH is $FOUND" }
  }
}
Remove-Item -Recurse -Force $TMP
```

</details>

**Expect:** `checksums OK`, `Initialization done!` (first run only), `Installing plugin …` lines,
`version: v9.1.1.0100.25746586`, then the plugins, each `installed` (`addon`, `cluster`,
`kubernetes-release`, `package` and `registry-secret` at `v3.8.0`), and no `FAILED` or `WARNING` line.
Lines about the `essential plugins` or `telemetry:v9.0.2` are harmless; the next section stops them.

**If not:**
- `FAILED: not found: …`: the file is not in `DOWNLOAD_DIR`, or it is from another release
  (download the file with the name in the `FAILED` line). `unsupported` in the name means there is no VCF CLI build for
  this OS/CPU.
- `FAILED: set VCF_CLI_SHA256 …`: copy both SHA2 values from the download page into the block.
- `FAILED: checksum mismatch; nothing installed`: compare the printed values with the page. If
  you copied them right, the file is damaged: delete it and download it again.
- `FAILED: could not unpack the downloads`: a download is incomplete. Download it again.
- `FAILED: plugin install`: `vcf` works without its plugins; the error above it says why the
  plugins failed. Run the block again once fixed.
- `note: … added to PATH for this terminal only`: make it permanent with
  [`~/.local/bin` on your PATH](PREREQS.md#localbin-on-your-path).
- `note: … added to your PATH` (Windows): new terminals find `vcf` from now on; nothing to do.
- `WARNING: 'vcf' on PATH is …`: another `vcf` (the path in that line) is found first. Delete that
  file, or put `INSTALL_DIR` first in your `PATH`.

## Stop the essentials message

Once `vcf` has been used on a machine, every command may first print `The vcf cli essential
plugins have not been installed …` and `Failed to install plugin 'telemetry:v9.0.2'`: `vcf` looks
online for a plugin version Broadcom has not published. The command still runs. Setting
`VCF_CLI_ESSENTIALS_PLUGIN_GROUP_VERSION` to `v9.1.1` stops the lookup; Broadcom does not document
this variable. This sets it for this terminal and for new ones.

**Linux, macOS, WSL (bash or zsh):**

```sh
case "$(uname -s)/${BASH_VERSION:+bash}" in
  Darwin/bash) RC="$HOME/.bash_profile" ;;
  */bash)      RC="$HOME/.bashrc" ;;
  *)           RC="$HOME/.zshrc" ;;
esac
grep -qs 'VCF_CLI_ESSENTIALS_PLUGIN_GROUP_VERSION' "$RC" \
  || echo 'export VCF_CLI_ESSENTIALS_PLUGIN_GROUP_VERSION=v9.1.1' >> "$RC"
if [ "$RC" = "$HOME/.bashrc" ]; then
  [ -f "$HOME/.bash_profile" ] || [ -f "$HOME/.bash_login" ] || [ -f "$HOME/.profile" ] \
    || echo '[ -f ~/.bashrc ] && . ~/.bashrc' > "$HOME/.bash_profile"
fi
export VCF_CLI_ESSENTIALS_PLUGIN_GROUP_VERSION=v9.1.1
echo "set in $RC"
vcf plugin list
```

**Windows (PowerShell):**

```powershell
[Environment]::SetEnvironmentVariable('VCF_CLI_ESSENTIALS_PLUGIN_GROUP_VERSION', 'v9.1.1', 'User')
$env:VCF_CLI_ESSENTIALS_PLUGIN_GROUP_VERSION = 'v9.1.1'
"set for your Windows user"
vcf plugin list
```

**Expect:** `set in …` (or `set for your Windows user`), then the plugins, each `installed`, with
no `essential plugins` or `telemetry:v9.0.2` line before them.

**If not:** the lines still appear in a terminal opened before this block: close it; terminals
opened after it have the setting.

## How `vcf` and `kubectl` keep your logins

**In short:** run the blocks as written. They use file and context names these guides chose, not
names `vcf` requires (see [what `vcf` does by
default](#what-vcf-does-by-default-and-what-these-guides-do)). Keep a VKS cluster's administrator
kubeconfig private: anyone with a copy administers that cluster.

### The words used here

| word | what it is |
|---|---|
| kubeconfig | a file that tells `kubectl` (the Kubernetes command-line tool, [KUBECTL.md](KUBECTL.md)) and other Kubernetes tools which server to talk to and how to log in: the server's address and certificate, and your login (for the Supervisor a *token*, a temporary key) |
| cluster, user (in a kubeconfig) | two kinds of entry in a kubeconfig: a *cluster* is a server's address and certificate, a *user* is a stored login (a token or a certificate). Not a vSphere cluster and not an SSO user |
| context | an entry in a kubeconfig that pairs one cluster with one user: "this server, as this login". One kubeconfig can hold several; its *current-context* is the one `kubectl` uses when a command does not name one |
| `~/.kube/config` | the kubeconfig `kubectl` uses when nothing else is named (Windows: `%USERPROFILE%\.kube\config`) |
| `KUBECONFIG` | an environment variable naming the kubeconfig to use instead (several files: separated by `:`, on Windows `;`). A command's `--kubeconfig <file>` overrides it |
| `config.yaml` | the VCF CLI's own list of your saved logins (`~/.config/vcf/config.yaml`; Windows: `%USERPROFILE%\.config\vcf\config.yaml`). `kubectl` never reads it, and you never edit it |
| `vcf` context | an entry in `config.yaml`: a name, the kubeconfig file it uses and a context in that file. Its *currentContext* is the one `vcf` commands use. `vcf context use` sets both that and the kubeconfig's current-context |

```mermaid
%%{init: {"flowchart": {"htmlLabels": false, "wrappingWidth": 600}}}%%
flowchart TB
  vcf["vcf commands"] -- reads --> CFG["~/.config/vcf/config.yaml<br/>your saved logins"]
  CFG -- "names the file" --> KC["a kubeconfig file"]
  vcf -- "writes your login" --> KC
  kubectl["kubectl"] -- reads --> KC
  KC -- "address and login" --> S["the server:<br/>Supervisor or VKS cluster"]
```

When you log in, `vcf` writes your login into a kubeconfig, so `kubectl` works afterwards, and
saves in `config.yaml` which file it used. `kubectl` reads only the kubeconfig.

<a id="why-the-supervisor-and-each-vks-cluster-have-their-own-kubeconfig"></a>

### Two servers, two logins

The Supervisor and a VKS cluster are two different Kubernetes servers (each an address `kubectl`
sends commands to), each with its own logins. This is how VKS works:

| | Supervisor | VKS cluster |
|---|---|---|
| what you work with there | what is in your vSphere Namespace: VKS clusters, VMs, and Supervisor Services such as ArgoCD (add-ons a vCenter administrator installs on the Supervisor) | your apps |
| how you can log in | your vCenter SSO account, with your permission on each vSphere Namespace (Can view, Can edit or Owner) | your vCenter SSO account through the Supervisor, or the cluster's administrator certificate, which the cluster keeps on the Supervisor |
| how long the login lasts | about 10 hours; then you renew it (log in again: [Renew the Supervisor login](LOGIN.md#renew-the-supervisor-login)) | the administrator certificate: about a year from when the cluster made it (so 6 to 12 months from when you got the file), whatever happens to your SSO account |

These guides use the administrator certificate for VKS clusters
([Get the VKS cluster's kubeconfig](LOGIN.md#get-the-vks-clusters-kubeconfig)): it needs no extra
login and does not end in the middle of a block. Anyone with a copy of that file is the cluster's
administrator, and anyone with **Can edit** on the vSphere Namespace can read it. A copy cannot be
withdrawn: it works until the certificate expires or the cluster is deleted, even after its holder
loses their permission on the vSphere Namespace. Keep it private.

To log in to a VKS cluster as your own SSO user instead, see Broadcom's
[Log in to a VKS Cluster Using vCenter SSO Credentials](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/configuring-identity-and-access-for-tkg-service-clusters/connecting-to-vsphere-with-tanzu-clusters/connect-to-a-tkg-service-cluster-as-a-vcenter-single-sign-on-user-with-kubectl/log-in-using-credentials.html)
and the steps in [ACCESS.md](ACCESS.md#the-persons-own-sso-account). That login loses its rights
when your permission is removed.

### What `vcf` does by default, and what these guides do

Where `vcf` writes a login is how `vcf` itself works. The file names, the context names and the
separate files are these guides' choice:

| | `vcf` and `kubectl` by default | these guides |
|---|---|---|
| where a Supervisor login is written | into the file `KUBECONFIG` names (with several files, the first one that exists), or into `~/.kube/config` when it is not set | `~/.kube/supervisor.kubeconfig`: [LOGIN.md](LOGIN.md) sets `KUBECONFIG` to it for the login and for each renewal |
| the login to a VKS cluster | your SSO account: `vcf cluster kubeconfig get` adds entries to your default kubeconfig that sign you in through the Supervisor | the cluster's administrator certificate, read from the Supervisor with `kubectl`, in `~/.kube/<cluster>.kubeconfig`, a file of its own for each cluster |
| the `vcf` context names | no default: you choose a name when you log in (`vcf context create <name>`), and `vcf` adds `<name>:<namespace>` for each vSphere Namespace you can see | `supervisor`, and `supervisor:<namespace>` |
| which file `kubectl` uses | `KUBECONFIG`, or `~/.kube/config` | the file named on each command with `kubectl`'s standard `--kubeconfig <file>` option, or `KUBECONFIG` set for one terminal ([Make it the default in this terminal](LOGIN.md#make-it-the-default-in-this-terminal)) |

```mermaid
%%{init: {"flowchart": {"htmlLabels": false, "wrappingWidth": 600}}}%%
flowchart TB
  subgraph guides["these guides: one file per server (names are the guides' choice)"]
    gk["kubectl --kubeconfig FILE"] --> gs["~/.kube/supervisor.kubeconfig<br/>your SSO login, about 10 hours"]
    gk --> gc["~/.kube/my-vks-cluster.kubeconfig<br/>the administrator certificate, about a year"]
  end
  subgraph def["vcf's default: one file"]
    dk["kubectl"] --> df["~/.kube/config<br/>the Supervisor, VKS clusters, your other clusters<br/>its current-context decides the server"]
  end
```

Why separate files:

- each command names the server it acts on, so an app meant for the VKS cluster does not end up on
  the Supervisor by mistake (with **Can edit** on the vSphere Namespace you can run apps there too,
  as vSphere Pods, containers that run directly on the ESXi hosts, if your Supervisor's setup
  supports them);
- renewing or ending the Supervisor login leaves the VKS cluster files as they are, and deleting a
  VKS cluster file changes nothing else;
- your own `~/.kube/config`, if you have one, is not changed.

The cost: every `kubectl` command carries `--kubeconfig <file>`, or you set `KUBECONFIG` for one
terminal. If you use other file names, change them in every block. Do not copy the Supervisor's
contexts, cluster and user into another file (for example with `kubectl config view --flatten`):
renewing updates only `~/.kube/supervisor.kubeconfig`, so a copy answers `Unauthorized` after
about 10 hours. Adding the guides' files at the end of your own `KUBECONFIG` list is fine for
`kubectl`.

Two rules keep these separate files working:

- Log in and renew with `KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"` in front of the command,
  as LOGIN.md does. A renewal (`vcf context refresh`) writes into the file `KUBECONFIG` names and
  uses that file from then on; without `KUBECONFIG=…` in front, the Supervisor's file keeps the old
  token.
- That applies in every terminal: where you ran *Make it the default in this terminal*,
  `KUBECONFIG` names a VKS cluster's file, and where your own `KUBECONFIG` lists several files, a
  login or renewal goes into one of them.

### If you already use kubectl with other clusters

Skip this section if `~/.kube/config` does not exist (`ls ~/.kube/config` reports that it does
not exist). Tools that create other Kubernetes clusters, such as kind, minikube, Docker Desktop and
`aws eks update-kubeconfig`, create it even if you never ran `kubectl` yourself. If that file
exists, it holds your other clusters, and a `vcf` login made without `KUBECONFIG` set goes into it:

| | `KUBECONFIG` not set (`vcf`'s default) | `KUBECONFIG` names a file of its own (these guides) |
|---|---|---|
| log in (`vcf context create`) | adds the Supervisor's contexts, one cluster and one user to `~/.kube/config`; your current-context stays; the whole file is written again (its comments are lost) | writes that file, creating it; `~/.kube/config` is not touched |
| switch (`vcf context use`) | makes the Supervisor the current-context of `~/.kube/config`: `kubectl` without `--kubeconfig`, and your other tools, now talk to the Supervisor | changes only that file |
| renew (`vcf context refresh`) | writes the new login into `~/.kube/config` again | writes only that file |
| log out (`vcf context delete -y`) | removes the Supervisor's contexts, cluster and user; your other clusters stay | changes only that file |

If you logged in with `KUBECONFIG` not set, `kubectl` without `--kubeconfig` may now talk to the
Supervisor instead of your own clusters. The block below saves a copy of `~/.kube/config`, makes
your own context the current one again, and removes the Supervisor's contexts from the file. Run it
in a new terminal, not one where you ran *Make it the default in this terminal*, so that it sees the
same files as your login did.

1. Run the block unchanged: it lists your contexts, then stops at the switch, because
   `my-old-context` does not exist. Nothing is removed.
2. Set `MY_CONTEXT` to your old context from that list and `VCF_CONTEXT` to the name you logged in
   with, and run it again.
3. Log in again as [LOGIN.md](LOGIN.md) shows.

**Linux, macOS, WSL (bash or zsh):**

```sh
VCF_CONTEXT="supervisor"
MY_CONTEXT="my-old-context"

[ ! -f "$HOME/.kube/config" ] || cp -p "$HOME/.kube/config" "$HOME/.kube/config.before-cleanup"
kubectl config get-contexts -o name
kubectl config use-context "$MY_CONTEXT" && vcf context delete "$VCF_CONTEXT" -y
```

**Windows (PowerShell):**

```powershell
$VCF_CONTEXT = "supervisor"
$MY_CONTEXT = "my-old-context"

if (Test-Path "$HOME\.kube\config") { Copy-Item "$HOME\.kube\config" "$HOME\.kube\config.before-cleanup" }
kubectl config get-contexts -o name
kubectl config use-context $MY_CONTEXT
if ($LASTEXITCODE -eq 0) { vcf context delete $VCF_CONTEXT -y }
```

**Expect:** your contexts and the Supervisor's, then `Switched to context "<yours>".`, one
`[i] Deleting kubeconfig context …` line per Supervisor context, and
`[ok] Successfully deleted context "<VCF_CONTEXT>"`. `~/.kube/config.before-cleanup` is your file
before this block; the comments it lost at the login are not restored.

**If not:** `no context exists with the name`: set `MY_CONTEXT` to a name from the list (the
Supervisor's are not removed then). `context <VCF_CONTEXT> not found`: set `VCF_CONTEXT` to the
name you logged in with (`vcf context list`).

<a id="what-a-login-creates-and-when-it-matters"></a>

### Messages after a login, and checking your contexts

A Supervisor login as LOGIN.md runs it creates a `vcf` context for the Supervisor and one for each
vSphere Namespace you can see, named `<name>:<namespace>` with the vSphere Namespace's name
(LOGIN.md: `supervisor` and `supervisor:my-namespace`). An administrator also gets one for each
Supervisor Service's own namespace (`svc-…`). All of them are in the same kubeconfig. Messages you
may see:

- `no current context set for type "kubernetes"` from a command such as `vcf cluster list`: a login
  as LOGIN.md runs it does not make a context active; `vcf context use <name>` does.
- `context "<name>" already exists` at login (`supervisor` with LOGIN.md): run
  [Log out](LOGIN.md#log-out), then log in again.
- `failed to discover plugin sources …` from `vcf context use`, with an error exit: `vcf` looks for
  plugins in the Supervisor's registry after it switched, and the switch is done all the same. Check the switch with `kubectl --kubeconfig <the file> config current-context`, not
  with the exit code.
- `Unable to read password from terminal` from `vcf context use`: the login has expired, so it
  asked for the password; the guides run it with `</dev/null` (PowerShell: `$null | vcf context
  use supervisor`) so that it stops instead. Renew the login, then run the block again.

The block below shows your `vcf` contexts, the kubeconfig file each one uses, and the
current-context of each file. It needs `jq` ([PREREQS.md](PREREQS.md)) and `kubectl`
([KUBECTL.md](KUBECTL.md)).

**Linux, macOS, WSL (bash or zsh):**

```sh
vcf context list --wide
vcf context list --wide -o json | jq -r '.[].kubeconfigpath // empty' | sort -u | while IFS= read -r F; do
  if [ -f "$F" ]; then
    echo "$F: current-context $(kubectl --kubeconfig "$F" config current-context 2>&1)"
  else
    echo "$F: missing"
  fi
done
```

**Windows (PowerShell):**

```powershell
vcf context list --wide
$L = vcf context list --wide -o json | Out-String | ConvertFrom-Json
foreach ($F in @($L | Where-Object { $_.kubeconfigpath } | ForEach-Object { $_.kubeconfigpath } | Sort-Object -Unique)) {
  if (Test-Path $F) { "${F}: current-context $(kubectl --kubeconfig $F config current-context 2>&1)" } else { "${F}: missing" }
}
```

**Expect:** a table with the columns `NAME`, `CURRENT`, `TYPE`, `ENDPOINT`, `KUBECONFIGPATH` and
`KUBECONTEXT`, `true` under `CURRENT` for the active context if there is one (all `false` until
`vcf context use`), then one line per kubeconfig file with its current-context.

**If not:** `error: current-context is not set` for a file: no context is selected in it; `vcf
context use <name>` sets one. `missing` for a file: it was deleted; `vcf context delete <name> -y
--skip-delete-kubeconfig-context` removes the contexts that use it, and you can log in again.

### What each `vcf context` command changes

Use this when a kubeconfig changed and you did not expect it.

| command | what changes for you | `config.yaml` (read by `vcf`) | kubeconfig (read by `kubectl`) |
|---|---|---|---|
| `vcf context create <name> --endpoint …` (log in) | you are logged in; no context is active yet | adds `<name>` and its `<name>:<namespace>` contexts, recording the kubeconfig file; does not make one active (unless you add `--set-current`) | adds their contexts, cluster and user to the file `KUBECONFIG` names (with several files, the first one that exists; `~/.kube/config` when it is not set), creating it if missing, and writes that whole file again (its comments are lost); its current-context stays |
| `vcf context refresh <name>` (renew) | the login is renewed | records the file `KUBECONFIG` names as the login's file from then on | writes the new login into the file `KUBECONFIG` names, not into the file recorded before |
| `vcf context create <name> --kubeconfig F --kubecontext C` | `vcf` can use a context that already exists in a kubeconfig; no login | adds `<name>`, recording `F` and `C` (give `F` as a full path) | none |
| `vcf context use <name>` | `<name>` becomes the active context for `vcf`, and for `kubectl` with the recorded file | sets `currentContext` | sets the recorded file's current-context to the recorded context, and writes that whole file again (its comments are lost); `KUBECONFIG` is ignored |
| `vcf context list`, `get` | nothing; they only show | none | none |
| `vcf context unset <name>` | no context is active for `vcf`; `kubectl` is unchanged | clears `currentContext` (the active context only) | none |
| `vcf context delete <name> -y`, for a login or a `--kubeconfig` context | the login and its namespace contexts are gone, from both files | removes `<name>` and its `<name>:<namespace>` contexts | removes their contexts, cluster and user from the recorded file (other entries stay), and clears its current-context if it was one of them |
| `vcf context delete <name>:<namespace> -y` | one namespace context is gone | removes that context | removes only that context |
| `vcf context delete <name> -y --skip-delete-kubeconfig-context` | `vcf` forgets the login; the kubeconfig keeps it (the guides' Log out in LOGIN.md then deletes that file; `vcf` itself does not) | removes `<name>` and its `<name>:<namespace>` contexts | none |

To stop `vcf context use` from changing the kubeconfig, set
`VCF_CLI_SKIP_UPDATE_KUBECONFIG_ON_CONTEXT_USE=true`. Broadcom does not document this variable.

Back to [README](../README.md).
