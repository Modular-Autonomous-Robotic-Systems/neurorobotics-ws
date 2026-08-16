---
name: nrt-RandD-workflow
description: The research-and-development workflow for the neurorobotics toolkit (NRT_WS) — an investigate → plan → validate → implement method for ANY hardware or software code/documentation change under $NRT_WS. Optimizes for the simplest Occam's-razor solution that is minimal-diff, consistent with current architecture, and future-proof, grounded in code, context/, plans/, and (when needed) literature and provided artefacts. Load before starting any non-trivial task, and for small tasks whenever an inline mini-plan cannot capture the full problem.
---

# NRT R&D Workflow

This is how R&D is done in this workspace — for hardware and software alike. Every change, from a one-line fix to an architectural feature, is produced by the same disciplined loop so the result is grounded in the current system and in literature, and is the **simplest possible solution** consistent with the architecture. Think more to change less.

## Objective function (why this exists)

- **Occam's razor.** Prefer the minimal-diff, most elegant solution that solves the problem and stays consistent with the existing architecture and future direction. Reject cleverness that adds surface area.
- **Grounded, never guessed.** Anchor every claim to a `file:line`, a `context/` entry, or a cited source. Verify structural claims against the actual tree before relying on them.
- **Backwards compatibility is inviolable.** No existing feature or workflow may break. Identify every consumer of what you touch before you touch it.
- **`context/` and `plans/` are the project's digital twin.** They are the accumulated knowledge base and change ledger. Reading them first saves tokens; keeping them current is a precondition for the next task, not an afterthought.

## The loop

### Phase 0 · Orient (do this at task start, and again after any context compaction)

Before reading source, load the high-level picture — cheaply, README-first, and across the whole tree available at the invocation point:

1. Read the **project root `README.md`**, **`ARCHITECTURE.md`**, and the **`README.md` index of `context/` and `plans/`** — at the directory where you were invoked and all nested directories. Traverse the directory tree to find all `README.md`, `ARCHITECTURE.md` and the `context/` and `plan/` directories as instructed in the next step.
2. Do the same in **every subdirectory and submodule** under that root that has them. Submodules may carry their own `README.md`, `ARCHITECTURE.md`, `context/`, and `plans/`; assembling all of them gives the full project context and change history. **When invoked at a submodule root, that submodule's `context/` and `plans/` govern.**
3. Enter `context/` and `plans/` **through their `README.md` index tables** — open only the specific files the index points to for this task. Do not blind-scan the repo when a context or plan file already covers the topic.

Orientation output: a mental map of the relevant architecture, the prior decisions/history bearing on this task, and which source files are load-bearing.

### Phase 1 · Investigate (to information saturation)

- **Context first, source second.** Extract everything the `context/` and `plans/` files already answer before re-deriving from source. Re-derive only what is missing or stale.
- **Breadth-first blast-radius sweep.** For anything you will change — a symbol, a path, an interface, a script — grep for **every** consumer across the tree, and read each. Use `git log`/`git diff` to understand how the current state came to be.
- **Verify, don't assume.** Confirm each structural claim against the tree (does the path exist? where does this variable resolve? what packages does this dir actually contain?). Never assert a path without checking it.
- **Literature survey — conditional.** Only when `context/`/`plans/` and the codebase do not yield enough to ground the plan, or when the task involves state-of-the-art research, algorithmic/mathematical questions, current hardware/software trends, or genuine ambiguity. The goal is to import missing context from outside the project.
- **Artefact analysis — conditional.** Only when concrete artefacts are provided (logs, images, videos, specific code/config files, datasheets). When a task names a specific file/script, treat it as an artefact to analyse.
- **Stop rule = saturation.** Stop when no additional question would materially increase the information you hold about the problem. Maximize information gathered per token spent.
- **Flag contradictions immediately.** The moment an observation contradicts how something was described (e.g. "this was already fixed" but the code shows otherwise), surface it at once — before spending further tokens investigating around it.

### Phase 2 · Plan (write it down)

Write the plan to **`plans/<feature>.md`** (a committed file — the change ledger; use the submodule's `plans/` when working there). Structure it motivation-first, then top-down:

1. **Motivation** — the problem and why it matters.
2. **High-level design** — the architectural idea and the key insight, before any detail.
3. **Detail** — the concrete changes, drilling down from the high-level. For each change include **only the headings that apply**: code snippet, mathematical background, intuition, need, significance. **Backwards-compatibility impact is mandatory on every change.**
4. The plan must **explain the why / how / what** — externalizing the mental map so a reader understands the reasoning, the document's structure, and every choice.

A change is well-specified when a human *or* an AI could execute it **without any further codebase investigation** — all needed context is in the plan.

### Phase 3 · Validate (repeat until a pass finds nothing new)

- Re-investigate the codebase to confirm every planned change is correct, that backwards compatibility holds, and that no existing feature breaks.
- Sanity-check any change claimed to be already done; report discrepancies faithfully.
- Fold newly-discovered detail back into the plan. **Repeat validation passes until a pass surfaces nothing new.**

### Phase 4 · Approval gate

**Always stop after the plan and wait for review and feedback.** Do not implement until approved (silence, when the reviewer has said so, counts as approval). Feedback loops back into the plan; re-validate as needed.

### Phase 5 · Implement (phased, verified)

- Apply the changes in a sensible order, **verifying each step** (syntax checks, targeted greps, re-reading the edited region's consumers).
- **Re-investigate to refresh context before writing documentation** — docs must reflect the actual post-change tree, not the pre-implementation plan.

### Phase 6 · Capture (update the digital twin)

- Update **`context/`** (AI-facing, maximal detail — build chains, gotchas, interfaces) and **user docs** (`ARCHITECTURE.md`, `README.md` — concise, grounded, referenced) per `CLAUDE.md §1`.
- Finish the `plans/<feature>.md` as a **clean change-record**, following the cleanup rules below.
- Refresh the relevant `README.md` index rows for anything added.

#### Plan cleanup after implementation — subtract process, never substance

The finished plan is the permanent, self-contained changelog of the work. Cleanup is a **subtraction of review and design-iteration artefacts only**. It is emphatically **not** a summarisation pass, and compressing a plan into a short summary destroys the very record the ledger exists to keep.

**Remove**, because it documents how the plan was produced rather than what was built.

- Revision markers, dates of revision, `Status: PLAN — awaiting review`, and any wording that addresses a reviewer in the second person.
- References to feedback items, review rounds, questions asked and answered, and options that were considered and rejected in review. A rejected option survives only if a future reader would otherwise re-propose it, and then it belongs in the decisions section as a settled decision with its reason.
- Sections that exist to obtain approval, for example a phased breakdown offered so a reviewer could approve it phase by phase, once every phase has landed. Collapse those into the change they describe.
- Corrections of the plan's own earlier claims. State the final, correct reading directly, and record the misreading only where it is itself a trap worth warning about, in which case it belongs in `context/`.
- Uncertainty that has since been resolved by implementation, for example "to be confirmed" or "assuming this holds".

**Retain in full**, because it is the substance of the change.

- Every code snippet for every change, at the same level of detail the plan carried before implementation, updated to match what was actually written.
- Every design decision and the reasoning behind it, including the alternatives that were rejected on technical grounds and why, so that the decision is not silently reopened later.
- The motivation, the defects or requirements that forced the design, and the evidence that established them, with `file:line` anchors.
- The backwards-compatibility analysis of every change, and the blast-radius table of consumers.
- The validation strategy, annotated with what was actually run and what remains outstanding, since checks that cannot run in the dev container are executed later against a running stack.
- Anything deliberately not done, with the reason, so a later reader does not mistake an omission for an oversight.

The test to apply is simple. A reader who has never seen the conversation must be able to reconstruct what changed, why each change was made that way, and what was ruled out, from the plan alone. If cleanup has made the plan shorter but that reader can no longer answer one of those three questions, the cleanup went too far.

## Inline mini-mode (small changes only)

For a change of at most a few lines across one or two files, the ritual may run inline: a brief written mini-plan (motivation + the change + backwards-compat note) in the response instead of a `plans/` file, still preceded by Phase 0/1 orientation and followed by context updates if anything non-obvious was learned. **Escalate to a full `plans/` document the moment inline prose cannot capture the full problem** — when the blast radius, ambiguity, or number of touched files makes inline detail insufficient.

## Self-improvement

This workspace's owner works this way for all R&D and expects the method to be **learned and sharpened over interactions**. When you observe a working-style preference, a recurring correction, or a calibration of the trivial-vs-full threshold (there is deliberately no fixed size/risk threshold — it is learned as `context/` grows), note it and propose an update to this skill and/or `CLAUDE.md`. New anti-patterns to forbid will be added here as they are identified.
