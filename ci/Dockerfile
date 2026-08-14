FROM alpine:3.19

# postgresql16-client provides pg_dump / pg_restore / pg_isready / psql without
# pulling in the server (which the `postgresql` metapackage did).
# NOTE: the client major must be >= the server's; pg_dump 16 refuses to dump a
# PostgreSQL 17+ server. Bump this package accordingly.
RUN apk add --no-cache \
      bash \
      ca-certificates \
      tar \
      gzip \
      dcron \
      aws-cli \
      postgresql16-client

WORKDIR /app
VOLUME /postgredb

COPY backup.sh schedule.sh /app/
RUN chmod +x /app/backup.sh /app/schedule.sh

# CRON_LOG points at PID 1's stdout (crond), so each backup's output shows up in
# `docker logs` as well as in /postgredb/backup.log.
ENV CRON_LOG=/proc/1/fd/1 \
    LOG_COLOR=always \
    RUN_ON_START=false

# schedule.sh installs the cron job and fails loudly if it cannot; crond then
# stays in the foreground as PID 1, so Docker receives signals and the container
# dies if the daemon does.
ENTRYPOINT ["/bin/bash", "-c", "/app/schedule.sh && exec crond -f -L /dev/stdout"]
