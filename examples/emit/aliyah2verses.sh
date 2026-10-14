#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/taameimikra @ c572284
# │ path     : aliyah2verses.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.2 emit archetype OUTSIDE infrastructure — the pattern is not an AWS habit
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
#
# aliyah2verses.sh — emit ffmpeg commands that slice PocketTorah aliyah
# recordings into per-verse mp3s for Torah cantillation practice.
#
# Usage:
#   bash ./aliyah2verses.sh <BookDir> <Parsha> <Chapter:VerseStart> <Chapter:VerseEnd> | bash
#
# Example:
#   bash ./aliyah2verses.sh Vayikra "Acharei Mot" 16:12 17:34 | bash
#
# Inputs to ffmpeg are streamed straight from
# https://raw.githubusercontent.com/<repo>/<branch>/data/audio/...; no local
# clone of PocketTorah is required. Override the source with the env vars
# POCKET_TORAH_REPO and POCKET_TORAH_BRANCH.
#
# Verse-level timing is computed from PocketTorah's per-word label files
# (data/torah/labels/<Parsha>-<aliyah>.txt) combined with verse word counts
# from data/torah/json/<Book>.json — the same data that drives Sefaria's
# Torah Reading widget. The Sefaria public API does not expose verse
# breakpoints itself; see README.md for details.
#
# Requires: bash, curl, jq, ffmpeg.

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <BookDir> <Parsha> <Chapter:VerseStart> <Chapter:VerseEnd>" >&2
  exit 64
fi

book_dir="$1"
parsha_in="$2"
start_ref="$3"
end_ref="$4"

# Reject malformed ref args before we touch the network or the filesystem; a
# typo here would otherwise survive into jq --argjson and fail mid-loop after
# mkdir has already run.
for ref in "$start_ref" "$end_ref"; do
  if ! [[ "$ref" =~ ^[0-9]+:[0-9]+$ ]]; then
    echo "aliyah2verses.sh: refs must be Chapter:Verse (e.g. 16:12); got: $ref" >&2
    exit 64
  fi
done
IFS=: read -r start_chapter start_verse <<< "$start_ref"
IFS=: read -r end_chapter end_verse <<< "$end_ref"
if (( start_chapter > end_chapter )) || \
   (( start_chapter == end_chapter && start_verse > end_verse )); then
  echo "aliyah2verses.sh: start ($start_ref) must be <= end ($end_ref)" >&2
  exit 64
fi

POCKET_TORAH_REPO="${POCKET_TORAH_REPO:-rneiss/PocketTorah}"
POCKET_TORAH_BRANCH="${POCKET_TORAH_BRANCH:-master}"
RAW_BASE="https://raw.githubusercontent.com/${POCKET_TORAH_REPO}/${POCKET_TORAH_BRANCH}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${TAAMEIMIKRA_CACHE:-$script_dir/cache}"
mkdir -p "$CACHE_DIR"

# cache_path <relative-path> — deterministic local cache filename for a raw
# PocketTorah path. Map / and space to distinct characters so different
# upstream paths cannot collide on a shared cache filename.
cache_path() {
  printf '%s/%s' "$CACHE_DIR" "$(printf '%s' "$1" | tr '/ ' '_-')"
}

# fetch <relative-path> — print contents of a PocketTorah file, caching it
# locally on first request so repeated lookups are cheap. A missing file is
# fatal.
fetch() {
  local rel="$1"
  local cached
  cached="$(cache_path "$rel")"
  if [[ ! -s "$cached" ]]; then
    # Percent-encode spaces; raw.githubusercontent.com rejects bare spaces.
    local encoded="${rel// /%20}"
    # On a miss curl leaves an empty output file behind; drop it so a later
    # run does not treat the stale zero-byte cache as a hit.
    curl --fail --silent --show-error --location \
      "$RAW_BASE/$encoded" -o "$cached" >&2 || { rm -f "$cached"; return 1; }
  fi
  cat "$cached"
}

# fetch_label <parsha_id> <aliyah_num> — print a PocketTorah per-word label
# file. The upstream label directory is case-inconsistent: most parshiot ship
# as "<Parsha>-N.txt" (e.g. Bamidbar-3.txt) but a handful ship lowercased
# (e.g. devarim-3.txt, eikev-1.txt), and the haftarah aliyah appears as both
# "-H" and "-h". raw.githubusercontent.com is case-sensitive, so probe the
# plausible casings and cache the first that resolves. A total miss is fatal.
fetch_label() {
  local parsha="$1" num="$2"
  local lower_parsha
  lower_parsha="$(printf '%s' "$parsha" | tr '[:upper:]' '[:lower:]')"

  local -a parsha_cases=("$parsha")
  [[ "$lower_parsha" != "$parsha" ]] && parsha_cases+=("$lower_parsha")

  local -a num_cases=("$num")
  [[ "$num" == [Hh] ]] && num_cases=(H h)

  local pc nc rel cached
  for pc in "${parsha_cases[@]}"; do
    for nc in "${num_cases[@]}"; do
      rel="data/torah/labels/${pc}-${nc}.txt"
      cached="$(cache_path "$rel")"
      if [[ -s "$cached" ]]; then
        cat "$cached"
        return 0
      fi
      # Probe quietly: an expected 404 on a wrong-case candidate is not an
      # error worth showing the user, so omit --show-error here.
      if curl --fail --silent --location \
           "$RAW_BASE/${rel// /%20}" -o "$cached"; then
        cat "$cached"
        return 0
      fi
      rm -f "$cached"
    done
  done
  echo "aliyah2verses.sh: no label file for $parsha aliyah $num" >&2
  return 1
}

# norm <name> — flatten whitespace, hyphens, and case for tolerant matching
# of parsha names (e.g. "Acharei Mot" vs "Achrei Mot" vs "Lech-Lecha").
norm() {
  printf '%s' "${1//’}" | tr -d " \-_'\"" | tr '[:upper:]' '[:lower:]'
}

# norm_skeleton <name> — like norm, but also strips ASCII vowels so common
# transliteration variants (Acharei vs Achrei, Vaera vs Va'eira) collapse
# to the same skeleton.
norm_skeleton() {
  norm "$1" | tr -d 'aeiou'
}

aliyah_json="$(fetch data/aliyah.json)"

# SC1112: the ’ (U+2019) in the jq character class is intentional — it matches
# parsha ids like Beha’alotcha; it is not a stray smart-quote.
# shellcheck disable=SC1112
parsha_id="$(jq -r --arg n "$(norm "$parsha_in")" '
  .parshiot.parsha[]
  | select((._id | gsub("[ \\-_’]"; "") | ascii_downcase) == $n)
  | ._id
' <<<"$aliyah_json")"

if [[ -z "$parsha_id" ]]; then
  # Fall back to a vowel-stripped skeleton match for transliteration drift.
  # shellcheck disable=SC1112  # intentional U+2019 in the jq class (see above)
  parsha_id="$(jq -r --arg n "$(norm_skeleton "$parsha_in")" '
    .parshiot.parsha[]
    | select(
        (._id | gsub("[ \\-_’]"; "") | ascii_downcase | gsub("[aeiou]"; ""))
        == $n
      )
    | ._id
  ' <<<"$aliyah_json")"
fi

if [[ -z "$parsha_id" ]]; then
  echo "aliyah2verses.sh: unknown parsha: $parsha_in" >&2
  exit 1
fi

# PocketTorah audio filenames strip spaces and U+2019 chars from the parsha id
# (e.g. "Achrei Mot" -> AchreiMot, "Beha’alotcha" -> Behaalotcha).
audio_id="$(printf '%s' "${parsha_id//’}" | tr -d ' ')"

# Derive the English Tanach book name from the parsha's _verse field
# (e.g. "Leviticus 16:1 - 18:30") so we can look up the matching JSON.
english_book="$(jq -r --arg p "$parsha_id" '
  .parshiot.parsha[] | select(._id == $p) | ._verse | split(" ") | .[0]
' <<<"$aliyah_json")"

book_json="$(fetch "data/torah/json/${english_book}.json")"

mkdir -p "${book_dir}/${parsha_id}"

while IFS=: read -r chapter v; do
  # Find the fullkriyah aliyah whose [_begin, _end] range covers chapter:v.
  # The fullkriyah ranges are non-overlapping, so wrap the stream in first(...)
  # rather than piping through head; the latter would race with pipefail when
  # head closes the pipe before jq finishes writing.
  aliyah_num="$(jq -r --arg p "$parsha_id" --argjson c "$chapter" --argjson v "$v" '
    first(
      .parshiot.parsha[]
      | select(._id == $p)
      | .fullkriyah.aliyah[]
      | select(._num != "M")
      | (._begin | split(":") | map(tonumber)) as $b
      | (._end   | split(":") | map(tonumber)) as $e
      | select(
          ($b[0] <  $c) or ($b[0] == $c and $b[1] <= $v)
        )
      | select(
          ($e[0] >  $c) or ($e[0] == $c and $e[1] >= $v)
        )
      | ._num
    ) // empty
  ' <<<"$aliyah_json")"

  if [[ -z "$aliyah_num" ]]; then
    echo "aliyah2verses.sh: no aliyah covers $parsha_id ${chapter}:${v}" >&2
    continue
  fi

  # Pull the begin/end refs of that aliyah so we know where to start counting
  # words for verse-index math.
  read -r b_chap b_verse e_chap e_verse <<<"$(jq -r --arg p "$parsha_id" --arg n "$aliyah_num" '
    .parshiot.parsha[]
    | select(._id == $p)
    | .fullkriyah.aliyah[]
    | select(._num == $n)
    | (._begin | split(":") | map(tonumber)) as $b
    | (._end   | split(":") | map(tonumber)) as $e
    | "\($b[0]) \($b[1]) \($e[0]) \($e[1])"
  ' <<<"$aliyah_json")"

  # Sum word counts of every verse in this aliyah strictly before chapter:v;
  # that's the label index where verse v begins. Then add this verse's word
  # count to get the index where the next verse begins.
  read -r start_idx end_idx <<<"$(jq -r \
    --argjson c "$chapter" --argjson v "$v" \
    --argjson bc "$b_chap" --argjson bv "$b_verse" \
    --argjson ec "$e_chap" --argjson ev "$e_verse" '
    . as $book
    | reduce range($bc; $ec + 1) as $ch (
        {idx: 0, start: null, end: null};
        . as $st
        | (if $ch == $bc then $bv else 1 end) as $first
        | ($book.Tanach.tanach.book.c[$ch - 1].v | length) as $vmax
        | (if $ch == $ec then $ev else $vmax end) as $last
        | reduce range($first; $last + 1) as $vv ($st;
            . as $s
            | ($book.Tanach.tanach.book.c[$ch - 1].v[$vv - 1].w | length) as $wc
            | if $ch == $c and $vv == $v then
                .start = .idx | .end = (.idx + $wc) | .idx = (.idx + $wc)
              else
                .idx = (.idx + $wc)
              end
          )
      )
    | "\(.start) \(.end)"
  ' <<<"$book_json")"

  if [[ "$start_idx" == "null" ]]; then
    echo "aliyah2verses.sh: verse $parsha_id ${chapter}:${v} not found in book JSON" >&2
    continue
  fi

  labels="$(fetch_label "$parsha_id" "$aliyah_num" | tr -d '\n')"
  IFS=',' read -r -a stamps <<<"$labels"

  start="${stamps[$start_idx]:-}"
  end="${stamps[$end_idx]:-}"

  src_url="${RAW_BASE}/data/audio/${audio_id}-${aliyah_num}.mp3"
  out="${book_dir}/${parsha_id}/${parsha_id} ${chapter}-${v}.mp3"

  # If the verse is the last in the aliyah, $end may be empty; let ffmpeg
  # read to end of stream by omitting -to in that case.
  if [[ -n "$end" ]]; then
    printf "ffmpeg -nostdin -y -i %q -ss %s -to %s -c copy " \
      "$src_url" "$start" "$end"
  else
    printf "ffmpeg -nostdin -y -i %q -ss %s -c copy " \
      "$src_url" "$start"
  fi

  # Increment track counter to correctly set track listing metadata.
  track_counter=$((${track_counter:-0}+1))

  printf -- "-metadata title=%q -metadata artist=%q -metadata album=%q -metadata track=%q %q\n" \
    "Pasuk ${chapter}:${v}" \
    "PocketTorah" \
    "Taamei Mikra: ${parsha_id}" \
    "${track_counter}" \
    "$out"

done < <(jq -r \
  --argjson sc "$start_chapter" --argjson sv "$start_verse" \
  --argjson ec "$end_chapter"   --argjson ev "$end_verse" '
  range($sc; $ec + 1) as $c
  | (if $c == $sc then $sv else 1 end) as $vfirst
  | .Tanach.tanach.book.c[$c - 1].v as $verses
  | (if $c == $ec then $ev else ($verses | length) end) as $vlast
  | range($vfirst; $vlast + 1) as $v
  | "\($c):\($v)"
' <<<"$book_json")
