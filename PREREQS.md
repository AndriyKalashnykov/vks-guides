# Prerequisites

The small command-line tools the other guides use: `curl`, `tar`, `unzip`, `jq`. Do the section
for your OS, then [Check](#check).

## macOS

macOS ships `curl`, `tar` and `unzip`. macOS 26 also has `jq` built in. On older releases, get it
from [Homebrew](https://brew.sh):

```sh
command -v jq >/dev/null 2>&1 || brew install jq
```

## Linux (Debian / Ubuntu)

```sh
sudo apt-get update && sudo apt-get install -y curl tar unzip jq
```

On other distributions, install the same four packages with your package manager.

## Windows

The guides are `bash`/`zsh` blocks, so on Windows they run inside
[WSL 2](https://learn.microsoft.com/windows/wsl/install) with Ubuntu. Inside it, everything is the
Linux path.

1. Open **PowerShell as Administrator** and install WSL with Ubuntu:

   ```powershell
   wsl --install -d Ubuntu
   ```

   **Expect:** the install finishes, possibly asking you to restart Windows. On first start,
   Ubuntu asks for a new Linux username and password.

2. Open **Ubuntu** from the Start menu and run the
   [Linux (Debian / Ubuntu)](#linux-debian--ubuntu) block there. Run every later guide in this
   Ubuntu terminal too.

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
for t in curl tar unzip jq; do
  command -v "$t" >/dev/null 2>&1 && echo "ok       $t" || echo "MISSING  $t"
done
```

**Expect:** four `ok` lines.

## sudo (optional)

The install blocks never ask for a password. When `/usr/local/bin` needs administrator rights
and `sudo` would ask, the tool goes into `~/.local/bin` instead. To have it in `/usr/local/bin`,
give `sudo` your password first, as a block of its own:

```sh
sudo -v
```

## `~/.local/bin` on your PATH

If an install went into `~/.local/bin`, add it to your `PATH` once, then open a new terminal:

```sh
RC="$HOME/.zshrc"; [ -n "$BASH_VERSION" ] && RC="$HOME/.bashrc"
grep -qs '.local/bin' "$RC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
```

On macOS with bash, use `~/.bash_profile` instead of `~/.bashrc`.

Back to [README](README.md).
