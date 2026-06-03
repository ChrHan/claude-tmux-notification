# VHS script for the indicator demo GIF. Regenerate from the repo root:
#   brew install vhs   # one-time
#   vhs demo.tape      # writes assets/demo.gif and assets/demo.mp4
# Drives a dedicated tmux server (socket "claudedemo") — your real tmux is untouched.
Output assets/demo.gif
Output assets/demo.mp4
Require tmux

Set Shell "bash"
Set FontSize 18
Set Width 1180
Set Height 560
Set Padding 16
Set Framerate 10
Set Theme "Catppuccin Mocha"

Type "bash demo/launch.sh"
Enter
Sleep 26s
