# linux-week4

Week 4 assignment: second server, hourly website backups and MariaDB replication.

- Server A (Ubuntu 26.04, 46.62.229.94): week 2 counter at http://46.62.229.94/viikko2/, MariaDB primary
- Server B (Rocky Linux 10, 95.216.189.103): read-only replica page at http://95.216.189.103/viikko4/

The week 2 app's own change (sqlite -> MariaDB) is in [linux-week2](https://github.com/Keilwii/linux-week2).

## Files

| Path | What |
| --- | --- |
| `replication/a-60-replication.cnf` | A's MariaDB config: server_id, binlog, listen address |
| `replication/b-60-replica.cnf` | B's MariaDB config: read_only, relay log, only replicate `week2` |
| `replication/b-change-master.sql.example` | how B is pointed at A (password removed) |
| `backup/backup.sh` | A: tar the website and upload it to B, log OK/FAIL |
| `backup/crontab-a.txt` | kalle's crontab on A (week 3 report + hourly backup) |
| `backup/prune-backups.sh`, `backup/crontab-b-backup.txt` | B: keep the newest 48 backups |
| `b-app/` | B's read-only page: app, template, systemd unit, nginx route |
| `setup/setup-a.sh`, `setup/setup-b.sh` | one-time root setup for each server |
| `setup/restore-test.sh` | B: restore a test file from the newest backup |

## Setup order

1. On A: `sudo bash ~/linux-week4/setup/setup-a.sh`
2. Copy `~/.week4-repl.env` from A to B (the replication password, never in git) and A's backup public key to `~/.backup_from_a.pub` on B
3. On B: `sudo bash ~/linux-week4/setup/setup-b.sh`
4. On A: `crontab ~/linux-week4/backup/crontab-a.txt`

No passwords, keys, backups or SQL dumps are in this repo. The setup scripts generate the
database passwords on the servers and store them in root-owned files with mode 640.
