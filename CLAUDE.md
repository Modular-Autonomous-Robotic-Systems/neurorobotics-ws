# Claude Directives — Neurorobotics Workspace (`NRT_WS`)

Project-specific instructions for Claude Code when working in this repository.

## 1. Context system (READ FIRST, every task)

This repo maintains a durable context store under [`context/`](context/) to minimise
token usage across sessions.

- **`context/README.md` is the entry point.** At the start of any non-trivial task,
  read it first and use its index table to decide which larger context file(s) to open.
  Do **not** blindly scan the whole repo when a context file already covers the topic.
- **Always update the context after doing work.** Whenever a task uncovers non-obvious,
  reusable knowledge — a build/call chain, a gotcha, a fix, a version constraint, an
  interface — write or update the relevant file in `context/` and add/refresh its row in
  `context/README.md`. The goal is that a future session can answer from `context/`
  instead of re-deriving from source.
- Keep context **accurate and current**. Correct or delete stale entries; note dates for
  time-sensitive facts (convert relative dates to absolute).
- Prefer one focused file per topic. Link between context files with relative markdown links.

## 2. Repo orientation

- `djinn` (repo root) is the primary workflow CLI — see [`context/djinn-cli.md`](context/djinn-cli.md).
  Requires `$NRT_WS` set to the workspace root.
- `ARCHITECTURE.md` describes the layered Docker image hierarchy, ROS, and SITL design.
- `sitl_ws/src/ue5/AirSim` is a git submodule (Cosys-AirSim). Docker builds clone **upstream**
  Cosys-AirSim fresh — so fixes belong Dockerfile-side, not in the local submodule's
  `build.sh`. See [`context/airsim-docker-build.md`](context/airsim-docker-build.md).
- The SITL workspaces (`ardu_ws/`, `sitl_ws/`) are mounted under `/ws`, not baked into the
  image, and built at container-start. See [`context/sitl-workspace-migration.md`](context/sitl-workspace-migration.md)
  and the workflow catalogue [`context/djinn-workflows.md`](context/djinn-workflows.md).

## 3. Working conventions

- Match surrounding code style; keep changes minimal and scoped.
- Commit/push only when explicitly asked; branch off `master` for PRs.
- When a fix depends on a decision only the user can make (e.g. which UE version to
  target), surface the tradeoff and ask rather than guessing.
- **Document every `djinn` workflow.** Whenever you add or change a `djinn` workflow (any `djinn <verb> <subject>`), record it in [`context/djinn-workflows.md`](context/djinn-workflows.md) with its invocation, call chain (helper functions + scripts), side effects (containers/images/files), expected outcome, and a validation/test strategy — the information needed to author its automated test later. This is mandatory: tests cannot run in the dev container and are authored from this catalogue.

## 4. Development workflow (MANDATORY)

- Every change — feature, fix, or doc — follows **investigate → plan → validate → implement**, grounded in code, `context/`, `plans/`, and (when needed) literature and provided artefacts. Optimize for the **simplest Occam's-razor solution** that is minimal-diff, consistent with current architecture, and future-proof. Load the **`nrt-RandD-workflow`** skill for the full method; it applies wherever Claude is invoked under `$NRT_WS`.
- **Orient first, README-first (at task start and after any context compaction).** Before reading source, locate and read the project root `README.md`, `ARCHITECTURE.md`, and the `README.md` index of `context/` and `plans/` — at the invocation root and in every subdirectory/submodule that has them — to load high-level context and change history. Enter `context/`/`plans/` through their `README.md` index. Prefer `context/`/`plans/` evidence over re-deriving from source. When invoked at a submodule root, that submodule's `context/`/`plans/` govern.
- **Investigate to saturation:** sweep for every consumer of what changes; verify claims against the tree; stop when no new question adds information. **Flag any contradiction immediately**, before spending more tokens.
- **Plan into `plans/<feature>.md`** (committed history): motivation → high-level → detail; backwards-compatibility impact is mandatory per change; detailed enough that a human or AI could execute without further investigation. **Always stop after the plan for review/approval before implementing.**
- **After approval:** implement in phases, verifying each; **re-investigate to refresh context before writing docs**; then update `context/` and `plans/` per §1 and finish the plan as a clean change-record.

## 5. File formatting — no hard-wrapping (MANDATORY)

- When writing or editing ANY file (Markdown context files, notes, docs, configs, prose of any kind), write each paragraph, sentence, list item, or table row as ONE COMPLETE LINE. Do NOT insert manual/hard line breaks to wrap prose at ~78/80/90 columns. Let the line run to its natural end; the viewer/editor is responsible for soft-wrapping on display.
- Rationale: hard-wrapped prose renders as many short (~80-char) lines, which reads as if content was truncated around 90 characters. Full, unwrapped lines guarantee no truncation and keep paragraphs intact and greppable.
- This applies to files Claude authors in this workspace. It does not require re-flowing pre-existing third-party files that are already wrapped, unless the task is specifically about that file.

## 6. Code change discipline

- Evaluate options before making a change, not after, with the goal of writing as little code as possible while preserving backwards compatibility absolutely.
- No change may alter the behaviour of an existing caller that did not ask for the change.
- Before editing anything in a shared module, enumerate its callers across every configuration, since shared functions may be consumed by multiple tasks and an in-place edit silently changes all of them, invalidating comparison against in-flight and historical runs.
- Where an optional argument can carry the new behaviour without altering the method's existing logic, prefer an optional argument whose default reproduces the old behaviour exactly, set explicitly only in the calling configuration.
- Only where no optional argument can preserve the old behaviour should a v2 of the method be created, with the calling configuration repointed at it and the original left untouched.
- Record any defect left standing in the untouched original or the unset default, so that other implementations may opt in deliberately.
- Add as little comments as possible when not writing function description. Comments should only be added when reading the code does not sufficiently provide all context required to understand the larger context
- Comments should be as succinct as possible. Function description comments should only describe the function of the method and any additional information regarding larger code context is to be left to the reader to infer from reading the code itself and not comments.

## 7. Writing style (MANDATORY)

- Code blocks, tables, and shell commands are exempt from the no-hard-wrap rule in §5 and follow their own formatting conventions.
- Do not use the hyphen, the semicolon, or the colon to break sentences. Only the comma may break a sentence. These three symbols may appear solely in contexts where they are not sentence breaks, for example code, file paths, list markers, table syntax, ratios, and compound words.
- Do not italicise or bold text unless explicitly asked to.
- Ensure all writing follows a high level coherent structure.
- Ensure all writing is grounded in fact and evidence, from papers, the codebase, the internet, or the context files, never from unverified recall.
- When writing documents, ensure a flow to the document while slowly building up to the ideas to be delivered.
- Do not use overtly long or short sentences.
- Write in a formal and academic register with a succinct and regal flair.
- Mimic the writing style of the user's prompts.

## 8. C++ naming conventions (MANDATORY)

All C++ code in this workspace must follow these naming conventions.

- Use camelCase as the general naming convention.
- All methods must start with a title case name, for example `void ExampleMethod()`.
- All member variables must be prefixed with `m` to denote they are member variables, for example `mCounter`.
- All private member variables must be prefixed with `mp` to denote they are private member variables, for example `mpInternalState`.
- All vector or array type member variables must be prefixed with `mv`, for example `mvPoints`. Private vector or array member variables must be prefixed with `mvp`, for example `mvpInternalPoints`. Method-local vector or array variables must be prefixed with `v`, for example `vResults`.
- Mutex member variables must be prefixed with `mMtx`, for example `mMtxDataGuard`. Private mutex member variables must be prefixed with `mpMtx`, for example `mpMtxInternalLock`.
