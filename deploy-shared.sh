#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Set environment variables
NAMESPACE="trustgate-shared"
RELEASE_NAME="trustgate-shared"

echo -e "${GREEN}Deploying shared TrustGate infrastructure...${NC}"

# Check if Prometheus Operator CRDs are installed
if kubectl get crd servicemonitors.monitoring.coreos.com > /dev/null 2>&1; then
  echo -e "${GREEN}Prometheus Operator CRDs found, enabling ServiceMonitor${NC}"
  MONITORING_ENABLED="--set monitoring.serviceMonitor.enabled=true"
else
  echo -e "${YELLOW}Prometheus Operator CRDs not found, disabling ServiceMonitor${NC}"
  MONITORING_ENABLED="--set monitoring.serviceMonitor.enabled=false"
fi

# Check if cert-manager CRDs are installed
if kubectl get crd certificates.cert-manager.io > /dev/null 2>&1; then
  echo -e "${GREEN}cert-manager CRDs found, enabling Certificate resources${NC}"
  CERT_MANAGER_ENABLED="--set certManager.enabled=true"
else
  echo -e "${YELLOW}cert-manager CRDs not found, disabling Certificate resources${NC}"
  echo -e "${YELLOW}To enable TLS certificate management, install cert-manager:${NC}"
  echo -e "${YELLOW}kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml${NC}"
  CERT_MANAGER_ENABLED="--set certManager.enabled=false"
fi

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create required secrets
echo -e "\n${GREEN}Creating required secrets...${NC}"

# Handle PostgreSQL password
if [ -f pg_credentials.txt ]; then
    echo -e "${GREEN}Using existing PostgreSQL password from pg_credentials.txt${NC}"
    PG_PASSWORD=$(grep "PostgreSQL Password:" pg_credentials.txt | cut -d' ' -f3)
else
    echo -e "${GREEN}Generating new PostgreSQL password${NC}"
    PG_PASSWORD=$(openssl rand -hex 16)
    echo "PostgreSQL Password: $PG_PASSWORD" > pg_credentials.txt
fi

# Handle Redis password
if [ -f redis_credentials.txt ]; then
    echo -e "${GREEN}Using existing Redis password from redis_credentials.txt${NC}"
    REDIS_PASSWORD=$(grep "Redis Password:" redis_credentials.txt | cut -d' ' -f3)
else
    echo -e "${GREEN}Generating new Redis password${NC}"
    REDIS_PASSWORD=$(openssl rand -hex 16)
    echo "Redis Password: $REDIS_PASSWORD" > redis_credentials.txt
fi

# Deploy using Helm with shared configuration
echo -e "\n${GREEN}Deploying TrustGate using Helm...${NC}"
helm upgrade --install $RELEASE_NAME . \
  --namespace $NAMESPACE \
  --set postgresql.auth.password=$PG_PASSWORD \
  --set postgresql.auth.username=trustgate \
  --set postgresql.auth.database=trustgate \
  --set redis.auth.password=$REDIS_PASSWORD \
  --set ingress.enabled=true \
  $MONITORING_ENABLED \
  $CERT_MANAGER_ENABLED

# Wait for pods to be ready
echo -e "\n${GREEN}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod \
  --selector app.kubernetes.io/instance=$RELEASE_NAME \
  --namespace $NAMESPACE \
  --timeout=300s

# Show deployment status
echo -e "\n${GREEN}Deployment Status:${NC}"
kubectl get pods -n $NAMESPACE

echo -e "\n${GREEN}Shared TrustGate infrastructure deployed successfully!${NC}"
echo -e "You can now register gateways using the API at https://admin.neuraltrust.ai" 
