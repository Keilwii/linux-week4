#!/usr/bin/env bash
# server A: back up the website files to server B, run hourly by cron as kalle

set -uo pipefail

B_TARGET="backup@95.216.189.103:"   # rrsync on B puts files in /srv/backups/server-a
SSH_KEY="$HOME/.ssh/backup_to_b"
LOG="$HOME/backup.log"
SOURCES=(var/www/html var/www/week-1)

log() {
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') $*" >> "$LOG"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
name="www-$(date -u '+%Y-%m-%d_%H%M%S').tar.gz"

if ! tar -czf "$work/$name" -C / "${SOURCES[@]}" 2> "$work/err"; then
    log "FAIL $name tar: $(head -1 "$work/err")"
    exit 1
fi
size=$(du -h "$work/$name" | cut -f1)

if rsync -pt --chmod=F600 -e "ssh -i $SSH_KEY -o BatchMode=yes -o ConnectTimeout=20" \
        "$work/$name" "$B_TARGET" 2> "$work/err"; then
    log "OK   $name $size"
else
    log "FAIL $name upload: $(tail -1 "$work/err")"
    exit 1
fi
