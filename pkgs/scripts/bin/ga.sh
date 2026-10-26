if [[ $# -eq 0 ]]; then
  git add .
else
  git add "$@"
fi
