#!/bin/bash
set -e

# Define color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# variables
OBSERVABILITY_NAMESPACE="observability"

echo -e "${BLUE}================================${NC}"
echo -e "${GREEN} Deployment Script${NC}"
echo -e "${BLUE}================================${NC}"


# Create cluster
echo -e "${BLUE}Creating cluster...${NC}"
if ! kind get clusters | grep -q "build-and-run"; then
  kind create cluster --config kind/cluster.yaml
else
  echo -e "${GREEN}Cluster 'build-and-run' already exists, skipping creation${NC}"
fi

# Update kubeconfig kind cluster
kubectl cluster-info --context kind-build-and-run

# Create namespaces
echo -e "${BLUE}Creating namespaces...${NC}"

# Create namespaces echo -e "${BLUE}Creating namespaces...${NC}"
kubectl create namespace $OBSERVABILITY_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repositories
echo -e "${BLUE}Adding Helm repositories...${NC}"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add victoria-metrics https://victoriametrics.github.io/helm-charts/
helm repo update

# Deploy Metrics Server
echo -e "${BLUE}Deploying Metrics Server...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

echo -e "${BLUE}Deploying kube-state-metrics...${NC}"

helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics -n $OBSERVABILITY_NAMESPACE

echo -e "${BLUE}Deploying VictoriaMetrics...${NC}"
helm upgrade --install vmsingle vm/victoria-metrics-single \
  --namespace $OBSERVABILITY_NAMESPACE \
  --values kubernetes/helm-values/vmsingle-values.yaml

# Deploy vmagent
echo -e "${BLUE}Deploying vmagent...${NC}"
helm upgrade --install vmagent vm/victoria-metrics-agent \
  --namespace $OBSERVABILITY_NAMESPACE \
  --values kubernetes/helm-values/vmagent-values.yaml

# Deploy vmalert
echo -e "${BLUE}Deploying vmalert...${NC}"
helm upgrade --install vmalert vm/victoria-metrics-alert \
  --namespace $OBSERVABILITY_NAMESPACE \
  --values kubernetes/helm-values/vmalert-values.yaml \
  --timeout 5m

# Deploy Alertmanager
echo -e "${BLUE}Deploying Alertmanager...${NC}"
helm upgrade --install alertmanager prometheus-community/alertmanager \
  --namespace $OBSERVABILITY_NAMESPACE \
  --values kubernetes/helm-values/alertmanager-values.yaml \
  --timeout 5m \
  --wait

#Deploy Grafana
echo -e "${BLUE}Deploying Grafana...${NC}"
helm upgrade --install grafana grafana/grafana \
  --namespace $OBSERVABILITY_NAMESPACE \
  --values kubernetes/helm-values/grafana-values.yaml

#Deploy Loki
echo -e "${BLUE}Deploying Loki...${NC}"
helm upgrade --install loki grafana/loki \
  --namespace $OBSERVABILITY_NAMESPACE \
  --values kubernetes/helm-values/loki-values.yaml \
  --timeout 5m

echo -e "${BLUE}Deploying Promtail...${NC}"
helm upgrade --install promtail grafana/promtail \
  --namespace $OBSERVABILITY_NAMESPACE \
  --values kubernetes/helm-values/promtail-values.yaml

echo -e "${BLUE}Deploying workload...${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}Creating customers namespaces...${NC}"
# Create namespaces
echo -e "${BLUE}Creating namespaces...${NC}"

# Create customer namespaces
echo -e "${BLUE}Creating customer namespaces...${NC}"
CUSTOMER_NAMESPACES=("ns-52327214" "ns-48414609" "ns-94714545")

for ns in "${CUSTOMER_NAMESPACES[@]}"; do
  echo -e "${GREEN}Creating namespace: $ns${NC}"
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done

# Deploy application components to each namespace
echo -e "${BLUE}Deploying trouble-box application components to each namespace...${NC}"

# Use raw GitHub content URLs for direct access to manifests
REPO_URL="https://raw.githubusercontent.com/rmnobarra/trouble-box/main/k8s"
MANIFESTS=("deployment.yaml" "service.yaml" "orders-pv.yaml" "orders-pvc.yaml" "cleanup-cronjob.yaml")

# Loop through each namespace and apply manifests
for ns in "${CUSTOMER_NAMESPACES[@]}"; do
  echo -e "${BLUE}Deploying applications to namespace: $ns${NC}"
  
  for manifest in "${MANIFESTS[@]}"; do
    echo -e "${GREEN}Applying $manifest to namespace $ns...${NC}"
    if ! kubectl apply -f "$REPO_URL/$manifest" -n "$ns"; then
      echo -e "${RED}Failed to apply $manifest to namespace $ns${NC}"
      # Continue with other manifests instead of exiting
    fi
  done
  
  echo -e "${GREEN}Deployment completed for namespace $ns${NC}"
done

echo -e "${GREEN}All workloads deployed successfully to all namespaces${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}To access all services at once, use:${NC}"
echo -e "${BLUE}./port-forward.sh${NC}"
echo -e "${GREEN}To stop all port forwards, press CTRL+C or run:${NC}"
echo -e "${BLUE}./cleanup-forwards.sh${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}Grafana credentials: "
GRAFANA_USER=$(kubectl get secret --namespace $OBSERVABILITY_NAMESPACE grafana -o jsonpath="{.data.admin-user}" | base64 --decode)
GRAFANA_PASS=$(kubectl get secret --namespace $OBSERVABILITY_NAMESPACE grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
echo -e "${GREEN}Username: $GRAFANA_USER / Password: $GRAFANA_PASS${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}Available services:${NC}"
echo -e "${GREEN}Grafana:        http://localhost:3000${NC}"
echo -e "${GREEN}VictoriaMetrics: http://localhost:8428${NC}"
echo -e "${GREEN}VMAlert:        http://localhost:8880${NC}"
echo -e "${GREEN}Alertmanager:   http://localhost:9093${NC}"
echo -e "${GREEN}Trouble-Box 1:  http://localhost:8000${NC}"
echo -e "${GREEN}Trouble-Box 2:  http://localhost:8001${NC}"
echo -e "${GREEN}Trouble-Box 3:  http://localhost:8002${NC}"
