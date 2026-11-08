# Shared settings for the ws-* scripts. Sourced, not executed.
# shellcheck shell=bash disable=SC2034  # the variables are used by those scripts

# Services and desktop launchers don't inherit the pod's env directly; the base
# image's entrypoint writes it here.
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-ubuntu}"
# shellcheck disable=SC1091
[ -f "${XDG_RUNTIME_DIR}/container-env" ] && . "${XDG_RUNTIME_DIR}/container-env"

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is not set}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is not set}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is not set}"
: "${R2_BUCKET:?R2_BUCKET is not set}"

# rclone remote "r2:" configured entirely from env, no config file
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="${R2_ENDPOINT:-https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com}"
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
export RCLONE_TRANSFERS=16 RCLONE_CHECKERS=32 RCLONE_S3_UPLOAD_CONCURRENCY=8

REMOTE="r2:${R2_BUCKET}"

# Local dir -> bucket prefix. Everything you want to survive the pod goes here.
# The image must not ship files inside these dirs (see the Dockerfile).
declare -A WS_SYNC_DIRS=(
  ["$HOME/work"]="work"
  ["$HOME/.config/blender"]="config/blender"
  ["$HOME/.config/Epic"]="config/Epic"
  ["$HOME/.claude"]="config/claude"
)

# Regenerable or noisy files that aren't worth paying to store
WS_EXCLUDES=(
  --exclude "**/Intermediate/**"
  --exclude "**/DerivedDataCache/**"
  # Unreal 5.4+ local DDC (~/.config/Epic/UnrealEngine/Common/Zen/Data)
  --exclude "**/Zen/Data/**"
  --exclude "**/Saved/Logs/**"
  --exclude "**/Saved/Crashes/**"
  --exclude "**/__pycache__/**"
  --exclude "*.blend1"
  --exclude "*.blend@"
  # Claude Code SSO login token stays on the pod: log in again on each new pod
  --exclude ".credentials.json"
)

# Present only after a successful restore. Saving without it would mirror an
# empty pod over the bucket.
WS_RESTORED_MARKER="${XDG_RUNTIME_DIR}/ws-restored"
WS_LOCK="${XDG_RUNTIME_DIR}/ws-sync.lock"
# Time of the last complete save, and when the pod deletes itself (epoch seconds)
WS_LAST_SAVE="${XDG_RUNTIME_DIR}/ws-last-save"
WS_DEADLINE="${XDG_RUNTIME_DIR}/ws-deadline"

log() { echo "[ws $(date -u +%H:%M:%S)] $*"; }

# Desktop notification, also logged. Best effort: there's no session bus until
# Plasma is up. alert is for failures and stays on screen until dismissed.
notify() { log "$*"; notify-send -a Workstation "$1" "${2:-}" 2>/dev/null || true; }
alert() { log "$*" >&2; notify-send -a Workstation -u critical "$1" "${2:-}" 2>/dev/null || true; }
