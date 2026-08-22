FROM node:22-slim AS base

# Create app directory and set ownership
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    unzip \
    tar \
    gzip \
    build-essential \
    procps \
    ripgrep \
    fd-find \
    python3 \
    python3-pip \
    python3-venv \
    clang \
    lldb \
    openjdk-17-jdk \
    ncurses-term \
    ncurses-base \
    locales \
    xclip \
    python3-pylatexenc \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Debian's fd-find package ships the binary as `fdfind` (name clash with an
# unrelated `fd` package); symlink it so tools that look for the upstream
# binary name `fd` (e.g. agentic.nvim's file picker) find it.
RUN ln -s /usr/bin/fdfind /usr/bin/fd

# Set terminal capabilities
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV SHELL=/bin/bash
# Generate UTF-8 Locale
# This is essential. Without it, Neovim may struggle with special characters.
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen

# Set Environment Variables for Locale
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LANGUAGE en_US:en

# Install global dependencies as root (necessary for global packages)
ARG CACHEBUST=1
ARG TARGETARCH
# Install Claude Code CLI for authentication (claude /login)
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    curl -fsSL https://claude.ai/install.sh | bash; \
    else \
    echo "Skipping Claude Code install on $TARGETARCH"; \
    fi
# Point Claude to the bind-mounted config dir so credentials persist across containers
ENV CLAUDE_CONFIG_DIR=/root/.claude
# Antigravity CLI (agy) — Google's terminal agent, successor to Gemini CLI for
# consumer/free tiers (retired 2026-06-18). Installs to /root/.local/bin, which
# is already on PATH below. https://antigravity.google/download
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    curl -fsSL https://antigravity.google/cli/install.sh | bash; \
    else \
    echo "Skipping Antigravity CLI install on $TARGETARCH"; \
    fi
RUN npm install -g @agentclientprotocol/claude-agent-acp agy-acp pyright bash-language-server dockerfile-language-server-nodejs tree-sitter-cli@0.25.10

# --- Install Java LSP (JDTLS) ---
# Downloading Eclipse JDTLS snapshot for headless installation
RUN mkdir -p /opt/jdtls && \
    curl -L https://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz -o /opt/jdtls/jdtls.tar.gz && \
    tar -xzf /opt/jdtls/jdtls.tar.gz -C /opt/jdtls && \
    rm /opt/jdtls/jdtls.tar.gz

WORKDIR /opt
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

# fzf from upstream, not apt: fzf-lua aborts below 0.36 and recommends >= 0.53,
# while jammy pins 0.29.0 and bookworm 0.38.0. See
# context/dev-ide-nvim-toolchain.md §3.1.
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

# Update PATH to include the generic Neovim bin location
ENV PATH="$PATH:/opt/nvim/bin"
RUN echo 'export PATH="$PATH:/opt/nvim/bin"' >> /root/.bashrc

RUN mkdir -p /root/.config/nvim /root/.config/nvim/lua/plugins/ /root/.config/nvim/ftplugin/
COPY init.lua /root/.config/nvim/init.lua
COPY core.lua /root/.config/nvim/lua/plugins/core.lua
COPY ai.lua /root/.config/nvim/lua/plugins/ai.lua
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

RUN curl -LsSf https://astral.sh/ruff/install.sh | sh
ENV PATH="$PATH:/root/.local/bin"

RUN nvim --headless "+Lazy! sync" +qa

# Use a more appropriate entrypoint
WORKDIR /ws
CMD ["/bin/bash"]
