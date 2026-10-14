#!/usr/bin/env bash

input_json="$1"

# Top-level keys are modules 

modules=($(jq -r 'keys[]' "$1"))

for m in "${modules[@]}"
do
    printf '\n\n## %s\n' "$m"

    # Header Rows
    tf_files=($(jq -r ".\"$m\".outputs_used|keys[]" "$input_json"))
    printf '|'
    printf ' %s |' "${tf_files[@]}"
    printf '\n'
    
    printf '|'
    for ((i=0;i<${#tf_files[@]};i++)) ; do printf ':--|' ; done
    printf '\n'

    # Outputs Used
    printf '|'
    printf ' %s |' "${tf_files[@]}"
    printf '\n'
done
