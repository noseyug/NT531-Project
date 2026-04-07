# LGTM Stack + OpenTelemetry Demo — Deployment Guide

Hệ thống observability đầy đủ trên K3s, bao gồm **LGTM stack** (Loki, Grafana, Tempo, Mimir)
và ứng dụng demo **OpenTelemetry** (webstore microservices).

---

## Kiến trúc tổng quan

```
┌──────────────────────── namespace: demo ─────────────────────────┐
│                                                                   │
│  load-generator ──► frontend-proxy (Envoy)                       │
│                           │                                       │
│         ┌─────────────────┼──────────────────┐                   │
│         ▼                 ▼                  ▼                   │
│     frontend           cart              checkout                 │
│     product-catalog    payment           shipping                 │
│     recommendation     currency          email                   │
│     ad, llm, quote, postgresql, kafka, ...                        │
│                                                                   │
│  (tất cả services gửi telemetry qua OTLP SDK)                    │
│                          │                                        │
│                          ▼ OTLP :4317                            │
│              ┌─────────────────────────┐                         │
│              │  OTel Collector         │ DaemonSet               │
│              │  (demo namespace)       │                         │
│              └─────────────────────────┘                         │
│                Traces│  Logs│  Metrics│                          │
└──────────────────────┼──────┼─────────┼──────────────────────────┘
                        │      │         │
┌──────────────────────┼──────┼─────────┼──── namespace: lgtm ─────┐
│                       ▼      ▼         ▼                          │
│              ┌───────────┐ ┌────────┐ ┌──────────────────┐       │
│              │   Tempo   │ │  Loki  │ │      Mimir       │       │
│              │ :4318/:3200│ │ :3100  │ │  distributed     │       │
│              └─────┬─────┘ └───┬────┘ └────────┬─────────┘       │
│                    │           │               │                  │
│              ┌─────────────────────────────────┘                  │
│              │  OTel Collector  (lgtm ns, DaemonSet)              │
│              │  - filelog: lgtm + kube-system pods               │
│              │  - OTLP receiver                                   │
│              └────────────────────────────────────                │
│                                                                   │
│              Prometheus ──scrape──► kube-state-metrics            │
│                        ──scrape──► node-exporter                  │
│                        ──remoteWrite──► Mimir                     │
│                                                                   │
│              ┌──────────────────────────────┐                     │
│              │  Grafana  (NodePort :30000)  │                     │
│              │  datasources:                │                     │
│              │    Mimir  (metrics)          │                     │
│              │    Tempo  (traces)           │                     │
│              │    Loki   (logs)             │                     │
│              └──────────────────────────────┘                     │
└───────────────────────────────────────────────────────────────────┘
```

---

## Yêu cầu

### Hạ tầng
- **K3s** cluster (>= v1.30), tối thiểu 2 nodes
- **AWS S3 bucket** để lưu traces (Tempo), logs (Loki), metrics (Mimir)
- EC2 instance với **IAM role** có quyền S3:
  ```json
  {
    "Effect": "Allow",
    "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"],
    "Resource": ["arn:aws:s3:::lgtm-stack-bucket","arn:aws:s3:::lgtm-stack-bucket/*"]
  }
  ```

### Tools cần cài trên server
```bash
# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl đã có sẵn nếu dùng k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

---

## Deploy nhanh

```bash
# 1. Clone / copy script lên server
scp -i your-key.pem deploy.sh ubuntu@<SERVER_IP>:~/

# 2. SSH vào server
ssh -i your-key.pem ubuntu@<SERVER_IP>

# 3. Set biến môi trường
export S3_BUCKET="lgtm-stack-bucket"        # tên S3 bucket
export AWS_REGION="ap-southeast-1"           # region AWS
export GRAFANA_PASSWORD="your-password"      # mật khẩu Grafana admin
export TELEGRAM_BOT_TOKEN="123:ABC..."       # (tuỳ chọn) bot token Telegram
export TELEGRAM_CHAT_ID="-100123456"         # (tuỳ chọn) chat ID Telegram

# 4. Chạy deploy
chmod +x deploy.sh
./deploy.sh
```

---

## Các bước deploy chi tiết

Script `deploy.sh` thực hiện theo thứ tự:

| Bước | Component | Namespace | Mô tả |
|------|-----------|-----------|-------|
| 1 | Helm repos | — | Thêm grafana, prometheus-community, open-telemetry |
| 2 | Namespaces | — | Tạo `lgtm`, `demo` |
| 3 | Secrets | lgtm | `grafana-telegram-secret` |
| 4 | Loki | lgtm | Log storage (S3 backend, single binary) |
| 5 | Mimir | lgtm | Metrics storage (S3 backend, distributed) |
| 6 | Tempo | lgtm | Trace storage (S3 backend) |
| 7 | Prometheus | lgtm | K8s metrics scraper → remote write → Mimir |
| 8 | Grafana | lgtm | Dashboard, NodePort 30000 |
| 9 | OTel Operator | lgtm | Quản lý OTel Collector CRDs |
| 10 | LGTM Collector | lgtm | DaemonSet thu infra logs + forward |
| 11 | Demo App | demo | OpenTelemetry webstore (~20 microservices) |
| 12 | Fix datasources | demo | Patch Grafana datasources → LGTM backends |

---

## Luồng dữ liệu

### Traces
```
Demo services → OTLP/gRPC → Demo Collector → OTLP/HTTP → Tempo → Grafana
```

### Logs
```
Demo services → OTLP → Demo Collector → OTLP/HTTP → Loki Gateway → Grafana
Infra pods    → filelog → LGTM Collector → OTLP/HTTP → Loki → Grafana
  (chỉ đọc lgtm + kube-system, KHÔNG đọc demo để tránh duplicate)
```

### Metrics
```
Demo services → OTLP → Demo Collector → Prometheus Remote Write → Mimir → Grafana
K8s infra     → scrape → Prometheus → Remote Write → Mimir → Grafana
Tempo spans   → metricsGenerator → Remote Write → Mimir → Grafana
```

---

## Truy cập sau khi deploy

| Service | Địa chỉ | Ghi chú |
|---------|---------|---------|
| **Grafana (LGTM)** | `http://<NODE_IP>:30000` | user: `admin` |
| **Demo App** | `http://localhost:8080` | cần port-forward |
| **Demo Grafana** | `http://localhost:8080/grafana/` | anonymous access |
| **Load Generator** | `http://localhost:8080/loadgen/` | điều chỉnh traffic |

```bash
# Port-forward để truy cập demo app
kubectl port-forward svc/frontend-proxy -n demo 8080:8080
```

---

## Helm charts & versions

| Chart | Repo | Version hiện tại |
|-------|------|-----------------|
| `grafana/grafana` | grafana | 10.5.15 |
| `grafana/loki` | grafana | 6.55.0 |
| `grafana/tempo` | grafana | 1.24.4 |
| `grafana/mimir-distributed` | grafana | 6.0.6 |
| `prometheus-community/prometheus` | prometheus-community | 28.15.0 |
| `open-telemetry/opentelemetry-operator` | open-telemetry | 0.109.0 |
| `open-telemetry/opentelemetry-collector` | open-telemetry | 0.147.1 |
| `open-telemetry/opentelemetry-demo` | open-telemetry | 0.40.6 |

---

## Cấu hình quan trọng

### S3 Backend (Loki, Tempo, Mimir)
Tất cả 3 components đều dùng chung 1 S3 bucket với prefix riêng.
EC2 instance phải có IAM role với S3 permissions — **không cần access key**.

### Mimir — giới hạn ingestion
```yaml
limits:
  ingestion_rate:             100000   # samples/giây
  ingestion_burst_size:       200000
  max_global_series_per_user: 500000
```

### Demo Collector — disable hostPort
Tắt `hostPort` để tránh conflict với LGTM Collector đang chạy trên cùng node:
```yaml
ports:
  otlp:      {hostPort: 0}
  otlp-http: {hostPort: 0}
```

### LGTM Collector — exclude demo logs
Tránh đọc log file của demo pods (đã có OTLP logs rồi):
```yaml
filelog:
  exclude:
    - /var/log/pods/demo_*/*.log
```

---

## Telegram Alerting (tuỳ chọn)

Grafana được cấu hình sẵn Telegram contact point.
Nếu muốn bật alerts:

```bash
export TELEGRAM_BOT_TOKEN="<bot_token_from_botfather>"
export TELEGRAM_CHAT_ID="<chat_id>"
./deploy.sh
```

Tạo bot: chat với `@BotFather` trên Telegram → `/newbot`
Lấy chat ID: thêm bot vào group → `https://api.telegram.org/bot<TOKEN>/getUpdates`

---

## Troubleshooting

### Kiểm tra trạng thái
```bash
# Tất cả pods
kubectl get pods -n lgtm
kubectl get pods -n demo

# Logs collector
kubectl logs -n demo -l app.kubernetes.io/name=opentelemetry-collector --tail=50

# Test Loki có nhận logs không
kubectl run curl-test --image=curlimages/curl --restart=Never --rm -it -n lgtm \
  -- curl -s http://loki.lgtm.svc.cluster.local:3100/loki/api/v1/labels

# Test Mimir có metrics không
kubectl run curl-test --image=curlimages/curl --restart=Never --rm -it -n lgtm \
  -- curl -s 'http://mimir-query-frontend.lgtm.svc.cluster.local:8080/prometheus/api/v1/query?query=kube_node_info'
```

### Lỗi thường gặp

| Lỗi | Nguyên nhân | Fix |
|-----|-------------|-----|
| Collector pod `Pending` | `hostPort` conflict | Đảm bảo `hostPort: 0` trong values |
| Loki 404 `/v1/logs/v1/logs` | URL bị duplicate | Endpoint phải là `/otlp` (không có `/v1/logs`) |
| Mimir `unauthorized` | Thiếu tenant header | Set `multitenancy_enabled: false` |
| S3 access denied | IAM role sai | Kiểm tra EC2 instance profile |
