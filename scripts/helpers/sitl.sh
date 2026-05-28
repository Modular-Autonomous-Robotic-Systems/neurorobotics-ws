#!/bin/bash

# This script is a helper script for djinn, meant only to be sourced within djinn and other scripts that source:
# 			$NRT_WS/scripts/data.sh
# 			$NRT_WS/scripts/exec.sh
# 			$NRT_WS/scripts/docker.sh

build_airsim_docker_image(){
	cd $NRT_WS/envs/ue5/AirSim/docker/
	python3 build_airsim_image.py --source --target_image="shandilya1998/nrt_airsim:0.0.1" --base_image="ghcr.io/epicgames/unreal-engine:dev-5.5"
	cd -
}

build_sitl_docker_image(){
	image="$userName/nrt:sitl"
	filepath="$NRT_WS/docker/nrt/sitl"
	platform="linux/amd64"
	docker build -t shandilya1998/nrt_ardupilot:dev-ros -f docker/ardupilot/ardupilot_dev_docker/docker/Dockerfile_dev-ros --push .
	build_image $platform $image $filepath
}

start_simulation(){
	environment=$1
	xhost +local:docker
	spawn_container_if_needed airsim_container "shandilya1998/nrt_airsim:0.0.1" "x86_64"
}

stop_simulation(){
	docker stop airsim_container
}

start_sitl_container(){
	spawn_container_if_needed sitl_bridge_container shandilya1998/nrt:sitl
}

stop_sitl_container(){
	docker stop sitl_bridge_container
}

setup_airsim_ros_pkgs_for_docker_build(){

	directory=$1

	if [[ ! -n "$directory" ]]
	then
		directory="ardupilot"
	fi

	image="$userName/nrt:camera"
	filepath="$NRT_WS/docker/nrt/camera"
	platform="linux/amd64,linux/arm64"
	container_name="init_container"
	source $NRT_WS/scripts/start.sh "$NRT_WS" "$container_name" "$image"
	iexec init_container "ls && echo \"Starting Container Setup\" && /ws/scripts/git-setup.sh $3 $userEmail $userName && /ws/scripts/docker-setup.sh"
	iexec init_container "mkdir -p /ws/docker/nrt/$directory/airsim_ws/src/AirSim && \
		cp -r /ws/envs/ue5/AirSim/cmake/ \
		/ws/envs/ue5/AirSim/AirLib/ \
		/ws/envs/ue5/AirSim/AirSim.sln \
		/ws/envs/ue5/AirSim/DroneShell \
		/ws/envs/ue5/AirSim/HelloDrone \
		/ws/envs/ue5/AirSim/HelloCar \
		/ws/envs/ue5/AirSim/HelloSpawnedDrones \
		/ws/envs/ue5/AirSim/MavLinkCom \
		/ws/envs/ue5/AirSim/DroneServer \
		/ws/envs/ue5/AirSim/AirLibUnitTests \
		/ws/envs/ue5/AirSim/ros2 \
		/ws/docker/nrt/$directory/airsim_ws/src/AirSim/ && \
		echo \"here\" && \
		ls /ws/docker/nrt/$directory/airsim_ws/src/AirSim/"
}
