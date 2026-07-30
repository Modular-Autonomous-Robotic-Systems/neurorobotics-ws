# Migration — Mounting `ardu_ws` and `sitl_ws` instead of baking them into the NRT image

This document records the migration that moves the ArduPilot and AirSim ROS 2 workspaces out of the `shandilya1998/nrt:$VERSION` Docker image and into workspace-root directories that are mounted into the container and compiled at container-start. It states the motivation and architecture, then lists every change made, the build/run usage, and the validation strategy.

---

## 1. Overview

### 1.1 Motivation

Previously the `/ardu_ws` (ArduPilot ROS 2 / DDS bridge) and `/airsim_ws` (Cosys-AirSim ROS 2 wrapper) workspaces were baked into the `nrt` image at build time via `docker/ardupilot/Dockerfile` (`vcs import` of `ros2.repos`, then `COPY`/`RUN` of the build scripts). Any change to either workspace forced a full multi-architecture image rebuild — a turnaround of tens of minutes to hours — which made SITL and ArduPilot configuration bugs slow to iterate on.

The migration stops baking these workspaces into the image. They now live under the workspace root (`ardu_ws/`, `sitl_ws/`), their sources are git submodules, and they are compiled at container-start. Edits to ArduPilot, the micro-ROS bridge, or the AirSim ROS 2 wrapper propagate into the container instantly (they are mounted, not copied) and require only a `djinn build …` recompile — never an image rebuild.

### 1.2 Why no additional Docker mount is required

The runtime spawner `scripts/start.sh` already bind-mounts the entire workspace root into the container: `docker run … -v $NRT_WS:/ws …`. Because `$NRT_WS` is mounted at `/ws`, any subdirectory of the workspace root is automatically visible inside the container. Relocating the workspaces from image-internal top-level paths (`/ardu_ws`, `/airsim_ws`) to workspace subdirectories (`/ws/ardu_ws`, `/ws/sitl_ws`) is therefore a pure path relocation with no new `-v` flag.

### 1.3 Before vs. after

| Aspect | Before (baked) | After (mounted) |
|---|---|---|
| ArduPilot workspace | `/ardu_ws` in image; sources via `vcs import` of `docker/ardupilot/ros2.repos`; built by `COPY build.sh && RUN build.sh` | `/ws/ardu_ws` = `$NRT_WS/ardu_ws`; sources are git submodules under `ardu_ws/src/`; built at container-start by `ardu_ws/scripts/build.sh` |
| AirSim ROS 2 workspace | `/airsim_ws` in image; a curated subset of AirSim copied in; built by `COPY build_airsim.sh && RUN build.sh` | `/ws/sitl_ws` = `$NRT_WS/sitl_ws`; full Cosys-AirSim submodule at `sitl_ws/src/ue5/AirSim`; built at container-start by `sitl_ws/scripts/build.sh` |
| UE5 environments | `envs/ue5/AirSim` | `sitl_ws/src/ue5/AirSim` (same submodule, relocated); UE4 assets stay at `envs/ue4/` |
| Image rebuild on workspace change | Required | Not required (recompile only) |

### 1.4 New functional features (`djinn`)

- `djinn build ardupilot-sitl` — build the ArduPilot SITL/DDS workspace at `/ws/ardu_ws`.
- `djinn build airsim-sitl` — build the AirSim ROS 2 workspace at `/ws/sitl_ws`.
- `djinn build sitl` — build both.
- `djinn up sitl_bridge` — spawn the bridge container and build both workspaces.
- `djinn start sitl` — orchestrate AirSim + the ArduPilot-AirSim-ROS bridge + QGroundControl using the relocated launch scripts.

---

## 2. Workspace layout

- **`ardu_ws/`** — ArduPilot SITL + micro-ROS DDS bridge.
  - `src/` — git submodules `ardupilot` (branch `master`; ROS 2 packages `ardupilot_sitl`, `ardupilot_msgs`, `ardupilot_dds_tests` under `Tools/ros2/`), `micro_ros_agent` (branch `humble`), `micro_ros_msgs` (branch `humble`). These replace the deleted `docker/ardupilot/ros2.repos`.
  - `scripts/build.sh` — `rosdep install` + `colcon build`.
  - `scripts/run_ardupilot_airsim_ros_sitl.sh` — launches the SITL bridge.
- **`sitl_ws/`** — Cosys-AirSim ROS 2 wrapper + Unreal Engine environments.
  - `src/ue5/AirSim` — the full Cosys-AirSim fork as a git submodule. ROS 2 packages under `ros2/src/`; a ROS 1 (catkin) tree under `ros/`.
  - `scripts/build.sh` — downloads rpclib/Eigen, then builds only the ROS 2 subtree.
  - `scripts/start.sh`, `scripts/run_airsim.sh` — spawn the AirSim container and launch a UE environment.

---

## 3. Changes made

### 3.1 Docker image (`docker/ardupilot/`)

- **`Dockerfile`** — removed all workspace baking: `WORKDIR /ardu_ws/src`, `COPY ros2.repos`, `vcs import`, `COPY build.sh && RUN build.sh`, `ADD ./airsim_ws`, and `COPY build_airsim.sh && RUN build.sh`. The stage now installs only the SITL toolchain/dependencies (ARM GCC, Micro-XRCE-DDS generator, MAVProxy, Python packages). Builds `shandilya1998/nrt:0.1.0`.
- **`ros2.repos`** — deleted (superseded by submodules).
- **`ros_entrypoint.sh`** — sources the workspace overlays from the new paths (`/ws/ardu_ws`, `/ws/sitl_ws`) and **existence-guards** them: `[ -f /ws/ardu_ws/install/setup.bash ] && source …`. This is required because the entrypoint runs on every container start (under `set -e`) while the install trees are created only by the later container-start build; without the guard the container would exit before the build could run.

### 3.2 Submodules (`.gitmodules`)

- Added `ardu_ws/src/ardupilot`, `ardu_ws/src/micro_ros_agent`, `ardu_ws/src/micro_ros_msgs`.
- Relocated the AirSim submodule path to `sitl_ws/src/ue5/AirSim` and renamed its stanza to `[submodule "sitl_ws/src/ue5/AirSim"]`. Because this submodule keeps an embedded `.git` directory, the stale `.git/config` section was renamed explicitly (`git config --rename-section submodule.envs/ue5/AirSim submodule.sitl_ws/src/ue5/AirSim`) so `git submodule status` reports it as initialized.

### 3.3 Build scripts

- **`ardu_ws/scripts/build.sh`** (moved from `docker/ardupilot/build.sh`) — `cd /ws/ardu_ws`; added `rosdep install --from-paths src -y --ignore-src --rosdistro humble` before `colcon build --cmake-args -DBUILD_TESTING=ON`. `ardu_ws/src` contains only ROS 2 packages, so `--from-paths src` resolves exactly the ROS 2 dependency set.
- **`sitl_ws/scripts/build.sh`** (moved from `docker/ardupilot/build_airsim.sh`) — `cd /ws/sitl_ws/src/ue5/AirSim` for the rpclib/Eigen download; then `cd /ws/sitl_ws` and scope discovery to the ROS 2 subtree: `rosdep install --from-paths src/ue5/AirSim/ros2/src …` and `colcon build --base-paths src/ue5/AirSim/ros2/src --cmake-args -DCMAKE_BUILD_TYPE=Release`. Scoping is essential: the full AirSim submodule also carries a ROS 1 (catkin) tree under `ros/` and stale colcon artifacts under `ros2/{build,install,log}` that must not be discovered. The unconditional `rm -rf build install log` was removed to keep incremental builds.

### 3.4 `djinn` orchestration

- Added `build ardupilot-sitl`, `build airsim-sitl`, `build sitl` (each spawns `sitl_bridge_container` and runs the corresponding build script(s)).
- `up sitl_bridge` spawns the bridge container and builds both workspaces.
- `build ardupilot <board> <config>` runs `waf` against `/ws/ardu_ws/src/ardupilot`.
- `start sitl` launches AirSim (`sitl_ws/scripts/run_airsim.sh`), the SITL bridge (`ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh`), and QGroundControl.

### 3.5 Helper libraries (`scripts/helpers/`)

- **`exec.sh`** — `iexec_sitl`, `iexec_sitl2`, `iexec_ros_ap` source the workspace install trees from `/ws/ardu_ws/install` and `/ws/sitl_ws/install`.
- **`docker.sh`** — `spawn_container_if_needed` sources `$NRT_WS/sitl_ws/scripts/start.sh` with `$NRT_WS/sitl_ws/src/ue5/AirSim/Unreal/Environments` for `airsim_container`.
- **`sitl.sh`** — `build_airsim_docker_image` `cd`s to `sitl_ws/src/ue5/AirSim/docker/` (where `build_airsim_image.py` lives). `setup_airsim_ros_pkgs_for_docker_build` is retained but marked deprecated and its AirSim source paths updated to `/ws/sitl_ws/src/ue5/AirSim/…` (removal deferred to a later cleanup).

### 3.6 Other scripts

- **`scripts/build_ros_packages.sh`** — sources the workspace overlays from `/ws/ardu_ws/install` and `/ws/sitl_ws/install`.
- **`envs/scripts/run_sitl_ardupilot_bridge.sh`, `envs/scripts/run_airsim_ros_pkgs.sh`** — legacy launch scripts path-corrected to the `/ws/ardu_ws` and `/ws/sitl_ws` layout.

### 3.7 Documentation & context

- **`ARCHITECTURE.md`** — revised the `docker/ardupilot` description (toolchain/deps only, workspaces mounted and built at container-start); synced the image tag to `0.1.0`; added a new **Workspaces** section (`ros_ws`, `ardu_ws`, `sitl_ws`) with structure and script descriptions; added the new `build` subjects; fixed the Miscellaneous Unreal-Engine path.
- **`README.md`** — added a **SITL (ArduPilot + AirSim)** section with the submodule/init/build/run commands.
- **`CLAUDE.md`** — updated the AirSim submodule path; added a directive that every `djinn` workflow must be documented in `context/djinn-workflows.md` with its test strategy.
- **`context/`** — `sitl-workspace-migration.md` (migration model, gotchas, final state), `djinn-workflows.md` (per-workflow catalogue with test strategy), index rows in `context/README.md`; refreshed `djinn-cli.md` (new build subjects, `up sitl_bridge`, `VERSION=0.1.0`), `airsim-docker-build.md` and `airsim.md` (AirSim path references).

---

## 4. Usage

```
git submodule update --init --recursive        # populate ardu_ws/src/*, sitl_ws/src/ue5/AirSim
djinn init docker nrt                           # build/rebuild nrt:0.1.0 (guarded entrypoint)
djinn up sitl_bridge                            # spawn bridge; build ardu_ws then sitl_ws
djinn init docker airsim                        # build the UE/AirSim simulation image (if needed)
djinn start sitl                                # AirSim + ArduPilot-AirSim-ROS bridge + QGC
```

Build workspaces individually with `djinn build ardupilot-sitl`, `djinn build airsim-sitl`, or `djinn build sitl`. Run SLAM against the simulation with `djinn start sitl orbslam3` or `djinn start sitl basalt`.

---

## 5. Validation strategy

Validation is performed manually (it cannot run in the development container). Each check maps to a change area; the full per-workflow catalogue with call chains and assertions is in `context/djinn-workflows.md`.

1. **Container start:** `docker run --rm shandilya1998/nrt:0.1.0 echo ok` prints `ok`, exit 0; `djinn up sitl_bridge` leaves `sitl_bridge_container` running (`djinn ps`).
2. **ArduPilot workspace:** `djinn build ardupilot-sitl` → `rosdep` resolves, `colcon` builds; `ros2 pkg prefix ardupilot_sitl` succeeds; `/ws/ardu_ws/install/setup.bash` exists.
3. **AirSim workspace:** `djinn build airsim-sitl` builds only `airsim_ros_pkgs`/`airsim_interfaces` (never `airsimros`/`fm_msgs`); `ros2 pkg prefix airsim_ros_pkgs` succeeds; `/ws/sitl_ws/install/setup.bash` exists.
4. **Combined:** `djinn build sitl` builds both; `djinn up sitl_bridge` is idempotent.
5. **SITL launch:** `djinn start sitl` opens the AirSim, SITL-bridge, and QGC terminals; the bridge runs `ros2 launch controllers sitl.launch.py` with all overlays sourced and no missing-file errors.
6. **AirSim spawn:** `djinn up airsim` spawns `airsim_container` from `sitl_ws/src/ue5/AirSim/Unreal/Environments`.
7. **AirSim image build:** `djinn init docker airsim` finds `build_airsim_image.py` under `sitl_ws/src/ue5/AirSim/docker/` and produces `nrt_airsim:0.0.1`.
8. **Regressions:** `djinn build nrt` still builds `ros_ws` with `ardupilot_msgs`/`airsim_interfaces` visible; `djinn build ardupilot SpeedyBeeF405WING plane` still compiles firmware from `/ws/ardu_ws/src/ardupilot`.

---

## 6. Follow-ups (out of scope here)

- Remove the deprecated `setup_airsim_ros_pkgs_for_docker_build`, `build_sitl_docker_image`, and `start_sitl_container` helpers and their commented call sites in `djinn`.
- Update the identical stale workspace paths inside the `ros_ws` submodule (`ros_ws/build_ros_packages.sh`).
- Sync the `djinn init` default `VERSION=0.0.9` (hard-coded at `djinn:44`) to the current `0.1.0`.
