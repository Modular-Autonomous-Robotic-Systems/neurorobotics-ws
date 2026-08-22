"""Print the Project AirSim spawn origin of every PlayerStart in the open map.

Run inside airsim2_container with the Unreal editor commandlet:

    $UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd \
      /ws/sitl_ws/src/ue5/ProjectAirSim/unreal/StonePineForest/StonePineForest.uproject \
      -run=pythonscript -script="/ws/sitl_ws/scripts/print_spawn_origin.py" \
      -unattended -nullrhi

Unreal world coordinates are centimetres in a north, east, up frame.
UnrealTransform::UnrealToNedLinear converts by ToMeters, a multiplication by
0.01, then NeuToNedLinear, which negates only the third component, so

    north =  UnrealX / 100
    east  =  UnrealY / 100
    down  = -UnrealZ / 100

and those three numbers in that order are the "xyz" string of the actor origin
in sitl_ws/config/airsim2/scene_ardu_copter.jsonc. Subtract a further one to
two metres from down, making it more negative, so that the copter starts just
above the surface rather than intersecting it.
"""

import unreal

subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

found = False
for actor in subsystem.get_all_level_actors():
    if isinstance(actor, unreal.PlayerStart):
        found = True
        location = actor.get_actor_location()
        print(
            "%s: unreal xyz (cm) %.1f %.1f %.1f"
            % (actor.get_actor_label(), location.x, location.y, location.z)
        )
        print(
            'origin xyz (NED metres): "%.3f %.3f %.3f"'
            % (location.x / 100.0, location.y / 100.0, -location.z / 100.0)
        )

if not found:
    print(
        "No PlayerStart in this map. Drag one onto the terrain at the wanted "
        "spawn point and rerun, or read any actor's Location and apply the "
        "same conversion."
    )
