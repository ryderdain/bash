#!/bin/sh

# Check for and retrieve full path to binary by name.  Optionally pass a second
# argument to specify a minimum version.  Binary must support '--version' flag
# for this test, or pass a third argument string which can be passed to the
# binary and will retrieve the version number (can be used to parse output).

PATH=${PATH}

checkfor() {
    message="Executable ${1} needed by this script could not be found."
    if ! (type -fP ${1})
        error 127 "$message"
    fi
}

#fullpathname=
if [ "$(which -a "${1}"|wc -l)" -gt 1 ]
then
	for pathname in $(which -a "${1}")
	do
		printf 'found %s: is%s executable' \
			"$pathname" \
			"$(sh -c "if ! [ -x $pathname ];then printf 'not';fi")"
	done
fi
