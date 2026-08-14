
# PostgreSQL Backup to S3 (Docker)

This repository provides a **Docker container based on Alpine Linux** to perform **PostgreSQL backups** using `pg_dump`, compress them, and **upload to Amazon S3 (or S3-compatible storage)**.

The container ships with **its own cron scheduler**: start it once and it keeps running, executing a backup at every occurrence of `CRON_SCHEDULE`.

Backup behavior is **fully configurable via environment variables**, making it ideal for:

* Docker / Docker Compose
* ECS / Kubernetes / VM

---

## ✨ Features

* ✅ PostgreSQL backup with `pg_dump` (custom format)
* ✅ Dump integrity check with `pg_restore --list` before upload
* ✅ `tar.gz` compression
* ✅ Upload to S3 with `aws-cli` (custom endpoint supported)
* ✅ Built-in cron scheduler
* ✅ Staged logging, on stdout and on a persistent log file
* ✅ Configuration **only via ENV**
* ✅ Alpine Linux (lightweight image)
* ✅ Configurable local retention

---

## 🔧 Environment Variables

### 🔴 Required

| Variable                | Description                    |
| ----------------------- | ------------------------------ |
| `PGHOST`                | PostgreSQL host                |
| `PGPORT`                | PostgreSQL port                |
| `PGUSER`                | PostgreSQL user                |
| `PGPASSWORD`            | PostgreSQL password            |
| `PGDATABASE`            | PostgreSQL database name       |
| `S3_BUCKET`             | S3 bucket name                 |
| `S3_PREFIX`             | Path prefix in the bucket      |
| `AWS_ACCESS_KEY_ID`     | AWS Access Key                 |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Key                 |
| `AWS_DEFAULT_REGION`    | AWS region (e.g. `eu-north-1`) |
| `INTERVAL`              | Local retention (days)         |

### ⚪ Optional

| Variable            | Default                | Description                                                                 |
| ------------------- | ---------------------- | --------------------------------------------------------------------------- |
| `CRON_SCHEDULE`     | `0 2 * * *`            | Cron expression (5 fields, or a shortcut such as `@daily`). **Times are UTC** |
| `RUN_ON_START`      | `false`                | Run one backup immediately at container start, to validate the configuration |
| `S3_ENDPOINT_URL`   | _(empty)_              | Endpoint for S3-compatible storage (MinIO, Cloudflare R2, …)                 |
| `PGCONNECT_TIMEOUT` | `10`                   | Connection timeout in seconds                                                |
| `BACKUP_ROOT`       | `/postgredb/backup`    | Local directory holding the archives                                         |
| `LOG_FILE`          | `/postgredb/backup.log` | Persistent log file (rotated to `.1`)                                       |
| `LOG_MAX_BYTES`     | `5242880`              | Size at which `LOG_FILE` is rotated                                          |
| `LOG_COLOR`         | `always` (in image)    | `auto` \| `always` \| `never`                                                |
| `CRON_LOG`          | `/proc/1/fd/1` (in image) | Where the cron job writes its output (PID 1 stdout → `docker logs`)       |

---

## 🐳 Docker

### ▶️ Build the image

The Dockerfile lives in `ci/`, so it must be passed with `-f`:

```bash
docker build -f ci/Dockerfile -t postgres-backup-s3 .
```

---

### ▶️ Run with `docker run`

The container is long-running: it installs the cron job and stays up.

```bash
docker run -d --name postgres-backup \
  -e PGHOST="127.0.0.1" \
  -e PGPORT="5432" \
  -e PGUSER="user" \
  -e PGPASSWORD="password" \
  -e PGDATABASE="mydb" \
  -e S3_BUCKET="my-backup-bucket" \
  -e S3_PREFIX="postgres" \
  -e AWS_ACCESS_KEY_ID="AKIA..." \
  -e AWS_SECRET_ACCESS_KEY="SECRET..." \
  -e AWS_DEFAULT_REGION="eu-north-1" \
  -e INTERVAL=7 \
  -e CRON_SCHEDULE="0 2 * * *" \
  -e RUN_ON_START=true \
  -v "$(pwd)/backups:/postgredb" \
  ghcr.io/lbd-core/postgresqldump:latest
```

Archives are stored locally under `./backups/backup/` and uploaded to S3. The log is kept at `./backups/backup.log`.

> With `RUN_ON_START=true` the first backup runs immediately, so a misconfiguration surfaces at startup instead of silently at 02:00. Keep it enabled for the first run, then disable it.

---

## 🧩 Docker Compose

### ▶️ `docker-compose.yml`

```yaml
services:

  postgres-backup:
    image: ghcr.io/lbd-core/postgresqldump:latest
    restart: unless-stopped
    environment:
      PGHOST: "127.0.0.1"
      PGPORT: "5432"
      PGUSER: "user"
      PGPASSWORD: "password"
      PGDATABASE: "mydb"
      S3_BUCKET: "my-backup-bucket"
      S3_PREFIX: "postgres"
      AWS_ACCESS_KEY_ID: "AKIA..."
      AWS_SECRET_ACCESS_KEY: "SECRET..."
      AWS_DEFAULT_REGION: "eu-north-1"
      INTERVAL: 7
      CRON_SCHEDULE: "0 2 * * *"
    volumes:
      - ./backups:/postgredb
```

### ▶️ Run

```bash
docker compose up -d
```

To trigger a backup manually, without waiting for the schedule:

```bash
docker compose exec postgres-backup /app/backup.sh
```

---

## 📋 Logs

Every run is logged stage by stage, both on stdout (`docker logs -f postgres-backup`) and in `LOG_FILE`:

```text
2026-01-15T02:00:01Z [INFO ] [1/6] Checking PostgreSQL connectivity ...
2026-01-15T02:00:01Z [OK   ] [1/6] Checking PostgreSQL connectivity -> done in 0s | PostgreSQL server 16.2
2026-01-15T02:00:01Z [INFO ] [2/6] Dumping database (pg_dump --format=custom) ...
2026-01-15T02:00:48Z [OK   ] [2/6] Dumping database (pg_dump --format=custom) -> done in 47s | dump: 812M
2026-01-15T02:00:48Z [INFO ] [3/6] Verifying dump integrity ...
2026-01-15T02:00:52Z [OK   ] [3/6] Verifying dump integrity -> done in 4s | 214 tables with data in the dump
2026-01-15T02:00:52Z [INFO ] [4/6] Compressing archive ...
2026-01-15T02:01:20Z [OK   ] [4/6] Compressing archive -> done in 28s | archive: 806M
2026-01-15T02:01:20Z [INFO ] [5/6] Uploading to S3 ...
2026-01-15T02:03:05Z [OK   ] [5/6] Uploading to S3 -> done in 1m 45s | s3://my-backup-bucket/postgres/...
2026-01-15T02:03:05Z [INFO ] [6/6] Pruning local backups older than 7 days ...
2026-01-15T02:03:05Z [OK   ] [6/6] Pruning local backups older than 7 days -> done in 0s | 1 removed, 7 archives kept locally
2026-01-15T02:03:05Z [OK   ] BACKUP COMPLETED in 3m 04s
```

On failure the exact stage is reported and the script exits non-zero:

```text
2026-01-15T02:00:12Z [ERROR] BACKUP FAILED at stage [5/6] 'Uploading to S3' (exit 255, line 252)
2026-01-15T02:00:12Z [ERROR] No backup was uploaded to S3 for this run.
```

Grep for `[ERROR]` in `backup.log` to build an alert.

---

## 📁 S3 Structure

```text
s3://my-backup-bucket/
└── postgres/
  └── 2026-01-15_02-00/
    └── 2026-01-15_02-00.tar.gz
```

---

## 🔁 Restore

The archive contains `backup.dump` **at its root**, not inside a dated directory:

```bash
aws s3 cp \
    s3://my-backup-bucket/postgres/2026-01-15_02-00/2026-01-15_02-00.tar.gz \
    .

mkdir -p restore
tar -xzf 2026-01-15_02-00.tar.gz -C restore

pg_restore \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname="$PGDATABASE" \
  --verbose \
  restore/backup.dump
```

---

## 🗑 Retention

`INTERVAL` controls **local retention only**: archives older than `INTERVAL` days are removed from `BACKUP_ROOT` at the end of every run.

**Nothing is ever deleted from S3.** To cap remote growth, configure a lifecycle policy on the bucket, for example:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-backup-bucket \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-postgres-backups",
      "Filter": {"Prefix": "postgres/"},
      "Status": "Enabled",
      "Expiration": {"Days": 90}
    }]
  }'
```

---

## ⏱ Scheduling

Scheduling is **built into the container** via `CRON_SCHEDULE`; no external cron is required. Start the container once with `docker compose up -d` and leave it running.

Times are interpreted in **UTC**: the image does not include `tzdata`, so `0 2 * * *` means 02:00 UTC.

To inspect the installed job:

```bash
docker compose exec postgres-backup crontab -l
```

---

## ⚠️ Notes

* **PostgreSQL major version** — the image ships `postgresql16-client`. `pg_dump` refuses to dump a server whose major version is newer than its own, so to back up a PostgreSQL 17+ server the package in [`ci/Dockerfile`](ci/Dockerfile) must be bumped accordingly.
* **Credentials on disk** — cron does not inherit the container environment, so `schedule.sh` serializes the variables into `/app/backup.env` (mode `0600`) and the job reloads them before each run. The file contains `PGPASSWORD` and the AWS keys in plain text inside the container.
* **Concurrent runs** — a `flock` lock prevents a new backup from starting while a previous one is still running.
* **Manual run** — `backup.sh` can be executed standalone, provided the required variables are exported in the shell.
