---
name: bash-ops
description: Rules for repeated-use operational Bash — the ops archetypes (emit-commands, read-only generator, and the DRIVER that runs phases through run-logs), how to shape an emitted stream ({ … } groups as anonymous functions, a check only where re-running a block would harm, never blanket &&-chaining), idempotent phases with a per-phase check, environment definitions (plain NAME=value files, exported values win), the approval rule, secrets by reference, stdout-canonical output, safe remote execution, dual-locus credentials, and the infrastructure operating model (saved-plan Terraform, teardown sweeps). Extends bash-doctrine; load BOTH for any script that deploys, tears down, or configures infrastructure. Triggers on: scripts that touch AWS/kubectl/terraform/helm, emitting commands or piping to `| bash`, writing a driver/orchestrator or phase script, run-logs, env files, `ssh host "..."`, CI/automation scripts, secrets or credentials in scripts, any script that produces content another step consumes. NOT for interactive run-once scripts (installers, configurators) — those follow bash-doctrine core only.
---

# Bash doctrine — operations

Extends **bash-doctrine** (load it first); rule references like "the return-code rule" point there. Scope: **repeated-use operational scripts** — run many times, by many operators, often unattended. Interactive run-once scripts are out of scope: they consume these scripts without following these conventions.

Reasoning and worked examples: `doctrine/STYLE.md` §1.2–§1.9 and `doctrine/OPERATIONS.md` of `ryderdain/bash`.

## 1. Pick an archetype and hold it

Every ops script is exactly one of two kinds. Blending them is the failure mode that produces action sequences which cannot succeed.

**Mutating / action → EMIT the commands, do not run them.**

- Print the commands to stdout. The caller previews with `bash x.sh` and runs with `bash x.sh | bash`.
- Emit commands in **`{ … }` groups used as anonymous functions**: one group per feature or object whose commands depend on each other closely and make sense run as a block. The group is for the **reader** of the preview first. Braces belong to the emitted text, not to code inside the script (use named functions there).
- **No check on every command.** A dependent failure shows in the log; an idempotent create that finds its object already there is fine. Never blanket-`&&`-chain (it is `set -e` in disguise and fails silently at the seam between two streams).
- **One check only where running the block again would be harmful, or where a failure would leave the state ambiguous.** Use `error` from `includes/error.sh`: print its definition at the top of the stream (only when used), stop with the reserved code **3** (`cmd || error 3 "<what state was left>"`), in words the operator can act on. Do not invent a second error helper. **A group that carries an `error` check is never piped** (not even to `log`): in a piped group the `exit` ends only the pipe's subshell and the stream runs on.
- To label a block's output, pipe the whole group once: `{ …; } 2>&1 | log '<name>'`, with a bespoke `log()` defined at the top of the stream. A piped group runs in a subshell, so groups stay self-contained: inputs from the emitted text, results in files.
- The emitted output must read as a straightforward procedure: runnable both from a saved file and piped to `bash`.
- When a generator feeds a downstream consumer, wrap it: `set -o pipefail; bash gen.sh | bash`.
- Never print *some* of the sequence and execute the rest.

**Read-only check / generator → RUN directly, report to stdout.**

- No preview ceremony; it changes nothing.
- Exit code must be meaningful — it is the script's real return value.
- On a failed check, print the exact remediation to **stderr**.

A script that genuinely needs both gets **one function per archetype**, separately dispatchable. Never blended in a single function.

The sourceable `main()` pattern (bash-doctrine) composes with this: an emit-style function still prints commands. The header contract gains a line: emit scripts show both the preview invocation and the run invocation.

## 2. Secrets: the artifact carries references, never values

- Emitted text contains `"$GHCR_TOKEN"` — the **name**. Only the shell that ultimately runs the command expands it, from that shell's own trusted source.
- Never interpolate a resolved secret into text that gets printed, reviewed, logged, or transmitted.
- When a tool must be *handed* a credential, use `GIT_ASKPASS` or equivalent so it never lands in `argv` (visible to `ps`), in `.git/config`, or in output. Scrub remote URLs after.
- To inspect a secret, print its **byte-length and charset class**, never its value.
- Secrets resolve at the **execution locus**. For remote execution the secret lives on the remote host, from its own secret store — do not pipe it from the laptop.

## 3. Producing content: stdout is canonical, the file is an argument

For any script whose point is producing content (a rendered manifest, a tfvars line, a kubeconfig):

- **Default to stdout** — with no file argument, print the content so it pipes.
- **Accept a target path as an argument.** Only then also write the file, backing up an existing target first.
- **Announce the path on stderr** (`wrote → <path>`), never stdout.
- **Always emit to stdout regardless**, so a retained copy is a side effect, not a mode switch.

`includes/runlib.sh` provides `emit_to <content> [target]` for exactly this.

No paste-back steps. If a script produces a value the next step needs, it puts it where it belongs.

## 4. Piping and remote execution — in this order

1. **Data to a data-consumer** — `render.sh | kubectl apply -f -`, or `render.sh | ssh host 'kubectl apply -f -'`. The content never meets a shell parser.  **Reach for this first.**
2. **Commands to a shell via stdin** — `gen.sh | ssh host bash`. Parsed exactly once, by the executing shell.
3. **Never `ssh host "inline command …"`.** The local shell builds a string and the remote shell parses it again — double-parse, quoting hell, values leaked into `argv`.

## 5. Credentials work in both loci

Scripts must run unchanged with an `AWS_PROFILE` (laptop) **and** with instance-role credentials (no profile).

- **Never hard-require `AWS_PROFILE`.** Let the SDK pick up ambient credentials.
- Guard reads as `${AWS_PROFILE:-}`; `sudo` and Ansible may strip the environment.
- Report which source is in use, on stderr, for the operator's benefit. Do not gate on it.

## 6. Derive account-bearing values at runtime

Anything embedding an account id — state bucket, registry host, role ARN — is derived from the caller (`aws sts get-caller-identity`) or read from a gitignored file the tool auto-loads. **Never** carried in a per-run environment variable an operator must remember.

## 7. Operating model

- **Saved-plan workflow, always:** `tofu plan -out=FILE` → review → `tofu apply FILE`. Never `-auto-approve` — it re-plans fresh and can drift from what was reviewed.
- **Approval rule — approval is running the output, never a prompt.** A phase whose effect leaves the driver's own machine (registry push, `git push`/commit, cloud-account change) or that costs money is driven the careful way: emit the next phase, review it, pipe it. Only phases whose effects stay local may go the fast way (`driver.sh <env> up | bash`). Approving one phase never approves the next. **Never put an interactive prompt in an emit script or the driver** — when the stream is piped to `bash`, stdin is the stream. Read-only phases run freely.
- **Authenticate with the instance profile** where a role can do the job; do not mint a second IAM user for it.
- **Secrets Manager for secrets, Parameter Store for non-secret config.** Do not conflate them.
- **Scope credentials to the job, not one token per call** — a single fine-grained token covering exactly the jobs at hand beats both an over-broad one and a fleet of fragments.
- **Teardown = reverse dependency order + explicit leak sweep.** `tofu destroy` misses: CSI-dynamically-provisioned volumes, pull-through cache repositories, script-created secrets. Deletion guards (`prevent_destroy`, non-empty repos, KMS pending-deletion windows) are features — plan around them, do not disable them casually.
- **Recover before GitOps adopts:** in a DR path, restore data standalone before the GitOps sync would initialize empty state; a standalone path installs its own prerequisites.

## 8. The driver and its phases

A driver sequences other scripts' emitted streams. It never does the work itself. Reasoning: `doctrine/STYLE.md` §1.11–§1.12.

- **The driver is an emit script.** Its output is one `{ … }` group per phase; each group (1) runs the phase's emitter into a run-log (`var/run/<env>/<YYYYmmddHHMM>/<NN>-<phase>.sh`, gitignored), (2) runs that **file** (`< /dev/null`) and writes `<NN>-<phase>.rc`, (3) runs the phase's **check** (a read-only generator) and writes `<NN>-<phase>.ok` if it passes. `driver.sh <env> next` emits the next phase only (careful); `driver.sh <env> up | bash` runs all remaining phases (fast, local-only effects).
- **Run-logs take stdin from `/dev/null`.** The procedure arrives on stdin, so a command in a run-log that reads stdin (`docker exec -i`, `kubectl exec -i`, `cat`, `ssh`) swallows the rest of it and the stream ends silently. Run each run-log, check and remote helper with `< /dev/null`; data reaches a command only by pipe or heredoc; never emit `-i` without one.
- **The exit code is not the verdict.** `.rc` only says the run-log ended, or (`.rc` = 3) an `error 3` check stopped it on purpose. The check decides whether the phase did its job.
- **Every phase must be safe to run again.** A phase can stop at any line; running it again from the top must converge. Use `kubectl apply`, `helm upgrade --install`, saved-plan `tofu apply`; let an idempotent create fail visibly.
- **Resume** = the first phase with no `.ok`. Emit it again before running it. A phase whose check keeps failing goes to the operator; do not loop on it.
- **Outputs between phases are files** in the run directory, never shell memory or paste-back.
- **Remote execution:** copy the run-log, verify it, run it detached; the remote writes the `.rc`; the driver collects it, runs the check, and writes the `.ok`. The driver's copies are the record.
- **Environment definition:** one committed file per environment, plain `NAME=value` lines, no secrets. Load it with `load_env_definition` (an exported value wins, announced on stderr). Record the resolved values at the top of each run-log with `env_definition_record`. **Never turn these values into flags.**
