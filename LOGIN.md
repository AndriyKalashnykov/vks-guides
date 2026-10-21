# Log in to the Supervisor and a guest cluster

You log in to the Supervisor with the VCF CLI and your vCenter SSO user, then read your guest
cluster's kubeconfig from it. Needs [kubectl](KUBECTL.md), the [VCF CLI](VCF.md), and from
[Prerequisites](PREREQS.md): `curl`, `unzip`, `openssl` (Windows PowerShell needs nothing extra). Have these at hand:

- the Supervisor's IP address or DNS name, and vCenter's DNS name;
- an SSO user with a role on your vSphere Namespace (for example `administrator@vsphere.local`),
  and its password;
- the vSphere Namespace's name and, once you see it in
  [Check your vSphere Namespace](#check-your-vsphere-namespace), the guest cluster's name.

Run the sections in order, in one terminal. After that, you need only
[Renew the Supervisor login](#renew-the-supervisor-login) when the login ends, and
[Log out](#log-out) when you are done.

## Get the vCenter CA

By default the Supervisor's certificate is issued by vCenter's own CA, which this machine does
not trust yet. This downloads vCenter's CAs so the login can check that it is talking to your
real Supervisor. The download itself is not checked (`curl -k`), so it is saved as `CA_FILE.new`
until you have compared its fingerprints with the ones your vCenter administrator gives you.
Skip this section only if you will log in without the check.

```sh
VCENTER_FQDN="vcsa.example.test"     # vCenter DNS name
CA_FILE="$HOME/.kube/vcenter-ca.pem"

TMP="$(mktemp -d)"
if ! curl -fsSk --max-time 60 -o "$TMP/certs.zip" "https://${VCENTER_FQDN}/certs/download.zip"; then
  echo "FAILED: download from https://${VCENTER_FQDN}"
elif ! unzip -oqj "$TMP/certs.zip" -d "$TMP/certs" || [ -z "$(find "$TMP/certs" -name '*.0')" ]; then
  echo "FAILED: no CA certificate in the download from https://${VCENTER_FQDN}"
else
  mkdir -p "$(dirname "$CA_FILE")"
  find "$TMP/certs" -name '*.0' -exec cat {} + > "$CA_FILE.new"
  find "$TMP/certs" -name '*.0' -exec openssl x509 -in {} -noout -subject -fingerprint -sha256 \;
  echo "saved as $CA_FILE.new"
fi
rm -rf "$TMP"
```

Windows (PowerShell):

```powershell
$VCENTER_FQDN = "vcsa.example.test"      # vCenter DNS name
$CA_FILE = "$HOME\.kube\vcenter-ca.pem"

$TMP = Join-Path $env:TEMP ([guid]::NewGuid()); New-Item -ItemType Directory -Path $TMP | Out-Null
curl.exe -fsSk --max-time 60 -o "$TMP\certs.zip" "https://$VCENTER_FQDN/certs/download.zip"
if ($LASTEXITCODE -ne 0) {
  "FAILED: download from https://$VCENTER_FQDN"
} else {
  Expand-Archive -Force -Path "$TMP\certs.zip" -DestinationPath "$TMP\certs" -ErrorAction SilentlyContinue
  $CERTS = Get-ChildItem -Recurse -Path "$TMP\certs" -Filter '*.0' -ErrorAction SilentlyContinue
  if (-not $CERTS) {
    "FAILED: no CA certificate in the download from https://$VCENTER_FQDN"
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $CA_FILE) | Out-Null
    $CERTS | Get-Content | Set-Content -Encoding ascii -Path "$CA_FILE.new"
    foreach ($C in $CERTS) {
      $X = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $C.FullName
      $H = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($X.RawData))
      "subject=$($X.Subject)"
      "sha256 Fingerprint=$($H.Replace('-', ':'))"
    }
    "saved as $CA_FILE.new"
  }
}
Remove-Item -Recurse -Force $TMP
```

**Expect:** for each CA, a `subject=` line (vCenter's own names `CA` and `vsphere`) and a
`sha256 Fingerprint=…` line (`SHA256 Fingerprint=` on macOS), then `saved as …`. Every CA
listed will be trusted for the login, so each fingerprint must match one from your
administrator, ignoring colons and upper/lower case. When they all match, keep the file:

```sh
CA_FILE="$HOME/.kube/vcenter-ca.pem"

mv "$CA_FILE.new" "$CA_FILE" && echo "kept $CA_FILE"
```

Windows (PowerShell):

```powershell
$CA_FILE = "$HOME\.kube\vcenter-ca.pem"

Move-Item -Force "$CA_FILE.new" $CA_FILE; if ($?) { "kept $CA_FILE" }
```

**If not:**
- `FAILED: download …`: `VCENTER_FQDN` is wrong, or this machine cannot reach vCenter. The
  `curl:` line above it says which.
- `FAILED: no CA certificate …`: the address answered, but it is not vCenter. Check
  `VCENTER_FQDN`.
- A fingerprint that matches none of your administrator's: do not keep the file. Check
  `VCENTER_FQDN`. A company proxy that replaces HTTPS certificates also causes this.

## Type your SSO password

The login reads the password from this terminal, so it is never on a command line or in your
shell history. Paste this line on its own, then type the password; nothing is shown as you type
(PowerShell shows `*`).

```sh
printf 'SSO password: '; IFS= read -rs SSO_PASSWORD; echo
```

Windows (PowerShell):

```powershell
$SSO_PASSWORD = Read-Host 'SSO password' -AsSecureString
```

**Expect:** a new prompt. The password stays in this terminal until you close it or run
[Log out](#log-out); in a new terminal, run this line again.

## Log in to the Supervisor

Get the password right first: **a few failed logins in a row lock the SSO user for some
minutes.** Your vCenter administrator sees the limit in the vSphere Client under Administration →
Single Sign-On → Configuration → Lockout Policy; hardened vCenters often allow only 3. This saves the login in
`SUPERVISOR_KUBECONFIG`, a kubeconfig of its own, so your other kubeconfigs are not changed.

`SUPERVISOR_CA` is the CA from [Get the vCenter CA](#get-the-vcenter-ca). Set it to `""` to log
in without checking the Supervisor's certificate: then someone between you and the Supervisor
could capture your password, and `vcf` keeps skipping the check for this login.

```sh
SUPERVISOR_ENDPOINT="10.0.0.10"                       # Supervisor IP or FQDN
SSO_USERNAME="administrator@vsphere.local"
SUPERVISOR_CA="$HOME/.kube/vcenter-ca.pem"            # "" = do not check the certificate
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

if [ -n "$SUPERVISOR_CA" ]; then TLS="--ca-certificate=$SUPERVISOR_CA"; else TLS="--insecure-skip-tls-verify"; fi
if [ -z "$SSO_PASSWORD" ]; then
  echo "FAILED: no password in this terminal; run the line under Type your SSO password"
elif [ -n "$SUPERVISOR_CA" ] && [ ! -s "$SUPERVISOR_CA" ]; then
  echo "FAILED: not found: $SUPERVISOR_CA"
elif mkdir -p "$(dirname "$SUPERVISOR_KUBECONFIG")" \
     && KUBECONFIG="$SUPERVISOR_KUBECONFIG" VCF_CLI_VSPHERE_PASSWORD="$SSO_PASSWORD" \
        vcf context create supervisor --type k8s --endpoint "https://${SUPERVISOR_ENDPOINT}" \
          --username "$SSO_USERNAME" --auth-type basic "$TLS"; then
  kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" config use-context supervisor
else
  echo "FAILED: login (see the vcf error above)"
fi
```

Windows (PowerShell):

```powershell
$SUPERVISOR_ENDPOINT = "10.0.0.10"                    # Supervisor IP or FQDN
$SSO_USERNAME = "administrator@vsphere.local"
$SUPERVISOR_CA = "$HOME\.kube\vcenter-ca.pem"         # "" = do not check the certificate
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$TLS = if ($SUPERVISOR_CA) { "--ca-certificate=$SUPERVISOR_CA" } else { "--insecure-skip-tls-verify" }
if (-not $SSO_PASSWORD) {
  "FAILED: no password in this terminal; run the line under Type your SSO password"
} elseif ($SUPERVISOR_CA -and -not (Test-Path $SUPERVISOR_CA)) {
  "FAILED: not found: $SUPERVISOR_CA"
} else {
  New-Item -ItemType Directory -Force -Path (Split-Path $SUPERVISOR_KUBECONFIG) | Out-Null
  $OLD_KUBECONFIG = $env:KUBECONFIG; $env:KUBECONFIG = $SUPERVISOR_KUBECONFIG
  $env:VCF_CLI_VSPHERE_PASSWORD = [Net.NetworkCredential]::new('', $SSO_PASSWORD).Password
  vcf context create supervisor --type k8s --endpoint "https://$SUPERVISOR_ENDPOINT" `
    --username $SSO_USERNAME --auth-type basic $TLS
  $RC = $LASTEXITCODE
  Remove-Item Env:VCF_CLI_VSPHERE_PASSWORD; $env:KUBECONFIG = $OLD_KUBECONFIG
  if ($RC -eq 0) {
    kubectl --kubeconfig $SUPERVISOR_KUBECONFIG config use-context supervisor
  } else {
    "FAILED: login (see the vcf error above)"
  }
}
```

**Expect:** `Logged in successfully`, a list of contexts, then
`Switched to context "supervisor"`. The login lasts about 10 hours.

**If not:**
- `FAILED: no password in this terminal`: run the line under
  [Type your SSO password](#type-your-sso-password), then this block again.
- `FAILED: not found: …`: run [Get the vCenter CA](#get-the-vcenter-ca), including its
  `mv` block, or set `SUPERVISOR_CA=""` to log in without the check.
- `context "supervisor" already exists`: run [Log out](#log-out), then the password line and this
  block again.
- A connection error: check `SUPERVISOR_ENDPOINT`.
- A certificate error (`x509: …`) with `SUPERVISOR_CA` set: that CA did not issue the
  Supervisor's certificate. Check `VCENTER_FQDN` in [Get the vCenter CA](#get-the-vcenter-ca).
  If it is right, your administrator replaced the Supervisor's certificate: ask them for its CA
  and set `SUPERVISOR_CA` to that file. With an IP address in `SUPERVISOR_ENDPOINT`, also try
  the Supervisor's DNS name.
- A login error: check `SSO_USERNAME`, and run the password line again. Mind the lock-out.
- `Failed to install plugin 'telemetry:…'` before the output: harmless; the command still runs.

`--auth-type basic` is the SSO user and password. A Supervisor that logs you in through a web
page or an external identity provider (Okta, Entra ID) is not covered here.

## Check your vSphere Namespace

This checks that your SSO user can see your vSphere Namespace, and lists the guest clusters in
it.

```sh
VKS_NAMESPACE="my-namespace"
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" get namespace "$VKS_NAMESPACE" \
  && kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get clusters.cluster.x-k8s.io
```

Windows (PowerShell):

```powershell
$VKS_NAMESPACE = "my-namespace"
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

kubectl --kubeconfig $SUPERVISOR_KUBECONFIG get namespace $VKS_NAMESPACE
if ($LASTEXITCODE -eq 0) { kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get clusters.cluster.x-k8s.io }
```

**Expect:** your namespace, `Active`, then a table whose `NAME` column holds your guest cluster.

**If not:**
- `NotFound`: check `VKS_NAMESPACE`.
- `Forbidden`: your SSO user has no role on this namespace, or got it after you logged in. Ask a
  vCenter administrator for the role, then [Log out](#log-out) and log in again.
- `Unauthorized`: the login has ended. Run [Renew the Supervisor login](#renew-the-supervisor-login).
- `No resources found`: the namespace has no guest cluster yet. Creating one is not covered here.

## Get the guest cluster's kubeconfig

This reads the guest cluster's kubeconfig from the Supervisor and saves it as
`GUEST_KUBECONFIG`, readable only by you (on Windows, your profile folder already is). It is the cluster's shared administrator login, not
yours: anyone with the file has full control of the cluster, it keeps working after the
Supervisor login ends, and it cannot be taken back from one person. Keep it private.

```sh
VKS_NAMESPACE="my-namespace"
VKS_CLUSTER="my-guest-cluster"                        # from the NAME column above
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"
GUEST_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"

rm -f "$GUEST_KUBECONFIG.new"
if ( umask 077
     kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VKS_NAMESPACE" get secret "${VKS_CLUSTER}-kubeconfig" \
       -o go-template='{{.data.value | base64decode}}' > "$GUEST_KUBECONFIG.new" ) \
   && kubectl --kubeconfig "$GUEST_KUBECONFIG.new" config view >/dev/null 2>&1; then
  mv "$GUEST_KUBECONFIG.new" "$GUEST_KUBECONFIG"
  kubectl --kubeconfig "$GUEST_KUBECONFIG" get nodes
else
  rm -f "$GUEST_KUBECONFIG.new"
  echo "FAILED: no kubeconfig read (see the kubectl error above); $GUEST_KUBECONFIG is as it was"
fi
```

Windows (PowerShell):

```powershell
$VKS_NAMESPACE = "my-namespace"
$VKS_CLUSTER = "my-guest-cluster"                     # from the NAME column above
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"
$GUEST_KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"

$KC = kubectl --kubeconfig $SUPERVISOR_KUBECONFIG -n $VKS_NAMESPACE get secret "${VKS_CLUSTER}-kubeconfig" `
  -o go-template='{{.data.value | base64decode}}'
if ($LASTEXITCODE -eq 0 -and $KC) {
  Set-Content -Encoding ascii -Path "$GUEST_KUBECONFIG.new" -Value $KC
  kubectl --kubeconfig "$GUEST_KUBECONFIG.new" config view *> $null
}
if ($LASTEXITCODE -eq 0 -and $KC) {
  Move-Item -Force "$GUEST_KUBECONFIG.new" $GUEST_KUBECONFIG
  kubectl --kubeconfig $GUEST_KUBECONFIG get nodes
} else {
  Remove-Item -Force -ErrorAction SilentlyContinue "$GUEST_KUBECONFIG.new"
  "FAILED: no kubeconfig read (see the kubectl error above); $GUEST_KUBECONFIG is as it was"
}
```

**Expect:** the cluster's nodes, each `Ready`.

**If not:**
- `FAILED: no kubeconfig read`, under `secrets "<name>-kubeconfig" not found`: check
  `VKS_CLUSTER`, or the cluster is still being created.
- … under `Forbidden`: your role on the namespace cannot read the kubeconfig; ask for the
  **Edit** role, then [Log out](#log-out) and log in again.
- … under `Unauthorized`: run [Renew the Supervisor login](#renew-the-supervisor-login).
- A node `NotReady`: the cluster is still starting, or a node has a problem; ask its
  administrator.

## Use the guest cluster

This makes the guest cluster `kubectl`'s default in this terminal. Set `VKS_CLUSTER` as above.

```sh
VKS_CLUSTER="my-guest-cluster"

export KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
kubectl config current-context
```

Windows (PowerShell):

```powershell
$VKS_CLUSTER = "my-guest-cluster"

$env:KUBECONFIG = "$HOME\.kube\${VKS_CLUSTER}.kubeconfig"
kubectl config current-context
```

**Expect:** a context named after your cluster. In a new terminal, run this block again. Then
[match kubectl to the cluster's version](KUBECTL.md#match-the-clusters-version).

## Renew the Supervisor login

Only when a `kubectl` command to the Supervisor answers
`error: You must be logged in to the server (Unauthorized)`. The guest cluster's kubeconfig does
not need it. Set `SUPERVISOR_CA` to the value you logged in with: a different one switches the
login to the other mode without saying so. It logs in with your password again, so in a new
terminal run the [password line](#type-your-sso-password) first, and mind the lock-out.

```sh
SUPERVISOR_CA="$HOME/.kube/vcenter-ca.pem"            # the value you logged in with
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

if [ -n "$SUPERVISOR_CA" ]; then TLS="--ca-certificate=$SUPERVISOR_CA"; else TLS="--insecure-skip-tls-verify"; fi
if [ -z "$SSO_PASSWORD" ]; then
  echo "FAILED: no password in this terminal; run the line under Type your SSO password"
elif [ -n "$SUPERVISOR_CA" ] && [ ! -s "$SUPERVISOR_CA" ]; then
  echo "FAILED: not found: $SUPERVISOR_CA"
else
  KUBECONFIG="$SUPERVISOR_KUBECONFIG" VCF_CLI_VSPHERE_PASSWORD="$SSO_PASSWORD" \
    vcf context refresh supervisor "$TLS"
fi
```

Windows (PowerShell):

```powershell
$SUPERVISOR_CA = "$HOME\.kube\vcenter-ca.pem"         # the value you logged in with
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$TLS = if ($SUPERVISOR_CA) { "--ca-certificate=$SUPERVISOR_CA" } else { "--insecure-skip-tls-verify" }
if (-not $SSO_PASSWORD) {
  "FAILED: no password in this terminal; run the line under Type your SSO password"
} elseif ($SUPERVISOR_CA -and -not (Test-Path $SUPERVISOR_CA)) {
  "FAILED: not found: $SUPERVISOR_CA"
} else {
  $OLD_KUBECONFIG = $env:KUBECONFIG; $env:KUBECONFIG = $SUPERVISOR_KUBECONFIG
  $env:VCF_CLI_VSPHERE_PASSWORD = [Net.NetworkCredential]::new('', $SSO_PASSWORD).Password
  vcf context refresh supervisor $TLS
  Remove-Item Env:VCF_CLI_VSPHERE_PASSWORD; $env:KUBECONFIG = $OLD_KUBECONFIG
}
```

**Expect:** `Successful re-authentication completed for context "supervisor"`, or
`Token is still active. Skipped the token refresh …` when the login had not ended. Then run the
command that answered `Unauthorized` again.

**If not:**
- `FAILED: no password in this terminal`: run the [password line](#type-your-sso-password), then
  this block again.
- `FAILED: not found: …`: set `SUPERVISOR_CA` to the value you logged in with (`""` if you
  logged in without the check).
- `context supervisor not found`: you are not logged in. Run
  [Log in to the Supervisor](#log-in-to-the-supervisor).
- `Token is still active`, and the command still answers `Unauthorized`: the login is not the
  cause. Check that the command uses `--kubeconfig "$HOME/.kube/supervisor.kubeconfig"`.
- A login error: check the password, and mind the lock-out.

## Log out

This deletes the Supervisor login with its namespace contexts, its kubeconfig, `vcf`'s log files
(they hold a copy of the login token, valid until its 10 hours are over) and the password in this
terminal. The guest cluster's kubeconfig is kept; delete it with `rm` if you no longer need it.

```sh
SUPERVISOR_KUBECONFIG="$HOME/.kube/supervisor.kubeconfig"

KUBECONFIG="$SUPERVISOR_KUBECONFIG" vcf context delete supervisor -y --skip-delete-kubeconfig-context
KUBECONFIG="$SUPERVISOR_KUBECONFIG" vcf context list
unset SSO_PASSWORD
rm -f "$SUPERVISOR_KUBECONFIG"
rm -rf "$HOME/.config/vcf/logs"
```

Windows (PowerShell):

```powershell
$SUPERVISOR_KUBECONFIG = "$HOME\.kube\supervisor.kubeconfig"

$OLD_KUBECONFIG = $env:KUBECONFIG; $env:KUBECONFIG = $SUPERVISOR_KUBECONFIG
vcf context delete supervisor -y --skip-delete-kubeconfig-context
vcf context list
$env:KUBECONFIG = $OLD_KUBECONFIG
Remove-Variable SSO_PASSWORD -ErrorAction SilentlyContinue
Remove-Item -Force -ErrorAction SilentlyContinue $SUPERVISOR_KUBECONFIG
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$HOME\.config\vcf\logs"
```

**Expect:** the list shows no `supervisor` context. `context supervisor not found` means you
were already logged out.

Back to [README](README.md).
