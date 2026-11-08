from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider

# real provider so spans/trace ids exist in tests (no exporter)
trace.set_tracer_provider(TracerProvider())
