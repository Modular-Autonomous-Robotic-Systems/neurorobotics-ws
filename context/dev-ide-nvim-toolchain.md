# Neovim IDE toolchain across `docker/base`, `docker/dev` and `docker/airsim`

Durable record of the Neovim development environment that is built into three separate Docker images, of the external binaries its plugins depend on, and of the version and parity defects found in that setup on 2026-08-12. Companion file to [dev-ide-ai-clis.md](dev-ide-ai-clis.md), which covers the agentic CLIs configured inside the same editor. Until 2026-08-16 the editor was built into two images; `docker/airsim/Dockerfile` gained it that date, per [../plans/antigravity-cli-integration.md](../plans/antigravity-cli-integration.md), so that the Project AirSim/Unreal image can be edited in-place with the same tooling.

## 1. Why the same editor is built three times

Two unrelated image lineages each install the identical Neovim configuration.

`docker/dev/Dockerfile` builds `nrt:dev` on `node:22-slim`, which is Debian 12 bookworm. This is the dedicated IDE image, spawned as `dev_container` by `docker/scripts/start_ide.sh` and carrying none of the ROS or simulation runtime.

`docker/base/Dockerfile` builds `nrt:base` on `ubuntu:22.04` jammy, and is the root of the runtime chain, base then ros then pangolin then camera then ardupilot, which terminates in `nrt:$VERSION`. Every runtime container therefore inherits this editor, so the same configuration is what an operator gets when opening `nvim` inside `nrt_container` or `sitl_bridge_container`.


The seven Lua configuration files are authored once under `docker/dev/` and all three images receive byte-identical copies. `docker/dev/Dockerfile` copies them from its own build context. For `docker/base` `setup_nvim_config_for_image_build` at `scripts/helpers/docker.sh:50-53` copies `docker/dev/*.lua` into the target Dockerfile's own directory immediately before the build and `cleanup_nvim_config_after_image_build` removes them after, called for `docker/base` from `djinn`'s own `nrt` branch  which is the Dockerfile can `COPY` files that are not committed at that path. The consequence to remember is that editing `docker/dev/ai.lua` changes all images, and that no `.lua` file should ever be committed under `docker/base/` or `docker/airsim/`.

Because the configuration is shared but the base distributions are not, every external binary the plugins invoke is resolved from a different package archive in each image. That asymmetry is the source of the defects in §3, and `docker/airsim/Dockerfile` was written from the start to include the `docker/base` remedies (`fd` symlink, `locale-gen`, upstream `fzf`) rather than reproducing them as defects to fix later.

## 2. What the plugins require from the system

Plugins are managed by `lazy.nvim`. The set installed at the time of writing is `agentic.nvim`, `bufferline.nvim`, `cmp-buffer`, `cmp_luasnip`, `cmp-nvim-lsp`, `cmp-path`, `Comment.nvim`, `conform.nvim`, `fzf-lua`, `gitsigns.nvim`, `gruvbox-material`, `lspkind.nvim`, `lualine.nvim`, `LuaSnip`, `markdown-preview.nvim`, `markview.nvim`, `mason.nvim` with `mason-lspconfig.nvim` and `mason-tool-installer.nvim`, `nabla.nvim`, `nvim-cmp`, `nvim-lint`, `nvim-lspconfig`, `nvim-osc52`, `nvim-tree.lua`, `nvim-treesitter`, `nvim-web-devicons` and `render-markdown.nvim`.

Three of these reach outside the editor for a binary.

`fzf-lua`, configured at `docker/dev/core.lua:54-78`, drives the `fzf` binary and is bound to `<leader>ff` for files, `<leader>fg` for live grep and `<leader>fs` for LSP document symbols. Its grep path shells out to `rg`. It enforces a hard minimum `fzf` version, discussed in §3.1.

`agentic.nvim`, configured in `docker/dev/ai.lua`, spawns an agentic CLI as an ACP subprocess and uses `fd` for its file picker. The comment at `docker/dev/Dockerfile:30-33` records why the symlink there exists.

`render-markdown.nvim`, at `docker/dev/ai.lua:128-151`, renders LaTeX through `latex2text`, which arrives from the `python3-pylatexenc` package present in both images.

## 3. Defects found 2026-08-12

All four were found while investigating a report that `docker/base` installs the wrong `fzf`. Each is a divergence between the two images in a component the shared Lua configuration assumes is uniform. None had been noticed earlier because `nvim --headless "+Lazy! sync" +qa`, the build-time step at `docker/base/Dockerfile:164` and `docker/dev/Dockerfile:114`, only downloads plugins and never executes a plugin's `config` function, so every one of these failures is deferred to runtime.

### 3.1 `fzf-lua` is inoperative in the entire runtime chain

`fzf-lua` aborts outright below `fzf` 0.36. The gate is at `lua/fzf-lua/config.lua:275-279` of the installed plugin.

```lua
elseif not utils.has(opts, "fzf", { 0, 36 }) then
  utils.error("fzf version %s is lower than minimum (0.36), aborting.",
    utils.ver2str(opts.__FZF_VERSION))
  return nil
end
```

The versions the two archives supply, both confirmed against the distribution publishers rather than recalled, are as follows. Ubuntu 22.04 jammy publishes `fzf` 0.29.0-1ubuntu0.1, established through the Launchpad API. Debian 12 bookworm publishes 0.38.0-1, established through `sources.debian.org`, and the running container reports `0.38.0 (debian)`.

Ubuntu jammy is therefore seven minor versions below the floor, so `fzf-lua` aborts in `nrt:base` and in every image descended from it, which means all three of `<leader>ff`, `<leader>fg` and `<leader>fs` fail with the message above in `nrt_container` and `sitl_bridge_container`. In `nrt:dev` the plugin functions, because 0.38.0 clears the floor, but it remains below the level the plugin's own health check advises, since `lua/fzf-lua/_health.lua:82-88` warns whenever the detected version is below 0.53.

The archives cannot resolve this, because the newest `fzf` either distribution offers to these releases is fixed at those numbers. Upstream ships static release binaries whose tarball contains exactly one file named `fzf`, verified by downloading `fzf-0.74.2-linux_amd64.tar.gz` and extracting it, and the current release at the time of writing is v0.74.2 of 2026-08-01 with `linux_amd64` and `linux_arm64` assets. The remedy, installing that binary in both images and dropping `fzf` from both apt lists, was applied 2026-08-14 per [../plans/antigravity-cli-integration.md](../plans/antigravity-cli-integration.md) §3.11, which additionally clears the 0.53 advisory in the dev image. Until 2026-08-14 this paragraph said the change was specified but not yet applied; both Dockerfiles now install `fzf` 0.74.2 from the upstream release binary immediately after their Neovim install block, using the same `TARGETARCH` architecture branch, since fzf's own release asset naming already matches Docker's `amd64`/`arm64` convention and needs no translation. (Until 2026-08-16 this branch read `uname -m`/`x86_64`/`aarch64`; replaced across every Dockerfile in `docker/` for consistency with the `ARG TARGETARCH` mechanism the `ros-humble-desktop-full` and Claude Code/`agy` gates already used, see [ros-deps-workspace.md](ros-deps-workspace.md).)

### 3.2 `docker/base` has no `fd` binary

Both distributions package the tool as `fd-find` and both install its binary as `/usr/bin/fdfind`, never as `fd`, because the name `fd` is taken by an unrelated package. This was confirmed for Debian by `dpkg -L fd-find` in the running container and for Ubuntu jammy through the package file list published at `packages.ubuntu.com`.

`docker/dev/Dockerfile:33` compensates.

```dockerfile
RUN ln -s /usr/bin/fdfind /usr/bin/fd
```

`docker/base/Dockerfile` now creates the same symlink immediately after its apt block, so `fd` resolves throughout the runtime chain and `agentic.nvim`'s file picker finds it. Until 2026-08-14 this paragraph said `docker/base/Dockerfile` installed `fd-find` at line 45 but never created the symlink, so no `fd` existed anywhere in the runtime chain; that gap is closed per [../plans/antigravity-cli-integration.md](../plans/antigravity-cli-integration.md) §3.12. The versions also differ, Ubuntu jammy carrying `fd-find` 8.3.1-1ubuntu0.1 against the 8.6.0 the dev container reports, which remains true and is not itself a functional defect.

### 3.3 `docker/base` declares a locale it never generates

Both images set the same three environment variables, at `docker/base/Dockerfile:16-18` and `docker/dev/Dockerfile:45-47`.

```dockerfile
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LANGUAGE en_US:en
```

Only the dev image then generates that locale, at `docker/dev/Dockerfile:41-42`, whose own comment calls the step essential and warns that Neovim will otherwise struggle with special characters.

```dockerfile
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen
```

`docker/base/Dockerfile` now runs the identical `sed`/`locale-gen` pair immediately after its apt block, so the declared locale exists in both images. Until 2026-08-14 this paragraph said `docker/base/Dockerfile` installed the `locales` package at line 71 but never ran `locale-gen`, leaving the C fallback in effect; that gap is closed per [../plans/antigravity-cli-integration.md](../plans/antigravity-cli-integration.md) §3.12. This matters to this configuration specifically, because `docker/dev/core.lua:65` sets `fzf-lua` window borders to the box-drawing characters `╭─╮│╯╰` and `docker/dev/ai.lua` renders Markdown and LaTeX, all of which depend on a UTF-8 locale.

### 3.4 `docker/base` omitted three packages the dev image installs

`procps`, `ncurses-term` and `ncurses-base` are now in `docker/base/Dockerfile`'s apt list alongside `docker/dev/Dockerfile:12` and `22-23`. Until 2026-08-14 this paragraph said the three were present only in the dev image and absent from the base list; that gap is closed per [../plans/antigravity-cli-integration.md](../plans/antigravity-cli-integration.md) §3.12. The `ncurses` pair supplies the terminfo database for the `TERM=xterm-256color` that both images set, and `procps` supplies `ps`. These were the mildest of the four, since the Ubuntu base image already provided much of this, and were closed for completeness rather than in response to a confirmed functional break.

## 4. Parity matrix

State as of 2026-08-16. `docker/base` and `docker/dev` reached parity 2026-08-14 per [../plans/antigravity-cli-integration.md](../plans/antigravity-cli-integration.md) §3.11 and §3.12; until that date this table reflected the state of 2026-08-12, before any remedy was applied, with `fzf`, `fd`, locale and the three packages all marked as defects in `docker/base`. `docker/airsim` is new to this table 2026-08-16, authored directly against the already-fixed versions rather than reproducing the defects first.

| Component | `docker/base` (ubuntu 22.04) | `docker/dev` (node:22-slim, bookworm) | `docker/airsim` (ubuntu 22.04, `USER ue4`) | Status |
|---|---|---|---|---|
| Neovim | v0.11.0, upstream tarball, same `TARGETARCH` branch | v0.11.0, upstream tarball | v0.11.0, upstream tarball, same `TARGETARCH` branch | parity |
| Lua config, seven files | staged from `docker/dev/*.lua` by helper | copied from own context | staged from `docker/dev/*.lua` by helper, `COPY --chown=ue4:ue4` into `/home/ue4/.config/nvim` | parity by construction |
| Node | 22 via NodeSource `setup_22.x` | 22 from the base image | 22 via NodeSource `setup_22.x` | parity |
| `fzf` | upstream release binary 0.74.2, `/usr/local/bin` | upstream release binary 0.74.2, `/usr/local/bin` | upstream release binary 0.74.2, `/usr/local/bin` | parity, fixed §3.1 |
| `fd` | `fd-find` 8.3.1 installed, `fd` symlink | `fd-find` 8.6.0 plus symlink | `fd-find` installed, `fd` symlink | parity, fixed §3.2 |
| `ripgrep` | 13.0.0 | 13.0.0 | apt jammy version | parity |
| locale | declared and generated | declared and generated | declared and generated | parity, fixed §3.3 |
| `procps`, `ncurses-term`, `ncurses-base` | present | present | present | parity, fixed §3.4 |
| `python3-pylatexenc` | present | present | present | parity |
| `xclip`, `openjdk-17-jdk`, JDTLS | present | present | present | parity |
| Nerd font plus `fc-cache` | present | present | present | parity |
| `ruff` via astral installer | present, as root | present, as root | present, as `ue4` (`$HOME/.local/bin` is `/home/ue4/.local/bin`) | parity |
| Global npm tooling | `@agentclientprotocol/claude-agent-acp`, `agy-acp`, both `$TARGETARCH`-guarded on `amd64` | same, same guard | same packages, **no** `$TARGETARCH` guard, this build is never multi-platform | parity in packages, deliberately not in the guard, see [dev-ide-ai-clis.md](dev-ide-ai-clis.md) §1/§1.1 |

The base image additionally carries the ROS and build toolchain, `cmake`, `gcc-9`, `gdb`, the `python3-flake8` family, `libeigen3-dev`, the mesa and GLEW development packages and others, none of which the editor uses and none of which belong in the dev image.

## 5. Gotchas worth carrying forward

A plugin failure in this setup is invisible at image build time. `+Lazy! sync` resolves and downloads plugin repositories but does not run their `config` callbacks, and `fzf-lua` is further deferred by `cmd = "FzfLua"` at `docker/dev/core.lua:55`, so its version gate is not reached until a human presses `<leader>ff` in a running container. Any future check that a plugin actually works must run the plugin, and `:checkhealth` is the cheapest way to do so.

Distribution package versions are the wrong tool for anything with a fast release cadence and a hard minimum. Both `fzf` defects trace to accepting whatever the archive happened to pin. Neovim itself was already installed from an upstream release tarball in both images, with an architecture branch on `TARGETARCH`, and that same idiom is the one to copy when a tool needs a version the archive cannot supply.

When adding a package for the editor, add it to both Dockerfiles or to neither. The shared Lua configuration cannot tell the two images apart, so a package added only to `docker/dev` produces a defect that appears exclusively in the runtime chain, which is where it is least likely to be noticed.
