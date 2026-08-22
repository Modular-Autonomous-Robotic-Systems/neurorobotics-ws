#!/bin/bash
# $1 selects the simulator target, one of airsim or airsim2.
# Defaults to airsim so that any caller written against the previous
# positional-directory convention still reaches the Cosys-AirSim container.

target="${1:-airsim}"

if [[ "$target" == "airsim2" ]]; then
    name="airsim2_container"
    image="shandilya1998/nrt_airsim:0.0.2"
    # The whole workspace, matching every other runtime container, so that the
    # game binary, the scene configuration and the build script are all
    # reachable by absolute path. Project AirSim has no settings file.
    mount="$NRT_WS"
    settings_mount=()
    # docker/airsim/Dockerfile now carries Claude Code and Antigravity CLI
    # (agy), same as docker/dev and docker/base. /home/ue4, not /root, since
    # this image runs as ue4, not root. See context/dev-ide-ai-clis.md.
    config_mount=(-v "$NRT_WS/.gemini:/home/ue4/.gemini" -v "$NRT_WS/.claude:/home/ue4/.claude" -v "$NRT_WS/.claude.json:/home/ue4/.claude.json")
else
    name="airsim_container"
    image="shandilya1998/nrt_airsim:0.0.1"
    # Only the UE Environments directory, so that -settings=/ws/settings.json
    # in run_airsim.sh resolves to Environments/settings.json.
    mount="$NRT_WS/sitl_ws/src/ue5/AirSim/Unreal/Environments"
    # Retained verbatim. $(pwd) is $NRT_WS because djinn cds there before
    # sourcing, so this binds $NRT_WS/settings.json, which is an empty
    # directory. The mount is inert because -settings= is always passed, and
    # it is preserved rather than corrected so that the Cosys-AirSim path
    # behaves exactly as it did before.
    settings_mount=(-v "$(pwd)/settings.json:/home/ue4/Documents/AirSim/settings.json")
    # shandilya1998/nrt_airsim:0.0.1 (Cosys-AirSim) carries no IDE, unlike
    # airsim2's image, so there is nothing for these to mount into.
    config_mount=()
fi

echo "Mount directory: $mount"
echo $name
echo $image
XAUTH=/tmp/.docker.xauth
docker run -d -it -v "$mount":/ws \
    --gpus=all \
    -v ./.ssh:/root/.ssh \
    -e DISPLAY=$DISPLAY \
    -e XAUTHORITY=/home/ue4/.Xauthority \
    -e QT_GRAPHICSSYSTEM=native \
    -v $XAUTH:$XAUTH:rw \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v /home/$UID/.Xauthority:/home/ue4/.Xauthority \
    "${settings_mount[@]}" \
    "${config_mount[@]}" \
    --env="DISPLAY" --net=host \
    --privileged --name $name $image bash
