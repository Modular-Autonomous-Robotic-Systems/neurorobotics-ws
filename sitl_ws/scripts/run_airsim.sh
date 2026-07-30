#!/bin/bash
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

iexec airsim_container "/ws/StonePineForest/Linux/StonePineForest.sh -settings=/ws/settings.json -renderoffscreen"
