# `/ros_deps_ws` — fixed ROS 2 dependencies baked into the image

Durable record of the migration that moves the two fixed, never-changing ROS 2 build dependencies — `vision_opencv` and `ros2_shared` — out of the `ros_ws` workspace (where they were git submodules) and into a dedicated overlay workspace `/ros_deps_ws` baked into the Docker `ros` image. Change date: 2026-07-24.

## Why

`vision_opencv` (provides `cv_bridge`, `image_geometry`, `vision_opencv`) and `ros2_shared` are upstream packages that are pinned and are not meant to evolve with the project. Carrying them as submodules of `ros_ws` meant every clone/`submodule update` pulled them and every `colcon build` rebuilt them. Baking them into the image once — in the shared `ros` layer, inherited by `pangolin`/`camera`/`ardupilot` — makes them available across **all** ROS 2 workspaces (`ros_ws`, `ardu_ws`, `sitl_ws`) and all use cases, with no per-workspace source or rebuild.

## The model

- **Image layer:** `docker/ros/Dockerfile` (after the `libi2c-dev`/`tf2` install, before `ulimit`) clones the two repos into `/ros_deps_ws/src` and `colcon build`s them:
  - `git clone -b humble https://github.com/ros-perception/vision_opencv.git`
  - `git clone -b master https://github.com/clydemcqueen/ros2_shared.git`
  - build: `source /opt/ros/humble/setup.bash && rosdep install --from-paths src -y --ignore-src --rosdistro humble && colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release`, wrapped in `/bin/bash -c "…"` because Dockerfile `RUN` defaults to `/bin/sh` and `setup.bash` requires bash. Preceded by `apt-get update` (rosdep resolves `cv_bridge`'s OpenCV to system `libopencv-dev`); `/var/lib/apt/lists` cleaned after.
  - `rosdep` is already `init`/`update`d earlier in the same Dockerfile; `colcon` is already installed. Placement after those is required.
- **Entrypoints:** both `docker/ros/ros_entrypoint.sh` and `docker/ardupilot/ros_entrypoint.sh` `source /ros_deps_ws/install/setup.bash` immediately after `source /opt/ros/$ROS_DISTRO/setup.bash`. Unconditional (no existence guard) because the overlay is baked into the image and always present — unlike the `/ws/{ardu_ws,sitl_ws}` mount-built trees, which are existence-guarded.
- **Build scripts** source the overlay so it is on `AMENT_PREFIX_PATH` at compile time:
  - `scripts/build_ros_packages.sh` (the one `djinn build nrt`/`up`/`start` invokes) sources `/ros_deps_ws/install/setup.bash` before the `ros_ws` `colcon build`.
  - `ardu_ws/scripts/build.sh` and `sitl_ws/scripts/build.sh` source it after `/opt/ros/humble/setup.bash` (defensive/consistent; those workspaces do not directly depend on the two packages today).

## Consumers (why the overlay must be sourced before `ros_ws` builds)

`ros_ws` packages `find_package` the removed deps and now resolve them from the overlay: `src/sensors` (`cv_bridge`, `image_geometry`), `src/slam` (`cv_bridge`), `src/tello/tello_driver` (`cv_bridge`), `src/flight_matrix_bridge` and `src/controllers` (`ros2_shared`). If `/ros_deps_ws/install/setup.bash` is not sourced, these fail with missing-package CMake errors.

## Gotchas / non-obvious facts (verified 2026-07-24)

1. **Nested submodule removal.** `ros_ws` is itself a submodule of the superproject; `vision-opencv`/`ros2_shared` were submodules **of `ros_ws`** (declared in `ros_ws/.gitmodules`, git-dirs under `.git/modules/ros_ws/modules/src/…`). Removal was done inside `ros_ws` via `git submodule deinit -f … && git rm -f …` (which also strips the `.gitmodules` stanzas and `.git/config` sections), plus `rm -rf` of the stale `.git/modules/ros_ws/modules/src/{vision-opencv,ros2_shared}`. This is a change to the `ros_ws` submodule repo — the superproject now sees `ros_ws` as modified until that is committed there.
2. **SSH → HTTPS.** The task specified `git@github.com:` URLs, but in-image `git clone` has no SSH key and would fail; all other in-image clones use `https://github.com/…`. The Dockerfile therefore uses HTTPS. Upstreams as specified: `ros-perception/vision_opencv`@`humble`, `clydemcqueen/ros2_shared`@`master`.
3. **Bash-only source in `RUN`.** `source /opt/ros/humble/setup.bash` fails under the default `/bin/sh`; the build `RUN` wraps the source+rosdep+colcon in `/bin/bash -c "…"` rather than setting a global `SHELL` (keeps the change local, avoids altering child-image `RUN` shells).
4. **`camera` image build is unaffected.** `docker/camera/build_camera_ros.sh` builds only `camera_ros` (libcamera-based) at image-build time and does not depend on `cv_bridge`/`ros2_shared`; it needs no overlay source.
5. **`ros_ws/build_ros_packages.sh`** (a copy inside the submodule) is **not** the script `djinn` runs — `djinn` calls the superproject `scripts/build_ros_packages.sh` (`djinn:164,187,195,200`). Only the superproject copy was updated.

## Cross-refs

- `docker/ros/Dockerfile`, `docker/ros/ros_entrypoint.sh`, `docker/ardupilot/ros_entrypoint.sh` — image + entrypoint changes.
- `scripts/build_ros_packages.sh`, `ardu_ws/scripts/build.sh`, `sitl_ws/scripts/build.sh` — build-time overlay source.
- `ros_ws/context/repo-layout.md` — the submodule-side note that these are no longer local submodules.
- [sitl-workspace-migration.md](sitl-workspace-migration.md) — the sibling migration (mounted `ardu_ws`/`sitl_ws`) and its entrypoint existence-guard pattern.
