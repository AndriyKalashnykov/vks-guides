# Build a container image with docker, push it and run it (short version) (Harbor example)

> [!NOTE]
> **Official documentation for this guide (Harbor, Docker and Kubernetes; Broadcom has none for
> building images)**
>
> - Harbor: [Pulling and Pushing Images](https://goharbor.io/docs/main/working-with-projects/working-with-images/pulling-pushing-images/), [Robot Accounts](https://goharbor.io/docs/main/administration/robot-accounts/)
> - Docker: [Verify repository client with certificates](https://docs.docker.com/engine/security/certificates/)
> - Kubernetes: [Pull an Image from a Private Registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

This builds the web app in [`argocd/test-web-apps`](../argocd/test-web-apps) with docker on Linux,
pushes it to a Harbor project (public, or private with step 5), and runs it in a VKS cluster.
[IMAGE.md](IMAGE.md) is the full guide (podman, macOS, Windows, checks); this one has only the
commands.

Run every block in the same terminal, one after the other: the first block sets the values the
others use. If you open a new terminal, first point kubectl at your VKS cluster again with
SUPERVISOR-LOGIN.md's [Make it the default in this
terminal](SUPERVISOR-LOGIN.md#make-it-the-default-in-this-terminal), then run the first block again.

## Prerequisites

- docker 29.5 or newer ([PREREQS.md](PREREQS.md#podman-and-docker-optional)), `curl`,
  `openssl` and [kubectl](KUBECTL.md);
- a Harbor project and a robot account (a Harbor login for programs, not a person) that may push to
  it ([HARBOR.md step 10](HARBOR.md#10-create-a-project-and-a-robot-account)), and [HARBOR.md step
  11](HARBOR.md#11-check-that-a-vks-cluster-can-pull-from-harbor) passed on this cluster (done by
  you or your Harbor administrator);
- for a private project, also a robot that may only pull: in Harbor's web page, as in HARBOR.md
  step 10, *In Harbor's web page*, with only **Repository** → **Pull** ticked. Its name is
  `robot$` and the name you type;
- `kubectl` pointed at your VKS cluster in this terminal: download its kubeconfig in the vSphere
  Client ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#download-the-vks-clusters-kubeconfig-from-the-vsphere-client)) or
  with the VCF CLI ([SUPERVISOR-LOGIN.md](SUPERVISOR-LOGIN.md#get-the-vks-clusters-kubeconfig)), then
  [make it the default in this terminal](SUPERVISOR-LOGIN.md#make-it-the-default-in-this-terminal);
- one free load-balancer address, for the app (step 6).

The connections this guide needs, for a firewall (all TCP, besides DNS; for a registry, also
the hosts in [Registry hosts](PREREQS.md#registry-hosts-for-a-firewall)):

| from | to | port | for |
|---|---|---|---|
| your machine (laptop or jump box) | Harbor's address | 443 | Harbor's CA (step 1), login and push (steps 4, 5) |
| your machine (laptop or jump box) | `raw.githubusercontent.com` | 443 | the app's files (steps 3, 5, 6) |
| your machine (laptop or jump box) | `docker.io` | 443 | the app's base image (step 3) |
| your machine (laptop or jump box) | the VKS cluster's API address (in its kubeconfig) | 6443 | kubectl (steps 5 to 8) |
| the VKS cluster's nodes | Harbor's address | 443 | pulling the app's image (step 6) |
| your machine and your browser | the app's address (step 7) | 80 | opening the app (step 7) |

## 0. Set your values

Run this first, and again in any new terminal (after SUPERVISOR-LOGIN.md's *Make it the default in this
terminal*): the other blocks use the values it sets. Set them to
your own: your Harbor and project, the two robot accounts (below the block), the app's namespace
inside your VKS cluster (a separate area for the app, not a vSphere Namespace). The block also
creates the folder `~/image-simple` for the downloaded files and moves this terminal into it.

```sh
HARBOR_FQDN="harbor.env1.lab.test"
HARBOR_PROJECT="my-project"
HARBOR_ROBOT='robot$my-project+push'
HARBOR_PULL_ROBOT='robot$my-project-pull'
APP_NAMESPACE="harbor-demo"
IMAGE="$HARBOR_FQDN/$HARBOR_PROJECT/test-web-apps:v1"
IMAGE_PLATFORM="linux/amd64"
SRC="https://raw.githubusercontent.com/AndriyKalashnykov/vks-guides/666cba94ba517ac79d1c2ec505226192962477a3/argocd/test-web-apps"
mkdir -p "$HOME/image-simple"
cd "$HOME/image-simple"
```

**Expect:** no output; the terminal is now in `~/image-simple`.

The two robot accounts:

- `HARBOR_ROBOT` (push): used on your machine in step 4 to upload the image. It may push and pull.
- `HARBOR_PULL_ROBOT` (pull): used only for a private project, in step 5. Its login becomes the
  Secret `harbor-pull` inside the VKS cluster, so the nodes can download the image. It may only
  pull, so whoever can read that Secret cannot change your images.

Keep `HARBOR_ROBOT` in single quotes: the `$` is part of the name. `IMAGE_PLATFORM` is
`linux/amd64` because the VKS cluster's nodes are x86-64 machines. `APP_NAMESPACE` is a
Kubernetes namespace that the guide creates inside your VKS cluster for this app, not a vSphere
Namespace. `SRC` is the address of the app's folder in this repository: the steps add a file name
to it (`$SRC/Dockerfile` and so on). Opened alone in a browser it shows `404: Not Found`, because
GitHub serves single files there, not folders.

## 1. Get Harbor's CA

docker can push to Harbor only once your machine trusts Harbor's certificate, and Harbor signs it
with its own CA (certificate authority), which your machine does not know. This downloads that CA
into the file `harbor-ca.crt` in this folder and prints its fingerprint. Compare the fingerprint
with the one your Harbor administrator gives you; step 2 then installs the file.

```sh
curl -fsSk -o harbor-ca.crt "https://$HARBOR_FQDN/api/v2.0/systeminfo/getcert"
openssl x509 -in harbor-ca.crt -noout -subject -fingerprint -sha256
```

**Expect:** `subject=CN = Harbor CA` (newer OpenSSL: `subject=CN=Harbor CA`) and a
`sha256 Fingerprint=` line.

**If not:** a `curl:` error: check `HARBOR_FQDN`; if it is right, this Harbor publishes no CA (it
uses your organization's certificate, HARBOR.md step 13): get `harbor-ca.crt` from your Harbor
administrator and save it in this folder.

## 2. Trust Harbor's CA

docker refuses to talk to Harbor until it trusts this CA. This copies `harbor-ca.crt` into the
folder where docker looks for Harbor's CA. Afterwards docker on this machine trusts your Harbor.
It asks for your password (`sudo`); run it as a block of its own.

```sh
sudo install -D -m 0644 harbor-ca.crt "/etc/docker/certs.d/$HARBOR_FQDN/ca.crt"
```

**Expect:** no output.

**If not:** `cannot stat 'harbor-ca.crt'`: run step 1 in `~/image-simple`.

## 3. Build the image

You build your own copy of the app here, so that you have an image to push. This downloads the
app's two files (`Dockerfile`, the build recipe, and `index.html`, its page), changes the page so
that you can tell your image from the original, and builds the image for the cluster's nodes. You
get the image on this machine, named as `IMAGE` says, ready for step 4.

```sh
curl -sSO "$SRC/Dockerfile"
curl -sSO "$SRC/index.html"
sed -i 's|<h1>test-web-apps v1</h1>|<h1>test-web-apps v1, built with docker, from Harbor</h1>|' index.html
docker build --platform "$IMAGE_PLATFORM" -t "$IMAGE" .
```

**Expect:** the build's steps, then `naming to <your Harbor name>/<your project>/test-web-apps:v1`.

**If not:** a `curl:` error or a failed base-image pull: this machine must reach
`raw.githubusercontent.com` and `docker.io` (Prerequisites).

## 4. Push it to Harbor

To upload the image, docker must first log in to Harbor as the push robot (`HARBOR_ROBOT`). This
logs in: docker asks for the robot's secret: paste it and press Enter (nothing is shown). Run
this line on its own. docker keeps the login until the next block logs out.

```sh
docker login -u "$HARBOR_ROBOT" "$HARBOR_FQDN"
```

**Expect:** `Login Succeeded` (docker without a credential helper first warns that the login is
stored unencrypted; the logout below removes it).

**If not:** `x509: …`: do step 2. `unauthorized`: the robot's name or secret is wrong.

Run this right after the login, in the same terminal. It uploads the image to your project, then
logs out, so the robot's login does not stay on this machine. Afterwards the image is in Harbor,
where the cluster's nodes pull it from in step 6:

```sh
docker push "$IMAGE"
docker logout "$HARBOR_FQDN"
```

**Expect:** the image's layers, `v1: digest: sha256:…`, then `Removing login credentials for …`.
In Harbor's web page, your project now lists `test-web-apps`.

**If not:** `insufficient_scope`: the robot may not push to this project.

## 5. Only for a private project: let the cluster pull from it

Skip this for a public project: anyone may pull from it, so the cluster needs no login. A private
project needs a robot that may pull, and the cluster must keep its login as a Secret, the
cluster's way to store a password.

First log in as the pull robot (`HARBOR_PULL_ROBOT`), to get a file that holds its login. docker
asks for that robot's secret: paste it and press Enter. `--config` makes docker save this login in
a new file, `~/image-simple/pull/config.json`, instead of your usual `~/.docker/config.json`: that
file then holds only this robot's login, which is what the cluster needs. Run this line on its own.

```sh
docker --config "$HOME/image-simple/pull" login -u "$HARBOR_PULL_ROBOT" "$HARBOR_FQDN"
```

**Expect:** `WARNING! Your credentials are stored unencrypted in
'/home/<you>/image-simple/pull/config.json'`, then `Login Succeeded`.

**If not:** no such warning: a docker credential helper keeps the secret elsewhere, and
`config.json` holds no login for the cluster. Create the Secret as
[IMAGE.md step 5](IMAGE.md#5-only-for-a-private-project-let-the-cluster-pull-from-it) does instead.

Run this line first: it prints which cluster kubectl talks to in this terminal, so that the next
block does not create the namespace and the Secret in another cluster. It changes nothing.

```sh
kubectl config current-context
```

**Expect:** the name of your VKS cluster's context.

**If not:** another cluster's name: stop, and point kubectl at your VKS cluster with SUPERVISOR-LOGIN.md's
[Make it the default in this terminal](SUPERVISOR-LOGIN.md#make-it-the-default-in-this-terminal). `error:
current-context is not set`: do that too. Then run this line again.

Run this right after that line. It creates the app's namespace in the VKS cluster
(`APP_NAMESPACE`), copies `config.json` into it as the Secret `harbor-pull`, and deletes the file,
which holds the robot's secret unencrypted. Afterwards the cluster holds the pull robot's login,
and step 6 tells the app to use it:

```sh
curl -sSO "$SRC/namespace.yaml"
sed -i "s|^  name: test-web-apps$|  name: $APP_NAMESPACE|" namespace.yaml
kubectl apply -f namespace.yaml
kubectl -n "$APP_NAMESPACE" create secret generic harbor-pull --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson="$HOME/image-simple/pull/config.json"
rm -r "$HOME/image-simple/pull"
```

**Expect:** `namespace/harbor-demo created` and `secret/harbor-pull created`.

**If not:** `localhost:8080` and `connection refused`: kubectl is not pointed at your VKS
cluster; [make its kubeconfig the default in this
terminal](SUPERVISOR-LOGIN.md#make-it-the-default-in-this-terminal), then run the login line above and this
block again.

## 6. Deploy the app

To run the app, the cluster needs its three Kubernetes files. This downloads them:
`namespace.yaml` (a separate area in the cluster for the app), `deployment.yaml` (the app: five
copies, called pods, of your image) and `service.yaml` (the app's network address). It puts your
values into them: the namespace's name and your image from Harbor. The last line shows the lines
that changed. Nothing changes in the cluster yet.

```sh
curl -sSO "$SRC/namespace.yaml"
curl -sSO "$SRC/deployment.yaml"
curl -sSO "$SRC/service.yaml"
sed -i "s|^  name: test-web-apps$|  name: $APP_NAMESPACE|" namespace.yaml
sed -i "s|namespace: test-web-apps|namespace: $APP_NAMESPACE|" deployment.yaml service.yaml
sed -i "s|image: .*|image: $IMAGE|" deployment.yaml
grep -H "^  name:\|namespace:\|image:" namespace.yaml deployment.yaml service.yaml
```

**Expect:** `namespace.yaml:  name: harbor-demo`, `namespace: harbor-demo` in the other two files,
and `image: <your Harbor name>/<your project>/test-web-apps:v1`. The `name: test-web-apps` lines
are the app's own name and stay as they are.

**Only for a private project:** run this when your project is private, after step 5. It adds the
Secret `harbor-pull` from step 5 to `deployment.yaml`, so the app's pods log in to Harbor when they
pull the image. The last line shows the added lines.

```sh
sed -i 's|^      automountServiceAccountToken: false$|&\n      imagePullSecrets:\n        - name: harbor-pull|' deployment.yaml
grep -A1 imagePullSecrets deployment.yaml
```

**Expect:** `imagePullSecrets:` and `- name: harbor-pull`.

Run this line first, as in step 5: it prints which cluster kubectl talks to in this terminal, and
changes nothing.

```sh
kubectl config current-context
```

**Expect:** the name of your VKS cluster's context.

**If not:** another cluster's name: stop, and point kubectl at your VKS cluster with SUPERVISOR-LOGIN.md's
[Make it the default in this terminal](SUPERVISOR-LOGIN.md#make-it-the-default-in-this-terminal). `error:
current-context is not set`: do that too. Then run this line again.

Now send the three files to the cluster and wait until the app's five pods run. This creates the
app's namespace (unless step 5 did), starts five pods from your Harbor image, and asks the load
balancer for an address. Afterwards the app runs in your VKS cluster, and step 7 opens it:

```sh
kubectl apply -f namespace.yaml -f deployment.yaml -f service.yaml
kubectl -n "$APP_NAMESPACE" rollout status deployment/test-web-apps
```

**Expect:** `namespace/harbor-demo`, `deployment.apps/test-web-apps` and `service/test-web-apps`
lines, then `deployment "test-web-apps" successfully rolled out`.

**If not:** `localhost:8080` and `connection refused`: kubectl is not pointed at your VKS
cluster; [make its kubeconfig the default in this
terminal](SUPERVISOR-LOGIN.md#make-it-the-default-in-this-terminal) and run this again. The wait does not
end: run `kubectl -n "$APP_NAMESPACE" get events`. `x509` means the nodes do not trust Harbor
(HARBOR.md step 11); `unauthorized` or `not found` means the project is private and step 5 is
missing, or the image name is wrong.

## 7. Open the app

Run this to see your image run. The Service (from `service.yaml`) gives the app an address on
your network. This waits until it has one (up to 2 minutes), prints it, and asks the app for its
page. You get the address to open in a browser.

```sh
kubectl -n "$APP_NAMESPACE" wait service/test-web-apps --for=jsonpath='{.status.loadBalancer.ingress}' --timeout=120s
APP_IP="$(kubectl -n "$APP_NAMESPACE" get service test-web-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "http://$APP_IP/"
curl -s "http://$APP_IP/" | grep h1
```

**Expect:** `service/test-web-apps condition met`, `http://<address>/` and
`<h1>test-web-apps v1, built with docker, from Harbor</h1>`. Open the address in a browser to see
the same page.

**If not:** `timed out waiting for the condition`: the Supervisor has given the app no address yet;
run the block again in a minute. Still no address: the Supervisor's load balancer has no address
left; see [IMAGE.md step 7](IMAGE.md#7-open-the-app), **If not**.

## 8. Remove it (optional)

Run this line first: the block after it deletes a namespace, so check that kubectl talks to your VKS
cluster in this terminal. It changes nothing.

```sh
kubectl config current-context
```

**Expect:** the name of your VKS cluster's context.

**If not:** another cluster's name: stop, and point kubectl at your VKS cluster with SUPERVISOR-LOGIN.md's
[Make it the default in this terminal](SUPERVISOR-LOGIN.md#make-it-the-default-in-this-terminal). `error:
current-context is not set`: do that too. Then run this line again.

Run this when you no longer need the app. It deletes the app and its namespace from the VKS
cluster, the image from this machine, and the folder with the downloaded files. Harbor's CA stays
trusted (the next block) and the image stays in Harbor (below).

```sh
kubectl delete namespace "$APP_NAMESPACE"
docker rmi "$IMAGE"
cd "$HOME"
rm -r "$HOME/image-simple"
```

**Expect:** `namespace "harbor-demo" deleted`, then docker's lines for the removed image.

**If not:** `namespaces "harbor-demo" not found`, `No such image` or `No such file or directory`:
that part was removed before (this is a second run); nothing is wrong.

Run this only if this machine will not use this Harbor with docker again. It removes Harbor's CA
from the folder where docker looks for it (it asks for your password; run it on its own). Afterwards
docker refuses to talk to this Harbor until you do step 2 again:

```sh
sudo rm -r "/etc/docker/certs.d/$HARBOR_FQDN"
```

**Expect:** no output.

The image stays in Harbor: delete it in Harbor's web page (**Projects** → your project →
**Repositories**, tick `test-web-apps` → **DELETE**).
