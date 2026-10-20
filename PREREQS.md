# Prerequisites

The small command-line tools the other guides use: `curl`, `tar`, `unzip`, `jq`.

## macOS

macOS ships `curl`, `tar` and `unzip`. macOS 26 also has `jq` built in. On older releases, get it
from [Homebrew](https://brew.sh):

```sh
command -v jq >/dev/null 2>&1 || brew install jq
```

## Debian / Ubuntu

```sh
sudo apt-get update && sudo apt-get install -y curl tar unzip jq
```

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
