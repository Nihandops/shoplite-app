from .logging_setup import setup_logging
from .main import Settings, Worker
from .telemetry import setup_tracing

settings = Settings()
setup_logging(settings.service, "INFO")
setup_tracing(settings.service, settings.environment)
Worker(settings).run()
