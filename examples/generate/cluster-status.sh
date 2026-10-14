#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/tools/cluster-status.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.2 read-only check archetype · threshold-driven exit code
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# cluster-status.sh — is the k3s HA cluster healthy via the fetched kubeconfig?
# Read-only: prints `kubectl get nodes` plus a Ready tally and exits non-zero
# unless at least <expected> nodes are Ready.
#
#   bash gitops/tools/cluster-status.sh           # expects 3
#   bash gitops/tools/cluster-status.sh 1         # expects >=1
#   KUBECONFIG=/path/to/cfg bash gitops/tools/cluster-status.sh
#
# Canonicalises the Ready check that bit us during the role build: in bash the
# jsonpath is single-quoted, so the inner "Ready" quotes survive (unlike the
# ansible command module, which shlex-strips them — hence argv there). Defaults
# KUBECONFIG to the kubernetes role's fetched config.
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): kubectl's exit codes are
# checked explicitly; an unreachable API is a reported outcome, not a crash.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export KUBECONFIG="${KUBECONFIG:-${script_dir}/../../ansible/.kube/config-dev.yaml}"
expected="${1:-3}"

if ! command -v kubectl >/dev/null 2>&1; then
  printf 'error: kubectl not found on PATH\n' >&2
  exit 1
fi
if [[ ! -r "$KUBECONFIG" ]]; then
  printf 'error: kubeconfig not readable: %s\n' "$KUBECONFIG" >&2
  printf '       run the kubernetes role first (ansible playbooks/cluster.yml)\n' >&2
  exit 1
fi

if ! kubectl get nodes -o wide 2>&1; then
  printf '\nerror: kubectl could not reach the API via %s\n' "$KUBECONFIG" >&2
  printf '       run admin-ip-check.sh — your public IP may no longer match the SG /32\n' >&2
  exit 1
fi

# Per-node Ready condition status, space-separated (e.g. "True True True").
ready="$(kubectl get nodes \
  -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)"
# shellcheck disable=SC2206  # deliberate word-split of the space-separated list
statuses=($ready)
ready_count=0
for s in "${statuses[@]}"; do
  [[ "$s" == "True" ]] && (( ready_count++ ))
done

printf '\nReady: %d/%d\n' "$ready_count" "$expected"
if (( ready_count < expected )); then
  printf 'cluster not fully Ready\n' >&2
  exit 1
fi
