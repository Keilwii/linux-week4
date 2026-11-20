#!/usr/bin/env bash
# server B: keep only the newest 48 backups (about 2 days of hourly ones)
# installed as /usr/local/bin/prune-backups.sh, run by the backup user's cron

set -euo pipefail
KEEP=48
cd /srv/backups/server-a
ls -1 www-*.tar.gz 2>/dev/null | sort -r | tail -n +$((KEEP + 1)) | xargs -r rm -f --
