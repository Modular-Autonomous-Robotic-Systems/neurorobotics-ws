#!/bin/bash

source /opt/ros/humble/setup.bash

cd /ardu_ws
colcon build --cmake-args -DBUILD_TESTING=ON
