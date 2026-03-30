#!/usr/bin/env bash

set -euo pipefail

ADDRESS="${1:-127.0.0.1}"

PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}

trap cleanup EXIT INT TERM

start_forward() {
  local namespace="$1"
  local service="$2"
  local local_port="$3"
  local remote_port="$4"

  echo "Forwarding ${namespace}/${service}: http://localhost:${local_port}"
  kubectl port-forward "svc/${service}" -n "$namespace" \
    "${local_port}:${remote_port}" --address "$ADDRESS" &
  PIDS+=("$!")
}

start_forward "moodle" "moodle" "8888" "8888"
start_forward "monitoring" "monitoring-grafana" "3000" "80"

echo "Forwarding argocd/argocd-server: https://localhost:8443"
kubectl port-forward svc/argocd-server -n argocd 8443:443 --address "$ADDRESS" &
PIDS+=("$!")

echo
echo "Active forwards:"
echo "  Moodle:  http://localhost:8888"
echo "  Grafana: http://localhost:3000"
echo "  ArgoCD:  https://localhost:8443"
echo
echo "Press Ctrl+C to stop all port-forwards."

wait
