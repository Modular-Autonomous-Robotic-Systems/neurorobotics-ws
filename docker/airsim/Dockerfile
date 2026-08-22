# shandilya1998/nrt:unreal is Unreal Engine 5.7 built on an Ubuntu 22.04 userland by
# docker/scripts/build_unreal.sh, which `djinn init docker airsim2` runs first. Epic's
# own ghcr.io/epicgames/unreal-engine:dev-5.7 is Ubuntu 18.04 and is not usable here,
# because Project AirSim's dependencies require 22.04.
ARG BASE_IMAGE=shandilya1998/nrt:unreal
FROM ${BASE_IMAGE}

# The base image ends on USER ue4. Every apt-get below needs root, and the
# image must end on ue4 again so that nothing writes root-owned files into
# the engine tree or $HOME.
USER root
ENV DEBIAN_FRONTEND=noninteractive

# Build toolchain. libeigen3-dev short circuits the GitLab clone at
# sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt:275-278. zlib1g-dev mitigates
# the libonnxruntime.so link failure of upstream issue 173. perl is required by
# the openssl-external target's CONFIGURE_COMMAND at CMakeLists.txt:349-367,
# which runs OpenSSL's own perl `Configure` script directly rather than through
# CMake. No clang, lld, llvm-dev or libc++-dev, because UE_ROOT selects the
# engine toolchain at CMakeLists.txt:27-39 and the system compiler is never used.
# cmake itself is intentionally absent from this list; see the pip install below.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git gnupg \
    libeigen3-dev lsb-release lsof make ninja-build perl \
    python3 python3-pip python3-venv rsync sudo unzip wget \
    zlib1g zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# CMake >=3.26 is required for the INSTALL_BYPRODUCTS keyword of ExternalProject_Add,
# used at CMakeLists.txt:386 for the openssl-external target. Ubuntu 22.04 (jammy)
# ships cmake 3.22.1 in apt, which does not recognise that keyword. ExternalProject_Add
# ignores unrecognised keywords rather than erroring, so the generated Ninja graph
# carries no dependency edge on OpenSSL's static libraries, and any target linking
# OPENSSL_CRYPTO_LIBRARY or OPENSSL_SSL_LIBRARY races the still-running OpenSSL build.
# Installed from PyPI rather than Kitware's APT repository, since python3-pip is
# already required above and this needs no extra apt source; the same command is
# upstream's own documented route to a working cmake, at docs/client_setup.md:58,123.
# Capped below 4, because CMake 4.0 errors on any cmake_minimum_required() below
# policy version 3.5, and while this project's own floor of 3.15.0 clears that,
# none of its FetchContent/ExternalProject dependencies (nng, assimp, msgpack,
# tinygltf, nlohmann-json, googletest) have been checked against it, so an
# unbounded floor would trade today's dated, understood defect for an untested one.
RUN python3 -m pip install --no-cache-dir 'cmake>=3.26,<4'

# Vulkan runtime. -RenderOffScreen still requires a loader and a driver.
# vulkan-tools, not vulkan-utils. The package was renamed at focal and the
# transitional vulkan-utils no longer exists on the jammy base this image now
# uses, so the pre-22.04 name fails to resolve exactly as vulkan-tools did on 18.04.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libvulkan1 vulkan-tools mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

# Desktop stack for the Unreal editor, needed only by the manual procedures
# of the integration plan's Phase 11. Drop this layer if the editor moves to
# a separate image.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libfontconfig1 libfreetype6 libgtk-3-0 libnss3 libsdl2-2.0-0 \
    libx11-6 libxcursor1 libxext6 libxi6 libxinerama1 libxrandr2 \
    libxss1 libxtst6 x11-apps x11-xserver-utils xauth xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN echo "ue4 ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER ue4

# UE_ROOT is the single switch selecting the engine toolchain at
# sitl_ws/src/ue5/ProjectAirSim/CMakeLists.txt:27-39
ENV UE_ROOT=/home/ue4/UnrealEngine

# display is required in addition to the headless capabilities because the
# editor opens a real window on the forwarded X display.
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=graphics,compute,utility,display

EXPOSE 8989 8990

# Neovim IDE, matching docker/dev/Dockerfile so the same editor and agentic
# CLIs are available here for in-editor Unreal/Project AirSim work. Back to
# root for system-wide installs; the image still ends on USER ue4 below,
# since UBT and the editor need to write into $UE_ROOT and $HOME.
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    tar gzip procps ripgrep fd-find clang lldb openjdk-17-jdk \
    ncurses-term ncurses-base locales xclip python3-pylatexenc \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Debian/Ubuntu's fd-find package ships the binary as `fdfind`; symlink it so
# tools that look for the upstream binary name `fd` (agentic.nvim's file
# picker) find it. See context/dev-ide-nvim-toolchain.md §3.2.
RUN ln -s /usr/bin/fdfind /usr/bin/fd

# Generate UTF-8 Locale. This is essential. Without it, Neovim may struggle
# with special characters. See context/dev-ide-nvim-toolchain.md §3.3.
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LANGUAGE en_US:en

# Claude Code and Antigravity CLI (agy). Unlike docker/base and docker/dev,
# this image is never cross-built for arm64, build_airsim2_docker_image runs
# a plain `docker build` rather than buildx --platform, because the Unreal
# Engine base image and the prebuilt ONNX Runtime tarball are x86-64 only
# (see context/project-airsim-docker-build.md §2 and djinn's `init docker
# airsim2` branch), so neither install needs the $TARGETARCH guard
# docker/base/Dockerfile and docker/dev/Dockerfile carry. See
# context/dev-ide-ai-clis.md §1.
RUN curl -fsSL https://claude.ai/install.sh | bash
# Point Claude to the bind-mounted config dir so credentials persist across
# containers. HOME is /home/ue4, not /root, since this image ends on USER ue4.
ENV CLAUDE_CONFIG_DIR=/home/ue4/.claude
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# Node 22, for the ACP adapters below, matching docker/base/Dockerfile and
# docker/dev/Dockerfile.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @agentclientprotocol/claude-agent-acp agy-acp pyright bash-language-server dockerfile-language-server-nodejs tree-sitter-cli@0.25.10

# --- Install Java LSP (JDTLS) ---
RUN mkdir -p /opt/jdtls && \
    curl -L https://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz -o /opt/jdtls/jdtls.tar.gz && \
    tar -xzf /opt/jdtls/jdtls.tar.gz -C /opt/jdtls && \
    rm /opt/jdtls/jdtls.tar.gz

WORKDIR /opt
# This image is only ever built with a plain `docker build`, never buildx --platform
# (see the Claude Code/agy comment above), but BuildKit still resolves TARGETARCH to the
# daemon's native platform ("amd64" here) without it, so the same ARG works uniformly
# across every Dockerfile in docker/ that branches on build architecture, in place of
# uname -m, which this block used until 2026-08-16.
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    NVIM_ASSET="nvim-linux-x86_64.tar.gz"; \
    NVIM_DIR="nvim-linux-x86_64"; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
    NVIM_ASSET="nvim-linux-arm64.tar.gz"; \
    NVIM_DIR="nvim-linux-arm64"; \
    else \
    echo "Unsupported architecture: $TARGETARCH"; exit 1; \
    fi && \
    echo "Downloading Neovim for $TARGETARCH..." && \
    curl -fLO "https://github.com/neovim/neovim/releases/download/v0.11.0/$NVIM_ASSET" && \
    tar -xzf "${NVIM_ASSET}" && \
    rm "${NVIM_ASSET}" && \
    # Rename specific arch folder to generic 'nvim' for PATH consistency
    mv "${NVIM_DIR}" nvim
ENV PATH="$PATH:/opt/nvim/bin"
RUN echo 'export PATH="$PATH:/opt/nvim/bin"' >> /home/ue4/.bashrc

# fzf from upstream, not apt: fzf-lua aborts below 0.36 and jammy pins
# 0.29.0. See context/dev-ide-nvim-toolchain.md §3.1.
ARG FZF_VERSION=0.74.2
# fzf's own release asset naming already matches TARGETARCH ("amd64"/"arm64"), so no
# translation table is needed here, only the unsupported-architecture guard.
RUN if [ "$TARGETARCH" != "amd64" ] && [ "$TARGETARCH" != "arm64" ]; then \
    echo "Unsupported architecture: $TARGETARCH"; exit 1; \
    fi && \
    curl -fLO "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${TARGETARCH}.tar.gz" && \
    tar -xzf "fzf-${FZF_VERSION}-linux_${TARGETARCH}.tar.gz" -C /usr/local/bin && \
    rm "fzf-${FZF_VERSION}-linux_${TARGETARCH}.tar.gz" && \
    fzf --version

# Owned by ue4, not root: nvim runs as ue4 at container runtime and lazy.nvim
# writes lazy-lock.json back into this directory.
RUN mkdir -p /home/ue4/.config/nvim /home/ue4/.config/nvim/lua/plugins/ /home/ue4/.config/nvim/ftplugin/ && \
    chown -R ue4:ue4 /home/ue4/.config
COPY --chown=ue4:ue4 init.lua /home/ue4/.config/nvim/init.lua
COPY --chown=ue4:ue4 core.lua /home/ue4/.config/nvim/lua/plugins/core.lua
COPY --chown=ue4:ue4 ai.lua /home/ue4/.config/nvim/lua/plugins/ai.lua
COPY --chown=ue4:ue4 git.lua /home/ue4/.config/nvim/lua/plugins/git.lua
COPY --chown=ue4:ue4 lang.lua /home/ue4/.config/nvim/lua/plugins/lang.lua
COPY --chown=ue4:ue4 lsp.lua /home/ue4/.config/nvim/lua/plugins/lsp.lua
COPY --chown=ue4:ue4 ui.lua /home/ue4/.config/nvim/lua/plugins/ui.lua

RUN sed -i 's/^# force_color_prompt=yes/force_color_prompt=yes/' /home/ue4/.bashrc && \
    echo "alias ls='ls --color=auto'" >> /home/ue4/.bashrc && \
    echo "alias grep='grep --color=auto'" >> /home/ue4/.bashrc && \
    echo "alias vim='nvim'" >> /home/ue4/.bashrc && \
    echo "alias vi='nvim'" >> /home/ue4/.bashrc && \
    echo "alias neovim='nvim'" >> /home/ue4/.bashrc

# Nerd Fonts (JetBrainsMono), system-wide.
RUN mkdir -p /usr/share/fonts/truetype/jetbrains-mono && \
    wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip && \
    unzip -q JetBrainsMono.zip -d /usr/share/fonts/truetype/jetbrains-mono && \
    rm JetBrainsMono.zip && \
    fc-cache -fv

# Back to ue4 for anything that writes into $HOME: ruff installs to
# $HOME/.local/bin, and Lazy's plugin state must land under
# /home/ue4/.local/{share,state}/nvim, since that is the user the container
# actually runs as, not /root.
USER ue4
RUN curl -LsSf https://astral.sh/ruff/install.sh | sh
ENV PATH="$PATH:/home/ue4/.local/bin"
RUN nvim --headless "+Lazy! sync" +qa

# Restores the working directory the base image set (WORKDIR /home/ue4/UnrealEngine
# in docker/unreal/Dockerfile), which the WORKDIR /opt above, used only to stage the
# Neovim download, would otherwise leave overridden for the final image.
WORKDIR /home/ue4/UnrealEngine
CMD ["bash"]
