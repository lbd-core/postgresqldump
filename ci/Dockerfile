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

COPY backup.sh schedule.sh entrypoint.sh /app/
RUN chmod +x /app/backup.sh /app/schedule.sh /app/entrypoint.sh

# cron detaches the job from any terminal, so its output must be redirected.
# CRON_LOG points at PID 1's stdout (crond): each backup's output therefore ends
# up in `docker logs`, and nothing is written to the filesystem.
ENV CRON_LOG=/proc/1/fd/1 \
    LOG_COLOR=always \
    RUN_ON_START=false

# entrypoint.sh installs the cron job and supervises crond as a child process,
# so that crond never becomes PID 1 (see the comments in that script).
# PID 1 stays the entrypoint shell, hence /proc/1/fd/1 is still the console.
ENTRYPOINT ["/app/entrypoint.sh"]
