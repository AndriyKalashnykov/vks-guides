# CLAUDE.md

Copy-paste how-to guides for VMware vSphere Kubernetes Service (VKS), VCF 9.x: README.md links
docs/: PREREQS.md, KUBECTL.md, VCF.md, LOGIN.md, ACCESS.md, KUBECONFIG.md, KEYCLOAK.md, KEYCLOAK-VKS.md, NAMESPACE.md, CLUSTER.md, HARBOR.md, IMAGE.md, IMAGE-DOCKER.md, ARGOCD.md,
GITEA.md, TEKTON.md, GITLAB.md, CICD.md, ADDONS.md, HEADLAMP.md, HELM.md, MONITORING.md, LOGGING.md, OBSERVABILITY.md (screenshots in
docs/img/). Readers paste
blocks; there is nothing to build.

## Rules

- No Makefile, mise, env file or helper script. Each block sets the variables it uses at its top
  and works on its own; never rely on a variable from an earlier block. The one exception is
  IMAGE-DOCKER.md (owner's choice): a short docker-on-Linux walkthrough whose blocks share the
  values of its first block, run in one terminal, with no error handling, no block labels and no
  download timeouts.
- Every shell block is POSIX sh that runs in bash and zsh, labeled in bold
  `**Linux (Ubuntu, AlmaLinux, Photon OS), macOS, WSL (bash or zsh):**`. Where Windows applies, a
  bold `**Windows (PowerShell):**` twin follows, written for Windows PowerShell 5.1: `curl.exe` (not
  the `curl` alias), `Expand-Archive`, `Get-FileHash`, installs to
  `%LOCALAPPDATA%\Programs\vks-tools`. A block pair where either block is 15 lines or more
  sits in two `<details>` cuts whose `<summary><b>…</b></summary>` is the label. PREREQS.md
  blocks sit under OS headings and have no label.
- Wherever several OSs appear (labels, sections, lists), the order is Linux, macOS, Windows.
- Each guide opens with a `> [!NOTE]` callout, first line `**Official … documentation … for this
  guide**`, listing the official docs it follows (Broadcom VCF 9.1 TechDocs; kubernetes.io or the
  tool's own docs where Broadcom has none). Open a link before adding it.
- Each guide has a `## Prerequisites` chapter right after its intro: the guides to do first, each
  tool as a link to its guide (KUBECTL.md, VCF.md, HELM.md) or PREREQS.md (never its install),
  what this guide alone needs (roles, resources, load-balancer addresses), and a table
  "The connections this guide needs, for a firewall (all TCP, besides DNS…):"
  `| from | to | port | for |` with every connection its blocks open or make another component
  open (the nodes, ArgoCD); registries by name, with a link to PREREQS.md's Registry hosts.
- After a block: **Expect:** (the output that proves it worked) and **If not:** (what to do).
- Passwords are typed (`read -rs` / `Read-Host -AsSecureString`) and passed only as the
  `VCF_CLI_VSPHERE_PASSWORD` env var for one command; never on argv, never saved.
- Downloads use `--connect-timeout 20 --speed-time 60`; a file is replaced only after it checks out.
- Broadcom terms: "VKS cluster" (not guest/TKG cluster), "Supervisor", "vSphere Namespace",
  "VCF CLI". Text is minimal: what to run and what to expect, no notes or mechanism essays.

## Checking a change

- Syntax: extract every sh block and run `bash -n` and `zsh -n`; parse every PowerShell block with
  `[System.Management.Automation.Language.Parser]::ParseFile` in Windows PowerShell 5.1 (no pwsh
  on the dev host; use the Windows walkbox from nested-vsphere-lab: `make walkbox-vm-start
  WALKBOX_OS=windows`).
- Readers paste blocks into an interactive shell, so a block is run pasted, not only as a script:
  feed it to `bash -i` and `zsh -i` under a pseudo-terminal (`script -qec "zsh -i" /dev/null <
  block.sh`, with an empty `.zshrc` in a scratch `HOME`/`ZDOTDIR`) and check for `event not
  found`. Outside single quotes a `!` is followed by a space (`[ ! -f x ]`,
  `if ! cmd`); never in a `case` pattern such as `*[!a-z]*`
  (interactive zsh history-expands it). `[^…]` is not a fix: dash reads it differently.
- Where the terminal does not bracket the paste, a pasted block's later lines wait in the terminal,
  and sudo 1.9.14 or later (`use_pty` by default: Ubuntu, Debian) reads them: nothing may follow a
  line that runs `sudo`, so clean-up goes on that line (`fi; rm -rf "$TMP"`).
  `vcf context use` reads the password from stdin when the login token has expired, so the
  next pasted line becomes a failed login: write it `vcf context use supervisor </dev/null`
  (PowerShell: `$null | vcf context use supervisor`), which stops with `Unable to read password
  from terminal` instead, on every shell, also where the paste is bracketed and the password could
  have been typed (the reader renews the login and runs the block again).
- A behaviour change is run for real before README's "Tested on" table claims it. On the owner's
  nested-vsphere-lab the agent logs in itself, only through that checkout's make targets, which read
  the lab's own secrets, so it never handles the password and never asks the owner. On this host
  the guides' login is the VCF CLI context `supervisor` recording LOGIN.md's file
  `~/.kube/supervisor.kubeconfig` (check: `yq '.contexts[] | select(.name=="supervisor") |
  .clusterOpts.path' ~/.config/vcf/config.yaml`). Renew it with `make vcf-context-refresh
  VCF_REFRESH_CONTEXT=supervisor`; it sends nothing while the token has more than 5 minutes left.
  If `supervisor` records another file, re-point it (no password; tell the lab session first;
  the delete also removes `supervisor:<ns>` contexts): `vcf context delete supervisor -y
  --skip-delete-kubeconfig-context`, then `vcf context create supervisor --type k8s --kubeconfig
  "$HOME/.kube/supervisor.kubeconfig" --kubecontext supervisor --skip-create-related-contexts`,
  then refresh. If the context or that file is missing, ask the
  lab session. Never run `make login VCF_CONTEXT=supervisor` or `make kubectl-login
  VCF_CONTEXT=supervisor` (they overwrite the lab's own kubeconfig), or any `vcf context refresh`
  not run through `make vcf-context-refresh` (vcf writes the file `KUBECONFIG` names,
  `~/.kube/config` when unset, and re-records it). `make walkbox-login
  WALKBOX_OS=ubuntu|photon|almalinux|windows` logs a walkbox in (LOGIN.md's files:
  `~/.kube/supervisor.kubeconfig`, context `supervisor`); use it whenever a walkbox run needs the
  SSO password (one attempt per run: mind the lock-out).
- Coordinate every lab use with the nested-vsphere-lab session (find it with ListAgents, message
  it with SendMessage): announce before installing anything cluster-wide on a VKS cluster (CRDs,
  DaemonSets, host ports) or starting the walkbox, say when the lab is clean, and send it any lab
  finding. It owns vCenter, the Supervisor and VCF Operations; this repo's work stays inside the
  VKS cluster.
