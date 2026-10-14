---
name: bash-doctrine
description: Core rules for authoring and reviewing Bash — return-code discipline instead of `set -e`, the sourceable main() pattern, quoting and BashPitfalls baseline, version guards, naming, and the script header contract. Load BEFORE writing or editing any `.sh` file or shell function, and when reviewing shell for correctness. Triggers on: writing or editing a shell script, adding a script to a repo, `set -euo pipefail`, sourcing scripts, shell functions, script naming. For operational scripts (deploy/teardown/AWS/kubectl/terraform, emitted command streams, secrets, remote execution) ALSO load bash-ops.
---

# Bash doctrine — core

Directive rules for every Bash script, whatever its purpose. The reasoning, failure modes, and worked examples live in `doctrine/STYLE.md` of `ryderdain/bash`; read it when a rule seems wrong for a case.

Scripts fall into three archetypes. **Repeated-use operational scripts** — mutating/action (emit-commands) and read-only check/generator — have their own rules: load the **bash-ops** skill alongside this one. **Interactive run-once scripts** (installers, first-time configurators) talk to a human, not a pipe: they follow the core rules here, may define conventions of their own, and often *consume* ops-shaped scripts without following ops conventions — do not apply bash-ops rules to them.

*Skill directories are kebab-case by ecosystem convention: a language-native convention outranks the default. Script file names use hyphens, as below.*

## 1. Return codes, not `set -e`

- **Do not use `set -e`.** It does not fire in command lists, in any command in a conditional context, in functions called from a condition, or through `local x=$(false)`.
- **Check the return code of every command whose failure matters**, explicitly.
- `set -o pipefail` is fine **when you can state why** — a piped generator's failure must not be masked. Comment the reason at the site.
- `|| true` on a stream that is emitted or consumed downstream is forbidden; it converts a failure into silent bad output. On an emitted stream, let the failure show in the log instead (bash-ops §1).
- **Never blanket-`&&`-chain commands** to get fail-fast. It is `set -e` in different notation. Check each command explicitly.

## 2. The sourceable `main()` pattern

Action scripts must run directly **or** be `source`d by an orchestrator.

```sh
# 1. Detect sourced-ness in THIS frame, first, before anything else.
#    A helper function cannot do this for you.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

source "<path>/includes/runlib.sh"

# 2. All work in named functions.
do_the_thing() {
  require_tools aws jq || end_function "$?" 'missing prerequisites'
  # ...
  end_function "$?" 'what just happened'
}

# 3. CLI dispatch, only when not sourced.
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else do_the_thing; fi
fi
```

`end_function` returns when sourced and exits when run directly — so an orchestrator survives a callee's failure and decides what to do, while a standalone run fails hard.  Everything it logs goes to **stderr**, so an emitted or generated stdout stream stays clean.

## 3. Baseline

- Draft against [BashPitfalls](https://mywiki.wooledge.org/BashPitfalls). Assume word-splitting, unset variables, and spaces in paths until proven otherwise.
- Quote every expansion unless you have a stated reason not to.
- Bashisms over subprocesses for string work — parameter expansion, not a `sed` fork.
- Enforce a minimum bash version at the top of the file: `(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }`
- **Identifiers (variables, functions) are `snake_case`; script FILE names use hyphens, never underscores** — `do_the_thing` is a function, `do-the-thing.sh` is a script, never `do_the_thing.sh`. A file name says what the file is for: a file of functions to source says so (`roll-func.sh`, not `roll.sh`). Scripts and functions stay visibly distinct. A stronger language-native convention still governs its own territory (Go's MixedCaps, Kubernetes manifest camelCase).
- Test membership with an equality test, not an unanchored regex against a joined string.

## 4. Header contract

Every script's header comment states, in this order: what it does, which archetype it is, how to invoke it, and which credentials or inputs it expects. If and only if it uses `set -o pipefail`, say why.
