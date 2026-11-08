"""Unit tests for the worker using a fake DB connection."""
import json

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider

trace.set_tracer_provider(TracerProvider())

from worker import main as wm  # noqa: E402


class FakeCursor:
    def __init__(self, conn):
        self.conn = conn
        self.description = None
        self._row = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.conn.statements.append(sql.strip().split()[0:2])
        if "pg_sleep" in sql:
            self.conn.slept += 1
        if "RETURNING status" in sql:
            self.description = ("status",)
            self._row = (self.conn.final_status,)
        else:
            self.description = None

    def fetchone(self):
        return self._row


class FakeConn:
    def __init__(self, final_status="COMPLETED"):
        self.final_status = final_status
        self.statements, self.slept, self.closed = [], 0, 0

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def cursor(self):
        return FakeCursor(self)

    def rollback(self):
        pass


def _settings(**over):
    s = wm.Settings()
    s.min_work = s.max_work = 0
    for k, v in over.items():
        setattr(s, k, v)
    return s


def _msg(order_id=7):
    return json.dumps({"order_id": order_id, "trace": {
        "traceparent": "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"}}).encode()


def test_completed_order():
    p = wm.OrderProcessor(_settings(), sleep=lambda s: None)
    assert p.process(FakeConn("COMPLETED"), _msg()) == "completed"


def test_out_of_stock_marks_failed():
    p = wm.OrderProcessor(_settings(), sleep=lambda s: None)
    assert p.process(FakeConn("FAILED"), _msg()) == "failed"


def test_chaos_slow_db_runs_pg_sleep_before_each_update():
    conn = FakeConn()
    wm.OrderProcessor(_settings(chaos_slow_db=True), sleep=lambda s: None).process(conn, _msg())
    assert conn.slept == 2


def test_chaos_memory_leak_retains_memory():
    before = len(wm._LEAK)
    wm.OrderProcessor(_settings(chaos_memory_leak=True), sleep=lambda s: None).process(FakeConn(), _msg())
    assert len(wm._LEAK) == before + 1
    wm._LEAK.clear()


def test_trace_context_is_continued_from_message():
    seen = {}
    orig = wm.OrderProcessor._update

    def spy(self, conn, sql, params):
        seen["trace_id"] = format(trace.get_current_span().get_span_context().trace_id, "032x")
        return orig(self, conn, sql, params)

    wm.OrderProcessor._update = spy
    try:
        wm.OrderProcessor(_settings(), sleep=lambda s: None).process(FakeConn(), _msg())
    finally:
        wm.OrderProcessor._update = orig
    assert seen["trace_id"] == "0af7651916cd43dd8448eb211c80319c"
