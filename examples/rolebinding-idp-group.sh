# rolebinding-idp-group.sh
# For: rights for an identity provider group
# Produces: a RoleBinding (or ClusterRoleBinding) for the group; no file
# Valid for: until the binding is deleted
# Needs: admin kubeconfig ~/.kube/<cluster>.kubeconfig
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
# |                     | re-create ServiceAccounts with rights, restart what uses them); with "*" or Can edit:    |
# |                     | also logins they made                                                                    |
# | renew               | nothing: each person signs in again                                                      |
# | meant for           | people in your identity provider with no vCenter account                                 |
# | needs on this host  | admin kubeconfig (rights); a Supervisor with an identity provider registered (file)      |

VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
KC_PREFIX="keycloak-sv"
KC_GROUP="k8s-devs"
VKS_CLUSTER_NAMESPACE="team-a"
ROLE="edit"

if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set the namespace, or "*" for cluster-admin on the whole cluster; nothing was changed'
elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
  echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": group ${KC_PREFIX}:${KC_GROUP} gets cluster-admin on the whole cluster"
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" create clusterrolebinding "${KC_PREFIX}-${KC_GROUP}-cluster-admin" --clusterrole=cluster-admin --group="${KC_PREFIX}:${KC_GROUP}"
  echo "group may do everything: $(kubectl --kubeconfig "$ADMIN_KUBECONFIG" auth can-i '*' '*' --all-namespaces --as=group-check --as-group="${KC_PREFIX}:${KC_GROUP}")"
else
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" create namespace "$VKS_CLUSTER_NAMESPACE" --dry-run=client -o yaml | kubectl --kubeconfig "$ADMIN_KUBECONFIG" apply -f - >/dev/null
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "${KC_PREFIX}-${KC_GROUP}-${ROLE}" --clusterrole="$ROLE" --group="${KC_PREFIX}:${KC_GROUP}"
  echo "group may create deployments in $VKS_CLUSTER_NAMESPACE: $(kubectl --kubeconfig "$ADMIN_KUBECONFIG" -n "$VKS_CLUSTER_NAMESPACE" auth can-i create deployments --as=group-check --as-group="${KC_PREFIX}:${KC_GROUP}")"
fi
