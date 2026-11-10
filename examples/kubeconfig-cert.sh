# kubeconfig-cert.sh
# For: a personal client certificate for one person, to hand over
# Produces: $HOME/<cluster>-<PERSON>.kubeconfig
# Valid for: DAYS (120); cannot be revoked before that
# Needs: admin kubeconfig ~/.kube/<cluster>.kubeconfig, openssl
#
# Description:
#
# | field               | value                                                                                                                        |
# |---------------------|------------------------------------------------------------------------------------------------------------------------------|
# | identity            | just a name in a certificate (PERSON-<date>); nothing is created for it in the cluster                                       |
# | what the file holds | a private key (made here, never sent) plus a certificate the cluster signed (via a CSR)                                      |
# | the cluster sees    | PERSON-<date>                                                                                                                |
# | rights              | edit in VKS_CLUSTER_NAMESPACE, or cluster-admin with "*" (WARNING)                                                          |
# | namespaces used     | one: VKS_CLUSTER_NAMESPACE ("*": the whole cluster, context namespace default)                                      |
# | take it away        | can't be revoked: delete its binding and never bind that name again; the certificate keeps proving the name until it expires |
# | keeps working       | with edit: ServiceAccount tokens and workloads the person made (delete the workloads, re-create ServiceAccounts with         |
# |                     | rights); with "*": also logins they made                                                                                     |
# | renew               | run again: a new name and certificate; the old one needs its own take-away                                                   |
# | meant for           | one person with no SSO or identity-provider account                                                                          |
# | needs on this host  | admin kubeconfig (~/.kube/<cluster>.kubeconfig)                                                                              |

VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
PERSON="alice"
VKS_CLUSTER_NAMESPACE="team-a"
DAYS="120"
PERSON_KUBECONFIG="$HOME/${VKS_CLUSTER}-${PERSON}.kubeconfig"

STAMP="$(mktemp)"
adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
if [ -z "$VKS_CLUSTER_NAMESPACE" ]; then
  echo 'STOPPED: VKS_CLUSTER_NAMESPACE is empty: set the namespace, or "*" for cluster-admin on the whole cluster; nothing was changed'
elif ! [ "$DAYS" -ge 1 ] 2>/dev/null || [ "${DAYS#0}" != "$DAYS" ] || [ "$DAYS" -gt 366 ]; then
  echo "STOPPED: DAYS is a number of days, 1 to 366: $DAYS; nothing was changed"
else
NAME="${PERSON}-$(date +%Y%m%d%H%M%S)"
CSR="kubeconfig-${NAME}"
adm delete csr "$CSR" --ignore-not-found >/dev/null
TMP="$(mktemp -d)"
openssl req -new -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -subj "/CN=${NAME}" -out "$TMP/csr.pem" 2>/dev/null
REQ="$(base64 < "$TMP/csr.pem" | tr -d '\n')"
printf 'apiVersion: certificates.k8s.io/v1\nkind: CertificateSigningRequest\nmetadata:\n  name: %s\nspec:\n  request: %s\n  signerName: kubernetes.io/kube-apiserver-client\n  expirationSeconds: %s\n  usages: [client auth]\n' \
  "$CSR" "$REQ" "$((DAYS * 86400))" | adm create -f - >/dev/null
if [ "$(adm get csr "$CSR" -o jsonpath='{.spec.request}')" = "$REQ" ]; then adm certificate approve "$CSR" >/dev/null; fi
CERT=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  CERT="$(adm get csr "$CSR" -o jsonpath='{.status.certificate}')"
  [ -n "$CERT" ] && break
  sleep 2
done
SERVER="$(adm config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
CA="$(adm config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
adm get csr "$CSR" -o go-template='{{.status.certificate | base64decode}}' > "$TMP/cert.pem" 2>/dev/null
if [ -n "$CERT" ] && [ -n "$SERVER" ] && [ -n "$CA" ] \
   && [ "$(openssl x509 -in "$TMP/cert.pem" -noout -pubkey)" = "$(openssl pkey -in "$TMP/key.pem" -pubout)" ]; then
  if [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
    echo "WARNING: VKS_CLUSTER_NAMESPACE is \"*\": ${NAME} gets cluster-admin on the whole cluster"
    adm create clusterrolebinding "${NAME}-cluster-admin" --clusterrole=cluster-admin --user="$NAME" >/dev/null
    CTX_NS="default"
  else
    adm create namespace "$VKS_CLUSTER_NAMESPACE" --dry-run=client -o yaml | adm apply -f - >/dev/null
    adm -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "${NAME}-edit" --clusterrole=edit --user="$NAME" >/dev/null
    CTX_NS="$VKS_CLUSTER_NAMESPACE"
  fi
  rm -f "$PERSON_KUBECONFIG"
  ( umask 077
    printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    client-certificate-data: %s\n    client-key-data: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\n    namespace: %s\ncurrent-context: %s\n' \
      "$NAME" "$SERVER" "$CA" "$NAME" "$CERT" "$(base64 < "$TMP/key.pem" | tr -d '\n')" \
      "$NAME" "$NAME" "$NAME" "$CTX_NS" "$NAME" > "$PERSON_KUBECONFIG" )
  openssl x509 -in "$TMP/cert.pem" -noout -subject -enddate
  if [ "$VKS_CLUSTER_NAMESPACE" = "*" ]; then
    echo "everything in every namespace: $(kubectl --kubeconfig "$PERSON_KUBECONFIG" auth can-i '*' '*' --all-namespaces)"
  else
    echo "create deployments in $VKS_CLUSTER_NAMESPACE: $(kubectl --kubeconfig "$PERSON_KUBECONFIG" auth can-i create deployments)"
  fi
else
  echo "FAILED: no matching certificate, server or CA (see the kubectl errors above)"
fi
adm delete csr "$CSR" --ignore-not-found >/dev/null; rm -rf "$TMP"
fi

if [ "$PERSON_KUBECONFIG" -nt "$STAMP" ]; then
  echo
  echo "Next: write down the name on the subject= line (step 4 needs it), then send $PERSON_KUBECONFIG"
  echo "to the person as a secret (it holds their key)."
fi
rm -f "$STAMP"
