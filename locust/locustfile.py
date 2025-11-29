"""
Locust Load Generator for Kubernetes Resilience Experiment
===========================================================

BALANCED VERSION - Generates moderate CPU load for HPA scaling + self-healing.

Target behavior:
- 100-200 users:  3 pods (baseline)
- 500 users:      ~5 pods  
- 1000 users:     ~8 pods (max)

The php-apache backend performs CPU calculations on each request,
so request frequency directly impacts CPU utilization.
"""

from locust import HttpUser, task, between, events
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class LoadTestUser(HttpUser):
    """
    Balanced load generator for HPA scaling and resilience testing.
    
    Generates enough CPU load to trigger HPA scaling while
    still allowing observation of failure/recovery patterns.
    """
    
    # Short wait times = more requests = higher CPU load
    # 0.5-1.5 seconds between requests per user
    wait_time = between(0.5, 1.5)
    
    # Statistics tracking
    request_count = 0
    failure_count = 0
    
    @task(10)
    def cpu_load_request(self):
        """
        Primary load generation - triggers CPU work on the server.
        
        The php-apache container performs sqrt() calculations in a loop,
        consuming CPU with each request.
        """
        with self.client.get("/", catch_response=True, name="CPU Load") as response:
            LoadTestUser.request_count += 1
            
            if response.status_code == 200:
                response.success()
            else:
                LoadTestUser.failure_count += 1
                response.failure(f"Error: {response.status_code}")
    
    @task(2)
    def health_check(self):
        """
        Lightweight health check - helps track availability during failures.
        """
        with self.client.get("/", catch_response=True, name="Health Check") as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Unhealthy: {response.status_code}")


class AggressiveUser(HttpUser):
    """
    More aggressive user for faster HPA triggering.
    
    Use this user type to quickly push CPU utilization up.
    Weight of 1 means fewer of these users in the mix.
    """
    
    # Very short wait = high request rate
    wait_time = between(0.1, 0.5)
    weight = 1  # 1/4 of users will be this type
    
    @task
    def rapid_request(self):
        """
        Rapid-fire requests to quickly increase CPU load.
        """
        self.client.get("/", name="Rapid Load")


# Event handlers
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Log when the load test begins."""
    logger.info("=" * 60)
    logger.info("KUBERNETES RESILIENCE EXPERIMENT - LOAD TEST STARTED")
    logger.info("=" * 60)
    logger.info(f"Target Host: {environment.host}")
    logger.info("Mode: Balanced (HPA scaling + self-healing)")
    logger.info("")
    logger.info("Expected scaling behavior:")
    logger.info("  100-200 users → 3 pods")
    logger.info("  500 users     → ~5 pods")
    logger.info("  1000 users    → ~8 pods")
    logger.info("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Log final statistics when test ends."""
    logger.info("=" * 60)
    logger.info("LOAD TEST COMPLETED")
    logger.info(f"Total Requests: {LoadTestUser.request_count}")
    logger.info(f"Total Failures: {LoadTestUser.failure_count}")
    if LoadTestUser.request_count > 0:
        failure_rate = (LoadTestUser.failure_count / LoadTestUser.request_count) * 100
        logger.info(f"Failure Rate: {failure_rate:.2f}%")
    logger.info("=" * 60)
