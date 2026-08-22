#!/bin/bash
# $1 selects the simulator target, one of airsim or airsim2. Defaults to
# airsim so that the existing no-argument caller in `djinn start sitl` is
# unchanged. For airsim2, $2 is the project and $3 the client configuration.
source $NRT_WS/scripts/helpers/data.sh
source $NRT_WS/scripts/helpers/exec.sh

target="${1:-airsim}"
mode="${2:-headless}"

if [[ "$target" == "airsim2" ]]; then
    project="${2:-StonePineForest}"
    config="${3:-Development}"
    pkg="/ws/sitl_ws/src/ue5/ProjectAirSim/packages/$project/$config/Linux"
    # The staged ELF is invoked rather than the generated $project.sh wrapper.
    # The wrapper's only jobs are a chmod, which build_airsim2_game.sh now
    # performs, and forwarding these flags, which upstream issue 75 reports
    # failing. A dropped -RenderOffScreen in a container with no display exits
    # with status 1 after two lines and is the least diagnosable failure
    # available. A Development client's binary is named bare $project; other
    # configurations append -Linux-$config.
    render_mode_flag="-RenderOffScreen"
    if [[ "$mode" == "headless" ]]; then
        render_mode_flag="-RenderOffScreen"
    elif [[ "$mode" == "windowed" ]]; then
        render_mode_flag="-windowed"
    fi
    iexec airsim2_container \
        "$pkg/$project/Binaries/Linux/$project \
         $render_mode_flag -nosound -unattended -nopause -NoSplash \
         -ResX=640 -ResY=480 -topicsport=8989 -servicesport=8990"
else
    iexec airsim_container \
        "/ws/StonePineForest/Linux/StonePineForest.sh -settings=/ws/settings.json -renderoffscreen"
fi
