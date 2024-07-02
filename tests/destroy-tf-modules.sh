#!/usr/bin/env bash

# Detection: works only for bash-to-bash
# TODO: add methods for running with zsh, etc.
(return 0 2>/dev/null) && is_sourced='true' || is_sourced='false'

end_function() {
    if [[ ${BASH_VERSINFO[0]} -ge 4 ]]
    then
        _ts() { printf '%(%F %T)T'; }
    else
        _ts() { date +'%F %T'; }
    fi
    return_code="${1}"; shift

    # On clean finish
    if [[ "${return_code}" -eq 0 ]]
    then
        printf '[%s] INFO (%s): %s\n' "$(_ts)" "${FUNCNAME[1]}" "${*}" >&2
        return 0
    fi

    # On error we want to return, not exit iff functions are sourced
    printf '[%s] ERROR (%s): %s\n' "$(_ts)" "${FUNCNAME[1]}" "${*}" >&2
    cd "$starting_position"
    if [[ "$is_sourced" = 'true' ]]
    then
        return $return_code
    else
        exit $return_code
    fi
}

prepare_run() {
    : # do things like assume-role, verify arguments, set region, etc.
}

preflight_check() {
    : # validation checks for acceptable input values
}

delete_cw_log_group() {
    log_group="$1"
    if [[ $(aws --region "$region" logs describe-log-groups | jq -r '.logGroups | map(select(.logGroupName?=="'$log_group'")) | length') -eq 1 ]]
    then
        aws --region "$region" logs delete-log-group --log-group-name "$log_group"
    fi
    end_function $? 'Finished run.'
}

delete_secrets_scheduled_for_deletion() {
    # necessary for test cases where the seven-day retention is unwanted.
    secret_arns=($(aws --region=eu-central-1 secretsmanager list-secrets --include-planned-deletion | jq -r '.SecretList[] | select(has("DeletedDate")) | .ARN?'))
    # printf "$secret_arns"
    if [[ ${#secret_arns[@]} -eq 0 ]] 
    then
        printf "No secrets marked for deletion found. \n"
    else
        for arn in "${secret_arns[@]}"
        do 
            printf "Found $arn, deleting... \n"
            aws --region="$region" secretsmanager delete-secret \
                --secret-id "$arn" \
                --force-delete-without-recovery
        done
        printf "Secrets deleted succesfully! \n"

    fi
    end_function $? 'Finished run.'
}

delete_namespace_finalizers() {
    # useful during automated termination. Finalizers occasionally prevent some
    # pods from being terminated, which interferes with node changes.
    namespaces=($(kubectl get namespaces -o name))
    local _rc=0
    for ns in "${namespaces[@]}"
    do
        case "${ns#*/}" in
        default|kube-*) continue ;;
        *) kubectl replace --raw "/api/v1/namespaces/${ns#*/}/finalize" \
                -f <(kubectl get $ns -o json | jq -r 'del(.spec?|.finalizers[]?)') ;;
        esac
        _rc=$(($_rc + $?))
    done
    end_function $_rc 'Finished run.'
}

destroy_module() {
    : # ymmv; usually some 'terraform destroy' call or a wrapper for the same.
}

remove_module_set() {
    : # e.g., 'destroy_module x', 'destroy_module y', etc.
}

run_pipeline_teardown() {
    prepare_run
    preflight_check

    remove_module_set

    cd "$starting_position"
}

apply_module() {
    : # run 'terraform apply' or the equivalent on some module
}

apply_targeted_module_components() {
    : # run 'terraform apply -target foo' or the equivalent on some module resource foo
}

install_module_set() {
    : # apply_targeted_module_components "foo" "resource.type.name"
    : # apply_module "foo"
}

run_pipeline() {
    prepare_run
    preflight_check

    install_module_set

    cd "$starting_position"
}
###############################################################################
# CLI Invocation
###############################################################################

# Ignore if sourced by other script.
if [[ "$is_sourced" = 'false' ]]
then
    if [[ $# -eq 0 ]]
    then
        run_pipeline_teardown
    else
        "$@"
    fi
fi
