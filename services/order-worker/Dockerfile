# syntax=docker/dockerfile:1
# ---- stage 1: build a virtualenv with runtime deps ----
FROM python:3.12-alpine AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
COPY requirements.txt .
RUN pip install -r requirements.txt \
 && pip uninstall -y pip setuptools 2>/dev/null || true

# ---- stage 2: unit tests ----
FROM python:3.12-alpine AS test
WORKDIR /app
COPY requirements.txt requirements-dev.txt ./
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY worker ./worker
COPY tests ./tests
RUN python -m pytest -q

# ---- stage 3: minimal non-root runtime ----
FROM python:3.12-alpine AS runtime
RUN addgroup -S -g 10001 app && adduser -S -D -H -u 10001 -G app app \
 && pip uninstall -y pip setuptools 2>/dev/null; rm -rf /root/.cache
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=10001:10001 worker ./worker
ENV PATH=/opt/venv/bin:$PATH PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 METRICS_PORT=9100
USER 10001:10001
EXPOSE 9100
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9100/metrics', timeout=2)" || exit 1
# exec form => python is PID 1 and receives SIGTERM directly (graceful shutdown)
CMD ["python", "-m", "worker"]
