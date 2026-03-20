if [[ $# -eq 0 ]]; then
  git add .
else
  git add "$@"
fi

if command -v critic >/dev/null 2>&1; then
  ( critic review 2>/dev/null & )
fi
