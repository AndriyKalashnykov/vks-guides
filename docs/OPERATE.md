# Operations and observability

All optional. Monitoring needs Helm ([Getting started](GET-STARTED.md)) or ArgoCD ([GitOps and
CI/CD](GITOPS-CICD.md)); observability needs monitoring and Helm.

| guide | what it is |
|---|---|
| [Headlamp: a web console for a VKS cluster](HEADLAMP.md) | Broadcom's Headlamp add-on, logging in with your own SSO token, optional accounts with the least rights and tokens for them, optional access by name through Contour, and the Prometheus and Kubescape plugins |
| [Monitor a VKS cluster](MONITORING.md) | Prometheus, Alertmanager and Grafana in a VKS cluster, from the upstream kube-prometheus-stack chart, with Helm or ArgoCD |
| [Send a VKS cluster's logs to VCF Operations](LOGGING.md) | Broadcom's Fluent Bit add-on, sending the cluster's logs over HTTPS to Log Management in VCF Operations |
| [See a VKS cluster's logs and traces in Grafana](OBSERVABILITY.md) | Loki and Jaeger in the cluster, Broadcom's Fluent Bit add-on sending logs to Loki, a sample app with linked logs and traces, and the cluster in VCF Operations |

On one cluster use either MONITORING.md or the Prometheus add-on of HEADLAMP.md step 11.1, not
both. Logging and Observability share one Fluent Bit add-on; each guide's step says how to
keep the other's output.

## Tested on

Where each guide in this group was run, on which OS and with which versions: [Tested on](TESTED.md#operations-and-observability).

Back to [README](../README.md).
