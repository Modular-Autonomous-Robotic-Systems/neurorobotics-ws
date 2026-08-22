# Simulation engine survey for the neurorobotics toolkit

Compiled 2026-08-01. This document surveys the robotics simulation landscape, evaluates every serious candidate against the requirements of the neurorobotics toolkit, and ranks them. It is a research and planning artefact, not a change record. No code is proposed here, and any migration that follows from it will be planned separately in `plans/`.

The scope is deliberately broad. The toolkit is intended to serve testing, reinforcement learning, model benchmarking, multi-agent training, visual and visual-inertial SLAM, lidar SLAM, planning, deep learning data collection and the development of novel analytical and learned algorithms, all from one simulation substrate where that is possible. A survey narrower than that scope would prejudge the answer.

Related workspace context, [`airsim.md`](airsim.md) for the current Cosys-AirSim data path, [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md) for the measured clock behaviour of the present stack, and [`airsim-sitl-gps-issue.md`](airsim-sitl-gps-issue.md) for the GPS and lockstep investigation that motivated much of this work.

---

## 1. What the current stack has already proved

The most valuable input to this survey is not a feature list from a vendor. It is the set of defects already measured inside `NRT_WS`, because each one identifies an architectural property that any replacement must possess. Three lessons follow from the existing Cosys-AirSim, ArduPilot SITL and ROS 2 stack, and they are the reason the criteria in section 3 are weighted as they are.

The first lesson concerns transport. The Cosys-AirSim ROS 2 bridge obtains vehicle state by polling the simulator over a msgpack remote procedure call on port 41451, one blocking round trip per sensor per iteration of `publish_vehicle_state()` at `airsim_ros_wrapper.cpp:1459-1500`. A timer nominally at 100 Hz achieved 14.05 Hz, and the image timer nominally at 20 Hz achieved 15.7 Hz, both measured on 2026-07-28 and recorded in [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md). The defect is not tuning, it is topology. A request-response client that must ask for every sample cannot outperform a publisher that pushes samples as they are produced, and it degrades further as the sensor count grows. Any candidate simulator must therefore be judged on whether its data path to ROS 2 is a push topology, ideally one that runs inside the simulator process rather than across a socket to a translating node.

The second lesson concerns time. AirSim stamps every sensor sample from a `SteppableClock` anchored to wall time once at construction, ArduPilot stamps every DDS message from a clock started at zero and advanced by AirSim timestamp deltas, and the two are consequently rate-locked and origin-independent. Connecting AirSim's clock to ArduPilot's `/clock` DataReader collapsed the constant offset, but replaced it with a quantisation, because `AP_DDS_Client::update_topic` copies the last received clock value verbatim and a 162 Hz inertial publisher against a 14 Hz clock produced runs of up to twenty-four identical stamps. Basalt discards every duplicate, so three quarters of the inertial data was lost. The lesson is that a simulator must own an authoritative, high-rate, monotonically stepped clock that every consumer can read, and that a stamp applied at serialisation time is not a substitute for a stamp applied at sample time.

The third lesson concerns the coupling between physics and the flight controller. In the ArduCopter path the `LockStep` settings key is inert, confirmed by the absence of any `lock_step` reference under `firmwares/arducopter/`, and the only coupling is that `recvRotorControl()` blocks until motor commands arrive. That is a handshake by accident rather than a negotiated lockstep, and it provides no way to pause, step or run faster than real time deterministically. A simulator intended for regression testing and for reinforcement learning must offer explicit stepping, because determinism is the precondition for reproducible experiments and for training throughput above real time.

These three lessons generalise beyond ArduPilot and beyond aerial vehicles, and they discriminate between candidates far more sharply than rendering quality does.

---

## 2. Method

Candidates were gathered from the curated list at `knmcguire/best-of-robot-simulators`, which enumerates 114 projects across simulators, game engines, physics engines and renderers, then extended with projects that list omits or classifies loosely, including Project AirSim, Unreal Robotics Lab, mjlab, Newton, Genesis World, UNav-Sim, OceanSim and the closed commercial platforms. Each candidate was assessed from primary sources where possible, meaning the source tree, the official documentation and the release notes, and from secondary sources only for context. Repository health was measured directly on 2026-08-01 through the GitHub API and through shields.io endpoints, so the activity figures in section 7.8 are observations rather than impressions.

Two findings required correcting claims made by the projects themselves, and both are recorded in place rather than silently resolved. They appear in sections 5.1.3 and 5.1.4.

---

## 3. Evaluation criteria and weights

Fourteen criteria were derived from the stated requirements. Weights sum to one hundred and reflect the toolkit's actual usage profile, in which perception, autopilot integration, transport and learning throughput carry the most consequence. The weights are stated explicitly so that a different judgement about priorities can be applied to the same scores without redoing the research.

| Criterion | Weight | What a score of five means |
|---|---|---|
| Photorealism | 10 | Path-traced or comparably physically based rendering suitable for closing the perception sim-to-real gap for VSLAM and VISLAM |
| Parallel RL throughput | 10 | Thousands of environments stepped on GPU with published throughput above 100k environment steps per second |
| Autopilot integration | 10 | First-party ArduPilot and PX4 support covering software in the loop and hardware in the loop, with genuine lockstep |
| ROS 2 transport | 10 | Push topology, ideally in-process, with no polling bridge and no serialisation round trip per sample |
| Time synchronisation | 8 | Authoritative simulator clock, explicit stepping, pause and step, deterministic replay |
| Swappable physics | 6 | Multiple solvers selectable at runtime behind one interface |
| Sensor realism | 8 | Physically grounded camera, lidar, radar, inertial and acoustic models with GPU acceleration |
| Description ingest | 6 | Native import of URDF, MJCF, SDF or USD without hand translation |
| Embodiment breadth | 6 | Aerial, legged, wheeled and marine platforms all first class |
| Multi-agent scale | 5 | Many interacting robots in one world, or distributed across hosts |
| Procedural generation | 6 | Programmatic environment synthesis with domain randomisation |
| Modularity | 5 | Clean extension points, standard interfaces, replaceable subsystems |
| Controller and dynamics integration | 5 | Actuator models, control interfaces and user-supplied dynamics accepted without forking the simulator |
| Ecosystem health | 5 | Permissive licence, active maintenance, broad community, credible institutional backing |

---

## 4. The candidate landscape

The field divides into five families that answer different questions. Confusing them is the most common source of poor simulator choices, because a platform optimised for one family is structurally weak in another.

### 4.1 Photorealistic game-engine platforms

These prioritise rendering and scene authoring, and inherit the tooling of a commercial or open game engine.

| Project | Engine | Licence | Status 2026-08-01 |
|---|---|---|---|
| Cosys-AirSim | Unreal Engine 5.8, LTS on 5.2.1 | MIT | Releases to v3.4.1, disclaimer of no active support |
| Project AirSim | Unreal Engine 5.2 and 5.7 | MIT | Active, IAMAI Simulations |
| Colosseum | Unreal Engine 5 | MIT | Archived 2026-07-11 |
| microsoft/AirSim | Unreal Engine 4 | MIT | Dormant since July 2022 |
| Unreal Robotics Lab | Unreal Engine 5.7 | Apache 2.0 | Active, ICRA 2026 |
| rclUE and RapyutaSimulationPlugins | Unreal Engine | Apache 2.0 | Slow but alive |
| CARLA | Unreal Engine 5.5 from 0.10 | MIT | Active |
| HoloOcean | Unreal Engine 5.3 | MIT with Unreal EULA | Active |
| UNav-Sim | Unreal Engine 5 over AirSim | Open source | Research artefact |
| UnrealZoo | Unreal Engine | Open source | Active |
| O3DE with ROS 2 Gem | Open 3D Engine, Atom renderer | Apache 2.0 and MIT | Active, Linux Foundation |
| Unity with ROS 2 For Unity, AWSIM | Unity | Unity terms, Apache 2.0 plugin | Plugin churn, AWSIM active |
| Godot with Jolt | Godot 4.6 | MIT | Emerging, no robotics standard |
| Duality Falcon | Unreal Engine | Commercial | Active, closed |
| AirGen and GRID | Unreal Engine over AirSim | Commercial cloud | Active, closed |

### 4.2 GPU-parallel learning simulators

These prioritise throughput for reinforcement learning and treat rendering as an optional consumer of the same state.

| Project | Physics | Licence | Note |
|---|---|---|---|
| Isaac Sim with Isaac Lab | PhysX 5 and Newton | Apache 2.0 core, BSD-3 Isaac Lab, closed Kit SDK | 150k environment steps per second reported |
| Newton | MuJoCo Warp, Kamino, VBD | Apache 2.0 | Version 1.0 on 2026-03-17, Linux Foundation |
| mjlab | MuJoCo Warp | Apache 2.0 | Isaac Lab API without Isaac Sim |
| MuJoCo Playground | MJX and MuJoCo Warp | Apache 2.0 | Madrona batch renderer for vision |
| Genesis World 1.0 | Unified multi-solver | Apache 2.0 | Nyx path tracer, Quadrants compiler |
| ManiSkill3 with SAPIEN | PhysX 5 | Apache 2.0 | 30k frames per second, rasterised |
| Aerial Gym Simulator | Isaac Gym | BSD-3 | Thousands of multirotors, ray-cast lidar |
| Habitat-Sim, iGibson, AI2-THOR | Bullet and custom | MIT and similar | Indoor embodied AI, not robot-stack oriented |

### 4.3 Classical robotics simulators

These prioritise correctness of the robot software interface and breadth of platform support.

| Project | Physics | Licence | Note |
|---|---|---|---|
| Gazebo Jetty | DART, Bullet, Bullet-Featherstone, TPE | Apache 2.0 | Long term support to September 2030 |
| Webots R2025a | ODE | Apache 2.0 | ArduPilot supported, annual cadence |
| CoppeliaSim | MuJoCo, Bullet, ODE, Vortex, Newton | Proprietary with free education tier | Five engines, Drake in preparation |
| Drake | Custom multibody | BSD-3 | Control and analysis, not perception |
| Project Chrono | Custom multibody | BSD-3 | Terramechanics, OptiX ray-traced sensors |

### 4.4 Domain simulators

| Domain | Projects |
|---|---|
| Marine | HoloOcean, Stonefish, DAVE, UUV Simulator, UWSim, OceanSim, UNav-Sim, MARUS |
| Driving | CARLA, AWSIM, MetaDrive, AutoDRIVE, BeamNG.tech, rFpro |
| Space | OmniLRS, Space Robotics Bench, BSK-RL |
| Aerial | Pegasus Simulator, Aerial Gym, gym-pybullet-drones, RotorPy, Flightmare, FlightGoggles, jMAVSim, JSBSim, FlightGear, X-Plane, RealFlight |

### 4.5 Components rather than simulators

These are worth naming because a modular architecture can adopt them without adopting a whole simulator. Newton, MuJoCo, PhysX 5, Bullet, DART, Jolt, AGX Dynamics and Vortex are physics engines. Madrona is a batched GPU renderer. Infinigen is a procedural scene generator that exports to Unreal Engine and Isaac Sim. RobotecGPULidar is a GPU lidar library. The ROS 2 `simulation_interfaces` package is a standard control surface for simulators, and its adoption is discussed in section 6.9.

---

## 5. Deep dives

### 5.1 The Unreal Engine family

Every Unreal candidate shares one inheritance and one liability. The inheritance is Unreal's renderer, which since version 5 provides Nanite virtualised geometry, Lumen global illumination and a mature material system, and which is the reason TartanAir and TartanGround, the two largest synthetic visual SLAM datasets, were generated from AirSim on Unreal. TartanGround alone spans 63 environments, 878 trajectories and 1.44 million samples with stereo, depth, semantics, optical flow and simulated lidar. The liability is that Unreal is a game engine whose scene graph, tick model and threading are optimised for interactive frame rates rather than for physical determinism, so every robotics framework built on it must impose a simulation clock from outside, and every one of them does so differently.

A second liability is commercial. Unreal Engine remains free for annual gross revenue below one million United States dollars, but non-game commercial use above that threshold is licensed per seat at 1,850 dollars per year, with optional direct support at a further 1,500 dollars per seat. This does not affect research use and does not affect the source availability of the robotics plugins, but it is a real constraint on any commercial deployment path, and it has no analogue in Gazebo, O3DE or the MuJoCo stack.

#### 5.1.1 microsoft/AirSim

The origin of the lineage, 18.4k stars, MIT licensed, built on Unreal Engine 4 with an experimental Unity path. Its architecture established the pattern the whole family still follows, namely a header-only `AirLib` containing vehicles, sensors and physics, an Unreal plugin, and a msgpack remote procedure call server on port 41451 serving Python, C++ and Matlab clients. It supports software in the loop with PX4 and ArduPilot and hardware in the loop with PX4.

It is dormant. The commit history shows substantive work ending in July 2022, with only three isolated commits since, in May 2025, March 2026 and June 2026. It should be treated as a historical reference, not a candidate.

#### 5.1.2 Cosys-AirSim

The current `NRT_WS` simulator, maintained by the Cosys-Lab at the University of Antwerp. It is the most capable sensor implementation in the AirSim lineage. It adds a GPU-accelerated lidar with realistic intensity generation, an echo sensor modelling sonar and radar, instance segmentation and multi-layer annotation for ground truth, camera chromatic aberration, motion blur and lens distortion, skid-steering vehicles including the ClearPath Husky and Pioneer P3DX, a Matlab toolbox, and both Python and C++ ROS 2 wrappers. It dropped Unity support and moved to Unreal Engine 5, with the main branch targeting 5.8 and a long term support branch on 5.2.1.

Two facts must be held together when judging its future. The README states plainly that the repository "is provided as is, will not be actively updated and comes without warranty or support", yet the commit history shows a burst of work on 2026-07-17 and a push on 2026-07-22, and releases v3.4 and v3.4.1 for Unreal 5.8 in July 2025. The honest reading is that this is a research group's artefact released in bursts around its own publications, with no maintenance commitment, 402 stars and fifty open issues. That is a supportable position for a laboratory and an unsupportable one for a toolkit that intends to depend on it for a decade.

Against the criteria it scores highly on rendering and sensors and poorly everywhere the three lessons of section 1 apply. Its ROS 2 bridge polls over remote procedure calls, its clock is a `SteppableClock` published on a private `~/clock` topic and disabled by default, its lockstep key is inert on the ArduPilot path, it has no vectorised environment abstraction for reinforcement learning, and vehicles are configured through `settings.json` rather than imported from a robot description.

#### 5.1.3 Project AirSim

Microsoft's own successor to AirSim, discontinued internally and released under the MIT licence as part of a DARPA-supported initiative, now developed publicly by IAMAI Simulations, a team of former AirSim engineers. It is the most architecturally interesting member of the family and the one that fixes, by design, the two defects that most damage the current stack.

The architecture is three layers, namely simulation libraries in C++ that own robots, physics, sensors and the tick loop, an Unreal Engine 5 plugin that binds those libraries to rendering and to the game thread, and client libraries that reach the simulator over the network. The transport is the decisive difference from AirSim. Clients connect over NNG, the successor to nanomsg, with topics published on port 8989 in a publish and subscribe pattern and services on port 8990 in a request and response pattern, serialised with a MessagePack and JSON hybrid. Sensor data is pushed, not polled. Control commands use the request-response channel where that semantics is correct.

The clock is the second decisive difference, and the mechanism must be selected rather than assumed, because the scene configuration offers four clock types with different scheduling behaviour. They are `steppable`, `real-time`, `engine-driven` and `external-clock`, at `core_sim/include/core_sim/clock.hpp:186-191`. The default is `steppable`, which does run its own periodic scene executor on a dedicated operating system thread started at `core_sim/src/scene.cpp:578-600`. The documented host-driven model, in which the core simulation "does not run its own periodic scene executor" and a host outside that scheduler instead supplies elapsed time through `AccumulateStep` for the simulation to consume in fixed `step-ns` steps, applies only to `engine-driven` and `external-clock`, which are the two types for which that executor is deliberately not started, at `:590-596`. Both of those construct the same `EngineDrivenClock` and are behaviourally identical today, at `:1076-1091`. Under Unreal the host is the game thread, and `AUnrealScene::Tick` passes each frame's delta time into the engine-driven clock and drains pending fixed steps, while `external-clock` is reserved for driving the simulation libraries from another application. The substantive advantage over Cosys-AirSim holds regardless of type, since deterministic fixed-step execution with pause and manual stepping is genuinely available and `SteppableClock` alone implements the pause and step API at `core_sim/src/clock.cpp:106-142`, which is exactly the property that makes reproducible regression testing possible.

This section was refined on 2026-08-02, having previously described the host-driven model alone and read as though that were the default. It is not, and the distinction matters because the default `steppable` type runs on its own thread rather than on the Unreal tick, which is the subject of open upstream issue 42, proposing exactly the refactor the earlier description assumed was already the norm. Detail in [project-airsim-architecture.md](project-airsim-architecture.md) §B.

The ROS 2 integration is a C++ package, `projectairsim_ros2_cpp`, an `rclcpp` node that connects through the C++ client, discovers simulator topics, republishes them as typed messages, and exposes services and a `MoveOnPath` action. It depends on `rosgraph_msgs`, which means it publishes the simulation clock on the standard topic rather than on a private one. It is still a bridge process rather than an in-process client library, so it does not reach the standard set by O3DE or CARLA, but it is a push bridge rather than a polling one, which is the important distinction.

Project AirSim implements ArduPilot, and the tree's own documentation contradicts itself about whether it does, which is worth recording because the contradiction is easy to resolve the wrong way. `Architecture.md` line 88 describes `vehicle_apis/` as containing "Robot controllers, SimpleFlight, ArduPilot, PX4", and lines 472 and 1095 repeat the pairing of PX4 and ArduPilot. Those statements are correct. Against them, `docs/controllers/controllers.md` states that "Project AirSim supports the following flight controllers, Simple Flight, PX4 Autopilot, and Manual Controller", and the robot configuration schema quoted at `docs/config_robot.md:324` admits only `simple-flight-api`, `px4-api` and `manual-controller-api`. Those two are stale prose, and the source settles it.

The implementation is `class ArduCopterApi : public VTOLFWApiBase` at `vehicle_apis/multirotor_api/include/arducopter_api.hpp:32`, with 862 lines of implementation at `vehicle_apis/multirotor_api/src/arducopter_api.cpp`, registered under the configuration string `ardupilot-api` at `simserver/src/simserver.cpp:299-301`. The controller enumeration in the machine-readable schema at `client/python/projectairsim/src/projectairsim/schema/robot_config_schema.jsonc:71` reads `simple-flight-api`, `simple-drive-api`, `px4-api`, `ardupilot-api`, `manual-controller-api`, `matlab-controller-api`, and an `ardupilot-settings` block with `ardupilot-ip` and `ardupilot-udp-port` follows at `:539-550`, made mandatory for that controller type at `:638-649`. Four worked example configurations and two ArduPilot parameter files ship under `client/python/example_user_scripts/ardupilot/`. The wire protocol is field for field the one Cosys-AirSim speaks, on the same default ports 9003 and 9002. The full evidence is in [project-airsim-architecture.md](project-airsim-architecture.md) §A and the migration is planned in [../plans/project-airsim-integration.md](../plans/project-airsim-integration.md).

This section previously concluded the opposite, that Project AirSim has no ArduPilot support and that `Architecture.md` was aspirational on the point, and it was corrected on 2026-08-02. Two mistakes produced that conclusion and both are worth avoiding again, namely trusting the prose documentation over the source, and inspecting `vehicle_apis/` at directory granularity rather than at file granularity, which shows only `multirotor_api` and `rover_api` and hides `arducopter_api.cpp` inside the first of them. The consequence to carry forward is that the scoring matrix in section 7 was computed before the correction, so Project AirSim's autopilot score of 3 rests partly on the false premise and would be higher on the corrected facts, tempered by the path being untested upstream.

What it does have for PX4 is thorough. The `px4-settings` block exposes a `lock-step` boolean whose documentation states that when true "Project AirSim and PX4 execute synchronously and can run faster or slower than real time as needed", and a `use-serial` boolean for hardware in the loop over a serial port. The controller comparison table records PX4 support for quadrotor, hexarotor, VTOL quad-x tailsitter and VTOL quad tiltrotor airframes in software in the loop, and quadrotor only in hardware in the loop.

Physics is pluggable in a limited sense. The `physics/` directory contains fast physics and a Matlab backend, documented at `docs/physics/fast_physics.md` and `docs/physics/matlab_physics.md`, alongside Unreal's own physics, and the simulation libraries define a `PhysicsEngine` interface with `update` and `applyForce`. Sensors comprise cameras with neural network post-processing and streaming, lidar generated by a compute shader, radar, battery models with several fidelity modes, and segmentation. Headless operation with `-RenderOffScreen` and `-nullrhi` is documented, along with Docker deployment and pixel streaming for browser access, and multiple robots in one scene are supported with per-robot APIs and robot-to-robot messaging.

Its weaknesses are the absence of any URDF or similar ingest, since robots are defined by JSONC link and joint configuration, the absence of a vectorised environment abstraction for large-scale reinforcement learning, a restriction to Unreal Engine 5.2 and 5.7 only, and a small maintaining organisation at 758 stars.

#### 5.1.4 Colosseum

The community fork of AirSim created by Codex Laboratories when Microsoft shut the original down, and the underlying simulation system for that company's SWARM platform. It was archived by its owner on 2026-07-11 and is now read-only, at 668 stars and seventy-four open issues.

This settles a question that has been open in the community since 2022. Of the three community continuations of AirSim, one is archived, one disclaims maintenance, and one is actively developed. Colosseum should be excluded from consideration, and any documentation or tutorial that recommends it should be treated as stale. Note that UNav-Sim, the Unreal Engine 5 underwater simulator, is built on AirSim extensions of this lineage, which places a maintenance risk under that project too.

#### 5.1.5 rclUE and RapyutaSimulationPlugins

Rapyuta Robotics' plugin pair, and the most architecturally pure answer to the transport question in the whole survey. Rather than bridging, rclUE embeds ROS 2 inside Unreal Engine by linking the C client libraries, `rcl` and `rclc`, and mapping ROS concepts onto Unreal types, with nodes as ActorComponents and publishers and subscribers as UObjects whose callbacks are bound through Unreal delegates. The design document is explicit that `rclcpp` was rejected because "rclcpp is built on fundamentals of inheritance which can directly conflict with UE4's version of inheritance necessary to work with serialization and garbage collection". The design philosophy is equally explicit, that unlike CARLA and AirSim, which fork Unreal for machine learning, rclUE is a standalone plugin deployable in any Unreal project. RapyutaSimulationPlugins adds robot components on top and supports distributed simulation by leveraging Unreal's multiplayer networking.

There is no simulated autopilot, no aerial vehicle support of note, a thin sensor suite and no reinforcement learning story. Activity is slow, with the devel branch showing work in January 2026 preceded by a gap back to October 2024, at 195 stars. It is best regarded as a reference implementation of in-process ROS 2 inside Unreal, and as a component to borrow from, rather than as a platform to adopt.

#### 5.1.6 Unreal Robotics Lab

A 2025 project published at ICRA 2026 that answers the Unreal liability directly by refusing to use Unreal's physics at all. It embeds MuJoCo in Unreal Engine as a C++ plugin and runs physics on its own thread while Unreal renders, so contacts are computed by a solver designed for contact-rich robotics and pixels are produced by a renderer designed for photorealism. Robots are authored in MJCF and dragged into the content browser to generate simulation-ready blueprints, with joints, actuators, tendons, muscles and flexcomp supported, and actuators driven from blueprints, from the editor, or over the network from Python and ROS 2 with proportional and derivative controllers and live gain tuning. It captures RGB, depth and segmentation with real camera intrinsics alongside MuJoCo's sensor suite, and it simulates smoke, fire and water for adverse-condition testing. The paper benchmarks visual navigation and SLAM methods within the framework.

The caveats are significant. ROS 2 is not built in, it is provided by a separate `urlab_bridge` package over ZeroMQ, which is a bridge with a serialisation hop. Only Unreal Engine 5.7 is supported and the documentation warns against 5.8 because of Vulkan driver regressions on Linux. There is no autopilot integration of any kind. It is young, with 497 stars and 101 commits, though it is actively developed with commits in July 2026. For a laboratory that wants photorealistic perception over trustworthy contact dynamics, this is the cleanest architecture available, and it is the one to watch.

#### 5.1.7 CARLA

The autonomous driving simulator, and the family member that has gone furthest on transport. Release 0.10.0 in December 2024 moved to Unreal Engine 5.5 with Lumen and Nanite and the Chaos vehicle physics engine, and 0.9.16 in September 2025 shipped native ROS 2 integration built into the server, connecting directly to Foxy, Galactic, Humble and later without a bridge tool and therefore without the latency of one. Combined with synchronous mode and a fixed simulation delta, this makes CARLA the most complete demonstration that a photorealistic Unreal simulator can speak ROS 2 natively and deterministically.

It is domain-locked. Vehicles and pedestrians are Unreal assets, there is no robot description ingest, no aerial or legged support, and no autopilot integration. It belongs in this survey as an architectural proof and as the tool of choice should ground vehicle work in urban scenes ever become a priority.

#### 5.1.8 HoloOcean, UNav-Sim and marine Unreal

HoloOcean 2.0, from the Field Robotic Systems Lab at Brigham Young University, migrated to Unreal Engine 5.3, added vehicle dynamics from the Fossen models, and gained ROS 2 support through a bridge built on `rclpy` and the Python client. Its distinguishing capability is acoustics, with ray-casting sonar covering sidescan, forward-looking and bathymetric modes, an octree-based sonar model, Doppler velocity logs, inertial sensors, optical and acoustic modems, and semantic labelling for both vision and sonar ground truth. The default tick is 30 Hz with physics substepping configurable to 240 Hz, and multi-agent underwater simulation is supported. A 2025 paper documents hardware in the loop testing of an underwater vehicle with it.

UNav-Sim is the other Unreal marine option, built on AirSim extensions with Unreal Engine 5, shipping a nonlinear model predictive controller for the BlueROV2 Heavy, a pipe-following planner and visual SLAM. Stonefish is the non-Unreal alternative, GPL-3.0, with six degree of freedom hydrodynamics, sonar, event cameras, thermal cameras and a `stonefish_ros2` package. DAVE has not been touched since December 2023 and should be considered dormant.

#### 5.1.9 Closed Unreal platforms

AirGen, from Scaled Foundations, is the commercial evolution of AirSim by its original creator, offering synthetic and geospatial scenes, custom mesh import, occupancy maps, path planning, signed distance fields, and RGB, depth, segmentation, infrared, optical flow, GPS, inertial and lidar streams, delivered entirely in the cloud as part of the GRID platform for robot foundation models. Duality Falcon is an Unreal-based digital twin platform whose middleware can create, write and launch ROS and ROS 2 nodes automatically for sensor publishing, with a runtime Python API and open-loop or closed-loop operation. Spleenlab offers a proprietary aerial simulator.

None of the three was deep-dived, in accordance with the rule agreed for this survey that a closed core earns a deep dive only if it clears most criteria on its surface. Each fails the same three, namely no self-hosted deployment guarantee, no ability to modify the simulation core when a sensor model or a clock behaviour is wrong, and no ArduPilot path. For a toolkit whose purpose includes developing novel algorithms inside the simulation loop, an unmodifiable core is a structural rather than an incidental limitation.

### 5.2 The NVIDIA stack

The user's stated position is that Isaac Lab is closed at its core and therefore unattractive. That position was accurate before 2025 and is no longer accurate, and since it determines the ranking it must be addressed with evidence.

Isaac Lab is BSD-3-Clause. Isaac Sim was open-sourced at SIGGRAPH 2025, and the source in the `isaac-sim/IsaacSim` repository is released under Apache 2.0, which permits free use, modification and redistribution including commercial use. What remains closed is the Omniverse Kit SDK on which Isaac Sim is built, together with the bundled assets and textures, which are covered by separate terms, and NVIDIA states that external contributions are not accepted at this time. So the correct characterisation is a permissively licensed application on a closed runtime, not a closed product.

More importantly, that dependency is being deliberately dissolved. The Isaac Lab development update, discussion 4339 of 6 January 2026, states that "we're freezing the main branch and continuing development in a new develop branch", that this branch "will contain larger refactoring efforts to support both PhysX and Newton physics backends, as well as multi-renderer support", that the `feature/newton` branch is the "Isaac Lab - Newton Beta 2 branch", that the intent is to "run headless training workloads without requiring a full Isaac Sim installation", and that "pluggable visualizers and renderers allow you to swap backends without code changes". The decisive sentence is that "by decoupling from RTX rendering requirements, you will be able to run Isaac Lab on a mix of the latest NVIDIA compute GPUs", naming L40S, H100, H200 and B200. The refactor is visible in the tags, where the current release line is v3.0.0-beta2 of 17 June 2026 rather than the 2.x series. If that direction holds, the closed Kit runtime becomes an option rather than a requirement, and the open Newton engine becomes the physics core.

#### 5.2.1 Isaac Sim 6.0

General availability was 8 June 2026. It is built on the Omniverse Kit framework with Universal Scene Description as the scene representation and Fabric as a vectorised runtime data layer, and it now supports both PhysX and Newton as physics backends, with URDF and MJCF importers producing assets structured so the backend can be switched, though only Newton's MuJoCo Warp solver is currently supported. Rendering is RTX ray tracing. Sensors are the strongest in the survey, comprising RTX lidar, cameras, radar, a new acoustic sensor with GPU-accelerated ultrasonic simulation, structured light cameras with custom projector patterns, an image signal processor pipeline configured through USD schema, and independent capture rates per renderer-based sensor. Synthetic data generation is handled by Replicator with domain randomisation.

The ROS 2 integration runs in-process through OmniGraph nodes rather than an external translator, publishes the simulation clock and the real time factor, supports H.264 compressed image publishing with hardware-accelerated encoding for software in the loop workflows, and integrates with NITROS for hardware-accelerated, low-latency image and point cloud transport when paired with Isaac ROS. Isaac Sim 6.0 allows any ROS 2 distribution built with Python 3.12 to be sourced directly, and adds native Windows ROS 2 support. A documented caveat is that publishing from Python is slow and is a known bottleneck, so the graph-based publishers should be preferred.

The cost is hardware. An RTX GPU with ray tracing cores and at least 12 GB of video memory is required, 16 GB or more is recommended for training, and A100 and H100 are explicitly unsupported because they lack ray tracing cores. Containers are Linux only, and remote access is by WebRTC streaming or the new browser-based client.

#### 5.2.2 Isaac Lab

The learning framework above Isaac Sim, at 7.8k stars and pushed on the day this survey was compiled. It provides manager-based and direct workflows, actuator models, multi-frequency sensor simulation, data collection pipelines and domain randomisation, and integrates with the common reinforcement learning libraries. Published throughput is 135,000 frames per second for Unitree H1 humanoid locomotion and above 150,000 for the Franka cabinet manipulation benchmark across 4,096 parallel environments, reported in NVIDIA's research digest of 10 February 2026. Independent measurements place quadruped locomotion at roughly 90,000 frames per second on an RTX A6000 with 4,096 environments. Multi-agent reinforcement learning is supported and has been extended by third parties with heterogeneous and adversarial variants using MAPPO and HAPPO.

#### 5.2.3 Newton

Newton tagged version 1.0.0 on 10 March 2026 according to its own `CHANGELOG.md`, and general availability was announced at GTC 2026 in the same month, having been unveiled in beta the previous year. Development since has been rapid, with 1.1.0 on 13 April, 1.2.0 on 12 May, 1.3.0 on 11 June and 1.4.0 on 28 July 2026. Note that secondary press reporting dates the release to 17 March 2026, which is the announcement rather than the tag. It is a GPU-accelerated physics engine built on NVIDIA Warp and OpenUSD, developed with Google DeepMind and Disney Research under the Linux Foundation, licensed Apache 2.0, at 5.3k stars and pushed daily. It ships multiple solvers, including MuJoCo Warp as the primary backend and Kamino, with velocity-based dynamics and an ADMM solver for multiphysics, and it supports differentiable simulation, URDF and MJCF import, inverse kinematics, contact and inertial sensors, and cloth and cable simulation. NVIDIA reports MuJoCo Warp on an RTX PRO 6000 Blackwell at up to 252 times the speed of MJX for locomotion and 475 times for manipulation.

The strategic significance for this survey is larger than the performance numbers. Newton is the first credible attempt at a shared, open, GPU-native physics substrate across NVIDIA, DeepMind and the MuJoCo community, governed by a neutral foundation. A toolkit that treats physics as a swappable component gains the most from this development, and a toolkit welded to one simulator's built-in solver gains the least.

#### 5.2.4 Pegasus Simulator

The aerial layer on Isaac Sim, BSD-3, 855 stars, providing PX4 integration through a MAVLink backend, a Python control interface, and an experimental ArduPilot interface. The PX4 backend connects over TCP on port 4560 with lockstep available, implementing the standard exchange in which the simulator sends `HIL_SENSOR` with a timestamp, PX4 performs one iteration of estimation and control, returns `HIL_ACTUATOR_CONTROLS`, and the simulator waits for that message before stepping physics. Version 5.1.0 was released on 26 October 2025 for Isaac Sim 5.1.0, and version 4.5.1 the day before for Isaac Sim 4.5.0, in which the ArduPilot experimental interface was fixed and improved by community contributors. The ArduPilot interface was not tested in 5.1.0, and only multirotors are supported.

This is the weak link in the strongest candidate. The ArduPilot path exists, it is community-maintained, it is labelled experimental, and it is untested against the current release. Section 9 proposes the spike that would resolve this.

### 5.3 The MuJoCo and Newton learning stack

MuJoCo itself, at 14k stars and Apache 2.0, remains the reference for contact-rich dynamics. MJX brought it to accelerators through JAX, MuJoCo Warp brings it to Warp with the throughput multiples quoted above, MuJoCo Playground packages more than fifty environments across classic control, quadruped and bipedal locomotion and manipulation with demonstrated zero-shot sim-to-real transfer, and mjlab reimplements the Isaac Lab manager-based API on MuJoCo Warp with minimal dependencies, reaching version 1.4.0 on 26 May 2026 with MuJoCo 3.10 and procedural terrain generation.

Vision is handled by Madrona, a GPU entity-component-system with a CUDA batch ray tracer and a Vulkan rasteriser, which renders thousands of environments in parallel to produce pixel observations for asymmetric actor-critic training. This is a genuine capability but it is not photorealism, and it will not close a perception sim-to-real gap for a feature-based SLAM front end in the way that path tracing does.

The ROS 2 story is adequate rather than good. The `ros-controls/mujoco_ros2_control` package provides a `ros2_control` system interface wrapping MuJoCo's simulate application, with force-torque, pose, inertial and camera support, and camera and lidar moved out into plugins, at version 1.1.0 in May 2026. URDF is accepted but the conversion to MJCF is described as highly experimental and MuJoCo does not support the full URDF and xacro feature set. There is no autopilot integration anywhere in this stack.

The right way to read this family is as the reinforcement learning engine room rather than as a whole simulator. It is where policies are trained fastest, and it is where the open physics substrate is being built.

### 5.4 Genesis World

Genesis began as an academic project in December 2024 and became Genesis World 1.0 under Genesis AI in May 2026, at roughly 30k stars and Apache 2.0. The platform now comprises a unified multi-solver physics engine covering rigid bodies, finite elements, material point method, smoothed particle hydrodynamics, position-based dynamics, stable fluids and an implicit contact solver, a real-time path-traced renderer named Nyx, a Python-to-GPU compiler named Quadrants targeting CUDA, ROCm, Metal, Vulkan, x86 and ARM64, and a simulation interface, all behind one Pythonic API. It imports URDF, MJCF, OBJ, GLB and USD, supports heterogeneous parallel environments and differentiable simulation, and the company reports that a robot foundation model evaluation requiring nearly a week on hardware completes in about thirty minutes.

Two cautions are necessary. The original headline of 43 million frames per second on an RTX 4090 was measured with robot self-collisions disabled, and independent testing found that enabling them reduced the figure by roughly 150 times to about 0.29 million frames per second, on a par with or slower than existing GPU simulators. The team subsequently published a more representative report. Second, ROS 2 support is absent from the project itself and exists only as community bridges. The breadth of physics is real and unmatched, the throughput claims should be verified against your own workload, and the robot software integration is not there yet.

### 5.5 Gazebo Jetty

The tenth named Gazebo release, long term support until September 2030, Apache 2.0. It is the weakest candidate on rendering and the strongest on everything the robot software stack touches.

Physics is genuinely swappable at runtime through `gz-physics`, with DART as the default and Bullet, Bullet-Featherstone and the trivial physics engine selectable by a command line flag naming the plugin shared library. Robot description is SDF and URDF natively. Sensors include GPU lidar and cameras, though camera realism is the acknowledged limitation and is the reason vision algorithm testing in Gazebo transfers poorly. Jetty adds a wheel slip lookup system driven by an eight-bit colour map for friction, automatic inertial computation from geometry, Qt 6, and Zenoh as an alternative transport implementation selected by an environment variable, which is a meaningful latency and discovery improvement for large graphs.

For ArduPilot it is the reference. The `ardupilot_gazebo` plugin supports Garden, Harmonic, Ionic and Jetty, exchanges state with SITL over a JSON interface selected by `--model JSON`, and, critically, implements true simulation lockstep, to the point that the documentation notes a debugger can now stop Gazebo time. For PX4 it is the only officially supported three-dimensional simulator alongside the in-hardware simulator, with lockstep and the `HIL_SENSOR` and `HIL_ACTUATOR_CONTROLS` exchange on port 4560. Reported speeds are six to ten times real time on desktop machines and three to four times on laptops, for scenes without heavy sensor loads.

Its failings against this survey's criteria are concentrated and severe. There is no GPU-parallel reinforcement learning path beyond wrapping single instances, procedural generation is manual, and multi-robot scenes with cameras degrade quickly. It is also the reference implementation of the ROS 2 `simulation_interfaces` standard, which matters for the modularity criterion.

### 5.6 O3DE with the ROS 2 Gem

The Open 3D Engine is Amazon's former Lumberyard, donated to the Linux Foundation, Apache 2.0 and MIT, 9.6k stars, with release 26.05 in May 2026. Its robotics support comes from Robotec.ai in the form of a family of gems covering ROS 2, controllers, robot import and sensors.

Its distinguishing property is stated plainly in the documentation, that the ROS 2 Gem "does not use any bridges to communicate between ROS and O3DE, and a simulation node will function as any other ROS 2 node". This is the in-process topology that section 1 identifies as the correct answer to the transport problem, and O3DE is the only fully open, non-game-licensed engine that provides it with a photorealistic renderer. Sensors cover two- and three-dimensional lidar, RGB-D cameras, inertial units, wheel odometry, GNSS and contact, with the RGL gem providing GPU-accelerated lidar reported at up to thirty times faster. Robot import handles URDF, SDF and xacro. Simulation time for ROS 2 is explicitly handled. O3DE 25.05 was the first release to ship the standardised ROS 2 simulation interfaces, developed with Open Robotics, NVIDIA and Robotec.ai, and multi-robot warehouse demonstrations at ROSCon have shown it scaling.

The gaps are equally clear. There is no autopilot integration of any kind, reinforcement learning is on the roadmap rather than in the engine, physics is PhysX 5 without a swappable abstraction, and independent assessments in early 2026 judge the sensor plugins less mature than Gazebo or Isaac Sim, with RGB-D and three-dimensional lidar requiring more manual setup. The robotics community around it remains small, with the `o3de-extras` repository at 86 stars.

### 5.7 Webots, CoppeliaSim, Drake and Chrono

Webots is Apache 2.0, mature, and one of the external simulators ArduPilot supports directly, with multicopter and rover examples. It is limited to ODE, has modest rendering, and releases annually, with R2025a from 31 January 2025 the current stable version at the time of writing.

CoppeliaSim has the best physics swappability in the field, with five engines, namely MuJoCo, Bullet, ODE, Vortex and Newton, and Drake in preparation, together with a distributed control architecture in which every object can be driven by an embedded script, a plugin, or a remote API client in any of eight languages, plus forward and inverse kinematics for arbitrary mechanisms. The core is proprietary with a free education tier, rendering is dated, and there is no autopilot path.

Drake is the reference for model-based control and analysis, BSD-3, with rigorous multibody dynamics and optimisation, and no ambition toward photorealistic perception. Project Chrono is BSD-3 and deserves more attention than its visibility suggests, since `Chrono::Sensor` generates lidar, camera, radar, GNSS and inertial data through NVIDIA OptiX ray tracing with headless support, `Chrono::ROS` bridges to ROS 2, and `Chrono::CRM` and `SCMTerrain` provide deformable-terrain terramechanics that no other candidate matches. For legged or wheeled ground vehicles on deformable soil it is the correct tool.

### 5.8 Aerial-specific and other domain simulators

Aerial Gym Simulator from the Autonomous Robots Lab at NTNU is the most relevant aerial reinforcement learning framework, built on Isaac Gym with GPU-resident geometric controllers permitting simultaneous control of thousands of multirotors, and customisable ray-cast lidar and camera sensors producing depth, segmentation and optical flow. It inherits Isaac Gym's deprecation, which is the reason its long-term home is likely to be Isaac Lab or Newton.

gym-pybullet-drones remains the accessible baseline for multirotor reinforcement learning, MIT licensed and active. RotorPy is a PX4 community-supported Python simulator. Flightmare and FlightGoggles, once the leading research aerial simulators, have not been substantively updated since 2023 and 2024 respectively and should be considered dormant. jMAVSim, JSBSim, FlightGear, X-Plane and RealFlight remain useful for flight dynamics fidelity and are irrelevant for perception.

For space, OmniLRS and the Space Robotics Bench build on Isaac Sim. For driving, AWSIM with Autoware uses ROS 2 For Unity, which like rclUE links the ROS 2 middleware directly rather than bridging over TCP, and MetaDrive serves lightweight driving reinforcement learning.

### 5.9 Dormant or excluded

The following were examined and set aside, with the reason recorded so that the judgement is not silently reopened. microsoft/AirSim is dormant since July 2022. Colosseum was archived on 2026-07-11. Flightmare last saw work in May 2023, FlightGoggles in April 2024, DAVE in December 2023, legged_gym in May 2025 and Isaac Gym Envs in October 2023. Unity-Robotics-Hub has not been updated since November 2024 and Unity's own robotics offering has been renamed and restructured, which makes the Unity path unattractive for a long-lived dependency despite AWSIM's continued health. Morse, USARSim, UWSim and Gazebo Classic are legacy.

---

## 6. Cross-cutting analysis

### 6.1 Transport architecture, the criterion that separates the field

Four topologies exist, and the difference between them is worth more than any feature comparison.

| Topology | Mechanism | Examples | Consequence |
|---|---|---|---|
| Polling remote procedure call | Client requests each sample | Cosys-AirSim, microsoft/AirSim | One blocking round trip per sensor per cycle, measured at 14 Hz against a 100 Hz target in this workspace |
| Push bridge | Simulator publishes, a translator republishes to ROS 2 | Project AirSim over NNG, HoloOcean over rclpy, URLab over ZeroMQ, `ros_gz` for Gazebo | Rate limited by the translator, not by the request pattern, so it scales with sensor count |
| In-process client | ROS 2 middleware linked inside the simulator | O3DE ROS 2 Gem, rclUE, ROS 2 For Unity, CARLA 0.9.16 and later, Isaac Sim OmniGraph | No inter-process hop for the publish path, lowest achievable latency |
| Accelerated transport | Type adaptation and zero copy above ROS 2 | Isaac ROS with NITROS, Zenoh in Gazebo Jetty | Removes serialisation and copies for images and point clouds |

The present stack sits in the worst row. Any of the other three would resolve the measured defect, and the top row is not recoverable by tuning.

### 6.2 Time synchronisation and lockstep

| Simulator | Clock model | Autopilot lockstep | Pause and step |
|---|---|---|---|
| Cosys-AirSim | `SteppableClock`, 3 ms physics period, anchored once at construction | Absent on the ArduPilot path, `LockStep` key inert | Pause exists, no negotiated stepping |
| Project AirSim | Engine-driven clock consuming host-supplied elapsed time in fixed `step-ns` steps, external clock reserved | PX4 lockstep configurable, faster or slower than real time | Yes, by construction |
| Gazebo Jetty | Authoritative simulation clock published on `/clock` | True lockstep with ArduPilot, official lockstep with PX4 | Yes, including debugger-stopped time |
| Isaac Sim | Deterministic stepping, `/clock` and real time factor published | PX4 lockstep through the Pegasus MAVLink backend | Yes |
| CARLA | Synchronous mode with fixed delta | Not applicable | Yes |
| MuJoCo and Newton | Explicit step function under caller control | Not applicable | Yes |

Note that the ArduPilot and PX4 answers differ in kind. PX4 defines lockstep in its simulator MAVLink API and every major simulator implements it. ArduPilot's flight dynamics model backends are driven by a JSON or backend-specific exchange, and only the Gazebo plugin implements true lockstep, with the AirSim path providing an accidental handshake through a blocking receive. This asymmetry is the single most important fact for an ArduPilot-centred toolkit.

A further fact from the workspace's own investigation deserves repeating here, because it constrains the hardware roadmap independently of simulator choice. ArduPilot has no mechanism anywhere to slew or step its monotonic clock from an external source, `AP_RTC` moves only a shift, and the `/clock` DataReader is compiled for software in the loop builds alone and would be semantically wrong on hardware. The hardware answer is a common UTC reference, and the simulator answer is that the simulator's clock is authoritative.

### 6.3 Swappable physics

| Simulator | Engines | Switchable at runtime |
|---|---|---|
| CoppeliaSim | MuJoCo, Bullet, ODE, Vortex, Newton, Drake planned | Yes |
| Gazebo | DART, Bullet, Bullet-Featherstone, TPE | Yes, by plugin selection |
| Isaac Sim 6.0 | PhysX 5, Newton with MuJoCo Warp | Yes, importers emit backend-agnostic assets |
| Genesis World | Rigid, FEM, MPM, SPH, PBD, fluids, IPC | Yes, coupled through an explicit coupler |
| Newton | MuJoCo Warp, Kamino, VBD with ADMM | Yes |
| Project AirSim | Fast physics, Matlab, Unreal | Configuration-level |
| Cosys-AirSim, CARLA, O3DE, URLab | One engine each | No |

### 6.4 Robot description ingest

Isaac Sim accepts URDF, MJCF and USD. Newton, Genesis and the MuJoCo stack accept URDF and MJCF. Gazebo and O3DE accept URDF, SDF and xacro. CoppeliaSim and Webots import URDF. URLab accepts MJCF. Neither Cosys-AirSim nor Project AirSim nor CARLA accepts any standard description, which means a new vehicle is a code and configuration exercise rather than a modelling exercise. For a toolkit that intends to onboard legged robots, ground vehicles and marine platforms, this criterion is a direct multiplier on the cost of every future platform.

### 6.5 Procedural environment generation

Unreal's Procedural Content Generation framework became production-ready in Unreal Engine 5.7, runs almost twice as fast as in 5.5, gained GPU generation and an editor mode with spline, point-painting and volume tools bound to PCG graphs. Any Unreal-based candidate on 5.7 or later inherits it, which covers Cosys-AirSim on 5.8, Project AirSim on 5.7 and URLab on 5.7, though none of the three exposes a documented robotics workflow over it, so the randomisation harness would have to be written locally. Isaac Sim provides Replicator with domain randomisation over USD scenes. Infinigen and Infinigen Indoors generate photorealistic scenes procedurally in Blender under a BSD licence, with 79 asset generators, roughly 741 random variables and a constraint-based layout solver, and export to both Unreal Engine and Isaac Sim, which makes it a simulator-independent answer to this requirement. Gazebo, Webots and CoppeliaSim have no comparable capability.

### 6.6 Parallel reinforcement learning throughput

| Stack | Reported throughput | Conditions |
|---|---|---|
| Isaac Lab | 150,000 frames per second, Franka cabinet, and 135,000 for Unitree H1 locomotion | 4,096 environments, NVIDIA report of 2026-02-10 |
| Isaac Lab, independent | about 90,000 frames per second, ANYmal locomotion | 4,096 environments, RTX A6000 |
| MuJoCo Warp | up to 252 times MJX for locomotion, 475 times for manipulation | RTX PRO 6000 Blackwell |
| ManiSkill3 | above 30,000 frames per second, about twice Isaac Lab with two to three times better memory efficiency | Rasterised rendering, not ray traced, so not a like-for-like comparison |
| Genesis | 43 million frames per second headline, about 0.29 million with self-collisions enabled | RTX 4090, Franka benchmark |

The pattern is that credible figures cluster between 10^5 and 10^6 environment steps per second for articulated robots on one modern GPU, and that any figure far above that band should be read with its collision and action settings in hand.

### 6.7 Licence and cost

Permissive and self-hostable are Isaac Lab under BSD-3, Isaac Sim source under Apache 2.0 with a closed Kit runtime, Newton, mjlab, MuJoCo, MuJoCo Playground, Genesis, Gazebo, O3DE, Webots, Drake, Chrono, ManiSkill and Infinigen under Apache 2.0 or BSD, and the whole AirSim lineage together with CARLA and HoloOcean under MIT with Unreal's engine terms layered beneath. Copyleft applies to Stonefish under GPL-3.0 and to `ardupilot_gazebo` under LGPL-3.0. Proprietary are CoppeliaSim's core, RaiSim, AGX Dynamics, Vortex, Duality Falcon, AirGen and GRID, and Spleenlab.

The practical cost line is not the licence, it is the hardware. Isaac Sim requires an RTX GPU with at least 12 GB of video memory and does not run on A100 or H100 accelerators, which means a datacentre training fleet and a simulation workstation are different machines. The Newton and MuJoCo Warp path has no such restriction, which is precisely why Isaac Lab is being decoupled from RTX rendering.

### 6.8 Maintenance health, observed 2026-08-01

| Repository | Stars | Licence | Last push | State |
|---|---|---|---|---|
| isaac-sim/IsaacLab | 7,813 | BSD-3-Clause | 2026-08-01 | Active |
| newton-physics/newton | 5,272 | Apache-2.0 | 2026-08-01 | Active |
| isaac-sim/IsaacSim | 3,819 | Apache-2.0 with additional terms | 2026-07-02 | Active |
| Genesis-Embodied-AI/Genesis | ~30k | Apache-2.0 | 2026-07-31 | Active |
| google-deepmind/mujoco | ~14k | Apache-2.0 | 2026-07-31 | Active |
| mujocolab/mjlab | ~2.8k | Apache-2.0 | 2026-07-31 | Active |
| o3de/o3de | ~9.6k | Apache-2.0 and MIT | 2026-07-31 | Active |
| carla-simulator/carla | ~14k | MIT | July 2026 | Active |
| gazebosim/gz-sim | ~1.4k | Apache-2.0 | July 2026 | Active |
| cyberbotics/webots | ~4.5k | Apache-2.0 | July 2026 | Active |
| iamaisim/ProjectAirSim | 758 | MIT | 2026-07-30 | Active |
| URLab-Sim/UnrealRoboticsLab | 497 | Apache-2.0 | 2026-07-30 | Active |
| PegasusSimulator | 855 | BSD-3-Clause | July 2026 | Active |
| Cosys-Lab/Cosys-AirSim | 402 | MIT | 2026-07-22 | Bursty, disclaims support |
| ntnu-arl/aerial_gym_simulator | 748 | BSD-3-Clause | June 2026 | Active |
| rapyuta-robotics/rclUE | 195 | Apache-2.0 | 2026-01-05 | Slow |
| ArduPilot/ardupilot_gazebo | 218 | LGPL-3.0 | April 2026 | Active |
| ros-simulation/simulation_interfaces | 130 | Apache-2.0 | April 2026 | Active |
| CodexLabsLLC/Colosseum | 668 | MIT | 2026-07-08 | Archived 2026-07-11 |
| microsoft/AirSim | 18,354 | MIT | 2026-06-30 | Dormant since 2022 |
| uzh-rpg/flightmare | ~1.4k | Unclear | May 2023 | Dormant |
| Field-Robotics-Lab/dave | 296 | Apache-2.0 | December 2023 | Dormant |

Star counts are a proxy for community and nothing more. The signal that matters is the pairing of recent pushes with institutional backing, and by that measure the NVIDIA and Linux Foundation cluster, the Gazebo project and the MuJoCo lineage are the only ones with a credible ten-year outlook.

### 6.9 The standard that changes the modularity calculation

The ROS 2 `simulation_interfaces` package, developed by Robotec.ai with Open Robotics and NVIDIA, defines standard messages and services for spawning and deleting entities, moving them, stepping the simulation and querying ground truth. It is implemented in Gazebo Jetty, NVIDIA Isaac Sim 5.0 and later, and O3DE 2505 and later, and a common warehouse scene originating in Isaac Sim now loads in all three, which is the first practical demonstration of simulator interoperability in ROS.

The consequence for architecture is significant and should shape the toolkit's design regardless of which simulator wins. If the toolkit's simulation-facing code speaks `simulation_interfaces` for world control and standard `sensor_msgs` for data, then the simulator becomes a replaceable component rather than a foundation, and the cost of the next migration falls to near zero. This is the single highest-leverage design decision available, and it is independent of the ranking below.

---

## 7. Scoring

Scores are zero to five against the criteria and weights of section 3, normalised to one hundred. The scores are judgements, but each is traceable to a fact recorded in section 5.

| Simulator | Photo (10) | RL (10) | Autopilot (10) | ROS 2 (10) | Time (8) | Physics (6) | Sensors (8) | Ingest (6) | Embodiment (6) | Multi-agent (5) | Procedural (6) | Modularity (5) | Control (5) | Ecosystem (5) | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Isaac Sim 6.0 with Isaac Lab and Pegasus | 5 | 5 | 3 | 4 | 4 | 4 | 5 | 5 | 5 | 4 | 4 | 4 | 4 | 4 | 86.0 |
| Gazebo Jetty with ardupilot_gazebo | 2 | 1 | 5 | 4 | 5 | 5 | 4 | 5 | 5 | 3 | 2 | 5 | 5 | 5 | 76.8 |
| Project AirSim | 5 | 2 | 3 | 4 | 4 | 3 | 4 | 2 | 3 | 3 | 3 | 4 | 4 | 3 | 68.0 |
| Newton with mjlab and MuJoCo Playground | 2 | 5 | 0 | 2 | 3 | 4 | 2 | 5 | 5 | 4 | 3 | 5 | 5 | 5 | 65.4 |
| O3DE with ROS 2 Gem | 4 | 1 | 1 | 5 | 4 | 2 | 3 | 4 | 3 | 4 | 3 | 5 | 3 | 4 | 63.6 |
| Genesis World 1.0 | 4 | 5 | 0 | 1 | 2 | 5 | 2 | 5 | 4 | 4 | 3 | 4 | 3 | 3 | 60.8 |
| CARLA 0.10 | 5 | 2 | 0 | 5 | 4 | 2 | 4 | 1 | 1 | 4 | 3 | 3 | 2 | 4 | 58.2 |
| CoppeliaSim | 2 | 2 | 1 | 3 | 3 | 5 | 3 | 4 | 4 | 2 | 2 | 4 | 4 | 3 | 56.6 |
| Webots R2025a | 2 | 1 | 3 | 4 | 4 | 1 | 3 | 3 | 4 | 2 | 1 | 3 | 4 | 4 | 55.0 |
| Cosys-AirSim, the current stack | 5 | 1 | 4 | 2 | 2 | 2 | 4 | 1 | 3 | 2 | 3 | 3 | 3 | 2 | 54.4 |
| Unreal Robotics Lab | 5 | 1 | 0 | 2 | 3 | 2 | 3 | 4 | 4 | 2 | 3 | 3 | 4 | 3 | 53.2 |
| ManiSkill3 with SAPIEN | 3 | 5 | 0 | 1 | 2 | 2 | 2 | 4 | 3 | 3 | 3 | 4 | 3 | 4 | 52.8 |
| rclUE with RapyutaSimulationPlugins | 5 | 2 | 0 | 5 | 2 | 1 | 2 | 2 | 2 | 4 | 3 | 4 | 2 | 2 | 52.0 |
| HoloOcean 2.x | 4 | 1 | 2 | 3 | 3 | 1 | 4 | 1 | 2 | 3 | 2 | 3 | 3 | 3 | 50.4 |

Two sensitivity observations follow. If the autopilot weight is doubled, Gazebo overtakes Isaac Sim, which is the correct answer for a workspace whose immediate obligation is ArduPilot regression testing. If the reinforcement learning and photorealism weights are doubled and autopilot is halved, Isaac Sim's lead widens and the MuJoCo stack rises above Gazebo. No reweighting within reason promotes Cosys-AirSim, because its deficits are in criteria that every profile values.

---

## 8. Recommendation

The honest conclusion of this survey is that no single simulator satisfies the full requirement set today, and that the attempt to force one to do so is what produced the defects recorded in section 1. Two simulators and one standard interface satisfy it completely, and the standard interface is what makes the pair cost less than the single.

The primary recommendation is Isaac Sim 6.0 with Isaac Lab as the perception, learning and multi-embodiment platform. It leads on photorealism, sensor breadth, parallel throughput, robot description ingest and embodiment breadth, its licensing objection is materially weaker than it was a year ago, and its physics is converging on the open Newton engine under neutral governance. Its weakness is precisely the workspace's current speciality, aerial autopilot integration, where the ArduPilot path exists only as an experimental community backend in Pegasus.

The secondary recommendation is Gazebo Jetty with `ardupilot_gazebo` as the flight-stack and control validation platform. It has genuine lockstep with ArduPilot, an authoritative clock, swappable physics, URDF and SDF ingest, long term support to 2030, and it is the reference implementation of the simulation interfaces standard. It cannot do photorealistic perception and should not be asked to.

The enabling recommendation, and the one that should be executed first regardless of the above, is to make the toolkit's simulation-facing code speak standard interfaces rather than simulator-specific APIs. Sensor data through `sensor_msgs`, world control through `simulation_interfaces`, time through `/clock`, and robots through URDF. Every hour spent on that is an hour that is not lost at the next migration, and it is the reason the two-simulator strategy is affordable.

On the current stack, the recommendation is to retain Cosys-AirSim in place until a replacement is proven, and to stop investing in it beyond defect repair. Its rendering and its ArduPilot support are real, its maintenance disclaimer is explicit, and the transport and clock defects measured in this workspace are architectural rather than incidental. The migration path off it should not be rushed, because the ArduPilot photorealistic combination it provides is genuinely scarce.

Project AirSim deserves one qualification to that judgement. It is the only actively maintained, permissively licensed, Unreal Engine 5 simulator with a push transport, a deterministic fixed-step clock and a first-party ROS 2 C++ node, and it would resolve both transport and clock defects without leaving Unreal. Its blocker is the absence of ArduPilot. If contributing an ArduPilot vehicle API to it is acceptable work, then it becomes the shortest path from where the workspace is to where it needs to be, because the pattern to copy already exists in `AirLib` and the surrounding infrastructure is materially better.

Finally, three components should be adopted independently of the simulator decision. Newton, as the physics backend to prefer wherever a choice exists. Infinigen, as the procedural scene generator, since it exports to both Unreal Engine and Isaac Sim and therefore survives any migration. And Isaac ROS with NITROS or Zenoh, as the accelerated transport for image and point cloud streams.

---

## 9. Next steps

The following are ordered by information gained per unit of effort. Each is a spike with a defined acceptance criterion, and none of them commits the workspace to a migration.

1. Measure the true cost of the transport defect before replacing anything. Instrument the existing Cosys-AirSim bridge to separate remote procedure call round-trip time from image encoding and from executor scheduling, over the same window used on 2026-07-28. Acceptance is a per-stage latency budget that either confirms the round trip dominates or identifies a cheaper fix.

2. Establish the ArduPilot and Gazebo baseline. Bring up `ardupilot_gazebo` on Jetty with a copter, confirm true lockstep, and measure the distinct-stamp rate on `/ap/imu/experimental/data` under `use_sim_time` against the numbers recorded in [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md). Acceptance is a stamp cadence at the AP_DDS gate rather than at the clock publication interval, which would demonstrate that the quantisation defect is a property of the AirSim clock path and not of ArduPilot.

3. Resolve the Pegasus ArduPilot question. Install Pegasus 5.1.0 on Isaac Sim, run the experimental ArduPilot backend, and determine whether it survives contact with the current release. Acceptance is an armed, flying ArduCopter in Isaac Sim with `/ap/*` topics and camera frames sharing one time domain, or a precise statement of what breaks.

4. Evaluate Project AirSim end to end on a PX4 airframe, since that is its supported configuration, and measure the ROS 2 bridge throughput under the same sensor load that yielded 14.05 Hz on the current stack. Acceptance is a measured publication rate for inertial and image streams and a confirmation that `/clock` is published on the global topic.

5. Scope an ArduPilot vehicle API for Project AirSim. Read `vehicle_apis/multirotor_api` and the PX4 controller implementation, and estimate the work to add an ArduPilot backend speaking the JSON flight dynamics model interface that ArduPilot's SITL already accepts. Acceptance is a written estimate with the specific files involved, sufficient to decide whether to contribute it upstream.

6. Prototype the standard interface layer. Add a thin abstraction in `ros_ws` so that SLAM, control and logging consume `sensor_msgs`, `/clock` and `simulation_interfaces` rather than simulator-specific topics. Acceptance is the existing Basalt pipeline running unchanged against two different simulators.

7. Trial Infinigen export into whichever Unreal or Isaac environment survives the spikes above, and generate one procedural scene with ground truth. Acceptance is a rendered trajectory with depth, segmentation and pose usable as a SLAM benchmark.

8. Benchmark the learning path separately from the testing path. Run one locomotion task in Isaac Lab and the same task in mjlab, on the same hardware, and record environment steps per second and wall-clock time to a fixed reward. Acceptance is a number that decides whether the learning backend should be Isaac Lab or the lighter MuJoCo Warp stack.

Should any of these lead to a migration, that migration is a change and therefore belongs in `plans/` as a full plan before implementation, per `CLAUDE.md` section 4.

---

## 10. Summary

| Rank | Simulator | Score | Greatest strength | Disqualifying or limiting weakness | Verdict for the toolkit |
|---|---|---|---|---|---|
| 1 | Isaac Sim 6.0 with Isaac Lab | 86.0 | Rendering, sensors and 150k steps per second across 4,096 environments | ArduPilot only through an experimental community backend, RTX GPU with 12 GB required, Kit runtime closed | Adopt as the perception and learning platform |
| 2 | Gazebo Jetty with ardupilot_gazebo | 76.8 | True ArduPilot lockstep, swappable physics, support to 2030 | No photorealism, no parallel learning | Adopt as the flight-stack validation platform |
| 3 | Project AirSim | 68.0 | Push transport over NNG, fixed-step engine clock, ROS 2 C++ node, MIT and active | No ArduPilot, no description ingest, no vectorised environments | Evaluate, and consider contributing an ArduPilot API |
| 4 | Newton with mjlab and MuJoCo Playground | 65.4 | Open GPU physics under neutral governance, highest throughput multiples | No autopilot, weak sensors, thin ROS 2 | Adopt Newton as the physics backend wherever selectable |
| 5 | O3DE with ROS 2 Gem | 63.6 | Only open engine with in-process ROS 2 and a modern renderer | No autopilot, no learning path, smaller robotics community | Watch, and borrow its transport architecture |
| 6 | Genesis World 1.0 | 60.8 | Widest multiphysics, path-traced Nyx renderer | No ROS 2, throughput claims require verification | Watch |
| 7 | CARLA 0.10 | 58.2 | Native in-server ROS 2, Unreal 5.5 rendering | Driving only, no description ingest | Reference architecture only |
| 8 | CoppeliaSim | 56.6 | Five interchangeable physics engines | Proprietary core, dated rendering | Reference for physics abstraction |
| 9 | Webots R2025a | 55.0 | ArduPilot supported, Apache 2.0, easy | ODE only, weak rendering, slow cadence | Fallback |
| 10 | Cosys-AirSim | 54.4 | Photorealism with ArduPilot today, GPU lidar and echo sensors | Polling transport, quantised clock, inert lockstep, disclaimed support | Retain until replaced, do not extend |
| 11 | Unreal Robotics Lab | 53.2 | MuJoCo physics inside Unreal rendering, MJCF ingest | ROS 2 only through an external ZeroMQ bridge, no autopilot, young | Watch closely |
| 12 | ManiSkill3 with SAPIEN | 52.8 | Throughput with low memory footprint | Manipulation focus, negligible ROS 2 | Not applicable |
| 13 | rclUE with RapyutaSimulationPlugins | 52.0 | In-process ROS 2 inside Unreal, distributed simulation | No autopilot, thin sensors, slow cadence | Borrow the pattern |
| 14 | HoloOcean 2.x | 50.4 | Best marine acoustics, Fossen dynamics, hardware in the loop demonstrated | Marine only | Adopt if and when marine work begins |
| n/a | Colosseum | Not scored | n/a | Archived 2026-07-11 | Exclude |
| n/a | microsoft/AirSim | Not scored | n/a | Dormant since July 2022 | Exclude |
| n/a | AirGen and GRID, Duality Falcon, Spleenlab | Not deep-dived | Cloud scale and polished tooling | Closed core, unmodifiable simulation loop, no ArduPilot | Exclude on the modifiability requirement |

---

## 11. References

Surveys and landscape

- [best-of-robot-simulators](https://github.com/knmcguire/best-of-robot-simulators), curated list of 114 simulation projects
- [A Survey of Robotic Navigation and Manipulation with Physics Simulators in the Era of Embodied AI](https://arxiv.org/html/2505.01458v2)
- [Robot Simulation Software, A 2026 Perspective](https://www.blackcoffeerobotics.com/blog/which-robot-simulation-software-to-use)
- [Aerial Robotics Landscape, simulation comparison](https://ros-aerial.github.io/aerial_robotic_landscape/simulation/)
- [UE5 is becoming the platform of choice for robotics simulation](https://www.unrealengine.com/spotlights/ue5-is-becoming-the-platform-of-choice-for-robotics-simulation)

The AirSim lineage

- [Cosys-AirSim repository](https://github.com/Cosys-Lab/Cosys-AirSim) and [releases](https://github.com/Cosys-Lab/Cosys-AirSim/releases)
- [Cosys-AirSim documentation](https://cosys-lab.github.io/Cosys-AirSim/)
- [Project AirSim repository](https://github.com/iamaisim/ProjectAirSim) and [Architecture.md](https://github.com/iamaisim/ProjectAirSim/blob/main/Architecture.md)
- [Project AirSim documentation](https://iamaisim.github.io/ProjectAirSim/)
- [Colosseum repository, archived](https://github.com/CodexLabsLLC/Colosseum)
- [microsoft/AirSim](https://github.com/Microsoft/AirSim)
- [AirGen, the evolution of AirSim](https://www.generalrobotics.company/post/airgen)
- [TartanGround dataset](https://arxiv.org/html/2505.10696v2) and [TartanAir](https://learn.microsoft.com/en-us/azure/open-datasets/dataset-tartanair-simulation)

Unreal Engine robotics frameworks

- [Unreal Robotics Lab paper](https://arxiv.org/abs/2504.14135) and [repository](https://github.com/URLab-Sim/UnrealRoboticsLab)
- [rclUE repository](https://github.com/rapyuta-robotics/rclUE) and [design document](https://github.com/rapyuta-robotics/rclUE/blob/devel/docs/source/design.rst)
- [RapyutaSimulationPlugins documentation](https://rapyutasimulationplugins.readthedocs.io/en/devel/)
- [CARLA 0.10.0 release with Unreal Engine 5.5](https://carla.org/2024/12/19/release-0.10.0/) and [CARLA 0.9.16 with native ROS 2](https://carla.org/2025/09/16/release-0.9.16/)
- [CARLA native ROS 2 documentation](https://carla-ue5.readthedocs.io/en/latest/ros2_native/)
- [Unreal Engine Procedural Content Generation framework](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-in-unreal-engine)
- [Epic pricing for non-game use](https://www.unrealengine.com/blog/we-are-updating-unreal-engine-twinmotion-and-realitycapture-pricing-in-late-april)

NVIDIA stack

- [Isaac Sim repository](https://github.com/isaac-sim/IsaacSim) and [Isaac Sim 6.0 general availability](https://github.com/isaac-sim/IsaacSim/discussions/655)
- [Isaac Sim licence FAQ](https://docs.isaacsim.omniverse.nvidia.com/6.0.0/common/license-faq.html) and [requirements](https://docs.isaacsim.omniverse.nvidia.com/6.0.0/installation/requirements.html)
- [Isaac Sim 5.0 and Isaac Lab 2.2 general availability](https://developer.nvidia.com/blog/announcing-general-availability-for-nvidia-isaac-sim-5-0-and-nvidia-isaac-lab-2-2)
- [NVIDIA Isaac Sim, Enabling Scalable GPU-Accelerated Simulation for Robotics](https://arxiv.org/html/2606.03551v1)
- [Isaac Lab, A GPU-Accelerated Simulation Framework for Multi-Modal Robot Learning](https://arxiv.org/abs/2511.04831)
- [Isaac Lab development update, Newton migration](https://github.com/isaac-sim/IsaacLab/discussions/4339)
- [R²D², Scaling Multimodal Robot Learning with NVIDIA Isaac Lab](https://developer.nvidia.com/blog/r2d2-scaling-multimodal-robot-learning-with-nvidia-isaac-lab/)
- [Newton repository](https://github.com/newton-physics/newton), [CHANGELOG.md](https://github.com/newton-physics/newton/blob/main/CHANGELOG.md) for authoritative version dates, and [Linux Foundation announcement](https://www.linuxjournal.com/content/linux-foundation-welcomes-newton-next-open-physics-engine-robotics)
- [Announcing Newton, an Open-Source Physics Engine for Robotics Simulation](https://developer.nvidia.com/blog/announcing-newton-an-open-source-physics-engine-for-robotics-simulation/)
- [Newton Adds Contact-Rich Manipulation and Locomotion Capabilities for Industrial Robotics](https://developer.nvidia.com/blog/newton-adds-contact-rich-manipulation-and-locomotion-capabilities-for-industrial-robotics/), the 1.0 general availability post
- [Newton Physics Engine product page](https://developer.nvidia.com/newton-physics)
- [Into the Omniverse, Open-Source Physics Engine and OpenUSD Advance Robot Learning](https://blogs.nvidia.com/blog/newton-physics-engine-openusd/)
- [Pegasus Simulator](https://github.com/PegasusSimulator/PegasusSimulator), [PX4 integration](https://pegasussimulator.github.io/PegasusSimulator/source/features/px4_integration.html) and [ArduPilot, experimental](https://pegasussimulator.github.io/PegasusSimulator/source/features/ardupilot.html)

MuJoCo, Genesis and learning simulators

- [MuJoCo](https://github.com/google-deepmind/mujoco), [MuJoCo Warp](https://github.com/google-deepmind/mujoco_warp), [MuJoCo Playground](https://github.com/google-deepmind/mujoco_playground)
- [mjlab](https://github.com/mujocolab/mjlab)
- [madrona_mjx batch renderer](https://github.com/shacklettbp/madrona_mjx)
- [mujoco_ros2_control](https://control.ros.org/rolling/doc/mujoco_ros2_control/doc/index.html)
- [Genesis World](https://github.com/Genesis-Embodied-AI/Genesis) and [Genesis World 1.0 announcement](https://www.genesis.ai/blog/the-role-of-simulation-in-scalable-robotics-genesis-world-10-and-the-path-forward)
- [Analysis of the Genesis throughput claims](https://stoneztao.substack.com/p/the-new-hyped-genesis-simulator-is)
- [ManiSkill3](https://arxiv.org/abs/2410.00425) and [performance benchmarking](https://maniskill.readthedocs.io/en/latest/user_guide/additional_resources/performance_benchmarking.html)
- [Aerial Gym Simulator](https://github.com/ntnu-arl/aerial_gym_simulator)

Classical simulators and standards

- [Gazebo Jetty release notes](https://gazebosim.org/docs/latest/release_notes/) and [release announcement](https://discourse.openrobotics.org/t/gazebo-jetty-released/50349)
- [Gazebo physics engines](https://gazebosim.org/api/sim/9/physics.html)
- [ardupilot_gazebo](https://github.com/ArduPilot/ardupilot_gazebo)
- [ArduPilot simulation index](https://ardupilot.org/dev/docs/simulation-2.html) and [Simulation on Hardware](https://ardupilot.org/dev/docs/sim-on-hardware.html)
- [PX4 simulation guide](https://docs.px4.io/main/en/simulation/) and [community supported simulators](https://docs.px4.io/main/en/simulation/community_supported_simulators)
- [O3DE ROS 2 Gem](https://www.docs.o3de.org/docs/user-guide/gems/reference/robotics/ros2/) and [O3DE robotics](https://o3de.org/industries/robotics-and-simulations/)
- [O3DE 25.05.0 release](https://www.linuxfoundation.org/blog/open-3d-foundation-launches-o3de-25.05.0-release)
- [simulation_interfaces](https://github.com/ros-simulation/simulation_interfaces) and [the new standard for open-source robotics simulation](https://www.robotec.ai/blog/robotics/standardizing-simulation-interfaces-for-open-source-robotics)
- [Webots](https://github.com/cyberbotics/webots) and [webots_ros2](https://github.com/cyberbotics/webots_ros2)
- [CoppeliaSim architecture](https://www.coppeliarobotics.com/coppeliaSimArchitecture.pdf)
- [Project Chrono sensor module](https://api.projectchrono.org/sensor_overview.html)

Domain simulators

- [HoloOcean 2.0 preview](https://arxiv.org/pdf/2510.06160) and [documentation](https://byu-holoocean.github.io/holoocean-docs/)
- [Hardware in the loop testing with HoloOcean](https://arxiv.org/pdf/2511.07687)
- [UNav-Sim](https://github.com/open-airlab/UNav-Sim) and [paper](https://arxiv.org/pdf/2310.11927)
- [Stonefish, supporting machine learning research in marine robotics](https://arxiv.org/abs/2502.11887)
- [OceanSim](https://arxiv.org/pdf/2503.01074)

Procedural generation

- [Infinigen Indoors](https://arxiv.org/abs/2406.11824) and [repository](https://github.com/princeton-vl/infinigen)
