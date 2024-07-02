#!/usr/bin/env bash

###############################################################################
# Destroy a bucket outside of Terraform
###############################################################################

# Detection: works only for bash-to-bash
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
    # identify s3 keys
}

preflight_check() {
    # validation and guardrails
}

aws_login() {
    # set up STS auth tokens in the environment for the target account
}

set_account_for_bucket() {
    # export the aws account based on the unique bucket name
}

set_region_for_bucket() {
    # export the aws region 
}

delete_all_bucket_objects_and_versions() {
    
    bucket_name="$1"

    set_account_for_bucket "$bucket_name"
    api_region="$(set_region_for_bucket)"

    bucket_exists=$(aws --region $api_region s3api list-buckets \
        | jq -r '.Buckets | map(select(.Name?=="'$bucket_name'")) | length')

    if [[ "$bucket_exists" -eq 0 ]]
    then
        printf 'No such bucket "%s" found.\n' "$bucket_name"
        return 0
    fi

    objects_and_versions="$(mktemp)"
    scratchfile="$(mktemp)"
    printf 'Creating json file of objects to remove:\n    %s\n' "$objects_and_versions"
    aws --region ${api_region} s3api list-object-versions \
            --bucket ${bucket_name} \
            --output=json \
            --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' > "$scratchfile"
    LC_NUMERIC='' printf "Found %'d objects to remove.\n" "$(jq '.Objects|length' "$scratchfile")"

    # Split the list of objects into chunks
    chunk_size=1000
    jq --argjson chunk $chunk_size '.Objects as $x |
        [range(0;$x|length;$chunk)] |
        map( {"Objects": $x[.:.+$chunk]} )
    ' "$scratchfile" > "$objects_and_versions"
    rm $scratchfile && unset scratchfile

    files_removed="$(mktemp)"
    printf 'Created logfile for removed objects:\n    %s\n' "$files_removed"

    # Deletion still needs testing. Look into parallelizing this to avoid
    # running over the session token limit.
    for ((i=0;i<$(jq length $objects_and_versions);i++))
    do
        set_account_for_bucket "$bucket_name" &>/dev/null # re-invoke session
        aws --region ${api_region} s3api delete-objects \
            --bucket ${bucket_name} \
            --delete "$(jq -r -c --argjson i $i '.[$i]' $objects_and_versions)"
    done >> $files_removed

    end_function $? 'Finished run.'
}

delete_all_bucket_deletion_markers() {
    
    bucket_name="$1"

    export api_region="eu-central-1"
    set_account_for_bucket "$bucket_name"
    bucket_exists=$(aws --region $api_region s3api list-buckets \
        | jq -r '.Buckets | map(select(.Name?=="'$bucket_name'")) | length')

    if [[ "$bucket_exists" -eq 0 ]]
    then
        printf 'No such bucket "%s" found.\n' "$bucket_name"
        return 0
    fi

    deletion_markers="$(mktemp)"
    scratchfile="$(mktemp)"
    printf 'Creating json file of objects to remove:\n    %s\n' "$deletion_markers"
    aws --region ${api_region} s3api list-object-versions \
            --bucket ${bucket_name} \
            --output=json \
            --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' > "$scratchfile"
    LC_NUMERIC='' printf "Found %'d objects to remove.\n" "$(jq '.Objects|length' "$scratchfile")"

    # Split the list of objects into chunks
    chunk_size=1000
    jq --argjson chunk $chunk_size '.Objects as $x |
        [range(0;$x|length;$chunk)] |
        map( {"Objects": $x[.:.+$chunk]} )
    ' "$scratchfile" > "$deletion_markers"
    rm $scratchfile && unset scratchfile

    files_removed="$(mktemp)"
    printf 'Created logfile for removed objects:\n    %s\n' "$files_removed"

    # Deletion still needs testing. Look into parallelizing this to avoid
    # running over the session token limit.
    for ((i=0;i<$(jq length $deletion_markers);i++))
    do
        set_account_for_bucket "$bucket_name" &>/dev/null # re-invoke session
        aws --region ${api_region} s3api delete-objects \
            --bucket ${bucket_name} \
            --delete "$(jq -r -c --argjson i $i '.[$i]' $deletion_markers)"
    done >> $files_removed

    end_function $? 'Finished run.'
}

delete_bucket() {
    bucket_name="$1"

    set_account_for_bucket "$bucket_name"
    bucket_exists=$(aws --region $api_region s3api list-buckets \
        | jq -r '.Buckets | map(select(.Name?=="'$bucket_name'")) | length')

    if [[ "$bucket_exists" -eq 0 ]]
    then
        printf 'No such bucket "%s" found.\n' "$bucket_name"
        return 0
    fi

    # Delete the bucket (for buckets without force_destroy=true)
    aws --region ${api_region} s3api delete-bucket \
        --expected-bucket-owner "${bucket_owner}" \
        --bucket ${bucket_name}

    end_function $? "Successfully deleted $bucket_name."
}

###############################################################################
# CLI Invocation
###############################################################################

# Ignore if sourced by other script.
if [[ "$is_sourced" = 'false' ]]
then
    case $# in 
    1)
        prepare_run
        preflight_check

        delete_all_bucket_objects_and_versions "$1"
        delete_all_bucket_deletion_markers "$1"
        delete_bucket "$1"
        ;;
    2)
        prepare_run
        preflight_check

        "$1" "$2" # for calling a single function
        ;;
    *)
        end_function 1 "requires a target bucket name, or a specific function name followed by the bucket name."
    esac
fi
