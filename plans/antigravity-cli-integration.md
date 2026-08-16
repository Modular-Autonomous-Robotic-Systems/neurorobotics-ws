# Antigravity CLI integration, Gemini CLI removal, unified AI directives, and Neovim toolchain parity

## 1. Motivation

The dev IDE stack installs two agentic coding CLIs, Claude Code and Gemini CLI, wires both into `agentic.nvim`'s ACP provider list, and persists their login state across container recreation through host bind mounts. Google retired Gemini CLI for free and consumer tiers on 2026-06-18 and ships Antigravity CLI, binary `agy`, as its replacement, sharing the agent harness of the Antigravity 2.0 desktop application. `djinn:112` already carries the acknowledgement, `# TODO gemini-cli is DEPRECATED need to replace with agy`. This plan replaces the one with the other rather than running both.

Three further problems surfaced during investigation, none of which was the task as first posed, and all of which are defects in the tree today.

The first concerns directives. The rules that govern how an agent works here live in `CLAUDE.md`, and until this plan only Claude Code reliably read current content there. `GEMINI.md` at the repository root was a divergent copy dated 2025-12-14, 3668 bytes against `CLAUDE.md`'s 11082, describing a tree that no longer exists and naming `nvim-gemini-companion/`, `ext/ardupilot` and `envs/` as current, none of which remain. Duplicating a directive file guarantees this outcome, and the goal stated for this revision goes further than fixing the one stale copy, namely that the setup must be **reproducible for every user of the workspace**, automated by `djinn` rather than performed by hand once, and must hold not only at the workspace root but at every submodule root that carries its own directives, so that the same content governs a session regardless of which directory it is started in or which of the three CLIs reads it.

The second, raised in the same revision, is that `CLAUDE.md` itself has grown into a single 92-line, 11082-byte file covering eight unrelated topics, and the request is to shrink it to headings plus references, moving the substance into `skills/`. Investigation in §3.5 found that this is not a purely mechanical move, because Claude Code has two independent always-loaded and on-demand tiers and only one of them is Skills, so the design has to place each section's content in the tier that preserves its current, unconditional enforcement.

The third concerns the editor itself, uncovered while checking a report that `docker/base` installs the wrong `fzf`. `fzf-lua` aborts below `fzf` 0.36 and Ubuntu 22.04 publishes 0.29.0, so the plugin is inoperative in `nrt:base` and in every image descended from it, which is the entire runtime chain. Three further Dockerfile divergences followed from the same investigation. The full evidence for both the toolchain defects and the directive architecture is recorded in [../context/dev-ide-nvim-toolchain.md](../context/dev-ide-nvim-toolchain.md) and [../context/ai-directive-architecture.md](../context/ai-directive-architecture.md) respectively, and the remedies are detailed below.

## 2. High-level design

Six threads, each preferring an existing mechanism to a new one.

1. Replace, not accumulate. `agy` is installed and Gemini CLI is removed from both images, from `djinn`, and from both copies of `ai.lua`. The `.gemini` bind mount and its `mkdir` are deliberately retained, because Antigravity stores its own state beneath `~/.gemini/` and removing them would break the very persistence this plan establishes.
2. One directive set, automated. `CLAUDE.md` and `skills/` remain authoritative. Every other consumer, `GEMINI.md`, `.agents/rules/`, `.agents/skills/`, `~/.claude/skills/`, and every submodule root that carries its own `CLAUDE.md` or `GEMINI.md`, reaches them through a symlink created by an idempotent `djinn`-invoked traversal rather than by a one-off manual step, so a fresh clone by any user reaches the same state after the same `djinn init`.
3. Shrink `CLAUDE.md` correctly, not just mechanically. Each of its nine sections keeps loading exactly as reliably as it does today, by moving into an `@`-imported file for the eight sections that must be unconditional, and staying a Skill-tool pointer for the one section, §5, that already is and should remain a genuine on-demand procedure. Until 2026-08-14 this bullet, and the corresponding detail in §3.5, said eight sections with six imports and one Skill pointer, counted against a `CLAUDE.md` snapshot taken before its own `§2, Correcting superseded claims and code (MANDATORY)`, was added; implementation against the live, nine-section file found the extra section and it is extracted as an import like the other seven standing rules, corrected throughout §3.5 below.
4. Persist by the mount that already exists. Everything `agy` writes lives under `~/.gemini/`, which both start scripts already mount, so login survives container recreation with no new mount.
5. Log in through `djinn`, mirroring the existing pattern rather than adding a verb.
6. Fix the editor toolchain in both images at once, taking `fzf` from an upstream release binary using the architecture-branch idiom the Dockerfiles already use for Neovim.

## 3. Detail

### 3.1 Install `agy` in both Dockerfiles, `amd64` only

The installer at `https://antigravity.google/cli/install.sh` was downloaded and read in full on 2026-08-11 rather than inferred from documentation. It is POSIX shell under `set -euo pipefail`, takes no interactive input, resolves a per-platform manifest, verifies a SHA512 checksum against it before installing and aborts on mismatch, and writes the binary to `$HOME/.local/bin/agy`. It depends only on `curl` or `wget`, `tar`, `sha512sum`, `mkdir`, `cp` and `chmod`, all present in both images. It ends by invoking `"$BINARY_PATH" install || true`, which configures the shell environment only. Nothing in it requires a terminal, so it is safe in a Dockerfile `RUN`.

Both installs, `agy`'s and, immediately above it, Claude Code's own `https://claude.ai/install.sh`, are guarded to run only when `$TARGETARCH` is `amd64`, `ARG TARGETARCH` being `docker buildx`'s own predefined build argument for the platform currently being built. This corrects the first implementation of this section, which installed both unconditionally on every platform in the multi-platform `linux/amd64,linux/arm64` build; that build was found live to segfault on the `linux/arm64` leg, `panic(main thread): Segmentation fault` inside Bun v1.4.0 during Claude Code's own `"$binary_path" install` step, a documented incompatibility between QEMU user-mode emulation and JIT-compiled binaries, not an arm64 support defect in Claude Code, `agy`, or this Dockerfile, and neither CLI is needed on arm64 hardware at present, so both installs are skipped there outright rather than worked around. The full diagnosis, including why `agy` itself, being Go and not JIT, was not shown to be at risk but was made amd64-only alongside Claude Code by direct instruction anyway, is in [../context/dev-ide-ai-clis.md](../context/dev-ide-ai-clis.md) §1.1.

In `docker/base/Dockerfile`, immediately after the locale-generation block of §3.12, and identically in `docker/dev/Dockerfile` after its own package block.

```dockerfile
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    curl -fsSL https://claude.ai/install.sh | bash; \
    else \
    echo "Skipping Claude Code install on $TARGETARCH"; \
    fi
# Point Claude to the bind-mounted config dir so credentials persist across containers
ENV CLAUDE_CONFIG_DIR=/root/.claude

# Antigravity CLI (agy) — Google's terminal agent, successor to Gemini CLI for
# consumer/free tiers (retired 2026-06-18). Installs to /root/.local/bin, which
# is already on PATH below. https://antigravity.google/download
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    curl -fsSL https://antigravity.google/cli/install.sh | bash; \
    else \
    echo "Skipping Antigravity CLI install on $TARGETARCH"; \
    fi
```

No `ENV PATH` change is required. Both files already append `/root/.local/bin` to `PATH` further down, added for `ruff`, and Dockerfile `ENV` applies to the whole resulting image irrespective of the line at which the binary was written. The `agy-acp` and `claude-agent-acp` npm packages of §3.9 remain installed on both architectures, since installing a pure npm package does not execute either CLI's binary and was not implicated in the crash; they are present but inert on arm64, since the binaries they wrap are absent there.

### 3.2 Persistence, and the correction it rests on

Antigravity writes to two directories, both beneath `~/.gemini/`. The private application data directory `~/.gemini/antigravity-cli/` holds `settings.json`, `history.jsonl`, `cache/projects.json`, `log/cli-*.log` and the OAuth token file `antigravity-oauth-token`. The shared configuration directory `~/.gemini/config/` holds `hooks.json`, `projects/`, `agents/`, `plugins/` and the globally discovered `skills/`. Both paths are quoted from the upstream `CHANGELOG.md`, and the split between them is the subject of several entries there.

Both start scripts already mount the common parent, at `docker/scripts/start_ide.sh:23` and `scripts/start.sh:28`.

```
-v $NRT_WS/.gemini:/root/.gemini \
```

A directory bind mount exposes the whole subtree, so every path above lands on the host under `$NRT_WS/.gemini/`. This was verified live rather than assumed, since `stat` reports `/ws/.gemini` and `/root/.gemini` as the same device and inode, `66306:2537107`, and `/proc/mounts` lists `/root/.gemini` as a mount. No new `-v` line is needed and `.gitignore:9` already ignores `.gemini`.

This corrects the first revision of this plan, which asserted that login could not persist in a container and that automating it was therefore pointless. That assertion rested on `google-antigravity/antigravity-cli#479`, which is open and reports that a valid on-disk token is ignored by a fresh process in a headless container. The issue is real but it was fixed and simply not closed, and its labels name the affected versions, `1.0.10` and `1.0.13`. The `CHANGELOG.md` entry for 1.1.3 of 2026-07-16, which is also the date of the issue's last activity, records that the release "Fixed repeated sign-in prompts on Linux caused by the OS keyring, the CLI now bypasses the keyring when no D-Bus session bus is present (headless hosts and containers), skips it for an hour after a timeout, and uses longer keyring timeouts so a slow-but-successful credential read is no longer cut short and forced into a fresh login". Release 1.1.12 of 2026-08-11 further raised the keyring read timeout from one second to five. The related `#57` was closed as fixed in 1.0.1. The installed version will be 1.1.12 or later, so the mount is sufficient.

The comment at the existing mount line in both scripts is updated, which matters more than usual now that Gemini CLI is gone and the directory name no longer names its only user.

```
# Antigravity CLI (agy) state: ~/.gemini/antigravity-cli/ (OAuth token,
# settings, history) and ~/.gemini/config/ (hooks, skills, plugins). The
# directory is named .gemini for historical reasons and must be kept even
# though gemini-cli itself has been removed. See context/dev-ide-ai-clis.md.
-v $NRT_WS/.gemini:/root/.gemini \
```

### 3.3 Container-side setup through `djinn init docker dev`: submodules and directives

This round narrows two things about how §3.3 and §3.4 were first drafted. First, AI tooling, Claude Code, `agy` and `agentic.nvim`, is only ever invoked from inside a container, never on the host, so any path a script writes for such tooling to read, or that mirrors what such tooling would see, must be `/ws`, the mount point every container in this workspace uses, and never `$NRT_WS`, a variable that exists only in the operator's host shell and is unset inside every container `djinn` builds. Second, a reusable shell method invoked from `djinn` belongs in `scripts/helpers/`, alongside `data.sh`, `exec.sh`, `docker.sh` and `sitl.sh`, rather than in a standalone script `djinn` calls by path.

Both corrections point at the same fix. `sync_directive_pair`, the per-directory pairing function of the previous revision, moves into a new `scripts/helpers/ai.sh`, sourced at the top of `djinn` exactly as the four existing helper files are. The traversal that calls it, the loop over the workspace root and every `.gitmodules` path, stays inline in `djinn` rather than becoming a second wrapper function, and, because it must run against `/ws`, is invoked as the body of an `iexec` call into `init_container` rather than executed directly by `djinn`'s own, host-side shell. The full grounding for the pairing policy itself, why it is safe to run generically over every submodule `.gitmodules` names without an exclusion list, and why `ros_ws` is the one case that runs in the opposite direction from the workspace root, is unchanged from the previous revision and remains in [../context/ai-directive-architecture.md](../context/ai-directive-architecture.md) §1 through §3.

```bash
#!/bin/bash

# This script is a helper for djinn, meant only to be sourced within djinn and
# other scripts that source $NRT_WS/scripts/helpers/data.sh
# available methods are
# 1. sync_directive_pair

# Ensures CLAUDE.md and GEMINI.md are symlinked to each other in $1. Never
# fabricates either file from nothing, and never picks a side when both
# already exist as independent regular files, that divergence is a one-time
# human judgement call (see context/ai-directive-architecture.md §3.1).
# Idempotent. $1 is passed explicitly rather than read from the environment,
# following the precedent of list_projectairsim_games in sitl.sh, because the
# workspace root is $NRT_WS on the host and /ws inside every container, and
# this function is meant to be callable from either.
sync_directive_pair() {
    local dir="$1"
    local claude="$dir/CLAUDE.md"
    local gemini="$dir/GEMINI.md"

    if [ -L "$claude" ] && [ "$(readlink "$claude")" = "GEMINI.md" ]; then
        return 0
    fi
    if [ -L "$gemini" ] && [ "$(readlink "$gemini")" = "CLAUDE.md" ]; then
        return 0
    fi

    local have_claude=0 have_gemini=0
    [ -e "$claude" ] && have_claude=1
    [ -e "$gemini" ] && have_gemini=1

    if [ "$have_claude" = 1 ] && [ "$have_gemini" = 1 ]; then
        echo "WARN: $dir has independent CLAUDE.md and GEMINI.md, not symlinked." >&2
        echo "      Resolve by hand: pick the canonical file, symlink the other to it." >&2
        return 0
    elif [ "$have_claude" = 1 ]; then
        ln -sfn CLAUDE.md "$gemini"
        echo "linked $gemini -> CLAUDE.md"
    elif [ "$have_gemini" = 1 ]; then
        ln -sfn GEMINI.md "$claude"
        echo "linked $claude -> GEMINI.md"
    fi
}
```

`djinn`'s own source block gains a fifth line, immediately after `scripts/helpers/sitl.sh`, following the same comment convention the existing four sources use.

```bash
# ai.sh declares directive-sync helper functions required for djinn
# available methods are
# 1. sync_directive_pair
source $NRT_WS/scripts/helpers/ai.sh
```

A second correction follows from the same "AI tooling runs only in a container" premise. `git-setup.sh` and `docker-setup.sh`, which set `safe.directory`, `user.email`, `user.name`, the commit template, and run `git submodule init` and `git submodule update --recursive --remote --merge`, must also run inside `init_container` rather than being left to whichever container a later `djinn up` happens to spawn, so that `ros_ws`, the one submodule this workspace owns, is actually checked out before the directive traversal looks for its `GEMINI.md`, and so that every later container, `nrt_container`, `sitl_bridge_container`, and any other spawned against the same `$NRT_WS` mount, inherits an already-configured git state through the bind mount rather than repeating the setup itself. This is not a new idiom invented for this plan. `scripts/helpers/sitl.sh`'s own `setup_airsim_ros_pkgs_for_docker_build`, marked `# DEPRECATED` and `# TODO Remove in later versions` but still present, already runs `iexec init_container "... /ws/scripts/git-setup.sh $userEmail $userName && /ws/scripts/docker-setup.sh"` against an `init_container` it spawns from `nrt:base`, reachable today only through a commented-out call at `djinn:93`. This plan revives the same idiom against the `init_container` the `dev` branch already spawns from `nrt:dev`, rather than reintroducing the commented-out one.

Two further corrections to this section were made directly in `djinn` this round, ahead of the rest of this plan, and this section is rewritten to describe what is now actually in the tree rather than what was proposed.

The `git-setup.sh` argument-count bug flagged in the previous revision is now fixed, not merely recorded. `git-setup.sh` itself reads two positional arguments, `echo "in docker-setup.sh email: $1"` and `git config --global user.email "$1"` at `scripts/git-setup.sh:5,25`, email then username. The three existing call sites, `up nrt`, `up dev`, and bare `up`, previously passed three, `"/ws/scripts/git-setup.sh $2 $userEmail $userName"` at what was `djinn:203,208,232`, the mode string `nrt`/`dev` landing in the email slot and shifting the real email into the username slot, so every one of those three calls set `user.email` to the literal string `nrt` or `dev`. This is fixed at all four call sites, the three existing ones and the new one below, all now `/ws/scripts/git-setup.sh $userEmail $userName`. This corrects the previous revision of this plan, which found the same defect and deliberately left it unfixed as out of scope for a branch this plan did not otherwise touch; the user has since asked for it fixed directly, so it is fixed rather than only recorded, and the correction is a genuine, intended behaviour change for those three callers, moved from §4's "recorded, not fixed" framing into the list of deliberate changes.

The operational-cost flag raised in the previous revision, that `docker-setup.sh`'s `git submodule update --recursive --remote --merge` would otherwise run, network-dependent, across all ten submodules including the two large UE5 mirrors, on every single `djinn init docker dev`, is resolved by a new fourth positional argument, added directly in `djinn` this round, that makes the git/submodule step opt-in rather than unconditional. `djinn init docker dev` is now two commands in one, first-time workspace setup and routine dev-image refresh, and the two need different git behaviour, the former must configure and populate submodules, the latter must not silently re-touch them on every image pull. The guard:

```bash
if [[ -n "$4" ]]; then
    if [[ "$4" == "skip-git-setup" ]]; then
        echo "skipping git submodule setup"
    else
        iexec init_container "source /ws/scripts/docker-setup.sh && source /ws/scripts/git-setup.sh $userEmail $userName"
    fi
else
    echo "skipping git submodule setup"
fi
```

The default, `$4` empty, skips the git/submodule step, and so does passing the literal `skip-git-setup`; any other non-empty `$4` runs it. This makes the safe, cheap operation, refreshing the image, the one that needs no extra argument, and the expensive, network-dependent one, first-time setup, the one that requires an explicit, deliberate `$4`. Any string other than `skip-git-setup` triggers the run, since the code checks only for that one sentinel, but the documentation in §3.13 recommends a specific spelling, `djinn init docker dev init-git-setup`, so operators have one canonical invocation to reach for rather than an arbitrary placeholder. `docker-setup.sh` and `git-setup.sh` are `source`d rather than executed as `./script.sh`, which sidesteps any question of whether the bind-mounted script carries the executable bit, and, because `source file arg1 arg2` passes `arg1`/`arg2` to the sourced file as its own `$1`/`$2`, `$userEmail`/`$userName` still reach `git-setup.sh` correctly through it.

The order, `docker-setup.sh` before `git-setup.sh`, is also a correction to the previous revision of this plan, which had the two the other way round. `docker-setup.sh` runs the `git submodule update --recursive --remote --merge` that actually populates `ros_ws`'s working tree; `git-setup.sh` then `cd ros_ws`s into it to add `safe.directory` entries for its own nested submodules and set the commit template. On a from-scratch clone, running `git-setup.sh` first would `cd` into an empty `ros_ws`, since only `docker-setup.sh` fetches its content, so `docker-setup.sh` must run first for `git-setup.sh`'s own submodule step to have anything to walk. `git-setup.sh`'s own `git submodule init` at `scripts/git-setup.sh:17` is consequently redundant with `docker-setup.sh`'s, but harmless, since both are idempotent.

The `dev` branch of `djinn init docker` is, in full order: build and pull the image; prepare the host-side `.claude`/`.gemini`/`.claude.json` state and the Claude skills symlink, all of which must exist before the bind mounts below take effect; spawn `init_container`; inside it, the now-guarded git/submodule step, then the directive traversal, which on the setup path depends on `ros_ws` having just been checked out and on the refresh path finds it already checked out from a previous run, then the two CLI logins of §3.4; then the nerd font and container teardown, both unchanged from before. The directive traversal is deliberately left outside the `$4` guard, unlike the git/submodule step, because `sync_directive_pair` touches only local files, no network, and is a no-op once the symlinks are already correct, so gating it would save nothing and would stop it self-healing a manually broken symlink on a routine refresh run.

```bash
elif [[ "$3" == "dev" ]]; then
    image="$userName/nrt:dev"
    filepath="$NRT_WS/docker/dev/"
    build_image $platform $image $filepath
    docker pull $image
    mkdir -p $NRT_WS/.claude $NRT_WS/.gemini
    if [[ ! -f $NRT_WS/.claude.json ]]; then
        touch $NRT_WS/.claude.json
    fi
    # Exposes the workspace skill to Claude Code. Created here rather than in
    # the Dockerfile because the $NRT_WS/.claude bind mount masks anything the
    # image places at /root/.claude. The symlink target is the in-container
    # path, since it is only ever dereferenced by a process running inside
    # the container.
    mkdir -p $NRT_WS/.claude/skills
    ln -sfn /ws/skills/nrt-RandD-workflow $NRT_WS/.claude/skills/nrt-RandD-workflow
    source $NRT_WS/docker/scripts/start_ide.sh init_container $image
    # $4 protects the git/submodule step: omit it, or pass skip-git-setup, on
    # a routine image refresh; pass any other value, e.g. init-git-setup, the
    # first time the workspace is set up. See context/ai-directive-architecture.md.
    if [[ -n "$4" ]]; then
        if [[ "$4" == "skip-git-setup" ]]; then
            echo "skipping git submodule setup"
        else
            iexec init_container "source /ws/scripts/docker-setup.sh && source /ws/scripts/git-setup.sh $userEmail $userName"
        fi
    else
        echo "skipping git submodule setup"
    fi
    # Runs inside init_container, not on the host, and unconditionally,
    # unlike the block above: /ws is what AI tooling actually sees, and the
    # traversal is a cheap, local, idempotent no-op once already correct.
    iexec init_container "source /ws/scripts/helpers/ai.sh && \
        sync_directive_pair /ws && \
        if [ -f /ws/.gitmodules ]; then \
            while IFS= read -r sm_path; do \
                [ -d \"/ws/\$sm_path\" ] && sync_directive_pair \"/ws/\$sm_path\"; \
            done < <(git config --file /ws/.gitmodules --get-regexp '\.path\$' | awk '{print \$2}'); \
        fi"
    iexec init_container "claude /login"
    iexec init_container "agy -p '/usage'"
    source $NRT_WS/docker/dev/install_nerd_font.sh
    docker stop init_container
```

The directive-traversal `iexec` string keeps every `$` meant for the container's shell backslash-escaped, `\$sm_path` and `\$2`, exactly as `djinn`'s own existing `awk '{print \$2}'` calls already do, for instance at `djinn:334` and `djinn:460`. `git config --file .gitmodules --get-regexp '\.path$'` needs no such escaping, since a `$` immediately followed by a single quote is never a substitution form even unescaped inside a double-quoted string, but it is escaped anyway for visual consistency with the rest of the line. That same clause reads the submodule list from the file directly, so it works even before `git submodule update --init --recursive` has populated every path, and each path is skipped with a directory-existence check rather than erroring the whole run, though on the setup path, immediately after the `docker-setup.sh` call above it, `ros_ws` is normally already checked out.

Because the git/submodule `iexec` call and `sync_directive_pair` are both idempotent, and the former is now opt-in rather than unconditional, `djinn init docker dev` remains safe to re-run in either mode, which matters more now than before, since §3.13 makes it the first command in the whole setup sequence rather than a one-off, first-time step.

### 3.4 Logging in through `djinn`

The two login lines close the block shown in §3.3, `iexec init_container "claude /login"` and `iexec init_container "agy -p '/usage'"`, `iexec` being `docker container exec -it` at `scripts/helpers/exec.sh:5-7`, unchanged from the previous revision of this plan except for their new position after the git and directive steps.

The invocation `agy -p '/usage'` is chosen over a bare `agy` for three grounded reasons. It authenticates, because quota cannot be reported without an identity, so an unauthenticated run enters the sign-in flow exactly as a bare launch would. It exits by itself, whereas a bare `agy` opens the full terminal interface and would hold `djinn init docker dev` until the operator quit it. And it is free and idempotent, the 1.1.9 changelog entry recording that print mode answers the read-only slash commands `/usage`, `/quota`, `/credits`, `/model`, `/effort` and `/skills` directly, "without starting an agent turn, spending quota, or leaving a conversation behind", so re-running the workflow on an already authenticated container costs nothing.

The sign-in works over `docker exec -it` because release 1.1.2 added pasting the OAuth authorization code through the controlling terminal, `/dev/tty` on POSIX, when stdin is consumed by a piped prompt, and made only genuinely terminal-less runs fail fast with an actionable message instead of blocking. A container entered with `-it` has a controlling terminal, so it takes the paste path. Should a future release regress this, the fallback is a bare `agy`, quit manually after signing in.

### 3.5 Decomposing `CLAUDE.md` into `skills/`, correctly

`CLAUDE.md` is reduced to a title, and for each of its nine sections, a heading followed by either a Skill-tool pointer or a single `@` import, so that "only the headings... belong in CLAUDE.md and the rest [is] in skills" as requested, while every section keeps loading exactly as reliably as it does today. Until 2026-08-14 this paragraph and the code block below said eight sections and seven imports, counted against a `CLAUDE.md` snapshot from before its own `§2, Correcting superseded claims and code (MANDATORY)`, was added to the live file; implementation found the live file already carried nine sections, and §2 is extracted as an eighth import alongside the other seven, with every later section's number in this document shifted to match the live file rather than the earlier snapshot. The reasoning for why eight sections become imports rather than Skills, and why every import uses an absolute path, is in [../context/ai-directive-architecture.md](../context/ai-directive-architecture.md) §4, summarised here only to the depth needed to execute the change.

Claude Code's own documentation draws a hard line between two mechanisms that both this plan and the request could easily conflate. `@` imports are unconditional: "Imported files are expanded and loaded into context at launch alongside the CLAUDE.md that references them... doesn't reduce context, since imported files load at launch." Skills are conditional: "For task-specific instructions that don't need to be in context all the time, use skills instead, which only load when you invoke them or when Claude determines they're relevant to your prompt." Sections 1, 2, 3, 4, 6, 7, 8 and 9 of `CLAUDE.md` are marked MANDATORY or are standing rules meant to hold on every session unconditionally, the same content class as `CLAUDE.md` itself, not a procedure the agent decides is relevant, so moving them behind Skill-invocation would make their enforcement depend on the agent recognising from a one-line description alone that a task touches them, a real reliability regression from today's unconditional loading. Section 5, Development workflow, already is a genuine on-demand procedure, correctly delegated to the `nrt-RandD-workflow` Skill today, and is left exactly as it is.

Every import path is absolute, `@/ws/skills/<file>.md` rather than `@skills/<file>.md`, because `GEMINI.md` and `.agents/rules/nrt-directives.md` are both symlinks to `CLAUDE.md` per §3.3 and §3.6, and every import-syntax specification read for this investigation, Claude Code's, Gemini CLI's, and Antigravity's own, states the relative case in terms of the importing file's own location without confirming how that location is computed for a symlinked file. An absolute path resolves identically no matter which of the three names is opened to reach it, closing off an ambiguity that would otherwise silently break only the Antigravity path while the other two continued to work.

The eight extracted files are plain Markdown, deliberately without `name`/`description` Skill frontmatter, since they are meant to load unconditionally through the import rather than be offered to the agent's on-demand judgement as an invokable Skill. Each is the corresponding section's bullet content moved verbatim, with no summarisation, consistent with `CLAUDE.md` §1's own append-only-in-spirit rule for context files, applied here to the directive file undergoing the same discipline it prescribes for others.

`CLAUDE.md` becomes:

```markdown
# Claude Directives — Neurorobotics Workspace (`NRT_WS`)

Project-specific instructions for Claude Code when working in this repository.

## 1. Context system (READ FIRST, every task)

@/ws/skills/context-system.md

## 2. Correcting superseded claims and code (MANDATORY)

@/ws/skills/correcting-superseded-claims.md

## 3. Repo orientation

@/ws/skills/repo-orientation.md

## 4. Working conventions

@/ws/skills/working-conventions.md

## 5. Development workflow (MANDATORY)

Load the `nrt-RandD-workflow` skill (Skill tool) before any non-trivial change; it applies wherever AI is invoked under `$NRT_WS` and any child directory. Within a docker container $NRT_WS is equivalent to /ws. Please note that AI will generally be invoked inside a docker container, unless specified

## 6. File formatting — no hard-wrapping (MANDATORY)

@/ws/skills/no-hard-wrap-formatting.md

## 7. Code change discipline

@/ws/skills/code-change-discipline.md

## 8. Writing style (MANDATORY)

@/ws/skills/writing-style.md

## 9. C++ naming conventions (MANDATORY)

@/ws/skills/cpp-naming-conventions.md
```

`skills/context-system.md` through `skills/cpp-naming-conventions.md` each carry the exact bullet content of the corresponding current section, for example `skills/cpp-naming-conventions.md` in full:

```markdown
All C++ code in this workspace must follow these naming conventions.

- Use camelCase as the general naming convention.
- All methods must start with a title case name, for example `void ExampleMethod()`.
- All member variables must be prefixed with `m` to denote they are member variables, for example `mCounter`.
- All private member variables must be prefixed with `mp` to denote they are private member variables, for example `mpInternalState`.
- All vector or array type member variables must be prefixed with `mv`, for example `mvPoints`. Private vector or array member variables must be prefixed with `mvp`, for example `mvpInternalPoints`. Method-local vector or array variables must be prefixed with `v`, for example `vResults`.
- Mutex member variables must be prefixed with `mMtx`, for example `mMtxDataGuard`. Private mutex member variables must be prefixed with `mpMtx`, for example `mpMtxInternalLock`.
```

and the remaining seven are formed the same way, one file per current section 1, 2, 3, 4, 6, 7 and 8, each holding that section's bullets verbatim and nothing else. `skills/README.md` gains a section noting that these eight files are `@`-imported standing directives, not invokable Skills, so a future reader of the directory is not surprised that they carry no Skill frontmatter.

A noted, not-yet-taken refinement: `.claude/rules/` supports the same `paths:` frontmatter Claude Code uses for path-scoped loading, which could make `cpp-naming-conventions.md` load only when a C++ file is actually touched, a genuine efficiency gain. It is not adopted here because Gemini CLI's and Antigravity's own mechanisms do not document an equivalent conditional load, and taking it now would make the rule's presence path-scoped for Claude while staying unconditional for the other two, a parity break in when the rule appears rather than in what it says. See [../context/ai-directive-architecture.md](../context/ai-directive-architecture.md) §4.4.

### 3.6 One directive set for both remaining CLIs, and skills from the same source

Claude Code reads `CLAUDE.md`, resolved per §3.3 and, at the workspace root, decomposed per §3.5. Antigravity reads workspace rules from `.agents/rules`, retaining `.agent/rules` for backward compatibility, per Google's rules documentation, and its global rules file is `~/.gemini/GEMINI.md`, addressed and deliberately not used in §2 of the context file. `CLAUDE.md` stays authoritative and Antigravity's path becomes a symlink to it.

```bash
mkdir -p .agents/rules
ln -sfn ../../CLAUDE.md .agents/rules/nrt-directives.md
```

Two constraints attach and must be recorded. Antigravity documents a limit of 12000 characters per rules file. After the decomposition of §3.5, `CLAUDE.md` itself falls well under that ceiling, since eight of its nine sections are now a heading and one import line each and the ninth, §5, a heading and a short Skill-tool pointer, though the combined, imported content Antigravity's own reader expands to is unchanged from before the decomposition and should still be checked against the ceiling as content grows. And because `GEMINI.md` becomes a symlink, any tool that writes to the project context file would write through into `CLAUDE.md`.

Antigravity discovers workspace skills at `.agents/skills/`, per Google's plugins documentation, in the same `SKILL.md` with `name` and `description` frontmatter format the workspace's own `nrt-RandD-workflow` already uses, so the same skill is exposed there by one more symlink.

```bash
mkdir -p .agents/skills
ln -sfn ../../skills/nrt-RandD-workflow .agents/skills/nrt-RandD-workflow
```

The project-level path is chosen over the global alternatives because it is version-controlled and reproducible from a clone. A changelog entry confirms symlinked customization directories are supported, having fixed rules being loaded twice when a rules directory was reachable through a symlink. The global locations and the disagreement between Google's plugins page and its own changelog about which one is scanned are recorded in [../context/dev-ide-ai-clis.md](../context/dev-ide-ai-clis.md) §4 rather than here.

The Claude-side symlink added in §3.3 closes the same reproducibility gap from the other direction. It exists today only under `$NRT_WS/.claude`, which `.gitignore:12` excludes, so it survives on this host through the bind mount but would be absent on a fresh checkout. It cannot be created in the Dockerfile, because the `$NRT_WS/.claude` bind mount masks whatever the image places at `/root/.claude`.

Both `.agents/` symlinks and `GEMINI.md` itself, being ordinary paths under `/ws` rather than under `.claude` or `.gemini`, are git-tracked directly, so unlike the Claude skills symlink, they need no `djinn` step at all beyond the one already given for `GEMINI.md` in §3.3, and are simply committed alongside `CLAUDE.md` and the `skills/*.md` files. They are listed here for completeness of the directory layout, not because `djinn` must recreate them.

The equivalent stale file inside the `ros_ws` submodule is resolved in §3.3, `ros_ws/CLAUDE.md` symlinked to `ros_ws/GEMINI.md` rather than the other way round, since that submodule's content is genuinely its own. No `.agents/` directory is created inside `ros_ws`, since Antigravity's workspace-rules discovery for a session rooted in a submodule is unverified and out of scope, recorded as such in [../context/ai-directive-architecture.md](../context/ai-directive-architecture.md) §3.3.

### 3.7 Directives and skills inside `agentic.nvim`

For Claude the directives already reach an editor-driven agent and no change is required. The adapter constructs its Claude Agent SDK query with `systemPrompt = { type: "preset", preset: "claude_code" }` and `settingSources: ["user", "project", "local"]`, read from the installed `dist/acp-agent.js` at lines 4082 and 4156. The SDK's own type declarations at `sdk.d.ts:1900-1910` document what that controls and state that a caller "Must include `'project'` to load CLAUDE.md files". The adapter includes it, so the decomposed `CLAUDE.md` of §3.5 loads exactly as it does from a terminal session, `@` imports and all, since import expansion happens wherever `CLAUDE.md` is read, not specially for terminal sessions. User scope is included too, so the skills symlink under `/root/.claude/skills/` is in scope for discovery. The separate `resolveSettings({ settingSources: [] })` at `dist/index.js:47` is a policy resolution and does not govern the session query.

For Antigravity the equivalent guarantee does not exist natively, which is a genuine asymmetry rather than an oversight. `agy` has no native ACP mode, `google-antigravity/antigravity-cli#31` being open since 2026-05-20 with 176 comments and activity as recent as 2026-08-11, so the sidebar must drive it through a third-party adapter. `agy-acp` wraps the real `agy` binary through a pseudo-terminal, so whatever `agy` discovers from `.agents/rules` and `.agents/skills` in the working directory applies, and the §3.3 through §3.6 symlinks are what make that equivalent to the terminal experience. That inheritance follows from the wrapper's mechanism rather than from a documented contract, so §5 verifies it at runtime.

### 3.8 The `agy-acp` provider entry

Two adapters were compared through the GitHub and npm APIs on 2026-08-11.

| | `agy-acp`, chosen | `antigravity-acp`, rejected |
|---|---|---|
| Repository | `shindgew/agy-acp` | `shubzkothekar/antigravity-acp` |
| Stars, forks, open issues | 8, 1, 20 | 38, 11, 9 |
| Last push | 2026-08-11 | 2026-07-01 |
| Runtime | Node >=22, npm package `agy-acp@0.5.0`, `bin: agy-acp -> dist/main.js` | Bun, or per-platform precompiled binaries |
| Mechanism | Wraps the installed `agy` binary through a pseudo-terminal, ACP v1 and draft v2 | Drives Antigravity's local Connect API |
| Disclosed risk | none stated | its README states that use with personal Antigravity OAuth credentials may violate Google's Terms of Service and risks account suspension |

`antigravity-acp` was rejected primarily for that self-disclosed terms of service risk and secondarily because it would add a Bun runtime neither image otherwise needs. `agy-acp` matches the existing architecture exactly, being a globally npm-installed package exposing a bare-name binary on the Node 22 base both images already provide. The residual risk was put to the user and accepted on 2026-08-11, and it remains that this is an unofficial single-maintainer project with 8 stars against 20 open issues, carrying no vendor endorsement, which drives a consumer-authenticated CLI.

### 3.9 Removing Gemini CLI

Six sites reference Gemini CLI as an installed tool. Each is listed with its disposition, since two references to the name must survive and confusing them with the rest would break Antigravity.

The npm install line in both `docker/base/Dockerfile:105` and `docker/dev/Dockerfile:55` loses `@google/gemini-cli` and gains the adapter and the package rename of §3.10, becoming identical in both files.

```dockerfile
RUN npm install -g @agentclientprotocol/claude-agent-acp agy-acp pyright bash-language-server dockerfile-language-server-nodejs tree-sitter-cli@0.25.10
```

The comment above it in `docker/base/Dockerfile:99-100` currently reads that Node 22 via NodeSource "matches node:22-slim used in docker/dev, ensures gemini-cli and claude-code-acp version parity" and is reworded to name the surviving tools. Neither package it cites is right, since `gemini-cli` is being removed and `claude-code-acp` is a different package that this line never installed, the installed one having been `claude-agent-acp`, which `agentic.nvim` distinguishes as two separate providers in its shipped defaults.

The provider table in both copies of `ai.lua`, at `docker/dev/ai.lua:9-16` and the live `/root/.config/nvim/lua/plugins/ai.lua`, loses `gemini-acp` and gains `agy-acp`.

```lua
acp_providers = {
    ["claude-agent-acp"] = {
        command = "claude-agent-acp",
    },
    ["agy-acp"] = {
        name = "Antigravity ACP",
        command = "agy-acp",
        args = {},
        env = {},
    },
},
```

The new entry is written in full while the surviving one remains partial, and the asymmetry is deliberate. `agentic.nvim` merges user options into its defaults with a recursive `deep_merge_into`, at `lua/agentic/utils/object.lua:4-15` by way of `merge_config` and `Agentic.setup`, and its `config_default.lua` ships thirteen providers including `claude-agent-acp`, so a partial entry inherits the fields it omits. No `agy-acp` default exists among the thirteen, so nothing would be inherited and the entry must stand alone. This inheritance is also why removing `gemini-acp` is safe and complete, since the entry in `ai.lua` was only an override of a shipped default and deleting it simply leaves that default unselected.

The keybinding description at `ai.lua:115` is corrected in both copies, since it names the two providers.

```lua
desc = "AI: Switch provider (Claude/Antigravity)",
```

The `djinn` login line at `djinn:113` and the stale TODO above it at `djinn:112` are both removed, as shown in §3.3.

The `djinn` first-run configuration prompt at `djinn:48-50` is removed.

```bash
echo "Fetch Google Project ID for gemini if using Google AI Pro, otherwise provide .env file in workspace root"
read -p "Enter Google project ID for gemini: " id
echo "GOOGLE_CLOUD_PROJECT=${id}" >>$config_file
```

Its stated purpose is Gemini AI Pro, and `GOOGLE_CLOUD_PROJECT` has no other consumer in the tree, verified by search, its only other mention being the description of `.djinn_config` in `context/djinn-cli.md:12`. Antigravity's Cloud-project and enterprise sign-in paths are options on its interactive sign-in screen rather than environment variables, per the 1.1.10 changelog entries, so nothing is lost. This block runs only when `.ssh` is absent, meaning first-time setup, so existing `.djinn_config` files are untouched and continue to export the variable harmlessly.

Two references to the name are retained and must not be removed. The bind mount at `docker/scripts/start_ide.sh:23` and `scripts/start.sh:28`, and the `mkdir -p … $NRT_WS/.gemini` at `djinn:107`, both now serve Antigravity, whose state lives beneath `~/.gemini/` as established in §3.2. The `.gitignore:9` entry likewise stays. This is the one place where a thorough removal of everything named after Gemini would break the feature this plan adds.

### 3.10 Migrating the Claude ACP adapter package

Both Dockerfiles install `@zed-industries/claude-agent-acp`, which npm now marks deprecated: "This package has been renamed to @agentclientprotocol/claude-agent-acp. Please migrate to continue receiving updates." This was found incidentally while investigating whether `CLAUDE.md` reaches an editor-driven agent, and is corrected in the same change since it would otherwise regress silently on the next image rebuild.

The rename is a straight relocation, not a rewrite, verified against the GitHub release history of the new location, `agentclientprotocol/claude-agent-acp`, whose tags run continuously through the exact version the old location's last release carried, `v0.23.1` on 2026-03-26T10:26:05Z, into `v0.24.0` on the same day, whose own release note reads in full, "Rename from `@zed-industries/claude-agent-acp` to `@agentclientprotocol/claude-agent-acp`. We are moving this to the main ACP org to better allow multiple teams to contribute and maintain this adapter." No release between the rename and the current latest, `v0.66.0` of 2026-08-07, flags a breaking change in its notes, checked by searching every release body for the word. The binary name the package installs, `claude-agent-acp`, is unchanged across the rename, `bin: { "claude-agent-acp": "dist/index.js" }` in both the old package's `package.json` and the new one, so no `ai.lua` keybinding, no `acp_providers` entry, and no other configuration in this tree references the old package name at all, only the two Dockerfiles' npm install lines do.

The migration is therefore exactly the one-line change already folded into §3.9's replacement `npm install -g` block, repeated here for its own record since the request asked for the migration to be called out with a code snippet in its own right.

```diff
- RUN npm install -g @google/gemini-cli @zed-industries/claude-agent-acp pyright bash-language-server dockerfile-language-server-nodejs tree-sitter-cli@0.25.10
+ RUN npm install -g @agentclientprotocol/claude-agent-acp agy-acp pyright bash-language-server dockerfile-language-server-nodejs tree-sitter-cli@0.25.10
```

in both `docker/base/Dockerfile:105` and `docker/dev/Dockerfile:55`, alongside the comment correction of §3.9. Nothing else changes. Verification that the migration held is folded into §5's build check, `npm ls -g` showing `@agentclientprotocol/claude-agent-acp` and neither the old package name nor `@google/gemini-cli`.

### 3.11 `fzf` from an upstream release binary in both images

`fzf-lua` enforces a hard minimum, at `lua/fzf-lua/config.lua:275-279` of the installed plugin.

```lua
elseif not utils.has(opts, "fzf", { 0, 36 }) then
  utils.error("fzf version %s is lower than minimum (0.36), aborting.",
    utils.ver2str(opts.__FZF_VERSION))
  return nil
end
```

Ubuntu 22.04 jammy publishes `fzf` 0.29.0-1ubuntu0.1, confirmed through the Launchpad API, so the plugin aborts in `nrt:base` and in every image descended from it, disabling `<leader>ff`, `<leader>fg` and `<leader>fs` throughout the runtime chain. Debian 12 bookworm publishes 0.38.0-1, confirmed through `sources.debian.org` and by the running container reporting `0.38.0 (debian)`, which clears the floor but sits below the 0.53 that the plugin's own health check advises at `lua/fzf-lua/_health.lua:82-88`. Neither archive offers anything newer to these releases, so the archives cannot resolve this.

Upstream ships a static binary whose tarball contains exactly one file named `fzf`, verified by downloading `fzf-0.74.2-linux_amd64.tar.gz`, extracting it and running it, which reported `0.74.2 (3337be9d)`. The release is v0.74.2 of 2026-08-01 with `linux_amd64` and `linux_arm64` assets. `fzf` is therefore dropped from the apt list in both Dockerfiles, at `docker/base/Dockerfile:46` and `docker/dev/Dockerfile:15`, and installed from that release instead, pinned by version.

The block mirrors the Neovim install already present in both files, at `docker/base/Dockerfile:115-130` and `docker/dev/Dockerfile:65-80`, using the same `uname -m` branch so that the multi-architecture build keeps working, and is placed immediately after it in each.

```dockerfile
# fzf from upstream, not apt: fzf-lua aborts below 0.36 and recommends >= 0.53,
# while jammy pins 0.29.0 and bookworm 0.38.0. See
# context/dev-ide-nvim-toolchain.md §3.1.
ARG FZF_VERSION=0.74.2
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
    FZF_ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
    FZF_ARCH="arm64"; \
    else \
    echo "Unsupported architecture: $ARCH"; exit 1; \
    fi && \
    curl -fLO "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${FZF_ARCH}.tar.gz" && \
    tar -xzf "fzf-${FZF_VERSION}-linux_${FZF_ARCH}.tar.gz" -C /usr/local/bin && \
    rm "fzf-${FZF_VERSION}-linux_${FZF_ARCH}.tar.gz" && \
    fzf --version
```

The binary lands in `/usr/local/bin`, which precedes `/usr/bin` on the default `PATH` in both images, so it would win even if an apt `fzf` were reinstalled later by a descendant image. The trailing `fzf --version` makes a failed download or a wrong architecture fail the build rather than surface months later as an aborting plugin, which is precisely how the current defect escaped notice. The version is an `ARG` so a future bump is a build argument rather than an edit, following the override idiom `djinn init docker airsim2` already uses for its base image.

### 3.12 The remaining `docker/base` parity gaps

Three further divergences were found while investigating the above, all in the same direction, namely something the dev image does for the editor that the base image omits. All three are corrected in `docker/base/Dockerfile` so that the shared Lua configuration meets the same environment in both.

The `fd` symlink is absent. Both distributions install the tool as `/usr/bin/fdfind` and never as `fd`, confirmed for Debian by `dpkg -L fd-find` and for Ubuntu jammy through the published package file list, so `docker/base` has no `fd` at all and `agentic.nvim`'s file picker cannot find one. `docker/dev/Dockerfile:33` already compensates and the same line, with the same explanatory comment, is added to `docker/base/Dockerfile` after its apt block.

```dockerfile
RUN ln -s /usr/bin/fdfind /usr/bin/fd
```

The locale is declared but never generated. Both images set `LANG`, `LC_ALL` and `LANGUAGE` to `en_US.UTF-8`, at `docker/base/Dockerfile:16-18` and `docker/dev/Dockerfile:45-47`, and only the dev image generates it, at lines 41 and 42, whose own comment calls the step essential and warns that Neovim will otherwise struggle with special characters. `docker/base` installs the `locales` package at line 71 but never runs `locale-gen`, so the declared locale does not exist and the C fallback applies. This matters to this configuration specifically, because `docker/dev/core.lua:65` sets `fzf-lua` borders to the box-drawing characters `╭─╮│╯╰` and `ai.lua` renders Markdown and LaTeX. The dev image's two lines are added to `docker/base/Dockerfile` after its apt block.

```dockerfile
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen
```

Three packages are absent, namely `procps`, `ncurses-term` and `ncurses-base`, present at `docker/dev/Dockerfile:12` and `22-23`. The `ncurses` pair supplies the terminfo database for the `TERM=xterm-256color` both images set and `procps` supplies `ps`. These are the mildest of the four defects, since the Ubuntu base image already provides much of this, and they are added to the existing apt list in `docker/base/Dockerfile` for parity rather than in response to an observed failure.

### 3.13 Documentation corrected alongside

Five documentation sites describe the superseded arrangement or omit the new operational requirement, and are corrected in the same change, since leaving any one of them would reintroduce the divergence this plan exists to remove, or leave an operator to discover the new ordering requirement by trial and error.

`ARCHITECTURE.md:32` describes `docker/dev` as "a Neovim IDE configured with the Gemini CLI companion" and is reworded to name Claude Code and Antigravity CLI driven through `agentic.nvim` over ACP. `ARCHITECTURE.md:219` claims "The `nvim-gemini-companion` Neovim plugin lives within the repository natively"; that directory does not exist and is not tracked by git, both verified, so the entry is rewritten around `agentic.nvim`, which is the plugin actually in use. `ARCHITECTURE.md:200` speculates about wrapping "foundational models (like Gemini and Claude)" into `djinn` and is left alone, being forward-looking prose rather than a claim about the tree.

`context/djinn-cli.md:21` describes `djinn init docker dev` as logging "into gemini/claude" and line 12 lists `GOOGLE_CLOUD_PROJECT` among the `.djinn_config` keys. Both are corrected, and the `init docker dev` row is rewritten to name the full sequence and the new fourth argument, git and submodule setup, opt-in behind `$4`, directive-symlink sync, unconditional, the Claude skills symlink, then `claude`/`agy` login, then nerd font, since a row this compressed is exactly what an operator reads before the first run. `context/djinn-workflows.md:127`'s `init docker dev` row in the "Other workflows" summary table carries the same correction. Both files gain a line stating that first-time workspace setup is `djinn init docker dev init-git-setup`, with any value other than the literal `skip-git-setup` working identically since the code checks only for that one sentinel, but `init-git-setup` given as the one spelling operators are told to use, and that every subsequent call, to refresh the dev image, is the bare `djinn init docker dev`, with no fourth argument, which leaves git and submodule state untouched. Both files also gain a line stating that the first, `init-git-setup` invocation must happen before `djinn init docker nrt`, or before any other `init docker` target, because the submodule setup and the directive symlinks it performs are shared, host-side state that every later container reads through the same `$NRT_WS` mount, and doing it once, first, through `dev` is what makes every later container's own setup a no-op for that part of the work.

`README.md`, checked for the first time in this revision, documents `djinn init docker nrt` and `djinn init docker kalibr` under "Docker NRT setup" but does not mention `djinn init docker dev` at all. A new step is added ahead of the existing ones, instructing the operator to run `djinn init docker dev init-git-setup` first, with the one-sentence reason above, since this is the one piece of guidance most likely to be skipped by an operator reading the file top to bottom, and noting that later calls should drop the argument.

No new `djinn` workflow is introduced by the login, git-setup, or Dockerfile changes, since the command grammar is unchanged and only the body of the existing `dev` branch is edited, gaining one new, optional positional argument. The directive traversal and the now-optional `git-setup.sh`/`docker-setup.sh` calls are new behaviour attached to that existing branch rather than a new subcommand, and are catalogued as such rather than as a new verb, per `CLAUDE.md` §3's mandate that any change to a `djinn` workflow's behaviour, not only a wholly new one, is recorded in `context/djinn-workflows.md`. The `git-setup.sh` call-signature fix at the three pre-existing `up` call sites is likewise not a new workflow, since it corrects an argument passed to an existing call without changing what is called or when.

## 4. Backwards compatibility

- Dockerfiles, additions. The `agy` installer is a new `RUN` writing a new binary to a path already on `PATH`, and `agy-acp` is a new package on an existing line. Neither affects an existing consumer. Both the `agy` and the pre-existing Claude Code install are now amd64-only, guarded on `$TARGETARCH`; the amd64 leg of the build, the only one this workspace has used, is unaffected, and the arm64 leg gains no new behaviour to be backwards-compatible with, since arm64 was never a working target for either install to begin with, per §3.1.
- Dockerfiles, the adapter rename. The image moves onto the package the live container already runs, closing a divergence rather than opening one, and the binary name is identical across the rename so no configuration references the old name, confirmed in §3.10 by checking every release note between the two endpoints for a breaking-change marker.
- Dockerfiles, `fzf`. The upstream binary is strictly newer than what either archive supplies and `fzf` is a stable, backward-compatible command-line tool, so the only behavioural change is that `fzf-lua` starts working in the runtime chain where it previously aborted. Anything invoking `fzf` directly from a shell continues to work. `/usr/local/bin` precedes `/usr/bin`, so the new binary wins deterministically.
- `docker/base` parity additions. The `fd` symlink creates a name that did not previously exist, `locale-gen` realises a locale the image already declared, and the three packages are additive. None removes or alters an existing behaviour, and the base image is the root of the runtime chain, so each propagates to `ros`, `pangolin`, `camera` and `ardupilot` as an improvement.
- Gemini CLI removal. This is the one deliberately breaking change, and it is the request. Anyone depending on `gemini` inside these containers loses it at the next image rebuild, which is the intent given the 2026-06-18 retirement, and a Standard or Enterprise licensee who still wants it can reinstate the npm package without touching anything else this plan changes. Removing the `gemini-acp` entry from `ai.lua` leaves the plugin's shipped default in place but unselected, so no keybinding breaks and the default provider is unchanged.
- The `.gemini` mount, its `mkdir` and its `.gitignore` entry are retained, so Antigravity's persistence works from the first run and any pre-existing Gemini credentials on the host are left undisturbed rather than deleted.
- `djinn` prompt removal. The block runs only when `.ssh` is absent, so existing installations never reach it and their `.djinn_config` is unchanged. `export $(grep -v '^#' $config_file | xargs)` continues to export a `GOOGLE_CLOUD_PROJECT` line that is already present.
- `djinn init docker dev`, submodule side effect (new, opt-in). Before this plan the `dev` branch had no interaction with git at all. It can now run `git-setup.sh` and `docker-setup.sh` inside `init_container`, which includes `git submodule update --recursive --remote --merge` across all ten submodules named in `.gitmodules`, network-dependent and, for `sitl_ws/src/ue5/UnrealEngine` and `sitl_ws/src/ue5/ProjectAirSim`, potentially slow, but only when a fourth argument is given and is not `skip-git-setup`. Every existing invocation of `djinn init docker dev`, all of which pass no fourth argument, is therefore unaffected, since the new step defaults to skipped; the side effect exists only on a caller that opts in with the new argument, so there is no behaviour change for anyone not using it.
- `djinn` additions. `scripts/helpers/ai.sh` only defines a function when sourced, matching the other four helper files and adding no side effect of its own. `ln -sfn`, `mkdir -p`, `sync_directive_pair`, and the directive-traversal `iexec` call are idempotent, so re-running `djinn init docker dev` in either mode is safe. No other branch is touched and the command grammar is unchanged beyond the new, optional fourth argument.
- `git-setup.sh`'s call signature, fixed at all four call sites (implemented directly in `djinn` this round, ahead of the rest of this plan). The three existing call sites in `up nrt`, `up dev` and bare `up`, and the new one inside `init docker dev`, all now pass `$userEmail` then `$userName`, the two arguments the script itself reads. This corrects the previous revision of this plan, which found the same three-argument mismatch and deliberately left it unfixed, recorded rather than corrected, as out of scope for a branch this plan did not otherwise touch; the user has since asked for it fixed outright, on the grounds that a bug, once found, is better fixed than carried forward. This is consequently a deliberate, intended behaviour change for those three existing callers, not a no-op correction: any of them run against a repository whose git identity was previously set to the literal string `nrt` or `dev` will, from the next run, correctly set it to the operator's real email and username instead. No other behaviour of those three branches changes.
- `CLAUDE.md` decomposition. Every session that reads `CLAUDE.md` today, from a terminal or through `agentic.nvim`, sees the identical concatenated content after the change, since `@` imports load at launch exactly as inline content does, per §3.5 and per Claude Code's own documentation. The only observable difference is that `CLAUDE.md` itself is now short, and the substance is one hop away in `skills/`. `nrt-RandD-workflow` is untouched.
- `GEMINI.md` and the `ros_ws/CLAUDE.md` this plan adds. Both are new-or-corrected symlinks to already-current content, so any tool reading either sees the same, current directives it did not reliably see before. Nothing in the repository references `GEMINI.md` by path outside a symlink read, verified by search.
- `.agents/`. A new directory containing only symlinks. No tool reads it today, so nothing can regress.
- Third-party submodules. `sync_directive_pair` never creates a file in a submodule that has neither `CLAUDE.md` nor `GEMINI.md` today, and none of the nine third-party submodules has either, verified by the same search that found `ros_ws`'s, so the traversal is a no-op for all of them and ArduPilot's own `AGENTS.md` is untouched.

## 5. Validation strategy

These cannot run in the dev container, per the constraint stated in `context/djinn-workflows.md`, and are recorded for a host-side pass.

- Build. `djinn init docker dev` and `djinn init docker nrt` both complete, on `linux/amd64` and on `linux/arm64`. On the amd64 leg, inside each image `agy --version` reports 1.1.12 or later, `claude --version` succeeds, `which agy-acp` resolves, `npm ls -g` shows `@agentclientprotocol/claude-agent-acp` and neither `@zed-industries/claude-agent-acp` nor `@google/gemini-cli`, and `command -v gemini` finds nothing. On the arm64 leg, the build itself must complete without the QEMU/Bun segfault of §3.1, and `command -v claude`/`command -v agy` both find nothing, confirming the guard actually skipped the installs rather than merely rendering the crash non-fatal.
- Git-setup call-signature fix. Already implemented directly in `djinn`, checked independently of the rest of this plan. Run `djinn up dev`, `djinn up nrt`, and bare `djinn up`, and inside the spawned container `git config --global user.email` reports the operator's actual address, not the literal string `dev` or `nrt`, at all three call sites. This is the regression check for §3.3's already-applied fix, and it does not require any of the remaining, unimplemented parts of this plan.
- Directive traversal and the git-setup opt-in. A from-scratch `djinn init docker dev init-git-setup` on a fresh clone leaves `GEMINI.md` a symlink to `CLAUDE.md` and `ros_ws/CLAUDE.md` a symlink to `ros_ws/GEMINI.md` on the host, at `$NRT_WS`, `readlink` confirming both there, and the `iexec` output shows no warning; `git config --global user.email` inside `init_container` reports the operator's actual address, confirming `git-setup.sh` ran via the opt-in path. A subsequent bare `djinn init docker dev`, with no fourth argument, must print "skipping git submodule setup" and must not touch the network or any submodule's checked-out commit, which is the regression check for the operational-cost flag this argument resolves; the directive traversal still runs and is still silent and idempotent on this bare call, since it is unconditional. Re-running either form a second time changes nothing, confirming idempotence in both modes. Temporarily creating an independent `CLAUDE.md` and `GEMINI.md` pair inside the container and calling `sync_directive_pair` on it confirms the warning path fires and neither file is touched.
- `CLAUDE.md` decomposition. `wc -l CLAUDE.md` reports a large reduction from 103 lines. In a Claude Code session, `/context` lists all eight `skills/*.md` files under Memory files alongside `CLAUDE.md`, confirming the imports resolved, and `/memory` shows the import tree. Ask a question that only §9's content answers, for example what prefix a private mutex member variable takes, and confirm the answer is `mpMtx` without the file being read explicitly first, proving the imported content reached context.
- Editor toolchain. In both images `fzf --version` reports 0.74.2, `fd --version` succeeds, `locale` reports `en_US.UTF-8` without a "cannot change locale" warning, and `ps` runs. The multi-architecture build is exercised by building for `linux/arm64` as well, since the `fzf` block branches on `uname -m`.
- `fzf-lua`. This is the assertion the §3.11 diagnosis turns on and it must be checked in a runtime container, not only in `nrt:dev`. In `nrt_container`, open `nvim` and press `<leader>ff`, which must open a picker rather than print "fzf version 0.29.0 is lower than minimum (0.36), aborting". Then `<leader>fg` for the `rg` path, and `:checkhealth fzf-lua`, which must report no version warning now that 0.74.2 exceeds the advised 0.53. Confirm the box-drawing border renders as `╭─╮│╯╰` rather than as replacement characters, which is the visible test of §3.12's locale fix.
- Login and persistence. The added `iexec` line reaches an Antigravity sign-in prompt and completes, after which `$NRT_WS/.gemini/antigravity-cli/antigravity-oauth-token` exists on the host. Recreate the container and run `djinn exec dev "agy -p '/usage'"`, which must print quota without prompting. This is the assertion the §3.2 correction turns on, and if it fails, capture the version before treating `#479` as unfixed.
- Skill parity across CLIs. `agy -p "/skills"` lists `nrt-RandD-workflow`, and `agy -p "what does CLAUDE.md section 9 require of C++ member variable names"` answers with the `m`, `mp`, `mv`, `mvp` and `mMtx` prefixes, proving both `.agents/rules/nrt-directives.md` and its `@` import resolved for Antigravity specifically, not only for Claude.
- ACP wiring. Neovim starts with no error from `ai.lua`, `:checkhealth agentic` reports `agy-acp` installed and no longer probes for `gemini`, and `switch_provider()` offers Claude and Antigravity only. Selecting Antigravity and sending a message reaches a live `agy` session, and the §8 naming question asked through the sidebar confirms the rules reach the wrapped process, which is the §3.7 inheritance that follows from the wrapper's mechanism rather than from a documented guarantee.
- Claude parity in the sidebar. Through `claude-agent-acp`, confirm the same question is answered and the `nrt-RandD-workflow` skill is offered, exercising the `settingSources` behaviour of §3.7 and the user-scope skills symlink.

## 6. Related context

- [../context/dev-ide-ai-clis.md](../context/dev-ide-ai-clis.md), the three CLIs, their credential and config paths, the directive and skill discovery paths of each, the ACP adapter comparison and the package rename, the upstream issues with the versions that fixed them, and the `agy -p '/usage'` login idiom.
- [../context/dev-ide-nvim-toolchain.md](../context/dev-ide-nvim-toolchain.md), why the editor is built twice, how the shared Lua files are staged into the base build context, the four parity defects with their evidence, the parity matrix, and the gotcha that `+Lazy! sync` never runs a plugin's `config`.
- [../context/ai-directive-architecture.md](../context/ai-directive-architecture.md), the full grounding for §3.3 through §3.6, namely why each CLI's own directory walk already reaches every submodule, why an OS-level global symlink was considered and rejected, the per-directory pairing policy and why it is safe to run generically, why the traversal runs inside a container against `/ws` rather than on the host against `$NRT_WS`, and the Rules-versus-Skills distinction behind the `CLAUDE.md` decomposition.
- `context/djinn-workflows.md` and `context/djinn-cli.md`, the `djinn init docker dev` rows refreshed for the added git-setup, directive-sync, skills-symlink and login steps, and the new run-`dev`-first guidance repeated in `README.md`.
