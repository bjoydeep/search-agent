#!/bin/bash
# User Pattern Analysis for Search API
# Weight: 25% of overall assessment
# Part of search-api-impact assessment methodology

set -euo pipefail

echo "=== Performance Analysis by User Patterns ==="

# Helper function for API pod operations with execution logging
api_pod_operation() {
  local operation="$1"
  local pod_name="$2"
  local namespace="$3"
  local description="$4"
  local timestamp=$(date '+%H:%M:%S')

  # Log the operation attempt
  echo "[$timestamp] API_POD_OPERATION: $description" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] POD: $namespace/$pod_name" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] OPERATION: $operation" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute the operation and capture output
  local raw_output=$(eval "$operation" 2>&1)
  local exit_code=$?

  # Log raw response for debugging
  echo "[$timestamp] OPERATION_OUTPUT_LINES: $(echo "$raw_output" | wc -l)" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results
  if [ $exit_code -eq 0 ]; then
    echo "[$timestamp] OPERATION_STATUS: success" >> "${EXECUTION_LOG:-/dev/null}"
    echo "$raw_output"
  else
    echo "[$timestamp] OPERATION_ERROR: Operation failed with exit code $exit_code" >> "${EXECUTION_LOG:-/dev/null}"
    echo "ERROR: $description failed for $namespace/$pod"
    echo "$raw_output"
  fi

  echo "[$timestamp] API_POD_OPERATION_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
}

# Helper function for user pattern analysis with comprehensive logging
user_pattern_analysis() {
  local metrics_data="$1"
  local pod_name="$2"
  local namespace="$3"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] USER_PATTERN_ANALYSIS: Starting pattern analysis for $namespace/$pod" >> "${EXECUTION_LOG:-/dev/null}"

  # Analyze user patterns with detailed logging
  local analysis_output=$(echo "$metrics_data" | python3 -c "
import sys
import re
from collections import defaultdict

# Enhanced pattern matching for API-specific user behavior
request_data = {}
client_patterns = defaultdict(lambda: {'total': 0, 'errors': 0, 'avg_duration': 0})
duration_data = defaultdict(list)

print('=== USER PATTERN ANALYSIS RESULTS ===')

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    # Parse request duration count metrics
    if 'search_api_request_duration_count{' in line:
        match = re.search(r'code=\"([^\"]+)\".*?remoteAddr=\"([^\"]+)\".*?userAgent=\"([^\"]+)\".*?}\s+(\d+)', line)
        if match:
            code, addr, agent, count = match.groups()
            # Classify client types
            client_type = 'Dashboard' if 'Mozilla' in agent or 'Chrome' in agent or 'Safari' in agent else \
                         'CLI' if 'curl' in agent or 'wget' in agent else \
                         'Automation' if 'Python' in agent or 'Go-http' in agent or 'Java' in agent else \
                         'Unknown'

            client_patterns[client_type]['total'] += int(count)
            if code != '200':
                client_patterns[client_type]['errors'] += int(count)

    # Parse request duration sum for performance analysis
    if 'search_api_request_duration_sum{' in line:
        match = re.search(r'userAgent=\"([^\"]+)\".*?}\s+([0-9.]+)', line)
        if match:
            agent, duration_sum = match.groups()
            client_type = 'Dashboard' if 'Mozilla' in agent or 'Chrome' in agent or 'Safari' in agent else \
                         'CLI' if 'curl' in agent or 'wget' in agent else \
                         'Automation' if 'Python' in agent or 'Go-http' in agent or 'Java' in agent else \
                         'Unknown'
            duration_data[client_type].append(float(duration_sum))

# Calculate and display results
print(f'Client Pattern Analysis (${namespace}/${pod_name}):')

if client_patterns:
    for client_type, data in sorted(client_patterns.items(), key=lambda x: x[1]['total'], reverse=True):
        error_rate = (data['errors'] / data['total'] * 100) if data['total'] > 0 else 0
        avg_duration = sum(duration_data[client_type]) / len(duration_data[client_type]) if duration_data[client_type] else 0

        print(f'  {client_type}: {data[\"total\"]} requests, {error_rate:.1f}% error rate, {avg_duration:.3f}s avg duration')
else:
    print('  No request patterns detected in metrics')

# Analyze remote address patterns for geographical distribution
addr_patterns = defaultdict(int)
for line in sys.stdin:
    if 'search_api_request_duration_count{' in line:
        match = re.search(r'remoteAddr=\"([^\"]+)\"', line)
        if match:
            addr = match.group(1)
            # Classify address types
            if addr.startswith('10.') or addr.startswith('192.168.') or addr.startswith('172.'):
                addr_type = 'Internal'
            elif addr.startswith('127.'):
                addr_type = 'Localhost'
            else:
                addr_type = 'External'
            addr_patterns[addr_type] += 1

print(f'Request Source Analysis:')
if addr_patterns:
    for addr_type, count in sorted(addr_patterns.items(), key=lambda x: x[1], reverse=True):
        print(f'  {addr_type}: {count} requests')
else:
    print('  No address patterns detected')
")

  # Log analysis results
  echo "[$timestamp] USER_PATTERN_RESULTS:" >> "${EXECUTION_LOG:-/dev/null}"
  echo "$analysis_output" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] USER_PATTERN_ANALYSIS_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results
  echo "$analysis_output"
}

# Find API pods with multiple fallback strategies
echo "=== Discovering Search API Pods ==="
echo "$(date '+%H:%M:%S') API_POD_DISCOVERY: Starting search for API pods" >> "${EXECUTION_LOG:-/dev/null}"

# Try multiple label selectors as fallback for API pods
API_PODS=""
if API_PODS=$(kubectl get pods -l app=search-api -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null) && [ ! -z "$API_PODS" ]; then
  echo "Found API pods with label app=search-api"
  echo "$(date '+%H:%M:%S') API_POD_DISCOVERY_METHOD: app=search-api label" >> "${EXECUTION_LOG:-/dev/null}"
elif API_PODS=$(kubectl get pods -l component=search-api -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null) && [ ! -z "$API_PODS" ]; then
  echo "Found API pods with label component=search-api"
  echo "$(date '+%H:%M:%S') API_POD_DISCOVERY_METHOD: component=search-api label" >> "${EXECUTION_LOG:-/dev/null}"
elif API_PODS=$(kubectl get pods -A --no-headers | grep search-api | awk '{print $1 "\t" $2}' 2>/dev/null) && [ ! -z "$API_PODS" ]; then
  echo "Found API pods via name pattern matching"
  echo "$(date '+%H:%M:%S') API_POD_DISCOVERY_METHOD: name pattern matching" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "ERROR: No search API pods found"
  echo "$(date '+%H:%M:%S') API_POD_DISCOVERY_ERROR: No search API pods found with any method" >> "${EXECUTION_LOG:-/dev/null}"
  exit 1
fi

pod_count=$(echo "$API_PODS" | wc -l)
echo "$(date '+%H:%M:%S') API_PODS_FOUND: $pod_count" >> "${EXECUTION_LOG:-/dev/null}"
echo "$(date '+%H:%M:%S') API_PODS_LIST: $API_PODS" >> "${EXECUTION_LOG:-/dev/null}"

# Analyze patterns for each API pod
echo ""
echo "=== User Pattern Analysis by Pod ==="

echo "$API_PODS" | while IFS=$'\t' read -r ns pod; do
  if [ ! -z "$ns" ] && [ ! -z "$pod" ]; then
    echo ""
    echo "=== $ns/$pod User Pattern Analysis ==="

    # Collect metrics from the API pod's /metrics endpoint
    echo "Collecting metrics from $ns/$pod..."
    metrics_operation="kubectl exec -n $ns $pod -- curl -k -s https://localhost:4010/metrics || kubectl exec -n $ns $pod -- curl -s http://localhost:4010/metrics"

    metrics_data=$(api_pod_operation "$metrics_operation" "$pod" "$ns" "API metrics collection from /metrics endpoint")

    if [ ! -z "$metrics_data" ] && [ "$metrics_data" != "ERROR:"* ]; then
      # Perform user pattern analysis on the metrics
      user_pattern_analysis "$metrics_data" "$pod" "$ns"
    else
      echo "  No metrics data available for user pattern analysis"
      echo "$(date '+%H:%M:%S') USER_PATTERN_WARNING: No metrics data available for $ns/$pod" >> "${EXECUTION_LOG:-/dev/null}"
    fi
  fi
done

# Summary analysis across all pods
echo ""
echo "=== Overall API Usage Summary ==="
echo "$(date '+%H:%M:%S') OVERALL_SUMMARY: Generating cross-pod usage summary" >> "${EXECUTION_LOG:-/dev/null}"

# Collect resource utilization for context
echo "API Pod Resource Utilization:"
if kubectl top pods -l app=search-api -A --no-headers 2>/dev/null | head -5; then
  echo "✅ Resource utilization data available"
else
  echo "⚠️  Resource utilization data not available (metrics-server may not be running)"
fi