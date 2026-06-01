#!/bin/bash

source /opt/ros/$ROS_DISTRO/setup.bash

mkdir -p /ros_ws/src
cd /ros_ws/src
git clone https://github.com/christianrauch/camera_ros.git
cd /ros_ws/src/camera_ros
# git checkout 46c6573
cd /ros_ws
rosdep install -y --from-paths src --ignore-src --rosdistro $ROS_DISTRO --skip-keys=libcamera
colcon build --event-handlers=console_direct+
source install/setup.bash
