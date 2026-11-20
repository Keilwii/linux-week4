#!/usr/bin/env bash
# server B (Rocky Linux 10): MariaDB replica of A, read-only page at /viikko4/,
# and the backup user that receives A's website backups.
#
# needs from A first: ~/.week4-repl.env (replication password) and ~/.backup_from_a.pub
# run once: sudo bash ~/linux-week4/setup/setup-b.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

A_IP=46.62.229.94
REPO=/home/kalle/linux-week4
REPL_ENV=/home/kalle/.week4-repl.env
BACKUP_PUB=/home/kalle/.backup_from_a.pub
APP_DIR=/opt/week4-app
BACKUP_DIR=/srv/backups/server-a

[[ -s $REPL_ENV ]] || { echo "missing $REPL_ENV (copy it from A first)"; exit 1; }
[[ -s $BACKUP_PUB ]] || { echo "missing $BACKUP_PUB"; exit 1; }
# shellcheck source=/dev/null
source "$REPL_ENV"

gen_pass() {
    head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32
}

echo "== MariaDB 11.8 repo (Rocky's own is 10.11, older than A's 11.8)"
cat > /etc/yum.repos.d/mariadb.repo <<'EOF'
[mariadb-11.8]
name=MariaDB 11.8
baseurl=https://rpm.mariadb.org/11.8/rhel/10/$basearch
gpgkey=https://rpm.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF

echo "== packages"
dnf install -y MariaDB-server MariaDB-client nginx python3-PyMySQL rsync rsync-rrsync git tar

echo "== linux users"
id week4 &>/dev/null || useradd --system --no-create-home --shell /sbin/nologin week4
id backup &>/dev/null || useradd --create-home --shell /bin/bash --comment "backups from server A" backup
passwd -l backup >/dev/null

echo "== mariadb replica config"
install -m 644 "$REPO/replication/b-60-replica.cnf" /etc/my.cnf.d/60-replica.cnf
systemctl enable mariadb
systemctl restart mariadb
SOCKET=$(mariadb -N -e 'SELECT @@socket')

RO_PASS=$(gen_pass)
mariadb <<SQL
CREATE OR REPLACE USER 'week4ro'@'localhost' IDENTIFIED BY '$RO_PASS';
GRANT SELECT ON week2.* TO 'week4ro'@'localhost';
GRANT SLAVE MONITOR ON *.* TO 'week4ro'@'localhost';
SQL

if [[ -z $(mariadb -N -e 'SHOW SLAVE STATUS') ]]; then
    echo "== starting replication from A"
    # empty gtid position = start from the beginning of A's binlog,
    # which has the CREATE DATABASE/TABLE and the data
    mariadb <<SQL
SET GLOBAL gtid_slave_pos = '';
CHANGE MASTER TO
    MASTER_HOST = '$A_IP',
    MASTER_PORT = 3306,
    MASTER_USER = 'repl',
    MASTER_PASSWORD = '$REPL_PASS',
    MASTER_USE_GTID = slave_pos,
    MASTER_SSL = $REPL_SSL;
START SLAVE;
SQL
else
    echo "replication already configured, not changing it"
fi
rm -f "$REPL_ENV"

install -d -m 750 -o root -g week4 /etc/week4
( umask 027
  cat > /etc/week4/db.cnf <<EOF
[client]
user = week4ro
password = $RO_PASS
socket = $SOCKET
EOF
)
chown root:week4 /etc/week4/db.cnf
chmod 640 /etc/week4/db.cnf

echo "== backup storage and the restricted key for A"
install -d -m 755 -o root -g root /srv/backups
install -d -m 750 -o backup -g week4 "$BACKUP_DIR"
install -d -m 700 -o backup -g backup /home/backup/.ssh
RRSYNC=$(command -v rrsync)
printf 'restrict,command="%s -wo %s" %s\n' "$RRSYNC" "$BACKUP_DIR" "$(cat "$BACKUP_PUB")" \
    > /home/backup/.ssh/authorized_keys
chown backup:backup /home/backup/.ssh/authorized_keys
chmod 600 /home/backup/.ssh/authorized_keys
restorecon -R /home/backup/.ssh 2>/dev/null || true
install -m 755 "$REPO/backup/prune-backups.sh" /usr/local/bin/prune-backups.sh
crontab -u backup "$REPO/backup/crontab-b-backup.txt"
systemctl enable --now crond

echo "== page app"
install -d -m 750 -o kalle -g week4 "$APP_DIR"
install -m 640 -o kalle -g week4 "$REPO/b-app/app.py" "$REPO/b-app/index.html" "$APP_DIR/"
install -m 644 "$REPO/b-app/viikko4.service" /etc/systemd/system/viikko4.service
systemctl daemon-reload
systemctl enable viikko4
systemctl restart viikko4

echo "== nginx"
install -m 644 "$REPO/b-app/nginx-viikko4.conf" /etc/nginx/default.d/viikko4.conf
setsebool -P httpd_can_network_connect 1 2>/dev/null || true
nginx -t
systemctl enable nginx
systemctl restart nginx
if firewall-cmd --state &>/dev/null; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --reload
fi

echo "== check"
sleep 3
mariadb -e "SHOW SLAVE STATUS\G" | grep -E 'Slave_(IO|SQL)_Running:|Seconds_Behind|Last_(IO|SQL)_Error:'
mariadb -e "SELECT * FROM week2.counter" || true
curl -s http://127.0.0.1/viikko4/ | grep -o 'class="count">[^<]*' || echo "page check failed"
echo "done"
