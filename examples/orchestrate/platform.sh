#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/tools/platform.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.4 sourceable main() at orchestrator scale · §1.8 the driver is a stream too · deliberate `set -o pipefail` (six sites, each explicable)
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# platform.sh — the AWS-environment lifecycle orchestrator: drives a bring-up
# (Terraform layers → Ansible/k3s → GitOps), the CloudNativePG DR restore, and the
# teardown, by SEQUENCING the repo's per-action scripts through the sourceable main()
# pattern (CLAUDE.md). One driver for both the normal GitOps bring-up and the
# RECOVERY.md "full teardown + restore" DR test — no second, divergent orchestrator.
#
# ENVIRONMENT — `ENV=dev` (default) or `ENV=prod`. AWS environments only; everything
# (state dir, SSM params, name prefix) is scoped to `brzl-<env>`. local-dev (k3d) is
# a LAPTOP concern run via gitops/clusters/local/k3d_up.sh and is rejected here.
#
# EXECUTION LOCUS — run this FROM THE CONDUCTOR (instance-role creds, no AWS_PROFILE)
# for AWS dev/prod ops; that's the audited, IAM-gated, identical-toolchain box
# (CLAUDE.md). The LAPTOP (AWS_PROFILE=brzl-apply) is only for *bootstrapping* —
# the admin trust anchor (terraform/bootstrap + terraform/identity) and launching the
# conductor (`platform.sh conductor`) — and for local-dev. The scripts are dual-locus,
# so they still run either place; the locus rule is operational policy, not a hard gate.
#
# Deliberately gated, not push-button: read-only phases run freely; every
# BILLABLE/mutating step prints what it will do and asks first (saved-plan workflow
# for tofu — plan -out, review, then apply the saved file). ASSUME_YES=1 skips the
# prompts in an automated/CI context (use with care).
#
# From-zero bring-up (two loci):
#   # 1) LAPTOP (admin first: terraform/bootstrap + terraform/identity), then launch the box:
#   AWS_PROFILE=brzl-apply bash gitops/tools/platform.sh conductor   # 💸 00-conductor (SELF-CONTAINED;
#                                                                     #    needs no 10-network/15-kms)
#   # 2) CONDUCTOR (SSM in; instance-role creds, no AWS_PROFILE): from-zero happy path.
#   #    Export the upstream tokens FIRST — `bootstrap` runs the `secrets` phase, which
#   #    consumes them (GHCR_TOKEN → CNPG/ESO pulls; DOCKERHUB_TOKEN → Grafana's image):
#   export GHCR_USERNAME=… GHCR_TOKEN=… DOCKERHUB_USERNAME=… DOCKERHUB_TOKEN=…
#   bash gitops/tools/platform.sh bootstrap   # secrets→layers(+15-kms)→images→cluster→gitops→watch→roundtrip
#   # (No separate `secrets` run — bootstrap includes it. `platform.sh secrets` ALONE just
#   #  re-runs the Secrets-Manager step, e.g. for token rotation; see Shared phases below.)
#
# Shared phases:
#   bash gitops/tools/platform.sh preflight   # FREE: identity/role + foundation + backups + conductor
#   bash gitops/tools/platform.sh secrets     # 💸 pull-through creds → Secrets Manager + ARNs → 40-ecr tfvars
#                                             #    (bootstrap runs this; standalone = token rotation)
#   bash gitops/tools/platform.sh layers      # 💸 10→50 (INCLUDE_KMS=1 also does 15-kms), saved-plan + confirm
#   bash gitops/tools/platform.sh images      # 💸 (re)build+push demo-app to ECR
#   bash gitops/tools/platform.sh cluster     # k3s via Ansible (gated) + kubeconfig
#
# Normal GitOps bring-up (`all` = the happy path when the foundation is already up):
#   bash gitops/tools/platform.sh gitops      # bootstrap ArgoCD + ApplicationSet (hands to GitOps)
#   bash gitops/tools/platform.sh watch       # FREE: wave-by-wave convergence snapshot
#   bash gitops/tools/platform.sh roundtrip   # FREE: CNPG + ESO + demo-app health
#   bash gitops/tools/platform.sh all         # preflight→layers→images→cluster→gitops→watch→roundtrip
#
# DR restore (`restore` = the happy path; recover-before-GitOps):
#   bash gitops/tools/platform.sh operator    # standalone CNPG operator (+ storage)
#   bash gitops/tools/platform.sh recover     # render recovery manifest + apply + wait
#   bash gitops/tools/platform.sh verify      # FREE: row-count acceptance check
#   bash gitops/tools/platform.sh restore     # preflight→layers→images→cluster→operator→recover→verify
#
# Teardown:
#   bash gitops/tools/platform.sh teardown    # 💸→0 reverse-order destroy (keep 15-kms)
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): each step's failure is
# checked explicitly via end_function; phases are independent and resumable.

# Detect sourced-ness in THIS frame, before sourcing the lib.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_root}/gitops/tools/lib/runlib.sh"

region="${AWS_REGION:-eu-central-1}"

# Target environment (AWS only): ENV=dev | prod. This orchestrator drives the AWS
# environments and is meant to run FROM THE CONDUCTOR. local-dev (k3d) is a LAPTOP
# concern driven by gitops/clusters/local/k3d_up.sh — reject it here so the
# environment + execution-locus boundary can't be crossed by accident.
env_name="${ENV:-dev}"
case "$env_name" in
  dev|prod) ;;
  local|local-dev)
    printf 'error: local-dev runs on the laptop via gitops/clusters/local/k3d_up.sh,\n' >&2
    printf '       not platform.sh (which drives the AWS dev/prod environments).\n' >&2
    # shellcheck disable=SC2317
    { return 2 2>/dev/null || exit 2; } ;;
  *)
    printf 'error: ENV must be dev or prod (got %q)\n' "$env_name" >&2
    # shellcheck disable=SC2317
    { return 2 2>/dev/null || exit 2; } ;;
esac

name_prefix="brzl-${env_name}"
# Single-source stack (model B, SPEC §3): ONE source per layer under
# terraform/stack/aws/<layer>, applied per env via <env>.tfvars. The env lives in the
# tfvars + the S3 state OBJECT KEY (composed below), not in a per-env directory.
stack_dir="${repo_root}/terraform/stack/aws"
# Conductor is NOT migrated this pass (its own pass — SPEC §9); it stays a self-contained
# layer at its legacy path with its own ../backend.hcl. dev-only.
conductor_dir="${repo_root}/terraform/environments/${env_name}/00-conductor"
ansible_dir="${repo_root}/ansible"
backup_bucket_param="${BACKUP_BUCKET_PARAM:-/${name_prefix}/backup/bucket_name}"
state_lock_table="${STATE_LOCK_TABLE:-brzl-demo-tflock}"
cnpg_ns="${CNPG_NAMESPACE:-cnpg-demo}"
cnpg_chart_version="${CNPG_CHART_VERSION:-0.28.2}"
# State bucket, DERIVED from the caller's account (SPEC §3 — no backend.hcl, no env var
# to remember). Cached on first resolve by _state_bucket. STATE_BUCKET overrides.
state_bucket="${STATE_BUCKET:-}"

# Propagate env-scoped SSM param paths + name prefix to the per-action scripts this
# orchestrator sources (render_recovery_manifest, bootstrap_argocd, create_pullthrough)
# so they target the SAME environment instead of falling back to their /brzl-dev defaults.
export BACKUP_BUCKET_PARAM="$backup_bucket_param"
export ECR_HOST_PARAM="/${name_prefix}/ecr/registry_host"
export NAME_PREFIX="$name_prefix"
export DEMO_APP_REPO="${DEMO_APP_REPO:-${name_prefix}/demo-app}"

# Acceptance target — the restored `app` DB must match EXACTLY (RECOVERY.md).
declare -A want=( [items]=4 [searches]=84 [search_results]=423 [api_calls]=84 )

# _confirm <prompt> — gate a billable/mutating step. Honors ASSUME_YES=1.
_confirm() {
  [[ "${ASSUME_YES:-0}" == 1 ]] && return 0
  local reply
  printf '\n>>> %s [y/N] ' "$1" >&2
  read -r reply
  [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]
}

# _state_bucket — DERIVE the single state bucket from the caller's account, cached
# (SPEC §3). brzl-demo-tfstate-<account_id>; STATE_BUCKET overrides. Prints to stdout.
_state_bucket() {
  if [[ -z "$state_bucket" ]]; then
    local acct
    acct="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || return 1
    [[ -n "$acct" && "$acct" != "None" ]] || return 1
    state_bucket="brzl-demo-tfstate-${acct}"
  fi
  printf '%s' "$state_bucket"
}

# _set_backend_args <layer> — compose this env's S3 backend config for a stack layer
# into the global array g_backend_args (model B: ONE bucket, env split by the OBJECT
# KEY <env>/<layer>/terraform.tfstate; SPEC §3). No backend.hcl. Returns 1 if the
# bucket can't be derived (no creds).
g_backend_args=()
_set_backend_args() {
  local layer="$1" bucket
  bucket="$(_state_bucket)" || { printf 'error: cannot derive state bucket (AWS creds/role set?)\n' >&2; return 1; }
  g_backend_args=(
    -backend-config="bucket=${bucket}"
    -backend-config="key=${env_name}/${layer}/terraform.tfstate"
    -backend-config="region=${region}"
    -backend-config="dynamodb_table=${state_lock_table}"
    -backend-config="encrypt=true"
  )
}

# ---- Phase: preflight (FREE) -------------------------------------------------
# Every kubectl-using phase calls this first: when the active context is the
# tunnel topology (server = https://127.0.0.1:6443, i.e. prod's private nodes),
# it starts/reuses the background SSM port-forward via api_tunnel.sh — so API
# reachability is the driver's job, never operator memory. Dev/local: no-op.
_kube_ready() {
  # shellcheck disable=SC1091
  source "${repo_root}/gitops/tools/api_tunnel.sh"   # defines ensure_api_tunnel
  ensure_api_tunnel
}

preflight() {
  require_tools aws || end_function "$?" 'aws required'
  aws_profile_note

  local who
  if ! who="$(aws sts get-caller-identity --query Arn --output text 2>&1)"; then
    printf 'error: cannot resolve caller identity:\n%s\n' "$who" >&2
    end_function 1 'no AWS identity'; return 1
  fi
  printf 'identity  : %s\n' "$who" >&2
  # Role check (dual-locus): laptop assumes brzl-tofu-apply; the conductor uses its
  # instance role. A raw IAM user can run read-only phases but should assume the apply
  # role before anything billable (only identity/perms changes run as the admin user).
  case "$who" in
    *assumed-role/brzl-tofu-apply/*)   printf 'role      : brzl-tofu-apply ✓ (apply-capable)\n' >&2 ;;
    *assumed-role/brzl-dev-conductor/*) printf 'role      : conductor instance role ✓ (on the toolbox)\n' >&2 ;;
    *:user/*) printf 'WARN: raw IAM user — assume brzl-tofu-apply before any 💸 step\n' >&2 ;;
    *)        printf 'role      : %s (confirm it can apply brzl-*)\n' "$who" >&2 ;;
  esac

  # Foundation (15-kms): its backup bucket SSM param is the liveness signal. Absent =
  # from-zero bring-up → layers must INCLUDE 15-kms (use `bootstrap`, which sets it).
  local bucket
  bucket="$(aws ssm get-parameter --region "$region" --name "$backup_bucket_param" \
    --query Parameter.Value --output text 2>/dev/null)"
  if [[ -z "$bucket" || "$bucket" == "None" ]]; then
    printf 'foundation: 15-kms DOWN — FROM-ZERO bring-up. Run: platform.sh bootstrap\n' >&2
    printf '            (launches 00-conductor + secrets, then layers INCLUDING 15-kms).\n' >&2
  else
    printf 'foundation: 15-kms up; backups s3://%s/pg/base/ (last objects):\n' "$bucket" >&2
    aws s3 ls "s3://${bucket}/pg/base/" --recursive 2>/dev/null | tail -3 >&2 \
      || printf 'WARN: could not list backup objects\n' >&2
  fi

  # Conductor (00-conductor) state — best-effort, read-only (needs an init'd state dir).
  local cond_id
  cond_id="$(cd "${conductor_dir}" 2>/dev/null && tofu output -raw conductor_instance_id 2>/dev/null)"
  if [[ -n "$cond_id" ]]; then
    printf 'conductor : %s up — aws ssm start-session --target %s\n' "$cond_id" "$cond_id" >&2
  else
    printf 'conductor : not applied (self-contained; run platform.sh conductor to launch it)\n' >&2
  fi

  printf 'pullthru  : ' >&2
  aws secretsmanager list-secrets --region "$region" \
    --query "SecretList[?starts_with(Name,'ecr-pullthroughcache/')].Name" --output text 2>/dev/null >&2 \
    || printf '(none / error)\n' >&2

  # State backend: DERIVED, not a backend.hcl (model B; SPEC §3). Report the bucket +
  # this env's object-key prefix so the operator sees where state lives.
  local sb
  if sb="$(_state_bucket)"; then
    printf 'state     : s3://%s  keys %s/<layer>/terraform.tfstate (composed per-layer)\n' "$sb" "$env_name" >&2
  else
    printf 'WARN: could not derive the state bucket (AWS creds/role set?)\n' >&2
  fi

  # Backend-block guard: a layer missing its `backend "s3"` block silently applies
  # to LOCAL state (and a later run then can't find what it created). Assert every
  # stack layer declares one — cheap insurance against a dropped backend.tf, so
  # correctness never rests on the operator noticing (GUIDANCE §1.7, generalized).
  local -a all_layers=(10-network 15-kms 20-security 30-iam 40-ecr 50-compute)
  local l missing_backend=0
  for l in "${all_layers[@]}"; do
    [[ -d "${stack_dir}/${l}" ]] || continue
    if ! grep -rqs 'backend "s3"' "${stack_dir}/${l}"; then
      # shellcheck disable=SC2016  # backticks are literal display text, not a subshell
      printf 'WARN: layer %s has NO `backend "s3"` block — tofu would use LOCAL state\n' "$l" >&2
      missing_backend=1
    fi
  done
  [[ "$missing_backend" == 0 ]] && printf 'backends  : all layers declare backend "s3" ✓\n' >&2

  end_function 0 'pre-flight complete (review the WARNs above)'
}

# ---- Phase: conductor (💸 launch/destroy the disposable SSM ops box) ----------
# 00-conductor is SELF-CONTAINED: its own VPC/subnet/IGW/SG/IAM, reads no other
# layer's state — so it has NO 10-network/15-kms prerequisite and can be applied or
# destroyed in isolation. Run from a laptop (AWS_PROFILE) to stand up the toolbox,
# then SSM onto it and drive the rest with instance-role creds.
#   platform.sh conductor          # apply (default)
#   platform.sh conductor destroy  # tear the box down
conductor() {
  require_tools tofu || end_function "$?" 'tofu required'
  # NOT migrated to the stack this pass (its own pass — SPEC §9): still the legacy
  # self-contained layer with its own ../backend.hcl. dev-only.
  local action="${1:-apply}" dir="${conductor_dir}"
  [[ -d "$dir" ]] || { printf 'error: no 00-conductor layer at %s\n' "$dir" >&2; end_function 1 'no conductor layer'; return 1; }
  printf 'note: 00-conductor is SELF-CONTAINED (own VPC/IAM, reads no other layer state)\n' >&2
  printf '      — it does NOT require 10-network or 15-kms; deploy/destroy in isolation.\n' >&2
  printf '      The box holds NO repo credential — after it is up, ship the working tree\n' >&2
  printf '      from the laptop (gitops/tools/ship-repo.sh), then run brzl-fetch on it.\n' >&2

  # Early identity check: with a role-assuming profile (brzl-apply) this fails fast
  # and CLEARLY if the trust anchor isn't up yet — the from-zero ordering trap (the
  # apply role + state bucket are admin Phase 0–1, created before this step).
  if command -v aws >/dev/null 2>&1; then
    local who
    if ! who="$(aws sts get-caller-identity --query Arn --output text 2>&1)"; then
      printf 'error: cannot resolve an AWS identity:\n%s\n' "$who" >&2
      printf '\nIf that is AssumeRole AccessDenied on brzl-tofu-apply, the trust anchor is\n' >&2
      printf 'not up yet. From a clean account do the ADMIN phases FIRST (as the admin user\n' >&2
      printf '— default profile, NOT AWS_PROFILE=brzl-apply); see docs/BOOTSTRAP.md 0–1:\n' >&2
      printf '  (admin) terraform/bootstrap  → state backend (S3 + DynamoDB + state CMK)\n' >&2
      printf '  (admin) terraform/identity   → brzl-tofu-apply role\n' >&2
      printf 'then re-run: AWS_PROFILE=brzl-apply bash gitops/tools/platform.sh conductor\n' >&2
      end_function 1 'no assumable identity (trust anchor up?)'; return 1
    fi
  fi

  ( cd "$dir" && tofu init -backend-config=../backend.hcl -input=false >/dev/null ) \
    || { end_function 1 'conductor init failed'; return 1; }

  if [[ "$action" == destroy ]]; then
    ( cd "$dir" && tofu plan -destroy -out=tfplan ) || { end_function 1 'conductor destroy-plan failed'; return 1; }
    if _confirm "DESTROY 00-conductor (the disposable ops box)?"; then
      ( cd "$dir" && tofu apply tfplan ) || { end_function 1 'conductor destroy failed'; return 1; }
    fi
    end_function 0 'conductor destroy phase complete'
    return 0
  fi

  ( cd "$dir" && tofu plan -out=tfplan ) || { end_function 1 'conductor plan failed'; return 1; }
  if _confirm "apply 00-conductor (launch the disposable SSM ops box)?"; then
    ( cd "$dir" && tofu apply tfplan ) || { end_function 1 'conductor apply failed'; return 1; }
    printf '\n--- conductor up ---------------------------------------------------\n' >&2
    ( cd "$dir" && tofu output ssm_session_command ) >&2 2>/dev/null || true
    printf 'Next: ship the tree from the laptop, then SSM in and fetch it:\n' >&2
    printf '  AWS_PROFILE=brzl-apply bash gitops/tools/ship-repo.sh | bash\n' >&2
    printf '  aws ssm start-session … ; then on the box:  brzl-fetch\n' >&2
    printf 'Then drive THIS script there (instance-role creds, no AWS_PROFILE).\n' >&2
  else
    printf 'skipped conductor apply (plan saved at %s/tfplan)\n' "$dir" >&2
  fi
  end_function 0 'conductor phase complete'
}

# ---- Phase: secrets (💸 pull-through creds → Secrets Manager + ARNs → tfvars) --
# ECR pull-through needs authenticated creds for ghcr.io (CNPG/ESO) and Docker Hub
# (Grafana) in Secrets Manager BEFORE 40-ecr applies. Export the upstream tokens
# first; they are referenced by name, never printed. (Grafana-admin + the repo
# deploy key are in-cluster secrets handled at the `gitops` phase — see BOOTSTRAP.md.)
secrets() {
  require_tools aws || end_function "$?" 'aws required'
  # shellcheck disable=SC1091
  source "${repo_root}/gitops/bootstrap/create-pullthrough-secrets.sh"  # defines emit_create_secrets + write_arns_to_tfvars
  if [[ -z "${GHCR_TOKEN:-}" && -z "${DOCKERHUB_TOKEN:-}" && -z "${QUAY_TOKEN:-}" ]]; then
    printf 'error: export the upstream tokens first, e.g.:\n' >&2
    printf '  export GHCR_USERNAME=... GHCR_TOKEN=...            # read:packages PAT (CNPG/ESO)\n' >&2
    printf '  export DOCKERHUB_USERNAME=... DOCKERHUB_TOKEN=...  # read-only token (Grafana)\n' >&2
    end_function 1 'no upstream creds exported'; return 1
  fi
  printf -- '--- preview: pull-through secret create-or-update ---\n' >&2
  emit_create_secrets >/dev/null || { end_function 1 'secrets emit failed'; return 1; }
  if _confirm "create/update the pull-through secrets in Secrets Manager?"; then
    set -o pipefail
    emit_create_secrets | bash || { end_function 1 'secret create run failed'; return 1; }
    # Account-level ARNs, SHARED across envs → the gitignored, auto-loaded
    # credentials.auto.tfvars in the single 40-ecr stack layer (model B; SPEC §3).
    local creds_tfvars="${stack_dir}/40-ecr/credentials.auto.tfvars"
    write_arns_to_tfvars "$creds_tfvars" >/dev/null \
      || { end_function 1 'write_arns_to_tfvars failed'; return 1; }
    printf 'credential ARNs rendered → %s\n' "$creds_tfvars" >&2
  fi
  end_function 0 'upstream secrets established'
}

# ---- Phase: layers (💸 saved-plan, gated, in order) --------------------------
# _tofu_layer <layer-dir-name> — init + plan -out + review + confirm + apply tfplan,
# against the SINGLE-SOURCE stack layer (model B). The env is carried by the composed
# backend object key (_set_backend_args) + the -var-file; the layer dir is SHARED, so
# `init -reconfigure` re-points the backend to THIS env each run (safe to switch envs
# in one dir). Bucket DERIVED from caller identity (no backend.hcl, no TF_VAR).
_tofu_layer() {
  local layer="$1" dir="${stack_dir}/$1" plan="tfplan"
  [[ -d "$dir" ]] || { printf 'error: no such layer: %s\n' "$dir" >&2; return 1; }
  _set_backend_args "$layer" || return 1
  printf '\n=== layer %s (env %s, key %s/%s/terraform.tfstate) ===\n' \
    "$layer" "$env_name" "$env_name" "$layer" >&2
  ( cd "$dir" \
      && tofu init -reconfigure "${g_backend_args[@]}" -input=false >/dev/null \
      && tofu plan -var-file="${env_name}.tfvars" -out="$plan" ) \
    || { printf 'error: plan failed for %s\n' "$layer" >&2; return 1; }
  if _confirm "apply the saved plan for ${layer} (${env_name})?"; then
    # The saved plan embeds the var values, so apply takes no -var-file.
    ( cd "$dir" && tofu apply "$plan" ) || { printf 'error: apply failed for %s\n' "$layer" >&2; return 1; }
  else
    printf 'skipped apply for %s (plan saved at %s/%s)\n' "$layer" "$dir" "$plan" >&2
  fi
  return 0
}

layers() {
  require_tools tofu || end_function "$?" 'tofu required'
  # 15-kms is retained (CMKs + backup bucket); skip by default, INCLUDE_KMS=1 to run it.
  local -a order=(10-network 20-security 30-iam 40-ecr 50-compute)
  [[ "${INCLUDE_KMS:-0}" == 1 ]] && order=(10-network 15-kms 20-security 30-iam 40-ecr 50-compute)
  local layer
  for layer in "${order[@]}"; do
    _tofu_layer "$layer" || { end_function 1 "stopped at ${layer}"; return 1; }
  done
  # 50-compute outputs (its .terraform is left init'd to THIS env by the loop above).
  ( cd "${stack_dir}/50-compute" && tofu output ) >&2 2>/dev/null || true
  end_function 0 'infra layers applied (or planned); 50-compute outputs above'
}

# ---- Phase: images (💸 push demo-app) ----------------------------------------
images() {
  # shellcheck disable=SC1091
  source "${repo_root}/apps/demo-app/build_push.sh"   # sourced → defines emit_build_push, no auto-run
  printf -- '--- preview: demo-app build/push ---\n' >&2
  emit_build_push >/dev/null || { end_function 1 'build_push emit failed'; return 1; }
  if _confirm "run the demo-app build+push?"; then
    set -o pipefail
    emit_build_push | bash || { end_function 1 'build/push run failed'; return 1; }
  fi
  end_function 0 'demo-app image step complete'
}

# ---- Phase: cluster (k3s via Ansible, gated; then kubeconfig) ----------------
cluster() {
  require_tools ansible-playbook kubectl tofu || end_function "$?" 'need ansible + kubectl + tofu'
  # The 50-compute stack layer is shared across envs; re-point its backend to THIS
  # env before reading outputs (generate_inventory + kubeconfig_setup both `tofu
  # output` there), so a standalone `cluster` run isn't reading another env's state.
  _set_backend_args 50-compute || { end_function 1 'cannot derive state backend (creds?)'; return 1; }
  ( cd "${stack_dir}/50-compute" && tofu init -reconfigure "${g_backend_args[@]}" -input=false >/dev/null ) \
    || { end_function 1 '50-compute init failed'; return 1; }
  printf 'rendering inventory from %s 50-compute outputs...\n' "$env_name" >&2
  ( cd "$ansible_dir" && bash inventory/generate_inventory.sh \
      "${stack_dir}/50-compute" > "inventory/${env_name}.yml" ) \
    || { end_function 1 'inventory generation failed'; return 1; }
  printf 'inventory : %s\n' "${ansible_dir}/inventory/${env_name}.yml" >&2

  if _confirm "run ansible bootstrap.yml + cluster.yml against the LIVE nodes?"; then
    ( cd "$ansible_dir" \
        && ansible-playbook -i "inventory/${env_name}.yml" playbooks/bootstrap.yml \
        && ansible-playbook -i "inventory/${env_name}.yml" playbooks/cluster.yml ) \
      || { end_function 1 'ansible run failed'; return 1; }
  else
    printf 'skipped ansible (inventory left in place)\n' >&2
  fi

  # Install the kubectl context. ENV drives the context name and which compute
  # layer the helper resolves the endpoint from (see kubeconfig_setup.sh).
  export ENV="$env_name" CONTEXT_NAME="brzl-${env_name}"
  # shellcheck disable=SC1091
  source "${repo_root}/gitops/tools/kubeconfig_setup.sh"   # defines setup_kubeconfig
  if [[ "$env_name" == "prod" ]]; then
    # Private nodes: no public endpoint exists. Install the context against
    # 127.0.0.1 (always in k3s's TLS SANs); the API is reached through a
    # background SSM port-forward the driver manages itself (_kube_ready).
    setup_kubeconfig --endpoint 127.0.0.1 || { end_function 1 'kubeconfig setup failed'; return 1; }
  else
    setup_kubeconfig || { end_function 1 'kubeconfig setup failed'; return 1; }
  fi
  _kube_ready || { end_function 1 'kube API unreachable (tunnel failed)'; return 1; }
  kubectl get nodes >&2 2>/dev/null || true
  end_function 0 'cluster phase complete (expect 3 Ready)'
}

# ---- Phase: gitops (bootstrap ArgoCD + ApplicationSet — NORMAL bring-up) ------
# Prereqs (one-time, see BOOTSTRAP.md): pull-through creds in Secrets Manager (their
# ARNs in 40-ecr tfvars) and the gitignored repo-deploy-key.yaml (operator-held — this
# phase applies it via bootstrap_argocd if present; it can't be auto-generated). The
# grafana-admin Secret is NOT a manual prereq anymore — this phase CREATES it (below)
# so the monitoring wave can't stall on a missing admin.existingSecret. Hands the
# cluster to GitOps: ArgoCD self-manages and syncs the ApplicationSet by wave (CNPG,
# ESO, monitoring, demo-app all come up FRESH here — this is NOT the DR path).
gitops() {
  require_tools helm kubectl aws || end_function "$?" 'need helm + kubectl + aws'
  _kube_ready || { end_function 1 'kube API unreachable (tunnel failed)'; return 1; }

  # GATE on the repo credential — the #1 evaluator/junior trip (it is gitignored,
  # so ship_repo NEVER carries it). Without it ArgoCD installs fine but every app
  # sits SYNC=Unknown with an empty REVISION. A scrolled warning is not a gate.
  if [[ ! -r "${repo_root}/gitops/bootstrap/repo-deploy-key.yaml" ]] \
      && ! kubectl -n argocd get secret brzl-demo-repo >/dev/null 2>&1; then
    printf 'BLOCKED: no repo credential — %s is absent and the brzl-demo-repo\n' \
      "gitops/bootstrap/repo-deploy-key.yaml" >&2
    printf '         Secret is not in the cluster. Stage the key first (BOOTSTRAP.md\n' >&2
    printf '         "Repo deploy key"; from a laptop: scp it over the SSM channel).\n' >&2
    if ! _confirm "continue ANYWAY (ArgoCD will install but sync nothing)?"; then
      end_function 1 'gitops blocked on the missing repo deploy key'
      return 1
    fi
  fi
  # shellcheck disable=SC1091
  source "${repo_root}/gitops/bootstrap/bootstrap_argocd.sh"  # defines emit_bootstrap_argocd
  printf -- '--- preview: ArgoCD + ApplicationSet bootstrap ---\n' >&2
  emit_bootstrap_argocd >/dev/null || { end_function 1 'argocd bootstrap emit failed'; return 1; }
  if _confirm "bootstrap ArgoCD + apply the ApplicationSet (hands the cluster to GitOps)?"; then
    set -o pipefail
    emit_bootstrap_argocd | bash || { end_function 1 'argocd bootstrap run failed'; return 1; }
    # The emitted stream ends in a tolerant `|| true` (storageclass patch), so
    # the piped bash can exit 0 over an upstream failure — assert the OUTCOME:
    kubectl -n argocd get applicationset "brzl-${env_name}" >/dev/null 2>&1 \
      || { end_function 1 "ApplicationSet brzl-${env_name} absent after bootstrap — see output above"; return 1; }
  fi

  # In-cluster app secret the monitoring wave consumes but that isn't in git: the
  # grafana-admin Secret (admin.existingSecret). Create it HERE, before monitoring
  # syncs, or Grafana sticks in CreateContainerConfigError on the missing Secret.
  # Idempotent create-or-update; the helper makes the monitoring ns too. (export
  # GRAFANA_ADMIN_PASSWORD to pin a password; otherwise one is generated. The value
  # stays out of the preview — emit_k8s_secret emits the @expr verbatim, CLAUDE.md §1.3.)
  # shellcheck disable=SC1091
  source "${repo_root}/gitops/bootstrap/create-cluster-secrets.sh"  # defines emit_grafana_admin
  printf -- '--- preview: grafana-admin Secret (monitoring-wave prereq) ---\n' >&2
  emit_grafana_admin >/dev/null || { end_function 1 'grafana-admin emit failed'; return 1; }
  if _confirm "create the grafana-admin Secret (the monitoring wave needs it)?"; then
    set -o pipefail
    emit_grafana_admin | bash || { end_function 1 'grafana-admin create failed'; return 1; }
  fi

  end_function 0 'GitOps bootstrap complete (ArgoCD self-manages from here)'
}

# ---- Phase: watch (FREE convergence snapshot) --------------------------------
watch() {
  require_tools kubectl || end_function "$?" 'kubectl required'
  _kube_ready || { end_function 1 'kube API unreachable (tunnel failed)'; return 1; }
  printf -- '--- ArgoCD applications ---\n' >&2
  kubectl -n argocd get applications -o wide >&2 2>/dev/null || printf 'no applications yet\n' >&2
  printf -- '--- pods (argocd|cnpg|external-secrets|demo|monitoring) ---\n' >&2
  kubectl get pods -A 2>/dev/null \
    | grep -E 'argocd|cnpg|external-secrets|demo|monitoring|kube-system' >&2 || true
  printf -- '--- storageclass (gp3 should be default) ---\n' >&2
  kubectl get storageclass >&2 2>/dev/null || true
  end_function 0 'convergence snapshot printed (re-run until all Synced/Healthy)'
}

# ---- Phase: roundtrip (FREE bring-up verify: CNPG + ESO + demo-app) ----------
roundtrip() {
  require_tools kubectl || end_function "$?" 'kubectl required'
  _kube_ready || { end_function 1 'kube API unreachable (tunnel failed)'; return 1; }
  printf -- '--- CNPG cluster health (ns %s) ---\n' "$cnpg_ns" >&2
  kubectl -n "$cnpg_ns" get cluster,pods >&2 2>/dev/null || true
  printf -- '--- ESO projection into demo ---\n' >&2
  kubectl -n demo get externalsecret,secret pg-app >&2 2>/dev/null || true
  printf -- '--- demo-app pods ---\n' >&2
  kubectl -n demo get pods -l app=demo-app >&2 2>/dev/null || true
  printf 'round-trip: seed the app end-to-end (self-contained port-forward, torn down after):\n' >&2
  printf '            bash gitops/tools/seed_demo_data.sh pf\n' >&2
  printf '            (or target a reachable URL: ... seed_demo_data.sh http://HOST | bash)\n' >&2
  end_function 0 'bring-up checks printed (CNPG + ESO + demo-app)'
}

# ---- Phase: operator (standalone EBS CSI + gp3, then CNPG; recover-before-GitOps)
# The DR path bypasses the wave-0 GitOps storage app, so this phase installs EBS CSI
# + the default gp3 StorageClass ITSELF, BEFORE the operator — without a default
# StorageClass the recovered CNPG cluster's gp3 PVCs hang Pending (a standalone path
# inherits GitOps's setup responsibilities — GUIDANCE §2.6, the A2 lesson). The
# install is the SAME chart/version/values the ApplicationSet wave 0 uses, via
# gitops/bootstrap/install_ebs_csi.sh (so the two paths can't drift).
operator() {
  require_tools helm kubectl aws || end_function "$?" 'need helm + kubectl + aws'
  _kube_ready || { end_function 1 'kube API unreachable (tunnel failed)'; return 1; }

  # 1) EBS CSI driver + default gp3 StorageClass — the wave-0 prereq, standalone.
  # shellcheck disable=SC1091
  source "${repo_root}/gitops/bootstrap/install_ebs_csi.sh"   # defines emit_install_ebs_csi
  printf -- '--- preview: EBS CSI + gp3 standalone install ---\n' >&2
  emit_install_ebs_csi >/dev/null || { end_function 1 'ebs-csi emit failed'; return 1; }
  if _confirm "install EBS CSI driver + default gp3 StorageClass (the DR storage prereq)?"; then
    set -o pipefail
    emit_install_ebs_csi | bash || { end_function 1 'ebs-csi install failed'; return 1; }
    # The emitted stream ends in a tolerant `|| true` (local-path patch); assert the
    # OUTCOME that recover() actually depends on rather than trusting the pipe's rc.
    kubectl get storageclass gp3 >/dev/null 2>&1 \
      || { end_function 1 'gp3 StorageClass absent after install — see output above'; return 1; }
  fi

  # 2) Standalone CNPG operator — the recovery cluster's controller.
  if _confirm "helm-install the standalone CNPG operator (ns cnpg-system)?"; then
    helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1
    helm repo update cnpg >/dev/null 2>&1
    helm upgrade --install cnpg-operator cnpg/cloudnative-pg \
      --version "$cnpg_chart_version" -n cnpg-system --create-namespace \
      || { end_function 1 'cnpg operator install failed'; return 1; }
    kubectl -n cnpg-system wait --for=condition=Available deploy --all --timeout=300s \
      || { end_function 1 'cnpg operator not Available'; return 1; }
    kubectl create namespace "$cnpg_ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  fi
  end_function 0 'storage (gp3) + CNPG operator ready for recover'
}

# ---- Phase: recover (render manifest + apply + wait) -------------------------
recover() {
  require_tools kubectl || end_function "$?" 'kubectl required'
  _kube_ready || { end_function 1 'kube API unreachable (tunnel failed)'; return 1; }
  # shellcheck disable=SC1091
  source "${repo_root}/gitops/operators/postgres/render-recovery-manifest.sh"  # defines render_recovery_manifest
  printf -- '--- preview: rendered recovery manifest ---\n' >&2
  render_recovery_manifest >/dev/null || { end_function 1 'render failed (SSM sentinels?)'; return 1; }
  if _confirm "apply the recovery Cluster (bootstrap.recovery from S3) into ${cnpg_ns}?"; then
    render_recovery_manifest | kubectl apply -f - || { end_function 1 'apply failed'; return 1; }
    printf 'waiting for the recovered primary (up to 10m)...\n' >&2
    kubectl -n "$cnpg_ns" wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \
      cluster/pg --timeout=600s || printf 'WARN: cluster not yet healthy; check kubectl cnpg status pg -n %s\n' "$cnpg_ns" >&2
  fi
  end_function 0 'recovery applied'
}

# ---- Phase: verify (FREE acceptance check) -----------------------------------
verify() {
  require_tools kubectl || end_function "$?" 'kubectl required'
  _kube_ready || { end_function 1 'kube API unreachable (tunnel failed)'; return 1; }
  local primary
  primary="$(kubectl -n "$cnpg_ns" get pod \
    -l cnpg.io/cluster=pg,cnpg.io/instanceRole=primary -o name 2>/dev/null)"
  if [[ -z "$primary" ]]; then
    printf 'error: no recovered primary in ns %s\n' "$cnpg_ns" >&2
    end_function 1 'no primary'; return 1
  fi
  local out
  out="$(kubectl -n "$cnpg_ns" exec "$primary" -- psql -U postgres -d app -tAF',' -c \
    "select 'items',count(*) from items union all select 'searches',count(*) from searches \
     union all select 'search_results',count(*) from search_results \
     union all select 'api_calls',count(*) from api_calls;" 2>/dev/null)"
  printf '%s\n' "$out" >&2

  local pass=1 t n
  while IFS=',' read -r t n; do
    [[ -z "$t" ]] && continue
    if [[ "${want[$t]:-}" != "$n" ]]; then
      printf 'MISMATCH %s: got %s, want %s\n' "$t" "$n" "${want[$t]:-?}" >&2; pass=0
    else
      printf 'OK       %s: %s\n' "$t" "$n" >&2
    fi
  done <<< "$out"

  if (( pass )); then
    end_function 0 'ACCEPTANCE PASS — DR proven (4/84/423/84)'
  else
    end_function 1 'ACCEPTANCE FAIL — counts do not match'
    return 1
  fi
}

# ---- Phase: teardown (💸→0, reverse order, keep 15-kms) ----------------------
teardown() {
  require_tools tofu || end_function "$?" 'tofu required'
  local -a order=(50-compute 40-ecr 30-iam 20-security 10-network)
  local layer
  for layer in "${order[@]}"; do
    local dir="${stack_dir}/$layer"
    [[ -d "$dir" ]] || { printf 'skip %s (no such layer)\n' "$layer" >&2; continue; }
    _set_backend_args "$layer" || { end_function 1 "cannot derive state backend for $layer (creds?)"; return 1; }
    printf '\n=== destroy %s (env %s) ===\n' "$layer" "$env_name" >&2
    ( cd "$dir" && tofu init -reconfigure "${g_backend_args[@]}" -input=false >/dev/null \
        && tofu plan -destroy -var-file="${env_name}.tfvars" -out=tfplan ) \
      || { end_function 1 "destroy-plan failed for $layer"; return 1; }
    if _confirm "DESTROY ${layer} (${env_name})?"; then
      ( cd "$dir" && tofu apply tfplan ) || { end_function 1 "destroy failed for $layer"; return 1; }
    fi
  done
  printf '\nNOTE: 15-kms (CMKs + backup bucket) intentionally KEPT. Run the manual leak\n' >&2
  printf 'sweep next (NAT gw, EIPs, orphaned EBS, LBs) — see docs/TEARDOWN.md.\n' >&2
  end_function 0 'teardown complete (15-kms retained)'
}

# ---- Happy paths -------------------------------------------------------------
# A halted multi-phase run must say WHERE it stopped and HOW to resume — the
# operator should never have to reconstruct "which phase was next?" from memory
# (GUIDANCE §1.7, generalized from values to sequencing). _run_phases sequences a
# phase list and, on the first failure, prints the failed phase + the exact resume
# command + the phases not reached.
#
# Dual-mode, because a phase's end_function EXITS on failure when the script is run
# directly but RETURNS when it was sourced (the runlib contract): in a direct run an
# EXIT trap fires the hint (the loop never regains control); when sourced we catch
# the nonzero return and print it after the loop — and we do NOT install an EXIT trap
# then, so a sourcing parent shell's own traps are left untouched.
current_phase=""
_resume_hint() {
  printf '\n✗ stopped at phase %q.\n' "${current_phase:-?}" >&2
  printf '  resume with: ENV=%s bash %s %s\n' \
    "$env_name" "${BASH_SOURCE[0]}" "${current_phase:-<phase>}" >&2
}
_phase_exit_trap() {
  local rc=$?
  (( rc == 0 )) && return 0
  [[ -n "${current_phase:-}" ]] && _resume_hint
  return 0
}
_run_phases() {
  current_phase=""
  [[ "$is_sourced" == false ]] && trap _phase_exit_trap EXIT
  local phase rc=0
  for phase in "$@"; do
    current_phase="$phase"
    "$phase"; rc=$?                         # capture the phase's OWN rc (not a negation's)
    (( rc != 0 )) && break                  # direct run: end_function already exited here
  done
  [[ "$is_sourced" == false ]] && trap - EXIT
  (( rc != 0 )) && _resume_hint            # sourced run: hint after the caught return
  current_phase=""
  return "$rc"
}

# bootstrap — the FROM-ZERO happy path, run FROM THE CONDUCTOR (the execution locus
# for AWS envs). Establishes the upstream secrets, then brings up every layer
# (INCLUDING 15-kms) and hands to GitOps. Each phase is still individually gated.
# Prereqs done from the LAPTOP first: terraform/bootstrap (state) + terraform/identity
# (apply role) as admin, then `platform.sh conductor` to launch this box. Use this
# when 15-kms / the upstream secrets do NOT yet exist.
bootstrap() {
  INCLUDE_KMS=1   # from-zero: 15-kms (backup bucket + CMKs) must be applied with the rest
  _run_phases preflight secrets layers images cluster gitops watch roundtrip
}

# all — the normal GitOps bring-up when the foundation (15-kms + secrets) is already
# up (e.g. iterating with only 50-compute torn down). Each phase still gated.
all() {
  _run_phases preflight layers images cluster gitops watch roundtrip
}

# restore — the DR happy path (recover-before-GitOps; each phase still gated).
restore() {
  _run_phases preflight layers images cluster operator recover verify
}

# CLI dispatch — only when run directly. Default prints the usage header (the leading
# comment block, range-independent so it survives edits to the header length).
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then
    "$@"
  else
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"
  fi
fi
