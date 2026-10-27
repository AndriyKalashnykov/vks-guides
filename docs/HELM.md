# Install Helm

> [!NOTE]
> **Official Helm documentation for this guide**
>
> - [Installing Helm](https://helm.sh/docs/intro/install/) (from the binary releases)
> - [Helm releases](https://github.com/helm/helm/releases) (versions and checksums)
> - [Helm 3 End of Life](https://helm.sh/blog/helm-v3-end-of-life) (why this guide installs Helm 4)

Helm installs charts, packaged sets of Kubernetes manifests. This downloads the official binary,
checks its SHA-256 and installs it into `INSTALL_DIR`. When that directory needs `sudo` and
`sudo` would ask for a password, it installs into `~/.local/bin` instead (see
[Prerequisites](PREREQS.md#sudo-optional)).

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
HELM_VERSION="v4.3.1"
INSTALL_DIR="/usr/local/bin"

case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=darwin ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
URL="https://get.helm.sh/helm-${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
TMP="$(mktemp -d)"

if [ -z "$OS" ] || [ -z "$ARCH" ]; then
  echo "FAILED: unsupported $(uname -s)/$(uname -m)"
elif ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$TMP/helm.tar.gz" "$URL" \
     || ! SUM="$(curl -fsSL --connect-timeout 20 --speed-time 60 "$URL.sha256sum" | cut -d' ' -f1)" || [ -z "$SUM" ]; then
  echo "FAILED: download of $URL"
elif [ "$( (sha256sum "$TMP/helm.tar.gz" 2>/dev/null || shasum -a 256 "$TMP/helm.tar.gz") | cut -d' ' -f1)" != "$SUM" ]; then
  echo "FAILED: checksum mismatch for $URL"
elif ! tar -xzf "$TMP/helm.tar.gz" -C "$TMP" || [ ! -f "$TMP/$OS-$ARCH/helm" ]; then
  echo "FAILED: no helm in $URL"
else
  if { mkdir -p "$INSTALL_DIR" 2>/dev/null && [ -w "$INSTALL_DIR" ] && install -m 0755 "$TMP/$OS-$ARCH/helm" "$INSTALL_DIR/helm"; } \
     || { sudo -n install -d "$INSTALL_DIR" 2>/dev/null && sudo -n install -m 0755 "$TMP/$OS-$ARCH/helm" "$INSTALL_DIR/helm"; }; then
    DEST="$INSTALL_DIR"
  else
    DEST="$HOME/.local/bin"; mkdir -p "$DEST" && install -m 0755 "$TMP/$OS-$ARCH/helm" "$DEST/helm"
    echo "note: $INSTALL_DIR needs sudo; installed into $DEST"
  fi
  case ":$PATH:" in *":$DEST:"*) ;; *) PATH="$DEST:$PATH"; echo "note: $DEST added to PATH for this terminal only (see PREREQS.md)";; esac
  hash -r 2>/dev/null
  "$DEST/helm" version
  [ "$(command -v helm)" = "$DEST/helm" ] || echo "WARNING: 'helm' on PATH is $(command -v helm)"
fi; rm -rf "$TMP"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$HELM_VERSION = "v4.3.1"
$INSTALL_DIR = "$env:LOCALAPPDATA\Programs\vks-tools"

$global:LASTEXITCODE = $null
$ARCH = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$URL = "https://get.helm.sh/helm-$HELM_VERSION-windows-$ARCH.zip"
$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null

curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$TMP\helm.zip" $URL
$SUM = if ($LASTEXITCODE -eq 0) { "$(curl.exe -fsSL --connect-timeout 20 --speed-time 60 "$URL.sha256sum")".Split(' ')[0] }
if (-not $SUM) {
  "FAILED: download of $URL"
} elseif ((Get-FileHash -Algorithm SHA256 "$TMP\helm.zip").Hash -ne $SUM) {
  "FAILED: checksum mismatch for $URL"
} else {
  Expand-Archive -Force -Path "$TMP\helm.zip" -DestinationPath "$TMP\x" -ErrorAction SilentlyContinue
  if (-not (Test-Path "$TMP\x\windows-$ARCH\helm.exe")) {
    "FAILED: no helm in $URL"
  } else {
    New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
    Copy-Item -Force "$TMP\x\windows-$ARCH\helm.exe" "$INSTALL_DIR\helm.exe"
    $USER_PATH = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (("$USER_PATH" -split ';') -notcontains $INSTALL_DIR) {
      $NEW_PATH = @("$USER_PATH".TrimEnd(';'), $INSTALL_DIR) | Where-Object { $_ }
      [Environment]::SetEnvironmentVariable('Path', ($NEW_PATH -join ';'), 'User')
      "note: $INSTALL_DIR added to your PATH"
    }
    if (($env:Path -split ';') -notcontains $INSTALL_DIR) { $env:Path = "$INSTALL_DIR;$env:Path" }
    & "$INSTALL_DIR\helm.exe" version
    $FOUND = (Get-Command helm -ErrorAction SilentlyContinue).Source
    if ($FOUND -ne "$INSTALL_DIR\helm.exe") { "WARNING: 'helm' on PATH is $FOUND" }
  }
}
Remove-Item -Recurse -Force $TMP
```

</details>

**Expect:** `version.BuildInfo{Version:"v4.3.1", …}` and no `FAILED` or `WARNING` line.

**If not:**
- `FAILED: unsupported …`: there is no Helm build for this OS/CPU.
- `FAILED: download …`: this machine cannot reach get.helm.sh, or `HELM_VERSION` names a release
  that does not exist; [Helm releases](https://github.com/helm/helm/releases) lists them.
- `FAILED: checksum mismatch …`: the download arrived damaged. Run the block again.
- `note: … added to PATH for this terminal only`: make it permanent with
  [`~/.local/bin` on your PATH](PREREQS.md#localbin-on-your-path).
- `note: … added to your PATH` (Windows): new terminals find `helm` from now on; nothing to do.
- `WARNING: 'helm' on PATH is …`: another helm is found first. Remove it, or put `INSTALL_DIR`
  first in your `PATH`.

Back to [README](../README.md).
