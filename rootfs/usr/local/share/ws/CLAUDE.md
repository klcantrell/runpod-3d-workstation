# This machine

An ephemeral Runpod GPU pod with a KDE desktop streamed to the user's browser.
It is deleted when the user is done.

- **Only `~/work` and app settings survive.** They are restored from Cloudflare
  R2 at boot and saved every 10 minutes. Put projects, scripts, and outputs in
  `~/work`; anything elsewhere is lost. Run `ws-save` to save immediately.
- `~/apps` (Isaac Sim, Unreal) is reinstalled from an R2 cache on each pod.
- The pod saves and deletes itself `WS_MAX_HOURS` after boot (the user gets a
  warning 15 minutes before). Before a long render or simulation, tell the user
  to run `ws-extend <hours>` first.

## Apps

- **Blender**: `blender` (`/opt/blender`). The running Blender GUI is reachable
  through the `blender` MCP server. For batch work without the GUI:
  `blender -b file.blend --python script.py`.
- **Isaac Sim**: install with `install-isaacsim`, then run standalone scripts
  with `~/apps/isaacsim-$ISAACSIM_VERSION/.venv/bin/python script.py`
  (`from isaacsim import SimulationApp` first). `isaacsim` opens the GUI.
- **Unreal Engine**: `unreal` opens the editor (`~/apps/unreal`). Python
  scripting requires enabling the Python Editor Script Plugin in the project.

Display is `:20`; GUI apps launched from a shell appear on the user's desktop.
