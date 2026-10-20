# Install the VCF CLI and its plugins

`vcf` is VMware's command-line tool; you use it to log in to the Supervisor. The plugin bundle
adds its other commands (`vcf cluster`, `vcf package`, …). The block installs both from files you
download, with no internet access needed at install time.

## Download

You need a Broadcom support account. Download both files for your platform (`Linux_AMD64`,
`Linux_ARM64`, `Darwin_ARM64` or `Darwin_AMD64`) into `~/Downloads`.

| file | where |
|---|---|
| `VCF-Consumption-CLI-<platform>-9.1.1.0100.25746586.tar.gz` | [VCF Consumption CLI](https://support.broadcom.com/group/ecx/productfiles?displayGroup=VMware%20vSphere%20Foundation%209&release=9.1.1.0100&os=&servicePk=547810&language=EN&groupId=545612&viewGroup=true) |
| `VCF-Consumption-CLI-PluginBundle-<platform>-9.1.1.0100.25793136.tar.gz` | [VCF Consumption CLI Plugins](https://support.broadcom.com/group/ecx/productfiles?displayGroup=VMware%20vSphere%20Foundation%209&release=9.1.1.0100&os=&servicePk=548172&language=EN&groupId=545621&viewGroup=true) |

Without the direct links: [My Downloads](https://support.broadcom.com/group/ecx/downloads) →
VMware vSphere Foundation → VMware vSphere Foundation 9 → 9.1.1.0100.

- Pick the release first; until you do, the page reads "No data found".
- Tick **"I agree to the Terms and Conditions"**. The checkbox stays greyed out until you open
  both Terms links, and until it is ticked the download icon does nothing.
- Take the row for your platform, not the multi-GB bundles without a platform.
- Note the **SHA2** value of each file; the block prints the checksums to compare.

## Install

Edit the variables at the top if your release, build numbers or download folder differ, then
paste the whole block. It installs `vcf` into `INSTALL_DIR`, or into `~/.local/bin` when that
needs `sudo` and `sudo` would ask for a password (see [PREREQS.md](PREREQS.md#sudo-optional)).

```sh
VCF_RELEASE="9.1.1.0100"
VCF_CLI_BUILD="25746586"
VCF_PLUGINS_BUILD="25793136"
DOWNLOAD_DIR="$HOME/Downloads"   # Windows (WSL): your Windows Downloads folder, see PREREQS.md
INSTALL_DIR="/usr/local/bin"

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)  P=Linux_AMD64 ;;
  Linux/aarch64) P=Linux_ARM64 ;;
  Darwin/arm64)  P=Darwin_ARM64 ;;
  Darwin/x86_64) P=Darwin_AMD64 ;;
  *)             P=unsupported ;;
esac
CLI_TGZ="$DOWNLOAD_DIR/VCF-Consumption-CLI-${P}-${VCF_RELEASE}.${VCF_CLI_BUILD}.tar.gz"
PLUGINS_TGZ="$DOWNLOAD_DIR/VCF-Consumption-CLI-PluginBundle-${P}-${VCF_RELEASE}.${VCF_PLUGINS_BUILD}.tar.gz"
TMP="$(mktemp -d)"

if [ ! -f "$CLI_TGZ" ] || [ ! -f "$PLUGINS_TGZ" ]; then
  [ -f "$CLI_TGZ" ]     || echo "FAILED: not found: $CLI_TGZ"
  [ -f "$PLUGINS_TGZ" ] || echo "FAILED: not found: $PLUGINS_TGZ"
elif ! tar -xzf "$CLI_TGZ" -C "$TMP" || ! mv "$TMP"/vcf-cli-* "$TMP/vcf" \
     || ! mkdir "$TMP/plugins" || ! tar -xzf "$PLUGINS_TGZ" -C "$TMP/plugins"; then
  echo "FAILED: could not unpack the downloads"
else
  (sha256sum "$CLI_TGZ" "$PLUGINS_TGZ" 2>/dev/null || shasum -a 256 "$CLI_TGZ" "$PLUGINS_TGZ")
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
fi
rm -rf "$TMP"
```

**Expect:** two checksum lines matching the **SHA2** values on the download page, then
`version: v9.1.1.0100.25746586`, then the plugins, each `installed`, and no `FAILED` or `WARNING`
line.

**If not:**
- `FAILED: not found: …`: the file is not in `DOWNLOAD_DIR` or has another name. `unsupported`
  in the name means there is no VCF CLI build for this OS/CPU.
- A checksum that differs from the download page: delete the file, download it again, and do
  not use the installed `vcf` until it matches.
- `WARNING: 'vcf' on PATH is …`: another `vcf` is found first. Remove it, or put `INSTALL_DIR`
  first in your `PATH`.

Back to [README](README.md).
