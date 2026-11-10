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
# | rights              | ROLE (edit or view) for the group in VKS_CLUSTER_NAMESPACE; "*" gives the whole cluster: |
# |                     | cluster-admin with edit, read-only with view (WARNING)                                   |
# | namespaces used     | VSPHERE_NAMESPACE (export), VKS_CLUSTER_NAMESPACE (rights; "*": the whole cluster)       |
# | take it away        | disable the person in the identity provider, or delete the group's binding               |
# | keeps working       | with edit: ServiceAccount tokens and workloads members made (delete the workloads,       |
# |                     | re-create ServiceAccounts with rights, restart what uses them); with "*" and edit, or    |
# |                     | Can edit: also logins they made                                                          |
# | renew               | nothing: each person signs in again                                                      |
# | meant for           | people in your identity provider with no vCenter account                                 |
# | needs on this host  | admin kubeconfig (rights); a Supervisor with an identity provider registered (file)      |

VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
KC_PREFIX="keycloak-sv"
KC_GROUP="k8s-devs"
VKS_CLUSTER_NAMESPACE="team-a"
ROLE="edit"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
G="${KC_PREFIX}:${KC_GROUP}"
case "$ROLE" in
  edit|view) ROLE_OK="yes" ;;
  *) ROLE_OK="no" ;;
esac
if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set the namespace, or "*" for the whole cluster (cluster-admin with edit, read-only with view); nothing was changed'
elif [ "$ROLE_OK" = "no" ]; then
  echo 'STOPPED: ROLE is edit or view; nothing was changed'
elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ] && [ "$ROLE" = "edit" ]; then
  echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": group ${G} gets cluster-admin on the whole cluster"
  adm create clusterrolebinding "${KC_PREFIX}-${KC_GROUP}-cluster-admin" --clusterrole=cluster-admin --group="$G"
  echo "group may do everything: $(adm auth can-i '*' '*' --all-namespaces --as=group-check --as-group="$G")"
elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
  echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": group ${G} gets read access to every namespace, pod logs included (they can hold credentials); not Secrets, not nodes"
  adm create clusterrolebinding "${KC_PREFIX}-${KC_GROUP}-view" --clusterrole=view --group="$G"
  echo "group may list pods in kube-system: $(adm auth can-i list pods -n kube-system --as=group-check --as-group="$G")"
  echo "group may list namespaces: $(adm auth can-i list namespaces --as=group-check --as-group="$G")"
  echo "group may get secrets in kube-system: $(adm auth can-i get secrets -n kube-system --as=group-check --as-group="$G")"
  echo "group may list nodes: $(adm auth can-i list nodes --as=group-check --as-group="$G")"
  echo "group may create deployments in default: $(adm auth can-i create deployments -n default --as=group-check --as-group="$G")"
else
  if ! adm get namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null 2>&1; then adm create namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null; fi
  adm -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "${KC_PREFIX}-${KC_GROUP}-${ROLE}" --clusterrole="$ROLE" --group="$G"
  echo "group may create deployments in $VKS_CLUSTER_NAMESPACE: $(adm -n "$VKS_CLUSTER_NAMESPACE" auth can-i create deployments --as=group-check --as-group="$G")"
fi
