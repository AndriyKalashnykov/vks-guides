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
# | rights              | edit in VKS_CLUSTER_NAMESPACE, or cluster-admin when it is empty (WARNING)                                                   |
# | namespaces used     | one: VKS_CLUSTER_NAMESPACE                                                                                                   |
# | take it away        | can't be revoked: delete its binding and never bind that name again; the certificate keeps proving the name until it expires |
# | renew               | run again: a new name and certificate; the old one needs its own take-away                                                   |
# | meant for           | one person with no SSO or identity-provider account                                                                          |
# | needs on this host  | admin kubeconfig (~/.kube/<cluster>.kubeconfig)                                                                              |

VKS_CLUSTER="my-vks-cluster"
ADMIN_KUBECONFIG="$HOME/.kube/${VKS_CLUSTER}.kubeconfig"
PERSON="alice"
VKS_CLUSTER_NAMESPACE="team-a"
DAYS="120"
PERSON_KUBECONFIG="$HOME/${VKS_CLUSTER}-${PERSON}.kubeconfig"

adm() { kubectl --kubeconfig "$ADMIN_KUBECONFIG" "$@"; }
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
  if [ -n "$VKS_CLUSTER_NAMESPACE" ]; then
    adm create namespace "$VKS_CLUSTER_NAMESPACE" --dry-run=client -o yaml | adm apply -f - >/dev/null
    adm -n "$VKS_CLUSTER_NAMESPACE" create rolebinding "${NAME}-edit" --clusterrole=edit --user="$NAME" >/dev/null
  else
    echo "WARNING: VKS_CLUSTER_NAMESPACE is empty: ${NAME} gets cluster-admin on the whole cluster"
    adm create clusterrolebinding "${NAME}-cluster-admin" --clusterrole=cluster-admin --user="$NAME" >/dev/null
  fi
  rm -f "$PERSON_KUBECONFIG"
  ( umask 077
    printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: %s\n  cluster:\n    server: %s\n    certificate-authority-data: %s\nusers:\n- name: %s\n  user:\n    client-certificate-data: %s\n    client-key-data: %s\ncontexts:\n- name: %s\n  context:\n    cluster: %s\n    user: %s\n    namespace: %s\ncurrent-context: %s\n' \
      "$NAME" "$SERVER" "$CA" "$NAME" "$CERT" "$(base64 < "$TMP/key.pem" | tr -d '\n')" \
      "$NAME" "$NAME" "$NAME" "${VKS_CLUSTER_NAMESPACE:-default}" "$NAME" > "$PERSON_KUBECONFIG" )
  openssl x509 -in "$TMP/cert.pem" -noout -subject -enddate
  if [ -n "$VKS_CLUSTER_NAMESPACE" ]; then
    echo "create deployments in $VKS_CLUSTER_NAMESPACE: $(kubectl --kubeconfig "$PERSON_KUBECONFIG" auth can-i create deployments)"
  else
    echo "everything in the cluster: $(kubectl --kubeconfig "$PERSON_KUBECONFIG" auth can-i '*' '*')"
  fi
else
  echo "FAILED: no matching certificate, server or CA (see the kubectl errors above)"
fi
adm delete csr "$CSR" --ignore-not-found >/dev/null; rm -rf "$TMP"

echo
echo "Next: use the file in this terminal:"
echo "  export KUBECONFIG=\"$PERSON_KUBECONFIG\""
echo "  kubectl auth whoami"
echo "  kubectl get pods"
echo "  kubectl auth can-i --list"
echo "Or one command without export:"
echo "  kubectl --kubeconfig \"$PERSON_KUBECONFIG\" auth whoami"
