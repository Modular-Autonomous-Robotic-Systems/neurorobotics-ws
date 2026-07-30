#!/bin/bash

export CMAKE_PREFIX_PATH=/Pangolin/build:$CMAKE_PREFIX_PATH
export CMAKE_PREFIX_PATH=/opencv:$CMAKE_PREFIX_PATH

source /ros_deps_ws/install/setup.bash
source /ws/ardu_ws/install/setup.bash
source /ws/sitl_ws/install/setup.bash

echo "===============Building ROS2 Package=============="
cd /ws/ros_ws
echo "***********************************************"
echo $PWD
cd /ws/ros_ws/src/slam/ext/MORB_SLAM/
# ./build.sh -DCMAKE_BUILD_TYPE=RELEASE -j7
cd /ws/ros_ws
source install/setup.bash
echo "***********************************************"
# rm -rf build install

# -march must be chosen per target architecture:
# TODO for cross compilation using toolkit, the value must be
# set according to target architecture.
if [ -z "${CXX_MARCH}" ]; then
    case "$(uname -m)" in
    x86_64) CXX_MARCH=x86-64-v3 ;;               # AVX2 + FMA; Haswell (2013) / Zen 1 and later
    aarch64) CXX_MARCH=armv8.2-a+fp16+dotprod ;; # Jetson Orin Nano, Cortex-A78AE
    *) CXX_MARCH=native ;;
    esac
fi
echo "Building with CXX_MARCH=${CXX_MARCH}"

MAKEFLAGS="-j12" colcon build --symlink-install --cmake-args '-DCMAKE_EXPORT_COMPILE_COMMANDS=1' '-DCMAKE_BUILD_TYPE=RelWithDebInfo' "-DCXX_MARCH=${CXX_MARCH}" '-Wno-dev' --mixin debug --parallel-workers 1 --executor sequential
