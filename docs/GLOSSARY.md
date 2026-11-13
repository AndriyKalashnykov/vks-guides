# Glossary

The words the guides use for where things live, for logins and kubeconfig files, and for rights.

| word | what it is |
|---|---|
| vSphere Namespace | the vCenter object on the Supervisor that holds VKS clusters; you give people roles on it in vCenter (**Can view**, **Can edit**, **Owner**) |
| Local Consumption Interface | the web page of a vSphere Namespace on the Supervisor, at `https://<Supervisor address>/appplatform0/#/namespaces/<vSphere Namespace>`: its VMs, VKS clusters, containers, images, network services and volumes ([USER-LCI.md](USER-LCI.md)); the same page is the namespace's **Resources** tab in the vSphere Client |
| Read-only (vCenter role) | a vCenter role that lets a user see vCenter objects; not a vSphere Namespace role |
| namespace | a folder inside one VKS cluster for a team's workloads, made with kubectl; not the vSphere Namespace |
| kubeconfig | a file that tells `kubectl` (the Kubernetes command-line tool, [KUBECTL.md](KUBECTL.md)) and other Kubernetes tools which server to talk to and how to log in: the server's address and certificate, and your login (a *token*, a certificate, or a command that signs you in through a browser); a *context* in it pairs the two (the ServiceAccount and certificate files of [ADMIN-GRANT-ACCESS.md](ADMIN-GRANT-ACCESS.md) also name a namespace: `VKS_CLUSTER_NAMESPACE`, or `default` with `"*"`) |
| cluster, user (in a kubeconfig) | two kinds of entry in a kubeconfig: a *cluster* is a server's address and certificate, a *user* is a stored login (a token, a certificate, or a command that signs you in through a browser). Not a vSphere cluster and not an SSO user |
| context | an entry in a kubeconfig that pairs one cluster with one user: "this server, as this login". One kubeconfig can hold several; its *current-context* is the one `kubectl` uses when a command does not name one |
| `~/.kube/config` | the kubeconfig `kubectl` uses when nothing else is named (Windows: `%USERPROFILE%\.kube\config`) |
| `KUBECONFIG` | an environment variable naming the kubeconfig to use instead (several files: separated by `:`, on Windows `;`). A command's `--kubeconfig <file>` overrides it |
| `config.yaml` | the VCF CLI's own list of your saved logins (`~/.config/vcf/config.yaml`; Windows: `%USERPROFILE%\.config\vcf\config.yaml`). `kubectl` never reads it, and you never edit it |
| `vcf` context | an entry in `config.yaml`: a name, the kubeconfig file it uses and a context in that file. Its *currentContext* is the one `vcf` commands use. `vcf context use` sets both that and the kubeconfig's current-context |
| ServiceAccount | a login that lives inside the cluster, not an SSO or identity provider user; in [ADMIN-GRANT-ACCESS.md](ADMIN-GRANT-ACCESS.md) for a tool, a team, or a person who needs the whole cluster; workloads also run as one |
| token | the key of one login, written into the kubeconfig: whoever holds a copy is that login, because the token is what proves who you are. Most expire (a Supervisor login's token is temporary; a ServiceAccount token lasts the days its administrator set); an administrator token made with `DAYS="never"` ([ADMIN-GRANT-ACCESS.md](ADMIN-GRANT-ACCESS.md#make-the-administrator-token), as Broadcom KB 423015 describes) does not |
| hand-out | a kubeconfig a cluster administrator makes and sends to a person, a team or a tool ([KUBECONFIG.md](KUBECONFIG.md#3-hand-a-file-over)): the ServiceAccount token, administrator token and personal certificate files of [ADMIN-GRANT-ACCESS.md](ADMIN-GRANT-ACCESS.md), which work for whoever holds a copy. Not the cluster's administrator kubeconfig, and not a file a `vcf` login writes |
| `cluster-admin` | the built-in role for everything in the cluster |
| `edit` | the built-in role to create, change and delete most things in one namespace, its Secrets included; it can act as any ServiceAccount there, but cannot change who has rights |
| `view` | the built-in role to read most things in one namespace, but not Secrets or who has rights |
| RoleBinding, ClusterRoleBinding | what gives a user, a group or a ServiceAccount a role: in one namespace, or in the whole cluster |

Back to [README](../README.md).
