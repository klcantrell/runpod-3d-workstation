# runpod-3d-workstation

A throwaway GPU desktop on Runpod for Blender, Unreal Engine, and Isaac Sim. The
pod is deleted when you're done; your work lives in Cloudflare R2.

- **Desktop:** KDE in your browser (Selkies), on port 8080 through Runpod's proxy.
- **Blender** is in the image. **Isaac Sim** and **Unreal** install on first
  launch and are cached in R2, so later pods restore them quickly.
- **Your work** (`~/work`, Blender and Unreal settings) is restored from R2 at
  boot, autosaved every 10 minutes, and saved on "Save & Terminate".
- Files you delete or overwrite aren't lost: the previous copy goes to
  `.trash/<timestamp>/` in the bucket.

## Rough cost

| What | Cost |
| --- | --- |
| RTX 4090 pod (secure cloud) | roughly $0.60–0.70/hr, only while it exists |
| Same, `WS_SPOT=true` | roughly half, but can be interrupted (you lose ≤10 min) |
| 200 GB container disk | ~$0.03/hr while running, nothing after delete |
| R2 storage | $0.015/GB/month, first 10 GB free, **no download fees** |

Check current prices on Runpod's pricing page.

## One-time setup

### 1. Cloudflare R2
1. In the Cloudflare dashboard, open **R2**, then **Create bucket**. Name it, for example `ws-3d`.
2. Open **R2**, then **Manage API tokens**, and create a token with **Object Read & Write**
   scoped to that bucket. Note the Access Key ID, Secret Access Key, and your
   Account ID.
3. Recommended: on the bucket, add a lifecycle rule that deletes objects with
   prefix `.trash/` after 30 days.

### 2. Runpod
1. Create an account and add credit.
2. Go to **Settings**, then **API Keys**, and create a key. It goes on your Mac in step 4.
3. Go to **Secrets** and create these secrets (the names must match exactly):
   - `desktop_password`: the password for the web desktop
   - `r2_account_id`, `r2_access_key_id`, `r2_secret_access_key`, `r2_bucket`

### 3. Build the image
Push this repo to GitHub. The `build` workflow publishes
`ghcr.io/<you>/runpod-3d-workstation:latest`. If the repo is private, either make
the GHCR package public (Package settings, then Change visibility), or add a GHCR token
under Runpod, then **Container Registry Auth**, and pass its ID as `containerRegistryAuthId`.

### 4. Your Mac
```sh
mkdir -p ~/.config/ws && chmod 700 ~/.config/ws
cat > ~/.config/ws/env <<'EOF'
RUNPOD_API_KEY=rpa_...
WS_IMAGE=ghcr.io/<you>/runpod-3d-workstation:latest
# WS_SPOT=true
# WS_CLOUD=COMMUNITY
EOF
chmod 600 ~/.config/ws/env
ln -s "$PWD/scripts/ws" /usr/local/bin/ws   # or add scripts/ to PATH
```

## Daily use

```sh
ws up       # prints https://<pod>-8080.proxy.runpod.net. Log in as ubuntu / desktop_password
ws status   # is anything running (and costing money)?
```

Work inside `~/work` on the pod. That folder is the one that gets saved. When
you're done, double-click **Save & Terminate Pod** on the desktop. It saves to R2
and then deletes the pod. If the save fails, the pod stays up so nothing is lost.

`ws down` deletes the pod from your Mac without a final save (you could lose up
to 10 minutes of work). Use it only if the desktop is unreachable.

### Unreal, first time
Epic requires a login to download, so:
1. In the pod's browser, go to https://www.unrealengine.com/linux and download the Linux zip.
2. In a terminal, run `install-unreal ~/Downloads/<zip>`. It installs and caches the zip in R2.

On later pods, the **Unreal Editor** shortcut installs from the R2 cache by itself.

### Isaac Sim
The **Isaac Sim** shortcut installs version `ISAACSIM_VERSION` (default 6.2.0.0)
from NVIDIA's pip index on first use, then caches it in R2. You'll be asked
to accept NVIDIA's EULA the first time it runs.

### Claude Code
Claude Code is installed in the image, with Blender connected through
[MCP for Blender](https://github.com/ahujasid/blender-mcp) (a community add-on, not
an official Blender project).

1. Open Blender. The add-on starts its connection on launch. To check it, press
   `N` in the viewport and open the **MCP for Blender** tab.
2. Open a terminal and `cd ~/work`, then run `claude`.
3. **On each new pod:** run `/login` and sign in with your org's SSO in the pod's
   browser. The login token is deliberately left out of the R2 sync. To keep
   it across pods, remove the `.credentials.json` exclude in `ws-lib.sh`.

Your Claude Code settings, history and MCP servers (`~/.claude`) *are* synced.
`~/.claude/CLAUDE.md` tells Claude about this machine: where the apps are, and
that only `~/work` survives. Edit it as you like. Claude Code updates come from
rebuilding the image (bump nothing, just re-run the workflow).

The Blender add-on executes whatever Python the agent sends it, so only connect
agents you trust. Its telemetry is opt-in, and this setup also turns off its
anonymous usage ping.

## Customizing what's saved
Edit `WS_SYNC_DIRS` and `WS_EXCLUDES` in `rootfs/usr/local/lib/ws-lib.sh`.
Anything outside those directories, including `~/apps`, is lost when the pod is deleted.

## Known caveats
- Pods are Linux, so you get the Unreal Editor for Linux. There's no Windows option.
- Isaac Sim officially targets Ubuntu 22.04/24.04. This image is 26.04 (the
  desktop base requires it), running Isaac Sim through its pip wheels.
- Isaac Sim needs an RTX GPU. `WS_GPUS` lists only RTX cards for that reason.
