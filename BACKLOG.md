# BACKLOG — doctrine points to resolve

Doctrine points that are decided in principle but not yet fully written up
in `doctrine/STYLE.md` and the skills.

## Naming: function names vs script file names

- **Decided and applied (2026-10-09):** _function names_ use underscores
  between words. _Script file names_ never use underscores. All scripts in
  this repo and in `barzel-cluster` are renamed.
- **Rationale written (2026-10-14):** a file name identifies the file's
  purpose or the functions it holds (`includes/roll-func.sh`, not
  `includes/roll.sh`). STYLE.md §1.1 and the `bash-doctrine` skill say so.
  The earlier URL argument is removed: RFC 3986 allows `_` in a URL path,
  so it had no instrument behind it.
- **To do:**
  - Apply the rule to `includes/`: which files hold only functions, and what
    suffix they get (`-func.sh` is the example). `runlib.sh` and `error.sh`
    are vendored into `barzel-cluster` (pinned by tag), so a rename there is
    a coordinated change.
  - Callers outside these repos that source a renamed file by its old name
    (dotfiles, cron, other machines).
