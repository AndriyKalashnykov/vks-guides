# Operate and observe

All optional. Monitoring needs Helm ([Get started](GET-STARTED.md)) or ArgoCD ([GitOps and
CI/CD](GITOPS-CICD.md)); observability needs monitoring and Helm.

| guide | what it is |
|---|---|
| [Headlamp: a web console for a VKS cluster](HEADLAMP.md) | Broadcom's Headlamp add-on, accounts with the least rights and tokens for them, optional access by name through Contour, and the Prometheus and Kubescape plugins |
| [Monitor a VKS cluster](MONITORING.md) | Prometheus, Alertmanager and Grafana in a VKS cluster, from the upstream kube-prometheus-stack chart, with Helm or ArgoCD |
| [Send a VKS cluster's logs to VCF Operations](LOGGING.md) | Broadcom's Fluent Bit add-on, sending the cluster's logs over HTTPS to Log Management in VCF Operations |
| [See a VKS cluster's logs and traces in Grafana](OBSERVABILITY.md) | Loki and Jaeger in the cluster, Broadcom's Fluent Bit add-on sending logs to Loki, a sample app with linked logs and traces, and the cluster in VCF Operations |

## Tested on

✅ every block run, "part" some blocks run, — not run.

On VCF 9.1.1 with VKS 3.8.0 (Kubernetes v1.37.1):

| guide | Ubuntu (bash, zsh) | AlmaLinux 10 (bash) | Photon OS 5 (bash) | Arch Linux (bash) | Windows PowerShell 5.1 | WSL 2 Ubuntu (bash, as root) |
|---|---|---|---|---|---|---|
| [Headlamp](HEADLAMP.md) | part | ✅ | — | — | ✅ | part |
| [Monitor a VKS cluster](MONITORING.md) | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| [Send logs to VCF Operations](LOGGING.md) | part | part | part | — | part | — |
| [Logs and traces in Grafana](OBSERVABILITY.md) | part | ✅ | part | — | part | part |

Back to [README](../README.md).
