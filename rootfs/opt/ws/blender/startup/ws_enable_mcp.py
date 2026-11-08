# Enables the Blender MCP add-on on every launch. The add-on lives in the
# image's system extensions repo (BLENDER_SYSTEM_EXTENSIONS), not the synced
# ~/.config/blender, so image upgrades replace it, and enabling it here means
# synced user prefs can't turn it off.
import addon_utils
import bpy
from bpy.app.handlers import persistent

ADDON = "bl_ext.system.mcp"


@persistent
def _enable(*_):
    bpy.app.handlers.load_post.remove(_enable)
    addon_utils.enable(ADDON, default_set=True, persistent=True)


def register():
    # The add-on won't start its socket server without online access. Set it
    # before Blender loads add-ons, so one enabled in synced prefs starts too.
    bpy.context.preferences.system.use_online_access = True
    # Extensions (bl_ext) are set up only after startup scripts run
    bpy.app.handlers.load_post.append(_enable)


def unregister():
    pass
