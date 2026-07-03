#!/usr/bin/env bash
set -euo pipefail

MARKER_START="# BEGIN acess.sh"
MARKER_END="# END acess.sh"
HOSTS_FILE="/etc/hosts"
LOCAL_IP="127.0.0.1"
PORT_FORWARD_LOCAL=80
PORT_FORWARD_REMOTE=80
PID_FILE="/tmp/acess.sh.port-forward.pid"
DEFAULT_GATEWAY_NS="istio-ingress"
DEFAULT_GATEWAY_NAME="main-gateway"

log() {
  printf '%s\n' "$*" >&2
}

die() {
  log "Error: $*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

require_oc_cluster() {
  oc whoami >/dev/null 2>&1 || die "OpenShift cluster is not reachable. Check your kubeconfig and 'oc login'."
}

remove_script_hosts_entries() {
  if [ ! -f "$HOSTS_FILE" ]; then
    return 0
  fi

  if ! grep -qF "$MARKER_START" "$HOSTS_FILE"; then
    return 0
  fi

  log "Removing /etc/hosts entries from acess.sh..."
  sudo sed -i "/^$(printf '%s' "$MARKER_START" | sed 's/[.[\*^$]/\\&/g')\$/,/^$(printf '%s' "$MARKER_END" | sed 's/[.[\*^$]/\\&/g')\$/d" "$HOSTS_FILE"
}

get_httproute_hostnames() {
  oc get httproute -A -o json \
    | python3 -c '
import json
import sys

data = json.load(sys.stdin)
hostnames = set()

for item in data.get("items", []):
    for hostname in item.get("spec", {}).get("hostnames", []) or []:
        hostname = hostname.strip()
        if hostname:
            hostnames.add(hostname)

for hostname in sorted(hostnames):
    print(hostname)
'
}

add_script_hosts_entries() {
  local hostnames
  hostnames="$(get_httproute_hostnames)"

  if [ -z "$hostnames" ]; then
    log "No HTTPRoute hostnames found in the cluster."
    return 0
  fi

  log "Adding HTTPRoute hostnames to /etc/hosts (pointing to ${LOCAL_IP})..."
  {
    printf '%s\n' "$MARKER_START"
    while IFS= read -r hostname; do
      [ -n "$hostname" ] || continue
      printf '%s %s\n' "$LOCAL_IP" "$hostname"
    done <<< "$hostnames"
    printf '%s\n' "$MARKER_END"
  } | sudo tee -a "$HOSTS_FILE" >/dev/null

  while IFS= read -r hostname; do
    [ -n "$hostname" ] || continue
    log "  ${LOCAL_IP} ${hostname}"
  done <<< "$hostnames"
}

discover_gateway() {
  local gateway_ns gateway_name

  gateway_ns="$(oc get httproute -A -o json \
    | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for item in data.get("items", []):
    for parent in item.get("spec", {}).get("parentRefs", []) or []:
        if parent.get("kind", "Gateway") == "Gateway" and parent.get("name"):
            print(parent.get("namespace", ""))
            sys.exit(0)
' || true)"

  gateway_name="$(oc get httproute -A -o json \
    | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for item in data.get("items", []):
    for parent in item.get("spec", {}).get("parentRefs", []) or []:
        if parent.get("kind", "Gateway") == "Gateway" and parent.get("name"):
            print(parent["name"])
            sys.exit(0)
' || true)"

  GATEWAY_NS="${gateway_ns:-$DEFAULT_GATEWAY_NS}"
  GATEWAY_NAME="${gateway_name:-$DEFAULT_GATEWAY_NAME}"
}

find_gateway_pod() {
  local pod

  pod="$(oc get pods -n "$GATEWAY_NS" \
    -l "gateway.networking.k8s.io/gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

  [ -n "$pod" ] || die "Gateway pod not found in namespace '${GATEWAY_NS}' (gateway: ${GATEWAY_NAME})."
  printf '%s' "$pod"
}

user_kubeconfig() {
  local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"

  [ -f "$kubeconfig" ] || die "Kubeconfig not found at '${kubeconfig}'."

  if command -v realpath >/dev/null 2>&1; then
    realpath "$kubeconfig"
  else
    readlink -f "$kubeconfig"
  fi
}

stop_previous_port_forward() {
  local old_pid=""

  if [ ! -f "$PID_FILE" ]; then
    return 0
  fi

  old_pid="$(tr -d '[:space:]' < "$PID_FILE")"
  rm -f "$PID_FILE" 2>/dev/null || sudo rm -f "$PID_FILE" 2>/dev/null || true

  if [ -z "$old_pid" ]; then
    return 0
  fi

  if sudo kill -0 "$old_pid" 2>/dev/null; then
    log "Stopping previous port-forward (PID ${old_pid})..."
    sudo kill "$old_pid" 2>/dev/null || true
    sleep 1
  fi
}

cleanup() {
  trap - EXIT INT TERM
  stop_previous_port_forward || true
  remove_script_hosts_entries || true
}

start_port_forward() {
  local gateway_pod="$1"
  local kubeconfig
  kubeconfig="$(user_kubeconfig)"

  log "Starting port-forward to Gateway pod '${gateway_pod}' (${PORT_FORWARD_LOCAL}:${PORT_FORWARD_REMOTE})..."
  log "Using kubeconfig: ${kubeconfig}"
  log "Press Ctrl+C to stop and remove /etc/hosts entries."

  trap cleanup EXIT INT TERM

  sudo KUBECONFIG="$kubeconfig" oc port-forward \
    -n "$GATEWAY_NS" \
    "pod/${gateway_pod}" \
    "${PORT_FORWARD_LOCAL}:${PORT_FORWARD_REMOTE}" &
  local pf_pid=$!

  echo "$pf_pid" > "$PID_FILE"

  wait "$pf_pid"
}

main() {
  local gateway_pod=""

  require_command oc
  require_command python3
  require_oc_cluster

  remove_script_hosts_entries
  add_script_hosts_entries

  discover_gateway
  gateway_pod="$(find_gateway_pod)"

  stop_previous_port_forward
  start_port_forward "$gateway_pod"
}

main "$@"
