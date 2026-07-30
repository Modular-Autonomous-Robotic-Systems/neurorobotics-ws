# Basalt SLAM + SITL logging defect remediation

**Status:** IMPLEMENTED 2026-07-25 (Phases 1–3 complete, Phase 4 partial, Phase 5 blocked). **Branch:** `shreyas/learning_plan`. Nothing is committed — the changes sit in the working tree across the `/ws`, `ros_ws`, `slam`, `ext/basalt` and `tello` repositories.
**Outstanding:** the container-side validation in §7, which cannot run from the authoring environment (no ROS, no toolchain, no docker).
**Durable findings from the investigation now live in `context/`:** [`ros_ws/context/simd-eigen-abi-mismatch.md`](../ros_ws/context/simd-eigen-abi-mismatch.md), [`ros_ws/context/ros-qos-compatibility.md`](../ros_ws/context/ros-qos-compatibility.md), [`ros_ws/context/rosbag2-recording-architecture.md`](../ros_ws/context/rosbag2-recording-architecture.md), [`ros_ws/context/slam-lifecycle-flow.md`](../ros_ws/context/slam-lifecycle-flow.md), [`ros_ws/context/launch-and-djinn.md`](../ros_ws/context/launch-and-djinn.md), [`ros_ws/src/slam/context/`](../ros_ws/src/slam/context/README.md), [`context/ardupilot-dds-qos.md`](../context/ardupilot-dds-qos.md), [`context/sitl-workspace-migration.md`](../context/sitl-workspace-migration.md), [`context/djinn-workflows.md`](../context/djinn-workflows.md). Background tutorial: [`ros_ws/src/slam/context/SIMD.md`](../ros_ws/src/slam/context/SIMD.md).

## 1. Motivation

A single SITL session (`djinn start sitl basalt`) surfaced a chain of independent defects across five subsystems. They were diagnosed together and fixed together so the result is coherent, but each phase is independently landable and independently testable.

The headline defect was a **silent ABI mismatch**. `libbasalt.so` is compiled with `-march=native` (AVX-512 on the Zen 5 build host) while `basalt_slam_node`'s own translation units are not, so the two disagreed about `sizeof(basalt::Controller)` — 1056 bytes/align 32 versus 1008/align 16. Constructing that object in `on_activate` overflowed the heap by 48 bytes; the crash surfaced later, inside the dynamic loader, during an unrelated `dlopen`. Nothing in the visible backtrace was at fault.

Behind that crash sat a second class of defect: **things that fail silently because they never match**. A RELIABLE IMU subscriber against a BEST_EFFORT publisher. An `ap_type` of `"ArduPilot"` compared against the literal `"ardupilot"`. A Tello state string `"taking off"` compared against the driver's `"taking_off"`. Launch arguments forwarded under a key no launch file declares. In every case `ros2 node info` looked healthy, the logs claimed success, and no data flowed. The unifying lesson — recorded in the context files — is that in ROS 2 the absence of an error is not evidence of a connection.

The third strand was **recording the message that triggered recording**. The recorder's subscriptions are created inside `on_activate`, so a trigger message is by definition published before anything is listening. Capturing it requires both that the publisher retained the sample and that activation happens before that sample is superseded. Neither platform satisfied both conditions, for different reasons.

## 2. What changed, by phase

| Phase | Scope | Repositories touched | Status |
|---|---|---|---|
| 1 | Eigen/`-march` ABI coherence | `slam`, `ext/basalt`, `/ws` | Done |
| 2 | `BasaltSLAMNode` / `BasaltSLAM` correctness | `slam` | Done |
| 3 | Video logging controller lifecycle, trigger capture, string/argument matching | `ros_ws` (`controllers`, `sensors`), `tello`, `/ws` | Done |
| 4 | Bake rosdep-resolved runtime deps into the image | `/ws` | Partial — see §5 |
| 5 | AirSim submodule conflict markers + client/server API skew | `sitl_ws` | **Not started — blocked on a decision**, see §6 |

Phases 1 and 2 must land together: Phase 2 contained a build blocker, so nothing compiled without it, and Phase 1's defect was only reachable once the node survived activation. Within Phase 3, Changes 3.2 + 3.3 must land together for ArduPilot and 3.2 + 3.6 for Tello, or nothing starts recording on that platform.

---

## 3. Phase 1 — Eigen/`-march` ABI coherence

**Root cause.** `slam/CMakeLists.txt` calls `add_subdirectory(ext/basalt)` and then declares `basalt_slam_node` in the **parent** scope. `ext/basalt/CMakeLists.txt` defaults `CXX_MARCH` to `native` and folds `-march=${CXX_MARCH}` into `CMAKE_CXX_FLAGS`, but CMake `set()` without `PARENT_SCOPE` is directory-scoped, so the parent's target never receives it. `-march=native` on an AVX-512 host defines `__AVX512F/DQ/BW/VL/CD__`; Eigen reads those macros and raises `EIGEN_MAX_ALIGN_BYTES` from 16 to 64, changing the layout of every fixed-size vectorizable Eigen type and everything embedding one by value — including `basalt::Controller` via `Calibration<double>` → `CalibGyroBias<double>` → `Eigen::Matrix<double,12,1>`.

### 3.1 Change 1.1 — pin `EIGEN_MAX_ALIGN_BYTES`

`ros_ws/src/slam/CMakeLists.txt`, as the first statement of the `elseif(SLAM_TYPE STREQUAL "BASALT")` branch, immediately before `add_subdirectory(ext/basalt)`:

```cmake
add_compile_definitions(EIGEN_MAX_ALIGN_BYTES=16 NRT_EIGEN_ABI_PIN=16)
```

The placement is the whole mechanism: `add_compile_definitions()` populates the `COMPILE_DEFINITIONS` **directory property**, inherited only by subdirectories added and targets created *after* the call. It lands in `CXX_DEFINES` rather than `CXX_FLAGS`, which is load-bearing because `ext/basalt/CMakeLists.txt:265` overwrites `CMAKE_CXX_FLAGS` wholesale — anything routed through `CXX_FLAGS` would be silently discarded. 16 rather than 32 so that basalt agrees with every distribution-built ROS 2 package in the same process (`rclcpp`, `tf2_eigen`, `cv_bridge`), all compiled without `-march`.

A NOTE was added to the `ORBSLAM3` branch recording that the same pin is required there if `-march` is ever introduced; ORB-SLAM3 and its vendored g2o/DBoW2 are currently built without it and are self-consistent at the default 16.

**Backwards compatibility.** No source, header, message, service, parameter, launch-argument or topic-name change; nothing outside the `slam` package observes this. It *is* an ABI change, so **every previously built artefact of the `slam` package must be discarded** — `rm -rf /ws/ros_ws/{build,install,log}/slam` — not incrementally rebuilt, or `colcon` will mix old and new object files and reproduce the same class of bug with different numbers.

### 3.2 Change 1.2 — compile-time guards on both sides of the boundary

Two `static_assert`s, because the two sides share no header (`ext/basalt` never includes anything from `include/slam/`):

- `ros_ws/src/slam/include/slam/slam.hpp`, after `#include <Eigen/Geometry>` — covers every parent-scope TU that can construct a basalt type.
- `ros_ws/src/slam/ext/basalt/src/controller.cpp`, after the includes and before `namespace basalt` — the definition site of the exact type that diverged.

Both read `static_assert(EIGEN_MAX_ALIGN_BYTES == NRT_EIGEN_ABI_PIN, …)` and both are wrapped in `#ifdef NRT_EIGEN_ABI_PIN`, so a standalone upstream basalt build — which its own `.gitlab-ci.yml` performs — is unaffected. The assert passes trivially while both definitions reach the TU and fires the moment the `-D` stops arriving.

### 3.3 Change 1.3 — per-architecture `CXX_MARCH`

`scripts/build_ros_packages.sh` now selects `CXX_MARCH` from `uname -m` (`x86-64-v3` on amd64, `armv8.2-a+fp16+dotprod` on aarch64, `native` otherwise) and passes `-DCXX_MARCH=${CXX_MARCH}` through `--cmake-args`. The selection is guarded by `if [ -z "${CXX_MARCH}" ]`, so `CXX_MARCH=native ./scripts/build_ros_packages.sh` reproduces the old behaviour exactly for a benchmark.

Necessary because `install/` is a mounted tree that outlives the container and can be carried to a host without AVX-512 (`SIGILL`); because `native` is meaningless under `docker buildx --platform`, where on aarch64 it degrades silently rather than erroring; and because a single global value cannot serve both architectures — `ext/basalt/CMakeLists.txt:89` still emits `-march=` on Linux/aarch64, where an x86 value is a hard compiler error.

**Backwards compatibility.** `-DCXX_MARCH` is consumed only by `ext/basalt`; grep confirms no other package in `ros_ws` reads it, so passing it globally is inert elsewhere. Floating-point results will differ in the last digits from the `native` build, because FMA contraction and vector width differ between arch levels — **do not validate by diffing trajectory files**; compare against ground truth with an ATE/RPE metric.

### 3.4 Change 1.4 — document the hazard at the point of temptation

A warning comment above `ext/basalt/CMakeLists.txt`'s `if(NOT CXX_MARCH)` default, recording that `-march` is an ABI switch and that the directory-scoped `set()` does not cross into a parent project's targets.

---

## 4. Phase 2 — `BasaltSLAMNode` / `BasaltSLAM` correctness

| Change | File | What |
|---|---|---|
| 2.1 | `src/basalt/node.cpp` | **Applied manually before this work, verified correct.** The SLAM-mode selection previously passed a hardcoded `"monocular-only"` regardless of `slam_type`; now `VSLAM` → `"monocular-only"` → `SlamMode::VO` and `VISLAM` → `"monocular-inertial"` → `SlamMode::VIO`, consistent end to end. |
| 2.2a | `src/basalt/slam.cpp` | **Build blocker.** `std::make_shared<basalt::OpticalFlowInput()>` → `std::make_shared<basalt::OpticalFlowInput>()`. The old form named a *function type* in the template argument and omitted the call parentheses. `OpticalFlowInput` is a plain aggregate (`int64_t t_ns`, `std::vector<ImageData> img_data`) with no user-declared constructor, so it takes no camera count and value-initialisation is correct. |
| 2.3 | `src/basalt/node.cpp` | `std::make_unique<tf2_ros::TransformBroadcaster>(tf2_ros::TransformBroadcaster(this))` → `std::make_unique<tf2_ros::TransformBroadcaster>(this)`. The old form built a `TransformBroadcaster` (creating a `/tf` publisher), copied it into the `unique_ptr`, then destroyed the original. |
| 2.4 | `src/basalt/node.cpp` | IMU subscription QoS: bare depth `10` → `rclcpp::SensorDataQoS()`. A bare depth means RELIABLE; `/ap/imu/experimental/data` is published BEST_EFFORT/VOLATILE/KEEP_LAST(5) by AP_DDS, so the endpoints never matched and VIO ran with zero IMU measurements while every log line looked healthy. |
| 2.5 | `CMakeLists.txt` | Deleted the malformed `install(TARGETS DESTINATION "${PYTHON_INSTALL_DIR}/${PROJECT_NAME}")` in the ORBSLAM3 branch — empty target list, and `PYTHON_INSTALL_DIR` is never set, so the destination expanded to the absolute path `/slam`. |
| 2.6 | `src/basalt/node.cpp` | `std::cout << "Received Image"` per frame → `RCLCPP_DEBUG`. |

**Backwards compatibility.** 2.4 is the only change with a propagation question, and it strictly *widens* compatibility: BEST_EFFORT is the weakest request, so the new subscriber matches BEST_EFFORT publishers (AP_DDS live) *and* RELIABLE ones (`ros2 bag play` replay). Durability stays VOLATILE, which is load-bearing — a TRANSIENT_LOCAL subscriber would not match a VOLATILE publisher and would break replay. **No ORB-SLAM3 propagation is required**: `slam/src/orbslam3/monocular.cpp` has no IMU subscription at all, and the one topic the two back-ends share (`/ap/status`, via the shared `driver_node.py` base class) is already compatible and untouched. That conclusion is the result of a full audit, not an assumption — the matrix is in [`ros_ws/context/ros-qos-compatibility.md`](../ros_ws/context/ros-qos-compatibility.md).

---

## 5. Phase 3 — Video logging controller

### 5.1 Change 3.1 — the initial `get_state` could never resolve

`main()` constructs `VideoLoggingDriver` and only *afterwards* calls `executor.add_node()` and `executor.spin()`. A service response is delivered by the executor, so during the constructor nothing could deliver it: the `wait_for` always exhausted `service_call_timeout_ms` (10 s) and reported a bogus failure. (`WaitForAllRegisteredServices()` succeeding is not a contradiction — it uses `wait_for_service`, driven by graph-discovery events rather than by the executor.)

The query moved to a zero-delay one-shot timer on the reentrant callback group, which fires as soon as spinning starts. `QueryInitialState()` cancels its own timer and hands the future to `EnqueueServiceResponseHandlerTask`, which is the base class's existing worker-thread mechanism for exactly this — blocking on `wait_for` inside the timer would deadlock a single-threaded executor and occupy an executor thread for up to 10 s even on a multi-threaded one. The `initial_constructor_get_state` context string is preserved so existing log-scraping still works. `SetupROSInterfaces()` stays in the constructor, so subscribers exist before the node is ever spun.

`LifecycleControllerBase` is untouched, so `tello_controller_node` — the other derived class — is entirely unaffected. That was the deciding factor in fixing the derived class rather than adding a deferred-init hook to the base.

### 5.2 Change 3.2 — chain configure → activate so the trigger message is recorded

**The problem.** The recorder's subscriptions are created inside `Recorder::record()`, i.e. inside `on_activate`. Everything published before that instant is lost unless the publisher retained it via `TRANSIENT_LOCAL`. A trigger message is by definition published before the activation it triggers. The two platforms failed this differently:

- **ArduPilot latched but activated too late.** `/ap/status` is the only latched `/ap/*` topic (TRANSIENT_LOCAL, depth 1), but the lifecycle used *two* events: arming configured, and the chain-to-activate test required `mpPreviousFlyingStatus && mpPreviousArmedStatus` — with `mpPreviousFlyingStatus` still false at arming, activation waited for the separate flying edge, seconds later. By then the depth-1 latch held the *flying* status; the arming status was superseded and gone.
- **Tello activated promptly but did not latch.** `TelloStatusCallback` sets both flags from one message, so the chain genuinely fired — but `tello_state` was VOLATILE and is published only on state edges with no keep-alive, so the triggering message was unrecoverable the instant it was sent.

**The fix, symmetric on both platforms**, in `controllers/src/logging/video_controller.cpp` plus one line in `tello_driver`:

**3.2b-i — chain on armed alone.** In `OnVideoLoggerChangeStateResponse`, the configure-success branch now tests `if (this->mpPreviousArmedStatus)` instead of `mpPreviousFlyingStatus && mpPreviousArmedStatus`. Branch A of the status callbacks is therefore the only trigger that matters on both platforms: arming (ArduPilot) or `taking_off`/`flying` (Tello) configures, and the response chains straight into activation.

**3.2b-ii — publish the status flags *before* dispatching, not after.** This is required, not cosmetic. 3.2b-i reads `mpPreviousArmedStatus` from a worker thread, and both callbacks used to assign it *after* the async dispatch. The configure round-trip to a local node is sub-millisecond, so the response handler could observe the flag still `false` and silently skip the chain — configure succeeds, activate never happens, the bag directory exists but stays empty. The two assignments moved above the dispatch block in both callbacks; the branch conditions have already consumed the previous values by then, so nothing else changes. In `TelloStatusCallback` the existing function-wide `mpcStatusMutex` lock already covers them; in `ArduPilotStatusCallback` they are wrapped in their own scoped lock.

**3.2b-iii — the flying branch becomes a state-based fallback.** `currentFlying && !mpPreviousFlyingStatus && currentArmed` became `currentFlying && currentArmed && mpVideoLoggerKnownState != PRIMARY_STATE_ACTIVE`, in both callbacks. It now covers a missed arming message (driver started mid-flight, dropped sample) rather than being the primary trigger, and it is idempotent because the guard is "not ACTIVE". The `UNKNOWN` state was added alongside `UNCONFIGURED` in its chained-configure sub-branch.

**3.2c — latch `tello_state`.** `tello/tello_driver/src/tello_driver_node.cpp`: `create_publisher<std_msgs::msg::String>("tello_state", rclcpp::QoS(1).transient_local())`. TRANSIENT_LOCAL is a stronger *offer*, and DDS matches when offered ≥ requested, so every existing volatile subscriber keeps matching unchanged — `video_controller.cpp`, `driver_node.py` and `tello/controller.cpp` needed no edit. It also makes `ros2 topic echo /<ns>/tello_state` show the current state immediately, which it previously did not. `tello_gazebo` defines the same strings but does not publish this topic, so `tello_driver` is the sole publisher and the recorder's `adapt_request_to_offers()` will negotiate transient-local.

**3.2 launch-side.** `target_recorder.launch.py`'s `start_logging_pub` (`ExecuteProcess` publishing a start signal) and its `delayed_start_logging` event handler were deleted. Nothing replaces them: the arming edge now starts recording, which is what the `ExecuteProcess` was approximating, and it does so early enough that the trigger message is still the retained sample. The `start_topic` parameter and the `mpStartSubscriber` it configures are **unchanged**, so manual triggering with `ros2 topic pub /video_logging_controller_node/start_logging std_msgs/msg/String "{data: 'start'}"` still works.

**Why this captures the trigger.** On ArduPilot the chain is two local service round-trips plus bag creation — order tens of milliseconds, dominated by `writer_->open()`. The next `/ap/status` publication is either the 500 ms keep-alive, which carries *identical content* because `update_topic()` republishes only on change or on the timer, or the flying edge, which is seconds away since something must command takeoff. Either way the retained sample at subscription time still reads `armed=1, flying=0`. On Tello the latched message is retained indefinitely, so there is no deadline at all. The one way to erode the ArduPilot margin is a slow `on_configure`; `UpdateFilenameIfExists` recursing over a directory with very many existing bags is the realistic candidate.

**Change 3.2a was deliberately skipped.** `sensors/src/logger/managed_logger.cpp:71-84` carries a **commented-out** `topic_qos_profile_overrides` block that would force VOLATILE + BEST_EFFORT on every recorded topic — the exact opposite of its own comment, since an override entry bypasses `adapt_request_to_offers()` entirely and would defeat both halves of this change. It was left commented rather than deleted by explicit decision. **Do not uncomment it.**

**Approaches considered and rejected**, recorded so they are not revisited: an `auto_start` parameter (preserved start-at-launch but not the intent); relying on transient-local negotiation alone (insufficient — depth-1 supersession on ArduPilot, no latch at all on Tello); a `~/log_message` service injecting the cached trigger through `rosbag2_cpp::Writer` (needed a new srv, a new service, serialisation plumbing and a cross-process hop, all to work around a lifecycle that simply activated too late); `Recorder::pause()`/`resume()` or `--start-paused` ([ros2/rosbag2#1302](https://github.com/ros2/rosbag2/issues/1302) documents that starting paused loses latched topics entirely); snapshot mode (right tool for a future "keep the 30 s before arming" feature, wrong for continuous post-arm recording); and raising the AP_DDS latch depth (means reflashing firmware and does nothing for Tello).

### 5.3 Change 3.3 — `ap_type` case mismatch

`target_recorder.launch.py` declared `default_value="ArduPilot"` and `/ws/djinn` passed `ap_type:=ArduPilot`, while `video_controller.cpp` compares against the lowercase literal `"ardupilot"`. **No `/ap/status` subscriber was ever created** — and an unconditional "Status subscriber created on topic '%s'" log fired regardless, which is what made it hard to spot.

Both callers are now lowercase, and `SetupROSInterfaces()` logs per branch: "ArduPilot status subscriber created…", "Tello status subscriber created…", or an `RCLCPP_WARN` naming the unrecognised value and listing the supported ones. The warning text is rendered from `DRIVER_SUPPORTED_AP_TYPES` by a file-local helper, so the list of valid spellings now has exactly one definition — an unused list of valid values is what let the two spellings drift apart.

The **`/ap/status` subscription QoS was deliberately not changed.** The audit shows the current default profile already matches the publisher; changing it is the one thing here that could break a working path.

Callers audited, and the set is closed (grep confirms these are the only occurrences of `ap_type`): `/ws/djinn` and `target_recorder.launch.py` changed; `video_controller.h`'s `DRIVER_DEFAULT_AP_TYPE` was already lowercase; `sitl.launch.py` and `basalt_slam_test.launch.py` gained the argument in Change 3.4, though `basalt_slam_test.launch.py`'s was removed again by §5.4a and `/ws/djinn` no longer passes it on the `basalt` path; `tello_controller.launch.py` already passed lowercase `"tello"`. An external caller still passing `ArduPilot` now gets a loud, diagnosable warning instead of a silent no-op.

### 5.4 Change 3.4 — `ap_type` was not forwarded down the launch chain

Two links dropped it, and both are fixed.

**Link 1, `sitl.launch.py` → `target_recorder.launch.py`.** It now declares `ap_type`, `output_bag_name` and `topics_to_record` (each defaulting to the value effectively in force before) and forwards all five arguments. **The `log_level` key was also wrong**: `target_recorder.launch.py` declares the argument as `"log-level"` with a hyphen, so the `"log_level"` key matched nothing and `log-level:=DEBUG` never reached the video logging controller.

**Link 2, `basalt_slam_test.launch.py` → `sitl.launch.py` — superseded 2026-07-26, see §5.4a.** This link originally forwarded the same three arguments plus `log-level` and `ap_status_topic_name`, with the `IncludeLaunchDescription` moved below the declarations so the `LaunchConfiguration` objects existed before the dict was built. That entire link has since been deleted along with the include itself.

**Backwards compatibility, and one deliberate behaviour change.** Every new argument defaults to the value effectively in force today, so a caller that passes nothing sees identical behaviour. But `djinn`'s `topics_to_record` list and `sitl.launch.py`'s differ, so *making the forwarding work* changes which topics get recorded — the outermost copy now wins. That was the intended outcome for Link 1, which remains in force. `input_topic`, `ffmpeg_topic` and `ffmpeg_node_name` were never declared anywhere in the chain and were always discarded; the encoder's topics are hardcoded in `sitl.launch.py`.

### 5.4a Follow-up (2026-07-26) — `basalt_slam_test.launch.py` no longer includes `sitl.launch.py`

Change 3.4's Link 2 rested on a premise that turned out to be wrong: that `basalt_slam_test.launch.py` should configure the stack `sitl.launch.py` brings up. In fact the two are launched by **separate `djinn` invocations**. `djinn start sitl` spawns the persistent `airsim_container`, and `djinn start sitl basalt` then execs `basalt_slam_test.launch.py` into the already-running `nrt_container`. Including `sitl.launch.py` from there started a **second** AirSim bridge, ArduPilot SITL, ffmpeg encoder and `managed_logger_node` on top of the live ones.

That duplicate recorder is a concrete failure, not a tidiness issue: two `managed_logger_node` instances race for `/ws/data/telemetry`, and the loser's `on_activate` throws `Database directory already exists (/ws/data/telemetry)`, leaving that instance stuck outside `ACTIVE`. Combined with the level-triggered recovery branch in `ArduPilotStatusCallback`, the controller then retries the failing activation at the `/ap/status` keep-alive rate for the rest of the flight.

**What changed.** `basalt_slam_test.launch.py` is now SLAM-only: the `sitl_launch` include, its entry in `delayed_seq_launch`, the `ap_type` / `output_bag_name` / `topics_to_record` declarations (including this file's copy of the 18-entry topic list), and the now-dead `controllers_launch_dir` binding are all deleted. `ap_status_topic_name` stays — `basalt_slam_controller` consumes it as the `ardupilot_status_topic` param — but is no longer forwarded anywhere. `sitl.launch.py` is untouched and is the sole owner of the recorder. `/ws/djinn`'s `basalt` branch dropped the six arguments that would now declare nothing (`ap_type`, `output_bag_name`, `topics_to_record`, `input_topic`, `ffmpeg_topic`, `ffmpeg_node_name`), with a comment recording why.

**Backwards compatibility.** Recorder settings are no longer reachable from `basalt_slam_test.launch.py`'s command line; pass them to `djinn start sitl` / `sitl.launch.py`. Anyone who relied on `basalt_slam_test.launch.py` to bring up the whole stack single-handedly must now run `djinn start sitl` first — which is what `djinn` already did.

`topics_to_record` is down from five divergent copies to **four** (`sitl.launch.py`, `target_recorder.launch.py`, `sensors/launch/managed_logger.launch.py`, `/ws/djinn`); this file's copy is gone. Collapsing the rest to one source of truth remains the deferred follow-up in §8.

### 5.5 Change 3.5 — `ffmpeg_encode` dead duplicate

`target_recorder.launch.py` contained a commented-out copy of `sitl.launch.py`'s `ffmpeg_encode` include, plus `delayed_launch.actions.append` calls referencing a `delayed_launch` that does not exist in that file — so uncommenting it would have raised `NameError` *and* launched the encoder twice. Deleted, with a note recording where the real include lives.

### 5.6 Change 3.6 — the Tello state strings never matched the controller

`tello_driver/include/tello_driver_node.hpp` is the authority: `idle`, `landed`, **`taking_off`**, `flying`, `landing`, `low_battery`. Both consumers compared against `"taking off"` **with a space**, so the takeoff edge was ignored entirely in both the recording and the SLAM lifecycle paths; `landing`, `idle` and `low_battery` had no branch at all and fell through to the "not flying" path, tearing recording down at the *start* of the landing manoeuvre and — for `low_battery` — mid-flight.

`video_controller.cpp` now handles the full enum: exact `taking_off`; `flying` unchanged; an explicit `landing` branch that **keeps recording through touchdown** (teardown happens on `landed`), carrying the current armed state forward rather than asserting one so the message cannot re-trigger the arming branch; `landed`/`idle` tearing down; `low_battery` warning without changing state; and an unrecognised-string warning. `controllers/controllers/slam/driver_node.py` gets the same `taking_off` fix — without it the Tello SLAM path stays broken independently of the recording path.

The `landing` semantics implement the recommendation in the plan's review question 6 (record through touchdown) rather than the alternative of preserving the previous *effective* behaviour. This is the one place where the shipped behaviour differs from the change's literal code snippet, and it is called out here because it is a behavioural choice rather than a bug fix.

### 5.7 Known gap: teardown is still keyed on the flying edge

Branch C fires on `!currentFlying && mpPreviousFlyingStatus`. Now that recording *starts* on the arming edge, an **arm → disarm without ever taking off** leaves the logger `ACTIVE` indefinitely, because no flying edge ever falls. The normal land-then-disarm sequence is unaffected, since landing lowers `flying` first. Making teardown symmetric with the new start condition would mean extending branch C to `(!currentFlying && mpPreviousFlyingStatus) || (!currentArmed && mpPreviousArmedStatus)`. **Deliberately not done** — branch C was explicitly out of scope, and this is a behavioural decision. Flagged in §8.

---

## 6. Phase 4 — runtime dependencies in the image (partial)

**The rule, now recorded in [`context/sitl-workspace-migration.md`](../context/sitl-workspace-migration.md):** with `--rm` containers and mounted, persistent `install/` trees, every rosdep-resolved runtime dependency must be baked into the image. Anything a build script `apt-get`s lives only in that container's writable layer and is destroyed on stop, while the prebuilt binaries survive — so the next container runs binaries whose shared libraries no longer exist. The observed failure was a fatal `dlopen` of `libgeographic_msgs__rosidl_typesupport_fastrtps_cpp.so`.

**Done:** `docker/ardupilot/Dockerfile` already carries the additions in the working tree (`libbz2-dev`, `ros-humble-geographic-msgs`, `ros-humble-ament-black`, `ros-humble-launch-pytest`, `python3-geopy`, `python3-geographiclib`), with `libbz2-dev` moved out of the `pip install` list where it was a no-op, and the dead `ros2.repos`/`vcs import` block removed. Uncommitted; correct as-is. The two misspelled dependency keys in `ros_ws/src/sensors/package.xml` — `lifecyle_msgs` and `rosbag2_trasport` — are also fixed, which matters because **a typo'd rosdep key is invisible to `rosdep install --simulate`**: it under-reports rather than erroring, so an audit run before this fix would have been misleading.

**Not done, requires a container:** the full rosdep-closure audit (`rosdep install --from-paths … --simulate` for `ardu_ws` and `sitl_ws/src/ue5/AirSim/ros2/src` inside a fresh container, adding every resulting apt package), and the image rebuild/publish (`djinn init docker nrt` then `docker pull`, since `docker-build.sh` uses `buildx … --push` which does not load locally).

---

## 7. Validation

None of this could be run from the authoring environment — it has no ROS, no rosbag2 headers, no `ros2` CLI, no compiler toolchain and no docker. What **was** verified statically: all four edited Python files compile (`python3 -m py_compile`); `djinn` and `build_ros_packages.sh` parse (`bash -n`); brace balance holds in every edited C++ file; the `EnqueueServiceResponseHandlerTask` overload taking a `const std::string &context` exists and is unambiguously selected; `mpCallbackGroupReentrant` and `mpServiceCallTimeoutMs` are accessible base-class members; and a blast-radius sweep confirms no stale `"taking off"`, `ap_type:=ArduPilot`, `PYTHON_INSTALL_DIR` or `start_logging_pub` references remain anywhere in the tree.

### 7.1 Phase 1 — the decisive checks

1. `rm -rf /ws/ros_ws/{build,install,log}/slam`, then rebuild via `scripts/build_ros_packages.sh`. **Do not build incrementally.**
2. Both sides carry the definitions:
   ```bash
   grep CXX_DEFINES /ws/ros_ws/build/slam/CMakeFiles/basalt_slam_node.dir/flags.make \
                    /ws/ros_ws/build/slam/ext/basalt/CMakeFiles/basalt.dir/flags.make
   ```
   Both must show `-DEIGEN_MAX_ALIGN_BYTES=16` and `-DNRT_EIGEN_ABI_PIN=16`.
3. `grep ^CXX_FLAGS /ws/ros_ws/build/slam/ext/basalt/CMakeFiles/basalt.dir/flags.make` must show `-march=x86-64-v3`, not `-march=native`.
4. **The pass/fail criterion for Phase 1** — the layouts agree:
   ```bash
   for o in /ws/ros_ws/build/slam/ext/basalt/CMakeFiles/basalt.dir/src/controller.cpp.o \
            /ws/ros_ws/build/slam/CMakeFiles/basalt_slam_node.dir/src/basalt/slam.cpp.o; do
     echo "== $o"
     objdump --dwarf=info "$o" | grep -A6 'DW_AT_name.*: Controller$' | grep -E "byte_size|alignment"
   done
   ```
   Both must report identical `DW_AT_byte_size` and `DW_AT_alignment`. Expected: 1008 / 16.
5. `objdump -d /ws/ros_ws/build/slam/ext/basalt/libbasalt.so | grep -c '%zmm'` should be 0 under `x86-64-v3` (`%ymm` non-zero is expected and desirable).
6. Negative test for the guards: configure with a deliberately wrong `NRT_EIGEN_ABI_PIN=32` and confirm the `static_assert` fires in **both** `controller.cpp` and a parent TU.
7. Record before/after timing on a fixed EuRoC sequence so the cost of Changes 1.1/1.3 is measured rather than assumed. Compare per-frame VIO and BA stage timings, not just wall clock.
8. Optional regression run under `MALLOC_CHECK_=3 MALLOC_PERTURB_=42` to confirm no residual heap damage.

### 7.2 Phase 2

1. The package compiles at all (Change 2.2a).
2. `ros2 lifecycle get /basalt_slam_node` reports `active` after the controller drives it, and `on_activate` completes past the `TransformBroadcaster` construction.
3. `ros2 topic info -v /ap/imu/experimental/data` shows the subscriber **matched**, with `Reliability: BEST_EFFORT` and a non-zero match count. `ros2 node info` cannot distinguish "subscribed" from "actually receiving" — this is the only check that can.
4. `ros2 topic hz /basalt_slam_node/annotated_frame` is non-zero.
5. `cmake -DSLAM_TYPE=ORBSLAM3` now configures without error (Change 2.5). That build remains blocked for unrelated reasons — see §8.

### 7.3 Phase 3

1. **No** "Timeout waiting for initial state future" warning; instead `Actual state of 'managed_logger_node' (initial_constructor_get_state): Unconfigured`. The constructor should finish in well under a second rather than ~10 s — time it from the log timestamps.
2. `ros2 node info /video_logging_controller` lists a subscriber on `/ap/status`, the log line reads "ArduPilot status subscriber created…", and `ros2 topic info -v /ap/status` shows it matched.
3. `ros2 lifecycle get /managed_logger_node` reports `unconfigured` after launch and stays there until the vehicle arms — the launch-time start signal is gone.
4. **Arm the vehicle and do not take off.** `ros2 lifecycle get /managed_logger_node` must already report `active` and the bag must start growing. This is the behaviour that did not exist before.
5. **The decisive check, ArduPilot:** read the first `/ap/status` message in the bag. It must carry `armed: true, flying: false`. If it carries `flying: true`, the chain did not fire on arming — check the flag-ordering fix (3.2b-ii) first.
6. **The decisive check, Tello:** `ros2 launch controllers tello_controller.launch.py`, issue `takeoff`, read the first `/<ns>/tello_state` message in the bag. It must be `"taking_off"`. Absent ⇒ 3.2c (latching) did not apply; late or `"flying"` ⇒ 3.6 (strings) did not apply.
7. While recording, `ros2 topic info -v /ap/status` and `ros2 topic info -v /<ns>/tello_state` must both list the `managed_logger_node_internal` subscriber with `Durability: TRANSIENT_LOCAL`. `VOLATILE` on either ⇒ `adapt_request_to_offers()` fell back — check for a second publisher, or for a reintroduced `topic_qos_profile_overrides`.
8. Take off after arming and confirm **no** second lifecycle transition is attempted — the fallback branch must find the logger already `ACTIVE`. No "Transition 'Activate' FAILED" line.
9. Land and confirm branch C still deactivates and cleans up as before.
10. `ros2 topic echo /<ns>/tello_state` through a full takeoff → land cycle: the strings must be exactly `taking_off`, `flying`, `landing`, `landed`, and the lifecycle transitions must line up with them — including recording continuing through `landing`.
11. `ros2 launch controllers target_recorder.launch.py ap_type:=nonsense` logs the new warning and creates no subscriber; `ap_type:=ArduPilot` now also warns (it no longer silently half-works).
12. `ros2 param get /video_logging_controller ap_type` returns the value `djinn` passed, proving both links of Change 3.4; and `log-level:=DEBUG` produces debug output from the video logging controller, proving the key fix.

### 7.4 Failure modes to watch

| # | Failure | Platform | Symptom |
|---|---|---|---|
| 1 | Flag ordering reverted (3.2b-ii) | Both | Configure succeeds, activate never chains; bag directory exists but stays empty |
| 2 | `topic_qos_profile_overrides` uncommented | Both | Recording works, trigger message missing |
| 3 | 3.2c reverted | Tello | Recording works, `tello_state` has no message until `landing` |
| 4 | `on_configure` slow over many existing bags | ArduPilot | Trigger replaced by a keep-alive of identical content — harmless, but the timestamp drifts up to 500 ms |
| 5 | A second publisher appears on a trigger topic | Both | `adapt_request_to_offers()` falls back to volatile; latched sample lost |
| 6 | Duplicate ACTIVATE from the un-edge-gated fallback | Both | Spurious "Transition 'Activate' FAILED" ERROR; self-corrects |
| 7 | `use_sim_time` enabled on the recorder | Both | `record()` skips the initial `subscribe_topics()` and waits for `/clock` |
| 8 | Arm then disarm without taking off | Both | Logger stays `ACTIVE`; see §5.7 |

---

## 8. Out of scope, and open follow-ups

Recorded so they are not rediscovered and so each exclusion is explicit.

1. **Phase 5 — AirSim submodule, blocked on a decision.** `sitl_ws/src/ue5/AirSim/docker/Dockerfile_source` has three unresolved merge-conflict blocks (the "Stashed changes" side is clearly the intended one — it carries the documented system-clang/libc++ workaround). Separately, `airsim_node` logs `Client Ver:3 (Min Req:4), Server Ver:4 (Min Req:3)`, because `Dockerfile_source` does an **unpinned** `git clone` of Cosys-AirSim while the ROS wrapper is built from the pinned submodule. The choice is (a) bump the submodule to the ref the image was built from — cheap, but unknown wrapper API changes — or (b) pin the clone to the submodule's ref and rebuild the UE image — a long build, but keeps the known-good wrapper. **Recommendation: (b) plus pinning**, because the submodule ref is what this workspace's AirSim camera/IMU calibration context was derived against.
2. **Teardown symmetry** — see §5.7. One-line change, but a behavioural decision.
3. **`djinn start sitl orbslam3` cannot run.** `/ws/djinn` launches `slam orbslam3.launch.py`, which does not exist (`slam/launch/` contains only `basalt_slam.launch.py`), and `mono_driver_node.py` uses `MultiThreadedExecutor` without importing it — raising `NameError` swallowed by a broad `except`. Change 2.5 removed one of the three blockers; the other two belong to the ORB-SLAM3 path and deserve their own plan.
4. ~~**`driver_node.py` calls `rclpy.spin_until_future_complete(self, …)` from inside its own subscription callbacks.**~~ Nested spinning on a node that is already being spun deadlocks under `rclpy.spin` and is undefined under a `MultiThreadedExecutor`. **RESOLVED 2026-07-27** by [slam-lifecycle-ap-status-reconciler.md](slam-lifecycle-ap-status-reconciler.md), which removed every blocking call from the driver's callbacks. The two synchronous helpers survive marked deprecated with no in-tree caller.
5. **`LifecycleControllerBase` inherits both `rclcpp::Node` and `std::enable_shared_from_this<LifecycleControllerBase>`.** `rclcpp::Node` already derives from `std::enable_shared_from_this<Node>`, so the class has two such bases and any `shared_from_this()` call is ambiguous or undefined. Latent — no current call site exercises it.
6. **Four divergent copies of `topics_to_record`** (`sitl.launch.py`, `target_recorder.launch.py`, `sensors/launch/managed_logger.launch.py`, `/ws/djinn`), down from five after §5.4a deleted `basalt_slam_test.launch.py`'s. Within `sitl.launch.py`'s surviving chain the outermost still wins; collapsing them to one source of truth is the clean fix.
7. **`sitl_config_vo.json` is a full VIO config with a VO filename.** Cosmetic rename, worth doing in its own commit.
8. ~~**The optional `mpTransitionInFlight` guard.**~~ Would suppress the cosmetic duplicate-ACTIVATE error line (failure mode 6) at the cost of one more member on a class that already has a lot of state. Skipped initially by decision. **DONE 2026-07-27** by [slam-lifecycle-ap-status-reconciler.md](slam-lifecycle-ap-status-reconciler.md) §6, where the reconciler needs the guard anyway to keep its chains single-threaded, so the cost had already been paid. Recorded there as accepted difference D2.

## 9. Landing notes

Nothing is committed. The changes span four git repositories and need coordinated submodule pointer bumps:

- **`ext/basalt`** (comment + `static_assert`) → bump in `slam`.
- **`slam`** (CMake pin, guard, Phase 2 fixes) → bump in `ros_ws`.
- **`tello`** (the `transient_local` line) → bump in `ros_ws`.
- **`ros_ws`** (`controllers`, `sensors`, launch files, submodule bumps) → bump in `/ws`.
- **`/ws`** (`djinn`, `scripts/build_ros_packages.sh`, `docker/ardupilot/Dockerfile`, context and plan files).

Phases 1 and 2 must land together. Within Phase 3, 3.2 + 3.3 must land together for ArduPilot and 3.2 + 3.6 for Tello. Note the working tree also carries pre-existing uncommitted clang-format reflows of `tello_driver_node.cpp` and `src/basalt/{node,slam}.cpp`, and an unrelated `BASALT_BUILD_TESTS` option in `ext/basalt/CMakeLists.txt` — consider separating those into formatting-only commits so the behavioural diff stays reviewable.
