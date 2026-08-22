#!/bin/bash
# $1 selects the simulator target, one of airsim or airsim2, and thereby which
# launch file is used. Defaults to airsim so that the existing no-argument
# caller in `djinn start sitl` is unchanged.
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

target="${1:-airsim}"

if [[ "$target" == "airsim2" ]]; then
    launch_file="sitl2.launch.py"
else
    launch_file="sitl.launch.py"
fi

iexec_sitl sitl_bridge_container "ros2 launch controllers $launch_file use-sim-time:=True"
