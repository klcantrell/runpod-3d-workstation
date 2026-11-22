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
[ -f "/usr/share/ghostty/themes/Catppuccin Mocha" ] || fail "Ghostty's Catppuccin Mocha theme is missing"
ghostty +validate-config >/dev/null || fail "Ghostty rejects its config"
pass "ghostty has its theme and a valid config"
tmux -V >/dev/null && pass "tmux runs"
[ -n "$(fc-list "CaskaydiaCove Nerd Font")" ] || fail "CaskaydiaCove Nerd Font isn't installed"
pass "CaskaydiaCove Nerd Font is installed"

# --- Editors with the dotfiles' settings
out="$(nvim --headless +qa 2>&1)"
if grep -E -q 'E[0-9]+:|Error' <<<"$out"; then fail "nvim reports errors at startup: $out"; fi
for s in rust-analyzer pyrefly typescript-language-server lua-language-server; do
  [ -e "$HOME/.local/share/nvim/mason/bin/$s" ] || fail "Mason didn't install $s"
done
pass "nvim starts cleanly, with its plugins and LSP servers"

TERM=xterm-256color tmux -L ws-test new-session -d -s t
[ "$(tmux -L ws-test show -gv prefix)" = C-Space ] || fail "tmux didn't load the dotfiles' config"
[ "$(tmux -L ws-test show -gv @catppuccin_flavor)" = mocha ] || fail "tmux didn't load catppuccin"
[ "$(tmux -L ws-test show -sv set-clipboard)" = on ] || fail "tmux's OSC 52 clipboard isn't on"
tmux -L ws-test kill-server
pass "tmux loads the dotfiles' config, catppuccin and the OSC 52 clipboard"

[ -f "$HOME/.config/Code/User/settings.json" ] || fail "VS Code settings are missing"
exts="$(code --list-extensions)"
for e in asvetliakov.vscode-neovim ms-python.python anthropic.claude-code; do
  grep -qix "$e" <<<"$exts" || fail "VS Code extension $e is missing"
done
pass "VS Code has the dotfiles' settings and its extensions"

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

# A synced settings.json with a stale value for each key the dotfiles set, and
# one key of its own
python3 -c 'import json, sys
s = {k: "stale" for k in json.load(open(sys.argv[1]))}
s["wsTestKeep"] = True
json.dump(s, open(sys.argv[2], "w"))' /usr/local/share/ws/claude-settings.json "$CLAUDE_CONFIG_DIR/settings.json"
ws-reconcile >/dev/null
grep -q "/opt/ws/blender-mcp/bin/blender-mcp" "$CLAUDE_CONFIG_DIR/.claude.json" ||
  fail "ws-reconcile didn't register the MCP server"
[ -f "$CLAUDE_CONFIG_DIR/CLAUDE.md" ] || fail "ws-reconcile didn't install CLAUDE.md"
python3 -c 'import json, sys
want, got = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
sys.exit(not (all(got.get(k) == v for k, v in want.items()) and got.get("wsTestKeep") is True))' \
  /usr/local/share/ws/claude-settings.json "$CLAUDE_CONFIG_DIR/settings.json" ||
  fail "ws-reconcile didn't merge the dotfiles' Claude settings over the synced ones"
pass "ws-reconcile registers the MCP server, CLAUDE.md and the dotfiles' Claude settings"

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
