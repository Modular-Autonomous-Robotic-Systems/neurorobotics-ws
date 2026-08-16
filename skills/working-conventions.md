- Match surrounding code style; keep changes minimal and scoped.
- Commit/push only when explicitly asked; branch off `master` for PRs.
- When a fix depends on a decision only the user can make (e.g. which UE version to
  target), surface the tradeoff and ask rather than guessing.
- **Document every `djinn` workflow.** Whenever you add or change a `djinn` workflow (any `djinn <verb> <subject>`), record it in [`context/djinn-workflows.md`](../context/djinn-workflows.md) with its invocation, call chain (helper functions + scripts), side effects (containers/images/files), expected outcome, and a validation/test strategy — the information needed to author its automated test later. This is mandatory: tests cannot run in the dev container and are authored from this catalogue.
