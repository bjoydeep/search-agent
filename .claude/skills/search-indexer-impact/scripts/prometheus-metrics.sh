#!/bin/bash
# Prometheus API Metrics Collection for Search Indexer
# Weight: 70% of overall assessment
# Part of search-indexer-impact assessment methodology

set -euo pipefail

# Function to capture metric value and write to JSON
capture_metric() {
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
      .raw_metrics.prometheus[$metric] = {
        "value": ($val | if . == "null" then null else tonumber end),
        "timestamp": $ts
      }
    ' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  fi

  return 0
}

echo "=== Prometheus API Metrics Collection ==="

# Discover Prometheus pod (corrected approach)
echo "=== Discovering Prometheus Pod ==="
PROM_POD=$(kubectl get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1)

if [ -z "$PROM_POD" ]; then
  echo "ERROR: Could not find Prometheus pod in openshift-monitoring"
  exit 1
fi

echo "Found Prometheus pod: $PROM_POD"

# Test Prometheus access and search for indexer metrics
echo "Checking for search indexer metrics..."
INDEXER_METRICS=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/label/__name__/values" | grep -c "search_indexer" || echo "0")

if [ "$INDEXER_METRICS" -eq 0 ]; then
  echo "WARNING: No search_indexer metrics found in Prometheus"
  echo "Available search metrics:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/label/__name__/values" | grep search | head -5
  # Continue anyway for demonstration
fi

echo "=== Collecting Indexer Metrics via Prometheus ==="

# Helper function for Prometheus queries with execution logging
prom_query() {
  local query="$1"
  local timestamp=$(date '+%H:%M:%S')

  # Log the query attempt
  echo "[$timestamp] QUERY: $query" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute the query and capture both output and raw response
  local raw_response=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$query")
  local exit_code=$?

  # Log raw response for debugging
  echo "[$timestamp] RAW_RESPONSE: $raw_response" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"

  # Check if response is empty or invalid
  if [ -z "$raw_response" ] || [ "$raw_response" = "" ]; then
    echo "[$timestamp] PARSE_ERROR: Empty response from Prometheus" >> "${EXECUTION_LOG:-/dev/null}"
    echo "Empty response for query: $query"
    echo "[$timestamp] QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
    echo "" >> "${EXECUTION_LOG:-/dev/null}"
    return 1
  fi

  # Parse and display results
  echo "$raw_response" | python3 -c "
import sys, json
timestamp = '${timestamp}'
query = '''${query}'''
try:
    response_text = sys.stdin.read().strip()
    if not response_text:
        print('[' + timestamp + '] PARSE_ERROR: Empty input received', file=sys.stderr)
        print('Empty response for: ' + query)
        sys.exit(1)

    data = json.loads(response_text)
    print('[' + timestamp + '] PARSED_STATUS: ' + data.get('status', 'unknown'), file=sys.stderr)

    if data.get('status') == 'success' and data.get('data', {}).get('result'):
        results = data['data']['result']
        print('[' + timestamp + '] RESULT_COUNT: ' + str(len(results)), file=sys.stderr)
        has_data = False
        for result in results:
            labels = result.get('metric', {})
            value = result['value'][1]
            if value and value != '0':
                has_data = True
            if labels:
                print(f'{labels}: {value}')
            else:
                print(f'{value}')
        if not has_data:
            print('No meaningful data (all zeros) for: ' + query)
        sys.exit(0 if has_data else 1)
    else:
        print('[' + timestamp + '] NO_DATA: Query returned no results', file=sys.stderr)
        print('No data returned for: ' + query)
        sys.exit(1)
except json.JSONDecodeError as e:
    print('[' + timestamp + '] PARSE_ERROR: Invalid JSON - ' + str(e), file=sys.stderr)
    print('Query failed for: ' + query + ' - Invalid JSON response')
    sys.exit(1)
except Exception as e:
    print('[' + timestamp + '] PARSE_ERROR: ' + str(e), file=sys.stderr)
    print('Query failed for: ' + query + ' - Error: ' + str(e))
    sys.exit(1)
" 2>> "${EXECUTION_LOG:-/dev/null}"

  local python_exit=$?
  echo "[$timestamp] QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
  return $python_exit
}

# Request count by managed cluster - try advanced first, fallback to basic
echo "Request Count by Cluster:"
echo "  Attempting aggregated request count by cluster:"
if prom_query "sum(search_indexer_request_count) by (managed_cluster_name)"; then
  echo "  ✅ Advanced aggregation successful"
  # Capture total requests for JSON
  capture_metric "total_requests" "sum(search_indexer_request_count)"
else
  echo "  ⚠️  Advanced query failed, using basic counter:"
  prom_query "search_indexer_request_count"
  # Capture basic request count for JSON
  capture_metric "total_requests" "search_indexer_request_count"
fi

# Request rate analysis - try rate() first, fallback to counters
echo ""
echo "Request Rate Analysis:"
echo "  Attempting rate calculation (req/sec, 5min average):"
if prom_query "sum(rate(search_indexer_request_count[5m])) by (managed_cluster_name)"; then
  echo "  ✅ Rate calculation successful"
else
  echo "  ⚠️  Rate query failed (likely insufficient time-series data)"
  echo "  📊 Fallback - Total requests since startup:"
  if ! prom_query "search_indexer_request_count"; then
    echo "  ❌ No indexer request metrics available"
  fi
fi

# Request duration analysis - try histogram percentiles first, fallback to average
echo ""
echo "Request Duration Analysis:"
echo "  Attempting 95th percentile calculation:"
if prom_query "histogram_quantile(0.95, sum(rate(search_indexer_request_duration_bucket[5m])) by (le))"; then
  echo "  ✅ Histogram percentile successful"
  echo "  Attempting 50th percentile (median):"
  prom_query "histogram_quantile(0.50, sum(rate(search_indexer_request_duration_bucket[5m])) by (le))"
else
  echo "  ⚠️  Histogram percentile failed (insufficient time-series data)"
  echo "  📊 Average request duration (seconds):"
  if ! prom_query "search_indexer_request_duration_sum / search_indexer_request_duration_count"; then
    echo "  ❌ No duration metrics available"
  fi
  echo "  📊 Total requests processed:"
  if ! prom_query "search_indexer_request_duration_count"; then
    echo "  ❌ No request count metrics available"
  fi
  echo "  📊 Total processing time:"
  if ! prom_query "search_indexer_request_duration_sum"; then
    echo "  ❌ No processing time metrics available"
  fi
fi

# Error rate analysis - try rate-based first, fallback to counters
echo ""
echo "Error Rate Analysis:"
echo "  Attempting rate-based error calculation:"
if prom_query "sum(rate(search_indexer_request_duration_count{code!=\"200\"}[5m])) by (code) / sum(rate(search_indexer_request_duration_count[5m])) * 100"; then
  echo "  ✅ Rate-based error calculation successful"
else
  echo "  ⚠️  Rate-based error calculation failed (insufficient time-series data)"
  echo "  📊 Fallback - Raw request counts by response code:"
  if ! prom_query "search_indexer_request_duration_count"; then
    echo "  ❌ No request duration metrics available"
  fi
fi

# Request size analysis - try rate-based first, fallback to totals
echo ""
echo "Request Size Analysis:"
echo "  Attempting rate-based request size calculation:"
if prom_query "sum(rate(search_indexer_request_size_sum[5m])) / sum(rate(search_indexer_request_size_count[5m]))"; then
  echo "  ✅ Rate-based size calculation successful"
  echo "  Attempting large request rate calculation:"
  prom_query "sum(rate(search_indexer_request_size_bucket{le=\"+Inf\"}[5m])) - sum(rate(search_indexer_request_size_bucket{le=\"25000\"}[5m]))"
else
  echo "  ⚠️  Rate-based size calculation failed (insufficient time-series data)"
  echo "  📊 Fallback - Total changes processed:"
  if ! prom_query "search_indexer_request_size_sum"; then
    echo "  ❌ No request size sum metrics available"
  fi
  echo "  📊 Total requests (size count):"
  if ! prom_query "search_indexer_request_size_count"; then
    echo "  ❌ No request size count metrics available"
  fi
  echo "  📊 Average changes per request:"
  if ! prom_query "search_indexer_request_size_sum / search_indexer_request_size_count"; then
    echo "  ❌ Cannot calculate average - missing size metrics"
  fi
fi

# Current capacity utilization (always works - gauge metric)
echo ""
echo "Capacity Utilization:"
echo "  Current requests in flight:"
prom_query "search_indexer_requests_in_flight"
# Capture requests in flight for JSON
capture_metric "requests_in_flight" "search_indexer_requests_in_flight"

echo "  Capacity utilization percentage:"
prom_query "search_indexer_requests_in_flight / 25 * 100"
# Capture capacity utilization for JSON
capture_metric "capacity_utilization_percent" "search_indexer_requests_in_flight / 25 * 100"

# Capture additional key metrics for JSON structure
echo ""
echo "📊 Capturing structured metrics for assessment..."

# Capture duration percentiles
capture_metric "request_duration_p95" "histogram_quantile(0.95, sum(rate(search_indexer_request_duration_bucket[5m])) by (le))"
capture_metric "request_duration_p50" "histogram_quantile(0.50, sum(rate(search_indexer_request_duration_bucket[5m])) by (le))"

# Capture success rate
capture_metric "success_rate_percent" "sum(rate(search_indexer_request_duration_count{code=\"200\"}[5m])) / sum(rate(search_indexer_request_duration_count[5m])) * 100"

echo "✅ Prometheus metrics captured to JSON structure"