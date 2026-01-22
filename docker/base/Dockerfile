# Use a minimal Ubuntu base image
FROM ubuntu:22.04

# TODO use alpine linux (more secure and leaner): https://jfrog.com/devops-tools/article/why-use-ubuntu-as-a-docker-base-image-when-alpine-exists/
# But there are some challenges: https://unix.stackexchange.com/questions/593549/can-you-install-ubuntu-or-debian-packages-in-alpine

# Error: https://uk.mathworks.com/help/matlab/matlab_env/remove-canberra-gtk-module-and-pk-gtk-module-messages.html#
# Solution: https://askubuntu.com/questions/1175572/how-to-fix-error-failed-to-load-module-canberra-gtk-module
#           https://uk.mathworks.com/help/matlab/matlab_env/remove-canberra-gtk-module-and-pk-gtk-module-messages.html# 

# Set environment variables to avoid interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV SHELL=/bin/bash
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LANGUAGE en_US:en

# setup timezone
RUN echo 'Asia/Kolkata' > /etc/timezone && \
    ln -snf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && \
    apt-get update && \
    apt-get install -q -y --no-install-recommends tzdata gpg-agent && \
    rm -rf /var/lib/apt/lists/*

# Install dependencies
RUN apt update && \
    apt install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:ubuntu-toolchain-r/test && \
    add-apt-repository -y ppa:deadsnakes/ppa  && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    ruby-dev \
    lua5.2 \
    liblua5.2-dev \
    libperl-dev \
    git\
    curl \
    wget \
    tar \
    gzip \
    fd-find \
    fzf \
    ripgrep \
    checkinstall \
    python3-dev \
    libglfw3-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libglew-dev \
    udev \
    sudo \
    gcc-9 \
    g++ \
    libeigen3-dev \
    cmake \
    unzip \
    pkg-config \
    libssl-dev \
    openssh-client \
    gdb \
    dirmngr \
    gnupg2 \
    bash-completion \
    clang \
    lldb \
    openjdk-17-jdk \
    locales \
    xclip \
    python3-argcomplete \
    python3-flake8 \
    python3-flake8-blind-except \
    python3-flake8-builtins \
    python3-flake8-class-newline \
    python3-flake8-comprehensions \
    python3-flake8-deprecated \
    python3-flake8-docstrings \
    python3-flake8-import-order \
    python3-flake8-quotes \
    python3-pip \
    python3-pytest-cov \
    python3-pytest-mock \
    python3-pytest-repeat \
    python3-pytest-rerunfailures \
    python3-pytest-runner \
    python3-venv \
    python3-pytest-timeout && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y \
    npm
RUN npm install n -g && \
    n latest

RUN npm install -g pyright bash-language-server dockerfile-language-server-nodejs tree-sitter-cli

# --- Install Java LSP (JDTLS) ---
# Downloading Eclipse JDTLS snapshot for headless installation
RUN mkdir -p /opt/jdtls && \
    curl -L https://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz -o /opt/jdtls/jdtls.tar.gz && \
    tar -xzf /opt/jdtls/jdtls.tar.gz -C /opt/jdtls && \
    rm /opt/jdtls/jdtls.tar.gz

WORKDIR /opt
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
    NVIM_ASSET="nvim-linux-x86_64.tar.gz"; \
    NVIM_DIR="nvim-linux-x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
    NVIM_ASSET="nvim-linux-arm64.tar.gz"; \
    NVIM_DIR="nvim-linux-arm64"; \
    else \
    echo "Unsupported architecture: $ARCH"; exit 1; \
    fi && \
    echo "Downloading Neovim for $ARCH..." && \
    curl -fLO "https://github.com/neovim/neovim/releases/download/v0.11.0/$NVIM_ASSET" && \
    tar -xzf "${NVIM_ASSET}" && \
    rm "${NVIM_ASSET}" && \
    # Rename specific arch folder to generic 'nvim' for PATH consistency
    mv "${NVIM_DIR}" nvim

# Update PATH to include the generic Neovim bin location
ENV PATH="$PATH:/opt/nvim/bin"
RUN echo 'export PATH="$PATH:/opt/nvim/bin"' >> /root/.bashrc

RUN mkdir -p /root/.config/nvim /root/.config/nvim/lua/plugins/ /root/.config/nvim/ftplugin/
COPY init.lua /root/.config/nvim/init.lua
COPY core.lua /root/.config/nvim/lua/plugins/core.lua
COPY git.lua /root/.config/nvim/lua/plugins/git.lua
COPY lang.lua /root/.config/nvim/lua/plugins/lang.lua
COPY lsp.lua /root/.config/nvim/lua/plugins/lsp.lua
COPY ui.lua /root/.config/nvim/lua/plugins/ui.lua

RUN sed -i 's/^# force_color_prompt=yes/force_color_prompt=yes/' /root/.bashrc && \
    echo "alias ls='ls --color=auto'" >> /root/.bashrc && \
    echo "alias grep='grep --color=auto'" >> /root/.bashrc && \
    echo "alias vim='nvim'" >> /root/.bashrc && \
    echo "alias vi='nvim'" >> /root/.bashrc && \
    echo "alias neovim='nvim'" >> /root/.bashrc

# 4. Install Nerd Fonts (JetBrainsMono)
# This installs the font INTO the container.
# Note: For terminal usage, you usually need this font on your HOST machine.
RUN mkdir -p /usr/share/fonts/truetype/jetbrains-mono && \
    wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip && \
    unzip -q JetBrainsMono.zip -d /usr/share/fonts/truetype/jetbrains-mono && \
    rm JetBrainsMono.zip && \
    fc-cache -fv

RUN nvim --headless "+Lazy! sync" +qa

# Use a more appropriate entrypoint
WORKDIR /ws
CMD ["/bin/bash"]
