# Context Index

This directory holds durable, task-scoped context for the Neurorobotics Workspace
(`NRT_WS`). It exists to **minimise future token usage**: read this README first,
then open only the specific context file(s) relevant to the task instead of
re-deriving knowledge by scanning the whole repo.

> **Maintenance rule:** whenever a task uncovers non-obvious, reusable knowledge
> (a build chain, a gotcha, a fix, an interface), record it as a context file here
> and add a one-line entry to the table below. Keep entries current — stale context
> is worse than none. See root `CLAUDE.md` for the full directive.

## How to use this index

1. Skim the table. Match your task to a topic.
2. Open the linked file for detail. Only escalate to the actual source files it
   points at if the context file is insufficient.
3. After the task, update the relevant file (or add a new one) and this table.

## Context files

| File | Topic | Read this when… |
|------|-------|-----------------|
| [airsim.md](airsim.md) | Cosys-AirSim & UE game (StonePineForest) architecture — sim modes, ArduCopter/ArduPilot SITL data path & ports, settings.json location/semantics, RPC-vs-MAVLink state, GPS sensor model | Running/understanding a UE AirSim game, SITL wiring, why RPC state getters are stubbed, where settings.json is read from |
| [airsim-sitl-gps-issue.md](airsim-sitl-gps-issue.md) | Investigation of "Not Implemented: get*" log spam & ArduPilot "GPS 1: not healthy" in StonePineForest SITL — root causes, config discrepancies, action plan | Debugging the copter SITL not arming, GPS-unhealthy, the Not-Implemented spam, or clock/port/version mismatches |
| [airsim-docker-build.md](airsim-docker-build.md) | Cosys-AirSim Docker image build (`djinn init docker airsim`), UE toolchain, the `<atomic>` build failure and its fix | Building/debugging the AirSim simulation image, UE version compatibility, `build_airsim_image.py` / `Dockerfile_source` |
| [sitl-workspace-migration.md](sitl-workspace-migration.md) | Migration of the ArduPilot/AirSim ROS 2 workspaces out of the baked image into mounted `ardu_ws`/`sitl_ws` under `/ws` — the mount model, submodule sources, colcon discovery-over-reach gotcha, and absolute-path debt | Working on `djinn build {ardupilot-sitl,airsim-sitl,sitl}`, `up sitl_bridge`, why the container exits on start, why the AirSim build must be scoped to `ros2/src`, or any `/ardu_ws`→`/ws/ardu_ws` / `/airsim_ws`→`/ws/sitl_ws` path fix |
| [sitl-time-synchronisation.md](sitl-time-synchronisation.md) | Every clock in the SITL stack — AirSim's `SteppableClock` and where each sensor and image stamp comes from, ArduPilot's `AP_DDS` stamp precedence and its SITL `/clock` DataReader, why the MAVLink `SYSTEM_TIME` and `TIMESYNC` routes cannot discipline the stamping clock, what ROS 2 `use_sim_time` does and does not change, why a constant camera-to-IMU offset hangs Basalt outright, the three architectural options with the reason one wins, and the full ArduPilot time architecture across SITL, HITL and real hardware (the two-layer `micros64()`/`AP_RTC` model, why the `/clock` DataReader is SITL-only, the unused `uxr_sync_session` handshake, and the ranked hardware options) | Debugging a timestamp offset between `/airsim_node/*` and `/ap/*`, deciding which nodes take `use_sim_time`, wiring `/clock`, planning HITL or hardware clock synchronisation, or after bumping either the `ardupilot` or `AirSim` submodule |
| [ardupilot-dds-qos.md](ardupilot-dds-qos.md) | Per-topic publisher QoS of every `/ap/*` topic, transcribed from `AP_DDS_Topic_Table.h`, plus the DDS matching rule and why a RELIABLE subscriber silently fails against them | A `/ap/*` subscriber's callback never fires, choosing QoS for a new `/ap/*` consumer, or after bumping the `ardupilot` submodule |
| [ros-deps-workspace.md](ros-deps-workspace.md) | The `/ros_deps_ws` overlay baked into the Docker `ros` image — `vision_opencv`+`ros2_shared` removed from `ros_ws` submodules and built once into the image, sourced by entrypoints and build scripts | Working on `docker/ros/Dockerfile`, why `cv_bridge`/`ros2_shared` resolve without a local `src/` checkout, the nested-submodule removal, or any `/ros_deps_ws` sourcing |
| [djinn-cli.md](djinn-cli.md) | The `djinn` orchestration CLI — subcommands, image build chain, container lifecycle | Running or extending `djinn`, understanding what a `djinn …` command does |
| [djinn-workflows.md](djinn-workflows.md) | Per-workflow catalogue: invocation → call chain → side effects → expected outcome → test strategy for every `djinn` command (SITL workflows in depth) | Authoring/automating tests for a `djinn` workflow, or documenting a new one (mandatory per `CLAUDE.md §3`) |

## Related top-level docs (not in this dir)

- `ARCHITECTURE.md` — high-level workspace architecture (Docker image hierarchy, ROS, SITL).
- `docs/` — roadmaps and cheatsheets.
