# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's
[private vulnerability reporting](../../security/advisories/new) for this repository
instead. You can expect an initial response within 7 days.

## Security review notes

- No `eval`, no `source` of user-controlled files, no dynamic command strings.
- Every external input is validated with an allow-list regex.
- Least privilege: only needs read access to sources and write access to the backup directory.
- Retention deletes only strictly matching backup names; created files use `umask 077`.
- CI runs ShellCheck and a gitleaks secret scan on every push and pull request;
  GitHub Actions are pinned to commit SHAs and run with `contents: read` only.
