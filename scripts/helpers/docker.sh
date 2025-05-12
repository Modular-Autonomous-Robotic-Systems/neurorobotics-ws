#!/bin/bash

# This script is a helper for djinn, meant only to be sourced within djinn and other scripts that source:
# 			$NRT_WS/scripts/data.sh
# 			$NRT_WS/scripts/exec.sh

#TODO add a method to check if a docker container exists and then start if it does not.

build_image(){
	if [[ -z "$(docker images -q $2 2> /dev/null)" ]]
	then
		if [[ "$(docker manifest inspect $2 > /dev/null 2>&1 && echo yes || echo no)" == "no" ]]
		then
			$NRT_WS/docker/scripts/docker-build.sh $1 $2 $3 $4 
		else
			docker pull $2
		fi
	fi
}

spawn_container_if_needed(){
    name=$1
    image_name=$2
    platform=$3
    echo "Starting container of name: $name from image $image_name"

    if [[ -n "$(docker ps -a -q -f name="${name}")" ]]
    then
        if [[ -n "$(docker ps -aq -f status=exited -f name="${name}")" ]]
        then
            # restart stopped container
            echo "Container Exists but stopped, restarting"
            docker start "${name}"
        else
            echo "Container exists and already present"
        fi
    else
        echo "Container does not exist creating now"
		if [[ ! -n "$platform" ]]
		then
			platform="$(uname -p)"
		fi
		if [[ "${name}" == "airsim_container" ]]
		then
			source $NRT_WS/envs/ue5/scripts/start.sh $NRT_WS/envs/ue5/AirSim/Unreal/Environments
		else
			source $NRT_WS/docker/scripts/start.sh $NRT_WS "${name}" ${image_name} ${platform}
		fi
    fi
}
