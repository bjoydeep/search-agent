#!/bin/bash
# Capacity Utilization and Health Analysis for Search Indexer
# Weight: 10% of overall assessment
# Part of search-indexer-impact assessment methodology

set -euo pipefail

# Function to capture capacity metric value and write to JSON
capture_capacity_metric() {
  local metric_name="$1"
  local query="$2"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Execute the query and capture the numeric result
  local raw_response=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$query")

  # Extract the first numeric value from the response
  local value=$(echo "$raw_response" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    if data.get('status') == 'success' and data.get('data', {}).get('result'):
        results = data['data']['result']
        if results and len(results) > 0:
            value = results[0].get('value', [None, None])
            if len(value) > 1 and value[1] is not None:
                print(value[1])
            else:
                print('null')
        else:
            print('null')
    else:
        print('null')
except:
    print('null')
" 2>/dev/null)

  # Update JSON with the captured value
  if [ -n "${OUTPUT_FILE:-}" ]; then
    jq --arg metric "$metric_name" --arg val "$value" --arg ts "$timestamp" '
      .raw_metrics.capacity[$metric] = {
        "value": ($val | if . == "null" then null else tonumber end),
        "timestamp": $ts
      }
    ' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  fi

  return 0
}

echo "=== Capacity Utilization and Health Analysis ==="

# Use ACM namespace from environment (set by generate-assessment.sh) or discover it
ACM_NAMESPACE=${ACM_NAMESPACE:-$(kubectl get multiclusterhub -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace 2>/dev/null | head -1 || echo "open-cluster-management")}

# Use corrected Prometheus access method
PROM_POD=$(kubectl get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1)
if [ -z "$PROM_POD" ]; then
  echo "ERROR: Could not find Prometheus pod"
  exit 1
fi

# Helper function for Prometheus queries with execution logging
prom_query() {
  local query="$1"
  local timestamp=$(date '+%H:%M:%S')

  # Log the query attempt
  echo "[$timestamp] CAPACITY_QUERY: $query" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute the query and capture both output and raw response
  local raw_response=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$query")
  local exit_code=$?

  # Log raw response for debugging
  echo "[$timestamp] RAW_RESPONSE: $raw_response" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"

  # Parse and display results
  echo "$raw_response" | python3 -c "
import sys, json
timestamp = '${timestamp}'
query = '''${query}'''
try:
    data = json.load(sys.stdin)
    print('[' + timestamp + '] CAPACITY_PARSED_STATUS: ' + data.get('status', 'unknown'), file=sys.stderr)
    if data['status'] == 'success' and data['data']['result']:
        print('[' + timestamp + '] CAPACITY_RESULT_COUNT: ' + str(len(data['data']['result'])), file=sys.stderr)
        for result in data['data']['result']:
            labels = result.get('metric', {})
            value = result['value'][1]
            print(f'{labels}: {value}')
    else:
        print('[' + timestamp + '] CAPACITY_NO_DATA: Query returned no results', file=sys.stderr)
        print('No data returned for: ' + query)
except Exception as e:
    print('[' + timestamp + '] CAPACITY_PARSE_ERROR: ' + str(e), file=sys.stderr)
    print('Query failed for: ' + query + ' - Error: ' + str(e))
" 2>> "${EXECUTION_LOG:-/dev/null}"

  echo "[$timestamp] CAPACITY_QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
}

# Request capacity utilization (from Prometheus)
echo "Request Processing Capacity:"
echo "  Current in-flight requests:"
prom_query "sum(search_indexer_requests_in_flight)"
echo "  Capacity utilization (%, based on 25 concurrent request limit):"
prom_query "sum(search_indexer_requests_in_flight) / 25 * 100"
echo "  Request queue health (avg in-flight over last hour):"
prom_query "avg_over_time(sum(search_indexer_requests_in_flight)[1h:])"

# Indexer pod health via Kubernetes metrics (if available through Prometheus)
echo "Pod Resource Utilization:"
echo "  CPU usage (millicores, if available):"
prom_query "sum(rate(container_cpu_usage_seconds_total{pod=~\"search-indexer.*\", container=\"search-indexer\"}[5m])) * 1000" || echo "CPU metrics not available"
echo "  Memory usage (MB, if available):"
prom_query "sum(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}) / 1024 / 1024" || echo "Memory metrics not available"

# Health status via pod readiness (if available through kube-state-metrics)
echo "Pod Health Status:"
echo "  Ready replicas:"
prom_query "kube_deployment_status_ready_replicas{deployment=\"search-indexer\", namespace=\"$ACM_NAMESPACE\"}" || echo "Deployment metrics not available"
echo "  Total replicas:"
prom_query "kube_deployment_spec_replicas{deployment=\"search-indexer\", namespace=\"$ACM_NAMESPACE\"}" || echo "Deployment metrics not available"

# Error rate trends (5min vs 1h)
echo "Health Trends:"
echo "  Error rate trend (current 5min vs 1h ago):"
prom_query "(sum(rate(search_indexer_request_duration_count{code!=\"200\"}[5m])) / sum(rate(search_indexer_request_duration_count[5m]))) / (sum(rate(search_indexer_request_duration_count{code!=\"200\"}[5m] offset 1h)) / sum(rate(search_indexer_request_duration_count[5m] offset 1h)))"

# Helper function for kubectl health checks with execution logging
kubectl_check() {
  local operation="$1"
  local description="$2"
  local timestamp=$(date '+%H:%M:%S')

  # Log the operation attempt
  echo "[$timestamp] KUBECTL_CHECK: $description" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] OPERATION: $operation" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute the kubectl operation and capture output
  local raw_output=$(eval "$operation" 2>&1)
  local exit_code=$?

  # Log raw response for debugging
  echo "[$timestamp] KUBECTL_OUTPUT: $raw_output" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results
  if [ $exit_code -eq 0 ]; then
    echo "[$timestamp] KUBECTL_STATUS: success" >> "${EXECUTION_LOG:-/dev/null}"
    echo "$raw_output"
  else
    echo "[$timestamp] KUBECTL_ERROR: Command failed with exit code $exit_code" >> "${EXECUTION_LOG:-/dev/null}"
    echo "ERROR: $description failed"
    echo "$raw_output"
  fi

  echo "[$timestamp] KUBECTL_CHECK_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
}

# Fallback: Direct health checks if Prometheus doesn't have pod metrics
echo "Fallback Health Checks (if Prometheus pod metrics unavailable):"
echo "$(date '+%H:%M:%S') POD_HEALTH_CHECK: Starting direct pod health verification" >> "${EXECUTION_LOG:-/dev/null}"

INDEXER_PODS=$(kubectl get pods -l name=search-indexer -A --no-headers -o custom-columns=:metadata.namespace,:metadata.name 2>/dev/null | head -3)
if [ ! -z "$INDEXER_PODS" ]; then
  echo "$INDEXER_PODS" | while read ns pod; do
    if [ ! -z "$ns" ] && [ ! -z "$pod" ]; then
      kubectl_check "kubectl get pod -n $ns $pod -o jsonpath='{.status.phase}'" "Pod health check for $ns/$pod"
    fi
  done
else
  echo "$(date '+%H:%M:%S') POD_HEALTH_WARNING: No indexer pods found for direct health check" >> "${EXECUTION_LOG:-/dev/null}"
  echo "  No indexer pods found for direct health check"
fi

# Capture key capacity metrics for JSON structure
echo ""
echo "📊 Capturing capacity metrics for assessment..."

# Capture capacity utilization data
capture_capacity_metric "current_requests_in_flight" "sum(search_indexer_requests_in_flight)"
capture_capacity_metric "capacity_utilization_percent" "sum(search_indexer_requests_in_flight) / 25 * 100"
capture_capacity_metric "avg_requests_in_flight_1h" "avg_over_time(sum(search_indexer_requests_in_flight)[1h:])"

# Capture resource utilization data
capture_capacity_metric "cpu_usage_millicores" "sum(rate(container_cpu_usage_seconds_total{pod=~\"search-indexer.*\", container=\"search-indexer\"}[5m])) * 1000"
capture_capacity_metric "memory_usage_mb" "sum(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}) / 1024 / 1024"
capture_capacity_metric "deployment_replicas" "kube_deployment_spec_replicas{deployment=\"search-indexer\", namespace=\"open-cluster-management\"}"

echo "✅ Capacity metrics captured to JSON structure"