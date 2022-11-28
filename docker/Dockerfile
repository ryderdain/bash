# syntax=docker/dockerfile-upstream:1-labs
FROM alpine

RUN apk add bash --no-cache

SHELL ["/bin/bash", "-c"]

RUN <<-EOF
printf 'The time is now %(%F %T)T\n' >&2
cat > foo.sh <<ENTRYSCRIPT
{
    outfile=foo.text
    printf 'Running a script named "%s" is fun\n' "\$0" > "\$outfile"
    find /var >> "\$outfile"
    printf "PS1='[\\D{%%F %%T}] \\h:\\w$ '" > ~/.bashrc
}
ENTRYSCRIPT
EOF

RUN cat foo.sh | /bin/bash -

ENTRYPOINT [ "/bin/bash", "-l" ]
