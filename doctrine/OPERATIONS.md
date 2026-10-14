# Infrastructure Operations — patterns & operating model

This sits on top of [`STYLE.md`](STYLE.md): most of what's here is *enforced by* scripts shaped the way that document describes, and §1.8's remote-execution machinery is what makes the operating model below practical rather than aspirational. The rules were asserted, and mostly learned, while driving a full disaster-recovery exercise — Terraform → Ansible → ArgoCD → CloudNativePG, torn down and restored from the object store alone. The model-consumable form of these rules lives in [`skills/bash-ops/SKILL.md`](../skills/bash-ops/SKILL.md), the operational extension of the core [`skills/bash-doctrine/SKILL.md`](../skills/bash-doctrine/SKILL.md).

The concrete incidents behind the abstractions are collected in the [appendix](#appendix--the-concrete-moments-these-came-from); where a rule seems oddly specific, the appendix is usually why.

> **Status:** ported from the original doctrine seed; needs the same voice review as STYLE.md §1.1–§1.4.

---

## §2.1 — Operations run from the toolbox, not the laptop

From pre-flight onward, the standard execution locus for infrastructure and cluster operations is an **operator toolbox** — a pinned toolchain image, run either in-cluster once a cluster exists, or on a one-off, disposable EC2 instance reached via SSM with no inbound SSH. Three goals justify the ceremony:

1. **Identical toolchain across all operators.** Everyone manages the infrastructure with the same tool versions; bootstrap, recovery, and deployment behave the same for everyone, and errors reproduce instead of dissolving into "works on my machine".
2. **Operator entry is IAM-gateable.** Authorization to *operate* is constrained to the toolbox itself, not scattered across laptops.
3. **All activity is auditable.** Toolbox operations, with the identity that triggered them, can be logged and reviewed later.

Two realization details learned the hard way: match the instance architecture to the toolchain image (an arm64 image needs a Graviton `t4g.*`, not the reflexive `t2.*`), and make the toolbox self-contained — able to install or build its own toolchain — so it can bootstrap the very stack (say, the container registry) it would otherwise depend on.

## §2.2 — Self-contained, disposable layers

A control resource like the conductor should be its own Terraform layer, owning everything it needs — VPC, subnet, IGW, security group, IAM — and reading no other layer's state, so it can be applied and destroyed at any time without touching anything else. DRY is deliberately relaxed here: a throwaway control box duplicating a little networking code is a fair price for full independence. Reach it via SSM Session Manager, from a public subnet with an egress-only security group — no NAT, no VPC endpoints; the agent dials out, the operator dials in, nothing listens.

## §2.3 — Terraform / GitOps division of labor

**Terraform scaffolds infrastructure; ArgoCD configures Kubernetes; Ansible bootstraps host and app config.** Blurring these is how you end up with two tools fighting over one resource.

- Layered Terraform (per Lee Briggs), strict dev/prod separation, remote state in S3 with a DynamoDB lock.
- GitOps through a single `ApplicationSet` rather than an app-of-apps root, with sync waves so operators land before the applications that need them.
- **Saved-plan workflow, always:** `tofu plan -out=FILE`, review, `tofu apply FILE`. Never `-auto-approve` — it re-plans fresh and can drift from what was reviewed, which defeats the reason for reviewing.
- Ask before every billable or mutating step, per step. Approval in one context does not carry forward to the next.

The orchestrator that drives all of this in practice is [`examples/orchestrate/platform.sh`](../examples/orchestrate/platform.sh) — read-only phases run freely, every mutating phase prints what it will do and asks first.

## §2.4 — Identity, secrets, access

- **Authenticate with the instance profile.** Don't mint a second IAM user for what a role can already do — CNPG/Barman reaching S3 via `inheritFromIAMRole` is the model case.
- **Secrets Manager for secrets, Parameter Store for non-secret config.** Don't conflate them; some services (ECR pull-through) will force the distinction on you anyway.
- **Scope credentials to their job — which is not the same as one token per call.** A single fine-grained token scoped to exactly the jobs at hand is correct and preferable: one GitHub PAT carrying both `read:packages` and repo-read serves the registry cache and the clone. The classic 403 in the appendix came from an *under-scoped* token, not a multi-purpose one; the fix was scoping one token to both needs, not splitting it in two.
- **Node access via SSH-over-SSM** — instance-id target, ProxyCommand tunnel, no inbound `:22`, no public API exposure beyond a tight admin `/32`. [`examples/generate/admin-ip-check.sh`](../examples/generate/admin-ip-check.sh) is the drift check for that `/32`.

## §2.5 — Cost posture

- Spot instances while iterating, on-demand for anything demonstrated to others — a `capacity_type` toggle, which earns its keep the first time spot reclamation hits under regional pressure.
- Managed NAT for a PoC, as a documented trade-off, not a default.
- Destroy compute between sessions; prove the same-session up/down and the automated reverse-order destroy before calling the work delivered.

## §2.6 — Disaster recovery, and the ordering that matters

- **Recover before GitOps adopts.** Bring the database operator up standalone and run the restore *before* the ApplicationSet would `initdb` an empty database. CNPG treats `spec.bootstrap` as immutable after creation, so the later-synced manifest shows OutOfSync but does not wipe recovered data — the ordering is what protects you.
- **A backup that hasn't been restore-tested is a hope, not a backup.** Prove it with an exact row-count acceptance target, on a freshly rebuilt stack, from the object store alone.
- **A standalone path inherits GitOps's setup responsibilities.** The drill bypassed the wave-0 storage app, so the recovery cluster's PVCs would have hung Pending forever — the operator phase had to install the CSI driver and StorageClass itself. Bypassing GitOps means doing GitOps's chores.

## §2.7 — Teardown discipline: the orphans `tofu destroy` never sees

`tofu destroy` is necessary and not sufficient. A real teardown runs in reverse dependency order — apply-role work first, then admin for the trust anchor and state, since you're deleting the role you're standing on — plus an explicit leak sweep for resources Terraform never created and can't see:

- CSI-dynamically-provisioned EBS volumes (the PVCs), orphaned when nodes die.
- ECR pull-through *cache* repositories, auto-created on first pull, in no layer's state.
- Script-created Secrets Manager entries, which survive the layer destroy by design.

And the guards that block a clean destroy are features, not obstacles: ECR repos aren't `force_delete` (empty them first); the state bucket carries `prevent_destroy` (flip it, destroy, restore the guard in committed code); KMS CMKs enter a seven-day-minimum pending-deletion window and should be documented as "scheduled", not "gone".

Standing leak-watch list: NAT gateways, unassociated EIPs, orphaned EBS, LoadBalancer Services, the state bucket and lock, and the three orphan classes above.

## §2.8 — Supply chain (noted, to build out)

- Scan stored images — ECR enhanced scanning / Inspector, or Trivy in CI — with a documented fail-on-critical gate; Harbor with its built-in Trivy is the production-registry recommendation.
- **Centralize the scanning regime, then distribute by purpose.** The reason to put a registry/cache hub in one account is not storage efficiency — it's a single vulnerability-scanning gate over everything the fleet pulls. Keep the cross-account sharing opt-in and least-privilege (selected consumer accounts, scoped resource policies, per-purpose CMKs, prod material never flowing into non-prod), and record the trust direction as a bootstrap-time decision: it trades blast radius for the gate.
- Distribute with both ECR modes, split by purpose: **pull** (a pull-through cache pointed at the hub) for the normal course, so downstream stays selective about versions and cadence; **push** (registry replication from a scanned `release`/`hotfix` prefix) for security patches only, so no spoke lags on a fix. The honest limit: replication delivers the artifact; *adoption* still needs a deploy bump when repos are immutable and digest-pinned.

---

## Appendix — the concrete moments these came from

- **GHCR PAT 403 on clone** → the token was under-scoped (`read:packages` only, used to clone), not "the wrong token". The durable fix is one fine-grained PAT scoped to both jobs (§2.4). The workaround at the time — shipping the tree through the state bucket, no GitHub credential at all — is [`examples/emit/ship-repo.sh`](../examples/emit/ship-repo.sh), since superseded by the scoped clone (STYLE.md §1.8).
- **`helm --wait` false-negative on CRDs** → wait on `kubectl wait --for=condition=Available`, not the chart, when CRDs lack `observedGeneration`.
- **Dex `$VAR` not expanded in `staticClients[].secret`** → know which fields your tool templates; `secretEnv:` vs `$VAR` are different mechanisms.
- **Broken multi-arch push (arm64 child manifests 404)** → build from source and import natively rather than trusting the manifest list.
- **`RepositoryNotEmpty` and bootstrap `prevent_destroy` at teardown** → the guards are real; plan the teardown around them (§2.7).
- **Three orphaned gp3 volumes and ECR cache repos after a clean `tofu destroy`** → the leak sweep is not optional (§2.7).
