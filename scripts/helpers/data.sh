#!/bin/bash

# This script is a helper for djinn, meant only to be sourced within djinn and other scripts to be run through djinn in separate windows

config_file=$NRT_WS/.djinn_config
# Refer to the following link for information about state management in bash using a statefile
# https://stackoverflow.com/questions/63084354/how-to-store-state-between-two-consecutive-runs-of-a-bash-script
statefile="/tmp/djinn_state"
last_run_sitl_env=""
# xhost +
echo "WORKSPACE PATH: $NRT_WS"
echo "DJINN MODE: $DJINN_MODE"

# Source the statefile to restore state
. "$statefile" 2>/dev/null || :

save_state () {
  typeset -p "$@" >"$statefile"
}

trap 'save_state last_run_sitl_env' EXIT

export $(grep -v '^#' $config_file | xargs)
