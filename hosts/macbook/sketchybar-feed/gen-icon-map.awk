# Turns sketchybar-app-font's icon_map.sh (a bash case statement) into a C
# table at build time. Each case label becomes one row; a trailing `*` glob
# becomes a prefix match. Output: static const struct icon_map_entry[].
BEGIN { print "struct icon_map_entry { const char *name; int prefix; const char *icon; };"; print "static const struct icon_map_entry icon_map[] = {"; n = 0 }
/^### END-OF-ICON-MAP/ { exit }
/^[[:space:]]*"/ && /\)[[:space:]]*$/ {
  n = 0; line = $0
  while (match(line, /"[^"]*"\*?/)) {
    tok = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
    prefix = (substr(tok, length(tok)) == "*") ? 1 : 0
    if (prefix) tok = substr(tok, 1, length(tok) - 1)
    name = substr(tok, 2, length(tok) - 2)
    gsub(/\\/, "\\\\", name)
    names[n] = name; prefixes[n] = prefix; n++
  }
  next
}
/icon_result=/ {
  match($0, /:[^:"]*:/); icon = substr($0, RSTART, RLENGTH)
  for (i = 0; i < n; i++) printf "  { \"%s\", %d, \"%s\" },\n", names[i], prefixes[i], icon
  n = 0
}
END { print "};"; print "#define ICON_MAP_COUNT (sizeof(icon_map) / sizeof(icon_map[0]))" }
