FROM alpine:3.19

RUN apk add --no-cache bash curl tar gzip ca-certificates python3 py3-pip dcron
RUN apk add --no-cache aws-cli
RUN apk add --no-cache postgresql
WORKDIR /app
VOLUME /postgredb
COPY backup.sh /app/backup.sh
COPY schedule.sh /app/schedule.sh
RUN chmod +x /app/backup.sh /app/schedule.sh

# Start cron and run schedule.sh to set up the cron job, then keep container running
ENTRYPOINT ["/bin/bash", "-c", "crond && /app/schedule.sh && tail -f /dev/null"]
