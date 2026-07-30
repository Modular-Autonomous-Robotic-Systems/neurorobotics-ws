# Time synchronisation across AirSim, ArduPilot SITL and ROS 2

Audited 2026-07-27. This file records how every clock in the SITL stack is constructed, which timestamp reaches which message field, and which of the available synchronisation mechanisms actually work. It spans three trees, `sitl_ws/src/ue5/AirSim` (Cosys-AirSim), `ardu_ws/src/ardupilot` (ArduPilot master) and `ros_ws/src` (the NRT ROS 2 packages), which is why it lives in the workspace-level `context/` rather than in any one of them.

Related, [`airsim.md`](airsim.md) for the AirSim and SITL data path, [`ardupilot-dds-qos.md`](ardupilot-dds-qos.md) for per-topic `/ap/*` publisher QoS, and [`../ros_ws/context/launch-and-djinn.md`](../ros_ws/context/launch-and-djinn.md) for the launch graph these clocks are configured from.

## The short version

There are two clocks in this stack and they share a rate but not an origin. AirSim stamps every sensor message and every image with its own `SteppableClock`, which is anchored to wall clock once at construction and thereafter advances only in fixed steps. ArduPilot stamps every DDS message with `AP::rtc().get_utc_usec()`, which is `AP_HAL::micros64()` plus a shift derived from the simulated GPS, whose epoch is wall clock at SITL process start. Both then advance by the same AirSim timestamp deltas, so the difference between them is a constant equal to the wall clock gap between the two anchors, which in a normal `djinn start sitl` run is several seconds.

The mechanism that removes the offset already exists on both sides and is simply not connected. ArduPilot master compiles a `/clock` DataReader in SITL builds and overrides every DDS stamp with it, and the Cosys-AirSim bridge can publish the simulator clock, but it publishes it on `~/clock` rather than the global `/clock`, and the option is off by default.

## AirSim, where sensor and image timestamps come from

Every message the bridge publishes copies a simulator timestamp field verbatim into the ROS header. There is no offset, no rebasing and no conversion anywhere in the bridge, which was verified by grepping for the PX4-fork idioms `first_imu_ros_ts`, `airsim_timestamp_to_ros` and `chrono_timestamp_to_ros`, none of which exist in Cosys-AirSim.

| Stream | Assignment | File |
|---|---|---|
| Camera image | `img_msg_ptr->header.stamp = rclcpp::Time(img_response.time_stamp)` | `ros2/src/airsim_ros_pkgs/src/airsim_ros_wrapper.cpp:1857` |
| Depth image | `depth_img_msg->header.stamp = rclcpp::Time(img_response.time_stamp)` | `airsim_ros_wrapper.cpp:1881` |
| `CameraInfo` | `rclcpp::Time(curr_img_response.time_stamp)` | `airsim_ros_wrapper.cpp:1919` |
| IMU | `rclcpp::Time(imu_data.time_stamp)` | `airsim_ros_wrapper.cpp:1212` |
| GPS, magnetometer, altimeter, distance, lidar, echo | same pattern | `airsim_ros_wrapper.cpp:1124`, `:1115`, `:1198`, `:1139`, `:853`, `:965` |
| Odometry and environment | vehicle state `timestamp` | `airsim_ros_wrapper.cpp:1399`, `:1447` |

Two members of the same file are exceptions and are stamped with wall clock instead, the dynamic vehicle transform at `airsim_ros_wrapper.cpp:1632` and the fallback return of `update_state()` at `:1372` and `:1435`. The bridge is therefore internally inconsistent already, although nothing in the NRT stack consumes the dynamic vehicle transform.

The image field itself is filled inside Unreal at GPU readback rather than at scene capture, `results_[i]->time_stamp = msr::airlib::ClockFactory::get()->nowNanos()` at `Unreal/Plugins/AirSim/Source/RenderRequest.cpp:180`, copied into the RPC response at `UnrealImageCapture.cpp:130`. The IMU field is filled the same way at `AirLib/include/sensors/imu/ImuSimple.hpp:72`. Both therefore read the same `ClockFactory` singleton, which is why AirSim's own streams are mutually consistent and only disagree with ArduPilot.

### Which clock the factory holds

`AirSimSettings::loadClockSettings` at `AirLib/include/common/AirSimSettings.hpp:1540-1566` reads `ClockType` from `settings.json`, defaults it to `ScalableClock`, then overrides it to `SteppableClock` whenever the sim mode is multirotor, reverting to `ScalableClock` only if an auto-created vehicle is of type PX4. `kVehicleTypeArduCopter` is a separate constant at `AirSimSettings.hpp:32` and is not covered by that exception, so an ArduCopter multirotor gets a `SteppableClock` even without an explicit setting. The active settings file, `Unreal/Environments/settings.json`, sets `"ClockType": "SteppableClock"` and `"ClockSpeed": 1.0` explicitly, so the default logic is moot.

`SteppableClock` at `AirLib/include/common/SteppableClock.hpp:25-28` sets `start_ = current_ = start ? start : Utils::getTimeSinceEpochNanos()`, and `nowNanos()` at `:50-53` merely returns the accumulator. It is advanced by `ClockFactory::get()->step()` once per physics tick from `World::update()` at `AirLib/include/physics/World.hpp:45`, with a period of 3 ms set by `physics_loop_period_ = 3000000LL` at `Unreal/Plugins/AirSim/Source/SimMode/SimModeWorldBase.h:75`. The consequence that matters is that this clock is anchored to wall clock exactly once, at construction, and never resynchronises afterwards, so it falls behind wall clock by however much the physics thread under-runs 333 Hz.

`ScalableClock` by contrast returns `Utils::getTimeSinceEpochNanos()` directly when unscaled, at `AirLib/include/common/ScalableClock.hpp:31-33`, and therefore tracks wall clock.

The ArduCopter firmware path in AirSim gates the physics loop on ArduPilot, because `ArduCopterApi::update()` at `AirLib/include/vehicles/multirotor/firmwares/arducopter/ArduCopterApi.hpp:59-64` calls `sendSensors()` then blocks in `recvRotorControl()` at `:479-495` waiting for PWM. The packet it sends carries `"timestamp": ClockFactory::get()->nowNanos() / 1000` at `:346`, which is the same steppable clock. The `"LockStep": true` key in `settings.json` is inert on this path, confirmed by the absence of any `lock_step` reference under `firmwares/arducopter/`, matching the note already recorded in [`airsim.md`](airsim.md).

### Publishing the clock

The bridge can publish the simulator clock but does not by default.

| Aspect | Value | Anchor |
|---|---|---|
| Parameter | `publish_clock`, default `false` | `airsim_ros_wrapper.cpp:131`, default at `:52` |
| Launch default | `'False'` | `launch/airsim_node.launch.py:18-20` |
| Topic | `"~/clock"`, resolving to `/airsim_node/clock` | `airsim_ros_wrapper.cpp:411-413`, node name at `src/airsim_node.cpp:9` |
| Publisher QoS | `create_publisher(..., 1)`, so RELIABLE, VOLATILE, KEEP_LAST depth 1 | `airsim_ros_wrapper.cpp:411` |
| Published from | `drone_state_timer_cb`, a wall timer at `update_airsim_control_every_n_sec` of 0.01 s | `airsim_ros_wrapper.cpp:1343-1345`, timer at `:141` |
| Value | `update_state()`, which returns the first vehicle's state timestamp | `airsim_ros_wrapper.cpp:1335-1341`, `:1389-1397` |
| Pause behaviour | while `simIsPaused()` the last value is republished rather than the topic going silent | `airsim_ros_wrapper.cpp:1338` |

The private namespace is the load-bearing defect. ROS 2 sim time only ever reads the global `/clock`, so out of the box no consumer can see AirSim's clock even with `publish_clock` enabled. A comment at `airsim_ros_wrapper.cpp:1337` says `/clock` while the code two lines below says `~/clock`, and the same mistake exists in the Microsoft ROS 1 wrapper.

The value is valid on the ArduCopter path despite the stubbed API. `MultirotorApiBase::getMultirotorState()` at `AirLib/include/vehicles/multirotor/api/MultirotorApiBase.hpp:134-140` sets `state.timestamp = clock()->nowNanos()` unconditionally, and the ArduCopter overrides that log `Not Implemented` at `ArduCopterApi.hpp:133-170` cover only the kinematics getters, which return defaults rather than throwing.

## ArduPilot, where DDS timestamps come from

Every published `/ap/*` header funnels through one function, `AP_DDS_Client::update_topic(builtin_interfaces_msg_Time&)` at `libraries/AP_DDS/AP_DDS_Client.cpp:213-231`, whose precedence is the external `/clock` first, then `AP::rtc().get_utc_usec()`, then a bare `AP_HAL::micros64()`.

```cpp
#if AP_DDS_CLOCK_SUB_ENABLED
    if (has_received_clock) {
        msg.sec = external_clock_time.sec;
        msg.nanosec = external_clock_time.nanosec;
        return;
    }
#endif
    uint64_t utc_usec;
    if (!AP::rtc().get_utc_usec(utc_usec)) {
        utc_usec = AP_HAL::micros64();
    }
```

`/ap/imu/experimental/data` reaches it at `AP_DDS_Client.cpp:670`, `/ap/clock` at `:705-708` and `/ap/time` at `:1874-1880`, so `/ap/clock` is a byte-identical echo of the same value and never a second, independent clock.

### The SITL clock is already simulated and already stepped by AirSim

`AP_HAL::micros64()` at `libraries/AP_HAL_SITL/system.cpp:163-174` returns `Scheduler::stopped_clock_usec()` whenever it is non-zero, and SITL primes it to 1 at `libraries/AP_HAL_SITL/SITL_State.cpp:82-83` and then overwrites it every physics step at `:273-274` with `_sitl->state.timestamp_us`. The stopped-clock branch is therefore always taken and ArduPilot's monotonic clock under SITL is a fully simulated clock starting near zero.

For the AirSim backend that clock is advanced by AirSim's own deltas, at `libraries/SITL/SIM_AirSim.cpp:323-325`.

```cpp
if (last_timestamp) {
    int deltat = state.timestamp - last_timestamp;
    time_now_us += deltat;
```

Only the delta transfers, never the absolute value, because `time_now_us` is ArduPilot's own accumulator declared at `libraries/SITL/SIM_Aircraft.h:269` and started at zero. This is the structural origin of the offset. The two clocks are rate-locked and origin-independent.

The UTC shift that turns that into an epoch timestamp comes from the simulated GPS. `SIM_GPS.cpp:269-283` seeds its first sample with `AP::sitl()->start_time_UTC`, which defaults to `gettimeofday()` at SITL process start at `libraries/AP_HAL_SITL/SITL_cmdline.cpp:267-271`, and `AP_GPS.cpp:984-991` feeds that to `AP_RTC` as `SOURCE_GPS`. `AP_RTC::get_utc_usec` at `libraries/AP_RTC/AP_RTC.cpp:106-113` then returns `AP_HAL::micros64() + rtc_shift`.

### The `/clock` subscriber, present in master only

| Item | Value | Anchor |
|---|---|---|
| Compile gate | `AP_DDS_CLOCK_SUB_ENABLED` defined as `(CONFIG_HAL_BOARD == HAL_BOARD_SITL)`, so enabled in every SITL build | `libraries/AP_DDS/AP_DDS_config.h:121-123` |
| Topic | the absolute name `"/clock"`, not `/ap/clock` | `libraries/AP_DDS/AP_DDS_Topic_Table.h:303-320` |
| Reader QoS | VOLATILE, RELIABLE, KEEP_LAST depth 5 | same entry |
| Callback | sets `external_clock_time` and latches `has_received_clock = true` | `AP_DDS_Client.cpp:1548-1560` |
| Runtime gate | subscription skipped unless `sitl->use_dds_sim_time` | `AP_DDS_Client.cpp:1542-1549` |
| Flag | `--use_sim_time <true\|false>`, underscore spelling despite the README saying hyphens | `libraries/AP_HAL_SITL/SITL_cmdline.cpp:319`, `:569-575` |
| Launch default | `use_sim_time` declared with `default_value="True"` and passed unconditionally | `Tools/ros2/ardupilot_sitl/src/ardupilot_sitl/launch.py:663-668`, `:426` |

Presence in the built binary was confirmed directly, `strings /ws/ardu_ws/install/ardupilot_sitl/bin/arducopter` contains `Using \clock topic for DDS timing: %s` and `%s Skipping subscription to /clock because use_sim_time is false`.

Three properties of this mechanism are traps worth stating plainly.

It is a stamp override and not clock disciplining. `micros64()`, the scheduler, the EKF and every internal deadline are untouched, and only the value written into DDS headers changes.

It quantises every `/ap/*` stamp to the `/clock` publication interval, because `external_clock_time` is copied verbatim and changes only when a sample arrives. Any `/ap/*` topic published faster than `/clock` emits runs of identical timestamps. Measured at 24 identical stamps in a row on `/ap/imu/experimental/data`, see the live-stack section above.

`has_received_clock` latches and never expires, at `AP_DDS_Client.cpp:1554`. If the `/clock` publisher stops, every `/ap/*` stamp freezes at the last received value rather than falling back to the RTC.

The reader is RELIABLE, so a `/clock` publisher offering BEST_EFFORT will not match it. The idiomatic `rclcpp::ClockQoS()` used by `rclcpp::TimeSource` for its own `/clock` subscription is BEST_EFFORT, which means a publisher tuned only for ROS consumers can silently fail to reach ArduPilot. The Cosys-AirSim publisher is RELIABLE by default and therefore satisfies both.

Version applicability matters here. The subscriber is absent from Copter-4.5, ArduPilot-4.6 and ArduPilot-4.7, which publish `/ap/clock` but cannot consume `/clock`. This workspace tracks ArduPilot master, where it is present.

### Why the MAVLink route cannot work

`SYSTEM_TIME` is handled at `libraries/GCS_MAVLink/GCS_Common.cpp:3915-3923` by a single call to `AP::rtc().set_utc_usec(packet.time_unix_usec, AP_RTC::SOURCE_MAVLINK_SYSTEM_TIME)`. That moves `rtc_shift` and nothing else, so the monotonic clock that paces the simulation is untouched. It is further blocked three ways. The source priority enum at `libraries/AP_RTC/AP_RTC.h:22-30` ranks `SOURCE_GPS = 0` above `SOURCE_MAVLINK_SYSTEM_TIME = 1`, and `set_utc_usec` rejects a lower-priority source once a higher one has claimed the slot at `AP_RTC.cpp:51-63`. `BRD_RTC_TYPES` defaults to 1, meaning GPS only, at `AP_RTC.cpp:29-35`, so the MAVLink source is filtered out at `:66-68`. The shift may never decrease, at `:75-81`.

`TIMESYNC` is handled at `GCS_Common.cpp:3773-3829` and is a pure ping responder and round-trip logger. It writes a `TSYN` log record and adjusts no clock at all. ArduPilot has no mechanism anywhere to slew or step its monotonic boot clock from an external time source.

The decisive point is that all of this is upstream of a branch that never executes once `/clock` is connected, because `update_topic` returns before consulting the RTC.

### `--synthetic-clock` is a no-op

The option table at `libraries/AP_HAL_SITL/SITL_cmdline.cpp:331` carries the comment `kept to warn that it's always enabled`, and the handler at `:455-456` prints `Ignoring obsolete command-line parameter '-S'/'--synthetic-clock'. Synthetic clock mode is now always enabled.` The `synthetic_clock` launch argument at `Tools/ros2/ardupilot_sitl/src/ardupilot_sitl/launch.py:600-605` still exists and still appends the flag at `:435-438`, and upstream ArduPilot documentation and `ardupilot_gz` both still pass it, so it is harmless to keep and equally harmless to drop.

## Measured against a live stack, 2026-07-28

A `djinn start sitl` plus `djinn start sitl basalt` run with `use-sim-time:=True` was captured on both sides. The wiring works and the epoch offset is gone. Two separate defects that the epoch offset had been masking are now the binding constraints, and neither is a clock synchronisation problem.

Confirmation that the mechanism is live, in order of strength.

ArduPilot prints `Using \clock topic for DDS timing: enabled` at startup, the message emitted at `libraries/AP_HAL_SITL/SITL_State.cpp:78` when `_use_dds_sim_time` is true, so the DataReader was created rather than skipped.

`/ap/imu/experimental/data` stamps are now held between `/clock` receipts. Over a 1.851 s window, 302 inertial messages carried only 27 distinct timestamps, in runs of up to 24 identical values. This is only possible on the external-clock branch. On the real time clock path the stamp is `micros64() + rtc_shift` and `micros64()` advances every 3 ms physics tick, so a 162 Hz publisher would have produced hundreds of distinct values, not 27.

The offset collapsed. The inertial lead over the camera fell from 6.13 s to 1.62 s, and the residual has a different character, described next.

### Residual one, the AirSim image delivery lag

Fitting the inertial lead against elapsed time over 24 frames gives

```
lead = 1.624 s + 0.156 * elapsed
```

Both terms are properties of the image path alone. Because `/ap/*` stamps are now the most recent `/clock` value, which is simulator now, the lead is simply how old each image header stamp is relative to simulator now. It is a delivery latency, not a clock domain difference. The slope says the image path is falling further behind at fifteen percent of elapsed time, which is a growing backlog between capture and publication rather than a rate mismatch between two clocks, since a merely slow renderer would produce sparser but current stamps.

The measured throughput shortfall is consistent. `img_response_timer_cb` is a wall timer at `update_airsim_img_response_every_n_sec` of 0.05 s, nominally 20 Hz, and achieved 15.7 Hz. `drone_state_timer_cb` is a wall timer at `update_airsim_control_every_n_sec` of 0.01 s, nominally 100 Hz, and achieved 14.05 Hz. Both defaults are set at `ros2/src/airsim_ros_pkgs/launch/airsim_node.launch.py:49-50`. Callback group contention is not the explanation, `src/airsim_node.cpp:22-26` creates a Reentrant group under a `MultiThreadedExecutor`, so the cause is the blocking RPC round trip into the simulator, which `drone_state_timer_cb` performs once per sensor per iteration through `publish_vehicle_state()` at `airsim_ros_wrapper.cpp:1459-1500`.

### Residual two, inertial stamp quantisation

This one was not anticipated and it invalidates a claim made earlier in this file, that the stamp override is harmless in simulation because the simulator clock is quantised at the physics step anyway. The binding quantum is not the 3 ms physics step. It is the `/clock` publication interval, because `AP_DDS_Client::update_topic` copies `external_clock_time` verbatim and that variable only changes when a `/clock` sample arrives.

At the measured 14.05 Hz clock rate against a 162 Hz inertial publisher, that is a mean of eleven inertial samples per distinct timestamp and a worst case of twenty four, with a mean stamp interval of 71 ms. Basalt's preintegration sees a run of samples with `dt = 0` followed by one 71 ms jump. This is fatal to visual inertial fusion whatever the offset is, so removing the epoch difference is necessary but not sufficient.

Even at the nominal 100 Hz the quantum would be 10 ms against a 162 Hz publisher, which is still coarser than the sample interval. The conclusion is that `/ap/imu/experimental/data` under `use_sim_time` is a telemetry stream, not a visual inertial odometry input, for the same structural reason given for hardware later in this file, the stamp is applied at DDS publish time rather than at sample time.

Substituting AirSim's own inertial topic does not by itself solve this. `/airsim_node/Copter/imu/Imu` is published from `publish_vehicle_state()` inside `drone_state_timer_cb` at `airsim_ros_wrapper.cpp:1490-1495`, so it is emitted at the same 14 Hz the clock is, and carries `imu_data.time_stamp` from the sensor rather than a held clock value. It has the correct per-sample timestamp and the wrong rate.

### What the run does not settle

`ros2 param get` was not run, so whether `use_sim_time` reached `basalt_slam_node` and `managed_logger_node` is unconfirmed. Note that `rclcpp` log line timestamps are always system time regardless of the parameter, so the log prefixes carry no information about it either way. Basalt reads header stamps and is unaffected by the parameter, so this does not bear on the offset measurement.

## The full ArduPilot time architecture, SITL against real hardware

Audited 2026-07-28. Everything above concerns SITL. The same code paths behave differently on a real flight controller, and the differences decide what a HITL or hardware deployment can and cannot do.

### The two layers, monotonic and UTC

ArduPilot keeps exactly two notions of time and nothing else. The lower layer is `AP_HAL::micros64()`, a monotonic counter, and the upper layer is `AP_RTC`, which holds a single signed `rtc_shift` such that UTC equals `micros64() + rtc_shift`. Every DDS stamp is drawn from one of the two, or from the external `/clock` when that is connected.

| Layer | SITL | Real hardware |
|---|---|---|
| `micros64()` | `Scheduler::stopped_clock_usec()` when non-zero, which it always is after `SITL_State.cpp:82-83` primes it to 1, thereafter overwritten every physics step at `:273-274` with the flight dynamics model timestamp | `clock_gettime(CLOCK_MONOTONIC)` minus process start on Linux boards, a hardware timer on ChibiOS. Boot-relative, free-running, never settable |
| Origin of `micros64()` | 1 µs, then advanced by AirSim deltas at `SIM_AirSim.cpp:323-325` | zero at board power-on |
| `rtc_shift` | set from the simulated GPS, whose epoch is `AP::sitl()->start_time_UTC`, defaulting to `gettimeofday()` at process start, `SITL_cmdline.cpp:267-271` | set from a real GPS 3D fix, from MAVLink `SYSTEM_TIME`, or from the board's hardware RTC |
| `/clock` DataReader | compiled in and armed by `--use_sim_time` | not compiled in, see below |

The single fact that governs every option below is that no code path anywhere in ArduPilot writes `micros64()`. `AP_RTC::set_utc_usec` moves only the shift, at `AP_RTC.cpp:47-101`, and it is constrained three ways, it refuses a source ranked worse than the one already in use, `AP_RTC.h:22-30` ordering `SOURCE_GPS = 0` above `SOURCE_MAVLINK_SYSTEM_TIME = 1` above `SOURCE_HW = 2`, it refuses any source whose bit is clear in `BRD_RTC_TYPES` which defaults to 1, and it refuses to let the shift ever decrease, `if (tmp < rtc_shift) return`. UTC in ArduPilot is therefore a monotone, coarsely stepped, one-way quantity.

### Flow chart, how a `/ap/*` stamp is produced

```
AP_DDS_Client::update_topic(builtin_interfaces_msg_Time&)   AP_DDS_Client.cpp:213-231
   |
   +-- #if AP_DDS_CLOCK_SUB_ENABLED   ... AP_DDS_config.h:121-123
   |      = (CONFIG_HAL_BOARD == HAL_BOARD_SITL) unless overridden by a build define
   |   and has_received_clock (latched true by the /clock callback, AP_DDS_Client.cpp:908-919)
   |      -> return external_clock_time                      [SITL with use-sim-time:=True]
   |
   +-- AP::rtc().get_utc_usec(utc_usec)                      AP_RTC.cpp:103-113
   |      returns micros64() + rtc_shift, false while rtc_source_type == SOURCE_NONE
   |      -> return that                                     [hardware with a time source]
   |
   +-- fallback: utc_usec = AP_HAL::micros64()
          -> return boot-relative microseconds               [hardware with no time source]
```

### Flow chart, how `rtc_shift` is established

```
GPS 3D fix ---- AP_GPS::update_instance()          AP_GPS.cpp:983-991
                  time_epoch_usec(instance)
                    (SITL: SIM_GPS.cpp:269-283 seeds from AP::sitl()->start_time_UTC,
                     itself gettimeofday() at process start, SITL_cmdline.cpp:267-271,
                     overridable with --start-time <unix seconds>, SITL_cmdline.cpp:537)
                  -> set_utc_usec(now, SOURCE_GPS)      priority 0, BRD_RTC_TYPES bit 0
                                                             |
MAVLink SYSTEM_TIME - GCS_Common.cpp:3915-3923               |
                  -> set_utc_usec(t, SOURCE_MAVLINK_SYSTEM_TIME)  priority 1, bit 1
                                                             |
Board hardware RTC - AP_BoardConfig.cpp:504                  |
                  -> set_utc_usec(hw, SOURCE_HW)        priority 2, bit 2
                                                             v
                                          AP_RTC::set_utc_usec   AP_RTC.cpp:47-101
                                            reject if type worse than rtc_source_type
                                            reject if bit clear in BRD_RTC_TYPES (default 1)
                                            reject if before 2022-01-01
                                            reject if tmp < rtc_shift (never goes backwards)
                                            -> rtc_shift = t - micros64()
```

### Why the `/clock` reader is a SITL-only facility

`AP_DDS_CLOCK_SUB_ENABLED` is defined at `AP_DDS_config.h:121-123` as `(CONFIG_HAL_BOARD == HAL_BOARD_SITL)`, inside an `#ifndef`, so a board could in principle force it on with a build define. That is not sufficient to make it usable on hardware, for two reasons that are visible in the same tree.

The runtime opt-out is itself guarded by `#if AP_DDS_CLOCK_SUB_ENABLED && CONFIG_HAL_BOARD == HAL_BOARD_SITL` at `AP_DDS_Client.cpp:1542-1549`, and that second condition is not overridable. On a hardware board with the macro forced on, the skip branch is compiled out entirely, so the `/clock` DataReader would be created unconditionally with no flag able to disable it.

More importantly the mechanism is semantically wrong off the simulator. It replaces the sample time of a measurement with the value of a clock sampled at DDS serialisation time, so every `/ap/*` stamp would absorb the scheduler phase and the whole of the serial or network link latency between companion and autopilot, and would lose the sub-sample resolution the IMU actually has. In simulation that is harmless because the simulator clock is quantised at the physics step anyway. On hardware it converts a good timestamp into a bad one.

### What the vendored micro-XRCE-DDS client already offers and ArduPilot does not use

`modules/Micro-XRCE-DDS-Client/include/uxr/client/core/session/session.h:528-552` declares `uxr_sync_session(session, timeout)`, `uxr_epoch_millis(session)` and `uxr_epoch_nanos(session)`. The eProsima documentation describes this as an NTP-style exchange between client and agent from which the client computes its offset, intended precisely for embedded targets with no other time source. Grepping `libraries/AP_DDS` for `uxr_sync_session` and `uxr_epoch` returns nothing, so ArduPilot links the capability and never calls it. This is the only mechanism in the stack that would give a latency-compensated, round-trip-derived offset over the existing DDS transport, and adopting it would be an upstream ArduPilot change rather than a workspace one.

### The hardware and HITL options, ranked

| Option | Mechanism | Accuracy | Verdict |
|---|---|---|---|
| Common UTC reference | ArduPilot takes UTC from its own GPS with the default `BRD_RTC_TYPES=1`, and the companion's system clock is disciplined to the same UTC by chrony against GPS/PPS, NTP or PTP | sub-millisecond with PPS, tens of milliseconds with plain NTP | Correct for outdoor hardware. No ROS-level plumbing, no `/clock`, no `use_sim_time` anywhere |
| MAVLink `SYSTEM_TIME` | companion sends `SYSTEM_TIME`, ArduPilot sets `rtc_shift` from it. Requires `BRD_RTC_TYPES=2` so that the GPS does not claim the higher-priority slot first. The mavros `sys_time` plugin implements the companion side with `system_time_rate: 1.0` | tens of milliseconds, one-way and uncompensated, quantised by the 1 Hz send rate | The correct fallback for indoor or GPS-denied hardware, and the case the ArduPilot wiki's `BRD_RTC_TYPES=2` recommendation is written for |
| MAVLink `TIMESYNC` | round-trip exchange, `timesync_rate: 10.0` in mavros | mavros rejects samples with round-trip above 10 ms | Moves the companion's estimate of the offset only. ArduPilot's handler at `GCS_Common.cpp:3773-3829` is a pure responder that writes a `TSYN` log record and adjusts no clock |
| DDS `/clock` override | force `AP_DDS_CLOCK_SUB_ENABLED` on for a hardware board | link latency enters every stamp | Rejected, see above |
| `uxr_sync_session` | NTP-style handshake over the existing uXRCE-DDS session | round-trip compensated | The principled answer, unimplemented upstream |

The practical consequence for this workspace is that the SITL fix and the hardware fix are different mechanisms answering different questions, and neither generalises to the other. In SITL the question is which of two simulated origins wins, and the answer is that the simulator's clock is authoritative and ArduPilot adopts it wholesale. On hardware the question is how two free-running physical oscillators are related, and the answer is that both must be referred to a common external standard, because neither can be set from the other without destroying the timestamp quality that visual inertial fusion depends on.

A further consequence for visual inertial odometry specifically. Even a perfectly disciplined pair of clocks does not make `/ap/imu/experimental/data` a suitable VIO input on hardware, because the stamp is applied at DDS publish time rather than at sample time and the link introduces jitter of the same order as the inter-sample interval. On real hardware the inertial stream for VIO should come from a sensor on the companion computer itself, or from a hardware-triggered source sharing the camera's trigger domain, and the autopilot's IMU should be treated as telemetry.

## ROS 2 sim time, what it does and does not do

`use_sim_time` switches a node's `ROSTime` source to the global `/clock` topic and changes nothing else. It does not alter a header stamp that a driver copies from a simulator or hardware field, which is the distinction that decides the whole design here. The AirSim bridge copies simulator timestamps into every sensor header, so setting `use_sim_time` on `airsim_node` would change only its dynamic vehicle transform and its fallback path, not the image or IMU stamps.

Consequences that bear on this workspace.

Before the first `/clock` message a node with `use_sim_time` true reports time zero, and zero is to be read as uninitialised rather than as an instant.

In `rclcpp`, `create_wall_timer` and `rclcpp::Rate` are unaffected by sim time, whereas `rclcpp::Clock::sleep_for` and the free function `rclcpp::create_timer` do follow it. In `rclpy`, `Node.create_timer` defaults to the node clock and therefore does follow sim time, which is why a Python supervisor node inherits sim time semantics more readily than a C++ one.

`tf2_ros::Buffer` polls `clock_->now()` in its `canTransform` wait loop, so a frozen clock makes that wait never expire, and it clears itself on a detected time jump or clock source change.

`message_filters` compares header stamps only and never consults a node clock, so it offers no protection against a stamp domain mismatch and will simply never produce a match.

Comparing `rclcpp::Time` values whose clock types differ throws `can't compare times with different time sources`.

There is no graph-wide switch. The parameter is per node, which makes a partially converted graph the normal failure mode rather than an exotic one.

## Basalt, why a constant offset is fatal rather than merely inaccurate

Basalt models camera to IMU misalignment as a single offline scalar, `cam_time_offset_ns` in the calibration structure, and the line that would apply it in the estimator is commented out at `ext/basalt/src/vi_estimator/sqrt_keypoint_vio.cpp:232`. The running estimator therefore assumes both streams already share one clock, and there is no online temporal calibration equivalent to the VINS-Mono `estimate_td` switch.

The pairing logic in `SqrtKeypointVioEstimator::ProcessFrame` is what fails. After initialisation it runs two catch-up loops at `sqrt_keypoint_vio.cpp:290-307`, discarding IMU up to `prev_frame->t_ns` and then integrating up to `curr_frame->t_ns`. When every IMU sample is ahead of every frame both conditions are false on entry, so no sample is ever popped, `imuData` is never refreshed, and the fill-in branch at `:308-315` fabricates a single measurement by temporarily rewriting a future sample's stamp to the current frame time.

The visible failure is not degraded accuracy but a hang. `imu_data_queue` is a `tbb::concurrent_bounded_queue` with capacity 300 at `ext/basalt/include/basalt/vi_estimator/vio_estimator.h:72`, and `addIMUToQueue` uses `emplace`, which blocks when the queue is full. Because `basalt_slam_node` spins a single-threaded executor at `src/basalt/driver.cpp:10`, the blocked IMU subscription callback consumes the only executor thread and the entire node stops, including its lifecycle services. The instrumentation that makes this visible in the logs is the workspace's own, `imu data queue size` at `ext/basalt/src/controller.cpp:221` and `imuData defined not popping` at `sqrt_keypoint_vio.cpp:230`.

## Where the NRT stack stamps with wall clock

These are the places in this workspace that produce a stamp rather than copying one, and are therefore sensitive to `use_sim_time`.

| Node | Site | What it stamps |
|---|---|---|
| `basalt_slam_node` | `slam/src/basalt/node.cpp:212` | `~/annotated_frame` |
| `basalt_slam_node` | `slam/src/node.cpp:30` | pose and transform output |
| `video_reader` | `sensors/src/video/reader.cpp:241` | replayed video frames |
| `imu_subscriber` | `sensors/src/imu/imu_subscriber.cpp:57` | CSV log column |

Consumers that copy header stamps rather than producing them, and so need no change, are the SLAM frame and IMU ingest at `slam/src/slam.cpp:27` and `slam/src/basalt/node.cpp:172-173`, and the `image_transport` republish node used for ffmpeg encoding, which propagates the input header.

As of 2026-07-28 the SITL stack carries one launch argument, `use-sim-time`, declared with `default_value="False"` and `choices=["True", "False"]` in five launch files, `controllers/launch/sitl.launch.py`, `controllers/launch/target_recorder.launch.py`, `controllers/launch/basalt_slam_test.launch.py`, `sensors/launch/managed_logger.launch.py` and `slam/launch/basalt_slam.launch.py`. It is set to `True` by `ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh` and by the `start sitl basalt` branch of `/ws/djinn`, and by nothing else.

The hyphen matters. `use-sim-time` is the launch argument, `use_sim_time` is the node parameter and also the name of the `ardupilot_sitl` launch argument that becomes `--use_sim_time` on the SITL command line. A forwarding dictionary that spells the key `use_sim_time` when the included file declares `use-sim-time` matches nothing and is silently discarded, which is the trap recorded in [`../ros_ws/context/launch-and-djinn.md`](../ros_ws/context/launch-and-djinn.md) and which this feature hit once during implementation in three separate files.

The parameter itself is set on exactly two nodes, `managed_logger_node` and `basalt_slam_node`, and deliberately not on `basalt_controller` or `video_logging_controller`, whose only use of a clock is to bound how long they wait for a lifecycle transition. `basalt_controller` would be the more dangerous of the two, because its watchdog reads `self.get_clock().now()` at `controllers/controllers/slam/driver_node.py:673` and `:711` and its readiness timer is an `rclpy` `Node.create_timer` at `:400`, both of which follow sim time; `video_logging_controller` uses `create_wall_timer` at `controllers/src/logging/video_controller.cpp:93`, which does not. Other occurrences of `use_sim_time` in `ros_ws/src` are `tello_gazebo/src/tello_plugin.cpp:227-231` and `frontier_detection/launch/frontier_detector.launch.py:19`, neither of which participates in `djinn start sitl`.

## Architectural options and why one wins

Three approaches exist for making a simulator and an autopilot agree on time.

The simulator publishes `/clock` and consumers opt in. This is the ROS native pattern, it is what ArduPilot's own `AP_DDS/README.md` recommends for simulated environments, and it is what `ardupilot_gz` implements by bridging Gazebo's `/clock` first in its bridge configuration. Its weaknesses are the per node opt-in and the transport latency bound on accuracy.

The autopilot clock is stepped by the simulator, which is PX4 lockstep. ArduPilot already implements the one-way half of this, its synthetic clock is advanced by the backend's timestamp deltas, but it has no blocking handshake, so a slow simulator produces skew rather than a stall, and it transfers deltas only, never the origin.

The bridge estimates an offset and rebases, which is the MAVLink `TIMESYNC` pattern and what mavros implements. It requires no cooperation from the estimator but adds a convergence transient, residual jitter and the obligation to apply the rebasing consistently to every stream.

For this stack the first option is the only one that is both correct and nearly free, because both endpoints already implement their half of it. AirSim can publish its clock, ArduPilot can consume it, and connecting the two collapses the offset to zero by construction rather than estimating it. The second option is unavailable because ArduPilot transfers deltas only. The third option would require patching the AirSim bridge or inserting a rebasing node, which is strictly more code for a strictly worse guarantee.
