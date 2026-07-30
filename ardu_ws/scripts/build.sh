#!/bin/bash

source /opt/ros/humble/setup.bash
source /ros_deps_ws/install/setup.bash

cd /ws/ardu_ws
rosdep install --from-paths src -y --ignore-src --rosdistro humble
colcon build --cmake-args -DBUILD_TESTING=ON
