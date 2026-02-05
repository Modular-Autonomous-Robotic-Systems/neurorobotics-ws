# #!/bin/bash

# export CMAKE_PREFIX_PATH=/Pangolin/build:$CMAKE_PREFIX_PATH
# export CMAKE_PREFIX_PATH=/opencv:$CMAKE_PREFIX_PATH



# echo "===============Building ROS2 Package=============="
# cd /ws/ros_ws
# echo "***********************************************"
# echo $PWD
# cd /ws/ros_ws/src/slam/ext/MORB_SLAM/
# ./build.sh -DCMAKE_BUILD_TYPE=RELEASE -j7
# cd /ws/ros_ws
# echo "***********************************************"
# # rm -rf build install
# colcon build --symlink-install --cmake-args '-DCMAKE_EXPORT_COMPILE_COMMANDS=1' '-DCMAKE_BUILD_TYPE=Release' '-Wno-dev' --mixin debug

#!/bin/bash

# Set environment variables
export CMAKE_PREFIX_PATH=/Pangolin/build:$CMAKE_PREFIX_PATH
export CMAKE_PREFIX_PATH=/opencv:$CMAKE_PREFIX_PATH

echo "===============Building ROS2 Package=============="
cd /ws/ros_ws || exit 1
echo "***********************************************"
echo $PWD
echo "***********************************************"

# Function to display the menu
show_menu() {
  echo "Select a package to build:"
  echo "1. All packages"
  echo "2. custom_interfaces"
  echo "3. gps_msgs"
  echo "4. mpu6050"
  echo "5. ros2_shared"
  echo "6. sensors"
  echo "7. slam"
  echo "8. tello"
  echo "9. vision-opencv"
  echo "10. controllers"
  echo "Enter the number of your choice: "
}

# Show the menu and get the user's choice
show_menu
read -r choice

# Map user input to the respective package
case $choice in
  1) package="" ;; # Build all packages
  2) package="custom_interfaces" ;;
  3) package="gps_msgs" ;;
  4) package="mpu6050" ;;
  5) package="ros2_shared" ;;
  6) package="sensors" ;;
  7) package="slam" ;;
  8) package="tello" ;;
  9) package="vision-opencv" ;;
  10) package="controllers" ;; 
  *) echo "Invalid choice, exiting."; exit 1 ;;
esac

# Build the selected package or all packages
if [ -z "$package" ]; then
  echo "Building all packages..."
  colcon build --symlink-install --cmake-args '-DCMAKE_EXPORT_COMPILE_COMMANDS=1' '-DCMAKE_BUILD_TYPE=Release' '-Wno-dev' --mixin debug
else
  echo "Building package: $package"
  colcon build --packages-select "$package" --symlink-install --cmake-args '-DCMAKE_EXPORT_COMPILE_COMMANDS=1' '-DCMAKE_BUILD_TYPE=Release' '-Wno-dev' --mixin debug
fi

echo "Build process complete."
