#!/bin/bash
#
# Container entrypoint: installs the cron job, then supervises crond.
#
set -euo pipefail

/app/schedule.sh

# crond must NOT be PID 1. At startup it calls setpgid(0,0), which fails with
# EPERM when the caller is a session leader - and PID 1 in a container is one.
# The daemon then dies with "setpgid: Operation not permitted".
#
# Note that ENTRYPOINT ["/bin/bash", "-c", "... && crond -f"] is not enough:
# bash execs the last command of a -c string, so crond would become PID 1 even
# without an explicit `exec`. Starting it in the background and waiting keeps
# this script as PID 1 for good.
crond -f -L /dev/stdout &
CROND_PID=$!

# Forward termination signals, so `docker stop` does not have to wait for its
# timeout before the container goes down.
terminate() {
  kill -TERM "$CROND_PID" 2>/dev/null || true
  wait "$CROND_PID" 2>/dev/null || true
  exit 0
}
trap terminate TERM INT

# If crond dies on its own the container exits with its status, instead of
# lingering with no scheduler running.
wait "$CROND_PID"
