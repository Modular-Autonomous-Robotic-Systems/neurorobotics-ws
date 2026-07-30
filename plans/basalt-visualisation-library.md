# `basalt_visualisation`: a reusable Pangolin-exporting target, and the `use-visualisation` launch path

**Implemented 2026-07-28.** Container-side validation outstanding, catalogued in §7.

## 1. Motivation

Integrating Basalt's real-time visualiser into the ROS 2 wrapper broke the `slam` package's build with roughly two hundred errors of the form `'glGenBuffers' was not declared in this scope`, raised from inside `/usr/local/include/pangolin/gl/gl.hpp` and `glsl.h`. The same work also left the visualiser unreachable from a launch file, since the node parameter that gates it had no launch argument behind it.

The error signature is the diagnosis. Every undeclared name is an OpenGL 1.5 or later entry point, `glGenBuffers`, `glUseProgram`, `glBindFramebufferEXT`, `glCopyImageSubDataNV`. Every name the compiler resolved and offered as a spelling correction is OpenGL 1.1, `glDrawBuffer`, `glReadBuffer`, `glSelectBuffer`. Mesa's `<GL/gl.h>` declares exactly the 1.1 set, so the translation unit had reached Pangolin's headers with no GLEW. `ext/basalt/thirdparty/Pangolin/include/pangolin/gl/glplatform.h:58` includes `<GL/glew.h>` unconditionally, so every consumer of a Pangolin header must be handed GLEW's include directory.

Two facts about the vendored tree explain why nothing handed it over.

- `basalt` is deliberately Pangolin-free. `add_library(basalt SHARED)` at `ext/basalt/CMakeLists.txt:306` compiles neither `src/visualisation/visualiser.cpp` nor `src/visualisation/utils.cpp`, and its `target_link_libraries` does not name `pangolin`. The intent is stated in the header comment of `include/basalt/visualisation/visualiser.h:20-24`. The two sources were instead listed directly in `basalt_slam`'s `add_executable`.
- `basalt_slam_node` linked only `basalt`, so it inherited no Pangolin include directory and no GLEW include directory. `pangolin/pangolin.h` resolved anyway, but only via an unrelated Pangolin installed under `/usr/local/include`, a default system search path. The package was compiling against a stale system Pangolin rather than the vendored one.

Investigating the runtime path for the same feature surfaced two further defects, both described in §4.

## 2. High-level design

The insight is that the Pangolin dependency is not a property of any one executable, it is a property of `basalt::SlamVisualiser`. Expressing it as a target rather than as a per-consumer source list makes it inheritable.

One static library, `basalt_visualisation`, owns the two visualiser translation units and re-exports Pangolin with a `PUBLIC` link. Anything that includes `basalt/visualisation/visualiser.h` links that single name and inherits the objects, the Pangolin include tree, its generated `config.h` directory and GLEW, all together. The recipe stops being something each consumer must reproduce correctly, which removes the failure mode where a consumer copies half of it.

## 3. Build changes

### 3.1 The library

`ext/basalt/CMakeLists.txt`, inserted after the `basalt` target and before the executables so both consumers can reach it.

```cmake
add_library(basalt_visualisation STATIC
  ${CMAKE_CURRENT_SOURCE_DIR}/src/visualisation/visualiser.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/src/visualisation/utils.cpp
)
target_link_libraries(basalt_visualisation PUBLIC basalt pangolin)
```

The `PUBLIC pangolin` link is the whole mechanism. `ext/basalt/thirdparty/Pangolin/src/CMakeLists.txt:176` appends `${GLEW_INCLUDE_DIR}` to `USER_INC`, and `:635` exports it with `target_include_directories(${LIBRARY_NAME} SYSTEM PUBLIC ${USER_INC} …)`. Explicit `-I` and `-isystem` flags are searched before `/usr/local/include`, so the vendored Pangolin now wins over the system copy.

No `target_include_directories` call is needed on the new target. `PUBLIC basalt` already propagates `${CMAKE_CURRENT_SOURCE_DIR}/include` from `ext/basalt/CMakeLists.txt:406`.

**Why `STATIC`.** The two objects are small, every consumer compiled them directly before this target existed, so an archive reproduces the same object placement exactly; and no new shared object enters the install tree or the RPATH set, so no install rule is required. `CMAKE_POSITION_INDEPENDENT_CODE` is `ON` for the directory at `:100`, so the archive still links into shared consumers. `pangolin` is itself static here, because `ext/basalt/thirdparty/CMakeLists.txt:11` sets `BUILD_SHARED_LIBS OFF` for that scope. `SHARED` was rejected because it would have required an install rule, an RPATH that resolves from `install/slam/lib`, and a runtime failure mode that the static choice simply does not have.

**Backwards compatibility.** Additive. No existing target's flags change except the two consumers repointed below.

### 3.2 `basalt_slam`, the standalone consumer

```cmake
add_executable(basalt_slam src/basalt_slam.cpp)
target_link_libraries(basalt_slam basalt basalt_visualisation basalt::cli11)
```

The two visualiser sources leave its `add_executable` list and `pangolin` leaves its link line, arriving transitively instead.

**Backwards compatibility.** The same objects and the same libraries reach the same executable, by a different route. Compile flags are unchanged, since both the archive and the executable are built in `ext/basalt`'s directory scope. No other basalt executable is touched, and they all keep their direct `pangolin` link.

### 3.3 `basalt_slam_node`, the ROS consumer

`ros_ws/src/slam/CMakeLists.txt`. The source list returns to the package's own five files, and the link line becomes

```cmake
  target_link_libraries(basalt_slam_node
    PUBLIC basalt
    PUBLIC basalt_visualisation
    PUBLIC ${YAMLCPP_LIBRARY}
    PUBLIC yaml-cpp
  )
```

`basalt` is named explicitly even though `basalt_visualisation` links it publicly, because this node uses `basalt::Controller` directly and should not depend on the visualiser to supply it.

**An ABI consequence worth recording.** The visualiser translation units moved from the parent scope, which supplies no `-march`, into `ext/basalt`'s scope, where `:265` supplies `-march=${CXX_MARCH}`. This is safe only because `add_compile_definitions(EIGEN_MAX_ALIGN_BYTES=16 NRT_EIGEN_ABI_PIN=16)` at `CMakeLists.txt:183` precedes `add_subdirectory(ext/basalt)` and so reaches the new target. The pin, not the arch flag, keeps `SlamVisualiser`'s `Eigen::aligned_vector<Eigen::Vector3d>` members laid out identically on both sides of the boundary. Full derivation in `ros_ws/src/slam/context/SIMD.md` and `ros_ws/src/slam/context/build-and-abi.md`.

### 3.4 Deliberately not done

`ros_ws/src/slam/CMakeLists.txt:42` calls `find_package(Pangolin REQUIRED)` at top level. No `Pangolin_*` variable is read anywhere in that file, and the ORBSLAM3 branch does not need it either, because `orb_slam3/CMakeLists.txt:6` issues its own and consumes the variables in its own scope at `:50,:57`. The call is dead in both branches while still making a system Pangolin a hard configure-time requirement of the default BASALT build. Left in place because removing it touches the section shared with the ORBSLAM3 branch and no failure depends on it.

It does establish one useful fact. Had `find_package(Pangolin)` created an imported target named `pangolin`, the vendored `add_library(pangolin …)` reached through `add_subdirectory(ext/basalt)` would have failed configuration on the duplicate name. Configuration succeeds, so `pangolin` refers unambiguously to the vendored target and the link entries above cannot bind to the system copy.

## 4. Runtime defects found while verifying the feature

Both were found by reading the visualiser's lifecycle against the node's, and both would have prevented the feature from functioning even once it compiled.

### 4.1 The GL context was bound to the wrong thread

`SlamVisualiser::Start()` calls `pangolin::CreateWindowAndBind` at `ext/basalt/src/visualisation/visualiser.cpp:48`. A GL context is current on the thread that creates it. `ext/basalt`'s own consumer states the consequence and obeys it, calling both `Start()` and `Run()` from its main thread with the comment "The render loop owns the GL context and must run on this main thread" at `src/basalt_slam.cpp:232-239`.

`BasaltSLAM::InitialiseSlam` was calling `Start()` inline, on the ROS executor thread by way of `BasaltSLAMNode::on_activate`, and only `Run()` on `mpVisualiserThread`. Every GL call in the render loop therefore executed on a thread with no current context.

The fix moves the whole GL lifetime onto the visualiser thread and uses a `std::promise` to keep the startup ordering the caller relied upon.

```cpp
std::promise<void> startedPromise;
std::future<void> started = startedPromise.get_future();
mpVisualiserThread = std::thread(&BasaltSLAM::RunSlamVisualiser, this,
                                 std::move(startedPromise));
started.get();
```

```cpp
void BasaltSLAM::RunSlamVisualiser(std::promise<void> startedPromise) {
    try {
        mpSlamVisualiser->Start();
    } catch (...) {
        startedPromise.set_exception(std::current_exception());
        return;
    }
    startedPromise.set_value();
    mpSlamVisualiser->Run();
}
```

Blocking on the future is not merely tidy. `Start()` is also the step that connects the visualiser's queues to the VIO and local mapper output hooks at `visualiser.cpp:54-57`, so returning from `InitialiseSlam` before it completes would let `on_activate` create the image subscription while the taps did not yet exist.

`get()` is used rather than `wait()` so that a `Start()` failure, most commonly no reachable `DISPLAY`, is rethrown on the caller's thread exactly as it was when `Start()` ran inline. The `catch (...)` is what makes that possible: an exception escaping a thread body calls `std::terminate`, and a promise left unfulfilled would block the waiter forever.

**Backwards compatibility.** `RunSlamVisualiser` changes signature, from `void()` to `void(std::promise<void>)`. It is a public member of `BasaltSLAM` but has exactly one caller, the `std::thread` construction inside `InitialiseSlam`, confirmed by grep across `src/` and `include/`. The failure path is unchanged: a `Start()` throw still surfaces from `on_activate`.

### 4.2 `StopSlamVisualiser` dereferenced a null pointer on the default path

`mpSlamVisualiser` is created only when `useVisualisation` is true, and `use_visualisation` defaults to false. `BasaltSLAMNode::on_deactivate` calls `mpSlam->StopSlamVisualiser()` unconditionally at `src/basalt/node.cpp:144`, and that function dereferenced the pointer without a guard. Every deactivation in the default configuration would therefore have faulted.

```cpp
void BasaltSLAM::StopSlamVisualiser() {
    if (!mpSlamVisualiser) {
        return;
    }
    mpSlamVisualiser->Stop();
    if (mpVisualiserThread.joinable()) {
        mpVisualiserThread.join();
    }
}
```

The guard is placed in the callee rather than at the call site so that every caller benefits, including `~BasaltSLAM()`. `Stop()` is itself idempotent through `mpRunning.exchange(false)` at `visualiser.cpp:74`, and it sets the flag that breaks `Run()`'s loop at `:240-243`, so the join terminates rather than waiting for the user to close the window.

**Backwards compatibility.** Strictly widens the set of states in which the call is safe. No caller changes.

## 5. Launch changes

### 5.1 `ros_ws/src/slam/launch/basalt_slam.launch.py`

A `use-visualisation` argument, defaulting to `False` with `choices=["True","False"]`, matching the shape of the neighbouring `use-sim-time`. It is passed to the node as the `use_visualisation` parameter, wrapped in an explicit type:

```python
"use_visualisation": ParameterValue(use_visualisation, value_type=bool),
```

with `from launch_ros.parameter_descriptions import ParameterValue` at the top of the file. The wrapper is required rather than cosmetic. A `LaunchConfiguration` resolves to text, and the node declares the parameter with `declare_parameter<bool>` at `src/basalt/node.cpp:43`, which rejects a string override with `InvalidParameterTypeException`. The explicit module path is used in preference to an attribute on the `launch_ros` package so the import does not depend on what that package's `__init__` happens to re-export.

`use_sim_time` in the same file still passes a bare `LaunchConfiguration` for what is also a boolean parameter. That inconsistency is pre-existing, is not touched here, and is flagged in `context/basalt-visualiser-integration.md` as a candidate defect to check when that path is next exercised.

**Backwards compatibility.** The argument has a default, so every existing caller of this launch file continues to work unchanged and gets the previous behaviour, no visualiser.

### 5.2 `ros_ws/src/controllers/launch/basalt_slam_test.launch.py`

Declares the same `use-visualisation` argument with the same default and choices, and forwards it into the `IncludeLaunchDescription` `launch_arguments` dict alongside `use-sim-time`. The key is the hyphenated launch-argument name, not the underscored parameter name, which is the same trap already commented for `use-sim-time` in that file.

**Backwards compatibility.** Additive and defaulted, so `djinn start sitl basalt` and every other existing invocation is unaffected.

## 6. Blast radius

| Consumer | Touched | Effect |
|---|---|---|
| `basalt_slam_node` | Yes | Compiles again; gains the visualiser objects and Pangolin transitively |
| `basalt_slam` | Yes | Same objects and libraries, sourced from the new target |
| `basalt`, and its other nine executables | No | Unchanged targets, flags and links |
| `orbslam3_mono_node` and the ORBSLAM3 branch | No | Guarded by `SLAM_TYPE`, and `find_package(Pangolin)` left in place |
| `basalt_slam_test.launch.py` callers | No | New argument is defaulted |
| `BasaltSLAM` API consumers | One | `RunSlamVisualiser` signature change, single call site |

## 7. Validation

Performed in the dev container:

- Python syntax check of both launch files with `python3 -m py_compile`, both pass.
- Grep confirming no remaining reference to `src/visualisation/*.cpp` outside the new target.
- Grep confirming `RunSlamVisualiser` has exactly one call site.
- Verified `GLEW_INCLUDE_DIR` reaches `USER_INC` at `Pangolin/src/CMakeLists.txt:176` and is exported `SYSTEM PUBLIC` at `:635`, which is the claim the whole build fix rests on.

Outstanding, because this dev container has no ROS, no CMake and no Pangolin, so nothing here was compiled or run:

- `rm -rf /ws/ros_ws/{build,install,log}/slam` then `/ws/scripts/build_ros_packages.sh`, expecting `basalt_visualisation`, `basalt_slam` and `basalt_slam_node` all to build.
- Launch with `use-visualisation:=False` and confirm no window, then take the node through activate and deactivate and confirm no fault at `on_deactivate`, which is the §4.2 regression test.
- Launch with `use-visualisation:=True` on a container with `DISPLAY` and an X socket mounted, and confirm the window renders a live trajectory rather than a black or frozen frame, which is the §4.1 regression test.
- Confirm the parameter arrives as a boolean, `ros2 param get /basalt_slam_node use_visualisation`, which is the §5.1 `ParameterValue` check.
- Forwarding check through the controllers launch file, `ros2 launch controllers basalt_slam_test.launch.py use-visualisation:=True`.

## 8. Related

- `ros_ws/src/slam/context/build-and-abi.md` — the target, the GLEW propagation mechanism and the ABI pin interaction.
- `ros_ws/src/slam/context/basalt-visualiser-integration.md` — the `Start`/`Run`/`Stop` contract and the parameter path.
- `ros_ws/src/slam/context/SIMD.md` — why `-march` is an ABI switch in an Eigen codebase.
