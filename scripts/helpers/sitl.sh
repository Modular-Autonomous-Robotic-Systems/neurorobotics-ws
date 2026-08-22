#!/bin/bash

# This script is a helper script for djinn, meant only to be sourced within djinn and other scripts that source:
# 			$NRT_WS/scripts/data.sh
# 			$NRT_WS/scripts/exec.sh
# 			$NRT_WS/scripts/docker.sh

build_airsim_docker_image() {
    cd $NRT_WS/sitl_ws/src/ue5/AirSim/docker/
    python3 build_airsim_image.py --source --target_image="shandilya1998/nrt_airsim:0.0.1" --base_image="ghcr.io/epicgames/unreal-engine:dev-5.5"
    cd -
}

# Image built with a plain docker build rather than build_image because the
# Unreal Engine base image and the prebuilt ONNX Runtime tarball are both
# x86-64 only, so the multi-platform path is inapplicable.
# The default is the locally built shandilya1998/nrt:unreal rather than Epic's
# ghcr.io/epicgames/unreal-engine:dev-5.7, because the latter is Ubuntu 18.04 and
# Project AirSim requires a 22.04 userland. See docker/scripts/build_unreal.sh.
build_airsim2_docker_image() {
    base_image="${1:-shandilya1998/nrt:unreal}"
    setup_nvim_config_for_image_build "$NRT_WS/docker/airsim"
    docker build "$NRT_WS/docker/airsim" \
        --build-arg BASE_IMAGE="$base_image" \
        -t shandilya1998/nrt_airsim:0.0.2
    cleanup_nvim_config_after_image_build "$NRT_WS/docker/airsim"
}

# Lists every supported Project AirSim Unreal environment in $NRT_WS
# $1 must be the workspace root, $NRT_WS on the host or /ws inside
# airsim2_container,
list_projectairsim_games() {
    local ws_root="$1"
    find "$ws_root/sitl_ws/src/ue5/ProjectAirSim/unreal" \
        -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

# $1 is the workspace root either $NRT_WS or /ws
clean_projectairsim_build_artefacts() {
    local ws_root="$1"
    local pas_root="$ws_root/sitl_ws/src/ue5/ProjectAirSim"
    (cd "$pas_root" && ./build.sh clean)
    local game
    for game in $(list_projectairsim_games "$ws_root"); do
        rm -rf "$pas_root/unreal/$game/Binaries" \
            "$pas_root/unreal/$game/Intermediate" \
            "$pas_root/unreal/$game/Saved" \
            "$pas_root/unreal/$game/Build" \
            "$pas_root/unreal/$game/Plugins/ProjectAirSim/Binaries" \
            "$pas_root/unreal/$game/Plugins/ProjectAirSim/Intermediate" \
            "$pas_root/unreal/$game/Plugins/ProjectAirSim/SimLibs" \
            "$pas_root/packages/$game"
    done
}

# $1 is the workspace root either $NRT_WS or /ws
copy_projectairsim_plugin_to_games() {
    local ws_root="$1"
    local pas_root="$ws_root/sitl_ws/src/ue5/ProjectAirSim"
    local game plugin
    for game in $(list_projectairsim_games "$ws_root"); do
        [[ "$game" == "Blocks" ]] && continue
        for plugin in ProjectAirSim Drone Rover; do
            sudo rsync -a --delete --exclude 'Binaries' --exclude 'Intermediate' \
                "$pas_root/unreal/Blocks/Plugins/$plugin/" \
                "$pas_root/unreal/$game/Plugins/$plugin/"
        done
    done
}

# DEPRECATED
# TODO Remove in later versions
build_sitl_docker_image() {
    image="$userName/nrt:sitl"
    filepath="$NRT_WS/docker/sitl"
    platform="linux/amd64"
    docker build -t shandilya1998/nrt_ardupilot:dev-ros -f docker/ardupilot/ardupilot_dev_docker/docker/Dockerfile_dev-ros --push .
    build_image $platform $image $filepath
}

start_simulation() {
    environment=$1
    xhost +local:docker
    spawn_container_if_needed airsim_container "shandilya1998/nrt_airsim:0.0.1" "x86_64"
}

stop_simulation() {
    docker stop airsim_container
}

start_simulation2() {
    environment=$1
    xhost +local:docker
    # Same host-side prep as djinn's `init docker dev` branch, needed here
    # because docker/airsim/Dockerfile now carries Claude Code and agy too.
    # Without this, a fresh workspace's missing $NRT_WS/.claude.json would be
    # created as a directory by the -v bind mount in sitl_ws/scripts/start.sh,
    # breaking the mount.
    mkdir -p $NRT_WS/.claude $NRT_WS/.gemini
    if [[ ! -f $NRT_WS/.claude.json ]]; then
        touch $NRT_WS/.claude.json
    fi
    spawn_container_if_needed airsim2_container "shandilya1998/nrt_airsim:0.0.2" "x86_64"
}

stop_simulation2() {
    docker stop airsim2_container
}

# DEPRECATED
# TODO Remove in later versions
start_sitl_container() {
    spawn_container_if_needed sitl_bridge_container shandilya1998/nrt:sitl
}

stop_sitl_container() {
    docker stop sitl_bridge_container
}

# DEPRECATED
# TODO Remove in later versions
setup_airsim_ros_pkgs_for_docker_build() {

    directory=$1

    if [[ ! -n "$directory" ]]; then
        directory="ardupilot"
    fi

    image="$userName/nrt:base"
    container_name="init_container"
    source $NRT_WS/scripts/start.sh "$NRT_WS" "$container_name" "$image"
    iexec init_container "ls && echo \"Starting Container Setup\" && /ws/scripts/git-setup.sh $userEmail $userName && /ws/scripts/docker-setup.sh"
    iexec init_container "mkdir -p /ws/docker/$directory/airsim_ws/src/AirSim && \
		cp -r /ws/sitl_ws/src/ue5/AirSim/cmake/ \
		/ws/sitl_ws/src/ue5/AirSim/AirLib/ \
		/ws/sitl_ws/src/ue5/AirSim/AirSim.sln \
		/ws/sitl_ws/src/ue5/AirSim/DroneShell \
		/ws/sitl_ws/src/ue5/AirSim/HelloDrone \
		/ws/sitl_ws/src/ue5/AirSim/HelloCar \
		/ws/sitl_ws/src/ue5/AirSim/HelloSpawnedDrones \
		/ws/sitl_ws/src/ue5/AirSim/MavLinkCom \
		/ws/sitl_ws/src/ue5/AirSim/DroneServer \
		/ws/sitl_ws/src/ue5/AirSim/AirLibUnitTests \
		/ws/sitl_ws/src/ue5/AirSim/ros2 \
		/ws/docker/$directory/airsim_ws/src/AirSim/ && \
		echo \"here\" && \
		ls /ws/docker/$directory/airsim_ws/src/AirSim/"
}
