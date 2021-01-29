#!/bin/sh

# split() {
#   for word in "$@"
#   do
#     printf '%s\n' "$word"
#   done
# }
# 
split() {
  string="${1}"; shift
  char="${1:- }" 
  regex="^([^$char]*)($char|$)"
  array=()
  if [[ "${string:-1:1}" != "$char" ]]
  then 
    string="${string}${char}"
  fi
  while [[ "$string" ]]
  do

    # Extract
    [[ "$string" =~ $regex ]]
    
    # Use field
    array+=("${BASH_REMATCH[1]}")

    # Update temp variable
    string="${string#"$BASH_REMATCH"}"

  done
  declare -p array
}

split "$@"
