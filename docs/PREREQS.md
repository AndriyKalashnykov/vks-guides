# Prerequisites

> [!NOTE]
> **Official documentation for this guide**
>
> - Ubuntu: [Install and manage packages](https://ubuntu.com/server/docs/how-to/software/package-management/)
> - AlmaLinux 10: Red Hat's [Installing packages](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/managing_software_with_the_dnf_tool/installing-rhel-content#installing-packages)
> - Photon OS 5: [tdnf Commands](https://vmware.github.io/photon/docs-v5/administration-guide/managing-packages-with-tdnf/standard-syntax-for-tndf/commands/)
> - Arch Linux: [pacman](https://wiki.archlinux.org/title/Pacman), [System maintenance](https://wiki.archlinux.org/title/System_maintenance) (why `-Syu`), [Docker](https://wiki.archlinux.org/title/Docker), [Podman](https://wiki.archlinux.org/title/Podman), [Package signing](https://wiki.archlinux.org/title/Pacman/Package_signing)
> - Homebrew: [Installation](https://docs.brew.sh/Installation); jq: [Download jq](https://jqlang.org/download/)
> - Microsoft: [Starting Windows PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/windows-powershell/starting-windows-powershell?view=powershell-5.1), [Install WSL](https://learn.microsoft.com/en-us/windows/wsl/install), [Working across Windows and Linux file systems](https://learn.microsoft.com/en-us/windows/wsl/filesystems)
> - curl: [curl shipped by Microsoft](https://curl.se/windows/microsoft.html) (`curl.exe` in Windows)
> - sudo: [Sudo Manual](https://www.sudo.ws/docs/man/sudo.man/) (`-v`)
> - Docker: [Install on Ubuntu](https://docs.docker.com/engine/install/ubuntu/), [Install on RHEL](https://docs.docker.com/engine/install/rhel/), [Linux post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/), [Install Docker Desktop on Windows](https://docs.docker.com/desktop/setup/install/windows-install/); Photon OS 5: [Docker Containers](https://vmware.github.io/photon/docs-v5/administration-guide/containers/docker-containers/); Colima: [README](https://github.com/abiosoft/colima)
> - Podman: [Podman Installation](https://podman.io/docs/installation), [Podman for Windows](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-for-windows.md)

The small command-line tools the other guides' blocks use: `curl`, `tar`, `unzip` (Photon OS:
`bsdtar`), `jq`, `openssl`, on your machine: the laptop, workstation or jump box where you paste
the blocks. Required: do the section for your OS, then run [Check](#check), before
any other guide. The sections marked optional are needed only where a guide says so.

1. The section for your OS: [Linux (Debian / Ubuntu)](#linux-debian--ubuntu),
   [AlmaLinux 10](#almalinux-10), [Photon OS 5](#photon-os-5), [Arch Linux](#arch-linux),
   [macOS](#macos) or [Windows](#windows).
2. [Check](#check).
3. When a guide or an install points you there: [sudo](#sudo-optional),
   [`~/.local/bin` on your PATH](#localbin-on-your-path),
   [podman and docker](#podman-and-docker-optional), [kubelogin](#kubelogin-optional).

[Registry hosts, for a firewall](#registry-hosts-for-a-firewall) lists the hosts a firewall must
also allow for each image registry.

## Linux (Debian / Ubuntu)

Run this once on Debian or Ubuntu: it installs the five tools with apt
(needs `sudo`). Afterwards the other guides' blocks find them.

```sh
sudo apt-get update && sudo apt-get install -y curl tar unzip jq openssl
```

**Expect:** the prompt returns with no `E:` line. Then run [Check](#check).

**If not:** `sudo: command not found`: run it as `root`, without `sudo`.

On other distributions (except AlmaLinux, Photon OS and Arch Linux, below), install the same five
packages with your package manager.

## AlmaLinux 10

AlmaLinux is a free rebuild of Red Hat Enterprise Linux (RHEL). Its blocks here and in the other
guides use RHEL's own tools (`dnf`, Docker's RHEL repository), so they also fit RHEL 10, Rocky
Linux 10 and CentOS Stream 10; they were run on AlmaLinux only.

Run this once on AlmaLinux: it installs the five tools with dnf (needs
`sudo`). Afterwards the other guides' blocks find them.

```sh
sudo dnf install -y curl tar unzip jq openssl
```

**Expect:** `Complete!`. Then run [Check](#check).

**If not:** `sudo: command not found` or `… is not in the sudoers file`: run it as `root`, without
`sudo`.

## Photon OS 5

Run this once on Photon OS 5. This refreshes the package list and installs the tools the guides
use (`libarchive` in place of `unzip`, see below), plus basic tools Photon OS lacks by default
(`coreutils`, `findutils`, `gawk`, `diffutils`, `sed`, `grep`). Afterwards the other guides' blocks
find them. The line can update the SSH server (keep `openssh openssh-socket` in it); its end
restarts it, so new SSH logins work. Keep this session open until a new one logs in.

```sh
sudo tdnf clean all && sudo tdnf makecache && sudo tdnf install -y ca-certificates curl tar libarchive jq openssl coreutils findutils gawk diffutils sed grep openssh openssh-socket && sudo /usr/sbin/sshd -t && sudo systemctl try-restart sshd.service
```

**Expect:** the prompt returns with no `Error` line (`Nothing to do.` when all are installed), and
an `ssh` from a new terminal logs in. Then run [Check](#check).

**If not:**
- `sudo: command not found`: run it as `root`, without `sudo`.
- A new `ssh` gets `kex_exchange_identification: … Connection reset by peer`: in the open session,
  run `sudo /usr/sbin/sshd -t && sudo systemctl try-restart sshd.service`. If `sshd -t` prints an
  error, fix that line in `/etc/ssh/sshd_config` first. Do not close the session.
- SSH as `root`, or `ssh -L` port forwarding, stops working: the updated SSH server refuses both
  when you never changed `/etc/ssh/sshd_config`. Log in as another user, or set
  `PermitRootLogin` and `AllowTcpForwarding` there as you need and run
  `sudo /usr/sbin/sshd -t && sudo systemctl try-restart sshd.service`.

**`libarchive` instead of `unzip`:** Photon OS 5's own package repositories have `unzip`, but
recent Photon OS VMs deployed through a vSphere Namespace's VM Service are set to a shorter package
list from Broadcom, without `unzip`, so `sudo tdnf install -y unzip` can fail there. The guides
unpack zip files with `unzip` where it is installed, and otherwise with `libarchive`'s `bsdtar`,
which gives the same files.

## Arch Linux

Run this once on Arch Linux. This installs the tools with `pacman`.
`-Syu` also upgrades the rest of the system first: Arch Linux does not support installing
packages without that upgrade. Afterwards the five tools are installed and the system is up to
date.

```sh
sudo pacman -Syu --needed --noconfirm curl tar unzip jq openssl
```

**Expect:** `installing …` lines for what was missing, or `… is up to date -- skipping` and
`there is nothing to do`, with no `error:` line. Then run [Check](#check).

**If not:**
- `sudo: command not found`: run it as `root`, without `sudo`.
- `error: … signature from … is unknown trust` or `invalid or corrupted package (PGP signature)`:
  the machine's Arch Linux signing keys are out of date. Run
  `sudo pacman -Sy --needed --noconfirm archlinux-keyring`, then the block again.

## macOS

Run this once on macOS. macOS ships `curl`, `tar`, `unzip` and
`openssl`, and recent releases also ship `jq`. This installs `jq` with [Homebrew](https://brew.sh)
only when it is missing; afterwards all five tools are there:

```sh
command -v jq >/dev/null 2>&1 || brew install jq
```

**If not:** `brew: command not found` — install Homebrew first ([brew.sh](https://brew.sh)), then
run the block again.

## Windows

Pick one:

- **PowerShell**: nothing to install. Windows 10 version 1803 or later, and Windows 11, already
  have what the guides use (`curl.exe`, `Expand-Archive`, `Get-FileHash`). Open **Windows
  PowerShell** from the Start menu (not as Administrator) and, in every later guide, run the
  **Windows (PowerShell)** block where a section has one. The tools go into
  `%LOCALAPPDATA%\Programs\vks-tools`, so no administrator rights are needed.
- **WSL 2 with Ubuntu**: run the Linux blocks in Ubuntu on Windows. Use it if you prefer the same
  blocks as Linux and macOS; it needs administrator rights once, to install WSL.

### WSL 2 with Ubuntu

1. Open **PowerShell as Administrator** and install WSL with Ubuntu. This also turns WSL on if
   Windows does not have it yet; it needs Windows 10 version 2004 or later, or Windows 11.
   When it finishes (restart Windows if it asks), go on with step 2.

   ```powershell
   wsl --install -d Ubuntu
   ```

   **Expect:** the install finishes, possibly asking you to restart Windows. On first start,
   Ubuntu asks for a new Linux username and password.

   **If not:** WSL cannot be turned on — no administrator rights, an older Windows, virtualization
   disabled in the BIOS/UEFI, or blocked by company policy. Use the PowerShell blocks instead.

2. Open **Ubuntu** from the Start menu and run the
   [Linux (Debian / Ubuntu)](#linux-debian--ubuntu) block there. Run every later guide in this
   Ubuntu terminal too, with the `sh` blocks.

3. Files you download in Windows (the VCF CLI tarballs) are in your Windows `Downloads` folder,
   not in Ubuntu's `~/Downloads`. Run this once, before you install the VCF CLI, to find that
   folder from Ubuntu: it prints the folder's path inside Ubuntu and changes nothing:

   ```sh
   WIN_DOWNLOADS="$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")/Downloads"
   ls -d "$WIN_DOWNLOADS"
   ```

   **Expect:** a path like `/mnt/c/Users/<you>/Downloads`. Use it as `DOWNLOAD_DIR` in
   [Install the VCF CLI](VCF.md).

## Check

Run this after your OS's section above, to see which tools are still
missing. This prints `ok` or `MISSING` for each tool the guides use: the ones above, and the ones
the next guides install (`kubectl`, `vcf`, and `helm` for the guides that install apps with Helm).
It changes nothing.

**Linux, macOS, WSL (bash or zsh):**

```sh
for t in curl tar unzip jq openssl tr awk diff find kubectl vcf helm; do
  command -v "$t" >/dev/null 2>&1 || { [ "$t" = unzip ] && command -v bsdtar >/dev/null 2>&1; } \
    && echo "ok       $t" || echo "MISSING  $t"
done
```

**Windows (PowerShell):**

```powershell
foreach ($t in 'curl.exe', 'tar.exe', 'kubectl', 'vcf', 'helm') {
  if (Get-Command $t -ErrorAction SilentlyContinue) { "ok       $t" } else { "MISSING  $t" }
}
```

**Expect:** an `ok` line for each tool, except the ones you have not installed yet.

**If not:** for a `MISSING` tool from the first nine, run your OS's block above; for `kubectl`,
[Install kubectl](KUBECTL.md); for `vcf`, [Install the VCF CLI](VCF.md); for `helm`,
[Install Helm](HELM.md), if a guide you follow uses it.

## sudo (optional)

The kubectl and VCF CLI install blocks never ask for a password. When `/usr/local/bin` needs
administrator rights and `sudo` would ask, the tool goes into `~/.local/bin` instead. To have it
in `/usr/local/bin`, give `sudo` your password first, as a block of its own. This makes `sudo`
remember your password for a few minutes and changes nothing else; the kubectl or VCF CLI install
block you run next in this terminal then uses `/usr/local/bin`:

```sh
sudo -v
```

**Expect:** a new prompt, after your password if `sudo` asks for it. Run the install block in this
terminal soon after.

**If not:** `… is not in the sudoers file`: skip this; the install uses `~/.local/bin`.

## `~/.local/bin` on your PATH

If an install printed `note: …/.local/bin added to PATH for this terminal only`, new terminals do
not find the tool yet. This adds `~/.local/bin` to `PATH`, the list of folders your shell searches
for commands, in your shell's startup file (`~/.zshrc`, `~/.bashrc` or `~/.bash_profile`). With
`~/.bashrc`, it also creates `~/.bash_profile` when bash has none of `~/.bash_profile`,
`~/.bash_login` and `~/.profile`, so SSH logins read it. Afterwards every new terminal finds the
tools:

```sh
case "$(uname -s)/${BASH_VERSION:+bash}" in
  Darwin/bash) RC="$HOME/.bash_profile" ;;
  */bash)      RC="$HOME/.bashrc" ;;
  *)           RC="$HOME/.zshrc" ;;
esac
grep -qs '.local/bin' "$RC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
if [ "$RC" = "$HOME/.bashrc" ]; then
  [ -f "$HOME/.bash_profile" ] || [ -f "$HOME/.bash_login" ] || [ -f "$HOME/.profile" ] \
    || echo '[ -f ~/.bashrc ] && . ~/.bashrc' > "$HOME/.bash_profile"
fi
echo "PATH set in $RC"
```

**Expect:** `PATH set in …`. New terminals, including SSH sessions, find the tools.

## podman and docker (optional)

Only for [IMAGE.md](IMAGE.md) (building app images and uploading them to Harbor, the image
registry). Install one or both
for your OS, then run [Check podman and docker](#check-podman-and-docker). Use docker 29.5 or
newer: docker 29.0 to 29.4 does not trust Harbor's CA when it pushes. Ubuntu's own `docker.io` is
29.1, so the Ubuntu and AlmaLinux blocks install Docker's own packages; Arch Linux's own `docker` is
29.5 or newer.

The `docker` group gives its members the same rights as `root` on that machine. Adding your user to
it lets you run `docker` without `sudo`, after you log out and back in.

### podman and docker on Debian / Ubuntu

podman, to build and push images with podman: this installs podman from Ubuntu's or Debian's
packages; then run [Check podman and docker](#check-podman-and-docker).

```sh
sudo apt-get update && sudo apt-get install -y podman
```

docker, to build and push images with docker: Ubuntu's own docker is too old to push to Harbor,
so this installs Docker's own packages from Docker's repository. It first removes Ubuntu's docker
packages if you have them, and at the end adds you to the `docker` group. Afterwards, once you
log out and back in, you run docker without `sudo`:

```sh
D="$(. /etc/os-release && echo "$ID")"
C="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
case "$D" in
  ubuntu|debian)
    for p in docker.io docker-doc docker-compose docker-compose-v2 docker-buildx podman-docker; do
      dpkg -s "$p" >/dev/null 2>&1 && sudo apt-get remove -y "$p"
    done
    sudo apt-get update && sudo apt-get install -y ca-certificates curl \
      && sudo install -m 0755 -d /etc/apt/keyrings \
      && sudo curl -fsSL --connect-timeout 20 --speed-time 60 "https://download.docker.com/linux/${D}/gpg" -o /etc/apt/keyrings/docker.asc \
      && sudo chmod a+r /etc/apt/keyrings/docker.asc \
      && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${D} ${C} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null \
      && sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
      && sudo systemctl reset-failed docker.service docker.socket \
      && sudo systemctl enable --now docker.socket docker.service \
      && sudo usermod -aG docker "$USER" \
      && echo "docker installed: log out and back in"
    ;;
  *) echo "Not Debian or Ubuntu ($D): nothing installed" ;;
esac
```

**Expect:** `docker installed: log out and back in`. Log out and back in, then run
[Check podman and docker](#check-podman-and-docker).

**If not:** `Not Debian or Ubuntu (…)`: follow
[Docker's install pages](https://docs.docker.com/engine/install/) for your distribution.

### podman and docker on AlmaLinux 10

podman, to build and push images with podman: this installs podman from AlmaLinux's own packages;
then run [Check podman and docker](#check-podman-and-docker).

```sh
sudo dnf install -y podman
```

docker, to build and push images with docker: this adds Docker's own repository (AlmaLinux has no
docker package), installs and starts docker, and adds you to the `docker` group. Afterwards, once
you log out and back in, you run docker without `sudo`:

```sh
sudo dnf install -y dnf-plugins-core && sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo && sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin && sudo usermod -aG docker "$USER" && sudo systemctl enable --now docker && echo "docker installed: log out and back in"
```

**Expect:** `Complete!` lines, `Importing GPG key 0x621E9F35` with fingerprint
`060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35`, then
`docker installed: log out and back in`.

**If not:** `Job for docker.service failed`, with `iptables … RULE_APPEND failed` in
`sudo journalctl -u docker`: the install brought kernel modules for a newer kernel than the one
running. Restart the machine; docker then starts by itself.

### podman and docker on Photon OS 5

docker only: podman cannot run without `root` on Photon OS. Run this on Photon OS to build and
push images with docker. This installs and starts docker and adds you to the `docker` group. Like
the line in [Photon OS 5](#photon-os-5), it can update the SSH server and restarts it. Afterwards,
once you log out and back in, you run docker without `sudo`.

```sh
sudo tdnf install -y docker openssh openssh-socket && sudo /usr/sbin/sshd -t && sudo systemctl try-restart sshd.service && sudo usermod -aG docker "$USER" && sudo systemctl enable --now docker && echo "docker installed: log out and back in"
```

**Expect:** `docker installed: log out and back in`. Check that an `ssh` from a new terminal logs
in before you log out.

**If not:** no `docker installed` line, or a new `ssh` is reset: see the SSH lines under **If not**
in [Photon OS 5](#photon-os-5).

### podman and docker on Arch Linux

podman, to build and push images with podman: this installs podman with pacman and upgrades the
system; then run [Check podman and docker](#check-podman-and-docker).

```sh
sudo pacman -Syu --needed --noconfirm podman
```

docker, to build and push images with docker: this installs and starts docker and its build
plugin, and adds you to the `docker` group. Afterwards, once you log out and back in, you run docker
without `sudo`:

```sh
sudo pacman -Syu --needed --noconfirm docker docker-buildx && sudo usermod -aG docker "$USER" && sudo systemctl enable --now docker.socket docker.service && echo "docker installed: log out and back in"
```

**Expect:** `docker installed: log out and back in`. Log out and back in, then run
[Check podman and docker](#check-podman-and-docker).

**If not:** `Job for docker.service failed`, with `upgrading linux` in the output above: the
upgrade brought a new kernel, and docker cannot start on the one still running. Restart the
machine; docker then starts by itself.

### podman and docker on macOS

podman, to build and push images with podman: on macOS it runs containers in a small Linux virtual
machine. This installs podman, then creates and starts that machine if it is not there or not
running. Afterwards the `podman` command uses that machine:

```sh
brew install podman
podman machine inspect >/dev/null 2>&1 || podman machine init
podman info >/dev/null 2>&1 || podman machine start
```

**Expect:** the last lines say the machine `started successfully`, or nothing if it was already
running.

docker, to build and push images with docker: use [Colima](https://github.com/abiosoft/colima),
which runs docker in a small Linux virtual machine (Docker Desktop also works; larger companies
need a paid subscription for it). This installs Colima, docker and its build plugin, starts
Colima, and points docker at it. Afterwards the `docker` command talks to docker in Colima:

```sh
brew install colima docker docker-buildx
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix)/opt/docker-buildx/bin/docker-buildx" ~/.docker/cli-plugins/docker-buildx
colima start
docker context use colima
```

**Expect:** `Current context is now "colima"`.

### podman and docker on Windows

Both run Linux in WSL 2. If you have no WSL yet, install it once in **PowerShell as
Administrator** with `wsl --install --no-distribution`, and restart Windows if it asks.

- podman: download `podman-installer-windows-amd64.msi` from
  [Podman's releases](https://github.com/podman-container-tools/podman/releases), install it, open a new
  **Windows PowerShell** and run the block below.
- docker: install [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)
  and start it. Larger companies need a paid subscription for it. Free instead: Docker CE inside
  WSL 2, with the [Debian / Ubuntu](#podman-and-docker-on-debian--ubuntu) docker block run in
  your WSL Ubuntu; then use docker, and IMAGE.md's Linux blocks, in that Ubuntu.

For podman, run this once in that new Windows PowerShell:
it creates and starts podman's Linux virtual machine, where your containers run. Afterwards the
`podman` command uses that machine:

```powershell
podman machine init
podman machine start
```

**Expect:** `Machine "podman-machine-default" started successfully`.

### Check podman and docker

Run this after you install either engine, and after you log out and back in, to see that it is
ready. This shows, for podman and docker, whether each is installed and running, and its version.
It changes nothing; afterwards you know which engine is ready for IMAGE.md.

**Linux, macOS, WSL (bash or zsh):**

```sh
for e in podman docker; do
  if ! command -v "$e" >/dev/null 2>&1; then
    echo "not installed: $e"
  elif [ "$e" = podman ] && V="$(podman info --format '{{.Version.Version}}' 2>/dev/null)" && [ -n "$V" ]; then
    echo "ok       podman $V"
  elif [ "$e" = docker ] && V="$(docker version --format '{{.Server.Version}}' 2>/dev/null)" && [ -n "$V" ]; then
    echo "ok       docker $V"
  else
    echo "NOT RUNNING: $e (or, for docker, you have not logged out and back in since the install)"
  fi
done
```

**Windows (PowerShell):**

```powershell
foreach ($e in 'podman', 'docker') {
  if (-not (Get-Command "$e.exe" -ErrorAction SilentlyContinue)) { "not installed: $e" }
  else {
    $V = if ($e -eq 'podman') { podman info --format '{{.Version.Version}}' 2>$null } else { docker version --format '{{.Server.Version}}' 2>$null }
    if ($V) { "ok       $e $V" } else { "NOT RUNNING: $e" }
  }
}
```

**Expect:** an `ok` line for each engine you installed: podman 4.9 or newer, docker 29.5 or newer.

**If not:**
- `NOT RUNNING: docker` on Linux: log out and back in (or restart the machine). Still there:
  `sudo systemctl start docker` and read its error.
- `ok docker 29.0` to `29.4`: its push does not trust Harbor's CA; on Ubuntu run the docker block
  above (Docker's own package).
- `ok podman` below 4.9 (Ubuntu 22.04, Debian 12): too old to build and push reliably; use docker,
  or a newer release of your distribution.
- `NOT RUNNING: podman` on macOS or Windows: `podman machine start`.

## kubelogin (optional)

Only for [KEYCLOAK.md](KEYCLOAK.md): run this once for each person who logs in to a VKS
cluster with Keycloak, on the machine they log in from. kubelogin is a kubectl plugin (an extra
command for kubectl) that does that Keycloak login for kubectl. This downloads kubelogin v1.36.4
(`KUBELOGIN_VERSION`) from GitHub, checks it against its published checksum, and installs it as
`kubectl-oidc_login`, the name under which kubectl runs it as `kubectl oidc-login`. Install
[kubectl](KUBECTL.md) first.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
KUBELOGIN_VERSION="v1.36.4"
INSTALL_DIR="$HOME/.local/bin"

case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=darwin ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
URL="https://github.com/int128/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin_${OS}_${ARCH}.zip"
TMP="$(mktemp -d)"
if [ -z "$OS" ] || [ -z "$ARCH" ]; then
  echo "FAILED: unsupported $(uname -s)/$(uname -m)"
elif ! curl -fsSL --connect-timeout 20 --speed-time 60 -o "$TMP/k.zip" "$URL" \
     || ! SUM="$(curl -fsSL --connect-timeout 20 --speed-time 60 "$URL.sha256" | cut -d' ' -f1)"; then
  echo "FAILED: download of $URL"
elif [ "$( (sha256sum "$TMP/k.zip" 2>/dev/null || shasum -a 256 "$TMP/k.zip") | cut -d' ' -f1)" != "$SUM" ]; then
  echo "FAILED: checksum mismatch for $URL"
elif ! command -v unzip >/dev/null 2>&1 && ! command -v bsdtar >/dev/null 2>&1; then
  echo "MISSING: unzip (see the section for your OS above)"
elif ! { if command -v unzip >/dev/null 2>&1 || ! command -v bsdtar >/dev/null 2>&1; then unzip -p "$TMP/k.zip" kubelogin; else bsdtar -xOf "$TMP/k.zip" kubelogin; fi; } > "$TMP/kubectl-oidc_login" \
     || ! chmod 755 "$TMP/kubectl-oidc_login" || ! "$TMP/kubectl-oidc_login" version; then
  echo "FAILED: no working kubelogin in $URL"
else
  mkdir -p "$INSTALL_DIR" && install -m 755 "$TMP/kubectl-oidc_login" "$INSTALL_DIR/kubectl-oidc_login"
  case ":$PATH:" in *":$INSTALL_DIR:"*) ;; *) PATH="$INSTALL_DIR:$PATH"; echo "note: $INSTALL_DIR added to PATH for this terminal only (see below)";; esac
  echo "installed $INSTALL_DIR/kubectl-oidc_login"
fi; rm -rf "$TMP"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$KUBELOGIN_VERSION = "v1.36.4"
$INSTALL_DIR = "$env:LOCALAPPDATA\Programs\vks-tools"

$ARCH = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$URL = "https://github.com/int128/kubelogin/releases/download/$KUBELOGIN_VERSION/kubelogin_windows_$ARCH.zip"
$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null
$global:LASTEXITCODE = $null
curl.exe -fsSL --connect-timeout 20 --speed-time 60 -o "$TMP\k.zip" $URL
$SUM = if ($LASTEXITCODE -eq 0) { "$(curl.exe -fsSL --connect-timeout 20 --speed-time 60 "$URL.sha256")".Split(' ')[0] }
if (-not $SUM) {
  "FAILED: download of $URL"
} elseif ((Get-FileHash -Algorithm SHA256 "$TMP\k.zip").Hash -ne $SUM) {
  "FAILED: checksum mismatch for $URL"
} else {
  Expand-Archive -Path "$TMP\k.zip" -DestinationPath "$TMP\x"
  New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
  Copy-Item -Force "$TMP\x\kubelogin.exe" "$INSTALL_DIR\kubectl-oidc_login.exe"
  $USER_PATH = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (("$USER_PATH" -split ';') -notcontains $INSTALL_DIR) {
    $NEW_PATH = @("$USER_PATH".TrimEnd(';'), $INSTALL_DIR) | Where-Object { $_ }
    [Environment]::SetEnvironmentVariable('Path', ($NEW_PATH -join ';'), 'User')
    "note: $INSTALL_DIR added to your PATH"
  }
  if (($env:Path -split ';') -notcontains $INSTALL_DIR) { $env:Path = "$INSTALL_DIR;$env:Path" }
  $global:LASTEXITCODE = 1
  & "$INSTALL_DIR\kubectl-oidc_login.exe" version
  if ($LASTEXITCODE -eq 0) { "installed $INSTALL_DIR\kubectl-oidc_login.exe" } else { "FAILED: no working kubelogin in $URL" }
}
Remove-Item -Recurse -Force $TMP
```

</details>

**Expect:** `kubelogin version v1.36.4 …` (Windows: `kubelogin version` with no number, as its
build prints it), then `installed …`. `kubectl oidc-login --help` then prints kubelogin's help.

**If not:** `FAILED: download …`: this machine cannot reach `github.com` and
`release-assets.githubusercontent.com` on port 443. `note: … added to PATH for this terminal only`:
see [`~/.local/bin` on your PATH](#localbin-on-your-path).

## Registry hosts, for a firewall

The guides' connection tables name an image registry the way images name it. A registry answers
from more hosts than its name; allow these too (measured, all TCP 443):

| registry in a table | also allow |
|---|---|
| `docker.io` | `registry-1.docker.io`, `auth.docker.io`, `production.cloudfront.docker.com` |
| `ghcr.io` | `pkg-containers.githubusercontent.com` |
| `quay.io` | `cdn01.quay.io` |
| `registry.k8s.io` | `cdn.registry.k8s.io`, and a `*-docker.pkg.dev` host near you (for example `us-east1-docker.pkg.dev`) |
| `cgr.dev` | `*.r2.cloudflarestorage.com` |
| `registry.gitlab.com` | `gitlab.com`, `cdn.registry.gitlab-static.net` |
| `projects.packages.broadcom.com` | nothing else |
| `mcr.microsoft.com` | `*.data.mcr.microsoft.com` (a host near you, for example `eastus.data.mcr.microsoft.com`) |

Back to [README](../README.md).
