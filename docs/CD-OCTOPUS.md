# Promote releases with Octopus and ArgoCD

This ties Octopus Deploy, ArgoCD and Nexus together. A new image version lands in Nexus; Octopus
creates a release and deploys it to `dev`; deploying means Octopus commits the new image tag into
the folder `envs/dev` of a Git repository; ArgoCD on the Supervisor sees the commit and rolls it
out to the namespace `test-web-apps-dev` of a VKS cluster. You then promote the same release to
`test` and, after an approval, to `prod`, and roll `prod` back to the previous release when you need
to. Octopus never reaches the VKS cluster: it only writes to Git and reads ArgoCD's status through
its Argo CD gateway, a small program that runs in Octopus's cluster.

The app is a page that says which version it runs. The Octopus Argo CD integration is a preview
feature of Octopus Server 2026.3 ([Argo CD in Octopus](https://octopus.com/docs/argo-cd)).

## Prerequisites

<!-- DRAFT: filled from the lab runs; see reports/CD-OCTOPUS design v2.md -->

## 1. Check what is in place

## 2. Push the first version to Nexus

Run this to give Octopus a first version to release; later, in step 10, you run it again with
`VERSION="1.0.1"`. It builds the app's image on your machine (an nginx page that shows its version),
names it `<NEXUS_REGISTRY>/<NEXUS_REPO>/test-web-apps:<VERSION>`, logs in to Nexus as the push user,
pushes it and logs out. You get version `1.0.0` of `test-web-apps` in Nexus; Octopus reads its
versions from there. A version cannot be pushed twice. Your machine must trust Nexus's CA
([NEXUS.md step 10](NEXUS.md#10-trust-nexus-and-push-an-image)).

The block logs in as the push user, so type that user's password
([NEXUS.md step 9](NEXUS.md#9-create-the-docker-repository-a-push-user-and-a-pull-user)) first, in
the same terminal:

**Linux, macOS, WSL (bash or zsh):**

```sh
printf 'Push user password: '; IFS= read -rs NEXUS_PUSH_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$NEXUS_PUSH_PASSWORD = Read-Host 'Push user password' -AsSecureString
```

Then run this. Set `CONTAINER_ENGINE` to `podman` or `docker`, `NEXUS_REGISTRY`, `NEXUS_REPO` and
`NEXUS_PUSH_USER` as in NEXUS.md.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
CONTAINER_ENGINE="podman"
NEXUS_REGISTRY="192.168.10.50"
NEXUS_REPO="apps"
NEXUS_PUSH_USER="apps-push"
VERSION="1.0.0"

IMG="${NEXUS_REGISTRY}/${NEXUS_REPO}/test-web-apps:${VERSION}"
D="$(mktemp -d)"
cat > "$D/Dockerfile" <<'EOF'
FROM docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
EOF
printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><title>test-web-apps</title></head>\n<body><h1>test-web-apps %s</h1></body></html>\n' "$VERSION" > "$D/index.html"
if [ -z "${NEXUS_PUSH_PASSWORD:-}" ]; then
  echo "STOPPED: type the push user's password first (the line above)"
elif "$CONTAINER_ENGINE" build --platform linux/amd64 -t "$IMG" "$D" \
     && printf '%s\n' "$NEXUS_PUSH_PASSWORD" | "$CONTAINER_ENGINE" login -u "$NEXUS_PUSH_USER" --password-stdin "$NEXUS_REGISTRY"; then
  "$CONTAINER_ENGINE" push "$IMG" && echo "pushed: $IMG"
  "$CONTAINER_ENGINE" logout "$NEXUS_REGISTRY"
fi
unset NEXUS_PUSH_PASSWORD; rm -rf "$D"
```

</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
$CONTAINER_ENGINE = "podman"
$NEXUS_REGISTRY = "192.168.10.50"
$NEXUS_REPO = "apps"
$NEXUS_PUSH_USER = "apps-push"
$VERSION = "1.0.0"

$IMG = "$NEXUS_REGISTRY/$NEXUS_REPO/test-web-apps:$VERSION"
$D = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory $D | Out-Null
[IO.File]::WriteAllText("$D\Dockerfile", "FROM docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03`nCOPY index.html /usr/share/nginx/html/index.html`nEXPOSE 8080`n")
[IO.File]::WriteAllText("$D\index.html", "<!doctype html>`n<html lang=`"en`"><head><meta charset=`"utf-8`"><title>test-web-apps</title></head>`n<body><h1>test-web-apps $VERSION</h1></body></html>`n")
$global:LASTEXITCODE = $null
if (-not $NEXUS_PUSH_PASSWORD -or $NEXUS_PUSH_PASSWORD.Length -eq 0) { "STOPPED: type the push user's password first (the line above)" } else {
  & $CONTAINER_ENGINE build --platform linux/amd64 -t $IMG $D
  if ($LASTEXITCODE -eq 0) { [Net.NetworkCredential]::new('', $NEXUS_PUSH_PASSWORD).Password | & $CONTAINER_ENGINE login -u $NEXUS_PUSH_USER --password-stdin $NEXUS_REGISTRY }
  if ($LASTEXITCODE -eq 0) {
    & $CONTAINER_ENGINE push $IMG
    if ($LASTEXITCODE -eq 0) { "pushed: $IMG" }
    & $CONTAINER_ENGINE logout $NEXUS_REGISTRY
  }
}
Remove-Variable -ErrorAction SilentlyContinue NEXUS_PUSH_PASSWORD
Remove-Item -Recurse -Force $D
```

</details>

<!-- DRAFT: Expect and If not are written from the lab run, not before. -->

## 3. Serve Gitea over HTTPS and create the deploy repository

## 4. Prepare the app cluster

## 5. Create the ArgoCD project and the three Applications

## 6. Give the gateway its ArgoCD token

## 7. Connect Octopus to ArgoCD (the gateway)

## 8. Create the Octopus project

## 9. Release 1.0.0 to dev, test and prod

## 10. Release a new version and roll back

## 11. Build the image with Tekton instead (optional)

## 12. Rotate the tokens (optional)

## 13. Clean up (optional)

## References

- Octopus: [Argo CD in Octopus](https://octopus.com/docs/argo-cd)
