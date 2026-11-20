#!/usr/bin/env bash
# server A (Ubuntu): MariaDB primary, move the week 2 counter from sqlite to MariaDB,
# firewall for port 3306 and a test file for the backups.
#
# run once: sudo bash ~/linux-week4/setup/setup-a.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

B_IP=95.216.189.103
REPO=/home/kalle/linux-week4
APP_DIR=/home/kalle/viikko2
SQLITE_DB=$APP_DIR/data/counter.db
REPL_ENV=/home/kalle/.week4-repl.env   # picked up by B's setup, then deleted

gen_pass() {
    head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32
}

echo "== packages"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q mariadb-server python3-pymysql

echo "== mariadb config (binlog on, listen for B)"
install -m 644 "$REPO/replication/a-60-replication.cnf" /etc/mysql/mariadb.conf.d/60-replication.cnf
systemctl enable mariadb
systemctl restart mariadb
SOCKET=$(mariadb -N -e 'SELECT @@socket')
HAVE_SSL=$(mariadb -N -e 'SELECT @@have_ssl')
echo "socket $SOCKET, ssl $HAVE_SSL"

echo "== week 2 database"
systemctl stop viikko2
if [[ -z $(mariadb -N -e "SHOW DATABASES LIKE 'week2'") ]]; then
    COUNT=$(python3 -c 'import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute("select value from counter where name = ?", ("visits",)).fetchone()[0])' "$SQLITE_DB")
    echo "moving count $COUNT from sqlite to MariaDB"
    # these go to the binlog, so B builds the same database from them
    mariadb <<SQL
CREATE DATABASE week2;
USE week2;
CREATE TABLE counter (
    name       VARCHAR(32) PRIMARY KEY,
    value      BIGINT      NOT NULL,
    updated_at DATETIME    NOT NULL
) ENGINE = InnoDB;
INSERT INTO counter VALUES ('visits', $COUNT, UTC_TIMESTAMP());
SQL
else
    echo "week2 database already exists, not touching the data"
fi

echo "== database users (not written to the binlog)"
APP_PASS=$(gen_pass)
REPL_PASS=$(gen_pass)
if [[ $HAVE_SSL == YES ]]; then REQUIRE="REQUIRE SSL"; REPL_SSL=1; else REQUIRE=""; REPL_SSL=0; fi
mariadb <<SQL
SET sql_log_bin = 0;
CREATE OR REPLACE USER 'week2app'@'localhost' IDENTIFIED BY '$APP_PASS';
GRANT SELECT, UPDATE ON week2.counter TO 'week2app'@'localhost';
CREATE OR REPLACE USER 'repl'@'$B_IP' IDENTIFIED BY '$REPL_PASS' $REQUIRE;
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'$B_IP';
SQL

install -d -m 750 -o root -g kalle /etc/week2
( umask 027
  cat > /etc/week2/db.cnf <<EOF
[client]
user = week2app
password = $APP_PASS
database = week2
socket = $SOCKET
EOF
)
chown root:kalle /etc/week2/db.cnf
chmod 640 /etc/week2/db.cnf

( umask 077
  printf 'REPL_PASS=%s\nREPL_SSL=%s\n' "$REPL_PASS" "$REPL_SSL" > "$REPL_ENV"
)
chown kalle:kalle "$REPL_ENV"

echo "== week 2 app: new code that uses MariaDB"
runuser -u kalle -- git -C "$APP_DIR" pull -q --ff-only
install -d /etc/systemd/system/viikko2.service.d
cat > /etc/systemd/system/viikko2.service.d/mariadb.conf <<'EOF'
[Unit]
After=mariadb.service
Wants=mariadb.service
EOF
systemctl daemon-reload
systemctl start viikko2
sleep 2

echo "== firewall: ssh + http for everyone, 3306 only from B"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow from "$B_IP" to any port 3306 proto tcp
ufw --force enable
ufw status

echo "== test file for the backup restore test"
echo "backup restore test file, created $(date -u '+%Y-%m-%d %H:%M:%S UTC') on server A" > /var/www/html/backup-test.txt
chmod 644 /var/www/html/backup-test.txt

echo "== check"
mariadb -e "SHOW MASTER STATUS; SELECT * FROM week2.counter;"
curl -s http://127.0.0.1/viikko2/ | grep -o 'class="count">[^<]*' || echo "week 2 page check failed"
echo "done"
