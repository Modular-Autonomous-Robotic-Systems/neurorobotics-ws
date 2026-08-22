# Move the workspace's Unreal Engine pin from 5.2 to 5.7

Implemented 2026-08-12. Host-side validation outstanding, catalogued in §4.

## 1. Motivation

`context/unreal-engine-packaging.md` §8 diagnoses why `unreal/StonePineForest/Content/StonePineForest/Maps/Mountains_Map.umap` refuses to open in the workspace's Unreal Engine 5.2, namely that the file was re-saved by a 5.5 editor at package version 1013 while 5.2's own ceiling is 1009. §9 of that file ranks five remedies that all keep the workspace on 5.2 and route around the one file, and its third remedy, generalised into a standing route usable for any future version mismatch, is to move to an engine that can read 1013 outright. That route was chosen, not for `Mountains_Map.umap` alone but for the workspace's Unreal Engine pin as a whole.

The documentation half of the decision lives in `context/`, where `unreal-engine-packaging.md` §9 records the choice and §11 records what it touched, and where `ARCHITECTURE.md` and `context/project-airsim-docker-build.md` §2 were corrected in place, each preserving the earlier 5.2 argument and the reason it was superseded. This plan is the code half, namely the configuration and scripts that make 5.7 the pin in fact rather than on paper, together with the automation that keeps any future engine-version change from being a hand-run sequence rediscovered from scratch.

## 2. Findings that shaped the design

Four findings are load-bearing, each verified against the tree or against a fresh sparse clone of `EpicGames/UnrealEngine` branch `5.7` at commit `0bcfaffa52e9557258dbd388835ac7668fe864a4`.

Unreal Engine 5.7 writes package version 1018, read directly from `Engine/Source/Runtime/Core/Public/UObject/ObjectVersion.h`'s `EUnrealEngineObjectUE5Version` enumeration, five past `Mountains_Map.umap`'s own 1013 rather than the four short that stops 5.2 at 1009. The version-asymmetry rule resolves cleanly in 5.7's favour and no version-format remedy is needed once the pin moves.

The correct base image is a function of the engine release rather than a constant. Upstream's own `Engine/Extras/Containers/Dockerfiles/linux/build.sh` pairs `nvidia/opengl:1.0-glvnd-devel-ubuntu18.04` with 5.2 and `nvidia/opengl:1.2-glvnd-devel-ubuntu22.04` with 5.7. Diffing the two branches' copies of that file shows they are byte-identical apart from precisely that one line, which is both the justification for making the tag conditional and the proof that every other line this workspace ported from it remains valid against 5.7. Neither upstream pairing is usable verbatim here, since Project AirSim requires a 22.04 userland whatever the engine version, so the workspace's own 5.2 pairing of `1.0-glvnd-devel-ubuntu22.04` is a splice upstream never ships and must be preserved for 5.2 rather than silently replaced.

The Project AirSim tree carries a compiled-artefact hazard neither the original request nor `context/unreal-engine-packaging.md` §9 named. `SimLibs`, the project's static archives, are built by `unreal-linux-toolchain.cmake` against the engine's own bundled Clang under `$UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64`, and that bundle is `v21_clang-15.0.1-centos7` for 5.2 against `v26_clang-20.1.8-rockylinux8` for 5.7, a five-major-version jump across which a static archive is not a supported link input for object code compiled by the other side. No build script in the tree deleted and rebuilt them automatically across an engine change, and none refreshed the copies every game other than `Blocks` carries, since `build_linux.mk` names only `unreal/Blocks/Plugins/ProjectAirSim/SimLibs` in every target that produces or consumes them. Because this recurs on every future engine-version change, it is automated in §3.5 rather than hand-run once.

The plugin's private includes into the engine's `Renderer/Private` and, on Linux, `Renderer/Internal` are the one risk no inspection can close, and are carried forward deliberately per §3.8.

## 3. Changes

### 3.1 `docker/scripts/build_unreal.sh`, release default and a base image derived from it

The release default moved to 5.7:
```bash
# The engine release to build. 5.7 is the version Project AirSim is pinned to, for
# the reasons in context/project-airsim-docker-build.md section 2 and
# context/unreal-engine-packaging.md section 11.
UNREAL_ENGINE_RELEASE="5.7"
```

The branch-resolution block below it is untouched. A release value containing one dot is treated as a branch name outright, so `5.7` resolves to branch `5.7`, verified against the remote as commit `0bcfaffa52e9557258dbd388835ac7668fe864a4`, the same commit the build context in §3.2 was vendored from.

The single `BASEIMAGE` constant became a per-release choice, placed after the release is resolved and before `CONTEXT`:
```bash
# nvidia/opengl's own glvnd-devel tag that upstream's build.sh pairs with each
# release differs by release, 1.0-glvnd-devel-ubuntu18.04 for 5.2's own build.sh
# and 1.2-glvnd-devel-ubuntu22.04 for 5.7's, confirmed against both branches'
# own copies of Engine/Extras/Containers/Dockerfiles/linux/build.sh. Neither
# pairing is usable verbatim, since Project AirSim requires 22.04 regardless of
# engine version, so the tag below is chosen per release and always kept on
# 22.04. 5.2's tag here is the one this workspace already validated while
# pinned to 5.2, not a pairing upstream itself ever uses.
BASEIMAGEDEFAULT="nvidia/opengl:1.2-glvnd-devel-ubuntu22.04"
if [[ "$UNREAL_ENGINE_RELEASE" == "5.2" ]]; then
    BASEIMAGEDEFAULT="nvidia/opengl:1.0-glvnd-devel-ubuntu22.04"
fi
BASEIMAGE="${UNREAL_BASE_IMAGE:-$BASEIMAGEDEFAULT}"
```

The script's provenance header additionally records that the port was re-checked against 5.7 and that the two upstream files differ in exactly the one line the conditional now derives, so a later reader knows the port is valid against both branches without re-deriving it, and its delta list now says the base is always Ubuntu 22.04 rather than "22.04 rather than 18.04", which only made sense while 5.2 was the pin.

A single constant was rejected in favour of the conditional because it would silently rebuild 5.2 on a `1.2` tag that pairing was never tested against, trading a validated configuration for an untested one to save three lines.

**Backwards compatibility.** `build_unreal.sh 5.2` builds exactly the base image this workspace already validated for 5.2. `UNREAL_BASE_IMAGE` overrides either branch of the conditional exactly as it overrode the single constant. The only behaviour change for a caller passing no arguments is that the image now embeds 5.7, which is the intent.

### 3.2 `docker/unreal/Dockerfile` and its build context, re-vendored from branch 5.7

The file could not be repointed at a new `GIT_BRANCH`, because Epic's Dockerfile changed shape between the two releases, generated by `ue4-docker` 0.0.114 rather than 0.0.102. Diffing the 5.2 vendoring against branch 5.7's own copy found:

- `gpg-agent`, `xdg-utils` and `libgbm1` added to the apt package lists.
- The `ppa:slonopotamus/glibc-dso` layer removed upstream entirely, along with the `GLIBC_TUNABLES=glibc.rtld.dynamic_sort=2` variable that accompanied it.
- A new Python 3.12 and `ushell` layer (`add-apt-repository ppa:deadsnakes/ppa`, `python3.12`, `get-pip.py`, then copying `Engine/Extras/ushell` into the installed build and onto `PATH`).
- `-set:BuildIdOverride=UE_5.4` added to the Installed Build step, `ShaderCompileWorker` replacing `UnrealHeaderTool` as the pre-build target, and `UnrealVersionSelector` additionally built and registered. `UnrealHeaderTool` is no longer a build target at all on 5.7, surviving only as a UBT mode, so the 5.2 file's two invocations of it would have failed outright.
- The Mono/UBT/AutomationTool first-run step determining the editor target through a new helper, `print-editor-target.py`, a fifth build-context file with no prior workspace version.
- `split-components.py` splitting `Binaries`, `Content`, `Extras`, `Intermediate`, `Plugins` and `Source` into their own layers alongside the three the 5.2 version split, matched by six new `COPY` lines. The script and the Dockerfile are a matched pair, so mixing versions across them yields a fatally incomplete image.

All five files were copied verbatim from `Engine/Extras/Containers/Dockerfiles/linux/dev/` of that commit, and the copies were diffed against the source afterwards to confirm the Dockerfile body was byte-identical below the added provenance header and the other four byte-identical outright, true of all five as vendored and still true of the four siblings; the Dockerfile itself went on to gain five deliberate deviations across 2026-08-14 and 2026-08-15, deltas 3 through 7 below.

Seven NRT deltas mark `docker/unreal/Dockerfile`, two retired and five added across 2026-08-14 and 2026-08-15, six in response to the first four real build attempts and a seventh found afterward, once the image built and ran successfully, during runtime debugging of the packaged client's own Vulkan device creation. Delta 2, stripping the glibc DSO patch layer, is retired because upstream removed the layer. Delta 1, defaulting `ARG BASEIMAGE` to a 22.04 tag, is retired because the Dockerfile has exactly one caller in the tree, `build_unreal.sh`'s `docker buildx build … "$CONTEXT"`, confirmed by grepping every script under `djinn`, `docker/scripts` and `scripts/` for a reference to the `docker/unreal` build context, and that caller always passes `--build-arg BASEIMAGE` unconditionally. A Dockerfile-side default is therefore dead in the only path that runs, and once §3.1 makes the correct tag conditional on the release, a hardcoded default would actively contradict the caller's choice for 5.2 in any other path. Upstream declares both `ARG BASEIMAGE` and `ARG GIT_BRANCH` bare on both branches, which is the precedent followed. Delta 3 replaces upstream's `RUN ./Engine/Build/BatchFiles/Linux/Build.sh ShaderCompileWorker Linux Development -SkipBuild -buildubt` line, commented out in place in the Dockerfile per `CLAUDE.md` §2 rather than deleted, with `RUN ./Engine/Build/BatchFiles/BuildUBT.sh`, and delta 4 changes `-set:WithServer=true` to `=false` in the Installed Build step, both commented out in place the same way. Delta 5 adds a new `RUN sed` step, no upstream line superseded, that disables the `NDIMedia` plugin entry inside the freshly cloned `Templates/TP_MotionDesignBP/TP_MotionDesignBP.uproject` before the Installed Build step runs, and delta 6 adds `libavahi-common3` to the upstream X11 runtime library layer, commented out in place the same way as deltas 3 and 4. Delta 7, added 2026-08-15, hardcodes the generated `nvidia_icd.json`'s `api_version` field to `1.4.312`, NVIDIA driver 580's own real capability, in place of deriving it from the unrelated `libvulkan1` system loader package version upstream's own expression reads, commented out in place the same way, because UE's own bundled Vulkan loader unconditionally rejects any ICD manifest missing that field outright, §7.5 below gives the full account. The provenance header records all seven deltas and their reasons, so a later reader neither hunts for one that is not there nor reintroduces one whose justification has lapsed. Until 2026-08-14 this paragraph and the provenance header both stated the file carried zero deltas from upstream, which was correct for the file as vendored and stopped being correct once deltas 3 and 4 were added, and the header's claim of two deltas stopped being correct in the same session once deltas 5 and 6 were added in turn. §7 below gives the full account of every build and runtime failure that motivated deltas 3 through 7, the log excerpts, the primary-source evidence read directly from `EpicGames/UnrealEngine` branch `5.7` at this file's own pinned commit, and why each fix was chosen over its alternatives; `context/unreal-engine-packaging.md` §11.2 carries the same account in the living context store.

**Backwards compatibility.** The accepted build arguments, `BASEIMAGE`, `GIT_REPO`, `GIT_BRANCH` and `CHANGELIST`, are unchanged in name and meaning. Removing the Dockerfile-side default cannot regress the one caller, which never omits the argument.

### 3.3 Comment-only corrections naming the engine version

`docker/airsim/Dockerfile:1-4` and `scripts/helpers/sitl.sh`'s comment above `build_airsim2_docker_image` both named `ghcr.io/epicgames/unreal-engine:dev-5.2` while explaining why the locally built base is used instead. Both now name `dev-5.7`. The surrounding reasoning, that Epic's published image is Ubuntu 18.04 and Project AirSim requires 22.04, is unchanged and still correct.

No other line of `docker/airsim/Dockerfile` names an engine version or an engine-version-sensitive path. `ENV UE_ROOT`, its package lists, its `vulkan-tools` name, its pip `cmake` pin and its `USER root`/`USER ue4` bracketing are all version-agnostic.

**Backwards compatibility.** Comment-only. No build argument, name or default changes.

### 3.4 `StonePineForest.uproject`, `EngineAssociation`

`"EngineAssociation"` moved from `"5.2"` to `"5.7"`. `context/unreal-engine-packaging.md` §3.1 establishes this field is a declaration read by the launcher and project-file generator rather than an enforced constraint, so this is corrected for accuracy rather than necessity, since it is the field a later reader checks first when auditing an environment's provenance.

`unreal/Blocks/Blocks.uproject:3` declares `"5.1"` and is left alone, since `Blocks` is the plugin's own reference project rather than an environment under migration, and its mismatch has stood without incident, which is itself evidence for the non-enforcement fact above.

**Backwards compatibility.** Declaration only. No behavioural change.

### 3.5 `scripts/helpers/sitl.sh`, three utility functions for any engine-version change

```bash
# Lists every supported Project AirSim Unreal environment by reading
# unreal/ rather than hardcoding a list, so that a newly added game needs
# no edit here. That directory holds only games to be built for simulation.
# $1 is the workspace root, $NRT_WS on the host or /ws inside
# airsim2_container, which is why it is a parameter rather than read from
# the environment. sitl_ws/scripts/start.sh passes no -e NRT_WS.
list_projectairsim_games() {
    local ws_root="$1"
    find "$ws_root/sitl_ws/src/ue5/ProjectAirSim/unreal" \
        -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

# Removes every build artefact for Project AirSim's own sim libraries and for
# every game listed above, so that a subsequent build recompiles and relinks
# everything against whichever engine $UE_ROOT now points at, rather than
# linking a static archive built by a different Clang into a module built by
# this one. $1 is the workspace root.
clean_projectairsim_build_artefacts() {
    local ws_root="$1"
    local pas_root="$ws_root/sitl_ws/src/ue5/ProjectAirSim"
    ( cd "$pas_root" && ./build.sh clean )
    local game
    for game in $(list_projectairsim_games "$ws_root"); do
        rm -rf "$pas_root/unreal/$game/Binaries" \
               "$pas_root/unreal/$game/Intermediate" \
               "$pas_root/unreal/$game/Saved" \
               "$pas_root/unreal/$game/Build" \
               "$pas_root/unreal/$game/Plugins/ProjectAirSim/Binaries" \
               "$pas_root/unreal/$game/Plugins/ProjectAirSim/Intermediate" \
               "$pas_root/unreal/$game/Plugins/ProjectAirSim/SimLibs" \
               "$pas_root/packages/$game"
    done
}

# Refreshes every game's copy of the ProjectAirSim, Drone and Rover plugins
# from Blocks's own copy, the one simlibs_release builds into and the one
# context/project-airsim-docker-build.md section 10 documents as the source
# for porting an environment onto the plugin. Binaries and Intermediate are
# excluded, since Unreal Build Tool regenerates them per game, matching the
# exclude list build_linux.mk's own package_plugin target uses. Blocks is
# skipped, since it is the source rather than a destination. $1 is the
# workspace root.
copy_projectairsim_plugin_to_games() {
    local ws_root="$1"
    local pas_root="$ws_root/sitl_ws/src/ue5/ProjectAirSim"
    local game plugin
    for game in $(list_projectairsim_games "$ws_root"); do
        [[ "$game" == "Blocks" ]] && continue
        for plugin in ProjectAirSim Drone Rover; do
            rsync -a --delete --exclude 'Binaries' --exclude 'Intermediate' \
                "$pas_root/unreal/Blocks/Plugins/$plugin/" \
                "$pas_root/unreal/$game/Plugins/$plugin/"
        done
    done
}
```

The workspace root is an explicit first argument rather than a read of `$NRT_WS`, because these run from two places, `djinn` on the host where that variable is set, and `build_airsim2_game.sh` inside `airsim2_container` where it is not, `sitl_ws/scripts/start.sh`'s `docker run` passing no `-e NRT_WS`. `/ws` inside the container and `$NRT_WS` on the host name the same bind-mounted tree, so one parameterised implementation serves both rather than two copies drifting apart. Sourcing the whole file inside the container was verified inert for the parts it does not use, since the file defines functions only and executes nothing at load time.

The games list is derived from `unreal/` rather than hardcoded so that adding an environment needs no edit in `sitl.sh`, in `build_airsim2_game.sh` or in `djinn`.

**Backwards compatibility.** Purely additive. No existing function is modified, renamed or removed.

### 3.6 `sitl_ws/scripts/build_airsim2_game.sh`, an explicit `rebuild_plugin` flag and derived project validation

```bash
#!/bin/bash
# Builds a Project AirSim Unreal environment inside airsim2_container.
# $1 selects the project, defaulting to StonePineForest, validated against
# every directory under unreal/ rather than a hardcoded list, so a newly
# added game needs no edit here. $2 selects the client configuration,
# defaulting to Development. $3, "true" or "false" (default "false"),
# selects whether to clean every build artefact, rebuild Blocks's SimLibs
# against whichever engine $UE_ROOT now points at, and refresh every other
# game's copy of the plugin before packaging $1. The old SimLibs-directory
# existence check is deliberately gone, since it could not tell a SimLibs
# built against a different engine from one that never needed rebuilding.
# The sim libs must exist before Unreal Build Tool runs regardless, because
# the plugin links their static archives by path out of
# Plugins/ProjectAirSim/SimLibs, which is upstream issues 83 and 129.

set -e
source /ws/scripts/helpers/sitl.sh

project="${1:-StonePineForest}"
config="${2:-Development}"
rebuild_plugin="${3:-false}"

PAS_ROOT=/ws/sitl_ws/src/ue5/ProjectAirSim

if ! list_projectairsim_games /ws | grep -qx "$project"; then
    echo "Unsupported project: $project"
    exit 1
fi

cd "$PAS_ROOT"

if [[ "$rebuild_plugin" == "true" ]]; then
    clean_projectairsim_build_artefacts /ws
    ./build.sh simlibs_release
    copy_projectairsim_plugin_to_games /ws
fi

"$UE_ROOT/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
    -project="$PAS_ROOT/unreal/$project/$project.uproject" \
    -nop4 -nocompile -build -cook -compressed -pak -allmaps -stage -archive \
    -archivedirectory="$PAS_ROOT/packages/$project/$config" \
    -clientconfig="$config" -clean -utf8output -prereqs

# run_airsim.sh invokes the staged ELF rather than the generated .sh wrapper,
# and the wrapper is what normally chmods the ELF, so do it here instead.
chmod +x "$PAS_ROOT/packages/$project/$config/Linux/$project/Binaries/Linux/"* || true
```

The replaced guard tested only whether `unreal/Blocks/Plugins/ProjectAirSim/SimLibs` existed, which cannot distinguish a directory built against a different engine from one that never needed rebuilding, and is precisely the test that would have let stale 5.2 archives link into 5.7 modules. A version tag or checksum on `SimLibs` was considered and rejected as more machinery than the problem warrants, since the caller already knows when it is changing engines and an explicit flag says so directly.

**Backwards compatibility.** This is the plan's one deliberate behaviour change. With no third argument the script defaults to `rebuild_plugin=false` and no longer auto-builds `SimLibs` when absent, so a genuinely fresh checkout now fails at `BuildCookRun`'s link step rather than silently building them first. §3.7 supplies the flag from `djinn`'s own call site wherever the old implicit behaviour is wanted. Project validation is behaviourally identical to the old `case` statement for both names it accepted, since `unreal/` contains exactly `Blocks` and `StonePineForest`, verified by listing it and by exercising the new predicate against both names and two invalid ones.

### 3.7 `djinn`, a positional force-rebuild and corrected `build airsim2` forwarding

In `init docker airsim2`, `$4` is a rebuild-mode selector and `$5` is the base-image override:
```bash
                if [[ -n "$4" ]]; then
                    echo "============ BUILDING PROJECT AIRSIM Image ============="
                    rebuild=false
                    if [[ "$4" == "force-all" ]]; then
                        export UNREAL_FORCE_REBUILD=1
                        rebuild=true
                    elif [[ "$4" == "rebuild-base" ]]; then
                        rebuild=true
                    else
                        echo "Not rebuilding base image"
                    fi
                    if [[ "$rebuild" == true ]]; then
                        if ! "$NRT_WS/docker/scripts/build_unreal.sh"; then
                            echo "Unreal Engine image build failed, not building Project AirSim on a missing base."
                            exit 1
                        fi
                    fi
                    echo "============ BUILDING UNREAL ENGINE Image ============="
                    # Run rather than source, so that the script's set -e and set -x
                    # cannot leak into djinn. It is a no-op when the image exists.
                    echo "============ BUILDING PROJECT AIRSIM Image ============="
                    if [[ -n "$5" ]]; then
                        echo "Building with base image: $5"
                        build_airsim2_docker_image "$5"
                    else
                        build_airsim2_docker_image
                    fi
                else
                    build_airsim2_docker_image
                fi
```
The two repeated `echo` banners are the file's own artefact of the 2026-08-14 hand edit rather than a further deliberate change, kept here so this quote is byte-accurate against `djinn` rather than a cleaned-up paraphrase; they print duplicate progress lines but change no behaviour.
`force-all` forces the engine rebuild unconditionally then builds the wrapper, `rebuild-base` runs `build_unreal.sh` without forcing it, so its own existence guard decides whether anything actually rebuilds, then builds the wrapper, and any other value, including empty, skips the engine build entirely and rebuilds only the wrapper. `$5`, read only when `$4` is non-empty, is the base-image override. This plan's own implementation phase instead gave `$4` the narrower role of the base-image override inherited from the original Project AirSim integration, with `$5` a bare force flag requiring the placeholder form `djinn init docker airsim2 "" force`; `$4` was redesigned into the mode selector above on 2026-08-14, in a direct edit to `djinn` after this plan's implementation phase rather than through a further planning cycle, and the placeholder form no longer exists in the tree. The replacement is `djinn init docker airsim2 force-all` for a forced rebuild and `djinn init docker airsim2 rebuild-wrapper <base_image>` for the override that used to live in `$4`. The full, current catalogue entry is `context/djinn-workflows.md`'s `djinn init docker airsim2 [mode] [base_image]`.

In `build airsim2`, the argument forwarding is corrected rather than merely extended:
```bash
            else
                # $3 the project, $4 the client configuration (default Development),
                # $5 "true" or "false" (default "false") for rebuild_plugin, forwarded
                # to build_airsim2_game.sh exactly. See sitl_ws/scripts/build_airsim2_game.sh.
                project="$3"
                config="${4:-Development}"
                rebuild_plugin="${5:-false}"
                iexec airsim2_container "cd /ws && /ws/sitl_ws/scripts/build_airsim2_game.sh $project $config $rebuild_plugin"
            fi
```
The previous form used `$3` only as a truthy gate whose value was discarded and forwarded `$4` as the project, so the client configuration could not be set through `djinn` at all. `context/djinn-workflows.md` documents `build_airsim2_game.sh` as invoked through `djinn exec airsim2 "…"` rather than through this branch, which is the evidence no catalogued workflow depended on the old mapping.

**Backwards compatibility.** `djinn build airsim2` with no `$3` still runs `build.sh all`. The old `djinn build airsim2 <truthy> <project>` form is not preserved; a caller using it now gets the truthy token as the project name, which fails validation cleanly rather than building the wrong thing silently. For `init docker airsim2`, a bare invocation with no `$4` now skips the engine-build step entirely and rebuilds only the wrapper; this plan's own implementation instead always attempted the engine build on a bare invocation (a no-op once the image existed), and that changed on 2026-08-14 along with the `$4`/`$5` redesign noted above. All six argument paths across both branches were exercised against the logic as it stood at the end of this plan's implementation and produced the mapping this paragraph originally described; §3.7's note above is the current source for `init docker airsim2`.

### 3.8 Renderer include-path coupling, carried forward as a risk

`ProjectAirSim.Build.cs:36` adds `EngineDirectory + "/Source/Runtime/Renderer/Private"` unconditionally and `:90` adds `EngineDir + "/Source/Runtime/Renderer/Internal"` on the Linux path. `Engine/Source/Runtime/Renderer/` under 5.2 contains only `Private`, `Public` and `Renderer.Build.cs`, while under 5.7 it additionally contains a populated `Internal` of 21 files, so the Linux path's previously inert reference can now resolve, which can only add resolvable headers rather than remove any, and is incidentally evidence that the plugin at this commit was authored with 5.7 in mind. Whether anything the plugin's own translation units include from `Renderer/Private` moved or changed shape across five minor versions cannot be settled by inspection, and the first evidence either way is a compiler error naming a missing header during §4's packaging step.

**Backwards compatibility.** No change made. Recorded so the risk is not forgotten now that the route naming it was chosen rather than rejected.

## 4. Validation

Everything checkable inside the development container was run and passed.

| Check | Result |
|---|---|
| `bash -n` on `djinn`, `scripts/helpers/sitl.sh`, `build_airsim2_game.sh`, `build_unreal.sh` | all parse |
| The three helpers are defined and callable with `NRT_WS` unset, the container condition | passes, `list_projectairsim_games /ws` returns `Blocks` and `StonePineForest` |
| Project validation accepts `StonePineForest` and `Blocks`, rejects invalid names | passes for all four cases exercised |
| Base image resolution per release, and `UNREAL_BASE_IMAGE` override of both branches | `5.7` and `5.6` give the `1.2` tag, `5.2` gives `1.0`, override wins in every case |
| Branch resolution for `5.7`, and that the branch exists on the remote | resolves to branch `5.7` at commit `0bcfaffa52e9557258dbd388835ac7668fe864a4` |
| Vendored build context is byte-identical to upstream 5.7 | true as vendored; no longer true of `docker/unreal/Dockerfile` after the 2026-08-14 deltas 3 through 6 noted in §3.2, made necessary by the first three real build attempts, see §7 |
| `djinn` argument mapping across all six paths of the two changed branches | matches §3.7 exactly |
| No stale code-level 5.2 reference remains | only deliberate ones, namely the provenance history and the per-release conditional with its rationale |

Four real attempts at `djinn init docker airsim2 force-all` have run so far, §7 giving the full account of all four. The first reached roughly 45 minutes in, through toolchain extraction and the initial engine setup, before failing inside Epic's own `Build.sh -buildubt` step, fixed by delta 3. The second, after that fix, reached roughly 35 minutes into the Installed Build step itself before failing inside the `UnrealServer` target's dependency walk, fixed by delta 4. The third, after that fix, ran the full `builder` stage to completion, over two hours, before failing inside `BuildDerivedDataCache`'s generation for the `TP_MotionDesignBP` template, fixed by deltas 5 and 6, §7.3. The fourth, after those fixes, ran the entire `builder` stage clean and reached the final `minimal` image-assembly stage before failing on host disk exhaustion, §7.4, not a Dockerfile defect. Once host disk space was freed, the next attempt built the image successfully end to end, and Project AirSim's own SimLibs then built and packaged against it, only to fail at runtime, `djinn start sitl2`, on the packaged client's own Vulkan device creation, §7.5, resolved together with an NVIDIA driver upgrade to 580 (`plans/update-nvidia-driver.md`). This whole sequence cannot run in the development container and needs a host with the Docker daemon, a GPU and roughly 200 GB free, and, per §7.4, headroom above that figure and a pruned BuildKit build cache if the host has already accumulated several failed attempts:

```bash
djinn init docker airsim2 force-all
djinn up airsim2
djinn build airsim2 StonePineForest Development true
djinn start sitl2
```
The first command uses the `force-all` mode of the 2026-08-14 argument redesign noted at the end of §3.7; the form this plan originally specified, `djinn init docker airsim2 "" force`, no longer forces anything under that redesign, since an empty `$4` now skips the engine-build step outright rather than reading `$5` as a force flag.

Confirm the build log's configuration block reports `Unreal Engine Release: 5.7` before the multi-hour build proceeds. The third command is where §3.8's risk would surface, as an unresolved-include error naming a header under `Renderer/Private` or `Renderer/Internal`. Verification of the fourth is the existing checklist at `context/unreal-engine-packaging.md` §12.9, namely that the cook log names `StonePineForest` with no missing `/Drone` or `/Rover` content, that the run log carries no `is too new` warning and no failed import of `/Script/AirSim`, that ports 8989 and 8990 are bound, and that the vehicle spawns at a stable altitude on `Mountains_Map_LevelDesign.umap`. `djinn kill sitl2` and `djinn down airsim2` tear the stack down. Check `df -h "$NRT_WS"` first rather than mid-build, since the existing 5.2 image's layers remain on disk until Docker prunes them, and prune the BuildKit build cache (`docker builder prune`) before each retry too, since accumulated cache across this migration's own four iterative attempts was the proximate cause of the disk exhaustion documented in §7.4.

Note when committing that `docker/airsim/Dockerfile`, `docker/scripts/build_unreal.sh`, `docker/unreal/` and `sitl_ws/scripts/build_airsim2_game.sh` are untracked in git, carried over from the Project AirSim integration that has not yet been committed, so `git diff` does not cover them and `git add` is needed to stage them.

## 5. Backwards compatibility summary

`build_unreal.sh <release>` still takes an explicit release and now picks the base image validated for that release, so `build_unreal.sh 5.2` reproduces the previously working 5.2 configuration exactly. `djinn init docker airsim2`'s `$4` is the rebuild-mode selector and `$5` the base-image override described at the end of §3.7, redesigned there from this plan's own implementation on 2026-08-14. `scripts/helpers/sitl.sh`'s existing functions are untouched. `build_airsim2_game.sh`'s replacement of an implicit `SimLibs` check with an explicit flag is the one deliberate behaviour change, with `djinn`'s call site updated in the same pass so no catalogued workflow observes a difference. `djinn start sitl` and the Cosys-AirSim image on `dev-5.5` are untouched, and the two simulators remain pinned to different engine versions as `ARCHITECTURE.md` requires. The one change with no opt-out is that `shandilya1998/nrt:unreal` refers to a 5.7 image once rebuilt, which is the intent.

## 6. Deliberately not done

`Mountains_Map.umap`, the 5.5-saved file, was not adopted as StonePineForest's active map. `context/unreal-engine-packaging.md` §9 records that this became optional once 5.7 could open it, and it remains a separate decision from the engine migration.

`unreal/Blocks/Blocks.uproject`'s `EngineAssociation` of `5.1` was left alone, per §3.4.

The `Renderer/Private` and `Renderer/Internal` coupling was not resolved in advance, since inspection cannot settle it and §4's packaging step is the test.

No version tag or checksum was added to `SimLibs`, per §3.6.

The Cosys-AirSim image's `dev-5.5` pin was not touched, since the two simulators pin different engines by design.

## 7. Build failures encountered during validation

Neither failure below originates in this workspace's own files. Both are inside `docker/unreal/`'s build context, the first inside the vendored Dockerfile's own `RUN` sequence and the second inside Epic's engine source that the Dockerfile clones fresh on every build. Both were diagnosed by reading the actual `EpicGames/UnrealEngine` source at branch `5.7`, commit `0bcfaffa52e9557258dbd388835ac7668fe864a4`, the exact commit this build context is vendored from and the exact commit the Dockerfile's `git fetch --depth 1 origin 5.7` clones, rather than by guessing from the log alone. Both are recorded here, beyond the compact deltas 3 and 4 in §3.2, as a self-contained incident report for a later reader who hits either symptom again and wants the full reasoning without re-deriving it.

### 7.1 `UnrealBuildTool` bootstrap failure, `Build.sh -buildubt`

**Symptom.** `djinn init docker airsim2 force-all` failed roughly 45 minutes in, inside `docker/unreal/Dockerfile`'s `RUN ./Engine/Build/BatchFiles/Linux/Build.sh ShaderCompileWorker Linux Development -SkipBuild -buildubt` step. The log showed `dotnet build Engine/Source/Programs/UnrealBuildTool/UnrealBuildTool.csproj -c Development -v quiet` reporting `Build succeeded. 0 Warning(s). 0 Error(s)`, immediately followed by `Running command : dotnet Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll ShaderCompileWorker Linux Development -SkipBuild -buildubt` and then `Could not execute because the specified command or file was not found`, naming that same `.dll` path.

**Investigation.** `Engine/Build/BatchFiles/Linux/Build.sh` was read directly. Its `-buildubt` handling is exactly:
```bash
if [[ $i == "-buildubt" ]] ; then
	if ! dotnet build Engine/Source/Programs/UnrealBuildTool/UnrealBuildTool.csproj -c Development -v quiet; then
		echo "Failed to build the build tool (UnrealBuildTool)"
		exit 1
	fi
fi
```
followed, unconditionally and regardless of `-buildubt`, by
```bash
echo Running command : dotnet Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll "$@"
dotnet Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll "$@"
```
The `dotnet build` call has no step that copies its output anywhere, so it is not what places `UnrealBuildTool.dll` at `Engine/Binaries/DotNET/UnrealBuildTool/`. `Engine/Build/BatchFiles/Linux/GenerateProjectFiles.sh`, the engine's own normal bootstrap entry point, was read next and found to call a different script, `Engine/Build/BatchFiles/BuildUBT.sh`, for the identical purpose. That script's relevant lines are
```bash
"$SCRIPT_DIR/DotnetRetry.sh" build Programs/UnrealBuildTool/UnrealBuildTool.csproj -c Development -v "$MSBuild_Verbosity"
...
"$SCRIPT_DIR/DotnetRetry.sh" publish Programs/UnrealBuildTool/UnrealBuildTool.csproj -c Development --output ../Binaries/DotNET/UnrealBuildTool --no-build -v "$MSBuild_Verbosity"
```
namely `build` followed by `publish --output ../Binaries/DotNET/UnrealBuildTool`, which is the step `Build.sh -buildubt` lacks. `Engine/Build/BatchFiles/Linux/Setup.sh` was read to rule out a prebuilt `UnrealBuildTool.dll` being seeded some other way, and on Linux it only installs the bundled Clang toolchain and third-party libs, calling no `GitDependencies` step that could have downloaded one.

**Root cause.** `Build.sh -buildubt` is designed to refresh an already-published `UnrealBuildTool.dll` in place, which a normal engine checkout has because `GenerateProjectFiles.sh`/`BuildUBT.sh` already ran once. On this Dockerfile's from-scratch, single-commit clone, nothing has run `BuildUBT.sh` yet, so the file `Build.sh`'s own next line depends on does not exist, and the unconditional final invocation fails with the exact "file not found" error observed.

**Fix, delta 3.** `docker/unreal/Dockerfile`'s `RUN ./Engine/Build/BatchFiles/Linux/Build.sh ShaderCompileWorker Linux Development -SkipBuild -buildubt` line is commented out in place per `CLAUDE.md` §2 and replaced with `RUN ./Engine/Build/BatchFiles/BuildUBT.sh`, which takes no target/platform/configuration arguments, since its job, building and publishing `UnrealBuildTool` itself, is narrower than `Build.sh`'s. Full account in `context/unreal-engine-packaging.md` §11.2.

**Verification.** The second real build attempt, §7.2 below, progressed roughly 35 minutes past this step before failing elsewhere, which is direct evidence the fix works, since the build would have failed here again otherwise. The fix has not yet been verified by a complete, successful Installed Build end to end.

### 7.2 `UnrealServer` target failure, `oneAPILevelZero` module refusal

**Symptom.** After delta 3, a second `djinn init docker airsim2 force-all` attempt progressed past UBT bootstrap and roughly 35 minutes into `RUN ./Engine/Build/BatchFiles/RunUAT.sh BuildGraph -target="Make Installed Build Linux" ...`, the Installed Build step itself. It successfully compiled `UnrealClient` for all three configurations, then began `UnrealServer`, and failed with:
```
Linux dedicated server is made to depend on oneAPILevelZero. We want to avoid this, please correct module dependencies.
Unable to instantiate module 'oneAPILevelZero': Linux dedicated server is made to depend on oneAPILevelZero. We want to avoid this, please correct module dependencies.
(referenced via allmodules option -> ExternalGPUStatistics.uplugin -> ExternalGPUStatistics.Build.cs)

Result: Failed (RulesError)
```
`RunUAT` exited with code 8 and `AutomationTool executed for 0h 35m 8s`.

**What `-set:WithServer=true` does.** `Engine/Build/InstalledEngineBuild.xml:72` declares `<Option Name="WithServer" Restrict="true|false" DefaultValue="false" Description="Include precompiled server targets"/>`, and `:148` reads `<Property Name="OptionalServerTarget" Value="UnrealServer" If="$(WithServer)"/>`. With it true, the BuildGraph script additionally precompiles `UnrealServer`, Unreal's generic headless dedicated-server target type, into the Installed Build, so that a downstream project built from this engine could package a `Server` configuration, the kind used for authoritative multiplayer game servers, without needing engine source. `false` is upstream's own default; `true` is a choice ue4-docker's generic Dockerfile-generation template makes for every engine it packages, inherited unexamined when this Dockerfile was first vendored for 5.2 and carried forward to 5.7 without this workspace ever having reconsidered it, since nothing before this build attempt had reached far enough to exercise the `UnrealServer` target at all.

**What `oneAPILevelZero` is, and whether it is a missing dependency.** It is not missing. `Engine/Source/ThirdParty/Intel/oneAPILevelZero/1.21.9/` is vendored in full in the engine tree, and `Engine/Source/ThirdParty/Intel/oneAPILevelZero/oneAPILevelZero.Build.cs` is the UnrealBuildTool module wrapping it. `oneAPILevelZero` is Intel's oneAPI Level Zero SDK, a low-level GPU compute and management API, the Intel counterpart to NVIDIA's NVML, which the same plugin also links. `Engine/Plugins/Runtime/ExternalGPUStatistics/Source/ExternalGPUStatistics/Private/Vendors/Intel.cpp` uses it to query Intel GPU utilisation and memory statistics for the `ExternalGPUStatistics` plugin, `"Description": "Plugin to find out more detailed GPU usage for NVIDIA, AMD, and Intel GPUs."` per its own `.uplugin`. The failure is not a filesystem or download problem, it is the module's own constructor deliberately refusing to build.

**Root cause.** `oneAPILevelZero.Build.cs`'s constructor contains, verbatim, on the Unix branch:
```csharp
else if (Target.IsInPlatformGroup(UnrealPlatformGroup.Unix))
{
	if (Target.Type == TargetType.Server)
	{
		string Err = string.Format("{0} dedicated server is made to depend on {1}. We want to avoid this, please correct module dependencies.", Target.Platform.ToString(), this.ToString());
		System.Console.WriteLine(Err);
		throw new BuildException(Err);
	}
	...
}
```
This is Epic's own deliberate design, a headless dedicated server has no GPU context to query, so the module refuses outright to be instantiated for `Target.Type == TargetType.Server` on any Unix platform. The reason it is instantiated at all is that `Engine/Plugins/Runtime/ExternalGPUStatistics/Source/ExternalGPUStatistics/ExternalGPUStatistics.Build.cs` adds it unconditionally for any Unix platform group member, `bool bWithIntel = (Target.IsInPlatformGroup(UnrealPlatformGroup.Windows) && Target.Architecture.bIsX64) || Target.IsInPlatformGroup(UnrealPlatformGroup.Unix);`, with no `Target.Type` check of its own, an omission relative to the guard `oneAPILevelZero.Build.cs` itself enforces. The plugin's own `.uplugin` does not close the gap either, `"TargetConfigurationDenyList": [ "Shipping" ]` restricts by build configuration (Debug, DebugGame, Development, Test, Shipping), a different axis from target type (Game, Client, Server, Editor, Program), so it does not stop the plugin being considered for a Server target in any configuration, Shipping included, since the deny list is evaluated for configuration filtering, not target-type filtering. `ExternalGPUStatistics` is `"EnabledByDefault": false` and is not part of any target's normal module set, so none of this matters for an ordinary build, it surfaces only because the Installed Build's own makefile generation for `UnrealServer` walks the full plugin list, `(referenced via allmodules option -> ...)` in the error, to precompile every plugin a downstream project might enable, which is exactly what `WithServer=true` asks the build to do.

**Fix, delta 4.** `docker/unreal/Dockerfile`'s `-set:WithServer=true` is commented out in place per `CLAUDE.md` §2 and changed to `-set:WithServer=false`, reverting to upstream's own documented default and skipping the `UnrealServer` target entirely, which avoids the `oneAPILevelZero` instantiation altogether rather than working around it. `sitl_ws/scripts/build_airsim2_game.sh:38-42`'s own `RunUAT.sh BuildCookRun -clientconfig="$config"` was checked and confirmed to request only a `Client`-family build, never a `Server` one, so Project AirSim as integrated into this workspace exercises no capability that `WithServer=false` removes.

**Alternative considered and rejected.** Patching `ExternalGPUStatistics.Build.cs` to add a `Target.Type != TargetType.Server` guard, mirroring `oneAPILevelZero.Build.cs`'s own, would fix the underlying plugin defect directly and preserve `WithServer=true`. It was rejected as disproportionate here, it edits third-party plugin source inside the freshly cloned engine tree on every build rather than a single BuildGraph flag, in exchange for a target type, `Server`, this workspace does not use regardless. If a future task needs a Linux dedicated server Installed Build from this same engine, this is the fix to apply instead of reverting delta 4.

**Verification.** Confirmed. A third `djinn init docker airsim2 force-all` attempt, after delta 4, ran the entire `Make Installed Build Linux` `UnrealClient` compile and the full `BuildDerivedDataCache` node to its end with no further mention of `oneAPILevelZero` or `UnrealServer`, `AutomationTool executed for 2h 18m 44s` total this time against `0h 35m 8s` before the previous failure, confirming the target was skipped as intended. It then failed at a different, later point, §7.3 below.

### 7.3 `DerivedDataCache` generation failure, `NDIMedia` plugin refusal to load `libndi.so.6`

**Symptom.** After delta 4, the same third `djinn init docker airsim2 force-all` attempt ran `BuildDerivedDataCache` to completion across every template `Engine/Build/InstalledEngineFilters.xml`'s `ProjectsToBuildDDC` names, generating and compressing DDC for all of them including `TP_MotionDesignBP`, the last in the list, whose own commandlet run reported success on its actual task and then failed regardless:
```
LogDerivedDataCache: Display: ../../../Engine/DerivedDataCache/Compressed.ddp.1EF669B2DF044B05BF5D3D63819DAC1C: Opened pak cache for reading. (306 MiB)
LogDerivedDataCache: Display: ../../../Engine/DerivedDataCache/Compressed.ddp: Opened pak cache for writing.
LogDerivedDataCache: Display: Sucessfully wrote ../../../Engine/DerivedDataCache/Compressed.ddp.
LogDerivedDataCacheCommandlet: Display: BeginCacheTime=3.79s, FinishCacheTime=108.99s, GCTime=0.63s.
LogInit: Display: Warning/Error Summary (Unique only)
LogInit: Display: -----------------------------------
LogInit: Display: LogNDIMedia: Error: Unable to load NDI runtime library: "../../../Engine/Plugins/Media/NDIMedia/Binaries/ThirdParty/Linux/libndi.so.6".
LogInit: Display: LogNDIMedia: Error: Unable to load "libndi.so.6" from the specified location(s).
LogInit: Display: LogCore: Warning: dlopen failed: libavahi-common.so.3: cannot open shared object file: No such file or directory
LogInit: Display: Failure - 2 error(s), 1 warning(s)
Execution of commandlet took:  6m 56s (416.34 seconds)
Exiting abnormally (error code: 1)
Editor terminated with exit code 1 while running DerivedDataCache for /home/ue4/UnrealEngine/Templates/TP_MotionDesignBP/TP_MotionDesignBP.uproject
AutomationTool executed for 0h 56m 28s
RunUAT ERROR: AutomationTool was unable to run successfully. Exited with code: 1
```
The shader compiler stats immediately above this excerpt reported `Shaders left to compile 0` and every asset in the template loaded and cached without error, so the DDC task itself did not fail, only the process's own exit code did.

**Investigation, whether this is a missing dependency.** Both hypotheses raised when this log was first seen, that `libndi.so.6` and `libavahi-common.so.3` were simply uninstalled packages needing an `apt-get install` fix, were checked directly against `EpicGames/UnrealEngine` branch `5.7` at this file's own pinned commit rather than assumed. `git ls-tree` against `Engine/Plugins/Media/NDIMedia/Binaries/ThirdParty/Linux/` in that commit lists only `libndi_licenses.txt`, confirming `libndi.so.6` itself was never vendored, not merely uninstalled, since NewTek and Vizrt's NDI SDK licence does not permit Epic to redistribute the compiled library in the public git tree, so no `apt-get` package can supply it. `libavahi-common.so.3`, by contrast, is a genuine Ubuntu package, `libavahi-common3`, simply absent from the Dockerfile's own library list, confirming that half of the original hypothesis.

**Why the DDC build treats a non-fatal library failure as a fatal build failure.** `Engine/Plugins/Media/NDIMedia/Source/NDIMedia/Private/NDIMediaModule.cpp`'s `FNDIMediaModule::StartupModule()` unconditionally calls `LoadModuleDependencies()`, which constructs an `FNDIMediaRuntimeLibrary` that attempts `FPlatformProcess::GetDllHandle()` against `libndi.so.6`, and both the constructor and `StartupModule()` itself log `UE_LOG(LogNDIMedia, Error, ...)` when the handle comes back null, exactly the two lines quoted above. `Engine/Source/Runtime/Launch/Private/LaunchEngineLoop.cpp:4161-4166` reads, verbatim:
```cpp
// Return an non-zero code if errors were logged and UseCommandletResultAsExitCode is false
if (!Commandlet->UseCommandletResultAsExitCode)
{
	if ((ErrorLevel == 0) && (GWarn->GetNumErrors() > 0))
	{
		ErrorLevel = 1;
	}
}
```
so any `UE_LOG(Category, Error, ...)` logged anywhere during a commandlet run, including during module startup before the commandlet's own code executes, overrides an otherwise-successful `ErrorLevel` of `0` to `1`, and that nonzero exit is what `RunUAT` reports as `Editor terminated with exit code 1`, aborting the `BuildDerivedDataCache` node and the Docker `RUN` step with it. The `libavahi-common.so.3` line is logged at `Warning`, not `Error`, so `GWarn->GetNumErrors()` does not count it, and it alone would not have failed the build.

**Root cause.** `NDIMedia.uplugin` declares `"EnabledByDefault": false`, so the module ordinarily loads only for projects that opt in, but `Templates/TP_MotionDesignBP/TP_MotionDesignBP.uproject`'s own `Plugins` array lists `{"Name": "NDIMedia", "Enabled": true, "SupportedTargetPlatforms": ["Win64"]}`. That `SupportedTargetPlatforms` entry is Epic's own signal that the plugin is intended for Win64 only in this project, since NDI's primary consumers are Windows-based broadcast production tools, but it does not gate editor module loading on Linux, since `NDIMedia.uplugin`'s own top-level `"SupportedTargetPlatforms": ["Win64", "Mac", "Linux"]` and each module's `"PlatformAllowList"` still include Linux, and the project-level per-plugin platform list is honoured by cook and package steps for packaged target platforms, not by the host editor's own plugin manager when it is simply running a commandlet on Linux. `Engine/Build/InstalledEngineFilters.xml`'s `ProjectsToBuildDDC` list was checked project by project, and `TP_MotionDesignBP` is the only one of the twenty listed whose `.uproject` enables `NDIMedia`, and `Engine/Plugins/VirtualProduction/Avalanche/Avalanche.uplugin` and its sibling `StormSync` plugins, also enabled by the same template, were checked and do not declare `NDIMedia` as a dependency of their own, so the plugin is reached only through the template's own explicit, and on this platform arguably mistaken, opt-in, not through any transitive requirement.

**Fix, delta 5 and delta 6.** `docker/unreal/Dockerfile` gained delta 5, `RUN sed -i '/"Name": "NDIMedia"/,+1 s/"Enabled": true/"Enabled": false/' .../Templates/TP_MotionDesignBP/TP_MotionDesignBP.uproject`, run against the freshly cloned source tree after delta 3's UBT bootstrap and before the Installed Build step, which disables exactly the one plugin entry in exactly the one template that needs it, leaving DDC generation for every other asset in that template, and for every other listed project, untouched. This is an addition, not a replacement of an upstream line, since upstream's Dockerfile never touched this file, so nothing is commented out in place for it. Delta 6 adds `libavahi-common3` to the existing X11 runtime library `apt-get install` layer, commented out in place per `CLAUDE.md` §2 the same way as deltas 3 and 4, closing the accompanying warning at negligible cost since the package is freely installable and carries no licence complication, unlike the NDI SDK.

**Alternatives considered and rejected.** Removing `Templates/TP_MotionDesignBP/TP_MotionDesignBP.uproject` from `ProjectsToBuildDDC` entirely was considered first, since it is a one-line change in a different file, but rejected because it discards DDC generation for the template's several hundred other assets to work around a single plugin, where patching the plugin entry directly costs the same one line and preserves everything else. Installing the actual NDI SDK's `libndi.so.6`, downloadable from NDI's own site after accepting its SDK licence, was considered and rejected, since it would bind this image to a second EULA beyond Epic's own, described in `context/unreal-engine-packaging.md` §11.2, for a broadcast video-over-IP protocol Project AirSim has no use for. Writing a stub `libndi.so.6` that satisfies the `dlopen` and `NDIlib_v5_load` symbol lookup without a functioning NDI runtime was considered and rejected as more code and more fragile across engine versions than a one-line `sed`, for no benefit this workspace needs. Raising `LogNDIMedia`'s verbosity to suppress the `Error` level globally was considered and rejected, since it would mask genuine `NDIMedia` errors in any other context that plugin runs in, for the sake of one template this workspace never uses.

**Verification.** Confirmed. A fourth `djinn init docker airsim2 force-all` attempt, after deltas 5 and 6, ran `BuildDerivedDataCache` to completion with no further mention of `NDIMedia` or `libavahi` anywhere in the log, and proceeded through `UnrealVersionSelector` registration into the final `minimal` image-assembly stage, `[minimal 14/17]` of `docker/unreal/Dockerfile`, well past this failure's own point. It then failed at a different, later point unrelated to either plugin, §7.4 below.

### 7.4 Fourth build attempt, host disk exhaustion in the final `minimal` stage

**Symptom.** With deltas 5 and 6 confirmed working, this same fourth attempt ran for over two hours through the `builder` stage's Installed Build and DDC generation, then failed twice in quick succession assembling the final `minimal` image:
```
#46 [minimal 14/17] RUN bash -c 'set -e; source /home/ue4/UnrealEngine/Engine/Extras/ushell/ushell.sh && exit 0' ...
#46 0.218 -- Creating a virtual environment in /home/ue4/.ushell/.working/python/3.11_11
#46 0.250 Error: [Errno 28] No space left on device: '/home/ue4/.ushell'
#46 0.253 !! ERROR: venv-based virtual environment creation failed
#46 0.253 Failed to provision Python

#48 [minimal 16/17] RUN EDITOR_TARGET=$(python3 /tmp/print-editor-target.py /home/ue4/UnrealEngine) && ./Engine/Build/BatchFiles/Linux/Build.sh "$EDITOR_TARGET" Linux Development -SkipBuild && ...
#48 0.316 Running command : dotnet Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll UnrealEditor Linux Development -SkipBuild
#48 0.572 Unhandled exception: IOException: The system cannot open the device or file specified. : 'Global\UnrealBuildTool_Mutex_XmlConfig_6dfc583763495d8f76cc17f3d67de59918c5f5d2'
#48 0.572    at System.Threading.Mutex.CreateMutexCore(Boolean initiallyOwned, String name, Boolean& createdNew)
#48 0.572    at UnrealBuildBase.GlobalSingleInstanceMutex..ctor(String mutexName, Boolean bWaitMutex) in /home/ue4/UnrealEngine/Engine/Source/Programs/Shared/EpicGames.Build/System/GlobalSingleInstanceMutex.cs:line 28
#48 0.585 Result: Failed (OtherCompilationError)
```
followed, outside Docker entirely, by `scripts/helpers/data.sh:18`'s own `save_state` trap failing on the host as `djinn` unwound after the build's exit code propagated: `typeset -p "$@" >"$statefile"` failing with `typeset: write error: No space left on device`, a plain shell redirect with no Docker or Unreal Engine code in the path at all.

**Investigation, whether this is genuinely disk exhaustion.** The user's own hypothesis was checked directly rather than assumed. The first error is unambiguous on its face, Python's own `venv` module surfacing `OSError` errno 28 verbatim as `No space left on device`. The second is not self-explanatory, an `IOException` reading "The system cannot open the device or file specified" naming a mutex, not a disk, so it was traced to source before accepting it as the same cause rather than a second, unrelated bug. `data.sh:18`'s failure is the decisive corroborating evidence, since it is a plain `bash` file redirect running on the host directly, outside any container or Docker storage driver, and it hit the identical OS-level `ENOSPC` independently, which rules out a container-scoped quota (a size-limited overlay filesystem or thin pool, for instance) as the explanation and confirms the underlying host disk itself, the one both Docker's data root and `$NRT_WS` sit on, was the resource that ran out.

**Why the mutex error is the same root cause, not a second bug.** `Engine/Source/Programs/Shared/EpicGames.Build/System/GlobalSingleInstanceMutex.cs:28` reads `GlobalMutex = new Mutex(true, mutexName, out bCreatedMutex);`, called from `UnrealBuildTool.cs:518` with a name built by `GetUniqueMutexForPath`, `$"Global\\{name}_{IoHash.Compute(uniquePath.ToUpperInvariant())}"`; the `Global\` prefix is Windows kernel-namespace syntax carried into the name string for cross-platform source parity, it has no special meaning to .NET's Unix mutex implementation. On Linux, CoreCLR's named `Mutex` is not a pure kernel primitive as it is on Windows, it is backed by a real shared-memory segment and lock file created under `/tmp/.dotnet-uid<uid>/`, specifically so that two unrelated processes naming the same string can rendezvous on the same object, and that file creation is exactly the operation that fails under `ENOSPC` when the filesystem backing `/tmp` is full. The confusing part is the exception text: .NET's Unix-to-managed exception translation for this code path does not carry a bespoke "No space left on device" message the way Python's `OSError` does, and instead falls back to a generic, Windows-flavoured `IOException` string, "The system cannot open the device or file specified", which is the exact same message reported in unrelated `dotnet/runtime` and `PowerShell/PSReadLine` issues under comparably resource-constrained conditions (full or restricted filesystems backing named-mutex creation on Linux and macOS), confirming this is a known, if unhelpfully worded, .NET pattern rather than something specific to Unreal Build Tool. `GlobalSingleInstanceMutex.cs` was read directly from `EpicGames/UnrealEngine` branch `5.7` at this file's own pinned commit to confirm the constructor call before accepting the mutex failure as disk-driven rather than investigating it as an independent Linux-support gap.

**Root cause.** Not a code defect in `docker/unreal/Dockerfile` or in Epic's own source, unlike deltas 3 through 6; the underlying host disk ran out of free space partway through the `minimal` stage, after the multi-hour `builder` stage had already completed and been committed as prior layers. `context/project-airsim-docker-build.md` §13 already recorded that a clean Installed Build with `WithDDC=true` needs roughly 200 GB, but that figure describes one successful build's own footprint, not the cumulative footprint of reaching one across several failed attempts against a Dockerfile that itself changed shape three times this session. Docker's BuildKit build cache retains every `RUN` layer up to each attempt's own point of failure, keyed by content hash, and editing a `RUN` line partway through the file, as deltas 3 through 6 each did in turn, invalidates the cache from that point forward without evicting the now-unreachable layers cached under the pre-edit hash, so four iterative attempts against an evolving multi-hour Dockerfile can leave several large, no-longer-referenced copies of the engine checkout and Installed Build tree on disk simultaneously, a cumulative footprint the single-build 200 GB figure was never meant to bound.

**Fix, no Dockerfile delta.** Unlike deltas 3 through 6, there is no source-level defect to patch, both failures are the filesystem correctly reporting that it is full, so the remedy is host-side disk hygiene rather than a code change to `docker/unreal/Dockerfile`. In order: confirm current usage with `df -h` on the actual Docker build host, not this development container, and `docker system df -v` for a breakdown between images, containers, local volumes and build cache; reclaim the build cache first, since it is the category three failed attempts against an edited Dockerfile most plausibly bloated, with `docker builder prune` (review interactively) or `docker builder prune --all --force` (unattended); if superseded images or containers from the prior 5.2 base or earlier partial 5.7 attempts remain, follow with `docker image prune -a` and `docker container prune`, reviewing output first since `-a` removes any image not referenced by a running container; confirm free space is comfortably above 200 GB, with headroom for this attempt's own layers to be cached in turn, before retrying `djinn init docker airsim2 force-all`. Going forward, since each Dockerfile-editing iteration adds a new multi-hour build's worth of large layers to the cache, pruning the builder cache between iterative attempts is now standard practice while deltas are still being found, rather than only once space is already exhausted.

**Verification.** Confirmed. The next attempt, after freeing host disk space, reached `[minimal 17/17]` and the final image tag step with no `ENOSPC` or `IOException` anywhere in the log, and the image built successfully end to end.

### 7.5 Vulkan device creation failure at runtime, `VK_KHR_compute_shader_derivatives` gap and ICD manifest `api_version` gap

**Symptom.** With the image built (§7.4) and Project AirSim's own SimLibs building and packaging cleanly against it, `djinn start sitl2` failed the packaged `StonePineForest` client's own Vulkan RHI initialization, every plugin and pak file already mounted correctly:
```
LogVulkanRHI: Starting Vulkan Profile check for VP_UE_Vulkan_SM6:
LogVulkanRHI: Warning: None of the 1 devices meet all the criteria!
LogVulkanRHI: Vulkan Profile check complete.
LogRHI: Display: Skipping SF_VULKAN_SM6...
Message dialog closed, result: Ok, title: Message, text: Vulkan device could not be created at the project's supported feature levels (see log for details).
LogCore: FUnixPlatformMisc::RequestExit(bForce=true, ReturnCode=1, CallSite=<NoCallSiteInfo>)
```
This was not a Docker build failure and needed no further `djinn init docker airsim2` attempt; the image was already correct, the failure was in the packaged client's own startup on the host, `server1`, GPU an NVIDIA RTX 4000 SFF Ada Generation on driver `550.163.01` at the time this was first seen.

**Investigation, part one, the missing Vulkan extension.** `Engine/Source/Runtime/VulkanRHI/Private/VulkanRHI.cpp`, read directly from `EpicGames/UnrealEngine` branch `5.7` at this file's own pinned commit, showed `LaunchEngineLoop` validating the GPU against a formal, versioned Khronos Vulkan Profiles specification, `VP_UE_Vulkan_SM6` (`Engine/Source/ThirdParty/Vulkan/profiles/include/vulkan_profiles_ue.h`), naming fifteen required device extensions, before creating any device at all. A full, non-summary `vulkaninfo` dump of the NVIDIA GPU's actual extension list, checked term by term against that requirement, found fourteen of fifteen present; the fifteenth, `VK_KHR_compute_shader_derivatives`, was absent, the driver instead carrying only its vendor-specific predecessor, `VK_NV_compute_shader_derivatives`. A web search corroborated the timeline, `VK_KHR_compute_shader_derivatives` was ratified into the Vulkan specification only at version 1.3.295, which postdates driver `550.163.01`'s own release, so the driver could not expose an extension name that did not exist when it shipped. The full account, including the complete extension diff and the rejected alternative of `-SkipVulkanProfileCheck`, is in `context/project-airsim-docker-build.md` §16.

**Fix, part one.** The host NVIDIA driver was upgraded to `580.173.02`, following the runbook in `plans/update-nvidia-driver.md`, confirmed by re-running `vulkaninfo` and finding `VK_KHR_compute_shader_derivatives` newly present alongside all fourteen extensions that were already there. This is a host system change, not a `docker/unreal/Dockerfile` delta.

**Investigation, part two, the packaged client still failed identically.** After the driver upgrade, `djinn start sitl2` produced the exact same warning, `None of the 1 devices meet all the criteria!`, at the exact same point, even though `vulkaninfo` in the same container now correctly reported both the NVIDIA device (fully compliant) and Mesa's `llvmpipe` software device. Restricting the loader to only the NVIDIA ICD manifest via `VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json` made the failure worse, a hard `vpCreateInstance(...) failed, VkResult=-9 ... VK_ERROR_INCOMPATIBLE_DRIVER` crash rather than the graceful warning, ruling out the simplest theory, that NVIDIA was merely deprioritised among several candidates. Removing the manifest's `api_version` field entirely, reasoning that modern Vulkan loaders treat it as optional and query the real driver directly, changed nothing, the identical graceful warning persisted, disproving that theory in turn. `VK_LOADER_DEBUG=all` against the actual packaged client launch settled it directly: the active loader is confirmed as UE's own bundled copy, `Engine/Binaries/ThirdParty/Vulkan/Linux`, distinct from the system loader also detected and logged (`1.3.204`) and then explicitly discarded per `LogVulkanRHI: Display: Using included Vulkan loader.`, and that loader's manifest parser reads, verbatim, `WARNING | DRIVER: loader_parse_icd_manifest: ICD JSON /etc/vulkan/icd.d/nvidia_icd.json does not have an 'api_version' field. Skipping ICD JSON.` NVIDIA's ICD is rejected wholesale at manifest-parsing time whenever the field is absent, before any `dlopen` of `libGLX_nvidia.so.0` is attempted. With NVIDIA excluded, the same trace shows exactly what fills the gap: `VirtIO` fails `vkCreateInstance` outright (no virtual GPU present), `Intel`, `Intel HASVK` and `RADV` are each removed by the loader's own device-enumeration step for reporting zero physical devices, correctly, since none of that hardware exists on this NVIDIA-only host, and Mesa's `llvmpipe` software rasterizer is the sole survivor, named directly in the trace. That is, and had always been, the `1 devices` the warning names, confirming the very first hypothesis raised when this investigation began and then set aside as "immaterial to the conclusion", which was a mistake worth recording, since it was in fact the entire mechanism.

**Root cause, part two.** `docker/unreal/Dockerfile`'s pre-existing, upstream-inherited generation step derives `nvidia_icd.json`'s `api_version` field from `dpkg -s libvulkan1 | grep -oP 'Version: [0-9|\.]+'`, the SYSTEM Vulkan loader package's own instance version, `1.3.204` on this Ubuntu 22.04 base, unrelated to any GPU driver's actual capability, a fact obscured until now because the two numbers happened to resemble each other against the pre-upgrade driver. This value had always technically satisfied the field's mere presence, which is why the defect was invisible through the entire 5.2 to 5.7 migration and the driver upgrade, and became visible only once the field was experimentally removed while chasing the (real, but by itself insufficient) extension gap of part one.

**Fix, part two, delta 7.** `docker/unreal/Dockerfile`'s `nvidia_icd.json` generation now hardcodes `api_version` to `1.4.312`, NVIDIA driver `580.173.02`'s own real `apiVersion` per `vulkaninfo`, confirmed by a live run to admit the real NVIDIA device and pass `VP_UE_Vulkan_SM6` outright. `apt-get install libvulkan1` is retained, since `vulkaninfo` and other system tooling still need the system loader present; only the version-string derivation from that package is dropped. Superseded upstream logic is commented out in place per `CLAUDE.md` §2. Deriving this value correctly at image build time is not possible by any method, since the NVIDIA Container Toolkit mounts the host's actual driver only at container start, never during the build, so the hardcoded value is a deliberate choice made on the explicit understanding, stated by the workspace owner, that this image is used with driver 580 only, not an oversight; a future driver change would force this value to be revisited only if a future engine's own Vulkan profile ever demands more than `1.4.312`, since the field acts as a version floor the loader gates on rather than an exact-match requirement.

**Alternatives considered and rejected.** Regenerating the manifest at container start from the live driver, via an entrypoint script querying `vulkaninfo` or `nvidia-smi`, was considered and rejected as unnecessary complexity for a workspace committed to one driver branch; it remains the right design if that commitment ever changes. Declaring the field with a maximally permissive placeholder value, rather than the real driver's own reported number, was considered and rejected as less honest for no benefit, since the field's role is to state a real capability ceiling, not merely to satisfy a presence check.

**Verification.** Confirmed. The packaged `StonePineForest` client, launched with the corrected manifest in place, passed `Vulkan Profile check complete.` with no criteria warning and reached simulation. Full account in `context/project-airsim-docker-build.md` §17 and `context/unreal-engine-packaging.md` §11.2.
