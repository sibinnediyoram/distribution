#!/bin/bash
# Make sure that the local machine have helm installed
# Function to check command success
set -euo pipefail

# Config
CLUSTER_NAME="sibin-mini-cluster"
NAMESPACES=("vikunja" "monitoring")
MODE="${1:-full}"

# Helper functions
cluster_exists() {
  kind get clusters | grep -q "^${CLUSTER_NAME}$"
}

reset_namespace() {
  local ns=$1
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    kubectl delete namespace "$ns"
    kubectl wait --for=condition=Active=False namespace "$ns" --timeout=120s || true
  fi
  kubectl create namespace "$ns"
}


# Cluster setup
if [[ "$MODE" == "full" ]]; then
  if cluster_exists; then
    echo "▶ kind cluster '${CLUSTER_NAME}' already exists, skipping creation"
  else
    echo "▶ Creating kind cluster: ${CLUSTER_NAME}"
    kind create cluster --name "${CLUSTER_NAME}" --config cluster/kind-config.yaml
  fi
fi

# Deploy Ingress Controller
if [[ "$MODE" == "full" ]]; then
  echo "▶ Deploying ingress-nginx"
  kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
  kubectl rollout status deployment ingress-nginx-controller \
    -n ingress-nginx --timeout=180s
fi

# Namespace
if [[ "$MODE" == "reset" ]]; then
  for ns in "${NAMESPACES[@]}"; do
    reset_namespace "$ns"
  done
  echo "▶ Namespaces reset complete"
  exit 0
fi

echo "▶ Ensuring namespaces exist: '${NAMESPACES[@]}'"
for ns in "${NAMESPACES[@]}"; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# Helm repos
echo "Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo " Deploying applications..."

# Application stack (Vikunja)
echo " Deploying PostgreSQL..."
helm upgrade --install vikunja-db bitnami/postgresql -n vikunja -f vikunja-db/values.yaml

# Keycloak
echo " Deploying Keycloak..."
helm upgrade --install keycloak bitnami/keycloak -n vikunja -f keycloak/values.yaml

echo " Waiting for Keycloak to be ready"
kubectl rollout status statefulset keycloak -n vikunja --timeout=180s

# Vikunja frontend
echo " Deploying Vikunja frontend..."
helm upgrade --install vikunja-frontend vikunja-frontend -n vikunja -f vikunja-frontend/values.yaml

# Resolve Keycloak Service IP
echo " update hostalias ip for keycloak service in backend app pod"
#sed -i.bak -E "s/ip: \"[0-9\.]+\"/ip: \"${KC_IP}\"/" vikunja-backend/values.yaml

# Vikunja Backend
echo " Deploying backend app"
KC_IP=$(kubectl get svc keycloak -n vikunja -o jsonpath='{.spec.clusterIP}')
echo "  Keycloak ClusterIP: ${KC_IP}"
helm upgrade --install vikunja-backend vikunja-backend -n vikunja -f vikunja-backend/values.yaml --set "hostAliases[0].ip=${KC_IP}"

# Deploy Metrics Server
echo " Deploying metrics-server and monitoring apps"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}
  ]'

#deploy monitoring stack
helm upgrade --install prometheus prometheus-community/prometheus -n monitoring -f monitoring/prometheus-values.yaml --wait --timeout 180s
helm upgrade --install grafana bitnami/grafana -n monitoring -f monitoring/grafana-values.yaml --timeout=120s

# Output info
echo
echo " Print grafana admin password"
kubectl get secret -n monitoring grafana-admin -o jsonpath="{.data.GF_SECURITY_ADMIN_PASSWORD}" | base64 --decode

echo
#dashboard setup
kubectl create configmap vikunja-dashboards --from-file=vikunja-backend.json=monitoring/dashboard.json -n monitoring

echo
echo "✅ Deployment completed successfully"
echo
echo "Add to /etc/hosts: 127.0.0.1 vikunja.local keycloak.local"
echo "All operations completed successfully!"
echo
echo "Usage:"
echo "  ./deploy.sh        # full install"
echo "  ./deploy.sh apps   # redeploy apps only"
echo "  ./deploy.sh reset  # reset namespaces"

# Run below command after full setup
# kubectl create configmap vikunja-dashboards --from-file=vikunja-backend.json=monitoring/dashboard.json -n monitoring
