#!/usr/bin/env bash
# server B: restore one test file from the newest backup into a separate folder
# and write its checksum where kalle can compare it with the original on A.
#
# run: sudo bash ~/linux-week4/setup/restore-test.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

FILE=var/www/html/backup-test.txt
RESULT=/home/kalle/restore-test-result.txt

latest=$(ls -1 /srv/backups/server-a/www-*.tar.gz | sort | tail -1)
dest=/home/backup/restore-test/$(date -u '+%Y-%m-%d_%H%M%S')

runuser -u backup -- mkdir -p "$dest"
runuser -u backup -- tar -xzf "$latest" -C "$dest" "$FILE"

{
    echo "restored at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "from:        $latest"
    echo "to:          $dest/$FILE"
    echo "sha256:      $(sha256sum "$dest/$FILE" | cut -d' ' -f1)"
    echo "content:     $(cat "$dest/$FILE")"
} | tee "$RESULT"
chown kalle:kalle "$RESULT"
