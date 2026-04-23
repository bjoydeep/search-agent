#!/bin/bash
# Historical Trend Analysis for Search Indexer
# Detects performance degradation over 1hr and 24hr windows
# Weight: 20% of overall assessment (replaces commented-out trend analysis)

set -euo pipefail

echo "=== Historical Trend Analysis ==="
echo "Analyzing performance trends over multiple time windows..."

# Get ACM namespace and execution log from environment
ACM_NAMESPACE="${ACM_NAMESPACE:-open-cluster-management}"
EXECUTION_LOG="${EXECUTION_LOG:-/dev/null}"

# Discover Prometheus pod
echo "=== Discovering Prometheus Pod ==="
PROM_POD=$(kubectl get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus -o name | head -1)

if [ -z "$PROM_POD" ]; then
  echo "ERROR: Could not find Prometheus pod in openshift-monitoring"
  exit 1
fi

echo "Found Prometheus pod: $PROM_POD"

# Helper function for Prometheus trend queries with execution logging
trend_query() {
  local query="$1"
  local description="$2"
  local timestamp=$(date '+%H:%M:%S')

  # Log the query attempt
  echo "[$timestamp] TREND_QUERY: $description" >> "${EXECUTION_LOG}"
  echo "[$timestamp] QUERY: $query" >> "${EXECUTION_LOG}"

  # Execute the query and capture both output and raw response
  local raw_response=$(kubectl exec -n openshift-monitoring $PROM_POD -- curl -s "http://localhost:9090/api/v1/query" --data-urlencode "query=$query")
  local exit_code=$?

  # Log raw response for debugging
  echo "[$timestamp] RAW_RESPONSE: $raw_response" >> "${EXECUTION_LOG}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG}"

  # Check if response is empty or invalid
  if [ -z "$raw_response" ] || [ "$raw_response" = "" ]; then
    echo "[$timestamp] TREND_PARSE_ERROR: Empty response from Prometheus" >> "${EXECUTION_LOG}"
    echo "  ❌ No data available for: $description"
    echo "[$timestamp] TREND_QUERY_COMPLETE" >> "${EXECUTION_LOG}"
    echo "" >> "${EXECUTION_LOG}"
    return 1
  fi

  # Parse and display results with trend interpretation
  echo "$raw_response" | python3 -c "
import sys, json
timestamp = '${timestamp}'
query = '''${query}'''
description = '''${description}'''
try:
    response_text = sys.stdin.read().strip()
    if not response_text:
        print('[' + timestamp + '] TREND_PARSE_ERROR: Empty input received', file=sys.stderr)
        print('  ❌ Empty response for: ' + description)
        sys.exit(1)

    data = json.loads(response_text)
    print('[' + timestamp + '] TREND_PARSED_STATUS: ' + data.get('status', 'unknown'), file=sys.stderr)

    if data.get('status') == 'success' and data.get('data', {}).get('result'):
        results = data['data']['result']
        print('[' + timestamp + '] TREND_RESULT_COUNT: ' + str(len(results)), file=sys.stderr)

        for result in results:
            labels = result.get('metric', {})
            value = result['value'][1]

            # Interpret trend values based on query type
            try:
                trend_value = float(value)

                if 'predict_linear' in query or 'deriv' in query:
                    # Trend analysis - positive means increasing
                    if abs(trend_value) < 0.001:
                        trend_status = '🟢 STABLE'
                        trend_desc = 'minimal change'
                    elif trend_value > 0:
                        if trend_value > 0.1:
                            trend_status = '🔴 DEGRADING'
                            trend_desc = f'increasing significantly (+{trend_value:.3f})'
                        else:
                            trend_status = '🟡 WATCH'
                            trend_desc = f'slowly increasing (+{trend_value:.3f})'
                    else:
                        trend_status = '🟢 IMPROVING'
                        trend_desc = f'decreasing ({trend_value:.3f})'
                    print(f'  {trend_status}: {description} - {trend_desc}')

                elif 'max_over_time' in query and 'min_over_time' in query:
                    # Memory range analysis (bytes to MB)
                    range_mb = trend_value / 1024 / 1024
                    if range_mb < 5:
                        trend_status = '🟢 STABLE'
                        trend_desc = f'very low variation ({range_mb:.1f}MB range)'
                    elif range_mb < 20:
                        trend_status = '🟡 MODERATE'
                        trend_desc = f'moderate variation ({range_mb:.1f}MB range)'
                    else:
                        trend_status = '🔴 VOLATILE'
                        trend_desc = f'high variation ({range_mb:.1f}MB range)'
                    print(f'  {trend_status}: {description} - {trend_desc}')

                elif 'stddev_over_time' in query:
                    # Standard deviation analysis (bytes to MB)
                    stddev_mb = trend_value / 1024 / 1024
                    if stddev_mb < 2:
                        trend_status = '🟢 STABLE'
                        trend_desc = f'very stable ({stddev_mb:.1f}MB stddev)'
                    elif stddev_mb < 10:
                        trend_status = '🟡 MODERATE'
                        trend_desc = f'moderate stability ({stddev_mb:.1f}MB stddev)'
                    else:
                        trend_status = '🔴 UNSTABLE'
                        trend_desc = f'unstable usage ({stddev_mb:.1f}MB stddev)'
                    print(f'  {trend_status}: {description} - {trend_desc}')

                elif 'increase' in query:
                    # Counter increase analysis (for restart counts, etc.)
                    if trend_value == 0:
                        print(f'  🟢 STABLE: {description} - no increase ({trend_value})')
                    elif trend_value < 5:
                        print(f'  🟡 MINOR: {description} - small increase ({trend_value})')
                    else:
                        print(f'  🔴 SIGNIFICANT: {description} - notable increase ({trend_value})')

                elif 'avg_over_time' in query and 'up{' in query:
                    # Uptime analysis (0-1 scale)
                    uptime_pct = trend_value * 100
                    if uptime_pct >= 99.9:
                        print(f'  🟢 EXCELLENT: {description} - {uptime_pct:.2f}% uptime')
                    elif uptime_pct >= 99:
                        print(f'  🟡 GOOD: {description} - {uptime_pct:.2f}% uptime')
                    else:
                        print(f'  🔴 POOR: {description} - {uptime_pct:.2f}% uptime')

                else:
                    # Regular value
                    print(f'  📈 DATA: {description} - current value: {value}')

            except ValueError:
                print(f'  📊 INFO: {description} - value: {value}')

        sys.exit(0)
    else:
        print('[' + timestamp + '] TREND_NO_DATA: Query returned no results', file=sys.stderr)
        print(f'  ⚠️  No historical data: {description}')
        sys.exit(1)
except json.JSONDecodeError as e:
    print('[' + timestamp + '] TREND_PARSE_ERROR: Invalid JSON - ' + str(e), file=sys.stderr)
    print(f'  ❌ Query failed: {description} - Invalid JSON response')
    sys.exit(1)
except Exception as e:
    print('[' + timestamp + '] TREND_PARSE_ERROR: ' + str(e), file=sys.stderr)
    print(f'  ❌ Query failed: {description} - Error: {str(e)}')
    sys.exit(1)
" 2>> "${EXECUTION_LOG}"

  local python_exit=$?
  echo "[$timestamp] TREND_QUERY_COMPLETE" >> "${EXECUTION_LOG}"
  echo "" >> "${EXECUTION_LOG}"
  return $python_exit
}

echo ""
echo "=== Memory Trend Analysis ==="
echo "Analyzing memory usage patterns over time..."

# Memory trend over 24 hours - detect potential leaks
echo "24-hour Memory Trend:"
trend_query "predict_linear(avg_over_time(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}[5m])[24h:], 3600*24)" "Memory growth prediction over 24h"

# Memory slope over 1 hour - recent changes
echo ""
echo "1-hour Memory Trend:"
trend_query "deriv(avg_over_time(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}[5m])[1h:])" "Memory change rate over 1h"

# Memory range and stability analysis (proper gauge analysis)
echo ""
echo "Memory Range Analysis:"
trend_query "max_over_time(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}[1h]) - min_over_time(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}[1h])" "Memory range variation in last 1h"
trend_query "max_over_time(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}[24h]) - min_over_time(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}[24h])" "Memory range variation in last 24h"

echo ""
echo "Memory Stability Analysis:"
trend_query "stddev_over_time(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}[1h])" "Memory stability (stddev) over 1h"
trend_query "stddev_over_time(container_memory_working_set_bytes{pod=~\"search-indexer.*\", container=\"search-indexer\"}[24h])" "Memory stability (stddev) over 24h"

echo ""
echo "=== CPU Trend Analysis ==="
echo "Analyzing CPU utilization patterns over time..."

# CPU trend over 24 hours
echo "24-hour CPU Trend:"
trend_query "predict_linear(rate(container_cpu_usage_seconds_total{pod=~\"search-indexer.*\", container=\"search-indexer\"}[5m])[24h:], 3600*24)" "CPU utilization trend over 24h"

# CPU slope over 1 hour
echo ""
echo "1-hour CPU Trend:"
trend_query "deriv(rate(container_cpu_usage_seconds_total{pod=~\"search-indexer.*\", container=\"search-indexer\"}[5m])[1h:])" "CPU utilization change rate over 1h"

echo ""
echo "=== Request Performance Trend Analysis ==="
echo "Analyzing request latency and throughput patterns..."

# Request duration trend over 24 hours - detect performance degradation
echo "24-hour Latency Trend:"
trend_query "predict_linear(histogram_quantile(0.95, rate(search_indexer_request_duration_bucket[5m]))[24h:], 3600*24)" "95th percentile latency trend over 24h"
trend_query "predict_linear(histogram_quantile(0.50, rate(search_indexer_request_duration_bucket[5m]))[24h:], 3600*24)" "Median latency trend over 24h"

# Request duration change over 1 hour
echo ""
echo "1-hour Latency Trend:"
trend_query "deriv(histogram_quantile(0.95, rate(search_indexer_request_duration_bucket[5m]))[1h:])" "95th percentile latency change rate over 1h"

# Request throughput trends
echo ""
echo "Request Throughput Trends:"
trend_query "predict_linear(rate(search_indexer_request_count[5m])[24h:], 3600*24)" "Request rate trend over 24h"
trend_query "deriv(rate(search_indexer_request_count[5m])[1h:])" "Request rate change over 1h"

echo ""
echo "=== Error Rate Trend Analysis ==="
echo "Analyzing error patterns and reliability trends..."

# Error rate trends (only if we have errors)
echo "Error Rate Trends:"
if trend_query "rate(search_indexer_request_duration_count{code!=\"200\"}[5m])" "Current error rate"; then
  trend_query "predict_linear(rate(search_indexer_request_duration_count{code!=\"200\"}[5m])[24h:], 3600*24)" "Error rate trend over 24h"
  trend_query "deriv(rate(search_indexer_request_duration_count{code!=\"200\"}[5m])[1h:])" "Error rate change over 1h"
else
  echo "  🟢 EXCELLENT: No errors detected - cannot trend zero error rate"
fi

echo ""
echo "=== Stability Trend Analysis ==="
echo "Analyzing pod restart patterns and stability..."

# Pod restart analysis
echo "Pod Restart Analysis:"
trend_query "increase(kube_pod_container_status_restarts_total{pod=~\"search-indexer.*\", container=\"search-indexer\"}[1h])" "Restarts in last 1h"
trend_query "increase(kube_pod_container_status_restarts_total{pod=~\"search-indexer.*\", container=\"search-indexer\"}[24h])" "Restarts in last 24h"

# Pod readiness and availability trends
echo ""
echo "Availability Analysis:"
trend_query "avg_over_time(up{job=\"search-indexer\"}[1h])" "Average uptime over 1h"
trend_query "avg_over_time(up{job=\"search-indexer\"}[24h])" "Average uptime over 24h"

echo ""
echo "=== Database Performance Trend Analysis ==="
echo "Analyzing PostgreSQL performance patterns..."

# Database connection trends (if metrics available)
echo "Database Connection Trends:"
trend_query "predict_linear(pg_stat_database_numbackends{datname=\"search\"}[24h:], 3600*24)" "Database connection count trend over 24h" || echo "  ⚠️  Database metrics may not be available via Prometheus"

echo ""
echo "=== Historical Trend Analysis Summary ==="
echo "Analysis complete using proper gauge metric analysis. Key patterns:"
echo "  🟢 STABLE trends indicate healthy, predictable system performance"
echo "  🟡 MODERATE/WATCH trends suggest monitoring required"
echo "  🔴 VOLATILE/DEGRADING trends indicate performance issues requiring attention"
echo ""
echo "Historical analysis provides insights for:"
echo "  • Memory stability (range and standard deviation analysis)"
echo "  • Performance trends (latency and throughput changes over time)"
echo "  • Resource utilization patterns (CPU, memory trending)"
echo "  • System reliability (restart patterns and uptime trends)"
echo ""
echo "Use this data to:"
echo "  • Establish performance baselines and acceptable ranges"
echo "  • Detect gradual system degradation before it impacts users"
echo "  • Plan capacity and scaling decisions based on trends"
echo "  • Validate optimization efforts with before/after trending"
echo "  • Identify normal operational variations vs. concerning patterns"

# Return success - trend analysis is informational
exit 0