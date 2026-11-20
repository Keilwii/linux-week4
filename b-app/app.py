# week 4: read-only page on server B
# shows the week 2 counter from B's own replicated MariaDB, never writes anything

import html
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from string import Template

import pymysql
import pymysql.cursors

HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "8004"))
BASE_DIR = Path(__file__).resolve().parent
# week4ro db user: SELECT on week2 + SLAVE MONITOR, file not in git
DB_CNF = os.environ.get("DB_CNF", "/etc/week4/db.cnf")
BACKUP_DIR = Path(os.environ.get("BACKUP_DIR", "/srv/backups/server-a"))


def read_db():
    conn = pymysql.connect(
        read_default_file=DB_CNF,
        read_default_group="client",
        connect_timeout=3,
        # extra safety on top of the SELECT-only user and read_only=ON
        init_command="SET SESSION TRANSACTION READ ONLY",
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT value, updated_at FROM week2.counter WHERE name = 'visits'")
            counter = cur.fetchone()
            cur.execute("SHOW SLAVE STATUS")
            repl = cur.fetchone() or {}
            cur.execute("SELECT @@read_only AS read_only, @@version AS version")
            server = cur.fetchone()
        return counter, repl, server
    finally:
        conn.close()


def list_backups(limit=6):
    try:
        files = sorted(
            (f for f in BACKUP_DIR.iterdir() if f.name.endswith(".tar.gz")),
            key=lambda f: f.name,
            reverse=True,
        )
    except OSError as e:
        return 0, f"<tr><td colspan='2'>can't list backups: {html.escape(str(e))}</td></tr>"
    rows = []
    for f in files[:limit]:
        st = f.stat()
        rows.append(f"<tr><td><code>{html.escape(f.name)}</code></td><td>{st.st_size / 1024:.0f} KiB</td></tr>")
    return len(files), "\n".join(rows) or "<tr><td colspan='2'>no backups yet</td></tr>"


def yes_no(value):
    cls = "ok" if value == "Yes" else "bad"
    return f'<span class="{cls}">{html.escape(str(value or "-"))}</span>'


def render():
    values = {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        "count": "?",
        "updated_at": "-",
        "io_running": yes_no(None),
        "sql_running": yes_no(None),
        "behind": "-",
        "gtid": "-",
        "last_error": "none",
        "read_only": "?",
        "version": "?",
        "db_error": "",
    }
    try:
        counter, repl, server = read_db()
        if counter:
            values["count"] = f"{counter['value']:,}".replace(",", " ")
            values["updated_at"] = f"{counter['updated_at']} UTC"
        values["io_running"] = yes_no(repl.get("Slave_IO_Running"))
        values["sql_running"] = yes_no(repl.get("Slave_SQL_Running"))
        behind = repl.get("Seconds_Behind_Master")
        values["behind"] = "-" if behind is None else f"{behind} s"
        values["gtid"] = html.escape(str(repl.get("Gtid_IO_Pos") or "-"))
        err = repl.get("Last_IO_Error") or repl.get("Last_SQL_Error")
        values["last_error"] = html.escape(err) if err else "none"
        values["read_only"] = "ON" if server["read_only"] else "OFF"
        values["version"] = html.escape(server["version"])
    except Exception as e:
        values["db_error"] = f'<p class="bad">Database error: {html.escape(str(e))}</p>'

    count, rows = list_backups()
    values["backup_count"] = str(count)
    values["backup_rows"] = rows

    # read on every request so the page text can be updated without restarting
    template = Template((BASE_DIR / "index.html").read_text(encoding="utf-8"))
    return template.substitute(values)


class Handler(BaseHTTPRequestHandler):
    server_version = "Viikko4/1.0"

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self.respond(200, "ok\n", "text/plain")
        elif path in ("/", "/index.html"):
            self.respond(200, render(), "text/html")
        else:
            self.respond(404, "Not found\n", "text/plain")

    def respond(self, status, body, content_type):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def main():
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Listening on http://{HOST}:{PORT}, database config {DB_CNF}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
