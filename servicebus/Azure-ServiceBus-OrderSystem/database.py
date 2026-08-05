"""All SQLite operations for the order system.

The same database file is shared by the Flask app (writer of new 'Pending'
orders) and the worker (which flips orders to 'Processing' then 'Completed'
or 'Failed'). WAL mode is enabled so both processes can read/write smoothly.
"""
import os
import sqlite3
from datetime import datetime

from config import DB_PATH

STATUSES = ("Pending", "Processing", "Completed", "Failed")


def _connect() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    return conn


def init_db() -> None:
    """Create the orders table if it does not already exist."""
    with _connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS orders (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                customer     TEXT    NOT NULL,
                product      TEXT    NOT NULL,
                quantity     INTEGER NOT NULL,
                price        REAL    NOT NULL,
                priority     TEXT    NOT NULL DEFAULT 'Normal',
                status       TEXT    NOT NULL DEFAULT 'Pending',
                created_on   TEXT    NOT NULL,
                processed_on TEXT
            );
            """
        )
        conn.commit()


def create_order(customer, product, quantity, price, priority) -> int:
    """Insert a new order in 'Pending' state and return its id."""
    now = datetime.utcnow().isoformat(timespec="seconds")
    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO orders (customer, product, quantity, price, priority,
                                   status, created_on)
               VALUES (?, ?, ?, ?, ?, 'Pending', ?)""",
            (customer, product, int(quantity), float(price), priority, now),
        )
        conn.commit()
        return cur.lastrowid


def set_status(order_id: int, status: str, stamp_processed: bool = False) -> None:
    processed_on = datetime.utcnow().isoformat(timespec="seconds") if stamp_processed else None
    with _connect() as conn:
        if stamp_processed:
            conn.execute(
                "UPDATE orders SET status=?, processed_on=? WHERE id=?",
                (status, processed_on, order_id),
            )
        else:
            conn.execute("UPDATE orders SET status=? WHERE id=?", (status, order_id))
        conn.commit()


def get_orders(limit: int = 50):
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM orders ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
    return [dict(r) for r in rows]


def get_failed_orders():
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM orders WHERE status='Failed' ORDER BY id DESC"
        ).fetchall()
    return [dict(r) for r in rows]


def get_stats() -> dict:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT status, COUNT(*) AS n FROM orders GROUP BY status"
        ).fetchall()
        counts = {s: 0 for s in STATUSES}
        for r in rows:
            counts[r["status"]] = r["n"]
        total = conn.execute("SELECT COUNT(*) AS n FROM orders").fetchone()["n"]

        # Average processing time in seconds for completed orders.
        avg_row = conn.execute(
            """SELECT AVG(strftime('%s', processed_on) - strftime('%s', created_on)) AS avg_s
               FROM orders WHERE status='Completed' AND processed_on IS NOT NULL"""
        ).fetchone()
    avg_seconds = round(avg_row["avg_s"], 1) if avg_row["avg_s"] is not None else 0
    return {
        "total": total,
        "pending": counts["Pending"],
        "processing": counts["Processing"],
        "completed": counts["Completed"],
        "failed": counts["Failed"],
        "avg_seconds": avg_seconds,
    }


def clear_orders() -> None:
    with _connect() as conn:
        conn.execute("DELETE FROM orders")
        conn.execute("DELETE FROM sqlite_sequence WHERE name='orders'")
        conn.commit()


if __name__ == "__main__":
    init_db()
    print(f"Database ready at {DB_PATH}")
