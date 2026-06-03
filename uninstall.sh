#!/usr/bin/env bash
# Reverses install.sh. Idempotent; safe to re-run.
set -uo pipefail

# Canonicalize a path through symlinks (BSD/macOS readlink has no -f) so edits write the
# real file instead of replacing a symlinked config with a regular file. See install.sh.
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
HOOK="bash $SCRIPTS_DIR/claude-tmux-hook.sh"

# 1. remove the hook symlink
rm -f "$SCRIPTS_DIR/claude-tmux-hook.sh" && echo "hook:     removed symlink"

# 2. strip the 3 hook entries from settings.json
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  if jq \
    --arg busy "$HOOK busy" \
    --arg idle "$HOOK idle" '
      def strip(event; cmd):
        if (.hooks[event]? | type) == "array"
        then .hooks[event] |= map(select((.hooks[]?.command) != cmd))
           | (if (.hooks[event] | length) == 0 then del(.hooks[event]) else . end)
        else . end;
      strip("UserPromptSubmit"; $busy)
      | strip("Stop"; $idle)
      | strip("SessionEnd"; $idle)
    ' "$SETTINGS" > "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$SETTINGS"; echo "settings: hook entries removed from $SETTINGS"
  else
    rm -f "$tmp"; echo "settings: jq edit FAILED — $SETTINGS left unchanged" >&2
  fi
fi

# 3. remove the marker-guarded block from tmux.conf
if [ -f "$TMUX_CONF" ] && grep -qF "# >>> claude-tmux indicator >>>" "$TMUX_CONF"; then
  tmp="$(mktemp)"
  sed '/# >>> claude-tmux indicator >>>/,/# <<< claude-tmux indicator <<</d' "$TMUX_CONF" > "$tmp"
  mv "$tmp" "$TMUX_CONF"
  echo "tmux:     removed indicator block from $TMUX_CONF (reload: tmux source-file $TMUX_CONF)"
else
  echo "tmux:     no marker block in $TMUX_CONF (manual lines, if any, left intact)"
fi
