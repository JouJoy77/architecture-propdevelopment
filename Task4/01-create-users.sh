#!/usr/bin/env bash
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-pd-sprint5}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/.local-credentials"
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
umask 077

for command in kubectl openssl base64; do
  command -v "$command" >/dev/null || { echo "Required command missing: $command" >&2; exit 1; }
done
kubectl --context "$KUBE_CONTEXT" cluster-info >/dev/null

server="$(kubectl config view --raw --flatten --minify --context="$KUBE_CONTEXT" -o jsonpath='{.clusters[0].cluster.server}')"
ca_data="$(kubectl config view --raw --flatten --minify --context="$KUBE_CONTEXT" -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
test -n "$server" && test -n "$ca_data" || { echo 'Cluster server or CA missing from kubeconfig' >&2; exit 1; }
printf '%s' "$ca_data" | base64 -d > "$OUT_DIR/ca.crt"

create_user() {
  local user="$1" group="$2"
  local key="$OUT_DIR/$user.key" csr_file="$OUT_DIR/$user.csr"
  local csr_name="${user}-client" cert="$OUT_DIR/$user.crt" config="$OUT_DIR/$user.kubeconfig"

  openssl genrsa -out "$key" 2048 >/dev/null 2>&1
  openssl req -new -key "$key" -out "$csr_file" -subj "/CN=$user/O=$group"
  kubectl --context "$KUBE_CONTEXT" delete csr "$csr_name" --ignore-not-found >/dev/null
  cat <<EOF | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $csr_name
spec:
  request: $(base64 -w0 < "$csr_file")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF
  kubectl --context "$KUBE_CONTEXT" certificate approve "$csr_name" >/dev/null
  for _ in $(seq 1 30); do
    local cert_data
    cert_data="$(kubectl --context "$KUBE_CONTEXT" get csr "$csr_name" -o jsonpath='{.status.certificate}')"
    if [[ -n "$cert_data" ]]; then
      printf '%s' "$cert_data" | base64 -d > "$cert"
      break
    fi
    sleep 1
  done
  test -s "$cert" || { echo "CSR $csr_name was not signed" >&2; exit 1; }
  kubectl --kubeconfig "$config" config set-cluster "$KUBE_CONTEXT" --server="$server" --certificate-authority="$OUT_DIR/ca.crt" --embed-certs=true >/dev/null
  kubectl --kubeconfig "$config" config set-credentials "$user" --client-certificate="$cert" --client-key="$key" --embed-certs=true >/dev/null
  kubectl --kubeconfig "$config" config set-context "$user@$KUBE_CONTEXT" --cluster="$KUBE_CONTEXT" --user="$user" >/dev/null
  kubectl --kubeconfig "$config" config use-context "$user@$KUBE_CONTEXT" >/dev/null
  echo "Created $user ($group): $config"
}

create_user pd-sales-viewer pd:sales:viewers
create_user pd-housing-devops pd:housing:devops
create_user pd-platform-configurator pd:platform:configurators
create_user pd-security-auditor pd:security:auditors
