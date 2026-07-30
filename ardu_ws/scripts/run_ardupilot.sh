#!/bin/bash
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

iexec ardupilot_container "cd /ardupilot && python3 Tools/autotest/sim_vehicle.py -v ArduCopter -f airsim-copter --console --map --enable-dds -A \"--serial1=udpclient:127.0.0.1:2019\""
