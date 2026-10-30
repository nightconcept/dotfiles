"""Isolated checks for benchmark streaming and safe tool validation."""

import importlib.util
import json
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "bench_ai_stack", Path(__file__).parents[1] / "scripts/bench-ai-stack.py"
)
assert SPEC is not None and SPEC.loader is not None
BENCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCH)


def event(chunk):
    """Encode one SSE JSON event."""
    return b"data: " + json.dumps(chunk).encode() + b"\n\n"


class StreamTest(unittest.TestCase):
    """Exercise actual fragmented tool calls and completion transport."""

    def test_fragmented_tool_and_usage_only_chunk(self):
        """Reassemble arguments and retain final usage without inventing timing."""
        chunks = [
            {
                "choices": [
                    {
                        "delta": {
                            "tool_calls": [
                                {
                                    "index": 0,
                                    "id": "call_1",
                                    "function": {
                                        "name": "read_benchmark_fixture",
                                        "arguments": '{"key":',
                                    },
                                }
                            ]
                        }
                    }
                ]
            },
            {
                "choices": [
                    {
                        "delta": {
                            "tool_calls": [{"index": 0, "function": {"arguments": '"marker"}'}}]
                        },
                        "finish_reason": "tool_calls",
                    }
                ]
            },
            {"choices": [], "usage": {"completion_tokens": 8}},
        ]
        result = BENCH.collect_stream(
            [*[event(chunk) for chunk in chunks], b"data: [DONE]\n"], time.monotonic()
        )
        self.assertEqual(result["usage"], {"completion_tokens": 8})
        self.assertIsNone(result["decode_tokens_per_second"])
        self.assertEqual(BENCH.fixture_result(result["message"])["content"], BENCH.FIXTURE)

    def test_refuse_unexpected_tool(self):
        """Reject model-generated commands instead of executing anything."""
        message = {
            "tool_calls": [
                {
                    "id": "x",
                    "function": {"name": "shell", "arguments": '{"command":"touch /tmp/unsafe"}'},
                }
            ]
        }
        with self.assertRaises(ValueError):
            BENCH.fixture_result(message)

    def test_truncated_stream(self):
        """Refuse apparent success when the connection ends prematurely."""
        with self.assertRaises(RuntimeError):
            BENCH.collect_stream([event({"choices": []})], time.monotonic())

    def test_http_stream(self):
        """Use a local HTTP fixture to verify the request and response protocol."""
        captured = {}

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                """Serve a synthetic completion with server timing."""
                captured.update(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                self.wfile.write(
                    event(
                        {
                            "choices": [
                                {"delta": {"content": "BENCH_OK"}, "finish_reason": "stop"}
                            ],
                            "usage": {"completion_tokens": 3},
                            "timings": {"predicted_per_second": 27.5},
                        }
                    )
                    + b"data: [DONE]\n\n"
                )

            def log_message(self, format, *args):
                """Suppress fixture HTTP logs."""

        server = HTTPServer(("127.0.0.1", 0), Handler)
        worker = threading.Thread(target=server.handle_request)
        worker.start()
        try:
            result = BENCH.completion(
                f"http://127.0.0.1:{server.server_port}/v1", {"model": "fixture"}, 2
            )
            self.assertTrue(captured["stream"])
            self.assertEqual(result["message"]["content"], "BENCH_OK")
            self.assertEqual(result["decode_tokens_per_second"], 27.5)
            self.assertGreaterEqual(result["latency_s"], result["ttft_s"])
        finally:
            server.server_close()
            worker.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
