# Project AirSim software architecture

Audited 2026-08-02 against `https://github.com/iamaisim/ProjectAirSim` at commit `7fb9c566515901112c8d246fd02685bc58c369e5`, authored 2026-07-15, titled "Improve CI triggers and add ROS 2 C++ node validation (#171)". Licence MIT. All paths are relative to that repository root unless prefixed with `/ws`, in which case they refer to this workspace.

Companion files, [`project-airsim-docker-build.md`](project-airsim-docker-build.md) for the build chain and the container, [`airsim.md`](airsim.md) for the Cosys-AirSim architecture this replaces, [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md) for the clock requirements the NRT stack imposes, and [`../plans/project-airsim-integration.md`](../plans/project-airsim-integration.md) for the migration plan built on this reference.

## Executive summary

Project AirSim is a four-layer system. A portable C++ simulation core, `core_sim/`, owns the clock, the scene graph, the sensors and the NNG transport. An assembly layer, `simserver/`, binds the core to physics models and vehicle controllers. A renderer host, in practice the Unreal plugin at `unreal/Blocks/Plugins/ProjectAirSim/`, drives the clock and supplies rendering and ray casts. Clients in Python, C++ and ROS 2 connect over two TCP ports, 8989 for pub-sub topics and 8990 for request-response services, verified at `client/cpp/ProjectAirsimClientLib/Include/ProjectAirsimClient/Client.h:31-32` and `unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/UnrealSimLoader.cpp:174,190`.

ArduPilot support is real and complete enough to fly. The controller class is `ArduCopterApi` at `vehicle_apis/multirotor_api/include/arducopter_api.hpp:32`, registered under the config string `ardupilot-api` at `simserver/src/simserver.cpp:299-301`. Its wire protocol is field for field the protocol Cosys-AirSim speaks, namely a newline-terminated JSON sensor datagram sent to UDP 9003 and eleven `uint16` servo PWM values received on UDP 9002, defaults at `vehicle_apis/multirotor_api/include/arducopter_api.hpp:167-172`. The NRT ArduPilot SITL side, `--model airsim-copter` with `sim_port_in` 9003 and `sim_port_out` 9002, requires no change whatsoever, corroborated against `/ws/ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.h:64-72,139-152`.

The documentation actively denies the feature the code implements. `docs/controllers/controllers.md:5` states only Simple Flight, PX4 and Manual Controller are supported, `docs/config_robot.md:326` lists three controller types, and no ArduPilot page exists under `docs/`. The code, the schema at `client/python/projectairsim/src/projectairsim/schema/robot_config_schema.jsonc:71,539-550` and four working example configs contradict that. The code is authoritative. The only surviving prose description of the ArduPilot workflow is a GitHub issue comment, reproduced in A.13.

The ROS 2 C++ bridge publishes a genuine global `/clock` on `rosgraph_msgs/msg/Clock` at `ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:179-180,981-1005`, a material improvement over the Cosys-AirSim private `~/clock` recorded in [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md). However the bridge discards every payload timestamp and restamps with the ROS node clock at `:108-114`, reintroducing the quantisation defect elsewhere.

There is no ArduRover. Twelve defects and doc-versus-code disagreements are registered in section G.

---

## A. ArduPilot integration

### A.1 Where it lives and how it is selected

| Concern | Location |
|---|---|
| Class declaration | `vehicle_apis/multirotor_api/include/arducopter_api.hpp:32` |
| Implementation | `vehicle_apis/multirotor_api/src/arducopter_api.cpp`, 862 lines |
| Controller registration | `simserver/src/simserver.cpp:299-301` |
| Config discriminator | `core_sim/src/constant.hpp:443`, value `"ardupilot-api"` |
| Schema controller enum | `client/python/projectairsim/src/projectairsim/schema/robot_config_schema.jsonc:71` |
| Schema settings block | `.../robot_config_schema.jsonc:539-550` |
| Schema conditional requirement | `.../robot_config_schema.jsonc:638-649` |
| Example robot configs | `client/python/example_user_scripts/ardupilot/sim_config/robot_ardu_quadrotor.jsonc`, `robot_ardu_hexarotor.jsonc` |
| Example scene configs | `.../ardupilot/sim_config/scene_ardu_quadrotor.jsonc`, `scene_ardu_hexarotor.jsonc`, plus `client/python/example_user_scripts/sim_config/scene_quadrotor_ardupilot.jsonc` |
| Example scripts | `client/python/example_user_scripts/ardupilot/ardupilot_quadrotor.py`, `ardupilot_hexarotor.py` |
| Parameter files | `.../ardupilot/project-airsim-quad.param`, `project-airsim-hexa.param` |

Selection happens once per scene load. `SimServer::LoadControllers` reads `Robot::GetControllerType()` and constructs `new ArduCopterApi(sim_robot, ptransformtree)` at `simserver/src/simserver.cpp:299-301`. An unrecognised controller type only warns at `:314-316`, so a typo yields a silently uncontrolled robot.

A dead constant exists. `core_sim/src/constant.hpp:444` declares `ardupilot_api_settings = "ardupilot-api-settings"`, but the loader reads `"ardupilot-settings"` at `vehicle_apis/multirotor_api/src/arducopter_api.cpp:43`, which is what every config and the schema use.

### A.2 Class hierarchy

```
IRuntimeComponent                    core_sim/include/core_sim/runtime_components.hpp:16
        ↑
IController                          core_sim/include/core_sim/runtime_components.hpp:29
        ↑            IMultirotorApi  vehicle_apis/multirotor_api/include/imultirotor_api.hpp:26
        └──────┬───────────┘
        MultirotorApiBase            vehicle_apis/multirotor_api/include/multirotor_api_base.hpp:27
             ↑          IVTOLFWApi   vehicle_apis/multirotor_api/include/ivtolfw_api.hpp:17
             └──────┬───────┘
            VTOLFWApiBase            vehicle_apis/multirotor_api/include/vtolfw_api_base.hpp:21
                  ↑
            ArduCopterApi            vehicle_apis/multirotor_api/include/arducopter_api.hpp:32
```

`IController` mandates `SetKinematics`, `Update`, `GetControlSignals` and `GetGimbalSignal` at `core_sim/include/core_sim/runtime_components.hpp:49-57`. `ArduCopterApi` does not override `GetGimbalSignal`.

### A.3 Member variables

Private types at `arducopter_api.hpp:151-174`.

| Member | Type | Line | Purpose and default |
|---|---|---|---|
| `k_ardu_copter_rotor_control_count_` | `static const int` | `:152` | 11, the PWM channel count |
| `RotorControlMessage` | struct | `:153-155` | `uint16_t pwm[11]`, 22 bytes, the inbound wire format |
| `ArduPilotConnectionInfo::ardupilot_ip` | `std::string` | `:167` | `"127.0.0.1"`, destination for outbound sensors |
| `ArduPilotConnectionInfo::ardupilot_udp_port` | `int` | `:168` | `9003`, destination port |
| `ArduPilotConnectionInfo::local_host_ip` | `std::string` | `:171` | `"127.0.0.1"`, local bind address |
| `ArduPilotConnectionInfo::local_host_udp_port` | `int` | `:172` | `9002`, local bind port |
| `udp_socket_` | `unique_ptr<mavlinkcom::UdpSocket>` | `:174` | One socket, both directions |

Private data at `arducopter_api.hpp:205-248`.

| Member | Type | Line | Purpose |
|---|---|---|---|
| `port_` | `uint16_t` | `:206` | Cached `ardupilot_udp_port`, the `sendto` destination |
| `ip_` | `std::string` | `:207` | Cached `ardupilot_ip` |
| `actuator_id_to_output_idx_map_` | `unordered_map<string,int>` | `:208` | Actuator name to PWM channel index |
| `k_control_outputs_count_` | `static constexpr int` | `:210` | 16, larger than the 11 actually filled |
| `airspeed_sensor_` | `AirspeedSensor*` | `:213` | Declared, never assigned. Dead. |
| `imu_sensor_` | `Imu*` | `:214` | Mandatory |
| `magnetometer_sensor_` | `Magnetometer*` | `:215` | Declared, never assigned. Dead. |
| `barometer_sensor_` | `Barometer*` | `:216` | Declared, never assigned. Dead. |
| `distance_sensor_` | `DistanceSensor*` | `:217` | Optional |
| `gps_sensor_` | `Gps*` | `:218` | Optional |
| `connection_info_` | `ArduPilotConnectionInfo` | `:219` | Populated by `LoadSettings` |
| `control_outputs_` | `float[16]` | `:221` | Normalised PWM, only 0 to 10 written |
| `is_simulation_mode_` | `bool` | `:222` | Set true unconditionally in `BeginUpdate` |
| `use_distance_sensor_` | `bool` | `:224` | Default false. See defect G2. |
| `status_messages_` | `std::queue<std::string>` | `:228` | Never pushed to. Dead. |
| `is_ready_` | `bool` | `:229` | Backs `GetReadyState` and `CanArm` |
| `has_gps_lock_` | `bool` | `:230` | Never assigned. Dead. |
| `is_ready_message_` | `std::string` | `:236` | Failure text |
| `connect_thread_` | `std::thread` | `:237` | Runs `ConnectThread` |
| `connecting_`, `connected_` | `bool` | `:238,240` | Connection state |
| `last_gps_time_` | `uint64_t` | `:245` | Monotonic gate for the GPS block |
| `sim_time_us_` | `TimeMicro` | `:248` | Sim time in microseconds |

Every member commented out traces to the abandoned lockstep design, at `:160-235`, namely `lock_step`, `lock_step_active_`, `lock_step_enabled_`, `received_actuator_controls_`, `mutex_received_actuator_controls_`, `cv_received_actuator_controls_`, `last_update_time_`, `last_hil_sensor_time_` and `use_lidar_`.

### A.4 Methods

Implemented.

| Method | Line | Behaviour |
|---|---|---|
| ctor | `.cpp:24-27` | Calls `LoadSettings(robot)` |
| dtor | `.cpp:29-35` | Closes connections, joins thread |
| `LoadSettings` | `.cpp:37-82` | Parses `ardupilot-settings` |
| `GetSensors` | `.cpp:84-119` | Binds first enabled IMU, GPS, distance sensor. Throws when no IMU. |
| `BeginUpdate` | `.cpp:124-133` | Sim mode, `Reset`, `GetSensors`, `InitializeConnections` |
| `EndUpdate` | `.cpp:135-142` | Close, join |
| `Reset` | `.cpp:144-149` | Base reset plus `ResetState` |
| `SetKinematics` | `.cpp:151` | Deliberate no-op |
| `Update` | `.cpp:153-198` | Per-tick body, see A.5 |
| `ReciveRotorsControls` | `.cpp:200-222` | Blocking receive, see A.8 |
| `GetControlSignals` | `.cpp:224-241` | One-element vector of normalised PWM. Unknown actuator yields `{0.0f}` plus a warning. |
| `GetMultirotorApiParams` | `.cpp:447-451` | Static default block |
| `BeforeTask`, `AfterTask` | `.cpp:464-465` | No-ops |
| `GetCommandPeriod` | `.cpp:502-504` | `1.0f/50`, 50 Hz |
| `InitializeConnections` | `.cpp:519-532` | Wraps `OpenAllConnections`, records failure text |
| `OpenAllConnections` | `.cpp:534-539` | `Disconnect`, `ResetState`, `Connect` |
| `CloseAllConnections` | `.cpp:541` | `Disconnect` |
| `Connect` | `.cpp:543-552` | Spawns `ConnectThread` |
| `Disconnect` | `.cpp:554-560` | Clears `connected_`, closes socket |
| `ConnectThread` | `.cpp:562-568` | `CreateUdpConnection`, then `connected_ = true` |
| `ResetState` | `.cpp:570-584` | Zeroes time, gps gate, outputs, cancels last task |
| `AddStatusMessage` | `.cpp:609-613` | Logs at trace level only |
| `CreateUdpConnection` | `.cpp:615-651` | Validates and binds, see A.5 |
| `AdvanceSimTime` | `.cpp:654-656` | `sim_time_us_ = SimClock::Get()->NowSimMicros()` |
| `GetSimTimeMicros` | `.cpp:658-667` | Never called |
| `SendSensorData` | `.cpp:691-839` | Builds and sends the JSON datagram, see A.7 |
| `GetReadyState` | `.cpp:841-848` | Reports `is_ready_` and message |
| `CanArm` | `.cpp:850` | Returns `is_ready_` |
| `NormalizeRotorControls` | `.cpp:852-859` | `(pwm - 1000) / 1000` on all eleven channels |

Stubbed. Each logs "Not Implemented" and returns a default.

| Group | Methods and lines |
|---|---|
| API control | `EnableApiControl` `:246`, `DisableApiControl` `:251`, `IsApiControlEnabled` `:256` |
| Arming and flight | `Arm` `:261`, `Disarm` `:266`, `Takeoff` `:286`, `Land` `:292`, `GoHome` `:297`, `Hover` `:303`, `RequestControl` `:308`, `SetMissionMode` `:313`, `SetVTOLMode` `:318` |
| Motion commands | `MoveToPosition` `:271`, `CommandMotorPWMs` `:326`, `CommandRollPitchYawZ` `:336`, `CommandRollPitchYawThrottle` `:345`, `CommandRollPitchYawrateThrottle` `:354`, `CommandRollPitchYawrateZ` `:364`, `CommandAngleRatesZ` `:373`, `CommandAngleRatesThrottle` `:382`, `CommandHeading` `:391`, `CommandVelocity` `:398`, `CommandVelocityZ` `:407`, `CommandVelocityBody` `:417`, `CommandVelocityZBody` `:428`, `CommandPosition` `:438` |
| State getters | `GetKinematicsEstimated` `:467`, `GetPosition` `:473`, `GetVelocity` `:479`, `GetOrientation` `:485`, `GetLandedState` `:491`, `GetGpsLocationEstimated` `:496`, `GetTakeoffZ` `:506`, `GetDistanceAccuracy` `:511` |
| Tuning | `SetControllerGains` `:453` |

The consequence matches the rule already recorded in [`airsim.md`](airsim.md) §4. Vehicle state must come from ArduPilot over MAVLink or DDS, never from the Project AirSim client API, while images and raw sensor topics remain fully available because `core_sim` owns them.

### A.5 UDP data path, socket binding, port direction

One socket serves both directions. `CreateUdpConnection` at `.cpp:615-651` caches `port_ = ardupilot_udp_port` and `ip_ = ardupilot_ip` at `:628-629`, rejects an empty ip or zero port at `:624,631,635`, then binds with `udp_socket_->bind(local_host_ip, local_host_udp_port)` at `:648-649`. Transmission is `udp_socket_->sendto(sensor_data.c_str(), len, ip_, port_)` at `:838`.

| Direction | Endpoint used | Config key | Default | Evidence |
|---|---|---|---|---|
| Sensors, sim to autopilot | `sendto(ip_, port_)` | `ardupilot-ip`, `ardupilot-udp-port` | `127.0.0.1`, 9003 | `.cpp:628-629,838` |
| Servos, autopilot to sim | `bind(local_host_ip, local_host_udp_port)` then `recv` | `local-host-ip`, `local-host-udp-port` | `127.0.0.1`, 9002 | `.cpp:648-649,203` |

`Update` at `.cpp:153-198` runs `MultirotorApiBase::Update()` at `:155`, returns early if the IMU is absent, the socket null or `connected_` false at `:157-161`, then `AdvanceSimTime()` `:179`, `SendSensorData()` `:182`, `ReciveRotorsControls()` `:184`. Any exception triggers `Disconnect()` then `Connect()` at `:189-196`, so a restarted ArduPilot is picked up automatically.

`Update` is called once per scene tick from `Robot::Impl::UpdateControlInput` at `core_sim/src/actor/robot.cpp:1045-1053`, invoked in phase 4 of the tick at `core_sim/src/scene.cpp:997`. That call deliberately does not hold the robot's `update_lock_`, with a comment naming external controllers with blocking wait loops as the reason, at `core_sim/src/actor/robot.cpp:1046-1049`.

### A.6 Configuration surface

Schema at `.../robot_config_schema.jsonc:539-550`. Only these keys are declared. The schema states no defaults, so the C++ defaults govern.

| Key | Schema type | C++ default | Read at |
|---|---|---|---|
| `local-host-ip` | string | `"127.0.0.1"` | `.cpp:67-68` |
| `ardupilot-ip` | string | `"127.0.0.1"` | `.cpp:61-62` |
| `ardupilot-udp-port` | integer | `9003` | `.cpp:64-65` |
| `local-host-udp-port` | integer | `9002` | `.cpp:70-71` |
| `use-distance-sensor` | boolean | `false` | see G2 |
| `actuator-order` | array of `{ id, initial-value? }` | empty | `.cpp:46-58`, item schema `:505-515` |
| `use-lidar` | commented out at `:546` | not read | `.cpp:73` commented out |

`actuator-order` assigns PWM channel index positionally from zero at `.cpp:50-55`, with lookup by name at output time at `.cpp:230-237`. The schema makes `ardupilot-settings` mandatory when `type` is `ardupilot-api`, via an `anyOf` negation at `:638-649`. The controller-level `airframe-setup` key accepts `quadrotor-x`, `hexarotor-x`, `vtol-quad-x-tailsitter`, `vtol-quad-tiltrotor`, `ackermann` at `:63-66`, and `ArduCopterApi` ignores it entirely.

### A.7 The sensor packet sent to ArduPilot

`SendSensorData` at `.cpp:691-839` writes one JSON line terminated with `"}\n"` at `:831`, the newline being required by ArduPilot's parser.

| JSON path | Type | Source | Units | Line |
|---|---|---|---|---|
| `timestamp` | integer | `sim_time_us_` from `SimClock::Get()->NowSimMicros()` | microseconds of sim time | `.cpp:703`, set at `:655` |
| `imu.angular_velocity` | 3 floats, 7 decimals | `ImuMessage::GetAngularVelocity()` | rad/s, body frame, noise applied | `.cpp:708-711` |
| `imu.linear_acceleration` | 3 floats, 7 decimals | `ImuMessage::GetLinearAcceleration()` | m/s squared, body frame, gravity removed, noise applied | `.cpp:712-714` |
| `pose.roll` | float | `TransformUtils::ToRPY(imu_output.GetOrientation())[0]` | radians, ground truth, no noise | `.cpp:717-721` |
| `pose.pitch` | float | index 1 | radians | `.cpp:722` |
| `pose.yaw` | float | index 2 | radians | `.cpp:723` |
| `gps.lat` | 7 decimals | `GpsMessage` latitude | degrees | `.cpp:751-752` |
| `gps.lon` | 7 decimals | `GpsMessage` longitude | degrees | `.cpp:753` |
| `gps.alt` | 3 decimals | `GpsMessage` altitude | metres, positive up | `.cpp:753-754` |
| `velocity.world_linear_velocity` | 3 floats | `GpsMessage` velocity, that is `kinematics->twist.linear` | m/s, world NED | `.cpp:756-760`, source `core_sim/src/sensors/gps.cpp:224` |
| `rng.distances` | floats, 3 decimals | `DistanceSensor::getOutput().GetCurrentDistance()` | metres | `.cpp:784-807` |

`gps` and `velocity` are emitted only when a GPS exists and `time_utc_millis` has advanced, gated at `:725-730`. `rng` is emitted whenever a distance sensor exists, but the value inside is written only when `use_distance_sensor_` is also true at `:798-803`, so the key mismatch in G2 produces `"rng": {"distances": []}`. RC channel injection is commented out at `:765-782`, lidar at `:809-828`.

The mapping onto ArduPilot's parser is exact. `/ws/ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.h:139-152` declares a thirteen-entry key table containing `timestamp`, `imu.angular_velocity`, `imu.linear_acceleration`, `gps.lat`, `gps.lon`, `gps.alt`, `pose.roll`, `pose.pitch`, `pose.yaw`, `velocity.world_linear_velocity`, `lidar.point_cloud`, `rc.channels`, `rng.distances`. Every field Project AirSim emits is consumed, and the three ArduPilot would additionally accept are the three left disabled.

### A.8 The servo packet received

`ReciveRotorsControls` at `.cpp:200-222` reads into `RotorControlMessage`, `uint16_t pwm[11]`, 22 bytes, declared at `arducopter_api.hpp:152-155`. It calls `udp_socket_->recv(&pkt, sizeof(pkt), 100)` at `:203` and loops at `:204-215` until the return equals `sizeof(pkt)`. On timeout the implementation returns `-1` after a 100 ms poll at `mavlinkcom/src/impl/UdpSocketImpl.cpp:115-118`, triggering an error log and immediate retry. The loop has no exit other than success.

Values are copied at `:217-219`, then `NormalizeRotorControls` maps them with `(v - 1000.0f) / 1000.0f` at `:852-859`, mapping 1000 to 2000 microseconds onto 0.0 to 1.0. A comment at `:857-858` records the intent that non-rotor surfaces should not be normalised, but the loop normalises all eleven regardless.

The producer matches. `/ws/ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.h:61-66` declares `kArduCopterRotorControlCount = 11` and `struct servo_packet { uint16_t pwm[11]; }`, sent by `output_copter` to `airsim_control_port` at `/ws/ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.cpp:79-97`.

### A.9 Blocking and handshake semantics, the de-facto lockstep

There is no negotiated lockstep. Every lockstep member is commented out at `arducopter_api.hpp:170,197,231-235` and `.cpp:164-177,668-689`. The `timeout-lock-step-update-ms` key exists in the schema only for PX4 at `.../robot_config_schema.jsonc:528`, and its ArduPilot reader is commented out at `.cpp:77-81`.

What exists instead is an unconditional blocking receive on the scene tick thread. `ReciveRotorsControls` cannot return without a complete packet, and it runs inside `Robot::UpdateControlInput` inside `Scene::Impl::SceneTick` at `core_sim/src/scene.cpp:997`, so the scene tick cannot complete and the sim clock cannot advance until ArduPilot replies. That is a de-facto lockstep with the same character as the one documented in [`airsim.md`](airsim.md) §3.

The reverse coupling comes from ArduPilot. `recv_fdm` advances `time_now_us` by the difference between successive `state.timestamp` values, and resends servos if no sensor packet arrives within one second, at `/ws/ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.cpp`. The autopilot's simulated clock is therefore slaved to the `timestamp` field Project AirSim emits, closing the loop.

Two failure modes follow. If ArduPilot is not running, the scene tick thread blocks indefinitely and the whole simulation freezes while the log fills at roughly 10 Hz. That is the most plausible explanation of the crash reported in issue 21 on 2025-09-16. Second, because the loop discards any packet whose length is not exactly 22 bytes, a rover configuration can never proceed.

### A.10 Comparison with Cosys-AirSim

| Aspect | Cosys-AirSim | Project AirSim | Same? |
|---|---|---|---|
| Send target port key | `UdpPort`, default 9003 | `ardupilot-udp-port`, default 9003 | Yes |
| Receive bind port key | `ControlPort` or `ControlPortLocal`, default 9002 | `local-host-udp-port`, default 9002 | Yes |
| Send target ip key | `UdpIp` | `ardupilot-ip` | Yes, renamed |
| Bind ip key | `LocalHostIp` | `local-host-ip` | Yes, renamed |
| Socket count | one, bound locally, `sendto` remote | identical | Yes |
| Outbound format | newline-terminated JSON line | identical | Yes |
| Fields sent | `timestamp`, `imu`, `pose`, `gps`, `velocity`, `rc`, `rng`, `lidar` | same minus `rc` and `lidar`, both present but commented out | Subset |
| Timestamp units | microseconds from the sim clock | identical | Yes |
| Inbound format | 11 by `uint16` PWM | identical | Yes |
| PWM normalisation | `(pwm-1000)/1000` | identical | Yes |
| Blocking receive loop | yes, unconditional | yes, unconditional | Yes |
| `LockStep` honoured | no on this path | no such key on this path | Yes in effect |
| Client state API | stubbed | stubbed | Yes |
| GPS lat storage | `double` throughout | `float` inside `GpsMessage` | No, see G3 |
| Actuator to channel mapping | fixed by firmware convention | explicit `actuator-order` array | No, Project AirSim more flexible |
| Distance sensor | present | present but disabled by a key typo | No, see G2 |

The NRT ArduPilot SITL side needs no modification. `--model airsim-copter` selects the copter output type at `/ws/ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.cpp:43-50`, and the defaults `sim_port_in` 9003 and `sim_port_out` 9002 align with `SIM_AirSim.h:68-72` and with Project AirSim's own defaults. The shipped parameter files independently state `python sim_vehicle.py -v ArduCopter -f airsim-copter --add-param-file=<path>` at `project-airsim-quad.param:2` and `project-airsim-hexa.param:2`.

### A.11 Worked examples

`scene_ardu_quadrotor.jsonc`.

| Key | Value | Line |
|---|---|---|
| `id` | `SceneBasicDrone` | `:2` |
| actor `name` | `Drone1` | `:6` |
| actor `origin.xyz` | `0.0 0.0 -4.0` m NED | `:8` |
| `robot-config` | `robot_ardu_quadrotor.jsonc` | `:11` |
| `clock.type` | `steppable` | `:15` |
| `clock.step-ns` | 3000000, 3 ms | `:16` |
| `clock.real-time-update-rate` | 3000000 | `:17` |
| `clock.pause-on-start` | false | `:18` |
| `home-geo-point` | 47.641468, -122.140165, 122.0 | `:20-24` |
| `scene-type` | `UnrealNative` | `:30` |

`scene_ardu_hexarotor.jsonc` is identical bar the robot filename. `client/python/example_user_scripts/sim_config/scene_quadrotor_ardupilot.jsonc` is a third variant with `home-geo-point` -35.363261, 149.165230, 3, ArduPilot's own Canberra default, but it references `robot_quadrotor_ardupilot.jsonc` which does not exist in the tree, so it is unusable as shipped.

`robot_ardu_quadrotor.jsonc`.

| Aspect | Value | Line |
|---|---|---|
| `physics-type` | `fast-physics` | `:2` |
| Links | `Frame`, `Prop_FL`, `Prop_FR`, `Prop_RL`, `Prop_RR` | `:3-169` |
| Frame | 1.0 kg, box 0.180 by 0.110 by 0.040 m | `:7-15` |
| Props | 0.055 kg each, point mass, arm 0.253 m | `:39-47` |
| Drag coefficient | 0.325 | `:17,49` |
| Joints | four fixed, axis `0 0 1` | `:170-199` |
| Controller | `ArduPilot_Controller`, `ardupilot-api` | `:201-202` |
| `actuator-order` | `Prop_FR`, `Prop_RL`, `Prop_FL`, `Prop_RR` actuators | `:209-222` |
| Rotor coefficients | thrust 0.109919, torque 0.040164, 6396.667 rpm, diameter 0.2286 m, smoothing 0.005 s | `:236-244` |
| Turning | FL and RR clockwise, FR and RL counter-clockwise | `:237,257,277,297` |
| `Chase` camera | 1280 by 720, 90 degrees, streaming only, origin `-10.0 0.0 -1.0`, `0 -11.46 0` | `:309-336` |
| `DownCamera` | 400 by 225, 90 degrees, image types 0 and 2 captured, origin `0 0.0 0.0`, `0 -90 0` | `:338-409` |
| `IMU1` | see D.6 | `:411-427` |
| GPS, Barometer, Magnetometer | enabled, all defaults | `:429-445` |

The actuator order is load-bearing. ArduCopter's Iris quad-X numbering is motor 1 front-right, 2 rear-left, 3 front-left, 4 rear-right, which the array reproduces exactly, hence channel 0 is `Prop_FR_actuator`. `robot_ardu_hexarotor.jsonc` sets `airframe-setup` `"hexarotor-x"` at `:282` and orders six actuators `Prop_2`, `Prop_5`, `Prop_0`, `Prop_3`, `Prop_1`, `Prop_4` at `:291-309`.

`ardupilot_quadrotor.py` connects a `ProjectAirSimClient`, loads the scene via `World(client, "scene_ardu_quadrotor.jsonc", delay_after_load_sec=2)` at `:34`, creates `Drone(client, world, "Drone1")` at `:37`, subscribes to `Chase/scene_camera` at `:43-46` and `DownCamera` scene and depth at `:51-61`, then blocks on `input()` at `:68`. Its comment at `:66-67` states control APIs are not supported and ArduPilot is driven externally. The docstring at `:8-11` names the Iris airframe, `FRAME_CLASS 1`, `FRAME_TYPE 1`, and recommends Mission Planner.

`project-airsim-quad.param`.

| Parameter | Value | Meaning |
|---|---|---|
| `ATC_RAT_RLL_P` | 0.733 | Roll rate P gain |
| `ATC_RAT_RLL_I` | 0.733 | Roll rate I gain |
| `ATC_RAT_RLL_D` | 0.0056 | Roll rate D gain |
| `ATC_ANG_RLL_P` | 36.000 | Roll angle P gain |
| `ATC_ACCEL_R_MAX` | 374870 | Max roll angular acceleration, cdeg per second squared |
| `ATC_RAT_PIT_P` | 0.768 | Pitch rate P gain |
| `ATC_RAT_PIT_I` | 0.768 | Pitch rate I gain |
| `ATC_RAT_PIT_D` | 0.0050 | Pitch rate D gain |
| `ATC_ANG_PIT_P` | 36.00 | Pitch angle P gain |
| `ATC_ACCEL_P_MAX` | 348730 | Max pitch angular acceleration |
| `ATC_RAT_YAW_P` | 2.000 | Yaw rate P gain |
| `ATC_RAT_YAW_I` | 0.200 | Yaw rate I gain |
| `ATC_RAT_YAW_D` | 0.0000 | Yaw rate D gain |
| `ATC_ANG_YAW_P` | 3.429 | Yaw angle P gain |
| `ATC_ACCEL_Y_MAX` | 2893 | Max yaw angular acceleration |

`project-airsim-hexa.param` sets `FRAME_CLASS 2` at `:7`, selecting the hexarotor class, then `ATC_RAT_RLL_P 2.000`, `ATC_RAT_RLL_I 2.000`, `ATC_RAT_RLL_D 0.0548`, `ATC_ANG_RLL_P 36.00`, `ATC_ACCEL_R_MAX 83776`, `ATC_RAT_PIT_P 2.000`, `ATC_RAT_PIT_I 2.000`, `ATC_RAT_PIT_D 0.0498`, `ATC_ANG_PIT_P 36.00`, `ATC_ACCEL_P_MAX 94015`, `ATC_RAT_YAW_P 2.000`, `ATC_RAT_YAW_I 0.200`, `ATC_RAT_YAW_D 0.0000`, `ATC_ANG_YAW_P 1.672`, `ATC_ACCEL_Y_MAX 1000`, at `:10-40`. Neither file sets `FRAME_TYPE`, so the ArduCopter default of 1, meaning X, applies. Both reference a documentation page that does not exist, at `:3` in each.

### A.12 ArduRover and other ArduPilot vehicle types

There are none. `ArduCopterApi` is the only class speaking the ArduPilot JSON FDM protocol, and `simserver/src/simserver.cpp:292-317` registers exactly six controller types, namely `simple-flight-api`, `px4-api`, `ardupilot-api`, `manual-controller-api`, `matlab-controller-api`, `simple-drive-api`. The rover path is served by `simple_drive::SimpleDriveApi` at `:310-312`, implemented under `vehicle_apis/rover_api/`, with no ArduPilot linkage.

Selecting `ardupilot-api` for a wheeled robot would load, because `SimServer` does not check the airframe, then deadlock, because ArduPilot's rover backend sends an 8-byte `rover_packet` of two floats at `/ws/ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.h:56-59` while `ReciveRotorsControls` waits for 22 bytes.

Only three other matches for ArduPilot exist, all incidental MAVLink enumeration entries at `mavlinkcom/include/MavLinkMessages.hpp:246-247` and `mavlinkcom/test/main.cpp:485`.

### A.13 GitHub issue 21 and related discussion

A repository-wide issue search for ardupilot returns three issues. Only 21 concerns the integration. Issue 70, "Addition of ROV and USV simulation", and issue 91, "Add Support for NVIDIA Omniverse as a Rendering Backend", match incidentally.

Issue 21, "How to connect ProjectAirSim to ArduPilot SITL instead of PX4 for Mission Planner control". Opened by `Agitolyev` on 2025-07-14, still open as of 2026-08-02, labelled `documentation`, `question`, `ardupilot`, three comments. The author reports Windows 11, Project AirSim v0.1, Python 3.12, UE 5.2, ArduPilot 4.3.7.

Comment 1, `jonyMarino`, 2025-07-14. This is the only surviving ArduPilot documentation.

| Claim | Corroborated? | Evidence |
|---|---|---|
| Examples live under `client/python/example_user_scripts/ardupilot` | Yes | directory with four configs, two scripts, two param files |
| "There is a good time since I tested ardupilot for this project, I'm not sure if it is working on the latest version" | Not testable here, consistent with the absence of any ArduPilot test or CI job | no ardupilot matches under `.github/` |
| Multi-rotor SITL only, quadrotor and hexarotor examples | Yes | two robot configs, two scripts |
| Settings table naming `id`, `local-host-ip`, `ardupilot-ip`, `ardupilot-udp-port` default 9003, `local-host-udp-port` default 9002, `use-distance-sensor`, `actuator-order` | Yes for names and defaults | `arducopter_api.hpp:167-172`, `.cpp:61-76` |
| "one simulation message communications channel", sent via UDP as specified by `local-host-udp-port` | Partly wrong | one socket but two endpoints, and outbound goes to `ardupilot-udp-port`, per `.cpp:838` |
| "Currently, no communication channel exists allowing you to send control commands from AirSim to ArduPilot" | Yes | every command method is a stub, A.4 |
| Same computer, different computers, WSL1, WSL2 topologies | Plausible, consistent with configurable ips, untested here | `.cpp:61-71` |
| `python sim_vehicle.py -v ArduCopter -f airsim-copter --add-param-file=project-airsim-hexa.param`, plus `--sim-address=<IP>` when remote | Yes | identical text at `project-airsim-hexa.param:2` |
| Commands `arm throttle`, `mode guided`, `takeoff <alt>`, `guided <lat> <lon> <alt>`, `mode land` | Consistent with the stubbed client API and external MAVLink control | not verifiable from this tree |
| "If you receive the `AP: Arm: Main loop slow...` error, run `arm throttle` again or modify the clock (step-ns, etc.)" | Consistent with the blocking-tick design | `.cpp:200-222` |
| Autotune procedure and the `ATC_*` mapping table | Consistent with the shipped `.param` files | A.11 |
| Paths such as `ProjectAirSim_client\ProjectAirSim_Example_User_Scripts\ardupilot` | Stale | current path is `client/python/example_user_scripts/ardupilot` |

Comment 2, `Sekilsgs2`, 2025-09-16, states "ProjectAirSim crashes after running sitl" with a screenshot. Comment 3, `jonyMarino`, 2026-12-02, replies "try with WSL1". No resolution recorded. Section A.9 gives a mechanism that produces exactly this symptom.

### A.14 The single-precision geodetic defect, its magnitude and its consumers

This section derives the two quantisation figures that defect G3 carries. G3 previously gave a single figure of roughly half a metre, corrected on 2026-08-03, because the quantum is a function of the magnitude of the coordinate and is therefore different for latitude and for longitude, which one number cannot express.

The defect is a type. `GpsMessage::Impl` declares `float latitude` and `float longitude` at `core_sim/src/message/gps_message.cpp:42-43`, and the public constructor at `core_sim/include/core_sim/message/gps_message.hpp:25-27` takes them as `float` too, so the narrowing happens at construction and nothing downstream can recover it.

The cause is a message-layer convention applied one field too far. Every scalar in every Project AirSim sensor message is `float`, which is correct for the quantities those messages carry, and `core_sim/src/message/barometer_message.cpp:38-40` and `magnetometer_message.cpp:41` show the same choice for pressure, altitude and magnetic field. Geodetic angle is the one quantity in the set for which it is wrong, because its magnitude rather than its resolution consumes the exponent. The simulator's own model is not confused about this, since `GeoPoint` declares `double` at `core_sim/include/core_sim/earth_utils.hpp:22-23`, `GpsData` holds a `GeoPoint` at `core_sim/src/sensors/gps.cpp:65-77`, and `NedToGeodetic` at `earth_utils.hpp:100-125` computes in double throughout. The precision is created correctly and discarded at the message boundary. `git log` shows the type has been `float` since the initial Microsoft commit, so this is inherited rather than introduced by IAMAI.

A binary32 has a 24-bit significand, so the quantum at a value of magnitude near 2^n is 2^(n-24) degrees. At the workspace home location of latitude −35.363261 and longitude 149.165230 the latitude falls in [32, 64) and quantises at 2^-19, about 1.9e-06 degrees or 0.21 m, while the longitude falls in [128, 256) and quantises at 2^-17, about 7.6e-06 degrees or, at that latitude where a degree of longitude spans about 90.8 km, 0.69 m. The east error is over three times the north error purely because the longitude is numerically larger, and that asymmetry is the fingerprint by which the defect is recognised in a log. Nothing else in the chain contributes, since `SendSensorData` prints with `std::setprecision(7)` in fixed mode at `vehicle_apis/multirotor_api/src/arducopter_api.cpp:751-753`, a resolution of about 1 cm, and ArduPilot parses into double.

`GpsMessage` is constructed in exactly two places, both inside the sensor, namely the periodic publish at `core_sim/src/sensors/gps.cpp:231-235` and the service-method accessor at `:255-261`. It is consumed in six.

| Consumer | Site | Effect of the narrowing |
|---|---|---|
| The ArduPilot controller | `vehicle_apis/multirotor_api/src/arducopter_api.cpp:726-727`, reading `gps_sensor_->getOutput()` then `getData()` | the `gps.lat` and `gps.lon` fields of the JSON sensor packet carry the quantised value, which is the path that matters to the NRT stack |
| The MAVLink controller | `vehicle_apis/multirotor_api/src/mavlink_api.cpp:2027` | the same defect on the PX4 path, unused here |
| The MATLAB controller | `vehicle_apis/multirotor_api/src/matlab_controller_api.cpp:139` | as above, unused here |
| The NNG topic | `core_sim/src/sensors/gps.cpp:231-238`, published on `<sensor root>/gps` | every client, Python or C++, sees the quantised value |
| The ROS 2 bridge | `CreateGpsPublisher` at `ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:338-358`, into `sensor_msgs::msg::NavSatFix` | the ROS field is `double` but is filled from the narrowed JSON, so the type is wider and the content is not |
| The service method | `core_sim/src/sensors/gps.cpp:255-261`, reached from Python by `Drone.get_gps_data` at `client/python/projectairsim/src/projectairsim/drone.py:988-1003` | as above |

Every path out of the simulator is affected, so no configuration and no alternative accessor avoids it. The effect is nonetheless bounded, because 0.21 m north and 0.69 m east of position noise sits below the GPS error the stack already models and far below what would prevent arming, EKF convergence or waypoint flight. Cosys-AirSim carries `double` throughout, so this is a real regression and the one respect in which the ArduPilot sensor path is measurably worse than the simulator being replaced.

The fix is three lines, namely widening the two members at `gps_message.cpp:42-43` and the two constructor parameters at `gps_message.hpp:25-27` and `gps_message.cpp:54-56`. It is deliberately not applied locally, because it changes a serialised message layout that every Project AirSim client shares, so a local patch would silently make this workspace's simulator wire-incompatible with any upstream client. It belongs upstream.

### A.15 The ArduPilot parameter file layers, it does not replace

Added 2026-08-03. `client/python/example_user_scripts/ardupilot/project-airsim-quad.param` is copied into this workspace as `sitl_ws/config/airsim2/project-airsim-quad.parm`, with the extension changed to the `.parm` spelling the rest of the stack uses, and copied rather than referenced in place so that a `git submodule update` cannot rewrite it.

The file is an addition and not a replacement, which its own header states and which determines how it must be wired. Its second comment line reads `Use it running the following command: python sim_vehicle.py -v ArduCopter -f airsim-copter --add-param-file=<path_to_this_file>`, so upstream layers it on top of the `airsim-copter` frame defaults rather than instead of them. Those frame defaults are exactly what this workspace already loads, since `ardu_ws/src/ardupilot/Tools/autotest/pysim/vehicleinfo.json:199-205` defines `airsim-copter` as `copter.parm` followed by `airsim-quadX.parm`. The upstream instruction and the workspace configuration therefore agree, and the correct wiring is to append a fourth entry to the `defaults` list rather than to substitute the third.

The contents confirm it. The file is 38 lines and sets only attitude control, namely the six `ATC_RAT_{RLL,PIT}_{P,I,D}` rate gains, the three `ATC_ANG_{RLL,PIT,YAW}_P` angle gains, the three `ATC_ACCEL_{R,P,Y}_MAX` limits and the three `ATC_RAT_YAW_{P,I,D}` gains. It sets no frame, no scheduler rate, no sensor lag, no filter and no hover thrust. Everything the stack depends on and that a naive substitution would have silently dropped, namely `FRAME_TYPE 1`, `MOT_THST_HOVER 0.461`, `SCHED_LOOP_RATE 185`, `SIM_GPS1_LAG_MS 0`, `GPS1_DELAY_MS 200` and the six `INS_*_FILTER` and `ATC_RAT_*_FLT*` entries, lives in `airsim-quadX.parm` and survives untouched. What the new file changes is the rate loop tuning, raising `ATC_RAT_RLL_P` from 0.25 to 0.733 and `ATC_RAT_PIT_P` from 0.25 to 0.768, which is the tuning matching Project AirSim's rotor coefficients of `coeff-of-thrust` 0.109919 and `coeff-of-torque` 0.040164 at `sim_config/robot_ardu_quadrotor.jsonc:239-240`.

One independent confirmation is worth recording, since loading `airsim-quadX.parm` at all depends on it. `FRAME_TYPE 1` is ArduPilot's quad X, whose motor order is front-right, rear-left, front-left, rear-right, and the example's `actuator-order` at `robot_ardu_quadrotor.jsonc:209-221` is `Prop_FR_actuator`, `Prop_RL_actuator`, `Prop_FL_actuator`, `Prop_RR_actuator`, in that order. The two match element for element, so the eleven-channel PWM packet lands on the rotor the autopilot intends.

---

## B. Time, clock and stepping

### B.1 The clock model

Four clock types at `core_sim/include/core_sim/clock.hpp:186-191`, namely `kSteppable`, `kRealTime`, `kEngineDriven`, `kExternalClock`. Config strings at `core_sim/src/constant.hpp:85-88`, namely `steppable`, `real-time`, `engine-driven`, `external-clock`.

`ClockSettings` at `clock.hpp:193-198` holds `type` defaulting to `kSteppable`, `step` defaulting to `kDefaultStepNanos` which is `3'000'000` at `clock.hpp:37`, `scene_tick_period` with the same default, and `pause_on_start` defaulting false.

Parsed by `Scene::Loader::LoadClockSettings` at `core_sim/src/scene.cpp:1186-1237`.

| Config key | Constant | Struct field | Default when absent |
|---|---|---|---|
| `type` | `constant.hpp:84` | `type` | `steppable` |
| `step-ns` | `constant.hpp:132` | `step` | 3000000 |
| `real-time-update-rate` | `constant.hpp:134-135` | `scene_tick_period` | 3000000 |
| `pause-on-start` | `constant.hpp:133` | `pause_on_start` | 0 |

A missing `clock` object returns early at `scene.cpp:1191-1199`. An unrecognised `type` warns and falls back at `:1215-1222`.

Documentation and code disagree. `docs/config_scene.md:77` says `step-ns` defaults to 20000000, 20 ms, while `clock.hpp:37` sets 3 ms and `scene.cpp:1224-1225` passes that constant. The code is authoritative. Every shipped ArduPilot scene sets 3000000 explicitly.

Clock construction at `scene.cpp:1076-1091`. `kRealTime` yields `RealTimeClock`, `kSteppable` yields `SteppableClock(step)` with an immediate `SimPause(true)` when `pause-on-start` is set, and both `kEngineDriven` and `kExternalClock` yield `EngineDrivenClock(step)`. The two are behaviourally identical today, stated in code at `:1085-1087` and in prose at `docs/config_scene.md:148-150`.

| Clock class | `NowSimNanos()` | Steps advanced by | File |
|---|---|---|---|
| `RealTimeClock` | `steady_clock` since epoch | nothing, passthrough | `core_sim/src/clock.cpp:71-73` |
| `SteppableClock` | atomic `current_sim_time_` | `Step()` adds `next_step_nanos_`, resets to `base_step_nanos_` | `clock.cpp:145-158` |
| `EngineDrivenClock` | atomic `current_sim_time_` | `Step()` consumes one `fixed_step_nanos_` from `accumulated_nanos_` | `clock.cpp:199-210` |

`SteppableClock` alone implements pause and step control, `SimPause`, `IsPaused`, `ContinueForSimTime`, `ContinueUntilSimTime`, `ContinueForSingleStep`, `ContinueForNBaseSteps`, at `clock.cpp:106-142`. These are no-ops on the base at `clock.cpp:52-62`, and the scene throws for any other clock type at `scene.cpp:668-671,690-693,717-720,743-746,767-770`.

### B.2 Who drives the tick

For `kSteppable` and `kRealTime`, `core_sim` owns a `ScheduledExecutor` thread. `Scene::Impl::StartSceneTick` at `scene.cpp:578-600` initialises it with `SceneTick` and period `clock_settings_.scene_tick_period`. `ScheduledExecutor::ExecutorLoop` in `clock.cpp` maintains that period with a hybrid sleep and spin, sleeping all but the last millisecond.

For `kEngineDriven` and `kExternalClock` the executor is never started, at `scene.cpp:590-596`, and a host must call `Scene::ExternalTick()` at `core_sim/include/core_sim/scene.hpp:81`, forwarding to `SceneTick` at `scene.cpp:325`.

The only host implementing the engine-driven contract is Unreal. `AUnrealScene::Tick` at `unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/UnrealScene.cpp:429-508` branches three ways.

Branch one, engine-driven, at `:436-449`. When `using_unreal_driven_clock` and not paused, the frame delta is pushed with `unreal_driven_clock_->AccumulateStep(UnrealHelpers::DeltaTimeToNanos(DeltaTime))` at `:438-439`, then fixed steps are drained with `while (unreal_driven_clock_->HasPendingStep()) { sim_scene->ExternalTick(); }` at `:441-448`. That drain is where fixed steps are consumed, one `step-ns` per `EngineDrivenClock::Step()` at `clock.cpp:203-210`.

Branch two, Unreal physics, at `:451-495`. Unreal's delta leads, so the tick calls `SimClock::Get()->SetNextSimTime(cur_sim_time)` then busy-waits until the sim clock catches up at `:470-475`, pausing and unpausing the game. Four pause-state conditions are handled and the fourth logs a desynchronisation warning at `:486-494`.

Branch three, everything else including Fast Physics, at `:497-507`. The sim clock leads and Unreal is paused or unpaused to follow.

`AUnrealScene` is `bTickEvenWhenPaused = true`, explained at `UnrealScene.cpp:425-428`, so the pause handshake can run while paused.

### B.3 What a scene tick does

`Scene::Impl::SceneTick` at `scene.cpp:894-1052`, five ordered phases.

1. Step the clock. `SimClock::Get()->Step()` at `:906`, then `sim_dt_nanos` at `:907-909`. In distributed mode a non-clock-source instance adopts the received sim time at `:900-904`, and a clock source broadcasts at `:911-914`.
2. Step physics. `physics_step_callback_(sim_dt_nanos)` at `:944-951`. Environment actors are updated first at `:920-928`.
3. Environment and sensors. `robot.UpdateEnvironment()` then `robot.UpdateSensors(sim_time_, sim_dt_nanos)` at `:975-981`.
4. Control and actuators. `robot.UpdateControlInput()` then `robot.UpdateActuators(...)` at `:997-1003`. This is where `ArduCopterApi::Update` runs.
5. Set wrenches. `physics_set_wrenches_callback_()` at `:1009-1015`.

The whole body is skipped when `sim_dt_nanos` is not positive, at `:916`.

### B.4 Whether ArduPilot lockstep exists, and what gates the step

No negotiated lockstep, per A.9. What gates the physics step under ArduPilot is the blocking `recv` in phase 4. Because phase 4 is synchronous on the tick thread, the next `SimClock::Get()->Step()` cannot occur until ArduPilot answers. This is unconditional and holds for all four clock types. The reciprocal coupling is that ArduPilot slaves `time_now_us` to the deltas of `timestamp`, at `/ws/ardu_ws/src/ardupilot/libraries/SITL/SIM_AirSim.cpp` `recv_fdm`. The pair forms a closed synchronous loop with sim time as master.

### B.5 How sensor and image timestamps are produced

| Sensor | Stamp source | Line |
|---|---|---|
| IMU | `output_.time_stamp = sim_time` | `core_sim/src/sensors/imu.cpp:174-197` |
| GPS | `output_.time_stamp = sim_time` | `core_sim/src/sensors/gps.cpp:214-221` |
| All others | same pattern via `Update(const TimeNano sim_time, const TimeNano sim_dt_nanos)` | `core_sim/include/core_sim/sensors/sensor.hpp` |
| Camera | `SimClock::Get()->NowSimNanos()` captured in `UnrealRobot::Tick`, propagated by `SetSimTimeAtPoseUpdate` | `unreal/.../Private/Robot/UnrealRobot.cpp:650,670`, consumed at `unreal/.../Private/Sensors/UnrealCamera.cpp:770,782` |

The camera's `Update` is a deliberate no-op, commented that the camera updates on render ticks from the rendering engine, at `core_sim/src/sensors/camera.cpp:415-420`. Capture is gated in sim time, comparing `PoseUpdatedTimeStamp - CapturedTime` against `CaptureIntervalSec` at `UnrealCamera.cpp:731-734`, then pushing `CapturedTime` into `SimCamera.AddRequestToCaptureQueue` at `:777` so asynchronous render completions republish in capture order via `Camera::Impl::PublishImages` at `camera.cpp:1035-1091`.

Every payload carries its stamp in nanoseconds of sim time. `ImuMessage` at `core_sim/src/message/imu_message.cpp:39,135`, `GpsMessage` at `gps_message.cpp:35,109-110`, `ImageMessage` at `image_message.cpp:63,217`.

### B.6 The clock as seen by clients and by ROS 2

Two service methods, registered by `Scene::Impl::RegisterServiceMethods` at `scene.cpp:827-836`. `GetSimClockType` returns the clock type string, `GetSimTime` returns current sim nanoseconds. Fully qualified as `<scene topic path>/GetSimClockType` and `<scene topic path>/GetSimTime`, composed at `scene.cpp:815-821`. Wrapped in Python at `client/python/projectairsim/src/projectairsim/world.py:85-107` and C++ at `client/cpp/ProjectAirsimClientLib/src/World.cpp:220-224`.

Exactly one component publishes `rosgraph_msgs/msg/Clock` on the global `/clock`, the ROS 2 C++ bridge. Publisher created at `ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:179-180` with the literal `"/clock"` and `rclcpp::QoS(10)`, whose reliability defaults to RELIABLE. The timer at `:997-1005` is a wall timer with period `publish_clock_period_sec`, default 0.02 s, nominal 50 Hz. `PublishClock` at `:981-995` calls `RequestSimTime`, a blocking NNG request to `<parent topic>/GetSimTime` at `:748-787`, with a fallback to `World::GetSimTime`.

The Python ROS bridge publishes no clock at all.

### B.7 Assessment against the NRT time-synchronisation requirements

| Requirement | Project AirSim status | Verdict |
|---|---|---|
| Publisher on the global `/clock` | Present, literal `"/clock"` at `projectairsim_ros2_cpp_node.cpp:180` | Better than Cosys-AirSim, no patch needed to reach the ArduPilot DataReader |
| RELIABLE QoS so the ArduPilot reader matches | `rclcpp::QoS(10)`, RELIABLE by default | Satisfied |
| Rate high enough to bound `/ap/*` stamp quantisation | Default 50 Hz, configurable through `publish_clock_period_sec` | Materially better than the measured 14.05 Hz and tunable. Each publication costs one blocking NNG round trip, so the achievable rate must be measured. |
| Clock value is sim time | Yes, from `GetSimTime` which returns `SimClock::Get()->NowSimNanos()` | Satisfied |
| Sensor header stamps carry sim time | No. `MakeHeader` uses `node.get_clock()->now()` at `:108-114`, and the payload `time_stamp` is never read | Not satisfied, see G12 |
| `use_sim_time` on downstream nodes | Standard mechanism, unaffected | Satisfied |

The one genuine gap is the header stamp. If the bridge node is launched with `use_sim_time:=true`, `get_clock()->now()` returns the value the node just published on `/clock`, self-consistent but quantised to the `/clock` interval, reproducing the defect class recorded in [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md). Without `use_sim_time` the stamps are wall time and share no epoch with `/clock`.

The remedy is small and local. Each publisher lambda already receives the parsed payload as `const json& msg`, so reading `msg["time_stamp"]` and converting nanoseconds to `builtin_interfaces::msg::Time` would give per-sample sim stamps. Affected call sites are `CreateGpsPublisher` `:338-358`, `CreateImuPublisher` `:378-397`, `CreateBarometerPublisher` `:399-411`, `CreateMagnetometerPublisher` `:413-431`, `CreateLidarPublisher` `:433-461`, `CreateCameraInfoPublisher` `:490-502`, `CreateImagePublisher` `:504-535`. This is the highest-value patch for the NRT stack.

---

## C. ROS 2 integration

### C.1 The two bridges

| Attribute | `ros/projectairsim_ros2_cpp` | `ros/node/projectairsim-ros2` |
|---|---|---|
| Language | C++ | Python |
| Package name | `projectairsim_ros2_cpp` | `projectairsim_ros`, shared catkin package at `ros/node/package.xml:3` |
| Build system | `ament_cmake`, `CMakeLists.txt:1-2` | catkin plus setuptools, `ros/node/CMakeLists.txt:1-13` |
| Transport into sim | Project AirSim C++ client, linked at `CMakeLists.txt:75-92` | Project AirSim Python client |
| Shared core | none | `projectairsim_rosbridge`, shared with ROS 1 |
| Documentation | `docs/ros/ros2.md`, current | `docs/ros/ros.md`, ROS 1 oriented, largely stale |
| Version | `0.1.0`, `package.xml:4` | `2023.9.15`, `setup.py:9` |
| Publishes `/clock` | Yes | No |
| Tests | five gtest suites under `test/` | none |
| CI | yes, the head commit added its validation | none |

The C++ package is current. Its copyright header reads 2026 at `src/projectairsim_ros2_cpp_node.cpp:1`, against 2025 elsewhere, and the head commit of the repository added its CI validation. It does not exist at release tag `v0.2.0`, verified by `git ls-tree -d --name-only v0.2.0 ros/`, which lists only `ros/examples`, `ros/examples_externals` and `ros/node`.

### C.2 The C++ node

One class, `ProjectAirSimROS2CppNode final : public rclcpp::Node`, at `src/projectairsim_ros2_cpp_node.cpp:118-1399`, node name `projectairsim_ros2_cpp_node` at `:124`. `main` at `:1401-1412` spins one instance. Installed to `lib/projectairsim_ros2_cpp` at `CMakeLists.txt:117-119`.

Constructor order at `:123-194`. Declare fifteen parameters, connect with `client_->Connect(address_, port_topics_, port_services_)` at `:149-155` throwing on failure, load the named scene or adopt the loaded one at `:160-175`, create the `topic_info` and `/clock` publishers at `:177-180`, create the TF broadcaster at `:181-183`, create services at `:184`, the action server at `:185`, run discovery at `:186`, start the clock timer at `:187`, optionally start rediscovery at `:188-193`.

### C.3 Parameters

All at `:127-147`.

| Parameter | Type | Default | Line | Purpose |
|---|---|---|---|---|
| `address` | string | `127.0.0.1` | `:127` | Server host |
| `port_topics` | int | 8989 | `:128` | Pub-sub port |
| `port_services` | int | 8990 | `:129-130` | Service port |
| `scene_config` | string | empty | `:131` | Scene to load. Empty attaches to the loaded scene. |
| `sim_config_path` | string | `client/python/example_user_scripts/sim_config` | `:132-133` | Directory for relative scene names |
| `delay_after_load_sec` | double | 2.0 | `:134` | Settling delay |
| `projectairsim_topic_root` | string | `/Sim` | `:135-136` | Native prefix to rewrite |
| `ros_topic_root` | string | `/ProjectAirsim` | `:137` | Replacement prefix |
| `publish_unmatched_as_json` | bool | false | `:138-139` | Republish unhandled topics as `std_msgs/String` |
| `publish_tf` | bool | true | `:140` | Broadcast TF |
| `tf_world_frame_id` | string | `map` | `:141` | TF parent frame |
| `refresh_topics_period_sec` | double | 0.0 | `:142-143` | Rediscovery interval, 0.0 disables |
| `publish_clock_period_sec` | double | 0.02 | `:144-145` | `/clock` interval, 0.0 disables |
| `vehicle_name` | string | `Drone1` | `:146` | Vehicle for single-drone services and the action |
| `service_root` | string | `/projectairsim` | `:147` | Namespace for services and actions |

### C.4 Topic discovery and naming

`client_->GetTopicInfo()` at `:239` returns the live topic list, matched by suffix in `CreateHandler` at `:291-313`. The rewrite is a pure prefix substitution in `ToRosTopic` at `:315-321`, leaving the scene and robot path untouched.

Native paths are built by concatenation. The simulator is `/Sim`, because `Simulator::Loader::LoadID` calls `SetTopicPath()` at `core_sim/src/simulator.cpp:301`, `SetTopicPath` is `parent_topic_path_ + "/" + id_` at `core_sim/src/component.hpp:98`, and the simulator id comes from the hard-coded `"id": "Sim"` at `simserver/src/simserver.cpp:36-44`. The scene appends its id. Robots get parent path `scene topic path + "/robots"` at `core_sim/src/scene.cpp:1399`. Sensors get `robot topic path + "/sensors"` at `core_sim/src/actor/robot.cpp:1348`. A `Topic` appends its own name at `core_sim/src/topic.cpp:73-79`. The client-side mirror of the same rule is `Drone.set_topics` and `set_sensor_topics` at `client/python/projectairsim/src/projectairsim/drone.py:55-135`, where image type 0 maps to `scene_camera` at `:87-95` and a capture setting yields a topic only when `capture-enabled` is true at `:104`.

Worked example for `Drone1` in the shipped ArduPilot scene, whose id is `SceneBasicDrone`, with sensors `IMU1` and `DownCamera`.

| Entity | Native topic | ROS 2 topic after the default rewrite | Type |
|---|---|---|---|
| IMU | `/Sim/SceneBasicDrone/robots/Drone1/sensors/IMU1/imu_kinematics` | `/ProjectAirsim/SceneBasicDrone/robots/Drone1/sensors/IMU1/imu` | `sensor_msgs/msg/Imu` |
| Camera image | `/Sim/SceneBasicDrone/robots/Drone1/sensors/DownCamera/scene_camera` | `/ProjectAirsim/SceneBasicDrone/robots/Drone1/sensors/DownCamera/scene_camera` | `sensor_msgs/msg/Image` |
| Camera info | `/Sim/SceneBasicDrone/robots/Drone1/sensors/DownCamera/scene_camera_info` | `/ProjectAirsim/SceneBasicDrone/robots/Drone1/sensors/DownCamera/scene_camera/camera_info` | `sensor_msgs/msg/CameraInfo` |
| Robot pose | `/Sim/SceneBasicDrone/robots/Drone1/actual_pose` | `/ProjectAirsim/SceneBasicDrone/robots/Drone1/actual_pose` | `geometry_msgs/msg/PoseStamped` |
| GPS | `/Sim/SceneBasicDrone/robots/Drone1/sensors/GPS/gps` | `/ProjectAirsim/SceneBasicDrone/robots/Drone1/sensors/GPS/gps` | `sensor_msgs/msg/NavSatFix` |

The `imu_kinematics` to `imu` rename is `ReplaceSuffix` at `:379`. The camera-info rename is `CameraImageTopicFromInfoTopic` then `CameraInfoRosTopic` at `:490-492`.

Compared with Cosys-AirSim's `/airsim_node/Copter/front_center_Scene/image` and `/airsim_node/Copter/imu/Imu`, the naming is very different. Project AirSim keeps the full hierarchical path, including the scene id and the literal `robots` and `sensors` segments, and uses the sensor's configured `id` rather than a fixed role name.

Remappability. Only the root prefix is configurable, through `projectairsim_topic_root` and `ros_topic_root`, plus the sensor ids in the robot config. The `/robots/` and `/sensors/` segments and the scene id are not configurable through the bridge. Standard ROS 2 remapping arguments remain the only way to reproduce Cosys-AirSim's flat naming.

### C.5 Published topics

| Suffix matched | ROS 2 suffix | Type | QoS | Handler |
|---|---|---|---|---|
| `/gps` | `/gps` | `sensor_msgs/msg/NavSatFix` | `SensorDataQoS` | `:292,338-358` |
| `/actual_pose` | `/actual_pose` | `geometry_msgs/msg/PoseStamped` | `QoS(10)` | `:293,360-376` |
| `/imu`, `/imu_kinematics` | `/imu` | `sensor_msgs/msg/Imu` | `SensorDataQoS` | `:294-296,378-397` |
| `/barometer` | `/barometer` | `sensor_msgs/msg/FluidPressure` | `SensorDataQoS` | `:297,399-411` |
| `/magnetometer` | `/magnetometer` | `sensor_msgs/msg/MagneticField` | `SensorDataQoS` | `:298,413-431` |
| `/lidar` | `/lidar` | `sensor_msgs/msg/PointCloud2` | `SensorDataQoS` | `:299,433-461` |
| `/radar_detections` | same | `projectairsim_ros2_cpp/msg/RadarScan` | `SensorDataQoS` | `:300,463-475` |
| `/radar_tracks` | same | `projectairsim_ros2_cpp/msg/RadarTracks` | `SensorDataQoS` | `:301,477-488` |
| `*_camera_info` | `<image topic>/camera_info` | `sensor_msgs/msg/CameraInfo` | `SensorDataQoS` | `:302,490-502` |
| `*_camera`, `/scene_camera`, `/depth_camera`, `/depth_planar_camera`, `/depth_vis_camera`, `/disparity_normalized_camera`, `/segmentation_camera`, `/surface_normals_camera` | same | `sensor_msgs/msg/Image` | `SensorDataQoS` | `:303-310,504-535` |
| anything else, when `publish_unmatched_as_json` | same | `std_msgs/msg/String` | `QoS(10)` | `:311,537-545` |

Three further topics published by the node itself.

| Topic | Type | QoS | Line |
|---|---|---|---|
| `/projectairsim/topic_info` | `std_msgs/msg/String`, JSON array of native paths | `QoS(1).transient_local()` | `:177-178,243-245` |
| `/clock` | `rosgraph_msgs/msg/Clock` | `QoS(10)` | `:179-180,988-994` |
| `/tf` | `tf2_msgs/msg/TFMessage` via `tf2_ros::TransformBroadcaster` | broadcaster default | `:181-183,323-336` |

### C.6 Subscribed topics

None. The C++ node subscribes to no ROS topic. All inbound control is through services and the single action. The Python bridge does subscribe, offering `desired_pose` and `cmd_vel` at `ros/node/projectairsim-rosbridge/src/projectairsim_rosbridge/ros_bridge.py:275-280` and `topic_helpers.py:1516`.

### C.7 Services

Created in `CreateServices` at `:1080-1307`. Single-vehicle prefix is `service_root + "/" + vehicle_name`, computed at `:1081`, defaulting to `/projectairsim/Drone1`.

| Service | Type | Line |
|---|---|---|
| `/projectairsim/request` | `RawRequest` | `:1083-1089` |
| `/projectairsim/get_client_info` | `GetClientInfo` | `:1090-1097` |
| `/projectairsim/get_topic_info` | `GetTopicInfo` | `:1098-1105` |
| `/projectairsim/get_drones` | `GetDrones` | `:1106-1112` |
| `/projectairsim/publish` | `Publish` | `:1113-1117` |
| `/projectairsim/unsubscribe` | `Unsubscribe` | `:1118-1122` |
| `/projectairsim/cancel_all_requests` | `CancelAllRequests` | `:1123-1129` |
| `/projectairsim/Drone1/takeoff` | `Takeoff` | `:1131-1134` |
| `/projectairsim/Drone1/land` | `Land` | `:1135-1138` |
| `/projectairsim/Drone1/arm` | `Arm` | `:1139-1142` |
| `/projectairsim/Drone1/disarm` | `Disarm` | `:1143-1146` |
| `/projectairsim/Drone1/move_to_position` | `MoveToPosition` | `:1147-1155` |
| `/projectairsim/Drone1/move_on_path` | `MoveOnPath` | `:1156-1163` |
| `/projectairsim/takeoff_group` | `TakeoffGroup` | `:1165-1167` |
| `/projectairsim/land_group` | `LandGroup` | `:1168-1170` |
| `/projectairsim/arm_group` | `ArmGroup` | `:1171-1173` |
| `/projectairsim/disarm_group` | `DisarmGroup` | `:1174-1176` |
| `/projectairsim/create_voxel_grid` | `CreateVoxelGrid` | `:1177-1186` |
| `/projectairsim/occupancy_grid` | `OccupancyGrid` | `:1187-1203` |
| `/projectairsim/get_clock` | `GetClock` | `:1204-1209` |
| `/projectairsim/get_origin_geo_point` | `GetOriginGeoPoint` | `:1210-1222` |
| `/projectairsim/set_segmentation_id_by_name` | `SetSegmentationIDByName` | `:1223-1233` |
| `/projectairsim/get_segmentation_id_by_name` | `GetSegmentationIDByName` | `:1234-1246` |
| `/projectairsim/get_segmentation_id_map` | `GetSegmentationIDMap` | `:1247-1255` |
| `/projectairsim/set_object_material` | `SetObjectMaterial` | `:1256-1263` |
| `/projectairsim/set_object_texture` | `SetObjectTexture` | `:1264-1289` |
| `/projectairsim/swap_object_texture` | `SwapObjectTexture` | `:1290-1296` |
| `/projectairsim/reset` | `Reset` | `:1297-1301` |
| `/projectairsim/load_scene` | `LoadScene` | `:1302-1306` |

All thirty-three interface files are listed at `CMakeLists.txt:30-68`. Selected definitions. `GetClock.srv` is empty request, `int64 nanosec` response. `RawRequest.srv` is `string method`, `string json_parameters` request, and `bool success`, `string status`, `int32 error_code`, `string result_json`, `string raw_response` response. `Takeoff.srv` is `bool wait_on_last_task` request, `bool success` response. `LoadScene.srv` is `string scene_file`, `bool is_primary_client` request, `bool success` response.

Every handler is wrapped in try-catch by the `CreateService` template at `:1052-1066`. The takeoff, land, arm, disarm and motion services route through the client's `Drone` API at `:836-906`, which for an ArduPilot-controlled robot lands on the stubs of A.4 and returns false.

### C.8 Actions

Exactly one. `MoveOnPath`, created at `:1309-1324` on `service_root + "/" + vehicle_name + "/move_on_path"`, defaulting to `/projectairsim/Drone1/move_on_path`, type `projectairsim_ros2_cpp/action/MoveOnPath`. Goals are always accepted, cancellation always accepted, execution on a detached thread at `:1319-1323`. Feedback is one `string current_point_on_path` published once with the value submitted at `:1330-1331`.

A service of the same name also exists at `:1156`. ROS 2 keeps the namespaces distinct, so this is legal but confusing to tooling.

### C.9 Custom messages

Four at `ros/projectairsim_ros2_cpp/msg/`. `RadarReturn.msg` holds `float32 range`, `azimuth`, `elevation`, `doppler_velocity`, `amplitude`. `RadarScan.msg` holds a `std_msgs/Header` and `RadarReturn[] returns`. `RadarTrack.msg` and `RadarTracks.msg` complete the pair. These mirror the upstream `radar_msgs` package, on which the Python bridge depends instead, at `ros/node/package.xml:16`.

### C.10 Coordinate conversion

NED to ENU conversion is a negation of the second and third components, in `ToRosVector3` at `include/projectairsim_ros2_cpp/ros2_conversion_utils.hpp:241-254` and `ToRosQuaternion` at `:265-281`, with lidar points handled inline at `src/projectairsim_ros2_cpp_node.cpp:454-458`. This is a NED to NWU flip, not a true NED to ENU rotation, so the resulting frame is North-West-Up. Consumers expecting REP 103 ENU must account for that. Note that this affects only bridged topics, so a stack that takes its inertial data from ArduPilot's `/ap/imu/experimental/data`, whose `frame_id` is `base_link_ned`, is unaffected.

### C.11 Distro and dependencies

ROS 2 Humble, at `docs/ros/ros2.md:16`. Dependencies from `package.xml:11-24` are `ament_cmake` and `rosidl_default_generators` as build tools, then `geometry_msgs`, `nav_msgs`, `rclcpp_action`, `rclcpp`, `rosgraph_msgs`, `rosidl_runtime_cpp`, `sensor_msgs`, `std_msgs`, `tf2_ros`, with `rosidl_default_runtime` at exec time and `ament_cmake_gtest` for tests.

The package also builds the Project AirSim C++ client as a subdirectory at `CMakeLists.txt:71-80`, defaulting to `<repo>/client/cpp` and overridable through the cache variable `PROJECTAIRSIM_CPP_CLIENT_DIR`. `BUILD_SHARED_LIBS` is forced ON for interface generation at `:27` then forced OFF for the client at `:70`, a subtlety that matters if the package is vendored elsewhere. The client subproject fetches nlohmann JSON, msgpack, Eigen and NNG from the network at configure time, at `client/cpp/CMakeLists.txt:24-86`, so the first build requires network access.

### C.12 Launch files

There are none. No `launch/` directory exists in `ros/projectairsim_ros2_cpp/` and none is installed. `docs/ros/ros2.md:69-72` documents `ros2 run` with `--ros-args -p` overrides as the only invocation. The `.launch` files under `ros/examples/` are MoveIt demonstrations, not bridge launchers.

---

## D. Core architecture

### D.1 The layers and how they communicate

| Layer | Directory | Role |
|---|---|---|
| Simulation core | `core_sim/` | Clock, scene graph, actors, links, joints, actuators, sensors, transforms, messages, NNG managers |
| Physics | `physics/` | `FastPhysicsModel`, `UnrealPhysicsModel`, `MatlabPhysicsModel`, and `PhysicsWorld` |
| Vehicle APIs | `vehicle_apis/` | `multirotor_api` and `rover_api`, containing every controller |
| Assembly | `simserver/` | `SimServer`, composing simulator, physics, controllers, GIS tile manager |
| Rendering scene | `rendering/` | Host-agnostic GIS tile management |
| Renderer host | `unreal/`, also `unity/` | Spawns actors, renders, ray casts, drives the clock in engine-driven mode |
| Clients | `client/python`, `client/cpp`, `ros/` | Connect over NNG |

Core-to-host communication is by callback registration. `Scene` exposes `SetCallbackPhysicsStart`, `SetCallbackPhysicsSetWrenches`, `SetCallbackPhysicsStep`, `SetCallbackPhysicsStop`, `SetCallbackTopicPublished`, `SetCallbackWindVelocityUpdated`, `SetCallbackEnableUnrealViewportCamera` at `core_sim/src/scene.cpp:478-515`. `SimServer` exposes four external-scene lifecycle callbacks at `simserver/src/simserver.cpp:114-131`, bound by `AUnrealSimLoader` at `unreal/.../Private/UnrealSimLoader.cpp:40-52`.

Client communication is NNG over TCP.

| Channel | NNG protocol | Default port | Bind address | Evidence |
|---|---|---|---|---|
| Topics, publish-subscribe | `nng_pair0` | 8989 | `*` | `core_sim/src/topic_manager.cpp:250,291-293`, ip and port injected at `simserver/src/simserver.cpp:36-44` |
| Services, request-response | `nng_rep0` | 8990 | `*` | `core_sim/src/service_manager.cpp:187,212-216` |

The choice of `nng_pair0` is consequential. Pair-0 is strictly one to one, so only one topic client can be connected at a time. That is why `docs/ros/ros.md:52` warns the ROS bridge and a separate mission script cannot connect simultaneously. Any workflow that wants both a ROS 2 bridge and a Python mission script must route the mission through the bridge's services rather than opening a second client.

Ports are configurable in three places. The Unreal host reads `-topicsport` and `-servicesport` at `unreal/.../Private/UnrealSimLoader.cpp:165-195`, falling back to `"8989"` at `:174` and `"8990"` at `:190`. The Python client defaults at `client/python/projectairsim/src/projectairsim/client.py:32`. The C++ client at `client/cpp/ProjectAirsimClientLib/Include/ProjectAirsimClient/Client.h:31-32`. The documented switches are at `docs/command_line_switches.md:24-27`, which notes the two values must differ.

Payload encoding is MessagePack for topics, decoded by `UnpackProjectAirSimMessage` at `ros/projectairsim_ros2_cpp/include/projectairsim_ros2_cpp/ros2_conversion_utils.hpp:166-169`, and JSON for services.

### D.2 Entry points

`AProjectAirSimGameMode::StartPlay` calls `UnrealSimLoader.LaunchSimulation(GetWorld())` at `unreal/.../Private/ProjectAirSimGameMode.cpp:20-24`, and `EndPlay` tears it down at `:26-31`. The constructor sets `DefaultPawnClass = nullptr` and `FApp::bUseFixedSeed = true` for determinism at `:16-18`.

`AUnrealSimLoader::LaunchSimulation` at `unreal/.../Private/UnrealSimLoader.cpp:59-110` performs, in order, an Unreal version check against `SupportedUnrealVersionMajor = 5` and `SupportedUnrealVersionMinor = 1` at `unreal/.../Public/UnrealSimLoader.h:88-89`, then `SetUnrealEngineSettings()`, reads the auth key and two ports, then `SimServer->LoadSimulator(...)`, `SimServer->LoadScene()` with no argument, `LoadUnrealScene()`, `SimServer->StartSimulator()`, `StartUnrealScene()`, `SimServer->StartScene()`. The version check warns rather than aborts, so 5.2 and 5.7 run while printing a spurious warning.

The scene loaded at startup is not the user's scene. `SimServer::LoadScene` defaults its argument to empty at `simserver/include/simserver.hpp:44`, and `LoadSimulator` supplies the hard-coded `"default-scene": "{\"id\": \"DefaultScene\"}"` at `simserver/src/simserver.cpp:36-44`.

There is no command-line switch that selects a scene. The complete set parsed by the plugin is `clientauthpubkey`, `topicsport`, `servicesport`, `gltfDir` and several PixelStreaming options, at `unreal/.../Private/UnrealSimLoader.cpp:147,169,183,199,287-311`. Scene selection is exclusively a client call, through the `LoadScene` service registered at `simserver/src/simserver.cpp:154-157`, whose handler `SimReloadSceneWithJSON` at `:160-250` stops, unloads, loads the new JSON, re-registers service methods and returns the new scene id so the client can rebuild its topic paths. Python reaches it through `World(client, "scene_x.jsonc")` at `client/python/projectairsim/src/projectairsim/world.py:37-72`, and the ROS 2 bridge through its `scene_config` parameter or the `/projectairsim/load_scene` service.

This is the single largest structural difference from Cosys-AirSim, which reads one `settings.json` at game startup through a `-settings=` flag. A Project AirSim game starts empty and waits for a client.

A headless entry point exists. `samples/standalone_sim/main.cpp` constructs a `SimServer` directly, loads the default scene, starts it and sleeps forever, with ports optionally from `argv[1]` and `argv[2]` at `:21-46`. It does no rendering, so cameras and ray-cast sensors are unavailable, but it proves `core_sim` plus `simserver` are engine-independent.

### D.3 The configuration file model

Two levels, at `docs/config.md:14-18`. Scene configs prefixed `scene_`, robot configs prefixed `robot_`, both in a `sim_config/` directory resolved relative to the client script, per `docs/config.md:3-12`. Format is JSONC.

Linkage is by filename. A scene actor entry carries `robot-config`, resolved and inlined by the client before sending, per `docs/config_scene.md:59` and `load_scene_config_as_dict` referenced at `client/python/projectairsim/src/projectairsim/world.py:60-70`.

Scene keys, from `docs/config_scene.md:21-32` and `.../scene_config_schema.jsonc`.

| Key | Type | Meaning |
|---|---|---|
| `id` | string | Scene identifier, and the second path segment of every topic |
| `actors` | array | Robots to spawn |
| `clock` | object | See B.1 |
| `home-geo-point` | `latitude`, `longitude`, `altitude` | Scene origin on Earth, used for GPS and atmosphere |
| `segmentation` | `initialize-ids`, `ignore-existing`, `use-owner-name` | Automatic segmentation id assignment |
| `scene-type` | enum | `UnrealNative`, `CustomGIS`, `BlackShark` in the schema at `:410-417`, but the C++ enum also has `CesiumGIS` at `core_sim/include/core_sim/scene.hpp:37-44` |
| `tiles-dir`, `tiles-altitude-offset`, `tiles-lod-max`, `tiles-lod-min` | GIS tile controls | defaults 19 and 13, `docs/config_scene.md:31-32` |

Actor keys, from `docs/config_scene.md:52-60`. `type`, only `robot`. `name`. `origin.xyz`, three floats in metres NED with up negative, measured from the global Unreal origin rather than `PlayerStart`. `origin.geo-point`, an alternative giving latitude, longitude, altitude. `origin.rpy` in radians or `origin.rpy-deg` in degrees. `robot-config`, which is the current key, used by all fifty two example scenes and declared at `scene_config_schema.jsonc:85`, whereas the `"ref"` spelling in `docs/use_plugin.md` is stale. `start-landed`, optional, locks the vertical position until net upward force exceeds weight.

Robot top-level keys are `physics-type`, `links`, `joints`, `controller`, `actuators`, `sensors`, per `docs/config.md:54-63`, with `physics-type` and `links` mandatory at `.../robot_config_schema.jsonc:678`.

### D.4 Coordinate frames and units

NED throughout. Translations in metres, rotations in radians when the key is `rpy` and degrees when the key is `rpy-deg`. Implemented in `JsonUtils::GetTransform` at `core_sim/src/json_utils.cpp:101-128`, reading `xyz`, or converting a `geo-point` through the geodetic converter at `:106-116`, preferring `rpy` over `rpy-deg` and converting the latter with `TransformUtils::ToRadians` at `:120-126`. Key strings at `core_sim/src/constant.hpp:93-96`.

NED to Unreal NEU helpers at `core_sim/include/core_sim/transforms/transform_utils.hpp:55-62`, with `ToCentimeters` and `ToMeters` at `:44-49`, since Unreal works in centimetres. `home-geo-point.altitude` is positive up, noted at `docs/config_scene.md:166`, unlike the NED z of `origin.xyz`.

### D.5 Links, joints, actuators and sensor poses

Links require only `name`, at `.../robot_config_schema.jsonc:11-40`, and may carry `inertial`, `collision`, `visual`, and for rotating visual-only links `revolutions-per-sec`, `initial-angle`, `axis`, `parent-link`.

`inertial` requires `mass` and `inertia`, optionally `origin` and `aerodynamics`, at `:397-406`. `inertia.type` is `geometry`, `point-mass` or `matrix` at `:355-366`. `geometry` supports `box` with a `size` string of three floats, or `cylinder` with `radius` and `length`, at `:373-393`. `aerodynamics` carries `drag-coefficient`, `type`, `geometry` at `:384-396`.

`collision` carries `restitution`, `friction`, `enabled` at `:408-415`. `visual` requires `geometry` with `type` and `name`, typically `unreal_mesh` and an asset path such as `/Drone/Quadrotor1`, per `robot_ardu_quadrotor.jsonc:30-35`.

Joints require `id`, `type`, `parent-link`, `child-link`, `axis`, at `:41-57`. The only supported `type` is `fixed`, at `:48-51`.

Actuators require `name`, `type`, `enabled`, `parent-link`, `child-link`, at `:112-126`. `type` is `rotor`, `lift-drag-control-surface`, `tilt`, `gimbal` or `wheel` at `:119-122`. `rotor-settings` requires `turning-direction` from `clock-wise` or `counter-clock-wise`, `normal-vector`, `coeff-of-thrust`, `coeff-of-torque`, `max-rpm`, `propeller-diameter`, `smoothing-tc`, at `:562-577`. `wheel-settings` requires `wheel-type`, `coeff-of-friction`, `coeff-of-wheel-torque`, `engine`, `steering`, `brake` at `:578-589`. `tilt-settings` requires `angle-max`, `angle-min`, `axis`, `smoothing-tc`, `target`, optionally `input-map`, at `:590-601`.

Sensor poses use the same `origin` object relative to `parent-link`. Only the camera loader actually reads it, at `core_sim/src/sensors/camera.cpp:1454-1464`. The IMU loader reads nothing but `accelerometer` and `gyroscope`, at `core_sim/src/sensors/imu.cpp:270-292`, so an IMU always sits exactly at its parent link's frame origin. Lidar, radar and distance sensors carry an `origin` in their settings structs defaulting to `Vector3(0, 0, -1)`, at `lidar.hpp:101` and `distance_sensor.hpp:41`.

The consequence for visual-inertial work is favourable and load-bearing. Because the IMU is pinned to the parent link origin, the camera-to-IMU extrinsic is exactly the camera's configured `origin` relative to the same parent link, with no composition required.

### D.6 Sensors

Types accepted at `.../robot_config_schema.jsonc:141-144` are `camera`, `imu`, `lidar`, `distance-sensor`, `gps`, `barometer`, `magnetometer`, `radar`, `airspeed`, `battery`. Every sensor requires `id`, `type`, `enabled`, `parent-link` at `:137`.

Sim-side topic names, appended to `<robot topic>/sensors/<sensor id>/`.

| Sensor type | Topic names | Line |
|---|---|---|
| `imu` | `imu_kinematics` | `core_sim/src/sensors/imu.cpp:161-162` |
| `gps` | `gps` | `gps.cpp:200` |
| `barometer` | `barometer` | `barometer.cpp:158` |
| `magnetometer` | `magnetometer` | `magnetometer.cpp:161` |
| `airspeed` | `airspeed` | `airspeed.cpp:167` |
| `distance-sensor` | `distance_sensor` | `distance_sensor.cpp:171` |
| `lidar` | `lidar` | `lidar.cpp:321` |
| `radar` | `radar_detections`, `radar_tracks` | `radar.cpp:160,163` |
| `battery` | `battery` | `battery.cpp:201` |
| `camera` | seven image topics, seven info topics, `post_process_onnx_image` | `camera.cpp:422-467` |

Robot-level topics are `actual_pose` published, `desired_pose` subscribed, `collision_info` published, `rotor_info` published, at `core_sim/src/actor/robot.cpp:564-578`.

Camera. `CaptureSettings` at `core_sim/include/core_sim/sensors/camera.hpp:65-113` holds `image_type` 0, `capture_enabled` false, `streaming_enabled` false, `show_debug_plots` false, `width` 256, `height` 144, `fov_degrees` NaN meaning 90, `pixels_as_float` false, `compress` true, a full auto-exposure block defaulting to NaN so Unreal's own defaults survive, `motion_blur_amount` NaN, `target_gamma` 2.5 with a scene override constant `kSceneTargetGamma = 1.4f` at `:76`, `projection_mode` 0 meaning perspective, `ortho_width` NaN, `max_depth_meters` 1.0, and three cinematic controls. `ImageType` at `:35-45` is `kScene` 0, `kDepthPlanar` 1, `kDepthPerspective` 2, `kSegmentation` 3, `kDepthVis` 4, `kDisparityNormalized` 5, `kSurfaceNormals` 6.

`capture-enabled` is the key that determines whether a capture setting yields a topic, documented at `docs/sensors/camera_capture_settings.md:86` and gated client-side at `drone.py:104`. `streaming-enabled` is a separate PixelStreaming video feed and is not a topic.

`CameraSettings` at `:167-186` adds `origin_setting`, `gimbal_setting`, `capture_interval` defaulting to 5.0 s, `capture_settings` and `noise_settings` arrays, `annotation_settings`, `post_process_model_settings`, a fixed `sensor_width` of 23.76 mm and `aperture` f/2.0.

`AnnotationSettings` at `:151-158` holds an `object_ids` set, separate 2D and 3D `BBoxSettings` each with `alignment` of `axis` or `oriented`, an `enabled` flag, and a distance filter defaulting to 10.0 m. `NoiseSettings` at `:115-136` holds the fifteen-parameter analogue-television noise model. `GimbalSettings` at `:139-145` holds `is_gimbal_mounted`, `gimbal_id`, `lock_roll`, `lock_pitch`, `lock_yaw`.

IMU. `ImuParams` at `core_sim/include/core_sim/sensors/imu.hpp:33-51`.

| Sub-block | Config key | Field | Default | Unit as used |
|---|---|---|---|---|
| `accelerometer` | `gravity` | `accelerometer.gravity` | 9.80665 | m/s squared |
| `accelerometer` | `velocity-random-walk` | `velocity_random_walk` | `0.24 * g / 1e3` = 2.35360e-3 | applied as sigma divided by sqrt(dt) |
| `accelerometer` | `tau` | `accelerometer.tau` | 800 | seconds |
| `accelerometer` | `bias-stability` | `accelerometer.bias_stability` | `36e-6 * g` = 3.53039e-4 | m/s squared |
| `accelerometer` | `turn-on-bias` | `turn_on_bias` | `0 0 0` | m/s squared, three-float string |
| `gyroscope` | `angle-random-walk` | `gyro.angle_random_walk` | `0.3/sqrt(3600) * pi/180` = 8.72665e-5 | rad per sqrt(s) |
| `gyroscope` | `tau` | `gyro.tau` | 500 | seconds |
| `gyroscope` | `bias-stability` | `gyro.bias_stability` | `4.6/3600 * pi/180` = 2.23014e-5 | rad/s |
| `gyroscope` | `turn-on-bias` | `gyro.turn_on_bias` | `0 0 0` | rad/s |
| top level | not configurable | `min_sample_time` | 1/1000 | seconds |

Key strings at `core_sim/src/constant.hpp:253-260`. The loader reads them with no unit conversion whatsoever, at `core_sim/src/sensors/imu.cpp:294-336`, using `JsonUtils::GetNumber<float>`. Two derived quantities are precomputed, `accelerometer_bias_stability_norm = bias_stability / sqrt(tau)` at `:311-313` and the gyroscope equivalent at `:333-334`.

The noise model is at `core_sim/src/sensors/imu.cpp:210-236`. Per update, `sqrt_dt = sqrt(max(dt, min_sample_time))`, white noise sigma is `random_walk / sqrt_dt`, and the bias random-walks with sigma `bias_stability_norm * sqrt_dt`. Orientation is never perturbed, at `:191`, so `pose` in the ArduPilot packet is exact ground truth.

This is the same model and defaults as Cosys-AirSim's `ImuSimpleParams` at `/ws/sitl_ws/src/ue5/AirSim/AirLib/include/sensors/imu/ImuSimpleParams.hpp:29-47`, with one critical difference. Cosys-AirSim accepts engineering units in `settings.json` and converts internally at `:51-72`. Project AirSim accepts only already-converted SI values. The translation table for the NRT settings follows.

| Cosys-AirSim key | NRT value | Cosys unit | Cosys conversion | Project AirSim key | Project AirSim value |
|---|---|---|---|---|---|
| `AngularRandomWalk` | 2.0 | deg per sqrt(hour) | divide by sqrt(3600), multiply by pi/180 | `gyroscope.angle-random-walk` | 5.817764e-4 |
| `GyroBiasStabilityTau` | 300 | seconds | none | `gyroscope.tau` | 300 |
| `GyroBiasStability` | 20.0 | deg per hour | divide by 3600, multiply by pi/180 | `gyroscope.bias-stability` | 9.696274e-5 |
| `VelocityRandomWalk` | 1.2 | milli-g | multiply by 9.80665, divide by 1000 | `accelerometer.velocity-random-walk` | 1.176798e-2 |
| `AccelBiasStabilityTau` | 600 | seconds | none | `accelerometer.tau` | 600 |
| `AccelBiasStability` | 500 | micro-g | multiply by 1e-6 and by 9.80665 | `accelerometer.bias-stability` | 4.903325e-3 |

The proof that the two are the same model is that Project AirSim's shipped example values reproduce Cosys-AirSim's defaults exactly. 0.30 deg per sqrt(hour) converts to 8.726646e-05 against the example's 8.72644e-05, 4.6 deg per hour to 2.230143e-05 against 2.23014e-05, 0.24 milli-g to 2.353596e-03 against 2.353e-03, and 36 micro-g to 3.530394e-04 against 3.53e-04.

The resulting sensor block is as follows.

```json
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

The camera-to-IMU extrinsic transfers unchanged, because both simulators express sensor poses in a body-fixed NED frame and the Project AirSim IMU sits at the parent link origin. The Cosys-AirSim camera at X 0.50, Y 0, Z 0.10 with Pitch -45 degrees becomes the following camera `origin` block.

```json
"origin": {
  "xyz": "0.50 0.0 0.10",
  "rpy-deg": "0 -45 0"
}
```

That equivalence was independently confirmed by decoding `/ws/ros_ws/src/slam/ext/basalt/data/sitl_calib.json:4-12`, whose quaternion maps the camera optical boresight onto 0.7071, 0.0, 0.7071 in the body NED frame, which is forward and forty five degrees down, and whose translation is 0.5, 0.0, 0.1 metres. The Basalt calibration therefore needs no edit.

GPS. `GpsParams` at `core_sim/include/core_sim/sensors/gps.hpp:26-34` holds `eph_time_constant` and `epv_time_constant` 0.9, `eph_initial` and `epv_initial` 100.0, `eph_final` and `epv_final` 0.1, `eph_min_3d` 3.0, `eph_min_2d` 4.0. Config keys `eph-time-constant`, `eph-initial`, `epv-initial`, `eph-final`, `epv-final`, `eph-min-3d`, `eph-min-2d` at `.../robot_config_schema.jsonc:206-233`. Dilution relaxes through a first-order filter and drives the fix type at `gps.cpp:241-253`, so a fresh GPS reports no fix and converges to 3D. Position comes directly from the environment geo point with no positional noise at `:224`, velocity from the ground-truth twist at `:225`.

Barometer. `BarometerParams` at `barometer.hpp:27-54` holds `qnh` defaulting to sea-level pressure in mbar, `pressure_factor_sigma` 0.0365/20, `pressure_factor_tau` 3600, `uncorrelated_noise_sigma` 2.7, `update_latency` 0.0 s, `update_frequency` 50 Hz, `startup_delay` 0 s. Config keys `qnh`, `pressure-factor-sigma`, `pressure-factor-tau`, `uncorrelated-noise-sigma`, `update-latency`, `update-frequency`, `startup-delay` at `.../robot_config_schema.jsonc:235-256`.

Magnetometer. `MagnetometerParams` at `magnetometer.hpp:27-44` holds `noise_sigma` of 0.005 on each axis, `scale_factor` 1.0, `noise_bias` zeros, `dynamic_reference_source` true, `ref_source` the dipole model. Config keys `scale-factor`, `noise-sigma`, `noise-bias` at `:257-266`.

Lidar. `LidarSettings` at `lidar.hpp:45-120`. `lidar-type` is one of `generic_cylindrical`, `generic_rosette`, `livox_mid70`, `livox_avia`, `gpu_cylindrical`, `depth_lidar` at the schema `:157`. Defaults are 16 channels, 100 m range, 100000 points per second, `report_frequency` 0 meaning as fast as possible, 10 Hz horizontal rotation, horizontal field of view 0 to 360 degrees, vertical field of view -45 to -15 degrees, `disable_self_hits` false, `report_no_return_points` false, `draw_debug_points` false.

Radar. `RadarSettings` at `radar.hpp:41-58`. Azimuth -60 to +60 degrees at 1 degree resolution, elevation -40 to +40 degrees at 3 degree resolution, `range_max` 2000 m at 3 m resolution, `velocity_max` 200 m/s at 1 m/s resolution, `detection_interval` 0.02 s, `track_interval` 0.1 s, `rcs_adjust_factor` 1.0, plus optional `masks` filtering by azimuth, elevation, range, velocity and radar cross-section at `:28-38`.

Distance sensor. `DistanceSensorSettings` at `distance_sensor.hpp:30-50`. Origin `(0, 0, -1)`, `report_frequency` 0, `min_distance` 0.2 m, `max_distance` 40.0 m, `draw_debug_points` false.

Airspeed. `AirspeedSensorParams` at `airspeed.hpp:27-44`, the same Gauss-Markov pressure model as the barometer plus `forward_xyz` `(1, 0, 0)`.

Battery. Two modes, `simple-discharge-mode` and `rotor-power-discharge-mode`, with `total-battery-capacity`, `battery-capacity-on-start`, `battery-drain-rate-on-start`, `rotor-power-coefficient`, at `.../robot_config_schema.jsonc:266-289`.

There is no `docs/sensors/imu.md`, despite `imu.hpp:30` instructing the reader to see it and `imu.cpp:210` referring to the docs for the mathematics. `docs/config_robot.md:679-686` lists Airspeed, Barometer, GPS, IMU and Magnetometer settings as plain unlinked text while linking only Camera, Lidar and Radar. The IMU documentation does not exist, and everything above is derived from source.

### D.7 Physics

`PhysicsType` at `core_sim/include/core_sim/physics_common_types.hpp:18-23` is `kNonPhysics` 0, `kFastPhysics` 1, `kUnrealPhysics` 2, `kMatlabPhysics` 3. Config strings at `core_sim/src/constant.hpp:386-392`, parsed by `Robot::Loader::LoadPhysicsType` at `core_sim/src/actor/robot.cpp:1394-1418`, falling back to `kNonPhysics` with a warning.

The schema is narrower than the code. `.../robot_config_schema.jsonc:10` allows only `fast-physics`, `non-physics`, `matlab-physics`, omitting `unreal-physics`, which the code supports and `docs/config_robot.md:56` documents. The code is authoritative and such a config works while failing schema validation.

There is no common `PhysicsEngine` base class. `physics/include/physics_world.hpp:26-27` uses `std::variant<FastPhysicsModel, UnrealPhysicsModel, MatlabPhysicsModel>`, with a comment at `:21-25` stating a common base was deliberately avoided so each model may expose unique methods. What they share is `BasePhysicsBody` at `physics/include/base_physics.hpp:19-79`, declaring one pure virtual, `CalculateExternalWrench()`, and otherwise holding mass, inverse mass, inertia, inverse inertia, friction, restitution, kinematics and the accumulated external wrench.

`PhysicsWorld` at `physics/include/physics_world.hpp:29-56` owns bodies and lazily instantiates one model per type in `AddRobot` at `physics/src/physics_world.cpp:22-58`. `StepPhysicsWorld(dt_nanos)` switches per body, delegating to `FastPhysicsModel::StepPhysicsBody` or `MatlabPhysicsModel::StepPhysicsBody`, and deliberately doing nothing for `kUnrealPhysics` because Unreal integrates that body itself.

Fast Physics is described at `docs/physics/fast_physics.md`, modelling the airframe as a cuboid with rotors as point masses and computing drag on the cuboid faces and rotor discs. Matlab physics is at `docs/physics/matlab_physics.md`, communicating with Simulink over TCP, with S-function sources at `physics/matlab_sfunc/`. Every shipped ArduPilot example uses `fast-physics`.

### D.8 The example vehicle catalogue

Eighty-nine files under `client/python/example_user_scripts/sim_config/`. The robot configs are as follows.

| Config | Airframe and notable feature |
|---|---|
| `robot_quadrotor_fastphysics.jsonc` | Baseline quadrotor with Simple Flight |
| `robot_quadrotor_fastphysics_sensors.jsonc` | Full sensor suite |
| `robot_quadrotor_fastphysics_chase.jsonc` | Chase camera |
| `..._lidar`, `_gpu_lidar`, `_depth_lidar`, `_mid70`, `_avia` | Each lidar backend |
| `..._battery_simple`, `_battery_energy` | The two battery discharge modes |
| `..._onnx` | Camera post-processing through ONNX |
| `..._weather` | Weather effects |
| `robot_quadrotor_nonphysics.jsonc`, `_annotations`, `_blocks_annotations` | Computer-vision mode |
| `robot_computer_vision.jsonc` | Camera-only actor |
| `robot_quadrotor_manual_controller.jsonc`, `robot_quadrotor_manual_step.jsonc` | Manual controller |
| `robot_quadrotor_matlab_controller/physics/combined.jsonc` | Matlab controller, physics, both |
| `robot_quadrotor_px4_sitl.jsonc`, `_px4_sitl_wsl2`, `_px4_hitl`, `_px4_gimbal` | PX4 in four configurations |
| `robot_hexarotor_fastphysics.jsonc` | Hexarotor |
| `robot_quadtiltrotor_fastphysics.jsonc`, `_px4_sitl`, `_px4_hitl`, `_sf_config` | VTOL quad tiltrotor |
| `robot_quadtiltrotor_matlabphysics.jsonc` | VTOL with Matlab physics |
| `robot_rover_fastphysics.jsonc` | Ackermann ground vehicle using `simple-drive-api` |
| `radar_tower.jsonc` | Static radar installation |
| `env_actor_*.jsonc` | Trajectory-driven environment actors |

The ArduPilot robot configs live separately, under `client/python/example_user_scripts/ardupilot/sim_config/`.

---

## E. The Unreal side

### E.1 Directory layout

```
unreal/
└─ Blocks/
   ├─ Blocks.uproject                   EngineAssociation "5.1"
   ├─ blocks_genprojfiles_vs2019.bat, _vs2022.bat, _vscode.bat, _vscode.sh
   ├─ Config/  DefaultEngine.ini, DefaultGame.ini, DefaultEditor.ini,
   │           DefaultInput.ini, DefaultGameUserSettings.ini,
   │           DefaultEditorPerProjectUserSettings.ini, HoloLens/HoloLensEngine.ini
   ├─ Content/ BlocksMap, GISMap, Geometry, glTF_tiles_to_pak
   ├─ Source/  Blocks.Target.cs, BlocksEditor.Target.cs,
   │           Blocks/{Blocks.Build.cs, Blocks.cpp, Blocks.h}
   └─ Plugins/
      ├─ ProjectAirSim/   ProjectAirSim.uplugin, Resources/, Content/,
      │                   Source/ProjectAirSim/{ProjectAirSim.Build.cs, Public/, Private/}
      │                   (SimLibs/ appears at build time, not in git)
      ├─ Drone/           content-only, drone meshes
      └─ Rover/           content-only, rover meshes
```

`unity/BlocksUnity/` also exists with a `UnitySimLoader.cs` using the same 8989 and 8990 defaults at `unity/BlocksUnity/Assets/ProjectAirSimAssets/Scripts/UnitySimLoader.cs:81,89`, confirming the core is engine-agnostic. It is not the supported path.

### E.2 What `unreal/Blocks` is

`Blocks` is the reference environment. Its `.uproject` declares one runtime module named `Blocks`, enables `ProjectAirSim` and `SunPosition`, explicitly disables `SteamVR`, `OculusVR`, `USDImporter` and `GLTFExporter`, and lists `LinuxNoEditor` and `WindowsNoEditor` as target platforms, with `EngineAssociation` `"5.1"`.

The `Blocks` module is a shell. `Source/Blocks/Blocks.cpp` is a single `IMPLEMENT_PRIMARY_GAME_MODULE` line, and `Source/Blocks/Blocks.Build.cs` depends only on `Core`, `CoreUObject`, `Engine`, `InputCore`. Its purpose is solely to make the project a C++ project so the plugin can compile during packaging. `Source/Blocks.Target.cs` sets `Type = TargetType.Game`, `DefaultBuildSettings = BuildSettingsVersion.Latest`, `IncludeOrderVersion = EngineIncludeOrderVersion.Latest`.

There is a three-way disagreement on the supported Unreal version. `README.md:86,92` states 5.2 or 5.7 only. `docs/development/dev_setup_linux.md:26,62` names 5.2 and 5.7. `Blocks.uproject` sets `EngineAssociation` `"5.1"`. `unreal/.../Public/UnrealSimLoader.h:88-89` hard-codes major 5 and minor 1, and `UnrealSimLoader.cpp:66-72` warns at startup for any other version. The warning is non-fatal, so 5.2 and 5.7 work but print a spurious warning. The README is the most recent statement of intent.

### E.3 What a third-party project must contain

Authoritative guidance is `docs/use_plugin.md`, and the packaged layout is at `:9-24`. The delta a project such as StonePineForest must acquire follows.

| Item | Requirement | Evidence |
|---|---|---|
| Plugins directory | Copy the packaged `Plugins/` folder into the project root beside the `.uproject`. It contains `ProjectAirSim` plus content-only plugins such as `Drone` and `Rover`. | `docs/use_plugin.md:30` |
| `.uproject` plugin entry | `{"Name": "ProjectAirSim", "Enabled": true}` | `unreal/Blocks/Blocks.uproject` |
| Transitive plugin entries | `ProjectAirSim.uplugin` itself requires `ProceduralMeshComponent`, `SunPosition`, `PixelStreaming` | `unreal/Blocks/Plugins/ProjectAirSim/ProjectAirSim.uplugin` |
| Module loading phase | The `ProjectAirSim` module is `Runtime`, `LoadingPhase` `PostConfigInit` | same file |
| `Config/DefaultEngine.ini` | `[/Script/EngineSettings.GameMapsSettings]` with `GlobalDefaultGameMode=/Script/ProjectAirSim.ProjectAirSimGameMode` | `docs/use_plugin.md:36-41`, live value at `unreal/Blocks/Config/DefaultEngine.ini:11` |
| Per-map GameMode override | Set the same GameMode in `World Settings` for every map, because that overrides the ini per map | `docs/use_plugin.md:43-49` |
| `Config/DefaultGame.ini` | `[/Script/UnrealEd.ProjectPackagingSettings]` with `+DirectoriesToAlwaysCook=(Path="/ProjectAirSim")`, `(Path="/Drone")`, `(Path="/Rover")`, otherwise plugin content is not cooked because nothing references it | `docs/use_plugin.md:110-121`, live values at `unreal/Blocks/Config/DefaultGame.ini` |
| A `Source/` folder | The project must be a C++ project or the plugin cannot compile during packaging. Add a dummy C++ class through the editor and delete the generated files, keeping the boilerplate. | `docs/use_plugin.md:51` |
| No `Build.cs` changes | Explicitly not required. `docs/use_plugin.md:3` states the plugin drops in without requiring any code changes to the project, and the `Blocks` module names no ProjectAirSim dependency. | `unreal/Blocks/Source/Blocks/Blocks.Build.cs` |
| No custom GameMode or Pawn | `AProjectAirSimGameMode` is provided and sets `DefaultPawnClass = nullptr`. Robots are spawned by the sim from the scene config, not by Unreal's pawn machinery. | `unreal/.../Private/ProjectAirSimGameMode.cpp:16-18` |
| Physics settings | Recommended to mirror `[/Script/Engine.PhysicsSettings]` from Blocks, notably `bSubstepping=False`, `MaxPhysicsDeltaTime=0.033333`, `DefaultGravityZ=-980.0` | `unreal/Blocks/Config/DefaultEngine.ini` |
| Renderer settings | Blocks sets `r.DefaultFeature.MotionBlur=False`, `r.DynamicGlobalIlluminationMethod=2`, `r.AntiAliasingMethod=1` | same file |

The plugin's own build requirements are in `unreal/.../ProjectAirSim.Build.cs`. It links eleven static libraries from `PluginDirectory + "/SimLibs/"`, namely `core_sim`, `simserver`, `physics`, `multirotor_api`, `rover_api`, `rendering_scene`, `mavlinkcom`, `nng`, `assimp`, `zlibstatic` and shared `onnxruntime`, at `:140-155` for Windows and `:180-192` for Linux, in a `Debug` or `Release` subdirectory selected at `:23-26`. Public module dependencies are `Core`, `CoreUObject`, `Engine`, `InputCore`, `ImageWrapper`, `RenderCore`, `Renderer`, `RHI`, `Landscape`, `UMG`, `PhysicsCore`, `CinematicCamera` at `:96-112`. Private adds `MovieSceneCapture`, `Slate`, `SlateCore`, `Projects`, `ProceduralMeshComponent`, `PixelStreaming`, `SunPosition` at `:114-131`. It also adds the engine's `Renderer/Private` and `Renderer/Internal` directories to private include paths at `:34-37` and `:89-92`, a hard coupling to engine internals and the most likely source of breakage across engine versions.

A third-party project consumes the packaged plugin, in which `SimLibs/` is already populated, so none of that concerns the integrator unless the plugin is rebuilt from source. The walkthrough at `docs/use_plugin.md:63-105` uses Epic's SunTemple as the worked example and is directly transferable. Its one substantive extra step is adjusting the drone spawn origin so the vehicle does not spawn inside geometry, at `:97-105`, which matters greatly for a landscape map whose terrain is far from the world origin.

### E.4 Packaging and the resulting binary

Packaging is driven by `build_linux.mk`, invoked through `./build.sh <target>`, requiring `UE_ROOT`, checked at `build.sh:9-12`. Targets are listed by the default rule at `build_linux.mk:20-47`.

| Target | Effect |
|---|---|
| `simlibs_debug`, `simlibs_release` | CMake-configure and build the sim libraries and C++ client, `:116-133` |
| `package_simlibs` | rsync `unreal/Blocks/Plugins/ProjectAirSim/SimLibs/` into `packages/projectairsim_simlibs/`, `:135-142` |
| `blocks_debuggame`, `blocks_development`, `blocks_shipping` | `$(UE_ROOT)/Engine/Build/BatchFiles/Linux/Build.sh Blocks Linux <Config> -project=.../Blocks.uproject`, `:198-243` |
| `package_blocks_development` | `RunUAT.sh BuildCookRun -project=.../Blocks.uproject -nop4 -nocompile -build -cook -compressed -pak -allmaps -stage -archive -archivedirectory=packages/Blocks/Development -clientconfig=Development -clean -utf8output -prereqs`, `:261-277` |
| `package_blocks_shipping` | As above with `-clientconfig=Shipping -nodebuginfo`, `:278-294` |
| `package_plugin` | rsync `unreal/Blocks/Plugins/` into `packages/projectairsim_ue_plugin/Plugins/`, excluding `Binaries` and `Intermediate`, `:295-304` |

CMake writes built libraries directly into the plugin tree. `CMakeLists.txt:70` sets `UE_PLUGIN_SIMLIBS_DIR` to `${CMAKE_SOURCE_DIR}/unreal/Blocks/Plugins/ProjectAirSim/SimLibs`, which is why `Build.cs` can reference `PluginDirectory + "/SimLibs/..."` unconditionally. This is also why the sim libs must be built before Unreal Build Tool ever runs, and is the root cause of the missing-module reports in issues 83 and 129.

The archive is the standard Unreal staged layout, `packages/Blocks/Development/LinuxNoEditor/` containing `Blocks.sh`, a `Blocks/Binaries/Linux/` executable and cooked `.pak` content. The run script is invoked with the switches at `docs/command_line_switches.md`, of which the operationally important ones are `-RenderOffScreen`, `-nullrhi`, `-ResX=`, `-ResY=`, `-windowed`, `-NoVSync`, `-vulkan`, `-topicsport=`, `-servicesport=`. `run_sim_with_streaming.sh` at the repository root wraps the PixelStreaming configuration.

---

## F. Documentation index

| File | Covers |
|---|---|
| `docs/index.md` | Sphinx entry point, includes the root `README.md` |
| `docs/api.md` | Complete client API overview, including SimClock control APIs and manual-controller commands |
| `docs/changelog.md` | Release history in Keep a Changelog format |
| `docs/client_setup.md` | Installing and configuring the Python client and its virtual environment |
| `docs/cpp_client.md` | The native C++ client library, API surface and build |
| `docs/command_line_switches.md` | Unreal and Project AirSim command-line switches, plus `PROJECTAIRSIM_CLIENT_AUTH_PUBKEY` |
| `docs/config.md` | The two-level JSONC configuration model and the `sim_config/` layout |
| `docs/config_scene.md` | Every scene config key, actors, four clock types, home geo point, segmentation |
| `docs/config_robot.md` | Every robot config key, physics type, links, joints, controllers for Simple Flight, PX4 and Manual, actuators, sensor preamble. No ArduPilot section. |
| `docs/faq.md` | Supported vehicle types, log file locations, general troubleshooting |
| `docs/gis_scenes.md` | Configuring geospecific GIS scenes and tile directories |
| `docs/license.md` | The MIT licence text |
| `docs/modify_drone_physical.md` | Changing geometry through link origins and inertial blocks |
| `docs/modify_drone_visual.md` | Changing appearance through the visual mesh reference |
| `docs/multiple_robots.md` | Several robots, possibly of different physics types, in one scene |
| `docs/system_specs.md` | Hardware and software specifications, largely inherited from Unreal |
| `docs/transition_from_airsim.md` | Migration from the original Microsoft AirSim, with an API equivalence table |
| `docs/use_plugin.md` | Dropping the plugin into a custom Unreal environment, GameMode, cooking directives |
| `docs/autonomy/autonomy.md` | The autonomy module, pre-trained models, sample applications |
| `docs/autonomy/setup.md` | Autonomy runtime and dependency setup |
| `docs/autonomy/gym/gym_envs.md` | OpenAI Gym compatible reinforcement-learning environments |
| `docs/controllers/controllers.md` | Flight controller overview and comparison chart. Names only Simple Flight, PX4, Manual. |
| `docs/controllers/simple_flight.md` | The built-in controller, its airframes and RC setup |
| `docs/controllers/px4/px4.md` | PX4 overview and supported versions |
| `docs/controllers/px4/px4_build.md` | Building PX4 from source |
| `docs/controllers/px4/px4_sitl.md` | PX4 software-in-the-loop |
| `docs/controllers/px4/px4_sitl_wsl2.md` | PX4 SITL under WSL 2 |
| `docs/controllers/px4/px4_hitl.md` | PX4 hardware-in-the-loop |
| `docs/controllers/px4/px4_lockstep.md` | PX4 lockstep, `lock-step` and `use-tcp` |
| `docs/controllers/px4/px4_multi_vehicle.md` | Multiple PX4 SITL instances on TCP ports from 4560 |
| `docs/datacollection/api.md` | The data generation module API |
| `docs/datacollection/config.md` | The data collection configuration file |
| `docs/datacollection/data_generation.md` | Components of a data generation run |
| `docs/datacollection/data_aggregation.md` | Aggregating output into COCO JSON and other formats |
| `docs/datacollection/trajectory.md` | Trajectory generation and waypoint types |
| `docs/datacollection/randomizations.md` | Object-level randomisation |
| `docs/datacollection/augmentations.md` | Image-level augmentation |
| `docs/datacollection/azure.md` | Running data generation on Azure Kubernetes |
| `docs/development/dev_setup_linux.md` | Linux developer setup, Unreal toolchain, Clang 20.1.x |
| `docs/development/dev_setup_win.md` | Windows setup for VS 2022 and VS Code |
| `docs/development/use_prebuilt.md` | Downloading and running pre-built binary environments |
| `docs/development/use_source.md` | Building from source, including MSVC version pinning |
| `docs/development/headless_cloud.md` | Headless Docker with `-RenderOffScreen` and `-nullrhi` |
| `docs/development/vscode_user_settings.md` | Optional VS Code user settings |
| `docs/development/scene/sim_clock_internal.md` | Internal view of the clock, including the engine-driven host contract |
| `docs/development/sensors/display.md` | Matplotlib sensor visualisation helpers |
| `docs/physics/fast_physics.md` | The Fast Physics rigid-body and aerodynamic model |
| `docs/physics/matlab_physics.md` | Importing a Simulink physics model over TCP |
| `docs/ros/ros.md` | The Python ROS 1 bridge. Its topic tables use a stale `/airsim_node/...` naming the code does not produce. |
| `docs/ros/ros2.md` | The ROS 2 C++ bridge, parameters, topics, services, actions. Current. |
| `docs/scene/sim_clock.md` | User-facing description of the four clock types |
| `docs/scene/weather_visual_effects.md` | Weather effects and the F10 GUI |
| `docs/sensors/camera_capture_settings.md` | Every camera capture parameter |
| `docs/sensors/camera_streaming.md` | High-resolution video through PixelStreaming |
| `docs/sensors/camera_post_processing_with_nn.md` | Running ONNX models on camera output inside the sim |
| `docs/sensors/lidar.md` | Lidar scan patterns, detections, settings |
| `docs/sensors/radar.md` | Radar beam model, detections, tracks, masks |
| `docs/sensors/battery.md` | Battery sensor modes and APIs |
| `docs/sensors/segmentation.md` | Segmentation ids, palette, editor assignment |
| `docs_external/README.md` | External-facing product introduction, marked non-public under NDA |
| `docs_external/eap_quickstart.md` | Early Access Program package contents and quick start |
| `docs_includes/`, `docs_test/` | Sphinx include fragments, internal-section toggles, preprocessor smoke test |

Documents referenced but absent. `docs/sensors/imu.md`, referenced at `core_sim/include/core_sim/sensors/imu.hpp:30`. Any ArduPilot guide, referenced at `project-airsim-quad.param:3` and `project-airsim-hexa.param:3`. Airspeed, Barometer, GPS, IMU and Magnetometer settings pages, listed as plain text at `docs/config_robot.md:680-685`.

---

## G. Consolidated defect and disagreement register

| Id | Class | Where | Statement | Authority |
|---|---|---|---|---|
| G1 | Docs contradict code | `docs/controllers/controllers.md:5`, `docs/config_robot.md:326` versus `simserver/src/simserver.cpp:299-301` | ArduPilot is supported. The docs say it is not. | Code |
| G2 | Code bug | `arducopter_api.cpp:75-76` versus `robot_config_schema.jsonc:547` | `use-sensor-distance` is read, `use-distance-sensor` is written. Distance sensor data never reaches ArduPilot. | Schema and configs are the intended spelling |
| G3 | Precision loss | `core_sim/src/message/gps_message.cpp:42-43` | GPS latitude and longitude stored as `float`, against `double` in `GeoPoint` at `core_sim/include/core_sim/earth_utils.hpp:22-23`. Quantisation is 0.21 m north and 0.69 m east at the workspace home location, refined 2026-08-03, see §A.14 | Defect |
| G4 | Naming bug | `core_sim/src/sensors/gps.cpp:222-223` | `time_utc_millis` holds microseconds, because nanoseconds are divided by 1.0e3 | Defect |
| G5 | Liveness | `arducopter_api.cpp:204-215` | Unbounded blocking receive freezes the whole simulation if ArduPilot is absent | Defect, and the likely cause of the crash report in issue 21 |
| G6 | Topic collision | `core_sim/src/sensors/camera.cpp:452-456` | The disparity-normalized camera-info topic reuses the image topic path instead of appending `_info` | Defect |
| G7 | Docs contradict code | `docs/config_scene.md:77` versus `core_sim/include/core_sim/clock.hpp:37` | `step-ns` default is 3 ms, not 20 ms | Code |
| G8 | Schema narrower than code | `robot_config_schema.jsonc:10` versus `core_sim/src/actor/robot.cpp:1407` | `unreal-physics` is supported and documented but rejected by the schema | Code |
| G9 | Version disagreement | `README.md:92` says 5.2 and 5.7, `Blocks.uproject` says 5.1, `UnrealSimLoader.h:88-89` says 5.1 | Three statements of the supported Unreal version | README, the others are stale |
| G10 | Docs stale | `docs/ros/ros.md:76-120` | Documents `/airsim_node/<robot>/...` names. The Python bridge reuses the native path verbatim per `topic_helpers.py:629-630`. | Code |
| G11 | Broken example | `client/python/example_user_scripts/sim_config/scene_quadrotor_ardupilot.jsonc:11` | References `robot_quadrotor_ardupilot.jsonc`, which does not exist | Defect |
| G12 | Missing timestamp propagation | `ros/projectairsim_ros2_cpp/src/projectairsim_ros2_cpp_node.cpp:108-114` | The bridge discards the sim-time `time_stamp` present in every payload and restamps with the node clock. Patched locally 2026-08-03 by a three-argument `MakeHeader` overload, see §C and [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md) | Defect, and the highest-value patch for the NRT stack |
| G13 | Doc key stale | `docs/use_plugin.md` uses `"ref"` for the actor robot reference | The current key is `robot-config`, per `scene_config_schema.jsonc:85` and all fifty two example scenes | Schema and examples |
| G14 | Key mismatch | `core_sim/src/message/gps_message.cpp:109` versus `core_sim/include/core_sim/json_utils.hpp:217` | `getData` writes `time_utc_millis` while `from_json` reads `j.at("time_utc_milli")`, so reconstructing a `GpsMessage` from its own JSON throws `nlohmann::json::out_of_range`. Latent, since nothing in the tree currently round trips it. Found 2026-08-03 | Defect |
| G15 | Liveness | `client/cpp/ProjectAirsimClientLib/src/Client.cpp:275-279`, `:462-467` and `:826-840` | The services socket sets `NNG_OPT_RECVTIMEO` to 300000 ms with `NNG_OPT_REQ_RESENDTIME` disabled, and `ResponseReceivingThreadProc`'s `NNG_ETIMEDOUT` branch (`:832-835`) does `continue` back into another `nng_recv()` rather than ever calling `SetDone()`, so a request whose response is lost blocks the calling thread forever, not for five minutes, since the 300 s figure is only the period between silent, unlogged retries rather than a bound on the wait. `Client::Impl::Request()`'s underlying `Wait()` (`AsyncResultInternal.h:54-60`) has no timeout parameter of its own either, so nothing upstream of this loop can time-bound it. Because the ROS 2 bridge calls from its single executor thread, one lost response freezes every bridge service and action indefinitely while the sensor streams continue normally, since those are delivered by the client SDK's own topic thread rather than through this request path. Present at any clock period. Confirmed as unbounded, not five-minute, by a live reproduction on the `GetSimTime` call from `PublishClock` that never recovered across a session exceeding several multiples of 300 s (2026-08-20), full trace in [`project-airsim-clock-publication-bug.md`](project-airsim-clock-publication-bug.md). Found 2026-08-03, corrected 2026-08-20 | Defect. An unbounded stall, not a five-minute one and not a deadlock |
| G16 | Silent build defect | `CMakeLists.txt:386` | `INSTALL_BYPRODUCTS` on the `openssl-external` `ExternalProject_Add` requires CMake 3.26, silently ignored by older CMake rather than erroring, dropping the Ninja dependency edge on OpenSSL's static libraries and exposing consumers to a link race. Worked around image-side by installing CMake from PyPI rather than apt, see [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §14. Found 2026-08-05 | Defect, image-side workaround only |
