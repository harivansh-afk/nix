base=$(git rev-parse --abbrev-ref HEAD)
upstream="${1:-main}"
remote_ref="origin/$upstream"
unpushed=$(git log "$remote_ref"..HEAD --oneline 2>/dev/null)

if [[ -z "$unpushed" ]]; then
  if git diff --cached --quiet; then
    echo "No unpushed commits and no staged changes"
    exit 1
  fi

  echo "No unpushed commits, but staged changes found. Opening commit dialog..."
  git commit
fi

msg=$(git log "$remote_ref"..HEAD --format='%s' --reverse | head -1)
branch=$(echo "$msg" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

git checkout -b "$branch"
git checkout "$base"
git reset --hard "$remote_ref"
git checkout "$branch"

git push -u origin "$branch"
gh pr create --base "$upstream" --fill --web 2>/dev/null || gh pr create --base "$upstream" --fill
gh pr view "$branch" --json url -q '.url'
