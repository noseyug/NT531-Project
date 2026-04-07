#!/bin/bash
# =============================================================================
# Deploy LGTM Stack + OpenTelemetry Demo on K3s
# Dùng values files riêng trong thư mục values/
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_DIR="${SCRIPT_DIR}/values"

# ─── Load .env nếu có ────────────────────────────────────────────────────────
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "${SCRIPT_DIR}/.env"; set +a
fi

# ─── CONFIG (có thể override bằng env vars) ───────────────────────────────────
S3_BUCKET="${S3_BUCKET:-lgtm-stack-bucket}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# envsubst chỉ thay thế đúng các biến này, không đụng tới ${__value.raw} của Grafana
SUBST_VARS='${S3_BUCKET} ${AWS_REGION} ${GRAFANA_PASSWORD}'

# ─── COLORS ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── HELPER: helm install với values file + envsubst ─────────────────────────
# Dùng envsubst để inject S3_BUCKET, AWS_REGION, GRAFANA_PASSWORD vào values
# Grafana-specific vars như ${TELEGRAM_BOT_TOKEN} được giữ nguyên (Grafana tự resolve)
helm_install() {
  local release="$1" chart="$2" namespace="$3" values_file="$4"
  [ -f "$values_file" ] || error "Values file not found: $values_file"
  envsubst "$SUBST_VARS" < "$values_file" \
    | helm upgrade --install "$release" "$chart" -n "$namespace" --values -
}

# ─── PREREQ ──────────────────────────────────────────────────────────────────
check_prereqs() {
  info "Checking prerequisites..."
  command -v kubectl   >/dev/null || error "kubectl not found"
  command -v helm      >/dev/null || error "helm not found"
  command -v envsubst  >/dev/null || error "envsubst not found (install: apt install gettext-base)"
  kubectl cluster-info >/dev/null 2>&1 || error "Cannot connect to Kubernetes cluster"
  [ -d "$VALUES_DIR" ] || error "values/ directory not found at: $VALUES_DIR"
  success "Prerequisites OK"
}

# ─── HELM REPOS ──────────────────────────────────────────────────────────────
setup_helm_repos() {
  info "Adding Helm repos..."
  helm repo add grafana              https://grafana.github.io/helm-charts 2>/dev/null || true
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo add open-telemetry       https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
  helm repo update
  success "Helm repos ready"
}

# ─── NAMESPACES ──────────────────────────────────────────────────────────────
create_namespaces() {
  info "Creating namespaces..."
  kubectl create namespace lgtm --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
  success "Namespaces ready"
}

# ─── SECRETS ─────────────────────────────────────────────────────────────────
create_secrets() {
  info "Creating secrets..."
  kubectl create secret generic grafana-telegram-secret \
    --namespace=lgtm \
    --from-literal=TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-placeholder}" \
    --from-literal=TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-placeholder}" \
    --dry-run=client -o yaml | kubectl apply -f -
  [ -z "$TELEGRAM_BOT_TOKEN" ] && warn "TELEGRAM_BOT_TOKEN not set — Telegram alerts disabled"
  success "Secrets ready"
}

# ─── DEPLOY FUNCTIONS ────────────────────────────────────────────────────────
deploy_loki() {
  info "Deploying Loki..."
  helm_install loki grafana/loki lgtm "${VALUES_DIR}/loki.yaml"
  success "Loki deployed"
}

deploy_tempo() {
  info "Deploying Tempo..."
  helm_install tempo grafana/tempo lgtm "${VALUES_DIR}/tempo.yaml"
  success "Tempo deployed"
}

deploy_mimir() {
  info "Deploying Mimir..."
  helm_install mimir grafana/mimir-distributed lgtm "${VALUES_DIR}/mimir.yaml"
  success "Mimir deployed"
}

deploy_prometheus() {
  info "Deploying Prometheus..."
  helm_install prometheus prometheus-community/prometheus lgtm "${VALUES_DIR}/prometheus.yaml"
  success "Prometheus deployed"
}

deploy_grafana() {
  info "Deploying Grafana..."
  helm_install grafana grafana/grafana lgtm "${VALUES_DIR}/grafana.yaml"
  success "Grafana deployed (NodePort :30000)"
}

deploy_otel_operator() {
  info "Deploying OpenTelemetry Operator..."
  helm upgrade --install opentelemetry-operator \
    open-telemetry/opentelemetry-operator -n lgtm \
    --set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib"
  success "OTel Operator deployed"
}

deploy_lgtm_collector() {
  info "Deploying LGTM OTel Collector..."
  helm_install otel-collector open-telemetry/opentelemetry-collector lgtm \
    "${VALUES_DIR}/otel-collector-lgtm.yaml"
  success "LGTM OTel Collector deployed"
}

deploy_demo() {
  info "Deploying OpenTelemetry Demo app..."
  helm_install opentelemetry-demo open-telemetry/opentelemetry-demo demo \
    "${VALUES_DIR}/otel-demo.yaml"
  success "Demo app deployed"
}

fix_demo_grafana() {
  info "Patching demo Grafana datasources..."
  kubectl patch configmap grafana-datasources -n demo --type=merge -p "$(cat <<'JSON'
{
  "data": {
    "default.yaml": "apiVersion: 1\ndatasources:\n  - name: Prometheus\n    uid: webstore-metrics\n    type: prometheus\n    url: http://mimir-gateway.lgtm.svc.cluster.local:80/prometheus\n    editable: true\n    isDefault: true\n    jsonData:\n      timeInterval: \"60s\"\n      exemplarTraceIdDestinations:\n        - datasourceUid: webstore-traces\n          name: trace_id\n",
    "jaeger.yaml": "apiVersion: 1\ndeleteDatasources:\n  - name: Jaeger\n    orgId: 1\n",
    "opensearch.yaml": "apiVersion: 1\ndeleteDatasources:\n  - name: OpenSearch\n    orgId: 1\n"
  }
}
JSON
)"
  kubectl rollout restart deployment/grafana -n demo
  success "Demo Grafana datasources fixed"
}

# ─── WAIT HELPER ─────────────────────────────────────────────────────────────
wait_for() {
  local ns="$1" label="$2" timeout="${3:-180}"
  info "Waiting for [$label] in namespace [$ns]..."
  kubectl wait pod -n "$ns" -l "$label" \
    --for=condition=Ready --timeout="${timeout}s" 2>/dev/null || \
    warn "Timeout — continuing anyway"
}

# ─── MAIN ────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "╔══════════════════════════════════════════════╗"
  echo "║   LGTM + OTel Demo Deployment               ║"
  echo "╠══════════════════════════════════════════════╣"
  echo "║  S3_BUCKET  : ${S3_BUCKET}"
  echo "║  AWS_REGION : ${AWS_REGION}"
  echo "║  Telegram   : $([ -n "$TELEGRAM_BOT_TOKEN" ] && echo enabled || echo disabled)"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  check_prereqs
  setup_helm_repos
  create_namespaces
  create_secrets

  deploy_loki
  deploy_mimir
  deploy_tempo
  deploy_prometheus
  deploy_grafana

  deploy_otel_operator
  wait_for lgtm "app.kubernetes.io/name=opentelemetry-operator" 180
  deploy_lgtm_collector

  deploy_demo
  wait_for demo "app.kubernetes.io/name=opentelemetry-collector" 180
  fix_demo_grafana

  local node_ip
  node_ip=$(kubectl get nodes \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null \
    || echo "<NODE_IP>")

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║   Deployment complete!                                       ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║  Grafana (LGTM) : http://${node_ip}:30000                   ║"
  echo "║  Demo App       : kubectl port-forward \                     ║"
  echo "║    svc/frontend-proxy -n demo 8080:8080                     ║"
  echo "║    -> http://localhost:8080                                  ║"
  echo "║    -> http://localhost:8080/grafana/                         ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
}

main "$@"
