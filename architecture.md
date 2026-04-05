# Kiến trúc hệ thống K8s Observability LGTM

```mermaid
flowchart TD
    %% ── External ──────────────────────────────────────────────
    k6["☁️ k6 Load Tester\n(kb1 Baseline / kb2 RED\nkb3 Stress / kb4 Spike)"]
    user["👤 User / Browser"]

    %% ── AWS Infrastructure ────────────────────────────────────
    subgraph AWS["AWS ap-southeast-1"]
        subgraph EC2["EC2 — k3s Single Node"]

            %% ── Ingress ───────────────────────────────────────
            subgraph ingress["Ingress Layer"]
                traefik["Traefik\n(IngressController)\n+ Middleware: InFlightReq ≤75"]
            end

            %% ── App ───────────────────────────────────────────
            subgraph bookinfo["Namespace: bookinfo"]
                pp["productpage\n(Python)\n✅ OTel auto-inject"]
                rv["reviews\n(Java)\n✅ OTel auto-inject"]
                rt["ratings\n(Node.js)"]
                dt["details\n(Ruby)"]
                hpa["HPA\n(min1 / max5)"]
            end

            %% ── Observability ─────────────────────────────────
            subgraph lgtm["Namespace: lgtm"]
                otel["OTel Collector\n(DaemonSet)\nfilelog preset"]
                loki["Loki\n(log store)"]
                tempo["Tempo\n(trace store)\nmetricsGenerator"]
                mimir["Mimir\n(metrics store)"]
                prom["Prometheus\n(scraper)"]
                grafana["Grafana\n• Dashboard: Infrastructure\n• Dashboard: RED Method\n• Alert Rules: CPU / Error / Latency"]
            end

        end

        s3["🪣 AWS S3\nlgtm-stack-bucket\n(Loki / Tempo / Mimir chunks)"]
        telegram["📱 Telegram\n(Alert notifications)"]
    end

    %% ── Traffic flow ──────────────────────────────────────────
    user -->|HTTP| traefik
    k6 -->|HTTP load| traefik
    traefik -->|route /| pp
    pp -->|REST| rv
    rv -->|REST| rt
    rv -->|REST| dt

    %% ── TRACES: app → OTel → Tempo → S3 ──────────────────────
    pp -->|OTLP gRPC traces| otel
    rv -->|OTLP gRPC traces| otel
    otel -->|OTLP gRPC| tempo
    tempo -->|chunks| s3

    %% ── LOGS: filelog → OTel → Loki → S3 ────────────────────
    bookinfo -->|/var/log/pods| otel
    lgtm -->|/var/log/pods| otel
    otel -->|OTLP HTTP| loki
    loki -->|chunks| s3

    %% ── METRICS (app OTLP): app → OTel → Mimir ───────────────
    pp -->|OTLP gRPC metrics| otel
    rv -->|OTLP gRPC metrics| otel
    otel -->|OTLP HTTP| mimir

    %% ── METRICS (infra): Prometheus scrape → Mimir ────────────
    prom -->|scrape: Traefik, kube-state, cadvisor| traefik
    prom -->|scrape: pod annotations| bookinfo
    prom -->|remote_write| mimir
    mimir -->|chunks| s3

    %% ── METRICS (service graph): Tempo → Mimir ───────────────
    tempo -->|metricsGenerator\nremote_write| mimir

    %% ── HPA ───────────────────────────────────────────────────
    mimir -->|CPU metrics| hpa
    hpa -->|scale pods| bookinfo

    %% ── Grafana reads ─────────────────────────────────────────
    loki -->|LogQL| grafana
    tempo -->|TraceQL| grafana
    mimir -->|PromQL| grafana

    %% ── Alerts ────────────────────────────────────────────────
    grafana -->|CPU >70%\nError >5%\nLatency >4s| telegram

    %% ── Styles ────────────────────────────────────────────────
    classDef app fill:#dbeafe,stroke:#3b82f6,color:#1e3a5f
    classDef obs fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef storage fill:#fef9c3,stroke:#ca8a04,color:#713f12
    classDef traffic fill:#f3e8ff,stroke:#9333ea,color:#3b0764
    classDef external fill:#fee2e2,stroke:#dc2626,color:#7f1d1d

    class pp,rv,rt,dt,hpa app
    class otel,loki,tempo,mimir,prom,grafana obs
    class s3 storage
    class traefik traffic
    class k6,user,telegram external
```

## Luồng dữ liệu theo Signal

| Signal | Thu thập | Xử lý | Lưu trữ | Visualize |
|--------|----------|-------|---------|-----------|
| **Traces** | OTel auto-inject (productpage, reviews) | OTel Collector | Tempo → S3 | Grafana (TraceQL) |
| **Logs** | OTel filelog DaemonSet (toàn cluster) | OTel Collector | Loki → S3 | Grafana (LogQL) |
| **Metrics (app)** | OTel OTLP receiver | OTel Collector | Mimir → S3 | Grafana (PromQL) |
| **Metrics (infra)** | Prometheus scrape (Traefik, cadvisor, kube-state) | Prometheus | Mimir → S3 | Grafana (PromQL) |
| **Service Graph** | Tempo metricsGenerator | remote_write | Mimir → S3 | Grafana (Node Graph) |

## Correlation (Loki ↔ Tempo ↔ Mimir)

```
Grafana: thấy latency spike trên Mimir
    → RED dashboard → Slow Traces panel (Tempo) → click trace
    → Tempo trace waterfall → "Logs for this span" (Loki derived field)
    → Loki logs filtered by traceID
```
