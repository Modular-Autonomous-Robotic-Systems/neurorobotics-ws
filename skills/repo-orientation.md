- `djinn` (repo root) is the primary workflow CLI — see [`context/djinn-cli.md`](../context/djinn-cli.md).
  Requires `$NRT_WS` set to the workspace root.
- `ARCHITECTURE.md` describes the layered Docker image hierarchy, ROS, and SITL design.
- `sitl_ws/src/ue5/AirSim` is a git submodule (Cosys-AirSim). Docker builds clone **upstream**
  Cosys-AirSim fresh — so fixes belong Dockerfile-side, not in the local submodule's
  `build.sh`. See [`context/airsim-docker-build.md`](../context/airsim-docker-build.md).
- The SITL workspaces (`ardu_ws/`, `sitl_ws/`) are mounted under `/ws`, not baked into the
  image, and built at container-start. See [`context/sitl-workspace-migration.md`](../context/sitl-workspace-migration.md)
  and the workflow catalogue [`context/djinn-workflows.md`](../context/djinn-workflows.md).
