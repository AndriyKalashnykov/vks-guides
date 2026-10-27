# Prerequisites

> [!NOTE]
> **Official documentation for this guide**
>
> - Ubuntu: [Install and manage packages](https://ubuntu.com/server/docs/how-to/software/package-management/)
> - Photon OS 5: [tdnf Commands](https://vmware.github.io/photon/docs-v5/administration-guide/managing-packages-with-tdnf/standard-syntax-for-tndf/commands/)
> - Homebrew: [Installation](https://docs.brew.sh/Installation); jq: [Download jq](https://jqlang.org/download/)
> - Microsoft: [Starting Windows PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/windows-powershell/starting-windows-powershell?view=powershell-5.1), [Install WSL](https://learn.microsoft.com/en-us/windows/wsl/install), [Working across Windows and Linux file systems](https://learn.microsoft.com/en-us/windows/wsl/filesystems)
> - curl: [curl shipped by Microsoft](https://curl.se/windows/microsoft.html) (`curl.exe` in Windows)
> - sudo: [Sudo Manual](https://www.sudo.ws/docs/man/sudo.man/) (`-v`)

The small command-line tools the other guides use: `curl`, `tar`, `unzip`, `jq`, `openssl`. Do the
section for your OS, then [Check](#check) (Linux, macOS and WSL; PowerShell needs no check).

## Linux (Debian / Ubuntu)

```sh
sudo apt-get update && sudo apt-get install -y curl tar unzip jq openssl
```

On other distributions (except Photon OS, below), install the same five packages with your
package manager.

## Photon OS 5

Keep `openssh openssh-socket` in the line: without them the machine stops accepting SSH logins.

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

If an install printed `note: …/.local/bin added to PATH for this terminal only`, add it to your
`PATH` once:

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

Back to [README](../README.md).
