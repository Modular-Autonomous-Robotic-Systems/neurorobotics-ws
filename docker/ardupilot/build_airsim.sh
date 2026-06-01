#!/bin/bash

source /opt/ros/humble/setup.bash

cd /airsim_ws/src/AirSim

# Download rpclib
if [ ! -d "external/rpclib/rpclib-2.3.1" ]; then
    echo "*********************************************************************************************"
    echo "Downloading rpclib..."
    echo "*********************************************************************************************"

    wget https://github.com/WouterJansen/rpclib/archive/refs/tags/v2.3.1.zip

    # remove previous versions
    rm -rf "external/rpclib"

    mkdir -p "external/rpclib"
    unzip -q v2.3.1.zip -d external/rpclib
    rm v2.3.1.zip
fi

if [ ! -d "AirLib/deps/eigen3" ]; then
    echo "Downloading Eigen..."
    wget -O eigen3.zip https://github.com/WouterJansen/eigen/archive/refs/tags/3.4.1r.zip
    unzip -q eigen3.zip -d temp_eigen
    mkdir -p AirLib/deps/eigen3
    mv temp_eigen/eigen*/Eigen AirLib/deps/eigen3
    rm -rf temp_eigen
    rm eigen3.zip
else
    echo "Eigen is already installed."
fi

cd /airsim_ws
rosdep install --from-paths src -y --ignore-src --skip-keys pcl --skip-keys message_runtime --skip-keys message_generation
rm -rf build install log
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release
