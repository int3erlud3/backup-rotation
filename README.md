# backup-rotation

[![CI](https://github.com/int3erlud3/backup-rotation/actions/workflows/ci.yml/badge.svg)](https://github.com/int3erlud3/backup-rotation/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A small, auditable Bash backup tool with **Grandfather-Father-Son (GFS)** retention.
It creates `tar.gz` archives or `rsync` hard-link snapshots, writes SHA-256
checksums, supports a dry-run mode, prevents overlapping runs with a lock file and
logs every action.

## Features

- **Two modes**: compressed `tar.gz` archives (multiple sources) or space-efficient
  `rsync --link-dest` snapshots (unchanged files are hard links)
- **GFS retention**: 1st of month → `monthly/`, weekly day (default Sunday) →
  `weekly/`, otherwise `daily/`; separate keep counts per tier
- **Integrity**: `.sha256` file per backup and a `--verify` mode
- **Safe operation**: `--dry-run`, `flock`-based lock file, atomic rename of
  finished backups (`.partial` → final name), `umask 077`
- **Logging** to stderr and optionally to a log file
- Retention only ever deletes entries matching the strict backup name pattern

## Requirements

Bash ≥ 4.4, GNU coreutils/findutils, GNU tar, `flock` (util-linux); `rsync` for rsync mode.

## Installation

```bash
git clone https://github.com/int3erlud3/backup-rotation.git
sudo install -m 0755 backup-rotation/bin/backup-rotation /usr/local/bin/
sudo install -d -m 0700 /var/backups/rotation
```

Optional systemd units: [`examples/backup-rotation.service`](examples/backup-rotation.service)
and [`examples/backup-rotation.timer`](examples/backup-rotation.timer).

## Usage

```bash
# Preview what would happen
backup-rotation -s /etc -s /srv/www -d /var/backups/rotation --dry-run

# tar.gz backup of /etc and /srv/www, exclude temp files, keep 7/4/12
backup-rotation -s /etc -s /srv/www -d /var/backups/rotation -e '*.tmp' \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 12 -l /var/log/backup-rotation.log

# rsync hard-link snapshots of a single directory
backup-rotation -m rsync -p www -s /srv/www -d /var/backups/rotation

# Verify all checksums
backup-rotation -d /var/backups/rotation --verify
```

Resulting layout:

```text
/var/backups/rotation/
├── daily/   backup-daily-20261007-023000.tar.gz  (+ .sha256)
├── weekly/  backup-weekly-20261004-023000.tar.gz (+ .sha256)
└── monthly/ backup-monthly-20261001-023000.tar.gz (+ .sha256)
```

Restore a tar backup:

```bash
cd /var/backups/rotation/daily && sha256sum -c backup-daily-20261007-023000.tar.gz.sha256
sudo tar -xzf backup-daily-20261007-023000.tar.gz -C /restore-target
```

## Configuration

| Option | Default | Description |
|---|---|---|
| `-s, --source PATH` | – | Absolute source path (repeatable; one in rsync mode) |
| `-d, --dest DIR` | – | Existing backup directory |
| `-m, --mode` | `tar` | `tar` or `rsync` |
| `-e, --exclude PATTERN` | – | Exclude pattern (repeatable) |
| `-p, --prefix NAME` | `backup` | Name prefix (`[A-Za-z0-9._-]`) |
| `--keep-daily/--keep-weekly/--keep-monthly` | `7/4/12` | Retention per tier |
| `--weekly-day N` | `7` | ISO weekday of weekly backups |
| `-n, --dry-run` | off | Print commands instead of running them |
| `-l, --log-file FILE` | – | Append log lines to FILE |
| `--lock-file FILE` | `DEST/.backup-rotation.lock` | Lock file location |

## Development

```bash
make lint   # shellcheck (script + bats tests)
make test   # bats-core tests in temporary directories
make scan   # gitleaks secret scan (needs Docker)
```

## Security notes

- Commands are executed from **argument arrays**, never via `eval` or shell strings;
  file names with spaces or shell metacharacters are handled safely (tested).
- Inputs are validated: absolute paths only, source/destination overlap is rejected,
  prefix and numbers are allow-listed.
- `umask 077`: archives, checksums and logs are created readable by the owner only.
  Backups may contain secrets (e.g. `/etc/shadow`) — keep the backup directory `0700`
  and encrypt off-site copies.
- Run with the least privilege that can read the sources. The example systemd unit
  uses `ProtectSystem=strict`, `NoNewPrivileges` and only `CAP_DAC_READ_SEARCH`.
- Deletion is restricted to names matching `PREFIX-(daily|weekly|monthly)-YYYYMMDD-HHMMSS`.

See [SECURITY.md](SECURITY.md).

## Limitations

- Local destinations only (mount remote storage or sync the backup dir off-site).
- In `--dry-run` mode retention is computed on existing backups only.

## License

[MIT](LICENSE)
