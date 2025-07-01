#!/bin/bash

# This script implements the steps to launch standalone data logging
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh
source $NRT_WS/scripts/helpers/docker.sh


echo "Starting container if needed for image: shandilya1998/nrt:$VERSION"
spawn_container_if_needed nrt_container shandilya1998/nrt:$VERSION

iexec_sitl2 nrt_container "ros2 launch controllers target_recorder.launch.py"
