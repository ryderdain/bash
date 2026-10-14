#!/bin/sh

## Usage
#description="
#"
usage="
Usage:
    $0 <binary name> [ <min version> ] [ <version check> ]

"

## Utilities
error() {
    exec 1>&2
    ret_code=${1}; shift
    printf '%s [error]: %s' "$(date)" "${@}"
    printf '%s' "$usage"
    exit "${ret_code}"
}

checkfor() {
    message="Executable ${1} needed by this script could not be found."
    command -v "${1}" || error 127 "$message"
}

checkfor jq
checkfor aws

policy_arn="$(aws iam list-policies --only-attached | jq -r '.Policies[]|select(.PolicyName=="'"${1}"'")|.Arn')"
#printf 'Contents of %s:\n\n' "$policy_arn"
default_version_id="$(aws iam list-policy-versions --policy-arn "$policy_arn" | jq -r '.Versions[]|select(.IsDefaultVersion==true)')"
aws iam get-policy-version --policy-arn "$policy_arn" --version-id "$default_version_id"

