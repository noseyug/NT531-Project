#!/bin/bash
set -e

echo "Create namespaces..."
kubectl create namespace bookinfo --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace lgtm --dry-run=client -o yaml | kubectl apply -f -

echo "Update Helm repos..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

echo "Deploying Cert-Manager & OpenTelemetry Operator..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
sleep 45 

helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator -n lgtm
# Ensure CRDs (like Instrumentation) are fully registered before applying bookinfo.yaml
sleep 30

echo "Deploy Bookinfo, Ingress & HPA..."
kubectl apply -f app/bookinfo.yaml -n bookinfo
kubectl apply -f app/ingress.yaml -n bookinfo
kubectl apply -f app/middleware.yaml -n bookinfo

kubectl set resources deployment productpage-v1 -n bookinfo \
  --requests=cpu=100m,memory=128Mi \
  --limits=cpu=500m,memory=512Mi

kubectl apply -f app/bookinfo-hpa.yaml -n bookinfo

echo "Deploy LGTM Stack..."

echo "-> Deploying Loki..."
helm upgrade --install loki grafana/loki -n lgtm -f monitoring/loki-values.yaml
sleep 10

echo "-> Deploying Tempo (Bản nhẹ)..."
helm upgrade --install tempo grafana/tempo -n lgtm -f monitoring/tempo-values.yaml
sleep 10

echo "-> Deploying Mimir (Single Binary)..."
helm upgrade --install mimir grafana/mimir-distributed -n lgtm -f monitoring/mimir-values.yaml
sleep 10

echo "-> Deploying OpenTelemetry Collector..."
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector -n lgtm -f monitoring/otel-values.yaml
sleep 10

echo "-> Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus -n lgtm -f monitoring/prometheus-values.yaml
sleep 10

echo "-> Deploying Grafana..."
# Đọc trực tiếp từ file values gốc, bỏ qua bước nhúng biến môi trường
helm upgrade --install grafana grafana/grafana -n lgtm \
  --set service.type=NodePort \
  --set service.nodePort=30000 \
  -f monitoring/grafana-values-public.yaml
  
echo "Done!"
