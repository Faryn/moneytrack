#!/usr/bin/env python3
"""Produce a closed, verified SQLite snapshot without copying live WAL files."""
import datetime
import os
import pathlib
import sqlite3

os.umask(0o077)
root = pathlib.Path("/var/backups/moneytrack")
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
temporary = root / (stamp + ".partial")
destination = root / (stamp + ".sqlite3")
with sqlite3.connect("file:/var/lib/moneytrack/moneytrack.sqlite3?mode=ro", uri=True) as source:
    target = sqlite3.connect(temporary)
    try:
        source.backup(target, pages=256, sleep=0.05)
        target.execute("PRAGMA journal_mode=DELETE")
        if target.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise RuntimeError("Backup integrity check failed")
    finally:
        target.close()
temporary.replace(destination)
print("Verified SQLite backup created:", destination.name)
