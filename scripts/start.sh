#!/bin/bash

dir=$1
name="$2"
image="$3"
echo $name
echo $image
platform="$(uname -p)"
echo "host platform=$platform"

if [[ -n "$4" ]]; then
    platform="$4"
fi
echo "build platform=$platform"

if [[ "$platform" == "x86_64" ]]; then
    platform="linux/amd64"
elif [[ "$platform" == "aarch64" ]]; then
    platform="linux/arm64/v8"
fi

echo "platform=$platform"

XAUTH=/tmp/.docker.xauth
docker run -d -it -v $dir:/ws/ \
    -v ./.ssh:/root/.ssh \
    -v /dev:/dev \
    -v $NRT_WS/.gemini:/root/.gemini \
    -v $NRT_WS/.claude:/root/.claude \
    -v $NRT_WS/.claude.json:/root/.claude.json \
    --device-cgroup-rule "c 81:* rmw" \
    --device-cgroup-rule "c 189:* rmw" \
    --device /dev/vchiq \
    -v /run/udev:/run/udev:ro \
    -e DISPLAY=$DISPLAY \
    -e XAUTHORITY=$XAUTHORITY \
    -e TERM=xterm-256color \
    -e QT_GRAPHICSSYSTEM=native \
    -v $XAUTH:$XAUTH:rw \
    --platform=$platform \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    --env="DISPLAY" --net=host \
    --privileged --name $name $image bash
