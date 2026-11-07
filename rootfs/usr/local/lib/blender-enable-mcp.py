# Run at image build: blender -b --python this.py
# Enables the MCP for Blender add-on and saves user prefs, so Blender starts
# the MCP socket server (port 9876) on launch. Fails the build if it can't.
import sys

import addon_utils
import bpy

if addon_utils.enable("blender_mcp", default_set=True) is None:
    print("could not enable blender_mcp add-on", file=sys.stderr)
    sys.exit(1)
bpy.ops.wm.save_userpref()
print("blender_mcp add-on enabled")
