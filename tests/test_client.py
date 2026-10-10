"""Unit tests for the thin client's config and API client."""

import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

import config
from api_client import STAGES, PipelineClient, ServerError


class TestConfig(unittest.TestCase):
    def test_default_is_localhost(self):
        self.assertEqual(config.DEFAULT_SERVER_URL, "http://localhost:8000")

    def test_set_and_get_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(config, "_CONFIG_PATH", os.path.join(tmp, "config.json")):
                config.set_server_url("http://192.168.1.10:8000/")
                self.assertEqual(config.get_server_url(), "http://192.168.1.10:8000")

    def test_set_rejects_empty(self):
        with self.assertRaises(ValueError):
            config.set_server_url("   ")

    def test_set_rejects_non_http(self):
        with self.assertRaises(ValueError):
            config.set_server_url("ftp://example.com")

    def test_ipv6_bare_loopback_with_port(self):
        self.assertEqual(
            config.normalize_server_url("http://::1:8000"),
            "http://[::1]:8000",
        )

    def test_ipv6_already_bracketed(self):
        self.assertEqual(
            config.normalize_server_url("http://[::1]:8000"),
            "http://[::1]:8000",
        )

    def test_ipv6_full_address_no_port(self):
        self.assertEqual(
            config.normalize_server_url("http://2001:db8::1"),
            "http://[2001:db8::1]",
        )

    def test_ipv4_unchanged(self):
        self.assertEqual(
            config.normalize_server_url("http://192.168.1.10:8000"),
            "http://192.168.1.10:8000",
        )

    def test_hostname_unchanged(self):
        self.assertEqual(
            config.normalize_server_url("http://localhost:8000"),
            "http://localhost:8000",
        )


class TestApiClient(unittest.TestCase):
    def test_stages_cover_pipeline(self):
        self.assertEqual(len(STAGES), 6)
        self.assertIn("dialogue", STAGES)
        self.assertIn("render", STAGES)

    def test_run_stage_rejects_unknown(self):
        client = PipelineClient("http://localhost:8000")
        with self.assertRaises(ValueError):
            client.run_stage("s1", "nope")


if __name__ == "__main__":
    unittest.main()
