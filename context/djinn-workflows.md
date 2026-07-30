# `djinn` workflow & test catalogue

Durable, AI-facing catalogue of every `djinn` workflow: its invocation, the call chain (helper functions + scripts) it drives, the side effects (containers/images/files) it produces, the expected outcome, and a validation/test strategy. It exists so the (currently manual) validation of these workflows can be **automated later** without re-deriving intent from source. **Maintenance rule (also in `CLAUDE.md §3`): every new or changed `djinn` workflow MUST be added/updated here in the same change.** Seeded 2026-07-24 from the SITL workspace-mounting migration — see [sitl-workspace-migration.md](sitl-workspace-migration.md) and [djinn-cli.md](djinn-cli.md).

Grammar: `djinn <verb> <subject> <args>`. Helpers are sourced from `scripts/helpers/{data,exec,docker,sitl}.sh`. Runtime containers mount `$NRT_WS` → `/ws` (`scripts/start.sh`). Current image `VERSION=0.1.0` (`.djinn_config`).

## Legend for "Test strategy"
Because these cannot run in the dev container, each entry lists a **precondition**, an **action**, and an **observable assertion** an automated harness can check (exit code, file existence, `ros2 pkg prefix`, `djinn ps`, log grep).

---

## SITL workflows (primary focus of the migration)

### `djinn build ardupilot-sitl`
- **Call chain:** `spawn_container_if_needed sitl_bridge_container nrt:$VERSION` → `iexec_ros sitl_bridge_container "/ws/ardu_ws/scripts/build.sh"`.
- **Script:** `ardu_ws/scripts/build.sh` → `source /opt/ros/humble/setup.bash`; `cd /ws/ardu_ws`; `rosdep install --from-paths src -y --ignore-src --rosdistro humble`; `colcon build --cmake-args -DBUILD_TESTING=ON`.
- **Sources:** submodules `ardu_ws/src/{ardupilot,micro_ros_agent,micro_ros_msgs}` (5 ROS 2 packages; ardupilot's are under `Tools/ros2/`).
- **Side effects:** creates `/ws/ardu_ws/{build,install,log}`.
- **Expected:** colcon builds all packages; `/ws/ardu_ws/install/setup.bash` exists.
- **Test:** *precond* submodules populated + `sitl_bridge_container` runnable → *action* run command → *assert* exit 0; `docker exec sitl_bridge_container bash -lc 'source /ws/ardu_ws/install/setup.bash && ros2 pkg prefix ardupilot_sitl'` prints a path.

### `djinn build airsim-sitl`
- **Call chain:** `spawn_container_if_needed sitl_bridge_container` → `iexec_ros sitl_bridge_container "/ws/sitl_ws/scripts/build.sh"`.
- **Script:** `sitl_ws/scripts/build.sh` → `cd /ws/sitl_ws/src/ue5/AirSim`; download rpclib (`external/rpclib`) + Eigen (`AirLib/deps/eigen3`) if absent; `cd /ws/sitl_ws`; `rosdep install --from-paths src/ue5/AirSim/ros2/src …`; `colcon build --base-paths src/ue5/AirSim/ros2/src --cmake-args -DCMAKE_BUILD_TYPE=Release`.
- **Critical scoping:** discovery is restricted to `src/ue5/AirSim/ros2/src` so the AirSim submodule's ROS 1 (catkin) tree under `ros/` and its stale `ros2/{build,install,log}` artifacts are **not** discovered (would otherwise break/duplicate). See [sitl-workspace-migration.md](sitl-workspace-migration.md) gotcha 2.
- **Side effects:** creates `/ws/sitl_ws/{build,install,log}`; downloads into the AirSim submodule tree.
- **Expected:** builds `airsim_ros_pkgs` + `airsim_interfaces` only; `/ws/sitl_ws/install/setup.bash` exists.
- **Test:** *assert* build log does **not** mention `airsimros`/`fm_msgs`; `ros2 pkg prefix airsim_ros_pkgs` succeeds; `/ws/sitl_ws/install/setup.bash` present.

### `djinn build sitl`
- **Call chain:** `spawn_container_if_needed sitl_bridge_container` → both build scripts above, in order (ardu_ws then sitl_ws).
- **Test:** both assertions from the two entries above hold.

### `djinn up sitl_bridge`
- **Call chain:** `spawn_container_if_needed sitl_bridge_container nrt:$VERSION` → `iexec_ros … /ws/ardu_ws/scripts/build.sh` → `iexec_ros … /ws/sitl_ws/scripts/build.sh`.
- **Entry point dependency:** the image entrypoint `docker/ardupilot/ros_entrypoint.sh` **must** existence-guard the workspace overlays; otherwise the container exits on spawn before the builds run (install trees don't exist yet). See gotcha 1.
- **Expected:** `sitl_bridge_container` is running and both workspaces are built.
- **Test:** *assert* `djinn ps` lists `sitl_bridge_container`; both `install/setup.bash` files exist.

### `djinn start sitl [orbslam3|basalt]`
- **Bare `start sitl`:** `start_simulation nature` (spawns `airsim_container`) → `spawn_container_if_needed sitl_bridge_container` → three `gnome-terminal`s: AirSim (`sitl_ws/scripts/run_airsim.sh`), SITL bridge (`ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh` → `iexec_sitl sitl_bridge_container "ros2 launch controllers sitl.launch.py use-sim-time:=True"`), and QGroundControl (`ext/QGroundControl.AppImage`).
  - **`use-sim-time:=True` added 2026-07-28.** It makes `airsim_ros_pkgs` publish its simulator clock, remaps `/airsim_node/clock` onto the global `/clock` with a scoped `SetRemap`, binds ArduPilot's `--use_sim_time` to it, and sets the `use_sim_time` parameter on `managed_logger_node`. Without it AirSim and ArduPilot stamp from rate-locked but origin-independent clocks, several seconds apart, and VISLAM cannot pair a frame with an inertial sample. The argument defaults to `False` everywhere it is declared, so dropping it from this invocation restores the pre-2026-07-28 behaviour exactly, which is the intended way to reproduce a historical run. See [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md) and [`/ws/plans/sitl-clock-synchronisation.md`](../plans/sitl-clock-synchronisation.md).
- **`orbslam3` / `basalt`:** `spawn_container_if_needed nrt_container` → `iexec_sitl2 nrt_container "ros2 launch …"` (the SLAM stack against AirSim topics).
- **`basalt` (`djinn:267-283`):** launches `controllers basalt_slam_test.launch.py` with `log-level`, `ap_status_topic_name`, `camera-topic`, `calibration-file-path`, `configuration-file-path:=…/sitl_config_vo.json` (a VIO config despite the `_vo` name), `slam-type:=VISLAM`, `use-sim-time:=True` and `imu-topic:=/ap/imu/experimental/data`. **This workflow starts SLAM only** — the simulator, ffmpeg encoder and managed recorder come from `djinn start sitl`, which must already be running.
  - **`use-sim-time:=True` added 2026-07-28.** It sets `use_sim_time` on `basalt_slam_node` only, forwarded through `basalt_slam.launch.py`, so the compute node's own output stamps land in the same domain as the camera and inertial stamps it consumes. `basalt_controller` deliberately does **not** get it, because its lifecycle-transition watchdog reads `self.get_clock().now()` and a stalled `/clock` would leave a failed transition latched in flight forever. This argument must be paired with `use-sim-time:=True` on `djinn start sitl`, since nothing publishes `/clock` otherwise and a sim-time node with no clock reports time zero. Note the spelling: no space after `:=`, `ros2 launch` splits on whitespace first, so `use-sim-time:= True` is two tokens and fails the launch.
  - **History (2026-07-25 → 2026-07-26).** `basalt_slam_test.launch.py` used to include `sitl.launch.py`, so `djinn start sitl basalt` brought up a *second* AirSim bridge, ArduPilot SITL, encoder and `managed_logger_node` on top of the persistent ones. Two recorders racing for `/ws/data/telemetry` make the loser's `on_activate` throw `Database directory already exists`. The include was removed 2026-07-26 and the file is now SLAM-only.
  - Six arguments were dropped from this invocation at the same time: `ap_type`, `output_bag_name` and `topics_to_record` (recorder settings — now owned solely by `sitl.launch.py`, pass them to `djinn start sitl`), and `input_topic`, `ffmpeg_topic`, `ffmpeg_node_name` (never declared by any file in this chain; the encoder's topics are hardcoded in `sitl.launch.py`). All six would now be silently discarded, since `ros2 launch` does not warn about undeclared arguments.
  - `ap_type` was separately corrected from `ArduPilot` to `ardupilot` on 2026-07-25; the old value matched nothing and left the stack with no `/ap/status` subscriber. It now lives only in `sitl.launch.py`'s chain. Change-record: [`/ws/plans/basalt-slam-defect-remediation.md`](../plans/basalt-slam-defect-remediation.md) Changes 3.3/3.4.
- **`orbslam3` (`djinn:265`):** runs `ros2 launch slam orbslam3.launch.py`. **This workflow is broken (2026-07-25):** `ros_ws/src/slam/launch/` contains only `basalt_slam.launch.py`; there is no `orbslam3.launch.py`. The ORB-SLAM3 stack is launched instead via `controllers/launch/slam_controller.launch.py`. The `-DSLAM_TYPE=ORBSLAM3` configure failure (`slam/CMakeLists.txt`, empty `install(TARGETS …)`) was fixed 2026-07-25, but the workflow is still broken: the missing launch file remains, and `controllers/controllers/slam/mono_driver_node.py:40-46` still uses `MultiThreadedExecutor` without importing it.
- **Overlays:** `iexec_sitl`/`iexec_sitl2` source `/opt/ros/humble`, `/ws/ardu_ws/install`, `/ws/sitl_ws/install`, `/ws/ros_ws/install`.
- **Test:** *assert* the three terminals launch; the bridge process runs with no "setup.bash: No such file"; for SLAM, the launch node appears in `ros2 node list`. For `basalt`, additionally *assert*:
  - **exactly one** of each shared node exists after `djinn start sitl` **and** `djinn start sitl basalt` are both up — `ros2 node list | grep -c managed_logger_node` returns `1`, and likewise for the AirSim bridge and the ffmpeg encoder. This is the regression test for the duplicate bring-up removed 2026-07-26; before the fix the count was 2 and the second recorder failed with `Database directory already exists`.
  - `ros2 param get /video_logging_controller ap_type` returns the value passed to **`djinn start sitl`** (not to `basalt`, which no longer carries it) — proves the surviving forwarding chain `sitl.launch.py` → `target_recorder.launch.py`.
  - `ros2 topic info -v /ap/imu/experimental/data` shows a **matched** subscriber (proves QoS compatibility — `ros2 node info` alone does not, see [`ardupilot-dds-qos.md`](ardupilot-dds-qos.md)).
  - `/clock` has exactly one publisher, `airsim_node`, at roughly 100 Hz; the SITL console prints `Using \clock topic for DDS timing: enabled`; `ros2 param get /basalt_slam_node use_sim_time` and `/managed_logger_node use_sim_time` return `true` while `/basalt_controller` and `/video_logging_controller` return `false`; and a contemporaneous `/ap/imu/experimental/data` stamp and camera stamp agree to within 50 ms. Relaunching without `use-sim-time` must reproduce the multi-second offset, which is the revert-path check.
  - `ros2 lifecycle get /managed_logger_node` reports `unconfigured` after launch and becomes `active` **on arming, before any takeoff**; and the first `/ap/status` message in the resulting bag carries `armed: true, flying: false`. That last one is the end-to-end proof that the trigger message itself was recorded.
- **Teardown:** `djinn kill sitl` (stops bridge/sim/QGC).

### `djinn up airsim [env]` / `start_simulation`
- **Call chain:** `start_simulation <env>` → `spawn_container_if_needed airsim_container nrt_airsim:0.0.1 x86_64` → (for `airsim_container`) `source $NRT_WS/sitl_ws/scripts/start.sh $NRT_WS/sitl_ws/src/ue5/AirSim/Unreal/Environments` which `docker run … -v <envs>:/ws … airsim_container`.
- **Test:** *assert* `airsim_container` running; `/ws` inside it is the UE `Environments` dir.

### `djinn build ardupilot [board] [config]` (firmware, non-SITL)
- **Call chain:** `spawn_container_if_needed sitl_bridge_container` → `iexec_sitl2 … "cd /ws/ardu_ws/src/ardupilot && ./waf configure --enable-dds --board $board && ./waf $config"` → copy `build/$board` → `/ws/logs/$board`.
- **Defaults:** board `SpeedyBeeF405WING`, config `plane`.
- **Test:** *assert* `waf` exits 0; `/ws/logs/$board` populated.

### `djinn init docker sitl`
- **Call chain:** `build_airsim_docker_image` (→ `cd sitl_ws/src/ue5/AirSim/docker/`; `python3 build_airsim_image.py --source …`) → `build_image` for `nrt:$VERSION` (`docker/ardupilot`) → fetch `ext/QGroundControl.AppImage` if absent.
- **Test:** *assert* images `nrt_airsim:0.0.1` and `nrt:$VERSION` exist; `ext/QGroundControl.AppImage` present + executable.

---

## Other workflows (summary)

| Workflow | Call chain (key) | Expected / test |
|---|---|---|
| `djinn init docker nrt` | `build_image` chain base→ros→pangolin→camera→ardupilot (`nrt:$VERSION`) | all five images exist; final = `nrt:0.1.0` |
| `djinn init docker dev` | `build_image nrt:dev`; `start_ide.sh`; gemini/claude login; nerd-font | `nrt:dev` exists; IDE container reachable |
| `djinn init docker kalibr` | `build_image nrt:kalibr` from `ext/calibration/kalibr` | `nrt:kalibr` exists |
| `djinn up nrt` | `spawn_container_if_needed nrt_container` → `git-setup.sh` → `build_ros_packages.sh` | `nrt_container` running; `ros_ws/install` built |
| `djinn up dev` | `spawn_container_if_needed dev_container` (→ `start_ide.sh`) | `dev_container` running |
| `djinn build nrt` | `iexec_ros nrt_container ./scripts/build_ros_packages.sh` | `ros_ws` builds with ardupilot/airsim msgs overlaid. Since 2026-07-25 the script selects `CXX_MARCH` from `uname -m` (`x86-64-v3` / `armv8.2-a+fp16+dotprod`) and passes `-DCXX_MARCH=…`, instead of letting `ext/basalt` default to `-march=native`. Override with `CXX_MARCH=native ./scripts/build_ros_packages.sh`. **After an ABI-affecting change, `rm -rf ros_ws/{build,install,log}/slam` first** — an incremental build mixes object files across the boundary. See [`/ws/ros_ws/context/simd-eigen-abi-mismatch.md`](../ros_ws/context/simd-eigen-abi-mismatch.md). |
| `djinn exec <t> "<cmd>"` | `iexec[_ros] <t>_container` | command runs in target container |
| `djinn kill sitl\|airsim\|gqc\|orbslam3` | `stop_*` + `terminate_process` | named processes/containers gone |
| `djinn down [t]` | `docker stop [<t>_container]` | container(s) stopped |
| `djinn rmi <img>\|all` | `docker rmi` | image(s) removed |
| `djinn ps` | `docker ps` | lists running containers |
| `djinn search <globtype> <pattern>` | `grep` across source | matching lines |
