#!/bin/bash

name="$2"
image="$3"
echo $name
echo $image
XAUTH=/tmp/.docker.xauth
docker run --rm -d -it -v $1:/ws/ \
			-v ./.ssh:/root/.ssh \
			-v /dev:/dev \
    		--device-cgroup-rule "c 81:* rmw" \
			--device-cgroup-rule "c 189:* rmw" \
			--device /dev/vchiq \
			-v /run/udev:/run/udev:ro \
			-e DISPLAY=$DISPLAY \
            -e XAUTHORITY=$XAUTHORITY \
			-e QT_GRAPHICSSYSTEM=native \
			-v $XAUTH:$XAUTH:rw \
			-v /tmp/.X11-unix:/tmp/.X11-unix \
			--env="DISPLAY" --net=host \
			--privileged --name $name $image bash
