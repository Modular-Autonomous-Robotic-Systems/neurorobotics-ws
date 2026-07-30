#!/bin/bash
set -e

# setup ros2 environment
source "/opt/ros/$ROS_DISTRO/setup.bash" --
source "/ros_deps_ws/install/setup.bash"
[ -f "/ws/ardu_ws/install/setup.bash" ] && source "/ws/ardu_ws/install/setup.bash"
[ -f "/ws/sitl_ws/install/setup.bash" ] && source "/ws/sitl_ws/install/setup.bash"
# install all ros dependencies for the workspace
#rosdep install -i --from-path src --rosdistro foxy -y
exec "$@"
