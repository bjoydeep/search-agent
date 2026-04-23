#!/bin/bash
# Component Deployment Health Analysis for Search Operator
# Weight: 25% of overall assessment
# Part of search-operator-impact assessment methodology

set -euo pipefail

echo "=== Component Deployment Health Analysis ==="

# Helper function for component deployment checks with execution logging
component_health_check() {
  local component="$1"
  local namespace="$2"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] COMPONENT_HEALTH_CHECK: $component in namespace $namespace" >> "${EXECUTION_LOG:-/dev/null}"

  # Check deployment status
  local deployment_info=$(kubectl get deployment -n "$namespace" "$component" -o jsonpath='{.metadata.name}: {.spec.replicas} desired, {.status.readyReplicas} ready, {.status.availableReplicas} available' 2>/dev/null || echo "")

  if [ ! -z "$deployment_info" ]; then
    echo "[$timestamp] COMPONENT_STATUS: $deployment_info" >> "${EXECUTION_LOG:-/dev/null}"
    echo "  ✅ $deployment_info"
    return 0
  else
    echo "[$timestamp] COMPONENT_ERROR: $component deployment not found" >> "${EXECUTION_LOG:-/dev/null}"
    echo "  ❌ $component: Not found"
    return 1
  fi
}

# Discover ACM namespace
echo "=== Discovering ACM Namespace ==="
ACM_NAMESPACE=$(kubectl get multiclusterhub -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace 2>/dev/null | head -1 || echo "open-cluster-management")

if [ "$ACM_NAMESPACE" = "" ]; then
  ACM_NAMESPACE="open-cluster-management"
  echo "Using default namespace: $ACM_NAMESPACE"
else
  echo "Found ACM namespace: $ACM_NAMESPACE"
fi

echo "$(date '+%H:%M:%S') ACM_NAMESPACE_DISCOVERY: $ACM_NAMESPACE" >> "${EXECUTION_LOG:-/dev/null}"

# Component deployment health analysis
echo ""
echo "Component deployment status:"

component_health_check "search-indexer" "$ACM_NAMESPACE"
component_health_check "search-api" "$ACM_NAMESPACE"
component_health_check "search-postgres" "$ACM_NAMESPACE"

# Search CR status analysis with execution logging
echo ""
echo "=== Search CR Health Analysis ==="
echo "$(date '+%H:%M:%S') SEARCH_CR_ANALYSIS: Starting Search custom resource analysis" >> "${EXECUTION_LOG:-/dev/null}"

SEARCH_CRS=$(kubectl get search -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,REASON:.status.conditions[?(@.type=='Ready')].reason,MESSAGE:.status.conditions[?(@.type=='Ready')].message" 2>/dev/null || echo "")

if [ ! -z "$SEARCH_CRS" ] && [ "$SEARCH_CRS" != "No resources found" ]; then
  echo "$SEARCH_CRS" | awk 'NR>1 {print "  " $1 "/" $2 ": " $3 " (" $4 ") - " $5}'
  echo "$(date '+%H:%M:%S') SEARCH_CR_COUNT: $(echo "$SEARCH_CRS" | wc -l)" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "  ❌ No Search CRs found"
  echo "$(date '+%H:%M:%S') SEARCH_CR_WARNING: No Search custom resources found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Component availability from Prometheus (if available)
echo ""
echo "=== Component Availability (from Prometheus) ==="
echo "$(date '+%H:%M:%S') PROMETHEUS_COMPONENT_CHECK: Checking component availability via Prometheus" >> "${EXECUTION_LOG:-/dev/null}"

# Try to find prometheus pod
PROM_POD=$(kubectl get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1 2>/dev/null || echo "")

if [ ! -z "$PROM_POD" ]; then
  echo "  Indexer pod readiness:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22search-indexer%22%7D" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for result in data['data']['result']:
            value = result['value'][1]
            print(f'    Indexer availability: {value}')
    else:
        print('    Indexer metrics not available')
except:
    print('    Indexer metrics not available')
" || echo "    Indexer metrics not available"

  echo "  API pod readiness:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22search-api%22%7D" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for result in data['data']['result']:
            value = result['value'][1]
            print(f'    API availability: {value}')
    else:
        print('    API metrics not available')
except:
    print('    API metrics not available')
" || echo "    API metrics not available"

  echo "  PostgreSQL pod readiness:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22postgres%22%7D" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for result in data['data']['result']:
            value = result['value'][1]
            print(f'    PostgreSQL availability: {value}')
    else:
        print('    PostgreSQL metrics not available')
except:
    print('    PostgreSQL metrics not available')
" || echo "    PostgreSQL metrics not available"
else
  echo "  ⚠️  Prometheus pod not available for component availability checks"
fi

# Recent deployment events analysis
echo ""
echo "=== Recent Deployment Events Analysis ==="
echo "$(date '+%H:%M:%S') DEPLOYMENT_EVENTS_ANALYSIS: Checking recent deployment events" >> "${EXECUTION_LOG:-/dev/null}"

echo "Recent deployment failures:"
RECENT_FAILURES=$(kubectl get events -n "$ACM_NAMESPACE" --field-selector reason=FailedCreate --sort-by='.lastTimestamp' 2>/dev/null | tail -3 || echo "")

if [ ! -z "$RECENT_FAILURES" ] && [ "$(echo "$RECENT_FAILURES" | wc -l)" -gt 1 ]; then
  echo "$RECENT_FAILURES" | awk 'NR>1 {print "  " $1 " " $2 ": " $NF}'
  echo "$(date '+%H:%M:%S') RECENT_DEPLOYMENT_FAILURES: $(echo "$RECENT_FAILURES" | wc -l) failure events found" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "  ✅ No recent deployment failures"
  echo "$(date '+%H:%M:%S') RECENT_DEPLOYMENT_FAILURES: 0 failure events found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Component pod status analysis
echo ""
echo "=== Component Pod Status Analysis ==="
echo "$(date '+%H:%M:%S') POD_STATUS_ANALYSIS: Analyzing component pod status" >> "${EXECUTION_LOG:-/dev/null}"

for component in search-indexer search-api search-postgres; do
  POD_STATUS=$(kubectl get pods -n "$ACM_NAMESPACE" -l app="$component" --no-headers 2>/dev/null | head -1 || echo "")

  if [ ! -z "$POD_STATUS" ]; then
    echo "  $component pod: $POD_STATUS"
    echo "$(date '+%H:%M:%S') COMPONENT_POD_STATUS: $component - $POD_STATUS" >> "${EXECUTION_LOG:-/dev/null}"
  else
    echo "  ❌ $component pod: Not found"
    echo "$(date '+%H:%M:%S') COMPONENT_POD_ERROR: $component pod not found" >> "${EXECUTION_LOG:-/dev/null}"
  fi
done

echo ""
echo "Component deployment health analysis completed."
echo "Key findings:"
echo "  - Component availability via Kubernetes API analyzed"
echo "  - Search CR status evaluated"
echo "  - Recent deployment events reviewed"
echo "  - Component pod status assessed"