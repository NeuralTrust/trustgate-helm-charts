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

# Check if firewall should be enabled
if [ -n "$ENABLE_FIREWALL" ] && [ "$ENABLE_FIREWALL" = "true" ]; then
  echo -e "${GREEN}Firewall component will be enabled${NC}"
  FIREWALL_ENABLED="--set firewall.enabled=true"
  
  # Set default Google Artifact Registry server if not provided
  REGISTRY_SERVER=${REGISTRY_SERVER:-"us-docker.pkg.dev"}
  
  # Check if Google service account JSON key file is provided
  if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ] && [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo -e "${GREEN}Using Google service account credentials from $GOOGLE_APPLICATION_CREDENTIALS${NC}"
    # Create secret from the JSON key file
    kubectl create secret docker-registry gcp-registry-creds \
      --docker-server=$REGISTRY_SERVER \
      --docker-username=_json_key \
      --docker-password="$(cat $GOOGLE_APPLICATION_CREDENTIALS)" \
      --docker-email=${REGISTRY_EMAIL:-"user@example.com"} \
      --namespace=$NAMESPACE \
      --dry-run=client -o yaml | kubectl apply -f -
    
    REGISTRY_CREDS="--set firewall.image.pullSecrets[0].name=gcp-registry-creds"
  else
    # Prompt for Google service account JSON key file if not provided
    echo -e "${YELLOW}Google service account JSON key file not provided via GOOGLE_APPLICATION_CREDENTIALS${NC}"
    echo -e "${YELLOW}The firewall component requires a Google service account JSON key file from NeuralTrust${NC}"
    echo -e "${YELLOW}Please contact NeuralTrust support to obtain the required service account credentials${NC}"
    read -p "Do you have a service account JSON key file provided by NeuralTrust? (y/n): " PROVIDE_CREDS
    
    if [[ "$PROVIDE_CREDS" =~ ^[Yy]$ ]]; then
      read -p "Enter the path to the NeuralTrust-provided service account JSON key file: " JSON_KEY_PATH
      
      if [ -f "$JSON_KEY_PATH" ]; then
        echo -e "${GREEN}Creating secret from Google service account JSON key file${NC}"
        kubectl create secret docker-registry gcp-registry-creds \
          --docker-server=$REGISTRY_SERVER \
          --docker-username=_json_key \
          --docker-password="$(cat $JSON_KEY_PATH)" \
          --docker-email=${REGISTRY_EMAIL:-"user@example.com"} \
          --namespace=$NAMESPACE \
          --dry-run=client -o yaml | kubectl apply -f -
        
        REGISTRY_CREDS="--set firewall.image.pullSecrets[0].name=gcp-registry-creds"
      else
        echo -e "${RED}Error: File $JSON_KEY_PATH not found${NC}"
        echo -e "${YELLOW}Continuing without Google Artifact Registry credentials. Firewall component may fail to pull images.${NC}"
        echo -e "${YELLOW}Please contact NeuralTrust support to obtain the required service account credentials.${NC}"
      fi
    else
      echo -e "${YELLOW}Continuing without Google Artifact Registry credentials. Firewall component may fail to pull images.${NC}"
      echo -e "${YELLOW}Please contact NeuralTrust support to obtain the required service account credentials.${NC}"
    fi
  fi
  
  # Handle Hugging Face API key for firewall model
  if [ -n "$HUGGINGFACE_API_KEY" ]; then
    echo -e "${GREEN}Using provided Hugging Face API key for firewall model${NC}"
    HF_API_KEY=$HUGGINGFACE_API_KEY
  else
    echo -e "${YELLOW}Hugging Face API key not provided via HUGGINGFACE_API_KEY environment variable${NC}"
    echo -e "${YELLOW}The firewall component requires a Hugging Face API key to download models${NC}"
    read -p "Do you have a Hugging Face API key? (y/n): " PROVIDE_HF_KEY
    
    if [[ "$PROVIDE_HF_KEY" =~ ^[Yy]$ ]]; then
      read -p "Enter your Hugging Face API key: " HF_API_KEY
      if [ -z "$HF_API_KEY" ]; then
        echo -e "${RED}Error: No API key provided${NC}"
        echo -e "${YELLOW}Continuing without Hugging Face API key. Firewall component may fail to download models.${NC}"
      fi
    else
      echo -e "${YELLOW}Continuing without Hugging Face API key. Firewall component may fail to download models.${NC}"
    fi
  fi
  
  # Create Hugging Face API key secret if we have a key
  if [ -n "$HF_API_KEY" ]; then
    echo -e "${GREEN}Creating Hugging Face API key secret${NC}"
    kubectl create secret generic hf-api-key \
      --from-literal=api-key=$HF_API_KEY \
      --namespace=$NAMESPACE \
      --dry-run=client -o yaml | kubectl apply -f -
    
    HUGGINGFACE_SECRET="--set firewall.huggingface.apiKeySecret=hf-api-key"
  fi
else
  echo -e "${YELLOW}Firewall component will be disabled${NC}"
  FIREWALL_ENABLED="--set firewall.enabled=false"
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
  $CERT_MANAGER_ENABLED \
  $FIREWALL_ENABLED \
  ${REGISTRY_CREDS:-""} \
  ${HUGGINGFACE_SECRET:-""}

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
