# Run at image build and in CI: blender -b --python-exit-code 1 --python this.py
# Fails unless the startup script in BLENDER_SYSTEM_SCRIPTS found and enabled
# the Blender MCP add-on, with the online access it needs. The socket server
# (port 9876) only auto-starts in the GUI, not here.
import bpy

ADDON = "bl_ext.system.mcp"

if ADDON not in bpy.context.preferences.addons:
    raise SystemExit(ADDON + " add-on is not enabled")
if not bpy.app.online_access:
    raise SystemExit("online access is off, so the add-on won't start its server")
print(ADDON + " add-on enabled")
