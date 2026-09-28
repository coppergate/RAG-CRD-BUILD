"""Tests for _line_span, the chunk -> line-range derivation in service.py.

Run:  python3 -m unittest test_line_span -v      (from services/rag-ingestion/)

service.py is not importable here -- it builds a FastAPI app and a DB pool at
module scope, and pulls in boto3/pulsar/langchain. So the function under test is
extracted from source and exec'd in isolation. That keeps the test honest (it
really is the shipped code, not a copy that can drift) without needing the
service's whole dependency tree.
"""

import ast
import logging
import pathlib
import unittest

_SERVICE = pathlib.Path(__file__).with_name("service.py")


def _load_line_span():
    """Pull the real _line_span out of service.py and compile it standalone."""
    tree = ast.parse(_SERVICE.read_text())
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "_line_span":
            module = ast.Module(body=[node], type_ignores=[])
            ns = {"logger": logging.getLogger("test")}
            exec(compile(module, str(_SERVICE), "exec"), ns)
            return ns["_line_span"]
    raise AssertionError("_line_span not found in service.py -- was it renamed?")


_line_span = _load_line_span()

DOC = "line1\nline2\nline3\nline4\nline5"


class TestLineSpan(unittest.TestCase):
    def test_first_chunk_starts_at_line_one(self):
        self.assertEqual(_line_span(DOC, 0, "line1\nline2"), (1, 2))

    def test_single_line_chunk_has_equal_start_and_end(self):
        off = DOC.index("line3")
        self.assertEqual(_line_span(DOC, off, "line3"), (3, 3))

    def test_multi_line_chunk_spans_correctly(self):
        off = DOC.index("line3")
        self.assertEqual(_line_span(DOC, off, "line3\nline4"), (3, 4))

    def test_last_line(self):
        off = DOC.index("line5")
        self.assertEqual(_line_span(DOC, off, "line5"), (5, 5))

    def test_reported_range_actually_contains_the_chunk(self):
        """The property that makes a citation trustworthy."""
        lines = DOC.split("\n")
        for probe in ("line1", "line2\nline3", "line4", "line5"):
            off = DOC.index(probe)
            start, end = _line_span(DOC, off, probe)
            recovered = "\n".join(lines[start - 1 : end])
            self.assertIn(probe, recovered, f"{probe!r} not within lines {start}-{end}")

    # ── Fail-closed behaviour ────────────────────────────────────────────────
    # A missing citation is recoverable; a confidently wrong one is not.

    def test_missing_offset_yields_no_span(self):
        self.assertEqual(_line_span(DOC, None, "line1"), (None, None))

    def test_negative_offset_yields_no_span(self):
        self.assertEqual(_line_span(DOC, -1, "line1"), (None, None))

    def test_out_of_range_offset_yields_no_span(self):
        self.assertEqual(_line_span(DOC, 10**6, "line1"), (None, None))

    def test_offset_disagreeing_with_chunk_yields_no_span(self):
        """The guard that matters: a wrong start_index must not become a wrong citation."""
        with self.assertLogs(level="WARNING"):
            self.assertEqual(_line_span(DOC, 0, "line3"), (None, None))

    def test_leading_whitespace_still_matches(self):
        """strip_whitespace=True means the chunk may be trimmed relative to the source."""
        self.assertEqual(_line_span(DOC, 0, "  line1  "), (1, 1))

    def test_empty_chunk_is_permitted(self):
        # No first line to verify, so the offset is taken at face value.
        self.assertEqual(_line_span(DOC, 0, ""), (1, 1))

    # ── Shapes real documents actually have ──────────────────────────────────

    def test_trailing_newline_does_not_overshoot(self):
        doc = "a\nb\nc\n"
        start, end = _line_span(doc, 0, "a\nb")
        self.assertEqual((start, end), (1, 2))

    def test_crlf_document(self):
        doc = "alpha\r\nbeta\r\ngamma"
        off = doc.index("beta")
        start, end = _line_span(doc, off, "beta")
        self.assertEqual((start, end), (2, 2))

    def test_blank_lines_are_counted(self):
        doc = "one\n\n\nfour"
        off = doc.index("four")
        self.assertEqual(_line_span(doc, off, "four"), (4, 4))

    def test_realistic_go_source(self):
        doc = "\n".join([
            "package pipeline",
            "",
            "func Run(ctx context.Context) error {",
            "\treturn nil",
            "}",
        ])
        chunk = "func Run(ctx context.Context) error {\n\treturn nil\n}"
        self.assertEqual(_line_span(doc, doc.index(chunk), chunk), (3, 5))


if __name__ == "__main__":
    unittest.main()
