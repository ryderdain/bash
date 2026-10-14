#!/bin/sh
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/freebsd-portupdater @ 95c3d8a
# │ path     : scripts/port-qa.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.9 shell-portability — POSIX `#!/bin/sh`, getopts, output-directory convention. NOTE: hyphen-named, against §1.1
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# port-qa.sh — generic FreeBSD port update + QA runner.
#
# Runs ON a FreeBSD host (local VM, CI VM, jail, or bare metal). Given a port
# origin, optionally bumps it to a new version, runs QA, and collects a
# Bugzilla-ready diff, description, and logs into an output directory.
#
# Usage:
#   port-qa.sh -o category/portname [options]
#
# Options:
#   -o origin     Port origin, e.g. deskutils/hebcal (required)
#   -v version    New DISTVERSION/PORTVERSION. Omit to QA the tree as-is
#                 (i.e. you already edited the port by hand or via a patch).
#   -m mode       QA mode: poudriere | stage | auto (default: auto).
#                 auto picks poudriere when a usable jail exists, else stage.
#   -t tree       Path to the ports tree (default: poudriere default tree if
#                 present, else /usr/ports). Must be a git checkout.
#   -j jail       Poudriere jail name (poudriere mode; default: first jail)
#   -p ptree      Poudriere ports-tree name (poudriere mode; default: default)
#   -O outdir     Output directory (default: ./port-qa-output)
#   -h            Show this help
#
# Outputs (in outdir):
#   <port>-<version>.diff   git diff of the port, ready to attach to Bugzilla
#   pr-summary.txt          one-line Bugzilla summary
#   pr-description.txt      description template with actual QA results
#   qa.log                  full log of this run
#   portlint.txt            portlint output
#   poudriere-logs.tgz      testport logs (poudriere mode only)
#
# Exit status is non-zero if the build/QA fails; portlint warnings are
# reported but not fatal.

set -u

# Explicit error handling rather than blanket errexit: set -e is silently
# disabled inside conditionals and has surprising semantics in functions and
# pipelines, so every step that matters checks its own status instead.
error() { _code=$1; shift; echo "ERROR: $*" >&2; exit "$_code"; }

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

ORIGIN=""
VERSION=""
MODE="auto"
TREE=""
JAIL=""
PTREE="default"
OUTDIR=""

while getopts o:v:m:t:j:p:O:h opt; do
  case $opt in
    o) ORIGIN=$OPTARG ;;
    v) VERSION=$OPTARG ;;
    m) MODE=$OPTARG ;;
    t) TREE=$OPTARG ;;
    j) JAIL=$OPTARG ;;
    p) PTREE=$OPTARG ;;
    O) OUTDIR=$OPTARG ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

[ -n "$ORIGIN" ] || { echo "ERROR: -o category/portname is required" >&2; usage 1; }
case $ORIGIN in
  */*) ;;
  *) error 1 "origin must look like category/portname" ;;
esac

# --- resolve defaults ------------------------------------------------------

if [ -z "$TREE" ]; then
  if [ -d "/usr/local/poudriere/ports/$PTREE" ]; then
    TREE="/usr/local/poudriere/ports/$PTREE"
  else
    TREE="/usr/ports"
  fi
fi
PORTDIR="$TREE/$ORIGIN"
[ -d "$PORTDIR" ] || error 1 "no such port: $PORTDIR"
git -C "$TREE" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || error 1 "$TREE is not a git checkout (needed to produce the diff)"

if [ "$MODE" = "auto" ]; then
  if command -v poudriere >/dev/null 2>&1 && [ -n "$(poudriere jail -lnq 2>/dev/null)" ]; then
    MODE="poudriere"
  else
    MODE="stage"
  fi
fi

if [ "$MODE" = "poudriere" ] && [ -z "$JAIL" ]; then
  JAIL=$(poudriere jail -lnq | head -1)
  [ -n "$JAIL" ] || error 1 "poudriere mode but no jail exists"
fi

OUTDIR="${OUTDIR:-$(pwd)/port-qa-output}"
mkdir -p "$OUTDIR" || error 1 "cannot create output directory $OUTDIR"
LOG="$OUTDIR/qa.log"
: > "$LOG"

say() { echo "==> $*" | tee -a "$LOG"; }
run() { echo "\$ $*" >> "$LOG"; "$@" >> "$LOG" 2>&1; }

PORTNAME=$(make -C "$PORTDIR" -V PORTNAME) \
  || error 1 "make -V PORTNAME failed — is $PORTDIR a valid port?"
OLDVERSION=$(make -C "$PORTDIR" -V DISTVERSIONFULL) || error 1 "make -V DISTVERSIONFULL failed"
MAINTAINER=$(make -C "$PORTDIR" -V MAINTAINER) || error 1 "make -V MAINTAINER failed"

say "port:       $ORIGIN ($PORTNAME)"
say "tree:       $TREE"
say "current:    $OLDVERSION"
say "qa mode:    $MODE"
say "output:     $OUTDIR"

# --- optional version bump -------------------------------------------------

if [ -n "$VERSION" ]; then
  say "bumping to $VERSION"
  MK="$PORTDIR/Makefile"
  if grep -q '^DISTVERSION' "$MK"; then
    sed -i.qa-bak -E "s|^(DISTVERSION[?+:!]*=[[:space:]]*).*|\1${VERSION}|" "$MK" \
      || error 1 "failed to edit DISTVERSION in $MK"
  elif grep -q '^PORTVERSION' "$MK"; then
    sed -i.qa-bak -E "s|^(PORTVERSION[?+:!]*=[[:space:]]*).*|\1${VERSION}|" "$MK" \
      || error 1 "failed to edit PORTVERSION in $MK"
  else
    error 1 "neither DISTVERSION nor PORTVERSION found in $MK" \
      "(complex port — edit it by hand and re-run without -v)"
  fi
  # A version bump resets PORTREVISION.
  sed -i.qa-bak -E '/^PORTREVISION[?+:!]*=/d' "$MK" || error 1 "failed to drop PORTREVISION"
  rm -f "$MK.qa-bak"

  say "regenerating distinfo (make makesum)"
  run make -C "$PORTDIR" -DBATCH makesum \
    || { say "FAILED: make makesum — see $LOG"; exit 1; }
fi

NEWVERSION=$(make -C "$PORTDIR" -V DISTVERSIONFULL) \
  || error 1 "make -V DISTVERSIONFULL failed after version bump"

# --- lint (non-fatal) ------------------------------------------------------

PORTLINT_RESULT="skipped (portlint not installed)"
if command -v portlint >/dev/null 2>&1; then
  say "running portlint"
  # PORTSDIR matters: portlint assumes /usr/ports otherwise
  if (cd "$PORTDIR" && env PORTSDIR="$TREE" portlint -AC) > "$OUTDIR/portlint.txt" 2>&1; then
    PORTLINT_RESULT="OK"
  else
    PORTLINT_RESULT="warnings (see portlint.txt)"
  fi
  say "portlint: $PORTLINT_RESULT"
fi

PORTCLIPPY_RESULT="skipped (portclippy not installed)"
if command -v portclippy >/dev/null 2>&1; then
  say "running portclippy"
  if (cd "$PORTDIR" && portclippy Makefile) >> "$OUTDIR/portlint.txt" 2>&1; then
    PORTCLIPPY_RESULT="OK"
  else
    PORTCLIPPY_RESULT="warnings (see portlint.txt)"
  fi
  say "portclippy: $PORTCLIPPY_RESULT"
fi

# --- build QA ---------------------------------------------------------------

QA_RESULT=""
case $MODE in
  poudriere)
    say "running poudriere testport (jail: $JAIL, tree: $PTREE) — this is the slow part"
    if poudriere testport -j "$JAIL" -p "$PTREE" -o "$ORIGIN" >> "$LOG" 2>&1; then
      QA_RESULT="poudriere testport: OK"
      say "testport: OK"
    else
      QA_RESULT="poudriere testport: FAILED"
      say "testport: FAILED — see $LOG"
    fi
    BULKLOGS="/usr/local/poudriere/data/logs/bulk/${JAIL}-${PTREE}/latest"
    if [ -d "$BULKLOGS" ]; then
      tar -czf "$OUTDIR/poudriere-logs.tgz" -C "$BULKLOGS/.." "$(basename "$(readlink -f "$BULKLOGS")")" 2>/dev/null \
        || tar -czhf "$OUTDIR/poudriere-logs.tgz" -C "$(dirname "$BULKLOGS")" "$(basename "$BULKLOGS")"
      say "poudriere logs saved to poudriere-logs.tgz"
    fi
    [ "$QA_RESULT" = "poudriere testport: OK" ] || FAILED=1
    ;;
  stage)
    say "installing build/run/test dependencies as official packages"
    # Not `make install-missing-packages` — that target pipes through SU_CMD
    # and `xargs -o` (which opens /dev/tty), so it only works interactively.
    DEPS=$(make -C "$PORTDIR" build-depends-list run-depends-list test-depends-list 2>>"$LOG" \
      | sed "s|^$TREE/||" | sort -u) \
      || error 1 "could not compute dependency list — see $LOG"
    if [ -n "$DEPS" ]; then
      # $DEPS is intentionally unquoted: one origin per word.
      run env ASSUME_ALWAYS_YES=yes pkg install -A $DEPS \
        || { say "FAILED: dependency installation — see $LOG"; exit 1; }
    fi
    say "running make stage / stage-qa / check-plist / package"
    STAGE_OK=yes
    for target in clean stage stage-qa check-plist package; do
      if ! run make -C "$PORTDIR" -DBATCH "$target"; then
        say "FAILED: make $target — see $LOG"
        STAGE_OK=no
        break
      fi
      say "make $target: OK"
    done
    run make -C "$PORTDIR" -DBATCH clean || true
    if [ "$STAGE_OK" = "yes" ]; then
      QA_RESULT="make stage + stage-qa + check-plist + package: OK"
    else
      QA_RESULT="make stage QA: FAILED"
      FAILED=1
    fi
    ;;
  *)
    error 1 "unknown QA mode: $MODE" ;;
esac

# --- collect diff + submission text ----------------------------------------

say "generating diff"
# Include newly-added files (e.g. files/patch-*) in the diff.
git -C "$TREE" add -N -- "$ORIGIN" 2>/dev/null || true
DIFF="$OUTDIR/${PORTNAME}-${NEWVERSION}.diff"
git -C "$TREE" diff -- "$ORIGIN" > "$DIFF" || error 1 "git diff failed"
if [ ! -s "$DIFF" ]; then
  say "note: diff is empty (no changes in $ORIGIN)"
fi

if [ -n "$VERSION" ]; then
  SUMMARY="$ORIGIN: Update to $NEWVERSION"
else
  SUMMARY="$ORIGIN: <one-line summary of the change>"
fi
printf '%s\n' "$SUMMARY" > "$OUTDIR/pr-summary.txt"

cat > "$OUTDIR/pr-description.txt" <<EOF
$SUMMARY

Changelog:
- <fill in upstream changes / what this patch does>

QA (run on $(uname -sr) $(uname -p)):
- $QA_RESULT
- portlint -AC: $PORTLINT_RESULT
- portclippy: $PORTCLIPPY_RESULT

Port maintainer: $MAINTAINER
EOF

say "done"
say "  diff:        $DIFF"
say "  summary:     $OUTDIR/pr-summary.txt"
say "  description: $OUTDIR/pr-description.txt (edit the changelog before submitting)"

[ -z "${FAILED:-}" ] || exit 1
