#!/usr/bin/env bash

# Builds the Unreal Engine development image on an Ubuntu 22.04 userland and tags it
# shandilya1998/nrt:unreal, which is the base image of docker/airsim/Dockerfile.
#
# Ported from Engine/Extras/Containers/Dockerfiles/linux/build.sh of
# EpicGames/UnrealEngine branch 5.2, commit 02dc8dbdd89f749cd5500376e9bb87271bf64848,
# and re-checked against branch 5.7, commit 0bcfaffa52e9557258dbd388835ac7668fe864a4,
# when the pin moved. Those two upstream files differ in exactly one line, the
# BASEIMAGE build argument, which is the line the conditional below now derives
# per release, so every other line ported here is valid against both branches.
# The branch resolution, the build arguments and the BuildKit secret plumbing are
# upstream's. The deltas are that only the `dev` image is built rather than the five
# upstream builds, that the base image is always Ubuntu 22.04, since Project AirSim
# requires that userland whatever the engine version, that the credential files are
# read from $NRT_WS rather than the working directory, and that the result is never
# pushed, because the Unreal Engine EULA does not permit redistribution of an image
# containing the engine.
#
# Usage: build_unreal.sh [RELEASE] [GIT_REPO] [CHANGELIST_OVERRIDE]

set -e

if [[ -z "$NRT_WS" ]]; then
    echo '[build_unreal.sh] NRT_WS is not set. It must point at the workspace root.'
    exit 1
fi

# The engine release to build. 5.7 is the version Project AirSim is pinned to, for
# the reasons in context/project-airsim-docker-build.md section 2 and
# context/unreal-engine-packaging.md section 11.
UNREAL_ENGINE_RELEASE="5.7"
if [[ ! -z "$1" ]]; then
    UNREAL_ENGINE_RELEASE="$1"
fi

# Determine which Git branch/tag we will be pulling the Unreal Engine source code from
# (If the release value contains a dash or does not contain two dots then we treat it as a branch/tag name)
GIT_BRANCH="${UNREAL_ENGINE_RELEASE}-release"
dots=$(echo "${UNREAL_ENGINE_RELEASE}" | grep -o '[.]' | wc -l)
if [[ "${UNREAL_ENGINE_RELEASE}" == *"-"* ]] || [[ "${dots}" != "2" ]]; then
    GIT_BRANCH="${UNREAL_ENGINE_RELEASE}"
fi

# If the user specified a custom Git repository to clone from then use that
GIT_REPO=https://github.com/EpicGames/UnrealEngine.git
if [[ ! -z "$2" ]]; then
    GIT_REPO="$2"
fi

# Determine whether the user specified a changelist number to set in Build.version
CHANGELIST_OVERRIDE=""
if [[ ! -z "$3" ]]; then
    CHANGELIST_OVERRIDE="$3"
fi

# If the user specified a git commit hash instead of a release, branch or tag then automatically determine the changelist
# number from the commit message, and tag the built container images with an abbreviated version of the commit hash
COMMIT_HASH=$(echo "${UNREAL_ENGINE_RELEASE}" | grep -E -o '^[0-9a-f]{40}$' || true)
COMMIT_SHORT=$(echo "${COMMIT_HASH}" | grep -E -o '^[0-9a-f]{8}' || true)
if [[ ! -z "$COMMIT_HASH" ]]; then
    UNREAL_ENGINE_RELEASE="$COMMIT_SHORT"
    CHANGELIST_OVERRIDE="auto"
fi

IMAGE="${UNREAL_IMAGE:-shandilya1998/nrt:unreal}"

# nvidia/opengl's own glvnd-devel tag that upstream's build.sh pairs with each
# release differs by release, 1.0-glvnd-devel-ubuntu18.04 for 5.2's own build.sh
# and 1.2-glvnd-devel-ubuntu22.04 for 5.7's, confirmed against both branches'
# own copies of Engine/Extras/Containers/Dockerfiles/linux/build.sh. Neither
# pairing is usable verbatim, since Project AirSim requires 22.04 regardless of
# engine version, so the tag below is chosen per release and always kept on
# 22.04. 5.2's tag here is the one this workspace already validated while
# pinned to 5.2, not a pairing upstream itself ever uses.
BASEIMAGEDEFAULT="nvidia/opengl:1.2-glvnd-devel-ubuntu22.04"
if [[ "$UNREAL_ENGINE_RELEASE" == "5.2" ]]; then
    BASEIMAGEDEFAULT="nvidia/opengl:1.0-glvnd-devel-ubuntu22.04"
fi
BASEIMAGE="${UNREAL_BASE_IMAGE:-$BASEIMAGEDEFAULT}"
CONTEXT="$NRT_WS/docker/unreal"

# The engine is compiled from source into an Installed Build, which takes hours. Never
# repeat that implicitly. UNREAL_FORCE_REBUILD=1 opts back in.
if [[ -n "$(docker images -q "$IMAGE" 2>/dev/null)" && "${UNREAL_FORCE_REBUILD:-0}" != "1" ]]; then
    echo "[build_unreal.sh] $IMAGE already exists, skipping the rebuild."
    echo '[build_unreal.sh] Set UNREAL_FORCE_REBUILD=1 to rebuild it anyway.'
    return 0 2>/dev/null || exit 0
fi

# Verify that the user has placed their GitHub username in the file `username.txt`
if [ ! -f "$NRT_WS/username.txt" ]; then
    echo "Please place your GitHub username in a text file called \`username.txt\` in $NRT_WS."
    exit 1
fi

# Verify that the user has placed their GitHub personal access token in the file `password.txt`
if [ ! -f "$NRT_WS/password.txt" ]; then
    echo "Please place your GitHub personal access token in a text file called \`password.txt\` in $NRT_WS."
    echo 'Note that you should NOT use your GitHub password. See the following page for details on why a token is needed:'
    echo 'https://github.blog/2020-12-15-token-authentication-requirements-for-git-operations/'
    exit 1
fi

# The token is only consumed hours into the build, at the clone step, so an unpopulated
# placeholder is caught here rather than after a long and wasted build.
if grep -q 'REPLACE_WITH_GITHUB_PERSONAL_ACCESS_TOKEN' "$NRT_WS/password.txt"; then
    echo "[build_unreal.sh] $NRT_WS/password.txt still holds the placeholder."
    echo '[build_unreal.sh] Replace it with a GitHub personal access token whose account'
    echo '[build_unreal.sh] is linked to Epic Games and can read EpicGames/UnrealEngine.'
    exit 1
fi

# Assemble the arguments to pass to the `docker buildx build` command
args=(
    --build-arg "BASEIMAGE=${BASEIMAGE}"
    --build-arg "GIT_REPO=${GIT_REPO}"
    --build-arg "GIT_BRANCH=${GIT_BRANCH}"
    --build-arg "CHANGELIST=${CHANGELIST_OVERRIDE}"
    --secret "id=username,src=$NRT_WS/username.txt"
    --secret "id=password,src=$NRT_WS/password.txt"
    --platform linux/amd64
    --progress=plain
)

# Print our build configuration values
echo 'Build configuration'
echo '-------------------'
echo
echo "Unreal Engine Release: ${UNREAL_ENGINE_RELEASE}"
echo "Git Repository:        ${GIT_REPO}"
echo "Git Branch/Tag/Commit: ${GIT_BRANCH}"
echo "Changelist Override:   ${CHANGELIST_OVERRIDE}"
echo "Base Image:            ${BASEIMAGE}"
echo "Target Image:          ${IMAGE}"
echo
echo '[build_unreal.sh] This compiles an Installed Build of the engine from source.'
echo '[build_unreal.sh] Expect several hours and a large amount of free disk space.'
echo

# Print commands as they are executed and halt immediately if any command fails
set -x

# No --push. The image contains the Unreal Engine and stays on the local host.
docker buildx build \
    -t "$IMAGE" \
    "${args[@]}" \
    --load \
    "$CONTEXT"
