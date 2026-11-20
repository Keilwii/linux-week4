#!/usr/bin/env bash
# server B: sshd only allows kalle (AllowUsers kalle), so the backup user was refused.
# add backup, but only when connecting from server A's IP.
#
# run: sudo bash ~/linux-week4/setup/allow-backup-ssh-b.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

CONF=/etc/ssh/sshd_config.d/50-week4-backup.conf
echo "AllowUsers backup@46.62.229.94" > "$CONF"
chmod 600 "$CONF"

# AllowUsers lines add up, check that kalle is still allowed before reloading
if sshd -t && sshd -T | grep -qx 'allowusers kalle' && sshd -T | grep -qx 'allowusers backup@46.62.229.94'; then
    systemctl reload sshd
    sshd -T | grep '^allowusers'
    echo "done"
else
    rm -f "$CONF"
    echo "check failed, nothing changed"
    exit 1
fi
