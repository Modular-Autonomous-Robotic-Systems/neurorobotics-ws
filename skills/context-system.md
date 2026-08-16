This repo maintains a durable context store under [`context/`](../context/) to minimise
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
- **Context files are INCREMENTAL and append-only in spirit (MANDATORY).** A context file is a cumulative knowledge base, not a document to be redrafted. When updating one, make only two kinds of change, namely corrections to what is now known to be wrong, and additions of newly discovered information. Every other piece of information already in the file must survive the edit verbatim or in substance. Never rewrite a context file wholesale, never summarise or compress existing sections to make room, and never drop background theory, derivations, worked numerical examples, code references or caveats merely because they are not relevant to the current task. The value of these files is precisely the accumulated detail that no single session would regenerate.
- **Corrections to context files follow §2, applied in place given the incremental structure above.** Every substantive line must survive an edit unless §2 is the reason it changed.
- **Verify preservation before finishing.** After editing a context file, diff it against the previous version and confirm that every substantive line that disappeared was deliberately corrected or removed rather than accidentally dropped.
- Prefer one focused file per topic. Link between context files with relative markdown links.
