#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/bootstrap/create-pullthrough-secrets.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.2 emit archetype · §1.3 secrets by reference, never by value · §1.5 stdout-canonical, file-as-argument · §1.6 dual-locus creds
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# create-pullthrough-secrets.sh — create the AWS Secrets Manager secrets ECR
# pull-through needs (quay.io + ghcr.io + Docker Hub), then write the resulting
# credential ARNs into the 40-ecr tfvars so no operator has to copy-paste them.
# ECR REQUIRES Secrets Manager here (credential_arn can't be Parameter Store) and
# the secret name MUST be prefixed `ecr-pullthroughcache/`.
#
# Two actions, matching the repo conventions:
#   • emit_create_secrets  — MUTATING/emit-commands: only PRINTS the create-or-update
#       commands; the tokens are referenced as runtime env vars ($GHCR_TOKEN etc.),
#       never interpolated into the printed text, so a dry run never reveals them.
#       Preview, then pipe to a shell (which expands them):
#         export GHCR_USERNAME=... GHCR_TOKEN=...        # GitHub user + read:packages PAT
#         export DOCKERHUB_USERNAME=... DOCKERHUB_TOKEN=...
#         export QUAY_USERNAME=... QUAY_TOKEN=...         # only if your quay cache needs auth
#         AWS_PROFILE=brzl-apply bash gitops/bootstrap/create-pullthrough-secrets.sh        # preview
#         AWS_PROFILE=brzl-apply bash gitops/bootstrap/create-pullthrough-secrets.sh | bash # run
#   • write_arns_to_tfvars [path] — READ-ONLY against AWS (describe-secret); resolves
#       the credential ARNs and renders the merged 40-ecr tfvars. Per §1.5 (stdout is
#       canonical, the file is an argument): with NO path it prints the merged tfvars
#       to stdout; given a path it ALSO writes that file (backup first) and still prints.
#       ARNs are not secret. Removes the manual paste-back step:
#         # preview the merged tfvars:
#         AWS_PROFILE=brzl-apply bash gitops/bootstrap/create-pullthrough-secrets.sh write_arns_to_tfvars
#         # persist it (backs up the existing file, still echoes to stdout):
#         AWS_PROFILE=brzl-apply bash gitops/bootstrap/create-pullthrough-secrets.sh \
#           write_arns_to_tfvars terraform/stack/aws/40-ecr/credentials.auto.tfvars
#
# Default action (run directly, no args) = emit_create_secrets (preserves the
# preview-then-pipe guardrail). The platform orchestrator calls both in turn.
#
# Credentials: AWS_PROFILE if set (laptop), else ambient/instance-role creds (the
# conductor) — the dual-locus rule (CLAUDE.md).
#
# KMS note: these secrets default to the AWS-managed Secrets Manager key. ECR's
# pull-through service must decrypt them; a customer-managed CMK (ADR-0006) would
# need an extra ECR-service decrypt grant on the key policy. Set SECRET_KMS_KEY_ID
# to opt in.
#
# Sourceable (CLAUDE.md): `source` it and call a function, or run it directly. No
# `set -euo pipefail` — emit-time checks are explicit; the emitted create-or-update
# stream is &&/||-chained per secret.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
source "${repo_root}/gitops/tools/lib/runlib.sh"

region="${AWS_REGION:-eu-central-1}"
name_prefix="${NAME_PREFIX:-brzl-dev}"
ecr_tfvars="${ECR_TFVARS:-${repo_root}/terraform/environments/dev/40-ecr/terraform.tfvars}"
kms_arg=""
[[ -n "${SECRET_KMS_KEY_ID:-}" ]] && kms_arg=" --kms-key-id ${SECRET_KMS_KEY_ID}"

# emit_one_secret <secret-name> <username-env> <token-env> — print a create-or-update
# for one upstream, referencing the token env var BY NAME so its value is expanded
# only by the downstream shell, never printed here. Returns 1 if creds aren't exported
# (caller tracks whether anything was emitted).
emit_one_secret() {
  local secret_name="$1" user_var="$2" token_var="$3"
  if [[ -z "${!user_var:-}" || -z "${!token_var:-}" ]]; then
    printf 'skip: %s (export %s and %s to create it)\n' "$secret_name" "$user_var" "$token_var" >&2
    return 1
  fi
  # create-or-update: try create, fall back to put-secret-value (update) if it exists.
  # The create's stderr is suppressed because the EXPECTED re-run case is a
  # ResourceExistsException — harmless noise. A genuine create failure (e.g. access
  # denied) still surfaces: the put fallback then runs and prints ITS own error.
  printf '%s\n' "\
aws secretsmanager create-secret --region ${region} \
--name ${secret_name}${kms_arg} \
--secret-string \"{\\\"username\\\":\\\"\$${user_var}\\\",\\\"accessToken\\\":\\\"\$${token_var}\\\"}\" \
--query ARN --output text 2>/dev/null \\
|| aws secretsmanager put-secret-value --region ${region} \
--secret-id ${secret_name} \
--secret-string \"{\\\"username\\\":\\\"\$${user_var}\\\",\\\"accessToken\\\":\\\"\$${token_var}\\\"}\" \
--query ARN --output text"
  return 0
}

emit_create_secrets() {
  require_tools aws || end_function "$?" 'aws CLI required'
  local emitted=0
  emit_one_secret "ecr-pullthroughcache/${name_prefix}-quay"      QUAY_USERNAME      QUAY_TOKEN      && emitted=1
  emit_one_secret "ecr-pullthroughcache/${name_prefix}-github"    GHCR_USERNAME      GHCR_TOKEN      && emitted=1
  emit_one_secret "ecr-pullthroughcache/${name_prefix}-dockerhub" DOCKERHUB_USERNAME DOCKERHUB_TOKEN && emitted=1
  if (( ! emitted )); then
    printf 'error: no creds exported — set GHCR_USERNAME/GHCR_TOKEN and/or DOCKERHUB_USERNAME/DOCKERHUB_TOKEN (and QUAY_* if needed)\n' >&2
    end_function 1 'nothing emitted'
    return 1
  fi
  printf '\n--- NEXT: populate the 40-ecr tfvars automatically ---------------------\n' >&2
  printf 'After piping the above to a shell, render the ARNs into the 40-ecr tfvars:\n' >&2
  printf '  %s \\\n' "gitops/bootstrap/create-pullthrough-secrets.sh" >&2
  printf '    write_arns_to_tfvars terraform/stack/aws/40-ecr/credentials.auto.tfvars\n' >&2
  printf 'then plan + apply 40-ecr (saved-plan workflow).\n' >&2
  end_function 0 'emitted create-or-update for the exported upstream creds'
}

# _secret_arn <secret-name> — resolve an existing secret's full ARN (read-only).
_secret_arn() {
  aws secretsmanager describe-secret --region "$region" --secret-id "$1" \
    --query ARN --output text 2>/dev/null
}

# _upsert_tfvar <content> <key> <value> — given a tfvars file's CONTENT (string),
# create-or-update a `key = "value"` line using bashisms (no sed) and print the new
# content. Un-comments a previously commented `#key =` line; appends if absent.
_upsert_tfvar() {
  local content="$1" key="$2" value="$3"
  local -a lines=() out=()
  local found=0 line
  mapfile -t lines <<< "$content"
  for line in "${lines[@]}"; do
    if [[ "$line" =~ ^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*= ]]; then
      out+=("${key} = \"${value}\"")
      found=1
    else
      out+=("$line")
    fi
  done
  (( found )) || out+=("${key} = \"${value}\"")
  printf '%s\n' "${out[@]}"
}

# write_arns_to_tfvars [target] — resolve the credential ARNs (read-only describe-
# secret) and render the merged 40-ecr tfvars. §1.5 (CLAUDE.md): stdout is canonical,
# the file is an argument. With no target it prints the merged tfvars to stdout;
# given a target it ALSO writes that file (backup first), announces it on stderr, and
# still prints to stdout. ARNs are not secret, so the merged tfvars is safe on stdout.
write_arns_to_tfvars() {
  require_tools aws || end_function "$?" 'aws CLI required'
  local target="${1:-}"

  # Base to merge into: the target if it exists, else the configured tfvars path,
  # else a fresh header — so the stdout preview reflects a real merge either way.
  local base="$ecr_tfvars"
  [[ -n "$target" && -f "$target" ]] && base="$target"
  local content
  if [[ -f "$base" ]]; then
    content="$(<"$base")"
  else
    content="# 40-ecr credential ARNs (gitignored). Rendered by create-pullthrough-secrets.sh."
  fi

  # Map each upstream secret to its 40-ecr variable. quay is credential-free in this
  # build (no quay_credential_arn variable), so it is intentionally NOT written.
  local -a pairs=(
    "ecr-pullthroughcache/${name_prefix}-github:ghcr_credential_arn"
    "ecr-pullthroughcache/${name_prefix}-dockerhub:dockerhub_credential_arn"
  )

  local resolved=0 entry secret key arn
  for entry in "${pairs[@]}"; do
    secret="${entry%%:*}"; key="${entry##*:}"
    arn="$(_secret_arn "$secret")"
    if [[ -z "$arn" || "$arn" == "None" ]]; then
      printf 'skip: %s — secret %s not found (create it first)\n' "$key" "$secret" >&2
      continue
    fi
    content="$(_upsert_tfvar "$content" "$key" "$arn")"
    printf 'resolved: %s = %s\n' "$key" "$arn" >&2
    resolved=1
  done

  if (( ! resolved )); then
    printf 'error: no secrets resolved (create them first); nothing rendered\n' >&2
    end_function 1 'no ARNs resolved'
    return 1
  fi

  printf '%s\n' "$content"                       # §1.5: always emit to stdout
  if [[ -n "$target" ]]; then                    # …and persist only when asked
    [[ -f "$target" ]] && cp -p -- "$target" "${target}.bak.$(date +%Y%m%d-%H%M%S)"
    printf '%s\n' "$content" > "$target"
    printf 'wrote → %s (backup alongside)\n' "$target" >&2
  fi
  end_function 0 'credential ARNs rendered'
}

# CLI dispatch — only when run directly. Default = emit_create_secrets (preview).
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else emit_create_secrets; fi
fi
