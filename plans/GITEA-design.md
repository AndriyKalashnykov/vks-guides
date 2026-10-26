# GITEA.md design (phase 2, idea round) — 2026-10-26

Standalone guide "Run Gitea in a VKS cluster", same conventions as MONITORING.md (each block sets its own
variables, sh + Windows PowerShell 5.1 twins, Expect/If not, files under ~/.config/vks-guides/gitea).

Premises (claims to attack):
P1 A plain Deployment (not the Helm chart) is the right install: chart 12.7.0 fails PSA restricted with
   defaults and pulls frozen Bitnami images (measured phase 0).
P2 Gitea 28.2.0-rootless @sha256:94807314…3306, SQLite on a 5Gi PVC from the cluster's DEFAULT storage class
   (no storageClassName), Recreate strategy, uid 1000, readOnlyRootFilesystem, emptyDir /etc/gitea and /tmp,
   PSA restricted namespace `gitea`, requests 100m/256Mi limits 1/1Gi. Ran in phase 0 under restricted.
P3 SECRET_KEY and INTERNAL_TOKEN generated on the reader's machine (openssl rand -hex 32 | tr -d '\n';
   PS RandomNumberGenerator → hex), sent to a Secret over stdin, created with `create` (never replaced on a
   re-run: a new SECRET_KEY would make stored secrets undecryptable). Trailing newline breaks pushes (measured).
P4 Config only via GITEA__section__KEY env: INSTALL_LOCK=true, DISABLE_REGISTRATION=true, DISABLE_SSH=true,
   ROOT_URL=http://localhost:3000/ (all credentialed use through kubectl port-forward 3000:3000),
   [security] ALLOWED_HOST_LIST=private (needed later for webhooks to in-cluster Tekton; [webhook] key is
   deprecated in 28), [repository] ENABLE_PUSH_CREATE_USER=true so `git push` creates the repo (private by
   default) — no UI step to create a repo.
P5 Admin user: `kubectl exec deploy/gitea -- gitea admin user create --admin --username gitea-admin
   --email <var> --random-password --must-change-password`; prints the generated password once (same
   pattern as ARGOCD.md step 4 printing the initial admin password); reader logs in through the
   port-forward and must set a new password. No password on any argv. ("admin" is a reserved name.)
P6 Push: local repo with one README, `git push http://localhost:3000/gitea-admin/hello.git main`; git prompts
   for user/password (typed, not argv). Windows Git Credential Manager may refuse plain-HTTP remotes
   (allowUnsafeRemotes) — to be measured; fallback `git -c credential.helper= push`.
P7 Optional step: make a repo public and switch the Service to type LoadBalancer so other machines (ArgoCD on
   the Supervisor) clone anonymously over plain HTTP :3000; the guide says never log in or push through it.
P8 Uninstall: delete namespace `gitea` (PVC and data go with it). Upgrade/backup not covered.
P9 Readers need git (not in PREREQS.md); "You need:" links git-scm.com rather than editing PREREQS.

Steps: 1 check cluster (nodes, default SC, no gitea namespace) · 2 namespace · 3 keys Secret · 4 install +
rollout wait · 5 admin user · 6 open Gitea (port-forward), change password · 7 create repo by push ·
8 (optional) let other machines clone · 9 uninstall.
