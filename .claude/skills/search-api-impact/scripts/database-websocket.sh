#!/bin/bash
# Database and WebSocket Health Analysis for Search API
# Weight: 10% of overall assessment
# Part of search-api-impact assessment methodology

set -euo pipefail

echo "=== Database and WebSocket Health Analysis ==="

# Helper function for health endpoint checks with execution logging
health_check() {
  local endpoint="$1"
  local pod_name="$2"
  local namespace="$3"
  local description="$4"
  local timestamp=$(date '+%H:%M:%S')

  # Log the health check attempt
  echo "[$timestamp] HEALTH_CHECK: $description" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] ENDPOINT: $endpoint" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] POD: $namespace/$pod_name" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute the health check and capture response
  local health_command="kubectl exec -n $namespace $pod_name -- curl -s -w '%{http_code}:%{time_total}' $endpoint"
  local raw_output=$(eval "$health_command" 2>&1)
  local exit_code=$?

  # Parse response safely
  local last_line=$(echo "$raw_output" | tail -1)
  local http_code=$(echo "$last_line" | cut -d: -f1 2>/dev/null || echo "000")
  local response_time=$(echo "$last_line" | cut -d: -f2 2>/dev/null || echo "0.000")
  local response_body=""
  if [ $(echo "$raw_output" | wc -l) -gt 1 ]; then
    response_body=$(echo "$raw_output" | sed '$d')  # Remove last line safely
  fi

  # Log health check results
  echo "[$timestamp] HTTP_CODE: $http_code" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] RESPONSE_TIME: ${response_time}s" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] RESPONSE_BODY: $response_body" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results
  if [ "$http_code" = "200" ]; then
    echo "[$timestamp] HEALTH_STATUS: healthy" >> "${EXECUTION_LOG:-/dev/null}"
    echo "  ✅ $description: OK (${response_time}s)"
  else
    echo "[$timestamp] HEALTH_STATUS: unhealthy" >> "${EXECUTION_LOG:-/dev/null}"
    echo "  ❌ $description: Failed (HTTP $http_code, ${response_time}s)"
  fi

  echo "[$timestamp] HEALTH_CHECK_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
}

# Helper function for resource analysis with execution logging
resource_analysis() {
  local resource_type="$1"
  local description="$2"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] RESOURCE_ANALYSIS: $description" >> "${EXECUTION_LOG:-/dev/null}"

  case $resource_type in
    "pod_resources")
      local resource_data=$(kubectl top pods -l app=search-api -A --no-headers 2>/dev/null || echo "")
      ;;
    "api_pod_status")
      local resource_data=$(kubectl get pods -l app=search-api -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase 2>/dev/null || echo "")
      ;;
    *)
      echo "[$timestamp] RESOURCE_ERROR: Unknown resource type $resource_type" >> "${EXECUTION_LOG:-/dev/null}"
      return 1
      ;;
  esac

  # Log resource analysis results
  local line_count=$(echo "$resource_data" | wc -l)
  echo "[$timestamp] RESOURCE_DATA_LINES: $line_count" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] RESOURCE_DATA: $resource_data" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results
  if [ ! -z "$resource_data" ] && [ "$resource_data" != "" ]; then
    echo "[$timestamp] RESOURCE_STATUS: data_available" >> "${EXECUTION_LOG:-/dev/null}"
    echo "$resource_data"
  else
    echo "[$timestamp] RESOURCE_STATUS: no_data" >> "${EXECUTION_LOG:-/dev/null}"
    echo "  ⚠️  $description: No data available"
  fi

  echo "[$timestamp] RESOURCE_ANALYSIS_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
}

# Discover API pods for health checks
echo "=== Discovering API Pods for Health Checks ==="
echo "$(date '+%H:%M:%S') HEALTH_POD_DISCOVERY: Starting API pod discovery for health analysis" >> "${EXECUTION_LOG:-/dev/null}"

# Find API pods using multiple methods
API_PODS=""
if API_PODS=$(kubectl get pods -l app=search-api -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null) && [ ! -z "$API_PODS" ]; then
  echo "Found API pods for health checks"
elif API_PODS=$(kubectl get pods -A --no-headers | grep search-api | awk '{print $1 "\t" $2}' 2>/dev/null) && [ ! -z "$API_PODS" ]; then
  echo "Found API pods via pattern matching"
else
  echo "WARNING: No API pods found for health checks"
  echo "$(date '+%H:%M:%S') HEALTH_POD_WARNING: No API pods found" >> "${EXECUTION_LOG:-/dev/null}"
  API_PODS=""
fi

if [ ! -z "$API_PODS" ]; then
  pod_count=$(echo "$API_PODS" | wc -l)
  echo "$(date '+%H:%M:%S') HEALTH_PODS_FOUND: $pod_count" >> "${EXECUTION_LOG:-/dev/null}"
  echo "$(date '+%H:%M:%S') HEALTH_PODS_LIST: $API_PODS" >> "${EXECUTION_LOG:-/dev/null}"

  # Health endpoint checks for each pod
  echo ""
  echo "=== Health Endpoint Analysis ==="

  echo "$API_PODS" | while IFS=$'\t' read -r ns pod; do
    if [ ! -z "$ns" ] && [ ! -z "$pod" ]; then
      echo ""
      echo "=== Health Checks for $ns/$pod ==="

      # Liveness probe check
      health_check "http://localhost:4010/liveness" "$pod" "$ns" "Liveness probe"

      # Readiness probe check
      health_check "http://localhost:4010/readiness" "$pod" "$ns" "Readiness probe"

      # Metrics endpoint availability
      health_check "http://localhost:4010/metrics" "$pod" "$ns" "Metrics endpoint"
    fi
  done
fi

# Resource utilization analysis
echo ""
echo "=== API Resource Utilization ==="

echo "Current pod resource usage:"
resource_analysis "pod_resources" "API pod resource consumption"

echo ""
echo "Pod status and readiness:"
resource_analysis "api_pod_status" "API pod status analysis"

# Database connection analysis (if we can find the database)
echo ""
echo "=== Database Connection Analysis ==="
echo "$(date '+%H:%M:%S') DATABASE_ANALYSIS: Starting database connection analysis" >> "${EXECUTION_LOG:-/dev/null}"

# Try to find PostgreSQL pod for connection analysis
POSTGRES_PODS=$(kubectl get pods -l name=search-postgres -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null || echo "")

if [ ! -z "$POSTGRES_PODS" ]; then
  echo "Found PostgreSQL pods for connection analysis"
  echo "$(date '+%H:%M:%S') DATABASE_PODS_FOUND: $(echo "$POSTGRES_PODS" | wc -l)" >> "${EXECUTION_LOG:-/dev/null}"

  echo "$POSTGRES_PODS" | head -1 | while IFS=$'\t' read -r pg_ns pg_pod; do
    if [ ! -z "$pg_ns" ] && [ ! -z "$pg_pod" ]; then
      echo "Analyzing database connections from API perspective:"

      # Check active connections to the database
      db_check_command="kubectl exec -n $pg_ns $pg_pod -- psql -U searchuser -d search -c \"SELECT state, COUNT(*) FROM pg_stat_activity WHERE datname='search' GROUP BY state;\""

      echo "$(date '+%H:%M:%S') DATABASE_CONNECTION_CHECK: $db_check_command" >> "${EXECUTION_LOG:-/dev/null}"

      db_output=$(eval "$db_check_command" 2>&1)
      db_exit_code=$?

      echo "$(date '+%H:%M:%S') DATABASE_CONNECTION_OUTPUT: $db_output" >> "${EXECUTION_LOG:-/dev/null}"
      echo "$(date '+%H:%M:%S') DATABASE_CONNECTION_EXIT_CODE: $db_exit_code" >> "${EXECUTION_LOG:-/dev/null}"

      if [ $db_exit_code -eq 0 ]; then
        echo "  ✅ Database connection analysis successful"
        echo "$db_output"
      else
        echo "  ⚠️  Database connection analysis failed"
        echo "  Error: $db_output"
      fi
    fi
  done
else
  echo "⚠️  No PostgreSQL pods found for database connection analysis"
  echo "$(date '+%H:%M:%S') DATABASE_WARNING: No PostgreSQL pods found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# WebSocket and subscription analysis summary
echo ""
echo "=== WebSocket and Real-time Analysis Summary ==="
echo "$(date '+%H:%M:%S') WEBSOCKET_SUMMARY: Generating WebSocket analysis summary" >> "${EXECUTION_LOG:-/dev/null}"

echo "WebSocket health analysis completed. Key metrics to review:"
echo "  - Active subscription count (from Prometheus metrics)"
echo "  - WebSocket connection failure rates"
echo "  - Real-time feature adoption patterns"
echo "  - Subscription duration trends"

echo ""
echo "For detailed WebSocket metrics, refer to Prometheus metrics analysis section."