# Skills Index

Version-controlled home for the AI skills authored for the Neurorobotics Workspace (`NRT_WS`). The canonical `SKILL.md` (and any reference files) for each skill live **here**, under git, so they are shared, portable, and survive container rebuilds. Each skill is then **symlinked** into `.claude/skills/` so Claude Code discovers it.

## Layout & symlink convention

- Canonical skill: `skills/<skill-name>/SKILL.md`.
- Discovery symlink: `.claude/skills/<skill-name>` → `/ws/skills/<skill-name>`.

> **Use an absolute symlink target (`/ws/skills/...`).** In this container `.claude` is bind-mounted at **both** `/ws/.claude` and `/root/.claude` (`HOME=/root`, same inode). Claude Code reads personal skills from `~/.claude/skills` = `/root/.claude/skills`; a *relative* symlink there would resolve to `/root/skills/...` (which does not exist), so the target must be absolute. Because `.claude` is git-ignored (it also holds credentials/sessions), the symlink itself is a container-local artifact — only this `skills/` tree is committed.

Recreate the symlink after a fresh checkout / container reset with:

```
ln -s /ws/skills/<skill-name> /ws/.claude/skills/<skill-name>
```

## Skills

| Skill | Purpose |
|-------|---------|
| [nrt-RandD-workflow](nrt-RandD-workflow/SKILL.md) | The R&D method for hardware and software work in this workspace — investigate → plan → validate → implement, optimizing for the simplest Occam's-razor solution grounded in `context/`, `plans/`, code, and literature. Referenced by `CLAUDE.md §4`; user-scope, so it loads in every session under `$NRT_WS`. |

## Maintenance

New skills are added here (canonical) and symlinked into `.claude/skills/`. Add a row above for each. Skills specific to a submodule may instead live in that submodule's own `skills/` + `.claude/skills/`.
