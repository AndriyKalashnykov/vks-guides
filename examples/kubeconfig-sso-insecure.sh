# kubeconfig-sso-insecure.sh
# For: creates a kubeconfig for SSO_USER in VKS_CLUSTER (without the vCenter CA)
# Produces: ~/.kube/<cluster>-<user>.kubeconfig
# Valid for: 10 hours (log in again after)
# Needs: the VCF CLI and kubectl; the SSO password typed first, then . ~/kubeconfig-sso-insecure.sh
#
# Description:
#
# | field               | value                                                                                                            |
# |---------------------|------------------------------------------------------------------------------------------------------------------|
# | identity            | the person's vCenter SSO account                                                                                 |
# | what the file holds | the person's login token                                                                                         |
# | the cluster sees    | sso:<user>@vsphere.local                                                                                         |
# | rights              | what the admin bound to the name, or the person's group role on the vSphere Namespace (Can edit = cluster-admin) |
# | namespaces used     | VSPHERE_NAMESPACE (where the cluster is)                                                                         |
# | take it away        | delete the person's RoleBinding and their role on the vSphere Namespace                                          |
# | renew               | run again (password)                                                                                             |
# | meant for           | a person with a vCenter SSO account                                                                              |
# | needs on this host  | the person's SSO password                                                                                        |

SUPERVISOR_ENDPOINT="10.0.0.10"
SUPERVISOR_CA=""
SSO_USER="alice@vsphere.local"
VSPHERE_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_USER_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}-${SSO_USER}.kubeconfig"

case "$SSO_USER" in */*|*\\*|*:*) SSO_USER_OK="" ;; *@*) SSO_USER_OK="yes" ;; *) SSO_USER_OK="" ;; esac
if [ -n "$SUPERVISOR_CA" ]; then TLS="--ca-certificate=$SUPERVISOR_CA"; else TLS="--insecure-skip-tls-verify"; fi
if [ -z "$SSO_USER_OK" ]; then
  printf '%s\n' "STOPPED: SSO_USER is the full SSO user name, such as alice@vsphere.local: $SSO_USER"
elif [ -z "$SSO_PASSWORD" ]; then
  echo "FAILED: no password in this terminal; run the password line above"
elif [ -n "$SUPERVISOR_CA" ] && { [ ! -f "$SUPERVISOR_CA" ] || [ ! -s "$SUPERVISOR_CA" ]; }; then
  echo "FAILED: not found: $SUPERVISOR_CA"
elif { [ -n "$SUPERVISOR_CA" ] || echo "WARNING: SUPERVISOR_CA is empty: the Supervisor's certificate is not checked"; } \
     && mkdir -p "$HOME/.kube" && ( umask 077; : >> "$VKS_USER_KUBECONFIG" ) && chmod 600 "$VKS_USER_KUBECONFIG" \
     && { KUBECONFIG="$VKS_USER_KUBECONFIG" vcf context delete "${VKS_CLUSTER}-${SSO_USER}" -y --skip-delete-kubeconfig-context </dev/null >/dev/null 2>&1; true; } \
     && KUBECONFIG="$VKS_USER_KUBECONFIG" VCF_CLI_VSPHERE_PASSWORD="$SSO_PASSWORD" \
        vcf context create "${VKS_CLUSTER}-${SSO_USER}" --type k8s --endpoint "https://${SUPERVISOR_ENDPOINT}" \
          --username "$SSO_USER" --auth-type basic "$TLS" --skip-create-related-contexts \
          --workload-cluster-name "$VKS_CLUSTER" --workload-cluster-namespace "$VSPHERE_NAMESPACE" </dev/null \
     && kubectl --kubeconfig "$VKS_USER_KUBECONFIG" config use-context "${VKS_CLUSTER}-${SSO_USER}:${VKS_CLUSTER}" >/dev/null; then
  echo "logged in as: $(kubectl --kubeconfig "$VKS_USER_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')"
else
  echo "FAILED: login (see the error above)"
fi
unset SSO_PASSWORD

echo
echo "Next: use the file in this terminal:"
echo "  export KUBECONFIG=\"$VKS_USER_KUBECONFIG\""
echo "  kubectl auth whoami"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "Or one command without export:"
echo "  kubectl --kubeconfig \"$VKS_USER_KUBECONFIG\" auth whoami"
