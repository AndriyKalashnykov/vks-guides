# kubeconfig-sso-plugin.sh
# For: a person's own SSO login with the kubectl vSphere plugin (deprecated)
# Produces: ~/.kube/<cluster>-<user>.kubeconfig
# Valid for: 10 hours (log in again after)
# Needs: ~/.local/bin/kubectl-vsphere, ~/.kube/vcenter-ca.pem; asks for the password: bash ~/kubeconfig-sso-plugin.sh
#
# Description:
#
# | field               | value                                                                   |
# |---------------------|-------------------------------------------------------------------------|
# | identity            | the person's vCenter SSO account                                        |
# | what the file holds | the person's login token                                                |
# | the cluster sees    | sso:<user>@vsphere.local                                                |
# | rights              | same as the VCF CLI login                                               |
# | namespaces used     | VSPHERE_NAMESPACE                                                       |
# | take it away        | delete the person's RoleBinding and their role on the vSphere Namespace |
# | keeps working       | with edit: ServiceAccount tokens and workloads the person made (delete  |
# |                     | the workloads, re-create ServiceAccounts with rights, restart what uses |
# |                     | them); with Can edit or Owner: also logins they made                    |
# | renew               | run again (password)                                                    |
# | meant for           | a person without the VCF CLI                                            |
# | needs on this host  | the person's SSO password                                               |

SUPERVISOR_ENDPOINT="10.0.0.10"
SUPERVISOR_CA="$HOME/.kube/vcenter-ca.pem"
SSO_USER="alice@vsphere.local"
VSPHERE_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
VKS_USER_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}-${SSO_USER}.kubeconfig"

printf 'SSO password: '; IFS= read -rs SSO_PASSWORD; echo

case "$SSO_USER" in */*|*\\*|*:*) SSO_USER_OK="" ;; *@*) SSO_USER_OK="yes" ;; *) SSO_USER_OK="" ;; esac
if [ -z "$SSO_USER_OK" ]; then
  printf '%s\n' "STOPPED: SSO_USER is the full SSO user name, such as alice@vsphere.local: $SSO_USER"
elif [ -z "$SSO_PASSWORD" ]; then
  echo "FAILED: no password typed; run the script again"
else
  mkdir -p "$HOME/.kube" && ( umask 077; : >> "$VKS_USER_KUBECONFIG" ) && chmod 600 "$VKS_USER_KUBECONFIG"
  KUBECONFIG="$VKS_USER_KUBECONFIG" SSL_CERT_FILE="$SUPERVISOR_CA" KUBECTL_VSPHERE_PASSWORD="$SSO_PASSWORD" \
    "$HOME/.local/bin/kubectl-vsphere" login --server "$SUPERVISOR_ENDPOINT" --vsphere-username "$SSO_USER" \
    --tanzu-kubernetes-cluster-namespace "$VSPHERE_NAMESPACE" --tanzu-kubernetes-cluster-name "$VKS_CLUSTER" </dev/null \
    && chmod 600 "$VKS_USER_KUBECONFIG" \
    && kubectl --kubeconfig "$VKS_USER_KUBECONFIG" config use-context "$VKS_CLUSTER" >/dev/null \
    && echo "logged in as: $(kubectl --kubeconfig "$VKS_USER_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')" \
    || echo "FAILED: the login did not work (see the error above); nothing was changed"
fi
unset SSO_PASSWORD

echo
echo "Next: use the file in this terminal:"
echo "  export KUBECONFIG=\"$VKS_USER_KUBECONFIG\""
echo "  kubectl auth whoami"
echo "  kubectl -n <your namespace> auth can-i create deployments"
echo "Or one command without export:"
echo "  kubectl --kubeconfig \"$VKS_USER_KUBECONFIG\" auth whoami"
