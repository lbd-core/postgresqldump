#!/bin/bash
#
# PostgreSQL backup -> tar.gz -> S3.
#
# Every stage is logged twice:
#   - to stdout    (visible with `docker logs`)
#   - to $LOG_FILE (persisted on the volume, without colour codes)
#
set -euo pipefail

# =========================
# REQUIRED ENV VARS
# =========================
: "${PGHOST:?Missing PGHOST}"
: "${PGPORT:?Missing PGPORT}"
: "${PGUSER:?Missing PGUSER}"
: "${PGPASSWORD:?Missing PGPASSWORD}"
: "${PGDATABASE:?Missing PGDATABASE}"
: "${S3_BUCKET:?Missing S3_BUCKET}"
: "${S3_PREFIX:?Missing S3_PREFIX}"
: "${AWS_ACCESS_KEY_ID:?Missing AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Missing AWS_SECRET_ACCESS_KEY}"
: "${AWS_DEFAULT_REGION:?Missing AWS_DEFAULT_REGION}"
: "${INTERVAL:?Missing INTERVAL}"

# =========================
# OPTIONAL ENV VARS
# =========================
BACKUP_ROOT="${BACKUP_ROOT:-/postgredb/backup}"
LOG_FILE="${LOG_FILE:-/postgredb/backup.log}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-5242880}"   # 5 MiB, then rotated to .1
LOG_COLOR="${LOG_COLOR:-auto}"              # auto | always | never
S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-}"      # for S3-compatible storage (MinIO, R2, ...)
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"

readonly TOTAL_STAGES=6

# =========================
# LOGGING
# =========================
mkdir -p "$BACKUP_ROOT" "$(dirname "$LOG_FILE")"

# Basic rotation: keeps backup.log from growing without bound.
if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt "$LOG_MAX_BYTES" ]; then
  mv -f "$LOG_FILE" "$LOG_FILE.1"
fi
: >> "$LOG_FILE"

case "$LOG_COLOR" in
  always) USE_COLOR=1 ;;
  never)  USE_COLOR=0 ;;
  *)      if [ -t 1 ]; then USE_COLOR=1; else USE_COLOR=0; fi ;;
esac

if [ "$USE_COLOR" -eq 1 ]; then
  C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
  C_ERR=$'\033[31m';  C_OFF=$'\033[0m'
else
  C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_OFF=''
fi

_ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

_log() {
  local color="$1" level="$2" msg="$3" ts
  ts="$(_ts)"
  printf '%s%s [%-5s] %s%s\n' "$color" "$ts" "$level" "$msg" "$C_OFF"
  printf '%s [%-5s] %s\n' "$ts" "$level" "$msg" >> "$LOG_FILE"
}

log_info()  { _log "$C_INFO" "INFO"  "$1"; }
log_ok()    { _log "$C_OK"   "OK"    "$1"; }
log_warn()  { _log "$C_WARN" "WARN"  "$1"; }
log_error() { _log "$C_ERR"  "ERROR" "$1" >&2; }

_fmt_duration() {
  local s="$1"
  if   [ "$s" -ge 3600 ]; then printf '%dh %02dm %02ds' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
  elif [ "$s" -ge 60 ];   then printf '%dm %02ds' $((s / 60)) $((s % 60))
  else                         printf '%ds' "$s"
  fi
}

_human_size() { du -h "$1" 2>/dev/null | cut -f1 || true; }

# =========================
# STAGES
# =========================
STAGE=0
STAGE_NAME="startup"
STAGE_STARTED=0
RUN_STARTED="$(date -u +%s)"

stage_begin() {
  STAGE=$((STAGE + 1))
  STAGE_NAME="$1"
  STAGE_STARTED="$(date -u +%s)"
  log_info "[$STAGE/$TOTAL_STAGES] $STAGE_NAME ..."
}

stage_end() {
  local detail="${1:-}" elapsed
  elapsed=$(( $(date -u +%s) - STAGE_STARTED ))
  log_ok "[$STAGE/$TOTAL_STAGES] $STAGE_NAME -> done in $(_fmt_duration "$elapsed")${detail:+ | $detail}"
}

# =========================
# TRAPS: temp dir cleanup + diagnostics about the failed stage.
# Installed early so they also cover validation failures.
# =========================
FAIL_LINE=""

# Records the line of the first command that failed under `set -e`; the summary
# itself is emitted by on_exit, so it is identical for explicit `exit 1` too.
on_error() { FAIL_LINE="$1"; }

on_exit() {
  local code=$?

  if [ -n "${DEST_DIR:-}" ] && [ -d "$DEST_DIR" ]; then
    rm -rf "$DEST_DIR"
  fi

  if [ "$code" -ne 0 ]; then
    if [ "$STAGE" -eq 0 ]; then
      log_error "BACKUP FAILED during initialization (exit $code)"
    else
      log_error "BACKUP FAILED at stage [$STAGE/$TOTAL_STAGES] '$STAGE_NAME' (exit $code${FAIL_LINE:+, line $FAIL_LINE})"
    fi
    log_error "Elapsed before failure: $(_fmt_duration $(( $(date -u +%s) - RUN_STARTED )))"
    log_error "No backup was uploaded to S3 for this run."
  fi
}

trap 'on_error $LINENO' ERR
trap on_exit EXIT

# =========================
# VALIDATION
# =========================
_require_uint() {
  case "${2:-}" in
    ''|*[!0-9]*)
      log_error "$1 must be a non-negative integer (got: '${2:-}')"
      exit 1
      ;;
  esac
}
_require_uint INTERVAL "$INTERVAL"
_require_uint PGPORT "$PGPORT"

# =========================
# LOCK: prevents concurrent runs if a backup overruns its schedule window
# =========================
LOCK_FILE="${LOCK_FILE:-$BACKUP_ROOT/.backup.lock}"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log_warn "Another backup is already running (lock: $LOCK_FILE) - exiting without doing anything"
    exit 0
  fi
fi

# =========================
# PATHS
# =========================
DATE="$(date -u +"%Y-%m-%d_%H-%M")"
DEST_DIR="$BACKUP_ROOT/$DATE"
DUMP_FILE="$DEST_DIR/backup.dump"
ARCHIVE="$DEST_DIR.tar.gz"

S3_PREFIX_CLEAN="${S3_PREFIX#/}"
S3_PREFIX_CLEAN="${S3_PREFIX_CLEAN%/}"
S3_URI="s3://$S3_BUCKET/$S3_PREFIX_CLEAN/$DATE/$(basename "$ARCHIVE")"

# =========================
log_info "=================================================="
log_info "Starting PostgreSQL backup"
log_info "  database  : $PGDATABASE @ $PGHOST:$PGPORT (user: $PGUSER)"
log_info "  archive   : $ARCHIVE"
log_info "  bucket    : $S3_URI"
log_info "  retention : $INTERVAL days (local only, nothing is removed from S3)"
log_info "=================================================="

# =========================
stage_begin "Checking PostgreSQL connectivity"

if ! pg_isready \
      --host="$PGHOST" \
      --port="$PGPORT" \
      --username="$PGUSER" \
      --dbname="$PGDATABASE" \
      --timeout="$PGCONNECT_TIMEOUT" >/dev/null 2>&1; then
  log_error "PostgreSQL unreachable at $PGHOST:$PGPORT (timeout ${PGCONNECT_TIMEOUT}s)"
  exit 1
fi

SERVER_VERSION="$(psql \
  --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$PGDATABASE" \
  --tuples-only --no-align --command='SHOW server_version' 2>/dev/null || echo 'unknown')"

stage_end "PostgreSQL server $SERVER_VERSION"

# =========================
stage_begin "Dumping database (pg_dump --format=custom)"

mkdir -p "$DEST_DIR"

pg_dump \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --no-password \
  --format=custom \
  --file="$DUMP_FILE" \
  "$PGDATABASE"

if [ ! -s "$DUMP_FILE" ]; then
  log_error "pg_dump exited successfully but the dump is empty: $DUMP_FILE"
  exit 1
fi

stage_end "dump: $(_human_size "$DUMP_FILE")"

# =========================
stage_begin "Verifying dump integrity"

if ! pg_restore --list "$DUMP_FILE" > "$DEST_DIR/toc.txt" 2>/dev/null; then
  log_error "Dump is corrupt or unreadable by pg_restore: $DUMP_FILE"
  exit 1
fi
TABLE_COUNT="$(grep -c 'TABLE DATA' "$DEST_DIR/toc.txt" || true)"
rm -f "$DEST_DIR/toc.txt"

stage_end "$TABLE_COUNT tables with data in the dump"

# =========================
stage_begin "Compressing archive"

tar -czf "$ARCHIVE" -C "$DEST_DIR" .
rm -rf "$DEST_DIR"

stage_end "archive: $(_human_size "$ARCHIVE")"

# =========================
stage_begin "Uploading to S3"

aws_args=(s3 cp "$ARCHIVE" "$S3_URI" --only-show-errors)
if [ -n "$S3_ENDPOINT_URL" ]; then
  aws_args+=(--endpoint-url "$S3_ENDPOINT_URL")
fi
aws "${aws_args[@]}"

stage_end "$S3_URI"

# =========================
stage_begin "Pruning local backups older than $INTERVAL days"

# -mmin avoids the off-by-one of -mtime (+N means age > N days, not >= N).
# The archive just created is excluded explicitly, as a safeguard.
REMOVED=0
while IFS= read -r old; do
  [ -n "$old" ] || continue
  rm -f "$old"
  REMOVED=$((REMOVED + 1))
  log_info "         removed: $(basename "$old")"
done < <(find "$BACKUP_ROOT" \
            -maxdepth 1 -type f -name '*.tar.gz' \
            ! -name "$(basename "$ARCHIVE")" \
            -mmin "+$((INTERVAL * 1440))" -print)

# Removes leftover temp directories from interrupted runs.
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -exec rmdir {} + 2>/dev/null || true

KEPT="$(find "$BACKUP_ROOT" -maxdepth 1 -type f -name '*.tar.gz' | wc -l)"

stage_end "$REMOVED removed, $KEPT archives kept locally"

# =========================
TOTAL_ELAPSED=$(( $(date -u +%s) - RUN_STARTED ))
log_ok "=================================================="
log_ok "BACKUP COMPLETED in $(_fmt_duration "$TOTAL_ELAPSED")"
log_ok "  local archive : $ARCHIVE ($(_human_size "$ARCHIVE"))"
log_ok "  S3 object     : $S3_URI"
log_ok "=================================================="
