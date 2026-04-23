#!/bin/bash
# Processing Performance Analysis for Search Indexer
# Weight: 20% of overall assessment
# Part of search-indexer-impact assessment methodology

set -euo pipefail

echo "=== Processing Performance Analysis via Prometheus ==="

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
  echo "[$timestamp] PERF_QUERY: $query" >> "${EXECUTION_LOG:-/dev/null}"

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
    print('[' + timestamp + '] PERF_PARSED_STATUS: ' + data.get('status', 'unknown'), file=sys.stderr)
    if data['status'] == 'success' and data['data']['result']:
        print('[' + timestamp + '] PERF_RESULT_COUNT: ' + str(len(data['data']['result'])), file=sys.stderr)
        for result in data['data']['result']:
            labels = result.get('metric', {})
            value = result['value'][1]
            print(f'{labels}: {value}')
    else:
        print('[' + timestamp + '] PERF_NO_DATA: Query returned no results', file=sys.stderr)
        print('No data returned for: ' + query)
except Exception as e:
    print('[' + timestamp + '] PERF_PARSE_ERROR: ' + str(e), file=sys.stderr)
    print('Query failed for: ' + query + ' - Error: ' + str(e))
" 2>> "${EXECUTION_LOG:-/dev/null}"

  echo "[$timestamp] PERF_QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
}

# Success rate analysis - try advanced first, fallback to basic
echo "Success Rate Analysis:"
echo "  Attempting rate-based success rate calculation:"
if prom_query "sum(rate(search_indexer_request_duration_count{code=\"200\"}[5m])) by (managed_cluster_name) / sum(rate(search_indexer_request_duration_count[5m])) by (managed_cluster_name) * 100" ; then
  echo "  ✅ Advanced success rate calculation successful"
else
  echo "  ⚠️  Rate-based calculation failed, using basic counters:"
  echo "  📊 Total successful requests (HTTP 200):"
  prom_query "search_indexer_request_duration_count{code=\"200\"}"
  echo "  📊 Total requests by response code:"
  prom_query "search_indexer_request_duration_count"
fi

# Processing efficiency analysis - try throughput first, fallback to totals
echo ""
echo "Processing Efficiency Analysis:"
echo "  Attempting current throughput calculation (req/sec):"
if prom_query "sum(rate(search_indexer_request_count[5m]))" | grep -q ":"; then
  echo "  ✅ Throughput calculation successful"
  echo "  Attempting peak throughput (last hour):"
  prom_query "max_over_time(sum(rate(search_indexer_request_count[5m]))[1h:])"
else
  echo "  ⚠️  Throughput calculation failed (insufficient time-series data)"
  echo "  📊 Fallback - Total requests processed:"
  prom_query "search_indexer_request_count"
  echo "  📊 Total processing time (seconds):"
  prom_query "search_indexer_request_duration_sum"
  echo "  📊 Average processing time per request:"
  prom_query "search_indexer_request_duration_sum / search_indexer_request_duration_count"
fi

# Duration trend analysis - try advanced first, fallback to basic
echo ""
echo "Request Duration Trend Analysis:"
echo "  Attempting current vs historical duration comparison:"
if prom_query "histogram_quantile(0.50, sum(rate(search_indexer_request_duration_bucket[5m])) by (le))" | grep -q ":"; then
  echo "  ✅ Current duration percentile successful"
  echo "  Attempting duration trend analysis:"
  prom_query "histogram_quantile(0.50, sum(rate(search_indexer_request_duration_bucket[5m])) by (le)) / histogram_quantile(0.50, sum(rate(search_indexer_request_duration_bucket[1h] offset 1h)) by (le))" || echo "  Historical comparison not available"
else
  echo "  ⚠️  Duration percentiles not available"
  echo "  📊 Current average duration:"
  prom_query "search_indexer_request_duration_sum / search_indexer_request_duration_count"
fi

# Error breakdown - try rate-based first, fallback to counters
echo ""
echo "Error Breakdown Analysis:"
echo "  Attempting rate-based error breakdown:"
if prom_query "sum(rate(search_indexer_request_duration_count{code!=\"200\"}[5m])) by (code)" | grep -q ":"; then
  echo "  ✅ Rate-based error breakdown successful"
else
  echo "  ⚠️  Rate-based breakdown failed"
  echo "  📊 Raw error counts (if any):"
  prom_query "search_indexer_request_duration_count{code!=\"200\"}" || echo "  No error responses detected"
fi

# Request size efficiency - try rate-based first, fallback to basic
echo ""
echo "Request Size Efficiency Analysis:"
echo "  Attempting rate-based size analysis:"
if prom_query "sum(rate(search_indexer_request_size_sum[5m])) / sum(rate(search_indexer_request_size_count[5m]))" | grep -q ":"; then
  echo "  ✅ Current average changes per request (rate-based)"
  echo "  Attempting large request percentage:"
  prom_query "(sum(rate(search_indexer_request_size_bucket{le=\"+Inf\"}[5m])) - sum(rate(search_indexer_request_size_bucket{le=\"25000\"}[5m]))) / sum(rate(search_indexer_request_size_count[5m])) * 100"
else
  echo "  ⚠️  Rate-based size analysis failed"
  echo "  📊 Total changes processed:"
  prom_query "search_indexer_request_size_sum"
  echo "  📊 Total requests:"
  prom_query "search_indexer_request_size_count"
  echo "  📊 Average changes per request:"
  prom_query "search_indexer_request_size_sum / search_indexer_request_size_count"
fi

# Capacity assessment (always available - gauge metrics)
echo ""
echo "Capacity Assessment:"
echo "  Current requests in flight:"
prom_query "search_indexer_requests_in_flight"
echo "  Capacity utilization percentage:"
prom_query "search_indexer_requests_in_flight / 25 * 100"