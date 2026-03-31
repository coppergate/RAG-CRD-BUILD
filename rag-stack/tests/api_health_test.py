import os
import requests
import json
import unittest
import sys

# Standardized API Health and Functionality Tests for Iteration 7
# This test script runs within the cluster and verifies that all services
# have correctly implemented health/readiness checks and TLS-enabled REST APIs.

# Base URLs (using service names in the cluster)
RAG_SYSTEM_NAMESPACE = "rag-system"
BASE_DOMAIN = f"{RAG_SYSTEM_NAMESPACE}.svc.cluster.local"

SERVICES = {
    "rag-admin-api": f"https://rag-admin-api.{BASE_DOMAIN}:443",
    "db-adapter": f"https://db-adapter.{BASE_DOMAIN}:443",
    "qdrant-adapter": f"https://qdrant-adapter.{BASE_DOMAIN}:443",
    "object-store-mgr": f"https://object-store-mgr.{BASE_DOMAIN}:443",
    "memory-controller": f"https://memory-controller.{BASE_DOMAIN}:443",
    "llm-gateway": f"https://llm-gateway.{BASE_DOMAIN}:443",
}

# Path to the CA bundle used in the cluster
CA_BUNDLE = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")

class APIHealthTest(unittest.TestCase):
    def setUp(self):
        # We assume the CA is already in the system bundle or provided via SSL_CERT_FILE
        # In the test runner pod, this should be the Hierocracy CA.
        self.verify = CA_BUNDLE if os.path.exists(CA_BUNDLE) else False

    def check_health(self, name, base_url):
        print(f"\n[INFO] Testing health of {name} at {base_url}...")
        
        # Test /readyz (standardized readiness)
        try:
            resp = requests.get(f"{base_url}/readyz", verify=self.verify, timeout=5)
            self.assertEqual(resp.status_code, 200, f"{name} /readyz failed with {resp.status_code}")
            health_info = resp.json()
            self.assertEqual(health_info.get("status"), "ready", f"{name} /readyz reports status {health_info.get('status')}")
            print(f"  [OK] {name} /readyz: {health_info}")
        except Exception as e:
            self.fail(f"Failed to reach {name} /readyz: {e}")

        # Test /healthz (standardized liveness)
        try:
            resp = requests.get(f"{base_url}/healthz", verify=self.verify, timeout=5)
            self.assertEqual(resp.status_code, 200, f"{name} /healthz failed with {resp.status_code}")
            print(f"  [OK] {name} /healthz: {resp.text}")
        except Exception as e:
            self.fail(f"Failed to reach {name} /healthz: {e}")

    def test_01_all_health_standardized(self):
        """Verify all services have standardized health and readiness endpoints."""
        for name, url in SERVICES.items():
            self.check_health(name, url)

    def test_02_admin_api_aggregation(self):
        """Verify RAG Admin API can aggregate health from all other services."""
        url = f"{SERVICES['rag-admin-api']}/api/health/all"
        try:
            resp = requests.get(url, verify=self.verify, timeout=10)
            self.assertEqual(resp.status_code, 200, f"Admin API health aggregation failed: {resp.status_code}")
            data = resp.json()
            self.assertIsInstance(data, dict)
            print(f"  [OK] Admin API Health Aggregation keys: {list(data.keys())}")
            # Each service in the aggregation should have health info
            for service_name in ["db-adapter", "qdrant-adapter", "object-store-mgr", "llm-gateway", "memory-controller"]:
                self.assertIn(service_name, data, f"Admin API missing health for {service_name}")
                info = data[service_name]
                if isinstance(info, dict):
                    self.assertIn("status", info, f"{service_name} health missing status field")
                    # Note: We don't fail the test if a downstream is DOWN, as this tests the aggregator's ability to report it.
                    # But if the aggregator fails to return a JSON for a service, that might be an issue.
        except Exception as e:
            self.fail(f"Admin API aggregation test failed: {e}")

    def test_03_db_adapter_api(self):
        """Verify DB Adapter REST API functionality."""
        url = f"{SERVICES['db-adapter']}/api/db/stats"
        try:
            resp = requests.get(url, verify=self.verify, timeout=5)
            self.assertEqual(resp.status_code, 200, f"DB Adapter stats failed: {resp.status_code}")
            data = resp.json()
            self.assertIn("sessions", data)
            self.assertIn("prompts", data)
            self.assertIn("responses", data)
            print(f"  [OK] DB Adapter stats: {data}")
        except Exception as e:
            self.fail(f"DB Adapter API test failed: {e}")

    def test_04_qdrant_adapter_api(self):
        """Verify Qdrant Adapter REST API functionality."""
        url = f"{SERVICES['qdrant-adapter']}/api/qdrant/collections"
        try:
            resp = requests.get(url, verify=self.verify, timeout=5)
            self.assertEqual(resp.status_code, 200, f"Qdrant Adapter collections failed: {resp.status_code}")
            data = resp.json()
            # The API returns {"result": {"collections": [...]}, "status": "ok", ...}
            self.assertIn("result", data)
            self.assertIn("collections", data["result"])
            self.assertIsInstance(data["result"]["collections"], list)
            print(f"  [OK] Qdrant Adapter collections count: {len(data['result']['collections'])}")
        except Exception as e:
            self.fail(f"Qdrant Adapter API test failed: {e}")

    def test_05_object_store_mgr_api(self):
        """Verify Object Store Manager REST API functionality."""
        url = f"{SERVICES['object-store-mgr']}/api/s3/buckets"
        try:
            resp = requests.get(url, verify=self.verify, timeout=5)
            self.assertEqual(resp.status_code, 200, f"Object Store Mgr buckets failed: {resp.status_code}")
            data = resp.json()
            self.assertIsInstance(data, list)
            print(f"  [OK] Object Store Mgr buckets count: {len(data)}")
        except Exception as e:
            self.fail(f"Object Store Mgr API test failed: {e}")

    def test_06_memory_controller_api(self):
        """Verify Memory Controller REST API functionality."""
        url = f"{SERVICES['memory-controller']}/api/memory/items"
        try:
            resp = requests.get(url, verify=self.verify, timeout=5)
            self.assertEqual(resp.status_code, 200, f"Memory Controller items failed: {resp.status_code}")
            data = resp.json()
            self.assertIsInstance(data, list)
            print(f"  [OK] Memory Controller items count: {len(data)}")
        except Exception as e:
            self.fail(f"Memory Controller API test failed: {e}")

if __name__ == "__main__":
    print("[INFO] Starting API Health and Functionality Tests...")
    suite = unittest.TestLoader().loadTestsFromTestCase(APIHealthTest)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
