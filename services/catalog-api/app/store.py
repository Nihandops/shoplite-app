"""PostgreSQL store + Redis queue. Both are injected into the app so tests can use fakes."""
import json
import logging
from contextlib import contextmanager
from typing import Optional

log = logging.getLogger(__name__)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS products (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL UNIQUE,
    price  NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    stock  INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0)
);
CREATE TABLE IF NOT EXISTS orders (
    id           SERIAL PRIMARY KEY,
    product_id   INTEGER NOT NULL REFERENCES products(id),
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    status       TEXT NOT NULL DEFAULT 'PENDING'
                 CHECK (status IN ('PENDING','PROCESSING','COMPLETED','FAILED')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS orders_status_idx ON orders(status);
"""

SEED_PRODUCTS = [
    ("Mechanical Keyboard", 79.99, 100000),
    ("Wireless Mouse", 24.50, 100000),
    ("27-inch Monitor", 229.00, 100000),
    ("USB-C Hub", 39.90, 100000),
    ("Noise-Cancelling Headphones", 149.00, 100000),
    ("Laptop Stand", 32.00, 100000),
    ("Webcam 1080p", 49.99, 100000),
    ("Desk Lamp", 27.75, 100000),
    ("External SSD 1TB", 99.00, 100000),
    ("Ergonomic Chair", 319.00, 100000),
    ("Bluetooth Speaker", 59.00, 100000),
    ("Smart Watch", 189.00, 100000),
]


def init_db(conn) -> None:
    """Create schema and seed products. Idempotent; safe with many replicas (advisory lock)."""
    with conn:
        with conn.cursor() as cur:
            cur.execute("SELECT pg_advisory_xact_lock(424242)")
            cur.execute(SCHEMA_SQL)
            cur.execute("SELECT count(*) FROM products")
            if cur.fetchone()[0] == 0:
                cur.executemany(
                    "INSERT INTO products (name, price, stock) VALUES (%s, %s, %s)"
                    " ON CONFLICT (name) DO NOTHING",
                    SEED_PRODUCTS,
                )
                log.info("seeded products", extra={"fields": {"count": len(SEED_PRODUCTS)}})


def _product(row) -> dict:
    return {"id": row[0], "name": row[1], "price": float(row[2]), "stock": row[3]}


def _order(row) -> dict:
    return {
        "id": row[0],
        "product_id": row[1],
        "quantity": row[2],
        "status": row[3],
        "created_at": row[4].isoformat() if row[4] else None,
        "completed_at": row[5].isoformat() if row[5] else None,
    }


class PgStore:
    def __init__(self, dsn: str, maxconn: int = 10):
        from psycopg2.pool import ThreadedConnectionPool

        self.pool = ThreadedConnectionPool(1, maxconn, dsn)

    @contextmanager
    def conn(self):
        c = self.pool.getconn()
        broken = False
        try:
            yield c
        except Exception:
            broken = c.closed != 0
            raise
        finally:
            self.pool.putconn(c, close=broken)

    def init(self) -> None:
        with self.conn() as c:
            init_db(c)

    def ping(self) -> bool:
        with self.conn() as c, c.cursor() as cur:
            cur.execute("SELECT 1")
            c.rollback()
            return True

    def list_products(self) -> list:
        with self.conn() as c, c:
            with c.cursor() as cur:
                cur.execute("SELECT id, name, price, stock FROM products ORDER BY id")
                return [_product(r) for r in cur.fetchall()]

    def get_product(self, product_id: int) -> Optional[dict]:
        with self.conn() as c, c:
            with c.cursor() as cur:
                cur.execute("SELECT id, name, price, stock FROM products WHERE id=%s", (product_id,))
                row = cur.fetchone()
                return _product(row) if row else None

    def create_order(self, product_id: int, quantity: int) -> dict:
        with self.conn() as c, c:
            with c.cursor() as cur:
                cur.execute(
                    "INSERT INTO orders (product_id, quantity, status) VALUES (%s, %s, 'PENDING')"
                    " RETURNING id, product_id, quantity, status, created_at, completed_at",
                    (product_id, quantity),
                )
                return _order(cur.fetchone())

    def set_status(self, order_id: int, status: str) -> None:
        with self.conn() as c, c:
            with c.cursor() as cur:
                cur.execute("UPDATE orders SET status=%s WHERE id=%s", (status, order_id))

    def get_order(self, order_id: int) -> Optional[dict]:
        with self.conn() as c, c:
            with c.cursor() as cur:
                cur.execute(
                    "SELECT id, product_id, quantity, status, created_at, completed_at"
                    " FROM orders WHERE id=%s",
                    (order_id,),
                )
                row = cur.fetchone()
                return _order(row) if row else None


class RedisQueue:
    def __init__(self, host: str, port: int, name: str):
        import redis

        self.name = name
        self.r = redis.Redis(host=host, port=port, socket_timeout=3, socket_connect_timeout=3)

    def ping(self) -> bool:
        return bool(self.r.ping())

    def push(self, message: dict) -> None:
        # LPUSH + worker BRPOP = FIFO
        self.r.lpush(self.name, json.dumps(message))

    def depth(self) -> int:
        return int(self.r.llen(self.name))
