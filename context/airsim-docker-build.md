# Cosys-AirSim Docker Build

## Entry point / call chain

`djinn init docker airsim`
→ `build_airsim_docker_image` (helper in `scripts/helpers/`, sourced by `djinn`)
→ `sitl_ws/src/ue5/AirSim/docker/build_airsim_image.py`
→ `docker build -f Dockerfile_source` (or `Dockerfile_binary` without `--source`)

Key files:
- `djinn` (repo root) — dispatcher; `init docker airsim` branch calls `build_airsim_docker_image`.
- `sitl_ws/src/ue5/AirSim/docker/build_airsim_image.py` — thin wrapper around `docker build`.
  - Default base image: `ghcr.io/epicgames/unreal-engine:dev-slim-5.8.0`.
  - `--source` → `Dockerfile_source` (compiles AirSim from source); otherwise `Dockerfile_binary`.
- `sitl_ws/src/ue5/AirSim/docker/Dockerfile_source` — clones **upstream** `Cosys-Lab/Cosys-AirSim`
  and runs its `setup.sh` then `build.sh --ue-root $UE_ROOT`.
- `sitl_ws/src/ue5/AirSim` — git **submodule**, pinned at **Cosys-AirSim `v3.4.1`** (HEAD `a552dd6c`).

> **Important:** `Dockerfile_source` `git clone`s upstream Cosys-AirSim fresh inside the
> image. The **local** submodule copy of `build.sh` is NOT what runs in the container —
> only the Dockerfile is under our control. Fixes must be Dockerfile-side (change the base
> image, install packages, or patch the cloned tree post-clone), not edits to the local
> `build.sh`.

## Version compatibility (NOT the cause here — verify the actual invocation)

- Cosys-AirSim **v3.4.1 targets Unreal Engine 5.5** (LTS branch: 5.2.1).
- The `5.8.0` strings in `build_airsim_image.py` and the `Dockerfile_*` `ARG BASE_IMAGE`
  defaults are **dead defaults** — `build_airsim_docker_image` (`scripts/helpers/sitl.sh:10`)
  calls the script with an explicit `--base_image="ghcr.io/epicgames/unreal-engine:dev-5.5"`,
  which overrides them via `--build-arg BASE_IMAGE=`.
- So the build already runs on **UE 5.5** (its toolchain is `v23_clang-18.1.0-rockylinux8`,
  which matches the version string in the error). The `<atomic>` failure is **not** a version
  mismatch; a version bump would be a no-op. Always confirm the effective base image from
  `sitl.sh` before assuming the file defaults apply.

## Known failure: `fatal error: 'atomic' file not found`

### Symptom
During `build.sh --ue-root`, the rpclib compile fails:
```
external/rpclib/rpclib-2.3.1/include/rpc/dispatcher.h:6:10: fatal error: 'atomic' file not found
    6 | #include <atomic>
```
The C compiler ABI check passes first (glibc C headers found), then the first C++ TU fails.

### Root cause
`build.sh`'s `--ue-root` branch sets:
```
CMAKE_VARS="... -DCMAKE_CXX_FLAGS=--sysroot=$UE_TOOLCHAIN_DIR ..."
```
where `UE_TOOLCHAIN_DIR = $UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/v23_clang-18.1.0-rockylinux8/x86_64-unknown-linux-gnu`.

Forcing `--sysroot` at the toolchain root redirects clang's **C++ standard library** header
search to `<sysroot>/usr/include/c++/…`. UE 5.8's `v23_clang-18.1.0` toolchain does not keep
libc++ headers there, so `<atomic>` (a libc++ header) is unresolved. `<atomic>` is C++, not C,
which is why the C ABI check passed but the first C++ include fails. Classic AirSim `<atomic>`
issue (microsoft/AirSim#177): C++ stdlib not on the include path.

UE's clang does not find libc++ by default outside UBT (which is why UBT passes
`-nostdinc++ -isystem <engine libc++>` explicitly), and the forced `--sysroot` prevents it from
falling back to system headers — so no C++ stdlib is on the include path.

### Fix — STATUS: RESOLVED & VERIFIED (2026-07-23), in `docker/Dockerfile_source`
Image `shandilya1998/nrt_airsim:0.0.1` builds green on base `ghcr.io/epicgames/unreal-engine:dev-5.5`.
The fix took THREE stacked changes — each earlier attempt only exposed the next real blocker:

1. **`apt-get install … clang lld llvm-dev libc++-dev libc++abi-dev`** (as root). The base image
   ships none of clang/llvm/libc++ (it uses only UE's bundled toolchain), so all are needed.
2. **Build with system clang + libc++, and UNSET `UE_ROOT`** for the build command:
   `env -u UE_ROOT CXXFLAGS="-stdlib=libc++" LDFLAGS="-stdlib=libc++" ./build.sh`
   - CRITICAL non-obvious bit: `build.sh` does `ue_root="${UE_ROOT:-}"`, so it takes the
     UE-toolchain path from the **`UE_ROOT` env var** alone — removing the `--ue-root` *flag* is
     NOT enough. The Dockerfile sets `ENV UE_ROOT=…`, so you MUST `env -u UE_ROOT` to force the
     system-clang branch. There build.sh sets `CC=clang`/`CXX=clang++` and does not pass
     `-DCMAKE_CXX_FLAGS`, so CMake picks up `CXXFLAGS` → `-stdlib=libc++`. `libc++-dev` provides
     `<atomic>`.
3. **`llvm-dev`** — in the system-clang branch `CommonSetup.cmake:71` does
   `find_package(LLVM REQUIRED CONFIG)` and links libc++ via `-L${LLVM_LIBRARY_DIRS}`; that needs
   `LLVMConfig.cmake`, shipped by `llvm-dev`. (The UE-toolchain branch skips this entirely.)

Also set the `ARG BASE_IMAGE` default to `dev-5.5` to match the real invocation (cosmetic; still
overridden by `sitl.sh`'s `--build-arg`).

**Root-cause recap (why the UE path failed on `<atomic>`):** the UE 5.5 toolchain
(`v23_clang-18.1.0-rockylinux8`) ships only **libstdc++** headers at `include/c++/13.2.0`, which
clang does NOT auto-detect under a bare `--sysroot`, so `<atomic>` was unresolved. UE's own libc++
(`Engine/Source/ThirdParty/Unix/LibCxx/include/c++/v1`) is normally injected by UBT, not by this
standalone build.

**Why libc++ (not libstdc++/gcc):** UE 5.5 uses libc++ on Linux; AirLib static libs are later
linked into the UE plugin by UBT, so they must be libc++ to avoid a C++ std ABI mismatch. The
`CommonSetup.cmake` else-branch is the upstream-blessed "system clang + LLVM libc++" path.

**Why unsetting `UE_ROOT` is safe here:** the UE path exists to avoid a `__isoc23_strtol`
glibc-version skew when building on a newer-glibc *host* (Ubuntu 24.04+, glibc ≥2.38). Inside this
container (Ubuntu 22.04, glibc 2.35) no isoc23 symbols are emitted.

### Verification quick-check (fast, no full ~10-min build)
`docker run --rm --entrypoint bash <base> -lc 'sudo apt-get install -y clang libc++-dev &&
printf "#include <atomic>\nint main(){return 0;}" > /tmp/t.cpp && clang++ -stdlib=libc++ -c /tmp/t.cpp'`

### Fallback / ABI-purist option (only if a downstream UE-plugin ABI mismatch ever appears)
Use UE's *own* libc++ instead of the system one: keep UE's clang but add the engine's bundled
libc++ include/lib (patch the cloned `build.sh` in the Dockerfile):
- include: `$UE_ROOT/Engine/Source/ThirdParty/Unix/LibCxx/include/c++/v1` (verified present)
- lib: `$UE_ROOT/Engine/Source/ThirdParty/Unix/LibCxx/lib/Unix/x86_64-unknown-linux-gnu`
Note build.sh's `make` only builds static `.a` libs (no linking), so headers alone get it to
compile; ABI matters only at the later UBT link step.

## References
- Cosys-AirSim README (UE 5.5 target): https://github.com/Cosys-Lab/Cosys-AirSim/blob/main/README.md
- `<atomic>` failure: https://github.com/Microsoft/AirSim/issues/177
