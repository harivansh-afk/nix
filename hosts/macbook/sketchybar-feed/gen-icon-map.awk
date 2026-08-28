# Generates icon_map.h from sketchybar-app-font's icon_map.sh at build time.
#
# The input is a bash case statement. Each case looks like
#
#    "Activity Monitor" | "Aktivitätsanzeige")
#         icon_result=":activity_monitor:"
#         ;;
#    "Adobe Bridge"*)
#         icon_result=":adobe_bridge:"
#         ;;
#
# and becomes one C row per app name:
#
#    { "Activity Monitor", 0, ":activity_monitor:" },
#    { "Aktivitätsanzeige", 0, ":activity_monitor:" },
#    { "Adobe Bridge",      1, ":adobe_bridge:" },     <- 1 = prefix match
#
# The pattern line comes before its icon line, so names are collected first
# and flushed when the icon_result line arrives.

BEGIN {
  print "struct icon_map_entry { const char *name; int prefix; const char *icon; };"
  print "static const struct icon_map_entry icon_map[] = {"
  pending = 0
}

/^### END-OF-ICON-MAP/ { exit }

# A pattern line: one or more quoted names, optional trailing *, ending in ).
/^[[:space:]]*"/ && /\)[[:space:]]*$/ {
  rest = $0
  while (match(rest, /"[^"]*"\*?/)) {
    token = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)

    is_prefix = 0
    if (substr(token, length(token)) == "*") {
      is_prefix = 1
      token = substr(token, 1, length(token) - 1)
    }

    name = substr(token, 2, length(token) - 2)   # strip the quotes
    gsub(/\\/, "\\\\", name)                     # keep it a valid C literal

    names[pending] = name
    prefixes[pending] = is_prefix
    pending++
  }
  next
}

# The icon line that follows: emit every collected name with this icon.
/icon_result=/ {
  match($0, /:[^:"]*:/)
  icon = substr($0, RSTART, RLENGTH)
  for (i = 0; i < pending; i++) {
    printf "  { \"%s\", %d, \"%s\" },\n", names[i], prefixes[i], icon
  }
  pending = 0
}

END {
  print "};"
  print "#define ICON_MAP_COUNT (sizeof(icon_map) / sizeof(icon_map[0]))"
}
