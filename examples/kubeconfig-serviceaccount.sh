# kubeconfig-serviceaccount.sh
# For: a ServiceAccount token for a tool, pipeline or team, to hand over
# Produces: $HOME/<cluster>-<SERVICE_ACCOUNT_NAME>.kubeconfig
# Valid for: DAYS (120), or until the ServiceAccount is deleted
# Needs: admin kubeconfig ~/.kube/<cluster>.kubeconfig
#
# Description:
#
# | field               | value                                                                                        |
# |---------------------|----------------------------------------------------------------------------------------------|
# | identity            | a ServiceAccount in SA_NAMESPACE (a real object in the cluster)                              |
# | what the file holds | a token the cluster issued for that ServiceAccount                                           |
# | the cluster sees    | system:serviceaccount:SA_NAMESPACE:SERVICE_ACCOUNT_NAME                                      |
# | rights              | ROLE (edit by default) in VKS_CLUSTER_NAMESPACE, or cluster-admin with "*" (WARNING)        |
# | namespaces used     | SA_NAMESPACE (where it lives), VKS_CLUSTER_NAMESPACE (rights; "*": the whole cluster)       |
# | take it away        | delete the ServiceAccount ("*": also its ClusterRoleBinding): Unauthorized within ~15 s    |
# | renew               | run again: a new token for the same ServiceAccount; old tokens work until they end           |
# | meant for           | tools, pipelines, or a team sharing one login                                                |
# | needs on this host  | admin kubeconfig (~/.kube/<cluster>.kubeconfig)                                              |

VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
SERVICE_ACCOUNT_NAME="cicd-account"
VKS_CLUSTER_NAMESPACE="team-a"
SA_NAMESPACE="kubeconfig-access"
ROLE="edit"
DAYS="120"
SERVICE_ACCOUNT_KUBECONFIG="$HOME/${VKS_CLUSTER}-${SERVICE_ACCOUNT_NAME}.kubeconfig"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
TOKEN=""
if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set the namespace, or "*" for cluster-admin on the whole cluster; nothing was changed'
elif ! [ "$DAYS" -ge 1 ] 2>/dev/null || [ "${DAYS#0}" != "$DAYS" ] || [ "$DAYS" -gt 36500 ]; then
  echo "STOPPED: DAYS is a number of days, 1 to 36500: $DAYS; nothing was changed"
else
adm create namespace "$SA_NAMESPACE" --dry-run=client -o yaml | adm apply -f - >/dev/null
adm -n "$SA_NAMESPACE" create serviceaccount "$SERVICE_ACCOUNT_NAME" --dry-run=client -o yaml | adm apply -f - >/dev/null
if [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
  echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": ${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME} gets cluster-admin on the whole cluster"
  adm create clusterrolebinding "${SERVICE_ACCOUNT_NAME}-cluster-admin" --clusterrole=cluster-admin \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  KC_NS="default"
else
  adm create namespace "$VKS_CLUSTER_NAMESPACE" --dry-run=client -o yaml | adm apply -f - >/dev/null
  adm -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "${SERVICE_ACCOUNT_NAME}-${ROLE}" --clusterrole="$ROLE" \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  KC_NS="$VKS_CLUSTER_NAMESPACE"
fi
TOKEN="$(adm -n "$SA_NAMESPACE" create token "$SERVICE_ACCOUNT_NAME" --duration="$((DAYS * 24))h")"
SERVER="$(adm config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
CA="$(adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
if [ -n "$TOKEN" ] && [ -n "$SERVER" ] && [ -n "$CA" ]; then
  rm -f "$SERVICE_ACCOUNT_KUBECONFIG"
  ( umask 077
    printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    token: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\n    namespace: %s\ncurrent-context: %s\n' \
      "$SERVICE_ACCOUNT_NAME" "$SERVER" "$CA" "$SERVICE_ACCOUNT_NAME" "$TOKEN" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" "$KC_NS" "$SERVICE_ACCOUNT_NAME" > "$SERVICE_ACCOUNT_KUBECONFIG" )
  P="$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+')"
  while [ $(( ${#P} % 4 )) -ne 0 ]; do P="$P="; done
  EXP="$(printf '%s' "$P" | base64 -d 2>/dev/null | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
  if [ -n "$EXP" ]; then echo "token ends in: $(( (EXP - $(date +%s)) / 86400 )) days"; else echo "token ends in: unknown"; fi
  echo "acts as: $(kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" auth whoami -o jsonpath='{.status.userInfo.username}')"
  if [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
    echo "everything in every namespace: $(kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" auth can-i '*' '*' --all-namespaces)"
  else
    echo "create deployments in $VKS_CLUSTER_NAMESPACE: $(kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" auth can-i create deployments)"
    echo "list pods in kube-system: $(kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" auth can-i list pods -n kube-system)"
  fi
else
  echo "FAILED: no token, server or CA read (see the kubectl errors above)"
fi
fi
unset TOKEN

if [ -s "$SERVICE_ACCOUNT_KUBECONFIG" ] && [ -n "${KC_NS:-}" ]; then
  echo
  echo "Next: send $SERVICE_ACCOUNT_KUBECONFIG to the team or tool as a secret (it holds the token)."
  echo "To try it here: kubectl --kubeconfig \"$SERVICE_ACCOUNT_KUBECONFIG\" auth whoami"
fi
