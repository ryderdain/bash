#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/tools/ship-repo.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.2 emit archetype · §1.8 relocating execution to the toolbox
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# ship-repo.sh — EMIT the command that ships the operator's CURRENT working tree to
# the Terraform state bucket, where the conductor fetches it via its instance role
# (`brzl-fetch`). This is how code reaches the conductor: the laptop is the source of
# truth where you read/review/approve; the conductor executes exactly the snapshot you
# push over the audited channel (CLAUDE.md §1.8). The conductor holds NO GitHub
# credential and never clones — there is nothing to authenticate to GitHub.
#
# Per the repo convention this is a mutating/action script: it only PRINTS the command
# (a read-only STS call resolves the bucket). Preview, then pipe:
#   AWS_PROFILE=brzl-apply bash gitops/tools/ship-repo.sh        # preview
#   AWS_PROFILE=brzl-apply bash gitops/tools/ship-repo.sh | bash # run (uploads to S3)
#
# The tarball is the WORKING tree — tracked files (current on-disk content, including
# uncommitted edits) PLUS new untracked files — and EXCLUDES gitignored paths
# (backend.hcl, *.tfvars, SPEC/PLAN/etc.): the conductor makes its own backend.hcl and
# its own tfvars. The bucket is derived from the caller's account id (no env var).
#
# Credentials: AWS_PROFILE if set (laptop), else ambient/instance-role creds — the
# dual-locus rule. No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): the only
# emit-time command whose failure matters (resolving the account) is checked explicitly.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_root}/gitops/tools/lib/runlib.sh"

transfer_key="${CONDUCTOR_TRANSFER_KEY:-conductor-transfer/tree.tgz}"

emit_ship_repo() {
  require_tools aws git tar || end_function "$?" 'need aws + git + tar on PATH'

  local account
  if ! account="$(aws sts get-caller-identity --query Account --output text 2>&1)"; then
    printf 'error: could not resolve AWS account (creds set?):\n%s\n' "$account" >&2
    end_function 1 'no AWS account'
    return 1
  fi
  local bucket="brzl-demo-tfstate-${account}"

  # git ls-files = tracked (read from disk, so uncommitted edits ride along);
  # ls-files --others --exclude-standard = new untracked files that are NOT gitignored.
  # Together: the working tree minus gitignored paths. The `while … [ -e ]` filter drops
  # entries that don't exist on disk (e.g. a staged-but-uncommitted DELETION like a
  # removed .gitkeep), so tar never fails to stat a missing path. tar -T - reads the
  # surviving list from stdin (ARG_MAX-safe). Run from repo_root so paths resolve.
  printf '%s\n' "\
( cd ${repo_root} \
&& { git ls-files; git ls-files --others --exclude-standard; } \
| while IFS= read -r f; do [ -e \"\$f\" ] && printf '%s\n' \"\$f\"; done \
| tar czf - -T - ) | aws s3 cp - s3://${bucket}/${transfer_key}"

  printf '\n--- NEXT --------------------------------------------------------------\n' >&2
  printf 'Shipped to s3://%s/%s. On the conductor (SSM in), run:\n' "$bucket" "$transfer_key" >&2
  printf '  brzl-fetch\n' >&2
  printf -- '----------------------------------------------------------------------\n' >&2
  end_function 0 "emitted ship to s3://${bucket}/${transfer_key}"
}

# CLI dispatch — only when run directly. Default = emit_ship_repo (preview).
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else emit_ship_repo; fi
fi
