#!/bin/bash
# Resource Utilization Analysis for Search Indexer
# Addresses critical gap: Resource pressure detection and trend analysis
# Part of search-indexer-impact assessment methodology

set -euo pipefail

echo "=== Resource Utilization Analysis ==="

# Discover ACM namespace
ACM_NAMESPACE=$(kubectl get multiclusterhub -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace 2>/dev/null | head -1 || echo "open-cluster-management")

echo "Using ACM namespace: $ACM_NAMESPACE"
echo "$(date '+%H:%M:%S') RESOURCE_ANALYSIS_START: namespace=$ACM_NAMESPACE" >> "${EXECUTION_LOG:-/dev/null}"

# Helper function for resource analysis with execution logging
resource_check() {
  local description="$1"
  local command="$2"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] RESOURCE_CHECK: $description" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] COMMAND: $command" >> "${EXECUTION_LOG:-/dev/null}"

  echo ""
  echo "=== $description ==="

  # Execute command and capture output
  local output
  if output=$(eval "$command" 2>&1); then
    if [ -z "$output" ] || echo "$output" | grep -q "No resources found"; then
      echo "[$timestamp] RESOURCE_STATUS: no_data" >> "${EXECUTION_LOG:-/dev/null}"
      echo "[$timestamp] RESOURCE_ANALYSIS: No resource data found - pods may not exist or labels incorrect" >> "${EXECUTION_LOG:-/dev/null}"
      echo "⚠️  $description: No resources found (check pod labels and namespace)"
    else
      echo "[$timestamp] RESOURCE_STATUS: success" >> "${EXECUTION_LOG:-/dev/null}"
      echo "[$timestamp] RESOURCE_DATA: $output" >> "${EXECUTION_LOG:-/dev/null}"
      echo "$output"

      # Add analysis of resource data
      if echo "$output" | grep -q "Mi"; then
        local cpu_usage=$(echo "$output" | awk '{print $2}')
        local memory_usage=$(echo "$output" | awk '{print $3}')
        echo "  📊 Analysis: CPU usage $cpu_usage, Memory usage $memory_usage"
        echo "[$timestamp] RESOURCE_ANALYSIS: CPU=$cpu_usage, Memory=$memory_usage" >> "${EXECUTION_LOG:-/dev/null}"
      fi
    fi
  else
    echo "[$timestamp] RESOURCE_ERROR: $description failed" >> "${EXECUTION_LOG:-/dev/null}"
    echo "[$timestamp] RESOURCE_FAILURE_DETAILS: $output" >> "${EXECUTION_LOG:-/dev/null}"
    echo "⚠️  $description not available: $output"
  fi

  echo "[$timestamp] RESOURCE_CHECK_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
}

# Current Resource Usage (Indexer Components)
resource_check "Indexer Pod Resource Usage" "kubectl top pods -l name=search-indexer -n '$ACM_NAMESPACE' --no-headers"

resource_check "PostgreSQL Resource Usage" "kubectl top pods -l name=search-postgres -n '$ACM_NAMESPACE' --no-headers || kubectl top pods -n '$ACM_NAMESPACE' | grep postgres"

# Resource Limits and Requests
echo ""
echo "=== Resource Configuration Analysis ==="

INDEXER_POD=$(kubectl get pods -l name=search-indexer -n "$ACM_NAMESPACE" --no-headers -o custom-columns=:metadata.name 2>/dev/null | head -1)

if [ ! -z "$INDEXER_POD" ]; then
  echo "Resource limits and requests for $INDEXER_POD:"

  RESOURCE_CONFIG=$(kubectl get pod -n "$ACM_NAMESPACE" "$INDEXER_POD" -o jsonpath='{range .spec.containers[*]}Container: {.name}{"\n"}  CPU Request: {.resources.requests.cpu}{"\n"}  CPU Limit: {.resources.limits.cpu}{"\n"}  Memory Request: {.resources.requests.memory}{"\n"}  Memory Limit: {.resources.limits.memory}{"\n"}{end}' 2>/dev/null)

  if [ ! -z "$RESOURCE_CONFIG" ]; then
    echo "$RESOURCE_CONFIG" | sed 's/^/  /'
    echo "$(date '+%H:%M:%S') INDEXER_RESOURCE_CONFIG: $RESOURCE_CONFIG" >> "${EXECUTION_LOG:-/dev/null}"
  else
    echo "  ⚠️  Could not retrieve resource configuration"
  fi
else
  echo "  ❌ Indexer pod not found"
fi

# Storage Analysis
echo ""
echo "=== Storage Analysis ==="

POSTGRES_POD=$(kubectl get pods -l name=search-postgres -n "$ACM_NAMESPACE" --no-headers -o custom-columns=:metadata.name 2>/dev/null | head -1)

if [ ! -z "$POSTGRES_POD" ]; then
  echo "Database storage utilization:"
  STORAGE_INFO=$(kubectl exec -n "$ACM_NAMESPACE" "$POSTGRES_POD" -- df -h /var/lib/postgresql/data 2>/dev/null || echo "Storage check failed")
  echo "$STORAGE_INFO" | sed 's/^/  /'
  echo "$(date '+%H:%M:%S') POSTGRES_STORAGE: $STORAGE_INFO" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "  ⚠️  PostgreSQL pod not found for storage analysis"
fi

# Memory Pressure and Restart Analysis
echo ""
echo "=== Memory Pressure and Stability Analysis ==="

echo "Recent pod restarts and memory pressure indicators:"
RESTART_INFO=$(kubectl describe pods -l name=search-indexer -n "$ACM_NAMESPACE" 2>/dev/null | grep -A 5 -B 5 "OOMKilled\|Killed\|Failed\|Evicted\|MemoryPressure\|restart.*[1-9]" || echo "No restart indicators found")

if [ "$RESTART_INFO" != "No restart indicators found" ]; then
  echo "⚠️  Memory pressure indicators detected:"
  echo "$RESTART_INFO" | sed 's/^/  /'
  echo "$(date '+%H:%M:%S') MEMORY_PRESSURE_DETECTED: $RESTART_INFO" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "✅ No memory pressure indicators detected"
  echo "$(date '+%H:%M:%S') MEMORY_PRESSURE: none" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Network and I/O Pressure (Basic Detection)
echo ""
echo "=== Network and I/O Analysis ==="

echo "Network connectivity to PostgreSQL:"
if [ ! -z "$INDEXER_POD" ] && [ ! -z "$POSTGRES_POD" ]; then
  # Check if nc is available, if not try alternative methods
  if kubectl exec -n "$ACM_NAMESPACE" "$INDEXER_POD" -- which nc >/dev/null 2>&1; then
    NETWORK_TEST=$(kubectl exec -n "$ACM_NAMESPACE" "$INDEXER_POD" -- nc -z -v -w5 postgres 5432 2>&1)
    echo "  ✅ Network connectivity test (nc): $NETWORK_TEST"
    echo "$(date '+%H:%M:%S') NETWORK_CONNECTIVITY: nc test - $NETWORK_TEST" >> "${EXECUTION_LOG:-/dev/null}"
  else
    # Alternative: Try timeout with /dev/tcp (if available)
    NETWORK_TEST=$(kubectl exec -n "$ACM_NAMESPACE" "$INDEXER_POD" -- timeout 5 bash -c "echo >/dev/tcp/postgres/5432" 2>&1 && echo "postgres:5432 connection successful" || echo "postgres:5432 connection failed")
    echo "  ✅ Network connectivity test (/dev/tcp): $NETWORK_TEST"
    echo "$(date '+%H:%M:%S') NETWORK_CONNECTIVITY: /dev/tcp test - $NETWORK_TEST" >> "${EXECUTION_LOG:-/dev/null}"
  fi
else
  echo "  ⚠️  Cannot test network connectivity - missing pod references"
  echo "$(date '+%H:%M:%S') NETWORK_CONNECTIVITY: Cannot test - missing pod references (indexer: $INDEXER_POD, postgres: $POSTGRES_POD)" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Resource Utilization Summary
echo ""
echo "=== Resource Utilization Summary ==="

# Try to extract actual utilization numbers for JSON output
INDEXER_CPU=$(kubectl top pods -l name=search-indexer -n "$ACM_NAMESPACE" --no-headers 2>/dev/null | awk '{print $2}' | head -1 || echo "unknown")
INDEXER_MEMORY=$(kubectl top pods -l name=search-indexer -n "$ACM_NAMESPACE" --no-headers 2>/dev/null | awk '{print $3}' | head -1 || echo "unknown")
POSTGRES_CPU=$(kubectl top pods -l name=search-postgres -n "$ACM_NAMESPACE" --no-headers 2>/dev/null | awk '{print $2}' | head -1 || echo "unknown")
POSTGRES_MEMORY=$(kubectl top pods -l name=search-postgres -n "$ACM_NAMESPACE" --no-headers 2>/dev/null | awk '{print $3}' | head -1 || echo "unknown")

echo "Resource utilization summary:"
echo "  🔍 Indexer: CPU $INDEXER_CPU, Memory $INDEXER_MEMORY"
echo "  🗄️  PostgreSQL: CPU $POSTGRES_CPU, Memory $POSTGRES_MEMORY"

# Provide operational analysis
echo ""
echo "📊 Resource Analysis & Conclusions:"

# Analyze CPU usage
if [ "$INDEXER_CPU" != "unknown" ] && [ "$INDEXER_CPU" != "" ]; then
  CPU_NUM=$(echo "$INDEXER_CPU" | sed 's/m$//')
  if [ "$CPU_NUM" -lt 5 ]; then
    echo "  ✅ Indexer CPU usage ($INDEXER_CPU) is very low - system is not CPU constrained"
  elif [ "$CPU_NUM" -lt 100 ]; then
    echo "  ✅ Indexer CPU usage ($INDEXER_CPU) is normal - system operating efficiently"
  elif [ "$CPU_NUM" -lt 500 ]; then
    echo "  ⚠️  Indexer CPU usage ($INDEXER_CPU) is elevated - monitor for potential load issues"
  else
    echo "  🚨 Indexer CPU usage ($INDEXER_CPU) is high - consider scaling or optimization"
  fi
else
  echo "  ❓ Indexer CPU usage unknown - metrics collection may have issues"
fi

# Analyze memory usage
if [ "$INDEXER_MEMORY" != "unknown" ] && [ "$INDEXER_MEMORY" != "" ]; then
  MEMORY_NUM=$(echo "$INDEXER_MEMORY" | sed 's/Mi$//')
  if [ "$MEMORY_NUM" -lt 100 ]; then
    echo "  ✅ Indexer memory usage ($INDEXER_MEMORY) is low - plenty of headroom available"
  elif [ "$MEMORY_NUM" -lt 500 ]; then
    echo "  ✅ Indexer memory usage ($INDEXER_MEMORY) is normal for typical workloads"
  elif [ "$MEMORY_NUM" -lt 1000 ]; then
    echo "  ⚠️  Indexer memory usage ($INDEXER_MEMORY) is elevated - monitor for memory leaks"
  else
    echo "  🚨 Indexer memory usage ($INDEXER_MEMORY) is high - check for memory pressure"
  fi
else
  echo "  ❓ Indexer memory usage unknown - metrics collection may have issues"
fi

# Overall assessment
echo ""
echo "🎯 Operational Recommendations:"
if [ "$INDEXER_CPU" != "unknown" ] && [ "$POSTGRES_CPU" != "unknown" ]; then
  echo "  • Resource monitoring is working correctly"
  echo "  • Current load appears manageable based on CPU/memory patterns"
  echo "  • Continue monitoring for trends over time"
else
  echo "  • ⚠️  Resource metrics collection has gaps - investigate kubectl top functionality"
  echo "  • Consider alternative monitoring methods if metrics-server is unavailable"
fi

# Log detailed summary for JSON integration
echo "$(date '+%H:%M:%S') RESOURCE_SUMMARY: indexer_cpu=$INDEXER_CPU, indexer_memory=$INDEXER_MEMORY, postgres_cpu=$POSTGRES_CPU, postgres_memory=$POSTGRES_MEMORY" >> "${EXECUTION_LOG:-/dev/null}"
echo "$(date '+%H:%M:%S') RESOURCE_ANALYSIS_COMPLETE: Analysis provided operational conclusions based on current utilization patterns" >> "${EXECUTION_LOG:-/dev/null}"