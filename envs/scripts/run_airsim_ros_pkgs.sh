#!/bin/bash
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

iexec_ros nrt_container "cd /airsim_ws && \ 
	source install/setup.bash && \ 
	ros2 launch airsim_ros_pkgs airsim_node.launch.py host_ip:=127.0.0.1"
