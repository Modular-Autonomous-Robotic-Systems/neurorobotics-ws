#!/bin/bash
set -e

# setup ros2 environment
source "/opt/ros/$ROS_DISTRO/setup.bash" --
# install all ros dependencies for the workspace
#rosdep install -i --from-path src --rosdistro foxy -y
exec "$@"
