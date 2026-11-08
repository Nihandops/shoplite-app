"""All configuration comes from environment variables (12-factor)."""
import os


def _float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, default))
    except ValueError:
        return default


def _bool(name: str) -> bool:
    return os.getenv(name, "false").strip().lower() in ("1", "true", "yes", "on")


SERVICE_NAME = os.getenv("SERVICE_NAME", "catalog-api")
PORT = int(os.getenv("PORT", "8000"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")

DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "shoplite")
DB_USER = os.getenv("DB_USER", "shoplite")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_POOL_MAX = int(os.getenv("DB_POOL_MAX", "10"))

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
QUEUE_NAME = os.getenv("QUEUE_NAME", "orders:pending")

# Fault-injection flags (all disabled by default)
CHAOS_LATENCY_MS = int(_float("CHAOS_LATENCY_MS", 0))
CHAOS_ERROR_RATE = _float("CHAOS_ERROR_RATE", 0.0)
INIT_DB_ON_START = os.getenv("INIT_DB_ON_START", "true").lower() == "true"


def dsn() -> str:
    return (
        f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} "
        f"user={DB_USER} password={DB_PASSWORD} connect_timeout=3"
    )
