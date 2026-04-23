#!/bin/bash
# Prometheus API Metrics Collection for Search API
# Weight: 60% of overall assessment
# Part of search-api-impact assessment methodology

set -euo pipefail

echo "=== Prometheus API Metrics Collection ==="

# Discover Prometheus pod (corrected approach)
echo "=== Discovering Prometheus Pod ==="
PROM_POD=$(kubectl get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1)

if [ -z "$PROM_POD" ]; then
  echo "ERROR: Could not find Prometheus pod in openshift-monitoring"
  exit 1
fi

echo "Found Prometheus pod: $PROM_POD"

# Test Prometheus access and search for API metrics
echo "Checking for search API metrics..."
API_METRICS=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/label/__name__/values" | grep -c "search_api" || echo "0")

if [ "$API_METRICS" -eq 0 ]; then
  echo "WARNING: No search_api metrics found in Prometheus"
  echo "Available search metrics:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/label/__name__/values" | grep search | head -5
  # Continue anyway for demonstration
fi

echo "=== Collecting Search API Metrics via Prometheus ==="

# Helper function for Prometheus queries with execution logging
api_prom_query() {
  local query="$1"
  local timestamp=$(date '+%H:%M:%S')

  # Log the query attempt
  echo "[$timestamp] API_QUERY: $query" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute the query and capture both output and raw response
  local raw_response=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=$(echo "$query" | sed 's/ /%20/g')")
  local exit_code=$?

  # Log raw response for debugging
  echo "[$timestamp] RAW_RESPONSE: $raw_response" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"

  # Check if response is empty or invalid
  if [ -z "$raw_response" ] || [ "$raw_response" = "" ]; then
    echo "[$timestamp] API_PARSE_ERROR: Empty response from Prometheus" >> "${EXECUTION_LOG:-/dev/null}"
    echo "Empty response for query: $query"
    echo "[$timestamp] API_QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
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
        print('[' + timestamp + '] API_PARSE_ERROR: Empty input received', file=sys.stderr)
        print('Empty response for: ' + query)
        sys.exit(1)

    data = json.loads(response_text)
    print('[' + timestamp + '] API_PARSED_STATUS: ' + data.get('status', 'unknown'), file=sys.stderr)

    if data.get('status') == 'success' and data.get('data', {}).get('result'):
        results = data['data']['result']
        print('[' + timestamp + '] API_RESULT_COUNT: ' + str(len(results)), file=sys.stderr)
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
        print('[' + timestamp + '] API_NO_DATA: Query returned no results', file=sys.stderr)
        print('No data returned for: ' + query)
        sys.exit(1)
except json.JSONDecodeError as e:
    print('[' + timestamp + '] API_PARSE_ERROR: Invalid JSON - ' + str(e), file=sys.stderr)
    print('Query failed for: ' + query + ' - Invalid JSON response')
    sys.exit(1)
except Exception as e:
    print('[' + timestamp + '] API_PARSE_ERROR: ' + str(e), file=sys.stderr)
    print('Query failed for: ' + query + ' - Error: ' + str(e))
    sys.exit(1)
" 2>> "${EXECUTION_LOG:-/dev/null}"

  local python_exit=$?
  echo "[$timestamp] API_QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
  return $python_exit
}

# API request duration percentiles - try advanced first, fallback to basic
echo "API Request Duration Analysis:"
echo "  Attempting 95th percentile calculation:"
if api_prom_query "histogram_quantile(0.95, sum(rate(search_api_request_duration_bucket[5m])) by (le))"; then
  echo "  ✅ Advanced percentile calculation successful"
  echo "  Attempting 50th percentile (median):"
  api_prom_query "histogram_quantile(0.50, sum(rate(search_api_request_duration_bucket[5m])) by (le))"
else
  echo "  ⚠️  Advanced percentile failed, using basic calculation:"
  echo "  📊 Average request duration (seconds):"
  if ! api_prom_query "search_api_request_duration_sum / search_api_request_duration_count"; then
    echo "  ❌ No request duration data available (API likely inactive)"
  fi
  echo "  📊 Total requests processed:"
  if ! api_prom_query "search_api_request_duration_count"; then
    echo "  ❌ No request count data available"
  fi
  echo "  📊 Total processing time:"
  if ! api_prom_query "search_api_request_duration_sum"; then
    echo "  ❌ No processing time data available"
  fi
fi

# Database connection health - try rate-based first, fallback to totals
echo ""
echo "Database Connection Health:"
echo "  Attempting connection failure rate calculation:"
if api_prom_query "sum(rate(search_api_db_connection_failed[5m]))"; then
  echo "  ✅ Rate-based connection failure analysis successful"
else
  echo "  ⚠️  Rate-based analysis failed (insufficient time-series data)"
  echo "  📊 Total connection failures:"
  if ! api_prom_query "sum(search_api_db_connection_failed)"; then
    echo "  ❌ No connection failure metrics available"
  fi
fi

# Database query performance - try percentiles first, fallback to averages
echo ""
echo "Database Query Performance:"
echo "  Attempting query duration 95th percentile:"
if api_prom_query "histogram_quantile(0.95, sum(rate(search_api_db_query_duration_bucket[5m])) by (le))"; then
  echo "  ✅ Database query percentile successful"
  echo "  Attempting query rate (queries/sec):"
  api_prom_query "sum(rate(search_api_db_query_duration_count[5m]))"
else
  echo "  ⚠️  Database query percentiles failed (insufficient time-series data)"
  echo "  📊 Average query duration:"
  if ! api_prom_query "search_api_db_query_duration_sum / search_api_db_query_duration_count"; then
    echo "  ❌ No database query timing data available"
  fi
  echo "  📊 Total database queries:"
  if ! api_prom_query "search_api_db_query_duration_count"; then
    echo "  ❌ No database query count data available"
  fi
fi

# WebSocket real-time metrics (gauge metrics should always be available)
echo ""
echo "WebSocket Real-time Metrics:"
echo "  Current active subscriptions:"
if ! api_prom_query "sum(search_api_subscriptions_active)"; then
  echo "  ❌ Subscription metrics not available"
fi
echo "  Total WebSocket connections attempted:"
if ! api_prom_query "sum(search_api_websocket_connections_total)"; then
  echo "  ❌ WebSocket connection metrics not available"
fi
echo "  WebSocket connection failure rate:"
if ! api_prom_query "sum(rate(search_api_websocket_connections_failed[5m]))"; then
  echo "  📊 WebSocket failure rate (fallback to totals):"
  if ! api_prom_query "sum(search_api_websocket_connections_failed)"; then
    echo "  ❌ No WebSocket failure data available"
  fi
fi

# Error analysis - try rate-based first, fallback to totals
echo ""
echo "Error Analysis:"
echo "  Attempting overall error rate calculation:"
if api_prom_query "(sum(rate(search_api_request_duration_count{code!=\"200\"}[5m])) / sum(rate(search_api_request_duration_count[5m]))) * 100"; then
  echo "  ✅ Rate-based error analysis successful"
  echo "  Attempting error breakdown by response code:"
  api_prom_query "sum(rate(search_api_request_duration_count{code!=\"200\"}[5m])) by (code)"
else
  echo "  ⚠️  Rate-based error analysis failed (insufficient time-series data)"
  echo "  📊 Total error requests by response code:"
  if ! api_prom_query "sum(search_api_request_duration_count{code!=\"200\"}) by (code)"; then
    echo "  ❌ No error request data available"
  fi
  echo "  📊 Total successful requests:"
  if ! api_prom_query "sum(search_api_request_duration_count{code=\"200\"})"; then
    echo "  ❌ No successful request data available"
  fi
fi

# Request rate analysis - try rate calculation first, fallback to totals
echo ""
echo "Request Rate Analysis:"
echo "  Attempting current request rate (req/sec):"
if api_prom_query "sum(rate(search_api_request_duration_count[5m]))"; then
  echo "  ✅ Request rate calculation successful"
else
  echo "  ⚠️  Request rate calculation failed (insufficient time-series data)"
  echo "  📊 Total API requests processed:"
  if ! api_prom_query "sum(search_api_request_duration_count)"; then
    echo "  ❌ No request count data available (API metrics likely not configured)"
  fi
fi