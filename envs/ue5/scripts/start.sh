#!/bin/bash

name="airsim_container"
image="shandilya1998/nrt_airsim:0.0.1"
echo "Environments directory: $1"
echo $name
echo $image
XAUTH=/tmp/.docker.xauth
docker run -d -it -v $1:/ws \
			--gpus=all \
			-v ./.ssh:/root/.ssh \
			-e DISPLAY=$DISPLAY \
            -e XAUTHORITY=/home/ue4/.Xauthority \
			-e QT_GRAPHICSSYSTEM=native \
			-v $XAUTH:$XAUTH:rw \
			-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
			-v /home/$UID/.Xauthority:/home/ue4/.Xauthority \
			-v $(pwd)/settings.json:/home/ue4/Documents/AirSim/settings.json \
			--env="DISPLAY" --net=host \
			--privileged --name $name $image bash
