# Enables the MCP for Blender add-on on every launch. The add-on lives in the
# image (BLENDER_SYSTEM_SCRIPTS=/opt/ws/blender), not the synced
# ~/.config/blender, so image upgrades replace it, and enabling it here means
# synced user prefs can't turn it off.
import os
import sys

import addon_utils

ADDONS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "addons")


def register():
    # Blender adds the addons dirs to sys.path only after startup scripts run
    if ADDONS not in sys.path:
        sys.path.append(ADDONS)
    addon_utils.enable("blender_mcp", default_set=True, persistent=True)


def unregister():
    pass
