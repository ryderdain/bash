#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/bootstrap/create-cluster-secrets.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.2 emit archetype (minimal) · §1.3 deferred $VAR expansion via a shared emitter
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# create-cluster-secrets.sh — EMIT the commands that create the CORE in-cluster
# bootstrap Secrets the platform needs before its GitOps apps go healthy. Today
# that's `grafana-admin` (the monitoring stack reads its admin login from this
# Secret via admin.existingSecret, so the password never lands in git and stays
# stable across chart renders). Per the repo convention this is a mutating/action
# script — it only PRINTS commands (via the shared emit_k8s_secret helper):
#
#   bash gitops/bootstrap/create-cluster-secrets.sh             # preview
#   bash gitops/bootstrap/create-cluster-secrets.sh | bash      # run
#
#   # supply a fixed password instead of generating one:
#   GRAFANA_ADMIN_PASSWORD=… bash gitops/bootstrap/create-cluster-secrets.sh | bash
#
# This replaces the hand-typed `kubectl create secret generic grafana-admin …`
# step the bootstrap runbook used to carry (the §1.5 paste-back anti-pattern).
# `gitops/tools/ui_forward.sh` reads the Secret back to print the Grafana login.
#
# Sibling secret-creators sharing this shape (sourceable main() + runlib emit_k8s_secret):
#   create-pullthrough-secrets.sh (AWS Secrets Manager) · create_sso_secrets.sh (SSO).
# The ArgoCD repo deploy key is intentionally NOT here — it stays the gitignored
# `repo-deploy-key.yaml` (committed `.example`), applied by bootstrap_argocd.sh, so
# the SSH private key is never assembled on a command line.
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): the emit-time checks are
# explicit; the emitted create-or-update stream is &&-chained per Secret.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

grafana_ns="${MONITORING_NAMESPACE:-monitoring}"

# emit_grafana_admin — create-or-update the grafana-admin Secret. admin-user is
# non-secret (defaults to "admin"); admin-password is taken from GRAFANA_ADMIN_PASSWORD
# if set, else generated in the PIPED shell (20 random bytes). Both via @-literal
# expressions so they evaluate downstream, not in this preview.
emit_grafana_admin() {
  require_tools kubectl || end_function "$?" 'kubectl required'
  # shellcheck disable=SC2016  # @-literals must reach the piped shell verbatim
  emit_k8s_secret "$grafana_ns" grafana-admin \
    'admin-user=@${GRAFANA_ADMIN_USER:-admin}' \
    'admin-password=@${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -hex 20)}'
  end_function 0 "emitted grafana-admin create-or-update (ns ${grafana_ns})"
}

# emit_cluster_secrets — every core in-cluster bootstrap Secret, in one preview.
emit_cluster_secrets() {
  emit_grafana_admin
}

# CLI dispatch — only when run directly. Default = emit_cluster_secrets (preview).
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else emit_cluster_secrets; fi
fi
