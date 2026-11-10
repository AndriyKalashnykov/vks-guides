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
# | rights              | ROLE (edit by default, or view) in VKS_CLUSTER_NAMESPACE; "*" gives the whole cluster:       |
# |                     | cluster-admin with edit, read-only with view (WARNING)                                       |
# | namespaces used     | SA_NAMESPACE (where it lives), VKS_CLUSTER_NAMESPACE (rights; "*": the whole cluster)       |
# | take it away        | delete the ServiceAccount ("*": also its ClusterRoleBinding): Unauthorized within ~15 s    |
# | keeps working       | with edit: tokens made with kubectl create token and workloads it started (delete the      |
# |                     | workloads, re-create ServiceAccounts with rights, restart what uses them); with "*" and    |
# |                     | edit: logins made with it as a cluster administrator                                       |
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

STAMP="$(mktemp)"
adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
kf() { kubectl --kubeconfig "$SERVICE_ACCOUNT_KUBECONFIG" "$@"; }
TOKEN=""
case "$ROLE" in
  edit|view) ROLE_OK="yes" ;;
  *) ROLE_OK="no" ;;
esac
if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set the namespace, or "*" for the whole cluster (cluster-admin with edit, read-only with view); nothing was changed'
elif [ "$ROLE_OK" = "no" ]; then
  echo 'STOPPED: ROLE is edit or view; nothing was changed'
elif [ "$VKS_CLUSTER_NAMESPACE" = "$SA_NAMESPACE" ]; then
  echo "STOPPED: VKS_CLUSTER_NAMESPACE must not be SA_NAMESPACE (${SA_NAMESPACE}): the team could read every token Secret stored there; nothing was changed"
elif ! [ "$DAYS" -ge 1 ] 2>/dev/null || [ "${DAYS#0}" != "$DAYS" ] || [ "$DAYS" -gt 36500 ]; then
  echo "STOPPED: DAYS is a number of days, 1 to 36500: $DAYS; nothing was changed"
else
if ! adm get namespace "$SA_NAMESPACE" >/dev/null 2>&1; then adm create namespace "$SA_NAMESPACE" >/dev/null; fi
adm -n "$SA_NAMESPACE" create serviceaccount "$SERVICE_ACCOUNT_NAME" --dry-run=client -o yaml | adm apply -f - >/dev/null
if [ "$VKS_CLUSTER_NAMESPACE" = "*" ] && [ "$ROLE" = "edit" ]; then
  echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": ${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME} gets cluster-admin on the whole cluster"
  O="$(adm delete clusterrolebinding "${SERVICE_ACCOUNT_NAME}-view" --ignore-not-found)"
  if [ -n "$O" ]; then echo "removed ClusterRoleBinding ${SERVICE_ACCOUNT_NAME}-view"; fi
  adm create clusterrolebinding "${SERVICE_ACCOUNT_NAME}-cluster-admin" --clusterrole=cluster-admin \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  CTX_NS="default"
elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
  echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": ${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME} gets read access to every namespace, pod logs included (they can hold credentials); not Secrets; nodes only as their names and CPU and memory figures (kubectl top nodes)"
  O="$(adm delete clusterrolebinding "${SERVICE_ACCOUNT_NAME}-cluster-admin" --ignore-not-found)"
  if [ -n "$O" ]; then echo "removed ClusterRoleBinding ${SERVICE_ACCOUNT_NAME}-cluster-admin"; fi
  adm create clusterrolebinding "${SERVICE_ACCOUNT_NAME}-view" --clusterrole=view \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  CTX_NS="default"
else
  if ! adm get namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null 2>&1; then adm create namespace "$VKS_CLUSTER_NAMESPACE" >/dev/null; fi
  OTHER="view"; if [ "$ROLE" = "view" ]; then OTHER="edit"; fi
  O="$(adm -n "$VKS_CLUSTER_NAMESPACE" delete rolebinding "${SERVICE_ACCOUNT_NAME}-${OTHER}" --ignore-not-found)"
  if [ -n "$O" ]; then echo "removed RoleBinding ${SERVICE_ACCOUNT_NAME}-${OTHER} in ${VKS_CLUSTER_NAMESPACE}"; fi
  adm -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "${SERVICE_ACCOUNT_NAME}-${ROLE}" --clusterrole="$ROLE" \
    --serviceaccount="${SA_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" --dry-run=client -o yaml | adm apply -f - >/dev/null
  CTX_NS="$VKS_CLUSTER_NAMESPACE"
fi
TOKEN="$(adm -n "$SA_NAMESPACE" create token "$SERVICE_ACCOUNT_NAME" --duration="$((DAYS * 24))h")"
SERVER="$(adm config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
CA="$(adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
if [ -n "$TOKEN" ] && [ -n "$SERVER" ] && [ -n "$CA" ]; then
  rm -f "$SERVICE_ACCOUNT_KUBECONFIG"
  ( umask 077
    printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    token: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\n    namespace: %s\ncurrent-context: %s\n' \
      "$SERVICE_ACCOUNT_NAME" "$SERVER" "$CA" "$SERVICE_ACCOUNT_NAME" "$TOKEN" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME" "$CTX_NS" "$SERVICE_ACCOUNT_NAME" > "$SERVICE_ACCOUNT_KUBECONFIG" )
  P="$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+')"
  while [ $(( ${#P} % 4 )) -ne 0 ]; do P="$P="; done
  EXP="$(printf '%s' "$P" | base64 -d 2>/dev/null | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
  S=""; if [ -n "$EXP" ]; then S=$(( EXP - $(date +%s) )); fi
  if [ -z "$S" ]; then echo "token ends in: unknown"
  elif [ "$S" -le 0 ]; then echo "token ends: it has ended"
  elif [ "$S" -ge 86400 ]; then N=$(( S / 86400 )); U="days"; if [ "$N" -eq 1 ]; then U="day"; fi; echo "token ends in: $N $U"
  else N=$(( S / 3600 )); U="hours"; if [ "$N" -eq 1 ]; then U="hour"; fi; echo "token ends in: $N $U"; fi
  echo "acts as: $(kf auth whoami -o jsonpath='{.status.userInfo.username}')"
  if [ "$VKS_CLUSTER_NAMESPACE" = "*" ] && [ "$ROLE" = "edit" ]; then
    echo "everything in every namespace: $(kf auth can-i '*' '*' --all-namespaces)"
  elif [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
    echo "list pods in kube-system: $(kf auth can-i list pods -n kube-system)"
    echo "list namespaces: $(kf auth can-i list namespaces)"
    echo "get secrets in kube-system: $(kf auth can-i get secrets -n kube-system)"
    echo "list nodes: $(kf auth can-i list nodes)"
    echo "create deployments in default: $(kf auth can-i create deployments -n default)"
  else
    echo "create deployments in $VKS_CLUSTER_NAMESPACE: $(kf auth can-i create deployments)"
    echo "list pods in kube-system: $(kf auth can-i list pods -n kube-system)"
  fi
else
  echo "FAILED: no token, server or CA read (see the kubectl errors above)"
fi
fi
unset TOKEN

if [ "$SERVICE_ACCOUNT_KUBECONFIG" -nt "$STAMP" ]; then
  echo
  echo "Next: send $SERVICE_ACCOUNT_KUBECONFIG to the team or tool as a secret (it holds the token)."
  echo "To try it here: kubectl --kubeconfig \"$SERVICE_ACCOUNT_KUBECONFIG\" auth whoami"
fi
rm -f "$STAMP"
