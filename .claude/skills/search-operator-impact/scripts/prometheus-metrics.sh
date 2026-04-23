#!/bin/bash
# Prometheus Operator Metrics Collection for Search Operator
# Weight: 40% of overall assessment
# Part of search-operator-impact assessment methodology

set -euo pipefail

echo "=== Prometheus Operator Metrics Collection ==="

# Discover Prometheus pod (following established pattern)
echo "=== Discovering Prometheus Pod ==="
PROM_POD=$(kubectl get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1)

if [ -z "$PROM_POD" ]; then
  echo "ERROR: Could not find Prometheus pod in openshift-monitoring"
  exit 1
fi

echo "Found Prometheus pod: $PROM_POD"

# Test Prometheus access and search for operator metrics
echo "Checking for search operator metrics..."
OPERATOR_METRICS=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/label/__name__/values" | grep -c "controller_runtime\|workqueue" || echo "0")

if [ "$OPERATOR_METRICS" -eq 0 ]; then
  echo "WARNING: No controller_runtime or workqueue metrics found in Prometheus"
  echo "Available operator-related metrics:"
  kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/label/__name__/values" | grep -E "(operator|controller|workqueue)" | head -5
  # Continue anyway for demonstration
fi

echo "=== Collecting Search Operator Metrics via Prometheus ==="

# Helper function for Prometheus queries with execution logging
operator_prom_query() {
  local query="$1"
  local timestamp=$(date '+%H:%M:%S')

  # Log the query attempt
  echo "[$timestamp] OPERATOR_QUERY: $query" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute the query and capture both output and raw response
  local raw_response=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query?query=$(echo "$query" | sed 's/ /%20/g')")
  local exit_code=$?

  # Log raw response for debugging
  echo "[$timestamp] RAW_RESPONSE: $raw_response" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"

  # Check if response is empty or invalid
  if [ -z "$raw_response" ] || [ "$raw_response" = "" ]; then
    echo "[$timestamp] OPERATOR_PARSE_ERROR: Empty response from Prometheus" >> "${EXECUTION_LOG:-/dev/null}"
    echo "Empty response for query: $query"
    echo "[$timestamp] OPERATOR_QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
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
        print('[' + timestamp + '] OPERATOR_PARSE_ERROR: Empty input received', file=sys.stderr)
        print('Empty response for: ' + query)
        sys.exit(1)

    data = json.loads(response_text)
    print('[' + timestamp + '] OPERATOR_PARSED_STATUS: ' + data.get('status', 'unknown'), file=sys.stderr)

    if data.get('status') == 'success' and data.get('data', {}).get('result'):
        results = data['data']['result']
        print('[' + timestamp + '] OPERATOR_RESULT_COUNT: ' + str(len(results)), file=sys.stderr)
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
        print('[' + timestamp + '] OPERATOR_NO_DATA: Query returned no results', file=sys.stderr)
        print('No data returned for: ' + query)
        sys.exit(1)
except json.JSONDecodeError as e:
    print('[' + timestamp + '] OPERATOR_PARSE_ERROR: Invalid JSON - ' + str(e), file=sys.stderr)
    print('Query failed for: ' + query + ' - Invalid JSON response')
    sys.exit(1)
except Exception as e:
    print('[' + timestamp + '] OPERATOR_PARSE_ERROR: ' + str(e), file=sys.stderr)
    print('Query failed for: ' + query + ' - Error: ' + str(e))
    sys.exit(1)
" 2>> "${EXECUTION_LOG:-/dev/null}"

  local python_exit=$?
  echo "[$timestamp] OPERATOR_QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
  return $python_exit
}

# Reconciliation performance metrics - try advanced first, fallback to basic
echo "Reconciliation Performance Analysis:"
echo "  Attempting success rate calculation (last 5 minutes):"
if operator_prom_query "sum(rate(controller_runtime_reconcile_total{controller=\"search\",result=\"success\"}[5m])) / sum(rate(controller_runtime_reconcile_total{controller=\"search\"}[5m])) * 100"; then
  echo "  ✅ Advanced reconciliation success rate successful"
else
  echo "  ⚠️  Advanced success rate failed (insufficient time-series data)"
  echo "  📊 Total successful reconciliations:"
  if ! operator_prom_query "sum(controller_runtime_reconcile_total{controller=\"search\",result=\"success\"})"; then
    echo "  ❌ No success reconciliation data available"
  fi
  echo "  📊 Total reconciliation attempts:"
  if ! operator_prom_query "sum(controller_runtime_reconcile_total{controller=\"search\"})"; then
    echo "  ❌ No reconciliation count data available"
  fi
fi

echo "  Attempting error rate calculation:"
if operator_prom_query "sum(rate(controller_runtime_reconcile_total{controller=\"search\",result=\"error\"}[5m])) / sum(rate(controller_runtime_reconcile_total{controller=\"search\"}[5m])) * 100"; then
  echo "  ✅ Advanced reconciliation error rate successful"
else
  echo "  ⚠️  Advanced error rate failed (insufficient time-series data)"
  echo "  📊 Total error reconciliations:"
  if ! operator_prom_query "sum(controller_runtime_reconcile_total{controller=\"search\",result=\"error\"})"; then
    echo "  ❌ No error reconciliation data available"
  fi
fi

# Reconciliation duration analysis - try percentiles first, fallback to averages
echo ""
echo "Reconciliation Duration Analysis:"
echo "  Attempting 95th percentile reconciliation time:"
if operator_prom_query "histogram_quantile(0.95, sum(rate(controller_runtime_reconcile_time_seconds_bucket{controller=\"search\"}[5m])) by (le))"; then
  echo "  ✅ Reconciliation duration percentiles successful"
  echo "  Attempting 50th percentile (median) reconciliation time:"
  operator_prom_query "histogram_quantile(0.50, sum(rate(controller_runtime_reconcile_time_seconds_bucket{controller=\"search\"}[5m])) by (le))"
else
  echo "  ⚠️  Reconciliation duration percentiles failed (insufficient time-series data)"
  echo "  📊 Average reconciliation duration (if available):"
  if ! operator_prom_query "controller_runtime_reconcile_time_seconds_sum{controller=\"search\"} / controller_runtime_reconcile_time_seconds_count{controller=\"search\"}"; then
    echo "  ❌ No reconciliation timing data available"
  fi
fi

# Work queue health analysis - try rate-based first, fallback to current values
echo ""
echo "Work Queue Health Analysis:"
echo "  Current queue depth:"
if ! operator_prom_query "workqueue_depth{name=\"search-controller\"}"; then
  if ! operator_prom_query "workqueue_depth{name=~\"search.*\"}"; then
    echo "  ❌ No work queue depth metrics available"
  fi
fi

echo "  Attempting queue additions rate (items/sec):"
if operator_prom_query "sum(rate(workqueue_adds_total{name=\"search-controller\"}[5m]))"; then
  echo "  ✅ Queue additions rate successful"
else
  echo "  ⚠️  Queue additions rate failed (insufficient time-series data)"
  echo "  📊 Total queue additions:"
  if ! operator_prom_query "sum(workqueue_adds_total{name=\"search-controller\"})"; then
    if ! operator_prom_query "sum(workqueue_adds_total{name=~\"search.*\"})"; then
      echo "  ❌ No queue additions data available"
    fi
  fi
fi

echo "  Attempting queue processing rate (items/sec):"
if operator_prom_query "sum(rate(workqueue_queue_duration_seconds_count{name=\"search-controller\"}[5m]))"; then
  echo "  ✅ Queue processing rate successful"
else
  echo "  ⚠️  Queue processing rate failed (insufficient time-series data)"
  echo "  📊 Total processed queue items:"
  if ! operator_prom_query "sum(workqueue_queue_duration_seconds_count{name=\"search-controller\"})"; then
    if ! operator_prom_query "sum(workqueue_queue_duration_seconds_count{name=~\"search.*\"})"; then
      echo "  ❌ No queue processing data available"
    fi
  fi
fi

# Additional operator metrics exploration
echo ""
echo "Additional Operator Metrics:"
echo "  Attempting requeue rate:"
if ! operator_prom_query "sum(rate(controller_runtime_reconcile_total{controller=\"search\",result=\"requeue\"}[5m]))"; then
  echo "  📊 Total requeue attempts:"
  if ! operator_prom_query "sum(controller_runtime_reconcile_total{controller=\"search\",result=\"requeue\"})"; then
    echo "  ❌ No requeue data available"
  fi
fi

echo ""
echo "Operator Prometheus metrics collection completed."
echo "For detailed query-by-query analysis, check execution log."