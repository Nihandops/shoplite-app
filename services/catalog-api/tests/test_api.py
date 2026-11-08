"""Unit tests for catalog-api using in-memory fakes (no Postgres/Redis needed)."""
import json

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


class FakeStore:
    def __init__(self, healthy=True):
        self.healthy = healthy
        self.products = {i: {"id": i, "name": f"P{i}", "price": 10.0 * i, "stock": 100}
                         for i in range(1, 11)}
        self.orders = {}

    def ping(self):
        if not self.healthy:
            raise ConnectionError("db down")
        return True

    def list_products(self):
        return list(self.products.values())

    def get_product(self, pid):
        return self.products.get(pid)

    def create_order(self, pid, qty):
        oid = len(self.orders) + 1
        self.orders[oid] = {"id": oid, "product_id": pid, "quantity": qty, "status": "PENDING",
                            "created_at": "2026-11-08T00:00:00+00:00", "completed_at": None}
        return self.orders[oid]

    def set_status(self, oid, status):
        self.orders[oid]["status"] = status

    def get_order(self, oid):
        return self.orders.get(oid)


class FakeQueue:
    def __init__(self, healthy=True):
        self.healthy = healthy
        self.items = []

    def ping(self):
        if not self.healthy:
            raise ConnectionError("redis down")
        return True

    def push(self, msg):
        if not self.healthy:
            raise ConnectionError("redis down")
        self.items.append(json.dumps(msg))

    def depth(self):
        return len(self.items)


@pytest.fixture
def ctx():
    store, queue = FakeStore(), FakeQueue()
    client = TestClient(create_app(store, queue, chaos_latency_ms=0, chaos_error_rate=0))
    return client, store, queue


def test_healthz(ctx):
    client, _, _ = ctx
    r = client.get("/healthz")
    assert r.status_code == 200 and r.json()["status"] == "ok"


def test_list_products_returns_all(ctx):
    client, _, _ = ctx
    r = client.get("/products")
    assert r.status_code == 200
    assert len(r.json()) == 10


def test_get_product_found_and_missing(ctx):
    client, _, _ = ctx
    assert client.get("/products/3").json()["name"] == "P3"
    assert client.get("/products/999").status_code == 404


def test_create_order_returns_201_and_enqueues(ctx):
    client, store, queue = ctx
    r = client.post("/orders", json={"product_id": 1, "quantity": 2})
    assert r.status_code == 201
    oid = r.json()["id"]
    assert r.json()["status"] == "PENDING"
    assert store.orders[oid]["quantity"] == 2
    msg = json.loads(queue.items[0])
    assert msg["order_id"] == oid and "traceparent" in msg["trace"]


def test_create_order_unknown_product_404(ctx):
    client, _, queue = ctx
    r = client.post("/orders", json={"product_id": 999, "quantity": 1})
    assert r.status_code == 404 and queue.items == []


def test_create_order_invalid_body_422(ctx):
    client, _, _ = ctx
    assert client.post("/orders", json={"product_id": 1, "quantity": 0}).status_code == 422
    assert client.post("/orders", json={"quantity": 1}).status_code == 422


def test_get_order_status(ctx):
    client, _, _ = ctx
    oid = client.post("/orders", json={"product_id": 2, "quantity": 1}).json()["id"]
    r = client.get(f"/orders/{oid}")
    assert r.status_code == 200 and r.json()["status"] == "PENDING"
    assert client.get("/orders/12345").status_code == 404


def test_readyz_ok_and_failing():
    ok = TestClient(create_app(FakeStore(), FakeQueue(), 0, 0))
    assert ok.get("/readyz").status_code == 200
    bad = TestClient(create_app(FakeStore(), FakeQueue(healthy=False), 0, 0))
    r = bad.get("/readyz")
    assert r.status_code == 503 and r.json()["checks"]["queue"].startswith("fail")


def test_metrics_exposes_required_series(ctx):
    client, _, _ = ctx
    client.get("/products")
    client.post("/orders", json={"product_id": 1, "quantity": 1})
    body = client.get("/metrics").text
    for name in ("http_requests_total", "http_request_duration_seconds",
                 "orders_created_total", "order_queue_depth"):
        assert name in body
    assert 'route="/products"' in body


def test_api_prefix_is_accepted(ctx):
    client, _, _ = ctx
    assert client.get("/api/products/1").status_code == 200
    assert client.get("/api/healthz").status_code == 200


def test_chaos_error_rate_returns_500():
    client = TestClient(create_app(FakeStore(), FakeQueue(), 0, chaos_error_rate=1.0))
    assert client.post("/orders", json={"product_id": 1, "quantity": 1}).status_code == 500


def test_enqueue_failure_marks_order_failed():
    store = FakeStore()
    client = TestClient(create_app(store, FakeQueue(healthy=False), 0, 0))
    r = client.post("/orders", json={"product_id": 1, "quantity": 1})
    assert r.status_code == 503 and store.orders[1]["status"] == "FAILED"


def test_prefixed_requests_keep_route_label(ctx):
    client, _, _ = ctx
    client.get("/api/products/5")
    assert 'route="/products/{product_id}"' in client.get("/metrics").text
