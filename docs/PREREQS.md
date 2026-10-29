# Prerequisites

> [!NOTE]
> **Official documentation for this guide**
>
> - Ubuntu: [Install and manage packages](https://ubuntu.com/server/docs/how-to/software/package-management/)
> - AlmaLinux 10: Red Hat's [Installing packages](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/managing_software_with_the_dnf_tool/installing-rhel-content#installing-packages)
> - Photon OS 5: [tdnf Commands](https://vmware.github.io/photon/docs-v5/administration-guide/managing-packages-with-tdnf/standard-syntax-for-tndf/commands/)
> - Homebrew: [Installation](https://docs.brew.sh/Installation); jq: [Download jq](https://jqlang.org/download/)
> - Microsoft: [Starting Windows PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/windows-powershell/starting-windows-powershell?view=powershell-5.1), [Install WSL](https://learn.microsoft.com/en-us/windows/wsl/install), [Working across Windows and Linux file systems](https://learn.microsoft.com/en-us/windows/wsl/filesystems)
> - curl: [curl shipped by Microsoft](https://curl.se/windows/microsoft.html) (`curl.exe` in Windows)
> - sudo: [Sudo Manual](https://www.sudo.ws/docs/man/sudo.man/) (`-v`)
> - Docker: [Install on Ubuntu](https://docs.docker.com/engine/install/ubuntu/), [Install on RHEL](https://docs.docker.com/engine/install/rhel/), [Linux post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/), [Install Docker Desktop on Windows](https://docs.docker.com/desktop/setup/install/windows-install/); Photon OS 5: [Docker Containers](https://vmware.github.io/photon/docs-v5/administration-guide/containers/docker-containers/); Colima: [README](https://github.com/abiosoft/colima)
> - Podman: [Podman Installation](https://podman.io/docs/installation), [Podman for Windows](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-for-windows.md)

The small command-line tools the other guides use: `curl`, `tar`, `unzip`, `jq`, `openssl`. Do the
section for your OS, then [Check](#check) (Linux, macOS and WSL; PowerShell needs no check).

## Linux (Debian / Ubuntu)

```sh
sudo apt-get update && sudo apt-get install -y curl tar unzip jq openssl
```

On other distributions (except AlmaLinux and Photon OS, below), install the same five packages
with your package manager.

## AlmaLinux 10

AlmaLinux is a free rebuild of Red Hat Enterprise Linux (RHEL). Its blocks here and in the other
guides use RHEL's own tools (`dnf`, Docker's RHEL repository), so they also fit RHEL 10, Rocky
Linux 10 and CentOS Stream 10; they were run on AlmaLinux only.

```sh
sudo dnf install -y curl tar unzip jq openssl
```

**Expect:** `Complete!`. Then run [Check](#check).

**If not:** `sudo: command not found` or `… is not in the sudoers file`: run it as `root`, without
`sudo`.

## Photon OS 5

This refreshes the package list and installs the tools the guides use, plus basic tools Photon OS
lacks by default (`coreutils`, `findutils`, `gawk`, `diffutils`, `sed`, `grep`). Keep
`openssh openssh-socket` in the line: without them the machine stops accepting SSH logins.

```sh
sudo tdnf clean all && sudo tdnf makecache && sudo tdnf install -y ca-certificates curl tar unzip jq openssl coreutils findutils gawk diffutils sed grep openssh openssh-socket
```

**Expect:** the prompt returns with no `Error` line (`Nothing to do.` when all are installed).
Then run [Check](#check).

**If not:**
- `sudo: command not found`: run it as `root`, without `sudo`.
- SSH as `root`, or `ssh -L` port forwarding, stops working: the updated SSH server refuses both
  when you never changed `/etc/ssh/sshd_config`. Log in as another user, or set
  `PermitRootLogin` and `AllowTcpForwarding` there as you need and run
  `sudo systemctl restart sshd`.

## macOS

macOS ships `curl`, `tar`, `unzip` and `openssl`, and recent releases also ship `jq`. This
installs `jq` with [Homebrew](https://brew.sh) only when it is missing:

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
   not in Ubuntu's `~/Downloads`. Print its path inside Ubuntu:

   ```sh
   WIN_DOWNLOADS="$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")/Downloads"
   ls -d "$WIN_DOWNLOADS"
   ```

   **Expect:** a path like `/mnt/c/Users/<you>/Downloads`. Use it as `DOWNLOAD_DIR` in
   [Install the VCF CLI](VCF.md).

## Check

This checks that each tool the guides use is installed and prints `ok` or `MISSING` for each.

```sh
for t in curl tar unzip jq openssl tr awk diff find; do
  command -v "$t" >/dev/null 2>&1 && echo "ok       $t" || echo "MISSING  $t"
done
```

**Expect:** nine `ok` lines.

## sudo (optional)

The kubectl and VCF CLI install blocks never ask for a password. When `/usr/local/bin` needs
administrator rights and `sudo` would ask, the tool goes into `~/.local/bin` instead. To have it
in `/usr/local/bin`, give `sudo` your password first, as a block of its own:

```sh
sudo -v
```

**Expect:** a new prompt, after your password if `sudo` asks for it. Run the install block in this
terminal soon after.

**If not:** `… is not in the sudoers file`: skip this; the install uses `~/.local/bin`.

## `~/.local/bin` on your PATH

If an install printed `note: …/.local/bin added to PATH for this terminal only`, new terminals do
not find the tool yet. This adds `~/.local/bin` to `PATH`, the list of folders your shell searches
for commands, in your shell's startup file (`~/.zshrc`, `~/.bashrc` or `~/.bash_profile`):

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

Only for [IMAGE.md](IMAGE.md), where you build an image and push it to Harbor. Install one or both
for your OS, then run [Check podman and docker](#check-podman-and-docker). Use docker 29.5 or
newer: docker 29.0 to 29.4 does not trust Harbor's CA when it pushes. Ubuntu's own `docker.io` is
29.1, so these blocks install Docker's own packages.

The `docker` group gives its members the same rights as `root` on that machine. Adding your user to
it lets you run `docker` without `sudo`, after you log out and back in.

### podman and docker on Debian / Ubuntu

podman:

```sh
sudo apt-get update && sudo apt-get install -y podman
```

docker: this installs Docker's own packages from Docker's repository (Ubuntu's own is too old).
It first removes Ubuntu's docker packages if you have them, and at the end adds you to the
`docker` group:

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

podman:

```sh
sudo dnf install -y podman
```

docker: this adds Docker's own repository (AlmaLinux has no docker package), installs and starts
docker, and adds you to the `docker` group:

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

docker only: podman cannot run without `root` on Photon OS. This installs and starts docker and
adds you to the `docker` group. Keep `openssh openssh-socket` in the line: without them the
machine stops accepting SSH logins.

```sh
sudo tdnf install -y docker openssh openssh-socket && sudo usermod -aG docker "$USER" && sudo systemctl enable --now docker && echo "docker installed: log out and back in"
```

**Expect:** `docker installed: log out and back in`.

### podman and docker on macOS

podman: on macOS it runs containers in a small Linux virtual machine. This installs podman, then
creates and starts that machine if it is not there or not running:

```sh
brew install podman
podman machine inspect >/dev/null 2>&1 || podman machine init
podman info >/dev/null 2>&1 || podman machine start
```

**Expect:** the last lines say the machine `started successfully`, or nothing if it was already
running.

docker, with [Colima](https://github.com/abiosoft/colima), which runs docker in a small Linux
virtual machine (Docker Desktop also works; larger companies need a paid subscription for it).
This installs Colima, docker and its build plugin, starts Colima, and points docker at it:

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
  **Windows PowerShell** and run the block below. It creates and starts podman's Linux virtual
  machine, where your containers run.
- docker: install [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)
  and start it. Larger companies need a paid subscription for it.

```powershell
podman machine init
podman machine start
```

**Expect:** `Machine "podman-machine-default" started successfully`.

### Check podman and docker

This shows, for podman and docker, whether each is installed and running, and its version.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

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

Back to [README](../README.md).
