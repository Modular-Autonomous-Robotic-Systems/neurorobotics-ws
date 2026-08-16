#!/bin/bash

# This script is a helper for djinn, meant only to be sourced within djinn and
# other scripts that source $NRT_WS/scripts/helpers/data.sh
# available methods are
# 1. sync_directive_pair

# Ensures CLAUDE.md and GEMINI.md are symlinked to each other in $1.
# TODO need to make sure additional skills in ./skills are also linked programmatically down the line
# Will need to create appropriate mechanism here
sync_directive_pair() {
    local dir="$1"
    local claude="$dir/CLAUDE.md"
    local gemini="$dir/GEMINI.md"

    if [ -L "$claude" ] && [ "$(readlink "$claude")" = "GEMINI.md" ]; then
        return 0
    fi
    if [ -L "$gemini" ] && [ "$(readlink "$gemini")" = "CLAUDE.md" ]; then
        return 0
    fi

    local have_claude=0 have_gemini=0
    [ -e "$claude" ] && have_claude=1
    [ -e "$gemini" ] && have_gemini=1

    if [ "$have_claude" = 1 ] && [ "$have_gemini" = 1 ]; then
        echo "WARN: $dir has independent CLAUDE.md and GEMINI.md, not symlinked." >&2
        echo "      Resolve by hand: pick the canonical file, symlink the other to it." >&2
        return 0
    elif [ "$have_claude" = 1 ]; then
        ln -sfn CLAUDE.md "$gemini"
        echo "linked $gemini -> CLAUDE.md"
    elif [ "$have_gemini" = 1 ]; then
        ln -sfn GEMINI.md "$claude"
        echo "linked $claude -> GEMINI.md"
    fi
}
