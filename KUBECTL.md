# Install kubectl

`kubectl` is the Kubernetes command-line tool. Run **one** of the two install blocks:
[From dl.k8s.io](#from-dlk8sio), or [From the Supervisor](#from-the-supervisor-dlk8sio-blocked)
when this machine cannot reach dl.k8s.io. Kubernetes supports a client within one minor version
of the cluster: once you can reach your cluster,
[match the cluster's version](#match-the-clusters-version).

## From dl.k8s.io

Downloads the official binary, checks its SHA-256 and installs it into `INSTALL_DIR`. When that
directory needs `sudo` and `sudo` would ask for a password, it installs into `~/.local/bin`
instead (see [Prerequisites](PREREQS.md#sudo-optional)).

```sh
KUBECTL_VERSION=""               # empty = latest stable; or e.g. v1.33.4
INSTALL_DIR="/usr/local/bin"

case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=darwin ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
[ -n "$KUBECTL_VERSION" ] || KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
KUBECTL_VERSION="${KUBECTL_VERSION%%+*}"     # drop a "+vmware.N" suffix
URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
TMP="$(mktemp -d)"

if [ -z "$OS" ] || [ -z "$ARCH" ] || [ -z "$KUBECTL_VERSION" ]; then
  echo "FAILED: unsupported $(uname -s)/$(uname -m), or dl.k8s.io unreachable"
elif ! curl -fsSL -o "$TMP/kubectl" "$URL" || ! SUM="$(curl -fsSL "$URL.sha256")"; then
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

**Expect:** `Client Version: v1.…` and no `FAILED` or `WARNING` line.

**If not:**
- `FAILED: unsupported …, or dl.k8s.io unreachable`: there is no build for this OS/CPU, or this
  machine cannot reach dl.k8s.io. Use [From the Supervisor](#from-the-supervisor-dlk8sio-blocked).
- `FAILED: download …` with a version such as `v1.33.4`: that exact patch has no upstream build.
  `curl -fsSL https://dl.k8s.io/release/stable-1.33.txt` prints the newest patch of that minor.
- `FAILED: checksum mismatch …`: the download arrived damaged. Run the block again.
- `note: … added to PATH for this terminal only`: make it permanent with
  [`~/.local/bin` on your PATH](PREREQS.md#localbin-on-your-path).
- `WARNING: 'kubectl' on PATH is …`: another kubectl is found first. Remove it, or put
  `INSTALL_DIR` first in your `PATH`.

## From the Supervisor (dl.k8s.io blocked)

The Supervisor serves its own kubectl, for amd64 Linux and macOS only (Apple silicon runs it
through Rosetta). It is the Supervisor's version, which can be older than your guest cluster.
The download skips the TLS check (`curl -k`).

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
elif ! curl -fsSk -o "$TMP/p.zip" "https://${SUPERVISOR_ENDPOINT}/wcp/plugin/${P}/vsphere-plugin.zip" \
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

**Expect:** `Client Version: v1.…` and no `FAILED` or `WARNING` line.

**If not:**
- `FAILED: no Supervisor kubectl for …` (Linux arm64): the Supervisor has none for this machine.
  Get dl.k8s.io unblocked and use [From dl.k8s.io](#from-dlk8sio).
- `FAILED: download from …`: `SUPERVISOR_ENDPOINT` is wrong, or this machine cannot reach the
  Supervisor. The `curl:` or `unzip:` line above it says which.
- `bad CPU type in executable` (Apple silicon): install Rosetta with
  `softwareupdate --install-rosetta --agree-to-license`, then run the block again.
- `note: …` and `WARNING: …` lines: as in [From dl.k8s.io](#from-dlk8sio).

## Match the cluster's version

Needs your guest cluster's kubeconfig, from
[Log in to the Supervisor and a guest cluster](LOGIN.md#get-the-guest-clusters-kubeconfig). This
prints the client and server versions:

```sh
KUBECONFIG_FILE="$HOME/.kube/my-guest-cluster.kubeconfig"   # the guest cluster's kubeconfig

kubectl --kubeconfig "$KUBECONFIG_FILE" version -o json \
  | jq -r '"client " + .clientVersion.gitVersion, "server " + (.serverVersion.gitVersion // "unreachable")'
```

**Expect:** `client v1.…` and `server v1.…`. If the minor versions differ by more than one, run
[From dl.k8s.io](#from-dlk8sio) again with `KUBECTL_VERSION` set to the server version (a
`+vmware.N` suffix is dropped for you).

**If not:** `server unreachable`: `KUBECONFIG_FILE` is wrong, or the cluster cannot be reached
from here. The `kubectl` error above it says which.

Back to [README](README.md).
