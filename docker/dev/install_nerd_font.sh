#!/bin/bash

# ==============================================================================
#  Nerd Font Installer (JetBrainsMono)
#  Supported OS: macOS, Linux
#  Note for Windows Users: This script generally cannot install fonts into 
#  Windows if run from WSL. Please install manually on Windows.
# ==============================================================================

FONT_NAME="JetBrainsMono"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip"
ZIP_FILE="JetBrainsMono.zip"

# 1. Detect OS and set target directory
OS="$(uname -s)"
case "$OS" in
    Linux*)     
        FONT_DIR="$HOME/.local/share/fonts/$FONT_NAME" 
        CMD_CACHE="fc-cache -fv"
        ;;
    Darwin*)    
        FONT_DIR="$HOME/Library/Fonts" 
        CMD_CACHE=""
        ;;
    *)          
        echo "❌ Unsupported OS: $OS"
        echo "If you are on Windows, please download and install the font manually."
        exit 1 
        ;;
esac

echo "Step 1: Preparing to install $FONT_NAME..."
mkdir -p "$FONT_DIR"

# 2. Download the Font
echo "Step 2: Downloading font..."
if command -v curl >/dev/null 2>&1; then
    curl -L -o "$ZIP_FILE" "$FONT_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$ZIP_FILE" "$FONT_URL"
else
    echo "❌ Error: Neither 'curl' nor 'wget' was found."
    exit 1
fi

# 3. Unzip
echo "Step 3: Extracting fonts..."
if command -v unzip >/dev/null 2>&1; then
    # -o: overwrite, -j: junk paths (flatten), -d: destination
    unzip -o -q "$ZIP_FILE" -d "$FONT_DIR"
else
    echo "❌ Error: 'unzip' command not found."
    exit 1
fi

# Cleanup
rm "$ZIP_FILE"

# 4. Refresh Cache (Linux only)
if [ -n "$CMD_CACHE" ]; then
    echo "Step 4: Refreshing font cache..."
    eval "$CMD_CACHE"
fi

echo "✅ Success! $FONT_NAME has been installed."
echo "👉 Action Required: Open your Terminal settings and change the font to 'JetBrainsMono Nerd Font'."
