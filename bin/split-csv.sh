#!/usr/bin/env bash

raw_file="$(readlink -f "$1")" # preserve full path
target_csv_length=7500 

header="$(head -1 "$raw_file")" ; [[ "${#header}" -gt 0 ]] || exit 1
footer_lines=0
footer="$(tail -$footer_lines "$raw_file")"

# Automating the readout of the trailing lines to produce a template is not recommended. Use `%d` for the count of lines or sequence number; if there are any `%` signs in the footer change these to `%%` to preserve them below.
footer_template='This CSV file has %d lines.
Produced on Friday, '"$(date)"' 
Copyright (c) Foobar, Inc. 2021.'

# Same goes for your filenames:
filename_template='TEST-REPORT-[%03d]-YYYYMMDDHHMMSS.CSV'

# Set up a scratch space for your files during processing
splitsville="$(mktemp -d)"
printf 'Wrote scratch directory: %s\n\n' "$splitsville"

# Preprocess the CSV file and split it...
footerless_length="$(( $(grep -cE . "$raw_file") - $footer_lines ))"
[[ "${#footerless_length}" -gt 1 ]] || exit 1
(
  cd "$splitsville"
  head -$footerless_length "$raw_file" \
  | tail +2 \
  | split -l $target_csv_length - raw.
)

# Now do the post-processing on the split files.
(
  cd "$splitsville"
  count=0
  for chunk in raw.*
  do
    chunk_len="$(grep -cE . "$chunk")" # grep is faster than wc
    csv_seq_filename="$(printf "$filename_template" "$count")"
    ((count++))

    cat <<<"$(printf '%s\n' "$header")" "$chunk" > "$csv_seq_filename"
    printf "$footer_template" "$chunk_len" >> "$csv_seq_filename"
    rm $chunk
  done
)

# Resulting files and sizes ...
du -hs "$splitsville"/*
