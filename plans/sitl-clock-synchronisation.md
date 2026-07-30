# Clock synchronisation across AirSim, ArduPilot SITL and the SLAM stack

IMPLEMENTED 2026-07-28 for SITL. Changes 5.1 to 5.10 are in the tree; container-side validation is outstanding and catalogued in section 8. Section 6 is the hardware and HITL time architecture, which this investigation produced and which nothing here implements, recorded so that the SITL result is not over-generalised when the stack moves onto real hardware.

Supporting context, [`/ws/context/sitl-time-synchronisation.md`](../context/sitl-time-synchronisation.md), written from the investigation behind this plan and holding the full mechanism-level detail. This document assumes it and does not repeat its anchors except where a change depends on one.

## 1. Motivation

A `djinn start sitl basalt` run terminates in a hang. The immediate cause is visible in the log, the Basalt IMU queue climbs monotonically to its bound of 300 and the node then stops producing any output at all, having received one hundred and thirty five image frames and never once integrated an IMU sample against them.

The underlying cause is that the two sensor streams feeding VISLAM are stamped from two different clocks. Camera frames arrive on `/airsim_node/Copter/front_center_Scene/image` carrying AirSim's simulator clock, and inertial data arrives on `/ap/imu/experimental/data` carrying ArduPilot's clock. In the captured run the inertial stamps lead the image stamps by roughly six point one three seconds, which is not a jitter and not a calibration residual but a fixed epoch difference of the kind that makes visual inertial fusion structurally impossible rather than merely inaccurate.

The consequence is that VISLAM has never actually run in this workspace. The estimator initialises, aligns gravity from an inertial sample taken six seconds after the frame it is aligning against, then enters a state in which no preintegration window can ever form. Every pose it emits afterwards is derived from a fabricated single measurement. Correcting this is a precondition for any of the SLAM work that follows, and it is also a precondition for the recorded telemetry being replayable, because a bag whose message stamps and receive stamps sit in different time domains cannot be replayed coherently.

## 2. Preliminaries

### 2.1 How AirSim stamps its messages

Every message the Cosys-AirSim ROS 2 bridge publishes copies a simulator timestamp field verbatim into the ROS header, with no offset and no conversion. Images take `ImageResponse::time_stamp` at `ros2/src/airsim_ros_pkgs/src/airsim_ros_wrapper.cpp:1857`, inertial data takes `imu_data.time_stamp` at `:1212`, and every other sensor follows the same pattern. There is no rebasing logic anywhere in the bridge, which was established by searching for the timestamp-alignment idioms that exist in the PX4-oriented forks and finding none of them present.

The field itself is filled inside Unreal from the `ClockFactory` singleton, at GPU readback for images and at sensor update for inertial data. For a multirotor sim mode with an ArduCopter vehicle that singleton holds a `SteppableClock`, both because the active `settings.json` requests it explicitly and because it is the automatic default, the PX4 exception in `AirSimSettings::loadClockSettings` not covering the ArduCopter vehicle type.

A `SteppableClock` reads wall clock exactly once, at construction, and thereafter advances only when the physics loop steps it, by three milliseconds per tick. It never resynchronises. Two properties follow. Its origin is the wall clock instant at which the Unreal game constructed it, and its rate falls behind wall clock by however much the physics thread under-runs its target.

The bridge can publish this clock, through a `publish_clock` parameter, but two facts make that feature unusable as shipped. It defaults to false in both the constructor and the launch file, and it publishes on `~/clock`, which resolves to `/airsim_node/clock` rather than the global `/clock` that ROS 2 sim time reads. A comment two lines above the publish call claims the topic is `/clock`, which is how the discrepancy has survived.

### 2.2 How ArduPilot stamps its messages

Every `/ap/*` header passes through a single function, `AP_DDS_Client::update_topic(builtin_interfaces_msg_Time&)` at `libraries/AP_DDS/AP_DDS_Client.cpp:213-231`, whose precedence is an externally supplied `/clock` first, then the real time clock, then a bare monotonic microsecond counter.

Under SITL that monotonic counter is itself simulated. `AP_HAL::micros64()` returns the scheduler's stopped clock whenever it is non-zero, and SITL primes it and then overwrites it on every physics step with the flight dynamics model timestamp. For the AirSim backend that timestamp is advanced by AirSim's own deltas, at `libraries/SITL/SIM_AirSim.cpp:323-325`, where the received absolute value is differenced against the previous one and the difference added to ArduPilot's own accumulator.

This is the crux of the whole problem. Only the delta transfers, never the origin. ArduPilot's accumulator begins at one microsecond and AirSim's clock begins at a wall clock epoch value, so the two run at an identical rate about two different anchors. The real time clock then adds a shift derived from the simulated GPS, whose epoch is wall clock at the SITL process start, which converts ArduPilot's stamps to the UNIX epoch without ever reconciling them with AirSim's.

ArduPilot master, which this workspace tracks, compiles a `/clock` DataReader into every SITL build and uses it to override the stamp on every published topic. It is gated at runtime by a `--use_sim_time` flag that the `ardupilot_sitl` launch wrapper already passes unconditionally with a default of true. The mechanism is therefore already armed in the running binary, which was confirmed directly against the built executable, and is inert only because nothing in the graph publishes `/clock`.

### 2.3 What ROS 2 sim time does and does not do

Setting `use_sim_time` on a node redirects that node's `ROSTime` source to the global `/clock` topic. It changes what `now()` returns and nothing else. In particular it does not alter a header stamp that a driver copies out of a simulator or hardware field, which is exactly what the AirSim bridge does for every sensor. Enabling sim time on the bridge would therefore not move a single image or inertial stamp.

Three further properties bear on the design. Before the first `/clock` message a sim-time node reports zero, and zero is to be read as uninitialised rather than as an instant. In `rclcpp` a wall timer is unaffected by sim time whereas the node clock is, and in `rclpy` a timer created through `Node.create_timer` defaults to the node clock and therefore does follow sim time. And there is no graph-wide switch, the parameter is per node, so a partially converted graph is the ordinary failure mode rather than an exotic one.

### 2.4 What Basalt requires, and what it does when it does not get it

Basalt models camera to inertial misalignment as a single offline scalar, and the line in the estimator that would apply it is commented out at `ext/basalt/src/vi_estimator/sqrt_keypoint_vio.cpp:232`. The running estimator therefore assumes both streams already share a clock, and unlike VINS-Mono it has no online temporal calibration to fall back on.

Its pairing logic is what fails. After initialisation `ProcessFrame` runs two catch-up loops, the first discarding inertial samples up to the previous frame time and the second integrating up to the current frame time. When every inertial sample is ahead of every frame, both loop conditions are false on entry, no sample is ever popped, the cached sample is never refreshed, and a fill-in branch fabricates a single measurement by temporarily rewriting a future sample's stamp to the current frame time.

The failure is then a hang rather than a degradation. The inertial queue is a bounded concurrent queue of capacity three hundred, its producer blocks when full, and because `basalt_slam_node` spins a single-threaded executor at `src/basalt/driver.cpp:10` the blocked subscription callback consumes the node's only thread. Image callbacks and lifecycle services stop with it.

## 3. The current setup, and the derivation of the offset

### 3.1 What the capture shows

Taking two adjacent lines from the supplied log, an inertial sample at 1785163926.498947000 and an image at 1785163920.364335104, both received within the same second of wall clock, gives a lead of 6.134611896 seconds for the inertial stream. The lead is stable across the whole capture, the last inertial sample logged is 1785163928.304986000 and the last image 1785163921.819366144, a difference of 6.485619856 seconds. The growth of roughly three hundred and fifty milliseconds over the capture is the expected consequence of images being sampled at twenty hertz against inertial at two hundred, and not of any drift between the clocks.

### 3.2 Why the offset exists and why it is constant

Writing the two stamps out,

```
AirSim stamp    = T_ue   + elapsed_sim_total
ArduPilot stamp = T_sitl + elapsed_sim_since_first_airsim_packet
```

where `T_ue` is wall clock at the Unreal `SteppableClock` construction and `T_sitl` is wall clock at the SITL process start. Both elapsed terms advance by the same AirSim deltas, so their difference is fixed from the moment ArduPilot receives its first packet, and

```
offset = T_sitl - T_ue - elapsed_sim_before_first_packet
```

The `djinn start sitl` sequence makes the sign inevitable and the magnitude plausible. The Unreal game is started first, the script sleeps three seconds at `djinn:295`, and only then is the SITL bridge container told to run `sitl.launch.py`, which itself waits a further three seconds inside a `TimerAction` at `sitl.launch.py:36` before starting ArduPilot. `T_sitl` therefore trails `T_ue` by at least six seconds of wall clock, and because the steppable clock lags wall clock the sim time accrued in that window is less than the wall gap, leaving a positive offset. The two terms that cannot be read off the launch files are how long the Unreal game takes to reach clock construction, which pushes `T_ue` later and shrinks the offset, and how far the steppable clock lags, which enlarges it. The measured six point one three seconds is therefore consistent with the launch sequence rather than derived from it, and the derivation predicts only the sign and the order of magnitude. Check 20 in section 8 pins the value empirically.

The offset is constant rather than drifting because after the first packet both clocks are driven by one delta stream. This matters for the design, because it means the problem is one of origin alone and can be removed exactly rather than estimated.

### 3.3 Why the MAVLink route cannot reach the stamping clock

The obvious alternative to the `/clock` route is to configure `airsim-quadX.parm` so that ArduPilot disciplines its clock over MAVLink, using `SYSTEM_TIME` and `BRD_RTC_TYPES` as the ArduPilot wiki describes for mavros deployments. It is recorded here because it is the first thing a reader will reach for, and because it cannot work in SITL, for four independent reasons, any one of which would be sufficient.

The `SYSTEM_TIME` handler calls `AP::rtc().set_utc_usec` and nothing else, which moves only the real time clock shift. The monotonic counter that paces the simulation and that the shift is added to is untouched, so the relationship between ArduPilot's clock and AirSim's is unchanged.

`BRD_RTC_TYPES` defaults to one, meaning GPS only, so a MAVLink time source is filtered out before it is considered.

Even were that bit set, the source priority enum ranks GPS above MAVLink, and `set_utc_usec` rejects a lower-priority source once a higher one has claimed the slot. The simulated GPS claims it within the first seconds of every run.

Most decisively, all of this sits downstream of a branch that does not execute. Once `/clock` is connected, `update_topic` returns the external time before it consults the real time clock at all, so the entire real time clock configuration becomes irrelevant to the stamps.

`TIMESYNC`, the other MAVLink mechanism, is a pure round-trip responder in ArduPilot. It writes a log record and adjusts no clock. ArduPilot has no mechanism anywhere to slew or step its monotonic clock from an external source.

`airsim-quadX.parm` is therefore left untouched. Setting `BRD_RTC_TYPES` to two would be actively harmful here, because it would deny the simulated GPS the real time clock slot while no companion in this graph sends `SYSTEM_TIME`, leaving the pre-`/clock` fallback stamping boot-relative microseconds near zero.

That conclusion is specific to SITL, and it should not be read as a judgement on the parameter itself. `BRD_RTC_TYPES=2` is the right setting for a GPS-denied hardware deployment, and section 6 works through why the same parameter is correct there and wrong here. The short form is that in SITL the question is which of two simulated origins wins, and the `/clock` route answers it exactly and upstream of the real time clock entirely, whereas on hardware the question is how two free-running physical oscillators are related, and there the real time clock is the only lever that exists.

### 3.4 Five further facts that shape the design

Publishing the clock and remapping it onto `/clock` is the whole of the fix on the publishing side, and neither half accomplishes anything without the other, since the bridge publishes into its own private namespace. Five further facts, none of them evident from the topology, determine everything else in section 4.

ArduPilot's side of the mechanism must be made explicit rather than inherited. The `ardupilot_sitl` launch wrapper passes `--use_sim_time True` by default, which means the `/clock` DataReader already exists in every run. That is a latent hazard as much as a convenience, because it means the moment anything in the graph publishes `/clock`, every `/ap/*` stamp changes without any deliberate act. The flag belongs in the launch arguments where it is visible and where it can be turned off.

The choice of which nodes take `use_sim_time` is not a formality and the answer is not all of them. Section 4.5 works through each node individually. Two of them must not have it, and section 4.6 records what would have to change before either could.

`synthetic_clock`, which `sitl.launch.py` passes as true, is a no-op on ArduPilot master, the option table carrying the comment that it is kept only to warn that synthetic clock mode is always enabled. It is not a lever on this problem and should not be mistaken for one.

The latching behaviour of `has_received_clock` is a new failure mode that the fix introduces. It is set on the first received message and never cleared, so if the AirSim bridge stops, every `/ap/*` stamp freezes at the last received value rather than reverting. A frozen inertial stamp stream drives Basalt into the same bounded-queue hang from the opposite direction.

The recorder's clock determines whether the resulting bag is replayable. Message receive timestamps come from the recorder's own clock, so leaving it on wall clock while headers carry sim time produces a bag that cannot be replayed with `--clock` without reintroducing the same class of defect at replay time.

## 4. Design

### 4.1 The chosen mechanism

AirSim publishes its simulator clock on the global `/clock`, and ArduPilot consumes it and stamps every DDS message with it. Both sensor streams then carry the same `SteppableClock` value and the offset is zero by construction rather than by estimation.

The whole of the fix is therefore three facts already true of the system plus one wire. AirSim already stamps images and its own sensors from the clock it can publish. ArduPilot already compiles and arms a `/clock` reader in SITL. The two are already rate-locked through the flight dynamics model. Connecting the topic supplies the missing origin.

### 4.2 Alternatives considered and rejected

Estimating the offset in a bridge node, in the manner of MAVLink `TIMESYNC` or of the PX4 timesync filter, would require a new node, an alpha-beta filter with outlier rejection and a convergence transient, and would then have to be applied consistently to every stream or it would merely move the problem. It buys an approximation of something the `/clock` route gives exactly.

Patching the AirSim submodule to publish on `/clock` directly would be a one-character change but diverges the submodule from upstream for something a launch-level remap achieves with no source change at all.

Relaying `/airsim_node/clock` to `/clock` with a `topic_tools` node would work, at the cost of an additional process, an additional hop of latency on the clock and a second place for the QoS to be got wrong.

Rebasing the inertial stamps inside `BasaltSLAMNode`, by subtracting a latched initial difference, would fix Basalt and nothing else, and would leave the recorded bag and every future consumer with the original defect.

Aligning the origins by passing `--start-time` to SITL was considered and rejected because it fixes only the constant term while the steppable clock continues to lag wall clock, and because it requires knowing the Unreal clock construction instant, which is not observable from the launch layer.

### 4.3 An opt-in flag whose default reproduces current behaviour

Every change is gated behind one new launch argument named `use-sim-time`, defaulting to `False`, propagated down the launch graph under that single name, and set to `True` only by the two invocation scripts that start the SITL stack.

This satisfies the workspace rule that no change may alter the behaviour of a caller that did not ask for it. A bare `ros2 launch controllers sitl.launch.py`, or `ros2 launch slam basalt_slam.launch.py` against a Tello where no `/clock` exists, behaves exactly as it did before this change. It also makes the entire feature revertible with one argument, which matters for comparing against the historical runs already recorded under the old timing.

The flag is deliberately singular. One concept, one name, one place per invocation where sim time is turned on, rather than separate `publish_clock` and `use_sim_time` knobs that could be set inconsistently and produce a graph in which ArduPilot waits for a clock that is not published or a recorder runs on a clock nobody else uses.

The name mirrors the node parameter it ultimately sets. Two spellings coexist and the distinction is load-bearing. `use-sim-time` with hyphens is the launch argument, following the workspace convention already established by `log-level`, `camera-topic` and `imu-topic`. `use_sim_time` with underscores is the ROS 2 node parameter, and separately the name of the `ardupilot_sitl` launch argument that becomes `--use_sim_time` on the SITL command line. A forwarding dictionary whose key is the underscored spelling when the included file declares the hyphenated one matches no declared argument and is silently discarded with no error and no warning, which is the trap recorded in [`launch-and-djinn.md`](../ros_ws/context/launch-and-djinn.md). It is a live hazard for this feature specifically, because the underscored spelling is not a typo but the genuinely correct name one line away, at the `ardupilot_sitl` forwarding site and at both parameter sites. Every forwarding site therefore carries a comment naming which spelling belongs there and why.

### 4.4 Type checking of the flag, and why `ParameterValue` is not used

The flag is validated once, at declaration, by `choices=["True", "False"]` on every `DeclareLaunchArgument`, and is then passed as a bare `LaunchConfiguration` everywhere it is consumed.

The alternative considered was wrapping each parameter-dictionary entry in `launch_ros.parameter_descriptions.ParameterValue(..., value_type=bool)`. It was rejected on three grounds. It is redundant, because `launch_ros` already type-infers a bare `LaunchConfiguration` in a parameter dictionary by running `yaml.safe_load` over the substituted string, so `"False"` arrives at the node as a boolean either way, which is exactly how the upstream AirSim launch file passes `is_vulkan` and `publish_clock`. It is inconsistent, because the wrapper is only applicable at the two sites that set a node parameter and cannot be applied at the three sites that forward the argument to an included launch file, so half the graph would be checked and half not. And `choices` does the validation strictly earlier and more completely, rejecting `use-sim-time:=yes` when the argument is declared rather than when a parameter is read, and covering the forwarding sites as well as the parameter sites.

`choices=["True", "False"]` also matches `BOOL_STRING_CHOICES` in `Tools/ros2/ardupilot_sitl/src/ardupilot_sitl/launch.py:34-36`, which is the set that the `ardupilot_sitl` `use_sim_time` argument itself enforces on the value forwarded to it from 5.3. Any value this workspace accepts is therefore a value ArduPilot's own launch wrapper accepts.

### 4.5 Which nodes take `use_sim_time`, and why

| Node | Sim time | Reasoning |
|---|---|---|
| `airsim_node` | No | It is the clock source. Its sensor and image stamps come from the simulator field and would not move. Its `update_state()` fallback and its own clock publish would return zero before the first `/clock` message, so enabling it risks publishing a zero clock and reproduces the shape of the known AirSim self-deadlock for no gain. |
| `arducopter` (SITL) | Yes, via `--use_sim_time` | This is the entire point of the change. It is a stamp override rather than clock disciplining, so the autopilot's internal timing, its scheduler and its estimator are unaffected. |
| `basalt_slam_node` | Yes | It produces stamps rather than only copying them, at `slam/src/basalt/node.cpp:212` for the annotated frame and `slam/src/node.cpp:30` for the pose and transform output. Under sim time those outputs land in the same domain as their inputs. Its frame and inertial ingest read header stamps and are unaffected either way. It holds no wall-clock deadline that a stalled clock could strand. |
| `basalt_slam_controller` | No | Its reconciler watchdog compares `self.get_clock().now()` against a ten second transition deadline. Under sim time a stalled or absent `/clock` would leave a failed transition latched in flight forever, disabling the recovery path that watchdog exists to provide. It is a supervisor and performs no stamp arithmetic, so it has nothing to gain. |
| `video_logging_controller_node` | No | Identical reasoning. It is a supervisor over the recorder's lifecycle and touches no message stamp. |
| `managed_logger_node` | Yes | Bag receive timestamps come from this node's clock. Leaving it on wall clock while every header carries sim time produces a bag that cannot be replayed with `--clock` coherently. It activates at the arming edge, long after `/clock` is established, so the uninitialised-zero window does not apply to it. |
| `image_transport republish` | No | It copies the input header into the compressed output and produces no stamp of its own. |
| `micro_ros_agent` | No | A transport bridge that does not stamp. |

The two refusals are the substantive judgements here. Both controller nodes are `rclpy` and `rclcpp` supervisors whose only use of a clock is to bound how long they will wait for something, and sim time converts a bounded wait into an unbounded one exactly when the simulator is the thing that has failed.

### 4.6 What the two controllers must do when they later need sim time

The refusal in 4.5 rests on what those two nodes do today, not on a principle that they may never have it. The moment either acquires logic that compares a message header stamp against its own `now()`, the refusal inverts, because a supervisor reasoning about staleness on wall clock while every stamp it reads carries simulator time would compute a difference of several seconds and act on it. This section records the exact steps so that the decision is made deliberately and the two nodes end up on the same mechanism the rest of the stack uses, rather than acquiring an ad hoc one.

The trigger to watch for is narrow and easy to state. Any use of `self.get_clock().now()` or `this->now()` whose result is compared against, subtracted from, or written into a message header stamp requires sim time. Any use whose result is only compared against another reading of the same clock, which is what a timeout is, does not, and is actively harmed by it.

The wiring is three steps and is identical in shape to 5.5 and 5.7.

For `basalt_controller`, declared in `basalt_slam_test.launch.py`, the argument is already declared and carried in that file by 5.8, so the only change is one entry in the node's parameter dictionary.

```python
    basalt_controller_node = launch_ros.actions.Node(
        ...
        parameters=[
            {
                ...
                "use_sim_time": use_sim_time,
            }
        ],
    )
```

For `video_logging_controller`, declared in `target_recorder.launch.py`, the argument is likewise already declared and carried by 5.5, and the same single entry is added to `video_logging_driver_node`'s parameter dictionary.

The third step is the one that is not mechanical, and it is the reason this is written down rather than left to be rediscovered. Enabling sim time on either node breaks its watchdogs unless they are moved off the node clock first, and the two languages fail differently.

In `basalt_controller`, which is `rclpy`, both mechanisms follow sim time by default. The transition deadline reads `self.get_clock().now()` at `controllers/controllers/slam/driver_node.py:673` and `:711`, and the service readiness poll is a `Node.create_timer` at `:400`, which in `rclpy` defaults to the node clock. Both must be moved to a steady clock explicitly, the deadline by holding a `rclpy.clock.Clock(clock_type=rclpy.clock.ClockType.STEADY_TIME)` as a member and reading `now()` from it instead of from the node, and the timer by passing that clock through the `clock=` keyword of `create_timer`. Without this, a `/clock` that stalls because the simulator has died leaves a failed lifecycle transition latched in flight forever, which disables precisely the recovery path the watchdog exists to provide.

In `video_logging_controller`, which is `rclcpp`, the single timer at `controllers/src/logging/video_controller.cpp:93` is a `create_wall_timer` and is therefore already immune, since `rclcpp` wall timers ignore sim time by construction. That node needs no defensive change, only the parameter entry. Should it ever acquire a `rclcpp::Clock`-based deadline, the same rule applies, the deadline uses `RCL_STEADY_TIME` and only stamp arithmetic uses the node clock.

The general rule that falls out, and which should govern any node added to this stack later, is that a node holds two clocks with two jobs. The node clock, which sim time redirects, answers what time is it in the domain my messages live in. A steady clock, which sim time never touches, answers how long have I been waiting. Conflating them is what makes a partially converted graph fail in ways that look like the simulator hanging rather than like a configuration error.

## 5. Changes

### 5.1 `ros_ws/src/controllers/launch/sitl.launch.py`, declare the flag

`sitl.launch.py:35-47`. Added alongside the existing argument declarations near the top of `generate_launch_description`.

```python
    use_sim_time_arg = launch.actions.DeclareLaunchArgument(
        "use-sim-time",
        default_value="False",
        choices=["True", "False"],
        description=(
            "Boolean, the only accepted values are True and False. Run the SITL "
            "stack on AirSim's simulator clock. When True the AirSim bridge "
            "publishes its clock on /clock, ArduPilot stamps every /ap/* message "
            "from it, and the recorder runs on it. Default False reproduces the "
            "pre-2026-07-27 behaviour exactly."
        ),
    )
    use_sim_time = launch.substitutions.LaunchConfiguration("use-sim-time")
```

and `use_sim_time_arg` appended to the returned `LaunchDescription` list alongside `topics_to_record_arg`.

Backwards compatibility. A new argument with a default that reproduces current behaviour, consumed only by the changes below. No existing caller is affected. `choices` narrows what the argument accepts but the argument is new, so nothing that previously worked is rejected.

### 5.2 `sitl.launch.py`, publish the AirSim clock and remap it

`sitl.launch.py:66-91`. The AirSim include gains the `publish_clock` argument and is wrapped in a scoped group carrying a conditional remap.

```python
    airsim_node_launch = launch.actions.IncludeLaunchDescription(
        launch.launch_description_sources.PythonLaunchDescriptionSource(
            airsim_launch_file
        ),
        launch_arguments={
            "host_ip": "127.0.0.1",
            "publish_clock": use_sim_time,
        }.items(),
    )
    # airsim_ros_pkgs publishes its simulator clock on "~/clock", which resolves
    # to /airsim_node/clock. ROS 2 sim time and ArduPilot's AP_DDS clock reader
    # both read the global /clock and neither can see the private one, so the
    # publish_clock parameter is useless without this remap. SetRemap applies to
    # every Node created in the enclosing scope, including those inside an
    # IncludeLaunchDescription, which is why the include sits inside the group.
    # The source is the fully resolved name because remap rules are matched
    # after private-name expansion.
    airsim_group = launch.actions.GroupAction(
        scoped=True,
        actions=[
            launch_ros.actions.SetRemap(
                src="/airsim_node/clock",
                dst="/clock",
                condition=launch.conditions.IfCondition(use_sim_time),
            ),
            airsim_node_launch,
        ],
    )
    delayed_launch.actions.append(airsim_group)
```

replacing the former `delayed_launch.actions.append(airsim_node_launch)`.

`publish_clock` is forwarded under its own upstream name rather than under `use-sim-time`, because it is the AirSim bridge's declared argument, at `sitl_ws/src/ue5/AirSim/ros2/src/airsim_ros_pkgs/launch/airsim_node.launch.py:18-20`, and is a different concept, it makes the bridge a clock publisher rather than a sim time consumer.

Note on the QoS, which is why no override is needed. The bridge creates the publisher with `create_publisher(..., 1)`, giving RELIABLE, VOLATILE and KEEP_LAST of depth one. ArduPilot's reader is RELIABLE, so it matches, and the `rclcpp` time source subscribes BEST_EFFORT, which a RELIABLE publisher also satisfies. A publisher tuned only for ROS consumers, using the idiomatic best-effort clock profile, would have silently failed to reach ArduPilot.

Backwards compatibility. With `use-sim-time` false the `SetRemap` is not applied and `publish_clock` is forwarded as `False`, which is the include's own default, so the AirSim node is launched exactly as it was before this change. `GroupAction(scoped=True)` confines the remap so it cannot leak onto the ArduPilot, encoder or recorder actions appended after it.

### 5.3 `sitl.launch.py`, make ArduPilot's clock consumption explicit

`sitl.launch.py:124-137`. Two keys in the existing `ardupilot_sitl_launch` argument dictionary, one new and one annotated.

```python
            # --synthetic-clock is a no-op on ArduPilot master, whose option
            # table keeps it only to print "Synthetic clock mode is now always
            # enabled" (SITL_cmdline.cpp:331,456). Retained because upstream
            # ArduPilot's own documented invocation and ardupilot_gz both still
            # pass it.
            "synthetic_clock": "True",
            # ArduPilot master compiles a /clock DataReader into every SITL
            # build (AP_DDS_config.h:121-123) and overrides every /ap/* header
            # stamp with it (AP_DDS_Client.cpp:216-223). The reader is created
            # only when --use_sim_time is true, which the ardupilot_sitl launch
            # wrapper passes with a default of True. Relying on that default is
            # a hazard rather than a convenience, it means any node that starts
            # publishing /clock silently retimes the whole autopilot. Bind it to
            # use-sim-time so it is deliberate and so use-sim-time:=False
            # provably restores the old stamping path.
            "use_sim_time": use_sim_time,
```

The key is the underscored `use_sim_time` here and correctly so, because that is the name `ardupilot_sitl`'s own launch file declares, at `Tools/ros2/ardupilot_sitl/src/ardupilot_sitl/launch.py:663-668`. This is the one forwarding site in the whole feature where the underscored spelling is right.

Backwards compatibility. This is the one place where the default changes an observable input. Before this change ArduPilot was launched with `--use_sim_time True` implicitly, and with `use-sim-time` false it is now launched with `--use_sim_time False`. Because nothing in the graph publishes `/clock` in that configuration, `has_received_clock` is never set and the stamping path is identical in both cases. The only difference is that the DataReader is not created, which removes a latent trap rather than changing behaviour.

### 5.4 `sitl.launch.py`, forward the flag to the recorder

`sitl.launch.py:230-234`. One key added to the `managed_logger_launch` argument dictionary.

```python
            # NOTE: the key is the hyphenated launch-argument name declared by
            # target_recorder.launch.py, not the node parameter "use_sim_time".
            # A key that matches no declared argument in the included file is
            # silently discarded -- see ros_ws/context/launch-and-djinn.md.
            "use-sim-time": use_sim_time,
```

Backwards compatibility. Additive, and the receiving file declares the same default.

### 5.5 `ros_ws/src/controllers/launch/target_recorder.launch.py`, forward to the logger

`target_recorder.launch.py:36-42`, `:99-101` and `:141`. A declaration mirroring 5.1, and one key added to the `logger_launch` argument dictionary.

```python
    use_sim_time_arg = launch.actions.DeclareLaunchArgument(
        "use-sim-time",
        default_value="False",
        choices=["True", "False"],
        description="Boolean, the only accepted values are True and False. Run the managed recorder on the simulator clock published on /clock.",
    )
    use_sim_time = launch.substitutions.LaunchConfiguration("use-sim-time")
```

```python
            # NOTE: the key is the hyphenated launch-argument name declared by
            # managed_logger.launch.py, not the node parameter "use_sim_time".
            "use-sim-time": use_sim_time,
```

`video_logging_driver_node` is deliberately left alone, per 4.5, and the steps to reverse that later are in 4.6.

One repair is folded into this change. The `all_supported_topics_list` entry for `/ap/time` had become `"/ap/time"sim-timsim-timee,`, a hard `SyntaxError` that stopped the file being loaded at all, and it is restored to `"/ap/time",`. It is recorded here rather than passed over silently because it is the fourth divergent copy of a topic list that section 9 notes should be collapsed to one source of truth.

Backwards compatibility. Additive with a default reproducing current behaviour. This file is also reachable directly, and an invocation that does not pass the argument is unchanged.

### 5.6 `ros_ws/src/sensors/launch/managed_logger.launch.py`, set the parameter

`managed_logger.launch.py:23-29`, `:83` and `:91`. A declaration mirroring 5.1, and one entry in the node's parameter dictionary.

```python
    use_sim_time_arg = launch.actions.DeclareLaunchArgument(
        "use-sim-time",
        default_value="False",
        choices=["True", "False"],
        description="Boolean, the only accepted values are True and False. Run the recorder on the simulator clock, so that bag receive timestamps and message header stamps share one domain and the bag replays coherently with --clock.",
    )
    use_sim_time = launch.substitutions.LaunchConfiguration("use-sim-time")
```

```python
                "use_sim_time": use_sim_time,
```

with `use_sim_time_arg` added to the returned description. The bare `LaunchConfiguration` is deliberate rather than a `ParameterValue` wrapper, for the reasons in 4.4.

Backwards compatibility. Additive. With the default the parameter is set to `False`, which is already the node's effective value, so the node is unchanged.

### 5.7 `ros_ws/src/slam/launch/basalt_slam.launch.py`, set the parameter on the compute node

`basalt_slam.launch.py:64-72`, `:91` and `:103`. A declaration mirroring 5.1 and one entry in the `basalt_slam_node` parameter dictionary.

```python
    use_sim_time_default = "False"
    use_sim_time_arg = launch.actions.DeclareLaunchArgument(
        "use-sim-time",
        default_value=[use_sim_time_default],
        choices=["True", "False"],
        description="Boolean, the only accepted values are True and False. Run the SLAM compute node on the simulator clock published on /clock, so that the stamps it produces on ~/annotated_frame and on its pose output share a domain with the stamps it consumes.",
    )
    use_sim_time = launch.substitutions.LaunchConfiguration(
        "use-sim-time", default=use_sim_time_default
    )
```

```python
                "use_sim_time": use_sim_time,
```

The declaration follows this file's existing `LaunchConfiguration(name, default=...)` plus `DeclareLaunchArgument(name, default_value=[...])` idiom rather than the plainer form used in `sitl.launch.py`, matching its surrounding style.

Backwards compatibility. Additive with a false default. The Tello and video-file paths, which have no `/clock`, are unaffected unless the argument is passed.

### 5.8 `ros_ws/src/controllers/launch/basalt_slam_test.launch.py`, declare and forward

`basalt_slam_test.launch.py:61-67`, `:121-123` and `:165`. A declaration mirroring 5.1, one key added to the `basalt_slam_launch` argument dictionary, and the argument appended to the `nodes` list.

```python
    use_sim_time_arg = launch.actions.DeclareLaunchArgument(
        "use-sim-time",
        default_value="False",
        choices=["True", "False"],
        description="Boolean, the only accepted values are True and False. Run the SLAM compute node on the simulator clock published on /clock, so that the stamps it produces share a domain with the camera and inertial stamps it consumes.",
    )
    use_sim_time = launch.substitutions.LaunchConfiguration("use-sim-time")
```

```python
            # NOTE: the key is the hyphenated launch-argument name declared by
            # basalt_slam.launch.py, not the node parameter "use_sim_time".
            "use-sim-time": use_sim_time,
```

`basalt_controller_node` is deliberately left alone, per 4.5, and the steps to reverse that later are in 4.6.

Backwards compatibility. Additive. Because this file declares the argument, passing `use-sim-time:=True` on its command line is not silently discarded, which is the trap recorded in [`launch-and-djinn.md`](../ros_ws/context/launch-and-djinn.md).

### 5.9 `ardu_ws/scripts/run_ardupilot_airsim_ros_sitl.sh`, opt in

`run_ardupilot_airsim_ros_sitl.sh:5`.

```bash
iexec_sitl sitl_bridge_container "ros2 launch controllers sitl.launch.py use-sim-time:=True"
```

Backwards compatibility. This script has one caller, `djinn start sitl`, and turning sim time on for the SITL stack is the intended behaviour change. Reverting is a matter of dropping the argument.

### 5.10 `/ws/djinn`, opt in on the Basalt path

`djinn:283`. One line in the `basalt_slam_test.launch.py` invocation in the `start sitl basalt` branch.

```
                    use-sim-time:=True \
```

There is no space after the assignment operator, and the omission is load-bearing. `ros2 launch` splits its arguments on whitespace before splitting each on `:=`, so `use-sim-time:= True` is two tokens, an argument set to the empty string and a bare positional `True`, and it fails the launch rather than setting anything.

Backwards compatibility. Same reasoning as 5.9. The `orbslam3` branch is left alone, since it invokes a launch file that does not exist and is a known broken workflow.

### 5.11 `airsim-quadX.parm`, no change

Recorded here so that a later reader does not mistake the omission for an oversight. The short reasoning is in 3.3 and the full treatment, including why the same parameter is correct on hardware, is in section 6.

Two further mechanical facts about this file are worth recording, because they would matter to anyone who did decide to change it. The file `sitl.launch.py` actually loads is `ardupilot_sitl/config/default_params/airsim-quadX.parm` from the install space, resolved through `FindPackageShare`, and the source it is installed from is `ardu_ws/src/ardupilot/Tools/autotest/default_params/airsim-quadX.parm`, so an edit to the source has no effect until `ardu_ws` is rebuilt. The file also carries two uncommitted local edits unrelated to this work, `SCHED_LOOP_RATE` reduced from 300 to 185 and `GPS1_DELAY_MS` raised from 20 to 200. Neither affects DDS stamping and both predate this plan. `SCHED_LOOP_RATE` is worth flagging for a different reason, the ArduPilot wiki names it as the parameter to raise when MAVLink `TIMESYNC` reports `RTT too high for timesync`, so lowering it moves the hardware time synchronisation path in the wrong direction should that path ever be taken with this airframe.

## 6. Time synchronisation on hardware and in HITL

Everything above concerns SITL, where both clocks are simulated and one of them can simply be declared authoritative. On a real flight controller neither clock is simulated and none of the SITL mechanisms apply. This section records what does apply, because the same `/ap/imu/experimental/data` and `/ap/status` topics will be consumed by the same SLAM stack on hardware, and because it is the evidence for leaving `airsim-quadX.parm` alone in 5.11 without leaving the impression that `BRD_RTC_TYPES` is a bad parameter.

Nothing in this section is implemented. It is the design record for the hardware bring-up that follows.

### 6.1 ArduPilot keeps exactly two clocks

The lower layer is `AP_HAL::micros64()`, a monotonic counter. The upper layer is `AP_RTC`, which holds one signed `rtc_shift` such that UTC equals `micros64() + rtc_shift`. There is no third clock and no other adjustable quantity anywhere in the firmware.

| Layer | SITL | Real hardware |
|---|---|---|
| `micros64()` | the scheduler's stopped clock, primed to 1 µs at `SITL_State.cpp:82-83` and overwritten every physics step at `:273-274` with the flight dynamics model timestamp | `clock_gettime(CLOCK_MONOTONIC)` less process start on Linux boards, a hardware timer on ChibiOS. Boot-relative and free-running |
| Its origin | 1 µs, then advanced by AirSim deltas at `SIM_AirSim.cpp:323-325` | zero at power-on |
| `rtc_shift` | from the simulated GPS, whose epoch is `gettimeofday()` at SITL process start, `SITL_cmdline.cpp:267-271` | from a real GPS 3D fix, from MAVLink `SYSTEM_TIME`, or from the board hardware RTC |
| `/clock` DataReader | compiled in, armed by `--use_sim_time` | not compiled in |

The fact that governs every option below is that no code path anywhere in ArduPilot writes `micros64()`. It cannot be stepped, slewed or set. `AP_RTC::set_utc_usec` at `AP_RTC.cpp:47-101` moves only the shift, and it is constrained three ways, it refuses a source ranked worse than the one already in use, it refuses any source whose bit is clear in `BRD_RTC_TYPES`, and it refuses ever to let the shift decrease, `if (tmp < rtc_shift) return`. UTC in ArduPilot is a monotone, coarsely stepped, one-way quantity.

### 6.2 How a `/ap/*` stamp is produced

```
AP_DDS_Client::update_topic(builtin_interfaces_msg_Time&)   AP_DDS_Client.cpp:213-231
   |
   +-- #if AP_DDS_CLOCK_SUB_ENABLED        AP_DDS_config.h:121-123
   |      = (CONFIG_HAL_BOARD == HAL_BOARD_SITL) unless overridden by a build define
   |   and has_received_clock, latched true by the /clock callback at :908-919
   |      -> return external_clock_time              [SITL with use-sim-time:=True]
   |
   +-- AP::rtc().get_utc_usec(utc_usec)              AP_RTC.cpp:103-113
   |      returns micros64() + rtc_shift, false while rtc_source_type == SOURCE_NONE
   |      -> return that                             [hardware with a time source]
   |
   +-- fallback: utc_usec = AP_HAL::micros64()
          -> return boot-relative microseconds       [hardware with no time source]
```

Three topics land on this one function, `/ap/imu/experimental/data` at `AP_DDS_Client.cpp:670`, `/ap/clock` at `:705-708` and `/ap/time` at `:1874-1880`, so `/ap/clock` is a byte-identical echo of the same value rather than an independent clock.

### 6.3 How `rtc_shift` is established

```
GPS 3D fix ------ AP_GPS::update_instance()               AP_GPS.cpp:983-991
                    time_epoch_usec(instance)
                      SITL: SIM_GPS.cpp:269-283 seeds from start_time_UTC,
                            itself gettimeofday() at process start,
                            overridable with --start-time <unix seconds>
                    -> set_utc_usec(now, SOURCE_GPS)        priority 0, bit 0
                                                                 |
MAVLink SYSTEM_TIME  GCS_Common.cpp:3915-3923                    |
                    -> set_utc_usec(t, SOURCE_MAVLINK_SYSTEM_TIME) priority 1, bit 1
                                                                 |
Board hardware RTC   AP_BoardConfig.cpp:504                      |
                    -> set_utc_usec(hw, SOURCE_HW)          priority 2, bit 2
                                                                 v
                                     AP_RTC::set_utc_usec        AP_RTC.cpp:47-101
                                       reject if worse than the source already in use
                                       reject if the bit is clear in BRD_RTC_TYPES
                                       reject if the time predates 2022-01-01
                                       reject if tmp < rtc_shift, never goes backwards
                                       -> rtc_shift = t - micros64()
```

`BRD_RTC_TYPES` is declared at `AP_RTC.cpp:29-35` with a default of 1, meaning GPS only. This is why the parameter is decisive on hardware and irrelevant in this SITL setup. On hardware the real time clock is the only thing that positions `/ap/*` stamps on the UNIX epoch, so which sources may write it is the whole question. In SITL with `/clock` connected, `update_topic` returns before the real time clock is consulted at all, so the parameter cannot influence a single stamp.

### 6.4 Why the `/clock` reader is a SITL-only facility

`AP_DDS_CLOCK_SUB_ENABLED` is defined at `AP_DDS_config.h:121-123` as `(CONFIG_HAL_BOARD == HAL_BOARD_SITL)`, inside an `#ifndef`, so a board could force it on with a build define. That is not sufficient to make it usable on hardware, for two reasons visible in the same tree.

The runtime opt-out is itself guarded by `#if AP_DDS_CLOCK_SUB_ENABLED && CONFIG_HAL_BOARD == HAL_BOARD_SITL` at `AP_DDS_Client.cpp:1542-1549`, and the second condition is not overridable by a define. On a hardware board with the macro forced on, the skip branch is compiled out entirely, so the `/clock` DataReader would be created unconditionally with no flag able to disable it.

The deeper objection is semantic. The mechanism replaces the sample time of a measurement with the value of a clock read at DDS serialisation time, so every `/ap/*` stamp would absorb the scheduler phase and the whole of the companion link latency, and would lose the sub-sample resolution the inertial measurement actually has. In simulation that is harmless, because the simulator clock is quantised at the physics step anyway and the sample and the serialisation happen in the same stopped-clock instant. On hardware it converts a good timestamp into a bad one.

### 6.5 The unused mechanism that would be correct

`modules/Micro-XRCE-DDS-Client/include/uxr/client/core/session/session.h:528-552` declares `uxr_sync_session(session, timeout)`, `uxr_epoch_millis(session)` and `uxr_epoch_nanos(session)`. The eProsima documentation describes this as an NTP-style exchange between client and agent from which the client computes its own offset, intended exactly for embedded targets with no other time source. Grepping `libraries/AP_DDS` for `uxr_sync_session` or `uxr_epoch` returns nothing, so ArduPilot links the capability and never calls it.

This is the only mechanism in the stack that would give a round-trip-compensated offset over the transport that is already there, with no additional wiring, no MAVLink dependency and no external reference. Adopting it is an upstream ArduPilot change, and it is the right thing to propose upstream if the MAVLink fallback in 6.6 proves insufficient in practice.

### 6.6 The options ranked, and the recommendation

| Option | Mechanism | Accuracy | Verdict |
|---|---|---|---|
| Common UTC reference | ArduPilot takes UTC from its own GPS with the default `BRD_RTC_TYPES=1`, and the companion's system clock is disciplined to the same UTC by chrony against GPS with PPS, or by NTP or PTP to a shared server | sub-millisecond with PPS, tens of milliseconds with plain NTP | Recommended for outdoor hardware. No ROS-level plumbing, no `/clock`, no `use_sim_time` on any node |
| MAVLink `SYSTEM_TIME` | the companion sends `SYSTEM_TIME`, ArduPilot sets `rtc_shift` from it. Requires `BRD_RTC_TYPES=2` so the GPS does not claim the higher-priority slot first. The mavros `sys_time` plugin implements the companion side, with `system_time_rate: 1.0` | tens of milliseconds, one-way and uncompensated, quantised by the send rate | Recommended fallback for indoor or GPS-denied hardware. This is the case the ArduPilot wiki's `BRD_RTC_TYPES=2` recommendation is written for |
| MAVLink `TIMESYNC` | round-trip exchange, `timesync_rate: 10.0` in mavros, which discards samples whose round trip exceeds 10 ms | bounded by the link | Adjusts the companion's estimate only. ArduPilot's handler at `GCS_Common.cpp:3773-3829` is a pure responder that writes a `TSYN` log record and moves no clock |
| DDS `/clock` override | force `AP_DDS_CLOCK_SUB_ENABLED` on for a hardware board | link latency enters every stamp | Rejected, see 6.4 |
| `uxr_sync_session` | NTP-style handshake over the existing uXRCE-DDS session | round-trip compensated | The principled answer, unimplemented upstream, see 6.5 |

The recommendation for hardware is therefore the first option, with the second as the GPS-denied fallback, and this is where the plan's SITL conclusion and the user's original instinct about `BRD_RTC_TYPES` converge rather than conflict. The parameter change is right, for the deployment it was written for, and wrong for this one.

Two constraints on the fallback deserve to be stated before it is relied upon. `set_utc_usec` refuses to move `rtc_shift` backwards under any circumstances, so a companion whose own clock steps backwards, which is exactly what an NTP daemon does on first sync after boot, will leave ArduPilot permanently ahead until the flight controller is power-cycled. The companion's clock must therefore be settled before it starts sending `SYSTEM_TIME`. And `set_utc_usec` hard-rejects any time before 2022-01-01, so a companion with no battery-backed clock that boots at the UNIX epoch cannot seed ArduPilot at all.

### 6.7 What this means for HITL and for VIO on hardware

HITL, where the autopilot runs on real hardware and the vehicle dynamics run on a host, is the harder case and not merely an intermediate one. The autopilot's `micros64()` is a real free-running oscillator that the simulator cannot step, so the lockstep property that SITL gets for free is unavailable, and the `/clock` override that SITL uses to paper over the origin difference is compiled out and inadvisable for the reasons in 6.4. The workable configuration is the same as for hardware, both the autopilot and the host are referred to one UTC reference, with the simulator publishing its own `/clock` for ROS consumers only and ArduPilot deliberately not reading it.

For visual inertial odometry specifically, a disciplined pair of clocks is necessary but not sufficient. `/ap/imu/experimental/data` is stamped at DDS publish time rather than at sample time, so on hardware it carries link jitter of the same order as the inter-sample interval, which is precisely the quantity Basalt's preintegration is sensitive to. The inertial stream for hardware VIO should come from a sensor on the companion computer, or from a hardware-triggered source sharing the camera's trigger domain, and the autopilot's inertial topic should be treated as telemetry rather than as an estimator input. That conclusion is independent of anything in this plan and is recorded here so the SITL result is not over-generalised.

## 7. Blast radius

| Consumer | Touched by | Effect |
|---|---|---|
| `djinn start sitl` | 5.9 | Runs the whole SITL stack on simulator time. This is the intended change. |
| `djinn start sitl basalt` | 5.10 | SLAM compute node on simulator time, controller on wall time. |
| `djinn start sitl orbslam3` | none | Already broken for unrelated reasons. |
| `ros2 launch controllers sitl.launch.py` by hand | 5.1 to 5.4 | Unchanged without `use-sim-time:=True`. |
| `ros2 launch controllers target_recorder.launch.py` by hand | 5.5 | Unchanged without the argument. |
| `ros2 launch sensors managed_logger.launch.py` by hand | 5.6 | Unchanged without the argument. |
| `ros2 launch slam basalt_slam.launch.py` by hand | 5.7 | Unchanged without the argument. |
| Tello stack, `tello_launch.py` and `tello_orbslam3_mono_launch.py` | none | No shared launch file is modified in a way that reaches them. |
| Video file replay through `video_reader` | none | It stamps with `now()` on wall time and is not part of the SITL graph. |
| Bags recorded before this change | none | Their contents are unchanged. Bags recorded after will have receive stamps in the simulator domain, which is a deliberate and documented difference. |
| `frontier_detection` | none | Sets `use_sim_time` to false explicitly and is unaffected. |

The shared launch files touched are `target_recorder.launch.py` and `managed_logger.launch.py`, both of which are reachable from the Tello recording path in principle. Both changes are additive arguments with false defaults, so that path is unchanged unless it opts in.

## 8. Validation

Four checks can run in the dev container, which has no ROS installation and therefore cannot build or launch anything. All four have been run and pass.

1. `python3 -m py_compile` on all five modified launch files. Passes, and it is what caught the corrupted topic-list entry repaired in 5.5.
2. `bash -n` on `/ws/djinn` and `run_ardupilot_airsim_ros_sitl.sh`. Passes.
3. A grep confirming that `use-sim-time` is declared in every file that reads it and that every forwarding key uses the hyphenated spelling, since a key matching no declared argument is silently discarded with no error. Passes, five declarations and three hyphenated forwarding sites, plus the one deliberately underscored `use_sim_time` key that targets `ardupilot_sitl`. This check is not optional given 4.3, because its failure mode is a graph that launches cleanly and runs half on each clock.
4. A grep confirming that the `use_sim_time` node parameter is set in exactly the two places 4.5 specifies, `managed_logger.launch.py:83` and `basalt_slam.launch.py:91`, and in neither of the two it forbids. Passes, `basalt_controller_node` and `video_logging_driver_node` carry no such entry.

The remainder must run against a live stack. A capture of both sides on 2026-07-28, `logs.txt` for the SLAM launch and `logs2.txt` for `sitl.launch.py`, settles five of them, and the results are annotated inline. The measurements and their consequences are in [`sitl-time-synchronisation.md`](../context/sitl-time-synchronisation.md) under the live-stack section.

The headline is that the mechanism works and the epoch offset is gone, the inertial lead over the camera having fallen from 6.13 s to 1.62 s, and that two defects the epoch offset had been masking are now the binding constraints. Neither is a clock synchronisation problem and neither is addressed by this plan. The first is an AirSim image delivery lag of `1.624 + 0.156 * elapsed` seconds. The second is that the stamp override quantises `/ap/*` to the `/clock` publication interval, which produced 27 distinct timestamps across 302 inertial messages, in runs of up to 24. Both are recorded as follow-up work in section 9.

5. `ros2 param get /airsim_node publish_clock` returns true.
6. `ros2 topic info /clock --verbose` shows one publisher, `airsim_node`, offering RELIABLE and VOLATILE.
7. `ros2 topic hz /clock` reports approximately one hundred hertz.
8. `ros2 topic echo /clock --once` returns a value close to the image header stamps and not to wall clock.
9. The SITL console prints `Using \clock topic for DDS timing: enabled` rather than the skipping message. PASSED 2026-07-28, `logs2.txt:53`.
10. `ros2 topic echo /ap/time --once` and the image header stamp agree to within one hundred milliseconds.
11. The absolute difference between an `/ap/imu/experimental/data` stamp and a contemporaneous image stamp is under fifty milliseconds, against six point one three seconds before this change. FAILED 2026-07-28, measured 1.624 s rising to 1.908 s. The epoch term is gone and the residual is the AirSim image delivery lag, which is outside the scope of this change.
12. `ros2 param get /basalt_slam_node use_sim_time` returns true, and the same query against `basalt_controller` returns false.
13. `ros2 param get /managed_logger_node use_sim_time` returns true, and the same against `video_logging_controller` returns false.
14. The Basalt log shows `popping from IMU data queue` recurring throughout the run rather than once, which is the direct signature of the preintegration loop functioning. FAILED 2026-07-28, it appears once at initialisation and every subsequent frame reports `imuData defined not popping`.
15. `imu data queue size` stays bounded well below three hundred. FAILED 2026-07-28, it reached the bound of 300 and the node stalled, `logs.txt:729`.
16. The node continues to emit pose output for a full flight rather than stopping. FAILED 2026-07-28, the local mapper reported `Queue wait time taken: 1.81147s` and the run was terminated by hand.
17. `~/annotated_frame` header stamps sit in the simulator domain.
18. A bag recorded through a full arm, fly and disarm cycle replays with `ros2 bag play --clock` and the replayed `/ap/*` and image stamps remain aligned.
19. `ros2 bag info` shows a duration consistent with the flight rather than an epoch-scale value.
20. Relaunching with `use-sim-time:=False` reproduces the six second offset exactly, confirming the revert path.
21. `ros2 launch controllers sitl.launch.py use-sim-time:=yes` is rejected at launch with a choices error rather than proceeding, confirming the validation described in 4.4.
22. Killing the AirSim bridge mid-run and observing that `/ap/*` stamps freeze, confirming the latching hazard of 3.4 is real and characterising how the stack degrades.
23. The transient at startup, where `/ap/*` stamps jump backwards by the offset once the first `/clock` arrives, does not disturb the video logging controller, which is expected to hold since it activates at arming and reads no stamps.

## 9. Deliberately not done

Patching the AirSim submodule so that `publish_clock` writes to `/clock` directly, for the reason in 4.2.

Any change to `airsim-quadX.parm` or to `BRD_RTC_TYPES`, for the reasons in 3.3, 5.11 and 6.3.

Any implementation of the hardware or HITL synchronisation described in section 6. That section is an architecture record produced by this investigation, and the work it describes belongs to hardware bring-up rather than to this change.

Setting `use_sim_time` on `basalt_controller` or `video_logging_controller`, for the reason in 4.5. The steps to do it later, and the watchdog changes that must accompany it, are specified in 4.6 rather than left to be rediscovered.

Wrapping parameter values in `launch_ros.parameter_descriptions.ParameterValue`, for the reason in 4.4. Validation is done once at declaration with `choices`.

Removing the `synthetic_clock` argument, which is a no-op but which upstream ArduPilot's own documentation and `ardupilot_gz` both still pass. It is annotated rather than removed.

Anything about the AirSim image delivery lag measured in section 8, `1.624 + 0.156 * elapsed` seconds. It is a throughput defect in the bridge and simulator, evidenced by the image callback achieving 15.7 Hz against a nominal 20 and the state callback 14.05 Hz against a nominal 100, and it is a separate problem from clock synchronisation that this change merely made visible.

Anything about the inertial stamp quantisation measured in section 8, 27 distinct timestamps across 302 messages. It is an unavoidable consequence of the stamp override, since `AP_DDS_Client::update_topic` copies `external_clock_time` verbatim and that variable changes only when a `/clock` sample arrives, so any `/ap/*` topic published faster than `/clock` emits runs of identical stamps. The conclusion it forces, that `/ap/imu/experimental/data` is a telemetry stream rather than a visual inertial odometry input, is the same conclusion 6.7 reaches for hardware and for the same structural reason, the stamp is applied at DDS publish time rather than at sample time. Choosing the replacement inertial source is a separate piece of work, and note that the obvious candidate `/airsim_node/Copter/imu/Imu` is published from `publish_vehicle_state()` inside `drone_state_timer_cb` at `airsim_ros_wrapper.cpp:1490-1495` and therefore inherits that callback's 14 Hz rate, so it has the right per-sample timestamp and the wrong rate.

Any watchdog on `/clock` liveness to guard the latching behaviour described in 3.4. Characterising the failure is check 22, and deciding whether it needs a guard should follow the observation rather than precede it.

Setting `use_sim_time` on `airsim_node`, which would make its dynamic vehicle transform consistent with its sensor stamps but which risks publishing a zero clock, for the reason in 4.5. Nothing in this stack consumes that transform.

Collapsing the four divergent copies of `topics_to_record`, a known follow-up recorded in `launch-and-djinn.md` and untouched here. The corrupted entry repaired in 5.5 is a reminder that four hand-maintained copies of one list is a defect waiting to recur.

## 10. Decisions taken

The offset is removed at its origin rather than estimated, because both endpoints already implement their half of the `/clock` mechanism and connecting them is exact where estimation is approximate.

The remap is done with `SetRemap` in a scoped group rather than with a relay node or a submodule patch, because it is the only option that adds no process and changes no source.

One flag named `use-sim-time` governs the whole feature, defaulting to false, so that no existing caller changes behaviour and so that the change is revertible in one argument for comparison against historical runs. The name mirrors the `use_sim_time` node parameter it sets, with the hyphenated spelling reserved for the launch argument and the underscored spelling for the parameter and for the `ardupilot_sitl` argument that becomes `--use_sim_time`.

The flag is validated once at declaration with `choices=["True", "False"]` rather than per parameter with `ParameterValue(value_type=bool)`, because `choices` rejects a malformed value earlier, covers the forwarding sites as well as the parameter sites, and adds less code, for the full reasoning in 4.4.

Sim time is refused on both controller nodes, because their only use of a clock is to bound how long they wait, and sim time would unbound that wait exactly when the simulator has failed. The refusal is conditional on what those nodes do today rather than permanent, and 4.6 records the exact steps and the accompanying watchdog changes for reversing it, so that the two nodes end up on the same mechanism the rest of the stack uses rather than acquiring an ad hoc one.

Sim time is granted to the recorder, because bag replay coherence depends on the receive stamps and the header stamps sharing a domain.

Sim time is granted to the SLAM compute node, because it produces stamps as well as consuming them, and refused to the AirSim bridge, because it produces none that matter and would risk publishing a zero clock.

`--use_sim_time` is bound to the flag rather than left to the upstream default, because an implicit default that arms a clock reader is a trap, and because binding it makes the false case provably equivalent to the pre-change stamping path.

`airsim-quadX.parm` is left untouched, because the MAVLink route cannot reach the stamping clock and because the branch it would influence does not execute once `/clock` is connected. This is a judgement about SITL and not about the parameter, and section 6 records that `BRD_RTC_TYPES=2` with a companion sending `SYSTEM_TIME` is the correct configuration for a GPS-denied hardware deployment.

Hardware and HITL synchronisation is designed but not implemented, because the mechanism that solves SITL is compiled out on hardware and is semantically wrong there in any case, and the mechanism that solves hardware, a common UTC reference with MAVLink `SYSTEM_TIME` as the GPS-denied fallback, requires hardware that is not yet in the loop.
