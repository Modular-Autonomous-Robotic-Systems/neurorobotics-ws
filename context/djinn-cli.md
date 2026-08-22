# `djinn` CLI

`djinn` (repo root, bash) is the workflow orchestrator for `NRT_WS`. Requires env `$NRT_WS` set to the workspace root. Sources five helper libs at startup, four since the beginning and `ai.sh` added 2026-08-14 alongside the Antigravity CLI integration:

- `scripts/helpers/data.sh` — `config_file`, `statefile`, `last_run_sitl_env`, `save_state`.
- `scripts/helpers/exec.sh` — `iexec`, `iexec_ros`, `iexec_kalibr`, `iexec_sitl`/`iexec_sitl2`, `terminate_process`.
- `scripts/helpers/docker.sh` — `build_image`, `setup_nvim_config_for_image_build`, `cleanup_nvim_config_after_image_build`, `spawn_container_if_needed`.
- `scripts/helpers/sitl.sh` — `build_*_docker_image`, `start_simulation`, `start_sitl_container`, `build_airsim_docker_image`, `setup_airsim_ros_pkgs_for_docker_build`.
- `scripts/helpers/ai.sh` — `sync_directive_pair`, the per-directory `CLAUDE.md`↔`GEMINI.md` symlink pairing function called by the directive traversal inline in `djinn init docker dev`. See [ai-directive-architecture.md](ai-directive-architecture.md).

Config comes from `$config_file` (created on first `init`): `VERSION`, `ROS_VERSION`, `userEmail`, `userName`. Current `VERSION=0.0.9`, ROS Humble. DockerHub namespace: `shandilya1998/nrt`. Current `VERSION=0.1.0`. Until 2026-08-14 first-run `init` also wrote a `GOOGLE_CLOUD_PROJECT` key, prompted for Gemini CLI's Google AI Pro billing; that prompt was removed when Gemini CLI was replaced by Antigravity CLI (`agy`), which authenticates interactively rather than through an environment variable, so new `.djinn_config` files no longer carry the key. A `.djinn_config` written before that date still has it and it is harmless to leave, since `export $(grep -v '^#' $config_file | xargs)` exports whatever keys are present.

## Subcommands

| Command | Effect |
|---------|--------|
| `djinn install <a> <b> <c>` | Runs `scripts/install.sh`. |
| `djinn init docker nrt` | Builds the full image chain: base → ros → pangolin → camera → ardupilot (`nrt:$VERSION`). Uses nvim-config setup/cleanup around the base build. |
| `djinn init docker dev [git-setup-flag]` | Builds `nrt:dev`, prepares `.claude`/`.gemini`/`.claude.json` and the Claude skills symlink, spawns `init_container`, then inside it: `git-setup.sh`/`docker-setup.sh` (submodule init/update, git identity) only if `[git-setup-flag]` is given and is not the literal `skip-git-setup`, the `CLAUDE.md`↔`GEMINI.md` directive-symlink traversal (unconditional), `claude /login`, `agy -p '/usage'`; then installs the nerd font. Run once as `djinn init docker dev init-git-setup` for first-time workspace setup, **before** any other `djinn init docker …` target, since the submodule checkout and directive symlinks are shared host state every later container reads through the `$NRT_WS`/`/ws` mount. Every later call is the bare `djinn init docker dev`, which refreshes the image without touching git/submodule state. See [ai-directive-architecture.md](ai-directive-architecture.md) and [djinn-workflows.md](djinn-workflows.md). |
| `djinn init docker airsim` | Builds the AirSim sim image → `build_airsim_docker_image`. See [airsim-docker-build.md](airsim-docker-build.md). |
| `djinn init docker sitl` | Builds AirSim image + SITL bridge image; fetches QGroundControl AppImage. |
| `djinn init docker kalibr` | Builds `nrt:kalibr` from `ext/calibration/kalibr/`. |
| `djinn up nrt\|dev\|airsim\|sitl_bridge\|kalibr` | Spawns/initialises the corresponding container. `up airsim [env]` → `start_simulation` (default env `nature`). `up sitl_bridge` spawns `sitl_bridge_container` and then builds **both** SITL workspaces (`/ws/ardu_ws/scripts/build.sh` and `/ws/sitl_ws/scripts/build.sh`). |
| `djinn build [nrt\|docker\|ardupilot\|ardupilot-sitl\|airsim-sitl\|sitl]` | `build` (no arg) rebuilds NRT + ROS pkgs in `nrt_container`. `docker <image> <path> [arch]` → `docker/scripts/docker-build.sh`. `ardupilot [board] [config]` → waf firmware build in `sitl_bridge_container` (default board `SpeedyBeeF405WING`, config `plane`). `ardupilot-sitl` → `ardu_ws/scripts/build.sh`; `airsim-sitl` → `sitl_ws/scripts/build.sh`; `sitl` → both. All three spawn `sitl_bridge_container` if needed. |
| `djinn exec <target> "<cmd>"` | Runs a command in `<target>_container` (`nrt` uses `iexec_ros`). |
| `djinn start tello\|tello-orbslam3\|sitl\|basalt\|ardupilot_target_recorder` | Launches ROS/SITL apps. `start sitl [orbslam3\|basalt]` runs the SLAM stack against AirSim; bare `start sitl` opens AirSim + ArduPilot + SITL bridge + QGC in gnome-terminals. |
| `djinn kill sitl\|airsim\|gqc\|orbslam3` | Kills the named running processes/containers. |
| `djinn down [target]` | Stops container(s). `down airsim` stops+removes `airsim_container`. |
| `djinn rmi <image>\|all` | Removes image(s). |
| `djinn ps` | `docker ps`. |
| `djinn search <globtype> <pattern>` | grep across source/CMake/sh/xml files. |

## Docker image build hierarchy (from `ARCHITECTURE.md`)

`docker/base` → `docker/ros` → `docker/pangolin` → `docker/camera` → `docker/ardupilot`
(builds `shandilya1998/nrt:$VERSION`). AirSim and SITL bridge are separate branches.
