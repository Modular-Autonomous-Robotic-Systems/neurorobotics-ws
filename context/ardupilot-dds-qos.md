# ArduPilot DDS (`AP_DDS`) publisher QoS — the SITL side of every `/ap/*` topic

**Date:** 2026-07-25. **Source of truth:** `ardu_ws/src/ardupilot/libraries/AP_DDS/AP_DDS_Topic_Table.h` (submodule; the table is a compile-time array of `uxrQoS` structs, so these values are fixed at ArduPilot build time and are not runtime-tunable).
**ROS-side consumer matrix:** [`/ws/ros_ws/context/ros-qos-compatibility.md`](../ros_ws/context/ros-qos-compatibility.md).

## Why this file exists

Every `/ap/*` topic in the SITL stack is published by ArduPilot's Micro-XRCE-DDS client, **not** by a ROS 2 node, so its QoS is declared in ArduPilot's C source rather than anywhere in `ros_ws`. A ROS subscriber whose requested QoS is stronger than what this table offers will silently never match — no error, no warning, just a callback that is never invoked. That failure mode cost a full debugging session in July 2026 (the Basalt VISLAM IMU subscription), so the table is transcribed here to make the contract greppable without opening the ArduPilot submodule.

## The table

Values are `.durability` / `.reliability` / `.history` / `.depth` from the `.qos` member of each entry. ROS topic names are the table's `.topic_name` prefixed with `/ap/` (the `rt/ap/` DDS mapping is applied by the client).

| ROS topic | Durability | Reliability | History | Depth |
|---|---|---|---|---|
| `/ap/status` | **TRANSIENT_LOCAL** | **RELIABLE** | KEEP_LAST | 1 |
| `/ap/clock` | VOLATILE | RELIABLE | KEEP_LAST | 20 |
| `/ap/time` | VOLATILE | RELIABLE | KEEP_LAST | 20 |
| `/ap/imu/experimental/data` | VOLATILE | **BEST_EFFORT** | KEEP_LAST | 5 |
| `/ap/navsat` | VOLATILE | BEST_EFFORT | KEEP_LAST | 5 |
| `/ap/battery` | VOLATILE | BEST_EFFORT | KEEP_LAST | 5 |
| `/ap/pose/filtered` | VOLATILE | BEST_EFFORT | KEEP_LAST | 5 |
| `/ap/twist/filtered` | VOLATILE | BEST_EFFORT | KEEP_LAST | 5 |
| `/ap/geopose/filtered` | VOLATILE | BEST_EFFORT | KEEP_LAST | 5 |
| `/ap/gps_global_origin/filtered` | VOLATILE | BEST_EFFORT | KEEP_LAST | 5 |

`/ap/status` is the outlier and the one worth remembering: it is the only **TRANSIENT_LOCAL + RELIABLE** publisher in the set, because it carries latched vehicle state (`armed`, `flying`) that a late-joining subscriber needs immediately rather than at the next change.

## How to re-derive it

The table is large and mostly boilerplate; this extracts just the QoS per topic:

```bash
awk '/topic_name = "/{name=$0} /reliability|durability|depth|history/{print name" | "$0}' \
  /ws/ardu_ws/src/ardupilot/libraries/AP_DDS/AP_DDS_Topic_Table.h
```

Individual entries are guarded by `AP_DDS_<NAME>_PUB_ENABLED` macros from `AP_DDS_config.h`, so a topic can be compiled out entirely — if a topic is missing at runtime, check the macro before assuming a QoS problem.

## Gotchas worth remembering

- **DDS matches an endpoint pair only when the offered policy is at least as strong as the requested one.** RELIABLE ≥ BEST_EFFORT, TRANSIENT_LOCAL ≥ VOLATILE. A **RELIABLE subscriber against a BEST_EFFORT publisher does not match** — this is the trap, because the "stronger" request is the one that fails.
- **`rclcpp`'s default is RELIABLE.** Writing `create_subscription<T>(topic, 10, cb)` requests RELIABLE + VOLATILE + KEEP_LAST(10). For any `/ap/*` topic other than `status`, `clock` and `time`, that request will not match. Use `rclcpp::SensorDataQoS()` (BEST_EFFORT + VOLATILE + KEEP_LAST(5)), which is an exact match for the BEST_EFFORT rows above.
- **A mismatch is silent by default.** `ros2 topic info -v <topic>` is the diagnostic: it prints each endpoint's QoS and lets you compare offered against requested. `ros2 node info` only proves a subscription was *created*, not that it *matched* — the two look identical in a healthy and a broken system.
- **These values are ArduPilot's, not ours.** Bumping the `ardupilot` submodule can change them. Re-run the `awk` above after any submodule bump that touches `libraries/AP_DDS`.
- **`ros2 bag play` does not reproduce them.** Replay republishes with the rosbag2 player's own profile (VOLATILE, and RELIABLE unless overridden), so a subscriber tuned exactly to this table still works on replay only if it requests BEST_EFFORT/VOLATILE — which is the weakest request and therefore matches both. This is the reason [`ros-qos-compatibility.md`](../ros_ws/context/ros-qos-compatibility.md) forbids requesting TRANSIENT_LOCAL anywhere in this workspace.

See also [`airsim.md`](airsim.md) for the AirSim/SITL data path, and [`sitl-workspace-migration.md`](sitl-workspace-migration.md) for where `ardu_ws` lives and how it is built.
