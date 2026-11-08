"""ShopLite order-worker.

Consumes `orders:pending` (Redis list), simulates 1-2 s of work and updates the
order status in PostgreSQL. Continues the producer's trace via the W3C
traceparent carried inside each message. Shuts down gracefully on SIGTERM:
stops taking new messages and finishes the orders already in flight.
"""
import json
import logging
import os
import random
import signal
import threading
import time

from opentelemetry import propagate, trace
from prometheus_client import Counter, Gauge, Histogram, start_http_server

log = logging.getLogger("order-worker")
tracer = trace.get_tracer("order-worker")

ORDERS_PROCESSED = Counter("orders_processed_total", "Orders processed by the worker", ["result"])
PROCESSING_SECONDS = Histogram(
    "order_processing_seconds", "End-to-end processing time per order",
    buckets=(0.5, 1, 1.5, 2, 3, 5, 8, 13, 21, 34),
)
QUEUE_DEPTH = Gauge("order_queue_depth", "Messages waiting in orders:pending")
IN_FLIGHT = Gauge("order_worker_in_flight", "Orders currently being processed")


def _bool(name: str) -> bool:
    return os.getenv(name, "false").strip().lower() in ("1", "true", "yes", "on")


class Settings:
    def __init__(self):
        self.service = os.getenv("SERVICE_NAME", "order-worker")
        self.environment = os.getenv("ENVIRONMENT", "dev")
        self.queue = os.getenv("QUEUE_NAME", "orders:pending")
        self.concurrency = int(os.getenv("WORKER_CONCURRENCY", "4"))
        self.metrics_port = int(os.getenv("METRICS_PORT", "9100"))
        self.min_work = float(os.getenv("WORK_MIN_SECONDS", "1"))
        self.max_work = float(os.getenv("WORK_MAX_SECONDS", "2"))
        self.chaos_memory_leak = _bool("CHAOS_MEMORY_LEAK")
        self.chaos_slow_db = _bool("CHAOS_SLOW_DB")
        self.dsn = (
            f"host={os.getenv('DB_HOST', 'postgres')} port={os.getenv('DB_PORT', '5432')} "
            f"dbname={os.getenv('DB_NAME', 'shoplite')} user={os.getenv('DB_USER', 'shoplite')} "
            f"password={os.getenv('DB_PASSWORD', '')} connect_timeout=3"
        )
        self.redis_host = os.getenv("REDIS_HOST", "redis")
        self.redis_port = int(os.getenv("REDIS_PORT", "6379"))


# CHAOS_MEMORY_LEAK: grows forever, never released
_LEAK: list = []


class OrderProcessor:
    """Processes a single queue message. DB connection is injected (testable)."""

    def __init__(self, settings: Settings, sleep=time.sleep):
        self.s = settings
        self.sleep = sleep

    def _update(self, conn, sql: str, params: tuple):
        with conn:
            with conn.cursor() as cur:
                if self.s.chaos_slow_db:
                    cur.execute("SELECT pg_sleep(2)")
                cur.execute(sql, params)
                return cur.fetchone() if cur.description else None

    def process(self, conn, raw: bytes) -> str:
        msg = json.loads(raw)
        order_id = int(msg["order_id"])
        parent = propagate.extract(msg.get("trace") or {})
        start = time.perf_counter()
        result = "error"
        with tracer.start_as_current_span(
            "orders:pending process", context=parent, kind=trace.SpanKind.CONSUMER,
            attributes={"messaging.system": "redis", "messaging.destination.name": self.s.queue,
                        "order.id": order_id},
        ) as span:
            IN_FLIGHT.inc()
            try:
                log.info("order processing started", extra={"fields": {"order_id": order_id}})
                self._update(conn, "UPDATE orders SET status='PROCESSING' WHERE id=%s", (order_id,))

                with tracer.start_as_current_span("order.simulate_work"):
                    self.sleep(random.uniform(self.s.min_work, self.s.max_work))

                row = self._update(
                    conn,
                    """
                    WITH o AS (SELECT product_id, quantity FROM orders WHERE id=%s),
                         p AS (UPDATE products SET stock = stock - o.quantity FROM o
                               WHERE products.id = o.product_id AND products.stock >= o.quantity
                               RETURNING products.id)
                    UPDATE orders SET status = CASE WHEN EXISTS (SELECT 1 FROM p)
                                                    THEN 'COMPLETED' ELSE 'FAILED' END,
                                      completed_at = now()
                    WHERE id=%s RETURNING status
                    """,
                    (order_id, order_id),
                )
                status = row[0] if row else "FAILED"
                result = "completed" if status == "COMPLETED" else "failed"
                span.set_attribute("order.status", status)
                log.info("order processed", extra={"fields": {"order_id": order_id, "status": status}})
            except Exception as exc:  # noqa: BLE001
                span.record_exception(exc)
                span.set_status(trace.Status(trace.StatusCode.ERROR, str(exc)))
                log.exception("order processing error", extra={"fields": {"order_id": order_id}})
                try:
                    conn.rollback()
                    self._update(conn, "UPDATE orders SET status='FAILED', completed_at=now()"
                                       " WHERE id=%s", (order_id,))
                except Exception:  # noqa: BLE001
                    pass
            finally:
                IN_FLIGHT.dec()
                elapsed = time.perf_counter() - start
                ORDERS_PROCESSED.labels(result).inc()
                tid = format(span.get_span_context().trace_id, "032x")
                PROCESSING_SECONDS.observe(elapsed, exemplar={"trace_id": tid})
                if self.s.chaos_memory_leak:
                    _LEAK.append(b"x" * (1024 * 1024))  # 1 MiB retained per order
        return result


class Worker:
    def __init__(self, settings: Settings):
        import redis

        self.s = settings
        self.stop = threading.Event()
        self.redis = redis.Redis(host=settings.redis_host, port=settings.redis_port,
                                 socket_timeout=10, socket_connect_timeout=3)
        self.processor = OrderProcessor(settings)

    def _connect(self):
        import psycopg2

        while not self.stop.is_set():
            try:
                return psycopg2.connect(self.s.dsn)
            except Exception as exc:  # noqa: BLE001
                log.warning(f"database not ready: {exc}")
                time.sleep(2)
        return None

    def loop(self, idx: int) -> None:
        conn = self._connect()
        while not self.stop.is_set():
            try:
                item = self.redis.brpop([self.s.queue], timeout=2)
            except Exception as exc:  # noqa: BLE001
                log.warning(f"redis error: {exc}")
                time.sleep(1)
                continue
            if not item:
                continue
            if conn is None or conn.closed:
                conn = self._connect()
            self.processor.process(conn, item[1])
        if conn is not None:
            conn.close()
        log.info(f"consumer {idx} stopped")

    def run(self) -> None:
        def _depth():
            try:
                return float(self.redis.llen(self.s.queue))
            except Exception:  # noqa: BLE001
                return float("nan")

        QUEUE_DEPTH.set_function(_depth)
        start_http_server(self.s.metrics_port)

        def _graceful(signum, _frame):
            log.info(f"received signal {signum}; finishing in-flight orders")
            self.stop.set()

        signal.signal(signal.SIGTERM, _graceful)
        signal.signal(signal.SIGINT, _graceful)

        threads = [threading.Thread(target=self.loop, args=(i,), daemon=True)
                   for i in range(self.s.concurrency)]
        for t in threads:
            t.start()
        log.info("order-worker started", extra={"fields": {
            "concurrency": self.s.concurrency, "queue": self.s.queue,
            "chaos_memory_leak": self.s.chaos_memory_leak, "chaos_slow_db": self.s.chaos_slow_db}})
        while any(t.is_alive() for t in threads):
            for t in threads:
                t.join(timeout=0.5)
        log.info("order-worker stopped cleanly")
