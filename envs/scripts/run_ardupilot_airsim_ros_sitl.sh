#!/bin/bash
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

iexec_sitl sitl_bridge_container "ros2 launch controllers sitl.launch.py" 
