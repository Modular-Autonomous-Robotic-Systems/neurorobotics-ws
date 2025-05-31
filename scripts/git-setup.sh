#!/bin/bash

echo ""

echo "in docker-setup.sh email: $2"
echo "in docker-setup.sh username: $3"

apply_safe_directory(){
    echo "Applying Safe Directory command to folder: ${1}/${2}"
    git config --global --add safe.directory "${1}/${2}"
}

git config --global --add safe.directory "/ws"
export -f apply_safe_directory
git submodule init
git submodule status | awk '{print $2}' | xargs -I {} bash -c 'apply_safe_directory "$PWD" "{}"'
git submodule status | awk '{print $2}' | xargs -I {} bash -c 'apply_safe_directory "$PWD" "{}"'
cd ros_ws
git submodule init
git submodule status | awk '{print $2}' | xargs -I {} bash -c 'apply_safe_directory "$PWD" "{}"'
cd ../


git config --global user.email "$2"
git config --global user.name "$3"
git config --global core.editor vim
git config commit.template /ws/.gitmessage
cd /ws/ros_ws
git config commit.template /ws/ros_ws/.gitmessage

echo ""

echo ""

echo "Done Setup"
