#!/usr/bin/env bash

_contains() { [[ "$1" =~ (^|[[:space:]])$2($|[[:space:]]) ]] ; return $?; }

prepare_run() {
    : # aws_login ; set_lock_path 
}

set_lock_path() {
    : # set and export the lock's DynamoDB key (depends on terraform's configuration)
}

preflight_checks() {
    if [[ $# -gt 0 ]]
    then
        vars2check=("$@")
    else
        vars2check=("region" "buildenv")
    fi
    for var in "${vars2check[@]}"
    do
        preflight_check_$var
    done
}

preflight_check_region() {
    case "$region" in 
    eu-central-1|us-west-1)
        : ;;
    *)
        printf 'ERROR: REGION not set correctly, was given "%s", giving up.\n' "${REGION}"
        printf '       acceptable values: eu-central-1, us-west-1\n'
        exit 1 ;;
    esac
    return 0
}

preflight_check_buildenv() {
    case "$buildenv" in
    test|int|e2e|prod)
        : ;;
    *)
        printf 'ERROR: ENV not set correctly, was given "%s", giving up.\n' "${ENV}"
        printf '       acceptable values: "test", "int", "e2e", "prod"\n'
        exit 1 ;;
    esac
    set_svclvl
    return 0
}

delete_state_lock() {
    # Using default table TerraformLocks, default attribute LockID

    lock_query='{"LockID":{"S":"'$lock_path'"}}'
    response_json="$(aws dynamodb get-item --table-name TerraformLocks --key "$lock_query")"

    lock_info_json="$(jq -r '.Item.Info.S' <<<"$response_json")"
    lock_id="$(jq -r '.ID' <<<"$lock_info_json")"

    echo "$response_json" | jq '.'

    if [[ -n "$response_json" ]]
    then
        printf 'Removing lock %s on %s...\n' "$lock_id" "$lock_path"
        aws dynamodb delete-item --table-name TerraformLocks --key "$lock_query"
    else 
        printf 'No lockfile on %s.\n' "$lock_path"
        return 1
    fi
    return 0
}

# main()
delete_state_lock "$@"
