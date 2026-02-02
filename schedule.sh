#!/bin/bash

# Set default cron schedule if not provided
CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"

# Path to postgredump script
POSTGREDUMP_SCRIPT="$(dirname "$0")/backup.sh"

# Create a cron job to run the backup script periodically
# Write out current crontab
crontab -l > mycron 2>/dev/null
# Echo new cron into cron file
sed -i '/backup.sh/d' mycron
# Add new cron job
cat <<EOF >> mycron
$CRON_SCHEDULE bash "$POSTGREDUMP_SCRIPT"
EOF
# Install new cron file
crontab mycron
rm mycron

echo "Scheduled backup with cron: $CRON_SCHEDULE"
