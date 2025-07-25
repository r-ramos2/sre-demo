# SRE Demo Project — Final Working Setup

This guide updates code, Helm charts, and commands for a fully functional SRE demo. Grafana will be accessible on host port 8080. Cleanup steps are at the end.

---

## 1. **Flask App Code**

**`app/app.py`**

```python
from flask import Flask, jsonify
from prometheus_client import start_http_server, Counter
app = Flask(__name__)
REQUESTS = Counter("app_requests_total", "Total HTTP requests")
@app.before_request
def count_requests():
 REQUESTS.inc()
@app.route("/health")
def health():
 return jsonify(status="ok")
@app.route("/")
def index():
 return jsonify(message="Hello from SRE demo")
if __name__ == "__main__":
 start_http_server(9090)
 app.run(host="0.0.0.0", port=8080)
```

---

## 2. **Dockerfile**

**`Dockerfile`**

```dockerfile
FROM python:3.11-slim
RUN useradd -m appuser
WORKDIR /home/appuser
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/app.py .
EXPOSE 8080 9090
HEALTHCHECK --interval=15s --timeout=3s \
 CMD curl --fail http://localhost:8080/health || exit 1
USER appuser
CMD ["sh","-c","python -m prometheus_client --bind 0.0.0.0:9090 & python app.py"]
```

---

## 3. **Helm Chart Files**

**`charts/sre-demo/values.yaml`**

```yaml
replicaCount: 2
image:
 repository: sre-demo
 pullPolicy: Never
 tag: latest
service:
 type: ClusterIP
 port: 80
 targetPort: 8080
 metricsPort: 9090
```

**`charts/sre-demo/templates/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
 name: sre-demo
spec:
 replicas: {{ .Values.replicaCount }}
 selector:
  matchLabels:
   app: sre-demo
 template:
  metadata:
   labels:
    app: sre-demo
  spec:
   containers:
   - name: sre-demo
     image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
     imagePullPolicy: {{ .Values.image.pullPolicy }}
     ports:
     - containerPort: {{ .Values.service.targetPort }}
     - containerPort: {{ .Values.service.metricsPort }}
     livenessProbe:
      httpGet:
       path: /health
       port: {{ .Values.service.targetPort }}
      initialDelaySeconds: 5
      periodSeconds: 10
     readinessProbe:
      httpGet:
       path: /health
       port: {{ .Values.service.targetPort }}
      initialDelaySeconds: 3
      periodSeconds: 5
```

**`charts/sre-demo/templates/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
 name: sre-demo
spec:
 type: {{ .Values.service.type }}
 selector:
  app: sre-demo
 ports:
 - name: http
   port: {{ .Values.service.port }}
   targetPort: {{ .Values.service.targetPort }}
 - name: metrics
   port: {{ .Values.service.metricsPort }}
   targetPort: {{ .Values.service.metricsPort }}
```

**`charts/sre-demo/templates/service-monitor.yaml`**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
 name: sre-demo-monitor
 labels:
  release: monitoring
spec:
 selector:
  matchLabels:
   app: sre-demo
 endpoints:
 - port: metrics
   path: /metrics
   interval: 15s
```

**`charts/sre-demo/templates/alert-rule.yaml`**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
 name: sre-demo-alerts
 labels:
  release: monitoring
spec:
 groups:
 - name: sre-demo.rules
   rules:
   - alert: HighErrorRate
     expr: rate(app_requests_total[5m]) < 0.9
     for: 2m
     labels:
      severity: page
     annotations:
      summary: "Service success rate < 90% for 2 minutes"
```

---

## 4. **Installation Commands**

```bash
# 1. Set Kubernetes context
kubectl config use-context orbstack
kubectl get nodes

# 2. Build Docker image
docker build -t sre-demo:latest .

# 3. Install monitoring stack (includes CRDs)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=120s

# 4. Uninstall old release and deploy app
helm uninstall sre-demo || true
helm install sre-demo ./charts/sre-demo --set image.pullPolicy=Never
kubectl rollout status deployment/sre-demo

# 5. Apply custom monitoring
kubectl apply -f charts/sre-demo/templates/service-monitor.yaml
kubectl apply -f charts/sre-demo/templates/alert-rule.yaml

# 6. Port-forward services
# Grafana on host port 8080
kubectl port-forward svc/monitoring-grafana 8080:80 -n monitoring &
# App on host port 8081
kubectl port-forward svc/sre-demo 8081:80 &
# Prometheus on host port 9090
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring &
```

Visit

* App health at [http://localhost:8081/health](http://localhost:8081/health)
* Metrics at [http://localhost:8081/metrics](http://localhost:8081/metrics)
* Grafana at [http://localhost:8080](http://localhost:8080) (user: admin, password from secret)
* Get Grafana 'admin' user password by running:
```bash
kubectl --namespace monitoring get secrets monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```
* Prometheus at [http://localhost:9090/targets](http://localhost:9090/targets)

---

## 5. **Cleanup**

```bash
# Kill background port-forwards
pkill -f "kubectl port-forward"

# Remove Helm releases
helm uninstall sre-demo
helm uninstall monitoring -n monitoring

# Delete Kubernetes resources
kubectl delete -n monitoring namespace monitoring --ignore-not-found
kubectl delete svc sre-demo deployment sre-demo --ignore-not-found

# Remove Docker images
docker rm -f sre-demo || true
docker rmi sre-demo:latest || true
```
