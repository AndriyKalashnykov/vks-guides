# kubeconfig-idp-group.sh
# For: the identity provider group's shared kubeconfig (no secret)
# Produces: $HOME/<cluster>-keycloak-sv.kubeconfig
# Valid for: no end: each person's sign-in lasts as long as their identity-provider session
# Needs: ~/.kube/supervisor.kubeconfig and an identity provider registered on the Supervisor (else: failed to
#   get pinniped-info)
#
# Description:
#
# | field               | value                                                                                    |
# |---------------------|------------------------------------------------------------------------------------------|
# | identity            | each person's identity-provider account, in a group                                      |
# | what the file holds | no secret: only where to sign in; each person signs in in a browser                      |
# | the cluster sees    | KC_PREFIX:<user>, in KC_PREFIX:KC_GROUP                                                  |
# | rights              | ROLE for the group in VKS_CLUSTER_NAMESPACE, or cluster-admin with "*" (WARNING) |
# | namespaces used     | VSPHERE_NAMESPACE (export), VKS_CLUSTER_NAMESPACE (rights)                               |
# | take it away        | disable the person in the identity provider, or delete the group's binding               |
# | keeps working       | with edit: ServiceAccount tokens and workloads members made (delete the workloads,       |
# |                     | re-create ServiceAccounts with rights); with "*" or Can edit: also logins they made      |
# | renew               | nothing: each person signs in again                                                      |
# | meant for           | people in your identity provider with no vCenter account                                 |
# | needs on this host  | admin kubeconfig (rights); a Supervisor with an identity provider registered (file)      |

VSPHERE_NAMESPACE="my-namespace"
VKS_CLUSTER="my-vks-cluster"
SUPERVISOR_CONTEXT="supervisor"
SUPERVISOR_KUBECONFIG="$HOME/.kube/${SUPERVISOR_CONTEXT}.kubeconfig"
KC_KUBECONFIG="$HOME/${VKS_CLUSTER}-keycloak-sv.kubeconfig"

rm -f "$KC_KUBECONFIG.new"
VCF_USE="$(vcf context use "$SUPERVISOR_CONTEXT" </dev/null 2>&1)"
RUNS=""
if ! printf '%s\n' "$VCF_USE" | grep -qF "Successfully activated context '${SUPERVISOR_CONTEXT}'"; then
  printf '%s\n' "$VCF_USE"
  echo "FAILED: the VCF CLI is not on context ${SUPERVISOR_CONTEXT}: log in or renew (SUPERVISOR-LOGIN.md), then run this again"
elif ! kubectl --kubeconfig "$SUPERVISOR_KUBECONFIG" -n "$VSPHERE_NAMESPACE" get clusters.cluster.x-k8s.io "$VKS_CLUSTER" -o name >/dev/null; then
  echo "FAILED: cannot read the cluster $VKS_CLUSTER in $VSPHERE_NAMESPACE (see the error above)"
elif vcf cluster kubeconfig get "$VKS_CLUSTER" -n "$VSPHERE_NAMESPACE" --export-file "$KC_KUBECONFIG.new" </dev/null \
   && RUNS="$(kubectl --kubeconfig "$KC_KUBECONFIG.new" config view -o jsonpath='{.users[0].user.exec.command} {.users[0].user.exec.args[0]}')" \
   && [ "$RUNS" = "vcf pinniped-auth" ]; then
  if mv -f "$KC_KUBECONFIG.new" "$KC_KUBECONFIG"; then echo "runs: $RUNS"; echo "saved $KC_KUBECONFIG"
  else echo "FAILED: $KC_KUBECONFIG is as it was (see the mv error above)"; fi
else
  rm -f "$KC_KUBECONFIG.new"
  echo "FAILED: the new file runs '$RUNS'; $KC_KUBECONFIG is as it was (see the error above)"
fi

echo
echo "Next: use the file in this terminal:"
echo "  export KUBECONFIG=\"$KC_KUBECONFIG\""
echo "  kubectl auth whoami"
echo "  kubectl -n <the namespace you were sent> auth can-i create deployments"
echo "Or one command without export:"
echo "  kubectl --kubeconfig \"$KC_KUBECONFIG\" auth whoami"
