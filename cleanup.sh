#!/usr/bin/env bash
set -e
kubectl delete -f k8s/alert-rule.yaml
kubectl delete -f k8s/service-monitor.yaml
kubectl delete -f k8s/deployment.yaml -f k8s/service.yaml
helm uninstall grafana
helm uninstall prometheus
kind delete cluster --name sre-demo
docker rm -f sre-demo || true
docker image rm sre-demo:v1 || true
