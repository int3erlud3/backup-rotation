#!/usr/bin/env bats
# Tests for backup-rotation. Each test uses an isolated temp directory.

setup() {
  BR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/backup-rotation"
  SRC="$BATS_TEST_TMPDIR/src"; DEST="$BATS_TEST_TMPDIR/dest"
  mkdir -p "$SRC/sub" "$DEST"
  echo "hello" >"$SRC/a.txt"
  echo "noise" >"$SRC/sub/debug.log"
}

backup_on() { BACKUP_DATE="$1" run "$BR" -s "$SRC" -d "$DEST" "${@:2}"; }

@test "--help exits 0" {
  run "$BR" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "creates a daily tar.gz with a valid sha256 file" {
  backup_on 2026-10-06
  [ "$status" -eq 0 ]
  archive=$(ls "$DEST"/daily/backup-daily-20261006-*.tar.gz)
  [ -f "$archive.sha256" ]
  (cd "$DEST/daily" && sha256sum -c "$(basename "$archive").sha256")
}

@test "GFS tier: Sunday -> weekly, 1st of month -> monthly" {
  backup_on 2026-10-04          # Sunday
  [ "$status" -eq 0 ]
  ls "$DEST"/weekly/backup-weekly-20261004-*.tar.gz
  backup_on 2026-11-01          # 1st of month (also a Sunday: monthly wins)
  [ "$status" -eq 0 ]
  ls "$DEST"/monthly/backup-monthly-20261101-*.tar.gz
}

@test "--weekly-day changes the weekly tier day" {
  backup_on 2026-10-05 --weekly-day 1   # Monday
  [ "$status" -eq 0 ]
  ls "$DEST"/weekly/
}

@test "retention keeps only the newest N daily backups" {
  for d in 2026-10-05 2026-10-06 2026-10-07 2026-10-08; do
    backup_on "$d" --keep-daily 2
    [ "$status" -eq 0 ]
  done
  [ "$(find "$DEST/daily" -name '*.tar.gz' | wc -l)" -eq 2 ]
  [ "$(find "$DEST/daily" -name '*.sha256' | wc -l)" -eq 2 ]
  ls "$DEST"/daily/backup-daily-20261008-*.tar.gz
}

@test "retention never touches unrelated files" {
  echo keep >"$DEST/daily-notes.txt"
  mkdir -p "$DEST/daily"; echo keep >"$DEST/daily/README"
  for d in 2026-10-06 2026-10-07; do backup_on "$d" --keep-daily 0; done
  [ -f "$DEST/daily/README" ]
  [ -f "$DEST/daily-notes.txt" ]
}

@test "--exclude is honoured" {
  backup_on 2026-10-06 -e '*.log'
  [ "$status" -eq 0 ]
  run tar -tzf "$(ls "$DEST"/daily/*.tar.gz)"
  [[ "$output" == *"a.txt"* ]]
  [[ "$output" != *"debug.log"* ]]
}

@test "--dry-run changes nothing" {
  backup_on 2026-10-06 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  [ -z "$(ls -A "$DEST")" ]
}

@test "rsync mode creates hard-linked snapshots" {
  command -v rsync >/dev/null || skip "rsync not installed"
  backup_on 2026-10-06 -m rsync
  [ "$status" -eq 0 ]
  backup_on 2026-10-07 -m rsync
  [ "$status" -eq 0 ]
  links=$(stat -c %h "$(ls -d "$DEST"/daily/backup-daily-20261007-*/)a.txt")
  [ "$links" -ge 2 ]
}

@test "--verify detects a corrupted archive" {
  backup_on 2026-10-06
  run "$BR" -d "$DEST" --verify
  [ "$status" -eq 0 ]
  echo garbage >>"$(ls "$DEST"/daily/*.tar.gz)"
  run "$BR" -d "$DEST" --verify
  [ "$status" -ne 0 ]
}

@test "lock prevents concurrent runs" {
  exec 8>>"$DEST/.backup-rotation.lock"
  flock -n 8
  backup_on 2026-10-06
  [ "$status" -ne 0 ]
  [[ "$output" == *"another backup is running"* ]]
  exec 8>&-
}

@test "log file is written with restrictive permissions" {
  backup_on 2026-10-06 -l "$BATS_TEST_TMPDIR/backup.log"
  [ "$status" -eq 0 ]
  grep -q "backup complete" "$BATS_TEST_TMPDIR/backup.log"
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/backup.log")" = "600" ]
}

@test "input validation" {
  run "$BR" -s "$SRC";                                    [ "$status" -ne 0 ]
  run "$BR" -s relative/path -d "$DEST";                  [ "$status" -ne 0 ]
  run "$BR" -s "$SRC" -d "$DEST" -m zip;                  [ "$status" -ne 0 ]
  run "$BR" -s "$SRC" -d "$DEST" -p '../evil';            [ "$status" -ne 0 ]
  run "$BR" -s "$SRC" -d "$DEST" --keep-daily -1;         [ "$status" -ne 0 ]
  run "$BR" -s "$SRC" -d "$BATS_TEST_TMPDIR/missing";     [ "$status" -ne 0 ]
  run "$BR" -s "$BATS_TEST_TMPDIR" -d "$DEST";            [ "$status" -ne 0 ]  # overlap
}

@test "metacharacters in paths are not interpreted by a shell" {
  weird="$BATS_TEST_TMPDIR/src \$(touch pwned); x"
  mkdir -p "$weird"; echo data >"$weird/f"
  cd "$BATS_TEST_TMPDIR"
  BACKUP_DATE=2026-10-06 run "$BR" -s "$weird" -d "$DEST"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}
