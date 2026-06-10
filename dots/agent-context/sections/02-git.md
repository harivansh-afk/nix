---
name: git
disclosure: always
---
## Git

- Never sign your name on commits.
- Do not add `Co-authored-by`, `Signed-off-by`, or any other personal or
  assistant attribution to commit messages.
- Always create task worktrees under the repo-local `.worktrees/<topic>`
  directory of the main checkout.
- Do not create sibling worktree directories like `<repo>-<topic>` or global
  worktree directories like `~/wt/<repo>/<topic>`.
- Create worktrees with plain Git from the main checkout:
  `git worktree add .worktrees/<topic> -b <branch> main`.
- Keep the main checkout on `main` unless the user explicitly asks otherwise.
