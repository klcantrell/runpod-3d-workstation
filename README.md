# runpod-3d-workstation

A throwaway GPU desktop on Runpod for Blender, Unreal Engine, and Isaac Sim. The
pod is deleted when you're done; your work lives in Cloudflare R2.

- **Desktop:** KDE in your browser (Selkies), on port 8080 through Runpod's proxy.
- **Blender** is in the image. **Isaac Sim** and **Unreal** install on first
  launch and are cached in R2, so later pods restore them quickly.
- **Your work** (`~/work`, plus Blender, Unreal and Claude Code settings) is
  restored from R2 at boot, autosaved every 10 minutes, and saved on "Save &
  Terminate".
- When a save deletes or overwrites a file in R2, the previous copy goes to
  `.trash/<timestamp>/` in the bucket (kept 30 days with the lifecycle rule
  below). Work that was never saved isn't covered.
- **Time limit:** 8 hours after boot the pod saves and deletes itself, with a
  desktop warning 15 minutes before. Run `ws-extend` (2 more hours) or
  `ws-extend 4` in a terminal on the pod to keep it longer.

## Rough cost

| What | Cost |
| --- | --- |
| RTX 4090 pod (secure cloud) | roughly $0.60–0.70/hr, only while it exists |
| 200 GB container disk | ~$0.03/hr while running, nothing after delete |
| R2 storage | $0.015/GB/month, first 10 GB free, **no download fees** |

Check current prices on Runpod's pricing page. Runpod is prepaid: keeping a
modest balance with auto-pay off caps what a forgotten pod can cost.

## One-time setup

### 1. Cloudflare R2
1. In the Cloudflare dashboard, open **R2**, then **Create bucket**. Name it, for example `ws-3d`.
2. Open **R2**, then **Manage API tokens**, and create a token with **Object Read & Write**
   scoped to that bucket. Note the Access Key ID, Secret Access Key, and your
   Account ID.
3. On the bucket, add a lifecycle rule that deletes objects with prefix
   `.trash/` after 30 days. Without it, old versions pile up forever.

### 2. Runpod
1. Create an account and add credit.
2. Go to **Settings**, then **API Keys**, and create a key. It goes on your Mac in step 4.
3. Go to **Secrets** and create these secrets (the names must match exactly):
   - `desktop_password`: the password for the web desktop. Use one you don't use anywhere else.
   - `r2_account_id`, `r2_access_key_id`, `r2_secret_access_key`, `r2_bucket`

   If one is missing or misnamed, the pod refuses to start rather than run with
   a guessable password; `ws logs` shows which one.

### 3. Build the image
Push this repo to GitHub. The `build` workflow publishes
`ghcr.io/<you>/runpod-3d-workstation:sha-<commit>` (and `:latest`). If the repo is
private, either make the GHCR package public (Package settings, then Change
visibility), or add a GHCR token under Runpod, then **Container Registry Auth**,
and put its ID in `WS_REGISTRY_AUTH_ID`.

Then install the [Renovate](https://github.com/apps/renovate) GitHub app on the
repo (see [Updates](#updates)).

### 4. Your Mac
```sh
brew install runpod/runpodctl/runpodctl
runpodctl doctor      # paste the API key from step 2 when asked

mkdir -p ~/.config/ws && chmod 700 ~/.config/ws
cat > ~/.config/ws/env <<'EOF'
# The sha- tag from the build summary; pin it so a new build can't surprise you
WS_IMAGE=ghcr.io/<you>/runpod-3d-workstation:sha-abc1234
# WS_CLOUD=COMMUNITY
# Allowed datacenters; nearer means less input lag. Full list at the top of scripts/ws.
# WS_DATACENTERS=US-IL-1,US-KS-2
# GPUs to try, in order (default: 4090, A6000, L40S, 6000 Ada, 5090)
# WS_GPUS="NVIDIA L40S,NVIDIA RTX 6000 Ada Generation"
# Only hosts whose driver supports at least this CUDA version (default: any)
# WS_MIN_CUDA=12.8
# WS_REGISTRY_AUTH_ID=...
EOF
chmod 600 ~/.config/ws/env
ln -s "$PWD/scripts/ws" /usr/local/bin/ws   # or add scripts/ to PATH
```

## Daily use

```sh
ws up       # prints https://<pod>-8080.proxy.runpod.net. Log in as ubuntu / desktop_password
ws status   # GPU, datacenter, $/hr, URL. Is anything running (and costing money)?
ws logs     # container log, e.g. if the desktop never comes up
```

Wait for the **Restore complete** notification before opening Blender or
Claude Code. Work inside `~/work` on the pod; that folder is the one that gets
saved. When you're done, double-click **Save & Terminate Pod** on the desktop.
It saves to R2 and then deletes the pod. If the save or the delete fails, it
says so and the window stays open; a failed delete means the pod is still
billing, so run `ws down`.

If an autosave or the boot restore fails, you get a desktop notification that
stays until dismissed. Run `ws-save` (or `ws-restore`) in a terminal to see the
error.

`ws down` deletes the pod from your Mac without a final save (you could lose up
to 10 minutes of work). Use it only if the desktop is unreachable.

### Unreal, first time
Epic requires a login to download, so:
1. In the pod's browser, go to https://www.unrealengine.com/linux and download the Linux zip.
2. In a terminal, run `install-unreal ~/Downloads/<zip>`. It installs and caches the zip in R2.

On later pods, the **Unreal Editor** shortcut installs from the R2 cache by itself.

### Isaac Sim
The **Isaac Sim** shortcut installs the version set by `ISAACSIM_VERSION` in the
`Dockerfile` from NVIDIA's pip index on first use, then caches it in R2. You'll be
asked to accept NVIDIA's EULA the first time it runs.

### Claude Code
Claude Code is installed in the image, with Blender connected through
[MCP for Blender](https://github.com/ahujasid/mcp-for-blender) (a community
add-on, not an official Blender project).

1. Open Blender. The add-on starts its connection on launch. To check it, press
   `N` in the viewport and open the **MCP for Blender** tab.
2. Open a terminal and `cd ~/work`, then run `claude`.
3. **On each new pod:** run `/login` and sign in with your org's SSO in the pod's
   browser. The login token is deliberately left out of the R2 sync. To keep
   it across pods, remove the `.credentials.json` exclude in `ws-lib.sh`.

Your Claude Code settings, history and MCP servers (`~/.claude`) *are* synced.
At boot the `blender` MCP server is re-registered to match the add-on in the
image. `~/.claude/CLAUDE.md` tells Claude about this machine: where the apps
are, and that only `~/work` survives. Edit it as you like; delete it to get the
image's current default on the next pod.

The Blender add-on executes whatever Python the agent sends it, so only connect
agents you trust. Anything running on the pod, including the agent, can read the
R2 keys from the environment. Its telemetry is opt-in, and this setup also turns
off its anonymous usage ping and its update check.

## Customizing what's saved
Edit `WS_SYNC_DIRS` and `WS_EXCLUDES` in `rootfs/usr/local/lib/ws-lib.sh`.
Anything outside those directories, including `~/apps`, is lost when the pod is
deleted. The image must not put files inside a synced directory (CI checks
this): restore keeps whichever copy is newer, so a baked file would hide your copy.

Other settings are `ENV` lines in the `Dockerfile`: `WS_AUTOSAVE_MINUTES` and
`WS_MAX_HOURS` (0 turns off the time limit).

## Updates

Every version is pinned in the `Dockerfile`. Renovate opens a pull request
(Mondays) when one has a new release: Blender, rclone, runpodctl, uv, Claude
Code (stable channel), MCP for Blender, Isaac Sim, the base desktop image, and
the GitHub Actions. CI lints, builds and smoke-tests every PR.

To take an update:
1. Read the PR's release notes, check CI is green, and merge.
2. Copy the new `sha-` tag from the build summary into `WS_IMAGE`.
3. On the next pod, check what the smoke test can't (no GPU in CI): the
   desktop streams, Blender opens with the MCP tab, and `claude mcp list`
   shows `blender` connected while Blender is open. For an Isaac Sim or Unreal
   bump, launch that too.
4. If anything's wrong, put the previous `sha-` tag back in `WS_IMAGE`. Every
   image you've built includes its base, so rolling back always works.

Notes:
- **Blender minor versions** (5.2 → 5.3) keep preferences per version. On the
  first launch Blender offers to import the previous version's preferences.
- **Isaac Sim** caches are per version; old ones stay in R2 under `apps/`
  until you delete them.
- **The base image** is pinned to upstream's timestamped tag and digest. Upstream
  deletes old ones, so if the build fails with "not found", merge Renovate's
  base-image PR.

Lint locally before pushing (CI does the rest):
```sh
brew install shellcheck
shellcheck scripts/ws tests/*.sh rootfs/usr/local/lib/ws-lib.sh rootfs/usr/local/bin/* rootfs/etc/service/r2-sync/*
```

## Known caveats
- Pods are Linux, so you get the Unreal Editor for Linux. There's no Windows option.
- Isaac Sim officially targets Ubuntu 22.04/24.04. This image is 26.04 (the
  desktop base requires it), running Isaac Sim through its pip wheels.
- Isaac Sim needs an RTX GPU. `WS_GPUS` lists only RTX cards for that reason.
