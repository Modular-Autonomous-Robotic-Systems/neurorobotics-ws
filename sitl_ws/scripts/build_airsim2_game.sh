#!/bin/bash
# Builds a Project AirSim Unreal environment inside airsim2_container.
# $1 selects the project, defaulting to StonePineForest, validated against
# every directory under unreal/ rather than a hardcoded list, so a newly
# added game needs no edit here. $2 selects the client configuration,
# defaulting to Development. $3, "true" or "false" (default "false"),
# selects whether to clean every build artefact, rebuild Blocks's SimLibs
# against whichever engine $UE_ROOT now points at, and refresh every other
# game's copy of the plugin before packaging $1. The old SimLibs-directory
# existence check is deliberately gone, since it could not tell a SimLibs
# built against a different engine from one that never needed rebuilding.
# The sim libs must exist before Unreal Build Tool runs regardless, because
# the plugin links their static archives by path out of
# Plugins/ProjectAirSim/SimLibs, which is upstream issues 83 and 129.

set -e
source /ws/scripts/helpers/sitl.sh

project="${1:-StonePineForest}"
config="${2:-Development}"
plugin_build_mode="${3:-build}"
echo "Building $1 in $2 via $3 build pathway"

PAS_ROOT=/ws/sitl_ws/src/ue5/ProjectAirSim

if ! list_projectairsim_games /ws | grep -qx "$project"; then
    echo "Unsupported project: $project"
    exit 1
fi

cd "$PAS_ROOT"

if [[ "$plugin_build_mode" == "build" ]]; then
    ./build.sh simlibs_release
elif [[ "$plugin_build_mode" == "clean-rebuild" ]]; then
    clean_projectairsim_build_artefacts /ws
    ./build.sh simlibs_release
    copy_projectairsim_plugin_to_games /ws
elif [[ "$plugin_build_mode" == "rebuild" ]]; then
    ./build.sh simlibs_release
    copy_projectairsim_plugin_to_games /ws
elif [[ "$plugin_build_mode" == "copy" ]]; then
    copy_projectairsim_plugin_to_games /ws
elif [[ "$plugin_build_mode" == "none" ]]; then
    echo "Not building plugin"
fi

"$UE_ROOT/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
    -project="$PAS_ROOT/unreal/$project/$project.uproject" \
    -nop4 -nocompile -build -cook -compressed -pak -allmaps -stage -archive \
    -archivedirectory="$PAS_ROOT/packages/$project/$config" \
    -clientconfig="$config" -clean -utf8output -prereqs

# run_airsim.sh invokes the staged ELF rather than the generated .sh wrapper,
# and the wrapper is what normally chmods the ELF, so do it here instead.
sudo chmod +x "$PAS_ROOT/packages/$project/$config/Linux/$project/Binaries/Linux/"* || true
