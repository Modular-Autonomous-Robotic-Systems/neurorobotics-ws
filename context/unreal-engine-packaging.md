# Unreal Engine for Project AirSim environments, from the object model to the packaged game

Durable reference for the Unreal Engine side of the simulation stack, written 2026-08-05 while diagnosing why `unreal/StonePineForest/Content/StonePineForest/Maps/Mountains_Map.umap` refuses to open in the Unreal Engine 5.2 editor that [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §2 pins. It is both a background text and a procedure manual. The background exists because the failure is unintelligible without the package format, and the procedures exist because the remedy is a sequence of editor and command line operations that no single upstream document assembles.

Its companions are [`project-airsim-architecture.md`](project-airsim-architecture.md), which covers the simulator's own software architecture and its configuration surface, and [`project-airsim-docker-build.md`](project-airsim-docker-build.md), which covers the image, the toolchain and the build chain that compiles and packages what this file describes. Where those files already answer a question, this one cites them rather than repeating them. Every claim below about engine internals was read from the Unreal Engine 5.2 source now checked out at `sitl_ws/src/ue5/UnrealEngine`, described in §13, and every claim about the project was read from the tree or measured from the binary assets themselves.

## 1. Introduction, Unreal Engine as a simulator substrate

A robotics simulator built on a game engine inherits a design that was never intended for robotics, and understanding which of its assumptions bind and which are merely conventional is the difference between extending it and fighting it. Unreal Engine is, for present purposes, three cooperating systems. There is an object model with runtime reflection, which gives every gameplay type a serialisable description of its own fields. There is a renderer, which turns a scene description into images on a thread of its own. And there is a build and content pipeline, which compiles native modules and transforms authored assets into a form the shipped executable can consume. A simulation environment is a project that binds all three, and packaging is the act of running the third over the first two.

The unit of persistence is the package. Every asset, whether a texture, a material, a static mesh or an entire level, is a package on disk, and every package shares the same container format regardless of what kind of asset it holds, which is why §2 can treat one asset as representative of all of them. A package opens with a header declaring the engine format it was written in, together with the package's own name, its flags, a container of custom versions, each covering one subsystem that versions its own serialisation independently, and the offsets and counts of the tables that follow it, namely a name table of every string the package uses, an import table naming every object the package references without owning, and an export table naming every object the package owns together with the location of its serialised data. The header therefore plays three roles at once, it is the gate an engine checks before it will attempt to read anything further, it is the index by which every later table and every export is located, and it is a record of origin, since the engine version and build that wrote the package are stamped into it and can be read back directly from the file, independently of the engine's own loader, as §8.1 and §12.2 both make direct use of. That header, and in particular the asymmetry by which a newer engine can read an older package while an older engine cannot read a newer one, is the whole of the present problem, so it is treated first and at length, in §2 below.

The unit of composition is the actor, an object placed in a world, and the unit of behaviour is the component attached to it. Every actor carries a transform, thetranslation, rotation and scale that fixes its position and orientation. An actor's transform places it within the world and a component's transform placing it relative to whichever actor or parent component it is attached to. The root component of an actor supplies the actor's own transform directly, so that moving an actor is in effect moving its root component and carrying every other attached component along with it.

A component is a unit of behaviour or geometry attached to an actor. A component, for instance, maybe a static mesh component contributing render geometry or a movement component contributing behaviour. An actor is typically no more than a named bundle of such components together with the logic that coordinates them. This pairing of actor, component and transform is the runtime half of the object model, standing apart from the storage axis described above, and it is developed at length in §4.1, the gameplay framework built on top of the object model, (the game mode, the player controller and the pawn), in §4.2, and the usage of a transform to spawn a robot from a scene configuration rather than from a placed actor, in §4.3.

A level is, in essence, a package whose exports are the actors of one world, which is the point at which the persistence axis above and the composition axis above coincide, since opening a `.umap` is exactly the generic package load already described, except that the objects its export table lists happen to be actors, and instantiating them is what populates a world. §4.1 develops this correspondence from the runtime side, and it is also the fact behind a constraint used repeatedly later in the document, namely that a level with no World Partition keeps every one of its actors in the single package that is the level file, so that package's header failing to load takes the entire level down with it at once, a consequence worked through for this project's own StonePineForest maps in §8.

The unit of distribution is the cooked, staged and archived game, produced by an automation tool that walks the content graph, converts every referenced asset to platform binary form, compiles the native code and lays the result out as a runnable tree. The content graph the automation tool walks is built from the import tables introduced above, so an asset that no other package's import table reaches is, by default, never cooked at all, regardless of whether it exists in the project, which is why a scene whose robot meshes are chosen only at runtime, from a configuration file the cooker never reads, must have those directories named explicitly for them to be included. §7 covers cooking, staging, paking and archiving in full, including the exact configuration directive this reachability rule requires and the single command that drives all four steps together with compilation.

Project AirSim attaches to this substrate at exactly one seam. It ships an Unreal plugin whose game mode, when the world begins play, starts a simulation server inside the Unreal process and then spawns robots from a JSON scene description rather than from anything placed in the level. The environment therefore contributes terrain, geometry, materials and lighting, and contributes nothing at all to the vehicle, the physics or the sensor models. This division is what makes an arbitrary Unreal environment usable as a robotics scene, and it is also why the environment's own author, who was almost certainly building a game, leaves behind artefacts that the roboticist must then reconcile.

The frame model is worth stating once, because both the sensor timestamps and the packaging behaviour follow from it. The game thread advances gameplay by one tick, during which actors update and physics steps, and it enqueues rendering work for the render thread, which runs one or more frames behind. A camera sensor in Project AirSim is a scene capture component whose readback therefore crosses that thread boundary, which is treated in §7. The clock that stamps those images is not Unreal's, and the four clock types, the tick driver and the stamping path are documented in [`project-airsim-architecture.md`](project-airsim-architecture.md) §B and in [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md), which this file does not duplicate.

## 2. The object model and the package format

### 2.1 UObject, reflection and tagged serialisation

Every persistent type in Unreal derives from `UObject`, and every field intended to survive a save is annotated with a reflection macro that a code generator, Unreal Header Tool, turns into runtime metadata. Serialisation is by default tagged, that is each property is written with an identifier for its name and type alongside its value, rather than as a bare struct laid out by the compiler. Tagged serialisation is what allows a package written by one engine build to be read by another whose class definitions have gained, lost or reordered fields, because the reader matches by tag and silently drops what it does not recognise.

This tolerance is broad but it is not unlimited, and the limit is precisely where the tag encoding itself changes. A reader can skip a property it does not know. It cannot skip a property whose tag it cannot parse, because it would not know where the property ends. Every one of the four format increments between Unreal Engine 5.2 and 5.5, enumerated in §8.2, touches either the export table layout or the property tag encoding, which is why the failure is total rather than partial.

### 2.2 What a `.uasset` and a `.umap` actually contain

The two extensions denote the same container. A `.umap` is a package whose flags include `PKG_ContainsMap` and whose exports are the actors of a world, and a `.uasset` is any other package. The container opens with `FPackageFileSummary`, serialised at `sitl_ws/src/ue5/UnrealEngine/Engine/Source/Runtime/CoreUObject/Private/UObject/PackageFileSummary.cpp`, and the summary is followed by four tables and then by the export data proper.

| Region | Content |
|---|---|
| Summary | The tag `0x9E2A83C1`, the legacy version, the two engine format versions, the licensee version, the custom version container, the total header size, the package name, the package flags, and the offsets and counts of every table that follows |
| Name table | Every `FName` string the package uses, written once and referenced by index thereafter |
| Import table | Every object this package references but does not own, each entry naming a class package, a class name, an outer index and an object name |
| Export table | Every object this package owns, with its class, its outer, its flags and the offset and size of its serialised data |
| Export data | The tagged property streams of the exports, in the order the export table declares |

The import table is the dependency edge set of the content graph, and it is the table that the cooker walks to decide what else must be cooked. It is also, as §8.3 shows, where a stale reference to a plugin that no longer exists becomes visible without opening the editor at all.

### 2.3 The two version numbers, and the asymmetry that governs everything

A package declares its format with two integers rather than one, and the reason is historical. `Engine/Source/Runtime/Core/Public/UObject/ObjectVersion.h:23-35` explains that Unreal Engine 4 and Unreal Engine 5 maintain independent enumerations so that a change made in one lineage does not consume version numbers in the other. `EUnrealEngineObjectUE4Version` counts from 214 and is effectively frozen, and `EUnrealEngineObjectUE5Version` starts at 1000, the comment at `:45` recording that the choice of 1000 was made to show a clear difference from the 522 that Unreal Engine 4 had reached. The pair is carried in `FPackageFileVersion` at `:732`, whose `ToValue()` at `:754` returns the Unreal Engine 5 number when it is at least 1000 and the Unreal Engine 4 number otherwise, which is why a single number appears in most diagnostics.

Each enumeration terminates in a sentinel pair, `AUTOMATIC_VERSION_PLUS_ONE` followed by `AUTOMATIC_VERSION = AUTOMATIC_VERSION_PLUS_ONE - 1`, at `ObjectVersion.h:78-79`. The consequence is that the format version an engine writes is simply the count of format changes its branch has accumulated, and that a release branch's number is fixed by the last entry present in its own copy of the header. Unreal Engine 5.2 therefore writes 1009 and Unreal Engine 5.5 writes 1013, which the two checkouts confirm directly and which §8.2 tabulates.

The asymmetry follows immediately and is the single most important fact in this document. A newer engine reads an older package, because the older format is a subset of what it knows and every subsequent change was designed to upgrade in place on load. An older engine cannot read a newer package, because it has no description of the fields that were added after it was built. The engine does not attempt it and does not fail obscurely. It refuses at the summary, in three separate places for three separate consumers.

| Consumer | Location | Behaviour |
|---|---|---|
| Asset registry gather | `Engine/Source/Runtime/AssetRegistry/Private/PackageReader.cpp:113-121` | Logs `Package %s is too new. Engine Version: %i Package Version: %i` as a warning and returns `EOpenPackageResult::VersionTooNew`, so the asset never enters the registry |
| Editor map load | `Engine/Source/Editor/UnrealEd/Private/EditorServer.cpp:2422-2433` | Formats `{File} is a UE map [File:v{UE4Version}\|{UE5Version}], from an engine release newer than this [Cur:v{UE4Lastest}\|{UE5Lastest}]` and refuses the load |
| Package linker | `PackageFileSummary` validation, consumed by `FLinkerLoad` | Handles the case gracefully, which is why both call sites above log a warning rather than an error |

There is no downgrade. This is not an omission that a switch could remedy, and it is worth stating why rather than merely asserting it. Upgrading a package is a matter of running the transformations that each intervening format change defined, and those transformations exist in the newer engine because the newer engine had to be able to load everything that came before it. Downgrading would require the older engine to invert transformations it has never heard of, discarding data whose meaning it does not know, and no such inverse is defined or definable in general. The engine's own bulk migration tool, `UResavePackagesCommandlet` in `Engine/Source/Editor/UnrealEd/Private/Commandlets/ContentCommandlets.cpp`, confirms the direction by construction, since it defaults `MaxResaveUEVersion` to `GPackageFileUEVersion.ToValue() - 1` at `:464`, which is to say it will only ever touch packages strictly older than the running engine.

### 2.4 Custom versions

Beside the two global numbers, a package carries a container of custom versions, each a GUID paired with an integer, one per subsystem that versions its own serialisation independently. The asset registry compares these against the running engine at `PackageReader.cpp:133-140` and reports a missing custom version as its own error class. In practice a custom version mismatch is a symptom of the same disease as a global version mismatch and is resolved by the same means, but it is worth knowing that a package can be rejected for a reason the two headline numbers do not show.

## 3. Projects, modules, plugins and the build system

### 3.1 The project descriptor

A project is a directory containing a `.uproject` file, and that file is a small JSON manifest rather than a build script. `sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/StonePineForest.uproject` declares four things that matter, namely the engine association, the runtime modules the project itself defines, the target platforms, and the plugins to enable.

```json
{
	"FileVersion": 3,
	"EngineAssociation": "5.2",
	"Modules": [ { "Name": "StonePineForest", "Type": "Runtime", "LoadingPhase": "Default" } ],
	"TargetPlatforms": [ "Linux" ],
	"Plugins": [
		{ "Name": "ModelingToolsEditorMode", "Enabled": true, "TargetAllowList": [ "Editor" ] },
		{ "Name": "ProjectAirSim", "Enabled": true },
		{ "Name": "ChaosVehiclesPlugin", "Enabled": true }
	]
}
```

`EngineAssociation` is a declaration of intent and not an enforcement. It tells the launcher and the project file generator which engine to use, and nothing in the load path rejects a mismatch. The migration recorded in [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §10 set it to `5.2`, and the assets on disk were not touched by that edit, which is exactly why the mismatch documented in §9 survived unnoticed.

### 3.2 Modules, targets and Unreal Build Tool

Native code lives in modules, each a directory under `Source` with a `<Module>.Build.cs` that declares its dependencies in C#. A target, declared by a `<Project>.Target.cs`, names a linkable artefact and the modules it comprises. `sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/Source` carries the minimum viable arrangement, namely `StonePineForest.Target.cs`, `StonePineForestEditor.Target.cs` and a `StonePineForest` module whose implementation is a single `IMPLEMENT_PRIMARY_GAME_MODULE` line. The module exists solely so that the project counts as a C++ project, which is a precondition for compiling the plugin during packaging, and `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md:51` states that requirement directly.

Two settings on the target files are version-coupled and were corrected during the port, as [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §10 records. `DefaultBuildSettings` and `IncludeOrderVersion` must name enumerators that exist in the engine being built against, and StonePineForest arrived carrying `BuildSettingsVersion.V5` and `EngineIncludeOrderVersion.Unreal5_5`, neither of which exists in Unreal Engine 5.2. That is the second independent trace of the same origin that §8.4 establishes from the asset headers, and it is worth noticing that this one broke the compile loudly while the asset version broke the editor quietly.

Unreal Build Tool reads these C# files, resolves the module graph, invokes Unreal Header Tool to generate the reflection code, and drives the compiler. Under this workspace it runs with the engine's own bundled clang, selected by `UE_ROOT` being set in the environment, for the reasons given in [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §3.

### 3.3 Plugins, and what ProjectAirSim is

A plugin is a self-contained project fragment with its own `.uplugin` descriptor, its own modules and its own content mount point. A `.uplugin` file reuses the same small JSON schema as the `.uproject` manifest of §3.1, declaring the plugin's own runtime modules under a `Modules` array and any other plugins it in turn requires under a `Plugins` array of `{Name, Enabled}` pairs identical in shape to the one quoted there. `sitl_ws/src/ue5/ProjectAirSim/unreal/Blocks/Plugins/ProjectAirSim/ProjectAirSim.uplugin` declares one runtime module, named `ProjectAirSim`, with `LoadingPhase` `PostConfigInit`, and it declares three transitive plugin requirements in its own `Plugins` array, namely `ProceduralMeshComponent`, `SunPosition` and `PixelStreaming`, each enabled automatically once `ProjectAirSim` itself is enabled from the project's `.uproject`, without any of the three needing to be named there directly.

`LoadingPhase` fixes the point in the engine's own startup sequence at which a module's code is loaded, and the engine's `ELoadingPhase::Type` enumerates the possible values in the order that sequence actually runs.

| Phase | Meaning |
|---|---|
| `EarliestPossible` | As soon as `.uplugin` files can be read at all, including from a pak file, for a module needed just to read files, such as one implementing a compression format |
| `PostConfigInit` | Immediately after the configuration system initialises, still before the engine itself is fully initialised, for a module needing very low level hooks in place early, the phase `ProjectAirSim` itself uses |
| `PostSplashScreen` | Right after the system splash screen renders |
| `PreEarlyLoadingScreen` | Before `CoreUObject`, for setting up a manual loading screen or a chunk patching system |
| `PreLoadingScreen` | Before the engine is fully initialised, for a module that must hook into the loading screen before it triggers |
| `PreDefault` | Immediately before the default phase |
| `Default` | During engine initialisation, after game modules are loaded, the ordinary phase for most modules |
| `PostDefault` | Immediately after the default phase |
| `PostEngineInit` | After the engine has finished initialising entirely |
| `None` | Not automatically loaded at all |

`PostConfigInit` is therefore among the earliest phases available and one of only two that run before the engine is fully initialised, and `ProjectAirSim` needs a phase that early for a reason worked through fully in §6.2, namely that the custom depth stencil buffer its segmentation image type depends on must be enabled, in `UnrealSimLoader.cpp`'s `SetUnrealEngineSettings`, before the world exists.

The three plugins are Epic's own, not authored by Project AirSim, and each is pulled in for a capability the simulator exercises elsewhere in its own code rather than as an unused dependency. `ProceduralMeshComponent` supplies a renderable component and a library of utilities for building and editing triangle mesh geometry at runtime rather than importing it as a fixed asset, and Project AirSim's GIS renderer uses it directly, at `Private/Renderers/GISRenderer.cpp`, to construct the terrain mesh for each map tile it streams in, the same renderer §5.3 already introduces as the runtime alternative to the procedural foliage spawners built into the editor. `SunPosition` computes the sun's position in the sky from a latitude, a longitude and a date and time, and Project AirSim calls it from `TimeOfDay::setSunPositionFromDateTime` in `Private/World/TimeofDay.cpp`, which is how a scene configuration can request realistic outdoor lighting for a given simulated time of day rather than relying on lighting baked once into the level. `PixelStreaming` compresses the engine's rendered frames and audio into an h.264 stream carried over WebRTC to a browser, and `UnrealSimLoader.cpp` configures its bitrate, frame rate and audio settings for simulation use, so that a camera sensor configured as a streaming camera can be viewed live in a browser over the network, including from a container with no display attached to the viewing machine, a workflow documented in full at `sitl_ws/src/ue5/ProjectAirSim/docs/sensors/camera_streaming.md`.

Two of the three plugins the port copies in, `Drone` and `Rover`, are content-only, carrying the meshes the simulator spawns for a vehicle and no code at all. Omitting them yields a robot that exists in physics and is invisible on screen, which is a confusing failure and is why `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md:9-24` lists them as part of the package rather than as optional extras. The full inventory of what a third-party project must acquire is tabulated in [`project-airsim-architecture.md`](project-airsim-architecture.md) §E.3 and is not repeated here.

A plugin's content is mounted under a virtual root named after the plugin, so `/ProjectAirSim`, `/Drone` and `/Rover` are sibling roots of `/Game`, which is the project's own `Content` directory. That naming is what the cook directives in `Config/DefaultGame.ini` refer to, and §8.1 explains why those directives are mandatory rather than advisory.

### 3.4 The configuration hierarchy

Settings live in ini files layered from engine defaults through project defaults to per-user overrides, and the project layer is the one under version control. `sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/Config/DefaultEngine.ini` carries the three settings that decide what a packaged run does.

```ini
[/Script/EngineSettings.GameMapsSettings]
EditorStartupMap=/Game/StonePineForest/Maps/Mountains_Map
GameDefaultMap=/Game/StonePineForest/Maps/Mountains_Map
GlobalDefaultGameMode=/Script/ProjectAirSim.ProjectAirSimGameMode
```

`GameDefaultMap` is the level a packaged game opens with no arguments, `EditorStartupMap` is the level the editor opens, and `GlobalDefaultGameMode` is the load-bearing edit of the whole port, since without it the plugin loads and never starts a simulation server. Note that all three name `Mountains_Map`, so the version failure of §9 takes out the editor startup path, the packaged run path and the cook simultaneously.

The renderer settings in the same file are worth reading before changing anything, because several of them cost frame time that a simulation does not need. `r.RayTracing=True`, `r.DynamicGlobalIlluminationMethod=1` and `r.ReflectionMethod=1` select Lumen with hardware ray tracing, and `r.Shadow.Virtual.Enable=1` selects virtual shadow maps. These produce a handsome image and they are not free, and a headless run producing camera frames for a visual odometry front end has no use for most of what they buy.

## 4. Levels, worlds and actors

### 4.1 Actors, components and the level as a container

An actor is an object that can be placed in a world and has a transform. A component is a unit of behaviour or geometry attached to an actor, and one component of an actor is its root, whose transform is the actor's own. A level is the container, and a world is the runtime object that owns one persistent level and any streamed sub-levels. Opening a `.umap` in the editor is loading a package whose exports are that level's actors, instantiating them, and attaching the result to a world.

Two structural facts about the StonePineForest maps were measured directly from the packages rather than assumed, and both simplify the recovery procedure of §10. Neither map uses World Partition, since the name tables contain `Landscape` and `InstancedFoliageActor` and contain no streaming proxy or partition types, and there are no `__ExternalActors__` or `__ExternalObjects__` directories anywhere under `Content`. Both are therefore classic monolithic levels, in which every actor lives in the one package. That is why one file being unreadable takes out the entire level, and equally why recovering that one file recovers the entire level.

A pawn is the class of actor built specifically to be possessed, that is, to be the physical presence in the world through which some will external to the world itself, human or artificial, acts. Where an ordinary actor placed in a level merely exists, a pawn exists to be driven, and it is this possession relationship, rather than any particular shape or behaviour, that marks an actor as a pawn. The significance of the distinction is that it is the seam at which control from outside the simulation, a player's input or an AI's decision, meets the physics and rendering of an actor inside it, which is why the entire gameplay framework organises itself around this one class. A pawn by itself carries no built-in movement and no visible form, only the capacity to be possessed, and every further specialisation the engine offers, taken up below, adds movement and form on top of that same capacity.

A controller is the counterpart that supplies the will a pawn lacks on its own, and Unreal Engine offers two kinds of it. A player controller receives input from a human at a keyboard, a gamepad or another device and translates that input into whichever actions the possessed pawn exposes, while an AI controller supplies the same possession relationship to behaviour generated by the engine's own artificial intelligence systems, typically a behaviour tree reading a blackboard, rather than by a human at all. Possession is exclusive yet not fixed for the lifetime of either party, since a controller possesses at most one pawn at a time but may release it and possess another, which is the mechanism behind switching a player between vehicles or characters, or handing the same pawn between a human and an artificial controller depending on context. The relationship is agnostic to what kind of pawn is on the other end of it, since a player controller can drive a walking character, a flying vehicle or a stationary camera-only pawn through the identical possession interface, and it is the pawn itself, not the controller, that supplies whatever movement logic its own type requires.

Unreal Engine ships a small hierarchy of pawn types, differentiated by the movement and form each adds on top of the bare class. The pawn class itself is the most general of them, an actor with the capacity for possession and no assumption about movement, suitable for a stationary turret, a free camera or a wholly bespoke vehicle carrying its own movement code. A character is the specialisation built for bipedal or humanoid movement, adding a movement component that handles walking, falling and jumping together with a collision capsule and a skeletal mesh appropriate to a legged body. A default pawn, and its lighter sibling the spectator pawn, are the engine's own simple free-flying pawns, used for editor navigation, debug flythroughs and non-gameplay camera control rather than for shipped gameplay. And a wheeled vehicle pawn is the specialisation for cars and other wheeled craft, modelling suspension, tyre friction and engine torque directly through its own movement component. Beyond this built-in set, a great many pawns encountered in practice are project-specific subclasses of the bare pawn class, built by a team to model a particular aircraft, vessel or other vehicle whose movement the built-in hierarchy does not cover, which is the category Project AirSim's own robot occupies conceptually even though, as §4.3 shows, it declines the pawn and controller machinery entirely and drives its actors directly from its own physics engine instead.

### 4.2 The gameplay framework, and how a player normally enters a world

Unreal's gameplay framework is a small set of cooperating classes with fixed responsibilities. The game mode defines the rules and, critically, decides what pawn class the player receives. The game state and player state hold replicated data. The player controller is the bridge between input and a possessed pawn. The pawn is the actor the player drives, and a character is a pawn with a movement component and a capsule.

The ordinary sequence is that the world begins play, the game mode is instantiated, the game mode finds a `PlayerStart` actor placed in the level, and it spawns its `DefaultPawnClass` at that actor's transform and hands it to a player controller to possess. Everything a level author does to control where a player appears reduces to placing `PlayerStart` actors and setting the game mode.

Which game mode applies is decided in two places, and the precedence matters. `GlobalDefaultGameMode` in `Config/DefaultEngine.ini` sets the project-wide default, and the per-map `GameMode Override` in the editor's World Settings panel, stored inside the map package itself, overrides it for that map. `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md:36-49` recommends setting both, and §8.3 shows what happens when the second is left pointing at a plugin that is no longer present.

### 4.3 How Project AirSim's robot enters a world instead

Project AirSim declines the pawn machinery entirely, and the code is short enough to quote in full because the design is legible from it. `unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/ProjectAirSimGameMode.cpp` is the whole of the integration on the Unreal side.

```cpp
AProjectAirSimGameMode::AProjectAirSimGameMode(
    const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer),
      UnrealSimLoader(FPaths::ConvertRelativePathToFull(FPaths::ProjectDir())) {
  DefaultPawnClass = nullptr;
  FApp::bUseFixedSeed = true;  // for determinism, persists in UE project
}

void AProjectAirSimGameMode::StartPlay() {
  Super::StartPlay();
  UnrealSimLoader.LaunchSimulation(this->GetWorld());
}
```

`DefaultPawnClass = nullptr` is the declaration that no pawn will be spawned by Unreal, and `FApp::bUseFixedSeed = true` pins the random seed for determinism, a setting the comment warns persists in the project. `StartPlay` hands the world pointer to the sim loader, which spawns the scene actor and then waits for a client to connect and load a scene configuration over the network transport described in [`project-airsim-architecture.md`](project-airsim-architecture.md) §D.1.

Robots arrive later and from the configuration, not from the level. `Private/UnrealScene.cpp:82-107` is the spawn path.

```cpp
auto xyz_ned = sim_robot.GetOrigin().translation_;
FVector translation(xyz_ned.x() * 100, xyz_ned.y() * 100,
                    -xyz_ned.z() * 100);  // NED m -> NEU cm
auto rpy = sim_robot.GetOrigin().rotation_;
FQuat rotation(rpy.x(), rpy.y(), rpy.z(), rpy.w());
FTransform transform(rotation, translation);

auto unreal_robot = World->SpawnActorDeferred<AUnrealRobot>(
    AUnrealRobot::StaticClass(), transform, nullptr, nullptr,
    ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn);
unreal_robot->Initialize(sim_robot, sim_physbody, this);
```

Three details of this are worth carrying forward. The spawn is deferred, so `BeginPlay` does not fire until `FinishSpawning` is called for every actor at `UnrealScene.cpp:174-180`, which lets the whole scene reach a consistent state before any actor begins ticking. The collision handling method is `AdjustIfPossibleButAlwaysSpawn`, so a robot whose origin intersects terrain is nudged rather than rejected, which mercifully converts one class of configuration error into a survivable one. And the transform comes from `sim_robot.GetOrigin()`, which is the `origin` block of the scene configuration file and has no relationship whatever to any `PlayerStart` in the level.

That last point is the practical trap, and `sitl_ws/src/ue5/ProjectAirSim/docs/config_scene.md:56` warns about it directly, namely that `"0 0 0"` is the Unreal world origin and not the `PlayerStart`. For a landscape map whose terrain sits kilometres from the world origin, the default drops the vehicle through the void. The exact conversion, the two cheap cross-checks and the interactive and headless procedures for reading the value out of a map are given in [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §11.1 and are summarised as a procedure in §12.7 below.

## 5. Assets, terrain and populated worlds

### 5.1 The asset types a natural environment is made of

An environment such as StonePineForest is assembled from a small number of asset kinds, and the `Content/StonePineForest` tree is a fair inventory of them.

| Kind | Where | Role |
|---|---|---|
| Texture | `Textures/` | Sampled image data, base colour, normal, packed roughness and metalness, masks |
| Material | `Materials/MasterMaterials/`, `Materials/MaterialFunctions/` | A shader graph compiled to a shader, parameterised for reuse |
| Material instance | `Materials/MI_*.uasset` | A cheap parameter override of a master material, adding no shader permutation |
| Static mesh | `Meshes/` | Rigid geometry with its own collision, lightmap UVs and level-of-detail chain |
| Landscape material | `Materials/LandscapeMaterials/` | A material with layer blend nodes, sampled by the terrain according to painted weights |
| Foliage type | `WorldSpawner/` | A description of how one mesh is to be scattered, its density, scale range, alignment and collision |
| Blueprint | `CustomSign/Blueprints/` | A visual script class, here a parameterised sign actor driven by a data table and an enumeration |
| Level | `Maps/` | The container of placed actors described in §4.1 |

The `CustomSign` directory is a compact and instructive example of the composition, since `BP_Sign.uasset` is an actor class whose appearance is driven by `DT_Signs.uasset`, a data table, keyed by `E_SignTypes.uasset`, an enumeration, over a struct declared in `Struct_Signs.uasset`. That is the ordinary Unreal idiom for a family of similar props and it is directly transferable to placing parameterised static obstacles for a robotics scene.

### 5.2 Landscape

Terrain in both mountain maps is a `Landscape` actor, a heightfield divided into components, each component carrying a heightmap, per-layer weightmaps and its own collision representation. Terrain is authored either by sculpting in the editor or by importing a heightmap, and the second route is what matters for a georeferenced or a procedurally generated environment, since a `.r16` or 16-bit `.png` heightmap plus one greyscale weightmap per material layer fully determines the result.

The material a landscape uses is not an ordinary material. It blends layers according to the painted weights, and the layer names in the material must match the layer info assets the landscape carries, which is the usual cause of a terrain that imports as flat grey. `Content/StonePineForest/Materials/LandscapeMaterials/` holds the project's own, and `MI_Mountains` is the instance the `Mountains_Map` import table references.

Landscape data does not survive a text export, which is a constraint that bears directly on the recovery options of §10. Heightmaps and weightmaps are bulk binary data attached to the landscape components, and the text format that carries actor properties between editors carries a reference to the landscape and not its heightfield. The supported route for moving terrain between projects or engine versions is therefore to export the heightmap and the weightmaps to image files and re-import them, which reproduces the terrain exactly and reproduces neither the foliage scattered on it nor the actors placed against it.

### 5.3 Foliage, and procedural generation

Foliage is instanced rather than placed as individual actors, because a forest is hundreds of thousands of trees and an actor apiece would be untenable. An `InstancedFoliageActor` in the level owns one `FoliageInstancedStaticMeshComponent` per foliage type, and each component holds a transform array. Both mountain maps carry these names in their name tables, confirming the arrangement.

The seven assets in `Content/StonePineForest/WorldSpawner/` are the procedural layer above that. Each imports `FoliageType_InstancedStaticMesh`, which is the signature of a procedural foliage spawner, an asset that describes a population of species with their sizes, ages, shade tolerances and spread rates, and which the editor simulates to produce a plausible distribution. The named populations, `StonePine_Forest`, `TraditioanalStonePine_Forest`, `Pecans_Forest_Green`, `Pecans_Forest_Red`, `Pecans_Forest_Yellow`, `Pecans_Forest_ColorFull` and `Rocks`, are exactly the vegetation communities the environment offers, and they are the mechanism by which a new map in this project should be populated. The workflow is to place a procedural foliage volume, assign the spawner, simulate, and then keep the result, which is written into the level as ordinary foliage instances.

This is the practical answer to procedural generation within the engine's own facilities. Generation at runtime, or generation from an external source such as a terrain tile server, is a different matter, and Project AirSim already carries a path for it in its GIS renderer, which spawns procedural mesh actors from tiles at `Private/Renderers/GISRenderer.cpp:151-160`. That path is documented at `sitl_ws/src/ue5/ProjectAirSim/docs/gis_scenes.md` and is out of scope here.

### 5.4 Moving objects and non-player characters

Project AirSim has a first-class notion for a scripted moving object, distinct from a robot, and it is the environment actor. `UnrealScene.cpp:110-140` spawns an `AUnrealEnvActor` from the same scene configuration that spawns robots, by the identical origin conversion, and `sitl_ws/src/ue5/ProjectAirSim/docs/scene/` covers the trajectory and link attachment surface. An environment actor is the correct construct for a moving vehicle, a walking pedestrian or an articulated obstacle that the robot must perceive and avoid, because it is driven by the simulation clock and therefore reproducible.

Placing an animated character by ordinary Unreal means, as a skeletal mesh actor with an animation blueprint, also works and is simpler, and it is the wrong choice whenever the motion must be repeatable across runs or must be synchronised with the simulation's own stepping, since it is then driven by Unreal's frame time rather than by the sim clock.

### 5.5 Importing new assets

Geometry and textures enter a project through the content browser's import, which converts an external file into a `.uasset`. A mesh arrives as `.fbx`, `.obj` or `.gltf`, a texture as `.png`, `.tga` or `.exr`, and a heightmap as `.r16` or 16-bit `.png`. Import is a one-way conversion with settings, and the settings are stored on the asset so a re-import repeats them.

Three import settings account for most of the trouble a robotics user meets. A mesh intended to be seen by a camera and touched by a lidar needs collision, and the import default of simple collision generated from the mesh bounds is frequently not what is wanted, so complex collision from the render mesh must be selected explicitly on the static mesh asset. A texture used as a normal map or a packed mask must have its compression setting changed from the default colour compression, or the data is degraded before the material ever samples it. And a mesh imported at the wrong scale is the commonest single error, because Unreal's unit is the centimetre while nearly every authoring tool exports metres.

## 6. Sensors and rendering

### 6.1 The renderer, in the detail this document needs

Unreal's default path is a deferred renderer. Geometry is rasterised once into a set of buffers holding base colour, normal, roughness, metalness and depth, and lighting is then evaluated per pixel over those buffers, so cost scales with screen area and light count rather than with their product. Post processing runs afterwards over the lit result, and it is post processing that supplies tone mapping, exposure, motion blur and the material-driven effects that Project AirSim uses to produce non-photometric image types.

The renderer runs on its own thread, one or more frames behind the game thread. Any request for pixels is therefore asynchronous with respect to gameplay, and the readback must be enqueued as a render command and its result collected later. `Private/Sensors/UnrealCameraRenderRequest.cpp` is where Project AirSim does this, and the consequence for the roboticist is that an image's content corresponds to a slightly earlier world state than the game thread's current tick, which is one of the reasons the timestamp discipline documented in [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md) matters.

### 6.2 How a camera sensor is built

A Project AirSim camera is not a `CameraActor`. It is a set of `USceneCaptureComponent2D` instances, each rendering the scene into its own `UTextureRenderTarget2D` from the same pose, one per image type the sensor is configured to produce. `Private/Sensors/UnrealCamera.cpp:187-290` constructs them, and the pattern is uniform across the seven types.

| Capture component | Image type |
|---|---|
| `SceneCaptureComponent` | Scene colour |
| `DepthPlanarCaptureComponent` | Planar depth |
| `DepthPerspectiveCaptureComponent` | Perspective depth |
| `SegmentationCaptureComponent` | Segmentation by stencil value |
| `DepthVisCaptureComponent` | Depth visualised for human inspection |
| `DisparityNormalizedCaptureComponent` | Normalised disparity |
| `SurfaceNormalsCaptureComponent` | Surface normals |

Every one of them sets `CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR`, which is to say that each renders a full lit and post-processed frame, and the non-colour types are then produced by installing a post-process material on the capture. That is the mechanism by which depth, segmentation and normals emerge from a colour pipeline. Segmentation in particular depends on the custom depth stencil buffer being enabled, which `UnrealSimLoader.cpp` does in `SetUnrealEngineSettings` before the world runs, and which is why the plugin module loads at `PostConfigInit`.

The cost model follows directly and is worth internalising before configuring a scene. Each enabled image type is an additional full scene render at the sensor's resolution, every frame it is requested. A robot with two cameras each producing colour and depth is four scene renders per frame beyond the viewport's own, and that, rather than the physics or the transport, is what usually sets the achievable rate.

The remaining sensors divide along the same line. Lidar has both a ray-cast implementation and a GPU implementation, at `Private/Sensors/UnrealLidar.cpp` and `Private/Sensors/GPULidar.cpp`, with the latter carrying its own compute shader and scene view extension for intensity. Radar and the distance sensor are ray-cast against physics collision, which is the reason §5.5 insists on collision being correct on imported meshes, since a mesh with no collision is invisible to every ray-cast sensor while remaining perfectly visible to every camera. The full parameter surface of every sensor is tabulated in [`project-airsim-architecture.md`](project-airsim-architecture.md) §D.6.

## 7. Cooking, staging and packaging

### 7.1 Cook

Cooking converts every asset the shipped game will need from its editor form into the target platform's binary form, compiling shaders for the target's feature level, converting textures to the target's compression formats and stripping editor-only data. The cooker starts from a root set and follows the import tables transitively, so an asset that nothing references is not cooked.

That reachability rule is the reason `Config/DefaultGame.ini` must be edited, and the edit is quoted here because getting it wrong produces a game that launches and then behaves as though the plugin were absent.

```ini
[/Script/UnrealEd.ProjectPackagingSettings]
+DirectoriesToAlwaysCook=(Path="/ProjectAirSim")
+DirectoriesToAlwaysCook=(Path="/Drone")
+DirectoriesToAlwaysCook=(Path="/Rover")
+MapsToCook=(FilePath="/Game/StonePineForest/Maps/Mountains_Map")
```

Plugin content is unreferenced by the level, because the robot mesh is chosen at runtime from a configuration file the cooker never reads, so nothing in the content graph reaches `/Drone` and without the directive its meshes are simply absent from the package. `MapsToCook` names the level explicitly. Note that removing the previous project's `/AirSim` directives matters as much as adding these, since the `/AirSim` mount point disappears with the plugin and cooking a path that no longer exists is an error rather than a warning, as [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §10 records.

### 7.2 Stage, pak and archive

Staging copies the cooked content and the compiled binaries into the layout the target expects. Paking collects the staged content into one or more `.pak` archives, which the runtime mounts as a virtual filesystem, reducing hundreds of thousands of small files to a handful of large ones. Archiving copies the staged tree to a chosen output directory.

The three steps plus the compile and the cook are driven by one Unreal Automation Tool command, and `sitl_ws/scripts/build_airsim2_game.sh` is the workspace's invocation of it.

```bash
"$UE_ROOT/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
    -project="$PAS_ROOT/unreal/$project/$project.uproject" \
    -nop4 -nocompile -build -cook -compressed -pak -allmaps -stage -archive \
    -archivedirectory="$PAS_ROOT/packages/$project/$config" \
    -clientconfig="$config" -clean -utf8output -prereqs
```

The switches decompose cleanly. `-build` compiles the game target, `-cook` runs the cooker, `-pak` and `-compressed` produce compressed pak files, `-stage` lays out the staged tree, `-archive` with `-archivedirectory` copies it out, `-allmaps` cooks every map rather than only those listed, `-clientconfig` selects Development or Shipping, `-nocompile` declines to rebuild the automation tool itself, and `-nop4` disables Perforce integration. The script guards the one ordering constraint that the build has, namely that the simulation libraries must exist before Unreal Build Tool runs, because the plugin links their static archives by path out of `Plugins/ProjectAirSim/SimLibs`. That constraint and its upstream issue history are documented in [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §7.

### 7.3 What lands on disk

The archive directory receives a `Linux` tree containing a generated `<Project>.sh` wrapper beside `<Project>/Binaries/Linux/<binary>` and the cooked content in pak form. The binary is named `<Project>` for a Development client and `<Project>-Linux-<Config>` for any other configuration. `sitl_ws/scripts/run_airsim.sh airsim2` invokes the staged executable directly rather than the wrapper, and the reasoning for that choice, along with the argument-forwarding failure it avoids, is recorded in [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §7.

## 8. The StonePineForest failure, diagnosed

### 8.1 The symptom and the measurement

The editor refuses to open the project's startup map. The authoritative line is in the editor log at `unreal/StonePineForest/Saved/Logs/StonePineForest.log`, emitted by the map-load validation of `EditorServer.cpp:2422-2433`.

```
Mountains_Map.umap is a UE map [File:v522|1013], from an engine release newer than this [Cur:v522|1009].
```

The same log's banner establishes the running engine beyond doubt, namely `Engine Version: 5.2.1-25360045+UE5` with `Installed Engine Build: 1`. The two numbers in the diagnostic are the pair of §2.3, so the map declares Unreal Engine 4 version 522 and Unreal Engine 5 version 1013, and the engine supports 522 and 1009.

Rather than trust the one message, every package in the project was decoded directly from its `FPackageFileSummary`, reading the tag, the two version fields and the `SavedByEngineVersion` and `CompatibleWithEngineVersion` structures. All 910 `.uasset` and `.umap` files under `Content` and `Plugins` were measured.

| Unreal Engine 5 version | Engine that wrote it | Count |
|---|---|---|
| 0, so Unreal Engine 4 only | 4.5 through 4.27 | 460 |
| 1004 | 5.0 | 123 |
| 1006, 1008 | 5.1 | 325 |
| 1009 | 5.2 | 1 |
| 1013 | 5.5.4 | 1 |

The distribution is the finding. Exactly one file in the project exceeds what Unreal Engine 5.2 can read, and it is `Content/StonePineForest/Maps/Mountains_Map.umap`, whose header decodes as `SavedByEngineVersion` 5.5.4 at changelist 37670630 and `CompatibleWithEngineVersion` 5.5.0. The project is not a 5.5 project with a 5.2 problem. It is a 5.0 and 5.1 project carrying a single file that was opened and re-saved by a 5.5 editor.

### 8.2 The four format changes that separate 1009 from 1013

Reading the two branches of `ObjectVersion.h` gives the exact content of the gap, and the entries are quoted from the enumeration comments.

| Value | Enumerator | Change |
|---|---|---|
| 1009 | `DATA_RESOURCES` | Added the bulk and data resource table. Unreal Engine 5.2's `AUTOMATIC_VERSION` |
| 1010 | `SCRIPT_SERIALIZATION_OFFSET` | Added a script property serialisation offset to export table entries for saved, versioned packages |
| 1011 | `PROPERTY_TAG_EXTENSION_AND_OVERRIDABLE_SERIALIZATION` | Property tag extension, overridable serialisation on `UObject`, overridable logic in containers |
| 1012 | `PROPERTY_TAG_COMPLETE_TYPE_NAME` | Added property tag complete type name and serialisation type |
| 1013 | `ASSETREGISTRY_PACKAGEBUILDDEPENDENCIES` | `WritePackageData` includes package build dependencies. Unreal Engine 5.5's `AUTOMATIC_VERSION` |

Three of the four changes alter the export table layout or the property tag encoding, which is precisely the class of change that §2.1 identified as unskippable. A 5.2 reader confronted with a 1011 property tag cannot determine where that property ends and therefore cannot reach the next one, so partial recovery is not merely unimplemented but incoherent. This is the concrete reason the refusal is at the summary rather than at the first unrecognised field.

### 8.3 A second and independent defect in the same file

Decoding the import table of `Mountains_Map.umap` reveals a reference that has nothing to do with engine versions and would have caused trouble regardless.

```
/Script/CoreUObject   Package   /Script/AirSim
/Script/CoreUObject   Class     AirSimGameMode
```

`Mountains_Map_LevelDesign.umap`, measured identically, contains neither. The map's World Settings therefore carry a per-map GameMode Override pointing at `AirSimGameMode` from the Cosys-AirSim plugin's `/Script/AirSim` module, a module that does not exist in this project, since the port deleted `Plugins/AirSim` and installed `Plugins/ProjectAirSim` in its place.

The consequence follows from the precedence rule of §4.2. The per-map override outranks `GlobalDefaultGameMode`, so if the class resolved it would win, and because it cannot resolve the engine nulls it and falls back to the project default, which happens to be the correct `ProjectAirSimGameMode`. The map is thus likely to function while logging a failed import, and it is carrying a latent hazard that must be cleared deliberately rather than left to a fallback. This is exactly the World Settings step that `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md:43-49` calls step 2B and that [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §10 deferred as conditional on the robot failing to spawn. The deferral was defensible and the finding supersedes it, since the override is now known to be not merely unset but actively wrong.

### 8.4 Provenance

Four independent traces converge on one account of how the file came to be as it is.

The map's `SavedByEngineVersion` is 5.5.4. The workspace's Cosys-AirSim image is built on `ghcr.io/epicgames/unreal-engine:dev-5.5`, hard-coded in `scripts/helpers/sitl.sh:10` and defaulted in `sitl_ws/src/ue5/AirSim/docker/Dockerfile_source:1`, and [`airsim-docker-build.md`](airsim-docker-build.md) records Cosys-AirSim v3.4.1 as targeting Unreal Engine 5.5. The map imports the Cosys-AirSim game mode. And the project arrived carrying `BuildSettingsVersion.V5` and `EngineIncludeOrderVersion.Unreal5_5` on its target files, per [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §10.

StonePineForest was therefore a 5.0 or 5.1 environment, adapted for Cosys-AirSim inside the Unreal Engine 5.5 editor, during which the level was opened, given a GameMode Override and re-saved, taking that one file to package version 1013 while every other asset was left untouched at its original version. The subsequent port onto Project AirSim moved the project's declared engine association to 5.2 and repaired the target files, and it did not and could not repair the asset, because nothing in a text edit reaches inside a binary package.

### 8.5 An artefact that will mislead a later reader

The same log carries four `LogAssetRegistry` warnings of the form `Package %s is too new. Engine Version: 1009 Package Version: 1013`, and three of them name StarterContent assets, namely `Audio/Collapse02.uasset`, `Props/Materials/M_TableRound.uasset` and `Props/Materials/M_Chair.uasset`. Decoding those three files today shows 4.5, 5.1 and 5.1 respectively, which appears to contradict the warnings and prompted a direct check.

The resolution is in the modification times. The warnings were written at 11:55:57 on 2026-08-05 and those three files have modification times between 11:56:12 and 11:56:15 on the same day, so they were rewritten fifteen seconds after being flagged. `Config/DefaultGame.ini` carries `[StartupActions]` with `bAddPacks=True` and `InsertPack=(PackSource="StarterContent.upack", PackName="StarterContent")`, so the 5.2 editor re-inserted its own bundled StarterContent over the 5.5-era copies during startup. The corroboration is that `Content/StarterContent/Blueprints/Blueprint_WallSconce.uasset` now reads as saved by 5.2.1 at changelist 25360045, which is the running engine's own changelist exactly, and is the single 1009 package in the whole distribution of §8.1.

The warnings were therefore accurate when written and the files they name have since been repaired by the engine itself. `Mountains_Map.umap` retains its original modification time of 2025-05-10 and was not repaired, because no startup action owns it. A reader who decodes the assets today and reads the log today will see a contradiction that does not exist, and this paragraph is here so that they do not spend the hour it cost to resolve.

## 9. Remedies, ranked

Five routes exist. They are ranked by the ratio of what they preserve to what they cost, and the reasoning is given so that a later reader can re-rank them if the constraints change.

The first is to rebuild from the surviving 5.1 sibling, and it is the recommendation. `Mountains_Map_LevelDesign.umap` decodes as package version 1008, saved by 5.1.0, and therefore loads in 5.2 without any intervention. Its name table shares 619 entries with `Mountains_Map` and it declares 4566 exports against the latter's 1160, so it is the fuller authoring level rather than a reduced one, and the reduction in `Mountains_Map` is consistent with a cleanup pass. Both carry `Landscape`, `InstancedFoliageActor`, `SkyAtmosphere`, `VolumetricCloud`, `ExponentialHeightFog`, `DirectionalLight`, `SkyLight` and `PostProcessVolume`, so the terrain, the vegetation and the lighting are all present. The two substantive differences are that `Mountains_Map_LevelDesign` has no `PlayerStart`, which costs one placed actor, and that it has no GameMode Override, which is a benefit rather than a cost given §8.3. The cost is one editor session and the risk is that the level is visually not identical to what was previously flown.

The second is to recover the actor placement out of the 5.5 file by way of a 5.5 editor. Unreal's clipboard and its level export both use a text representation of actor properties, so actors copied in a 5.5 editor can be pasted into a 5.2 editor, and asset references by path survive because they are paths. This preserves the placement of every static mesh actor and every light. It does not preserve the landscape heightfield or the foliage instance arrays, for the reason given in §5.2, so the terrain must additionally be moved as exported heightmap and weightmap images and the foliage must be re-scattered from the procedural spawners of §5.3. The cost is a second engine installation and a careful reconstruction, and the benefit over the first route is fidelity to the level as last flown.

The third is to move the whole project to an engine whose own `AUTOMATIC_VERSION` reaches the file's package version, which is the only route that preserves the file exactly and, unlike the first four, is available against any future version combination and not merely this one. Weighed purely on the evidence available while `Mountains_Map.umap` was the only file in question, it was rejected rather than chosen. `README.md:92` of the submodule states that Project AirSim supports Unreal Engine 5.2 and 5.7 only, and `sitl_ws/src/ue5/ProjectAirSim/docs/development/dev_setup_linux.md:26,62` names the same pair, so 5.5 is not among the supported engines and the intermediate option does not exist. Moving to 5.7 abandons the argument of [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §2, namely that 5.2 is the version upstream's own release binaries are cut against and therefore the only one under which a prebuilt upstream release and a locally packaged game can both run. It also requires rebuilding the Unreal base image at the cost recorded in that file's §13, which is roughly 200 GB and four or more hours. And the plugin's private include paths reach into the engine's `Renderer/Private` and `Renderer/Internal` directories, per [`project-airsim-architecture.md`](project-airsim-architecture.md) §E.3, which is the hard coupling most likely to break across two minor versions and is now stretched across five, from 5.2 to 5.7.

This route has since been chosen, not for `Mountains_Map.umap` specifically but for the workspace's Unreal Engine pin as a whole, on the judgement that the cost recorded above is acceptable and the coupling risk is worth taking rather than continuing to route around it. §11 below gives the complete list of files this moved and the command sequence used to rebuild the image and verify StonePineForest under the new pin. Unreal Engine 5.7 writes package version 1018, read directly from `Engine/Source/Runtime/Core/Public/UObject/ObjectVersion.h` of branch `5.7` at commit `0bcfaffa52e9557258dbd388835ac7668fe864a4`, five past `Mountains_Map.umap`'s own 1013 rather than the four short that stops 5.2, so the file that motivated this whole document now opens without any of the five remedies above. StonePineForest continues to run `Mountains_Map_LevelDesign.umap` as of this writing, so adopting the 5.5 file remains optional rather than required by the pin change alone.

The fourth is to use one of the project's other maps unchanged. `GooseLand_Map.umap` at 1008, `Overview.umap` at 1008, `Showcase.umap` at 1004 and `Traditional_Map.umap` at 1004 all load in 5.2 today. This is the zero-cost route and it changes the environment rather than recovering it, so it serves as an immediate unblock for testing the rest of the stack while a decision is made on the first two.

The fifth is to author a new map. This is the right answer when the requirement is a scene designed for the perception task rather than a scene inherited from an asset pack, and §12.4 gives the procedure.

Whichever route is taken, three repairs are common to all of them and none is optional. The chosen map must carry a `PlayerStart` or an equivalent marker at the intended spawn point, so that the origin can be read reproducibly by the procedure of §12.7. Its World Settings GameMode Override must be set to `ProjectAirSimGameMode` or cleared, per §8.3. And `Config/DefaultEngine.ini` and `Config/DefaultGame.ini` must be repointed at the chosen map in all three of `EditorStartupMap`, `GameDefaultMap` and `MapsToCook`.

## 10. Learning checklists

Two checklists precede the procedures. The first is what to understand before touching an Unreal environment, and each item names the section of this document that covers it. The second is what to verify about any environment before adopting it.

### 10.1 Concepts to hold before beginning

- The package is the unit of persistence, a `.umap` is a package with a map flag, and the summary declares the format version. §2.2
- Two version integers exist, the Unreal Engine 5 one governs for anything modern, and newer reads older while older cannot read newer. §2.3
- A project is a `.uproject` plus `Config`, `Content` and `Source`, and the engine association is a declaration rather than an enforcement. §3.1
- Native code lives in modules described by C# build files, and the project must be a C++ project for the plugin to compile at packaging time. §3.2
- Plugin content mounts at a virtual root named after the plugin, which is what the cook directives refer to. §3.3
- The game mode decides what the player receives, and the per-map World Settings override outranks the project default. §4.2
- Project AirSim sets `DefaultPawnClass` to null and spawns robots from its own scene configuration, so the level's `PlayerStart` is a survey marker and not a spawn point. §4.3
- The spawn origin is in NED metres from the Unreal world origin, and the conversion negates the third component. §4.3 and §12.7
- Terrain is a `Landscape` actor whose heightfield is bulk binary data and does not survive a text export. §5.2
- Foliage is instanced, and the procedural foliage spawner is the tool that populates it. §5.3
- Ray-cast sensors see collision and cameras see render geometry, so a mesh with no collision is invisible to lidar and perfectly visible to a camera. §5.5 and §6.2
- Each enabled camera image type is an additional full scene render per frame, which usually sets the achievable rate. §6.2
- Cooking follows references, so anything not referenced must be named in `DirectoriesToAlwaysCook` or `MapsToCook`. §7.1
- A packaged game is bound to the engine version that produced it, for the same reason an asset is. §7.3

### 10.2 Audit to run against any environment before adopting it

- Decode every package's version and confirm none exceeds the target engine's `AUTOMATIC_VERSION`. §12.2
- Decode the import tables of the maps and confirm no reference to a plugin the project does not carry. §12.2
- Confirm whether the maps use World Partition, since that changes both the file layout and every migration procedure.
- Confirm the target files name build settings and include order enumerators that exist in the target engine. §3.2
- Confirm `EditorStartupMap`, `GameDefaultMap` and `MapsToCook` all name a map that exists and loads.
- Confirm the map carries a marker actor at the intended spawn point, and record the converted origin.
- Confirm the project carries no leftover packaged-game directory, since it survives the standard exclude list and costs gigabytes.

## 11. Migrating the workspace's Unreal Engine pin from 5.2 to 5.7

§9's third remedy has been chosen, not for `Mountains_Map.umap` alone but for the workspace's Unreal Engine pin as a whole. This section records what that move touched, found by the same method as the rest of this document, reading the tree and a fresh checkout of the target branch rather than assuming, and it is written so that a later reader auditing the workspace's current engine version, or reopening the question of a further version move, can do so from here without re-deriving it.

### 11.1 Why 5.7 clears the blocking version

Unreal Engine 5.7 writes package version 1018, read directly from `EUnrealEngineObjectUE5Version` in `Engine/Source/Runtime/Core/Public/UObject/ObjectVersion.h` of `EpicGames/UnrealEngine` branch `5.7` at commit `0bcfaffa52e9557258dbd388835ac7668fe864a4`, fetched by the same sparse-clone method §13 (below) already uses for reading engine source without a full clone. That ceiling is five past `Mountains_Map.umap`'s own 1013, rather than the four short that stops 5.2 at 1009 per §8.2, so the asymmetry rule of §2.3 resolves in 5.7's favour and the file that opened §8 now opens without any of the five remedies §9 ranks. The branch resolves exactly as `5.2` already does for this workspace, namely a release value containing one dot is treated as a branch name outright rather than having `-release` appended, confirmed against the remote by `git ls-remote --heads` returning a branch literally named `5.7` at that commit.

### 11.2 Changes to the Docker build chain

`docker/scripts/build_unreal.sh`'s default `UNREAL_ENGINE_RELEASE` moved from `"5.2"` to `"5.7"`, with its header comment reworded to match. Its default base image is no longer a single constant but a value derived from the release, because the correct tag turns out to differ by release rather than being fixed. Upstream's own `build.sh` pairs `nvidia/opengl:1.0-glvnd-devel-ubuntu18.04` with 5.2 and `nvidia/opengl:1.2-glvnd-devel-ubuntu22.04` with 5.7, and diffing the two branches' copies of that file shows they are byte-identical apart from precisely that one line, so every other line this workspace ported from it is valid against both branches. Neither upstream pairing is usable verbatim here, since Project AirSim requires a 22.04 userland whatever the engine version, so the script now selects `1.2-glvnd-devel-ubuntu22.04` by default and falls back to `1.0-glvnd-devel-ubuntu22.04` when the release is `5.2`, that being the pairing this workspace actually validated while pinned there and one upstream itself never ships. `UNREAL_BASE_IMAGE` continues to override whichever branch the conditional selects. Until 2026-08-12 this section stated the base image had simply moved to the `1.2` tag as a new constant, which was the plan's first reading and is wrong, because it would have silently rebuilt 5.2 on a tag that pairing was never tested against.

`docker/unreal/Dockerfile` could not simply be repointed at a new `GIT_BRANCH`, because Epic's own Dockerfile changed shape between 5.2 and 5.7, generated by a newer `ue4-docker` (0.0.114 against 5.2's 0.0.102). It was re-vendored from branch 5.7's own `Engine/Extras/Containers/Dockerfiles/linux/dev/Dockerfile` at the same commit, together with its sibling files `git-credential-helper-secrets.sh`, `set-changelist.py` and `split-components.py`, plus a new sibling, `print-editor-target.py`, that 5.2's vendoring never needed. Diffing the two upstream files found that the `ppa:slonopotamus/glibc-dso` layer this workspace's own "NRT delta 2" previously had to strip for Ubuntu 22.04 is gone from upstream entirely on 5.7, so that delta is now obsolete and was not reapplied, and that a Python 3.12 and `ushell` installation layer, a `ShaderCompileWorker`/`UnrealVersionSelector` build step in place of the old `UnrealHeaderTool` one, and a wider `split-components.py` split are all new upstream and were carried across unmodified. The re-vendored file carries five deliberate deviations from upstream, "NRT delta 3" through "NRT delta 7" below, and both of the two the 5.2 vendoring had are retired. "NRT delta 2", stripping the `ppa:slonopotamus/glibc-dso` layer, is retired because upstream removed that layer outright, as just described. "NRT delta 1", defaulting `ARG BASEIMAGE` to an Ubuntu 22.04 tag, is retired because the Dockerfile has exactly one caller in the tree, `build_unreal.sh`'s own `docker buildx build`, and that caller always passes `--build-arg BASEIMAGE` explicitly, so a Dockerfile-side default is dead in the only path that runs and would additionally contradict the per-release choice just described in any other. Upstream declares `ARG BASEIMAGE` bare on both branches, and `GIT_BRANCH` is bare on both for the same reason, which is the precedent this follows. Until 2026-08-12 this section stated that delta 1 survived with a bumped tag, which was the plan's first reading and is wrong for the reason just given. The vendored file was diffed against upstream after copying to confirm the body is byte-identical below the provenance header. `docker/airsim/Dockerfile:1-4`'s header comment, which names the engine version for a human reader's benefit only, was reworded from 5.2 to 5.7 to match, and needed no other change, since `ENV UE_ROOT`, its package lists and its `USER root`/`USER ue4` bracketing are all version-agnostic.

"NRT delta 3", added 2026-08-14, replaces upstream's `RUN ./Engine/Build/BatchFiles/Linux/Build.sh ShaderCompileWorker Linux Development -SkipBuild -buildubt` with `RUN ./Engine/Build/BatchFiles/BuildUBT.sh`, found necessary only once the image was actually built for the first time, which happened after this section was first written. `Build.sh`'s own `-buildubt` handling runs only `dotnet build Engine/Source/Programs/UnrealBuildTool/UnrealBuildTool.csproj -c Development -v quiet`, with no step that copies the compiled assembly anywhere, and the script's own next line unconditionally runs `dotnet Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll`, assuming that path is already populated. That assumption holds when a prebuilt `UnrealBuildTool.dll` already sits there to be refreshed in place, which is the normal case after a prior `GenerateProjectFiles.sh` run, but not on this Dockerfile's from-scratch clone, where nothing seeds one; `Engine/Build/BatchFiles/Linux/Setup.sh`, read at the same time, confirms it fetches no `GitDependencies` binaries on Linux, only the toolchain and third-party libs. The build failed here with `dotnet build` itself reporting zero errors, immediately followed by "Could not execute because the specified command or file was not found" against that `.dll` path. `Engine/Build/BatchFiles/BuildUBT.sh`, the script `GenerateProjectFiles.sh` itself uses for the identical purpose, runs `dotnet build` followed by `dotnet publish --output ../Binaries/DotNET/UnrealBuildTool --no-build`, which is what actually places the assembly at the path every later step expects, and takes no target/platform/configuration arguments to reproduce, since its job is narrower than `Build.sh`'s. Both scripts were read directly from `EpicGames/UnrealEngine` branch `5.7` at this file's own pinned commit to confirm the discrepancy before making the change. Until 2026-08-14 this section and the Dockerfile's own header both stated the file carried zero deltas from upstream; that was correct for the file as vendored and stopped being correct once this delta was added in response to the build failure just described.

"NRT delta 4", added 2026-08-14 in the same session as delta 3, changes `-set:WithServer=true` to `-set:WithServer=false` in the `RunUAT.sh BuildGraph -target="Make Installed Build Linux"` step, found once the previous build failure was fixed and the build reached that step for the first time. `WithServer`'s own declaration in `Engine/Build/InstalledEngineBuild.xml:72` reads `Restrict="true|false" DefaultValue="false" Description="Include precompiled server targets"`, so `true` is not upstream's own default, it is ue4-docker's generic template choice, carried into this Dockerfile unexamined during the 5.2 vendoring and never revisited. With it `true`, `InstalledEngineBuild.xml:148` adds `UnrealServer` as a build target, and that target's own dependency walk instantiates `Engine/Source/ThirdParty/Intel/oneAPILevelZero/oneAPILevelZero.Build.cs`, whose constructor contains, verbatim, `if (Target.Type == TargetType.Server) { ... throw new BuildException(string.Format("{0} dedicated server is made to depend on {1}. We want to avoid this, please correct module dependencies.", ...)); }` for any Unix platform group member, a deliberate refusal by Epic's own design, since a headless dedicated server has no GPU context to query. That module is reached at all because `Engine/Plugins/Runtime/ExternalGPUStatistics/Source/ExternalGPUStatistics/ExternalGPUStatistics.Build.cs` adds both `oneAPILevelZero` and `NVML` for any Unix platform unconditionally, with no `Target.Type` guard of its own, an omission the plugin's `.uplugin` does not cover either, since `TargetConfigurationDenyList: [ "Shipping" ]` restricts by build configuration, not by target type, so it does not stop the plugin being considered for a Server target in any configuration. The plugin is `EnabledByDefault: false` and is not part of any target's normal module set, so this surfaces only when the Installed Build's own makefile generation for `UnrealServer` walks the full plugin list to precompile everything a downstream project might enable, which is precisely what `WithServer=true` asks for. `RunUAT`'s own log confirmed the mechanism before the fix, `dotnet build` for `UnrealClient` completing with zero errors followed immediately by `UnrealServer`'s makefile generation raising the quoted exception and exiting `RulesError`. Project AirSim never builds a Server-type target, only `Client` via `BuildCookRun -clientconfig=` in `sitl_ws/scripts/build_airsim2_game.sh`, so `WithServer=false` costs this workspace no capability it uses. Patching `ExternalGPUStatistics.Build.cs` to add the missing guard, mirroring `oneAPILevelZero.Build.cs`'s own, was considered and rejected as a larger and less certain change, since it edits third-party plugin source inside the freshly cloned engine tree rather than a single BuildGraph flag, for a target type this workspace does not use regardless. Both files were read directly from `EpicGames/UnrealEngine` branch `5.7` at this file's own pinned commit to confirm the mechanism before making the change. See `plans/unreal-engine-packaging.md`'s build-failures section for the full log excerpts.

"NRT delta 5", added 2026-08-14 in the same session as deltas 3, 4 and 6, disables the `NDIMedia` plugin entry inside the freshly cloned `Templates/TP_MotionDesignBP/TP_MotionDesignBP.uproject` immediately before the Installed Build step runs, found once delta 4's fix let the build reach `DerivedDataCache` generation for the first time. `Engine/Plugins/Media/NDIMedia/NDIMedia.uplugin` declares `"EnabledByDefault": false`, but `TP_MotionDesignBP.uproject`'s own `Plugins` array re-enables it explicitly, with `"SupportedTargetPlatforms": ["Win64"]` on that one entry even though the plugin's own `PlatformAllowList` still names `Linux`, so Epic's own project metadata already signals the plugin is not meant for this platform even as nothing in the editor's module loading actually honours that per-project hint. `Engine/Plugins/Media/NDIMedia/Source/NDIMedia/Private/NDIMediaModule.cpp`'s `StartupModule()` and the constructor of its `FNDIMediaRuntimeLibrary` helper both unconditionally attempt to `dlopen` `libndi.so.6`, and the public engine source vendors only `Binaries/ThirdParty/Linux/libndi_licenses.txt`, not the proprietary NDI SDK redistributable itself, since NewTek and Vizrt's own SDK licence does not permit Epic to ship it in the public git tree. The failed load logs two `UE_LOG(LogNDIMedia, Error, ...)` calls, and `Engine/Source/Runtime/Launch/Private/LaunchEngineLoop.cpp:4161` reads `if (!Commandlet->UseCommandletResultAsExitCode) { if ((ErrorLevel == 0) && (GWarn->GetNumErrors() > 0)) { ErrorLevel = 1; } }`, so any error logged during a commandlet run forces the editor process's own exit code to 1 even when the commandlet's actual task, in this case the DDC build itself, fully succeeds, and that nonzero exit is what aborts the whole `BuildDerivedDataCache` BuildGraph node. `Engine/Build/InstalledEngineFilters.xml`'s `ProjectsToBuildDDC` list was checked against every project it names, and `TP_MotionDesignBP` is the only one whose `.uproject` enables `NDIMedia`, and no plugin the template also enables, including `Avalanche` and its siblings, declares `NDIMedia` as a dependency of its own, so disabling the one entry is scoped to exactly the project that needs it and changes nothing else the template or any other listed project builds. Installing the actual proprietary NDI SDK library was considered and rejected, since it would bind the image to a second EULA beyond Epic's own for a broadcast video protocol Project AirSim never uses. Both files were read directly from `EpicGames/UnrealEngine` branch `5.7` at this file's own pinned commit to confirm the mechanism before making the change. See `plans/unreal-engine-packaging.md`'s build-failures section for the full log excerpts.

"NRT delta 6", added 2026-08-14 in the same session, adds `libavahi-common3` to the X11 runtime library layer that upstream installs for CEF, since the same `DerivedDataCache` run that logged delta 5's `NDIMedia` errors also logged `LogCore: Warning: dlopen failed: libavahi-common.so.3: cannot open shared object file`. That line is a warning rather than an error, so it does not itself trip the exit code mechanism delta 5 describes, but the package it names is a genuine, freely apt installable Ubuntu library, unlike the NDI SDK, so adding it costs nothing and removes the last blemish from an otherwise clean build log. The likely source is `PixelStreaming`, also enabled by `TP_MotionDesignBP.uproject`, whose vendored WebRTC stack optionally resolves local mDNS hostnames through `libavahi-client` and `libavahi-common` on Linux as a privacy feature for ICE candidate exchange, but this was not traced to an exact call site the way delta 5's `NDIMedia` failure was, since doing so would require checking out and searching the full WebRTC third party source tree for a warning that does not block the build, so it is recorded here as the most plausible explanation available rather than a confirmed one. See `plans/unreal-engine-packaging.md`'s build-failures section for the full log excerpts.

"NRT delta 7", added 2026-08-15, hardcodes the generated `nvidia_icd.json`'s `api_version` field to `1.4.312` rather than deriving it from the apt `libvulkan1` package's own version, found once the host NVIDIA driver was upgraded to `580.173.02` (`plans/update-nvidia-driver.md`) to close the extension gap of `context/project-airsim-docker-build.md` §16, and the packaged client still failed identically, `LogVulkanRHI: Warning: None of the 1 devices meet all the criteria!`. `dpkg -s libvulkan1 | grep -oP 'Version: [0-9|\.]+'`, the upstream expression this workspace inherited unmodified, reads the SYSTEM Vulkan loader package's own instance version, `1.3.204` on this Ubuntu 22.04 base regardless of GPU or driver, not any driver capability, a fact obscured before now because the two numbers happened to look similar against the pre-upgrade driver. `VK_LOADER_DEBUG=all` against the actual packaged client's launch showed the real cause directly: UE 5.7 uses its own bundled Vulkan loader, `Engine/Binaries/ThirdParty/Vulkan/Linux`, a private copy distinct from the system one and confirmed by its own `LogVulkanRHI: Display: Using included Vulkan loader.` log line, and that loader's manifest parser unconditionally rejects any ICD JSON missing the `api_version` field outright, `loader_parse_icd_manifest: ICD JSON /etc/vulkan/icd.d/nvidia_icd.json does not have an 'api_version' field. Skipping ICD JSON.`, confirmed against this exact image after the field was briefly removed as an intermediate diagnostic step and produced exactly this warning. With NVIDIA's ICD unconditionally skipped this way, the loader's remaining candidates, per the same trace, resolve to nothing usable, `VirtIO` fails `vkCreateInstance` outright with no virtual GPU present, `Intel`, `Intel HASVK` and `RADV` are each removed for enumerating zero physical devices since none of that hardware exists on this NVIDIA-only host, leaving Mesa's `llvmpipe` software rasterizer as the sole surviving device, which is the `1 devices` the warning names and which fails every criterion of `VP_UE_Vulkan_SM6` outright, being a CPU-type software implementation. The apt-derived value was not itself absent before this delta, so the "field must be present" requirement had always been silently satisfied by an unrelated number, which is why this defect was invisible until the field was experimentally removed while investigating a separate issue. `1.4.312`, NVIDIA driver `580.173.02`'s own real `apiVersion` as reported by `vulkaninfo`, was confirmed by a live run to satisfy `VP_UE_Vulkan_SM6`'s device enumeration once declared, admitting the real NVIDIA device and passing every one of the profile's fifteen required extensions, already independently confirmed present in `context/project-airsim-docker-build.md` §16. Deriving this value correctly at image build time is not possible regardless of method, since the NVIDIA Container Toolkit mounts the host's actual driver only at container start, never during the build, so the value is hardcoded on the deliberate understanding, stated by the workspace owner, that this image is used with driver 580 only; a future driver change would need this value revisited only if a newer engine's own Vulkan profile ever demands more than `1.4.312`, since the field acts as a version floor the loader gates on rather than an exact-match requirement. Full analysis in `plans/update-nvidia-driver.md` and `context/project-airsim-docker-build.md` §17.

A fourth build attempt, after deltas 5 and 6, ran the entire `builder` stage clean, over two hours, and then failed twice in the final `minimal` stage with `Error: [Errno 28] No space left on device` provisioning `ushell`'s Python virtual environment, followed by `Unhandled exception: IOException: The system cannot open the device or file specified.` naming a `Global\UnrealBuildTool_Mutex_XmlConfig_...` mutex out of `UnrealBuildBase.GlobalSingleInstanceMutex..ctor`. This is not a Dockerfile delta at all, since neither failure is a code defect; the host disk backing both Docker's data root and `$NRT_WS` genuinely ran out of space, confirmed independently by `scripts/helpers/data.sh:18`'s own `save_state` trap, a plain host-side `bash` redirect with no Docker or Unreal code in the path, failing on the identical OS-level `ENOSPC` moments later. The mutex error is the same root cause wearing a misleading message rather than a second bug: `GlobalSingleInstanceMutex.cs:28`'s `new Mutex(true, mutexName, out bCreatedMutex)` is, on Linux CoreCLR, backed by a real shared-memory segment and lock file under `/tmp/.dotnet-uid<uid>/` rather than a pure kernel object as on Windows, so named-mutex creation is itself a filesystem write that fails under `ENOSPC`, and .NET's Unix exception translation for that path has no bespoke "No space left on device" text, falling back instead to the generic `IOException` string seen here, a documented pattern in unrelated `dotnet/runtime` (`dotnet/coreclr#3422`) and `PowerShell/PSReadLine` (`#1464`) issues under comparably full or restricted filesystems. `GlobalSingleInstanceMutex.cs` was read directly from `EpicGames/UnrealEngine` branch `5.7` at this file's own pinned commit to confirm the constructor call before accepting this explanation. The likely mechanism is BuildKit's build cache compounding across the four iterative attempts this session actually took, rather than the roughly 200 GB single-build figure in `context/project-airsim-docker-build.md` §13 being wrong, since each Dockerfile edit (deltas 3 through 6) invalidates cache from that line forward without evicting the now-unreachable layers cached under the pre-edit content hash, leaving several large, superseded copies of the engine tree on disk at once; `docker builder prune` between iterative attempts is the recommended practice going forward. See `plans/unreal-engine-packaging.md` §7.4 for the full log excerpts and remediation steps.

### 11.3 Changes to the Project AirSim project and plugin

`unreal/StonePineForest/StonePineForest.uproject:3`'s `EngineAssociation` moved from `"5.2"` to `"5.7"` for accuracy, though §3.1 already establishes this field is a declaration read by the launcher rather than an enforced constraint, so the build would have succeeded either way.

The one change neither the request nor §9 named, found only by tracing what actually compiles the plugin, is that `SimLibs`, the project's own compiled static archives (`core_sim`, `simserver`, `physics`, `rendering_scene`, `multirotor_api`, `rover_api`, `mavlinkcom` and the rest), are built by `unreal-linux-toolchain.cmake` against the engine's own bundled Clang and libc++ under `$UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64`, and that bundle differs materially between the two engine versions, `v21_clang-15.0.1-centos7` for 5.2 against `v26_clang-20.1.8-rockylinux8` for 5.7, a five-major-version Clang jump across which a static archive is not a supported link input for object code compiled by the other side of it. `build_airsim2_game.sh:24-26`'s existence guard, and every target of `build_linux.mk` that produces or consumes `SimLibs`, name only `unreal/Blocks/Plugins/ProjectAirSim/SimLibs`, and §10 (above) already records that StonePineForest's own copy is a point-in-time copy made when the environment was ported onto the plugin, so the migration requires deleting both copies, rebuilding Blocks's copy against the new engine, and re-copying it into StonePineForest before StonePineForest is packaged again. `Drone` and `Rover` carry no compiled code and needed no equivalent refresh.

Because that hazard recurs on every future engine-version change rather than only this one, it was automated rather than hand-run. `scripts/helpers/sitl.sh` gained three functions, `list_projectairsim_games`, which enumerates the supported environments by listing `unreal/` rather than hardcoding them, so adding a game needs no edit anywhere, `clean_projectairsim_build_artefacts`, which runs the project's own `build.sh clean` and then removes `Binaries`, `Intermediate`, `Saved`, `Build`, the per-game plugin `SimLibs` and the staged package for every game, and `copy_projectairsim_plugin_to_games`, which refreshes every non-Blocks game's `ProjectAirSim`, `Drone` and `Rover` plugin copies from Blocks's, excluding `Binaries` and `Intermediate` exactly as `build_linux.mk`'s own `package_plugin` target does. Each takes the workspace root as its first argument rather than reading `$NRT_WS`, because they run both from `djinn` on the host, where that variable is set, and from `build_airsim2_game.sh` inside `airsim2_container`, where it is not, since `sitl_ws/scripts/start.sh` passes no `-e NRT_WS`; `/ws` and `$NRT_WS` name the same bind-mounted tree, so one parameterised implementation serves both. `build_airsim2_game.sh` now takes a third argument, `rebuild_plugin`, defaulting to `false`, and runs those three in order when it is `true`, replacing the previous guard that merely tested whether Blocks's `SimLibs` directory existed, a test that could not distinguish a directory built against a different engine from one that never needed rebuilding. It also validates its project argument against `list_projectairsim_games` rather than a hardcoded `case` arm.

The plugin's private include paths reaching into the engine's `Renderer/Private` and, on Linux, `Renderer/Internal` (`ProjectAirSim.Build.cs:36,90`), the coupling §9 already named as the reason this route was originally rejected, is carried forward unresolved rather than mitigated. `Engine/Source/Runtime/Renderer/` under 5.2 contains only `Private`, `Public` and `Renderer.Build.cs`, while the same directory under 5.7 additionally contains a populated `Internal` of 21 files, so the Linux build path's existing (and previously inert, since the directory did not exist) reference to `Renderer/Internal` can now resolve, which can only add headers relative to today rather than remove any. Whether anything the plugin's own `.cpp` files include from `Renderer/Private` moved or changed shape across five minor versions cannot be settled by source inspection alone, and the first evidence either way is a compiler error naming a missing header during the rebuild of §11.4, should one occur.

### 11.4 Rebuilding and testing

The existing image tag is reused rather than versioned, so the engine rebuild must be forced or `build_unreal.sh`'s own existence guard silently keeps serving the stale 5.2 image under the same name. That force is a rebuild-mode value on `djinn`'s fourth positional argument rather than an environment variable the caller has to export beforehand, `djinn init docker airsim2 force-all`. `$4` selects among three modes, `force-all` forces the engine rebuild unconditionally and then builds the wrapper, `rebuild-base` runs the engine build script but leaves its own existence guard in charge of whether anything actually rebuilds, and any other value, including the empty string, skips the engine build entirely and rebuilds only the wrapper; `$5`, read only when `$4` is non-empty, is the base-image override. The whole sequence is four `djinn` invocations, with no raw `docker exec` step, which is the point of the automation recorded in §11.3. Until 2026-08-14 this paragraph described `$4` itself as the base-image override, with the empty string in the command below read as a placeholder occupying that position, which was already inconsistent with the command it introduced and is superseded by the mode selector above; the full argument catalogue is in [`djinn-workflows.md`](djinn-workflows.md).

```bash
djinn init docker airsim2 force-all
djinn up airsim2
djinn build airsim2 StonePineForest Development true
djinn start sitl2
```

The third command is where the artefact hazard is discharged, since its trailing `true` is the `rebuild_plugin` flag that cleans every game's build products, rebuilds Blocks's `SimLibs` against the new engine and refreshes every other game's plugin copy before packaging. `djinn build airsim2` also now forwards its project, configuration and flag arguments through to `build_airsim2_game.sh` in that order, where previously the second positional slot was a truthy gate whose value was discarded and the configuration could not be set through `djinn` at all.

The last command is verified exactly as §12.9 (below) already prescribes, namely that the cook log names `StonePineForest` with no missing `/Drone` or `/Rover` content, that the run log carries no `is too new` warning and no failed import of `/Script/AirSim`, that ports 8989 and 8990 are bound, and that the vehicle spawns at a stable altitude on `Mountains_Map_LevelDesign.umap` rather than falling or intersecting terrain, after which `djinn kill sitl2` and `djinn down airsim2` tear the stack back down. The full command-by-command rationale, including the disk-space precondition and the pre-copy divergence check between the two `Plugins/ProjectAirSim/Source` trees, is `plans/unreal-engine-packaging.md` §4, the plan this section implements.

## 12. Procedures

Every command below runs inside the Project AirSim container unless stated otherwise. The container is started by `djinn up airsim2` and entered by `docker exec -it -u ue4 airsim2_container bash`, and the `ue4` user is mandatory for the reasons in [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §4.

### 12.1 Open the editor, and diagnose a failure to open

```bash
djinn up airsim2
docker exec -it -u ue4 airsim2_container bash

xdpyinfo | head -3          # the display, before blaming the editor
vulkaninfo --summary | head -20   # Vulkan, or the editor starts and renders nothing

$UE_ROOT/Engine/Binaries/Linux/UnrealEditor \
  /ws/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/StonePineForest.uproject
```

The first open of a project with a C++ module offers to rebuild that module and the offer must be accepted. When the editor starts but the level does not appear, the answer is in `unreal/<Project>/Saved/Logs/<Project>.log`, and the two lines worth grepping first are `from an engine release newer than this` and `is too new`.

### 12.2 Audit package versions without the editor

The engine cannot decode a package it refuses to open, so the audit is done outside it, directly against the summary. The script below is the one used to produce §8.1 and it is reproduced in full because it is the only tool that answers the question cheaply.

The field order it implements is the one `PackageFileSummary.cpp:218-330` serialises, and every optional field is guarded on the same enumerator the engine guards it on. Those guards are the whole difficulty of writing this correctly, since a single misjudged threshold silently misaligns the stream and yields a plausible-looking wrong answer rather than an exception. The constants below were verified empirically, by requiring that all 910 packages of this project, spanning Unreal Engine 4.5 to 5.5, parse without a single error.

```python
import struct, sys, os

# Enumerator values of EUnrealEngineObjectUE4Version, from
# Engine/Source/Runtime/Core/Public/UObject/ObjectVersion.h of branch 5.2.
ENGINE_VERSION_OBJECT    = 336
STRING_ASSET_REFS_MAP    = 384
HAS_COMPATIBLE_VERSION   = 444
SERIALIZE_TEXT_IN_PKGS   = 459
ADDED_SEARCHABLE_NAMES   = 510
ADDED_LOCALIZATION_ID    = 516
ADDED_PACKAGE_OWNER      = 518
NON_OUTER_PACKAGE_IMPORT = 520
ADD_SOFTOBJECTPATH_LIST  = 1008
PKG_FILTER_EDITOR_ONLY   = 0x80000000

def rd(f, fmt): return struct.unpack(fmt, f.read(struct.calcsize(fmt)))

def rdstr(f):
    (n,) = rd(f, '<i')
    if n == 0: return ''
    if n < 0:  return f.read(-n * 2).decode('utf-16-le', 'replace').rstrip('\0')
    return f.read(n).decode('latin-1').rstrip('\0')

def engine_version(f):
    maj, mi, pa, cl = rd(f, '<HHHI')
    return f'{maj}.{mi}.{pa} cl={cl} branch={rdstr(f)}'

def summary(path):
    with open(path, 'rb') as f:
        (tag,) = rd(f, '<I')
        if tag != 0x9E2A83C1: raise ValueError(f'not a UE package: {hex(tag)}')
        (legacy,) = rd(f, '<i')
        if legacy != -4: rd(f, '<i')                  # LegacyUE3Version
        (u4,) = rd(f, '<i')
        u5 = rd(f, '<i')[0] if legacy <= -8 else 0
        rd(f, '<i')                                   # FileVersionLicenseeUE4
        if legacy <= -2:
            (n,) = rd(f, '<i'); f.read(n * 20)        # custom versions
        rd(f, '<i'); rdstr(f)                         # TotalHeaderSize, PackageName
        (flags,) = rd(f, '<I')
        rd(f, '<ii')                                  # NameCount, NameOffset
        if u5 >= ADD_SOFTOBJECTPATH_LIST: rd(f, '<ii')
        editor_data = not (flags & PKG_FILTER_EDITOR_ONLY)
        if editor_data and u4 >= ADDED_LOCALIZATION_ID: rdstr(f)
        if u4 >= SERIALIZE_TEXT_IN_PKGS: rd(f, '<ii')
        rd(f, '<ii'); rd(f, '<ii'); rd(f, '<i')       # Export, Import, Depends
        if u4 >= STRING_ASSET_REFS_MAP: rd(f, '<ii')
        if u4 >= ADDED_SEARCHABLE_NAMES: rd(f, '<i')
        rd(f, '<i'); f.read(16)                       # ThumbnailTable, Guid
        if editor_data:
            if u4 >= ADDED_PACKAGE_OWNER: f.read(16)  # PersistentGuid
            if ADDED_PACKAGE_OWNER <= u4 < NON_OUTER_PACKAGE_IMPORT:
                f.read(16)                            # OwnerPersistentGuid
        (gens,) = rd(f, '<i'); f.read(gens * 8)
        saved  = engine_version(f) if u4 >= ENGINE_VERSION_OBJECT else 'n/a'
        compat = engine_version(f) if u4 >= HAS_COMPATIBLE_VERSION else 'n/a'
        return u4, u5, saved, compat

TARGET = 1009  # Unreal Engine 5.2 AUTOMATIC_VERSION
for root, _, files in os.walk(sys.argv[1]):
    for name in sorted(files):
        if not name.endswith(('.uasset', '.umap')): continue
        path = os.path.join(root, name)
        try:
            u4, u5, saved, compat = summary(path)
        except Exception as exc:
            print(f'ERROR {path}: {exc}'); continue
        flag = '  <-- TOO NEW' if u5 > TARGET else ''
        print(f'{path}  UE4={u4} UE5={u5} saved={saved}{flag}')
```

Run it and filter, remembering that binary strings can appear in the output so `grep -a` is required. Zero errors is part of the expected result, since an error means the parse desynchronised and the versions it did print cannot be trusted.

```bash
cd /ws/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest
python3 audit_packages.py Content  > /tmp/audit.txt 2>&1
python3 audit_packages.py Plugins >> /tmp/audit.txt 2>&1

grep -ac 'UE4='   /tmp/audit.txt   # packages parsed, expect 910 for this project
grep -ac ERROR    /tmp/audit.txt   # must be 0
grep -a  'TOO NEW' /tmp/audit.txt
grep -aoE 'UE5=[0-9]+ saved=[0-9.]+' /tmp/audit.txt | sort | uniq -c | sort -rn
```

One trap attends recomputing those eight constants from the header rather than copying them. `EUnrealEngineObjectUE4Version` assigns an explicit value only to its first member, `VER_UE4_OLDEST_LOADABLE_PACKAGE = 214`, and every subsequent value is implicit, so the enumerators must be counted. One member of that enumeration is spelled `VAR_UE4_ARRAY_PROPERTY_INNER_TAGS` rather than `VER_UE4_`, a typographical error in Epic's own header, and a script that counts members by matching the `VER_UE4_` prefix silently skips it and computes every subsequent value one too low. The check that catches it is that `VER_UE4_AUTOMATIC_VERSION` must come out at 522, which is the value the editor reports as `Cur:v522` in the diagnostic of §8.1.

The engine's own equivalent, for packages it can read, is the resave commandlet in its reporting mode, and it is useful for confirming that nothing older than the engine needs upgrading.

```bash
$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd \
  /ws/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/StonePineForest.uproject \
  -run=ResavePackages -unattended -nullrhi
```

Note the direction. `UResavePackagesCommandlet` defaults `MaxResaveUEVersion` to one below the running engine at `ContentCommandlets.cpp:464`, so it upgrades and never downgrades, and it will not touch the offending map.

### 12.3 Recover the map, route one, adopt the 5.1 sibling

```bash
$UE_ROOT/Engine/Binaries/Linux/UnrealEditor \
  /ws/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/StonePineForest.uproject
```

In the editor, open `Content/StonePineForest/Maps/Mountains_Map_LevelDesign`. Then, in order, do the following.

Open Window then World Settings, find GameMode Override under the Game Mode category, and set it to `ProjectAirSimGameMode`. Confirm it is not left at `AirSimGameMode` or `None`.

Drag a `PlayerStart` from the Place Actors panel onto the terrain at the point the vehicle should begin. The editor snaps it to the surface. Any actor serves if a `PlayerStart` is unwanted and an empty Actor is the lightest choice.

Save the level under a new name, for instance `Mountains_Map_UE52`, with File then Save Current Level As, so that neither original is overwritten and both remain available for comparison.

Then edit the two ini files outside the editor.

```ini
# Config/DefaultEngine.ini
[/Script/EngineSettings.GameMapsSettings]
EditorStartupMap=/Game/StonePineForest/Maps/Mountains_Map_UE52
GameDefaultMap=/Game/StonePineForest/Maps/Mountains_Map_UE52
GlobalDefaultGameMode=/Script/ProjectAirSim.ProjectAirSimGameMode
```

```ini
# Config/DefaultGame.ini
[/Script/UnrealEd.ProjectPackagingSettings]
+DirectoriesToAlwaysCook=(Path="/ProjectAirSim")
+DirectoriesToAlwaysCook=(Path="/Drone")
+DirectoriesToAlwaysCook=(Path="/Rover")
+MapsToCook=(FilePath="/Game/StonePineForest/Maps/Mountains_Map_UE52")
```

Finally, remove `Mountains_Map.umap` from the cook path, which the `MapsToCook` edit already does, and consider moving the file out of `Content` altogether so that the asset registry stops warning about it on every editor start. Keep it, since it is the only copy of that level's last authored state and route two depends on it.

### 12.4 Author a new environment from an empty level

The following is the full sequence for a scene built rather than inherited, and it is also the reference for what route one is reproducing.

Create the level with File then New Level, choosing Basic rather than Empty so that the sky, the directional light, the sky atmosphere and the fog arrive already configured.

Add terrain by switching to Landscape mode in the mode dropdown. Either sculpt with the brush tools, or select Import from File and supply a 16-bit heightmap, setting the section size and the component count to match the world extent required. Assign a landscape material, and for a natural environment take `Content/StonePineForest/Materials/LandscapeMaterials/` as the model, since its layer structure already matches the project's texture set. Paint layer weights in the Paint tab.

Populate the terrain by placing a Procedural Foliage Volume, assigning one of the spawners from `Content/StonePineForest/WorldSpawner/`, resizing the volume over the region to be forested, and pressing Resimulate. The result is written into the level as foliage instances. For manual control, use Foliage mode instead and paint instances of individual foliage types directly.

Place static geometry by dragging static meshes from the content browser into the viewport. For a family of similar props, prefer a Blueprint actor parameterised by a data table, following the `CustomSign` pattern of §5.1.

Add moving elements as Project AirSim environment actors declared in the scene configuration, per §5.4, rather than as level-placed animated actors, whenever the motion must be reproducible.

Set the World Settings GameMode Override to `ProjectAirSimGameMode`.

Place a `PlayerStart` at the intended vehicle origin.

Save the level under `Content/<Project>/Maps/`, and repoint the two ini files as in §12.3.

### 12.5 Import a new asset

Drag the source file into the content browser, or use its Import button, and then attend to the three settings of §5.5. For a mesh, open the static mesh asset and set Collision Complexity to `Use Complex Collision As Simple` if the geometry must be sensed accurately by ray-cast sensors, and verify the import scale against a known dimension in the scene, remembering that the engine unit is the centimetre. For a normal map or a packed mask texture, set the compression settings to `Normalmap` or `Masks` respectively rather than leaving the default colour compression. For a heightmap, import through Landscape mode rather than the content browser.

Any asset that is to appear in the packaged game must be reachable from a cooked map, or its directory must be named in `DirectoriesToAlwaysCook`.

### 12.6 Set the per-map game mode without the editor

There is no text route. `AWorldSettings` is an export inside the binary map package and its GameMode Override is a hard class reference recorded in the import table, which is why §8.3 could detect the wrong value by decoding the package and why correcting it requires the editor. The `GlobalDefaultGameMode` setting in `DefaultEngine.ini` is sufficient for a packaged headless run when the map carries no override at all, which is the case for every map in this project except `Mountains_Map`.

### 12.7 Read the spawn origin

Unreal world coordinates are centimetres in a north, east, up frame, and the simulator's origin is metres in north, east, down. The conversion, derived in [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §11.1 from `UnrealTransforms.h:16-23` and `transform_utils.cpp:91-93`, is the following.

```
north =  UnrealX / 100
east  =  UnrealY / 100
down  = -UnrealZ / 100
```

The reproducible route is the headless commandlet, which prints the converted numbers for every `PlayerStart` in the map.

```bash
$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd \
  /ws/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/StonePineForest.uproject \
  -run=pythonscript -script="/ws/sitl_ws/scripts/print_spawn_origin.py" -unattended -nullrhi
```

Write the three numbers into `sitl_ws/config/airsim2/scene_ardu_copter.jsonc`, subtracting a further one to two metres from the down component so that the vehicle starts just above the surface, and keep `start-landed` true so that it holds position until thrust exceeds weight.

```jsonc
"origin": {
  "xyz": "125.0 -34.0 -82.0",
  "rpy-deg": "0 0 0"
},
"start-landed": true
```

Two cross-checks cost nothing. The down component must be negative for any point above the Unreal world origin, so a positive value on a mountainous map is almost always a forgotten sign. And the magnitude of north and east is the horizontal distance in metres from `home-geo-point`, so a value of several kilometres is worth recognising rather than debugging.

### 12.8 Package and run

```bash
docker exec -it -u ue4 airsim2_container bash
/ws/sitl_ws/scripts/build_airsim2_game.sh StonePineForest Development
```

The script builds the simulation libraries first when `Plugins/ProjectAirSim/SimLibs` is absent, then runs the `BuildCookRun` of §7.2, then makes the staged executable executable. The archive lands in `packages/StonePineForest/Development/Linux/`. Run it with `sitl_ws/scripts/run_airsim.sh airsim2`, or start the whole stack with `djinn start sitl2`, both catalogued in [`djinn-workflows.md`](djinn-workflows.md).

### 12.9 Verify

After packaging, confirm in order that the cook log names the chosen map and reports no missing `/Drone` or `/Rover` content, that the packaged run's log contains no `is too new` warning and no failed import of `/Script/AirSim`, that the simulation server binds the topic and service ports 8989 and 8990, that a client can load the scene, and that the vehicle appears at the intended altitude rather than falling or intersecting terrain. A vehicle that never reports a stable altitude and therefore never arms is the standard symptom of a wrong spawn origin.

## 13. The engine source checkout

`sitl_ws/src/ue5/UnrealEngine` is a submodule added on 2026-08-05 for reference reading, pinned to branch 5.2 at commit `02dc8dbd`, registered in `.gitmodules` under the name `UnrealEngine` with `shallow = true`. It is a blobless sparse checkout and occupies 90 MB rather than the tens of gigabytes a full clone costs, and the sparse set covers the object model, the asset registry, the editor's private sources, the batch files and the engine configuration.

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch 5.2 --filter=blob:none --sparse --no-tags \
  git@github.com:EpicGames/UnrealEngine.git UnrealEngine
cd UnrealEngine && git sparse-checkout set \
  Engine/Source/Runtime/Core/Public/UObject Engine/Source/Runtime/Core/Private/UObject \
  Engine/Source/Runtime/CoreUObject/Public/UObject Engine/Source/Runtime/CoreUObject/Private/UObject \
  Engine/Source/Runtime/AssetRegistry Engine/Source/Runtime/Engine/Classes/GameFramework \
  Engine/Source/Editor/UnrealEd/Private Engine/Build/BatchFiles Engine/Config
```

Two constraints attach to it. The repository is behind Epic's licence gate, so access requires a GitHub account linked to an Epic account, which this workspace has and which [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §4 already relied upon. And it is a reference checkout and not a build tree, so it must not be confused with the engine inside `shandilya1998/nrt:unreal`, which is a full Installed Build compiled by the procedure of that file's §13. Adding another sparse path is a one-line `git sparse-checkout add`, and comparing against a later release costs one `git fetch --depth 1 --filter=blob:none origin <branch>` followed by `git show FETCH_HEAD:<path>`, which is exactly how the 5.5 enumeration of §8.2 was obtained without a second checkout.

This does not contradict the decision recorded in [`project-airsim-docker-build.md`](project-airsim-docker-build.md) §13 against carrying an engine submodule. That decision concerned the Docker build context, where Epic's own Dockerfile clones the engine inside the image from `GIT_REPO` and `GIT_BRANCH`, so a submodule would have contributed gigabytes that no build step reads. The present checkout serves reading rather than building, costs 90 MB, and no build step consumes it.

## 14. Conclusion

The failure that prompted this document is narrow and its diagnosis is complete. One file among nine hundred and ten, the project's startup map, was re-saved by an Unreal Engine 5.5 editor and thereby written in a package format four increments beyond what Unreal Engine 5.2 can parse, and because three of those four increments alter the export table layout or the property tag encoding, no partial recovery is possible and the engine correctly refuses at the summary. The same file carries a second, unrelated defect, a per-map game mode override still pointing at the Cosys-AirSim plugin that the port removed, and the two together identify the file's provenance precisely as an environment adapted for Cosys-AirSim inside that stack's Unreal Engine 5.5 container.

The general lesson is larger than the instance. An Unreal package records the engine that wrote it and the compatibility relation runs in exactly one direction, so an environment acquired from any third party carries a version floor that no configuration change can lower, and the only defences are to audit the packages before adopting the environment and to control which editor is ever permitted to open them. The audit costs one script and a few seconds, and running it at acquisition would have surfaced this in advance of the port rather than after it.

The recommended remedy is to adopt `Mountains_Map_LevelDesign.umap`, which is the same environment at package version 1008, carries the terrain, the vegetation and the lighting, and needs only a game mode override, a spawn marker and three ini edits. The 5.5 file should be retained, because it is the only record of the level as last flown and it is the source for a higher-fidelity recovery should the visual difference prove to matter.

Beyond the immediate repair, the material assembled here is the working knowledge an environment author needs, namely what a package is and how it versions, how projects, modules and plugins compose, how a level holds actors and how the game mode decides what enters the world, why Project AirSim declines the pawn machinery and spawns from configuration instead, how terrain, foliage and props are authored and imported, how a camera sensor is seven scene captures wearing post-process materials, and how the cook, stage, pak and archive sequence turns all of it into a binary that the SITL stack can launch. The procedures of §12 are written so that a new environment can be built and packaged from that knowledge without further investigation.

## 15. Bibliography

Primary sources, engine. All paths are relative to the reference checkout at `sitl_ws/src/ue5/UnrealEngine`, branch 5.2 at commit `02dc8dbd`.

- `Engine/Source/Runtime/Core/Public/UObject/ObjectVersion.h`, the two version enumerations, the `AUTOMATIC_VERSION` sentinel construction and `FPackageFileVersion`.
- `Engine/Source/Runtime/CoreUObject/Private/UObject/PackageFileSummary.cpp`, the package summary serialisation that §12.2 reimplements.
- `Engine/Source/Runtime/AssetRegistry/Private/PackageReader.cpp`, the asset registry version gates and the `is too new` warning.
- `Engine/Source/Editor/UnrealEd/Private/EditorServer.cpp`, the editor map-load validation and the `from an engine release newer than this` diagnostic.
- `Engine/Source/Editor/UnrealEd/Private/Commandlets/ContentCommandlets.cpp`, `UResavePackagesCommandlet` and its `MaxResaveUEVersion` default.
- Branch 5.5 of the same repository, `Engine/Source/Runtime/Core/Public/UObject/ObjectVersion.h`, for the enumerators 1010 to 1013.

Primary sources, Project AirSim. Paths relative to `sitl_ws/src/ue5/ProjectAirSim`.

- `sitl_ws/src/ue5/ProjectAirSim/docs/use_plugin.md`, the authoritative integration procedure, the plugin package layout and the SunTemple walkthrough.
- `sitl_ws/src/ue5/ProjectAirSim/docs/config_scene.md`, the scene configuration surface and the warning that the origin is the Unreal world origin.
- `docs/command_line_switches.md`, the runtime switches of a packaged game.
- `docs/gis_scenes.md`, the georeferenced tile path.
- `unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/ProjectAirSimGameMode.cpp`, the whole of the Unreal-side entry point.
- `unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/UnrealScene.cpp`, the robot and environment actor spawn paths and the deferred spawn ordering.
- `unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/Sensors/UnrealCamera.cpp`, the seven scene capture components and their post-process materials.
- `unreal/Blocks/Plugins/ProjectAirSim/Source/ProjectAirSim/Private/UnrealSimLoader.cpp`, the simulation launch, the engine settings and the version warning.
- `build_linux.mk` and `build.sh`, the target graph and the `BuildCookRun` invocations.
- `README.md:92` and `docs/development/dev_setup_linux.md:26,62`, the supported engine versions.

Primary sources, workspace.

- `unreal/StonePineForest/Saved/Logs/StonePineForest.log`, the engine banner, the four asset registry warnings and the map-load refusal.
- `unreal/StonePineForest/Config/DefaultEngine.ini` and `DefaultGame.ini`, the map, game mode and cook settings.
- `sitl_ws/scripts/build_airsim2_game.sh`, the packaging invocation.
- `sitl_ws/scripts/print_spawn_origin.py`, the headless spawn origin reader.
- `scripts/helpers/sitl.sh:10` and `sitl_ws/src/ue5/AirSim/docker/Dockerfile_source:1`, the Cosys-AirSim Unreal Engine 5.5 pin that §8.4 relies upon.
- The binary package headers of all 910 assets under `unreal/StonePineForest/Content` and `Plugins`, decoded by the method of §12.2.

Companion context.

- [`project-airsim-architecture.md`](project-airsim-architecture.md), the simulator's software architecture, the sensor parameter surface, the clock model and the defect register.
- [`project-airsim-docker-build.md`](project-airsim-docker-build.md), the image, the toolchain, the engine pin and its evidence, the porting procedure and the spawn origin derivation.
- [`airsim-docker-build.md`](airsim-docker-build.md), the Cosys-AirSim image and its Unreal Engine 5.5 target.
- [`sitl-time-synchronisation.md`](sitl-time-synchronisation.md), every clock in the stack and why the stamping path matters to camera frames.
- [`djinn-workflows.md`](djinn-workflows.md), the `up airsim2`, `start sitl2` and related workflow entries.
- [`../plans/project-airsim-integration.md`](../plans/project-airsim-integration.md), the change record of the whole integration.

Secondary sources, Epic Games documentation. These are stable entry points rather than deep links, since Epic reorganises its documentation between releases.

- Unreal Engine documentation, https://dev.epicgames.com/documentation/en-us/unreal-engine
- Gameplay framework, game mode and game state, referenced from `docs/use_plugin.md:49` as https://docs.unrealengine.com/en-US/Gameplay/Framework/GameMode/index.html
