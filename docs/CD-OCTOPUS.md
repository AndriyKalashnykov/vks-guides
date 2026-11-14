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

Do these first:

- [NEXUS.md](NEXUS.md) steps 1 to 10: Nexus with the Docker repository `apps`, its push and pull users,
  and `nexus-ca.pem`; your machine trusts Nexus's CA;
- [OCTOPUS.md](OCTOPUS.md) steps 1 to 11: Octopus Server 2026.3 with the environments `dev`, `test`
  and `prod`, the lifecycle `dev-test-prod`, the Docker feed `nexus`, and `octopus-ca.pem`;
- [GITEA.md](GITEA.md) steps 1 to 8 and [Over HTTPS, for pushes and
  tokens](GITEA.md#over-https-for-pushes-and-tokens), with `gitea-ca.pem`;
- [ARGOCD.md](ARGOCD.md) steps 1 to 4 and 7: an ArgoCD instance and the VKS cluster for the app
  added to it;
- [NEXUS.md step 11](NEXUS.md#11-let-vks-clusters-pull-from-nexus) for the app's cluster: its nodes
  trust Nexus's CA.

You need [kubectl](KUBECTL.md), [Helm](HELM.md), [the VCF CLI](VCF.md), [jq, curl, openssl and git, and
podman or docker](PREREQS.md); the **Namespaces Edit** role on ArgoCD's vSphere Namespace; Octopus's
`admin` (or a user who may manage Argo CD instances, Git credentials and projects); and Gitea's
administrator.

**The VKS clusters to make.** This guide adds little to the clusters of the guides above. In
Octopus's cluster, the Argo CD gateway asks for nothing and used 1 to 9m CPU and 17 to 19 MiB
(measured on VKS 3.8). The app's cluster runs one small web server per environment (0.05 CPU and 32
MiB reserved each): one `best-effort-medium` worker with room for that is enough; the app may share
the cluster of [ARGOCD.md](ARGOCD.md).

The connections this guide needs, for a firewall (all TCP, besides DNS; for a registry, also
[its other hosts](PREREQS.md#registry-hosts-for-a-firewall)):

| from | to | port | for |
|---|---|---|---|
| your machine (laptop or jump box) | the Supervisor's address | 443 | kubectl and the VCF CLI (steps 1, 5 and 6) |
| your machine (laptop or jump box) | the VKS clusters' API addresses (in their kubeconfigs) | 6443 | kubectl and Helm (steps 1, 4 and 7) |
| your machine (laptop or jump box) | Nexus's address | 443 | pushing images (steps 2 and 10) |
| your machine (laptop or jump box) | `registry-1.docker.io` | 443 | the gateway's Helm chart (step 7) |
| your machine and your browser | Octopus's web address, ArgoCD's address, Gitea's HTTPS address | 443 | the web pages and REST APIs |
| the nodes of Octopus's cluster | `docker.io` | 443 | the gateway's image (step 7) |
| the gateway (Octopus's cluster) | Octopus's web and gRPC Services, in the cluster | 443 and 8443 | registering, then the link to Octopus |
| the gateway (Octopus's cluster) | ArgoCD's address | 443 | reading and syncing the Applications |
| Octopus Server | Gitea's HTTPS address | 443 | committing the new image tags |
| Octopus Server | Nexus's address | 443 | listing image versions |
| ArgoCD (the Supervisor) | Gitea's HTTPS address | 443 | reading the `deploy` repository |
| ArgoCD (the Supervisor) | the app cluster's API address | 6443 | deploying the app |
| the app cluster's nodes | Nexus's address | 443 | pulling the app's image |

## 1. Check what is in place

Run this first, to see that the guides this one builds on are done before you change anything. It
only reads: it asks Octopus for its version, Nexus and Gitea whether they answer over HTTPS with the
CAs you saved, and the Supervisor for ArgoCD's instance and the app cluster's ArgoCD destination. You
get one line per part. Set `OCTOPUS_ADDRESS`, `NEXUS_REGISTRY` and `GITEA_ADDRESS` to their addresses,
`ARGOCD_NAMESPACE` to ArgoCD's vSphere Namespace, and `VSPHERE_NAMESPACE` and `VKS_CLUSTER` to the app's
cluster.

**Linux, macOS, WSL (bash or zsh):**

```sh
OCTOPUS_ADDRESS="192.168.10.70"
NEXUS_REGISTRY="192.168.10.50"
GITEA_ADDRESS="192.168.10.60"
ARGOCD_NAMESPACE="my-namespace"
VSPHERE_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"

c() { curl -sS --connect-timeout 20 --max-time 30 "$@"; }
echo "Octopus: $(c --cacert "$HOME/octopus-ca.pem" "https://$OCTOPUS_ADDRESS/api" | sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p')"
echo "Nexus: $(c --cacert "$HOME/nexus-ca.pem" -o /dev/null -w '%{http_code}' "https://$NEXUS_REGISTRY/service/rest/v1/status")"
echo "Gitea: $(c --cacert "$HOME/gitea-ca.pem" -o /dev/null -w '%{http_code}' "https://$GITEA_ADDRESS/api/v1/version")"
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get argocd argocd-1 -o jsonpath='ArgoCD: {.status.phase} https://{.status.externalIP}{"\n"}'
kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get managedentities.argocd-service.vsphere.vmware.com "vks-${VSPHERE_NAMESPACE}-${VKS_CLUSTER}" -o jsonpath='ArgoCD destination: {.status.phase}{"\n"}'
```

**Expect:** `Octopus: 2026.3.…`, `Nexus: 200`, `Gitea: 200`, `ArgoCD: Ready https://<address>` and
`ArgoCD destination: Ready`.

**If not:**
- `Octopus:` with nothing after it, or `Nexus:`/`Gitea:` with `000`: this machine cannot reach the
  address, or the CA file is missing (`curl` prints why above the line); do that guide first.
- `managedentities… not found`: do [ARGOCD.md step 7](ARGOCD.md#7-add-the-vks-cluster-to-argocd) for
  the app's cluster.
- `Octopus:` older than `2026.3`: the steps in this guide need Octopus 2026.3 or newer.

<!-- DRAFT: Windows twin. Block PASS on the lab 2026-11-14 14:4x. -->


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

**Expect:** the build, `Login Succeeded`, the push, `pushed: <NEXUS_REGISTRY>/apps/test-web-apps:1.0.0`,
then `Removed login credentials for …` (docker: `Removing login credentials for …`).

**If not:** as in [NEXUS.md step 10](NEXUS.md#10-trust-nexus-and-push-an-image); `redeploy is not
allowed` means this version was pushed before: push with a new `VERSION`.

## 3. Create the deploy repository and Gitea's users

Run this once, after step 2: ArgoCD deploys what this repository says, and Octopus changes it. Type
`gitea-admin`'s password first, in the terminal where you run this guide's blocks; it stays in this
terminal only:

**Linux, macOS, WSL (bash or zsh):**

```sh
printf 'gitea-admin password: '; IFS= read -rs GITEA_PASSWORD; echo
```

**Windows (PowerShell):**

```powershell
$GITEA_PASSWORD = Read-Host 'gitea-admin password' -AsSecureString
```

Then run this, in the same terminal. Through Gitea's HTTPS address it creates the private repository
`deploy`, with the folders `envs/dev`, `envs/test` and `envs/prod`; each holds the app's Deployment
(the image `<NEXUS_REGISTRY>/<NEXUS_REPO>/test-web-apps:1.0.0`, pulled with the Secret `nexus-pull`)
and a Service with a load-balancer address. It then creates two Gitea users whose passwords no one
knows and who may create no repositories: `octopus`, who may write to `deploy`, and `argocd`, who may
only read it, and saves a token for each, readable only by you, in `~/.config/vks-guides/cd-octopus`
(`gitea-octopus.token` for step 8, `gitea-argocd.token` for step 5). A second run keeps the
repository, the users and the tokens. Set `VKS_CLUSTER` to Gitea's cluster, `GITEA_ADDRESS` to its
HTTPS address, and `NEXUS_REGISTRY` and `NEXUS_REPO` as in NEXUS.md.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-vks-cluster"
GITEA_ADDRESS="192.168.10.60"
NEXUS_REGISTRY="192.168.10.50"
NEXUS_REPO="apps"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
CD_DIR="$HOME/.config/vks-guides/cd-octopus"

gx() { kubectl --kubeconfig "$VKS_KUBECONFIG" -n gitea exec deployment/gitea -- gitea admin user "$@"; }
mkdir -p "$CD_DIR" && chmod 700 "$CD_DIR"
if ! command -v jq >/dev/null 2>&1; then
  echo "MISSING: jq (PREREQS.md)"
elif [ -z "${GITEA_PASSWORD:-}" ]; then
  echo "STOPPED: type gitea-admin's password first (the line above)"
elif [ ! -s "$HOME/gitea-ca.pem" ]; then
  echo "MISSING: $HOME/gitea-ca.pem (GITEA.md, Over HTTPS, 4.)"
else
  ( umask 077; printf 'user = "gitea-admin:%s"\n' "$(printf '%s' "$GITEA_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')" > "$CD_DIR/gitea-admin.cfg" )
  api() { curl -sS --connect-timeout 20 --max-time 30 --cacert "$HOME/gitea-ca.pem" -K "$CD_DIR/gitea-admin.cfg" -H 'Content-Type: application/json' "$@"; }
  if [ "$(api -o /dev/null -w '%{http_code}' "https://$GITEA_ADDRESS/api/v1/user")" != 200 ]; then
    echo "FAILED: Gitea did not accept gitea-admin and this password at https://$GITEA_ADDRESS"
  else
    echo "repository deploy: $(api -o /dev/null -w '%{http_code}' -d '{"name":"deploy","private":true,"default_branch":"main"}' "https://$GITEA_ADDRESS/api/v1/user/repos")"
    for E in dev test prod; do
      for F in deployment service; do
        if [ "$F" = deployment ]; then
          Y="$(printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: test-web-apps\nspec:\n  replicas: 1\n  strategy:\n    rollingUpdate:\n      maxUnavailable: 0\n      maxSurge: 1\n  selector:\n    matchLabels:\n      app.kubernetes.io/name: test-web-apps\n  template:\n    metadata:\n      labels:\n        app.kubernetes.io/name: test-web-apps\n    spec:\n      automountServiceAccountToken: false\n      imagePullSecrets:\n        - name: nexus-pull\n      securityContext:\n        runAsNonRoot: true\n        runAsUser: 101\n        runAsGroup: 101\n        seccompProfile:\n          type: RuntimeDefault\n      containers:\n        - name: web\n          image: %s/%s/test-web-apps:1.0.0\n          ports:\n            - name: http\n              containerPort: 8080\n          readinessProbe:\n            httpGet:\n              path: /\n              port: http\n            periodSeconds: 5\n          securityContext:\n            allowPrivilegeEscalation: false\n            readOnlyRootFilesystem: true\n            capabilities:\n              drop: ["ALL"]\n          resources:\n            requests:\n              cpu: 50m\n              memory: 32Mi\n            limits:\n              memory: 128Mi\n          volumeMounts:\n            - name: tmp\n              mountPath: /tmp\n      volumes:\n        - name: tmp\n          emptyDir: {}\n' "$NEXUS_REGISTRY" "$NEXUS_REPO")"
        else
          Y="$(printf 'apiVersion: v1\nkind: Service\nmetadata:\n  name: test-web-apps\nspec:\n  type: LoadBalancer\n  selector:\n    app.kubernetes.io/name: test-web-apps\n  ports:\n    - name: http\n      port: 80\n      targetPort: http\n')"
        fi
        jq -n --arg c "$(printf '%s\n' "$Y" | base64 | tr -d '\n')" --arg f "envs/$E/$F.yaml" '{content: $c, message: "add \($f)", branch: "main"}' \
          | api -o /dev/null -w "  envs/$E/$F.yaml: %{http_code}\n" --data-binary @- "https://$GITEA_ADDRESS/api/v1/repos/gitea-admin/deploy/contents/envs/$E/$F.yaml"
      done
    done
    for U in octopus argocd; do
      if gx list | awk -v u="$U" '$2 == u { f = 1 } END { exit !f }'; then
        echo "user $U: exists, kept"
      else
        gx create --username "$U" --email "$U@localhost" --random-password --must-change-password=false >/dev/null && echo "user $U: created"
        jq -n --arg u "$U" '{source_id: 0, login_name: $u, max_repo_creation: 0}' \
          | api -o /dev/null -w "user $U may create no repositories: %{http_code}\n" -X PATCH --data-binary @- "https://$GITEA_ADDRESS/api/v1/admin/users/$U"
      fi
    done
    echo "octopus writes deploy: $(api -o /dev/null -w '%{http_code}' -X PUT -d '{"permission":"write"}' "https://$GITEA_ADDRESS/api/v1/repos/gitea-admin/deploy/collaborators/octopus")"
    echo "argocd reads deploy: $(api -o /dev/null -w '%{http_code}' -X PUT -d '{"permission":"read"}' "https://$GITEA_ADDRESS/api/v1/repos/gitea-admin/deploy/collaborators/argocd")"
    for U in octopus argocd; do
      if [ -s "$CD_DIR/gitea-$U.token" ]; then
        echo "token for $U: kept"
      else
        [ "$U" = octopus ] && S=write:repository || S=read:repository
        ( umask 077; gx generate-access-token --username "$U" --token-name "cd-octopus-$(date +%Y%m%d%H%M%S)" --scopes "$S" --raw \
            | tr -d '\r\n' > "$CD_DIR/gitea-$U.token.new" )
        if grep -Eq '^[0-9a-f]{40}$' "$CD_DIR/gitea-$U.token.new"; then
          mv "$CD_DIR/gitea-$U.token.new" "$CD_DIR/gitea-$U.token" && echo "token for $U: saved"
        else
          rm -f "$CD_DIR/gitea-$U.token.new"; echo "FAILED: Gitea made no token for $U"
        fi
      fi
    done
  fi
  rm -f "$CD_DIR/gitea-admin.cfg"
fi
```

</details>

**Expect:** `repository deploy: 201`, six `envs/…: 201` lines, `user octopus: created`, `user argocd:
created`, two `… may create no repositories: 200`, `octopus writes deploy: 204`, `argocd reads deploy:
204`, `token for octopus: saved` and `token for argocd: saved`. Run again: `repository deploy: 409`,
six `422` lines (the files are kept as they are), `exists, kept`, the two `204` lines and `token …:
kept`.

**If not:**
- `FAILED: Gitea did not accept …`: the password or `GITEA_ADDRESS` is wrong, or this machine does not
  trust Gitea's CA (`curl --cacert ~/gitea-ca.pem https://<GITEA_ADDRESS>` says why).
- `deployments.apps "gitea" not found`: `VKS_CLUSTER` is not Gitea's cluster (both ways of GITEA.md
  step 4 run Gitea as the deployment `gitea` in the namespace `gitea`).
- `FAILED: Gitea made no token for …`: the line above it says why; run the block again.

<!-- DRAFT: Windows twin; first-run arm (201/created/200) not run on the lab yet (lab ran the second-run arm 2026-11-14 14:26). -->

## 4. Prepare the app cluster

Run this once, before step 5: ArgoCD deploys into namespaces that exist, and the app's pods pull from
Nexus with a login. It creates the namespaces `test-web-apps-dev`, `test-web-apps-test` and
`test-web-apps-prod` (inside the VKS cluster, not vSphere Namespaces), which allow only pods that follow
the `restricted` Pod Security Standard, and copies into each the pull Secret `nexus-pull` that
[NEXUS.md step 11](NEXUS.md#check-that-a-cluster-can-pull) made in the namespace `default`. Run again,
it updates the copies. Set `VKS_CLUSTER` to the app's cluster.

**Linux, macOS, WSL (bash or zsh):**

```sh
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" "$@"; }
if ! command -v jq >/dev/null 2>&1; then echo "MISSING: jq (PREREQS.md)"
elif ! S="$(kc -n default get secret nexus-pull -o json)"; then echo "FAILED: no Secret nexus-pull in default (NEXUS.md step 11)"
else
  for E in dev test prod; do
    kc create namespace "test-web-apps-$E" --dry-run=client -o yaml | kc apply -f - >/dev/null \
      && kc label namespace "test-web-apps-$E" --overwrite pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted \
      && printf '%s' "$S" | jq --arg n "test-web-apps-$E" '{apiVersion, kind, type, data, metadata: {name: .metadata.name, namespace: $n}}' | kc apply -f -
  done
fi
```

**Windows (PowerShell):**

```powershell
$VKS_CLUSTER = "my-vks-cluster"
$VKS_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$global:LASTEXITCODE = $null
$S = kubectl --kubeconfig $VKS_KUBECONFIG -n default get secret nexus-pull -o json | Out-String
if ($LASTEXITCODE -ne 0) { "FAILED: no Secret nexus-pull in default (NEXUS.md step 11)" } else {
  $J = $S | ConvertFrom-Json
  foreach ($E in 'dev', 'test', 'prod') {
    kubectl --kubeconfig $VKS_KUBECONFIG create namespace "test-web-apps-$E" --dry-run=client -o yaml | kubectl --kubeconfig $VKS_KUBECONFIG apply -f - | Out-Null
    kubectl --kubeconfig $VKS_KUBECONFIG label namespace "test-web-apps-$E" --overwrite pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
    @{ apiVersion = 'v1'; kind = 'Secret'; type = $J.type; data = $J.data; metadata = @{ name = 'nexus-pull'; namespace = "test-web-apps-$E" } } |
      ConvertTo-Json -Depth 5 | kubectl --kubeconfig $VKS_KUBECONFIG apply -f -
  }
}
```

**Expect:** for each environment `namespace/test-web-apps-<env> labeled` (`not labeled` when run again)
and `secret/nexus-pull created` (`configured` or `unchanged` when run again).

**If not:** `FAILED: no Secret nexus-pull in default`: run [NEXUS.md step
11](NEXUS.md#check-that-a-cluster-can-pull) for this cluster first.

<!-- DRAFT: second-run arm of this exact block PASS on the lab 2026-11-14 14:3x (not labeled / unchanged x3); first-run arm by an equivalent script 2026-11-13; Windows twin not run. -->

## 5. Create the ArgoCD project and the three Applications

Run this once, after steps 3 and 4, on the Supervisor: ArgoCD then deploys each environment's folder
of `deploy` to its namespace, and Octopus finds the Applications by their annotations. It:

- adds Gitea's CA to ArgoCD's list of trusted Git servers (the ConfigMap `argocd-tls-certs-cm`, under
  Gitea's address), so ArgoCD checks Gitea's certificate;
- stores the Gitea user `argocd` and its token (step 3) as ArgoCD's login for `deploy`;
- creates the project `test-web-apps`, which may take only `deploy` and deploy only a Deployment and a
  Service into the three namespaces, with the role `octopus` that may only read and sync its apps and
  read their logs (step 6 makes its token);
- creates the Applications `test-web-apps-dev`, `-test` and `-prod`, each with the annotations
  `argo.octopus.com/project: test-web-apps` and `argo.octopus.com/environment: <env>`, synced
  automatically.

You get the three environments running version 1.0.0. Run again, it changes nothing. Set
`ARGOCD_NAMESPACE` to ArgoCD's vSphere Namespace, `VSPHERE_NAMESPACE` and `VKS_CLUSTER` to the app's
cluster (as in [ARGOCD.md step 7](ARGOCD.md#7-add-the-vks-cluster-to-argocd)), and `GITEA_ADDRESS` as
in step 3.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VSPHERE_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
GITEA_ADDRESS="192.168.10.60"
CD_DIR="$HOME/.config/vks-guides/cd-octopus"

K() { kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" "$@"; }
REPO="https://$GITEA_ADDRESS/gitea-admin/deploy.git"
DEST="${VKS_CLUSTER}-${VSPHERE_NAMESPACE}"
if ! command -v jq >/dev/null 2>&1; then echo "MISSING: jq (PREREQS.md)"
elif [ ! -s "$HOME/gitea-ca.pem" ] || [ ! -s "$CD_DIR/gitea-argocd.token" ]; then
  echo "MISSING: $HOME/gitea-ca.pem or $CD_DIR/gitea-argocd.token (GITEA.md Over HTTPS 4., step 3)"
else
  jq -n --arg k "$GITEA_ADDRESS" --rawfile c "$HOME/gitea-ca.pem" '{data: {($k): $c}}' \
    | K patch configmap argocd-tls-certs-cm --type merge --patch-file /dev/stdin
  jq -n --arg u "$REPO" --rawfile t "$CD_DIR/gitea-argocd.token" '{apiVersion: "v1", kind: "Secret",
      metadata: {name: "repo-gitea-deploy", labels: {"argocd.argoproj.io/secret-type": "repository"}},
      stringData: {type: "git", url: $u, username: "argocd", password: $t, project: "test-web-apps"}}' | K apply -f -
  K apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: test-web-apps
spec:
  description: test-web-apps, promoted by Octopus
  sourceRepos:
    - ${REPO}
  destinations:
    - name: ${DEST}
      namespace: test-web-apps-dev
    - name: ${DEST}
      namespace: test-web-apps-test
    - name: ${DEST}
      namespace: test-web-apps-prod
  clusterResourceWhitelist: []
  namespaceResourceWhitelist:
    - group: apps
      kind: Deployment
    - group: ""
      kind: Service
  roles:
    - name: octopus
      description: the Octopus Argo CD gateway
      policies:
        - p, proj:test-web-apps:octopus, applications, get, test-web-apps/*, allow
        - p, proj:test-web-apps:octopus, applications, sync, test-web-apps/*, allow
        - p, proj:test-web-apps:octopus, logs, get, test-web-apps/*, allow
EOF
  for E in dev test prod; do
    K apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-web-apps-${E}
  annotations:
    argo.octopus.com/project: test-web-apps
    argo.octopus.com/environment: ${E}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: test-web-apps
  source:
    repoURL: ${REPO}
    targetRevision: main
    path: envs/${E}
  destination:
    name: ${DEST}
    namespace: test-web-apps-${E}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
  done
fi
```

</details>

**Expect:** `configmap/argocd-tls-certs-cm patched`, `secret/repo-gitea-deploy created`,
`appproject.argoproj.io/test-web-apps created` and three `application.argoproj.io/test-web-apps-<env>
created`, each Application after a `Warning:` about the finalizer name (as in ARGOCD.md step 8). Run
again: `patched (no change)`, `configured` for the Secret and the project (`unchanged` when nothing
changed), and `unchanged` for the Applications.

**If not:** `configmaps "argocd-tls-certs-cm" not found`: `ARGOCD_NAMESPACE` is not ArgoCD's vSphere
Namespace.

<!-- DRAFT: Windows twin. Re-run arm of this exact block PASS 2026-11-14 14:28 (patched (no change), Secret/project configured, apps unchanged); first-run arm by lab scripts 2026-11-13 18:2x. -->

Run this after the block above, to see the three environments run. It only reads: it shows ArgoCD's
status for each Application, how many of its pods are ready with which image, and what the page at
its address says. Run it again until all three show `Synced  Healthy`, `1/1` and a page: ArgoCD may
need two minutes to trust Gitea's CA. Set the values as above.

**Linux, macOS, WSL (bash or zsh):**

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

for E in dev test prod; do
  A="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get applications.argoproj.io "test-web-apps-$E" -o jsonpath='{.status.sync.status}  {.status.health.status}')"
  D="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n "test-web-apps-$E" get deployment test-web-apps -o jsonpath='{.status.readyReplicas}/{.spec.replicas} {.spec.template.spec.containers[0].image}' 2>/dev/null)"
  IP="$(kubectl --kubeconfig "$VKS_KUBECONFIG" -n "test-web-apps-$E" get service test-web-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
  P=""; [ -z "$IP" ] || P="$(curl -s --connect-timeout 10 --max-time 20 "http://$IP/" | sed -n 's/.*<h1>\(.*\)<\/h1>.*/\1/p')"
  echo "$E: ArgoCD $A | pods ${D:-none} | http://${IP:-?}/ ${P:-no page}"
done
```

**Expect:** three lines such as `dev: ArgoCD Synced  Healthy | pods 1/1
<NEXUS_REGISTRY>/apps/test-web-apps:1.0.0 | http://<address>/ test-web-apps 1.0.0`.

**If not:**
- `Unknown` instead of `Synced`, and the ArgoCD page shows `x509: certificate signed by unknown
  authority` for the Application: ArgoCD has not read Gitea's CA yet. Wait two minutes, then in the
  ArgoCD page open the Application and click **Refresh** → **Hard Refresh**.
- `pods none`: the Application is not synced yet, or its namespace is missing (step 4).
- `0/1` with `ErrImagePull` (`kubectl --kubeconfig <file> -n test-web-apps-<env> get pods`): the
  cluster's nodes do not trust Nexus's CA, or `nexus-pull` is missing (step 4).

<!-- DRAFT: Windows twin. Check block PASS 2026-11-14 14:28 (1.0.2/1.0.2/1.0.1 after the e2e runs). -->

## 6. Give the gateway its ArgoCD token

Run this once, after step 5, as ArgoCD's `admin`: the gateway signs in to ArgoCD with a token of the
project's role `octopus`, which may only read and sync the apps of the project `test-web-apps` and
read their logs. It reads ArgoCD's first `admin` password and certificate from the Supervisor,
signs in to ArgoCD, makes a token that ends after 90 days, and saves it in
`~/.config/vks-guides/cd-octopus/argocd-project.token` (readable only by you), then signs out. It
checks the token by listing the project's apps with it. You get the token that step 7 gives the
gateway; ArgoCD keeps no copy you can read again, so run this again for a new one. Set
`ARGOCD_NAMESPACE` to ArgoCD's vSphere Namespace.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
CD_DIR="$HOME/.config/vks-guides/cd-octopus"

K() { kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" "$@"; }
mkdir -p "$CD_DIR" && chmod 700 "$CD_DIR"
IP="$(K get argocd argocd-1 -o jsonpath='{.status.externalIP}')"
if ! command -v jq >/dev/null 2>&1; then echo "MISSING: jq (PREREQS.md)"
elif [ -z "$IP" ] || ! K get secret argocd-secret -o go-template='{{index .data "tls.crt" | base64decode}}' > "$CD_DIR/argocd-server.pem"; then
  echo "FAILED: no ArgoCD address or certificate (ARGOCD.md step 1)"
else
  ac() { curl -fsS --resolve "argocd-server:443:$IP" --cacert "$CD_DIR/argocd-server.pem" --connect-timeout 20 --max-time 60 -H 'Content-Type: application/json' "$@"; }
  ( umask 077
    K get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}' | jq -Rs '{username:"admin",password:.}' > "$CD_DIR/login.json"
    ac --data-binary @"$CD_DIR/login.json" https://argocd-server/api/v1/session \
      | jq -r '"header = \"Authorization: Bearer \(.token // "")\""' > "$CD_DIR/admin.cfg"
    jq -n --arg id "octopus-gateway-$(date +%Y%m%d%H%M%S)" '{id:$id,expiresIn:7776000}' \
      | ac -K "$CD_DIR/admin.cfg" --data-binary @- https://argocd-server/api/v1/projects/test-web-apps/roles/octopus/token \
      | jq -j '.token // empty' > "$CD_DIR/argocd-project.token.new"
    ac -K "$CD_DIR/admin.cfg" -X DELETE -o /dev/null https://argocd-server/api/v1/session || echo "NOTE: ArgoCD sign-out failed (the session ends by itself)"
    rm -f "$CD_DIR/login.json" "$CD_DIR/admin.cfg"
    printf 'header = "Authorization: Bearer %s"\n' "$(cat "$CD_DIR/argocd-project.token.new")" > "$CD_DIR/project.cfg" )
  if [ -s "$CD_DIR/argocd-project.token.new" ] \
     && N="$(ac -K "$CD_DIR/project.cfg" https://argocd-server/api/v1/applications | jq -e '(.items // []) | length')"; then
    mv "$CD_DIR/argocd-project.token.new" "$CD_DIR/argocd-project.token"
    echo "token saved: lists $N apps of test-web-apps"
  else
    rm -f "$CD_DIR/argocd-project.token.new"
    echo "FAILED: no working token; $CD_DIR/argocd-project.token is as it was"
  fi
  rm -f "$CD_DIR/project.cfg"
fi
```

</details>

**Expect:** `token saved: lists 3 apps of test-web-apps`. Run again, it makes another token and
prints the same; the earlier token keeps working until it ends (step 12 removes it).

**If not:**
- `FAILED: no working token`, after `curl: (22) … 401`: ArgoCD's first `admin` password was changed;
  the Secret `argocd-initial-admin-secret` no longer holds it.
- … after `curl: (22) … 403` or `404`: step 5 did not create the project `test-web-apps` with its role
  `octopus`.
- `FAILED: no ArgoCD address or certificate`: the instance is not `Ready` ([ARGOCD.md step
  1](ARGOCD.md#1-check-for-an-argocd-you-have)).

<!-- DRAFT: Windows twin from the lab run of this exact block. -->


## 7. Connect Octopus to ArgoCD (the gateway)

The Argo CD gateway is a small program that Octopus provides; it runs in Octopus's cluster, keeps a
connection to Octopus (gRPC, port 8443) and to ArgoCD, and tells Octopus which Applications exist and
how they are doing. It registers itself in Octopus once, with an Octopus API key.

1. In Octopus's web page, click your user (bottom left) → **Profile** → **My API Keys** → **New API
   key**, enter a purpose such as `argocd gateway`, and click **Generate new**. Copy the key (it starts
   with `API-`); Octopus shows it once. You delete it again in 4.
2. Type the key in the terminal where you run this guide's blocks; it stays in this terminal only:

**Linux, macOS, WSL (bash or zsh):**

```sh
printf 'Octopus API key: '; IFS= read -rs OCTOPUS_API_KEY; echo
```

**Windows (PowerShell):**

```powershell
$OCTOPUS_API_KEY = Read-Host 'Octopus API key' -AsSecureString
```

3. Then run this, in the same terminal. In Octopus's cluster it creates the namespace
   `octopus-argocd-gateway` (`restricted` pods only) and in it:

   - the Service `argocd-server`, which points at ArgoCD's address, so that the gateway reaches ArgoCD
     by the name ArgoCD's certificate is made for (`argocd-server`) and checks that certificate;
   - three Secrets: the API key, step 6's ArgoCD token, and the certificates to trust (Octopus's CA
     from OCTOPUS.md step 5 and ArgoCD's own certificate);
   - the gateway, installed with Helm from Octopus's chart `octopus-argocd-gateway-chart` 2.4.0 (image
     `v2.2.1`, pinned by its digest), with its daily self-update turned off, reaching Octopus inside the
     cluster and pinned to the certificate of Octopus's gRPC port.

   It registers the gateway in Octopus as `<VKS_CLUSTER>-argocd` for the environments `dev`, `test` and
   `prod`, waits until it runs, and prints its log lines about the connections. You get Octopus and
   ArgoCD connected. Run again, it keeps the registration (it changes the gateway only if a value
   changed). Set `VKS_CLUSTER` to Octopus's cluster, `ARGOCD_NAMESPACE` to ArgoCD's vSphere Namespace.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
VKS_CLUSTER="my-octopus-cluster"
ARGOCD_NAMESPACE="my-namespace"
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
VKS_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
CD_DIR="$HOME/.config/vks-guides/cd-octopus"
CHART="oci://registry-1.docker.io/octopusdeploy/octopus-argocd-gateway-chart"
NS="octopus-argocd-gateway"

kc() { kubectl --kubeconfig "$VKS_KUBECONFIG" "$@"; }
ARGOCD_IP="$(kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" get argocd argocd-1 -o jsonpath='{.status.externalIP}')"
GRPC_IP="$(kc -n octopus get service octopus-grpc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
if ! command -v helm >/dev/null 2>&1; then echo "MISSING: helm (HELM.md)"
elif [ -z "${OCTOPUS_API_KEY:-}" ]; then echo "STOPPED: type the Octopus API key first (the line above)"
elif [ -z "$ARGOCD_IP" ] || [ -z "$GRPC_IP" ]; then echo "FAILED: no ArgoCD address or no octopus-grpc address (OCTOPUS.md step 4)"
elif [ ! -s "$CD_DIR/argocd-project.token" ] || [ ! -s "$CD_DIR/argocd-server.pem" ]; then echo "MISSING: step 6's token or certificate in $CD_DIR"
elif ! TP="$(openssl s_client -connect "$GRPC_IP:8443" </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)" || [ -z "$TP" ]; then
  echo "FAILED: cannot read the certificate of Octopus's gRPC port $GRPC_IP:8443"
else
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
  kc label namespace "$NS" --overwrite pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted >/dev/null
  kc -n "$NS" apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
spec:
  ports:
    - name: https
      port: 443
      targetPort: 443
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: argocd-server-1
  labels:
    kubernetes.io/service-name: argocd-server
addressType: IPv4
ports:
  - name: https
    port: 443
    protocol: TCP
endpoints:
  - addresses:
      - ${ARGOCD_IP}
EOF
  printf '%s' "$OCTOPUS_API_KEY" | kc -n "$NS" create secret generic octo-registration --from-file=token=/dev/stdin --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS" create secret generic gw-project-tokens --from-file=PROJECT_AUTH_TOKEN_test-web-apps="$CD_DIR/argocd-project.token" --dry-run=client -o yaml | kc apply -f -
  kc -n octopus get secret octopus-ca -o go-template='{{index .data "ca.crt" | base64decode}}' \
    | kc -n "$NS" create secret generic gw-certs --from-file=octopus-server-http-certificate.pem=/dev/stdin \
        --from-file=argo-cd-server-certificate.pem="$CD_DIR/argocd-server.pem" --dry-run=client -o yaml | kc apply -f -
  cat > "$CD_DIR/gateway-values.yaml" <<EOF
image:
  tag: "v2.2.1@sha256:9c8aa3317525c383a4ef623346b7c76b4dbe83b72e61c8b195d3281507b031f7"
autoUpdate:
  enabled: false
podSecurityContext:
  runAsNonRoot: true
registration:
  octopus:
    name: ${VKS_CLUSTER}-argocd
    serverApiUrl: https://octopus-web.octopus.svc
    serverAccessTokenSecretName: octo-registration
    serverAccessTokenSecretKey: token
    environments:
      - dev
      - test
      - prod
    spaceId: Spaces-1
  argocd:
    webUiUrl: https://${ARGOCD_IP}
gateway:
  serverCertificateSecretName: gw-certs
  octopus:
    serverGrpcUrl: grpc://octopus-grpc.octopus.svc:8443
    serverThumbprint: "${TP}"
  argocd:
    serverGrpcUrl: grpc://argocd-server:443
    projectAuthenticationSecretName: gw-project-tokens
EOF
  helm upgrade --install --atomic --timeout 6m gw "$CHART" --version 2.4.0 --kubeconfig "$VKS_KUBECONFIG" -n "$NS" -f "$CD_DIR/gateway-values.yaml" >/dev/null \
    && kc -n "$NS" rollout status deployment/octopus-argocd-gateway --timeout=3m \
    && sleep 20 && kc -n "$NS" logs deployment/octopus-argocd-gateway | grep -E '"state":"READY"|token status' | cut -c1-200
fi
unset OCTOPUS_API_KEY
```

</details>

<!-- DRAFT: Windows twin; Expect/If not from a pasted run of this exact block (lab used an equivalent script 2026-11-13 18:08; measured log lines: READY for octopus-grpc.octopus.svc:8443 and argocd-server:443, token status ok). Finding to cover: a token Secret with a trailing newline -> "invalid header field value for Authorization". -->

4. In Octopus, open **Infrastructure** → **Argo CD Instances**: the instance `<VKS_CLUSTER>-argocd` is
   healthy and shows the three Applications. Then delete the API key from 1. (**Profile** → **My API
   Keys**): the gateway needs it only to register.

![Argo CD Instances: octopus-gc-argocd healthy, 3 applications, environments dev and 2 more](img/cd-octopus/01-argocd-instances.jpg)

## 8. Create the Octopus project

Do this once, in Octopus's web page, signed in as `admin`. It tells Octopus how to deploy: commit the
new image tag into the Application's folder of `deploy`, ask ArgoCD to sync, and wait until the
Application is healthy; with an approval before `prod`, and a new release for every new image in
Nexus.

**Octopus's Git login.** Octopus commits to `deploy` as the Gitea user `octopus` (step 3). Under
**Manage** → **Git Credentials** → **Add Git Credential**: **Git credential name** `gitea-deploy`,
**HTTP/HTTPS**, **Username** `octopus`, **Personal Access Token or Password** the content of
`~/.config/vks-guides/cd-octopus/gitea-octopus.token`, and under **Allowed Repositories** **Only allow
specified Git repositories** with `https://<GITEA_ADDRESS>/gitea-admin/deploy.git` (**Add to list**),
then **Save**.

![Create Git Credential: name gitea-deploy, HTTP/HTTPS, user octopus, token, allowed repository deploy.git](img/cd-octopus/02-git-credential.jpg)

**Octopus trusts Gitea.** Octopus checks Gitea's certificate when it clones `deploy`; until it trusts
Gitea's CA, the deployment stops at `Cloning repository failed` and `The remote certificate is invalid
because of errors in the certificate chain: PartialChain`. Put Nexus's and Gitea's CAs in one file and
give it to Octopus with [OCTOPUS.md step 11](OCTOPUS.md#11-trust-nexus-and-add-it-as-a-docker-feed-optional)
(set `NEXUS_CA` there to this file), then restart Octopus as that step's **If not:** says. This line
makes the file `~/octopus-extra-cas.pem` from the two CA files:

**Linux, macOS, WSL (bash or zsh):**

```sh
cat "$HOME/nexus-ca.pem" "$HOME/gitea-ca.pem" > "$HOME/octopus-extra-cas.pem" && grep -c BEGIN "$HOME/octopus-extra-cas.pem"
```

**Windows (PowerShell):**

```powershell
Get-Content "$HOME\nexus-ca.pem", "$HOME\gitea-ca.pem" | Set-Content -Encoding ascii "$HOME\octopus-extra-cas.pem"; (Select-String -Path "$HOME\octopus-extra-cas.pem" -Pattern 'BEGIN').Count
```

**Expect:** `2`.

**Expect:** after the restart, `kubectl --kubeconfig <file> -n octopus logs octopus-octopus-deploy-0 -c
ca-bundle` prints one more CA than before (150 instead of 149 on Octopus 2026.3).

**The project.** **Projects** → **Add Project**: **Project name** `test-web-apps`, **Deploy to**
**Kubernetes**, **Are you using Argo CD?** **Yes**, and under **Lifecycle** `dev-test-prod` (OCTOPUS.md
step 10), then **Create Project**. The project's name must be `test-web-apps`: the Applications'
annotation `argo.octopus.com/project` (step 5) names it.

![Add New Project: test-web-apps, Kubernetes, using Argo CD Yes, lifecycle dev-test-prod](img/cd-octopus/03-add-project.jpg)

**The step that changes the image.** In the **Process Editor**, under **Argo CD**, add **Update Argo CD
Application Image Tags**. Under **Container Images** click **Add**: **Package feed** `nexus`, **Package
ID** `apps/test-web-apps` (`<NEXUS_REPO>/test-web-apps`), **Name** `test-web-apps`, then **Add
Package**. Keep the rest as it is: commit straight to `main` (**Git Commit Method** without pull
requests: Gitea has none in Octopus), **Step Verification** **Argo CD application is healthy** with a
180-second timeout, and **Trigger Sync** for all environments. **Save**.

![Reference a package: feed nexus, package ID apps/test-web-apps, name test-web-apps](img/cd-octopus/05-package-reference.jpg)

**Argo CD Applications** then shows **Applications ready to update** `3`. Right after you create the
project it may say **No Argo CD applications found matching the current scope** for a few minutes,
until the gateway reports the Applications again; reload the page.

![Process Editor: Applications ready to update 3, 1 container image will be updated](img/cd-octopus/06-apps-ready.jpg)

**An approval before prod.** **Add Step** → **Manual Intervention Required**: **Instructions** such as
`Approve the release for prod: check that test shows the new version.`, under **Environments** **Run
only for specific environments** `prod`, and under **Required** **Prevent this step from being skipped
when deploying**; **Save**. Then, in the step list's menu, **Reorder steps**: move it above the image
step, **Done**, **Save**. A release keeps the process it was created with: create releases after this.

![Process: 1 Manual Intervention Required (runs for prod), 2 Update Argo CD Application Image Tags; lifecycle dev-test-prod](img/cd-octopus/13-process-approval.jpg)

**A release for every new image.** **Triggers** → **Create Trigger** → **External feed**: **Release
trigger name** `new image in nexus`, and under **Trigger sources** tick `test-web-apps`; **Save**.
Octopus checks Nexus every few minutes; for a new tag it creates a release and, because `dev` is the
lifecycle's automatic phase, deploys it to `dev`.

![Create External Feed Trigger: lifecycle preview dev, test, prod; trigger source test-web-apps](img/cd-octopus/17-trigger-create.jpg)

## 9. Release a new version to dev, test and prod

1. Push a new version: run step 2's block again with `VERSION="1.0.1"`.
2. Within a few minutes the trigger creates a release (`0.0.1` and up; Octopus numbers releases itself)
   with `test-web-apps` `1.0.1` and deploys it to `dev`: Octopus commits the new tag into
   `envs/dev/deployment.yaml` as the user `octopus` (message `Octopus Deploy updated image versions`),
   asks ArgoCD to sync, and waits until the Application is healthy. Watch it under **Projects** →
   `test-web-apps` → **Releases**.

   ![Deploy test-web-apps release to dev: Step 1 Update Argo CD Application Image Tags, 1.1 trigger sync, 1.2 wait, all green](img/cd-octopus/10-deploy-dev-success.jpg)

3. Run step 5's check block: `dev` shows `test-web-apps 1.0.1`; `test` and `prod` still show the
   version they had.
4. Promote it: on the release's page click **Deploy to test...**, then **Deploy**. When `test` shows
   the new version, click **Deploy to prod...** → **Deploy**. The prod deployment stops at **Manual
   Intervention Required**: click **Assign to me**, read the instructions, then **Proceed** (or **Reject
   Deployment**). Until then nothing changes in `envs/prod`.

   ![Deploy to prod: Manual Intervention Required, This task is waiting for manual intervention and must be assigned before proceeding](img/cd-octopus/14-prod-waits-approval.jpg)

5. Run step 5's check block again: all three show the new version.

If a version does not start (its pods crash), the deployment fails after the step's 180-second wait
with `Verification failed due to the timeout being exceeded (180 seconds)`. The environment keeps
serving the version before: its Deployment starts a new pod next to the old one and removes the old
one only when the new one is ready. Deploy the release before it again (step 10) to put `deploy`
back in line with what runs.

Each deployment is one commit in `deploy`, which changes only that environment's
`envs/<env>/deployment.yaml`; Gitea's history of `deploy` is the record of what ran where.

Or deploy from a terminal, with Octopus's REST API: run this to deploy a release to an environment
(the prod approval still waits in the web page). It needs an Octopus API key typed first, as in
step 7 (1. and 2.); delete the key afterwards. On Windows, Windows must trust Octopus's CA ([OCTOPUS.md
step 9](OCTOPUS.md#9-sign-in)). Set `OCTOPUS_ADDRESS` (OCTOPUS.md step 4), `RELEASE` to
the release's number and `ENVIRONMENT` to `dev`, `test` or `prod`.

**Linux, macOS, WSL (bash or zsh):**

```sh
OCTOPUS_ADDRESS="192.168.10.70"
RELEASE="0.0.2"
ENVIRONMENT="test"

if ! command -v jq >/dev/null 2>&1; then echo "MISSING: jq (PREREQS.md)"
elif [ -z "${OCTOPUS_API_KEY:-}" ]; then echo "STOPPED: type the Octopus API key first (step 7, 2.)"
else
  CFG="$(mktemp)"; ( umask 077; printf 'header = "X-Octopus-ApiKey: %s"\n' "$OCTOPUS_API_KEY" > "$CFG" )
  oc() { curl -fsS --connect-timeout 20 --max-time 60 --cacert "$HOME/octopus-ca.pem" -K "$CFG" "$@"; }
  O="https://$OCTOPUS_ADDRESS/api/Spaces-1"
  if P="$(oc "$O/projects/test-web-apps" | jq -er .Id)" \
     && R="$(oc "$O/projects/$P/releases?take=100" | jq -er --arg v "$RELEASE" '.Items[] | select(.Version == $v) | .Id')" \
     && E="$(oc "$O/environments?name=$ENVIRONMENT" | jq -er '.Items[0].Id')"; then
    jq -n --arg r "$R" --arg e "$E" '{ReleaseId: $r, EnvironmentId: $e}' \
      | oc -H 'Content-Type: application/json' --data-binary @- "$O/deployments" | jq -r '"deployment \(.Id) started, task \(.TaskId)"'
  else
    echo "FAILED: no project test-web-apps, release $RELEASE or environment $ENVIRONMENT"
  fi
  rm -f "$CFG"
fi
```

**Windows (PowerShell):**

```powershell
$OCTOPUS_ADDRESS = "192.168.10.70"
$RELEASE = "0.0.2"
$ENVIRONMENT = "test"

if (-not $OCTOPUS_API_KEY) { "STOPPED: type the Octopus API key first (step 7, 2.)" } else {
  $H = @{ 'X-Octopus-ApiKey' = [Net.NetworkCredential]::new('', $OCTOPUS_API_KEY).Password }
  $O = "https://$OCTOPUS_ADDRESS/api/Spaces-1"
  try {
    $P = (Invoke-RestMethod -Headers $H "$O/projects/test-web-apps").Id
    $R = ((Invoke-RestMethod -Headers $H "$O/projects/$P/releases?take=100").Items | Where-Object { $_.Version -eq $RELEASE }).Id
    $E = ((Invoke-RestMethod -Headers $H "$O/environments?name=$ENVIRONMENT").Items | Select-Object -First 1).Id
    if (-not $R -or -not $E) { throw "no release $RELEASE or environment $ENVIRONMENT" }
    $D = Invoke-RestMethod -Headers $H -Method Post -ContentType 'application/json' -Body (@{ ReleaseId = $R; EnvironmentId = $E } | ConvertTo-Json) "$O/deployments"
    "deployment $($D.Id) started, task $($D.TaskId)"
  } catch { "FAILED: $($_.Exception.Message)" }
}
```

<!-- DRAFT: Expect/If not; the sh form ran on the lab as an equivalent script 2026-11-14 12:10-12:13 (Deployments-28..30); the PowerShell form not run on Windows yet. -->

## 10. Roll prod back

To put `prod` back on the version it had, deploy the earlier release to `prod` again: on that release's
page, **Deploy to prod...** → **Deploy** (or the block in step 9 with its `RELEASE`). It waits for the
same approval; after **Proceed**, Octopus commits the earlier tag into `envs/prod/deployment.yaml` and
ArgoCD rolls it out. Run step 5's check block: `prod` shows the earlier version, `dev` and `test` keep
the new one.

![Deploy release 0.0.3 to prod (the rollback): approval, then the image step, sync and wait, all green](img/cd-octopus/19-rollback-prod.jpg)

## 11. Build the image with Tekton instead (optional)

## 12. Rotate the tokens (optional)

## 13. Clean up (optional)

Do this when you no longer need the example. It removes only what this guide made; Octopus, Nexus,
Gitea, ArgoCD and the clusters stay.

1. In Octopus: **Projects** → `test-web-apps` → **Settings** → the menu (⋮) → **Delete**; then
   **Infrastructure** → **Argo CD Instances** → `<VKS_CLUSTER>-argocd` → the menu → **Delete** (the
   gateway stops reporting); then **Manage** → **Git Credentials** → `gitea-deploy` → **Delete**.
2. Run the block below. On the Supervisor it deletes the three Applications, which deletes the app in
   the three namespaces, and waits until they are gone; then the project `test-web-apps`, ArgoCD's login
   for `deploy` and Gitea's CA in ArgoCD. In the app's cluster it deletes the three namespaces; in
   Octopus's cluster it uninstalls the gateway and deletes its namespace. It stops before deleting
   anything of the project if an Application is still there. Run again, it says what is already gone.
   Set the values as in steps 5 and 7.

<details>
<summary><b>Linux, macOS, WSL (bash or zsh)</b></summary>

```sh
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
ARGOCD_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
OCTOPUS_CLUSTER="my-octopus-cluster"
GITEA_ADDRESS="192.168.10.60"

K() { kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$ARGOCD_NAMESPACE" "$@"; }
for E in dev test prod; do K delete applications.argoproj.io "test-web-apps-$E" --ignore-not-found --wait=false; done
N=""
for i in $(seq 60); do
  if ! N="$(K get applications.argoproj.io test-web-apps-dev test-web-apps-test test-web-apps-prod --ignore-not-found -o name)"; then N="FAILED"; break; fi
  [ -z "$N" ] && break
  sleep 5
done
if [ -n "$N" ]; then
  echo "FAILED: Applications not gone after 5 minutes ($N); the project, its login and the CA are kept"
else
  K delete appproject test-web-apps --ignore-not-found
  K delete secret repo-gitea-deploy --ignore-not-found
  if ! C="$(K get configmap argocd-tls-certs-cm -o jsonpath='{.data}')"; then
    echo "FAILED: cannot read argocd-tls-certs-cm; Gitea's CA in ArgoCD is kept"
  elif printf '%s' "$C" | grep -qF "\"$GITEA_ADDRESS\""; then
    K patch configmap argocd-tls-certs-cm --type json -p "[{\"op\":\"remove\",\"path\":\"/data/$GITEA_ADDRESS\"}]"
  else
    echo "Gitea's CA in ArgoCD: already gone"
  fi
  for E in dev test prod; do kubectl --kubeconfig "$HOME/.kube/${VKS_CLUSTER}.kubeconfig" delete namespace "test-web-apps-$E" --ignore-not-found; done
  helm uninstall gw --kubeconfig "$HOME/.kube/${OCTOPUS_CLUSTER}.kubeconfig" -n octopus-argocd-gateway --ignore-not-found
  kubectl --kubeconfig "$HOME/.kube/${OCTOPUS_CLUSTER}.kubeconfig" delete namespace octopus-argocd-gateway --ignore-not-found
fi
```

</details>

<!-- DRAFT: Windows twin; Expect/If not; run on the lab at the very end (it removes the test setup). -->

3. In Gitea, if you no longer need them: delete the repository `deploy` (its **Settings** → **Danger
   Zone**) and the users `octopus` and `argocd` (**Site Administration** → **User Accounts**), and
   delete `~/.config/vks-guides/cd-octopus`.

## References

- Octopus: [Argo CD in Octopus](https://octopus.com/docs/argo-cd)
