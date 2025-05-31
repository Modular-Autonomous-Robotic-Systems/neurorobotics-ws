#!/bin/bash

git submodule init
git submodule update --recursive --remote --merge
git submodule status | awk '{print $2}' | xargs -I {} bash -c 'apply_safe_directory "$PWD" "{}"'
cd ros_ws
git submodule init
git submodule status | awk '{print $2}' | xargs -I {} bash -c 'apply_safe_directory "$PWD" "{}"'
git submodule update --recursive --remote --merge
cd ../



echo "Done Setup"
