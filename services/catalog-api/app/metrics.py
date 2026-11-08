"""Prometheus metrics exposed on GET /metrics (OpenMetrics format carries exemplars)."""
from prometheus_client import Counter, Gauge, Histogram

HTTP_REQUESTS = Counter(
    "http_requests_total", "HTTP requests", ["method", "route", "status"]
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
ORDERS_CREATED = Counter("orders_created_total", "Orders accepted by the API")
QUEUE_DEPTH = Gauge("order_queue_depth", "Messages waiting in orders:pending")
