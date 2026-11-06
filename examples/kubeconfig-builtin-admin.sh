# kubeconfig-builtin-admin.sh
# For: the cluster's built-in administrator kubeconfig (kubernetes-admin)
# Produces: $HOME/<cluster>-kubernetes-admin.kubeconfig
# Valid for: until its certificate's end date (the end date it prints); cannot be taken from one holder
# Needs: ~/.kube/supervisor.kubeconfig with Can edit or Owner on VSPHERE_NAMESPACE
#
# Description:
#
# | field               | value                                                                                     |
# |---------------------|-------------------------------------------------------------------------------------------|
# | identity            | the cluster's own administrator, shared by every holder                                   |
# | what the file holds | a client certificate and key in group system:masters                                      |
# | the cluster sees    | kubernetes-admin                                                                          |
# | rights              | everything (system:masters bypasses RBAC)                                                 |
# | namespaces used     | VSPHERE_NAMESPACE (where the Secret is)                                                   |
# | take it away        | can't be taken from one holder: no binding to delete; a new Secret keeps old copies valid |
# | renew               | run again: the same file, or a newer certificate after the cluster rotates it             |
# | meant for           | the cluster's administrators only; the guides say not to send it                          |
# | needs on this host  | admin Supervisor login with Can edit or Owner (Can view: Forbidden)                       |

VSPHERE_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
BUILTIN_ADMIN_KUBECONFIG="$HOME/${VKS_CLUSTER}-kubernetes-admin.kubeconfig"

rm -f "$BUILTIN_ADMIN_KUBECONFIG.new"
if [ -e "$BUILTIN_ADMIN_KUBECONFIG" ] \
   && ! kubectl --kubeconfig "$BUILTIN_ADMIN_KUBECONFIG" config get-contexts -o name 2>/dev/null | grep -qxF -- "${VKS_CLUSTER}-admin@${VKS_CLUSTER}"; then
  echo "FAILED: $BUILTIN_ADMIN_KUBECONFIG holds another login, not this cluster's; it is kept"
elif ( umask 077
     kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VSPHERE_NAMESPACE" get secret "${VKS_CLUSTER}-kubeconfig" \
       -o go-template='{{.data.value | base64decode}}' > "$BUILTIN_ADMIN_KUBECONFIG.new" ) \
   && kubectl --kubeconfig "$BUILTIN_ADMIN_KUBECONFIG.new" config view >/dev/null 2>&1; then
  mv "$BUILTIN_ADMIN_KUBECONFIG.new" "$BUILTIN_ADMIN_KUBECONFIG"
  kubectl --kubeconfig "$BUILTIN_ADMIN_KUBECONFIG" config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' \
    | base64 -d | openssl x509 -noout -subject -enddate
  echo "acts as: $(kubectl --kubeconfig "$BUILTIN_ADMIN_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')"
  echo "everything in the cluster: $(kubectl --kubeconfig "$BUILTIN_ADMIN_KUBECONFIG" auth can-i '*' '*')"
  echo "WARNING: this is the cluster's built-in administrator, the file the guides say not to send: every holder is the same admin and cannot be taken away alone (no binding to delete) until the end date above"
else
  rm -f "$BUILTIN_ADMIN_KUBECONFIG.new"
  echo "FAILED: no kubeconfig read (see the kubectl error above); $BUILTIN_ADMIN_KUBECONFIG is as it was"
fi

echo
echo "Next: use the file in this terminal:"
echo "  export KUBECONFIG=\"$BUILTIN_ADMIN_KUBECONFIG\""
echo "  kubectl auth whoami"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "Or one command without export:"
echo "  kubectl --kubeconfig \"$BUILTIN_ADMIN_KUBECONFIG\" auth whoami"
