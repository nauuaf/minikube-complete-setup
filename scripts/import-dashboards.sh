#!/bin/bash

source config/config.env

GRAFANA_USER="admin"
GRAFANA_PASS="$GRAFANA_ADMIN_PASSWORD"

# Try NodePort first, fallback to port-forward
GRAFANA_URL="http://localhost:$GRAFANA_NODEPORT"

echo "Testing Grafana connection..."
if ! curl -s --max-time 5 $GRAFANA_URL/api/health | grep -q "ok"; then
    echo "NodePort not accessible, using port-forward..."
    # Start port-forward for Grafana
    kubectl port-forward --address=127.0.0.1 svc/grafana 3001:3000 -n monitoring > /dev/null 2>&1 &
    GRAFANA_PF_PID=$!
    sleep 3
    GRAFANA_URL="http://localhost:3001"
    
    # Wait for port-forward to be ready
    retry_count=0
    until curl -s --max-time 5 $GRAFANA_URL/api/health | grep -q "ok" && [ $retry_count -lt 30 ]; do
        echo "Waiting for Grafana via port-forward..."
        sleep 2
        ((retry_count++))
    done
    
    if [ $retry_count -eq 30 ]; then
        echo "❌ Failed to connect to Grafana after 60 seconds"
        [[ -n "${GRAFANA_PF_PID:-}" ]] && kill $GRAFANA_PF_PID 2>/dev/null || true
        exit 1
    fi
else
    echo "✅ Grafana accessible via NodePort"
fi

# Add Prometheus data source
curl -X POST \
  -H "Content-Type: application/json" \
  -u $GRAFANA_USER:$GRAFANA_PASS \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus.monitoring:9090",
    "access": "proxy",
    "isDefault": true
  }' \
  $GRAFANA_URL/api/datasources

# Import dashboards
for dashboard in kubernetes/monitoring/dashboards/*.json; do
    echo "Importing dashboard: $(basename $dashboard)"
    curl -X POST \
      -H "Content-Type: application/json" \
      -u $GRAFANA_USER:$GRAFANA_PASS \
      -d @$dashboard \
      $GRAFANA_URL/api/dashboards/db
done

# Cleanup port-forward if it was used
if [[ -n "${GRAFANA_PF_PID:-}" ]]; then
    kill $GRAFANA_PF_PID 2>/dev/null || true
fi

echo "✅ Dashboards imported successfully"