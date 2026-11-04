# Install the VCF CLI and its plugins

> [!NOTE]
> **Official Broadcom documentation (VCF 9.1.1) for this guide**
>
> - [Installing the VCF CLI](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/installing-and-using-vcf-cli-v9/installing-the-vcf-cli-in-internet-connected-environments/install-the-vcf-cli%283%29.html) (install the downloaded binary)
> - [Installing the VCF CLI in Internet Restricted Environments](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-consumption/latest/consumer-interfaces-in-vcf/installing-and-using-vcf-cli-v9/installing-the-vcf-cli-in-internet-connected-environments/installing-the-vcf-cli-in-internet-restricted-environments%282%29.html) (the download and the plugin bundle)

`vcf` is VMware's command-line tool; you use it to [log in to the Supervisor](LOGIN.md) (the
Kubernetes control plane that vCenter runs when Workload Management is enabled; it holds your
vSphere Namespaces). The plugin bundle adds its other commands (`vcf cluster`, `vcf addon`, …).
Download two files from Broadcom, then run the install block; it needs no internet access.

## Prerequisites

- a Broadcom support account with access to your company's VMware downloads ([Download](#download));
- [tar](PREREQS.md) (Linux, macOS).

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
this variable. This sets it for this terminal and for new ones: it adds one line to `~/.zshrc` or
`~/.bashrc` (`~/.bash_profile` on macOS bash; on Linux bash it also creates `~/.bash_profile` when
there is none of `~/.bash_profile`, `~/.bash_login` and `~/.profile`); on Windows it sets a user environment
variable.

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

If you logged in with `vcf` before these guides, without `KUBECONFIG` set, see
[If you already use kubectl with other clusters](KUBECONFIG.md#if-you-already-use-kubectl-with-other-clusters)
first.

Next: [Log in](LOGIN.md).

Back to [README](../README.md).
