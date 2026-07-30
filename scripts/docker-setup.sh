#!/bin/bash

git submodule init
git submodule update --recursive --remote --merge
git config core.editor nvim

echo "Done Setup"
