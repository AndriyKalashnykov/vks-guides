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
          Y="$(printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: test-web-apps\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app.kubernetes.io/name: test-web-apps\n  template:\n    metadata:\n      labels:\n        app.kubernetes.io/name: test-web-apps\n    spec:\n      automountServiceAccountToken: false\n      imagePullSecrets:\n        - name: nexus-pull\n      securityContext:\n        runAsNonRoot: true\n        runAsUser: 101\n        runAsGroup: 101\n        seccompProfile:\n          type: RuntimeDefault\n      containers:\n        - name: web\n          image: %s/%s/test-web-apps:1.0.0\n          ports:\n            - name: http\n              containerPort: 8080\n          securityContext:\n            allowPrivilegeEscalation: false\n            readOnlyRootFilesystem: true\n            capabilities:\n              drop: ["ALL"]\n          resources:\n            requests:\n              cpu: 50m\n              memory: 32Mi\n            limits:\n              memory: 128Mi\n          volumeMounts:\n            - name: tmp\n              mountPath: /tmp\n      volumes:\n        - name: tmp\n          emptyDir: {}\n' "$NEXUS_REGISTRY" "$NEXUS_REPO")"
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

<!-- DRAFT: Windows twin; Expect/If not from the lab run of this exact block. -->

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

<!-- DRAFT: Windows twin; Expect/If not (incl. x509 for ~2 min, MEASURED 2026-11-13: hard refresh fixed it). -->

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

## 8. Create the Octopus project

## 9. Release 1.0.0 to dev, test and prod

## 10. Release a new version and roll back

## 11. Build the image with Tekton instead (optional)

## 12. Rotate the tokens (optional)

## 13. Clean up (optional)

## References

- Octopus: [Argo CD in Octopus](https://octopus.com/docs/argo-cd)
