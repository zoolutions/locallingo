# Plans

There is no `docs/plans/` directory in this repository, and no plan file has
ever been committed. Plans live in **GitHub issues** on `zoolutions/locallingo`:
`/lode:plan` creates one with `gh issue create --title "…" --body-file <tmpfile>`
(a temp file, not an inline heredoc — code fences get mangled by shell
interpolation), and `/lode:lfg <issue-number>` executes it.

When a plan genuinely needs to be a file — too long for an issue, or drafted
before the work is scheduled — write it to `docs/plans/YYYY-MM-DD-<slug>.md`,
creating the directory, and leave it uncommitted unless the user asks for it.

Session handovers, gate reports and other scratch go in `../tmp/`, which is
git-ignored.
