while true; do
  pr=$(
    gh pr list --limit 50 \
      --json number,title,author,headRefName \
      --template '{{range .}}#{{.number}} {{.title}} ({{.author.login}}) [{{.headRefName}}]{{"\n"}}{{end}}' \
      | fzf --preview 'gh pr view {1} --comments' \
        --preview-window=right:60%:wrap \
        --header 'enter: view | ctrl-m: merge | ctrl-x: close | ctrl-o: checkout | ctrl-b: browser' \
        --bind 'ctrl-o:execute(gh pr checkout {1})' \
        --bind 'ctrl-b:execute(gh pr view {1} --web)' \
        --expect=ctrl-m,ctrl-x,enter
  )

  [[ -z "$pr" ]] && exit 0

  key=$(echo "$pr" | head -1)
  selection=$(echo "$pr" | tail -1)
  num=$(echo "$selection" | grep -o '#[0-9]*' | tr -d '#')

  [[ -z "$num" ]] && exit 0

  case "$key" in
    ctrl-m)
      read -r -p "Merge PR #$num? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        gh pr merge "$num" --merge
      fi
      ;;
    ctrl-x)
      read -r -p "Close PR #$num? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        gh pr close "$num"
      fi
      ;;
    enter|"")
      gh pr view "$num"
      ;;
  esac
done
