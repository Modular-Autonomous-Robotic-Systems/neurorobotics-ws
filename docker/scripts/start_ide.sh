#!/bin/bash

name="$1"
image="$2"
echo $name
echo $image
XAUTH=/tmp/.docker.xauth
docker run --rm -d -it -v $NRT_WS:/ws/ \
    -v ./.ssh:/root/.ssh \
    -v /dev:/dev \
    --device-cgroup-rule "c 81:* rmw" \
    --device-cgroup-rule "c 189:* rmw" \
    --device /dev/vchiq \
    -v /run/udev:/run/udev:ro \
    -e DISPLAY=$DISPLAY \
    -e XAUTHORITY=$XAUTHORITY \
    -e TERM=xterm-256color \
    -e QT_GRAPHICSSYSTEM=native \
    -v $XAUTH:$XAUTH:rw \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v $NRT_WS/.local/share/nvim:/root/.local/share/nvim \
    -v $NRT_WS/.local/state/nvim:/root/.local/state/nvim \
    -v $NRT_WS/.gemini:/root/.gemini \
    -v $NRT_WS/.claude:/root/.claude \
    -v $NRT_WS/.claude.json:/root/.claude.json \
    --env="DISPLAY" --net=host \
    --privileged --name $name $image bash
