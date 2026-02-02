
# PostgreSQL Backup to S3 (Docker)

This repository provides a **Docker container based on Alpine Linux** to perform **PostgreSQL backups** using `pg_dump`, compress them, and **upload to Amazon S3 (or S3-compatible storage)**.

Backup behavior is **fully configurable via environment variables**, making it ideal for:

* Docker / Docker Compose
* External cron
* ECS / Kubernetes / VM

---

## ✨ Features

* ✅ PostgreSQL backup with `pg_dump`
* ✅ `tar.gz` compression
* ✅ Upload to S3 with `aws-cli`
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
| `CRON_SCHEDULE`         | Cron string to schedule backup |

---

---

## 🐳 Docker


### ▶️ Build the image

```bash
docker build -t postgres-backup-s3 .
```

---


### ▶️ Run with `docker run`

```bash
docker run --rm \
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
  -e CRON_SCHEDULE="0 0 * * *"
  -v $(pwd)/backups:/postgredb \
  ghcr.io/lbd-core/postgresqldump:latest
```

Backups will be saved locally in `./backups` and uploaded to S3.

---

## 🧩 Docker Compose

### ▶️ `docker-compose.yml`

```yaml
version: "3.9"

services:

  postgres-backup:
    image: ghcr.io/lbd-core/postgresqldump:latest
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
      CRON_SCHEDULE: "0 0 * * *"
    volumes:
      - ./backups:/postgredb
```

### ▶️ Run

```bash
docker compose run --rm postgres-backup
```

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

```bash
aws s3 cp \
    s3://my-backup-bucket/postgres/2026-01-15_02-00/2026-01-15_02-00.tar.gz \
    .

tar -xzf 2026-01-15_02-00.tar.gz

pg_restore \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname="$PGDATABASE" \
  --verbose \
  2026-01-15_02-00/backup.dump
```

---

## ⏱ Scheduling (recommended)

Use an **external cron**:

```cron
0 2 * * * docker compose run --rm postgres-backup
```