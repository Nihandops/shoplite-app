"""OpenTelemetry tracing setup. Exports via OTLP/HTTP when OTEL_EXPORTER_OTLP_ENDPOINT is set.

Even without an exporter we keep a real TracerProvider so every request has a
trace_id that is written to the logs.
"""
import os

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def setup_tracing(service: str, environment: str) -> None:
    resource = Resource.create(
        {
            "service.name": service,
            "service.namespace": "shoplite",
            "deployment.environment": environment,
        }
    )
    provider = TracerProvider(resource=resource)
    if os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT") or os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"):
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)

    # psycopg2-binary is not detected as "psycopg2" by the dependency check
    from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
    from opentelemetry.instrumentation.redis import RedisInstrumentor

    Psycopg2Instrumentor().instrument(skip_dep_check=True)
    RedisInstrumentor().instrument()


def current_trace_id() -> str:
    ctx = trace.get_current_span().get_span_context()
    return format(ctx.trace_id, "032x") if ctx.is_valid else ""
