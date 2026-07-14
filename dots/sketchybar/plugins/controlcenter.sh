#!/bin/bash
# Opens the native Control Center panel. Needs Accessibility permission for
# sketchybar (System Settings > Privacy & Security > Accessibility).

osascript <<'EOF'
tell application "System Events" to tell process "ControlCenter"
  repeat with mbi in menu bar items of menu bar 1
    if description of mbi contains "Control Center" then
      click mbi
      return
    end if
  end repeat
end tell
EOF
