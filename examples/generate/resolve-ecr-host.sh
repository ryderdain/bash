#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/bootstrap/resolve-ecr-host.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.7 derive account-bearing values from the caller, never from shell memory
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# resolve-ecr-host.sh — print THIS account's ECR registry host, derived live from
# `aws sts get-caller-identity`. A bootstrap shim: the account id is fetched at
# bring-up and injected into the ArgoCD install via `helm --set`, so it is never
# committed to git and never depends on the SSM param 40-ecr publishes.
#
#   host="$(AWS_PROFILE=brzl-apply bash gitops/bootstrap/resolve-ecr-host.sh)"
#   # -> <account-id>.dkr.ecr.<region>.amazonaws.com
#
# Read-only generator (per the repo bash convention): it runs one STS call and
# prints the host to stdout with a meaningful exit code — it does NOT emit
# commands for piping. The only command whose failure matters (the STS call) is
# checked explicitly, so no reflexive `set -euo pipefail` (CLAUDE.md / BashFAQ/105).

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

region="${AWS_REGION:-eu-central-1}"

if ! command -v aws >/dev/null 2>&1; then
  printf 'error: aws CLI not found on PATH\n' >&2
  exit 1
fi

# Direct lookup — the whole point of the shim (vs. reading the published SSM param).
if ! account="$(aws sts get-caller-identity --query Account --output text 2>&1)"; then
  printf 'error: could not resolve AWS account (creds/role set?):\n%s\n' "$account" >&2
  exit 1
fi

if [[ -z "$account" || "$account" == "None" ]]; then
  printf 'error: empty account id from get-caller-identity\n' >&2
  exit 1
fi

printf '%s.dkr.ecr.%s.amazonaws.com\n' "$account" "$region"
