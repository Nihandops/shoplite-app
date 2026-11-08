"""ShopLite catalog-api: products, orders, health and metrics."""
import logging
import random
import time

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from opentelemetry import propagate, trace
from prometheus_client import REGISTRY
from prometheus_client.exposition import choose_encoder
from pydantic import BaseModel, Field

from . import config
from .metrics import HTTP_LATENCY, HTTP_REQUESTS, ORDERS_CREATED, QUEUE_DEPTH
from .telemetry import current_trace_id

log = logging.getLogger("catalog-api")
tracer = trace.get_tracer("catalog-api")

UNTRACKED = {"/metrics", "/healthz", "/readyz"}


class OrderIn(BaseModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=1000)


class StripPrefix:
    """ASGI middleware: `/api/products` -> `/products`.

    The Kubernetes Ingress sends `/api/*` straight to this service, so the API
    accepts both forms and no controller-specific rewrite annotation is needed.
    """

    def __init__(self, app, prefix: str = "/api"):
        self.app, self.prefix = app, prefix

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            path = scope["path"]
            if path == self.prefix or path.startswith(self.prefix + "/"):
                # mutate in place so outer middleware still sees the matched route
                scope["path"] = path[len(self.prefix):] or "/"
        await self.app(scope, receive, send)


def create_app(store, queue, chaos_latency_ms=None, chaos_error_rate=None) -> FastAPI:
    latency_ms = config.CHAOS_LATENCY_MS if chaos_latency_ms is None else chaos_latency_ms
    error_rate = config.CHAOS_ERROR_RATE if chaos_error_rate is None else chaos_error_rate

    app = FastAPI(title="ShopLite catalog-api", version="1.0.0")
    app.add_middleware(StripPrefix, prefix="/api")
    app.state.store = store
    app.state.queue = queue

    def _depth() -> float:
        try:
            return float(queue.depth())
        except Exception:  # never break /metrics because redis is down
            return float("nan")

    QUEUE_DEPTH.set_function(_depth)

    @app.middleware("http")
    async def observe(request: Request, call_next):
        start = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            elapsed = time.perf_counter() - start
            route_obj = request.scope.get("route")
            route = getattr(route_obj, "path", None) or "unmatched"
            if route not in UNTRACKED:
                HTTP_REQUESTS.labels(request.method, route, str(status)).inc()
                tid = current_trace_id()
                HTTP_LATENCY.labels(request.method, route).observe(
                    elapsed, exemplar={"trace_id": tid} if tid else None
                )
                level = logging.ERROR if status >= 500 else logging.INFO
                log.log(
                    level,
                    f"{request.method} {request.url.path} {status}",
                    extra={"fields": {
                        "method": request.method, "route": route, "path": request.url.path,
                        "status": status, "duration_ms": round(elapsed * 1000, 2),
                    }},
                )

    @app.get("/healthz")
    def healthz():
        return {"status": "ok"}

    @app.get("/readyz")
    def readyz():
        checks = {}
        for name, fn in (("database", store.ping), ("queue", queue.ping)):
            try:
                checks[name] = "ok" if fn() else "fail"
            except Exception as exc:  # noqa: BLE001
                checks[name] = f"fail: {type(exc).__name__}"
        ok = all(v == "ok" for v in checks.values())
        return JSONResponse({"status": "ready" if ok else "not-ready", "checks": checks},
                            status_code=200 if ok else 503)

    @app.get("/metrics")
    def metrics(request: Request):
        encoder, content_type = choose_encoder(request.headers.get("accept", ""))
        return Response(encoder(REGISTRY), media_type=content_type)

    @app.get("/products")
    def list_products():
        return store.list_products()

    @app.get("/products/{product_id}")
    def get_product(product_id: int):
        if latency_ms > 0 and random.random() < 0.30:
            with tracer.start_as_current_span("chaos.latency") as span:
                span.set_attribute("chaos.latency_ms", latency_ms)
                time.sleep(latency_ms / 1000)
        product = store.get_product(product_id)
        if product is None:
            raise HTTPException(status_code=404, detail=f"product {product_id} not found")
        return product

    @app.post("/orders", status_code=201)
    def create_order(body: OrderIn):
        if error_rate > 0 and random.random() < error_rate:
            span = trace.get_current_span()
            span.set_attribute("chaos.injected_error", True)
            log.error("order creation failed: upstream error",
                      extra={"fields": {"product_id": body.product_id}})
            raise HTTPException(status_code=500, detail="internal error")
        if store.get_product(body.product_id) is None:
            raise HTTPException(status_code=404, detail=f"product {body.product_id} not found")

        order = store.create_order(body.product_id, body.quantity)
        carrier: dict = {}
        with tracer.start_as_current_span(
            "orders:pending publish", kind=trace.SpanKind.PRODUCER,
            attributes={"messaging.system": "redis",
                        "messaging.destination.name": config.QUEUE_NAME,
                        "order.id": order["id"]},
        ):
            propagate.inject(carrier)  # W3C traceparent travels inside the message
            try:
                queue.push({"order_id": order["id"], "product_id": body.product_id,
                            "quantity": body.quantity, "trace": carrier})
            except Exception as exc:  # noqa: BLE001
                store.set_status(order["id"], "FAILED")
                log.exception("enqueue failed")
                raise HTTPException(status_code=503, detail="queue unavailable") from exc
        ORDERS_CREATED.inc()
        log.info("order created", extra={"fields": {"order_id": order["id"],
                                                    "product_id": body.product_id,
                                                    "quantity": body.quantity}})
        return {"id": order["id"], "status": order["status"]}

    @app.get("/orders/{order_id}")
    def get_order(order_id: int):
        order = store.get_order(order_id)
        if order is None:
            raise HTTPException(status_code=404, detail=f"order {order_id} not found")
        return order

    return app
