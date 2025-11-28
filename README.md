# Kubernetes Resilience Experiment

## Validating Automatic Restart and Replacement of Unhealthy Resources

This repository contains a controlled experiment designed to demonstrate and validate Kubernetes' ability to **automatically restart or replace unhealthy resources** in a compute orchestration layer. The experiment uses industry-standard tools (Locust load generator, php-apache sample application) and can be executed on cloud-based Kubernetes playgrounds like Killercoda.

---

## Table of Contents

1. [Experiment Design](#1-experiment-design)
2. [Load Generation with Locust](#2-load-generation-with-locust)
3. [Predicted Outcomes and Validation](#3-predicted-outcomes-and-validation)
4. [Quick Start Guide](#quick-start-guide)
5. [Running on Killercoda](#running-on-killercoda)

---

## 1. Experiment Design

### 1.1 Objective

The primary objective of this experiment is to **validate the requirement**: *"Configure the compute orchestration layer to automatically restart or replace unhealthy resources."*

Specifically, we aim to demonstrate that Kubernetes can:

1. **Detect unhealthy pods** through liveness and readiness probes
2. **Automatically restart containers** when they fail health checks
3. **Reschedule pods** when nodes become unavailable or cordoned
4. **Maintain service availability** during infrastructure failures through replication
5. **Scale resources** based on demand using Horizontal Pod Autoscaler (HPA)
6. **Enforce availability constraints** through Pod Disruption Budgets (PDB)

### 1.2 Environment Configuration

#### 1.2.1 Kubernetes Cluster

| Component | Specification |
|-----------|---------------|
| **Platform** | Killercoda Kubernetes Playground (or equivalent) |
| **Nodes** | Minimum 1 node (single-node); ideally 2+ nodes for node failure scenarios |
| **Kubernetes Version** | v1.25+ (supports autoscaling/v2 API) |
| **Namespace** | `k8s-resilience-experiment` (isolated for clean teardown) |

#### 1.2.2 Application Deployment (php-apache)

The target application is based on the official Kubernetes [php-apache example](https://k8s.io/examples/application/php-apache.yaml). This lightweight PHP application performs CPU-intensive calculations when receiving HTTP requests, making it ideal for demonstrating:

- Load-based autoscaling
- Health monitoring
- Container restart behavior

**Deployment Configuration:**

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Initial Replicas** | 3 | Provides redundancy for failure testing |
| **Container Image** | `registry.k8s.io/hpa-example` | Official K8s example; performs CPU work |
| **CPU Request** | 200m | Baseline resource allocation |
| **CPU Limit** | 500m | Prevents resource exhaustion |
| **Memory Request** | 64Mi | Lightweight memory footprint |
| **Memory Limit** | 128Mi | Prevents OOM situations |
| **Liveness Probe** | HTTP GET `/` every 5s | Detects unresponsive containers |
| **Readiness Probe** | HTTP GET `/` every 3s | Gates traffic to healthy pods |
| **Failure Threshold** | 3 consecutive failures | Triggers restart after 15s of failure |

#### 1.2.3 Self-Healing Components

**Horizontal Pod Autoscaler (HPA):**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **Min Replicas** | 3 | Maintains minimum availability |
| **Max Replicas** | 10 | Caps scaling to prevent runaway |
| **Target CPU Utilization** | 50% | Triggers scaling when exceeded |
| **Scale-Up Stabilization** | 0s | Immediate response to load |
| **Scale-Down Stabilization** | 60s | Prevents thrashing |

**Pod Disruption Budget (PDB):**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **minAvailable** | 2 | Ensures at least 2 pods during disruptions |
| **Selector** | `run: php-apache` | Applies to all application pods |

### 1.3 Experiment Inputs

The experiment accepts the following inputs:

#### 1.3.1 Load Generation Parameters (via Locust)

| Input | Range | Description |
|-------|-------|-------------|
| **Number of Users** | 10 - 500 | Simulated concurrent users |
| **Spawn Rate** | 1 - 50 users/second | Rate of user ramp-up |
| **Target Host** | `http://php-apache:80` | In-cluster service endpoint |
| **Test Duration** | 5 - 30 minutes | Length of load test |

#### 1.3.2 Failure Injection Inputs

| Scenario | Input Method | Parameters |
|----------|--------------|------------|
| **Single Pod Failure** | Script execution | Pod name (auto-selected) |
| **Multiple Pod Failure** | Script execution | Count (50% of replicas) |
| **Rolling Failures** | Script execution | Interval (10s), Count (5 cycles) |
| **Node Cordon** | Script execution | Node name |
| **Node Drain** | Script execution | Node name, grace period |
| **Node Taint** | Script execution | Taint key/value/effect |

### 1.4 Expected Outputs

#### 1.4.1 Quantitative Metrics

| Metric | Expected Behavior | Measurement Method |
|--------|-------------------|-------------------|
| **Request Success Rate** | > 95% during failures | Locust statistics |
| **Response Time (P50)** | < 500ms steady state | Locust statistics |
| **Response Time (P99)** | < 2000ms during recovery | Locust statistics |
| **Pod Restart Count** | Increment after failure | `kubectl get pods` |
| **Time to Recovery** | < 60s for pod restart | Timestamp analysis |
| **Endpoint Count** | ≥ minAvailable (2) | `kubectl get endpoints` |

#### 1.4.2 Qualitative Observations

| Observation | Validation Criteria |
|-------------|---------------------|
| **Container Restart** | Pod shows increased restart count; STATUS remains Running |
| **Pod Replacement** | New pod created with different name; old pod Terminating |
| **Service Continuity** | Requests continue succeeding during pod churn |
| **Load Redistribution** | Remaining pods handle increased traffic |
| **Autoscaling** | Replica count increases under load |

### 1.5 Experiment Phases

The experiment proceeds through five distinct phases:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        EXPERIMENT TIMELINE                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Phase 1: Setup (2 min)                                                     │
│  ├── Deploy namespace, application, HPA, PDB                                │
│  └── Start Locust load generator                                            │
│                                                                              │
│  Phase 2: Baseline (5 min)                                                  │
│  ├── Ramp up to 50 users                                                    │
│  ├── Collect steady-state metrics                                           │
│  └── Verify all pods healthy, HPA stable                                    │
│                                                                              │
│  Phase 3: Pod Failure Injection (10 min)                                    │
│  ├── Scenario A: Single pod deletion                                        │
│  ├── Scenario B: Multiple pod deletion (50%)                                │
│  ├── Scenario C: Rolling failures (5 cycles)                                │
│  └── Scenario D: Complete pod failure (all pods)                            │
│                                                                              │
│  Phase 4: Node Failure Injection (10 min)                                   │
│  ├── Scenario A: Node cordon (prevent scheduling)                           │
│  ├── Scenario B: Node drain (graceful eviction)                             │
│  └── Scenario C: Node taint (NoSchedule)                                    │
│                                                                              │
│  Phase 5: Recovery & Analysis (5 min)                                       │
│  ├── Allow cluster to stabilize                                             │
│  ├── Collect final metrics                                                  │
│  └── Generate report                                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.6 Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES CLUSTER                                    │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                    NAMESPACE: k8s-resilience-experiment                 │  │
│  │                                                                         │  │
│  │   ┌─────────────────┐     ┌─────────────────────────────────────────┐  │  │
│  │   │  Locust Master  │     │         php-apache Deployment           │  │  │
│  │   │  (Load Gen)     │     │                                         │  │  │
│  │   │  Port: 8089     │     │  ┌─────────┐ ┌─────────┐ ┌─────────┐   │  │  │
│  │   └────────┬────────┘     │  │ Pod 1   │ │ Pod 2   │ │ Pod 3   │   │  │  │
│  │            │              │  │ ┌─────┐ │ │ ┌─────┐ │ │ ┌─────┐ │   │  │  │
│  │   ┌────────┼────────┐     │  │ │ PHP │ │ │ │ PHP │ │ │ │ PHP │ │   │  │  │
│  │   │ Locust Workers  │     │  │ │     │ │ │ │     │ │ │ │     │ │   │  │  │
│  │   │ (Distributed)   │     │  │ └─────┘ │ │ └─────┘ │ │ └─────┘ │   │  │  │
│  │   └────────┬────────┘     │  └────┬────┘ └────┬────┘ └────┬────┘   │  │  │
│  │            │              │       │          │          │         │  │  │
│  │            │              └───────┴──────────┴──────────┴─────────┘  │  │
│  │            │                              │                          │  │
│  │            │              ┌───────────────┴───────────────┐          │  │
│  │            └──────────────►      php-apache Service       │          │  │
│  │              HTTP GET /   │        (ClusterIP:80)         │          │  │
│  │                           └───────────────────────────────┘          │  │
│  │                                                                       │  │
│  │   ┌─────────────────────────────────────────────────────────────┐    │  │
│  │   │                    CONTROL COMPONENTS                        │    │  │
│  │   │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │    │  │
│  │   │  │     HPA      │  │     PDB      │  │    Deployment    │   │    │  │
│  │   │  │ min:3 max:10 │  │ minAvail: 2  │  │   Controller     │   │    │  │
│  │   │  │ CPU: 50%     │  │              │  │                  │   │    │  │
│  │   │  └──────────────┘  └──────────────┘  └──────────────────┘   │    │  │
│  │   └─────────────────────────────────────────────────────────────┘    │  │
│  │                                                                       │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      FAILURE INJECTION LAYER                          │   │
│  │                                                                       │   │
│  │   [simulate-pod-failure.sh]          [simulate-node-failure.sh]      │   │
│  │   • Delete pods                      • Cordon nodes                   │   │
│  │   • Kill processes                   • Drain nodes                    │   │
│  │   • Simulate crashes                 • Add taints                     │   │
│  │                                                                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Load Generation with Locust

### 2.1 Overview of Locust

[Locust](https://locust.io/) is an open-source, Python-based load testing framework that allows simulation of user behavior through scriptable test scenarios. For this experiment, Locust serves as the **input generator**, creating continuous HTTP traffic that exercises the Kubernetes cluster's ability to maintain service availability under stress.

### 2.2 Load Test Configuration

The Locust configuration (`locust/locustfile.py`) defines three user behavior classes:

#### 2.2.1 PhpApacheUser (Primary Load Generator)

```python
class PhpApacheUser(HttpUser):
    wait_time = between(0.5, 2.0)  # Realistic user think time
    
    @task(10)  # Weight: 10 (most common)
    def generate_load(self):
        # Sends CPU-intensive requests to trigger autoscaling
        
    @task(3)   # Weight: 3 (moderate frequency)
    def health_check(self):
        # Lightweight health verification requests
        
    @task(1)   # Weight: 1 (occasional)
    def burst_request(self):
        # Simulates traffic spikes with 5 rapid requests
```

#### 2.2.2 SteadyStateUser (Baseline Traffic)

```python
class SteadyStateUser(HttpUser):
    wait_time = between(1.0, 3.0)  # Slower, consistent traffic
    weight = 1  # Lower weight in user distribution
```

### 2.3 Traffic Patterns and Their Meanings

The load test produces distinct traffic patterns that correlate with cluster behavior:

```
Requests/Second
     │
 200 ┤                    ╭──────────────────╮
     │                   ╱                    ╲
 150 ┤    ╭─────────────╯                      ╲
     │   ╱              ↑                       ╲
 100 ┤  ╱      HPA scales up                     ╲
     │ ╱       to handle load                     ╲────────────
  50 ┤╱                                                  ↑
     │    ↑                                        Load reduced
     │  Ramp-up                                    HPA scales down
   0 ┼────┴─────────┴─────────────┴─────────────┴─────────────▶ Time
     0    1min       5min          15min         25min
     
     ├──────┤ ├───────────────────────────────┤ ├───────────┤
      Phase 2        Phase 3 & 4 (Failures)        Phase 5
      Baseline       Injection & Recovery          Stabilize
```

### 2.4 Interpreting Load Patterns During Failures

#### 2.4.1 Normal Operation (Baseline)

| Metric | Expected Value | Indication |
|--------|----------------|------------|
| RPS (Requests/Second) | Steady 50-100 | Cluster handling load normally |
| Failure Rate | < 1% | All pods healthy and responding |
| Response Time P50 | < 200ms | No resource contention |
| Response Time P99 | < 500ms | Consistent performance |

#### 2.4.2 During Pod Failure

```
Response Time (ms)
     │
2000 ┤                 ╭╮
     │                ╱  ╲    ← Brief spike during pod termination
1000 ┤               ╱    ╲     (connections draining)
     │              ╱      ╲
 500 ┤─────────────╯        ╲─────────────────────
     │                       ↑
     │               New pod receives traffic
 200 ┤               (readiness probe passes)
     │
   0 ┼──────────────┬────────┬──────────────────▶ Time
                   Pod      Recovery
                  Killed   Complete
```

**Observable Pattern:**
- **Immediate Impact (0-5s):** Request failures spike to 5-10% as connections to terminated pod fail
- **Recovery (5-15s):** Failure rate returns to < 1% as traffic redistributes
- **Stabilization (15-30s):** Response times normalize; new pod becomes ready

#### 2.4.3 During Multiple Pod Failure (50%)

```
Failure Rate (%)
     │
 30% ┤        ╭──────╮
     │       ╱        ╲         ← Higher failure rate
 20% ┤      ╱          ╲          (50% capacity lost)
     │     ╱            ╲
 10% ┤    ╱              ╲
     │   ╱                ╲
  5% ┤  ╱                  ╲──────────────
     │ ╱                    ↑
  0% ┼╯──────────────────────────────────▶ Time
         ↑               Pods recovered
     50% pods          (all replicas ready)
      killed
```

**Observable Pattern:**
- **Immediate Impact (0-10s):** Failure rate jumps to 10-30% depending on timing
- **PDB Activation:** Kubernetes ensures minimum 2 pods remain (if eviction API used)
- **Recovery (10-60s):** Gradual restoration as new pods pass readiness probes
- **Compensatory Scaling:** HPA may scale up additional replicas if CPU threshold exceeded

#### 2.4.4 During Node Failure/Drain

```
Active Endpoints
     │
  6  ┤───────────────╮
     │               │    ← Node drain begins
  4  ┤               ╰───────────────────╮
     │                                   │  ← Pods rescheduled
  2  ┤ (minAvailable)  - - - - - - - - - │ - - - - - -
     │                                   ╰────────────
  0  ┼────────────────┬──────────────────┬───────────▶ Time
                   Drain              Uncordon
                   Start              Node
```

**Observable Pattern:**
- **Graceful Eviction:** Pods terminate with grace period (respecting PDB)
- **Rescheduling:** Pods move to available nodes (may take 30-60s)
- **Service Continuity:** Traffic flows to remaining pods during transition
- **Endpoint Updates:** Service endpoint list shrinks then recovers

### 2.5 Request Types and Their Purpose

| Request Type | Weight | Purpose in Experiment |
|--------------|--------|----------------------|
| **CPU Load Request** | 77% | Triggers autoscaling; simulates real workload |
| **Health Check** | 23% | Monitors availability separately from load |
| **Burst Request** | Occasional | Tests spike handling and queue behavior |
| **Steady State** | Background | Provides consistent baseline for comparison |

### 2.6 Using Locust for Experiment Correlation

During the experiment, correlate Locust metrics with Kubernetes events:

```bash
# Terminal 1: Run Locust
# Access web UI at port 30089

# Terminal 2: Watch Kubernetes events
kubectl get events -n k8s-resilience-experiment -w

# Terminal 3: Inject failures
./scripts/simulate-pod-failure.sh
```

**Correlation Table:**

| Time | Locust Metric | K8s Event | Interpretation |
|------|---------------|-----------|----------------|
| T+0s | Failures spike | Pod deleted | Failure injection successful |
| T+5s | Failures decrease | Pod scheduled | Deployment controller responding |
| T+15s | Failures < 1% | Pod ready | Readiness probe passed |
| T+30s | RPS normalized | - | Full recovery achieved |

---

## 3. Predicted Outcomes and Validation

### 3.1 Hypothesis

Based on Kubernetes' architecture and the configured self-healing mechanisms, we predict that the cluster will **successfully restart or replace unhealthy resources within 60 seconds** while maintaining **greater than 95% request success rate** throughout all failure scenarios.

### 3.2 Predicted Outcomes by Scenario

#### 3.2.1 Scenario A: Single Pod Failure

| Prediction | Rationale | Validation Method |
|------------|-----------|-------------------|
| Pod restart within 30s | Deployment controller detects missing replica immediately | `kubectl get pods -w` shows new pod |
| Service availability maintained | Remaining 2 pods handle traffic | Locust failure rate < 5% |
| No data loss | StatelessHTTP application | All requests return valid responses |
| HPA unaffected | Load distributed to remaining pods | HPA replica count stable |

**Expected Timeline:**

```
T+0s:   Pod deleted
T+1s:   Deployment controller detects ReplicaSet mismatch
T+2s:   New pod scheduled
T+5s:   Container pulls image (cached)
T+8s:   Container starts, liveness probe begins
T+13s:  Readiness probe passes (after initialDelaySeconds)
T+15s:  Pod receives traffic, full recovery
```

#### 3.2.2 Scenario B: Multiple Pod Failure (50%)

| Prediction | Rationale | Validation Method |
|------------|-----------|-------------------|
| All pods replaced within 60s | Parallel scheduling and startup | Pod count returns to desired |
| Brief service degradation | 50% capacity reduction | Locust P99 latency increases |
| PDB respected (if using eviction) | minAvailable=2 enforced | At least 2 pods always running |
| Possible HPA scale-up | Remaining pods exceed CPU threshold | Replica count increases |

**Expected Metrics:**

```
Before:  3 pods, ~50% CPU each, 100 RPS
During:  1-2 pods, ~100% CPU, 50 RPS (requests queued)
After:   3-4 pods, ~40% CPU each, 100 RPS (possible scale-up)
```

#### 3.2.3 Scenario C: Rolling Failures (Chaos Engineering)

| Prediction | Rationale | Validation Method |
|------------|-----------|-------------------|
| Continuous recovery | Each failure triggers restart | Restart count increments |
| Accumulated restart count | Multiple failures across pods | Sum of restarts = 5 |
| Service never fully unavailable | Never all pods down simultaneously | Failure rate never 100% |
| Increased P99 latency | Constant pod churn | Locust P99 > 1000ms during test |

**Expected Pattern:**

```
Restart Count Over Time
     │
  5  ┤                              ╱
     │                           ╱──
  4  ┤                        ╱──
     │                     ╱──
  3  ┤                  ╱──
     │               ╱──
  2  ┤            ╱──
     │         ╱──
  1  ┤      ╱──
     │   ╱──
  0  ┼───────┬──────────┬──────────┬──────────┬──▶ Time
           10s        20s        30s        40s
           ↑          ↑          ↑          ↑
         Kill 1    Kill 2    Kill 3    Kill 4
```

#### 3.2.4 Scenario D: Complete Pod Failure

| Prediction | Rationale | Validation Method |
|------------|-----------|-------------------|
| Temporary service outage | No pods available | Locust 100% failure rate briefly |
| Full recovery within 60s | 3 pods scheduled simultaneously | All pods Ready |
| No manual intervention needed | Deployment controller automated | Cluster self-heals |
| PDB violation allowed | Voluntary deletion (not eviction) | Pods deleted despite PDB |

**Critical Validation Point:** This scenario demonstrates that while Kubernetes *prefers* to maintain availability (via PDB), the system *always* recovers even from catastrophic failures.

#### 3.2.5 Scenario E: Node Cordon

| Prediction | Rationale | Validation Method |
|------------|-----------|-------------------|
| Existing pods continue running | Cordon only affects scheduling | Pod STATUS unchanged |
| New pods scheduled elsewhere | Cordoned node excluded | Node affinity in new pods |
| Graceful handling | No immediate disruption | Locust metrics stable |

#### 3.2.6 Scenario F: Node Drain

| Prediction | Rationale | Validation Method |
|------------|-----------|-------------------|
| Pods evicted gracefully | Drain respects terminationGracePeriod | Pod terminating with delay |
| PDB respected | Eviction API checks PDB | minAvailable=2 maintained |
| Pods rescheduled | Available nodes receive pods | Pod node assignment changes |
| Brief latency increase | Pod migration in progress | Locust P95 latency up |

### 3.3 Success Criteria

The experiment validates the requirement **"Configure the compute orchestration layer to automatically restart or replace unhealthy resources"** if ALL of the following criteria are met:

| # | Criterion | Threshold | Measurement |
|---|-----------|-----------|-------------|
| 1 | Pod Recovery Time | < 60 seconds | Time from deletion to Ready |
| 2 | Overall Success Rate | > 95% | Locust aggregate statistics |
| 3 | Automatic Recovery | 100% of scenarios | No manual intervention required |
| 4 | Service Endpoints | ≥ 2 at all times | `kubectl get endpoints` |
| 5 | Final State | All pods Ready | `kubectl get pods` shows 3/3 Running |
| 6 | Restart Count | Reflects failures | Non-zero after failure scenarios |

### 3.4 Failure Analysis Framework

If any scenario produces unexpected results, analyze using this framework:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    FAILURE ANALYSIS DECISION TREE                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Pods not recovering?                                                │
│  ├── Check: kubectl describe pod <pod-name>                         │
│  │   ├── ImagePullBackOff → Image registry issue                    │
│  │   ├── CrashLoopBackOff → Container failing health checks         │
│  │   └── Pending → Insufficient resources or node issues            │
│  │                                                                   │
│  High failure rate persists?                                         │
│  ├── Check: kubectl get endpoints php-apache                        │
│  │   ├── Empty → No ready pods, service unavailable                 │
│  │   └── Partial → Some pods ready, check pod distribution          │
│  │                                                                   │
│  HPA not scaling?                                                    │
│  ├── Check: kubectl describe hpa php-apache-hpa                     │
│  │   ├── Unable to calculate metrics → Metrics server issue         │
│  │   └── Below threshold → Load insufficient to trigger scaling     │
│  │                                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.5 Expected Evidence for Requirement Validation

Upon successful completion of the experiment, the following evidence will demonstrate that Kubernetes has been configured to automatically restart or replace unhealthy resources:

1. **Pod Restart Counts > 0:** Indicates containers were restarted after failures
2. **Different Pod Names:** New pod UIDs show replacements occurred
3. **Events Log:** Shows "Killing," "Scheduled," "Started," "Pulled" event sequence
4. **Locust Recovery Graph:** Failure rate drops back to baseline after each injection
5. **HPA Activity:** (If load triggers) Shows scaling decisions in response to conditions
6. **PDB Status:** Shows disruptions allowed decreased during failures

### 3.6 Conclusion

This experiment provides empirical evidence that the Kubernetes compute orchestration layer is correctly configured to:

✅ **Detect** container and pod failures through health probes  
✅ **Restart** containers that fail liveness checks  
✅ **Replace** pods that are deleted or fail permanently  
✅ **Redistribute** traffic to healthy pods during failures  
✅ **Scale** resources based on demand  
✅ **Maintain** availability through replication and PDBs  

These capabilities, demonstrated under controlled failure conditions with continuous load, validate the requirement for automatic restart and replacement of unhealthy resources in the compute orchestration layer.

---

## Quick Start Guide

### Prerequisites

- Kubernetes cluster (v1.25+)
- `kubectl` configured and connected
- Network access to the cluster

### Installation

```bash
# Clone or copy the repository
cd Cloud_k8s_impl

# Make scripts executable
chmod +x scripts/*.sh

# Deploy the experiment environment
./scripts/setup.sh
```

### Running the Experiment

```bash
# Terminal 1: Start monitoring
./scripts/monitor.sh

# Terminal 2: Access Locust UI (port 30089)
# Start a test with 50 users, spawn rate 10

# Terminal 3: Inject failures
./scripts/simulate-pod-failure.sh
# or
./scripts/simulate-node-failure.sh
```

### Cleanup

```bash
./scripts/cleanup.sh
```

---

## Running on Killercoda

[Killercoda](https://killercoda.com/) provides free, browser-based Kubernetes environments. Follow these steps:

### Step 1: Access Killercoda

1. Go to [Killercoda Kubernetes Playground](https://killercoda.com/playgrounds/scenario/kubernetes)
2. Wait for the environment to initialize

### Step 2: Clone the Experiment

```bash
# In the Killercoda terminal
git clone https://github.com/YOUR_USERNAME/Cloud_k8s_impl.git
cd Cloud_k8s_impl
chmod +x scripts/*.sh
```

Or copy files manually if git is unavailable:

```bash
# Create directory structure
mkdir -p Cloud_k8s_impl/{k8s,locust,scripts}
cd Cloud_k8s_impl

# Copy file contents from this repository
```

### Step 3: Deploy the Experiment

```bash
./scripts/setup.sh
```

### Step 4: Access Services

In Killercoda, use the "Traffic / Ports" feature:

1. Click on the hamburger menu (≡) in the top-left
2. Select "Traffic / Ports"
3. Enter port `30089` and click "Access" for Locust UI
4. Enter port `30080` and click "Access" for php-apache

### Step 5: Run Load Test

1. In Locust UI, enter:
   - Number of users: `50`
   - Spawn rate: `10`
2. Click "Start Swarming"

### Step 6: Inject Failures

In a second terminal tab in Killercoda:

```bash
cd Cloud_k8s_impl
./scripts/simulate-pod-failure.sh
```

### Step 7: Observe and Document

Watch the Locust graphs and Kubernetes events. The experiment demonstrates:

- Failure rate spikes during pod deletion
- Automatic recovery as new pods start
- Continuous service availability

### Note on Killercoda Limitations

- Single-node cluster: Node failure scenarios are limited
- Session timeout: Experiments may need to restart after 60 minutes
- Resource constraints: Use moderate load (< 100 users)

---

## Scaling the Experiment

The experiment supports three scale profiles for different cluster sizes and use cases:

### Scale Profiles

| Profile | Users | php-apache Pods | Locust Workers | Cluster Requirements |
|---------|-------|-----------------|----------------|---------------------|
| **Small** | 50-100 | 3-10 | 2 | Single node (Killercoda) |
| **Medium** | 500-1,000 | 5-30 | 5 | 2+ nodes, 2 CPU/node |
| **Large** | 5,000-10,000 | 10-100 | 10-20 | 3+ nodes, 4 CPU/node |

### Using the Scale Script

```bash
# Interactive scale configuration
./scripts/scale-experiment.sh

# Options:
# 1) Small   - Up to 100 users (Killercoda compatible)
# 2) Medium  - Up to 1,000 users (multi-node cluster)
# 3) Large   - Up to 10,000 users (production cluster)
# 4) Custom  - Specify your target user count
```

### Manual Scaling Commands

```bash
# Scale php-apache pods
kubectl scale deployment php-apache -n k8s-resilience-experiment --replicas=10

# Update HPA limits
kubectl patch hpa php-apache-hpa -n k8s-resilience-experiment --type='json' \
  -p='[{"op": "replace", "path": "/spec/minReplicas", "value": 10},
       {"op": "replace", "path": "/spec/maxReplicas", "value": 100}]'

# Scale Locust workers
kubectl scale deployment locust-worker -n k8s-resilience-experiment --replicas=15
```

### High-Scale Mode for Locust

Enable aggressive load generation for large-scale tests:

```bash
# Set environment variable in Locust deployment
kubectl set env deployment/locust-master -n k8s-resilience-experiment HIGH_SCALE_MODE=true
kubectl set env deployment/locust-worker -n k8s-resilience-experiment HIGH_SCALE_MODE=true
```

### Capacity Planning

| Component | Capacity | Notes |
|-----------|----------|-------|
| **php-apache pod** | ~100-200 concurrent users | CPU-bound (500m limit) |
| **Locust worker** | ~500-1,000 simulated users | Memory-bound |
| **Service** | Limited by endpoint count | Use NodePort or LoadBalancer |

### Scaling Recommendations

1. **For 1,000 users:**
   ```bash
   ./scripts/scale-experiment.sh  # Choose option 2 (Medium)
   ```
   - 5 initial php-apache pods (scales to 30)
   - 5 Locust workers
   - Spawn rate: 50 users/second

2. **For 10,000 users:**
   ```bash
   ./scripts/scale-experiment.sh  # Choose option 3 (Large)
   ```
   - 10 initial php-apache pods (scales to 100)
   - 15-20 Locust workers
   - Spawn rate: 100-500 users/second
   - **Requires production cluster with adequate resources**

### Monitoring at Scale

For large-scale tests, use the monitoring script with a faster refresh rate:

```bash
./scripts/monitor.sh 2  # Refresh every 2 seconds
```

Watch for:
- HPA scaling activity (should scale up under load)
- Pod distribution across nodes
- Endpoint count matching ready pods
- Event logs for scheduling issues

---

## File Structure

```
Cloud_k8s_impl/
├── README.md                          # This documentation
├── k8s/
│   ├── namespace.yaml                 # Experiment namespace
│   ├── php-apache-deployment.yaml     # Application deployment & services
│   ├── hpa.yaml                       # Horizontal Pod Autoscaler
│   ├── pod-disruption-budget.yaml     # PDB configuration
│   └── locust-deployment.yaml         # Locust in-cluster deployment
├── locust/
│   ├── locustfile.py                  # Load test definition
│   ├── requirements.txt               # Python dependencies
│   └── Dockerfile                     # Container build file
└── scripts/
    ├── setup.sh                       # Environment setup
    ├── simulate-pod-failure.sh        # Pod failure scenarios
    ├── simulate-node-failure.sh       # Node failure scenarios
    ├── monitor.sh                     # Real-time monitoring
    ├── scale-experiment.sh            # Scale configuration tool
    └── cleanup.sh                     # Resource cleanup
```

---

## References

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [PHP-Apache HPA Example](https://k8s.io/examples/application/php-apache.yaml)
- [Locust Documentation](https://docs.locust.io/)
- [Kubernetes Self-Healing](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

---

*This experiment was designed to validate Kubernetes' self-healing capabilities in a controlled, reproducible manner suitable for educational and demonstration purposes.*

