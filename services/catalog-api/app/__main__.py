"""Entrypoint: `python -m app` (serve) or `python -m app init-db` (schema + seed, used by the Helm Job)."""
import logging
import sys
import time

from . import config
from .logging_setup import setup_logging
from .telemetry import setup_tracing

setup_logging(config.SERVICE_NAME, config.LOG_LEVEL)
setup_tracing(config.SERVICE_NAME, config.ENVIRONMENT)
log = logging.getLogger("catalog-api")


def _store_with_retry():
    from .store import PgStore

    for attempt in range(1, 31):
        try:
            return PgStore(config.dsn(), config.DB_POOL_MAX)
        except Exception as exc:  # noqa: BLE001
            log.warning(f"database not ready (attempt {attempt}): {exc}")
            time.sleep(2)
    raise SystemExit("database unreachable")


def main() -> None:
    store = _store_with_retry()
    if len(sys.argv) > 1 and sys.argv[1] == "init-db":
        store.init()
        log.info("database initialised")
        return
    if config.INIT_DB_ON_START:
        store.init()

    import uvicorn
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

    from .main import create_app
    from .store import RedisQueue

    queue = RedisQueue(config.REDIS_HOST, config.REDIS_PORT, config.QUEUE_NAME)
    app = create_app(store, queue)
    FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz,readyz,metrics")
    log.info("starting catalog-api", extra={"fields": {"port": config.PORT}})
    uvicorn.run(app, host="0.0.0.0", port=config.PORT, log_config=None,
                access_log=False, timeout_graceful_shutdown=20)


if __name__ == "__main__":
    main()
