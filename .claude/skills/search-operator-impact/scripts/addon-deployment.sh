#!/bin/bash
# ManagedClusterAddOn Deployment Success Analysis for Search Operator
# Weight: 20% of overall assessment
# Part of search-operator-impact assessment methodology

set -euo pipefail

echo "=== ManagedClusterAddOn Deployment Analysis ==="

# Helper function for addon analysis with execution logging
addon_analysis() {
  local description="$1"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] ADDON_ANALYSIS: $description" >> "${EXECUTION_LOG:-/dev/null}"
}

# Overall addon deployment success rate calculation
echo "=== Addon Deployment Success Rate Calculation ==="
echo "$(date '+%H:%M:%S') ADDON_SUCCESS_ANALYSIS: Starting addon deployment success analysis" >> "${EXECUTION_LOG:-/dev/null}"

TOTAL_CLUSTERS=$(kubectl get managedclusters --no-headers 2>/dev/null | wc -l || echo "0")
SUCCESSFUL_ADDONS=$(kubectl get managedclusteraddons search -A --no-headers 2>/dev/null | grep -c Available || echo "0")

echo "$(date '+%H:%M:%S') ADDON_CLUSTER_COUNT: Total clusters: $TOTAL_CLUSTERS" >> "${EXECUTION_LOG:-/dev/null}"
echo "$(date '+%H:%M:%S') ADDON_SUCCESS_COUNT: Successful addons: $SUCCESSFUL_ADDONS" >> "${EXECUTION_LOG:-/dev/null}"

echo "Addon Deployment Summary:"
if [ "$TOTAL_CLUSTERS" -gt 0 ]; then
  # Use awk for floating point calculation
  SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", $SUCCESSFUL_ADDONS * 100 / $TOTAL_CLUSTERS}" 2>/dev/null || echo "0.0")
  echo "  Total clusters: $TOTAL_CLUSTERS"
  echo "  Successful addon deployments: $SUCCESSFUL_ADDONS"
  echo "  Success rate: ${SUCCESS_RATE}%"

  # Log success rate calculation
  echo "$(date '+%H:%M:%S') ADDON_SUCCESS_RATE: ${SUCCESS_RATE}%" >> "${EXECUTION_LOG:-/dev/null}"

  # Determine success rate level for logging
  if (( $(echo "$SUCCESS_RATE >= 95" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ✅ Excellent addon deployment success rate"
  elif (( $(echo "$SUCCESS_RATE >= 90" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ⚠️  Good addon deployment success rate (some issues detected)"
  else
    echo "  ❌ Poor addon deployment success rate (needs attention)"
  fi
else
  echo "  ⚠️  No managed clusters found"
  echo "$(date '+%H:%M:%S') ADDON_WARNING: No managed clusters found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Detailed addon status analysis
echo ""
echo "=== Detailed Addon Status Analysis ==="
addon_analysis "Collecting detailed addon status information"

ADDON_STATUS=$(kubectl get managedclusteraddons search -A -o custom-columns="CLUSTER:.metadata.namespace,STATUS:.status.conditions[-1].type,REASON:.status.conditions[-1].reason,MESSAGE:.status.conditions[-1].message" 2>/dev/null || echo "")

if [ ! -z "$ADDON_STATUS" ] && [ "$(echo "$ADDON_STATUS" | wc -l)" -gt 1 ]; then
  echo "Addon Status Details:"
  FAILED_ADDONS=$(echo "$ADDON_STATUS" | awk 'NR>1 && $2!="Available" {count++; print "  " $1 ": " $2 " (" $3 ") - " $4} END {print "FAILED_COUNT:" count}')

  # Extract failed count
  FAILED_COUNT=$(echo "$FAILED_ADDONS" | grep "FAILED_COUNT:" | cut -d: -f2 || echo "0")

  # Show failed addons (excluding the count line)
  FAILED_DISPLAY=$(echo "$FAILED_ADDONS" | grep -v "FAILED_COUNT:" || echo "")

  if [ ! -z "$FAILED_DISPLAY" ]; then
    echo "$FAILED_DISPLAY"
    echo "$(date '+%H:%M:%S') ADDON_FAILURES: $FAILED_COUNT failed addon deployments" >> "${EXECUTION_LOG:-/dev/null}"
  else
    echo "  ✅ No failed addons detected"
    echo "$(date '+%H:%M:%S') ADDON_FAILURES: 0 failed addon deployments" >> "${EXECUTION_LOG:-/dev/null}"
  fi
else
  echo "  ⚠️  No addon status information available"
  echo "$(date '+%H:%M:%S') ADDON_STATUS_WARNING: No addon status information available" >> "${EXECUTION_LOG:-/dev/null}"
fi

# ManifestWork analysis (addon framework dependency)
echo ""
echo "=== ManifestWork Health Analysis ==="
echo "$(date '+%H:%M:%S') MANIFESTWORK_ANALYSIS: Analyzing ManifestWork health" >> "${EXECUTION_LOG:-/dev/null}"

SEARCH_MANIFESTWORKS=$(kubectl get manifestworks -A --no-headers 2>/dev/null | grep search || echo "")

if [ ! -z "$SEARCH_MANIFESTWORKS" ]; then
  echo "ManifestWork Health:"
  MANIFESTWORK_COUNT=$(echo "$SEARCH_MANIFESTWORKS" | wc -l)
  echo "  Found $MANIFESTWORK_COUNT search-related ManifestWorks:"

  echo "$SEARCH_MANIFESTWORKS" | awk '{print "    " $1 "/" $2 ": " $3}' | head -10

  if [ "$MANIFESTWORK_COUNT" -gt 10 ]; then
    echo "    ... and $(($MANIFESTWORK_COUNT - 10)) more"
  fi

  echo "$(date '+%H:%M:%S') MANIFESTWORK_COUNT: $MANIFESTWORK_COUNT" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "  ⚠️  No search ManifestWorks found"
  echo "$(date '+%H:%M:%S') MANIFESTWORK_WARNING: No search ManifestWorks found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Addon deployment patterns from Prometheus (if available)
echo ""
echo "=== Addon Metrics from Prometheus ==="
echo "$(date '+%H:%M:%S') PROMETHEUS_ADDON_METRICS: Attempting to collect addon metrics from Prometheus" >> "${EXECUTION_LOG:-/dev/null}"

# Try to find prometheus pod
PROM_POD=$(kubectl get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1 2>/dev/null || echo "")

if [ ! -z "$PROM_POD" ]; then
  echo "  ManifestWork success rate:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=sum(kube_manifestwork_status_condition%7Bcondition%3D%22Applied%22%2Cstatus%3D%22True%22%7D)%20%2F%20sum(kube_manifestwork_status_condition%7Bcondition%3D%22Applied%22%7D)" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for result in data['data']['result']:
            value = float(result['value'][1]) * 100
            print(f'    ManifestWork applied rate: {value:.1f}%')
    else:
        print('    ManifestWork metrics not available')
except Exception as e:
    print('    ManifestWork metrics not available')
" || echo "    ManifestWork metrics not available"

  echo "  Addon deployment events rate:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=sum(rate(kube_managedclusteraddon_status_condition%5B5m%5D))" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for result in data['data']['result']:
            value = result['value'][1]
            print(f'    Addon condition change rate: {value} events/sec')
    else:
        print('    Addon event metrics not available')
except:
    print('    Addon event metrics not available')
" || echo "    Addon event metrics not available"
else
  echo "  ⚠️  Prometheus pod not available for addon metrics"
  echo "$(date '+%H:%M:%S') PROMETHEUS_ADDON_WARNING: Prometheus pod not available" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Cluster-specific addon analysis
echo ""
echo "=== Cluster-Specific Addon Analysis ==="
echo "$(date '+%H:%M:%S') CLUSTER_ADDON_ANALYSIS: Analyzing addon status per cluster" >> "${EXECUTION_LOG:-/dev/null}"

# Get list of clusters with their addon status
CLUSTER_ADDON_STATUS=$(kubectl get managedclusteraddons search -A -o custom-columns="CLUSTER:.metadata.namespace,ADDON:.metadata.name,STATUS:.status.conditions[-1].type,READY:.status.conditions[?(@.type=='Available')].status" --no-headers 2>/dev/null || echo "")

if [ ! -z "$CLUSTER_ADDON_STATUS" ]; then
  echo "Per-cluster addon status:"

  # Count successful and failed clusters
  AVAILABLE_CLUSTERS=$(echo "$CLUSTER_ADDON_STATUS" | awk '$3=="Available" {count++} END {print count+0}')
  DEGRADED_CLUSTERS=$(echo "$CLUSTER_ADDON_STATUS" | awk '$3!="Available" {count++} END {print count+0}')

  echo "  Available clusters: $AVAILABLE_CLUSTERS"
  echo "  Degraded clusters: $DEGRADED_CLUSTERS"

  # Show degraded clusters if any
  if [ "$DEGRADED_CLUSTERS" -gt 0 ]; then
    echo "  Degraded cluster details:"
    echo "$CLUSTER_ADDON_STATUS" | awk '$3!="Available" {print "    " $1 ": " $3}' | head -5

    if [ "$DEGRADED_CLUSTERS" -gt 5 ]; then
      echo "    ... and $(($DEGRADED_CLUSTERS - 5)) more degraded clusters"
    fi
  fi

  echo "$(date '+%H:%M:%S') CLUSTER_ADDON_AVAILABLE: $AVAILABLE_CLUSTERS" >> "${EXECUTION_LOG:-/dev/null}"
  echo "$(date '+%H:%M:%S') CLUSTER_ADDON_DEGRADED: $DEGRADED_CLUSTERS" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "  ⚠️  No cluster addon status information available"
  echo "$(date '+%H:%M:%S') CLUSTER_ADDON_WARNING: No cluster addon status available" >> "${EXECUTION_LOG:-/dev/null}"
fi

echo ""
echo "ManagedClusterAddOn deployment analysis completed."
echo "Key findings:"
echo "  - Addon deployment success rate calculated across all clusters"
echo "  - Failed addon deployments identified with reasons"
echo "  - ManifestWork health assessed"
echo "  - Per-cluster addon status analyzed"