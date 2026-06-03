#!/usr/bin/env bash
# Drives a scripted Claude-agent lifecycle so the tmux indicator can be recorded.
# Runs INSIDE the dedicated demo session started by launch.sh; bare `tmux` therefore
# targets that demo server (via $TMUX), never your real tmux.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_TMUX_DIR:-$(cd "$DIR/.." && pwd)}"   # repo root: count.sh / hook.sh live here
HOOK="$ROOT/claude-tmux-hook.sh"
poll(){ bash "$ROOT/claude-tmux-count.sh"; }

# Fake "agent": a symlink named `claude` -> /bin/sleep. `ps comm` reports "claude", so the
# poller counts it exactly like a real Claude Code process. (A copied binary gets killed by
# macOS codesigning; the symlink runs the real signed /bin/sleep under the name `claude`.)
FB="$(mktemp -d)"; ln -s /bin/sleep "$FB/claude"
cleanup(){ rm -rf "$FB"; tmux kill-server 2>/dev/null; }
trap cleanup EXIT

RST=$'\033[0m'; TITLE=$'\033[1;38;5;75m'; SUB=$'\033[38;5;245m'
cap(){ clear; printf '\n\n   %s%s%s\n\n   %s%s%s\n' "$TITLE" "$1" "$RST" "$SUB" "${2:-}" "$RST"; }
beat(){ sleep "${1:-2}"; }

tmux set -g allow-rename off \; rename-window main

# Open project windows as idle shells (no agent yet).
EDIT=$(tmux new-window -d -n edit  -P -F '#{pane_id}')
TEST=$(tmux new-window -d -n test  -P -F '#{pane_id}')
BUILD=$(tmux new-window -d -n build -P -F '#{pane_id}')

agent_start(){ tmux send-keys -t "$1" "$FB/claude 900" Enter; sleep 0.8; }  # let the process exist before poll()
agent_stop(){ tmux send-keys -t "$1" C-c; sleep 0.5; }
busy(){ TMUX_PANE="$1" bash "$HOOK" busy; }
idle(){ TMUX_PANE="$1" bash "$HOOK" idle; }

cap "Claude tmux indicator"          "green ✳ = idle agent   ·   orange ✳ = busy agent   ·   number = agents in that window"; beat 3
cap "Four windows, no agents yet"    "tabs stay clean"; poll; beat 2
cap "Launch Claude in 'edit'"        "poller detects the process → green ✳1 on the edit tab"; agent_start "$EDIT"; poll; beat 2.5
cap "edit starts working"            "UserPromptSubmit hook → ✳1 turns orange (busy)"; busy "$EDIT"; beat 2.5
cap "A second agent in 'test'"       "each window is tracked independently"; agent_start "$TEST"; poll; busy "$TEST"; beat 2.5
cap "edit finishes its turn"         "Stop hook → edit ✳1 back to green (idle, still running)"; idle "$EDIT"; beat 2.5
cap "Close edit's agent"             "process gone → poller clears its ✳, tab clean again"; agent_stop "$EDIT"; poll; beat 2.5
cap "test is still busy → ✳1 orange" "one glance at the tab bar shows who's working"; beat 2.5
cap "Stop everything"                "all agents done → indicator clears"; agent_stop "$TEST"; idle "$TEST"; poll; beat 2
cap "claude-tmux-notification"       "drop-in tmux + Claude Code agent indicator · install.sh"; beat 3
