#!/bin/bash
# Operator Resource Consumption and Stability Analysis for Search Operator
# Weight: 15% of overall assessment
# Part of search-operator-impact assessment methodology

set -euo pipefail

echo "=== Operator Resource Analysis ==="

# Helper function for resource analysis with execution logging
resource_analysis() {
  local analysis_type="$1"
  local description="$2"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] RESOURCE_ANALYSIS: $analysis_type - $description" >> "${EXECUTION_LOG:-/dev/null}"
}

# Discover ACM namespace (reuse from component-deployment)
ACM_NAMESPACE=$(kubectl get multiclusterhub -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace 2>/dev/null | head -1 || echo "open-cluster-management")

if [ "$ACM_NAMESPACE" = "" ]; then
  ACM_NAMESPACE="open-cluster-management"
fi

echo "Using ACM namespace: $ACM_NAMESPACE"
echo "$(date '+%H:%M:%S') ACM_NAMESPACE: $ACM_NAMESPACE" >> "${EXECUTION_LOG:-/dev/null}"

# Current operator resource usage
echo ""
echo "=== Current Operator Resource Usage ==="
resource_analysis "current_usage" "Collecting current operator resource consumption"

OPERATOR_RESOURCE_USAGE=$(kubectl top pods -n "$ACM_NAMESPACE" -l control-plane=search-controller-manager --no-headers 2>/dev/null || echo "")

if [ ! -z "$OPERATOR_RESOURCE_USAGE" ]; then
  echo "Operator Resource Usage:"
  echo "$OPERATOR_RESOURCE_USAGE" | awk '{print "  " $1 ": CPU " $3 ", Memory " $4}'
  echo "$(date '+%H:%M:%S') OPERATOR_RESOURCE_DATA: $OPERATOR_RESOURCE_USAGE" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "  ⚠️  Resource metrics not available"
  echo "$(date '+%H:%M:%S') OPERATOR_RESOURCE_WARNING: Resource metrics not available" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Find operator pod for detailed analysis
OPERATOR_POD=$(kubectl get pods -n "$ACM_NAMESPACE" -l control-plane=search-controller-manager --no-headers -o custom-columns=:metadata.name 2>/dev/null | head -1 || echo "")

if [ -z "$OPERATOR_POD" ]; then
  # Try alternative label selectors
  OPERATOR_POD=$(kubectl get pods -n "$ACM_NAMESPACE" -l app=search-operator --no-headers -o custom-columns=:metadata.name 2>/dev/null | head -1 || echo "")
  if [ -z "$OPERATOR_POD" ]; then
    OPERATOR_POD=$(kubectl get pods -n "$ACM_NAMESPACE" | grep search.*operator | awk '{print $1}' | head -1 || echo "")
  fi
fi

echo "$(date '+%H:%M:%S') OPERATOR_POD_DISCOVERY: $OPERATOR_POD" >> "${EXECUTION_LOG:-/dev/null}"

# Resource requests and limits analysis
echo ""
echo "=== Resource Configuration Analysis ==="
resource_analysis "config" "Analyzing resource requests and limits"

if [ ! -z "$OPERATOR_POD" ]; then
  echo "Resource Configuration for $OPERATOR_POD:"

  RESOURCE_CONFIG=$(kubectl get pod -n "$ACM_NAMESPACE" "$OPERATOR_POD" -o jsonpath='{range .spec.containers[*]}Container: {.name}{"\n"}  CPU Request: {.resources.requests.cpu}{"\n"}  CPU Limit: {.resources.limits.cpu}{"\n"}  Memory Request: {.resources.requests.memory}{"\n"}  Memory Limit: {.resources.limits.memory}{"\n"}{end}' 2>/dev/null || echo "")

  if [ ! -z "$RESOURCE_CONFIG" ]; then
    echo "$RESOURCE_CONFIG" | sed 's/^/  /'
    echo "$(date '+%H:%M:%S') RESOURCE_CONFIG: $RESOURCE_CONFIG" >> "${EXECUTION_LOG:-/dev/null}"
  else
    echo "  ⚠️  Could not retrieve resource configuration"
    echo "$(date '+%H:%M:%S') RESOURCE_CONFIG_ERROR: Could not retrieve configuration" >> "${EXECUTION_LOG:-/dev/null}"
  fi
else
  echo "  ❌ Operator pod not found"
  echo "$(date '+%H:%M:%S') OPERATOR_POD_ERROR: Operator pod not found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Historical resource trends from Prometheus (if available)
echo ""
echo "=== Historical Resource Trends (from Prometheus) ==="
resource_analysis "prometheus" "Collecting historical resource trends"

PROM_POD=$(kubectl get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1 2>/dev/null || echo "")

if [ ! -z "$PROM_POD" ]; then
  echo "  CPU usage (last 5 min average):"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=avg(rate(container_cpu_usage_seconds_total%7Bpod%3D~%22search-controller-manager.*%22%7D%5B5m%5D))" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for result in data['data']['result']:
            value = float(result['value'][1])
            print(f'    Average CPU usage: {value:.4f} cores')
    else:
        print('    CPU metrics not available')
except:
    print('    CPU metrics not available')
" || echo "    CPU metrics not available"

  echo "  Memory usage (current):"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=avg(container_memory_working_set_bytes%7Bpod%3D~%22search-controller-manager.*%22%7D)" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for result in data['data']['result']:
            value = int(result['value'][1])
            mb = value / (1024 * 1024)
            print(f'    Current memory usage: {mb:.1f} MB')
    else:
        print('    Memory metrics not available')
except:
    print('    Memory metrics not available')
" || echo "    Memory metrics not available"

  echo "  Container restart count:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=sum(kube_pod_container_status_restarts_total%7Bpod%3D~%22search-controller-manager.*%22%7D)" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for result in data['data']['result']:
            value = int(result['value'][1])
            print(f'    Total container restarts: {value}')
    else:
        print('    Restart metrics not available')
except:
    print('    Restart metrics not available')
" || echo "    Restart metrics not available"
else
  echo "  ⚠️  Prometheus pod not available for resource trend analysis"
  echo "$(date '+%H:%M:%S') PROMETHEUS_RESOURCE_WARNING: Prometheus not available" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Leader election stability analysis
echo ""
echo "=== Leader Election Stability Analysis ==="
resource_analysis "leader_election" "Analyzing leader election stability"

LEASE_HOLDER=$(kubectl get lease -n "$ACM_NAMESPACE" search-controller-manager -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || echo "")

if [ ! -z "$LEASE_HOLDER" ]; then
  echo "Leader Election Status:"
  echo "  Current leader: $LEASE_HOLDER"
  echo "$(date '+%H:%M:%S') LEADER_ELECTION_HOLDER: $LEASE_HOLDER" >> "${EXECUTION_LOG:-/dev/null}"

  # Count recent lease events
  LEASE_TRANSITIONS=$(kubectl get events -n "$ACM_NAMESPACE" --field-selector involvedObject.name=search-controller-manager,involvedObject.kind=Lease --sort-by='.lastTimestamp' 2>/dev/null | wc -l || echo "0")
  echo "  Recent lease events: $LEASE_TRANSITIONS"
  echo "$(date '+%H:%M:%S') LEADER_ELECTION_EVENTS: $LEASE_TRANSITIONS" >> "${EXECUTION_LOG:-/dev/null}"

  if [ "$LEASE_TRANSITIONS" -gt 5 ]; then
    echo "  ⚠️  High leader election activity detected (potential instability)"
  else
    echo "  ✅ Stable leader election"
  fi
else
  echo "  ⚠️  Leader election lease not found"
  echo "$(date '+%H:%M:%S') LEADER_ELECTION_WARNING: Lease not found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Operator stability indicators
echo ""
echo "=== Operator Stability Analysis ==="
resource_analysis "stability" "Analyzing operator stability indicators"

if [ ! -z "$OPERATOR_POD" ]; then
  echo "Operator Stability for $OPERATOR_POD:"

  # Restart count
  RESTART_COUNT=$(kubectl get pod -n "$ACM_NAMESPACE" "$OPERATOR_POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "unknown")
  echo "  Restart count: $RESTART_COUNT"
  echo "$(date '+%H:%M:%S') OPERATOR_RESTART_COUNT: $RESTART_COUNT" >> "${EXECUTION_LOG:-/dev/null}"

  # Pod age
  POD_AGE=$(kubectl get pod -n "$ACM_NAMESPACE" "$OPERATOR_POD" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null | xargs -I {} date -d {} +%s 2>/dev/null || echo "")
  if [ ! -z "$POD_AGE" ]; then
    CURRENT_TIME=$(date +%s)
    AGE_SECONDS=$((CURRENT_TIME - POD_AGE))
    AGE_HOURS=$((AGE_SECONDS / 3600))
    echo "  Pod age: ${AGE_HOURS} hours"
    echo "$(date '+%H:%M:%S') OPERATOR_POD_AGE_HOURS: $AGE_HOURS" >> "${EXECUTION_LOG:-/dev/null}"
  fi

  # Check for resource pressure warnings in logs
  echo "  Analyzing recent logs for resource pressure..."
  PRESSURE_WARNINGS=$(kubectl logs -n "$ACM_NAMESPACE" "$OPERATOR_POD" --tail=50 2>/dev/null | grep -icE "(memory.*pressure|cpu.*throttle|resource.*limit|oom)" || echo "0")
  echo "  Resource pressure warnings: $PRESSURE_WARNINGS"
  echo "$(date '+%H:%M:%S') OPERATOR_PRESSURE_WARNINGS: $PRESSURE_WARNINGS" >> "${EXECUTION_LOG:-/dev/null}"

  if [ "$PRESSURE_WARNINGS" -gt 0 ]; then
    echo "  ⚠️  Resource pressure detected in logs"
    echo "  Recent pressure-related log entries:"
    kubectl logs -n "$ACM_NAMESPACE" "$OPERATOR_POD" --tail=50 2>/dev/null | grep -iE "(memory.*pressure|cpu.*throttle|resource.*limit|oom)" | tail -3 | sed 's/^/    /' || echo "    No specific pressure log entries found"
  else
    echo "  ✅ No resource pressure warnings in recent logs"
  fi

  # Check pod status
  POD_STATUS=$(kubectl get pod -n "$ACM_NAMESPACE" "$OPERATOR_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
  echo "  Pod status: $POD_STATUS"
  echo "$(date '+%H:%M:%S') OPERATOR_POD_STATUS: $POD_STATUS" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "  ❌ Operator pod status unknown (pod not found)"
  echo "$(date '+%H:%M:%S') OPERATOR_STABILITY_ERROR: Pod not found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Resource utilization summary
echo ""
echo "=== Resource Utilization Summary ==="
resource_analysis "summary" "Generating resource utilization summary"

if [ ! -z "$OPERATOR_RESOURCE_USAGE" ]; then
  # Extract CPU and memory values for analysis
  CPU_USAGE=$(echo "$OPERATOR_RESOURCE_USAGE" | awk '{print $3}' | head -1)
  MEMORY_USAGE=$(echo "$OPERATOR_RESOURCE_USAGE" | awk '{print $4}' | head -1)

  echo "Resource Health Assessment:"
  echo "  Current CPU usage: $CPU_USAGE"
  echo "  Current memory usage: $MEMORY_USAGE"

  # Simple heuristic for resource health (more sophisticated analysis would compare against limits)
  if echo "$MEMORY_USAGE" | grep -qE "[0-9]+Mi$"; then
    MEMORY_MB=$(echo "$MEMORY_USAGE" | sed 's/Mi//')
    if [ ! -z "$MEMORY_MB" ] && [ "$MEMORY_MB" -lt 500 ] 2>/dev/null; then
      echo "  ✅ Memory usage appears healthy (< 500Mi)"
    elif [ ! -z "$MEMORY_MB" ] && [ "$MEMORY_MB" -lt 1000 ] 2>/dev/null; then
      echo "  ⚠️  Memory usage moderate (500Mi-1Gi)"
    elif [ ! -z "$MEMORY_MB" ] && [ "$MEMORY_MB" -ge 1000 ] 2>/dev/null; then
      echo "  ❌ Memory usage high (> 1Gi)"
    else
      echo "  ℹ️  Memory usage format not recognized: $MEMORY_USAGE"
    fi
  fi

  echo "$(date '+%H:%M:%S') RESOURCE_SUMMARY: CPU=$CPU_USAGE, Memory=$MEMORY_USAGE" >> "${EXECUTION_LOG:-/dev/null}"
fi

echo ""
echo "Operator resource analysis completed."
echo "Key findings:"
echo "  - Current resource usage analyzed"
echo "  - Resource configuration assessed"
echo "  - Historical trends reviewed"
echo "  - Leader election stability evaluated"
echo "  - Operator stability indicators checked"