# Build an image with docker, push it to Harbor and run it (short version)

> [!NOTE]
> **Official documentation for this guide (Harbor, Docker and Kubernetes; Broadcom has none for
> building images)**
>
> - Harbor: [Pulling and Pushing Images](https://goharbor.io/docs/main/working-with-projects/working-with-images/pulling-pushing-images/), [Robot Accounts](https://goharbor.io/docs/main/administration/robot-accounts/)
> - Docker: [Verify repository client with certificates](https://docs.docker.com/engine/security/certificates/)
> - Kubernetes: [Pull an Image from a Private Registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

This builds the web app in [`argocd/test-web-apps`](../argocd/test-web-apps) with docker on Linux,
pushes it to a public Harbor project, and runs it in a VKS cluster. [IMAGE.md](IMAGE.md) is the
full guide (podman, macOS, Windows, checks); this one has only the commands.

You need:
- docker 29.5 or newer ([Prerequisites](PREREQS.md#podman-and-docker-optional)), `curl`,
  `openssl` and [kubectl](KUBECTL.md);
- a Harbor project and a robot account that may push to it ([HARBOR.md](HARBOR.md) step 10);
- the VKS cluster's kubeconfig ([LOGIN.md](LOGIN.md#get-the-vks-clusters-kubeconfig)).

Run every block in the same terminal, one after the other: the first block sets the values the
others use. If you open a new terminal, run the first block again.

## 0. Set your values

Change these to your own. `HARBOR_PULL_ROBOT` is needed only for a private project (step 5).

```sh
HARBOR_FQDN="harbor.env1.lab.test"
HARBOR_PROJECT="my-project"
HARBOR_ROBOT='robot$my-project+push'
HARBOR_PULL_ROBOT='robot$my-project+pull'
APP_NAMESPACE="harbor-demo"
IMAGE="$HARBOR_FQDN/$HARBOR_PROJECT/test-web-apps:v1"
IMAGE_PLATFORM="linux/amd64"
SRC="https://raw.githubusercontent.com/AndriyKalashnykov/vks-guides/666cba94ba517ac79d1c2ec505226192962477a3/argocd/test-web-apps"
export KUBECONFIG="$HOME/.kube/my-vks-cluster.kubeconfig"
mkdir -p "$HOME/image-simple"
cd "$HOME/image-simple"
```

Keep `HARBOR_ROBOT` in single quotes: the `$` is part of the name. `IMAGE_PLATFORM` is
`linux/amd64` because the VKS cluster's nodes are x86-64 machines. `KUBECONFIG` makes every
`kubectl` command in this terminal use your VKS cluster. `APP_NAMESPACE` is a Kubernetes namespace
that the guide creates inside your VKS cluster for this app, not a vSphere Namespace. `SRC` is the
address of the app's folder in this repository: the steps add a file name to it (`$SRC/Dockerfile`
and so on). Opened alone in a browser it shows `404: Not Found`, because GitHub serves single files
there, not folders.

## 1. Get Harbor's CA

Harbor signs its own certificate with its own CA, which your machine does not know. This downloads
that CA and prints its fingerprint. Compare the fingerprint with the one your Harbor administrator
gives you.

```sh
curl -sSk -o harbor-ca.crt "https://$HARBOR_FQDN/api/v2.0/systeminfo/getcert"
openssl x509 -in harbor-ca.crt -noout -subject -fingerprint -sha256
```

**Expect:** `subject=CN = Harbor CA` and a `sha256 Fingerprint=` line.

## 2. Trust Harbor's CA

docker refuses to talk to Harbor until it trusts this CA. This puts the CA where docker looks for
it. It asks for your password (`sudo`); run it as a block of its own.

```sh
sudo install -D -m 0644 harbor-ca.crt "/etc/docker/certs.d/$HARBOR_FQDN/ca.crt"
```

## 3. Build the image

This downloads the app's two files, changes its page so that you can tell your image from the
original, and builds the image for the cluster's nodes.

```sh
curl -sSO "$SRC/Dockerfile"
curl -sSO "$SRC/index.html"
sed -i 's|<h1>test-web-apps v1</h1>|<h1>test-web-apps v1, built with docker, from Harbor</h1>|' index.html
docker build --platform "$IMAGE_PLATFORM" -t "$IMAGE" .
```

**Expect:** the build's steps, then `naming to <your Harbor name>/<your project>/test-web-apps:v1`.

## 4. Push it to Harbor

Log in to Harbor as the robot account. docker asks for the robot's secret: paste it and press
Enter (nothing is shown). Run this line on its own.

```sh
docker login -u "$HARBOR_ROBOT" "$HARBOR_FQDN"
```

**Expect:** `Login Succeeded`.

Then upload the image to your project and log out, so the robot's login does not stay on this
machine:

```sh
docker push "$IMAGE"
docker logout "$HARBOR_FQDN"
```

**Expect:** the image's layers, `v1: digest: sha256:…`, then `Removing login credentials for …`.
In Harbor's web page, your project now lists `test-web-apps`.

## 5. Only for a private Harbor project: let the cluster log in - create pull secret

Skip this for a public project: anyone may pull from it, so the cluster needs no login. A private
project needs a robot that may pull, and the cluster must keep its login as a Secret.

First log in as the pull robot. docker asks for that robot's secret. `--config` makes docker save
this login in a new file, `~/image-simple/pull/config.json`, instead of your usual
`~/.docker/config.json`: that file then holds only this robot's login, which is what the cluster
needs. Run this line on its own.

```sh
docker --config "$HOME/image-simple/pull" login -u "$HARBOR_PULL_ROBOT" "$HARBOR_FQDN"
```

**Expect:** `Login Succeeded`.

Then create the app's namespace, copy `config.json` into it as the Secret `harbor-pull`, and
delete the file, which holds the robot's secret unencrypted:

```sh
curl -sSO "$SRC/namespace.yaml"
sed -i "s|^  name: test-web-apps$|  name: $APP_NAMESPACE|" namespace.yaml
kubectl apply -f namespace.yaml
kubectl -n "$APP_NAMESPACE" create secret generic harbor-pull --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson="$HOME/image-simple/pull/config.json"
rm -r "$HOME/image-simple/pull"
```

**Expect:** `namespace/harbor-demo created` and `secret/harbor-pull created`.

## 6. Run it

This downloads the app's three Kubernetes files and puts your values into them: the namespace's
name and your image from Harbor. The last line shows the lines that changed.

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

Only for a private project: this adds the Secret from step 5 to the app, so its pods log in to
Harbor when they pull the image.

```sh
sed -i 's|^      automountServiceAccountToken: false$|&\n      imagePullSecrets:\n        - name: harbor-pull|' deployment.yaml
grep -A1 imagePullSecrets deployment.yaml
```

**Expect:** `imagePullSecrets:` and `- name: harbor-pull`.

Now send the three files to the cluster and wait until the app's five pods run:

```sh
kubectl apply -f namespace.yaml -f deployment.yaml -f service.yaml
kubectl -n "$APP_NAMESPACE" rollout status deployment/test-web-apps
```

**Expect:** `namespace/harbor-demo`, `deployment.apps/test-web-apps` and `service/test-web-apps`
lines, then `deployment "test-web-apps" successfully rolled out`.

**If not:** the wait does not end: run `kubectl -n "$APP_NAMESPACE" get events`. `x509` means the
nodes do not trust Harbor (HARBOR.md step 11); `unauthorized` or `not found` means the project is
private and step 5 is missing, or the image name is wrong.

## 7. Open the app

The Service gives the app an address on your network. This waits until it has one (up to 2
minutes), prints it, and asks the app for its page.

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
run the block again in a minute.

## 8. Remove it (optional)

This deletes the app and its namespace from the VKS cluster, the image from this machine, and the
folder with the downloaded files.

```sh
kubectl delete namespace "$APP_NAMESPACE"
docker rmi "$IMAGE"
cd "$HOME"
rm -r "$HOME/image-simple"
```

To stop trusting Harbor's CA (asks for your password; run it on its own):

```sh
sudo rm -r "/etc/docker/certs.d/$HARBOR_FQDN"
```

The image stays in Harbor: delete it in Harbor's web page (**Projects** → your project →
`test-web-apps` → **DELETE**).
