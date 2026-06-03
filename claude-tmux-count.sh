#!/bin/bash
# Poller for the tmux claude-agent indicator.
# Invoked from status-right via #(...) every status-interval. Emits nothing.
#   - Sets window option @claude_count = number of distinct claude agents in the window
#     (claude anywhere in a pane's process tree; a claude child of claude is not double-counted).
#   - Reconciles @claude_busy: clears stale pane flags whose claude process is gone
#     (recovers from kill -9 where the Stop hook never fired), then recomputes window flags.

pane_map=$(tmux list-panes -a -F '#{window_id} #{pane_id} #{pane_pid}')
ps_out=$(ps -axo pid=,ppid=,comm=)

# awk emits two record types:
#   WCOUNT <window_id> <agent_count>
#   PANE   <pane_id> <claude_present 0|1>
parsed=$(printf '%s\nPSDELIM\n%s\n' "$pane_map" "$ps_out" | awk '
  $1=="PSDELIM" { mode=1; next }
  mode!=1 {
    # window_id pane_id pane_pid
    pane_of_pid[$3]=$2          # pane_pid -> pane_id
    win_of_pane[$2]=$1          # pane_id  -> window_id
    panes[++np]=$2              # ordered pane_id list
    next
  }
  {
    pid=$1; pp=$2; c=$3; sub(/.*\//,"",c)
    parent[pid]=pp; name[pid]=c
  }
  END {
    for (pid in name) {
      if (name[pid]=="claude" && name[parent[pid]]!="claude") {
        p=pid
        while ((p in parent) && !(p in pane_of_pid) && p>1) p=parent[p]
        if (p in pane_of_pid) {
          paneid=pane_of_pid[p]
          panehas[paneid]=1
          wcount[win_of_pane[paneid]]++
        }
      }
    }
    for (i=1;i<=np;i++) seenw[win_of_pane[panes[i]]]=1
    for (w in seenw) printf "WCOUNT %s %d\n", w, wcount[w]+0
    for (i=1;i<=np;i++) printf "PANE %s %d\n", panes[i], (panes[i] in panehas)?1:0
  }
')

# Apply per-window agent counts (unset when zero so the tab stays clean).
echo "$parsed" | grep '^WCOUNT ' | while read -r _ wid n; do
  if [ "$n" -gt 0 ]; then tmux set -w -t "$wid" @claude_count "$n"
  else tmux set -w -t "$wid" -u @claude_count; fi
done

# Stale busy cleanup: clear pane @claude_pane_busy where no claude process is present.
# (Per-pane flag is @claude_pane_busy to avoid pane->window option inheritance; the
# window display flag @claude_busy is recomputed from it below.)
echo "$parsed" | grep '^PANE ' | while read -r _ pid present; do
  if [ "$present" = "0" ]; then
    cur=$(tmux show -pqv -t "$pid" @claude_pane_busy 2>/dev/null)
    [ -n "$cur" ] && tmux set -p -t "$pid" -u @claude_pane_busy
  fi
done

# Recompute window @claude_busy from surviving pane flags.
tmux list-panes -a -F '#{window_id} #{@claude_pane_busy}' | awk '
  { if ($2=="1") b[$1]++; seen[$1]=1 }
  END { for (w in seen) printf "%s %d\n", w, b[w]+0 }
' | while read -r wid n; do
  if [ "$n" -gt 0 ]; then tmux set -w -t "$wid" @claude_busy "$n"
  else tmux set -w -t "$wid" -u @claude_busy; fi
done
