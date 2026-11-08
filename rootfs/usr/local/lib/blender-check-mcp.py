# Run at image build and in CI: blender -b --python-exit-code 1 --python this.py
# Fails unless the startup script in BLENDER_SYSTEM_SCRIPTS found and enabled
# the MCP for Blender add-on. The socket server (port 9876) only auto-starts in
# the GUI, not here.
import bpy

if "blender_mcp" not in bpy.context.preferences.addons:
    raise SystemExit("blender_mcp add-on is not enabled")
print("blender_mcp add-on enabled")
