#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/tools/admin-ip-check.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.2 read-only check archetype · meaningful exit code · remediation on stderr
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# admin-ip-check.sh — does my current public IP still match the cluster SG's
# admin /32 for the Kubernetes API (6443)? If it drifted (new network, VPN,
# DHCP lease), kubectl over the public IP silently hangs/refuses — SSM node
# access is unaffected. Read-only: prints the comparison and, on mismatch, the
# exact fix.
#
#   AWS_PROFILE=brzl-apply bash gitops/tools/admin-ip-check.sh
#   AWS_PROFILE=brzl-apply bash gitops/tools/admin-ip-check.sh brzl-prod-cluster
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): each read is checked
# explicitly.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

region="${AWS_REGION:-eu-central-1}"
sg_name="${1:-brzl-dev-cluster}"

for tool in aws curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: %s not found on PATH\n' "$tool" >&2
    exit 1
  fi
done

# Current public IPv4 — same vendor-neutral service the TF layers document.
if ! my_ip="$(curl -fsS -4 icanhazip.com 2>&1)"; then
  printf 'error: could not determine current public IP:\n%s\n' "$my_ip" >&2
  exit 1
fi
my_ip="${my_ip//[$'\r\n ']/}"  # strip stray whitespace/newline

# The SG's 6443 ingress CIDR(s). Only the admin rule carries a CidrIp; the
# node-to-node rule is a security-group reference (no IpRanges), so it drops out.
# shellcheck disable=SC2016  # single quotes are intentional: the backticks are JMESPath literals, not shell expansion
if ! cidrs="$(aws ec2 describe-security-groups \
  --region "$region" \
  --filters "Name=group-name,Values=${sg_name}" \
  --query 'SecurityGroups[].IpPermissions[?FromPort==`6443`][].IpRanges[].CidrIp' \
  --output text 2>&1)"; then
  printf 'error: describe-security-groups failed:\n%s\n' "$cidrs" >&2
  exit 1
fi

printf 'current public IP : %s\n' "$my_ip"
printf 'SG %-18s 6443 CIDR(s): %s\n' "$sg_name" "${cidrs:-<none>}"

if [[ " ${cidrs} " == *" ${my_ip}/32 "* ]]; then
  printf 'OK — your IP matches the admin /32; the API is reachable.\n'
  exit 0
fi

printf '\nMISMATCH — your IP (%s) is not in the SG; kubectl over the public IP will hang/refuse.\n' "$my_ip" >&2
printf 'Fix: re-apply 20-security FROM THE HOST YOU access from — it auto-detects that\n' >&2
printf 'host'\''s current public /32 (the http data source), so no export is needed:\n' >&2
printf '  tofu -chdir=terraform/environments/dev/20-security plan  -out=20.tfplan\n' >&2
printf '  tofu -chdir=terraform/environments/dev/20-security apply 20.tfplan\n' >&2
printf '(Or pin a fixed range: -var admin_cidr=YOUR_CIDR. SSM node access is unaffected.)\n' >&2
exit 1
