#!/usr/bin/env bash

# Retrieve and cache a list of available AMIs from AWS.

workdir="${HOME}/.aws"
[[ -d ${workdir} ]] || mkdir -p "${workdir}" || exit 1
imgcache="${workdir}/ami_list.json"
cache_age="${workdir}/.ami_list.touchstone"

if [[ -z "${1}" ]]
then
    regex='.'
else
    regex="${1}"
fi

# Touch "24 hours ago" to compare against the current cache age.
touch -d `date -v -1d +%Y-%m-%dT%H:%M:%S` "$cache_age"

# Only refresh every 24 hours
if [[ ! -r $imgcache ]] || [[ $imgcache -ot $cache_age ]]
then
    for cli in '--owners self' \
               '--owners aws-marketplace'
    do
        aws ec2 describe-images $cli |\
            jq '(.Images[])'
    done > $imgcache
    echo "finished refreshing cache at `stat -f '%Sm' $imgcache`."
fi

jq -s "{ \"AvailableAMIs\":
        [
            (.[] | select(.Description|@text|test(\"${regex}\")) | {
                    \"ImageId\": (.ImageId),
                    \"ImageLocation\": (.ImageLocation),
                    \"Desc\": (.Description),
                    \"Arch\": (.Architecture),
                    \"Created\": (.CreationDate)
            })
        ] | sort_by(.Created)
}" < $imgcache
