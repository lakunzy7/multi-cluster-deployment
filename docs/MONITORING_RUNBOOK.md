# Monitoring and Observability Runbook

## Monitoring Stack Overview

**Components:**
- Prometheus: Metrics collection and storage
- Grafana: Visualization and alerting
- Alertmanager: Alert routing and notifications
- Loki: Log aggregation
- Jaeger: Distributed tracing
- Promtail: Log shipping agent

## Accessing Monitoring Dashboards

### Grafana
```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80

# Access: http://localhost:3000
# Default credentials: admin / <password-from-secret>

# Get admin password
kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Prometheus
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Access: http://localhost:9090

# Query examples:
# - rate(http_requests_total[5m])
# - container_memory_usage_bytes
# - node_cpu_seconds_total
```

### Alertmanager
```bash
# Port-forward to Alertmanager
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093

# Access: http://localhost:9093
```

### Loki (Logs)
```bash
# Access via Grafana Explore tab
# Data source: Loki
# Query: {job="prometheus"}
```

### Jaeger (Traces)
```bash
# Port-forward to Jaeger
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686

# Access: http://localhost:16686
# Select service: analytics-platform
```

## Key Metrics to Monitor

### Cluster Health
```prometheus
# Node status
kube_node_status_condition{condition="Ready",status="true"}

# Pod status
kube_pod_status_phase{phase="Running"}

# Deployment replicas
kube_deployment_status_replicas_available
```

### Application Performance
```prometheus
# Request rate
rate(http_requests_total[5m])

# Response latency (p95)
histogram_quantile(0.95, http_request_duration_seconds)

# Error rate
rate(http_requests_total{status=~"5.."}[5m])

# Database query latency
rate(db_query_duration_seconds[5m])
```

### Resource Utilization
```prometheus
# CPU usage per node
rate(node_cpu_seconds_total{mode!="idle"}[5m])

# Memory usage per node
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Disk usage
(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes))

# Network I/O
rate(node_network_receive_bytes_total[5m])
```

## Alert Thresholds

| Alert | Condition | Severity |
|-------|-----------|----------|
| PodCrashLooping | crash restarts > 0.1/min for 5m | Critical |
| PodNotHealthy | pending/unknown for > 15m | Warning |
| NodeNotReady | node ready=false for > 5m | Critical |
| HighMemoryUsage | usage > 85% for > 5m | Warning |
| HighCPUUsage | usage > 80% for > 5m | Warning |
| PersistentVolumeHigh | usage > 80% | Warning |
| APILatencyHigh | p95 latency > 1s | Warning |
| ErrorRateHigh | error rate > 1% | Warning |

## Common Queries

### Pod Restarts
```bash
# Pods with recent restarts
kubectl get pods -A --sort-by=.status.containerStatuses[0].restartCount | tail -20
```

### Resource Pressure
```bash
# Nodes with memory pressure
kubectl get nodes --field-selector=status.conditions[?(@.reason=="MemoryPressure")].status=True

# Pods pending resources
kubectl get pods -A --field-selector=status.phase=Pending
```

### Events
```bash
# Recent events across cluster
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Events for specific resource
kubectl describe node <node-name>
kubectl describe pod <pod-name> -n <namespace>
```

## Creating Custom Dashboards

### Pod Metrics Dashboard
1. Open Grafana
2. Create new dashboard
3. Add panels:
   - CPU usage by pod
   - Memory usage by pod
   - Network I/O by pod
   - Restart count by pod

### Application Metrics Dashboard
1. Add panels:
   - Request rate (RPM)
   - Latency (p50, p95, p99)
   - Error rate
   - Top error types
   - Database query latency

### Node Health Dashboard
1. Add panels:
   - Node count by status
   - CPU usage by node
   - Memory usage by node
   - Disk usage by node
   - Network I/O by node

## Alert Configuration

### Update AlertManager Configuration
```bash
# Edit AlertManager config
kubectl edit configmap prometheus-kube-prometheus-alertmanager -n monitoring

# Reload configuration
kubectl rollout restart statefulset prometheus-kube-prometheus-alertmanager -n monitoring
```

### Slack Notifications
```yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

route:
  group_by: ['alertname', 'cluster']
  group_wait: 10s
  group_interval: 10s
  receiver: 'slack'
  routes:
    - match:
        severity: critical
      receiver: 'slack-critical'

receivers:
  - name: 'slack'
    slack_configs:
      - channel: '#alerts'
        title: 'CloudOpsHub Alert'
        text: '{{ .GroupLabels.alertname }}'

  - name: 'slack-critical'
    slack_configs:
      - channel: '#incidents'
        title: 'CRITICAL: {{ .GroupLabels.alertname }}'
```

## Log Aggregation with Loki

### Query Syntax
```bash
# Basic label query
{cluster="local-cluster"}

# Combined labels
{cluster="cloud-cluster", namespace="production"}

# Filter by content
{namespace="production"} |= "error"

# Exclude pattern
{namespace="production"} != "INFO"

# JSON parsing
{namespace="production"} | json | level="error"
```

### Creating Log Dashboard
1. Open Grafana Explore
2. Select Loki data source
3. Query examples:
   - `{namespace="production"} | json | level="error"` - errors in prod
   - `{namespace="production"} | json | duration > 1000` - slow requests
   - `{cluster="local-cluster"}` - all logs from local cluster

## Performance Tuning

### Prometheus Optimization
```bash
# Reduce retention (adjust in values.yaml)
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.retention=7d

# Adjust scrape intervals
kubectl edit configmap prometheus-kube-prometheus-prometheus -n monitoring
# Change scrape_interval: 15s → 30s
```

### Storage Optimization
```bash
# Check Prometheus storage
kubectl exec -it prometheus-0 -n monitoring -- du -sh /prometheus

# Clear old data
kubectl delete pvc prometheus-kube-prometheus-prometheus-db-prometheus-0 -n monitoring
```

## Incident Response with Monitoring

### High Error Rate
1. Check Grafana dashboard for error spike
2. Identify affected endpoints: `{status=~"5.."}`
3. Check application logs: `{namespace="production"} |= "error"`
4. Review recent changes: check Git history
5. Execute rollback if necessary

### High Latency
1. Identify slowest endpoints in metrics
2. Check database query latency
3. Check resource utilization (CPU, memory, disk)
4. Review distributed traces in Jaeger
5. Scale pod replicas if resource-constrained

### Pod Crashes
1. Check pod restart count
2. Review pod logs: `kubectl logs <pod> -n <namespace>`
3. Check pod events: `kubectl describe pod <pod>`
4. Check resource requests/limits
5. Review application logs for errors

## Maintenance Tasks

### Daily
- Monitor alert dashboard
- Check cluster health metrics
- Review error logs

### Weekly
- Validate backup completeness
- Review storage usage trends
- Check data retention policies

### Monthly
- Update Prometheus retention policies
- Clean up old logs
- Review and optimize slow queries
- Capacity planning review
