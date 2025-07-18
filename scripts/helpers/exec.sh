#!/bin/bash

# This script is helper script for djinn, meant only to be sourced within djinn and other scripts that source $NRT_WS/scripts/data.sh

iexec(){
            time docker container exec -it "$1" /bin/bash -l -c "$2"
        }

iexec_ros(){
			export $(grep -v '^#' $config_file | xargs)
			time docker container exec -it "$1" /bin/bash -l -c "source /opt/ros/${ROS_VERSION}/setup.bash && $2"
        }

iexec_kalibr(){
			time docker container exec -it "$1" /bin/bash -l -c "source /opt/ros/noetic/setup.bash && source \$WORKSPACE/devel/setup.bash && $2"
        }

terminate_process(){
			local process_name=$1
			ps -ef | grep $process_name | grep -v grep | awk '{print $2}' | xargs -r kill -9
		}

iexec_sitl(){
			export $(grep -v '^#' $config_file | xargs)
			time docker container exec -it "$1" /usr/bin/bash -l -c "source /opt/ros/${ROS_VERSION}/setup.bash && source /ardu_ws/install/setup.bash && source /airsim_ws/install/setup.bash && source /ws/ros_ws/install/setup.bash && $2"
}

iexec_sitl2(){
			export $(grep -v '^#' $config_file | xargs)
			time docker container exec "$1" /usr/bin/bash -l -c "echo \"starting execution process\n\" && source /opt/ros/${ROS_VERSION}/setup.bash && echo \"installing ardupilot dependencies\n\" && source /ardu_ws/install/setup.bash && echo \"installing airsim dependencies\n\" && source /airsim_ws/install/setup.bash && echo \"installing nrt dependencies\n\" && source /ws/ros_ws/install/setup.bash && echo \"executing now\n\" && $2"
}
