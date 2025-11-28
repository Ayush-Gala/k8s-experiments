# Locust Load Generator Container
# For running distributed load tests within the Kubernetes cluster

FROM python:3.11-slim

LABEL maintainer="K8s Resilience Experiment"
LABEL description="Locust load generator for Kubernetes resilience testing"

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy locust configuration
COPY locustfile.py .

# Expose Locust web UI and worker ports
EXPOSE 8089 5557 5558

# Default command runs Locust in web UI mode
ENTRYPOINT ["locust"]
CMD ["-f", "locustfile.py"]

