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

# cron detaches the job from any terminal, so its output must be redirected.
# CRON_LOG points at PID 1's stdout (crond): each backup's output therefore ends
# up in `docker logs`, and nothing is written to the filesystem.
ENV CRON_LOG=/proc/1/fd/1 \
    LOG_COLOR=always \
    RUN_ON_START=false

# schedule.sh installs the cron job and fails loudly if it cannot; crond then
# runs in the foreground, so the container dies if the daemon does.
#
# Deliberately NOT `exec crond`: crond calls setpgid(0,0) at startup, which
# fails with EPERM for PID 1 (already a session leader) and kills the container
# with "setpgid: Operation not permitted". Keeping bash as PID 1 makes crond a
# child process, for which setpgid succeeds. /proc/1/fd/1 then refers to bash's
# stdout, which is still the container console.
ENTRYPOINT ["/bin/bash", "-c", "/app/schedule.sh && crond -f -L /dev/stdout"]
