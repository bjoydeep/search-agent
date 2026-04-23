#!/bin/bash
# RBAC Authentication Analysis for Search API
# Weight: 5% of overall assessment
# Part of search-api-impact assessment methodology

set -euo pipefail

echo "=== RBAC Authentication Analysis ==="

# Helper function for log-based RBAC analysis with execution logging
rbac_log_analysis() {
  local log_source="$1"
  local time_window="$2"
  local description="$3"
  local timestamp=$(date '+%H:%M:%S')

  # Log the analysis attempt
  echo "[$timestamp] RBAC_LOG_ANALYSIS: $description ($time_window)" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] LOG_SOURCE: $log_source" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute log collection
  local raw_logs=$(eval "$log_source" 2>&1)
  local exit_code=$?

  # Log the raw log collection status
  echo "[$timestamp] LOG_COLLECTION_EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] LOG_LINE_COUNT: $(echo "$raw_logs" | wc -l)" >> "${EXECUTION_LOG:-/dev/null}"

  # Filter for RBAC-relevant entries
  local rbac_logs=$(echo "$raw_logs" | grep -iE "(auth|rbac|permission|role|token|unauthorized|forbidden|401|403)" 2>/dev/null || echo "")
  local rbac_line_count=$(echo "$rbac_logs" | wc -l)

  echo "[$timestamp] RBAC_RELEVANT_LINES: $rbac_line_count" >> "${EXECUTION_LOG:-/dev/null}"

  # Analyze RBAC patterns
  local rbac_analysis=$(echo "$rbac_logs" | python3 -c "
import sys
import re
from collections import defaultdict
from datetime import datetime

# RBAC-specific pattern analysis
auth_patterns = defaultdict(int)
error_patterns = defaultdict(int)
timing_patterns = []
user_patterns = defaultdict(int)

print('=== RBAC Analysis Results ($description) ===')

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    # Authentication event classification
    if re.search(r'auth.*success|login.*success|token.*valid', line, re.I):
        auth_patterns['successful_auth'] += 1
    elif re.search(r'auth.*fail|login.*fail|token.*invalid|unauthorized', line, re.I):
        auth_patterns['failed_auth'] += 1
    elif re.search(r'permission.*denied|access.*denied|forbidden', line, re.I):
        auth_patterns['permission_denied'] += 1

    # Error classification
    if re.search(r'401', line):
        error_patterns['unauthorized'] += 1
    elif re.search(r'403', line):
        error_patterns['forbidden'] += 1
    elif re.search(r'token.*expired', line, re.I):
        error_patterns['token_expired'] += 1

    # Performance timing for auth operations
    time_match = re.search(r'(?:auth|rbac).*?(\d+(?:\.\d+)?)\s*(?:ms|seconds?)', line, re.I)
    if time_match:
        timing_patterns.append(float(time_match.group(1)))

    # User/service account patterns
    user_match = re.search(r'user[:\s=]([a-zA-Z0-9@._-]+)', line, re.I)
    if user_match:
        user_patterns[user_match.group(1)] += 1

# Generate analysis report
print(f'Authentication Event Summary:')
if auth_patterns:
    for event_type, count in auth_patterns.items():
        print(f'  {event_type}: {count}')
else:
    print('  No authentication events detected')

print(f'RBAC Error Analysis:')
if error_patterns:
    total_errors = sum(error_patterns.values())
    for error_type, count in error_patterns.items():
        percentage = (count / total_errors * 100) if total_errors > 0 else 0
        print(f'  {error_type}: {count} ({percentage:.1f}%)')
else:
    print('  No RBAC errors detected')

print(f'Authentication Performance:')
if timing_patterns:
    avg_time = sum(timing_patterns) / len(timing_patterns)
    max_time = max(timing_patterns)
    min_time = min(timing_patterns)
    print(f'  avg: {avg_time:.1f}ms, max: {max_time:.1f}ms, min: {min_time:.1f}ms, samples: {len(timing_patterns)}')
else:
    print('  No authentication timing data available')

print(f'User Activity Patterns (top 5):')
if user_patterns:
    for user, count in sorted(user_patterns.items(), key=lambda x: x[1], reverse=True)[:5]:
        print(f'  {user}: {count} operations')
else:
    print('  No user patterns detected')
")

  # Log analysis results
  echo "[$timestamp] RBAC_ANALYSIS_RESULTS:" >> "${EXECUTION_LOG:-/dev/null}"
  echo "$rbac_analysis" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] RBAC_LOG_ANALYSIS_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results
  echo "$rbac_analysis"
}

# Helper function for RBAC policy analysis with execution logging
rbac_policy_analysis() {
  local description="$1"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] RBAC_POLICY_ANALYSIS: $description" >> "${EXECUTION_LOG:-/dev/null}"

  # Check for search-related RBAC policies
  local rbac_resources=$(kubectl get clusterroles,roles,clusterrolebindings,rolebindings -A 2>/dev/null | grep -i search || echo "")
  local rbac_count=$(echo "$rbac_resources" | wc -l)

  echo "[$timestamp] SEARCH_RBAC_RESOURCES_FOUND: $rbac_count" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] RBAC_RESOURCES: $rbac_resources" >> "${EXECUTION_LOG:-/dev/null}"

  # Analyze search-related RBAC complexity
  local policy_analysis=$(echo "$rbac_resources" | python3 -c "
import sys

roles = []
bindings = []
clusters = []

print('=== RBAC Policy Analysis ===')

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    if 'clusterrole/' in line or 'role/' in line:
        roles.append(line)
    elif 'rolebinding/' in line or 'clusterrolebinding/' in line:
        bindings.append(line)

print(f'Search-related RBAC Resources:')
print(f'  Roles/ClusterRoles: {len(roles)}')
print(f'  RoleBindings/ClusterRoleBindings: {len(bindings)}')

if len(roles) > 10 or len(bindings) > 15:
    print('  ⚠️  High RBAC complexity detected - may impact authentication performance')
elif len(roles) == 0 and len(bindings) == 0:
    print('  ℹ️  No search-specific RBAC resources found (using default)')
else:
    print('  ✅ Normal RBAC complexity')

print(f'Key RBAC Resources (top 5):')
for resource in (roles + bindings)[:5]:
    print(f'  {resource}')
")

  # Log policy analysis results
  echo "[$timestamp] RBAC_POLICY_RESULTS:" >> "${EXECUTION_LOG:-/dev/null}"
  echo "$policy_analysis" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] RBAC_POLICY_ANALYSIS_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results
  echo "$policy_analysis"
}

# Multi-window RBAC log analysis
echo "=== RBAC Log Analysis Across Time Windows ==="

# Find API pods for log analysis
echo "$(date '+%H:%M:%S') RBAC_POD_DISCOVERY: Finding API pods for RBAC log analysis" >> "${EXECUTION_LOG:-/dev/null}"

API_PODS=$(kubectl get pods -l app=search-api -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null || echo "")

if [ ! -z "$API_PODS" ]; then
  pod_count=$(echo "$API_PODS" | wc -l)
  echo "Found $pod_count API pod(s) for RBAC analysis"
  echo "$(date '+%H:%M:%S') RBAC_PODS_FOUND: $pod_count" >> "${EXECUTION_LOG:-/dev/null}"

  # Get the first pod for log analysis
  first_pod=$(echo "$API_PODS" | head -1)
  ns=$(echo "$first_pod" | cut -f1)
  pod=$(echo "$first_pod" | cut -f2)

  echo ""
  echo "=== Recent Authentication Activity (Last 10 minutes) ==="
  rbac_log_analysis "kubectl logs -n $ns $pod --since=10m 2>/dev/null" "10m" "Recent RBAC activity analysis"

  echo ""
  echo "=== Short-term Authentication Patterns (Last 30 minutes) ==="
  rbac_log_analysis "kubectl logs -n $ns $pod --since=30m 2>/dev/null" "30m" "Short-term RBAC pattern analysis"

  echo ""
  echo "=== Broader Authentication Context (Last 1 hour) ==="
  rbac_log_analysis "kubectl logs -n $ns $pod --since=1h 2>/dev/null" "1h" "Long-term RBAC context analysis"

else
  echo "WARNING: No API pods found for RBAC log analysis"
  echo "$(date '+%H:%M:%S') RBAC_WARNING: No API pods found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# RBAC policy complexity analysis
echo ""
echo "=== RBAC Policy Complexity Analysis ==="
rbac_policy_analysis "Search RBAC policy complexity assessment"

# Authentication overhead estimation
echo ""
echo "=== Authentication Overhead Estimation ==="
echo "$(date '+%H:%M:%S') AUTH_OVERHEAD_ANALYSIS: Estimating authentication overhead" >> "${EXECUTION_LOG:-/dev/null}"

# Check for service account tokens and their complexity
echo "Authentication Configuration Analysis:"

# Count service accounts related to search
SA_COUNT=$(kubectl get serviceaccounts -A 2>/dev/null | grep -i search | wc -l || echo "0")
echo "  Search-related ServiceAccounts: $SA_COUNT"

# Check for complex authentication mechanisms
AUTH_COMPLEXITY="normal"
if [ $SA_COUNT -gt 10 ]; then
  AUTH_COMPLEXITY="high"
elif [ $SA_COUNT -eq 0 ]; then
  AUTH_COMPLEXITY="minimal"
fi

echo "  Authentication complexity: $AUTH_COMPLEXITY"

case $AUTH_COMPLEXITY in
  "high")
    echo "  ⚠️  High authentication complexity may introduce latency"
    ;;
  "minimal")
    echo "  ℹ️  Minimal authentication setup detected"
    ;;
  *)
    echo "  ✅ Normal authentication complexity"
    ;;
esac

echo "$(date '+%H:%M:%S') AUTH_COMPLEXITY_LEVEL: $AUTH_COMPLEXITY" >> "${EXECUTION_LOG:-/dev/null}"
echo "$(date '+%H:%M:%S') SEARCH_SERVICE_ACCOUNTS: $SA_COUNT" >> "${EXECUTION_LOG:-/dev/null}"

echo ""
echo "RBAC analysis completed. Key findings:"
echo "  - Authentication event patterns analyzed across multiple time windows"
echo "  - RBAC policy complexity assessed"
echo "  - Authentication overhead estimated"
echo "  - Service account configuration reviewed"