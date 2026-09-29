#!/usr/bin/env bash
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-pd-sprint5}"

for domain in sales housing finance data; do
  namespace="pd-$domain"
  kubectl --context "$KUBE_CONTEXT" create namespace "$namespace" --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null
  kubectl --context "$KUBE_CONTEXT" label namespace "$namespace" \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=latest \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/audit-version=latest \
    pod-security.kubernetes.io/warn=restricted \
    pod-security.kubernetes.io/warn-version=latest \
    --overwrite >/dev/null
  kubectl --context "$KUBE_CONTEXT" -n "$namespace" create serviceaccount pd-unprivileged --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null
  kubectl --context "$KUBE_CONTEXT" -n "$namespace" patch serviceaccount pd-unprivileged --type=merge -p '{"automountServiceAccountToken":false}' >/dev/null
  kubectl --context "$KUBE_CONTEXT" create rolebinding pd-domain-viewers \
    --clusterrole=pd-domain-viewer --group="pd:$domain:viewers" --namespace="$namespace" \
    --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null
  kubectl --context "$KUBE_CONTEXT" create rolebinding pd-domain-devops \
    --clusterrole=pd-domain-deployer --group="pd:$domain:devops" --namespace="$namespace" \
    --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null
  kubectl --context "$KUBE_CONTEXT" create rolebinding pd-secret-auditors \
    --clusterrole=pd-secret-auditor --group=pd:security:auditors --namespace="$namespace" \
    --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null
  echo "Bound domain roles in $namespace"
done

kubectl --context "$KUBE_CONTEXT" create clusterrolebinding pd-platform-configurators \
  --clusterrole=pd-cluster-configurator --group=pd:platform:configurators \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null
echo 'Bound cluster configurators'
