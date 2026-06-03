#!/usr/bin/env bash
# Installer for the tmux claude-agent indicator. Idempotent; safe to re-run.
#
# Wires two host files (neither lives in this module):
#   - ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json  -> UserPromptSubmit/Stop/SessionEnd hooks
#   - ${TMUX_CONF:-~/.tmux.conf}                      -> status-interval, poller, window format
#
# Overrides via env:
#   CLAUDE_CONFIG_DIR  Claude config dir            (default: ~/.claude)
#   TMUX_CONF          tmux config file             (default: ~/.tmux.conf)
set -uo pipefail

# --- resolve this module's absolute dir (follow symlinks) ---
src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  d="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"; [[ $src != /* ]] && src="$d/$src"
done
MODULE_DIR="$(cd -P "$(dirname "$src")" && pwd)"

# Canonicalize a path through symlinks (BSD/macOS readlink has no -f). Returns the real
# file so writes target it directly instead of replacing a symlink with a regular file
# (which would orphan a dotfiles-managed config). Unchanged if missing or not a link.
resolve_link() {
  local p="$1" d t
  while [ -L "$p" ]; do
    d="$(cd -P "$(dirname "$p")" && pwd)"
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$d/$t" ;; esac
  done
  printf '%s\n' "$p"
}

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
SETTINGS="$(resolve_link "$CLAUDE_DIR/settings.json")"
TMUX_CONF="$(resolve_link "${TMUX_CONF:-$HOME/.tmux.conf}")"
MARKER="# >>> claude-tmux indicator >>>"

# --- 1. link the hook script into the Claude scripts dir ---
mkdir -p "$SCRIPTS_DIR"
ln -sf "$MODULE_DIR/claude-tmux-hook.sh" "$SCRIPTS_DIR/claude-tmux-hook.sh"
HOOK="bash $SCRIPTS_DIR/claude-tmux-hook.sh"
echo "hook:     linked -> $SCRIPTS_DIR/claude-tmux-hook.sh"

# --- 2. merge the 3 lifecycle hooks into settings.json (idempotent) ---
if ! command -v jq >/dev/null 2>&1; then
  echo "settings: jq not found — add these to $SETTINGS manually:"
  echo "  UserPromptSubmit -> command: \"$HOOK busy\""
  echo "  Stop / SessionEnd -> command: \"$HOOK idle\""
else
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  tmp="$(mktemp)"
  if jq \
    --arg busy "$HOOK busy" \
    --arg idle "$HOOK idle" '
      def present(event; cmd):
        ([.hooks[event][]?.hooks[]?.command] | index(cmd)) != null;
      def ensure(event; cmd):
        if present(event; cmd) then .
        else .hooks[event] = ((.hooks[event] // [])
          + [{matcher:"",hooks:[{type:"command",command:cmd,timeout:2}]}]) end;
      (.hooks //= {})
      | ensure("UserPromptSubmit"; $busy)
      | ensure("Stop"; $idle)
      | ensure("SessionEnd"; $idle)
    ' "$SETTINGS" > "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$SETTINGS"
    echo "settings: hooks merged into $SETTINGS"
  else
    rm -f "$tmp"; echo "settings: jq merge FAILED — $SETTINGS left unchanged" >&2; exit 1
  fi
fi

# --- 3. wire tmux.conf (idempotent via the marker block) ---
# Only the marker block is installer-managed, so uninstall.sh can always reverse it.
# A manual (markerless) wiring is left alone and warned about rather than duplicated.
if [ -f "$TMUX_CONF" ] && grep -qF "$MARKER" "$TMUX_CONF"; then
  echo "tmux:     already wired in $TMUX_CONF (skipped)"
elif [ -f "$TMUX_CONF" ] && grep -qF "claude-tmux-count.sh" "$TMUX_CONF"; then
  echo "tmux:     manual claude-tmux wiring found in $TMUX_CONF — NOT adding managed block." >&2
  echo "          Remove your manual lines and re-run to let install/uninstall manage it." >&2
else
  sed "s|__CLAUDE_TMUX_DIR__|$MODULE_DIR|g" "$MODULE_DIR/tmux.snippet.conf" >> "$TMUX_CONF"
  echo "tmux:     appended indicator block to $TMUX_CONF"
fi

echo
echo "Done. Reload tmux:  tmux source-file $TMUX_CONF"
echo "Hooks take effect on the NEXT Claude Code session (not this one)."
