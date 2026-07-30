# SITL workspace migration — baked-image → mounted `ardu_ws` / `sitl_ws`

Durable record of the migration that moves the ArduPilot and AirSim ROS 2 workspaces out of the `nrt:$VERSION` Docker image and into workspace-root subdirectories mounted at `/ws`. Investigation date: 2026-07-24. Full change-record: [`plans/sitl-workspace-mount-migration.md`](../plans/sitl-workspace-mount-migration.md).

## The model

`scripts/start.sh:25` bind-mounts `$NRT_WS` → `/ws` (`-v $dir:/ws/`). Therefore any workspace subdirectory is visible in the container with **no extra `-v` flag**. The migration relocates the two SITL workspaces from image-internal top-level paths to workspace subdirectories:

- `/ardu_ws` → `/ws/ardu_ws` (= `$NRT_WS/ardu_ws`). Sources are submodules under `ardu_ws/src/`: `ardupilot` (branch `master`), `micro_ros_agent` (`humble`), `micro_ros_msgs` (`humble`) — the three repos formerly imported via `docker/ardupilot/ros2.repos` + `vcs import` (both now removed). Built by `ardu_ws/scripts/build.sh` (`colcon build`, cwd `/ws/ardu_ws`).
- `/airsim_ws` → `/ws/sitl_ws` (= `$NRT_WS/sitl_ws`). Source is the **full** Cosys-AirSim submodule at `sitl_ws/src/ue5/AirSim` (was `envs/ue5/AirSim`). Built by `sitl_ws/scripts/build.sh`.

Consequence: editing ArduPilot or the AirSim wrapper needs only a `djinn build …` recompile, never an image rebuild.

`djinn` wiring (already present): `build ardupilot-sitl` (`/ws/ardu_ws/scripts/build.sh`), `build airsim-sitl` (`/ws/sitl_ws/scripts/build.sh`), `build sitl` (both), `up sitl_bridge` (spawn + both builds), `start sitl` (uses `sitl_ws/scripts/run_airsim.sh` + `ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh`).

## Gotchas / non-obvious facts (verified 2026-07-24)

1. **`ros_entrypoint.sh` is `set -e` and baked into the image.** It sourced `/ardu_ws` + `/airsim_ws` install trees unconditionally → with the relocation those paths vanish and the entrypoint aborts before `exec "$@"`, so the container exits on start. The install trees also don't exist until the container-start build runs, so the sources **must be existence-guarded** (`[ -f … ] && source …`) at the new `/ws/...` paths. Fixing it requires an image rebuild.

2. **AirSim colcon discovery over-reach (the important one).** The *old* `/airsim_ws` was populated by `setup_airsim_ros_pkgs_for_docker_build` (now `# DEPRECATED` in `scripts/helpers/sitl.sh`), which copied only a **curated subset** of AirSim — it included `ros2/` but **not** the ROS 1 tree `ros/python_ws/src/{airsimros,fm_msgs}`. The full mount exposes that ROS 1 (catkin) tree plus stale `ros2/{build,install,log}` artifacts. An unscoped `colcon build` / `rosdep --from-paths src` at `/ws/sitl_ws` will now try to build the ROS 1 packages / hit duplicate-package errors. **Scope both to `src/ue5/AirSim/ros2/src`** (`colcon build --base-paths …`). `AIRSIM_ROOT` in `ros2/src/airsim_ros_pkgs/CMakeLists.txt:28` is relative (`${CMAKE_CURRENT_SOURCE_DIR}/../../../`), so the ROS 2 packages themselves build fine at the new absolute path.

3. **Absolute-path debt.** Every consumer of the old paths must move `/ardu_ws`→`/ws/ardu_ws`, `/airsim_ws`→`/ws/sitl_ws`: `scripts/helpers/exec.sh:25,30,35` (`iexec_sitl`/`iexec_sitl2`/`iexec_ros_ap`), `scripts/helpers/docker.sh:39` (AirSim spawn → `sitl_ws/scripts/start.sh` + `sitl_ws/src/ue5/AirSim/Unreal/Environments`), `scripts/build_ros_packages.sh:6-7`, `sitl_ws/scripts/build.sh:5,35`. Same debt exists inside the `ros_ws` submodule (`ros_ws/build_ros_packages.sh:6-7`) — separate repo, follow-up there.

4. `.gitmodules` AirSim stanza **has been renamed** from `[submodule "envs/ue5/AirSim"]` to `[submodule "sitl_ws/src/ue5/AirSim"]`. Because this submodule keeps an **embedded** `.git` directory (in-tree at `sitl_ws/src/ue5/AirSim/.git`, not under the superproject's `.git/modules/`), `git submodule sync` alone did **not** update `.git/config`; the stale `submodule.envs/ue5/AirSim.*` section had to be renamed explicitly with `git config -f .git/config --rename-section submodule.envs/ue5/AirSim submodule.sitl_ws/src/ue5/AirSim`. After that, `git submodule status` returns to `+a552dd6c…` (initialized). If a future rename touches a submodule that *does* live under `.git/modules/`, that directory must be moved too.

5. `build_airsim_docker_image` (`scripts/helpers/sitl.sh`) must `cd` to `sitl_ws/src/ue5/AirSim/docker/` — `build_airsim_image.py` lives under `docker/`, not the AirSim root. (A migration edit briefly dropped the `/docker/` segment; corrected.)

6. **Every rosdep-resolved runtime dependency must be baked into the image, not installed at build time (added 2026-07-25).** This follows directly from the mount model above and is a general rule, not a one-off. `scripts/start.sh:25` runs containers with `--rm`, so anything a build script `apt-get`s (e.g. `ardu_ws/scripts/build.sh`'s and `sitl_ws/scripts/build.sh`'s `rosdep install`) lives only in that container's writable layer and is destroyed on stop — while the mounted `install/` tree **survives**. The next container therefore runs prebuilt binaries whose shared libraries no longer exist. The observed failure was a fatal `dlopen` of `libgeographic_msgs__rosidl_typesupport_fastrtps_cpp.so`, pulled in because `sitl_ws/src/ue5/AirSim/ros2/src/airsim_interfaces` depends on `geographic_msgs`. The fix is to add the packages to `docker/ardupilot/Dockerfile` so they are part of the image; `rosdep install` at build time then becomes a no-op rather than the only thing making the workspace runnable.

   **Auditing the closure has a trap:** a misspelled `<depend>` key is *invisible* to `rosdep install --simulate` — rosdep cannot resolve it, so it silently under-reports rather than erroring. `ros_ws/src/sensors/package.xml` carried `lifecyle_msgs` and `rosbag2_trasport` (both fixed 2026-07-25) and built only because the correct packages happened to already be in the image. **Spell-check every `package.xml` before trusting an audit.**

## Final implemented state (2026-07-24)

All migration fixes are applied: `sitl_ws/scripts/build.sh` builds only `--base-paths src/ue5/AirSim/ros2/src`; `ardu_ws/scripts/build.sh` runs `rosdep install --from-paths src` before `colcon`; `docker/ardupilot/ros_entrypoint.sh` existence-guards the workspace overlays (`[ -f … ] && source …`) so a fresh container starts before the first build; the deprecated `setup_airsim_ros_pkgs_for_docker_build` source paths and the legacy `envs/scripts/*` launch scripts were path-corrected. The full change catalogue lives in [`plans/sitl-workspace-mount-migration.md`](../plans/sitl-workspace-mount-migration.md); each djinn workflow and its test strategy is in [djinn-workflows.md](djinn-workflows.md).

## Cross-refs

- [`plans/sitl-workspace-mount-migration.md`](../plans/sitl-workspace-mount-migration.md) — the clean change-record (motivation, changes made, usage, validation strategy).
- [airsim-docker-build.md](airsim-docker-build.md) — the UE/AirSim *image* build (`djinn init docker airsim`); path refs there predate this move (`envs/ue5/AirSim` → `sitl_ws/src/ue5/AirSim`).
- [airsim.md](airsim.md), [airsim-sitl-gps-issue.md](airsim-sitl-gps-issue.md) — AirSim/SITL runtime architecture.
- [djinn-cli.md](djinn-cli.md) — `djinn` subcommand reference.
