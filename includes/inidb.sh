#!/usr/bin/env bash 

# ALL FROM: https://www.baeldung.com/linux/ini-file-bash-array-convert

# 3. Parsing and Building the Array
# We’ll follow a few simple steps to parse the file and build the array:
# 
# Read each line from the file as a string.
# Parse the string to get the section name or key-value pair.
# Build a unique key name using the section and key name and store the value in the bash array.

# 3.1. Parse a Section Name

# declare an associative array using -A option 
declare -A inidb
function _ini_get_section {
    if [[ "$1" =~ ^(\[)(.*)(\])$ ]]; 
    then 
        echo ${BASH_REMATCH[2]} ; 
    else 
        echo ""; 
    fi
}

# Here, we declare a global variable inidb as an associative array, which we’ll
# use throughout the script. This is the array that will be filled by reading
# the INI file. We’re using the regular expression ^([)(.*)(])$ which matches
# any string that begins with a square bracket and ends with a square bracket.
# The string between the square brackets is retrieved as the section name. The
# function takes a string as an input parameter.

# 3.2. Parse the Key-Value Pair
# In order to get the key-value pair, we retrieve the key and associated value
# from the input string:

function _ini_get_key_value {
    if [[ "$1" =~ ^([^=]+)=([^=]+)$ ]]; 
    then 
        echo "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"; 
    else 
        echo ""
    fi
}

# To emphasize, we’re using the regular expression^([^=]+)=([^=]+)$ which
# matches any string of the form KEY=VALUE. This function acts as validation
# for the strings that follow the INI file format. It returns the string in the
# form of KEY=VALUE. The caller of the function can post-process it to split it
# into parts.

# 3.3. Reading and Building the Array

# At this point, we have to stitch all the pieces together to build the array.
# By and large, there are only two steps:

# - Open and read the file one line at a time.
# - Parse and populate the array.
# In order to do the above, let’s write a function:

function ini_loadfile {
    local cur_section=""
    local cur_key=""
    local cur_val=""
    IFS=
    while read -r line; do
        new_section=$(_ini_get_section $line)
        # got a new section
        if [[ -n "$new_section" ]]; then
            cur_section=$new_section
        # not a section, try a key value
        else
            val=$(_ini_get_key_value $line)
            # trim the leading and trailing spaces as well
            cur_key=$(echo $val | cut -f1 -d'=' | sed -e 's/^[[:space:]]*//' | sed -e 's/[[:space:]]*$//') 
            cur_val=$(echo $val | cut -f2 -d'=' | sed -e 's/^[[:space:]]*//' | sed -e 's/[[:space:]]*$//')
        if [[ -n "$cur_key" ]]; then
            # section + key is the associative in bash array, the field seperator is space
            inidb[${cur_section} ${cur_key}]=$cur_val
        fi
    fi
    done <$1
}

# As we can see, we’re reading the given file line by line. We’re able to do it
# line by line using the separator specified with IFS. This is important since
# some of the values may have spaces. Bash uses spaces as a separator. By
# specifying IFS as an empty string, we’re able to read the file one line at a
# time.

# We use the functions _ini_get_section and _ini_get_key_value to allow us to
# pick out section names and key-value pairs from each line. Finally, we store
# the value in an associative array, inidb. We also trim the leading and
# trailing spaces for the key and value using the sed command.

# 3.4. Putting It All Together

# Now that we have all the building blocks, we can read an INI file into a Bash
# array using all the above functions:

function ini_printdb {
    for i in "${!inidb[@]}"
    do
    # split the associative key in to section and key
       echo -n "section :: $(echo $i | cut -f1 -d ' ');"
       echo -n "key : $(echo $i | cut -f2 -d ' ');"
       echo  "value: ${inidb[$i]}"
    done
}
function ini_get_value {
    section=$1
    key=$2
    echo "${inidb[$section $key]}"
}

# To clarify, we have written two functions. ini_printdb prints the INI
# database. ini_get_value gets the key and value based on the specified section
# and key name. 

# In summary, the complete program using all the above-developed functions is
# saved as inidb.sh.

# In brief, we have read the file, stored the file contents in the Bash array,
# and printed the contents of the array.
