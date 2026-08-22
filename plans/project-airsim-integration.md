# Integrating Project AirSim into `NRT_WS`

Status, IMPLEMENTED 2026-08-03. This document is the change record for the integration. Written against Project AirSim commit `7fb9c566515901112c8d246fd02685bc58c369e5` of 2026-07-15, which is now checked out in the workspace as the submodule `sitl_ws/src/ue5/ProjectAirSim`, Cosys-AirSim submodule `1be917ce`, ArduPilot submodule `e257f85b`, workspace image version `0.1.1`.

Every Project AirSim source, documentation and configuration path in this document is written relative to the workspace root and therefore begins with `sitl_ws/src/ue5/ProjectAirSim/`, so that every citation can be opened directly without first reconstructing where the tree lives.

---

## 1. Introduction

### 1.1 Why the simulator is being replaced

The decision to leave Cosys-AirSim does not rest on a preference for one renderer over another. It rests on three defects measured inside this workspace, each of which is a property of the simulator's architecture rather than of its configuration, and each of which is recorded with evidence in [`context/sitl-time-synchronisation.md`](../context/sitl-time-synchronisation.md) and [`context/simulation-engine-survey.md`](../context/simulation-engine-survey.md).

The first defect is the transport. The Cosys-AirSim ROS 2 bridge obtains vehicle state by polling the simulator over a msgpack remote procedure call on port 41451, performing one blocking round trip per sensor per iteration of `publish_vehicle_state()` at `sitl_ws/src/ue5/AirSim/ros2/src/airsim_ros_pkgs/src/airsim_ros_wrapper.cpp:1459-1500`. A timer nominally at 100 Hz achieved 14.05 Hz and the image timer nominally at 20 Hz achieved 15.7 Hz, both measured on 2026-07-28. No amount of tuning recovers a request-response client that must ask for every sample.

The second defect follows from the first. Because the simulator clock is published from that same starved callback, `/clock` arrives at roughly 14 Hz, and ArduPilot's `AP_DDS_Client::update_topic` copies the last received clock value verbatim into every header. A 162 Hz inertial publisher against a 14 Hz clock produced runs of up to twenty-four identical timestamps, and Basalt discards every duplicate, so roughly three quarters of the inertial data was lost. The workspace mitigated this by halving `ClockSpeed`, which is a reduction of the duplication ratio bought at the price of running the simulation at half speed, and not a fix.

The third defect is the absence of a negotiated coupling between physics and the flight controller. The `LockStep` settings key is inert on the ArduCopter path, confirmed by the absence of any `lock_step` reference under `firmwares/arducopter/`, and the only coupling is that `recvRotorControl()` blocks until motor commands arrive. There is no pause, no explicit step and no deterministic faster-than-real-time execution, so regression testing cannot be made reproducible.

A fourth consideration is not a defect but a risk. The Cosys-AirSim README states plainly that the repository is provided as is, will not be actively updated, and comes without warranty or support. For a laboratory artefact that is a defensible position. For a toolkit intended to carry a decade of work it is not.

### 1.2 What Cosys-AirSim does well

An honest comparison must record what is being given up. Cosys-AirSim has the richest sensor implementation in the AirSim lineage, adding a GPU-accelerated lidar with realistic intensity generation, an echo sensor modelling sonar and radar, instance segmentation and multi-layer annotation for ground truth, camera chromatic aberration, motion blur and lens distortion, skid-steering ground vehicles, and both Python and C++ ROS 2 wrappers. It tracks recent Unreal releases, with the main branch on 5.8. Its `settings.json` is a single file that both configures the vehicle and is read by the game at startup, which makes the launch contract trivially simple. Most importantly, it works today in this workspace, and the entire SITL, SLAM and recording stack is built around it.

### 1.3 What Project AirSim offers

Project AirSim is Microsoft's own successor to AirSim, discontinued internally and released under the MIT licence, now developed publicly by IAMAI Simulations, a team drawn from the original AirSim engineers. Against the three defects above it answers as follows.

The transport is a publish and subscribe topology over NNG, with topics on port 8989 and services on port 8990, documented at `sitl_ws/src/ue5/ProjectAirSim/docs/command_line_switches.md:24-25`. Sensor data is pushed rather than polled, so the sensor count no longer multiplies the round trip cost.

The clock is a first-class, configurable, fixed-step object. Four types exist, `steppable`, `real-time`, `engine-driven` and `external-clock`, documented at `sitl_ws/src/ue5/ProjectAirSim/docs/config_scene.md:74-99` and `sitl_ws/src/ue5/ProjectAirSim/docs/scene/sim_clock.md`, with `step-ns` giving deterministic fixed sim-time steps and `pause-on-start` and the SimClock client API giving genuine pause and manual step control. The ratio of `step-ns` to `real-time-update-rate` scales execution faster or slower than real time deterministically.

The ROS 2 bridge publishes the simulation clock on the global `/clock` topic as `rosgraph_msgs/msg/Clock`, at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:180`, on a dedicated timer whose period defaults to 0.02 s, at `:144-145` and `:997-1005`. This corrects the load-bearing defect in Cosys-AirSim, whose bridge publishes on the private `~/clock` and therefore reaches no sim-time consumer at all without a remap.

The vehicle catalogue is broader, covering quadrotor, hexarotor, VTOL quad-x tailsitter and VTOL quad tiltrotor airframes, alongside rovers, which suits the immediate use cases.

### 1.4 A correction to the prior assessment, and the evidence for it

[`context/simulation-engine-survey.md`](../context/simulation-engine-survey.md) §5.1.3, compiled 2026-08-01, records the conclusion that Project AirSim has no ArduPilot support today and that `sitl_ws/src/ue5/ProjectAirSim/Architecture.md` is aspirational on the point. That conclusion is wrong and is corrected here.

ArduPilot is implemented. The evidence is a C++ controller class `ArduCopterApi` deriving from `VTOLFWApiBase` at `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/include/arducopter_api.hpp:32`, its implementation at `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/arducopter_api.cpp`, an `ardupilot-api` member of the controller type enumeration at `sitl_ws/src/ue5/ProjectAirSim/client/python/projectairsim/src/projectairsim/schema/robot_config_schema.jsonc:71`, an `ardupilot-settings` block with `ardupilot-ip` and `ardupilot-udp-port` at `:539-545`, a conditional schema rule making those settings mandatory for that controller type at `:644-647`, and four worked example configurations plus two ArduPilot parameter files under `sitl_ws/src/ue5/ProjectAirSim/client/python/example_user_scripts/ardupilot/`.

The survey was misled by the documentation, and the documentation is still wrong. `sitl_ws/src/ue5/ProjectAirSim/docs/controllers/controllers.md:5` continues to state that Project AirSim supports Simple Flight, PX4 Autopilot and Manual Controller, omitting ArduPilot entirely, and the controller comparison table at `:29-35` does the same. The authoritative source here is the code and the schema, not the prose. This is the second occasion on which a Project AirSim document has disagreed with the tree, and the general lesson, which is recorded in the context files, is that this project's prose lags its source.

### 1.5 The risks that the investigation surfaced, stated plainly

Three findings temper the case, and none of them is a reason to abandon the migration, but all three must be planned for rather than discovered during implementation.

The ArduPilot path is not known to work on the current tree. GitHub issue 21 is frequently cited as evidence of a functioning integration. It is not. It is a question opened on 2025-07-14 by a user asking how to connect Project AirSim to ArduPilot, and it remains open. The maintainer `jonyMarino` replied the same day with unpublished documentation of the `ardupilot-settings` surface and the explicit caveat that there is a good time since he tested ArduPilot for this project and that he is not sure it is working on the latest version. A second user reported on 2025-09-16 that Project AirSim crashes after running SITL, and the only reply, on 2026-12-02, was to try WSL1. That same documentation also records that no communication channel exists allowing control commands to be sent from AirSim to ArduPilot, which mirrors the stubbed remote procedure call state getters already documented for Cosys-AirSim in [`context/airsim.md`](../context/airsim.md) §4. The correct expectation is therefore that the ArduPilot path is unproven rather than broken, and Phase 6 exists to prove it before anything downstream is trusted.

The reported crash has a plausible mechanism, and knowing it changes how it should be diagnosed. `ArduCopterApi::ReciveRotorsControls` at `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/arducopter_api.cpp:200-219` loops until it receives exactly twenty two bytes, with no exit other than success, and it runs synchronously inside `Robot::UpdateControlInput` inside `Scene::Impl::SceneTick` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/scene.cpp:1002`. If ArduPilot is absent or slow to start, the scene tick thread blocks indefinitely and the entire simulation freezes while the error log fills at roughly ten hertz. That presents to a user as a hang or a crash, and it is a startup ordering problem rather than a protocol fault. It is the direct reason Phase 6 raises the delay between starting the game and starting the bridge, and the reason `djinn start sitl2` must not launch ArduPilot before the simulator is listening.

The ROS 2 bridge discards the simulator's per-sample timestamps. Every bridged message header is stamped by `MakeHeader` at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:108-119`, whose entire body is `header.stamp = node.get_clock()->now()`, and the payload's own `time_stamp` field is never consulted anywhere in the file. The simulator does carry that field, serialised by `MSGPACK_DEFINE_MAP(time_stamp, orientation, angular_velocity, ...)` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/message/imu_message.cpp:39` and exposed as JSON at `:135`, with the same for images at `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/message/image_message.hpp:82`. This is a regression against Cosys-AirSim, which copies `imu_data.time_stamp` and `img_response.time_stamp` verbatim into the header. Left unaddressed it reintroduces the exact quantisation defect that motivated the migration, now applied to the camera and inertial streams rather than to `/ap/*`, because a bridge running under `use_sim_time` would stamp from the `/clock` value it last published itself. Phase 7 addresses it directly.

The source build has an open blocker. `sitl_ws/src/ue5/ProjectAirSim/samples/standalone_sim` is a member of the ALL target at `sitl_ws/src/ue5/ProjectAirSim/samples/standalone_sim/CMakeLists.txt:20-23`, and its link fails under the Unreal toolchain because the prebuilt `libonnxruntime.so` carries transitive dependencies on `libz.so.1` and the sysroot `libstdc++.so.6` that are absent from the link line, while `CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY` at `sitl_ws/src/ue5/ProjectAirSim/unreal-linux-toolchain.cmake:58` prevents resolution outside the sysroot. This is GitHub issue 173, opened 2026-07-31 and open at the time of writing, and the maintainer's own workaround is to comment out `sitl_ws/src/ue5/ProjectAirSim/samples/CMakeLists.txt:19`.

### 1.6 Why Project AirSim is nonetheless the right choice

The migration is justified because the defects it fixes are structural and the defects it introduces are local.

The polling transport, the private clock topic and the inert lockstep are properties of Cosys-AirSim's design that cannot be repaired without rewriting its bridge and its firmware layer. Project AirSim replaces all three with a push transport, a global `/clock` on a dedicated timer, and a configurable fixed-step clock with pause and step. Against that, the header stamping defect is nine lines in one function of a bridge that this workspace will vendor as a submodule and can therefore patch, and the build blocker is one commented line with an upstream-endorsed workaround.

Decisively, the ArduPilot wire protocol is unchanged. `ArduCopterApi::SendSensorData()` at `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/arducopter_api.cpp:691-839` emits the same JSON document that ArduPilot's `SITL::AirSim` backend parses, using the identical key names `timestamp`, `imu.angular_velocity`, `imu.linear_acceleration`, `pose.roll`, `pose.pitch`, `pose.yaw`, `gps.lat`, `gps.lon`, `gps.alt`, `velocity.world_linear_velocity` and `rng.distances`, every one of which appears in the thirteen-entry parse table at `ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.h:139-153`. The example configuration uses `ardupilot-udp-port` 9003 and `local-host-udp-port` 9002, at `sitl_ws/src/ue5/ProjectAirSim/client/python/example_user_scripts/ardupilot/sim_config/robot_ardu_quadrotor.jsonc`, which are exactly the ports this workspace already uses. The consequence is that the entire ArduPilot side of the stack, the `--model airsim-copter` flight dynamics backend, the `sim_port_in` and `sim_port_out` arguments, the DDS bridge and every `/ap/*` topic, continues to work without modification. The migration therefore touches the simulator and the bridge, and leaves the autopilot alone.

---

## 2. Codebase context the change rests on

This section exists so that an implementer, human or machine, can execute Section 3 without re-deriving anything. It summarises the current stack, the target stack, and the four interfaces where they meet.

### 2.1 The current Cosys-AirSim call chain

| Step | Artefact | Effect |
|---|---|---|
| 1 | `djinn:284-292`, the bare `start sitl` branch | `start_simulation "nature"`, spawn `sitl_bridge_container`, then three `gnome-terminal` windows |
| 2 | `scripts/helpers/sitl.sh:24-28` `start_simulation` | `xhost +local:docker`, `spawn_container_if_needed airsim_container shandilya1998/nrt_airsim:0.0.1 x86_64` |
| 3 | `scripts/helpers/docker.sh:38-40` | for `airsim_container` only, sources `sitl_ws/scripts/start.sh` with the UE `Environments` directory as `$1` |
| 4 | `sitl_ws/scripts/start.sh:9-20` | `docker run` with `--gpus=all`, `$1` mounted at `/ws`, and `$(pwd)/settings.json` bind-mounted to `/home/ue4/Documents/AirSim/settings.json` |
| 5 | `sitl_ws/scripts/run_airsim.sh:5` | `iexec airsim_container "/ws/StonePineForest/Linux/StonePineForest.sh -settings=/ws/settings.json -renderoffscreen"` |
| 6 | `ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh:5` | `iexec_sitl sitl_bridge_container "ros2 launch controllers sitl.launch.py use-sim-time:=True"` |
| 7 | `ros_ws/src/controllers/launch/sitl.launch.py` | after a 3 s timer, the AirSim bridge, ArduPilot SITL, the ffmpeg encoder and the managed recorder |

The settings file the game actually loads is `sitl_ws/src/ue5/AirSim/Unreal/Environments/settings.json`, because step 3 mounts that directory at `/ws` inside `airsim_container` and step 5 passes `-settings=/ws/settings.json`. The file is git-ignored and therefore a per-machine artefact.

### 2.2 The four interfaces that matter

The migration is best understood as four contracts, of which one is preserved untouched and three are replaced.

The autopilot contract is preserved. ArduPilot sends an eleven-channel `uint16` PWM packet to the simulator's receive port and receives a JSON sensor document on its own port. `ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.h:65-75` fixes the defaults `airsim_ip` 127.0.0.1, `airsim_sensor_port` 9003 and `airsim_control_port` 9002, and `SIM_AirSim.cpp` advances ArduPilot's clock by the delta between successive packet timestamps at `:323-325`.

The settings contract is replaced. Cosys-AirSim reads one `settings.json` at game startup through a `-settings=` command line flag. Project AirSim has no equivalent flag, as `sitl_ws/src/ue5/ProjectAirSim/docs/command_line_switches.md` confirms by its absence. The game starts empty and waits, and a client loads a scene. The ROS 2 bridge is capable of being that client, through its `scene_config` and `sim_config_path` parameters documented at `sitl_ws/src/ue5/ProjectAirSim/docs/ros/ros2.md:96-99`. This inverts the startup ordering and is the single largest structural change made here.

The ROS 2 contract is replaced. Cosys-AirSim publishes under `/airsim_node/<Vehicle>/...`. Project AirSim republishes native `/Sim/...` topics under a configurable root defaulting to `/ProjectAirsim`, with the rewrite performed at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:316-318` and the two roots declared as parameters at `:135-137`.

The calibration contract is preserved in value and replaced in expression. The camera intrinsics, the image dimensions and the camera to inertial extrinsics must produce the same numbers, but the keys and the units differ, and §2.5 gives the exact mapping.

### 2.3 Project AirSim architecture, in brief

The full reference is written to [`context/project-airsim-architecture.md`](../context/project-airsim-architecture.md) as part of this work. The summary needed here is as follows.

Three layers exist. `core_sim`, `simserver`, `physics`, `sitl_ws/src/ue5/ProjectAirSim/rendering/scene`, `mavlinkcom` and `vehicle_apis` compile to static archives collectively called the sim libs, rooted at `sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt:42`. An Unreal plugin at `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Plugins/ProjectAirSim` links those archives by path. Clients reach the simulator over NNG, in Python at `sitl_ws/src/ue5/ProjectAirSim/client/python/projectairsim` and in C++ at `sitl_ws/src/ue5/ProjectAirSim/client/cpp`.

The coupling between the sim libs and the plugin is by file copy rather than CMake export. Every sim lib target carries a `POST_BUILD` command copying its output and headers into `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Plugins/ProjectAirSim/SimLibs/<target>/<Debug|Release>`, the destination defined at `sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt:70`. The sim libs must therefore be built before Unreal Build Tool is invoked, which is the root cause of the "modules are missing or built with a different engine version" reports in GitHub issues 83 and 129.

The clock is configured per scene. The `clock` block admits `type` from `steppable`, `real-time`, `engine-driven` and `external-clock`, `step-ns` defaulting to 20000000, `real-time-update-rate` defaulting to 3000000, and `pause-on-start`, documented at `sitl_ws/src/ue5/ProjectAirSim/docs/config_scene.md:74-79`. The ArduPilot examples use `steppable` with `step-ns` 3000000 and `real-time-update-rate` 3000000, which is a 3 ms fixed step advancing at real time and is numerically identical to the Cosys-AirSim physics period of `physics_loop_period_ = 3000000LL`.

The ArduPilot controller mirrors the Cosys-AirSim structure. `ArduCopterApi::Update()` at `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/arducopter_api.cpp:152-196` calls `AdvanceSimTime()`, then `SendSensorData()`, then `ReciveRotorsControls()`, and the last of these blocks in a retry loop at `:204-215` until a full rotor control packet arrives. Genuine lockstep is present in the source but commented out, at `:669-689`. The coupling is therefore the same accidental handshake that Cosys-AirSim provides, which is important because it means the ArduPilot side behaves as it does today.

### 2.4 The ROS 2 bridge, parameters and topics

Package `projectairsim_ros2_cpp`, `ament_cmake`, ROS 2 Humble, manifest at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/package.xml`. It depends on `geometry_msgs`, `nav_msgs`, `rclcpp_action`, `rclcpp`, `rosgraph_msgs`, `rosidl_runtime_cpp`, `sensor_msgs`, `std_msgs` and `tf2_ros`, and pulls in `sitl_ws/src/ue5/ProjectAirSim/client/cpp` by `add_subdirectory` at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/CMakeLists.txt:73-83`. The executable is `projectairsim_ros2_cpp_node`.

Critically, this package exists only on the `main` branch. It is absent from tag `v0.2.0` of 2026-06-01, verified by `git ls-tree -d --name-only v0.2.0 ros/`, which lists only `sitl_ws/src/ue5/ProjectAirSim/ros/examples`, `sitl_ws/src/ue5/ProjectAirSim/ros/examples_externals` and `sitl_ws/src/ue5/ProjectAirSim/ros/node`. It was added by commit `7fb9c566` on 2026-07-15. The consequence for Phase 1 is that the submodule cannot be pinned to the latest release and thus, the latest main must be pinned for now.

The parameters set are as follows, defaults from `sitl_ws/src/ue5/ProjectAirSim/docs/ros/ros2.md:91-107`.

| Parameter | Default | Role here |
|---|---|---|
| `address` | `127.0.0.1` | unchanged, the simulator shares the host network |
| `port_topics` | `8989` | unchanged |
| `port_services` | `8990` | unchanged |
| `scene_config` | empty | set, so the bridge is the primary client that loads the scene |
| `sim_config_path` | the example directory | set to the workspace configuration directory |
| `delay_after_load_sec` | `2.0` | raised, because the StonePineForest map is heavier than Blocks |
| `publish_clock_period_sec` | `0.02` | lowered to `0.005`, a 200 Hz clock, for the reasons derived in §2.4.1 |
| `projectairsim_topic_root` | `/Sim` | unchanged |
| `ros_topic_root` | `/ProjectAirsim` | unchanged, with consumer topics remapped instead |
| `publish_tf` | `true` | set false, because the SLAM stack broadcasts its own `map` to `camera` transform |
| `vehicle_name` | `Drone1` | set to `Copter`, matching the existing vehicle name |

The clock publisher is created unconditionally at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:179-180` with `rclcpp::QoS(10)`, which is RELIABLE by default and therefore satisfies ArduPilot's RELIABLE `/clock` DataReader, whose QoS is recorded in [`context/sitl-time-synchronisation.md`](../context/sitl-time-synchronisation.md). The timer is armed only once a scene is loaded, at `:997-1000`, and each tick performs a `RequestSimTime` round trip at `:984`.

One transport constraint shapes every workflow built on this bridge and must be stated before it is discovered the hard way. The topic channel is an `nng_pair0` socket, at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/topic_manager.cpp:250,291-293`, and pair-0 is strictly one to one. Only one topic client may be connected at a time, which `sitl_ws/src/ue5/ProjectAirSim/docs/ros/ros.md:52` acknowledges by warning that the ROS bridge and a separate mission script cannot connect simultaneously. The consequence for this workspace is that once the ROS 2 bridge is up, no Python client script may connect alongside it, and any scripted mission must be driven through the bridge's own services and action rather than through a second client. This is a genuine regression against Cosys-AirSim, whose msgpack remote procedure call server accepts many concurrent clients.

The service channel is a separate socket and a separate topology. The server opens `nng_rep0` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/service_manager.cpp:187` and the client opens `nng_req0` at `sitl_ws/src/ue5/ProjectAirSim/client/cpp/ProjectAirsimClientLib/src/Client.cpp:459`, both over TCP on port 8990, and request-reply admits many clients. The distinction matters because the clock is carried by the service channel rather than the topic channel, and the next subsection depends on it.

#### 2.4.1 The cost of a clock tick, and the period that follows from it

The bridge does not receive the simulation clock, it asks for it. `PublishClock` at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:981-995` performs a synchronous `RequestSimTime` and publishes whatever comes back, so the choice of `publish_clock_period_sec` is a choice about how often to pay for a service round trip. Deciding it on evidence rather than on the default requires knowing what one round trip costs, what the simulator can actually resolve, and what the consumer needs.

The cost is small and the reason is that nothing on the path does any work. On the client side `Client::Impl::Request` at `:581-595` wraps `RequestAsync` at `:597-621`, which appends the call to `list_pending_request_entry_` and signals a condition variable at `:614`, so a dedicated sending thread wakes and transmits, at `:716-771`. The wait is condition-variable driven throughout, with no polling interval anywhere on the path, since the half-second `wait_until` at `:744` and `:805` are idle backstops that a `notify_all` preempts. On the server side the request is served by NNG asynchronous input and output, with sixty four concurrent job contexts created at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/service_manager.cpp:114` and `:197`, so the handler runs on an NNG worker thread and never on the scene tick thread. The handler itself is `Scene::Impl::SimGetTime` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/scene.cpp:665`, whose entire body is `return sim_time_;`, a single field read. What remains is therefore one TCP loopback round trip, of order thirty to sixty microseconds, three thread handoffs at roughly five to twenty microseconds each, and the serialisation of a request and a response of a few dozen bytes. The estimate is one hundred to three hundred microseconds per call, and it should be treated as an estimate until check B2a measures it, because it is dominated by scheduler latency rather than by anything the code controls.

That cost is charged to the node's executor. `main` at `:1401-1412` calls `rclcpp::spin`, a single-threaded executor, so the clock timer's blocking wait occupies the one executor thread for the duration of the call. Critically it does not delay the sensor streams, because Project AirSim topic payloads are delivered on the client's own `TopicReceiveThreadProc` at `sitl_ws/src/ue5/ProjectAirSim/client/cpp/ProjectAirsimClientLib/src/Topics.cpp:262`, and the handler registered by `Subscribe` at `:266-270` publishes to ROS directly from that thread. The only things a clock tick can delay are the bridge's own services and its `MoveOnPath` action. At a two hundred hertz period of five milliseconds and three hundred microseconds per call, the executor duty cycle is six per cent, which leaves those unaffected in practice.

Three bounds then fix the period. The lower bound is the simulation step. The scene advances `sim_time_` in increments of `step-ns`, which §3.5 sets to three milliseconds, so polling faster than every three milliseconds returns repeated values and buys nothing. The upper bound is the consumer. ArduPilot's `AP_DDS_Client::update_topic` stamps every `/ap/*` message with the last `/clock` value it received, and the fastest `/ap/*` publisher in this stack is `/ap/imu/experimental/data` at a measured 162 Hz, a period of 6.17 ms, so any clock period at or above 6.17 ms guarantees that some pairs of consecutive inertial samples share a stamp. Below it, in a fixed-rate model, no two consecutive samples can fall in the same clock interval and duplication is eliminated rather than merely reduced. The third bound is prudence, since the period must sit far enough inside that window that jitter in either rate does not cross an edge.

Five milliseconds is the round figure inside the window, at 1.67 times the simulation step and 0.81 of the inertial period, and `publish_clock_period_sec` is therefore set to `0.005`. The default of `0.02` was rejected because 50 Hz against a 162 Hz publisher yields runs of three to four identical stamps, which is a threefold improvement on the 14 Hz of Cosys-AirSim but is still the same defect in kind, and the whole point of Phase 7 is to end it rather than to shrink it. Ten milliseconds was rejected for the same reason with a smaller factor. Three milliseconds, matching the simulation step exactly, was rejected because it sits on the lower bound with no margin, so any jitter in the wall timer against the step schedule produces duplicate reads for no benefit over five milliseconds.

One hazard on this path deserves recording because its consequence is severe and its cause is invisible. The services socket is opened with `NNG_OPT_RECVTIMEO` of 300000 ms and `NNG_OPT_REQ_RESENDTIME` disabled, at `sitl_ws/src/ue5/ProjectAirSim/client/cpp/ProjectAirsimClientLib/src/Client.cpp:275-279` and `:462-467`, so a request whose response is lost blocks the calling thread for five minutes with no retry. Because the caller here is the single executor thread, one lost response silently freezes every bridge service and action for five minutes while the sensor streams continue normally. It is not a consequence of raising the clock rate, since it is present at any period, and it is recorded here and as defect G15 in [`context/project-airsim-architecture.md`](../context/project-airsim-architecture.md) §G so that a five minute stall is recognised for what it is rather than investigated as a deadlock.

### 2.5 The calibration mapping, derived and verified

The SLAM stack expects specific numbers, and reproducing them exactly is what makes the two simulators comparable. Two conversions are required and both were derived from source and cross-checked.

The inertial noise model is the same model in both simulators, taken from the same MPU 6000 reference, but Cosys-AirSim accepts engineering units and converts internally while Project AirSim accepts SI units directly. Cosys-AirSim's conversions are visible at `sitl_ws/src/ue5/AirSim/AirLib/include/sensors/imu/ImuSimpleParams.hpp:51-72`, namely angular random walk from degrees per root hour by dividing by the root of 3600 and multiplying by pi over 180, gyroscope bias stability from degrees per hour by dividing by 3600 and multiplying by pi over 180, velocity random walk from milli-g by multiplying by gravity over 1000, and accelerometer bias stability from micro-g by multiplying by 1e-6 and by gravity. Project AirSim performs no conversion, reading the JSON keys straight into SI-valued struct members whose defaults at `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/sensors/imu.hpp:33-51` carry the conversion arithmetic in comments only.

The proof that the two are the same model is that Project AirSim's own example values reproduce Cosys-AirSim's defaults exactly. A gyroscope angle random walk of 0.30 degrees per root hour converts to 8.726646e-05 and the example carries 8.72644e-05. A gyroscope bias stability of 4.6 degrees per hour converts to 2.230143e-05 and the example carries 2.23014e-05. A velocity random walk of 0.24 milli-g converts to 2.353596e-03 and the example carries 2.353e-03. An accelerometer bias stability of 36 micro-g converts to 3.530394e-04 and the example carries 3.53e-04.

Applying the same conversions to the values in the live `settings.json` gives the table that Phase 5 writes into the robot configuration.

| Cosys-AirSim key | Current value | Conversion | Project AirSim key | Value to write |
|---|---|---|---|---|
| `AngularRandomWalk` | 2.0 deg per root hour | divide by root 3600, multiply by pi over 180 | `gyroscope.angle-random-walk` | 5.817764e-04 |
| `GyroBiasStabilityTau` | 300 | none, seconds in both | `gyroscope.tau` | 300 |
| `GyroBiasStability` | 20.0 deg per hour | divide by 3600, multiply by pi over 180 | `gyroscope.bias-stability` | 9.696274e-05 |
| `VelocityRandomWalk` | 1.2 milli-g | multiply by 9.80665, divide by 1000 | `accelerometer.velocity-random-walk` | 1.176798e-02 |
| `AccelBiasStabilityTau` | 600 | none, seconds in both | `accelerometer.tau` | 600 |
| `AccelBiasStability` | 500 micro-g | multiply by 1e-6 and by 9.80665 | `accelerometer.bias-stability` | 4.903325e-03 |

An independent confirmation of the gyroscope figure exists in the workspace already. `ros_ws/src/slam/ext/basalt/data/sitl_calib.json:116` carries `gyro_noise_std` of 0.0005818, which is the converted angular random walk to four significant figures. A discrepancy also exists and is recorded rather than silently corrected, because it predates this work. The same file carries `accel_noise_std` of 0.020 at `:111`, whereas the converted velocity random walk is 0.0117680. The Basalt calibration therefore models the accelerometer as noisier than the simulator generates it. This plan does not change that value, because doing so would alter the behaviour of a component that did not ask for the change, and because the conservative direction of the error makes it harmless. It is flagged so that a future calibration exercise does not mistake it for a transcription of the simulator settings.

The camera to inertial extrinsics require no change at all, which was verified by decoding the calibration rather than by assuming it. `sitl_calib.json:4-12` gives a translation of 0.5, 0.0 and 0.1 metres and a quaternion of 0.27060, 0.27060, 0.65328 and 0.65328. Converting that quaternion to a rotation matrix maps the camera optical boresight, the positive Z axis of the optical frame, onto 0.7071, 0.0 and 0.7071 in the body frame, which in the north east down convention is forward and forty five degrees down. That is precisely the `"Pitch": -45` of the current `settings.json`, and the translation is precisely its `"X": 0.50, "Y": 0, "Z": 0.10`. Project AirSim expresses the same pose as an `origin` block with `xyz` in metres and `rpy-deg` in degrees, in the same north east down frame, confirmed by `sitl_ws/src/ue5/ProjectAirSim/docs/config_robot.md:586` and `:607`. The camera origin to write is therefore `"xyz": "0.5 0.0 0.1"` with `"rpy-deg": "0 -45 0"`, and neither `sitl_calib.json` nor `ros_ws/src/slam/orb_slam3/config/Monocular/sitl.yaml` needs any edit.

The intrinsics also carry over unchanged. Both SLAM configurations assume a 640 by 480 pinhole camera with focal lengths of 320 and a principal point at 320 and 240, which is the exact pinhole model of a 90 degree horizontal field of view at 640 pixels width, since 320 divided by the tangent of 45 degrees is 320. Setting `width` 640, `height` 480 and `fov-degrees` 90 in the Project AirSim capture settings reproduces it.

One value does change and must be tracked. `sitl.yaml:28` declares `Camera.fps: 15`, which was chosen to match the measured 15.7 Hz that the Cosys-AirSim image path achieved rather than its nominal 20 Hz. Project AirSim expresses camera rate as `capture-interval` in seconds. Phase 5 sets it to 0.05, a nominal 20 Hz, and Phase 10 measures what is actually achieved so that `Camera.fps` can be corrected from evidence rather than from the nominal figure.

### 2.6 Blast radius, every consumer of what changes

The set of files that reference the Cosys-AirSim topic namespace is small and was enumerated exhaustively.

| File and line | Reference | Treatment |
|---|---|---|
| `ros_ws/src/controllers/launch/sitl.launch.py:62` | includes `airsim_node.launch.py` | untouched, the new launch file is a sibling |
| `ros_ws/src/controllers/launch/sitl.launch.py:78` | remaps `/airsim_node/clock` to `/clock` | untouched, unnecessary in the new file |
| `ros_ws/src/controllers/launch/sitl.launch.py:153` | encoder input `/airsim_node/Copter/front_center_Scene/image` | new file uses the Project AirSim topic |
| `ros_ws/src/controllers/launch/video.launch.py:44` | same topic as a node parameter | untouched, it is an independent workflow |
| `djinn:262` | ORB-SLAM3 `camera-topic` argument | a new `sitl2` branch carries the new topic, the old branch is untouched |
| `djinn:272` | Basalt `camera-topic` argument | as above |

No C++ source in `ros_ws` hardcodes an AirSim topic, so the SLAM nodes, the controllers and the recorder are all agnostic and require no recompilation.

---

## 3. The implementation, phase by phase

The phases are ordered by dependency rather than by the numbering of the original task list. Two reorderings and five additions were made after investigation, and the reasons are stated in §3.0 so that the deviation is deliberate and reviewable.

### 3.0 Evaluation of the proposed task list

The proposed plan was sound in outline and needed the following corrections.

The Docker image was to be built first and the submodule added second. That order cannot work, because the Dockerfile builds Project AirSim from a source tree and the enumeration of its dependencies is a property of that tree. The submodule is therefore added first, as Phase 1, and the image second, as Phase 2.

`run_airsim.sh` was to gain an argument selecting a settings file for each simulator. Project AirSim has no settings file and no `-settings=` flag. The script still gains a target argument, because it must choose between two container names and two binary paths, but the scene selection moves to the ROS 2 bridge, which is the only component that can perform it.

`run_ardupilot_airsim2_ros_sitl.sh` was to be created as a sibling of `run_ardupilot_airsim_ros_sitl.sh`. The two would have differed in one identifier, so the existing script gains a target argument instead and no new file is created. §3.6 carries the reasoning.

Six steps were absent and are added. The ROS 2 bridge must be built into `sitl_ws/install`, otherwise `ros2 launch` cannot resolve the node, which becomes §3.4.3. The runtime dependencies of `projectairsim_ros2_cpp` must be baked into the `nrt` image rather than installed by `rosdep` at build time, for the reason recorded as gotcha 6 of [`context/sitl-workspace-migration.md`](../context/sitl-workspace-migration.md), which becomes §3.4.4. The header stamping defect must be patched or the migration fails at its primary objective, which becomes Phase 7. The `standalone_sim` build blocker must be worked around, which becomes part of Phase 7. The submodule cannot be pinned to the latest release, which becomes Phase 1. And the spawn origin cannot be derived from any file in either tree, so a manual procedure against the map asset is required, which becomes Phase 11.

Two further points are settled decisions rather than findings, and are recorded so that the reasoning is not reopened. The engine version is fixed at 5.2 rather than 5.7, so that Project AirSim's own release binaries and a locally packaged game remain mutually runnable, and §3.2 gives the evidence. The Project AirSim quadrotor parameter file is a required artefact rather than an optional one, and §3.5.2 shows that it layers on top of the existing defaults rather than replacing them.

The naming convention `airsim2` is adopted throughout as requested, and every new artefact is additive, so that no existing command changes behaviour.

### 3.1 Phase 1, add Project AirSim as a submodule

The submodule was added ahead of the rest of the work for two reasons, both of which apply to the reader of this document as much as they did to its author. The tree is the authority for every claim in §2, so having it locally lets each citation be opened and checked rather than trusted, and a repository of this size is expensive to clone repeatedly, so cloning it once and holding it under version control is cheaper than fetching it for each investigation.

The latest commit on `main` and not a release tag is pinned as the submodule HEAD. The latest release tag, `v0.2.0` of 2026-06-01, predates the ROS 2 C++ bridge, which arrived with commit `7fb9c566` on 2026-07-15, and without that package there is no ROS 2 integration whatsoever. Pinning to `main` is a deliberate acceptance of a moving upstream in exchange for the only viable bridge.

```bash
cd $NRT_WS
git submodule add https://github.com/iamaisim/ProjectAirSim.git sitl_ws/src/ue5/ProjectAirSim
```

The resulting `.gitmodules` stanza sits alongside the existing Cosys-AirSim entry, which is retained.

```
[submodule "sitl_ws/src/ue5/ProjectAirSim"]
	path = sitl_ws/src/ue5/ProjectAirSim
	url = https://github.com/iamaisim/ProjectAirSim.git
```

Note that the URL is HTTPS rather than the SSH form used by the existing submodules, because this is a third-party public repository to which the workspace has no push access, and an SSH URL would require the container to hold a key that grants nothing. No `-b` branch is recorded either, so the submodule is pinned to a commit rather than tracking a moving branch, which is the behaviour wanted from a third-party tree that this workspace patches locally.

The result, verified by `git submodule status`, is commit `7fb9c566515901112c8d246fd02685bc58c369e5`, which `git describe` renders as `v0.2.0-6-g7fb9c56`, so the pin is six commits past the latest release. The tree carries no submodules of its own, so `--recursive` is unnecessary. The full working tree measures 537 MB.

Backwards compatibility. Purely additive. `sitl_ws/scripts/build.sh` scopes `colcon` with `--base-paths src/ue5/AirSim/ros2/src`, so the new tree is invisible to the existing build until §3.4.3 changes that deliberately. The Cosys-AirSim submodule is untouched and `djinn build airsim-sitl` continues to build exactly what it built before.

### 3.2 Phase 2, the Docker image

The need is a container that can compile the sim libs, build the Unreal plugin, package a game, run that game headlessly, and open the Unreal editor interactively so that the map inspection of Phase 11 can be carried out without a second machine. The artefacts live in a new directory `docker/airsim`, and the image is tagged `shandilya1998/nrt_airsim:0.0.2`, one patch version above the Cosys-AirSim image so that both can coexist.

The engine version is 5.2 and the choice is not a preference. Project AirSim's own release binaries are cut against 5.2, which the log excerpt in upstream issue 75 makes explicit by reporting the engine banner `5.2.1-0+UE5`, and running a prebuilt release alongside a locally packaged game is a requirement of this workspace rather than an option. Building against 5.7 would make the two mutually incompatible, because a packaged Unreal game and its plugin binaries are tied to the engine version that produced them. The README does state support for 5.2 and 5.7 at `sitl_ws/src/ue5/ProjectAirSim/README.md:92`, so both are defensible in isolation, and of the two only 5.2 also runs what upstream ships. The `BASE_IMAGE` build argument survives so that the decision can be revisited without editing the Dockerfile.

The base image was initially Epic's published `ghcr.io/epicgames/unreal-engine:dev-5.2` and is now the locally built `shandilya1998/nrt:unreal`, which is the same engine version compiled from source on an Ubuntu 22.04 userland. The engine version argument above is unaffected by that move and stands exactly as written. The reason for the move, the mechanism and its cost are §3.2.1, and the reader who only wants the current state may take from here that the base is a local image built by `docker/scripts/build_unreal.sh` before `nrt_airsim:0.0.2` is built on top of it.

Two further statements of the supported version exist in the tree and neither contradicts this choice. `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Blocks.uproject:3` declares `"EngineAssociation": "5.1"`, and `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Public/UnrealSimLoader.h:88-89` hard-codes a supported major of 5 and minor of 1, with `UnrealSimLoader.cpp:66-72` printing a startup warning for anything else. That warning is non-fatal, so a 5.2 run works while announcing an unsupported engine, and the message should not be mistaken for the cause of a later failure. This is defect G9 of [`context/project-airsim-architecture.md`](../context/project-airsim-architecture.md) §G.

The decisive design fact is the toolchain switch. `sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt:27-39` selects the compiler purely on whether `UE_ROOT` is set in the environment. Set, the build uses the engine's bundled clang through `sitl_ws/src/ue5/ProjectAirSim/unreal-linux-toolchain.cmake`. Unset, it hard-codes `clang-13` and `clang++-13` from the system. Because the plugin's static archives are later linked into Unreal by Unreal Build Tool, the engine toolchain is the correct choice, and the workspace's prior experience makes the reason concrete.

The `<atomic>` failure that cost three stacked fixes in the Cosys-AirSim image, recorded in [`context/airsim-docker-build.md`](../context/airsim-docker-build.md), does not recur here, and the reason is specific rather than hopeful. Cosys-AirSim's `sitl_ws/src/ue5/AirSim/build.sh` smuggled `--sysroot` through `-DCMAKE_CXX_FLAGS` and supplied no C++ standard library include path, so clang had no libc++ headers. Project AirSim sets `CMAKE_SYSROOT` properly at `sitl_ws/src/ue5/ProjectAirSim/unreal-linux-toolchain.cmake:49-51` and then explicitly adds the engine's own libc++ include directories at `:55`, while `sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt:33` adds the matching library directory. That is exactly the remedy recorded as the fallback option in the Cosys-AirSim context file, applied preemptively upstream.

`sitl_ws/src/ue5/ProjectAirSim/setup_linux_dev_tools.sh` is deliberately not executed. Its LLVM version map at `:28-33` yields a non-existent `llvm-toolchain-noble-13` suite on Ubuntu 24.04, which is GitHub issues 120 and 173, and under `UE_ROOT` the system clang it installs is never used. Its package list is instead inlined, minus the clang and libc++ entries. Note that it calls `sudo` on every line, which is not an obstacle in this base image but is a signal about how the image is meant to be used, and that signal is the subject of the next paragraph.

The second decisive design fact is the user. The Epic development image does not run as root. Its lineage is the `ue4-docker` project, whose prerequisites layer creates the account with `useradd --create-home --home /home/ue4 --shell /bin/bash --uid 1000 ue4`, clears its password, adds it to the `sudo` group and then switches to it with `USER ue4`, and Epic's own images derive from that work. The same shape is visible inside this workspace, since `sitl_ws/src/ue5/AirSim/docker/Dockerfile_source` installs `sudo` explicitly at `:20`, performs every `apt-get` under `USER root` at `:4`, then drops to `USER ue4` at `:75` before touching the engine, sets `ENV UE_ROOT=/home/ue4/UnrealEngine` at `:76`, and clones and builds under `/home/ue4`. Unreal Build Tool and the editor both write into the engine tree and into `$HOME`, and running them as root leaves artefacts that the `ue4` account cannot subsequently overwrite, so the pattern is a requirement rather than a convention. This Dockerfile follows it exactly, doing its package installation as root and ending on `USER ue4`.

The third decisive design choice is that the image contains no Project AirSim source at all. It is a toolchain image, carrying the engine, the compilers, the Vulkan runtime and the desktop libraries the editor needs, and nothing else. The source arrives through the `/ws` bind mount at container start, and every compilation happens inside a running container.

Three reasons make this the only defensible option. The workspace already works this way, since `ARCHITECTURE.md` §3 and [`context/sitl-workspace-migration.md`](../context/sitl-workspace-migration.md) establish that workspaces are mounted rather than baked precisely so that an edit needs a recompile and never an image rebuild. Phase 7 carries a local patch to the bridge, and baking a `git clone` into the Dockerfile would compile upstream instead of the patched tree, which is exactly the trap recorded in [`context/airsim-docker-build.md`](../context/airsim-docker-build.md), where the Cosys-AirSim Dockerfile clones upstream fresh and the local submodule's `sitl_ws/src/ue5/AirSim/build.sh` is not what runs. And mechanically, `docker build` cannot reach outside its build context, so a Dockerfile under `docker/airsim` cannot `COPY` from `sitl_ws/src/ue5/ProjectAirSim` without making the whole workspace the context and paying a multi-gigabyte transfer on every build.

```dockerfile
# docker/airsim/Dockerfile
# shandilya1998/nrt:unreal is Unreal Engine 5.2 built on an Ubuntu 22.04 userland by
# docker/scripts/build_unreal.sh, which `djinn init docker airsim2` runs first. Epic's
# own ghcr.io/epicgames/unreal-engine:dev-5.2 is Ubuntu 18.04 and is not usable here,
# because Project AirSim's dependencies require 22.04.
ARG BASE_IMAGE=shandilya1998/nrt:unreal
FROM ${BASE_IMAGE}

USER root
ENV DEBIAN_FRONTEND=noninteractive

# libeigen3-dev short circuits the GitLab clone at
# sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt:275-278.
# zlib1g-dev mitigates the libonnxruntime.so link failure of upstream issue
# 173. ninja-build is the build driver. perl runs OpenSSL's own Configure
# script for the openssl-external target, see §3.2.2. cmake is deliberately
# absent, see the pip install below and §3.2.2.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git gnupg \
        libeigen3-dev lsb-release lsof make ninja-build perl \
        python3 python3-pip python3-venv rsync sudo unzip wget \
        zlib1g zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# CMake >=3.26 for the INSTALL_BYPRODUCTS keyword of the openssl-external
# ExternalProject_Add, capped below 4 because untested against this tree's
# fetched dependencies. See §3.2.2 for the full account.
RUN python3 -m pip install --no-cache-dir 'cmake>=3.26,<4'

# vulkan-tools, not vulkan-utils. The package was renamed at focal and the
# transitional vulkan-utils no longer exists on the jammy base this image now
# uses, so the pre-22.04 name fails to resolve exactly as vulkan-tools did on 18.04.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libvulkan1 vulkan-tools mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        libfontconfig1 libfreetype6 libgtk-3-0 libnss3 libsdl2-2.0-0 \
        libx11-6 libxcursor1 libxext6 libxi6 libxinerama1 libxrandr2 \
        libxss1 libxtst6 x11-apps x11-xserver-utils xauth xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN echo "ue4 ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER ue4

# UE_ROOT is the single switch selecting the engine toolchain at
# sitl_ws/src/ue5/ProjectAirsim/CMakeLists.txt:28-33
ENV UE_ROOT=/home/ue4/UnrealEngine

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=graphics,compute,utility,display
EXPOSE 8989 8990
CMD ["bash"]
```

Four points about that file are worth stating rather than leaving to be inferred.

The `USER root` and `USER ue4` bracketing is load bearing. Every `apt-get` needs root and the base image is not root, so without the first directive the build fails on the first layer. Without the second, the container starts as root and every engine or editor invocation writes root-owned files into `/home/ue4/UnrealEngine` and `/home/ue4/.config`, after which nothing run as `ue4` can rewrite them, and the failure appears much later as an unexplained permission error inside Unreal Build Tool rather than as a container problem.

The package list is split into three layers by purpose rather than merged, so that a later reader can tell why each package is present and can drop the third layer entirely if the editor is ever built into a separate image. The overlap with the base image is deliberate and harmless, since `apt-get install` on an installed package is a no-op, and naming the package is worth more than saving a few seconds of build time.

The `display` capability is added to `NVIDIA_DRIVER_CAPABILITIES`, which the headless-only case does not need but the editor does, because the editor opens a real window on the forwarded X display.

The Vulkan package name is coupled to the base image's Ubuntu release and must be revisited whenever that release changes, in either direction. Ubuntu renamed the package carrying `vulkaninfo` from `vulkan-utils` to `vulkan-tools` at focal, and dropped the transitional `vulkan-utils` after focal. On the Ubuntu 18.04 of Epic's published image only `vulkan-utils` resolves, and on the Ubuntu 22.04 of the current base only `vulkan-tools` does. This is not a hypothetical, since the layer above failed with `E: Unable to locate package vulkan-tools` against the 18.04 base, was changed to `vulkan-utils` while that base was still in use, and was changed back when the base moved to 22.04. Had the base image moved without the second change, the build would have failed on the same layer with the same class of error and the opposite package name. This was verified against the Ubuntu package index, where jammy returns a real page for `vulkan-tools` and reports no such package for `vulkan-utils`.

The upstream `standalone_sim` blocker is consequently not handled here. Because no compilation happens at image build time, the workaround belongs to the source tree and is applied by Phase 7 directly in the submodule.

Six preconditions cannot be checked from the development container and are listed in Phase 10 as host-side validation. Whether the base image exists, which was originally a question about pulling `ghcr.io/epicgames/unreal-engine:dev-5.2` and is now a question about building `shandilya1998/nrt:unreal`, whether `$UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64` is populated in that image, since `sitl_ws/src/ue5/ProjectAirSim/unreal-linux-toolchain.cmake:26-28` raises a fatal error when it is not, whether `$UE_ROOT/Engine/Source/ThirdParty/Unix/LibCxx/include/c++/v1` exists, since without it the libc++ injection is inert and the Cosys `<atomic>` failure returns, whether the image carries a prebuilt `Engine/Binaries/Linux/UnrealEditor`, since the manual procedures of Phase 11 depend on it and building it from source inside the container is a multi-hour operation if it is absent, whether the Docker daemon's filesystem has room for an Installed Build, and whether `password.txt` holds a usable token. The last two arrive with §3.2.1 and are the ones to check first, because they gate the engine build that everything else now sits on.

Backwards compatibility. A new directory and a new image tag. The Cosys-AirSim image `nrt_airsim:0.0.1` and its build path through `sitl_ws/src/ue5/AirSim/docker/build_airsim_image.py` are untouched, and they remain untouched under §3.2.1, which pins a different engine on a different base and shares no build step with them.

#### 3.2.1 The Unreal base image on an Ubuntu 22.04 userland

The image described above initially took Epic's published `ghcr.io/epicgames/unreal-engine:dev-5.2` as its base, and the first attempt to build it failed on the Vulkan layer with `E: Unable to locate package vulkan-tools`. Diagnosis established that Epic's development images are built on Ubuntu 18.04, where the package carrying `vulkaninfo` is still named `vulkan-utils`. The evidence is direct rather than inferred, since `Engine/Extras/Containers/Dockerfiles/linux/build.sh:54` of branch 5.2 hard-codes `--build-arg 'BASEIMAGE=nvidia/opengl:1.0-glvnd-devel-ubuntu18.04'`. Renaming the package was therefore a correct immediate fix that treated a symptom.

The underlying condition is that Project AirSim requires an Ubuntu 22.04 userland while Epic's published image provides 18.04. `sitl_ws/src/ue5/ProjectAirSim/Architecture.md:420` states that 22.04 carries full development and runtime support. Note that the submodule's own claims disagree with one another, since `README.md:19` says Ubuntu 22, both `docs_external/README.md:29` and `docs/development/use_source.md:42` say 20.04, and `.github/copilot-instructions.md:27` implies a 24.04 sandbox by symlinking clang-18 onto clang-13. None of them says 18.04, so the published base sits outside every claimed support window regardless of which claim is taken as authoritative. The 22.04 target follows `Architecture.md`, which is the most specific and the most recent.

Two remedies were available and the choice between them is the substantive decision of this subsection. The engine could be rehosted, by copying the prebuilt Installed Build out of Epic's 18.04 image into a 22.04 base and relying on glibc's forward compatibility, since binaries linked against an older glibc run on a newer one. That is cheap, on the order of an hour, and it leaves any engine component genuinely bound to an 18.04 library to surface later at runtime. Or the engine could be rebuilt from source against a 22.04 base, which is expensive but eliminates the class of failure outright. The second was chosen deliberately, because a dependency fault discovered during a simulation run is far more costly to diagnose than a long build performed once, and the rehosting option is recorded here so that it is not silently reproposed as an optimisation later.

The mechanism is small, because Epic ships the very Dockerfile that produces the published image, at `Engine/Extras/Containers/Dockerfiles/linux/dev/Dockerfile`, and the Ubuntu release it targets is a single build argument. Pointing that argument at the 22.04 variant of the same NVIDIA image is the whole of it, and everything else below is plumbing.

The structural insight that determines the shape of that plumbing is that the Dockerfile does not consume a local engine checkout. Its `source` stage takes `GIT_REPO` and `GIT_BRANCH` as build arguments and clones the engine inside the image with `git fetch --depth 1`, authenticated by BuildKit secrets that `git-credential-helper-secrets.sh` reads from `/run/secrets`. The build context is consequently four files totalling 32 KB, namely the `Dockerfile`, that credential helper, `set-changelist.py` and `split-components.py`. Vendoring those four files into `docker/unreal` therefore captures the entire input to the build. An Unreal Engine submodule was considered and rejected on exactly this ground, since it would carry several gigabytes of source that no build step reads.

The four files are copied from branch 5.2 at commit `02dc8dbdd89f749cd5500376e9bb87271bf64848`. The three helper scripts are byte-for-byte upstream. The Dockerfile carries a provenance header and exactly two deltas, both marked `NRT` in place, and the whole file was diffed against the pristine checkout to confirm that nothing else moved. Notably the `ue4` user creation at the prerequisites stage is untouched, which is what allows `docker/airsim/Dockerfile` to keep the `USER root` and `USER ue4` bracketing described above unchanged.

Delta one declares a default for the base image, replacing a bare `ARG BASEIMAGE`.

```dockerfile
ARG BASEIMAGE=nvidia/opengl:1.0-glvnd-devel-ubuntu22.04
FROM ${BASEIMAGE} as prerequisites
```

That tag was verified to exist, returning HTTP 200 from the registry, while `1.0-glvnd-devel-ubuntu24.04` returns 404, so 22.04 is the newest available variant of this image family and the choice is also the ceiling. The default is stated in the Dockerfile rather than left to the build script so that the Ubuntu release is greppable from the file that depends on it.

Delta two removes the glibc DSO patch layer, which upstream installs as follows.

```dockerfile
RUN add-apt-repository -y ppa:slonopotamus/glibc-dso && \
	apt-get update && \
	apt upgrade -y libc6 && \
	rm -rf /var/lib/apt/lists/* && …
```

That PPA publishes bionic, focal, hirsute, impish and devel, and publishes no jammy, verified by the jammy `Release` file returning HTTP 404 while bionic and focal return 200. On a 22.04 base `apt-get update` therefore fails on a missing `Release` file and the layer aborts, which makes this a hard blocker rather than a preference and means Epic's file cannot be used unmodified. The layer is deleted and the tunable that follows it is retained.

```dockerfile
ENV GLIBC_TUNABLES=glibc.rtld.dynamic_sort=2
```

Retaining the tunable while dropping the patch is correct rather than merely harmless. The PPA exists to backport the depth-first DSO sorting algorithm to the glibc 2.27 of the 18.04 base. That algorithm landed upstream in glibc 2.35, which is what 22.04 ships, and `dynamic_sort=2` is its default there. The patch is thus redundant on jammy for precisely the same reason it is unavailable, namely that jammy already has it.

Authentication is by GitHub username and personal access token, and not by the SSH key this workspace otherwise uses, because the clone step mounts two BuildKit secrets both declared `required`. An SSH agent does not substitute. `username.txt` holds `shandilya1998` and `password.txt` holds a token whose account must be linked to Epic Games in order to read `EpicGames/UnrealEngine`. Both live at the workspace root, are mode 600, and are added to `.gitignore`, verified with `git check-ignore`. The repository only ever sees the placeholder `REPLACE_WITH_GITHUB_PERSONAL_ACCESS_TOKEN`, which is the point of shipping a placeholder rather than a real value.

`docker/scripts/build_unreal.sh` drives the build. It is a port of Epic's `Engine/Extras/Containers/Dockerfiles/linux/build.sh` from the same commit, and the branch resolution, the build arguments and the secret plumbing are upstream's, preserved so that the script remains recognisable against its source and so that a future engine bump behaves as Epic intends. The release argument defaults to 5.2, matching the pin argued above.

The branch resolution is upstream's and is subtle enough to record, since a release value containing a dash, or not containing exactly two dots, is treated as a branch name outright, and anything else has `-release` appended. Consequently `5.2` resolves to branch `5.2`, which was verified to exist, while `5.2.1` would resolve to the tag `5.2.1-release`.

Five deltas from upstream are deliberate. Only the `dev` image is built, rather than upstream's five, since the runtime, slim, pixel-streaming and multi-user-server variants are unused here. The base image is the 22.04 variant. The credential files are read from `$NRT_WS` rather than from the working directory. The result is tagged `shandilya1998/nrt:unreal`. And the build is never pushed, because the image embeds the Unreal Engine and the licence does not permit redistribution, which is also the reason `docker/scripts/docker-build.sh` could not be reused, its `--push` being unconditional.

Two guards were added that upstream has no need of.

```bash
if [[ -n "$(docker images -q "$IMAGE" 2>/dev/null)" && "${UNREAL_FORCE_REBUILD:-0}" != "1" ]]; then
    echo "[build_unreal.sh] $IMAGE already exists, skipping the rebuild."
    echo '[build_unreal.sh] Set UNREAL_FORCE_REBUILD=1 to rebuild it anyway.'
    return 0 2>/dev/null || exit 0
fi
```

```bash
if grep -q 'REPLACE_WITH_GITHUB_PERSONAL_ACCESS_TOKEN' "$NRT_WS/password.txt"; then
    echo "[build_unreal.sh] $NRT_WS/password.txt still holds the placeholder."
    exit 1
fi
```

The first exists because the engine is compiled from source into an Installed Build, so repeating that implicitly on every `djinn init docker airsim2` would cost hours, and `UNREAL_FORCE_REBUILD=1` opts back in. The second exists because the token is not consumed until the clone step deep into the build, so without it a forgotten token is discovered only after a long and wasted build rather than immediately.

The `djinn` branch that calls it is as follows.

```bash
            elif [[ "$3" == "airsim2" ]]; then
                if [[ -n "$4" ]]; then
                    echo "============ BUILDING PROJECT AIRSIM Image ============="
                    build_airsim2_docker_image "$4"
                else
                    echo "============ BUILDING UNREAL ENGINE Image ============="
                    if ! "$NRT_WS/docker/scripts/build_unreal.sh"; then
                        echo "Unreal Engine image build failed, not building Project AirSim on a missing base."
                        exit 1
                    fi
                    echo "============ BUILDING PROJECT AIRSIM Image ============="
                    build_airsim2_docker_image
                fi
```

The script is executed rather than sourced, which departs from the surrounding convention at `djinn:232` and elsewhere, and the departure is deliberate. `build_unreal.sh` sets `set -e` and `set -x`, and sourcing it would leak both into `djinn`, tracing every later command and turning any subsequent non-zero exit into an abort of the whole CLI. Execution as a subprocess contains both. The failure branch is explicit so that Project AirSim is never built against a base image that does not exist.

The corresponding default in `scripts/helpers/sitl.sh` moves accordingly, the parameter and its override semantics being unchanged.

```bash
    base_image="${1:-shandilya1998/nrt:unreal}"
```

The cost is real and is the price of the decision recorded above. The engine is compiled with `-set:WithDDC=true`, which precompiles the derived data cache, and `sitl_ws/src/ue5/ProjectAirSim/docs/development/dev_setup_linux.md:83` puts a native Installed Build at roughly 200 GB and four or more hours, with the containerised build at least that once layer storage is counted. The workspace filesystem showed 130 GB free at the time of writing, and the Docker daemon runs on the host so its storage may differ, which is why free space is written as precondition P5 in Phase 10 rather than assumed. The DDC setting was left at upstream's value rather than disabled, since disabling it would shorten the build materially at the cost of shader compilation on every editor launch, and that is a tradeoff to make deliberately rather than silently.

The following were verified during implementation, in the development container, without a Docker daemon.

| # | Check | Result |
|---|---|---|
| I1 | Branch `5.2` exists on `EpicGames/UnrealEngine` and is reachable over SSH from this workspace | Passes, resolves to `02dc8dbdd89f749cd5500376e9bb87271bf64848` |
| I2 | `nvidia/opengl:1.0-glvnd-devel-ubuntu22.04` exists | Passes, HTTP 200. The 24.04 variant returns 404 |
| I3 | `ppa:slonopotamus/glibc-dso` has no jammy suite | Confirmed, jammy `Release` returns 404 while bionic and focal return 200 |
| I4 | `glibc.rtld.dynamic_sort` is native to glibc 2.35 with default 2 | Confirmed against the glibc 2.35 release notes |
| I5 | Every package in Epic's two prerequisite lists resolves on jammy | Passes for all checked, including `libglu1`, `libasound2`, `x11-xkb-utils`, `xfonts-base` and `libxv1` |
| I6 | `vulkan-tools` exists on jammy and `vulkan-utils` does not | Confirmed against the Ubuntu package index |
| I7 | The vendored Dockerfile differs from upstream only in the two intended deltas | Confirmed by diff against the pristine checkout |
| I8 | `djinn`, `scripts/helpers/sitl.sh` and `docker/scripts/build_unreal.sh` parse | Passes, `bash -n` clean on all three |
| I9 | The branch resolution port reproduces upstream's mapping | Passes for `5.2`, `5.2.1`, `ue5-main` and a full commit hash |
| I10 | `username.txt` and `password.txt` are ignored by git | Passes, `git check-ignore` matches both and neither appears in `git status` |

Backwards compatibility. `docker/unreal`, `docker/scripts/build_unreal.sh` and the two credential files are all new, and the credential files are ignored, so no tracked state changes on their account. The optional fourth argument of `djinn init docker airsim2` is preserved exactly, and supplying it now additionally skips the engine build, which is correct because an explicit override names the base outright and cannot want a locally built one, so `djinn init docker airsim2 ghcr.io/epicgames/unreal-engine:dev-5.7` behaves as it did before. The bare invocation gains the engine build, which is the intended change. `build_airsim_docker_image`, which builds the Cosys-AirSim image on `dev-5.5`, is untouched, so `djinn init docker airsim` and `djinn start sitl` are unaffected and the two images continue to pin different engines on purpose. `docker/scripts/docker-build.sh` is not modified, so every other image build retains the `--push` behaviour it depends on.

Deliberately not done. The Unreal Engine submodule was not added, for the reason given above. The `-set:WithDDC=true` setting was not changed, for the reason given above. And the engine version was not moved off 5.2, since the argument at the head of §3.2 is unaffected by the change of base and is not reopened here.

#### 3.2.2 CMake version and the OpenSSL `ExternalProject_Add` byproducts gap

An audit of the image against every dependency the submodule fetches at configure time, prompted by review of §3.2, found two defects in the Build toolchain layer, neither of which the build had previously reached because the first masked the second.

`CMakeLists.txt:386` passes `INSTALL_BYPRODUCTS` to the `ExternalProject_Add` that builds `openssl-external`, declaring `${OPENSSL_CRYPTO_LIBRARY}` and `${OPENSSL_SSL_LIBRARY}` as files the target's install step produces. That keyword requires CMake 3.26, confirmed against CMake's own 3.26 release notes, which state it was added so that `ExternalProject_Add` install-step outputs could be declared to generators such as Ninja. `apt-get install cmake` on the Ubuntu 22.04 base of §3.2.1 resolves to `3.22.1-1ubuntu1`, confirmed against `packages.ubuntu.com/jammy/cmake`, which predates that release. `ExternalProject_Add` is implemented with `cmake_parse_arguments`, whose default behaviour on an unrecognised keyword is to fold it into the unparsed-argument list rather than to raise an error, so the configure step neither fails nor warns, and the byproduct declaration is simply absent from the generated Ninja graph. The consequence is that any target linking `OPENSSL_CRYPTO_LIBRARY` or `OPENSSL_SSL_LIBRARY` carries no dependency edge back to the `openssl-external` install step, and under Ninja's parallel scheduling such a target can be built before OpenSSL's static archives exist, a failure that reproduces intermittently and not at all under a serial `make`.

Walking every `ExternalProject_Add` and `FetchContent_Declare` in the submodule, `nng`, `assimp`, `msgpack`, `tinygltf`, `nlohmann-json`, `googletest`, `onnxruntime`, `Eigen3` and `openssl`, confirms that OpenSSL alone shells out to a tool the image does not already carry. Every other dependency goes through `cmake --build`, already covered by `ninja-build`, or fetches headers or a prebuilt binary needing no build at all. `CMakeLists.txt:349-367` shows why OpenSSL is the exception, since both branches of `OPENSSL_CONFIGURE_COMMAND`, the `UE_ROOT` branch and its `else()`, invoke `<SOURCE_DIR>/Configure` directly, and that `Configure` is OpenSSL's own perl script rather than a CMake-generated one. `perl` is absent from both `docker/unreal/Dockerfile` and `docker/airsim/Dockerfile`, so once the Ninja graph defect above is fixed the build reaches this step for the first time and fails on a missing interpreter. The two defects are fixed together so that a single rebuild suffices.

The apt package is removed from the Build toolchain layer rather than pinned by a second, versioned apt source such as Kitware's, and CMake is installed instead with `python3 -m pip install --no-cache-dir 'cmake>=3.26,<4'` in its own layer immediately after, while still `USER root` so the binary lands in `/usr/local/bin`, ahead of `/usr/bin` in `PATH` and world-executable exactly as an apt-installed binary would be. `python3-pip` is already a dependency for other reasons, so this needs no new apt source, and the same command is upstream's own documented route to a working CMake, given verbatim at `docs/client_setup.md:58` and `:123` for the Windows client build. `perl` is added as a fourth entry to the same apt layer.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git gnupg \
        libeigen3-dev lsb-release lsof make ninja-build perl \
        python3 python3-pip python3-venv rsync sudo unzip wget \
        zlib1g zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir 'cmake>=3.26,<4'
```

The upper bound on the pip floor is not cosmetic. PyPI's `cmake` package, checked at the time of this writing, lists `4.4.2` as its latest release, so an unbounded `>=3.26` would silently take CMake 4 rather than the newest 3.x release. CMake's own 4.0 release notes state that compatibility was removed only for `cmake_minimum_required()` calls whose policy version is below 3.5. This project's own floor of `3.15.0` at `CMakeLists.txt:18` clears that comfortably, but the floors declared inside `nng`, `assimp`, `msgpack`, `tinygltf`, `nlohmann-json` and `googletest` are not checked, none of them being vendored in this tree, all being fetched fresh at configure time. Capping below 4 trades an unbounded, unchecked risk for a small and revisitable one, namely that the pin must be widened deliberately if a future dependency bump requires CMake 4, rather than crossing that boundary silently on the next `docker build`.

The following were verified by consulting primary sources, continuing the numbering of the table in §3.2.1 since both address what cannot be checked from the development container without a Docker daemon.

| # | Check | Result |
|---|---|---|
| I11 | The apt `cmake` package version on Ubuntu 22.04 (jammy) | `3.22.1-1ubuntu1`, confirmed against `packages.ubuntu.com/jammy/cmake` |
| I12 | The CMake release that introduced `INSTALL_BYPRODUCTS` | 3.26, confirmed against CMake's 3.26 release notes and the `ExternalProject` module documentation |
| I13 | The latest release on PyPI's `cmake` project, at time of writing | `4.4.2`, confirmed against the PyPI project page, which is why the pip install is bounded below 4 |
| I14 | The `cmake_minimum_required()` policy floor below which CMake 4.0 removed compatibility | 3.5, confirmed against CMake's 4.0 release notes; this project's own `3.15.0` floor clears it, its fetched dependencies are not checked |
| I15 | Every `ExternalProject_Add` and `FetchContent_Declare` in the submodule, and which of them shell out to a build tool outside `cmake --build` | Confirmed by grep across the tree; `openssl-external` alone invokes `<SOURCE_DIR>/Configure`, OpenSSL's own perl script |

Backwards compatibility. Both changes are confined to `docker/airsim/Dockerfile`, which carries no Project AirSim source per §3.2, so no tracked file outside that Dockerfile changes. The image tag `shandilya1998/nrt_airsim:0.0.2` is unchanged, so every caller in `scripts/helpers/sitl.sh` and `djinn` that names it is unaffected. `docker/unreal/Dockerfile` and `docker/scripts/build_unreal.sh`, which build the base image, are untouched, since neither `cmake` nor `perl` is needed until Project AirSim itself is configured, which happens only inside a running `airsim2_container`. The Cosys-AirSim image and its `dev-5.5` toolchain share no layer with this one and are unaffected.

Deliberately not done. Kitware's APT repository was not added, since a pip-installed wheel achieves the same version floor without a second apt source or a GPG key import, and upstream's own documented remedy for this exact class of problem is the pip route. The exact CMake release was not pinned within the `3.26,<4` range, since no defect specific to a particular release in that range was found, and a floor with a ceiling is sufficiently reproducible without also being needlessly brittle to a yanked release.

### 3.3 Phase 3, `djinn` wiring

Three helper functions are added to `scripts/helpers/sitl.sh`, mirroring the existing Cosys-AirSim helpers rather than generalising them, so that no existing caller changes.

```bash
# The default base is the locally built engine image of §3.2.1 rather than Epic's
# published dev-5.2, which is Ubuntu 18.04.
build_airsim2_docker_image() {
    base_image="${1:-shandilya1998/nrt:unreal}"
    docker build "$NRT_WS/docker/airsim" \
        --build-arg BASE_IMAGE="$base_image" \
        -t shandilya1998/nrt_airsim:0.0.2
}

start_simulation2() {
    environment=$1
    xhost +local:docker
    spawn_container_if_needed airsim2_container "shandilya1998/nrt_airsim:0.0.2" "x86_64"
}

stop_simulation2() {
    docker stop airsim2_container
}
```

The platform is `linux/amd64` alone, unlike the multi-architecture builds elsewhere, because the Unreal Engine base image and the prebuilt ONNX Runtime tarball at `sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt:402` are x86-64 only.

`scripts/helpers/docker.sh` gains one branch in `spawn_container_if_needed`, immediately after the existing `airsim_container` branch, and the existing branch is left exactly as it is.

```bash
        if [[ "${name}" == "airsim_container" ]]; then
            source $NRT_WS/sitl_ws/scripts/start.sh airsim
        elif [[ "${name}" == "airsim2_container" ]]; then
            source $NRT_WS/sitl_ws/scripts/start.sh airsim2
```

This changes the calling convention of `sitl_ws/scripts/start.sh`, which today receives the UE `Environments` directory as `$1`. The script is rewritten to take a target name and to derive both the mount and the image from it, and because `spawn_container_if_needed` is the only caller in the tree, the change is contained.

```bash
#!/bin/bash
# $1 selects the simulator target, one of airsim or airsim2.
# Defaults to airsim so that any caller written against the previous
# positional-directory convention still reaches the Cosys-AirSim container.

target="${1:-airsim}"

if [[ "$target" == "airsim2" ]]; then
    name="airsim2_container"
    image="shandilya1998/nrt_airsim:0.0.2"
    mount="$NRT_WS"
    settings_mount=()
else
    name="airsim_container"
    image="shandilya1998/nrt_airsim:0.0.1"
    mount="$NRT_WS/sitl_ws/src/ue5/AirSim/Unreal/Environments"
    settings_mount=(-v "$mount/settings.json:/home/ue4/Documents/AirSim/settings.json")
fi

XAUTH=/tmp/.docker.xauth
docker run -d -it -v "$mount":/ws \
    --gpus=all \
    -v ./.ssh:/root/.ssh \
    -e DISPLAY=$DISPLAY \
    -e XAUTHORITY=/home/ue4/.Xauthority \
    -e QT_GRAPHICSSYSTEM=native \
    -v $XAUTH:$XAUTH:rw \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v /home/$UID/.Xauthority:/home/ue4/.Xauthority \
    "${settings_mount[@]}" \
    --env="DISPLAY" --net=host \
    --privileged --name $name $image bash
```

Two differences between the targets deserve statement. The Cosys-AirSim container mounts only the UE `Environments` directory, so `/ws` inside it is that directory and `-settings=/ws/settings.json` resolves. The Project AirSim container mounts the whole workspace root at `/ws`, matching every other runtime container in the workspace as described in `ARCHITECTURE.md` §3, so that the game binary, the scene configuration and the build script are all reachable by absolute path. The settings bind mount is dropped for `airsim2` because Project AirSim has no settings file.

`djinn` then gains three branches, each placed beside its Cosys-AirSim counterpart.

```bash
            elif [[ "$3" == "airsim2" ]]; then
                echo "============ BUILDING PROJECT AIRSIM Image ============="
                # $4 optionally overrides the Unreal base image, so that
                # `djinn init docker airsim2 ghcr.io/epicgames/unreal-engine:dev-5.7`
                # is available without editing the Dockerfile.
                if [[ -n "$4" ]; then
                    build_airsim2_docker_image "$4"
                else
                    build_airsim2_docker_image
                fi
```

```bash
        elif [[ "$2" == "airsim2" ]]; then
            if [[ -n "$3" ]]; then
                start_simulation2 $3
            else
                start_simulation2 "nature"
            fi
```

The `down` branch also gains a case, because its existing `airsim` case names the container explicitly.

```bash
        if [[ "$2" == "airsim" ]]; then
            docker stop airsim_container && docker rm airsim_container
        elif [[ "$2" == "airsim2" ]]; then
            docker stop airsim2_container && docker rm airsim2_container
```

Backwards compatibility. Every change is a new branch in an `if` chain or a new function. The one edit to existing behaviour is the calling convention of `sitl_ws/scripts/start.sh`, whose sole caller is updated in the same change, and whose default preserves the Cosys-AirSim path for any caller written against the old convention.

### 3.4 Phase 4, building the game and the bridge

#### 3.4.1 Porting StonePineForest

The delta between a Cosys-AirSim project and a Project AirSim project is small and fully documented at `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md`, and the reference implementation is `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks`. The steps are as follows.

The project is copied without its build products, since `Binaries`, `Intermediate`, `Saved`, `Build` and `DerivedDataCache` are Cosys-AirSim artefacts compiled against a different plugin and a different engine.

```bash
rsync -a \
  --exclude Binaries --exclude Intermediate --exclude Saved \
  --exclude Build --exclude DerivedDataCache --exclude .vscode \
  $NRT_WS/sitl_ws/src/ue5/AirSim/Unreal/Environments/StonePineForest/ \
  $NRT_WS/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/
rm -rf $NRT_WS/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/Plugins/AirSim
cp -r $NRT_WS/sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Plugins/* \
      $NRT_WS/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/Plugins/
```

The three plugins copied are `ProjectAirSim`, which is the simulator, and `Drone` and `Rover`, which are content-only plugins carrying the meshes that the simulator spawns at runtime, per `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md:9-24`.

`StonePineForest.uproject` is edited to declare the new plugin and to drop the old one. The engine association moves to the version the image provides.

```json
{
	"FileVersion": 3,
	"EngineAssociation": "5.2",
	"Category": "",
	"Description": "",
	"Modules": [
		{
			"Name": "StonePineForest",
			"Type": "Runtime",
			"LoadingPhase": "Default"
		}
	],
	"TargetPlatforms": [
		"Linux"
	],
	"Plugins": [
		{
			"Name": "ProjectAirSim",
			"Enabled": true
		},
		{
			"Name": "SunPosition",
			"Enabled": true
		}
	]
}
```

The `AdditionalDependencies` entry naming `AirSim` is removed, because the Project AirSim plugin is not a module dependency of the game module, as `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Source/Blocks/Blocks.Build.cs` demonstrates by depending only on `Core`, `CoreUObject`, `Engine` and `InputCore`.

`Config/DefaultEngine.ini` gains the game mode override, which is the load-bearing edit. Without it the plugin loads but never starts a simulation server.

```ini
[/Script/EngineSettings.GameMapsSettings]
EditorStartupMap=/Game/StonePineForest/Maps/Mountains_Map
GameDefaultMap=/Game/StonePineForest/Maps/Mountains_Map
GlobalDefaultGameMode=/Script/ProjectAirSim.ProjectAirSimGameMode
```

`Config/DefaultGame.ini` gains the cook directives, because the plugin content is referenced only at runtime and would otherwise be omitted from a packaged binary, per `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md`.

```ini
[/Script/UnrealEd.ProjectPackagingSettings]
+DirectoriesToAlwaysCook=(Path="/ProjectAirSim")
+DirectoriesToAlwaysCook=(Path="/Drone")
+DirectoriesToAlwaysCook=(Path="/Rover")
+MapsToCook=(FilePath="/Game/StonePineForest/Maps/Mountains_Map")
```

`Source/StonePineForest.Target.cs` and `Source/StonePineForestEditor.Target.cs` are aligned with the Blocks targets, which set `DefaultBuildSettings = BuildSettingsVersion.Latest` and `IncludeOrderVersion = EngineIncludeOrderVersion.Latest`. The existing `Source` directory is retained, which conveniently satisfies step 3 of `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md`, since StonePineForest already has a C++ module and does not need a dummy class generated.

The world settings game mode override, step 2B of `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md`, cannot be set from a text editor because it lives in the map asset. The documentation recommends setting it in both places. The `DefaultEngine.ini` setting alone is sufficient for a packaged headless run, and the map-level override is recorded in §3.11.4 as a conditional editor step to perform if the drone fails to spawn.

#### 3.4.2 The game build script

```bash
#!/bin/bash
# sitl_ws/scripts/build_airsim2_game.sh
# Builds a Project AirSim Unreal environment inside airsim2_container.
# $1 selects the project, defaulting to StonePineForest. Further environments
# are added by extending the case statement.

set -e

project="${1:-StonePineForest}"
config="${2:-Development}"

PAS_ROOT=/ws/sitl_ws/src/ue5/ProjectAirSim

case "$project" in
    StonePineForest|Blocks) ;;
    *) echo "Unsupported project: $project"; exit 1 ;;
esac

cd "$PAS_ROOT"

# The sim libs must exist before Unreal Build Tool runs, because the plugin
# links their static archives by path out of Plugins/ProjectAirSim/SimLibs.
# This is the cause of upstream issues 83 and 129.
if [ ! -d "unreal/Blocks/Plugins/ProjectAirSim/SimLibs" ]; then
    ./build.sh simlibs_release
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

The `BuildCookRun` invocation is copied verbatim in shape from `sitl_ws/src/ue5/ProjectAirSim/build_linux.mk:261-276`, substituting the project and the archive directory, so that it inherits an argument set the upstream project exercises. The archive directory carries the configuration as its last component, `packages/<Project>/<Config>`, which is upstream's own layout at `:270` and which matters because a Development and a Shipping package of the same project would otherwise overwrite one another.

#### 3.4.3 Building the ROS 2 bridge

`sitl_ws/scripts/build.sh` currently scopes discovery to `src/ue5/AirSim/ros2/src`, for the reason recorded as gotcha 2 of [`context/sitl-workspace-migration.md`](../context/sitl-workspace-migration.md), namely that an unscoped build would discover the Cosys-AirSim ROS 1 catkin tree and its stale artefacts. That scoping must be preserved while adding a second base path.

```bash
cd /ws/sitl_ws
rosdep install --from-paths src/ue5/AirSim/ros2/src src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp \
    -y --ignore-src --skip-keys pcl --skip-keys message_runtime --skip-keys message_generation
colcon build \
    --base-paths src/ue5/AirSim/ros2/src src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp \
    --cmake-args -DCMAKE_BUILD_TYPE=Release
```

Naming the ROS 2 package directory rather than `src/ue5/ProjectAirSim/ros` is deliberate. The parent `sitl_ws/src/ue5/ProjectAirSim/ros/` directory also contains `sitl_ws/src/ue5/ProjectAirSim/ros/node`, a ROS 1 catkin package, and `sitl_ws/src/ue5/ProjectAirSim/ros/examples`, likewise catkin, and discovering either would reproduce exactly the failure that the existing scoping was introduced to prevent.

Note that `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/CMakeLists.txt:73-83` pulls in `sitl_ws/src/ue5/ProjectAirSim/client/cpp` by `add_subdirectory`, and that `sitl_ws/src/ue5/ProjectAirSim/client/cpp/CMakeLists.txt:24-86` fetches nlohmann JSON, msgpack, Eigen and NNG from the network at configure time. The first build therefore requires network access from inside the container, which is a departure from the Cosys-AirSim build whose only downloads are the two explicit `wget` calls at the top of the same script.

#### 3.4.4 Baking the runtime dependencies

Gotcha 6 of [`context/sitl-workspace-migration.md`](../context/sitl-workspace-migration.md) establishes a general rule for this workspace. Containers run with `--rm`, so anything a build script installs through `rosdep` lives only in that container's writable layer and is destroyed on stop, while the mounted `install/` tree survives, leaving prebuilt binaries whose shared libraries no longer exist. Every rosdep-resolved runtime dependency must therefore be baked into `docker/ardupilot/Dockerfile`.

The dependencies of `projectairsim_ros2_cpp` that are not already present through `airsim_ros_pkgs` are `nav_msgs`, `rclcpp_action` and `rosgraph_msgs`. All three are members of `ros-humble-desktop`, so if the image installs the desktop metapackage no change is needed, and if it installs a narrower set the three must be added explicitly. Since the base image in which the ros2 bridge is to be built already installss `ros-humble-desktop`, the aforementioned dependencies are already present. However, the trap recorded in the same gotcha applies, namely that a misspelled dependency key is invisible to `rosdep install --simulate`, so the `package.xml` must be read directly rather than trusted through rosdep. An investigation into a container spawned using `shandilya1998/nrt:0.1.1` demonstrates the presence of all three aforementioned packages. Thus, no new update to the image is required.

Backwards compatibility. The game build script is new. The changes to `sitl_ws/scripts/build.sh` add a second base path and leave the first, so `djinn build airsim-sitl` continues to build `airsim_ros_pkgs` and `airsim_interfaces` exactly as before, and additionally builds the new bridge. Any addition to `docker/ardupilot/Dockerfile` is additive and requires an image rebuild, which is already required whenever that file changes.

### 3.5 Phase 5, the configuration files

Two configuration files are created under a new directory `sitl_ws/config/airsim2/`, which is chosen over the Project AirSim example directory so that workspace configuration is version-controlled in the superproject rather than inside a third-party submodule.

The scene configuration reproduces the origin geopoint and the clock of the current setup.

```jsonc
// sitl_ws/config/airsim2/scene_ardu_copter.jsonc
{
  "id": "StonePineForestArduCopter",
  "actors": [
    {
      "type": "robot",
      "name": "Copter",
      "origin": {
        "xyz": "0.0 0.0 -4.0",
        "rpy-deg": "0 0 0"
      },
      "robot-config": "robot_ardu_copter.jsonc"
    }
  ],
  "clock": {
    "type": "steppable",
    "step-ns": 3000000,
    "real-time-update-rate": 3000000,
    "pause-on-start": false
  },
  "home-geo-point": {
    "latitude": -35.363261,
    "longitude": 149.165230,
    "altitude": 583.0
  },
  "segmentation": {
    "initialize-ids": true,
    "ignore-existing": false,
    "use-owner-name": true
  },
  "scene-type": "UnrealNative"
}
```

The geopoint is carried over verbatim from `settings.json:10-14`, and is ArduPilot's own default home location near Canberra, which matters because `ardu_ws/src/ardupilot/Tools/autotest` and the ArduPilot parameter defaults assume it.

The spawn origin needs care and is the one value in this file that cannot be carried over, because Cosys-AirSim has no equivalent. `sitl_ws/src/ue5/ProjectAirSim/docs/config_scene.md:56` warns explicitly that `"0 0 0"` is at the global Unreal origin and not relative to `PlayerStart`, whereas the Cosys-AirSim vehicle spawns at `PlayerStart` by default and the current `settings.json` therefore specifies no vehicle origin at all. StonePineForest is a landscape map whose terrain is nowhere near the world origin, so a literal copy of the Blocks example would drop the copter through the void or bury it in a mountain. Two remedies exist and both should be applied. The `origin` above must be replaced with the world coordinates of the existing `PlayerStart` actor, which no file in either tree records because it lives inside the binary map asset, so Phase 11 gives the procedure for reading it. And `"start-landed": true` should be added to the actor block, documented at `sitl_ws/src/ue5/ProjectAirSim/docs/config_scene.md:60`, so that the copter holds its spawn position until rotor thrust exceeds its weight rather than falling from wherever it appears. Validation check B6a covers this, and the symptom of getting it wrong is a copter that never reports a stable altitude and therefore never arms.

The placeholder written above is `"0.0 0.0 -4.0"` and it is a placeholder rather than a value. It must be replaced by the output of Phase 11 before the scene is used, and check B6a exists to catch the case where it was not.

Note also that the actor key is `robot-config`, used by all fifty two example scenes and declared in `sitl_ws/src/ue5/ProjectAirSim/client/python/projectairsim/src/projectairsim/schema/scene_config_schema.jsonc:85`. The `"ref"` spelling that appears in `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md` is stale documentation and will not validate.

The clock deserves a note. `step-ns` of 3000000 with `real-time-update-rate` of 3000000 gives a 3 ms fixed step advancing at real time, which is numerically the Cosys-AirSim physics period without the `ClockSpeed` of 0.5 that was introduced purely to reduce stamp duplication. That mitigation is deliberately not carried across, because Phase 7 removes the cause rather than the symptom, and because running at full speed is the point of the exercise. If duplication reappears, lowering the ratio remains available.

The robot configuration is derived from `sitl_ws/src/ue5/ProjectAirSim/client/python/example_user_scripts/ardupilot/sim_config/robot_ardu_quadrotor.jsonc`, with the links, joints and actuators taken over unchanged and three blocks rewritten. The controller keeps the example's ports, which already match the workspace.

```jsonc
  "controller": {
    "id": "ArduPilot_Controller",
    "type": "ardupilot-api",
    "ardupilot-settings": {
      "local-host-ip": "127.0.0.1",
      "ardupilot-ip": "127.0.0.1",
      "ardupilot-udp-port": 9003,
      "local-host-udp-port": 9002,
      "use-distance-sensor": false,
      "actuator-order": [
        { "id": "Prop_FR_actuator" },
        { "id": "Prop_RL_actuator" },
        { "id": "Prop_FL_actuator" },
        { "id": "Prop_RR_actuator" }
      ]
    }
  }
```

The port semantics are worth restating because they are easy to invert. `ardupilot-udp-port` 9003 is the destination to which the simulator sends the sensor JSON, and `local-host-udp-port` 9002 is the port on which the simulator binds to receive rotor control. That is the same orientation as the Cosys-AirSim `UdpPort` and `ControlPort` keys documented in [`context/airsim.md`](../context/airsim.md) §3, and it matches `sim_port_in` 9003 and `sim_port_out` 9002 already passed by `sitl.launch.py:134-135`.

`use-distance-sensor` is set false because the current `settings.json` configures no distance sensor and ArduPilot's parse table treats `rng.distances` as optional. The value is in any case inert, which is worth recording so that nobody later wastes time enabling it. The loader reads the key `use-sensor-distance` at `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/arducopter_api.cpp:75-76`, while the schema at `robot_config_schema.jsonc:547` and every shipped example write `use-distance-sensor`, so the flag can never be set true from a valid configuration and the `rng.distances` array is always emitted empty. This is defect G2 in [`context/project-airsim-architecture.md`](../context/project-airsim-architecture.md) §G.

#### 3.5.1 The single-precision geodetic defect, and who it reaches

A second upstream defect is recorded here because it bounds what the ArduPilot path can achieve rather than because this change addresses it. Three things about it are established, namely why it exists, how large it is, and which consumers inherit it.

The defect is a type. `GpsMessage::Impl` declares `float latitude` and `float longitude` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/message/gps_message.cpp:42-43`, and the public constructor at `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/message/gps_message.hpp:25-27` takes them as `float` too, so the narrowing happens at construction and nothing downstream can recover it.

The cause is a message-layer convention applied one field too far. Every scalar in every Project AirSim sensor message is `float`, which is correct for the quantities those messages carry, and `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/message/barometer_message.cpp:38-40` and `magnetometer_message.cpp:41` show the same choice for pressure, altitude and magnetic field. Geodetic angle is the one quantity in the set for which it is wrong, because its magnitude rather than its resolution consumes the exponent. The simulator's own model is not confused about this, since `GeoPoint` declares `double latitude` and `double longitude` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/earth_utils.hpp:22-23`, `GpsData` holds a `GeoPoint` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/sensors/gps.cpp:65-77`, and `NedToGeodetic` at `earth_utils.hpp:100-125` computes in double throughout. The precision is created correctly and discarded at the message boundary. `git log` on the file shows the type has been `float` since the initial Microsoft commit, so this is inherited rather than introduced by IAMAI, and it is defect G3 of [`context/project-airsim-architecture.md`](../context/project-airsim-architecture.md) §G.

The magnitude is a function of position rather than a constant, and is therefore two figures rather than one. A binary32 has a 24-bit significand, so the quantum at a value of magnitude near 2^n is 2^(n-24) degrees. At the workspace home location of latitude −35.363261 and longitude 149.165230 the latitude falls in [32, 64) and quantises at 2^-19, about 1.9e-06 degrees or 0.21 m, while the longitude falls in [128, 256) and quantises at 2^-17, about 7.6e-06 degrees or, at that latitude where a degree of longitude spans about 90.8 km, 0.69 m. The east error is thus over three times the north error, purely because the longitude is numerically larger, and the asymmetry is the fingerprint by which this defect can be recognised in a log. Nothing else in the chain contributes, since `SendSensorData` prints with `std::setprecision(7)` in fixed mode at `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/arducopter_api.cpp:751-753`, a resolution of about 1 cm, and ArduPilot parses into double.

The consumers were enumerated exhaustively. `GpsMessage` is constructed in exactly two places, both inside the sensor, namely the periodic publish at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/sensors/gps.cpp:231-235` and the service-method accessor at `:255-261`, and it is consumed in six.

| Consumer | Site | Effect of the narrowing |
|---|---|---|
| The ArduPilot controller | `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/arducopter_api.cpp:726-727`, reading `gps_sensor_->getOutput()` and then `getData()` | the `gps.lat` and `gps.lon` fields of the JSON sensor packet carry the quantised value, so this is the path that matters here |
| The MAVLink controller | `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/mavlink_api.cpp:2027` | the same defect on the PX4 path, which this workspace does not use |
| The MATLAB controller | `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/matlab_controller_api.cpp:139` | as above, unused here |
| The NNG topic | `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/sensors/gps.cpp:231-238`, published on `<sensor root>/gps` | every client, Python or C++, sees the quantised value |
| The ROS 2 bridge | `CreateGpsPublisher` at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:338-358`, into `sensor_msgs::msg::NavSatFix` | the ROS message field is `double` but is filled from the narrowed JSON, so the type is wider and the content is not |
| The service method | `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/sensors/gps.cpp:255-261`, reached from Python by `Drone.get_gps_data` at `sitl_ws/src/ue5/ProjectAirSim/client/python/projectairsim/src/projectairsim/drone.py:988-1003` | as above |

Two conclusions follow. Every path out of the simulator is affected, so there is no configuration and no alternative accessor that avoids it, and consequently there is nothing to choose between. And the effect on this workspace is bounded, because 0.21 m north and 0.69 m east of position noise sits below the GPS error the stack already models and far below what would prevent arming, EKF convergence or waypoint flight. Cosys-AirSim carries `double` throughout, so this is a real regression, and it is the one respect in which the ArduPilot sensor path is measurably worse than the simulator being replaced.

The fix, should it be wanted later, is three lines, namely widening the two members at `gps_message.cpp:42-43` and the two constructor parameters at `gps_message.hpp:25-27` and `gps_message.cpp:54-56`. It is not applied here because it changes a serialised message layout that every Project AirSim client shares, so a local patch would silently make this workspace's simulator wire-incompatible with any upstream client, which is a far worse trade than 0.69 m of position noise. It belongs upstream, alongside the stamping defect of Phase 7.

One neighbouring defect was found during the same sweep and is recorded so that it is not rediscovered as a mystery. `getData` writes the key `time_utc_millis` at `gps_message.cpp:109`, while `from_json` reads `j.at("time_utc_milli")` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/json_utils.hpp:217`, so any attempt to reconstruct a `GpsMessage` from its own JSON throws `nlohmann::json::out_of_range`. Nothing in the tree currently does that, so the defect is latent, and it is recorded as G14.

The inertial sensor carries the converted noise figures derived in §2.5.

```jsonc
    {
      "id": "IMU1",
      "type": "imu",
      "enabled": true,
      "parent-link": "Frame",
      "accelerometer": {
        "velocity-random-walk": 1.176798e-2,
        "tau": 600,
        "bias-stability": 4.903325e-3,
        "turn-on-bias": "0 0 0"
      },
      "gyroscope": {
        "angle-random-walk": 5.817764e-4,
        "tau": 300,
        "bias-stability": 9.696274e-5,
        "turn-on-bias": "0 0 0"
      }
    }
```

The camera reproduces the intrinsics and the extrinsics that the SLAM configurations already assume.

```jsonc
    {
      "id": "front_center",
      "type": "camera",
      "enabled": true,
      "parent-link": "Frame",
      "capture-interval": 0.05,
      "capture-settings": [
        {
          "image-type": 0,
          "width": 640,
          "height": 480,
          "fov-degrees": 90,
          "capture-enabled": true,
          "streaming-enabled": false,
          "pixels-as-float": false,
          "compress": false,
          "target-gamma": 1.5
        }
      ],
      "origin": {
        "xyz": "0.5 0.0 0.1",
        "rpy-deg": "0 -45 0"
      }
    }
```

A GPS sensor is added with no parameters, matching the current `settings.json`, and the barometer and magnetometer from the example are retained because ArduPilot's sensor fusion expects them and their presence costs nothing.

#### 3.5.2 The ArduPilot parameter file

ArduPilot parameters are the last piece, and the file is a required artefact rather than an optional one. It is copied into the workspace, and the copy is what the launch file loads.

```bash
mkdir -p $NRT_WS/sitl_ws/config/airsim2
cp $NRT_WS/sitl_ws/src/ue5/ProjectAirSim/client/python/example_user_scripts/ardupilot/project-airsim-quad.param \
   $NRT_WS/sitl_ws/config/airsim2/project-airsim-quad.parm
```

Two details of that command are deliberate. The source extension is `.param` and the destination is `.parm`, which is the spelling every other parameter file in this stack uses and the spelling the launch chain already reads. And the file is copied rather than referenced in place, because a path into a third-party submodule would be silently rewritten by the next `git submodule update`, whereas `sitl_ws/config/airsim2/` is workspace-controlled and diffable.

The critical fact about this file, which its own header states and which changes how it must be wired, is that it is an addition and not a replacement. Its second comment line reads `Use it running the following command: python sim_vehicle.py -v ArduCopter -f airsim-copter --add-param-file=<path_to_this_file>`, so upstream layers it on top of the `airsim-copter` frame defaults rather than instead of them. Those frame defaults are exactly what this workspace already loads, since `ardu_ws/src/ardupilot/Tools/autotest/pysim/vehicleinfo.json:199-205` defines `airsim-copter` as `copter.parm` followed by `airsim-quadX.parm`. The upstream instruction and the current workspace configuration therefore agree, and the correct wiring is to append rather than to substitute.

The contents confirm it. The file is 38 lines and sets only attitude control, namely the six `ATC_RAT_{RLL,PIT}_{P,I,D}` rate gains, the three `ATC_ANG_{RLL,PIT,YAW}_P` angle gains, the three `ATC_ACCEL_{R,P,Y}_MAX` limits and the three `ATC_RAT_YAW_{P,I,D}` gains. It sets no frame, no scheduler rate, no sensor lag, no filter and no hover thrust. Everything this stack depends on and that a naive substitution would have silently dropped, namely `FRAME_TYPE 1`, `MOT_THST_HOVER 0.461`, `SCHED_LOOP_RATE 185`, `SIM_GPS1_LAG_MS 0`, `GPS1_DELAY_MS 200` and the six `INS_*_FILTER` and `ATC_RAT_*_FLT*` entries, lives in `airsim-quadX.parm` and survives untouched. What the new file changes is the rate loop tuning, raising `ATC_RAT_RLL_P` from 0.25 to 0.733 and `ATC_RAT_PIT_P` from 0.25 to 0.768, which is the tuning that matches Project AirSim's own rotor coefficients of `coeff-of-thrust` 0.109919 and `coeff-of-torque` 0.040164 at `sitl_ws/src/ue5/ProjectAirSim/client/python/example_user_scripts/ardupilot/sim_config/robot_ardu_quadrotor.jsonc:239-240`.

The `defaults` list passed to `sitl_dds_udp.launch.py` therefore gains a fourth entry and keeps the existing three in order, and §3.6 shows the launch code. One independent confirmation that the airframes agree is worth recording, since it is the assumption on which loading `airsim-quadX.parm` at all depends. `FRAME_TYPE 1` is ArduPilot's quad X, whose motor order is front-right, rear-left, front-left, rear-right, and the example's `actuator-order` at `robot_ardu_quadrotor.jsonc:209-221` is `Prop_FR_actuator`, `Prop_RL_actuator`, `Prop_FL_actuator`, `Prop_RR_actuator`, in that order. The two match element for element, so the eleven-channel PWM packet lands on the rotor the autopilot intends.

Backwards compatibility. Entirely new files in a new directory. `sitl_ws/src/ue5/AirSim/Unreal/Environments/settings.json` is untouched and `djinn start sitl` continues to consume it.

### 3.6 Phase 6, the launch chain

One artefact is created and two are extended in place.

`ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh` gains a target argument rather than acquiring a sibling. A separate `run_ardupilot_airsim2_ros_sitl.sh` was considered and rejected, because the two would have differed in one identifier inside one string, and a duplicated file that differs in a single token is a maintenance liability rather than a separation of concerns. The script is short enough that the branch is clearer than the copy. Note that this file lives under `ardu_ws/scripts/` and not `sitl_ws/scripts/`, since it starts ArduPilot rather than the simulator.

```bash
#!/bin/bash
# $1 selects the simulator target, one of airsim or airsim2, and thereby which
# launch file is used. Defaults to airsim so that the existing no-argument
# caller in `djinn start sitl` is unchanged.
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

target="${1:-airsim}"

if [[ "$target" == "airsim2" ]]; then
    launch_file="sitl2.launch.py"
else
    launch_file="sitl.launch.py"
fi

iexec_sitl sitl_bridge_container "ros2 launch controllers $launch_file use-sim-time:=True"
```

`sitl_ws/scripts/run_airsim.sh` gains a target argument while defaulting to its present behaviour.

```bash
#!/bin/bash
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

target="${1:-airsim}"

if [[ "$target" == "airsim2" ]]; then
    project="${2:-StonePineForest}"
    config="${3:-Development}"
    pkg="/ws/sitl_ws/src/ue5/ProjectAirSim/packages/$project/$config/Linux"
    iexec airsim2_container \
        "$pkg/$project/Binaries/Linux/$project \
         -RenderOffScreen -nosound -unattended -nopause -NoSplash \
         -ResX=640 -ResY=480 -topicsport=8989 -servicesport=8990"
else
    iexec airsim_container \
        "/ws/StonePineForest/Linux/StonePineForest.sh -settings=/ws/settings.json -renderoffscreen"
fi
```

The staged path follows from the archive directory that §3.4.2 passes to `BuildCookRun`, namely `packages/<Project>/<Config>`, into which Unreal Automation Tool stages a `Linux` tree containing the wrapper script `<Project>.sh` beside `<Project>/Binaries/Linux/<binary>`. The binary is named `<Project>` for a Development client and `<Project>-Linux-<Config>` for any other configuration, which is why the `Development` default produces a bare `$project` here and why the reporter in upstream issue 75, packaging Shipping, saw `EolicPark-Linux-Shipping`. The layout is Unreal's standard staging convention rather than anything Project AirSim controls, and check V3 verifies it before `run_airsim.sh` is trusted.

#### 3.6.1 Why the staged ELF is invoked rather than the generated wrapper

The justification has two halves, of which only the first is established fact, and the distinction matters because the second is frequently asserted as though it were the first.

What upstream issue 75 actually reports is a single user's experience. The reporter, running Project AirSim v0.1.1 on Ubuntu 24.04 Server, could not start `EolicPark.sh` in headless rendering mode although the same package ran under a desktop session, and states that the wrapper script required modification to pass its arguments to the binary, having changed its final line to invoke `"$UE_PROJECT_ROOT/EolicPark/Binaries/Linux/EolicPark-Linux-Shipping" -RenderOffScreen -nullrhi` with the flags hard-coded rather than forwarded. The report is credible but it is one report, it was never reproduced by a maintainer, and the wrapper is generated by Unreal Automation Tool rather than by anything in the Project AirSim tree, so there is no line in this repository that can be cited as the cause. Its generated shape is, in substance, a resolution of the script's own directory into `UE_PROJECT_ROOT`, a `chmod +x` on the staged ELF, and an invocation of that ELF with the project name followed by the caller's arguments. Project AirSim itself assumes the forwarding works, since `sitl_ws/src/ue5/ProjectAirSim/run_sim_with_streaming.sh:27` passes `-PixelStreamingURL=...`, `-RenderOffScreen` and `-Log` straight to the wrapper. The two statements are in tension, and the tension is not resolvable from either tree.

What makes the direct invocation correct is therefore not that the wrapper is known to be broken, it is that the wrapper buys nothing and can only lose. Its two contributions are the `chmod` and the argument forwarding. The `chmod` is done once by the build script at §3.4.2, at which point it is no longer needed at every start. The forwarding is the thing that is in doubt. Removing the layer removes the entire class of failure at the cost of one extra path component, and the failure it removes is not a graceful one, because a silently dropped `-RenderOffScreen` in a container with no display manifests as a process that exits with status 1 after printing two lines, which is exactly what the reporter saw and is the least diagnosable failure mode available. The same reasoning does not apply to the Cosys-AirSim branch, which keeps its `.sh` invocation because it demonstrably works today and nothing that works is changed.

One incidental finding from the same issue is load bearing elsewhere in this document. The reporter's output begins `5.2.1-0+UE5`, which is the engine banner of the release binary, and it is the evidence cited in §3.2 that Project AirSim's releases are built against Unreal 5.2.

`ros_ws/src/controllers/launch/sitl2.launch.py` takes `sitl.launch.py` as its archetype and changes only what must change. The encoder include, the recorder include, the three second timer and every existing launch argument are preserved verbatim. No CMake change is needed to install it, because `ros_ws/src/controllers/CMakeLists.txt:83-86` installs the whole `launch` directory rather than an enumerated file list. Three things differ.

The AirSim bridge include is replaced by a node action, because `projectairsim_ros2_cpp` ships no launch file.

```python
    projectairsim_node = launch_ros.actions.Node(
        package="projectairsim_ros2_cpp",
        executable="projectairsim_ros2_cpp_node",
        name="projectairsim_ros2_cpp_node",
        output="screen",
        respawn=False,
        arguments=["--ros-args", "--log-level", log_level],
        parameters=[
            {
                "address": "127.0.0.1",
                "port_topics": 8989,
                "port_services": 8990,
                "scene_config": "scene_ardu_copter.jsonc",
                "sim_config_path": "/ws/sitl_ws/config/airsim2",
                "delay_after_load_sec": 5.0,
                # 200 Hz. Derived in §2.4.1: above the 3 ms simulation step,
                # below the 6.17 ms period of the fastest /ap/* publisher, so
                # no two consecutive ArduPilot samples share a /clock stamp.
                "publish_clock_period_sec": 0.005,
                "publish_tf": False,
                "vehicle_name": "Copter",
            }
        ],
        remappings=[
            (
                "/ProjectAirsim/StonePineForestArduCopter/robots/Copter"
                "/sensors/front_center/scene_camera",
                "/airsim_node/Copter/front_center_Scene/image",
            ),
        ],
    )
```

The source topic is not guessed. It is composed by the rule at `sitl_ws/src/ue5/ProjectAirSim/client/python/projectairsim/src/projectairsim/drone.py:61-121`, where the parent topic is `<world_parent_topic>/robots/<robot_name>`, the sensor root is that plus `/sensors/<sensor_id>`, and a camera appends the image type name drawn from the dictionary at `:87-95`, in which image type 0 maps to `scene_camera`. With the scene `id` of `StonePineForestArduCopter`, the actor `name` of `Copter` and the camera `id` of `front_center` from Phase 5, the native topic is therefore `/Sim/StonePineForestArduCopter/robots/Copter/sensors/front_center/scene_camera`, and the bridge rewrites only the leading `/Sim` to `/ProjectAirsim` at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:316-318`, leaving the remainder intact.

Note also that a camera capture setting is only published when `capture-enabled` is true, documented at `sitl_ws/src/ue5/ProjectAirSim/docs/sensors/camera_capture_settings.md:86`, and that the client-side topic construction at `drone.py:104` gates on exactly that key. `streaming-enabled` is a separate real-time video feed and is not a topic, which is why Phase 5 sets it false.

The remapping is what preserves backwards compatibility for the consumers, and §3.8 explains the choice. `publish_clock_period_sec` is lowered from its default of 0.02 to 0.005 for the reasons derived in §2.4.1, and check B2a measures the resulting round trip cost so that the choice can be revisited from evidence.

The second difference is the ArduPilot parameter file. The launch file declares a new argument whose default is the copy made in §3.5.2, and appends it to the `defaults` list rather than substituting it, for the layering reason established there.

```python
    airsim2_copter_params_arg = launch.actions.DeclareLaunchArgument(
        "ardupilot-params",
        default_value="/ws/sitl_ws/config/airsim2/project-airsim-quad.parm",
        description=(
            "Absolute path to the ArduPilot parameter file appended last to "
            "the SITL defaults list. Applied on top of copter.parm, "
            "dds_udp.parm and airsim-quadX.parm, so it need only carry the "
            "parameters that differ. The default is Project AirSim's own "
            "quadrotor tuning, copied from the upstream example scripts."
        ),
    )
    ardupilot_params = launch.substitutions.LaunchConfiguration("ardupilot-params")
```

```python
            "defaults": [
                default_copter_params,
                ",",
                default_dds_udp_params,
                ",",
                default_airsim_copter_params,
                ",",
                ardupilot_params,
            ],
```

Everything else in the ArduPilot include is copied from `sitl.launch.py:109-138` unchanged, including `model` `airsim-copter`, `sim_port_in` 9003 and `sim_port_out` 9002, because §1.6 established that the wire protocol is identical and therefore that the autopilot side needs no change.

The third difference is that the `/clock` remap group disappears, because the bridge already publishes on the global topic. The `use-sim-time` argument is retained with the same default of `False` and the same `choices` list, and continues to bind ArduPilot's `use_sim_time` and the recorder's `use_sim_time`, so the semantics of the flag are unchanged from the operator's point of view. Note that `use_sim_time` is deliberately not set on the bridge node itself, and that after the Phase 7 patch it would make no difference to any sensor header if it were, because the stamp then comes from the payload rather than from the node clock.

The startup ordering changes and the change is structural rather than cosmetic. Under Cosys-AirSim the game loads its own settings at startup and the bridge merely connects. Under Project AirSim the game starts with no scene and the bridge loads one, so the bridge must reach a running simulator before it can do anything. The three second `TimerAction` inherited from `sitl.launch.py` is retained and the launch is still started three seconds after the game by `djinn`, giving six seconds in total, and `delay_after_load_sec` is raised from 2.0 to 5.0 because StonePineForest is a substantially heavier map than Blocks. If the bridge still fails to connect, the remedy is to raise the `djinn` sleep rather than the timer, and Phase 10 measures the actual load time.

`djinn` gains a `start sitl2` branch beside `start sitl`.

```bash
    elif [[ "$2" == "sitl2" ]]; then
        echo "starting Project AirSim sitl"
        start_simulation2 "nature"
        echo "Starting Ardupilot"
        spawn_container_if_needed sitl_bridge_container "shandilya1998/nrt:$VERSION"
        gnome-terminal --title "ProjectAirSim" -- bash -c "$NRT_WS/sitl_ws/scripts/run_airsim.sh airsim2;"
        sleep 10

        gnome-terminal --title "SITL Bridge" -- bash -c "$NRT_WS/ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh airsim2;"
        gnome-terminal --title "QGroundControl" -- bash -c "$NRT_WS/ext/QGroundControl.AppImage"
```

The sleep rises from three seconds to ten, because the Unreal binary must reach the point of listening on ports 8989 and 8990 before the bridge connects, and unlike the Cosys-AirSim path a premature connection is fatal rather than merely delayed, since `projectairsim_ros2_cpp_node`'s constructor throws on a failed connect at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:152-155`.

Backwards compatibility. One artefact is new, `sitl2.launch.py`, and two are extended. `run_airsim.sh` and `run_ardupilot_airsim_ros_sitl.sh` both default their new target argument to `airsim`, and both default branches reproduce their previous single line exactly, so the existing no-argument callers in the `start sitl` branch are unaffected. `sitl.launch.py` is not touched at all.

### 3.7 Phase 7, time synchronisation and the header stamping patch

This phase is the reason the migration is worth performing and it is the one place where upstream must be patched.

The defect is that `MakeHeader` at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:108-119` stamps every bridged message with `node.get_clock()->now()`, the bridge's own clock read at republish time, and never consults the `time_stamp` field that the simulator places in the payload. Under `use_sim_time` the bridge's clock is the `/clock` topic, which the bridge itself publishes, so every camera and inertial header would be quantised to the clock period, 20 ms at the bridge default and 5 ms after §2.4.1 and every message arriving between two clock ticks would carry an identical stamp. Basalt drops any sample whose stamp equals the previous one, at `ros_ws/src/slam/src/basalt/node.cpp:190-206`, with the duplicate branch at `:203-205` logging `Received duplicate IMU, dropping`, so this reproduces the precise failure recorded in [`context/sitl-time-synchronisation.md`](../context/sitl-time-synchronisation.md) that the migration exists to escape.

The payload does carry the correct value. `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/message/imu_message.cpp:39` serialises `time_stamp` as the first member of the msgpack map and `:135` exposes it as JSON, and `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/message/image_message.hpp:82` constructs image messages with a `TimeNano time_stamp_val`. The fix is therefore to read what is already there.

```cpp
// sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp

// Stamp from the simulator's own per-sample timestamp when the payload carries
// one, falling back to the node clock otherwise. The simulator emits
// time_stamp in nanoseconds (core_sim/src/message/imu_message.cpp:135).
std_msgs::msg::Header MakeHeader(rclcpp::Node& node,
                                 const std::string& frame_id,
                                 const nlohmann::json& msg) {
  std_msgs::msg::Header header;
  if (msg.contains("time_stamp") && msg["time_stamp"].is_number_integer()) {
    header.stamp = rclcpp::Time(msg["time_stamp"].get<std::int64_t>());
  } else {
    header.stamp = node.get_clock()->now();
  }
  header.frame_id = frame_id;
  return header;
}
```

The existing two-argument overload is retained so that the eleven call sites which have no payload in scope, and the occupancy grid at `:939`, continue to compile and behave identically. The call sites that do have a payload, namely the pose at `:345`, the GPS at `:385`, the inertial at `:406`, the barometer at `:420`, the lidar at `:441`, the magnetometer and the camera paths, pass it.

The patch is applied directly to the working tree of `sitl_ws/src/ue5/ProjectAirSim`. No fork of `iamaisim/ProjectAirSim` is created and no branch is pushed. Both were considered and both were rejected, because the divergence is two small hunks, because the workspace owner will carry the upstream contribution manually, and because introducing a fork now would add a remote to maintain before there is anything to maintain on it. The consequence to accept knowingly is that the submodule will report a dirty working tree until the patch is either accepted upstream or committed to a fork, and a later `git submodule update --force` would discard it.

The second local patch is the `standalone_sim` workaround for upstream issue 173, applied in the same way. The file already carries a commented-out invocation at `sitl_ws/src/ue5/ProjectAirSim/samples/CMakeLists.txt:18` immediately above the live one at `:19`, which is the maintainer's own hint, so the change is to delete or comment the live line and leave the commented one as the record.

```cmake
# sitl_ws/src/ue5/ProjectAirSim/samples/CMakeLists.txt
# add_subdirectory(standalone_sim)  # upstream issue 173, link fails under the
# UE toolchain because libonnxruntime.so pulls in libz and the sysroot
# libstdc++, neither of which reaches the link line. Restore on the upstream fix.
```

Applying both patches in the submodule tree rather than with a `sed` in a Dockerfile or a build script is deliberate, and it is the reason §3.2 keeps the image free of source. The workspace has already been bitten once by a Dockerfile that cloned upstream and therefore ignored the local tree, which is the warning recorded at the top of [`context/airsim-docker-build.md`](../context/airsim-docker-build.md). A patch in the mounted tree is what actually compiles, is visible to `git diff`, and survives an image rebuild.

An upstream issue should be opened for both, and the stamping defect in particular is a clean, small, well-evidenced report that upstream is likely to accept, which would eventually remove the divergence entirely.

The remainder of the clock architecture needs no change. ArduPilot continues to compile its `/clock` DataReader in every SITL build, gated by `AP_DDS_CLOCK_SUB_ENABLED` at `libraries/AP_DDS/AP_DDS_config.h:121-123` and armed by `--use_sim_time`, and the bridge's `rclcpp::QoS(10)` publisher is RELIABLE and therefore matches it. The quantisation of `/ap/*` stamps at the `/clock` interval remains a property of ArduPilot's `update_topic`, unchanged by this migration, but the interval improves from roughly 71 ms to the 5 ms chosen in §2.4.1, which is below the 6.17 ms period of the fastest `/ap/*` publisher and therefore eliminates the duplication rather than reducing it. Once the camera and inertial streams also carry true per-sample stamps, the `/ap/*` inertial topic is no longer needed as a visual-inertial input at all. The natural follow-up, deliberately not undertaken, is to move Basalt from `/ap/imu/experimental/data` onto the simulator's own inertial topic, which after this patch would carry per-sample simulator stamps at the sensor rate. That is recorded as a deliberate non-goal so that a later reader does not mistake it for an oversight.

Backwards compatibility. The patch adds an overload and leaves the existing one, so no call site changes behaviour unless it is deliberately updated. Nothing in `ros_ws`, `ardu_ws` or the Cosys-AirSim path is touched.

### 3.8 Phase 8, the consumers

The objective stated in the task list is that topic names should be identical between the two simulators so that consumers need no change. That is achievable and it is achieved by remapping rather than by renaming.

Renaming was considered and rejected. The bridge's `ros_topic_root` parameter can be set to `/airsim_node`, but the remainder of the path is derived from the native topic and takes the form `<scene_id>/robots/<vehicle>/<sensor>`, so the result would be `/airsim_node/StonePineForestArduCopter/robots/Copter/front_center`, which is not the Cosys-AirSim name and merely obscures the origin of the topic. A launch-level `remappings` entry, by contrast, states both names in one place, is visible to anyone reading the launch file, and leaves the bridge's own conventions intact for any future consumer that prefers them.

The consumers therefore require no edit at all. `ros_ws/src/controllers/launch/basalt_slam_test.launch.py` and `slam_controller.launch.py` both take the camera topic as a launch argument and hardcode nothing, and the `djinn start sitl basalt` and `djinn start sitl orbslam3` invocations continue to pass `/airsim_node/Copter/front_center_Scene/image`, which the remap now supplies. The encoder input in `sitl2.launch.py` is likewise unchanged from `sitl.launch.py`, and the recorder's topic list needs no edit because it records `/front_center_camera/compressed` and the `/ap/*` family, none of which changes.

The native topic name is derived rather than guessed, from the composition rule at `sitl_ws/src/ue5/ProjectAirSim/client/python/projectairsim/src/projectairsim/drone.py:61-121` quoted in §3.6, giving `/Sim/StonePineForestArduCopter/robots/Copter/sensors/front_center/scene_camera`. The bridge preserves the suffix verbatim, because the rewrite at `projectairsim_ros2_cpp_node.cpp:316-318` substitutes only the leading root, so the published ROS name is that path with `/Sim` replaced by `/ProjectAirsim`. Two suffixes are exceptions and neither affects the camera remap. The inertial topic is renamed from `imu_kinematics` to `imu` by `ReplaceSuffix` at `:379`, so a sensor with `id` `IMU1` publishes on `.../sensors/IMU1/imu`. The camera information topic is rewritten from `scene_camera_info` to `<image topic>/camera_info` by `CameraImageTopicFromInfoTopic` and `CameraInfoRosTopic` at `:490-492`.

The camera name should still be confirmed by `ros2 topic list` before the remap is trusted, which is validation check B1, since the derivation depends on the scene `id`, the actor `name` and the sensor `id` all being spelled exactly as Phase 5 writes them. Setting `publish_unmatched_as_json` true is the documented way to enumerate everything the simulator offers if an expected name does not appear.

One conversion caveat applies to any future consumer of the bridged pose or inertial topics, though not to anything changed here. The NED to ROS conversion at `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/include/projectairsim_ros2_cpp/ros2_conversion_utils.hpp:241-254` and `:265-281` negates the second and third components, which is a NED to north-west-up flip rather than a true NED to east-north-up rotation, so the published frame is not REP 103 ENU. The SLAM stack is unaffected because it takes its inertial data from ArduPilot's `/ap/imu/experimental/data`, whose `frame_id` is `base_link_ned`, and its camera data as raw pixels.

Backwards compatibility. No consumer file changes. Both `djinn start sitl basalt` and a future `djinn start sitl2 basalt` present the same topic to the same SLAM stack, which is what makes the two simulators comparable on identical inputs.

### 3.9 Phase 9, teardown

```bash
    if [[ "$2" == "sitl" ]]; then
        ...unchanged...
    elif [[ "$2" == "sitl2" ]]; then
        if [[ -n "$3" ]]; then
            if [[ "$3" == "basalt" ]]; then
                ...identical to the sitl basalt block...
            fi
        else
            echo "Killing Project AirSim SITL processes"
            stop_sitl_container
            stop_simulation2
            terminate_process "QGroundControl"
            iexec nrt_container "ps -ef | grep projectairsim_ros2_cpp | grep -v grep | awk '{print \$2}' | xargs -r kill -9"
        fi
```

The `kill airsim` branch also gains an `airsim2` case, whose process grep targets the game binary name rather than `airsim_lib`.

Backwards compatibility. New branches beside the existing ones. `djinn kill sitl` is untouched.

### 3.10 Phase 10, validation

None of this can be executed in the development container, which has no Docker daemon, so every check below is written as a precondition, an action and an observable assertion, in the form the workspace already uses in [`context/djinn-workflows.md`](../context/djinn-workflows.md).

What was actually verified during implementation is recorded in §3.13, and it is a small set, namely the four preconditions below, the parse of both configuration files, the seven-case behavioural check of the `MakeHeader` overload, and the syntax of every edited shell script and launch file. Everything in the V and B tables remains outstanding and must be run against a host with a Docker daemon and a GPU.

The blocking preconditions come first, because each can invalidate Phase 2. P1 through P4 were written against Epic's published base image and were tested against it. P5 and P6 arrive with §3.2.1 and gate the engine build that P2 through P4 are now properties of, so they are checked first in practice even though they are numbered last.

| # | Check | Assertion |
|---|---|---|
| P1 | `docker manifest inspect ghcr.io/epicgames/unreal-engine:dev-5.2` | succeeds with the workspace's existing ghcr credentials; the tag must be `dev-5.2` and not `dev-slim-5.2`, because the slim variant strips the editor. Tested Manually. The image can be pulled and is available with the tag `dev-5.2`. Superseded as a precondition by §3.2.1, since the base is now the locally built `shandilya1998/nrt:unreal` and this check no longer gates the build. Retained because it records that the published image was reachable, which is what made the 18.04 diagnosis possible |
| P2 | `ls $UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64` inside that image | lists at least one SDK directory, else `sitl_ws/src/ue5/ProjectAirSim/unreal-linux-toolchain.cmake:26-28` raises a fatal error. Tested Manually. The directory exists |
| P3 | `ls $UE_ROOT/Engine/Source/ThirdParty/Unix/LibCxx/include/c++/v1` inside that image | exists, else the libc++ injection is inert and the Cosys `<atomic>` failure returns. Tested Manually. Directory exists and is populated |
| P4 | `ls $UE_ROOT/Engine/Binaries/Linux/UnrealEditor` and `vulkaninfo --summary` inside that image | the editor binary exists and Vulkan reports a device, which together are the precondition for the manual procedures of Phase 11. If the editor is absent it must be built once with `Engine/Build/BatchFiles/Linux/Build.sh UnrealEditor Linux Development`, which is a multi-hour operation and should be discovered now rather than at the point of needing it. Tested Manually. `UnrealEditor` binaries exist, but `vulkaninfo` needs to be installed as is done in `docker/airsim/Dockerfile` already. Note that P2, P3 and P4 must be re-checked against `shandilya1998/nrt:unreal`, since they were tested against Epic's image and are properties of whatever base is actually used |
| P5 | `df -h` on the Docker daemon's storage filesystem | sufficient free space for an Installed Build with DDC, on the order of 200 GB per §3.2.1. This gates V0 and should be checked before anything else, since the workspace filesystem showed only 130 GB free and the daemon's storage may differ |
| P6 | `password.txt` holds a real token whose account is linked to Epic Games | `git ls-remote https://<token>@github.com/EpicGames/UnrealEngine.git` succeeds. The guard in `build_unreal.sh` catches the unedited placeholder, but not a token that is merely wrong or unlinked |

The build and bring-up checks follow, all outstanding, to be performed manually against a host with a Docker daemon.

| # | Action | Assertion |
|---|---|---|
| V0 | `docker/scripts/build_unreal.sh` | image `shandilya1998/nrt:unreal` exists; the build log shows the clone, `Setup.sh` and `BuildGraph` completing, and shows no `add-apt-repository` failure, which is the check that the glibc layer removal of §3.2.1 was sufficient |
| V0a | `docker run --rm shandilya1998/nrt:unreal cat /etc/os-release` | reports Ubuntu 22.04, which is the whole point of §3.2.1 |
| V0b | `docker run --rm shandilya1998/nrt:unreal ls /home/ue4/UnrealEngine/Engine/Binaries/Linux/UnrealEditor` | the editor binary exists, which is P4 re-established on the new base |
| V0c | re-run `docker/scripts/build_unreal.sh` with the image present | prints the skip message and exits without rebuilding, which is the guard that keeps `djinn init docker airsim2` cheap |
| V1 | `djinn init docker airsim2` | image `shandilya1998/nrt_airsim:0.0.2` exists; the Vulkan layer resolves `vulkan-tools`, which is the jammy name; the build log shows `simlibs_release` completing and does not show a `standalone_sim` link error, a missing-`perl` interpreter error at the `openssl-external` configure step, or a missing `libcrypto.a`/`libssl.a` link failure, which is the empirical test of the §3.2.2 fix |
| V1c | `djinn exec airsim2 "cmake --version"` | reports a 3.x release `>=3.26` and `<4`, confirming the pip-installed CMake shadows any apt one on `PATH` |
| V1a | `djinn init docker airsim2 ghcr.io/epicgames/unreal-engine:dev-5.7` | skips the engine build entirely and builds on the named base, which is the backwards-compatibility regression check for the optional fourth argument |
| V1b | `djinn exec airsim2 "vulkaninfo --summary"` | reports a device, which closes the `E: Unable to locate package vulkan-tools` failure that opened §3.2.1 |
| V2 | `djinn up airsim2` | `docker ps` lists `airsim2_container`; `/ws` inside it is the workspace root |
| V3 | `sitl_ws/scripts/build_airsim2_game.sh StonePineForest` inside that container | exits 0; the staged executable exists at the path `run_airsim.sh` uses, which confirms or corrects the inferred staging layout |
| V4 | `djinn build airsim-sitl` | `ros2 pkg prefix projectairsim_ros2_cpp` and `ros2 pkg prefix airsim_ros_pkgs` both resolve; the log mentions neither `airsimros` nor `projectairsim_ros` nor `fm_msgs` |
| V5 | read every `package.xml` under the two base paths by eye | every rosdep key is spelled correctly, per the trap in gotcha 6 of the migration context, and every resolved runtime dependency is present in the image. Partly done, since `projectairsim_ros2_cpp` adds only `nav_msgs`, `rclcpp_action` and `rosgraph_msgs` over `airsim_ros_pkgs`, and `docker/ros/Dockerfile:15-16` installs `ros-humble-desktop` and `ros-humble-desktop-full`, which carry all three. No image change was needed |
| V6 | `djinn start sitl2` | the game listens on 8989 and 8990, checked with `lsof -i :8989 -i :8990`; the bridge logs `Connected to Project AirSim` and `Loaded Project AirSim scene` |

The behavioural checks are what decide whether the migration succeeded.

| # | Action | Assertion |
|---|---|---|
| B1 | `ros2 topic list` | the camera topic appears under the remapped name `/airsim_node/Copter/front_center_Scene/image`; record the true native name for the context files |
| B2 | `ros2 topic hz /clock` | one publisher, `projectairsim_ros2_cpp_node`, at approximately 200 Hz, against the 14.05 Hz measured for Cosys-AirSim on 2026-07-28. A rate materially below 200 Hz means the timer is being starved and B2a explains why |
| B2a | `ros2 topic delay /clock`, and separately time one thousand `GetSimTime` requests from a standalone client with the bridge stopped | measures the `RequestSimTime` round trip against the one hundred to three hundred microsecond estimate of §2.4.1. If it exceeds one millisecond the 200 Hz period is unsustainable and the period should be raised to 0.006, which is still below the 6.17 ms inertial period |
| B2b | `ros2 topic echo /clock` for ten seconds and count distinct values | the count equals the message count, which confirms that 5 ms of wall time reliably crosses at least one 3 ms simulation step and that the period is not below the simulator's own resolution |
| B3 | `ros2 topic hz` on the camera topic | record the achieved rate and correct `Camera.fps` in `sitl.yaml` from it rather than from the nominal 20 Hz |
| B4 | count messages against unique stamps on the camera and inertial topics, using the two `ros2 topic echo` pipelines already recorded in [`context/sitl-time-synchronisation.md`](../context/sitl-time-synchronisation.md) | after the Phase 7 patch the ratio is one, which is the direct proof that per-sample stamps survive the bridge |
| B5 | ArduPilot console | prints `Using \clock topic for DDS timing: enabled`, proving the DataReader was created and that the bridge's RELIABLE publisher matched it |
| B6a | the simulator viewport or `ros2 topic echo` on the pose topic | the copter spawns on the StonePineForest terrain and holds a stable altitude, which confirms the spawn origin and `start-landed` of §3.5; a copter falling or buried is a spawn-origin error and not an ArduPilot fault |
| B6 | ArduPilot GCS | the copter reports a healthy GPS and arms, which is the end-to-end proof that the ArduPilot JSON contract is satisfied, and the first real test of the concern raised in §1.5 |
| B7 | `djinn start sitl2 basalt` after B6 | VISLAM initialises and tracks; exactly one `managed_logger_node`, one bridge and one encoder exist across both invocations |
| B8 | in the ArduPilot console, `param show ATC_RAT_RLL_P`, `param show SCHED_LOOP_RATE`, `param show FRAME_TYPE` and `param show MOT_THST_HOVER` after boot | 0.733, 185, 1 and 0.461 respectively, which proves that the four-file `defaults` list of §3.6 layered in the intended order and that appending the Project AirSim tuning did not displace the workspace's own parameters |
| B8a | `ros2 topic echo /ap/navsat` while stationary | the reported latitude and longitude quantise in steps of about 1.9e-06 and 7.6e-06 degrees respectively, which confirms the single-precision analysis of §3.5.1 and establishes the position noise floor for later comparison against Cosys-AirSim |
| B9 | `djinn kill sitl2`, then `djinn start sitl` | the Cosys-AirSim path still works unchanged, which is the regression test for the whole migration |

B6 is the gate. If ArduPilot does not arm against Project AirSim, the fault is in the ArduPilot controller rather than anywhere in this change, and the diagnostic order is to confirm the JSON on the wire with `tcpdump -i lo -A udp port 9003`, to compare it field by field against the thirteen-entry parse table at `SIM_AirSim.h:139-153`, and to report the result upstream on issue 21, which is still open and whose maintainer has asked for exactly this evidence.

### 3.11 Phase 11, the manual procedures

Three things this change needs cannot be produced by any script, because they live inside binary Unreal assets rather than in text, and they are gathered here so that they are performed deliberately after the build and bring-up checks rather than improvised when something fails to spawn. All three are performed inside `airsim2_container`, which is why §3.2 gives the image the editor's desktop libraries and why precondition P4 checks that the editor binary exists.

#### 3.11.1 Opening the editor inside the container

`sitl_ws/scripts/start.sh` already forwards X11 to the container, since it passes `DISPLAY`, mounts `/tmp/.X11-unix` and binds the host `.Xauthority` onto `/home/ue4/.Xauthority`, so nothing new is needed for the display. The host must permit the connection, which `start_simulation2` does with `xhost +local:docker`.

```bash
djinn up airsim2
docker exec -it -u ue4 airsim2_container bash

# Confirm the display before blaming the editor. xdpyinfo comes from x11-apps.
xdpyinfo | head -3

# Confirm Vulkan, since the editor will start and then fail to render without it.
vulkaninfo --summary | head -20

$UE_ROOT/Engine/Binaries/Linux/UnrealEditor \
  /ws/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/StonePineForest.uproject
```

The first open of a project with a C++ module offers to rebuild that module, which must be accepted, and which is the same compilation `build_airsim2_game.sh` performs non-interactively. The map to open is the one named by `EditorStartupMap` in §3.4.1.

#### 3.11.2 Reading the spawn origin from the map

This is the procedure that produces the `origin.xyz` value left as a placeholder in §3.5. The conversion it depends on is exact and was read from the plugin rather than assumed. Unreal world coordinates are centimetres in a north, east, up frame, and `UnrealTransform::UnrealToNedLinear` at `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/UnrealTransforms.h:16-23` converts by `ToMeters`, a multiplication by 0.01 at `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/transforms/transform_utils.hpp:48-51`, followed by `NeuToNedLinear`, which negates only the third component at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/transforms/transform_utils.cpp:91-93`. The mapping is therefore

```
north =  UnrealX / 100
east  =  UnrealY / 100
down  = -UnrealZ / 100
```

and the same three numbers, in that order, are what the `"xyz"` string carries.

The interactive procedure, which is the one to use when the terrain must be seen rather than merely located, is as follows.

1. Open the map as in §3.11.1.
2. In the World Outliner, type `PlayerStart` in the search box and select the actor. StonePineForest has one, because Cosys-AirSim spawned its vehicle there, so this reproduces the current spawn point exactly rather than choosing a new one.
3. Read Transform, Location in the Details panel. The three values are X, Y and Z in centimetres.
4. Apply the mapping above. As a worked example, a `PlayerStart` at X 12500, Y −3400, Z 8200 gives north 125.0, east −34.0 and down −82.0, so the string is `"125.0 -34.0 -82.0"`.
5. Subtract a further one to two metres from the down component, making it more negative, so that the copter starts just above the surface rather than intersecting it, and set `"start-landed": true` so that it holds that position until thrust exceeds weight.

The non-interactive procedure, which is the one to prefer when the value is simply needed and the terrain is not in question, uses the editor's Python plugin and prints the converted numbers directly. It is reproducible, it can be rerun after any map change, and it does not depend on reading a panel correctly.

```python
# /ws/sitl_ws/scripts/print_spawn_origin.py
import unreal

subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for actor in subsystem.get_all_level_actors():
    if isinstance(actor, unreal.PlayerStart):
        location = actor.get_actor_location()
        print(
            "origin xyz (NED metres): %.3f %.3f %.3f"
            % (location.x / 100.0, location.y / 100.0, -location.z / 100.0)
        )
```

```bash
$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd \
  /ws/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/StonePineForest.uproject \
  -run=pythonscript -script="/ws/sitl_ws/scripts/print_spawn_origin.py" -unattended -nullrhi
```

#### 3.11.3 The same procedure for a terrain that has no `PlayerStart`

A future environment may have no `PlayerStart`, or the wanted spawn point may not be where one sits, and the procedure generalises without changing the arithmetic.

If the map has no `PlayerStart`, place one from the Place Actors panel by dragging it onto the terrain at the wanted point, at which point Unreal snaps it to the surface, and then read its Location exactly as above. The actor need not be saved into the map, since only its transform is wanted, though saving it makes the choice reproducible and is preferable.

If the wanted point is somewhere else on the terrain, the same drag-and-read works with any actor, and an empty Actor is the lightest choice. Where a numeric surface height is wanted rather than a snapped one, select the Landscape and read the Z of the terrain under the cursor from the viewport's coordinate readout.

Two cross-checks apply to whatever value results, and both are cheap. The `down` component must be negative for any point above the Unreal world origin, so a positive `down` on a mountainous map is almost always a forgotten sign. And the magnitude of the north and east components is the horizontal distance in metres from the world origin, which is the offset from `home-geo-point`, because `JsonUtils::GetTransform` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/json_utils.cpp:100-129` maps NED zero onto that geopoint and `EarthUtils::NedToGeodetic` at `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/earth_utils.hpp:100-125` converts from it. A value of several kilometres therefore means the copter reports a GPS position several kilometres from the declared home, which is harmless because ArduPilot takes its home from the first fix, but which is worth recognising rather than debugging.

A third route exists and is worth knowing, because it removes the conversion entirely. `GetTransform` accepts `"geo-point": "lat lon alt"` in place of `"xyz"` at `json_utils.cpp:100-115` and performs the geodetic to NED conversion itself, so a spawn point known in latitude and longitude can be written directly. It is the better form for a georeferenced terrain and the worse form for a map like StonePineForest whose relationship to the Earth is arbitrary.

#### 3.11.4 The map-level game mode override

Step 2B of `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md` sets the game mode override in the World Settings of the map itself, which cannot be done from a text editor. §3.4.1 sets `GlobalDefaultGameMode` in `DefaultEngine.ini`, which is sufficient for a packaged headless run, so this step is conditional rather than mandatory. Perform it only if check B6a shows the copter failing to spawn at all, in which case open the map, use Window then World Settings, and set GameMode Override to `ProjectAirSimGameMode`. Save the map afterwards and repackage, since a map change is a cook input.

### 3.12 Phase 12, documentation

Two of these were written during the investigation rather than deferred, because they record findings about the upstream tree that do not depend on the implementation and would have been lost to a later session otherwise.

`context/project-airsim-architecture.md` carries the full architecture reference, and its row is in `context/README.md`. It is the authority for everything in §2.

`context/simulation-engine-survey.md` §5.1.3 is corrected in place, stating the correct reading directly and recording alongside it what the section previously claimed and why that was wrong, per the correction rule in `CLAUDE.md` §1, since artefacts built from the old reading exist in this document's own §1.4 and in the scoring matrix of that survey's section 7. A second, narrower refinement to the same section records that the host-driven clock description applies to two of the four clock types rather than to the default.

The remainder were written on completion, per `CLAUDE.md` §1 and §3.

`context/project-airsim-docker-build.md` is new, carrying the build chain and every make target, the third-party dependency inventory with a reason per package, the toolchain analysis with the libc++ hazard verdict, the `standalone_sim` workaround, the four preconditions and their results, the `ue4` user and engine-version constraints of §3.2, the full procedure for porting an Unreal environment onto the plugin, the editor procedures and spawn-origin conversion of §3.11, and the `.jsonc` comment-stripping loader. Its row is in `context/README.md`.

`context/sitl-time-synchronisation.md` is extended with a Project AirSim section carrying the clock model, the global `/clock` difference, the `RequestSimTime` cost model and clock-period derivation of §2.4.1, defect G15, the stamping defect with the patch as written, the deliberate non-goal, and the outstanding measurements B2 through B5. The existing Cosys-AirSim material is retained in full and its header now states that an unqualified reference to AirSim means Cosys-AirSim, since the two simulators coexist.

`context/djinn-workflows.md` is extended with `djinn init docker airsim2`, `djinn up airsim2`, `build_airsim2_game.sh`, `djinn start sitl2`, `djinn kill sitl2` and `djinn down airsim2`, each with the call chain, side effects, expected outcome and test strategy that §3.10 establishes. The existing `djinn build airsim-sitl` and `djinn up airsim` entries are corrected, the first for the second colcon base path and the second for the changed `start.sh` calling convention. This is mandatory rather than optional, per `CLAUDE.md` §3.

`ARCHITECTURE.md` is updated in §2, §3.3 and §4 to record the second simulator image and its separate lineage, the two workspaces' coexistence and the differing engine pins, and the new `djinn` subjects.

`context/project-airsim-architecture.md` §G is extended with G14, the `time_utc_milli` against `time_utc_millis` key mismatch between `json_utils.hpp:217` and `gps_message.cpp:109`, and G15, the five minute service response timeout with retry disabled at `client/cpp/ProjectAirsimClientLib/src/Client.cpp:275-279` and `:462-467`. G3 and G12 are annotated in place, G3 with the refined magnitudes and G12 with the fact that it is now patched locally. §A gains A.14, the enumerated `GpsMessage` consumer table with the cause and magnitude analysis, and A.15, the parameter-file layering.

### 3.13 What implementation found that the plan did not

Eight things differed between the tree as the plan described it and the tree as it was. All were resolved in the direction the plan's own reasoning pointed, and they are recorded because each is a trap that would otherwise be rediscovered.

`sitl_ws/scripts/start.sh` did not bind the settings file the plan assumed. It binds `$(pwd)/settings.json`, and because `djinn` cds to `$NRT_WS` before sourcing it, that resolves to `$NRT_WS/settings.json`, which is an empty directory rather than a file, almost certainly created by Docker when the source path did not exist. The mount is inert, because `run_airsim.sh` always passes `-settings=/ws/settings.json` which resolves inside the `Environments` mount. The rewrite preserves the line verbatim rather than pointing it at the real file, because substituting a populated settings file for an empty directory at the path Cosys-AirSim reads by default is a behaviour change to a path that did not ask for one.

`StonePineForest.uproject` declared `ModelingToolsEditorMode` and `ChaosVehiclesPlugin`, not the `SunPosition` the plan's snippet carried, which came from Blocks. The project's own two are retained and only `AirSim` is swapped for `ProjectAirSim`.

`Config/DefaultGame.ini` carried nine `+MapsToCook` and `+DirectoriesToAlwaysCook` entries under `/AirSim/*`. These are removed rather than merely supplemented, because the `/AirSim` mount point disappears with the plugin and cooking a path that no longer exists is an error rather than a warning.

The `Source/*.Target.cs` change is load bearing rather than cosmetic. Both files carried `BuildSettingsVersion.V5` and `EngineIncludeOrderVersion.Unreal5_5`, and neither enumerator exists in Unreal 5.2, so aligning them with the Blocks targets is required for the project to compile at all.

The project copy carried a 2.5 GB `Linux/` directory, the packaged Cosys-AirSim game that `run_airsim.sh` runs for the old simulator. It is not one of Unreal's standard in-project build directories, so it survived the plan's exclude list, and it is useless against the new plugin. It is deleted from the copy and left untouched in the original. The port is 4.1 GB after removal.

`rsync` is absent from the development container, so the copy was performed with `tar -cf - --exclude … | tar -xf -`, which has the same exclude-copy semantics.

The `MakeHeader` patch reuses `JsonToInt64` from `ros2_conversion_utils.hpp:179` rather than calling `get<std::int64_t>()` directly, because msgpack delivers a positive `TimeNano` as an unsigned JSON number and that existing helper already handles both signednesses with an overflow guard. A `time_stamp > 0` test was added beyond what the plan specified, so that a zero stamp falls back to the node clock rather than publishing an epoch stamp, which a sim-time consumer would read as "no clock yet".

Comments are safe in the workspace `.jsonc` configuration files, which is not obvious from the extension alone and was verified rather than assumed. `LoadJSONCFromFile` at `client/cpp/ProjectAirSimMessageLib/src/jsonc.cpp:168` wraps the input stream in a `jsoncbuf` filter that strips comments before nlohmann parses it.

---

## 4. Conclusion

The migration replaces a simulator whose defects are architectural with one whose defects are local. Cosys-AirSim polls its own simulator over a remote procedure call and cannot exceed a measured 14 Hz, publishes its clock where no consumer can see it, and offers no negotiated coupling to the flight controller. Project AirSim pushes over a publish and subscribe transport, publishes `rosgraph_msgs/msg/Clock` on the global `/clock` from a dedicated timer at a period set here to 5 ms, and exposes a configurable fixed-step clock with genuine pause and step control.

The migration is affordable because the interface that would have been most expensive to change does not change. Project AirSim's ArduPilot controller emits the same JSON document, on the same ports, with the same blocking handshake, that ArduPilot's `SITL::AirSim` backend already consumes. The entire autopilot side of the stack, and every `/ap/*` topic that the SLAM and recording stack depends on, continues to work untouched.

Three risks are carried into implementation rather than resolved by it, and all three are stated rather than smoothed over. The ArduPilot path is unproven on the current tree, and the maintainer's own words in issue 21 are that he is unsure whether it still works, so validation check B6 is a gate rather than a formality. The ROS 2 bridge discards the simulator's per-sample timestamps, which would reintroduce the exact quantisation defect that motivated the migration, so the Phase 7 patch is not optional. The source build has an open upstream blocker in `standalone_sim`, for which the maintainer's own workaround is applied.

Every change is additive. A new submodule beside the existing one, a new image tag beside the existing one, new `djinn` branches beside the existing ones, a new launch file beside the existing one, two existing scripts that gain a defaulted target argument reproducing their previous behaviour, and a launch-level remapping that presents the new simulator's camera under the old simulator's topic name. `djinn start sitl` continues to run Cosys-AirSim exactly as it does today, which is what makes validation check B9 meaningful and what allows the two simulators to be compared on identical inputs before the old one is retired.

---

## 5. References

### Workspace context

- [`context/README.md`](../context/README.md), the context index.
- [`context/project-airsim-architecture.md`](../context/project-airsim-architecture.md), the full Project AirSim architecture reference produced by this investigation, and the authority for every Project AirSim claim in §2.
- [`context/airsim.md`](../context/airsim.md), Cosys-AirSim architecture, the ArduCopter UDP data path, port semantics, `settings.json`, and the `SteppableClock`.
- [`context/airsim-docker-build.md`](../context/airsim-docker-build.md), the Cosys-AirSim image build and the `<atomic>` libc++ failure whose recurrence §3.2 rules out.
- [`context/sitl-time-synchronisation.md`](../context/sitl-time-synchronisation.md), every clock in the stack, the `/clock` DataReader, the stamp quantisation measurements of 2026-07-28 and 2026-07-31.
- [`context/sitl-workspace-migration.md`](../context/sitl-workspace-migration.md), the mount model, the colcon discovery scoping, and the rule that runtime dependencies must be baked into the image.
- [`context/djinn-workflows.md`](../context/djinn-workflows.md), the per-workflow catalogue that §3.12 extends.
- [`context/simulation-engine-survey.md`](../context/simulation-engine-survey.md), the survey that selected Project AirSim, whose §5.1.3 is corrected by §1.4 above.
- [`context/ardupilot-dds-qos.md`](../context/ardupilot-dds-qos.md), per-topic `/ap/*` publisher QoS.
- [`plans/sitl-clock-synchronisation.md`](sitl-clock-synchronisation.md), the change record for the current `use-sim-time` wiring.

### Project AirSim source, at commit `7fb9c566`

- `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/include/arducopter_api.hpp`, `sitl_ws/src/ue5/ProjectAirSim/vehicle_apis/multirotor_api/src/arducopter_api.cpp`, the ArduPilot controller.
- `sitl_ws/src/ue5/ProjectAirSim/client/python/projectairsim/src/projectairsim/schema/robot_config_schema.jsonc`, the robot configuration schema.
- `sitl_ws/src/ue5/ProjectAirSim/client/python/example_user_scripts/ardupilot/`, the worked ArduPilot examples and parameter files.
- `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/sensors/imu.hpp`, `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/message/imu_message.cpp`, the inertial model and its serialisation.
- `sitl_ws/src/ue5/ProjectAirSim/ros/projectairsim_ros2_cpp/`, the ROS 2 Humble bridge.
- `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/`, the reference Unreal project.
- `sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt`, `sitl_ws/src/ue5/ProjectAirSim/build.sh`, `sitl_ws/src/ue5/ProjectAirSim/build_linux.mk`, `sitl_ws/src/ue5/ProjectAirSim/unreal-linux-toolchain.cmake`, the build system.
- `sitl_ws/src/ue5/ProjectAirSim/client/cpp/ProjectAirsimClientLib/src/Client.cpp`, `sitl_ws/src/ue5/ProjectAirSim/client/cpp/ProjectAirsimClientLib/src/Topics.cpp`, the NNG client, its socket types, its threading and its timeouts, which §2.4.1 depends on.
- `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/service_manager.cpp`, `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/scene.cpp`, the service dispatch and the `GetSimTime` handler.
- `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/message/gps_message.cpp`, `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/sensors/gps.cpp`, `sitl_ws/src/ue5/ProjectAirSim/core_sim/include/core_sim/earth_utils.hpp`, the geodetic path of §3.5.1.
- `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/json_utils.cpp`, `sitl_ws/src/ue5/ProjectAirSim/core_sim/src/transforms/transform_utils.cpp`, `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/UnrealTransforms.h`, the Unreal to NED conversion that Phase 11 inverts by hand.

### Container images

- `sitl_ws/src/ue5/AirSim/docker/Dockerfile_source`, the Cosys-AirSim image, which is this workspace's own precedent for the `USER root` then `USER ue4` pattern at `:4`, `:20`, `:75` and `:76`, and whose `clang`, `lld`, `llvm-dev`, `libc++-dev` and `libc++abi-dev` installs §3.2 deliberately omits because Project AirSim builds with the engine toolchain rather than the system one.
- https://github.com/adamrehn/ue4-docker, `src/ue4docker/dockerfiles/ue4-build-prerequisites/linux/Dockerfile`, the public ancestor of Epic's official development images, and the source of the `useradd --create-home --home /home/ue4 --shell /bin/bash --uid 1000 ue4` account definition, the passwordless `sudo` membership and the desktop library inventory that §3.2 extends.
- https://github.com/EpicGames/UnrealEngine, `Engine/Extras/Containers/Dockerfiles/linux/dev/Dockerfile` on branch 5.2 at commit `02dc8dbdd89f749cd5500376e9bb87271bf64848`, the Dockerfile of `ghcr.io/epicgames/unreal-engine:dev-5.2`. It is behind the Epic licence gate, and anonymous HTTP access returns 404, but it is readable over SSH with a GitHub account linked to Epic, which is how §3.2.1 obtained it. It is now vendored at `docker/unreal/Dockerfile`. The two references above were originally written as stand-ins for it and are retained because the `ue4-docker` lineage they document is what explains the file's structure.
- https://github.com/EpicGames/UnrealEngine, `Engine/Extras/Containers/Dockerfiles/linux/build.sh:54` on the same commit, which hard-codes `BASEIMAGE=nvidia/opengl:1.0-glvnd-devel-ubuntu18.04` and is the direct evidence that Epic's published development images are Ubuntu 18.04. Ported to `docker/scripts/build_unreal.sh` per §3.2.1.
- https://hub.docker.com/r/nvidia/opengl, the base image family. The `1.0-glvnd-devel-ubuntu22.04` tag exists and `1.0-glvnd-devel-ubuntu24.04` does not, which fixes 22.04 as both the target and the ceiling.
- https://launchpad.net/~slonopotamus/+archive/ubuntu/glibc-dso, the glibc DSO patch PPA that upstream's Dockerfile installs. It publishes bionic, focal, hirsute, impish and devel, and no jammy, which is why §3.2.1 removes that layer.
- https://sourceware.org/glibc/wiki/Release/2.35, the glibc 2.35 release notes, which introduce the depth-first DSO sorting algorithm and the `glibc.rtld.dynamic_sort` tunable with a default of 2. This is why removing the PPA layer on a 22.04 base loses nothing.

### Project AirSim documentation

- `sitl_ws/src/ue5/ProjectAirSim/docs/config_scene.md`, `sitl_ws/src/ue5/ProjectAirSim/docs/scene/sim_clock.md`, scene and clock configuration.
- `sitl_ws/src/ue5/ProjectAirSim/docs/config_robot.md`, robot, sensor and controller configuration.
- `sitl_ws/src/ue5/ProjectAirSim/docs/ros/ros2.md`, the ROS 2 bridge parameters, topics, services and actions.
- `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md`, adding the plugin to a custom Unreal environment.
- `sitl_ws/src/ue5/ProjectAirSim/docs/command_line_switches.md`, runtime switches and ports.
- `sitl_ws/src/ue5/ProjectAirSim/docs/controllers/controllers.md`, which omits ArduPilot and is contradicted by the source.
- `sitl_ws/src/ue5/ProjectAirSim/docs/system_specs.md`, Vulkan and driver requirements.

### Upstream issues consulted

- https://github.com/iamaisim/ProjectAirSim/issues/21, ArduPilot SITL, open, the maintainer's configuration documentation and his uncertainty about current status.
- https://github.com/iamaisim/ProjectAirSim/issues/42, clock synchronisation between the simulator and Unreal, open.
- https://github.com/iamaisim/ProjectAirSim/issues/41, unstable timestamp synchronisation between stereo cameras in ROS, open.
- https://github.com/iamaisim/ProjectAirSim/issues/75, headless mode on Ubuntu server, closed, opened 2025-10-04 by `earlzero` against v0.1.1 on Ubuntu 24.04 Server. Three things are taken from it. The first is the single unreproduced report that the staged `.sh` wrapper did not forward its arguments, which §3.6.1 weighs. The second is the diagnosis that `-RenderOffScreen` still requires a Vulkan loader and driver, which §3.2 acts on. The third is the engine banner `5.2.1-0+UE5` in the reporter's output, which is the evidence that Project AirSim's release binaries are built against Unreal 5.2.
- https://github.com/iamaisim/ProjectAirSim/issues/83 and 129, adding the plugin to a custom project, both open, the build-simlibs-first requirement.
- https://github.com/iamaisim/ProjectAirSim/issues/120 and 173, Ubuntu 24.04 LLVM repository and the `standalone_sim` link failure, both open.
- https://github.com/iamaisim/ProjectAirSim/issues/11 and 62, Unreal Engine 5.5 and 5.4 support, both open.

### ArduPilot source, at submodule `e257f85b`

- `libraries/SITL/SIM_AirSim.h`, `SIM_AirSim.cpp`, the flight dynamics backend, its ports and its thirteen-entry JSON parse table.
- `Tools/autotest/pysim/vehicleinfo.json:199-205`, the definition of the `airsim-copter` frame as `copter.parm` followed by `airsim-quadX.parm`, which is what makes the parameter layering of §3.5.2 correct.
- `libraries/AP_DDS/AP_DDS_Client.cpp`, `AP_DDS_config.h`, the stamp precedence and the `/clock` DataReader.
- `Tools/autotest/default_params/airsim-quadX.parm`, the current airframe parameters.
