# Architecture

## 1. Introduction
The Neurorobotics Workspace (NRT_WS) is a comprehensive environment tailored for robotics, computer vision, and drone development. This workspace serves as a structured wrapper for various toolkits, specifically the neurorobotics-toolkit, providing a streamlined and uniform interface for development, simulation, and deployment.

The primary motivation behind this workspace is to bridge the gap between complex software dependencies (ROS 2, ArduPilot, AirSim, ORB_SLAM3, multi-architecture build setups) and ease of use. By providing high-level orchestration, the workspace simplifies workflows, removes the friction of environment setup across multiple platforms (arm64, amd64), and offers automation tools for building, testing, and deploying complex robotic AI systems.

## 2. Docker
Docker is the cornerstone of this workspace, ensuring reproducible and consistent environments without polluting the host system. The workspace utilizes a strict linear hierarchy of layered Docker images to separate concerns and cache dependencies efficiently:

**Docker Image Dependency Graph:**
`docker/base`
  └── `docker/ros`
        └── `docker/pangolin`
              └── `docker/camera`
                    └── `docker/ardupilot` (builds into `shandilya1998/nrt:0.1.0`)

Subsequent images must be built on top of the image at `docker/ardupilot`.
*   **`docker/base`**: The base development image containing common system dependencies used across architectures.
*   **`docker/ros`**: Built directly on top of `docker/base`, this image installs core ROS 2 (Humble) components and extensions. It also bakes the fixed, never-changing ROS 2 build dependencies — `vision_opencv` (branch `humble`) and `ros2_shared` (branch `master`) — into a dedicated `/ros_deps_ws` overlay workspace, cloned and `colcon`-built at image-build time. Because this is the shared base layer, that overlay is inherited by `pangolin`/`camera`/`ardupilot` and is available to every ROS 2 workspace (`ros_ws`, `ardu_ws`, `sitl_ws`) without those workspaces carrying the packages as submodules. Both `ros_entrypoint.sh` variants source `/ros_deps_ws/install/setup.bash`.
*   **`docker/pangolin`**: Built on top of `docker/ros`, this image installs Pangolin, necessary for ORB_SLAM3 visualizations.
*   **`docker/camera`**: Built on top of `docker/pangolin`, adding hardware interface dependencies like `libcamera` (including specific Raspberry Pi configurations) and `libi2c-dev` for MPU6050.
*   **`docker/ardupilot`**: Built on top of `docker/camera`, this final stage installs the ArduPilot and AirSim SITL *toolchain and dependencies only* (ARM GCC, the Micro-XRCE-DDS generator, MAVProxy, and the associated Python packages) and is tagged as `shandilya1998/nrt:0.1.0`. Unlike earlier revisions, it **no longer bakes the ArduPilot or AirSim ROS 2 workspaces into the image**. Those workspaces now live under the workspace root (`ardu_ws/`, `sitl_ws/`), are mounted into the container via the `/ws` bind-mount, and are compiled at container-start (see the *Workspaces* section). This keeps workspace edits out of the image-build critical path.

**Development Environment:**
*   **`docker/dev`**: A completely separate image containing a Neovim IDE configured with the Gemini CLI companion. It is strictly a development environment and *does not* contain the runtime dependencies found in the `nrt` stack.

### Docker Scripts and Positional Arguments
The workspace utilizes specific shell scripts to manage image building and container spawning. Their positional arguments are as follows:

*   **`docker/scripts/docker-build.sh`**: Handles multi-architecture image construction.
    *   `$1` (`platform`): The target build platform (e.g., `linux/amd64,linux/arm64`).
    *   `$2` (`image_name`): The tag assigned to the output image (e.g., `shandilya1998/nrt:0.0.9`).
    *   `$3` (`image_file_path`): The path containing the target `Dockerfile`.
    *   `$4` (`build_args` - optional): Additional build arguments passed to Docker (e.g., `NRT_WS=$NRT_WS`).
*   **`docker/scripts/start_ide.sh`**: Entry point to initialize the Neovim-based development container.
    *   `$1` (`container_name`): The designated name for the spawned container (e.g., `dev_container`).
    *   `$2` (`image_name`): The image tag to run (e.g., `shandilya1998/nrt:dev`).
*   **`scripts/docker-setup.sh`**: Internal script executed within containers to initialize and update Git submodules safely.
    *   *No positional arguments required.*

### Future Architectural Improvements
As the number of containers to be managed increases (e.g., moving to micro-containers that separate SLAM, planning, and control), manual lifecycle management via shell scripts will become unwieldy.
*   **Docker Compose**: We will investigate and incorporate `docker-compose` to orchestrate multiple related containers declaratively, allowing for defined startup orders, complex network bridges (like linking SITL and ROS2 containers securely), and streamlined deployments.
*   **MicroK8s**: For scaling to highly complex robotics AI systems that span multiple compute nodes, integrating MicroK8s (a lightweight Kubernetes distribution) will provide fault tolerance, dynamic scaling of inference nodes, and production-ready container orchestration.

## 3. Workspaces

The codebase in the toolkit is largely distributed between workspaces each containing independent units. Currently three workspaces are implemented:

*   **`ros_ws/`** — the neurorobotics-toolkit (SLAM, controllers, sensors, and message packages). Built by `scripts/build_ros_packages.sh` (`djinn build nrt`).
*   **`ardu_ws/`** — the ArduPilot SITL flight-controller stack and its micro-ROS DDS bridge. Built by `ardu_ws/scripts/build.sh` (`djinn build ardupilot-sitl`).
*   **`sitl_ws/`** — the Cosys-AirSim ROS 2 wrapper and the Unreal Engine simulation environments. Built by `sitl_ws/scripts/build.sh` (`djinn build airsim-sitl`).

A key design point: the workspace root (`$NRT_WS`) is bind-mounted into every runtime container at `/ws` (`scripts/start.sh`), so each of these workspaces is visible inside the container as `/ws/<workspace>` **without any additional Docker `-v` mount**. Because the sources are mounted rather than copied into the image, an edit to any workspace propagates into the container instantly and needs only a `djinn build …` recompile — never an image rebuild.

### 3.1 `ros_ws/`

The core neurorobotics ROS 2 (`colcon`) workspace, managed as a git submodule tracking `neurorobotics-toolkit`, holds three SLAM integrations (ORB_SLAM3, Basalt, and MORB_SLAM), the robot controller framework, the sensor drivers and data loggers, and the shared message definitions consumed across the stack. `scripts/build_ros_packages.sh` overlays the ArduPilot and AirSim install trees (for `ardupilot_msgs` and `airsim_interfaces`) before building it.

The source tree under `ros_ws/src/` contains the following top-level packages:

*   **`controllers`** — Lifecycle-based robot controller framework for all platforms onboarded into NRT.
*   **`sensors`** — Sensor interface and data-logging nodes covering video capture, IMU recording, and rosbag2 bag recording.
*   **`slam`** — ROS 2 lifecycle-node wrappers for all SLAM algorithms integrated into the toolkit.
*   **`custom_interfaces`** — Custom ROS 2 message and service interface definitions shared across the stack.
*   **`gps_msgs`** — Extended GPS message definitions from SWRI (Southwest Research Institute) supplementing `sensor_msgs/NavSatFix`, including DOP values, per-axis uncertainty estimates, and full ENU position covariance.
*   **`mpu6050`** — ROS 2 hardware driver for the MPU6050 six-axis inertial measurement unit, publishing on `imu/mpu6050`.
*   **`flight_matrix_bridge`** — Python ROS 2 bridge that exposes the FlightMatrix simulation API as standard `sensor_msgs`, `geometry_msgs`, and `std_msgs` topics.
*   **`frontier_detection`** — 3D frontier detection for autonomous exploration, consuming OctoMap-based point cloud inputs from SLAM to identify unexplored regions for path planning.
*   **`tello`** — DJI Tello drone stack, comprising the `tello_msgs` (custom messages and services), `tello_driver` (UDP command, state, and H.264 video socket driver with joystick teleoperation), `tello_description` (URDF robot model), and `tello_gazebo` (Gazebo simulation plugin) sub-packages.

#### `controllers`

The `controllers` package provides the lifecycle-based controller infrastructure for every robot platform onboarded into NRT. The following controllers are implemented:

*   **`LifecycleControllerBase`** (`src/common/controller.cpp`) — Abstract base class from which all controllers derive. It maintains a configurable worker thread pool for processing lifecycle service responses off the ROS 2 executor, and exposes async (`AsyncCallChangeState`, `AsyncGetNodeState`) and synchronous (`SyncCallChangeState`, `SyncGetNodeState`) wrappers around the `lifecycle_msgs` `ChangeState` and `GetState` services. Derived controllers register managed nodes via `RegisterNode`, supplying per-node state-change and get-state response callbacks that are dispatched through the pool.
*   **`TelloControllerNode`** (`src/tello/controller.cpp`) — Concrete controller for the DJI Tello drone. On construction it registers and drives the `tello_joy` lifecycle driver node through the configure and activate transitions, subscribes to `tello_msgs/FlightData` to monitor battery and flight status, and dispatches emergency `TelloAction` service calls (such as a forced landing) when failsafe thresholds are breached.
*   **`VideoLoggingDriver`** (`src/logging/video_controller.cpp`) — Lifecycle controller that manages the `video_logger` lifecycle node. It subscribes to an autopilot status topic (`ardupilot_msgs/Status` when `ap_type` is `ardupilot`, or `std_msgs/String` flight state when `ap_type` is `tello`) and drives the logger through the ROS 2 lifecycle state machine in response to arm and land events. A static transition-step lookup table encodes all valid single-step lifecycle transitions, a latched target-state variable records intent across status messages, and a mutex-guarded reconciler prevents concurrent duplicate transition requests.

#### `sensors`

The `sensors` package provides sensor interface and data-logging nodes used throughout the toolkit. The following sensor classes are supported:

*   **Video (camera)**: Two GStreamer-based lifecycle nodes handle camera data. `VideoReaderNode` (`src/video/reader.cpp`) decodes H.264/MP4 files through a `filesrc → qtdemux → avdec_h264 → videoconvert → appsink` GStreamer pipeline and publishes decoded frames at up to 30 Hz as `sensor_msgs/Image`. `VideoLoggerNode` (`src/video/logger.cpp`) receives `sensor_msgs/Image` frames from a configurable topic, encodes them via an `appsrc → videoconvert → x264enc → h264parse → mp4mux → filesink` pipeline, and writes the result to an MP4 file with configurable resolution and frame rate.
*   **IMU**: `IMUSubscriber` (`src/imu/imu_subscriber.cpp`) subscribes to `sensor_msgs/Imu` on the `imu/mpu6050` topic, applies configurable per-axis bias offsets to the angular velocity and linear acceleration readings, and logs timestamped orientation, angular velocity, and linear acceleration data to a CSV file.
*   **Rosbag2 recording**: `ManagedLogger` (`src/logger/managed_logger.cpp`) is a lifecycle node wrapping `rosbag2_transport::Recorder`. On activation it creates a SQLite3-backed rosbag2 writer for a configurable list of topics and runs the recorder on a dedicated `MultiThreadedExecutor` thread. Automatic filename versioning is applied to prevent overwrites when a bag with the specified name already exists on disk.

#### `slam`

The `slam` package provides ROS 2 lifecycle-node wrappers around three SLAM algorithm implementations. All nodes inherit from `SlamNode` (a `rclcpp_lifecycle::LifecycleNode` subclass defined in `ros_ws/src/slam/src/node.cpp`) and share a common `Slam` abstract base class (`ros_ws/src/slam/src/slam.cpp`) that exposes `TrackMonocular` and `GrabIMU` methods. On each tracked frame every node broadcasts the estimated camera pose as a TF2 `map → camera` transform via `tf2_ros::TransformBroadcaster`. The three integrated SLAM systems are as follows:

*   **ORB_SLAM3** — Feature-based monocular visual SLAM using ORB feature descriptors, a DBoW2 bag-of-words visual place-recognition database, and pose-graph loop closure.
    *   Algorithm source: `ros_ws/src/slam/orb_slam3/`
    *   ROS 2 wrapper: `ros_ws/src/slam/src/orbslam3/` (classes `MonoORBSLAM3` and `VisualSlamNode`, enabled at compile time with the `USE_ORBSLAM3` macro)
    *   Supported modes: monocular visual odometry
    *   Published topics: `~/annotated_frame` (`sensor_msgs/Image`), `~/map_points` (`custom_interfaces/PointCloud3`)
    *   ORB vocabulary file: `ros_ws/src/slam/orb_slam3/Vocabulary/ORBvoc.txt.bin`
*   **Basalt** — Keyframe-based visual-inertial odometry optimised for low-latency and high-accuracy state estimation with tightly coupled IMU integration.
    *   Algorithm source: `ros_ws/src/slam/ext/basalt/`
    *   ROS 2 wrapper: `ros_ws/src/slam/src/basalt/` (classes `BasaltSLAM` and `BasaltSLAMNode`)
    *   Supported modes: VSLAM (visual-only, parameter `slam_type: VSLAM`) and VISLAM (visual-inertial, parameter `slam_type: VISLAM`, requiring an IMU topic via the `imu_topic_name` parameter)
    *   Published topics: `~/annotated_frame` (`sensor_msgs/Image`)
    *   Calibration and configuration are provided at activation via YAML files referenced by the `calibration_file_path` and `configuration_file_path` parameters
*   **MORB_SLAM** — A modular extension of ORB_SLAM3 with a network-accessible external sensor client interface, supporting WebSocket-based RealSense and external IMU input.
    *   Algorithm source: `ros_ws/src/slam/ext/MORB_SLAM/`
    *   ROS 2 wrapper: `ros_ws/src/slam/src/morbslam/` (classes `MonoMORBSLAM` and `VisualSlamNode`, enabled at compile time with the `USE_MORBSLAM` macro)
    *   Supported modes: monocular visual odometry
    *   Initialisation is deferred to runtime via the `custom_interfaces/StartupSlam` service, which supplies the vocabulary and settings file paths and the camera type
    *   ORB vocabulary file: `ros_ws/src/slam/ext/MORB_SLAM/Vocabulary/ORBvoc.txt`

The compile-time macros `USE_ORBSLAM3` and `USE_MORBSLAM` select which feature-based backend the shared `VisualSlamNode` instantiates, so ORB_SLAM3 and MORB_SLAM share the same ROS 2 node class. Basalt operates as an independent `BasaltSLAMNode` in all configurations.

#### `custom_interfaces`

The `custom_interfaces` package provides the shared ROS 2 interface definitions consumed by the `slam`, `controllers`, and `frontier_detection` packages. The following interfaces are defined:

*   **`msg/PointCloud3.msg`** — Bundles a `sensor_msgs/PointCloud2` sparse map-point cloud with a `geometry_msgs/Transform` camera pose, allowing SLAM consumers to receive a spatially consistent point cloud and its associated pose in a single atomic message. Published by `VisualSlamNode` on each tracked frame.
*   **`srv/StartupSlam.srv`** — Service for runtime SLAM initialisation. The request carries `config_file_path` (a path to a YAML file specifying the vocabulary and settings file locations), `camera_topic` (the ROS 2 image topic to subscribe to), and `camera_type` (e.g., `"monocular"`). The response carries a `bool success` flag and a `string message` describing any failure reason.

### 3.2 `ardu_ws/`

The ArduPilot SITL and DDS-bridge workspace.

*   **`ardu_ws/src/`** — three git submodules: `ardupilot` (branch `master`; its ROS 2 packages `ardupilot_sitl`, `ardupilot_msgs`, `ardupilot_dds_tests` live under `Tools/ros2/`), `micro_ros_agent` (branch `humble`), and `micro_ros_msgs` (branch `humble`). These replace the deprecated `vcs import` of `docker/ardupilot/ros2.repos`; submodules are now the single version-control mechanism for independent components. All ardupilot related code can be found in `ardu_ws/src/ardupilot` and any reference to ardupilot code must use the local instance of ardupilot setup in `ardu_ws` for codebase investigation.
*   **`ardu_ws/scripts/build.sh`** — runs `rosdep install --from-paths src` (the workspace holds only ROS 2 packages) then `colcon build --cmake-args -DBUILD_TESTING=ON`. Invoked by `djinn build ardupilot-sitl` and by `djinn up sitl_bridge`.
*   **`ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh`** — launches the ArduPilot–AirSim–ROS SITL bridge (`ros2 launch controllers sitl.launch.py`) inside `sitl_bridge_container`; used by `djinn start sitl`.

Firmware (non-SITL) builds for real boards still use `djinn build ardupilot <board> <configuration>`, which runs `waf` against `ardu_ws/src/ardupilot`.

### 3.3 `sitl_ws/`

The Cosys-AirSim wrapper and Unreal Engine environments workspace.

*   **`sitl_ws/src/ue5/AirSim`** — the full Cosys-AirSim fork as a git submodule (was `envs/ue5/AirSim`). Its ROS 2 packages (`airsim_ros_pkgs`, `airsim_interfaces`) live under `ros2/src/`; the repository also carries a ROS 1 (catkin) tree under `ros/`. Any code base invesigation requiring AirSim code must look at `sitl_ws/src/ue5/AirSim` for Cosys-AirSim source code. The simulation environments currently being used by AirSim can be found at `sitl_ws/src/ue5/AirSim/Unreal/Environments`.
*   **`sitl_ws/scripts/build.sh`** — downloads rpclib/Eigen into the AirSim tree, then builds **only the ROS 2 subtree**: `rosdep`/`colcon` are scoped with `--from-paths`/`--base-paths src/ue5/AirSim/ros2/src` so the ROS 1 tree and stale colcon artifacts are not discovered. Invoked by `djinn build airsim-sitl` and by `djinn up sitl_bridge`.
*   **`sitl_ws/scripts/start.sh`** / **`sitl_ws/scripts/run_airsim.sh`** — spawn the AirSim simulation container and launch a UE environment binary.

The UE4 environments remain at `envs/ue4/`; only the UE5 (Cosys-AirSim) setup moved under `sitl_ws/`.

## 4. djinn
`djinn` is the master CLI entry point and orchestration script for the workspace. It acts as an abstraction layer, hiding the complexities of Docker CLI commands, CMake invocations, and multi-process startup sequences behind a simple, unified interface.

### CLI Architecture and Grammar
`djinn` implements a simple, consistent command grammar: `djinn <verb> <subject> <arguments>`. This grammar creates powerful shorthands for complex automations.

Here is the breakdown of implemented verbs, their subjects, and command structures:

*   **`install`**: Installs host-side prerequisites.
    *   *Arguments*: `--docker`, `--ssh`, `--git`.
    *   *Example*: `djinn install --docker --ssh --git`
*   **`init`**: Configures the workspace and builds targeted Docker images.
    *   *Subjects*: `docker`.
    *   *Arguments*: `nrt`, `dev`, `airsim`, `sitl`, `kalibr`.
    *   *Example*: `djinn init docker sitl` (Builds the SITL simulation images).
*   **`up`**: Spawns Docker containers based on the pre-built images.
    *   *Subjects*: `nrt`, `dev`, `airsim`, `sitl_bridge`, `kalibr`.
    *   *Example*: `djinn up nrt` (Starts the main runtime container).
*   **`build`**: Compiles source code across various environments.
    *   *Subjects*: `nrt` (ROS packages), `docker` (images), `ardupilot` (Firmware), `ardupilot-sitl` (the `ardu_ws` ROS 2 workspace), `airsim-sitl` (the `sitl_ws` ROS 2 workspace), `sitl` (both SITL workspaces).
    *   *Arguments for `ardupilot`*: `<board>` `<configuration>`.
    *   *Example*: `djinn build ardupilot SpeedyBeeF405WING plane` (Builds fixed-wing firmware for the SpeedyBee board).
    *   *Example*: `djinn build sitl` (Builds both `ardu_ws` and `sitl_ws`; `djinn up sitl_bridge` performs the same two builds after spawning the bridge container).
*   **`start`**: Launches specific high-level workflows or nodes.
    *   *Subjects*: `tello`, `tello-orbslam3`, `sitl`, `ardupilot_target_recorder`.
    *   *Arguments for `sitl`*: `orbslam3`, `basalt` (to specify SLAM integrations alongside the simulation).
    *   *Example*: `djinn start sitl orbslam3` (Starts closed-loop simulation stack with ORB_SLAM3).
*   **`exec`**: Runs arbitrary shell commands inside targeted containers.
    *   *Subjects*: Container prefix (e.g., `nrt`, `dev`).
    *   *Arguments*: `<command>`.
    *   *Example*: `djinn exec nrt bash` (Opens a bash session in the `nrt` container).
*   **`kill`**: Forcefully terminates active workflows and their sub-processes.
    *   *Subjects*: `sitl`, `airsim`, `gqc`, `orbslam3`.
    *   *Example*: `djinn kill sitl` (Stops all SITL bridges, simulators, and QGroundControl).
*   **`down`**: Gracefully stops specific or all Docker containers.
    *   *Subjects*: Container prefix (e.g., `airsim`). If omitted, stops all workspace containers.
    *   *Example*: `djinn down nrt`
*   **`rmi`**: Removes built Docker images from the host system.
    *   *Subjects*: Image name or `all`.
    *   *Example*: `djinn rmi all`
*   **`ps`**: Lists currently active workspace containers.
    *   *Example*: `djinn ps`
*   **`search`**: Fast `grep`-based search across the codebase.
    *   *Arguments*: `<directory_to_search>` `<search_string>`.
    *   *Example*: `djinn search ros_ws/src "orbslam3"`

### Scaling the Interface
As the `djinn` interface grows to handle highly complex operations, managing arguments and workflows linearly will reach a limit. In the future, Large Language Models (LLMs) will play a critical role in `djinn`'s functionality. By natively wrapping foundational models (like Gemini and Claude) directly into the CLI architecture, we can implement intelligent workflow automation.

Instead of remembering exact flags, developers could input conversational requests such as *"Run a simulation with the Tello drone testing the ORB_SLAM3 pipeline and record the telemetry"*. `djinn`, backed by an LLM, will dynamically interpret this intent, translate it into the strict `djinn <verb> <subject> <arguments>` grammar, and sequentially orchestrate the exact commands needed.

## 5. Services
For physical deployment on hardware (e.g., a companion computer on a drone or rover), the workspace provides mechanisms to run components as OS-level services.

Linux systems use managers like `systemd` or `cron` to handle background tasks. Systemd services (defined by `.service` files) dictate how and when an application should boot, specifying dependencies (like waiting for the network), and providing automatic restart rules upon failure. To deploy these custom services, their definitions are typically placed in `/etc/systemd/system/` and enabled via `systemctl`.

### `data_logger.service`
Currently, the primary service implemented is `services/data_logger.service`. It is responsible for initializing an autonomous telemetry and data recording node immediately when the host machine boots.

*   When triggered by systemd, it securely executes the wrapper script: `scripts/deploy/data_logger.sh`.
*   **`scripts/deploy/data_logger.sh` Arguments**: This script requires *no positional arguments*. It statically inherits state from the workspace's helper functions, checks that the `nrt` Docker environment is active, and issues a non-interactive `iexec_sitl2` call to trigger the `ros2 launch controllers target_recorder.launch.py` process seamlessly inside the container.

As we deploy more complex behaviors (e.g., dedicated planning services or standalone communication bridges), additional service definitions will be documented here following the same robust deployment structure.

## 6. Miscellaneous
*   **Unreal Engine Simulation**: High-fidelity environmental simulations are supported via the Cosys-AirSim fork at `sitl_ws/src/ue5/AirSim`, integrated directly into Unreal Engine 5 workflows (see the *Workspaces* section). Legacy UE4 assets remain under `envs/ue4/`.
*   **LLM Companion Integration**: `agentic.nvim`, configured in `docker/dev/ai.lua` and shared by both the `docker/dev` and `nrt` image chains, drives Claude Code and Antigravity CLI (`agy`) as ACP subprocesses to allow agentic code modifications natively within the workspace. See [`context/dev-ide-ai-clis.md`](context/dev-ide-ai-clis.md).
*   **Code Organization**: Core source code for the neurorobotics toolkit resides in `ros_ws/`, utilizing strict Colcon semantics. Independent external resources and calibration toolings (like Kalibr) are maintained in `ext/`.
