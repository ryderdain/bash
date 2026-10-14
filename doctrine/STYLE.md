# Bash Scripting — an opinionated doctrine

This explains the reasoning behind the rules. Infrastructure and operations doctrine which sits on top of this is in [`OPERATIONS.md`](OPERATIONS.md). All the rules from these two files have been composed for a model to consume, split across two skills: [`skills/bash-doctrine/SKILL.md`](../skills/bash-doctrine/SKILL.md) carries the core rules every script follows, and [`skills/bash-ops/SKILL.md`](../skills/bash-ops/SKILL.md) extends it for repeated-use operational scripts.

Every section here which rests on a claim about how Bash actually behaves is backed by a example test in [`tests/`](../tests/) rather than left open. Some worked implementations are in [`examples/`](../examples/).

Section numbering follows an original seed document developed in other repositories, retained here so that cross-references from those projects will still resolve.

> **Status:** Part 1 is fully drafted. §1.1–§1.4 need an additional review to match the §0.1 voice; §1.5–§1.9 were written in it. §1.10 is reserved; §1.11–§1.12 (the driver, environment definitions) are new and need a voice review.

---

## §0.1 - Preface: In a Nutshell

The opinions and practices I've developed here were drawn from a variety of sources: the old `#bash` channel on IRC ca. 2008-2010, which also introduced me to [Greg's Wiki](https://mywiki.wooledge.org/), an invaluable resource even today, some of the lessons imparted in MIT's ["The Missing Semester of Your CS Education"](https://missing.csail.mit.edu/2026/command-line-environment/) online course, and of course, years of developing bash scripts for automated systems in production and for use by colleagues.

In my opinion, the most overlooked and misunderstood issue with the way most people use shell scripts in general is the _process context_. This is partly because what it means as a concept, vs. what it refers to explicitly in how a bash script works, overlaps just enough to convince one that they can be treated the same way. But in practice, the differences are sharp, and tend to bite.

Simple scripts are simple because they don't do much: they're there to assist with running more elaborate commands for other tools, such as `kubectl` or `openssl`, where the number of options and arguments can be burdensome to remember, may require succesive invocations in a particular order, or require running other commands first which confirm the next commands can safely go ahead.

What follows is a "doctrine", a set of rules backed by principles based on this experience and expectations, to avoid error, make scripts more flexible and easier to understand, and allow them to work in a wide variety of environments.

## §1.1 — Foundations

**Write for the failure modes, not the happy path.** Draft against [BashPitfalls](https://mywiki.wooledge.org/BashPitfalls); assume word-splitting, unset variables, and spaces-in-paths until proven otherwise. Quote every expansion unless you have a stated reason not to. An unquoted `$var` expects a reader to know whether word-splitting the value is intended or not, which represents a tax on attention and added complexity. Using quoted Bash arrays like `"${var[@]}"` makes your intentions far clearer and easier for a reader to follow.

**Check return codes explicitly; do not delegate to `set -e`.** Any command whose failure matters requires a check the reader can see. The use of `set -e` very often obscures why your script errored out, and may even cause the exit to _not_ fire in the places you want it to. See  ([BashFAQ/105](https://mywiki.wooledge.org/BashFAQ/105)) which lists some of these failures:

1. anywhere in a `&&`/`||` list except the final command;
2. any command tested by `if`/`while`/`!` — which is what testing means, so this one is by design;
3. the **entire body** of a function called from a condition — including bare failures that would abort anywhere else;
4. `local x=$(false)` — `local`'s own zero status replaces the substitution's failure.

All four are demonstrated, not asserted: [`tests/set-e-cases.sh`](../tests/set-e-cases.sh) runs them against the live shell and fails if bash ever behaves otherwise. Case 3 is the killer — the sourceable-function pattern (§1.4) puts _everything_ in functions and orchestrators call them from conditions, so under this doctrine's own house style `set -e` would be suspended exactly where the work happens. The two are incompatible; we keep the one that makes failures visible.

`set -o pipefail` is different: use it **when you can say why**, and say it at the site — the canonical why being a piped generator whose failure must not be masked by a healthy consumer (§1.2).

**Bashisms over subprocesses for string work.** Use parameter expansion instead of a `sed`/`awk`/`cut` fork wherever a bashism does the job. There are a few reasons for this; fewer process invocations, no need to add different escape sequences for different tools in order to work with the tool's dialect, and no danger of getting tripped up by . The portability objection is answered by the §1.9 split: the bashisms live in the _generator_, and what it emits is plain commands almost any shell can run.

**Mandate a minimum bash version and enforce it** — `(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }` at the top — rather than writing for the lowest common denominator. The guard converts "works on my machine" into a stated, testable contract, and buys the bashisms above.

**Underscores for identifiers, hyphens for script file names.** Variable and function names are `snake_case`: `do_the_thing`, `repo_root`. Script _file_ names use hyphens and never underscores: `do-the-thing.sh`, never `do_the_thing.sh`. The split is deliberate: **a file name identifies the file's purpose or the functions it holds**, and an identifier names one thing in the code. `create-secrets.sh` is a file you run, `create_secrets` is a function you call, and neither can be mistaken for the other. A file that only defines functions for others to source says so in its name: `includes/roll-func.sh`, not `includes/roll.sh`, which reads like a command. The reader of a directory listing then knows what each file does before opening it. The escape clause is deliberate and narrow: a _stronger, language-native_ convention governs its own territory (Go's MixedCaps, Kubernetes manifest camelCase, kebab-case skill directories) — the default only yields to a convention with an ecosystem behind it, not to habit.

## §1.2 — Script archetypes

Every _repeated-use operational_ script is exactly one of two kinds, and the kind dictates its shape.

**Mutating / action scripts** emit the commands they would run to stdout, and are executed by piping into a shell:

```sh
bash deploy.sh          # PREVIEW — read exactly what will run
bash deploy.sh | bash   # RUN
```

**Read-only check and generator scripts** run their queries directly and emit a report, or data, to stdout with a meaningful exit code. No preview ceremony — they change nothing.

The qualifier on "repeated-use operational" is doing real work, because there is a third kind of script this document is _not_ about: the **interactive, run-once script**. An installer, or a first-time configurator for a local application, exists to walk a person through choices they may not know the options for or the impact of. Its output is human-friendly text rather than an executable stream; it is generally expected to run once and never again; and it will often _consume_ ops-shaped scripts while following none of their conventions — which is fine, because those conventions exist for repetition, review, and unattended execution, none of which apply to it. An emit-preview makes no sense when the commands depend on answers the user hasn't given yet. Interactive scripts inherit the foundations (§1.1) and are welcome to develop conventions of their own; the rest of this Part simply isn't addressed to them.

Within ops scripting, though, this split is the spine of everything else. It makes "what will this do?" answerable without a sandbox; it is what makes a secrets-safe preview possible at all (§1.3); and it is the reason a script's output can be relocated to another host (§1.8). But the argument for holding the line is not any of those. It is this:

### A script that drifts between archetypes emits a sequence that cannot succeed

[`examples/antipatterns/vpc-nuke.sh`](../examples/antipatterns/vpc-nuke.sh) is mine, and it deletes default VPCs across every region in an account. It is half-emitted. The commands that delete the VPC's dependencies — detach and delete the internet gateway, delete the subnets, delete the security groups — are `echo`ed. The command that deletes the VPC itself runs.

So it can only ever fail. AWS refuses to delete a VPC that still has an internet gateway attached and subnets in it, and that is precisely the state this script guarantees before asking. And because nothing checks a return code, the next line prints `Default VPC deleted in $region` anyway. A script that cannot succeed, reporting success, once per region, across every region in the account.

Nobody decided that. It is what happens when a script is written a command at a time and the question "is this one previewing or executing?" is answered locally each time. The archetype rule is not an aesthetic preference about consistency; it is the thing that makes that question have one answer per file instead of one per line.

The corollary is worth stating separately, because it is the rule people break while believing they are being careful: **never print part of a sequence and execute the rest.** A mixed script is more dangerous than a fully-executing one, because the preview it shows you is a subset that reads like the whole.

### The shape of an emitted stream: group, do not chain

Given a script that emits, there is a second question: what does the emitted text look like? The obvious answer — `&&`-chain the commands so the run fails fast — is wrong, and it took a while to see why.

Emit grouped in braces instead:

```sh
{
  aws ecr create-repository --repository-name "$name"
  aws ecr put-lifecycle-policy --repository-name "$name" --lifecycle-policy-text "$policy"
}
```

A brace group is not a subshell. It runs in the consuming shell, so a variable set or a directory entered in one group is still there in the next — which is what lets an orchestrator concatenate the output of several emitters into one stream and have the result behave like one procedure rather than a series of amnesiac fragments. `( … )` does not do this; the distinction is demonstrated in cases 1 and 2 of [`tests/emit-grouping-demo.sh`](../tests/emit-grouping-demo.sh).

Grouping also buys a safety property that has nothing to do with composition. The consuming shell must parse a group to its closing brace before it can execute any of it. So a stream truncated mid-group — a generator that dies partway, a pipe broken over the wire — executes **nothing** from that group. Bare newline-separated commands half-execute instead, running everything up to the cut. For a stream whose commands delete infrastructure, "executes nothing" and "executes the first two thirds" are very different failure modes. Cases 7 and 8.

### A group is an anonymous function

The braces are there for the reader first. A group says: these commands work on one feature or one object, they depend on each other closely, and it makes more sense to run them as a block than one at a time. That is why they are called anonymous functions, and they should be used that way. A reader of the preview sees a procedure made of meaningful blocks, not a flat list of commands to reassemble in their head.

Two consequences follow. First, group by meaning, not by mechanics: one group per feature or object, not one group per script and not one group per command. Second, braces belong to the **emitted** text. Inside the emitting script, ordinary functions do this job (§1.4); an inline group there adds nothing a named function does not do better.

Every emitted group should still read as straightforward procedure. The output of an emitter must work two ways with no change: redirected into a file and run later, or piped directly into `bash`.

### Collecting a group's output

A group has one more property that matters in practice: one redirection after the closing brace collects the output of every command in it. So a stream can label everything a block printed without a pipe on each command:

```sh
log() { while IFS= read -r line; do printf '%s | %s\n' "$1" "$line"; done; }

{
  aws ecr create-repository --repository-name "$name"
  aws ecr put-lifecycle-policy --repository-name "$name" --lifecycle-policy-text "$policy"
} 2>&1 | log ecr
```

`log` is bespoke: define it at the top of the stream, once, only when the stream uses it. Note what the pipe does: a group on the left of a pipe runs in a subshell, so a variable it sets or a directory it enters does not reach the next group ([`tests/emit-group-cases.sh`](../tests/emit-group-cases.sh), case 2). For an anonymous function that is the correct behaviour anyway. A group takes its inputs from the emitted text and leaves its results in files; it does not hand state to its neighbour through the shell.

The same subshell has a sharper consequence: an `exit` inside a piped group ends only the pipe, not the stream. So **a group that carries an `error` check (below) is never piped**. Leave it bare, and let its output go straight to the run sheet's output. (Case 7 of `emit-group-cases.sh` shows the stream carrying on past a piped check.)

### What grouping gives up, and why that is the correct trade

A group does not fail fast. Its exit status is its last command's, and a failure partway through does not stop what follows (cases 3 and 4). `&&`-chaining had that property and grouping surrenders it, so the trade needs defending on two grounds.

**First: blanket `&&`-chaining is `set -e` in disguise.** §1.1 rejects `set -e` not because failing fast is bad but because _implicit_ failing-fast is — it substitutes a blanket mechanism for the author's judgment about which failures actually matter, and it is unreliable in exactly the constructs where you stop thinking about it. Chaining every emitted command with `&&` is the same move in different notation: fail-fast applied uniformly, by reflex, rather than stated where it is meant. A doctrine that rejects `set -e` in §1.1 and then requires a blanket chain in §1.2 is arguing with itself.

**Second, and decisively: the `&&` guarantee does not survive composition.** It holds within a single emitted chain and evaporates at the seam where two emitters are concatenated — which is the exact composition the orchestrator pattern in §1.4 is built on. Concatenate an emitter whose chain fails with a second emitter, and the second one's commands run regardless, and the combined stream exits `0` (cases 9 and 10).

That is the whole case. The property is present where you do not need it, absent where you do, and silently absent — no error, no warning, a clean exit code on a stream that failed. It is worse than not having the guarantee, because you will believe you have it.

### A check only where running the block again would hurt

A group does not stop at a failure inside it, and most of the time that is correct. In the ECR group above, if the first command fails, the second fails too, and loudly: the log shows both. A check on each command would add nothing but noise. And the commands in a phase are meant to be idempotent (§1.11), so `create-repository` failing because the repository already exists is not a problem at all. An exit code can also be lost inside a group, and that is fine: plenty of command-line software is not POSIX-compliant, and some of it returns error codes that mean nothing consistent. Do not build the procedure on them.

So a check goes in the emitted text only in two cases: where **running the block again would be harmful**, or where a failure would leave the **state ambiguous**. Where one is needed, use the `error` function from [`includes/error.sh`](../includes/error.sh): print its definition at the top of the stream (again, only when the stream uses it), stop with the reserved exit code **3** (§1.11), and say what happened in words the operator can act on:

```sh
error() { ret_code=${1}; shift; exec >&2; TZ=UTC printf '[%(%Y-%m-%dT%H:%M:%SZ)T] ' -1; printf 'ERROR: %s\n' "$*"; exit "${ret_code}"; }

{
  pg_dump --format=custom --file="$dump" "$dsn" \
    || error 3 "no dump at $dump; schema legacy NOT dropped — safe to run again"
  psql "$dsn" -c 'DROP SCHEMA legacy CASCADE'
}
```

The second command destroys data, and it is only safe after the first succeeded. Without the check, a failed dump followed by a successful drop is a loss that no amount of running the block again will undo. An `exit` inside a group aborts the whole piped stream, and its status reaches the caller (cases 5 and 6 of `emit-grouping-demo.sh`) — but only when the group itself is not piped to `log` (see above).

This is the opposite of a uniform chain, and that is the point. A reader of the preview sees exactly one check, on exactly the step the author judged dangerous. A check on every line would bury it.

### When a script legitimately needs both archetypes

Some do. [`examples/emit/create-pullthrough-secrets.sh`](../examples/emit/create-pullthrough-secrets.sh) creates Secrets Manager entries — mutating, so it emits — and then resolves the resulting ARNs into a tfvars file, which is read-only against AWS and follows §1.5 instead.

The resolution is **one function per archetype, separately dispatchable, never blended inside a single function**. The file has two entry points with different contracts, each documented as what it is, and the default action when the script is run bare is the emit one — so the preview guarantee is what you get if you do not think about it. Blending them inside one function is how you arrive back at `vpc-nuke.sh`.

## §1.3 — The artifact carries structure, not secrets

The emitted, reviewable, transmittable thing an action script produces carries **command structure and references — never resolved secret values**. A secret is materialised only by the **execution context**, from **its own trusted source**: the shell's environment when execution is local, a secret store when it is remote (§1.8). "A dry run is safe to paste into a ticket" is a pleasant consequence of this rule, not the rule.

The mechanism is deferred expansion. What the reviewer of a preview actually sees is this:

```sh
aws secretsmanager create-secret --name ecr-pullthroughcache/brzl-dev-github \
  --secret-string "{\"username\":\"$GHCR_USERNAME\",\"accessToken\":\"$GHCR_TOKEN\"}"
```

The emitted text contains `"$GHCR_TOKEN"` — the name, single-quoted or escaped past the emitter — and only the shell that finally runs the command expands it. The two sides of `bash gen.sh | bash` are separate processes: a value reaches the consumer through _its_ inherited environment, and a runtime `export` inside the emitting script is never seen downstream. That separation is what makes the preview safe by construction rather than by discipline — the emitter _cannot_ leak a value it never resolves. [`examples/emit/create-pullthrough-secrets.sh`](../examples/emit/create-pullthrough-secrets.sh) and the shared `emit_k8s_secret` helper in [`examples/orchestrate/runlib.sh`](../examples/orchestrate/runlib.sh) are the working forms.

Two supporting rules close the side channels. When a tool must be _handed_ a credential — `git` over HTTPS — use `GIT_ASKPASS` or equivalent, so the value never lands in `argv` (visible to every user via `ps`), in `.git/config`, or in output; scrub remote URLs after. And when a human needs to _inspect_ a secret, print its byte-length and charset class, never the value — enough to catch the classic bugs (an empty secret; a base64 `+/=` value breaking an encoder) without creating a disclosure path.

## §1.4 — The sourceable `main()` pattern

Action scripts are structured so they run directly **or** are `source`d by an orchestrator. The contract is four steps, implemented in [`includes/runlib.sh`](../includes/runlib.sh):

```sh
# 1. Detect sourced-ness in THIS frame, before anything else.
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

source "<path>/includes/runlib.sh"

# 2. All work in named functions, each finished with end_function.
do_the_thing() {
  require_tools aws jq || end_function "$?" 'missing prerequisites'
  # ...
  end_function "$?" 'what just happened'
}

# 3–4. CLI dispatch, only when not sourced; bare run gets the default action.
if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else do_the_thing; fi
fi
```

What it buys is one legible top-level driver sequencing many complex actions, with no copied logic and no loss of the per-script preview guarantee. [`examples/generate/render-recovery-manifest.sh`](../examples/generate/render-recovery-manifest.sh) shows the shape at readable size; [`examples/orchestrate/platform.sh`](../examples/orchestrate/platform.sh) is the claim that it stays legible at 700 lines.

The load-bearing asymmetry is in `end_function`: on failure it **returns when sourced, exits when run directly**. Run standalone, a script fails hard, as it should. Sourced, the same failure comes back to the orchestrator as a return code — and failure _policy_ (abort the run, skip the phase, retry) lives in the one file whose job is sequencing, instead of being scattered as `exit`s through every callee. This is also why §1.1's rejection of `set -e` is a precondition, not a preference: functions called from an orchestrator's conditions are exactly where `set -e` is suspended.

Two details are contractual, not stylistic. Detection — `(return 0 2>/dev/null) && is_sourced=true || is_sourced=false` — must run in the script's **own frame, before anything else**: `return`'s validity is what is being probed, and inside a helper function `return` is always valid, so a helper always answers "sourced". And everything the harness logs goes to **stderr**, because a sourced emit-function's stdout is a command stream an orchestrator may be piping (§1.2) — one stray log line on stdout becomes a command.

The pattern composes with the archetypes rather than replacing them: an emit-style function still prints commands, a generator still prints data. The original reference implementation is [`tests/destroy-tf-modules.sh`](../tests/destroy-tf-modules.sh) — kept as-is, including its own doctrine violation (its `cd "$starting_position"` runs unguarded), which are catalogued in [`examples/README.md`](../examples/README.md) as audit and linter fodder.

## §1.5 — Producing content: stdout is canonical, the file is an argument

Plenty of scripts exist to produce a piece of content: a rendered manifest, a resolved `tfvars` line, a rewritten kubeconfig. The common failure with these isn't in the rendering, it's in the delivery — the script prints the value and a human copies it into the place it belongs. I think of these as paste-back steps, and they are where reproducibility quietly dies: the procedure now has a step that exists only in someone's working memory, doesn't appear in any log, and gets skipped or mangled precisely when the operator is tired or hurried.

The fix is not "write it to a file instead", because then you have two script shapes — one that prints and one that writes — and callers have to know which they're holding. One convention covers both:

- With no file argument, the content goes to stdout. It pipes directly (`bash render.sh | kubectl apply -f -`), through `tee`, or into whatever the caller wants.
- Given a target path, the script _also_ writes the file, backing up an existing target first.
- The announcement (`wrote → <path>`) goes to stderr, so the human sees where the copy landed without it polluting the payload.
- The content still goes to stdout either way. A retained copy is a side effect, not a mode switch; the script behaves identically whether or not you asked for the file.

This is another place the process context matters: stdout belongs to whatever consumes the script, stderr belongs to the human running it, and the file is a courtesy for later. Keeping those three straight is most of the convention. [`includes/runlib.sh`](../includes/runlib.sh) provides `emit_to <content> [target]` so the shape doesn't have to be re-implemented each time, and `write_arns_to_tfvars` in [`examples/emit/create-pullthrough-secrets.sh`](../examples/emit/create-pullthrough-secrets.sh) shows it doing real work — resolving credential ARNs and merging them into a Terraform tfvars file that no operator ever has to paste into again.

## §1.6 — Credentials in both loci

The same script will be run from two credential contexts: a laptop, where AWS access comes from an assumed-role profile (`AWS_PROFILE=…`), and a toolbox or instance, where access comes from the instance role and no profile exists at all. A script that hard-requires `AWS_PROFILE` breaks in the second context for no reason — the `aws` CLI already knows how to find ambient credentials, and the script's insistence adds nothing but a failure mode.

So the rule is: let the tool resolve its own credentials, and _report_ which source is in use rather than gating on it. The `aws_profile_note` helper in [`examples/orchestrate/runlib.sh`](../examples/orchestrate/runlib.sh) is the whole implementation — one line to stderr saying either "profile X" or "no profile, using ambient/instance-role credentials". That's genuinely useful information when an operator is confused about why a call was denied, and it costs nothing.

Two practical notes from being bitten. Read the variable as `${AWS_PROFILE:-}` so the unset case is an ordinary empty string rather than an error under `set -u` — someone will eventually source your script from a shell that has it set. And remember that `sudo` and Ansible both strip the environment by default, so a credential context that existed when the operator typed the command may be gone by the time your script runs; where a tunnel or ProxyCommand needs the variable, re-inject it explicitly rather than assuming it survived.

## §1.7 — Derive account-bearing values; never lean on shell memory

Some values embed an account identity: the state bucket name, the registry host, a role ARN. The tempting way to handle these is an environment variable the operator exports at the start of a session — and the problem is that anything an operator has to remember to export is something an operator will eventually forget to export. I know because I did it: a teardown run against a freshly opened shell, the bucket variable unset, and a `NoSuchBucket` error halfway through a destroy. If I can drop a value between runs, so can anyone who inherits the script.

The rule that came out of it: an account-bearing value is either **derived at runtime from the caller** — `aws sts get-caller-identity` answers "which account am I in" authoritatively, from whatever credentials are actually in force — or **persisted in a gitignored file the tool loads automatically**, the way Terraform picks up `*.auto.tfvars`. Both put the value where the process context can always reach it. What's ruled out is the third option, per-run shell state, because its lifetime is the terminal session and its correctness depends on a human's memory.

[`examples/generate/resolve-ecr-host.sh`](../examples/generate/resolve-ecr-host.sh) is the pattern at its smallest: one STS call, one printf, and the registry host for whatever account the caller's credentials resolve to. Nothing to export, nothing to remember, and it cannot disagree with the credentials in use — which is the property the environment variable never had.

## §1.8 — Why this shape travels

Everything up to here has been about keeping the process contexts straight: the emitter and the consumer are separate processes (§1.2, §1.3), stdout belongs to the consumer and stderr to the human (§1.5), credentials belong to whichever context is executing (§1.6). The payoff of all that bookkeeping is something I didn't fully appreciate until I needed it: if a script's output is a clean stream and its inputs come from env and args rather than a TTY, then the consuming process doesn't have to be on the same machine. The stream pipes across an SSH tunnel or an SSM session, and execution lands on a remote host without the script changing at all.

But what you send down the pipe matters, and there's an order of preference:

1. **Data to a data-consumer** — `render.sh | kubectl apply -f -`, or the same with `ssh toolbox 'kubectl apply -f -'` in the middle. The content never meets a shell parser on the far side, so the whole family of quoting and escaping problems doesn't arise. This is why §1.5 renders data rather than shell where it can; reach for this form first.
2. **Commands to a shell, via stdin** — `gen.sh | bash`, or `gen.sh | ssh toolbox bash`. Fed through stdin, the stream is parsed exactly once, by the shell that executes it — byte-identical to the local pipe. Ordinary quoting in the emitted text is all you need.
3. **Never `ssh toolbox "inline command…"`.** This form makes the local shell build a string and the remote shell parse it _again_. Your quoting wasn't wrong; it just only survives one shell. Now you're escaping for a parse you never see, and any value you interpolated has been resolved into the transmitted string — which also lands it in the remote `argv`, visible to `ps`.

The difference between forms 2 and 3 is the difference between one parse and two, and [`tests/remote-quoting-demo.sh`](../tests/remote-quoting-demo.sh) demonstrates all of it locally — `bash -c "$string"` does to a string exactly what the remote shell does to an inline ssh command, so no host is needed to watch it break. Most of the escaping pain people attribute to "shelling out over SSH" lives entirely in form 3; the emit-to-stdin pattern exists to sidestep it.

Secrets follow the execution locus. Deferred expansion (§1.3) happens wherever the final shell runs, so for remote execution the secret has to live on the remote box, resolved there from its own trusted source — a secret store reached through the instance's own role, not a value piped over from the laptop. In the disaster-recovery exercise that shaped most of this document, the conductor pulled its GitHub token from Secrets Manager via its instance role and used it on-box; no secret ever crossed the wire from my machine.

One honest caveat, because the picture above can sound more fileless than it is. The same rule binds the _driver_, not just the leaf scripts — a bring-up or teardown should be expressible as a flattened command stream piped to a bare shell on the execution box, not a stateful program you copy over and run in place. But Terraform and Ansible are file-based tools: the modules, playbooks, and manifests have to be _present_ on the execution host, so the box still needs the repo. The reconciliation is to separate the two concerns: deliver the repo by a scoped `git clone` (one fine-grained, least-privilege token), and drive the work as a piped stream. [`examples/emit/ship-repo.sh`](../examples/emit/ship-repo.sh) is an earlier version of that delivery step. And the box that receives it all is best kept temporary, single-purpose, and per-account — a disposable conductor with a minimal IAM perimeter, not a long-lived hub — which is [`OPERATIONS.md`](OPERATIONS.md)'s territory.

## §1.9 — Why bash here, and not Ansible

The question deserves a straight answer, because "just use Ansible" is the standard critique of everything in this document, and it's half right.

The case for this shape is partly organisational. Breaking a procedure into small, previewable, single-purpose scripts gives a whole ops team one methodology to work in regardless of seniority. For a junior, the emitted preview is a chance to read and understand exactly what a procedure will do before it runs — not a description of it, the thing itself. For a senior, the same preview is an audit surface: every step of a colleague's change, readable before approval. And it's a path toward actually _developing_ tooling as a team, rather than only consuming whatever the most conventional off-the-shelf thing does.

The case is also about overhead and portability. There's no Python distribution to install and keep consistent across hosts; at most you need a newer bash on the _generator_ box. The bashisms stay local to the generator — the same split as §1.4 — and what travels is a plain list of commands (or data) that almost any shell can run: Bourne, dash, busybox `ash`, zsh. The execution host doesn't even need to be running bash, which is precisely why the remote piping in §1.8 works without assuming anything about the far side.

And here is the honest boundary. Ansible — or any structured runner — earns its overhead when you need structured module transport instead of shell text, real idempotency, secret injection that never touches `argv`, fact-gathering and inventory across a fleet, or to assume no usable shell at all. Those are real needs and I use it for them. The bash patterns own the large middle ground where transparency, low overhead, and shell-portability win — where a human being able to read the procedure before it runs is worth more than the framework. When a procedure crosses that line, move it; the mistake is starting on the far side for jobs that never needed it.

## §1.10 — A script's claims are part of its contract

_Reserved._ The seed document's §1.10 (no masked failures; a phase's claim must match its body) has not been ported yet. The number is kept so that cross-references from other projects still resolve.

## §1.11 — The driver: run sheets, phases you can run again, and no prompts

§1.4 gave the driver its calling surface: it sources action scripts and sequences their functions. This section gives it its execution model. A driver does not do the work, and it never prompts. **It is an emit script itself**: its output is a procedure made of one group per **phase**. A phase's own commands depend on what earlier phases produced, so the driver cannot print them all up front; instead each phase group makes them at the moment it runs, and records them:

```sh
{ # phase 10-substrate (local)
  bash driver/phases/10-substrate.sh local > var/run/local/202610091430/10-substrate.sh
  bash var/run/local/202610091430/10-substrate.sh < /dev/null; printf '%s\n' "$?" > var/run/local/202610091430/10-substrate.rc
  bash driver/driver.sh local check 10-substrate
}
```

Each phase group does three things, in order:

1. **Record.** Run the phase's emit function and write its stream to a run sheet file, `var/run/<env>/<YYYYmmddHHMM>/<NN>-<phase>.sh`, before anything runs. The top of the file records the resolved inputs (§1.12).
2. **Run.** Run the file, not a pipe, and write its exit status beside it as `<NN>-<phase>.rc`.
3. **Check.** Run the phase's check: a read-only generator (§1.2) that asks the system whether the phase's result is there — the repository exists, the pods are ready, the secret reads back. If it passes, it writes `<NN>-<phase>.ok`.

**Approval is running the output.** As with any emit script, the preview is the review and piping it is the decision (§1.2). There are two ways to drive:

- **Careful:** `bash driver.sh <env> next` emits only the next phase without an `.ok`. Read it; to see the phase's actual commands, run its emitter on its own (`bash driver/phases/10-substrate.sh local`). Then pipe the phase to `bash`, and repeat.
- **Fast:** `bash driver.sh <env> up | bash` runs every remaining phase in one go.

The run sheet is the exact record of what ran. The run directory is gitignored, and safe to keep, because the stream holds secrets only as references (§1.3).

**Run sheets take stdin from `/dev/null`.** The driver's procedure arrives on stdin (`driver.sh <env> up | bash`). A command inside a run sheet that reads stdin without a pipe or a heredoc of its own — `docker exec -i`, `kubectl exec -i`, `cat`, `ssh` — inherits that stdin and swallows the rest of the procedure. The stream then ends silently: the later phases never run, and nothing reports it. So the driver runs each run sheet, each check and each remote-execution helper with `< /dev/null`. Data reaches a command only through a pipe or a heredoc, and a generator never passes `-i` to `docker exec` or `kubectl exec` without one. The instrument is a test whose fake phases read stdin: a driver that forgets the redirect fails it ([`barzel-cluster`](https://github.com/ryderdain/barzel-cluster), `driver/tests/driver-cases.sh`).

**Outputs pass between phases as files.** A phase that produces a value a later phase needs (a digest, an address, a kubeconfig) writes it into the run directory. The later phase reads the file. Nothing passes through shell memory or a paste-back step (§1.5, §1.7).

**The exit code is not the verdict.** A run sheet's exit status is its last command's (§1.2), and command-line tools do not report failure consistently. So the `.rc` file records only two facts: the run sheet ran to its end, or an `error` check stopped it on purpose. Exit code **3** is reserved for that deliberate stop: a `.rc` of 3 means "read the `ERROR:` line; do not simply run it again". Whether the phase did its job is the check's answer, not the exit code's. The check's result is written beside the run sheet as `<NN>-<phase>.ok`.

**Resume is a property of the run directory.** The driver starts at the first phase with no `.ok` file. It emits that phase again before it runs it, because the inputs may have changed. No trap or state machine is needed. A phase whose check keeps failing stops the driver and goes to the operator with its run sheet; running it again by reflex is useless.

**Every phase must be safe to run again.** This is the rule that makes resume work, and it is not optional. A phase can stop at any line: a failed step, a lost connection, a killed pod. When it runs again from the top, the steps that already succeeded must succeed again with no change. So use the converging forms: `kubectl apply`, `helm upgrade --install`, `tofu apply` from a saved plan. A create that fails because its object already exists is not a problem; let it fail visibly in the log. A block that is not safe to run again gets an `error 3` check on the dangerous step (§1.2), in the emitted text where the reader can see it. A missing `.ok` then always means the same thing: the phase may run again.

**The approval rule is a rule about which way you drive.** A phase whose effect leaves the driver's own machine, or that costs money — a push to a registry, a `git push` or a commit, a change to a cloud account — is driven the careful way, one reviewed phase at a time. The fast way is only for phases whose effects stay local: a local cluster, a local image rebuild, a rendered file. Approving one phase never approves the next.

**Remote execution keeps the same shape.** When the driver sends a phase to another host, it copies the run sheet there, verifies the copy, and runs it detached. The remote side writes the `.rc` file when the run sheet ends. The driver follows the output and polls for the `.rc`; a dropped connection does not kill the phase, and the driver can attach again. The driver collects the remote `.rc` into its own run directory, runs the check, and writes the `.ok`. Its copies are the record.

## §1.12 — Environment definitions: one file of plain values

A driver needs values that differ from one environment to the next: a substrate, a registry host, an image digest. §1.7 rules out the per-run export an operator must remember. The other half of the answer is the **environment definition**: one committed file per environment, a plain list of `NAME=value` lines and nothing else.

```sh
# env/local.env
BRZL_SUBSTRATE=k3d
BRZL_REGISTRY_HOST=registry.localhost:5000
BRZL_K3D_AGENTS=0
```

Three rules make it work:

- **The file holds defaults, and an exported value wins.** An operator can try a one-off value without an edit: `BRZL_K3D_AGENTS=2 bash driver.sh local up | bash`. The override is announced on stderr, and the driver records the resolved values at the top of each run sheet, so it is always on record.
- **Never turn these values into flags.** A flag for each value grows without limit, and it splits one question ("what is this environment?") across every call site. The file is the single answer.
- **No secrets.** An environment definition is committed and reviewed. Secrets arrive as environment variables from their own source and stay references in emitted text (§1.3).

`load_env_definition` in [`includes/runlib.sh`](../includes/runlib.sh) implements the precedence and the announcement, and `env_definition_record` prints the resolved values for a run sheet. Both are demonstrated in [`tests/env-definition-cases.sh`](../tests/env-definition-cases.sh).
