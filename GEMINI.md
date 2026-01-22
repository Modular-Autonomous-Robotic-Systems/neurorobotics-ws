# Neurorobotics Workspace (NRT_WS)

This workspace is a comprehensive environment for robotics and drone development, integrating ROS 2, ArduPilot, AirSim simulation, and various computer vision tools (ORB_SLAM3, Pangolin). It relies heavily on Docker for environment management, orchestrated by a custom CLI tool named `djinn`.

## Project Overview

*   **Core Technologies:** ROS 2 (Humble), Docker, ArduPilot, AirSim, Bash.
*   **Key Components:**
    *   **NRT (Neurorobotics):** The main container/environment for ROS development.
    *   **SITL (Software In The Loop):** Simulation environment using ArduPilot and AirSim.
    *   **Kalibr:** Camera calibration tools.
    *   **Tello:** Support for DJI Tello drones.
*   **CLI:** The `./djinn` script at the root is the primary interface for all operations.

## Directory Structure

*   `djinn`: The main CLI entry point.
*   `ros_ws/`: The ROS 2 workspace.
    *   `src/`: Contains ROS packages (`controllers`, `slam`, `tello`, etc.).
*   `docker/`: Dockerfiles and build scripts for the various environments (`base`, `nrt`, `ardupilot`, `sitl`).
*   `scripts/`: Helper scripts used by `djinn` and inside containers (builds, setup).
*   `ext/`: External tools and repositories (ArduPilot source, Kalibr, QGroundControl).
*   `envs/`: Environment configurations, likely for simulation setups (UE4/UE5).
*   `nvim-gemini-companion/`: A standalone Neovim plugin project residing within the workspace.

## The `djinn` CLI

The `djinn` script abstracts complex Docker and build commands. Always prefer using `djinn` over manual Docker or CMake commands.

### Key Commands

*   **Setup & Initialization:**
    *   `./djinn install --docker --ssh --git`: Installs host prerequisites (Docker, Git, SSH).
    *   `./djinn init docker`: Builds the base Docker images.
    *   `./djinn init docker nrt`: Builds the NRT specific images.
    *   `./djinn init docker sitl`: Builds Simulation images (ArduPilot/AirSim).

*   **Running Containers:**
    *   `./djinn up nrt`: Starts the main NRT container.
    *   `./djinn up dev`: Starts a development container (likely with IDE support).
    *   `./djinn up sitl_bridge`: Starts the SITL bridge container.

*   **Building Code:**
    *   `./djinn build`: Builds the entire ROS workspace inside the NRT container.
    *   `./djinn build nrt`: Rebuilds NRT ROS packages.
    *   `./djinn build ardupilot <board> <config>`: Builds ArduPilot firmware (e.g., `./djinn build ardupilot SpeedyBeeF405WING plane`).

*   **Execution:**
    *   `./djinn exec <container_suffix> <command>`: Runs a command inside a running container.
        *   Example: `./djinn exec nrt bash` (Opens a shell in the NRT container).
    *   `./djinn start tello`: Launches Tello drone control nodes.
    *   `./djinn start sitl`: Launches the full SITL simulation stack (AirSim + ArduPilot + ROS bridge).

*   **Cleanup:**
    *   `./djinn down`: Stops all running containers.
    *   `./djinn kill sitl`: Kills specific simulation processes.

## Development Workflow

1.  **Start the Environment:** Usually begins with `./djinn up nrt`.
2.  **Develop:** Edit files in `ros_ws/src` on the host (mapped into the container).
3.  **Build:** Run `./djinn build` to compile changes.
4.  **Test/Run:** Use `./djinn exec nrt ...` to run ROS nodes or launch files.

## Conventions

*   **Docker-First:** All compilation and execution happen inside Docker containers to ensure consistent dependencies.
*   **ROS 2:** The project uses standard ROS 2 (Colcon) build flows, wrapped by the `build.sh` script inside the container.
*   **ArduPilot:** Firmware builds are handled via `waf` but abstracted by `djinn`.
