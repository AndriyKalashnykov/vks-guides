# GitOps and CI/CD

ArgoCD first. For build and deploy on every push, use Gitea and Tekton, or GitLab instead of both.
With GitLab, read [CICD.md's Prerequisites](CICD.md#prerequisites) before you create any cluster:
GitLab's cluster needs a worker with its own image disk (tested with 40 GiB), made with
[CLUSTER.md](CLUSTER.md#9-create-the-cluster-with-kubectl-and-a-yaml-file) step 9, not
[ARGOCD.md](ARGOCD.md#6-create-a-vks-cluster-with-argocd) step 6. Octopus Deploy, for releases
promoted through dev, test and prod, needs none of the other guides here except Nexus, for its step
11.

| guide | what it is |
|---|---|
| [Create a VKS cluster and deploy an app with ArgoCD](ARGOCD.md) | the ArgoCD Service, a VKS cluster made from Git, and a test app ArgoCD keeps in sync |
| [Run Nexus Repository in a VKS cluster](NEXUS.md) | Nexus Repository Community Edition with PostgreSQL in a VKS cluster: a Docker registry on one HTTPS address, with a push user and a pull user, that VKS clusters pull from |
| [Run Gitea in a VKS cluster](GITEA.md) | a self-hosted Git server with a web page, in one pod of a VKS cluster, that other machines such as ArgoCD can clone from |
| [Run Tekton in a VKS cluster](TEKTON.md) | a CI/CD engine that runs each build step as a pod, with a sample pipeline started by an HTTP request |
| [Run GitLab in a VKS cluster](GITLAB.md) | GitLab Community Edition, Git and CI/CD in one product, in one pod of a VKS cluster, with a runner that runs each CI job as a pod; an alternative to Gitea and Tekton |
| [Build and deploy on every push](CICD.md) | a push to a Git repository builds the image in the VKS cluster, pushes it to the container registry (Harbor) and has ArgoCD roll it out, with Gitea and Tekton or with GitLab |
| [Run Octopus Deploy in a VKS cluster](OCTOPUS.md) | a release server that promotes releases through dev, test and prod, with SQL Server Express, in a VKS cluster |

## Tested on

Where each guide in this group was run, on which OS and with which versions: [Tested on](TESTED.md#gitops-and-cicd).

Back to [README](../README.md).
