# Install kubectl

`kubectl` is the Kubernetes command-line tool. Run **one** of the two install blocks:
[From dl.k8s.io](#from-dlk8sio), or [From the Supervisor](#from-the-supervisor-dlk8sio-blocked)
when this machine cannot reach dl.k8s.io. After you log in,
[match it to your cluster's version](LOGIN.md#match-kubectl-to-the-clusters-version).

## From dl.k8s.io

Downloads the official binary, checks its SHA-256 and installs it into `INSTALL_DIR`. When that
directory needs `sudo` and `sudo` would ask for a password, it installs into `~/.local/bin`
instead (see [Prerequisites](PREREQS.md#sudo-optional)).

macOS, Linux, WSL (bash or zsh):

```sh
KUBECTL_VERSION=""               # empty = latest stable; or e.g. v1.33.4
INSTALL_DIR="/usr/local/bin"

case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=darwin ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
[ -n "$KUBECTL_VERSION" ] || KUBECTL_VERSION="$(curl -fsSL --connect-timeout 20 --speed-time 60 https://dl.k8s.io/release/stable.txt)"
KUBECTL_VERSION="${KUBECTL_VERSION%%+*}"     # drop a "+vmware.N" suffix
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
fi
rm -rf "$TMP"
```

Windows (PowerShell):

```powershell
$KUBECTL_VERSION = ""                    # empty = latest stable; or e.g. v1.33.4
$INSTALL_DIR = "$env:LOCALAPPDATA\Programs\vks-tools"

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

**Expect:** `Client Version: v1.…` and no `FAILED` or `WARNING` line.

**If not:**
- `FAILED: unsupported …, or dl.k8s.io unreachable`: there is no build for this OS/CPU, or this
  machine cannot reach dl.k8s.io. Use [From the Supervisor](#from-the-supervisor-dlk8sio-blocked).
- `FAILED: download …` with a version such as `v1.33.4`: that exact patch has no upstream build.
  `curl -fsSL https://dl.k8s.io/release/stable-1.33.txt` prints the newest patch of that minor.
- `FAILED: checksum mismatch …`: the download arrived damaged. Run the block again.
- `note: … added to PATH for this terminal only`: make it permanent with
  [`~/.local/bin` on your PATH](PREREQS.md#localbin-on-your-path).
- `note: … added to your PATH` (Windows): new terminals find `kubectl` from now on; nothing to do.
- `WARNING: 'kubectl' on PATH is …`: another kubectl is found first (on Windows, often Docker
  Desktop's). Remove it, or put `INSTALL_DIR` first in your `PATH`.

## From the Supervisor (dl.k8s.io blocked)

The Supervisor serves its own kubectl, for amd64 Linux, macOS and Windows only (Apple silicon
runs it through Rosetta). It is the Supervisor's version, usually more than one minor version
older than your VKS cluster. The download skips the TLS check (`curl -k`).

macOS, Linux, WSL (bash or zsh):

```sh
SUPERVISOR_ENDPOINT="10.0.0.10"  # Supervisor IP or FQDN
INSTALL_DIR="/usr/local/bin"

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)               P=linux-amd64 ;;
  Darwin/x86_64|Darwin/arm64) P=darwin-amd64 ;;
  *)                          P="" ;;
esac
TMP="$(mktemp -d)"

if [ -z "$P" ]; then
  echo "FAILED: no Supervisor kubectl for $(uname -s)/$(uname -m)"
elif ! curl -fsSk --connect-timeout 20 --speed-time 60 -o "$TMP/p.zip" "https://${SUPERVISOR_ENDPOINT}/wcp/plugin/${P}/vsphere-plugin.zip" \
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
fi
rm -rf "$TMP"
```

Windows (PowerShell), amd64 only:

```powershell
$SUPERVISOR_ENDPOINT = "10.0.0.10"       # Supervisor IP or FQDN
$INSTALL_DIR = "$env:LOCALAPPDATA\Programs\vks-tools"

$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null
curl.exe -fsSk --connect-timeout 20 --speed-time 60 -o "$TMP\p.zip" "https://$SUPERVISOR_ENDPOINT/wcp/plugin/windows-amd64/vsphere-plugin.zip"
if ($LASTEXITCODE -eq 0) { Expand-Archive -Force -Path "$TMP\p.zip" -DestinationPath "$TMP\p" -ErrorAction SilentlyContinue }

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

**Expect:** `Client Version: v1.…` and no `FAILED` or `WARNING` line.

**If not:**
- `FAILED: no Supervisor kubectl for …` (Linux arm64): the Supervisor has none for this machine.
  Get dl.k8s.io unblocked and use [From dl.k8s.io](#from-dlk8sio).
- `FAILED: download from …`: `SUPERVISOR_ENDPOINT` is wrong, or this machine cannot reach the
  Supervisor. The `curl:` or `unzip:` line above it says which (in PowerShell, `curl:` only).
- `bad CPU type in executable` (Apple silicon): install Rosetta with
  `softwareupdate --install-rosetta --agree-to-license`, then run the block again.
- `note: …` and `WARNING: …` lines: as in [From dl.k8s.io](#from-dlk8sio).

Back to [README](README.md).
