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

<!-- DRAFT: filled from the lab runs; see reports/CD-OCTOPUS design v2.md -->

## 1. Check what is in place

## 2. Push the first version to Nexus

## 3. Serve Gitea over HTTPS and create the deploy repository

## 4. Prepare the app cluster

## 5. Create the ArgoCD project and the three Applications

## 6. Give the gateway its ArgoCD token

## 7. Connect Octopus to ArgoCD (the gateway)

## 8. Create the Octopus project

## 9. Release 1.0.0 to dev, test and prod

## 10. Release a new version and roll back

## 11. Build the image with Tekton instead (optional)

## 12. Rotate the tokens (optional)

## 13. Clean up (optional)

## References

- Octopus: [Argo CD in Octopus](https://octopus.com/docs/argo-cd)
