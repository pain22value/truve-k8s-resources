#!/bin/sh

set -eu

NODEPOOL_LABEL="${NODEPOOL_LABEL:-karpenter.sh/nodepool=app-general}"
DEFAULT_NAMESPACES="${DEFAULT_NAMESPACES:-truve-auth-service truve-ticketing-service}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/app-node-ops.sh list-fixed-pods
  ./scripts/app-node-ops.sh list-terminating
  ./scripts/app-node-ops.sh cleanup-terminating [namespace ...]
  ./scripts/app-node-ops.sh drain-node <node-name>

Environment:
  NODEPOOL_LABEL      label selector for app nodes (default: karpenter.sh/nodepool=app-general)
  DEFAULT_NAMESPACES  namespaces used by cleanup-terminating when none are passed
EOF
}

require_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found" >&2
    exit 1
  fi
}

list_app_nodes() {
  kubectl get nodes -l "$NODEPOOL_LABEL" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

list_fixed_pods() {
  nodes="$(list_app_nodes)"
  if [ -z "$nodes" ]; then
    echo "No nodes matched: $NODEPOOL_LABEL" >&2
    return 1
  fi

  for node in $nodes; do
    kubectl get pods -A \
      --field-selector "spec.nodeName=$node" \
      -o custom-columns='NODE:.spec.nodeName,NAMESPACE:.metadata.namespace,NAME:.metadata.name,OWNER_KIND:.metadata.ownerReferences[0].kind,OWNER_NAME:.metadata.ownerReferences[0].name,PHASE:.status.phase' \
      --no-headers
  done | awk '$4 != "DaemonSet"'
}

list_terminating() {
  kubectl get pods -A -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.nodeName}{"\t"}{.metadata.deletionTimestamp}{"\n"}{end}'
}

cleanup_terminating() {
  if [ "$#" -gt 0 ]; then
    namespaces="$*"
  else
    namespaces="$DEFAULT_NAMESPACES"
  fi

  for ns in $namespaces; do
    pods="$(kubectl get pods -n "$ns" -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}')"
    if [ -z "$pods" ]; then
      echo "No terminating pods in namespace: $ns"
      continue
    fi

    for pod in $pods; do
      echo "Force deleting $ns/$pod"
      kubectl delete pod -n "$ns" "$pod" --grace-period=0 --force
    done
  done
}

drain_node() {
  node="$1"
  kubectl cordon "$node"
  kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --force
}

require_kubectl

command="${1:-}"
case "$command" in
  list-fixed-pods)
    list_fixed_pods
    ;;
  list-terminating)
    list_terminating
    ;;
  cleanup-terminating)
    shift
    cleanup_terminating "$@"
    ;;
  drain-node)
    if [ "$#" -ne 2 ]; then
      usage
      exit 1
    fi
    drain_node "$2"
    ;;
  *)
    usage
    exit 1
    ;;
esac
