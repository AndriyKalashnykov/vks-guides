# Install kubectl

> [!NOTE]
> **Official Kubernetes, Broadcom and Apple documentation for this guide**
>
> - [Install and Set Up kubectl on Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
> - [Install and Set Up kubectl on macOS](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/)
> - [Install and Set Up kubectl on Windows](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/)
> - [The Kubernetes CLI Tools for vSphere download package (vsphere-plugin.zip) cannot be downloaded from the Web UI](https://knowledge.broadcom.com/external/article/414343/the-kubernetes-cli-tools-for-vsphere-dow.html) (Broadcom KB 414343: the Supervisor's download links)
> - [Using Intel-based apps on a Mac with Apple silicon](https://support.apple.com/en-us/102527) (Rosetta)

`kubectl` is the Kubernetes command-line tool. Run **one** of the two install blocks:
[From dl.k8s.io](#from-dlk8sio), or [From the Supervisor](#from-the-supervisor-dlk8sio-blocked)
when this machine cannot reach dl.k8s.io. After you log in,
[match it to your cluster's version](LOGIN.md#match-kubectl-to-the-clusters-version-optional).

## Prerequisites

- [curl](PREREQS.md); for [From the Supervisor](#from-the-supervisor-dlk8sio-blocked) also
  [unzip and openssl](PREREQS.md), the Supervisor's IP address or DNS name, and the vCenter CA
  from step 1 of [Create Supervisor context with CA](LOGIN.md#create-supervisor-context-with-ca).

The connections this guide needs, for a firewall (all TCP):

| from | to | port | for |
|---|---|---|---|
| your machine | `dl.k8s.io` | 443 | From dl.k8s.io |
| your machine | vCenter | 443 | From the Supervisor: the vCenter CA ([LOGIN.md](LOGIN.md#create-supervisor-context-with-ca), step 1) |
| your machine | the Supervisor's address | 443 | From the Supervisor |

## From dl.k8s.io

This installs `kubectl`, so that you can type `kubectl` in any terminal. It downloads the official
program, checks that it arrived whole (its SHA-256 checksum) and copies it into `INSTALL_DIR`. If
that folder needs `sudo` and `sudo` would ask for a password, it uses `~/.local/bin` instead (see
[Prerequisites](PREREQS.md#sudo-optional)). On Windows it also adds the folder to your PATH.
Leave `KUBECTL_VERSION` empty for the latest stable release, or set one such as `v1.37.1`.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
KUBECTL_VERSION=""
INSTALL_DIR="/usr/local/bin"

case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=darwin ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
[ -n "$KUBECTL_VERSION" ] || KUBECTL_VERSION="$(curl -fsSL --connect-timeout 20 --speed-time 60 https://dl.k8s.io/release/stable.txt)"
KUBECTL_VERSION="${KUBECTL_VERSION%%+*}"
URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
TMP="$(mktemp -d)"

if [ -z "$OS" ] || [ -z "$ARCH" ] || [ -z "$KUBECTL_VERSION" ]; then
  echo "FAILED: unsupported $(uname -s)/$(uname -m), or dl.k8s.io unreachable"
elif ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$TMP/kubectl" "$URL" \
     || ! SUM="$(curl -fsSL --connect-timeout 20 --speed-time 60 "$URL.sha256")"; then
  echo "FAILED: download of $URL"
elif [ "$( (sha256sum "$TMP/kubectl" 2>/dev/null || shasum -a 256 "$TMP/kubectl") | cut -d' ' -f1)" != "$SUM" ]; then
  echo "FAILED: checksum mismatch for $URL"
else
  if { mkdir -p "$INSTALL_DIR" 2>/dev/null && [ -w "$INSTALL_DIR" ] && install -m 0755 "$TMP/kubectl" "$INSTALL_DIR/kubectl"; } \
     || { sudo -n install -d "$INSTALL_DIR" 2>/dev/null && sudo -n install -m 0755 "$TMP/kubectl" "$INSTALL_DIR/kubectl"; }; then
    DEST="$INSTALL_DIR"
  else
    DEST="$HOME/.local/bin"; mkdir -p "$DEST" && install -m 0755 "$TMP/kubectl" "$DEST/kubectl"
    echo "note: $INSTALL_DIR needs sudo; installed into $DEST"
  fi
  case ":$PATH:" in *":$DEST:"*) ;; *) PATH="$DEST:$PATH"; echo "note: $DEST added to PATH for this terminal only (see PREREQS.md)";; esac
  hash -r 2>/dev/null
  "$DEST/kubectl" version --client
  [ "$(command -v kubectl)" = "$DEST/kubectl" ] || echo "WARNING: 'kubectl' on PATH is $(command -v kubectl)"
fi; rm -rf "$TMP"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$KUBECTL_VERSION = ""                    # empty = latest stable; or e.g. v1.37.1
$INSTALL_DIR = "$env:LOCALAPPDATA\Programs\vks-tools"

$global:LASTEXITCODE = $null
$ARCH = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
if (-not $KUBECTL_VERSION) { $KUBECTL_VERSION = curl.exe -fsSL --connect-timeout 20 --speed-time 60 https://dl.k8s.io/release/stable.txt }
$KUBECTL_VERSION = "$KUBECTL_VERSION".Split('+')[0]   # drop a "+vmware.N" suffix
$URL = "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/windows/$ARCH/kubectl.exe"
$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null

if (-not $KUBECTL_VERSION) {
  "FAILED: unsupported $env:PROCESSOR_ARCHITECTURE, or dl.k8s.io unreachable"
} else {
  curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$TMP\kubectl.exe" $URL
  $SUM = if ($LASTEXITCODE -eq 0) { curl.exe -fsSL --connect-timeout 20 --speed-time 60 "$URL.sha256" }
  if (-not $SUM) {
    "FAILED: download of $URL"
  } elseif ((Get-FileHash -Algorithm SHA256 "$TMP\kubectl.exe").Hash -ne "$SUM".Trim()) {
    "FAILED: checksum mismatch for $URL"
  } else {
    New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
    Copy-Item -Force "$TMP\kubectl.exe" "$INSTALL_DIR\kubectl.exe"
    $USER_PATH = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (("$USER_PATH" -split ';') -notcontains $INSTALL_DIR) {
      $NEW_PATH = @("$USER_PATH".TrimEnd(';'), $INSTALL_DIR) | Where-Object { $_ }
      [Environment]::SetEnvironmentVariable('Path', ($NEW_PATH -join ';'), 'User')
      "note: $INSTALL_DIR added to your PATH"
    }
    if (($env:Path -split ';') -notcontains $INSTALL_DIR) { $env:Path = "$INSTALL_DIR;$env:Path" }
    & "$INSTALL_DIR\kubectl.exe" version --client
    $FOUND = (Get-Command kubectl -ErrorAction SilentlyContinue).Source
    if ($FOUND -ne "$INSTALL_DIR\kubectl.exe") { "WARNING: 'kubectl' on PATH is $FOUND" }
  }
}
Remove-Item -Recurse -Force $TMP
```

</details>

**Expect:** `Client Version: v1.…` and no `FAILED` or `WARNING` line.

**If not:**
- `FAILED: unsupported …, or dl.k8s.io unreachable`: there is no build for this OS/CPU, or this
  machine cannot reach dl.k8s.io. Use [From the Supervisor](#from-the-supervisor-dlk8sio-blocked).
- `FAILED: download …` with a version you set: check that it starts with `v` and that the patch
  exists. [stable-1.37.txt](https://dl.k8s.io/release/stable-1.37.txt) names the newest 1.37 patch;
  for another minor, change the number in the link.
- `FAILED: checksum mismatch …`: the download arrived damaged. Run the block again.
- `note: … added to PATH for this terminal only`: make it permanent with
  [`~/.local/bin` on your PATH](PREREQS.md#localbin-on-your-path).
- `note: … added to your PATH` (Windows): new terminals find `kubectl` from now on; nothing to do.
- `WARNING: 'kubectl' on PATH is …`: another kubectl is found first (on Windows, often Docker
  Desktop's). Remove it, or put `INSTALL_DIR` first in your `PATH`.

## From the Supervisor (dl.k8s.io blocked)

If this machine cannot reach dl.k8s.io, get `kubectl` from the Supervisor instead. This downloads
the Supervisor's tool package, takes `kubectl` out of it and installs it like the block above. It
works for amd64 Linux, macOS and Windows only. This `kubectl` has the Supervisor's version, which
may be too old for your VKS cluster. The download checks the Supervisor's certificate against the
vCenter CA, so first do step 1 of
[Create Supervisor context with CA](LOGIN.md#create-supervisor-context-with-ca), including its
`mv` block (on Linux and macOS it needs only curl, unzip and openssl). On Windows, then trust that
CA with `Import-Certificate -FilePath "$HOME\.kube\vcenter-ca.pem" -CertStoreLocation
Cert:\CurrentUser\Root` and confirm with **Yes**. Set `SUPERVISOR_ENDPOINT` to the Supervisor's IP
address or DNS name.

On Apple silicon this kubectl runs through Rosetta. If you have not installed Rosetta, do it
first: `softwareupdate --install-rosetta --agree-to-license`.

<details>
<summary><b>Linux amd64 (Ubuntu, AlmaLinux, Photon OS), macOS, WSL amd64 (bash or zsh)</b></summary>

```sh
SUPERVISOR_ENDPOINT="10.0.0.10"
SUPERVISOR_CA="$HOME/.kube/vcenter-ca.pem"
INSTALL_DIR="/usr/local/bin"

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)               P=linux-amd64 ;;
  Darwin/x86_64|Darwin/arm64) P=darwin-amd64 ;;
  *)                          P="" ;;
esac
TMP="$(mktemp -d)"

if [ -z "$P" ]; then
  echo "FAILED: no Supervisor kubectl for $(uname -s)/$(uname -m)"
elif [ ! -s "$SUPERVISOR_CA" ]; then
  echo "FAILED: no vCenter CA at $SUPERVISOR_CA (LOGIN.md, Create Supervisor context with CA, step 1)"
elif ! curl -fsS --connect-timeout 20 --speed-time 60 --cacert "$SUPERVISOR_CA" -o "$TMP/p.zip" "https://${SUPERVISOR_ENDPOINT}/wcp/plugin/${P}/vsphere-plugin.zip" \
     || ! unzip -oq "$TMP/p.zip" bin/kubectl -d "$TMP"; then
  echo "FAILED: download from https://${SUPERVISOR_ENDPOINT}"
else
  if { mkdir -p "$INSTALL_DIR" 2>/dev/null && [ -w "$INSTALL_DIR" ] && install -m 0755 "$TMP/bin/kubectl" "$INSTALL_DIR/kubectl"; } \
     || { sudo -n install -d "$INSTALL_DIR" 2>/dev/null && sudo -n install -m 0755 "$TMP/bin/kubectl" "$INSTALL_DIR/kubectl"; }; then
    DEST="$INSTALL_DIR"
  else
    DEST="$HOME/.local/bin"; mkdir -p "$DEST" && install -m 0755 "$TMP/bin/kubectl" "$DEST/kubectl"
    echo "note: $INSTALL_DIR needs sudo; installed into $DEST"
  fi
  case ":$PATH:" in *":$DEST:"*) ;; *) PATH="$DEST:$PATH"; echo "note: $DEST added to PATH for this terminal only (see PREREQS.md)";; esac
  hash -r 2>/dev/null
  "$DEST/kubectl" version --client
  [ "$(command -v kubectl)" = "$DEST/kubectl" ] || echo "WARNING: 'kubectl' on PATH is $(command -v kubectl)"
fi; rm -rf "$TMP"
```

</details>

<details>
<summary><b>Windows (PowerShell), amd64 only</b></summary>

```powershell
$SUPERVISOR_ENDPOINT = "10.0.0.10"       # Supervisor IP or FQDN
$INSTALL_DIR = "$env:LOCALAPPDATA\Programs\vks-tools"

$ProgressPreference = 'SilentlyContinue'
if ([Net.ServicePointManager]::SecurityProtocol -ne 'SystemDefault') { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 'Tls12' }
$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null
try {
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri "https://$SUPERVISOR_ENDPOINT/wcp/plugin/windows-amd64/vsphere-plugin.zip" -OutFile "$TMP\p.zip"
  Expand-Archive -Force -Path "$TMP\p.zip" -DestinationPath "$TMP\p" -ErrorAction SilentlyContinue
} catch { $_.Exception.Message }

if (-not (Test-Path "$TMP\p\bin\kubectl.exe")) {
  "FAILED: download from https://$SUPERVISOR_ENDPOINT"
} else {
  New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
  Copy-Item -Force "$TMP\p\bin\kubectl.exe" "$INSTALL_DIR\kubectl.exe"
  $USER_PATH = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (("$USER_PATH" -split ';') -notcontains $INSTALL_DIR) {
    $NEW_PATH = @("$USER_PATH".TrimEnd(';'), $INSTALL_DIR) | Where-Object { $_ }
    [Environment]::SetEnvironmentVariable('Path', ($NEW_PATH -join ';'), 'User')
    "note: $INSTALL_DIR added to your PATH"
  }
  if (($env:Path -split ';') -notcontains $INSTALL_DIR) { $env:Path = "$INSTALL_DIR;$env:Path" }
  & "$INSTALL_DIR\kubectl.exe" version --client
  $FOUND = (Get-Command kubectl -ErrorAction SilentlyContinue).Source
  if ($FOUND -ne "$INSTALL_DIR\kubectl.exe") { "WARNING: 'kubectl' on PATH is $FOUND" }
}
Remove-Item -Recurse -Force $TMP
```

</details>

**Expect:** `Client Version: v1.…` and no `FAILED` or `WARNING` line.

**If not:**
- `FAILED: no Supervisor kubectl for …` (Linux arm64): the Supervisor has none for this machine.
  Get dl.k8s.io unblocked and use [From dl.k8s.io](#from-dlk8sio).
- `FAILED: no vCenter CA at …`: do step 1 of
  [Create Supervisor context with CA](LOGIN.md#create-supervisor-context-with-ca) first, including
  its `mv` block.
- `FAILED: download from …`: `SUPERVISOR_ENDPOINT` is wrong, or this machine cannot reach the
  Supervisor. The `curl:` or `unzip:` line above it says which (in PowerShell, the message above
  it). `curl: (60)` (PowerShell: `Could not establish trust relationship`): the CA is not the
  vCenter CA, on Windows it is not trusted yet, or the certificate is not for
  `SUPERVISOR_ENDPOINT` (curl says `subject name`): use the Supervisor's DNS name.
  `curl: (77)`: the file at `SUPERVISOR_CA` is not a certificate; do step 1 again.
- `bad CPU type in executable` (Apple silicon): install Rosetta with
  `softwareupdate --install-rosetta --agree-to-license`, then run the block again.
- `note: …` and `WARNING: …` lines: as in [From dl.k8s.io](#from-dlk8sio).

Back to [README](../README.md).
