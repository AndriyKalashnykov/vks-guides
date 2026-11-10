# CLAUDE.md

Copy-paste how-to guides for VMware vSphere Kubernetes Service (VKS), VCF 9.x. README.md links six
group pages (docs/GET-STARTED.md, ACCESS-SIGN-IN.md, CLUSTERS.md, IMAGES.md, GITOPS-CICD.md, OPERATE.md);
each lists its guides and the order to follow, and its `## Tested on` is one line linking its group's
table in docs/TESTED.md (owner, 2026-11-10: one page holds every guide's cells; a new guide gets a row
in its group page's guide table and one in its group's table in TESTED.md). docs/GLOSSARY.md is the one
word list: a guide links it and keeps no glossary table of its own (ADMIN-GRANT-ACCESS.md's `## Glossary`
and KUBECONFIG.md's `### The words used here` are one-line pointers kept for old links). The guides in docs/: PREREQS.md, KUBECTL.md, VCF.md, SUPERVISOR-LOGIN.md, USER-LOGIN.md, USER-KUBECONFIG.md, USER-IDP-LOGIN.md, ADMIN-GRANT-ACCESS.md, ADMIN-GRANT-ACCESS-IDP.md, KUBECONFIG.md, KEYCLOAK.md, KEYCLOAK-VKS.md, NAMESPACE.md, CLUSTER.md, HARBOR.md, IMAGE.md, IMAGE-DOCKER.md, ARGOCD.md, NEXUS.md,
GITEA.md, TEKTON.md, GITLAB.md, CICD.md, OCTOPUS.md, ADDONS.md, HEADLAMP.md, HELM.md, MONITORING.md, LOGGING.md, OBSERVABILITY.md (screenshots in
docs/img/). Readers paste
blocks; there is nothing to build.

## Rules

- `examples/` (owner's choice) holds runnable admin scripts built from guide blocks (`kubeconfig-*.sh`,
  `rolebinding-idp-group.sh`) and `examples/README.md` comparing them. They use the guides' placeholder values
  (no lab values), are not guides (no References, Prerequisites or Tested on row, not on group pages), and must follow
  the guide blocks they copy: a change to such a block updates its script in the same PR.
- `docs/img/access/which-way-in-light.svg` and `-dark.svg` (in ADMIN-GRANT-ACCESS.md under **Which way for
  which customer**, light and dark through `<picture>`) draw that chooser, the compare table and how each way is
  taken away: a change to any of those rows or behaviours updates both pictures and their alt text in the same PR.
  The same holds for the five per-way pictures `docs/img/access/way-<way>-light.svg`/`-dark.svg` at the top of
  each way's chapter (SSO, ServiceAccount token, administrator token, certificate; the IdP group in
  ADMIN-GRANT-ACCESS-IDP.md): a change that makes a label untrue, or moves what a label describes to another
  guide, updates that picture in the same PR.
  Every label in them is a statement from the guides: no versions, durations, paths or commands.
- LOGIN.md, ACCESS.md and ACCESS-IDP.md are moved-guide pages (owner): a title, then "Who are you? Start
  here", a table that sends each kind of reader (an administrator who logs in, an administrator who gives
  access, a person with an SSO account, a person sent a kubeconfig file, a person who signs in with an
  identity provider, a tool or pipeline with a token file) to the guide and step they need, then "Where the
  old guide went": one line naming the new guide and links from the old sections to their new homes. The
  three tables are the same: change them together. No References, Prerequisites, blocks or Tested on row; not in
  the guide list or on group pages.
- The person's steps live in the three person guides: USER-LOGIN.md (own SSO account), USER-KUBECONFIG.md (a
  sent file with a token or a certificate) and USER-IDP-LOGIN.md (an identity provider). An admin guide's
  step for the person is a pointer line that sends them there, plus only what the administrator must do or
  diagnose (precedent: ADMIN-GRANT-ACCESS.md's SSO steps 3 and 4). A section moved to another guide keeps its
  heading, byte for byte, with that pointer to its new home, so that old links keep resolving.
- No Makefile, mise, env file or helper script. Each block sets the variables it uses at its top
  and works on its own; never rely on a variable from an earlier block. The one exception is
  IMAGE-DOCKER.md (owner's choice): a short docker-on-Linux walkthrough whose blocks share the
  values of its first block, run in one terminal, with no error handling, no block labels, no
  download timeouts, and plain `kubectl` (the terminal's default kubeconfig, set by SUPERVISOR-LOGIN.md's *Make
  it the default in this terminal* in each new terminal, no `--kubeconfig`); a
  `kubectl config current-context` line comes before each block that changes the cluster. Its
  blocks still get **Expect:** and **If not:**.
- Every shell block is POSIX sh, besides `IFS= read -rs` for a typed password (bash and zsh
  only; dash rejects `-s`), and runs in bash and zsh, labeled in bold
  `**Linux, macOS, WSL (bash or zsh):**`. Where Windows applies, a
  bold `**Windows (PowerShell):**` twin follows, written for Windows PowerShell 5.1: `curl.exe` (not
  the `curl` alias), `Expand-Archive`, `Get-FileHash`, installs to
  `%LOCALAPPDATA%\Programs\vks-tools`. A block pair where either block is 15 lines or more
  sits in two `<details>` cuts whose `<summary><b>…</b></summary>` is the label. PREREQS.md
  blocks sit under OS headings and have no label, besides its three tool checks. A step that trusts a CA
  in the browser's store, whose commands differ per OS (KEYCLOAK-VKS.md step 8, USER-IDP-LOGIN.md step
  2), leads each block with **Linux:**, **macOS:**, **WSL:** and **Windows (PowerShell):** instead.
- In a PowerShell block, `elseif` and `else` never start a line: write `} elseif (…) {` and `} else {`. Typed
  line by line into a console, PowerShell 5.1 runs a complete top-level `if { }` at its line end, so the next
  line fails as "The term 'elseif' is not recognized" and its branch never runs (MEASURED 2026-11-10, PowerShell
  5.1.26100 with PSReadLine 2.0.0; a terminal paste that sends each line with Enter is INFERRED to behave the same).
  A `.ps1` run and the parser (`ParseInput`) accept it, so neither catches it. `catch` and `finally` may start a
  line (the console waits for them).
- Wherever several OSs appear (labels, sections, lists), the order is Linux, macOS, Windows.
- Block labels name no distribution or OS version; docs/TESTED.md says what
  was run. Where a command differs per distribution, the text or PREREQS.md names it.
- Each guide opens with its title and what it does, never with an official-docs box (owner, 2026-11-10).
  Its last chapter is `## References`, before "Back to README" (at the very end where a guide has no such
  line): the official docs it follows (Broadcom VCF 9.1 TechDocs; kubernetes.io or the tool's own docs
  where Broadcom has none), with a first line `**Official … documentation … for this guide**` where the
  list carries a version. Open a link before adding it.
- Each guide has a `## Prerequisites` chapter right after its intro: the guides to do first, each
  tool as a link to its guide (KUBECTL.md, VCF.md, HELM.md) or PREREQS.md (never its install),
  what this guide alone needs (roles, resources, load-balancer addresses), and a table
  "The connections this guide needs, for a firewall (all TCP, besides DNS…):"
  `| from | to | port | for |` with every connection its blocks open or make another component
  open (the nodes, ArgoCD); registries by name, with a link to PREREQS.md's Registry hosts.
  A row from the reader's own machine says `your machine (laptop or jump box)`.
  A guide that installs a product or add-on into a VKS cluster has, in Prerequisites, a paragraph
  that opens **The VKS cluster to make.** and gives the VM class and worker count for the base
  install and for each optional part, measured on the lab (requests and real use), never as
  millicores or MiB the reader must add up (a guide's own small test app needs no size). Control
  plane and examples use `best-effort-medium` (CLUSTER step 2 holds the measured why; KB 446139).
- After a block: **Expect:** (the output that proves it worked) and **If not:** (what to do).
- The Supervisor is named by `SUPERVISOR_CONTEXT="supervisor"` (one name per Supervisor: a-z,
  0-9 and `-`, not ending in `-keycloak`) and its file by
  `SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"`; no block writes either
  name out.
- Passwords are typed (`IFS= read -rs` / `Read-Host -AsSecureString`) and passed only as the
  `VCF_CLI_VSPHERE_PASSWORD` env var for one command; never on argv, never saved.
- A block whose create, update, delete, request body, wait or reported cause depends on jq
  checks `command -v jq` before any command that changes the cluster, the Supervisor or a
  server (local file writes and `vcf context use` may come first), and prints
  `MISSING: jq (PREREQS.md)`: empty output takes the wrong branch, deletes nothing, or loses a
  token a server already made.
- A delete, uninstall or update decided by a query's result fails closed (IMAGE-DOCKER.md too)
  wherever a failed or empty result would read as "remove" or "nothing uses it": read the query's
  exit code (for example sh `if ! X="$(…)"`, `X="$(…)" || X=FAILED` or
  `X="$(…)"; RC=$?`, no `2>/dev/null`; PowerShell `$global:LASTEXITCODE = $null` before, `-ne 0`
  after), with the query alone in `$(…)` (a pipe keeps only the last command's exit code: capture
  the raw output, then filter it), and stop with `FAILED: …` naming what was not removed. A piped
  query whose failure removes nothing (`kubectl get … | jq … | while read …; do kubectl delete …`)
  is fine. A shared add-on (cert-manager, Contour, Prometheus) is removed only
  after an in-block check that nothing uses it; a check namespace or Secret is deleted only when
  this run created it.
- Downloads use `--connect-timeout 20 --speed-time 60`; a file is replaced only after it checks out.
- Broadcom terms: "VKS cluster" (not guest/TKG cluster), "Supervisor", "vSphere Namespace",
  "VCF CLI". Text is minimal: what to run and what to expect, no notes or mechanism essays.

## Checking a change

- Syntax: extract every sh block and run `bash -n` and `zsh -n`; parse every PowerShell block with
  `[System.Management.Automation.Language.Parser]::ParseFile` in Windows PowerShell 5.1 (no pwsh
  on the dev host; use the Windows walkbox from nested-vsphere-lab: `make walkbox-vm-start
  WALKBOX_OS=windows`).
- Readers paste blocks into an interactive shell, so a block is run pasted, not only as a script:
  the checker below pastes it into interactive bash and zsh (do not hand-roll `script -qec`
  loops). Outside single quotes a `!` is followed by a space (`[ ! -f x ]`,
  `if ! cmd`); never in a `case` pattern such as `*[!a-z]*`
  (interactive zsh history-expands it). `[^…]` is not a fix: dash reads it differently.
  macOS's bash 3.2 also expands a `!` inside `'…'` when an odd number of `"` come before it on that
  line (it ignores `$(` nesting: `N="$(kubectl … -l '!x')"`): put such a value in a variable on its
  own line (`WORKERS='!x'`) and use `"$WORKERS"`. A `!` before `=` or a space is safe everywhere.
  Test with `docker run --rm -i --network none bash:3.2 timeout -s KILL 60 bash -i < block.sh`.
- Run the `/guide-block-check` skill's checker on every file a change touches that has sh
  blocks (group pages and README have none: a call with no sh block ends rc 2), whole files, in
  one call (or a few parallel calls for a whole-repo sweep). It runs its own self-test first,
  about 16 minutes per call, so run it in the background with its output in a file:
  `bash "$(readlink -f ~/.claude/commands)/../scripts/guide-block-check.sh" "$PWD/docs/X.md"`
  (one path per touched file). It pastes each sh block into this host's bash and zsh, raw and
  bracketed, with tools stubbed. Read its rc on its own line: only 0 is clean (1 FAIL, 2
  instrument, 3 INCONCLUSIVE), and the log must start with `self-check: N fixture verdicts
  match`. ADVISORY for `security` (macOS) and `wslpath` (WSL) is expected on Linux. It does not
  run PowerShell blocks (parse those on the Windows walkbox), and it runs no bash 3.2: still run
  the bash 3.2 test above. Measured 2026-11-04 on main acd023a: 328 blocks in 33 files, rc 0,
  about 37 minutes as three parallel calls.
- Where the terminal does not bracket the paste, a pasted block's later lines wait in the terminal,
  and sudo 1.9.14 or later (`use_pty` by default: Ubuntu, Debian) reads them: nothing may follow a
  line that runs `sudo`, so clean-up goes on that line (`fi; rm -rf "$TMP"`). `vcf context use`
  reads the password from stdin when the login token has expired, so the next pasted line becomes a
  failed login: write it `vcf context use "$SUPERVISOR_CONTEXT" </dev/null` (PowerShell: `$null |
  vcf context use $SUPERVISOR_CONTEXT`), which stops with `Unable to read password from terminal`
  instead (Windows: `… The handle is invalid`), on every shell, also where the paste is bracketed
  and the password could have been typed (the reader renews the login and runs the block again). Its
  exit code says nothing (it exits 1 after a switch when plugin discovery fails): capture its output
  and go on only when it holds `Successfully activated context '<name>'`, else print the output and
  `FAILED: the VCF CLI is not on context …`.
  A program that queries the terminal (`vcf cluster …` from plugin 3.7.1 on: termenv sends OSC 11
  and reads the answer from the terminal, not stdin) swallows the pasted lines still waiting, so
  nothing may follow the compound command that runs it; the check of its result goes inside that
  compound (`if vcf cluster … && …; then`).
- A behaviour change is run for real before docs/TESTED.md claims it. On the owner's
  nested-vsphere-lab the agent logs in itself, only through that checkout's make targets, which read
  the lab's own secrets, so it never handles the password and never asks the owner. On this host
  the guides' login is the VCF CLI context `supervisor` recording SUPERVISOR-LOGIN.md's file
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
  WALKBOX_OS=ubuntu|photon|almalinux|windows` logs a walkbox in (SUPERVISOR-LOGIN.md's files:
  `~/.kube/supervisor.kubeconfig`, context `supervisor`); use it whenever a walkbox run needs the
  SSO password (one attempt per run: mind the lock-out).
- Coordinate every lab use with the nested-vsphere-lab session (find it with ListAgents, message
  it with SendMessage): announce before installing anything cluster-wide on a VKS cluster (CRDs,
  DaemonSets, host ports) or starting the walkbox, say when the lab is clean, and send it any lab
  finding. It owns vCenter, the Supervisor and VCF Operations; this repo's work stays inside the
  VKS cluster.
- Walkboxes stay powered off when not in use (owner order): start one with `make walkbox-vm-start
  WALKBOX_OS=…` in nested-vsphere-lab (it prints the address, which can change; never hard-code it)
  and `make walkbox-vm-stop WALKBOX_OS=…` after the run (`WALKBOX_NAME=` for a second box). Guide
  blocks run for real (not the stubbed checks above) and lab reads and changes during guide work
  (kubectl with the Supervisor kubeconfig, curl, upgrades) run from a walkbox, not this host. Toward
  the lab, this host runs only nested-vsphere-lab's make targets (for example the `walkbox-*`
  targets, the `supervisor` login above with `make vcf-context-refresh`, and `make lab-capacity`).
  `make lab-capacity` is read-only but signs in to vCenter once (mind the lock-out); run it before
  making a VKS cluster.
