# shellcheck shell=sh
# On an SSH login, say when the pod deletes itself: the desktop's warning
# isn't visible from here.
if [ -n "${SSH_TTY:-}" ] && [ -r "${XDG_RUNTIME_DIR:-/tmp/runtime-ubuntu}/ws-deadline" ]; then
  ws_left=$(( $(cat "${XDG_RUNTIME_DIR:-/tmp/runtime-ubuntu}/ws-deadline") - $(date +%s) ))
  if [ "$ws_left" -gt 0 ]; then
    echo "This pod saves ~/work and deletes itself in $(( ws_left / 3600 ))h $(( ws_left % 3600 / 60 ))m. ws-extend [hours] keeps it longer."
  fi
  unset ws_left
fi
