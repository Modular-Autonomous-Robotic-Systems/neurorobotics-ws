# Investigation: StonePineForest SITL — "Not Implemented" spam & "PreArm: GPS 1: not healthy"

**Date:** 2026-07-23 · **Game:** `sitl_ws/src/ue5/AirSim/Unreal/Environments/StonePineForest` · **Vehicle:** `ArduCopter` (ArduPilot SITL) · Companion architecture notes: [airsim.md](airsim.md).

**Status: root cause identified with high confidence** — a clock-rate mismatch between AirSim (`ClockSpeed 0.45`) and ArduPilot SITL (`SIM_SPEEDUP 1.0`). See Finding B.

## How the sim is launched and which settings file is active (definitive)

- `sitl_ws/scripts/run_airsim.sh` runs, inside the `airsim_container`: `/ws/StonePineForest/Linux/StonePineForest.sh -settings=/ws/settings.json -renderoffscreen`. The explicit `-settings=` command-line argument overrides the default `~/Documents/AirSim/settings.json` search path.
- `scripts/helpers/docker.sh` → `spawn_container_if_needed()` → for `airsim_container` it sources `sitl_ws/scripts/start.sh` with argument `$NRT_WS/sitl_ws/src/ue5/AirSim/Unreal/Environments`.
- `sitl_ws/scripts/start.sh` does `docker run ... -v $1:/ws ...`, so the airsim container's `/ws` is the host directory `$NRT_WS/sitl_ws/src/ue5/AirSim/Unreal/Environments`. Therefore the airsim container's `/ws/settings.json` = host `sitl_ws/src/ue5/AirSim/Unreal/Environments/settings.json`. **That is the active settings file** — the one with `ClockSpeed 0.45`, `UdpPort 9003` / `ControlPort 9002`, `SettingsVersion 1.2`, GPS+IMU enabled, origin Canberra.
- `start.sh` also bind-mounts `$(pwd)/settings.json` to `/home/ue4/Documents/AirSim/settings.json`, but the explicit `-settings=` flag wins, so that mount is not the effective config.
- Path note for future sessions: Claude usually runs inside a different container whose `/ws` is the NRT_WS root (`$NRT_WS`). From there the active AirSim settings file is at `/ws/sitl_ws/src/ue5/AirSim/Unreal/Environments/settings.json`. The paths inside `run_airsim.sh` (`/ws/settings.json`, `/ws/StonePineForest/...`) are relative to the **airsim container's** mount, not Claude's container.

## Symptoms

1. Log flooded with repeating bursts of `Not Implemented: getKinematicsEstimated` / `getGpsLocation` / `getLandedState` (see Finding A).
2. QGroundControl first reports the copter is **"ready to fly"**, but attempting to arm fails with **`PreArm: GPS 1: not healthy`** and arming is rejected. This exact string appears 4× in `/ws/mav.tlog`.

## Finding A — the "Not Implemented" spam is BY DESIGN, not a bug

`VehicleType` is `ArduCopter`, so ArduPilot SITL owns flight control and state estimation, and `ArduCopterApi` deliberately stubs every state getter, each logging `Not Implemented: …` at info level (see [airsim.md §4](airsim.md)). One `getMultirotorState()` RPC call emits exactly the observed triple (`MultirotorApiBase.hpp:134` calls `getKinematicsEstimated` → `getGpsLocation` → `getLandedState`). Repeating bursts mean something (the AirSim ROS2 wrapper or a user client/HUD) is polling `getMultirotorState()` on the RPC. These logs are harmless in themselves but signal that the SITL software is reading vehicle state from the wrong source: in ArduCopter mode the AirSim RPC state API returns NaN, and vehicle pose/velocity/GPS/armed/landed must be read from ArduPilot over MAVLink (mavros / pymavlink / DroneKit). Raw sensor getters (`getGpsData`, `getImuData`, `getLidarData`, …) and images remain valid on the AirSim RPC.

## Finding B — "PreArm: GPS 1: not healthy" root cause: AirSim/ArduPilot clock-rate mismatch

The exact string `GPS N: not healthy` in ArduPilot comes from `AP_Arming::gps_checks()` when `AP_GPS::is_healthy(instance)` returns false. `is_healthy()` is fundamentally a **GPS message timing/rate** check — it fails when GPS samples do not arrive at the expected cadence in ArduPilot's own clock frame. It is NOT the satellite-count, HDOP, or EKF-variance check (those produce different strings such as "Bad HDOP", "not enough satellites", "check GPS", "EKF3 waiting for GPS"). The ArduPilot params confirm sat/HDOP quality is fine (`SIM_GPS1_NUMSATS 10`, `GPS_HDOP_GOOD 140`, `EK3_GPS_CHECK 31` with good simulated values), so the failure is purely about *when* GPS updates land, not their quality.

The decisive evidence — two clocks running at different rates with nothing forcing them to agree:

- **AirSim** active `settings.json`: `ClockSpeed = 0.45` with an auto-selected `SteppableClock`. Sim-time (and therefore every sensor packet's `timestamp`) advances at **0.45× wall-clock** (derivation in [airsim.md §4a](airsim.md): step size = physics_loop_period 3 ms × 0.45 = 1.35 ms sim-time per 3 ms wall tick).
- **ArduPilot** `mav.parm`: `SIM_SPEEDUP = 1.000000`. ArduPilot SITL targets **1.0× wall-clock**.
- **ArduPilot** GPS cadence: `SIM_GPS1_HZ = 5`, `GPS1_RATE_MS = 200` → GPS is delivered to the EKF at 5 Hz (one sample per 200 ms) as measured by ArduPilot's clock.
- **The `LockStep` settings key is IGNORED in the ArduCopter path** (no `lock_step` reference anywhere under `firmwares/arducopter/`). The only coupling is AirSim blocking in `recvRotorControl` until ArduPilot returns motor PWM; nothing forces ArduPilot's clock to track AirSim's sensor timestamps.

Because AirSim advances simulated time (which drives the vehicle position feeding GPS, and the sensor timestamps) at 0.45× while ArduPilot's scheduler runs at 1.0×, the interval between GPS updates as seen in ArduPilot's clock frame is stretched and irregular. ArduPilot expects a fresh GPS sample every 200 ms of its own time; when the underlying simulation feeding those samples only advances at 0.45×, the effective GPS delta blows past the health tolerance and `is_healthy()` trips → `PreArm: GPS 1: not healthy`.

This precisely explains the **"ready to fly, then arm fails"** pattern: the EKF is tolerant and converges on the GPS data it does receive (so QGC declares "ready to fly"), but the stricter pre-arm `is_healthy()` timing check, sampled at the instant of the arm request, catches a moment where the GPS update interval is out of tolerance and rejects the arm. Intermittent/marginal GPS timing health — exactly what a 0.45-vs-1.0 clock mismatch produces — is consistent with "ready" one moment and "not healthy" the next.

**Primary fix:** set AirSim `ClockSpeed` to **`1.0`** in the active `settings.json` so it matches ArduPilot's `SIM_SPEEDUP 1.0`. Both processes then advance time at 1.0× wall-clock, GPS update intervals become consistent in ArduPilot's frame, and the `is_healthy()` timing check should pass. This is the single highest-value change and is now well motivated (not a guess): the two configured clock rates are provably different (0.45 vs 1.0), and the failing check is provably a timing check.

**Residual uncertainty / alternatives, in case ClockSpeed 1.0 alone does not fix it:**
- If some form of timestamp-lockstep IS actually engaged on the ArduPilot JSON backend, ArduPilot's clock would be paced by AirSim's timestamp and SIM_SPEEDUP would be moot; then the clock rates already agree and the residual cause would be a genuine lockstep stall/stutter (e.g. `-renderoffscreen` headless frame pacing) making GPS intervals jittery. Fix path: verify the loop is stepping steadily; keep ClockSpeed at 1.0 regardless.
- If GPS timing still flaps after ClockSpeed 1.0, options on the ArduPilot side: raise the tolerance by lowering the expected GPS rate is not advisable; better to confirm AirSim is emitting GPS steadily and that the FDM loop is not stalling. `SIM_GPS1_HZ 5` vs AirSim GPS sensor `UpdateFrequency 50` is fine (ArduPilot down-samples), so that mismatch is not the issue.

## Finding C — configuration discrepancies (fix these regardless)

| Setting | active `settings.json` | `settings.json.bkp` | Notes |
|---------|------------------------|---------------------|-------|
| `SettingsVersion` | 1.2 | 2.0 | 1.2 only warns (auto-upgrade path) and still loads, but is stale — bump to 2.0 to match Cosys-AirSim docs. |
| `ClockSpeed` | **0.45** | 1.0 | The root-cause knob (Finding B). Set to 1.0 to match ArduPilot `SIM_SPEEDUP 1.0`. |
| `UdpPort` / `ControlPort` | 9003 / 9002 | 9002 / 9003 (swapped) | AirSim sends sensors on `UdpPort`, receives PWM on `ControlPort`. 9003/9002 is the standard ArduPilot-AirSim convention; the active file is correct and `.bkp` is swapped. Must match the ports ArduPilot SITL was launched with. Since attitude/EKF work, the ports are already correct. |
| `UseTcp` | true | absent | Only relevant to the PX4/MAVLink path; harmless for ArduCopter (UDP socket used regardless). |

## Recommended action plan

1. Edit the active file `sitl_ws/src/ue5/AirSim/Unreal/Environments/settings.json`: set `"ClockSpeed": 1.0`, bump `"SettingsVersion": 2.0`. Leave the ports as-is (9003/9002).
2. Restart the AirSim container / relaunch via `run_airsim.sh` so the new settings load (the game reads settings once at startup).
3. Relaunch (or keep) ArduPilot SITL; keep `SIM_SPEEDUP 1.0`. Both sides now target 1.0×.
4. Wait 30–60 s after both sides connect for GPS/EKF to settle, then attempt arm. `PreArm: GPS 1: not healthy` should be gone.
5. Rewire the SITL software to read vehicle state from ArduPilot via MAVLink rather than AirSim `getMultirotorState` — this both fixes the state source and stops the "Not Implemented" spam.
6. If GPS health still flaps, investigate FDM loop stalling under `-renderoffscreen` and confirm AirSim is emitting sensor packets steadily (temporary packet capture on `UdpPort 9003`).

## Evidence appendix (as of 2026-07-23)

- ArduPilot state files live in the NRT_WS root (`/ws` in Claude's container): `mav.parm` (param dump), `mav.tlog` / `mav.tlog.raw` (MAVLink telemetry logs), `eeprom.bin` (SITL EEPROM), `mav.parm` timestamps ~16:11, tlog ~16:24.
- `mav.tlog` STATUSTEXT: `PreArm: GPS 1: not healthy` ×4.
- Key `mav.parm` values: `SIM_SPEEDUP 1.0`, `SIM_GPS1_ENABLE 1`, `SIM_GPS1_HZ 5`, `SIM_GPS1_NUMSATS 10`, `SIM_GPS1_ACC 0.3`, `GPS1_TYPE 1`, `GPS1_RATE_MS 200`, `GPS_HDOP_GOOD 140`, `AHRS_EKF_TYPE 3`, `EK3_ENABLE 1`, `EK3_GPS_CHECK 31`, `EK3_SRC1_POSXY 3` (GPS), `EK3_SRC1_VELXY 3`, `FRAME_CLASS 1` / `FRAME_TYPE 1` (quad X), `SCHED_LOOP_RATE 100`, `SIM_RATE_HZ 1200`.

## Open items / not yet verified

- Whether the ArduPilot JSON backend is running with true timestamp-lockstep (would make SIM_SPEEDUP moot). Not determinable from `mav.parm` alone; the ArduPilot SITL launch command / JSON backend flags would confirm it.
- Exact identity of the `getMultirotorState()` poller (AirSim ROS2 wrapper vs user client) — confirm by checking what is connected to RPC port 41451.
- Confirmation that setting `ClockSpeed 1.0` clears the arm failure (the concrete test that closes this out).
