#!/usr/bin/env bash
# server B: -wo alone still let A's key delete files with rsync --delete.
# add -no-del and -no-overwrite so A can only add new backups.
#
# run: sudo bash ~/linux-week4/setup/harden-backup-key-b.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

KEYS=/home/backup/.ssh/authorized_keys
grep -q -- '-no-del' "$KEYS" || sed -i 's/ -wo / -wo -no-del -no-overwrite /' "$KEYS"
cut -d'"' -f2 "$KEYS"
