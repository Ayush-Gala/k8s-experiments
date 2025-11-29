"""
Locust Load Generator for Kubernetes Resilience Experiment
===========================================================

BALANCED VERSION - Generates CPU load via nginx+Lua backend.

The OpenResty backend performs 1,000,000 sqrt() calculations per request,
creating measurable CPU load for HPA scaling.

Expected scaling:
- 100-200 users → 3 pods (baseline)
- 500 users     → ~5 pods
- 1000 users    → ~8 pods (max)
"""

from locust import HttpUser, task, between, events
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class LoadTestUser(HttpUser):
    """
    Primary load generator - sends requests that trigger CPU work.
    """
    
    # 0.5-1.5 seconds between requests
    wait_time = between(0.5, 1.5)
    weight = 3  # 75% of users
    
    request_count = 0
    failure_count = 0
    
    @task(10)
    def cpu_load_request(self):
        """
        Request to the main endpoint which performs CPU calculations.
        """
        with self.client.get("/", catch_response=True, name="CPU Load") as response:
            LoadTestUser.request_count += 1
            
            if response.status_code == 200:
                response.success()
            else:
                LoadTestUser.failure_count += 1
                response.failure(f"Error: {response.status_code}")
    
    @task(1)
    def health_check(self):
        """
        Lightweight health check (no CPU work).
        """
        with self.client.get("/health", catch_response=True, name="Health Check") as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Unhealthy: {response.status_code}")


class AggressiveUser(HttpUser):
    """
    Aggressive user for faster HPA triggering.
    Sends rapid requests to quickly increase CPU utilization.
    """
    
    wait_time = between(0.1, 0.3)
    weight = 1  # 25% of users
    
    @task
    def rapid_request(self):
        """
        Rapid-fire CPU load requests.
        """
        self.client.get("/", name="Rapid Load")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    logger.info("=" * 60)
    logger.info("KUBERNETES RESILIENCE EXPERIMENT - LOAD TEST STARTED")
    logger.info("=" * 60)
    logger.info(f"Target Host: {environment.host}")
    logger.info("Backend: OpenResty (Nginx + Lua CPU simulation)")
    logger.info("")
    logger.info("Expected scaling:")
    logger.info("  200 users  → 3 pods")
    logger.info("  500 users  → ~5 pods")
    logger.info("  1000 users → ~8 pods")
    logger.info("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    logger.info("=" * 60)
    logger.info("LOAD TEST COMPLETED")
    logger.info(f"Total Requests: {LoadTestUser.request_count}")
    logger.info(f"Total Failures: {LoadTestUser.failure_count}")
    if LoadTestUser.request_count > 0:
        failure_rate = (LoadTestUser.failure_count / LoadTestUser.request_count) * 100
        logger.info(f"Failure Rate: {failure_rate:.2f}%")
    logger.info("=" * 60)
