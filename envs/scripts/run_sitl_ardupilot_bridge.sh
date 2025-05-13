#!/bin/bash
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

docker exec -it sitl_bridge_container bash -l -c "source /opt/ros/humble/setup.bash && source /ardu_ws/install/setup.bash && ros2 launch ardupilot_sitl sitl_dds_udp.launch.py transport:=udp4 synthetic_clock:=True wipe:=False model:=airsim-copter speedup:=1 slave:=0 instance:=0 defaults:=\$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/copter.parm,\$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/dds_udp.parm sim_address:=127.0.0.1 master:=tcp:127.0.0.1:5760 sitl:=127.0.0.1:5501 map:=False console:=False sim_port_in:=9003 sim_port_out:=9002 sim_address:=127.0.0.1"
