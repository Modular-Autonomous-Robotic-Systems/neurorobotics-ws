# Update the host NVIDIA driver for Unreal Engine 5.7 Vulkan support

**Status.** Executed and confirmed working, in combination with a second, companion fix this plan's own validation surfaced the need for. The driver upgrade below is a host system package change, not a code or Dockerfile change, and remains necessary, but it turned out not to be sufficient by itself: the packaged client continued failing identically after the upgrade alone, because a second, independent defect in `docker/unreal/Dockerfile`'s Vulkan ICD manifest generation was masking the fix throughout. That second defect and its own fix, "NRT delta 7", are recorded in full in `plans/unreal-engine-packaging.md` §7.5 and `context/project-airsim-docker-build.md` §17, and are not duplicated here; §4 below records only that they exist and were both required.

## 1. Motivation

The 5.2 to 5.7 Unreal Engine pin migration, recorded in [unreal-engine-packaging.md](unreal-engine-packaging.md), reached the point where Project AirSim's `StonePineForest` client builds and packages cleanly against the 5.7 engine and launches inside `airsim2_container`. The launch itself then fails, not during build, not during asset mounting, but during Vulkan RHI initialization, with every plugin and pak file already mounted correctly:

```
LogVulkanRHI: Starting Vulkan Profile check for VP_UE_Vulkan_SM6:
LogVulkanRHI: Warning: None of the 1 devices meet all the criteria!
LogVulkanRHI: Vulkan Profile check complete.
LogRHI: Display: Skipping SF_VULKAN_SM6...
Message dialog closed, result: Ok, title: Message, text: Vulkan device could not be created at the project's supported feature levels (see log for details).
LogCore: FUnixPlatformMisc::RequestExit(bForce=true, ReturnCode=1, CallSite=<NoCallSiteInfo>)
```

The host GPU is an NVIDIA RTX 4000 SFF Ada Generation, PCI device ID `0x27b0`, on driver `550.163.01`, passed through into `airsim2_container` with `NVIDIA_VISIBLE_DEVICES=all` and `NVIDIA_DRIVER_CAPABILITIES=graphics,compute,utility,display` per `docker/airsim/Dockerfile:72-73`.

### 1.1 Why the failure is a driver gap, not a container or code defect

`Engine/Source/Runtime/VulkanRHI/Private/VulkanRHI.cpp`, read directly from `EpicGames/UnrealEngine` branch `5.7` at this workspace's pinned commit, shows that `LaunchEngineLoop` validates the GPU against a formal, versioned specification, the Vulkan Profiles library's `VP_UE_Vulkan_SM6` profile (`Engine/Source/ThirdParty/Vulkan/profiles/include/vulkan_profiles_ue.h`), before it will create a device at all. That profile's `deviceExtensions` array names fifteen required Vulkan extensions: `VK_EXT_calibrated_timestamps`, `VK_EXT_descriptor_buffer`, `VK_EXT_descriptor_indexing`, `VK_EXT_mesh_shader`, `VK_EXT_mutable_descriptor_type`, `VK_EXT_scalar_block_layout`, `VK_EXT_shader_image_atomic_int64`, `VK_KHR_buffer_device_address`, `VK_KHR_compute_shader_derivatives`, `VK_KHR_maintenance4`, `VK_KHR_pipeline_library`, `VK_KHR_separate_depth_stencil_layouts`, `VK_KHR_shader_atomic_int64`, `VK_KHR_synchronization2`, `VK_KHR_timeline_semaphore`.

The first diagnostic hypothesis, that the NVIDIA ICD was not being reached at all and the game was silently falling back to Mesa's `llvmpipe` software rasterizer, was checked and ruled out. `vulkaninfo --summary` run inside `airsim2_container` lists two devices, GPU0 the NVIDIA card correctly typed `PHYSICAL_DEVICE_TYPE_DISCRETE_GPU` with `apiVersion = 1.3.277`, and GPU1 `llvmpipe`, correctly typed `PHYSICAL_DEVICE_TYPE_CPU`. The ICD, the driver, and the NVIDIA Container Toolkit passthrough are all demonstrably functional in that same container. Why the game's own Vulkan Profiles-scoped temporary instance reports only `1` device where a plain `vulkaninfo` instance reports `2` was not resolved to an exact mechanism, and is immaterial to the conclusion below, since the conclusion holds regardless of which device the game's check actually reached.

A full, non-summary `vulkaninfo` was then run to get GPU0's complete 219-entry device extension list, and checked term by term against the profile's fifteen requirements. Fourteen are present. The fifteenth, `VK_KHR_compute_shader_derivatives`, is absent, and the list instead carries `VK_NV_compute_shader_derivatives`, the older, vendor-specific extension that predates it. A web search corroborated the timeline rather than leaving it to inference, `VK_KHR_compute_shader_derivatives` was only ratified into the Vulkan specification at version 1.3.295, which postdates driver `550.163.01`'s own release, so the driver cannot expose an extension name that did not exist yet when it shipped. Every other criterion, all fourteen remaining extensions plus every required feature and property struct the profile checks, is satisfied by this GPU. The gap is exactly one extension wide, and it is a driver-age gap on the host, not a workspace, container, or CMake defect.

`-SkipVulkanProfileCheck`, a genuine Epic-provided command line flag (`Engine/Source/Runtime/VulkanRHI/Private/VulkanGenericPlatform.cpp`) that bypasses `CheckVulkanProfile()` entirely, was considered and rejected as a fix. The gap is a real, confirmed missing capability rather than a false-negative check, so skipping it would only defer the same shortfall to whichever render pass first dispatches a compute shader using derivatives, a less diagnosable failure than the one already in hand.

The full investigation, including the exact source citations and the complete extension diff, is recorded in [context/project-airsim-docker-build.md](../context/project-airsim-docker-build.md) §16.

### 1.2 Why the fix is a host driver upgrade rather than a workspace change

The Vulkan device the container sees is the host's own GPU, mediated by the NVIDIA Container Toolkit, which mounts the host kernel driver's userspace libraries into the container at start time. There is no version of `docker/unreal/Dockerfile`, `docker/airsim/Dockerfile`, or Project AirSim's own CMake configuration that can add a Vulkan extension a driver does not implement. The only fix is to install a newer NVIDIA driver branch on the host and restart the containers that use the GPU so they remount the new driver's libraries.

NVIDIA's `open-gpu-kernel-modules` repository lists device ID `27b0`, the exact ID this GPU reports, as supported, and NVIDIA's own materials confirm the 580 production branch supports the Ada Lovelace architecture this card belongs to. 580 is the target branch.

## 2. The procedure

This section is written to be run directly on the host, `server1` in the logs above, not inside any development or SITL container. Nothing here can be executed from this workspace's own tooling, since the dev container has no access to the host's package manager or kernel.

### 2.1 Before you begin

Check secure boot first, since this is the one thing that can strand a remote or headless server:

```bash
mokutil --sb-state
```

If it reports secure boot enabled, the driver install will prompt for an enrollment password, and completing that enrollment requires console access at the next boot, a one-time MOK-management screen that appears before Ubuntu itself starts. SSH will not reach it. Confirm IPMI, iDRAC, or physical console access as a fallback before proceeding if secure boot is enabled, or disable it in BIOS first if that is viable.

This change affects the whole host, not only `airsim2_container`. Every container that has the GPU passed through, not just Project AirSim's, will need to restart afterward to pick up the new driver's userspace libraries, since a running process keeps the old libraries mapped until it restarts and a kernel module swap underneath a still-running process is not something to rely on. A host reboot, which this procedure already requires, handles this for every container at once.

### 2.2 Steps

```bash
# 1. Check secure boot status, read the note above before proceeding if enabled
mokutil --sb-state

# 2. Record what's currently installed, for reference/rollback
apt list --installed 2>/dev/null | grep nvidia
>>> libnvidia-cfg1-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-common-550/jammy-updates,jammy-updates,jammy-security,jammy-security,now 550.163.01-0ubuntu0.22.04.2 all [installed,automatic]
    libnvidia-common-580/jammy-security,jammy-security,now 580.95.05-0ubuntu0.22.04.1 all [installed,upgradable to: 580.173.02-0ubuntu0.22.04.1]
    libnvidia-compute-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-compute-550/now 550.163.01-0ubuntu0.22.04.1 i386 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-container-tools/unknown,now 1.17.8-1 amd64 [installed,upgradable to: 1.20.0-1]
    libnvidia-container1/unknown,now 1.17.8-1 amd64 [installed,upgradable to: 1.20.0-1]
    libnvidia-decode-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-decode-550/now 550.163.01-0ubuntu0.22.04.1 i386 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-egl-wayland1/jammy-updates,now 1:1.1.9-1.1ubuntu0.1 amd64 [installed,automatic]
    libnvidia-egl-wayland1/jammy-updates,now 1:1.1.9-1.1ubuntu0.1 i386 [installed,automatic]
    libnvidia-encode-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-encode-550/now 550.163.01-0ubuntu0.22.04.1 i386 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-extra-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-fbc1-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-fbc1-550/now 550.163.01-0ubuntu0.22.04.1 i386 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-gl-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    libnvidia-gl-550/now 550.163.01-0ubuntu0.22.04.1 i386 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    nvidia-compute-utils-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    nvidia-container-toolkit-base/unknown,now 1.17.8-1 amd64 [installed,upgradable to: 1.20.0-1]
    nvidia-container-toolkit/unknown,now 1.17.8-1 amd64 [installed,upgradable to: 1.20.0-1]
    nvidia-dkms-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    nvidia-driver-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    nvidia-firmware-550-550.163.01/jammy-updates,now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,automatic]
    nvidia-firmware-575-575.64.03/jammy-updates,now 575.64.03-0ubuntu0.22.04.1 amd64 [installed,auto-removable]
    nvidia-firmware-580-580.65.06/jammy-updates,jammy-security,now 580.65.06-0ubuntu0.22.04.4 amd64 [installed,auto-removable]
    nvidia-kernel-common-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    nvidia-kernel-source-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    nvidia-prime/jammy,jammy,now 0.8.17.1 all [installed,automatic]
    nvidia-settings/jammy,now 510.47.03-0ubuntu1 amd64 [installed,upgradable to: 510.47.03-0ubuntu1.22.04.1]
    nvidia-utils-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]
    xserver-xorg-video-nvidia-550/now 550.163.01-0ubuntu0.22.04.1 amd64 [installed,upgradable to: 550.163.01-0ubuntu0.22.04.2]

nvidia-smi --query-gpu=driver_version --format=csv
>>> driver_version
    550.163.01


# 3. Refresh package lists and see what Ubuntu recommends
sudo apt update
ubuntu-drivers devices
>>> == /sys/devices/pci0000:00/0000:00:01.1/0000:01:00.0 ==
    modalias : pci:v000010DEd000027B0sv000010DEsd000016FAbc03sc00i00
    vendor   : NVIDIA Corporation
    manual_install: True
    driver   : nvidia-driver-545-open - distro non-free
    driver   : nvidia-driver-580-server-open - distro non-free
    driver   : nvidia-driver-580 - distro non-free
    driver   : nvidia-driver-580-server - distro non-free
    driver   : nvidia-driver-595-server - distro non-free
    driver   : nvidia-driver-595-open - distro non-free
    driver   : nvidia-driver-610-open - distro non-free
    driver   : nvidia-driver-595-server-open - distro non-free
    driver   : nvidia-driver-545 - distro non-free
    driver   : nvidia-driver-610 - distro non-free
    driver   : nvidia-driver-595 - distro non-free recommended
    driver   : nvidia-driver-580-open - distro non-free
    driver   : xserver-xorg-video-nouveau - distro free builtin


# 4. Install the 580 branch (desktop/workstation driver, not "-server" —
#    RenderOffScreen still creates a real Vulkan device and renders, it just
#    has no physical display attached, so the full graphics driver is needed)
sudo apt install nvidia-driver-580

# If apt can't find that package (Ubuntu 22.04's repos haven't picked it up
# on your mirror yet), add the trusted graphics-drivers PPA and retry:
#   sudo add-apt-repository ppa:graphics-drivers/ppa
#   sudo apt update
#   sudo apt install nvidia-driver-580

# 5. Reboot, required for the new kernel module to load
sudo reboot
```

After reboot, completing MOK enrollment first if secure boot prompted for it:

```bash
# 6. Verify the new driver loaded
nvidia-smi

# 7. Restart the containers so NVIDIA Container Toolkit remounts the new
#    driver's userspace libraries, it caches them at container start
docker restart airsim2_container

# 8. Confirm the extension gap is closed
docker exec -it airsim2_container vulkaninfo --summary
# check GPU0's extension list for VK_KHR_compute_shader_derivatives

# 9. Retry the actual game launch
djinn start sitl2
```

### 2.3 If something goes wrong

If the driver fails to load after reboot, `nvidia-smi` erroring or the card not appearing, `sudo ubuntu-drivers autoinstall` falls back to whatever Ubuntu currently considers the recommended driver for the hardware. To return to the exact known-working prior state, reinstall the recorded version explicitly, `sudo apt install nvidia-driver-550`, then reboot again.

## 3. Backwards compatibility

This procedure itself changes no workspace file, it is a host system package upgrade. `docker/airsim/Dockerfile`'s `NVIDIA_VISIBLE_DEVICES`/`NVIDIA_DRIVER_CAPABILITIES` declarations and every `djinn` workflow are unaffected, since none of them pin a driver version, they all read whatever driver the host and the NVIDIA Container Toolkit present at container start. `docker/unreal/Dockerfile`'s `nvidia_icd.json` generation did have to change, but as a separate, companion fix this plan's own validation surfaced the need for, not as a consequence of the driver upgrade itself; that change, "NRT delta 7", is recorded in `plans/unreal-engine-packaging.md` §7.5, not here. The only caller-visible effect of the driver upgrade proper is that every container using the GPU must be restarted once, which the reboot in step 2.2 already forces for all of them together, so no container is left running against a mismatched driver.

## 4. Validation

- `nvidia-smi` on the host reports a `580.x` driver version. Confirmed, `580.173.02`.
- A full, non-summary `vulkaninfo` inside `airsim2_container` lists `VK_KHR_compute_shader_derivatives` in GPU0's device extension list, where it was previously absent. Confirmed.
- `djinn start sitl2` proceeds past `LogVulkanRHI: Vulkan Profile check complete.` with no `None of the %u devices meet all the criteria!` warning, and the packaged `StonePineForest` client reaches simulation rather than exiting with `ReturnCode=1` at RHI initialization. This did **not** hold on the driver upgrade alone, the identical warning persisted, because `docker/unreal/Dockerfile`'s `nvidia_icd.json` generation was independently, silently excluding the NVIDIA device from every enumeration the packaged client ever ran, regardless of the real device's own capability. Confirmed only once that second defect was also fixed (`plans/unreal-engine-packaging.md` §7.5, "NRT delta 7"), both fixes together.

`context/project-airsim-docker-build.md` §16's own Verification line has been updated to record exactly this, confirmed but not sufficient by itself, with the full second-defect account in that file's own §17.

## 5. Deliberately not done

No exact minimum 580-branch point version is pinned in this plan. NVIDIA's own release notes were searched without turning up the specific point release that first added the KHR-named extension, so the procedure installs whatever `nvidia-driver-580` resolves to via `apt`/`ubuntu-drivers` at the time it is run, rather than a version this plan would freeze and eventually go stale against.

A separate, unrelated Linux Vulkan regression in UE 5.7, `VK_ERROR_DEVICE_LOST` inside `Engine/Source/Runtime/VulkanRHI/Private/VulkanPipeline.cpp`, is reported across drivers `570` through `610` on the Epic forums. It was not treated as a reason to avoid the 580 branch, since every reported trigger is an interactive editor event, material recompilation, window resize, level unload, PCG graph debugging, none of which a headless, unattended packaged client launched with `-RenderOffScreen -unattended` exercises. It is recorded here as a residual risk to watch for rather than something this plan attempts to pre-empt, since no fix for it has shipped from Epic as of the writing of this plan.
