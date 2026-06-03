#!/usr/bin/env bash
# Launch the indicator demo in a DEDICATED tmux server (socket "claudedemo"), so it never
# touches your real tmux session. Run directly to preview live, or let demo.tape drive it
# for recording (vhs demo.tape). The session ends itself when the demo finishes.
set -uo pipefail
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLAUDE_TMUX_DIR="$(cd "$DIR/.." && pwd)"   # repo root, where count.sh / hook.sh live
SOCK=claudedemo
tmux -L "$SOCK" kill-server 2>/dev/null
exec tmux -L "$SOCK" -f "$DIR/demo.tmux.conf" new-session -s demo "bash '$DIR/demo.sh'"
