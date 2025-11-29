"""
Locust Load Generator for Kubernetes Resilience Experiment
===========================================================

LIGHTWEIGHT VERSION - Focused on self-healing demonstration, not HPA scaling.

This load generator creates continuous HTTP traffic to test Kubernetes'
ability to maintain service availability during:
- Pod failures and restarts
- Pod deletions and replacements
- Node cordoning and draining

The nginx backend is lightweight, so this generates minimal CPU load
while still producing meaningful traffic for failure detection.
"""

from locust import HttpUser, task, between, events
from locust.runners import MasterRunner
import logging

# Configure logging for experiment tracking
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ResilienceTestUser(HttpUser):
    """
    Lightweight user for resilience testing.
    
    Generates steady, low-overhead traffic to:
    1. Detect when pods fail (requests start failing)
    2. Observe recovery (requests succeed again)
    3. Measure recovery time
    """
    
    # Wait 1-3 seconds between requests (low load, easy on resources)
    wait_time = between(1, 3)
    
    # Track statistics
    request_count = 0
    failure_count = 0
    
    @task(10)
    def check_service(self):
        """
        Primary request - checks if service is responding.
        
        This is the main metric for observing failures and recovery.
        """
        with self.client.get("/", catch_response=True, name="Service Check") as response:
            ResilienceTestUser.request_count += 1
            
            if response.status_code == 200:
                response.success()
            else:
                ResilienceTestUser.failure_count += 1
                response.failure(f"Status: {response.status_code}")
    
    @task(2)
    def health_probe(self):
        """
        Simulates a health probe similar to Kubernetes probes.
        """
        with self.client.get("/", catch_response=True, name="Health Probe") as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Unhealthy: {response.status_code}")


# Event handlers for experiment logging
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Log when the load test begins."""
    logger.info("=" * 60)
    logger.info("KUBERNETES RESILIENCE EXPERIMENT - LOAD TEST STARTED")
    logger.info("=" * 60)
    logger.info(f"Target Host: {environment.host}")
    logger.info("Mode: Lightweight (self-healing focus)")
    logger.info("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Log final statistics when test ends."""
    logger.info("=" * 60)
    logger.info("LOAD TEST COMPLETED")
    logger.info(f"Total Requests: {ResilienceTestUser.request_count}")
    logger.info(f"Total Failures: {ResilienceTestUser.failure_count}")
    if ResilienceTestUser.request_count > 0:
        failure_rate = (ResilienceTestUser.failure_count / ResilienceTestUser.request_count) * 100
        logger.info(f"Failure Rate: {failure_rate:.2f}%")
    logger.info("=" * 60)

