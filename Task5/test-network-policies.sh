#!/usr/bin/env bash
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-pd-sprint5}"
NAMESPACE="${NAMESPACE:-pd-network-demo}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-3}"

cleanup() {
  kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" delete pod \
    test-front-end test-back-end-api test-admin-front-end \
    test-admin-back-end-api test-unlabeled --ignore-not-found --wait=true >/dev/null
}
trap cleanup EXIT
cleanup

run_test_pod() {
  local name="$1" role="${2:-}"
  local labels=()
  [[ -n "$role" ]] && labels=(--labels="role=$role")
  kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" run "$name" \
    --image=busybox:1.36 --restart=Never "${labels[@]}" \
    --command -- sleep 3600 >/dev/null
}

run_test_pod test-front-end front-end
run_test_pod test-back-end-api back-end-api
run_test_pod test-admin-front-end admin-front-end
run_test_pod test-admin-back-end-api admin-back-end-api
run_test_pod test-unlabeled
kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" wait --for=condition=Ready \
  pod/test-front-end pod/test-back-end-api pod/test-admin-front-end \
  pod/test-admin-back-end-api pod/test-unlabeled --timeout=180s >/dev/null

failures=0
check() {
  local source="$1" destination="$2" expected="$3" actual
  if kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" exec "$source" -- \
      wget -qO /dev/null -T "$TIMEOUT_SECONDS" "http://$destination" >/dev/null 2>&1; then
    actual=ALLOW
  else
    actual=DENY
  fi
  printf '| `%s` | `%s` | %s | %s |\n' "$source" "$destination" "$expected" "$actual"
  [[ "$actual" == "$expected" ]] || failures=$((failures + 1))
}

printf '| Источник | Назначение | Ожидание | Результат |\n'
printf '| --- | --- | --- | --- |\n'
check test-front-end back-end-api-app ALLOW
check test-back-end-api front-end-app ALLOW
check test-admin-front-end admin-back-end-api-app ALLOW
check test-admin-back-end-api admin-front-end-app ALLOW
check test-front-end admin-back-end-api-app DENY
check test-back-end-api admin-front-end-app DENY
check test-admin-front-end back-end-api-app DENY
check test-admin-back-end-api front-end-app DENY
check test-unlabeled back-end-api-app DENY
check test-unlabeled admin-back-end-api-app DENY

if (( failures > 0 )); then
  echo "$failures network-policy checks failed" >&2
  exit 1
fi
