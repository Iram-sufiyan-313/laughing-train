# 🧠 Self-Healing Autonomous Runtime Layer

## Overview

This system implements **production-grade operational resilience** that automatically detects failures, diagnoses root causes, and recovers without human intervention.

---

## Architecture

```
📊 OBSERVABILITY SIGNALS
(CloudWatch + Logs + Metrics)
         ↓
🧠 HEALTH EVALUATION ENGINE
(Lambda: health_monitor every 5 min)
         ↓
    ┌────┴────┬─────────────┬──────────────┬─────────────┐
    ↓         ↓            ↓              ↓             ↓
🔁 RESTART  📉 ROLLBACK  ⚖️ AUTO-SCALE  🧯 BACKPRESSURE
    ↓         ↓            ↓              ↓             ↓
      🧬 SIMULATION (RECOVERY LOOP)
           ↓
    📊 STATE VALIDATION
           ↓
    🧯 SAFE CONTINUATION
```

---

## Quick Start

### 1. Deploy Infrastructure

```bash
cd infra
terraform init
terraform plan
terraform apply
```

### 2. Build Worker Container

```bash
cd worker
docker build -t ai-civ-worker:latest .
aws ecr get-login-password | docker login --username AWS --password-stdin <ECR_URI>
docker tag ai-civ-worker:latest <ECR_URI>:latest
docker push <ECR_URI>:latest
```

### 3. Monitor

```bash
# View health monitor logs
aws logs tail /aws/lambda/ai-civ-health-monitor --follow

# View ECS logs
aws logs tail /ecs/ai-civ-worker --follow

# View CloudWatch dashboard
# AWS Console → CloudWatch → Dashboards → ai-civ-self-healing
```

---

## Key Components

### Health Monitor Lambda (Every 5 minutes)
- ✅ Collects CPU, memory, queue depth metrics
- ✅ Evaluates system health
- ✅ Triggers recovery actions via SNS

### Recovery Handler Lambda (On SNS trigger)
- ✅ Restarts ECS tasks
- ✅ Scales up workers
- ✅ Applies backpressure (reduces tick rate)
- ✅ Rolls back deployments

### CloudWatch Alarms
- ✅ High CPU (80%)
- ✅ High Memory (85%)
- ✅ Queue Backlog (5000 msgs)
- ✅ DLQ Messages (1+)
- ✅ Low Task Count
- ✅ Deployment Failures

### ECS Circuit Breaker
- ✅ Auto-rollback on deployment failure
- ✅ No manual intervention needed

### Adaptive Auto-Scaling
- ✅ Primary: SQS queue depth
- ✅ Secondary: CPU utilization
- ✅ Min: 2 tasks, Max: 10 tasks

### Simulation Backpressure
- ✅ Queue-aware tick rate reduction
- ✅ Prevents runaway backlog
- ✅ Gradual recovery

---

## Recovery Scenarios

### High CPU
1. Detected by CloudWatch alarm
2. SNS triggers recovery handler
3. ECS service restarted
4. Tasks redistributed → CPU drops
5. System stabilizes

**Time**: ~2-5 minutes

### Queue Backlog
1. Detected by health monitor
2. Scale-up triggered (adds 2 tasks)
3. Backpressure applied (reduce tick rate)
4. New tasks drain backlog
5. Queue depth decreases
6. Tick rate gradually increases

**Time**: ~3-8 minutes

### Task Crash
1. ECS auto-replaces failed task
2. Message re-delivered by SQS
3. Health monitor alerts if not resolved
4. Force restart triggered if needed

**Time**: ~30s-2min (ECS) + 2-5min (health monitor)

### Bad Deployment
1. New deployment starts
2. Health checks fail
3. Circuit breaker detects failure
4. Automatic rollback to previous version
5. Service returns to working state

**Time**: ~2-5 minutes

---

## Configuration

Edit `infra/variables.tf`:

```hcl
cpu_high_threshold = 85              # Restart threshold (%)
cpu_low_threshold = 30               # Scale-down threshold (%)
queue_depth_threshold = 5000         # Backpressure trigger
tick_rate_reduction_factor = 0.5     # Backpressure factor (0-1)
health_check_interval = 5             # Minutes between checks
```

---

## Monitoring

### CloudWatch Dashboard
- 🧠 CPU & Memory utilization
- 📊 Queue depth
- 🚀 Task count (running vs desired)
- ❤️ System health status
- 📈 Recovery actions triggered

### Logs
```bash
# Health Monitor
aws logs tail /aws/lambda/ai-civ-health-monitor --follow

# Recovery Handler
aws logs tail /aws/lambda/ai-civ-health-recovery --follow

# ECS Worker
aws logs tail /ecs/ai-civ-worker --follow
```

### Key Metrics
| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| CPU | < 50% | 50-80% | > 80% |
| Memory | < 60% | 60-85% | > 85% |
| Queue | < 100 | 100-5000 | > 5000 |
| Tasks | Running = Desired | - | Running < Desired |
| Error Rate | < 0.1% | 0.1-1% | > 1% |

---

## Troubleshooting

### Frequent Restarts
**Fix**: Increase CPU threshold or add more resources
```bash
terraform apply -var="cpu_high_threshold=90"
```

### Queue Not Draining
**Fix**: Check worker logs and manually scale up
```bash
aws ecs update-service --cluster ai-civ-cluster --service ai-civ-worker --desired-count 10
```

### DLQ Growing
**Fix**: Investigate worker logs for persistent failures
```bash
aws logs tail /ecs/ai-civ-worker --follow
```

---

## Best Practices

✅ Monitor the monitors (set Lambda alerts)  
✅ Test recovery regularly  
✅ Tune thresholds for your workload  
✅ Review DLQ messages weekly  
✅ Keep Lambda dependencies current  
✅ Version control all Terraform  
✅ Document threshold changes  

---

## Limitations

This is **NOT**:
- Self-improving AI
- Autonomous decision making
- Self-modifying code
- Emergent reasoning system

This **IS**:
- Production SRE automation
- Deterministic recovery rules
- Similar to Netflix/AWS patterns
- Safe automation boundary

---

## What's Next?

🎯 **Next Evolution**: Multi-tenant SaaS platform
- Per-customer simulation clusters
- Billing & quota enforcement
- Marketplace for templates
- Role-based access control

Say: "🔐 make full multi-tenant simulation SaaS platform"
