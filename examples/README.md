# Examples — the doctrine, as code that actually ran

These are **verbatim copies** of working scripts from my other repositories, pulled in so the doctrine in [`doctrine/`](../doctrine/) can point at real implementations rather than at illustrations written to make a point. Each carries a provenance block after its shebang naming the source repo, path, and commit.

**Do not edit them here.** Fix the upstream copy and re-pull; a divergence between an example and its source is worse than no example. The pull is mechanical — provenance block inserted after line 1, everything else byte-identical.

They serve three purposes:

1. **Reference** — what each doctrine section looks like when a real constraint (an AWS API, a token, a 3 a.m. teardown) pushes back on it.
2. **Linter corpus** — a body of code the linter must parse without choking, including [`antipatterns/`](antipatterns/), which it must *not* pass.
3. **Honesty check** — where a rule and the code disagree, one of them is wrong, and it is not always the code.

---

## `emit/` — the mutating/action archetype (§1.2)

Scripts that **print the commands they would run** and are executed by piping into a shell. `bash x.sh` is the preview; `bash x.sh | bash` is the run.

| Script | Shows |
| --- | --- |
| [`create-pullthrough-secrets.sh`](emit/create-pullthrough-secrets.sh) | The densest single example. Emit archetype (§1.2), secrets referenced by name so the value only ever expands in the piped shell (§1.3), *and* a second action following stdout-canonical/file-as-argument (§1.5) — all in one file, with the two archetypes deliberately kept as separate dispatchable functions. |
| [`create-cluster-secrets.sh`](emit/create-cluster-secrets.sh) | The same pattern at minimum size, via a shared `emit_k8s_secret` helper. Read this one first. |
| [`ship-repo.sh`](emit/ship-repo.sh) | Emit + §1.8: the emitted stream is what lets execution be relocated to the toolbox. |
| [`aliyah2verses.sh`](emit/aliyah2verses.sh) | Emit-then-pipe applied to slicing audio recordings with `ffmpeg`. Included deliberately: the pattern is not an AWS habit, it is a way of writing scripts. |

## `generate/` — the read-only check/generator archetype (§1.2)

Scripts that **run their queries directly** and emit a report or data to stdout with a meaningful exit code. No preview ceremony — they change nothing.

| Script | Shows |
| --- | --- |
| [`admin-ip-check.sh`](generate/admin-ip-check.sh) | The archetype done properly: a real answer on stdout, a non-zero exit on mismatch, and the *exact remediation* on stderr. A check that tells you what to do about it. |
| [`cluster-status.sh`](generate/cluster-status.sh) | Threshold-driven exit code — "at least N nodes Ready" — so it composes into a gate. |
| [`resolve-ecr-host.sh`](generate/resolve-ecr-host.sh) | §1.7: an account-bearing value derived live from `aws sts get-caller-identity`, never carried in an env var an operator has to remember. |
| [`render-recovery-manifest.sh`](generate/render-recovery-manifest.sh) | §1.1 bashisms over subprocesses — whole-file substitution by parameter expansion instead of a `sed` pipeline — plus the full §1.4 sourceable shape at readable size. |

## `orchestrate/` — the sourceable `main()` pattern at scale (§1.4)

| Script | Shows |
| --- | --- |
| [`platform.sh`](orchestrate/platform.sh) | ~700 lines sequencing every other script in that repo through the sourced-function contract. Also the honest picture of §1.8's "the orchestrator is a stream too", and the only place `set -o pipefail` appears — six times, each guarding a specific piped generator whose failure must not be masked. Worth reading *because* it is long: the pattern's claim is that it stays legible at this size. |
| [`runlib.sh`](orchestrate/runlib.sh) | The harness as it exists in situ, with its AWS and Kubernetes helpers attached. The de-project-ified core lives at [`includes/runlib.sh`](../includes/runlib.sh) and is the version to source. |

## `portable/` — shell-portability and dispatch (§1.9)

| Script | Shows |
| --- | --- |
| [`port-qa.sh`](portable/port-qa.sh) | POSIX `#!/bin/sh` throughout, `getopts`, output-directory convention. Runs on a FreeBSD host with no bash installed — the concrete case §1.9's portability claim is about. **Also a live §1.1 violation: it is hyphen-named.** Left as-is; see the note below. |
| [`vm.sh`](portable/vm.sh) | Subcommand dispatch and an environment-variable configuration surface, documented in the header rather than discovered by reading the body. |

## `antipatterns/` — what the linter must catch

| Script | Shows |
| --- | --- |
| [`vpc-nuke.sh`](antipatterns/vpc-nuke.sh) | Mine, and instructive precisely because of *how* it fails. See below. |

### Why `vpc-nuke.sh` is the example

It deletes default VPCs across every region in the account, and it is **half-emitted**. The commands that delete the VPC's dependencies — detach/delete the internet gateway (L37–38), delete the subnets (L44), delete the security groups (L50) — are `echo`ed. The command that deletes the VPC itself (L54) *runs*.

So it can only ever fail: AWS refuses to delete a VPC that still has an IGW attached and subnets in it, which is exactly the state this script guarantees. And because nothing checks a return code, the next line prints `"Default VPC deleted in $region"` anyway. A script that cannot succeed, reporting success, once per region.

Everything else is ordinary:

- `KEEP_REGIONS=` (L12) assigns the empty *string*, not an array — the keep-list is silently inert, so the "regions you want to KEEP" feature does nothing at all.
- Membership is tested with `[[ " ${KEEP_REGIONS[@]} " =~ " ${region} " ]]` (L19) — an unanchored *regex* match against a space-joined string, where an equality test was meant.
- `${ALL_REGIONS[@]}`, `$region`, `$VPC_ID` unquoted throughout.
- Command substitutions feeding array assignments with no check that the `aws` call succeeded — a failed `describe-regions` yields an empty loop and a clean exit.

Each of those maps to a doctrine rule, which is why this file is here instead of fixed: §1.2 (pick an archetype and hold it — the fatal one), §1.1 (quoting, explicit return-code checks). It is the linter's acceptance test.

---

## Known violations, kept on purpose

One file breaks a rule it is filed under, and it is load-bearing for the audit (task item 2) and the linter (task item 3):

- **`tests/destroy-tf-modules.sh`** — this repo's own cited reference implementation for §1.4 — has an `end_function` whose `cd "$starting_position"` runs unguarded when the variable was never set.

(Its hyphenated name, and `portable/port-qa.sh`'s, were violations under the old all-`snake_case` rule; under §1.1 now, hyphenated script names are correct.)

The emit examples also predate the §1.2 rule against blanket `&&`-chaining (group emitted commands as anonymous functions; check only where running a block again would hurt). They are kept as snapshots of the code they were taken from:

- **`emit/create-cluster-secrets.sh`** and the `emit_k8s_secret` helper in **`orchestrate/runlib.sh`** emit `&&`-chained streams, and their comments say so.
- **`emit/create-pullthrough-secrets.sh`** emits an `&&`/`||` chain for each secret.
- **`emit/ship-repo.sh`** emits a `( cd … && … )` subshell chain.

They change when their upstream scripts are rewritten, not before.
