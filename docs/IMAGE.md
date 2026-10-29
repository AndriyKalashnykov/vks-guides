# Build an image, push it to Harbor and run it

> [!NOTE]
> **Official documentation for this guide (Harbor, Docker, Podman and Kubernetes; Broadcom has none
> for building images)**
>
> - Harbor: [Pulling and Pushing Images](https://goharbor.io/docs/main/working-with-projects/working-with-images/pulling-pushing-images/), [Robot Accounts](https://goharbor.io/docs/main/administration/robot-accounts/)
> - Docker: [Verify repository client with certificates](https://docs.docker.com/engine/security/certificates/), Docker Desktop FAQs for [Mac](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) and [Windows](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/windowsfaqs/) (certificates)
> - Podman: [containers-certs.d](https://github.com/podman-container-tools/container-libs/blob/main/image/docs/containers-certs.d.5.md), [Install a certificate authority](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-install-certificate-authority.md), [podman machine set](https://docs.podman.io/en/latest/markdown/podman-machine-set.1.html)
> - Kubernetes: [Pull an Image from a Private Registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

This builds the web app in [`argocd/test-web-apps`](../argocd/test-web-apps) into an image with
podman or docker, pushes it to a Harbor project, runs it in a VKS cluster from Harbor, and opens
it in a browser and with `curl`. The page it shows names the engine that built it, so you can tell
it from the same app pulled from Docker Hub.

Needs:
- Harbor with a project and a robot account that may push to it
  ([HARBOR.md](HARBOR.md), steps 1 to 10), and Harbor's CA in
  `~/.config/vks-guides/harbor/harbor-ca.crt` ([step 9](HARBOR.md#save-the-ca), or step 1 below);
- podman or docker ([Prerequisites](PREREQS.md#podman-and-docker-optional)), `curl`, `jq` and
  `openssl`, and [kubectl](KUBECTL.md);
- the VKS cluster's kubeconfig ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig));
- a machine that reaches `github.com` and `docker.io` (the app's base image).

Every step works with podman or docker. Steps 3, 4 and 6 start with `CONTAINER_ENGINE="podman"`:
keep it for podman, or change it to `CONTAINER_ENGINE="docker"` for docker. The app runs in its
own namespace, `harbor-demo`: [ARGOCD.md](ARGOCD.md) keeps the same app in `test-web-apps` and would
undo changes there.

## 1. Get Harbor's CA

Harbor's certificate is signed by Harbor's own CA (certificate authority), not by one your
machine already knows. podman and docker need that CA's file to trust Harbor (step 2); without it
they refuse to connect (`x509: certificate signed by unknown authority`).

Skip this if you ran [HARBOR.md step 9](HARBOR.md#save-the-ca) on this machine. Otherwise this
downloads Harbor's CA from Harbor, saves it as `harbor-ca.crt.new` and prints its fingerprint, a
short code that identifies it. Harbor is not trusted yet, so the file could be a fake: keep it
(next block) only if the fingerprint is the same as the one step 9 printed for your Harbor
administrator. In Harbor's web page, **Projects** → your project →
**REGISTRY CERTIFICATE** downloads the same file as `ca.crt`.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
HARBOR_FQDN="harbor.example.test"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"

mkdir -p "$HARBOR_DIR" && rm -f "$HARBOR_DIR/harbor-ca.crt.new"
if curl -fsSk --connect-timeout 20 --speed-time 60 -o "$HARBOR_DIR/harbor-ca.crt.new" "https://${HARBOR_FQDN}/api/v2.0/systeminfo/getcert" \
   && openssl x509 -in "$HARBOR_DIR/harbor-ca.crt.new" -noout -subject -fingerprint -sha256; then
  echo "compare the fingerprint above with your Harbor administrator's, then keep the file"
else
  rm -f "$HARBOR_DIR/harbor-ca.crt.new"
  echo "FAILED: no CA certificate from https://${HARBOR_FQDN} (see the error above)"
fi
```

**Windows (PowerShell):**

```powershell
$HARBOR_FQDN = "harbor.example.test"
$HARBOR_DIR = "$HOME\.config\vks-guides\harbor"

New-Item -ItemType Directory -Force -Path $HARBOR_DIR | Out-Null
$NEW = "$HARBOR_DIR\harbor-ca.crt.new"; Remove-Item -Force -ErrorAction SilentlyContinue $NEW
curl.exe -fsSk --connect-timeout 20 --speed-time 60 -o $NEW "https://$HARBOR_FQDN/api/v2.0/systeminfo/getcert"
if ($LASTEXITCODE -eq 0 -and (Test-Path $NEW)) {
  $X = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $NEW
  "subject=$($X.Subject)"
  "sha256 Fingerprint=$(([Security.Cryptography.SHA256]::Create().ComputeHash($X.RawData) | ForEach-Object { $_.ToString('X2') }) -join ':')"
  "compare the fingerprint above with your Harbor administrator's, then keep the file"
} else {
  Remove-Item -Force -ErrorAction SilentlyContinue $NEW
  "FAILED: no CA certificate from https://$HARBOR_FQDN (see the error above)"
}
```

**Expect:** `subject=CN = Harbor CA` (newer OpenSSL and PowerShell: `subject=CN=Harbor CA`; or
your organization's CA, HARBOR.md step 13) and a `sha256 Fingerprint=` line. When it is the same
as your administrator's, keep the file:

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
mv "$HOME/.config/vks-guides/harbor/harbor-ca.crt.new" "$HOME/.config/vks-guides/harbor/harbor-ca.crt"
```

**Windows (PowerShell):**

```powershell
Move-Item -Force "$HOME\.config\vks-guides\harbor\harbor-ca.crt.new" "$HOME\.config\vks-guides\harbor\harbor-ca.crt"
```

**If not:** the fingerprints differ: delete `harbor-ca.crt.new` and stop; this is not your
Harbor's CA. `FAILED: …`: check the name (HARBOR.md step 7, *Check the DNS record*); if the name
is right, this Harbor publishes no CA (your organization's certificate, HARBOR.md step 13): get
`harbor-ca.crt` from your Harbor administrator.

## 2. Trust Harbor's CA

podman and docker talk to Harbor over HTTPS and check its certificate first. Until they trust
Harbor's CA, `login`, `push` and `pull` stop with `x509: certificate signed by unknown authority`.
This tells your engine to trust it.

Run the part for your OS and engine. Step 4's push proves that it worked (a login alone does not
prove it for docker).

### Linux

#### podman

This copies Harbor's CA into the folder in your home where podman looks for it, so podman trusts
Harbor. No `sudo` needed.

```sh
HARBOR_FQDN="harbor.example.test"
HARBOR_DIR="$HOME/.config/vks-guides/harbor"

if [ ! -s "$HARBOR_DIR/harbor-ca.crt" ]; then
  echo "FAILED: no $HARBOR_DIR/harbor-ca.crt (HARBOR.md step 9, or step 1 above)"
else
  mkdir -p "$HOME/.config/containers/certs.d/$HARBOR_FQDN" \
    && cp "$HARBOR_DIR/harbor-ca.crt" "$HOME/.config/containers/certs.d/$HARBOR_FQDN/ca.crt" \
    && echo "podman trusts $HARBOR_FQDN"
fi
```

**Expect:** `podman trusts <your Harbor name>`.

#### docker

This copies Harbor's CA into the system folder where docker looks for it, so docker trusts Harbor.
Run it as a block of its own: it uses `sudo`. docker 29.5 or newer reads it at once, without a
restart. podman reads this folder too.

```sh
HARBOR_FQDN="harbor.example.test"
sudo install -D -m 0644 "$HOME/.config/vks-guides/harbor/harbor-ca.crt" "/etc/docker/certs.d/$HARBOR_FQDN/ca.crt" && echo "docker trusts $HARBOR_FQDN"
```

**Expect:** `docker trusts <your Harbor name>`.

### macOS

podman and Docker Desktop read the CA from your login keychain. Add it there first (macOS asks
for your password):

```sh
security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$HOME/.config/vks-guides/harbor/harbor-ca.crt"
```

#### podman

Let the podman machine import the keychain's CAs: `podman machine stop`, then
`podman machine set --import-native-ca`, then `podman machine start`.

**If not:** `unknown flag: --import-native-ca`: your podman is older; follow Podman's
[Install a certificate authority](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-install-certificate-authority.md).

#### docker

- With Colima ([Prerequisites](PREREQS.md#podman-and-docker-on-macos)), which does not read the
  keychain, put the CA into its virtual machine:

  ```sh
  HARBOR_FQDN="harbor.example.test"
  colima ssh -- sudo mkdir -p "/etc/docker/certs.d/$HARBOR_FQDN" </dev/null
  colima ssh -- sudo tee "/etc/docker/certs.d/$HARBOR_FQDN/ca.crt" < "$HOME/.config/vks-guides/harbor/harbor-ca.crt" >/dev/null && echo "docker (Colima) trusts $HARBOR_FQDN"
  ```

  **Expect:** `docker (Colima) trusts <your Harbor name>`.
- With Docker Desktop: quit it and start it again, so that it reads the keychain.

### Windows

podman and Docker Desktop read the CA from your user's trusted root CAs. Add it there first
(Windows asks you to confirm with **Yes**):

```powershell
Import-Certificate -FilePath "$HOME\.config\vks-guides\harbor\harbor-ca.crt" -CertStoreLocation Cert:\CurrentUser\Root
```

**Expect:** a line with the CA's thumbprint and `CN=Harbor CA`.

**If not:** `UI is not allowed in this operation`: this PowerShell has no desktop to ask on (for
example over SSH). Run the line in Windows PowerShell on the desktop, or in Windows PowerShell as
Administrator with `Cert:\LocalMachine\Root` in place of `Cert:\CurrentUser\Root`, which trusts
the CA for every user of this machine.

#### podman

Let the podman machine import Windows' CAs: `podman machine stop`, then
`podman machine set --import-native-ca`, then `podman machine start`.

**If not:** `unknown flag: --import-native-ca`: your podman is older; follow Podman's
[Install a certificate authority](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-install-certificate-authority.md).

#### docker

Docker Desktop: quit it (tray icon → **Quit Docker Desktop**) and start it again, so that it reads
the new CA.

## 3. Build the image

This downloads the app's files from this repository, marks its page with the engine's name, and
builds the image.

`IMAGE_PLATFORM="linux/amd64"` builds the image for the VKS cluster's nodes, which are x86-64
machines. Keep it, also on a Mac with Apple silicon: without it, such a Mac builds an `arm64` image,
and the cluster's pods then fail with `exec format error`.

The first line picks the engine: `CONTAINER_ENGINE="podman"` builds with podman; change it to
`CONTAINER_ENGINE="docker"` (PowerShell: `$CONTAINER_ENGINE = "docker"`) to build with docker. To
build with both, run the block twice, once with each; the images get the tags `v1-podman` and
`v1-docker`.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
CONTAINER_ENGINE="podman"
HARBOR_FQDN="harbor.example.test"
HARBOR_PROJECT="my-project"
IMAGE_PLATFORM="linux/amd64"
IMAGE_DIR="$HOME/.config/vks-guides/image"

SRC="https://raw.githubusercontent.com/AndriyKalashnykov/vks-guides/666cba94ba517ac79d1c2ec505226192962477a3/argocd/test-web-apps"
IMG="${HARBOR_FQDN}/${HARBOR_PROJECT}/test-web-apps:v1-${CONTAINER_ENGINE}"
ERR=""
case "$CONTAINER_ENGINE" in podman|docker) ;; *) ERR="CONTAINER_ENGINE must be podman or docker" ;; esac
if [ -z "$ERR" ]; then
  rm -rf "$IMAGE_DIR/new" && mkdir -p "$IMAGE_DIR/new/app" "$IMAGE_DIR/new/k8s"
  for f in app/Dockerfile app/index.html k8s/namespace.yaml k8s/deployment.yaml k8s/service.yaml; do
    curl -fsS --connect-timeout 20 --speed-time 60 -o "$IMAGE_DIR/new/$f" "$SRC/${f#*/}" || ERR="download of ${f#*/} failed"
  done
fi
if [ -z "$ERR" ] && ! grep -q -x '<h1>test-web-apps v1</h1>' "$IMAGE_DIR/new/app/index.html"; then
  ERR="index.html is not the expected page"
fi
if [ -n "$ERR" ]; then
  echo "FAILED: $ERR"
else
  sed "s|^<h1>test-web-apps v1</h1>\$|<h1>test-web-apps v1, from Harbor ($CONTAINER_ENGINE)</h1>|" "$IMAGE_DIR/new/app/index.html" > "$IMAGE_DIR/new/app/index.html.tmp" \
    && mv "$IMAGE_DIR/new/app/index.html.tmp" "$IMAGE_DIR/new/app/index.html" \
    && chmod 0644 "$IMAGE_DIR/new/app/"* "$IMAGE_DIR/new/k8s/"* \
    && rm -rf "$IMAGE_DIR/app" "$IMAGE_DIR/k8s" && mv "$IMAGE_DIR/new/app" "$IMAGE_DIR/new/k8s" "$IMAGE_DIR/" && rm -rf "$IMAGE_DIR/new" \
    && "$CONTAINER_ENGINE" build --platform "$IMAGE_PLATFORM" -t "$IMG" "$IMAGE_DIR/app" \
    && echo "built: $IMG"
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$CONTAINER_ENGINE = "podman"
$HARBOR_FQDN = "harbor.example.test"
$HARBOR_PROJECT = "my-project"
$IMAGE_PLATFORM = "linux/amd64"
$IMAGE_DIR = "$HOME\.config\vks-guides\image"

$SRC = "https://raw.githubusercontent.com/AndriyKalashnykov/vks-guides/666cba94ba517ac79d1c2ec505226192962477a3/argocd/test-web-apps"
$IMG = "$HARBOR_FQDN/$HARBOR_PROJECT/test-web-apps:v1-$CONTAINER_ENGINE"
$ERR = ''
if ($CONTAINER_ENGINE -cnotmatch '^(podman|docker)$') { $ERR = 'CONTAINER_ENGINE must be podman or docker' }
elseif (-not (Get-Command "$CONTAINER_ENGINE.exe" -ErrorAction SilentlyContinue)) { $ERR = "$CONTAINER_ENGINE not found (Prerequisites)" }
else {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$IMAGE_DIR\new"
  New-Item -ItemType Directory -Force -Path "$IMAGE_DIR\new\app", "$IMAGE_DIR\new\k8s" | Out-Null
  foreach ($f in 'app/Dockerfile', 'app/index.html', 'k8s/namespace.yaml', 'k8s/deployment.yaml', 'k8s/service.yaml') {
    curl.exe -fsS --ssl-no-revoke --connect-timeout 20 --speed-time 60 -o "$IMAGE_DIR\new\$f" "$SRC/$($f -replace '^[^/]*/', '')"
    if ($LASTEXITCODE -ne 0) { $ERR = "download of $f failed" }
  }
}
$PAGE = "$IMAGE_DIR\new\app\index.html"
if (-not $ERR -and -not (Select-String -Path $PAGE -Pattern '^<h1>test-web-apps v1</h1>$' -CaseSensitive -Quiet)) { $ERR = 'index.html is not the expected page' }
if ($ERR) { "FAILED: $ERR" }
else {
  $T = [IO.File]::ReadAllText($PAGE) -replace '<h1>test-web-apps v1</h1>', "<h1>test-web-apps v1, from Harbor ($CONTAINER_ENGINE)</h1>"
  [IO.File]::WriteAllText($PAGE, $T)
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$IMAGE_DIR\app", "$IMAGE_DIR\k8s"
  Move-Item "$IMAGE_DIR\new\app", "$IMAGE_DIR\new\k8s" $IMAGE_DIR
  Remove-Item -Recurse -Force "$IMAGE_DIR\new"
  & $CONTAINER_ENGINE build --platform $IMAGE_PLATFORM -t $IMG "$IMAGE_DIR\app"
  if ($LASTEXITCODE -eq 0) { "built: $IMG" } else { "FAILED: the build (see the error above)" }
}
```

</details>

**Expect:** the build's steps (podman: `STEP 1/3: FROM …`; docker: `[1/2] FROM …`), then
`built: <your Harbor name>/<your project>/test-web-apps:v1-podman` (or `v1-docker`).

**If not:**
- `download of … failed`: the machine does not reach `raw.githubusercontent.com`.
- An error pulling `docker.io/nginxinc/nginx-unprivileged`: the machine does not reach Docker
  Hub, or Docker Hub limits your pulls (log in with `podman login docker.io` / `docker login`).
- `Cannot connect to the Docker daemon` or `permission denied … docker.sock`: see
  [Check podman and docker](PREREQS.md#check-podman-and-docker).
- podman on Photon OS: `user namespaces are not enabled`: use docker there
  ([Prerequisites](PREREQS.md#podman-and-docker-on-photon-os-5)).

## 4. Push it to Harbor

Use the robot account from HARBOR.md step 10. Keep `HARBOR_ROBOT` in single quotes: the `$` is
part of the name. A robot made in Harbor's web page under **Administration** is called
`robot$<its name>`; one made by step 10's block is `robot$<your project>+push`.

The first line picks the engine: `CONTAINER_ENGINE="podman"` pushes the image podman built; change
it to `CONTAINER_ENGINE="docker"` (PowerShell: `$CONTAINER_ENGINE = "docker"`) to push the image
docker built. Built with both? Run the block once with each.

Type the robot's secret in this terminal (it is not shown):

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
printf 'Robot secret: '; IFS= read -rs HARBOR_ROBOT_SECRET; echo
```

**Windows (PowerShell):**

```powershell
$HARBOR_ROBOT_SECRET = Read-Host -AsSecureString 'Robot secret'
```

Then this uploads (pushes) your image to your Harbor project:

- it logs in to Harbor as the robot account and pushes the image;
- it saves the image's digest, a unique ID of this exact build, so that step 6 runs this build;
- it logs out again, so the robot's login is not left on this machine.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
CONTAINER_ENGINE="podman"
HARBOR_FQDN="harbor.example.test"
HARBOR_PROJECT="my-project"
HARBOR_ROBOT='robot$my-project+push'
IMAGE_DIR="$HOME/.config/vks-guides/image"

IMG="${HARBOR_FQDN}/${HARBOR_PROJECT}/test-web-apps:v1-${CONTAINER_ENGINE}"
DIGEST_FILE="$IMAGE_DIR/digest-$CONTAINER_ENGINE"
rm -f "$DIGEST_FILE"
if [ -z "$HARBOR_ROBOT_SECRET" ]; then
  echo "FAILED: no robot secret in this terminal; run the line above"
elif printf '%s\n' "$HARBOR_ROBOT_SECRET" | "$CONTAINER_ENGINE" login -u "$HARBOR_ROBOT" --password-stdin "$HARBOR_FQDN"; then
  if [ "$CONTAINER_ENGINE" = podman ]; then
    podman push --digestfile "$DIGEST_FILE" "$IMG"
  else
    docker push "$IMG" \
      && docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$IMG" \
        | sed -n "s|^${HARBOR_FQDN}/${HARBOR_PROJECT}/test-web-apps@||p" | head -n 1 > "$DIGEST_FILE"
  fi
  "$CONTAINER_ENGINE" logout "$HARBOR_FQDN"
  if [ -s "$DIGEST_FILE" ]; then
    echo "pushed: ${IMG%:*}@$(cat "$DIGEST_FILE")"
  else
    echo "FAILED: the push (see the error above)"
  fi
fi
unset HARBOR_ROBOT_SECRET
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$CONTAINER_ENGINE = "podman"
$HARBOR_FQDN = "harbor.example.test"
$HARBOR_PROJECT = "my-project"
$HARBOR_ROBOT = 'robot$my-project+push'
$IMAGE_DIR = "$HOME\.config\vks-guides\image"

$IMG = "$HARBOR_FQDN/$HARBOR_PROJECT/test-web-apps:v1-$CONTAINER_ENGINE"
$DIGEST_FILE = "$IMAGE_DIR\digest-$CONTAINER_ENGINE"
Remove-Item -Force -ErrorAction SilentlyContinue $DIGEST_FILE
if (-not $HARBOR_ROBOT_SECRET -or $HARBOR_ROBOT_SECRET.Length -eq 0) { "FAILED: no robot secret in this terminal; run the line above" }
else {
  $B = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($HARBOR_ROBOT_SECRET)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($B) | & $CONTAINER_ENGINE login -u $HARBOR_ROBOT --password-stdin $HARBOR_FQDN }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($B) }
  if ($LASTEXITCODE -eq 0) {
    if ($CONTAINER_ENGINE -eq 'podman') { podman push --digestfile $DIGEST_FILE $IMG }
    else {
      docker push $IMG
      if ($LASTEXITCODE -eq 0) {
        $D = @(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' $IMG) |
          Where-Object { $_ -clike "$HARBOR_FQDN/$HARBOR_PROJECT/test-web-apps@*" } | Select-Object -First 1
        if ($D) { [IO.File]::WriteAllText($DIGEST_FILE, ($D -replace '^[^@]*@', '')) }
      }
    }
    & $CONTAINER_ENGINE logout $HARBOR_FQDN
  }
  if (Test-Path $DIGEST_FILE) { "pushed: $($IMG -replace ':[^:/]*$', '')@$(Get-Content -Raw $DIGEST_FILE)" }
  else { "FAILED: the push (see the error above)" }
}
Remove-Variable -ErrorAction SilentlyContinue HARBOR_ROBOT_SECRET
```

</details>

**Expect:** `Login Succeeded`, the push, `Removed login credentials for …` (docker: `Removing`), then
`pushed: <your Harbor name>/<your project>/test-web-apps@sha256:…`. In Harbor's web page the
project now lists the repository `test-web-apps`.

**If not:**
- `x509: certificate signed by unknown authority`: do step 2 for your engine. With docker, a login
  that works followed by this error at the push (`failed to fetch oauth token`) means docker is
  older than 29.5 ([Prerequisites](PREREQS.md#podman-and-docker-optional)).
- `unauthorized` (podman: `invalid username/password`): the robot's name or secret is wrong, or it
  has expired.
- `denied: requested access to the resource is denied` (podman) or `insufficient_scope` (docker):
  the robot may not push to this project.

## 5. Let the cluster pull from a private project (optional)

Skip this for a public project. For a private one, the cluster needs a robot's login: this stores
it in the cluster as the Secret `harbor-pull`, and step 6 makes the app use it. Use a robot that
may only pull: in Harbor's web page, a robot with only **Pull Repository** on this project
([HARBOR.md step 10](HARBOR.md#create-a-robot-account), *In Harbor's web page*); the push robot
also works, but it can also push. Anyone who may read Secrets in the namespace can read it.

Type the pull robot's secret in this terminal (it is not shown):

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
printf 'Pull robot secret: '; IFS= read -rs HARBOR_PULL_SECRET; echo
```

**Windows (PowerShell):**

```powershell
$HARBOR_PULL_SECRET = Read-Host -AsSecureString 'Pull robot secret'
```

Then this saves the pull robot's login in your VKS cluster. It creates:

- the namespace `harbor-demo`, a separate area of the cluster for the app (if it is not there
  yet);
- the Secret `harbor-pull`, the cluster's way to store a password, with the robot's name and
  secret.

The cluster's nodes log in to Harbor with it when they download the app's image in step 6.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
HARBOR_FQDN="harbor.example.test"
HARBOR_PULL_ROBOT='robot$my-project+pull'
APP_NAMESPACE="harbor-demo"
IMAGE_DIR="$HOME/.config/vks-guides/image"

VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
if [ -z "$HARBOR_PULL_SECRET" ]; then
  echo "FAILED: no pull robot secret in this terminal; run the line above"
elif [ ! -s "$VKS_KUBECONFIG" ] || [ ! -s "$IMAGE_DIR/k8s/namespace.yaml" ]; then
  echo "FAILED: $VKS_KUBECONFIG or $IMAGE_DIR/k8s/namespace.yaml is missing (step 3)"
elif sed "s/^  name: test-web-apps\$/  name: $APP_NAMESPACE/" "$IMAGE_DIR/k8s/namespace.yaml" \
       | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f -; then
  HARBOR_PULL_SECRET="$HARBOR_PULL_SECRET" jq -n --arg ns "$APP_NAMESPACE" --arg h "$HARBOR_FQDN" --arg u "$HARBOR_PULL_ROBOT" \
    '{apiVersion: "v1", kind: "Secret", type: "kubernetes.io/dockerconfigjson",
      metadata: {name: "harbor-pull", namespace: $ns},
      data: {".dockerconfigjson": ({auths: {($h): {username: $u, password: env.HARBOR_PULL_SECRET,
        auth: ("\($u):\(env.HARBOR_PULL_SECRET)" | @base64)}}} | tojson | @base64)}}' \
    | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f -
fi
unset HARBOR_PULL_SECRET
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$HARBOR_FQDN = "harbor.example.test"
$HARBOR_PULL_ROBOT = 'robot$my-project+pull'
$APP_NAMESPACE = "harbor-demo"
$IMAGE_DIR = "$HOME\.config\vks-guides\image"

$VKS_KUBECONFIG = "$HOME\.kube\$VKS_CLUSTER.kubeconfig"
$global:LASTEXITCODE = $null
if (-not $HARBOR_PULL_SECRET -or $HARBOR_PULL_SECRET.Length -eq 0) { "FAILED: no pull robot secret in this terminal; run the line above" }
elseif (-not (Test-Path $VKS_KUBECONFIG) -or -not (Test-Path "$IMAGE_DIR\k8s\namespace.yaml")) { "FAILED: $VKS_KUBECONFIG or $IMAGE_DIR\k8s\namespace.yaml is missing (step 3)" }
else {
  (Get-Content "$IMAGE_DIR\k8s\namespace.yaml") -creplace '^  name: test-web-apps$', "  name: $APP_NAMESPACE" | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
  if ($LASTEXITCODE -eq 0) {
    $B = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($HARBOR_PULL_SECRET)
    try {
      $P = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($B)
      $AUTH = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${HARBOR_PULL_ROBOT}:$P"))
      $CFG = @{ auths = @{ $HARBOR_FQDN = @{ username = $HARBOR_PULL_ROBOT; password = $P; auth = $AUTH } } } | ConvertTo-Json -Depth 5 -Compress
      @{ apiVersion = 'v1'; kind = 'Secret'; type = 'kubernetes.io/dockerconfigjson'
         metadata = @{ name = 'harbor-pull'; namespace = $APP_NAMESPACE }
         data = @{ '.dockerconfigjson' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CFG)) } } |
        ConvertTo-Json -Depth 5 | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
    } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($B); $P = $null; $AUTH = $null; $CFG = $null }
  }
}
Remove-Variable -ErrorAction SilentlyContinue HARBOR_PULL_SECRET
```

</details>

**Expect:** `namespace/harbor-demo created` (or `unchanged`), then `secret/harbor-pull created`
(or `configured`).

## 6. Deploy the app

This starts the app in your VKS cluster from the image you pushed to Harbor in step 4, which
shows that the cluster can pull your own images from Harbor. It creates:

- the namespace `harbor-demo`, to keep the app apart from everything else;
- the app itself: five pods, each running your image;
- a Service, which gives the app an address you can open from your machine (step 7).

If you did step 5, the pods log in to Harbor with the Secret `harbor-pull`. The block waits until
the five pods run, then checks that they run exactly the image you pushed, not an older one.

The first line picks which push to run: `CONTAINER_ENGINE="podman"` runs the image podman pushed,
`CONTAINER_ENGINE="docker"` (PowerShell: `$CONTAINER_ENGINE = "docker"`) the one docker pushed.

<details>
<summary><b>Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
CONTAINER_ENGINE="podman"
HARBOR_FQDN="harbor.example.test"
HARBOR_PROJECT="my-project"
APP_NAMESPACE="harbor-demo"
IMAGE_DIR="$HOME/.config/vks-guides/image"

VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
K="$IMAGE_DIR/k8s"
DIGEST="$(cat "$IMAGE_DIR/digest-$CONTAINER_ENGINE" 2>/dev/null)"
if [ -z "$DIGEST" ] || [ ! -s "$K/deployment.yaml" ] || [ ! -s "$VKS_KUBECONFIG" ]; then
  echo "FAILED: no digest (step 4), no $K/deployment.yaml (step 3), or no $VKS_KUBECONFIG"
else
  IMG="${HARBOR_FQDN}/${HARBOR_PROJECT}/test-web-apps@${DIGEST}"
  PULL=""
  kubectl --kubeconfig "$VKS_KUBECONFIG" -n "$APP_NAMESPACE" get secret harbor-pull >/dev/null 2>&1 && PULL="harbor-pull"
  echo "image: $IMG"; echo "pull secret: ${PULL:-none}"
  { sed "s/^  name: test-web-apps\$/  name: $APP_NAMESPACE/" "$K/namespace.yaml"
    echo "---"
    sed "s/^  namespace: test-web-apps\$/  namespace: $APP_NAMESPACE/" "$K/service.yaml"
    echo "---"
    awk -v ns="$APP_NAMESPACE" -v img="$IMG" -v pull="$PULL" '
      $0 == "  namespace: test-web-apps" { print "  namespace: " ns; next }
      /^          image: / { print "          image: " img; next }
      { print }
      $0 == "      automountServiceAccountToken: false" && pull { print "      imagePullSecrets:"; print "        - name: harbor-pull" }' "$K/deployment.yaml"
  } | kubectl --kubeconfig "$VKS_KUBECONFIG" apply -f - \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n "$APP_NAMESPACE" rollout status deployment/test-web-apps --timeout=180s \
    && kubectl --kubeconfig "$VKS_KUBECONFIG" -n "$APP_NAMESPACE" get pods -l app.kubernetes.io/name=test-web-apps \
         --no-headers -o 'custom-columns=DELETING:.metadata.deletionTimestamp,IMAGE:.status.containerStatuses[0].imageID' \
       | awk -v d="@$DIGEST" '$1 == "<none>" { n++; if (substr($2, length($2) - length(d) + 1) == d) ok++ } END { printf "pods running your image: %d of %d\n", ok, n }'
fi
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$CONTAINER_ENGINE = "podman"
$HARBOR_FQDN = "harbor.example.test"
$HARBOR_PROJECT = "my-project"
$APP_NAMESPACE = "harbor-demo"
$IMAGE_DIR = "$HOME\.config\vks-guides\image"

$VKS_KUBECONFIG = "$HOME\.kube\$VKS_CLUSTER.kubeconfig"
$K = "$IMAGE_DIR\k8s"
$DIGEST = if (Test-Path "$IMAGE_DIR\digest-$CONTAINER_ENGINE") { (Get-Content -Raw "$IMAGE_DIR\digest-$CONTAINER_ENGINE").Trim() } else { '' }
if (-not $DIGEST -or -not (Test-Path "$K\deployment.yaml") -or -not (Test-Path $VKS_KUBECONFIG)) {
  "FAILED: no digest (step 4), no $K\deployment.yaml (step 3), or no $VKS_KUBECONFIG"
} else {
  $IMG = "$HARBOR_FQDN/$HARBOR_PROJECT/test-web-apps@$DIGEST"
  kubectl --kubeconfig $VKS_KUBECONFIG -n $APP_NAMESPACE get secret harbor-pull 2>$null | Out-Null
  $PULL = ($LASTEXITCODE -eq 0)
  "image: $IMG"; "pull secret: $(if ($PULL) { 'harbor-pull' } else { 'none' })"
  $DEP = foreach ($l in Get-Content "$K\deployment.yaml") {
    if ($l -ceq '  namespace: test-web-apps') { "  namespace: $APP_NAMESPACE" }
    elseif ($l -cmatch '^          image: ') { "          image: $IMG" }
    else { $l; if ($PULL -and $l -ceq '      automountServiceAccountToken: false') { '      imagePullSecrets:'; '        - name: harbor-pull' } }
  }
  @((Get-Content "$K\namespace.yaml") -creplace '^  name: test-web-apps$', "  name: $APP_NAMESPACE") + '---' +
    ((Get-Content "$K\service.yaml") -creplace '^  namespace: test-web-apps$', "  namespace: $APP_NAMESPACE") + '---' + $DEP |
    kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
  if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $VKS_KUBECONFIG -n $APP_NAMESPACE rollout status deployment/test-web-apps --timeout=180s }
  if ($LASTEXITCODE -eq 0) {
    $IDS = @(kubectl --kubeconfig $VKS_KUBECONFIG -n $APP_NAMESPACE get pods -l app.kubernetes.io/name=test-web-apps --no-headers -o custom-columns=DELETING:.metadata.deletionTimestamp,IMAGE:.status.containerStatuses[0].imageID |
      Where-Object { $_ -clike '<none> *' } | ForEach-Object { ($_ -split '\s+')[1] })
    "pods running your image: $(@($IDS | Where-Object { $_.EndsWith("@$DIGEST") }).Count) of $($IDS.Count)"
  }
}
```

</details>

**Expect:** `namespace/harbor-demo`, `service/test-web-apps` and `deployment.apps/test-web-apps`
lines, `deployment "test-web-apps" successfully rolled out`, then
`pods running your image: 5 of 5`.

**If not:** the wait ends with `exceeded its progress deadline` or times out: run
`kubectl --kubeconfig ~/.kube/<cluster>.kubeconfig -n harbor-demo get events --sort-by=.lastTimestamp | tail`.
- `x509: certificate signed by unknown authority`: the nodes do not trust Harbor; run HARBOR.md
  step 11.
- `401 Unauthorized`, `no basic auth credentials` or `insufficient_scope`: the project is private
  and the Secret is missing or its robot may not pull: do step 5, then run this block again.
- `pods running your image: 4 of 5` (fewer than all): a copy was still starting; run the block
  again.

## 7. Open the app

This shows that the app answers from your machine. It waits up to 2 minutes for the app's address,
which the Supervisor's load balancer gives it, prints the address, and fetches the app's page.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
APP_NAMESPACE="harbor-demo"

VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
IP=""; n=0
until [ -n "$IP" ] || [ "$n" -ge 24 ]; do
  [ "$n" -eq 0 ] || sleep 5
  n=$((n + 1))
  IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n "$APP_NAMESPACE" get service test-web-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
done
if [ -z "$IP" ]; then
  echo "FAILED: the Service has no external IP after 2 minutes"
else
  echo "address: http://$IP/"
  curl -sS --connect-timeout 10 --max-time 20 "http://$IP/" | sed -n 's|.*<h1>\(.*\)</h1>.*|page: \1|p'
fi
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$APP_NAMESPACE = "harbor-demo"

$VKS_KUBECONFIG = "$HOME\.kube\$VKS_CLUSTER.kubeconfig"
$IP = ''; $n = 0
while (-not $IP -and $n -lt 24) {
  if ($n -gt 0) { Start-Sleep 5 }
  $n++
  $IP = kubectl --kubeconfig $VKS_KUBECONFIG -n $APP_NAMESPACE get service test-web-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
}
if (-not $IP) { "FAILED: the Service has no external IP after 2 minutes" }
else {
  "address: http://$IP/"
  $H = curl.exe -sS --connect-timeout 10 --max-time 20 "http://$IP/" | Out-String
  if ($H -match '<h1>(.*)</h1>') { "page: $($Matches[1])" }
}
```

**Expect:** `address: http://<IP>/` and `page: test-web-apps v1, from Harbor (podman)` (or
`docker`). Open the address in a browser: it shows the same line.

![The app's page in a browser, served from the image in Harbor](img/image/01-app-in-browser.png)

**If not:**
- `FAILED: … no external IP`: the Supervisor's load balancer has no address left; ask your vCenter
  administrator.
- No `page:` line: the address does not answer from this machine (a firewall between your network
  and the Supervisor's load balancer network), or the pods are not running (step 6).

## 8. Remove it (optional)

This deletes the app and its namespace from the cluster and the files this guide wrote.

**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
APP_NAMESPACE="harbor-demo"
IMAGE_DIR="$HOME/.config/vks-guides/image"

kubectl --kubeconfig "$HOME/.kube/${VKS_CLUSTER}.kubeconfig" delete namespace "$APP_NAMESPACE" --ignore-not-found \
  && rm -rf "$IMAGE_DIR" && echo "deleted $APP_NAMESPACE and $IMAGE_DIR"
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$APP_NAMESPACE = "harbor-demo"
$IMAGE_DIR = "$HOME\.config\vks-guides\image"

kubectl --kubeconfig "$HOME\.kube\$VKS_CLUSTER.kubeconfig" delete namespace $APP_NAMESPACE --ignore-not-found
if ($LASTEXITCODE -eq 0) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $IMAGE_DIR; "deleted $APP_NAMESPACE and $IMAGE_DIR" }
```

**Expect:** `namespace "harbor-demo" deleted`, then `deleted harbor-demo and …`.

The image stays in Harbor: delete it in Harbor's web page (**Projects** → your project →
**Repositories** → `test-web-apps` → **DELETE**). To stop trusting Harbor's CA:
- Linux:
  - podman: `rm -rf ~/.config/containers/certs.d/<your Harbor name>`;
  - docker, as a block of its own: `sudo rm -rf /etc/docker/certs.d/<your Harbor name>`;
  - if you followed an earlier version of HARBOR.md, Harbor's CA is also in the system's trust
    store; as a block of its own, on Ubuntu or Debian
    `sudo rm -f /usr/local/share/ca-certificates/harbor-ca.crt && sudo update-ca-certificates --fresh`,
    on AlmaLinux `sudo rm -f /etc/pki/ca-trust/source/anchors/harbor-ca.crt && sudo update-ca-trust`.
- macOS: remove `Harbor CA` in **Keychain Access**, then:
  - podman: `podman machine stop` and `podman machine start` (it imports the CAs again at start);
  - docker in Colima: `colima ssh -- sudo rm -rf /etc/docker/certs.d/<your Harbor name> </dev/null`;
    Docker Desktop: quit it and start it again.
- Windows: `certmgr.msc` → **Trusted Root Certification Authorities** → **Certificates** →
  `Harbor CA` → **Delete**, then:
  - podman: `podman machine stop` and `podman machine start`;
  - docker: quit Docker Desktop and start it again.

Back to [README](../README.md).
