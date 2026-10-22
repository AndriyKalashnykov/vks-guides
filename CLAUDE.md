# CLAUDE.md

Copy-paste how-to guides for VMware vSphere Kubernetes Service (VKS), VCF 9.x: README.md links
docs/: PREREQS.md, KUBECTL.md, VCF.md, LOGIN.md. Readers paste blocks; there is nothing to build.

## Rules

- No Makefile, mise, env file or helper script. Each block sets the variables it uses at its top
  and works on its own; never rely on a variable from an earlier block.
- Every shell block is POSIX sh that runs in bash and zsh, labeled in bold
  `**Linux, macOS, WSL (bash or zsh):**`. Where Windows applies, a bold
  `**Windows (PowerShell):**` twin follows, written for Windows PowerShell 5.1: `curl.exe` (not
  the `curl` alias), `Expand-Archive`, `Get-FileHash`, installs to
  `%LOCALAPPDATA%\Programs\vks-tools`. A block pair where either block is 15 lines or more
  sits in two `<details>` cuts whose `<summary><b>…</b></summary>` is the label. PREREQS.md
  blocks sit under OS headings and have no label.
- Wherever several OSs appear (labels, sections, lists), the order is Linux, macOS, Windows.
- Each guide opens with one line linking the official docs it follows (Broadcom VCF 9.1
  TechDocs; kubernetes.io where Broadcom has none). Open a link before adding it.
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
- A behaviour change is run for real before README's "Platforms" table claims it. The password login
  is run by the owner, never by an agent.
