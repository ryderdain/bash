#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/operators/postgres/render-recovery-manifest.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.2 generator archetype · §1.1 bashisms over subprocesses (no sed) · §1.4 sourceable main()
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# render-recovery-manifest.sh — GENERATOR: resolve the two account-bearing sentinels
# in cluster-recovery.yaml from SSM and PRINT the ready-to-apply CNPG recovery Cluster
# to stdout. Replaces the hand-rolled `sed -e ... | kubectl apply` in the A2 runbook
# with a single previewable, consistent `bash x.sh | <exec>` step (CLAUDE.md guardrail).
#
#   # preview the rendered manifest (no cluster contact):
#   bash gitops/operators/postgres/render-recovery-manifest.sh
#   # apply it:
#   bash gitops/operators/postgres/render-recovery-manifest.sh | kubectl apply -f -
#
# Credentials: uses AWS_PROFILE if set (laptop), else ambient/instance-role creds
# (the conductor) — the dual-locus rule (CLAUDE.md). Read-only: two `aws ssm
# get-parameter` calls; it never touches the cluster or any AWS resource.
#
# Sourceable (CLAUDE.md): `source` it and call render_recovery_manifest, or run it
# directly. No `set -euo pipefail` — each failure that matters is checked explicitly.

# 1. Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

region="${AWS_REGION:-eu-central-1}"
manifest="${RECOVERY_MANIFEST:-${script_dir}/cluster-recovery.yaml}"
ecr_host_param="${ECR_HOST_PARAM:-/brzl-dev/ecr/registry_host}"
backup_bucket_param="${BACKUP_BUCKET_PARAM:-/brzl-dev/backup/bucket_name}"
# Env pull-through prefix for __PULLTHROUGH_PREFIX__ (brzl-dev | brzl-prod). platform.sh
# exports NAME_PREFIX per ENV; standalone defaults to dev. This is what keeps a PROD DR
# drill from pulling the postgres image through the dev (-github) cache repo.
name_prefix="${NAME_PREFIX:-brzl-dev}"

# _ssm <param-name> — read-only single-parameter fetch; prints the value or empty.
_ssm() {
  aws ssm get-parameter --region "$region" --name "$1" \
    --query Parameter.Value --output text 2>/dev/null
}

render_recovery_manifest() {
  require_tools aws || end_function "$?" 'aws CLI required to resolve SSM sentinels'

  if [[ ! -r "$manifest" ]]; then
    printf 'error: recovery manifest not readable: %s\n' "$manifest" >&2
    end_function 1 "missing manifest $manifest"
    return 1
  fi

  local host bucket
  host="$(_ssm "$ecr_host_param")"
  bucket="$(_ssm "$backup_bucket_param")"

  if [[ -z "$host" || "$host" == "None" ]]; then
    printf 'error: SSM param %s unresolved (creds? is 40-ecr applied?)\n' "$ecr_host_param" >&2
    end_function 1 "could not resolve ECR host"
    return 1
  fi
  if [[ -z "$bucket" || "$bucket" == "None" ]]; then
    printf 'error: SSM param %s unresolved (creds? is 15-kms applied?)\n' "$backup_bucket_param" >&2
    end_function 1 "could not resolve backup bucket"
    return 1
  fi

  printf 'resolved  : ECR host=%s  backup bucket=%s  pull-through prefix=%s\n' \
    "$host" "$bucket" "$name_prefix" >&2

  # Substitute both sentinels. Bashism-first (no sed): read the manifest and replace
  # via parameter expansion on the whole-file string. Sentinels are unique tokens.
  local body
  body="$(<"$manifest")"
  body="${body//__ECR_REGISTRY_HOST__/$host}"
  body="${body//__BACKUP_BUCKET__/$bucket}"
  body="${body//__PULLTHROUGH_PREFIX__/$name_prefix}"
  printf '%s\n' "$body"
  end_function 0 'rendered cluster-recovery manifest to stdout'
}

# 4. CLI dispatch — only when run directly. Default action renders the manifest;
# `… render_recovery_manifest` (or any defined fn) also works for an explicit call.
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else render_recovery_manifest; fi
fi
