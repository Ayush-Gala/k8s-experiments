"""
Locust Load Generator for Kubernetes Resilience Experiment
===========================================================

This load generator creates realistic HTTP traffic patterns to test
Kubernetes' ability to maintain service availability during:
- Pod failures
- Node failures
- Resource exhaustion scenarios

The php-apache image responds to GET requests with CPU-intensive
calculations, making it ideal for testing autoscaling and resilience.

SCALE PROFILES:
- Small:   50-100 users,   spawn rate 10    (Killercoda)
- Medium:  500-1,000 users, spawn rate 50   (multi-node)
- Large:   5,000-10,000 users, spawn rate 100-500 (production)

Each Locust worker can handle approximately 500-1,000 simulated users.
Scale workers proportionally for larger tests.
"""

from locust import HttpUser, task, between, events, constant_pacing
from locust.runners import MasterRunner
import time
import logging
import os

# Configure logging for experiment tracking
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# High-scale mode: reduce wait times for more aggressive load
HIGH_SCALE_MODE = os.environ.get('HIGH_SCALE_MODE', 'false').lower() == 'true'


class PhpApacheUser(HttpUser):
    """
    Simulates a user making requests to the php-apache service.
    
    The php-apache container performs CPU calculations on each request,
    which allows us to:
    1. Generate meaningful load for HPA scaling
    2. Observe response time degradation during failures
    3. Track request success/failure rates
    """
    
    # Wait between 0.5 and 2 seconds between tasks (realistic user behavior)
    # For high-scale mode, use shorter wait times
    wait_time = between(0.1, 0.5) if HIGH_SCALE_MODE else between(0.5, 2.0)
    
    # Weight for user distribution (higher = more of this user type)
    weight = 3
    
    # Track request statistics for experiment analysis
    request_count = 0
    failure_count = 0
    
    @task(10)
    def generate_load(self):
        """
        Primary load generation task.
        
        Sends GET requests to the php-apache service root endpoint.
        The service performs CPU calculations and returns a response.
        
        Weight: 10 (most common request type)
        """
        with self.client.get("/", catch_response=True, name="CPU Load Request") as response:
            PhpApacheUser.request_count += 1
            
            if response.status_code == 200:
                response.success()
            elif response.status_code >= 500:
                # Server errors indicate potential pod/node issues
                PhpApacheUser.failure_count += 1
                response.failure(f"Server Error: {response.status_code}")
                logger.warning(f"Server error detected: {response.status_code}")
            else:
                response.failure(f"Unexpected status: {response.status_code}")
    
    @task(3)
    def health_check(self):
        """
        Simulates health check requests.
        
        These lightweight requests help us observe service availability
        separate from CPU-intensive operations.
        
        Weight: 3 (less frequent than load requests)
        """
        with self.client.get("/", catch_response=True, name="Health Check") as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Health check failed: {response.status_code}")
    
    @task(1)
    def burst_request(self):
        """
        Simulates burst traffic patterns.
        
        Rapid successive requests to simulate traffic spikes.
        Helps test HPA scaling behavior.
        
        Weight: 1 (occasional bursts)
        """
        for _ in range(5):
            self.client.get("/", name="Burst Request")


class SteadyStateUser(HttpUser):
    """
    Maintains a steady baseline load for the experiment.
    
    This user class provides consistent background traffic,
    making it easier to observe the impact of failures.
    """
    
    wait_time = between(0.5, 1.5) if HIGH_SCALE_MODE else between(1.0, 3.0)
    weight = 1  # Lower weight than PhpApacheUser
    
    @task
    def steady_request(self):
        """
        Consistent, predictable requests for baseline measurement.
        """
        self.client.get("/", name="Steady State Request")


class HighThroughputUser(HttpUser):
    """
    High-throughput user for large-scale testing.
    
    Uses constant pacing to generate predictable, high-volume traffic.
    Enable by setting HIGH_SCALE_MODE=true environment variable.
    """
    
    # Fixed 100ms between requests = 10 RPS per user
    wait_time = constant_pacing(0.1)
    weight = 2 if HIGH_SCALE_MODE else 0  # Only active in high-scale mode
    
    @task
    def rapid_request(self):
        """
        Rapid-fire requests for stress testing.
        """
        with self.client.get("/", catch_response=True, name="High Throughput") as response:
            if response.status_code != 200:
                response.failure(f"Status: {response.status_code}")


# Event handlers for experiment logging
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Log when the load test begins."""
    logger.info("=" * 60)
    logger.info("KUBERNETES RESILIENCE EXPERIMENT - LOAD TEST STARTED")
    logger.info("=" * 60)
    logger.info(f"Target Host: {environment.host}")
    if isinstance(environment.runner, MasterRunner):
        logger.info("Running in distributed mode (master)")
    logger.info("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Log final statistics when test ends."""
    logger.info("=" * 60)
    logger.info("LOAD TEST COMPLETED")
    logger.info(f"Total Requests: {PhpApacheUser.request_count}")
    logger.info(f"Total Failures: {PhpApacheUser.failure_count}")
    if PhpApacheUser.request_count > 0:
        failure_rate = (PhpApacheUser.failure_count / PhpApacheUser.request_count) * 100
        logger.info(f"Failure Rate: {failure_rate:.2f}%")
    logger.info("=" * 60)


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, 
               response, context, exception, start_time, url, **kwargs):
    """
    Track individual request metrics for detailed analysis.
    
    This data helps correlate failures with specific events
    (pod restarts, node failures, etc.)
    """
    if exception:
        logger.debug(f"Request failed: {name} - {exception}")

