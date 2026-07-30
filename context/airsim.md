# Cosys-AirSim & the Unreal Environments (architecture)

Durable notes on the Cosys-AirSim plugin and the Unreal Engine game projects (e.g. **StonePineForest**) used for SITL testing in this workspace. Written while investigating a GPS / "Not Implemented" issue — see the companion investigation file [airsim-sitl-gps-issue.md](airsim-sitl-gps-issue.md).

Repo root for AirSim: `sitl_ws/src/ue5/AirSim` (git submodule, Cosys-AirSim, currently `v3.4.1` on branch `main`, targeting **Unreal Engine 5.8**). See also [airsim-docker-build.md](airsim-docker-build.md) for the Docker image build.

---

## 1. What the pieces are

| Piece | What it is |
|-------|-----------|
| **Cosys-AirSim plugin** | UE plugin under `Unreal/Environments/<Game>/Plugins/AirSim`. Contains `AirLib` (the header-only C++ sim/vehicle/sensor library) + the UE integration (`AirSim` / `AirSimInterfaces`). |
| **AirLib** | `Plugins/AirSim/Source/AirLib` — vehicle firmware APIs, sensors, physics, the RPC server, and `common/AirSimSettings.hpp` (settings parser). This is where all the "Not Implemented" strings and the ArduPilot data path live. |
| **A "Game"** (e.g. StonePineForest) | A UE5 `.uproject` that bundles the AirSim plugin + a level/map. Each game (StonePineForest, NaturalEnvironments, Blocks, …) is a separate UE project but shares the same vendored AirSim plugin copy. |
| **RPC server** | msgpack-rpc server on `ApiServerPort` (default **41451**). This is the AirSim client API (Python `cosysairsim`, C++, ROS2 wrapper) — `simGetImages`, `getMultirotorState`, sensor getters, etc. |
| **ROS2 wrapper** | `ros2/` in the AirSim repo. Bridges the RPC API to ROS2 topics. Polls vehicle state via the RPC API. |

Each game has its own vendored copy of the plugin, so `Unreal/Environments/StonePineForest/Plugins/AirSim/...` is what actually runs for that game — **not** the top-level `AirLib/` in the repo root (that is the source of truth that gets copied in). Paths in this doc are relative to the AirSim repo root; substitute the game's plugin copy when reasoning about a running game.

---

## 2. Sim modes and vehicle types

`SimMode` in settings selects the world type: `Multirotor`, `Car`, `ComputerVision`. Within a mode, each entry under `Vehicles` has a `VehicleType`:

- **Multirotor**: `SimpleFlight` (AirSim's own built-in flight controller — full physics + state estimation *inside* AirSim), `ArduCopter` (ArduPilot SITL), `PX4Multirotor` (PX4 SITL via MAVLink).
- **Car**: `PhysXCar`, `BoxCar`, `ArduRover` (ArduPilot SITL).

**This is the single most important architectural fork:**

| VehicleType | Who owns flight control & state estimation | AirSim RPC state API (`getMultirotorState`, `getGpsLocation`, …) |
|-------------|--------------------------------------------|------------------------------------------------------------------|
| `SimpleFlight` | **AirSim** (internal) | ✅ Fully implemented — returns real state |
| `ArduCopter` / `ArduRover` | **External ArduPilot SITL** | ❌ **Stubbed** — logs "Not Implemented", returns NaN |
| `PX4Multirotor` | **External PX4 SITL** (MAVLink) | Partially — state comes back over MAVLink |

The StonePineForest setup here uses **`VehicleType: "ArduCopter"`** → **ArduPilot SITL**. Consequences of that choice are the whole story of the GPS issue.

---

## 3. ArduPilot (ArduCopter) SITL data path — how it actually works

Code: `AirLib/include/vehicles/multirotor/firmwares/arducopter/ArduCopterApi.hpp`.

AirSim in ArduCopter mode is **only a physics + sensor simulator and a motor sink**. ArduPilot SITL is the flight controller. They exchange data over two UDP sockets:

```
                 sensor JSON (IMU, GPS, pose, RC, rng, lidar)
   AirSim  ──────────────────────────────────────────────────►  ArduPilot SITL
   (game)   sendto(ip=UdpIp, port=UdpPort)                        (JSON FDM backend)

                 servo/motor PWM (11 channels, uint16)
   AirSim  ◄──────────────────────────────────────────────────  ArduPilot SITL
            bind(local_host_ip, ControlPort) / recv
```

- Every physics `update()` (`ArduCopterApi::update`) does `sendSensors()` then `recvRotorControl()`.
- `recvRotorControl()` **blocks and loops until it receives a full 11×uint16 PWM packet**. This is the *only* coupling between the two processes: AirSim cannot advance a physics step until ArduPilot returns motor outputs.
- **The `LockStep` settings key is IGNORED in the ArduCopter/ArduRover path** — `grep lock_step` over `firmwares/arducopter/` and `firmwares/ardurover/` returns nothing; it is only wired into the MAVLink/PX4 firmware. So there is **no lockstep handshake and no clock negotiation** in ArduCopter mode — nothing forces ArduPilot's clock to track AirSim's sensor timestamps. Whether the two stay in sync depends entirely on the ArduPilot side (see the clock/timing section below and [airsim-sitl-gps-issue.md](airsim-sitl-gps-issue.md) Finding B).
- `sendSensors()` builds a JSON line and `sendto`s it. **The GPS block it sends contains only `lat`, `lon`, `alt` and `velocity.world_linear_velocity`** — no HDOP, fix type, or satellite count. ArduPilot's SITL synthesizes GPS/fix quality from the FDM position at its own `SIM_GPS1_HZ` rate. Timestamp sent per packet = `ClockFactory::get()->nowNanos()/1000` (µs) from the **SteppableClock** (advances only as the sim steps).

### Port semantics (settings.json ↔ code) — easy to get backwards

In `AirSimSettings.hpp::createMavLinkVehicleSetting`:
- `UdpPort` → `connection_info.udp_port` → **destination** AirSim sends sensors to.
- `ControlPort` (legacy key; also `ControlPortLocal`) → `control_port_local` → the local port AirSim **binds to receive** motor PWM.
- In `ArduCopterApi::connect()`: `port_ = udp_port` (send target), `udp_socket_->bind(local_host_ip, control_port_local)` (receive).

So for the AirSim side: **sensors go out on `UdpPort`, control comes in on `ControlPort`.** The matching ArduPilot SITL must send servos to AirSim's `ControlPort` and listen for sensors on `UdpPort`. Standard ArduPilot-AirSim convention is `UdpPort: 9003`, `ControlPort: 9002`. Because IMU and GPS ride the **same** UDP packet to `UdpPort`, a port mismatch breaks *everything*, not GPS alone — if attitude works but GPS is "unhealthy", the ports are fine.

Other keys: `UseTcp`, `TcpPort` are for the MAVLink (PX4) path; `LockStep` toggles lockstep only for MAVLink/PX4; `UseSerial` for real hardware. `LocalHostIp`/`UdpIp` default `127.0.0.1`.

---

## 4. The RPC state API is stubbed in ArduCopter mode (the "Not Implemented" source)

`ArduCopterApi` inherits `MultirotorApiBase` but deliberately **stubs every state/estimation/command method**, each logging `Utils::log("Not Implemented: …")` at info level. Stubbed getters include: `getKinematicsEstimated`, `getGpsLocation`, `getLandedState`, `getPosition`, `getVelocity`, `getOrientation`, `getHomeGeoPoint`, `isApiControlEnabled`, `armDisarm`, and all `command*` methods.

`MultirotorApiBase::getMultirotorState()` (`MultirotorApiBase.hpp:134`) assembles a state by calling — in order — `getKinematicsEstimated()` (137), `getGpsLocation()` (139), `getLandedState()` (141). So **one `getMultirotorState()` RPC call emits exactly the triple `getKinematicsEstimated / getGpsLocation / getLandedState`** as "Not Implemented" logs. Repeated bursts of that triple ⇒ something is polling `getMultirotorState()` at a fixed rate (the ROS2 wrapper, or a user Python/C++ client, or a subwindow/HUD).

**Rule for SITL software in ArduCopter mode:** do **not** read vehicle pose/velocity/GPS/landed-state from the AirSim RPC API — those are no-ops returning NaN. Get vehicle state from **ArduPilot over MAVLink** (mavros / pymavlink / MAVProxy / DroneKit). Use the AirSim RPC only for things AirSim still owns: images (`simGetImages`), raw sensor data (`getImuData`, `getGpsData`, `getLidarData`, `getDistanceSensorData`, `getBarometerData`), and world/scene ops. Note the subtlety: `getGpsData` (the *sensor* getter) works; `getGpsLocation` (the *estimated-state* getter) is the stub.

---

## 4a. Clock & timing (SteppableClock, ClockSpeed) — how sim-time is generated

This governs the `timestamp` on every sensor packet and is the crux of the GPS issue. Two clock types (`common/SteppableClock.hpp`, `ScalableClock.hpp`, chosen in `SimModeBase::setupClockSpeed` and overridden per sim-mode):

- **ScalableClock** — `nowNanos()` = wall time × scale. Default; also forced for PX4.
- **SteppableClock** — `nowNanos()` is an accumulator advanced by a **fixed step per physics tick**, fully decoupled from wall time. Auto-selected for `SimMode: Multirotor` unless a vehicle is PX4 (`loadClockSettings`). This is what a copter-ArduCopter setup uses.

**Who advances it:** `World::update()` (`physics/World.hpp:45`) calls `ClockFactory::get()->step()` once per physics tick, *then* updates the vehicles (→ `ArduCopterApi::update` → `sendSensors`). So the timestamp on outgoing sensor packets is the SteppableClock accumulator.

**Who paces the physics loop:** `ScheduledExecutor` (`common_utils/ScheduledExecutor.hpp:174`) runs `World::update()` in a loop, sleeping `physics_loop_period − elapsed` to target one tick per `physics_loop_period_` (default **3 ms wall**, `SimModeWorldBase.h:75`) — **unless** the tick already took longer, e.g. blocked in `recvRotorControl` waiting for ArduPilot, in which case it loops immediately.

**How `ClockSpeed` maps to the step size** — the multirotor override `ASimModeWorldMultiRotor::setupClockSpeed()` (`Vehicles/Multirotor/SimModeWorldMultiRotor.cpp:35`) is deliberately asymmetric for SteppableClock:

| `ClockSpeed` | What is scaled | Result |
|--------------|----------------|--------|
| `>= 1` (speed up) | **loop period** shrinks: `setPhysicsLoopPeriod(period / clock_speed)`; step size stays full `physics_loop_period` (3 ms) | more wall ticks/sec; can max out on CPU. Scaling the *step size* up instead was rejected — code comment: "would cause quadrotors to become unstable". |
| `< 1` (slow down) | **step size** shrinks: `SteppableClock(physics_loop_period · 1e-9 · clock_speed)`; loop period stays 3 ms | fewer sim-ms per wall-tick; stable. |

So for `ClockSpeed = 0.45`: step size = `3 ms × 0.45 = 1.35 ms` sim-time per tick, loop still ~3 ms wall ⇒ **sim-time advances at 0.45× wall-clock**. That is the exact meaning of ClockSpeed 0.45, and it directly scales the sensor-packet `timestamp` rate. Combined with the "LockStep ignored in ArduCopter" fact above, a non-unity ClockSpeed means AirSim's sensor timestamps drift relative to a free-running ArduPilot clock — the mechanism behind "GPS not healthy". The active setup pairs AirSim `ClockSpeed 0.45` with ArduPilot `SIM_SPEEDUP 1.0`, a provable rate mismatch; full analysis in [airsim-sitl-gps-issue.md](airsim-sitl-gps-issue.md) Finding B.

---

## 5. settings.json — location, precedence, version

- **Command-line override wins:** the game accepts `-settings=<path>`. The launch script `sitl_ws/scripts/run_airsim.sh` passes `-settings=/ws/settings.json`, so the default search path is bypassed. In the airsim container `/ws` is a mount of host `sitl_ws/src/ue5/AirSim/Unreal/Environments`, so the effective file is **`sitl_ws/src/ue5/AirSim/Unreal/Environments/settings.json`**. (Full launch/mount chain is documented in [airsim-sitl-gps-issue.md](airsim-sitl-gps-issue.md).)
- **Default search path (when no `-settings=`):** `FileSystem::getAppDataFolder()` = `<UserDocuments>/AirSim/settings.json`, which on Linux is `$HOME/Documents/AirSim/settings.json` (`FileSystem.cpp::getUserDocumentsFolder` → `$HOME/Documents`, then `AirSim/`). The `start.sh` bind-mount to `/home/ue4/Documents/AirSim/settings.json` targets this path but is overridden by the explicit `-settings=` flag.
- **The repo file `Unreal/Environments/settings.json` is git-ignored** (`.gitignore:61`), so it is a local, per-machine artifact. `settings.json.bkp` and `settings.json.default` are also local staging copies.
- If no settings.json exists, AirSim writes a default one and may prompt for SimMode.
- `SettingsVersion` minimum is **2.0** (`settings_version_minimum = 2.0f`). `checkSettingsVersion`: an actual version `< 2.0` that isn't exactly `== 1` (e.g. `1.2`) falls through to `auto_upgrade = true` → **warning only, still loads**. So a `1.2` file works but is stale; prefer 2.0 to match Cosys docs.
- Sensor types (numeric `SensorType`): 1=Barometer, 2=Imu, 3=Gps, 4=Magnetometer, 5=Distance, 6=Lidar, 7=Echo, 8=GPULidar.

### The settings files present here (as of 2026-07-23)

| File | Mode / Vehicle | Notable |
|------|----------------|---------|
| `Unreal/Environments/settings.json` (active, edited 2026-07-13) | Multirotor / ArduCopter | `SettingsVersion 1.2`, `ClockSpeed 0.45`, `UdpPort 9003`, `ControlPort 9002`, `UseTcp true`, GPS+IMU enabled, origin = ArduPilot default (Canberra −35.363261,149.165230,583). This is the file the game loads via `-settings=`. |
| `settings.json.bkp` | Multirotor / ArduCopter | `SettingsVersion 2.0`, `ClockSpeed 1.0`, ports swapped (`UdpPort 9002`, `ControlPort 9003`), no explicit sensor block, origin Seattle. |
| `settings.json.default` | (full reference) | `SettingsVersion 2.0`. |
| `docker/settings.json` | Car / BoxCar | Unrelated to the copter SITL; used by the Docker/Car workflow. |

---

## 6. GPS sensor model (AirSim side)

Code: `AirLib/include/sensors/gps/GpsSimpleParams.hpp`.

Defaults: `update_frequency = 50 Hz`, `startup_delay = 1 s`, `update_latency 0.2 s`, `eph_initial = epv_initial = 100`, `eph_final = epv_final = 0.1`, `eph/epv_time_constant = 0.9 s`, `eph_min_3d = 3.0`, `eph_min_2d = 4.0`.

The position error (eph/epv) starts "fully diluted" (100) and decays toward 0.1 with a 0.9 s time constant, so it converges within a handful of seconds **of simulated time**. Because the clock is a SteppableClock (and here `ClockSpeed 0.45`), convergence and the steadiness of the GPS timestamp both depend on the sim actually stepping in step with ArduPilot. Note ArduPilot down-samples GPS to `SIM_GPS1_HZ` (5 Hz here), so AirSim's 50 Hz sensor rate is not itself a problem. Overridable via settings keys `UpdateFrequency`, `StartupDelay`, `EphInitial`, `EphFinal`, etc.

---

## 7. Quick reference — where things live

| Topic | File (under `Plugins/AirSim/Source`) |
|-------|--------------------------------------|
| ArduCopter SITL API / UDP data path | `AirLib/include/vehicles/multirotor/firmwares/arducopter/ArduCopterApi.hpp` |
| ArduRover SITL API | `AirLib/include/vehicles/car/firmwares/ardurover/ArduRoverApi.hpp` |
| PX4/MAVLink API | `AirLib/include/vehicles/multirotor/firmwares/mavlink/MavLinkMultirotorApi.hpp` |
| SimpleFlight (internal FC) | `AirLib/include/vehicles/multirotor/firmwares/simple_flight/` |
| `getMultirotorState` assembly | `AirLib/include/vehicles/multirotor/api/MultirotorApiBase.hpp:134` |
| Settings parse + port keys | `AirLib/include/common/AirSimSettings.hpp` (MavLink conn ~955–1005) |
| Settings file location | `AirLib/include/common/Settings.hpp:49`, `AirLib/include/common/common_utils/FileSystem.hpp:55`, `AirLib/src/common/common_utils/FileSystem.cpp:71` |
| GPS params | `AirLib/include/sensors/gps/GpsSimpleParams.hpp` |
| Clock types | `AirLib/include/common/SteppableClock.hpp`, `ScalableClock.hpp`, `ClockBase.hpp` |
| Clock/physics-period setup | `SimMode/SimModeBase.cpp:1507` (`setupClockSpeed`), `Vehicles/Multirotor/SimModeWorldMultiRotor.cpp:35` (multirotor override) |
| Physics loop pacing | `AirLib/include/common/common_utils/ScheduledExecutor.hpp:174`, `AirLib/include/physics/World.hpp:43` |
| Launch scripts | `sitl_ws/scripts/run_airsim.sh`, `sitl_ws/scripts/start.sh`, `scripts/helpers/docker.sh` |
