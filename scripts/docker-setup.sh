#!/bin/bash

git submodule init
git submodule update --recursive --remote --merge

echo "Done Setup"
