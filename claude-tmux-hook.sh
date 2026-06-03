#!/bin/bash
# Claude Code lifecycle hook handler for the tmux claude-agent indicator.
# Usage: claude-tmux-hook.sh busy|idle
#   busy  -> mark this pane's agent as working   (UserPromptSubmit)
#   idle  -> mark this pane's agent as finished   (Stop, SessionEnd)
# No-op when not running inside tmux.

[ -z "$TMUX_PANE" ] && exit 0
mode="$1"

win=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null) || exit 0
[ -z "$win" ] && exit 0

# Pane flag is @claude_pane_busy (NOT @claude_busy): tmux user options resolve up the
# pane->window hierarchy, so reusing @claude_busy at pane scope would inherit the window
# value and make the recompute below self-referential. Window display flag is @claude_busy.
if [ "$mode" = "busy" ]; then
  tmux set -p -t "$TMUX_PANE" @claude_pane_busy 1
else
  tmux set -p -t "$TMUX_PANE" -u @claude_pane_busy
fi

# Recompute the window flag from pane flags so the color flips immediately.
n=$(tmux list-panes -t "$win" -F '#{@claude_pane_busy}' 2>/dev/null | grep -c '^1$')
if [ "$n" -gt 0 ]; then
  tmux set -w -t "$win" @claude_busy "$n"
else
  tmux set -w -t "$win" -u @claude_busy
fi
