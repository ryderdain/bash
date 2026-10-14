#!/usr/bin/env bash
#
# timer.sh — countdown timer for the terminal. It shows a spinner and the time
# that is left. At zero it rings the bell, flashes the screen, and shows a
# coloured banner that says how long the timer ran.
#
# Archetype: interactive. It talks to a person at a terminal, not to a pipe,
# and it changes nothing. The bash-ops conventions (emit, preview) do not
# apply. All display goes to stderr. Only timer_parse writes to stdout.
#
# Invoke:
#   bin/timer.sh 4:15                     # run directly
#   source bin/timer.sh; timer 1h2m3s     # or source it (from .bashrc) and call timer
#   bin/timer.sh timer_parse 4:15         # print the duration in seconds (255)
#
# Durations:
#   1h2m3s, 1h30m, 5m, 90s   units h, m, s; any subset, in that order
#   3                        one number    = minutes   -> 00:03:00
#   4:15                     two fields    = MM:SS     -> 00:04:15
#   01:02:03                 three fields  = HH:MM:SS
#
# Inputs: the DURATION argument. LC_ALL, LC_CTYPE or LANG select a Unicode or
# an ASCII spinner. `tput colors` selects 16- or 8-colour banners. No
# credentials. Needs bash >= 4 (bash 5 gives sub-second timing) and
# includes/runlib.sh from this repo.
#
# Exit codes: 0 when the timer ran to zero, 2 for a duration it cannot read,
# 130 when cancelled with Ctrl-C.

# 1. Detect sourced-ness in THIS frame, before anything else.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required (timer.sh)\n' >&2
  # shellcheck disable=SC2317  # the exit is reachable only when run directly
  { return 1 2>/dev/null || exit 1; }
fi

timer_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091  # dynamic path; runlib.sh is shellchecked on its own
if ! source "${timer_script_dir}/../includes/runlib.sh"; then
  printf 'error: cannot load %s\n' "${timer_script_dir}/../includes/runlib.sh" >&2
  # shellcheck disable=SC2317
  { return 1 2>/dev/null || exit 1; }
fi

# timer_usage — print the usage text to stdout. The caller picks the stream.
timer_usage() {
  printf 'Usage: timer DURATION\n'
  printf '  1h2m3s | 90s | 5m     units: h, m, s\n'
  printf '  3                     minutes\n'
  printf '  4:15                  MM:SS\n'
  printf '  01:02:03              HH:MM:SS\n'
}

# timer_parse <duration...> — GENERATOR: print the duration in whole seconds
# to stdout. Returns 2 for a duration it cannot read, with the reason on
# stderr. A success is not logged: timer calls this at every start, and an
# INFO line there is only noise.
timer_parse() {
  local in="$*" h=0 m=0 s=0 a b c total
  local re_units='^([0-9]+[hH])?([0-9]+[mM])?([0-9]+[sS])?$'
  local re_clock='^[0-9]+(:[0-9]+)?(:[0-9]+)?$'
  in="${in// /}"

  if [[ -z "$in" ]]; then
    end_function 2 'no duration given'
    return 2
  fi

  # The right side of =~ stays unquoted: a quoted pattern matches as a literal string.
  if [[ "$in" =~ $re_units ]]; then
    h="${BASH_REMATCH[1]%[hH]}"
    m="${BASH_REMATCH[2]%[mM]}"
    s="${BASH_REMATCH[3]%[sS]}"
  elif [[ "$in" =~ $re_clock ]]; then
    IFS=: read -r a b c <<<"$in"
    if [[ -n "$c" ]]; then
      h="$a"; m="$b"; s="$c"
    elif [[ -n "$b" ]]; then
      m="$a"; s="$b"
    else
      m="$a"
    fi
  else
    end_function 2 "cannot read duration \"$*\""
    return 2
  fi

  # 10# stops a leading zero ("08") from being read as octal.
  total=$(( 10#${h:-0} * 3600 + 10#${m:-0} * 60 + 10#${s:-0} ))
  if (( total <= 0 )); then
    end_function 2 'the duration must be more than zero'
    return 2
  fi
  printf '%s\n' "$total"
}

# timer_fmt_human <seconds> — print a short duration: 3723 -> "1h 2m 3s".
timer_fmt_human() {
  local t="$1" out=''
  if (( t >= 3600 )); then out+="$(( t / 3600 ))h "; fi
  if (( t % 3600 >= 60 )); then out+="$(( t % 3600 / 60 ))m "; fi
  if (( t % 60 > 0 || t == 0 )); then out+="$(( t % 60 ))s "; fi
  printf '%s' "${out% }"
}

# timer_now_us <var> — put the current time, in microseconds, into <var>.
# No fork: bash 5 has EPOCHREALTIME; bash 4 falls back to printf %()T, which
# has whole-second resolution.
timer_now_us() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    printf -v "$1" '%s' "${EPOCHREALTIME//[!0-9]/}"   # drop the "." or "," (locale radix)
  else
    printf -v "$1" '%(%s)T000000' -1
  fi
}

# timer_cancel — INT/TERM handler for timer. It reads timer's locals (start,
# label, tty) through bash's dynamic scope, because it runs inside timer.
timer_cancel() {
  local now
  if [[ "$tty" == true ]]; then printf '\r\033[K'; fi
  timer_now_us now
  end_function 130 "cancelled after $(timer_fmt_human "$(( (now - start) / 1000000 ))") of $label"
  exit 130   # reached only when sourced: end_function returned instead of exiting
}

# timer <duration...> — the default action. Count down on stderr, then
# announce the end.
#
# The body is a subshell, so its traps and its `exec >&2` stay inside it and
# never reach a shell that sourced this file.
timer() (
  local total label started now start end rem secs ran msg extra='' colors k
  local tty=false utf8=false i=0 n
  local -a frames styles

  if (( $# == 0 )) || [[ "$1" == -h || "$1" == --help ]]; then
    timer_usage >&2
    return 2
  fi
  if ! total="$(timer_parse "$@")"; then
    timer_usage >&2
    return 2
  fi
  if ! require_tools sleep; then
    end_function 1 'missing prerequisites'
    return 1
  fi

  exec >&2   # the display is for the human: stderr, not stdout
  if [[ -t 2 ]]; then tty=true; fi
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) utf8=true ;;
  esac

  label="$(timer_fmt_human "$total")"
  TZ=UTC printf -v started '%(%H:%M:%SZ)T' -1
  timer_now_us start
  end=$(( start + total * 1000000 ))

  trap 'if [[ "$tty" == true ]]; then printf "\033[?25h"; fi' EXIT   # show the cursor again
  trap timer_cancel INT TERM

  # Not a terminal (a log, cron): no spinner and no escape codes.
  if [[ "$tty" == false ]]; then
    if ! sleep "$total"; then
      end_function 1 "sleep $total failed"
      return 1
    fi
    printf "TIME'S UP - ran for %s\n" "$label"
    end_function 0 "ran for $label, started $started"
    return 0
  fi

  # --- Count down -----------------------------------------------------------
  if [[ "$utf8" == true ]]; then
    frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  else
    frames=('|' '/' '-' "\\")
  fi
  n="${#frames[@]}"

  printf '\033[?25l'   # hide the cursor
  while :; do
    timer_now_us now
    rem=$(( end - now ))
    if (( rem <= 0 )); then break; fi
    secs=$(( (rem + 999999) / 1000000 ))   # round up: show 00:00:01, never 00:00:00
    printf '\r\033[K \033[1;36m%s\033[0m  \033[1m%02d:%02d:%02d\033[0m  \033[2mof %s\033[0m' \
      "${frames[i % n]}" "$(( secs / 3600 ))" "$(( secs % 3600 / 60 ))" "$(( secs % 60 ))" "$label"
    i=$(( i + 1 ))
    if ! sleep 0.1; then
      end_function 1 'sleep 0.1 failed'
      return 1
    fi
  done

  # --- Finish: bell, flash, banner ------------------------------------------
  timer_now_us now
  ran=$(( (now - start + 500000) / 1000000 ))
  printf '\r\033[K\033[?25h'

  colors=8
  if command -v tput >/dev/null 2>&1; then
    colors="$(tput colors 2>/dev/null)" || colors=8
  fi
  if [[ ! "$colors" =~ ^[0-9]+$ ]]; then colors=8; fi
  if (( colors >= 16 )); then
    styles=('1;97;101' '1;30;103' '1;97;104' '1;30;102' '1;97;105' '1;30;106')
  else
    styles=('1;37;41' '1;30;43' '1;37;44' '1;30;42' '1;37;45' '1;30;46')
  fi

  if [[ "$utf8" == true ]]; then
    msg="  ⏰  TIME'S UP — ran for $(timer_fmt_human "$ran")  "
  else
    msg="  *** TIME'S UP - ran for $(timer_fmt_human "$ran") ***  "
  fi
  if (( ran != total )); then extra=" (set for $label)"; fi

  for (( k = 0; k < 12; k++ )); do
    if (( k % 4 == 0 )); then printf '\a'; fi         # bell, three times
    if (( k % 2 == 0 )); then printf '\033[?5h'; fi   # reverse-video screen flash on
    printf '\r\033[%sm%s\033[0m' "${styles[k % ${#styles[@]}]}" "$msg"
    sleep 0.12
    printf '\033[?5l'                                 # flash off
    sleep 0.08
  done
  printf '\r\033[K\033[%sm%s\033[0m%s\n' "${styles[0]}" "$msg" "$extra"

  end_function 0 "ran for $(timer_fmt_human "$ran")${extra}, started $started"
)

# CLI dispatch, only when run directly. A first argument that names a function
# in this file is called with the rest (the §1.4 form). Anything else is a
# duration for timer, so `bin/timer.sh 4:15` does what it says.
if [[ "$is_sourced" == false ]]; then
  if (( $# )) && declare -F -- "$1" >/dev/null; then "$@"; else timer "$@"; fi
fi
