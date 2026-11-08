#!/bin/bash
# Checks run inside the built image (as uid 1000) by tests/smoke.sh: the tools
# work, the Blender add-on loads, and the R2 sync scripts behave, against a
# local S3 server (rclone serve s3) standing in for R2.
set -euo pipefail

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- The image ships nothing in synced dirs (restore uses --update). Checked
# first: running Blender or Claude creates their config dirs.
for d in "$HOME/.claude" "$HOME/.config/blender" "$HOME/.config/Epic" "$HOME/work"; do
  [ ! -e "$d" ] || fail "$d exists in the image"
done
pass "synced dirs are empty in the image"

# --- Tools and add-on
claude --version >/dev/null && pass "claude runs"
runpodctl --version >/dev/null && pass "runpodctl runs"
uvx --version >/dev/null && pass "uvx runs"
blender -b --python-exit-code 1 --python /usr/local/lib/blender-check-mcp.py >/dev/null 2>&1 ||
  fail "Blender doesn't enable the MCP add-on"
pass "blender enables the MCP add-on"
/opt/ws/blender-mcp/bin/blender-mcp --help >/dev/null && pass "blender-mcp runs"

# --- Sync scripts against a local S3 server
export XDG_RUNTIME_DIR; XDG_RUNTIME_DIR="$(mktemp -d)"
s3="$(mktemp -d)"; mkdir -p "$s3/bucket"
rclone serve s3 "$s3" --addr 127.0.0.1:9000 >/dev/null 2>&1 &
sleep 2
export R2_ACCOUNT_ID=test R2_ACCESS_KEY_ID=test R2_SECRET_ACCESS_KEY=test R2_BUCKET=bucket \
  R2_ENDPOINT=http://127.0.0.1:9000 RCLONE_RETRIES=1
put() { (. /usr/local/lib/ws-lib.sh; echo "$2" | rclone rcat "$REMOTE/$1"); }
get() { (. /usr/local/lib/ws-lib.sh; rclone cat "$REMOTE/$1" 2>/dev/null); }
has() { (. /usr/local/lib/ws-lib.sh; [ -n "$(rclone lsf "$REMOTE/$1" 2>/dev/null)" ]); }

if ws-save >/dev/null 2>&1; then fail "ws-save ran before a restore"; fi
pass "ws-save refuses before restore"

put work/scene.txt "from r2"
put work/old.txt "older in r2"
put config/claude/.credentials.json "token"
sleep 1
mkdir -p "$HOME/work"; echo "edited on the pod" > "$HOME/work/old.txt"
ws-restore >/dev/null
[ "$(cat "$HOME/work/scene.txt")" = "from r2" ] || fail "restore didn't copy work/scene.txt"
[ "$(cat "$HOME/work/old.txt")" = "edited on the pod" ] || fail "restore overwrote a newer local file"
[ ! -e "$HOME/.claude/.credentials.json" ] || fail "restore copied .credentials.json"
pass "restore copies work, keeps newer local files, skips credentials"

ws-reconcile >/dev/null
grep -q "/opt/ws/blender-mcp/bin/blender-mcp" "$CLAUDE_CONFIG_DIR/.claude.json" ||
  fail "ws-reconcile didn't register the MCP server"
[ -f "$CLAUDE_CONFIG_DIR/CLAUDE.md" ] || fail "ws-reconcile didn't install CLAUDE.md"
pass "ws-reconcile registers the MCP server and CLAUDE.md"

echo "v2" > "$HOME/work/scene.txt"
echo "secret" > "$HOME/.claude/.credentials.json"
mkdir -p "$HOME/.config/Epic/UnrealEngine/Common/Zen/Data"; echo x > "$HOME/.config/Epic/UnrealEngine/Common/Zen/Data/cache"
ws-save >/dev/null
[ "$(get work/scene.txt)" = "v2" ] || fail "save didn't upload work/scene.txt"
(. /usr/local/lib/ws-lib.sh; rclone lsf -R "$REMOTE/.trash" | grep -q 'work/scene.txt$') ||
  fail "overwritten file didn't go to .trash"
[ "$(get config/claude/.credentials.json)" = "token" ] || fail "save uploaded .credentials.json"
if has config/Epic/UnrealEngine/Common/Zen/Data/cache; then fail "save uploaded Unreal's Zen DDC"; fi
[ -f "$XDG_RUNTIME_DIR/ws-last-save" ] || fail "save didn't record its time"
pass "save uploads, keeps old versions in .trash, honours excludes"

# A file growing during upload (Claude Code's session logs) must not stop the
# other dirs from being saved
head -c 20M /dev/urandom > "$HOME/.claude/session.jsonl"
( for _ in $(seq 1 100); do echo line >> "$HOME/.claude/session.jsonl"; sleep 0.02; done ) &
writer=$!
echo "v3" > "$HOME/work/scene.txt"
ws-save >/dev/null 2>&1 || true
wait "$writer"
[ "$(get work/scene.txt)" = "v3" ] || fail "a busy ~/.claude stopped ~/work from being saved"
pass "save still saves ~/work while ~/.claude is being written"

ws-extend 3 >/dev/null
[ "$(cat "$XDG_RUNTIME_DIR/ws-deadline")" -gt "$(( $(date +%s) + 10000 ))" ] || fail "ws-extend didn't set the deadline"
pass "ws-extend sets the deadline"

echo "all in-image checks passed"
