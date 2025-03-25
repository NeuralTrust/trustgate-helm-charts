#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check for required commands
for cmd in kubectl helm openssl base64 jq; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${RED}Error: $cmd is not installed. Please install it to continue.${NC}"
    exit 1
  fi
done

# Set environment variables
NAMESPACE="trustgate"
RELEASE_NAME="trustgate"

echo -e "${GREEN}Deploying TrustGate infrastructure...${NC}"

# Load environment variables from .env file if it exists
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
  echo -e "${GREEN}Loading environment variables from $ENV_FILE${NC}"
  export $(grep -v '^#' $ENV_FILE | xargs)
else
  echo -e "${YELLOW}No .env file found at $ENV_FILE, using default values${NC}"
fi

# Check if ingress should be enabled
if [ -n "$ENABLE_INGRESS" ] && [ "$ENABLE_INGRESS" = "true" ]; then
  echo -e "${GREEN}Ingress will be enabled${NC}"
  INGRESS_ENABLED="--set ingress.enabled=true"
else
  echo -e "${YELLOW}Ingress will be disabled (default)${NC}"
  INGRESS_ENABLED="--set ingress.enabled=false"
fi

# Check if firewall should be enabled
if [ -n "$ENABLE_FIREWALL" ] && [ "$ENABLE_FIREWALL" = "true" ] || [ -n "$ENABLE_MODERATION" ] && [ "$ENABLE_MODERATION" = "true" ]; then
  echo -e "${GREEN}Firewall component will be enabled${NC}"
  
  # Check for Google service account credentials
  if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ] || [ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo -e "${YELLOW}Google service account credentials not found or invalid${NC}"
    echo -e "${YELLOW}The firewall component requires a Google service account JSON key file${NC}"
    
    # Prompt for credentials
    read -p "Do you have a Google service account JSON key file? (y/n): " HAVE_CREDS
    if [[ "$HAVE_CREDS" =~ ^[Yy]$ ]]; then
      read -p "Enter the path to your Google service account JSON key file: " JSON_KEY_PATH
      if [ -f "$JSON_KEY_PATH" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$JSON_KEY_PATH"
      else
        echo -e "${RED}ERROR: File $JSON_KEY_PATH not found${NC}"
        echo -e "${RED}Firewall component requires valid Google service account credentials${NC}"
        echo -e "${RED}Contact NeuralTrust support to obtain the required credentials${NC}"
        exit 1
      fi
    else
      echo -e "${RED}ERROR: Firewall component requires Google service account credentials${NC}"
      echo -e "${RED}Contact NeuralTrust support to obtain the required credentials${NC}"
      exit 1
    fi
  fi
  
  # Check for Hugging Face API key
  if [ -z "$HUGGINGFACE_TOKEN" ] && [ -z "$HF_API_KEY" ]; then
    echo -e "${YELLOW}Hugging Face API key not found${NC}"
    echo -e "${YELLOW}The firewall component requires a Hugging Face API key to download models${NC}"
    
    # Prompt for API key
    read -p "Do you have a Hugging Face API key? (y/n): " HAVE_KEY
    if [[ "$HAVE_KEY" =~ ^[Yy]$ ]]; then
      read -p "Enter your Hugging Face API key: " HF_API_KEY
      if [ -z "$HF_API_KEY" ]; then
        echo -e "${RED}ERROR: No API key provided${NC}"
        echo -e "${RED}Firewall component requires a valid Hugging Face API key${NC}"
        exit 1
      fi
    else
      echo -e "${RED}ERROR: Firewall component requires a Hugging Face API key${NC}"
      echo -e "${RED}You can get one from https://huggingface.co/settings/tokens${NC}"
      exit 1
    fi
  fi
  
  if [ -n "$ENABLE_MODERATION" ] && [ "$ENABLE_MODERATION" = "true" ]; then
    echo -e "${GREEN}Moderation component will be enabled${NC}"
    MODERATION_ENABLED="--set moderation.enabled=true"
  else
    echo -e "${YELLOW}Moderation component will be disabled${NC}"
    MODERATION_ENABLED="--set moderation.enabled=false"
  fi
  if [ -n "$ENABLE_FIREWALL" ] && [ "$ENABLE_FIREWALL" = "true" ]; then
    echo -e "${GREEN}Firewall component will be enabled${NC}"
    FIREWALL_ENABLED="--set firewall.enabled=true"
  else
    echo -e "${YELLOW}Firewall component will be disabled${NC}"
    FIREWALL_ENABLED="--set firewall.enabled=false"
  fi
else
  echo -e "${YELLOW}Firewall component will be disabled${NC}"
  FIREWALL_ENABLED="--set firewall.enabled=false"
  MODERATION_ENABLED="--set moderation.enabled=false"
fi

# Check if Prometheus Operator CRDs are installed
if kubectl get crd servicemonitors.monitoring.coreos.com > /dev/null 2>&1; then
  echo -e "${GREEN}Prometheus Operator CRDs found, enabling ServiceMonitor${NC}"
  MONITORING_ENABLED="--set monitoring.serviceMonitor.enabled=true"
else
  echo -e "${YELLOW}Prometheus Operator CRDs not found, disabling ServiceMonitor${NC}"
  MONITORING_ENABLED="--set monitoring.serviceMonitor.enabled=false"
fi

# Check if cert-manager should be enabled
if [ -z "$ENABLE_INGRESS" ] || [ "$ENABLE_INGRESS" != "true" ]; then
  echo -e "${YELLOW}Ingress is disabled, disabling cert-manager integration${NC}"
  CERT_MANAGER_ENABLED="--set certManager.enabled=false"
else
  # Only check for cert-manager if ingress is enabled
  if kubectl get crd certificates.cert-manager.io > /dev/null 2>&1; then
    echo -e "${GREEN}cert-manager CRDs found, enabling Certificate resources${NC}"
    CERT_MANAGER_ENABLED="--set certManager.enabled=true"
  else
    echo -e "${YELLOW}cert-manager CRDs not found, disabling Certificate resources${NC}"
    echo -e "${YELLOW}To enable TLS certificate management, install cert-manager:${NC}"
    echo -e "${YELLOW}kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml${NC}"
    CERT_MANAGER_ENABLED="--set certManager.enabled=false"
  fi
fi

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create .secret directory if it doesn't exist
mkdir -p .secret

# Create required secrets
echo -e "\n${GREEN}Creating required secrets...${NC}"

# Handle PostgreSQL password
if [ -f .secret/pg_credentials.txt ]; then
    echo -e "${GREEN}Using existing PostgreSQL password from .secret/pg_credentials.txt${NC}"
    PG_PASSWORD=$(grep "PostgreSQL Password:" .secret/pg_credentials.txt | cut -d' ' -f3)
else
    echo -e "${GREEN}Generating new PostgreSQL password${NC}"
    PG_PASSWORD=$(openssl rand -hex 16)
    echo "PostgreSQL Password: $PG_PASSWORD" > .secret/pg_credentials.txt
fi

# Handle Redis password
if [ -f .secret/redis_credentials.txt ]; then
    echo -e "${GREEN}Using existing Redis password from .secret/redis_credentials.txt${NC}"
    REDIS_PASSWORD=$(grep "Redis Password:" .secret/redis_credentials.txt | cut -d' ' -f3)
else
    echo -e "${GREEN}Generating new Redis password${NC}"
    REDIS_PASSWORD=$(openssl rand -hex 16)
    echo "Redis Password: $REDIS_PASSWORD" > .secret/redis_credentials.txt
fi

# Set default values for environment variables if not set
LOG_LEVEL=${LOG_LEVEL:-"info"}
SERVER_BASE_DOMAIN=${SERVER_BASE_DOMAIN:-"example.com"}
SERVER_ADMIN_PORT=${SERVER_ADMIN_PORT:-"8080"}
SERVER_METRICS_PORT=${SERVER_METRICS_PORT:-"9090"}
SERVER_PROXY_PORT=${SERVER_PROXY_PORT:-"8081"}
DATABASE_HOST=${DATABASE_HOST:-"trustgate-postgresql.$NAMESPACE.svc.cluster.local"}
DATABASE_PORT=${DATABASE_PORT:-"5432"}
DATABASE_USER=${DATABASE_USER:-"trustgate"}
DATABASE_PASSWORD=${DATABASE_PASSWORD:-$PG_PASSWORD}
DATABASE_NAME=${DATABASE_NAME:-"trustgate"}
DATABASE_SSL_MODE=${DATABASE_SSL_MODE:-"disable"}
REDIS_HOST=${REDIS_HOST:-"trustgate-redis-headless.$NAMESPACE.svc.cluster.local"}
REDIS_PORT=${REDIS_PORT:-"6379"}
REDIS_PASSWORD=${REDIS_PASSWORD:-$REDIS_PASSWORD}
REDIS_DB=${REDIS_DB:-"0"}

# If firewall is enabled, set up the required secrets
if [ -n "$ENABLE_FIREWALL" ] && [ "$ENABLE_FIREWALL" = "true" ]; then
  # Set default Google Artifact Registry server if not provided
  REGISTRY_SERVER=${REGISTRY_SERVER:-"europe-west1-docker.pkg.dev"}
  
  # Create secret from the Google service account JSON key file
  echo -e "${GREEN}Creating Google service account credentials secret${NC}"
  kubectl create secret docker-registry gcp-registry-creds \
    --docker-server=$REGISTRY_SERVER \
    --docker-username=_json_key \
    --docker-password="$(cat $GOOGLE_APPLICATION_CREDENTIALS)" \
    --docker-email=${REGISTRY_EMAIL:-"admin@neuraltrust.ai"} \
    --namespace=$NAMESPACE \
    --dry-run=client -o yaml | kubectl apply -f -
  
  REGISTRY_CREDS="--set global.image.imagePullSecrets[0].name=gcp-registry-creds"
  
  # Create Hugging Face API key secret
  HF_KEY=${HUGGINGFACE_TOKEN:-$HF_API_KEY}
  echo -e "${GREEN}Creating Hugging Face API key secret${NC}"
  kubectl create secret generic hf-api-key \
    --from-literal=HUGGINGFACE_TOKEN=$HF_KEY \
    --namespace=$NAMESPACE \
    --dry-run=client -o yaml | kubectl apply -f -
  
  HUGGINGFACE_SECRET="--set global.huggingface.apiKeySecret=hf-api-key"
  
  # Generate JWT secret for firewall API
  if [ -f .secret/firewall_jwt_credentials.txt ]; then
    echo -e "${GREEN}Using existing JWT secret from .secret/firewall_jwt_credentials.txt${NC}"
    JWT_SECRET=$(grep "JWT Secret:" .secret/firewall_jwt_credentials.txt | cut -d' ' -f3)
    JWT_TOKEN=$(grep "JWT Token:" .secret/firewall_jwt_credentials.txt | cut -d' ' -f3)
  else
    echo -e "${GREEN}Generating new JWT secret for firewall API${NC}"
    
    # Use a more portable way to generate random hex
    if ! command -v openssl &> /dev/null; then
      # Fallback if openssl is not available
      random_hex() {
        head -c $1 /dev/urandom | xxd -p
      }
      JWT_SECRET=$(random_hex 32)
    else
      JWT_SECRET=$(openssl rand -hex 32)
    fi
    
    # Generate a JWT header
    JWT_HEADER_JSON='{"alg":"HS256","typ":"JWT"}'
    JWT_HEADER=$(echo -n "$JWT_HEADER_JSON" | base64 | tr '/+' '_-' | tr -d '=')

    # Calculate expiration time (current time + 30 days in seconds)
    CURRENT_TIME=$(date +%s)
    EXPIRATION_TIME=$((CURRENT_TIME + 2592000))  # 30 days = 2592000 seconds

    # Create the JWT payload
    JWT_PAYLOAD_JSON='{"purpose":"firewall","name":"TrustGate","iat":'$CURRENT_TIME',"exp":'$EXPIRATION_TIME'}'
    JWT_PAYLOAD=$(echo -n "$JWT_PAYLOAD_JSON" | base64 | tr '/+' '_-' | tr -d '=')

    # Create the signature
    JWT_SIGNATURE=$(echo -n "${JWT_HEADER}.${JWT_PAYLOAD}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 | tr '/+' '_-' | tr -d '=')
    JWT_TOKEN="${JWT_HEADER}.${JWT_PAYLOAD}.${JWT_SIGNATURE}"

    # Debug output - make compatible with both Linux and macOS
    echo -e "${GREEN}JWT Token generated with expiration in 30 days${NC}"

    # Use a cross-platform way to display dates
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      echo -e "${GREEN}Current time: $(date -r $CURRENT_TIME)${NC}"
      echo -e "${GREEN}Expiration time: $(date -r $EXPIRATION_TIME)${NC}"
    else
      # Linux and others
      echo -e "${GREEN}Current time: $(date --date="@$CURRENT_TIME")${NC}"
      echo -e "${GREEN}Expiration time: $(date --date="@$EXPIRATION_TIME")${NC}"
    fi

    echo -e "${GREEN}JWT Header: $JWT_HEADER_JSON${NC}"
    echo -e "${GREEN}JWT Payload: $JWT_PAYLOAD_JSON${NC}"
    
    echo "JWT Secret: $JWT_SECRET" > .secret/firewall_jwt_credentials.txt
    echo "JWT Token: $JWT_TOKEN" >> .secret/firewall_jwt_credentials.txt
  fi
  
  # Create JWT secret for firewall API
  echo -e "${GREEN}Creating JWT secret for firewall API${NC}"
  kubectl create secret generic firewall-jwt-secret \
    --from-literal=JWT_SECRET=$JWT_SECRET \
    --namespace=$NAMESPACE \
    --dry-run=client -o yaml | kubectl apply -f -
  
  # Save the token to be displayed in NOTES.txt
  JWT_TOKEN_FOR_NOTES=$JWT_TOKEN
fi

# Create environment variables secret
echo -e "${GREEN}Creating environment variables secret...${NC}"
kubectl create secret generic ${RELEASE_NAME}-env-vars \
  --from-literal=LOG_LEVEL=$LOG_LEVEL \
  --from-literal=SERVER_BASE_DOMAIN=$SERVER_BASE_DOMAIN \
  --from-literal=SERVER_ADMIN_PORT=$SERVER_ADMIN_PORT \
  --from-literal=SERVER_METRICS_PORT=$SERVER_METRICS_PORT \
  --from-literal=SERVER_PROXY_PORT=$SERVER_PROXY_PORT \
  --from-literal=DATABASE_HOST=$DATABASE_HOST \
  --from-literal=DATABASE_PORT=$DATABASE_PORT \
  --from-literal=DATABASE_USER=$DATABASE_USER \
  --from-literal=DATABASE_PASSWORD=$DATABASE_PASSWORD \
  --from-literal=DATABASE_NAME=$DATABASE_NAME \
  --from-literal=DATABASE_SSL_MODE=$DATABASE_SSL_MODE \
  --from-literal=REDIS_HOST=$REDIS_HOST \
  --from-literal=REDIS_PORT=$REDIS_PORT \
  --from-literal=REDIS_PASSWORD=$REDIS_PASSWORD \
  --from-literal=REDIS_DB=$REDIS_DB \
  --namespace=$NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Deploy using Helm with configuration
echo -e "\n${GREEN}Deploying TrustGate using Helm...${NC}"
helm upgrade --install $RELEASE_NAME ./ \
  --namespace $NAMESPACE \
  --set postgresql.auth.password=$PG_PASSWORD \
  --set postgresql.auth.username=trustgate \
  --set postgresql.auth.database=trustgate \
  --set redis.auth.password=$REDIS_PASSWORD \
  $INGRESS_ENABLED \
  --set global.env.LOG_LEVEL=$LOG_LEVEL \
  --set global.env.SERVER_BASE_DOMAIN=$SERVER_BASE_DOMAIN \
  --set global.env.SERVER_ADMIN_PORT=$SERVER_ADMIN_PORT \
  --set global.env.SERVER_METRICS_PORT=$SERVER_METRICS_PORT \
  --set global.env.SERVER_PROXY_PORT=$SERVER_PROXY_PORT \
  --set global.env.DATABASE_HOST=$DATABASE_HOST \
  --set global.env.DATABASE_PORT=$DATABASE_PORT \
  --set global.env.DATABASE_USER=$DATABASE_USER \
  --set global.env.DATABASE_PASSWORD=$DATABASE_PASSWORD \
  --set global.env.DATABASE_NAME=$DATABASE_NAME \
  --set global.env.DATABASE_SSL_MODE=$DATABASE_SSL_MODE \
  --set global.env.REDIS_HOST=$REDIS_HOST \
  --set global.env.REDIS_PORT=$REDIS_PORT \
  --set global.env.REDIS_PASSWORD=$REDIS_PASSWORD \
  --set global.env.REDIS_DB=$REDIS_DB \
  $MONITORING_ENABLED \
  $CERT_MANAGER_ENABLED \
  $FIREWALL_ENABLED \
  $REGISTRY_CREDS

# Wait for pods to be ready
echo -e "\n${GREEN}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod \
  --selector app.kubernetes.io/instance=$RELEASE_NAME \
  --namespace $NAMESPACE \
  --timeout=300s

# Show deployment status
echo -e "\n${GREEN}Deployment Status:${NC}"
kubectl get pods -n $NAMESPACE

echo -e "\n${GREEN}TrustGate infrastructure deployed successfully!${NC}"

echo -e "\n${YELLOW}Services are deployed with ClusterIP. You can use port-forwarding to access them:${NC}"
echo -e "kubectl port-forward svc/${RELEASE_NAME}-control-plane -n ${NAMESPACE} 8080:80"
echo -e "kubectl port-forward svc/${RELEASE_NAME}-data-plane -n ${NAMESPACE} 8081:80"

if [ -n "$ENABLE_FIREWALL" ] && [ "$ENABLE_FIREWALL" = "true" ]; then
  echo -e "kubectl port-forward svc/${RELEASE_NAME}-firewall -n ${NAMESPACE} 8082:80"
fi

echo -e "\n${YELLOW}After port-forwarding, you can access the services at:${NC}"
echo -e "Admin API: http://localhost:8080/api/v1"
echo -e "Proxy API: http://localhost:8081"

if [ -n "$ENABLE_FIREWALL" ] && [ "$ENABLE_FIREWALL" = "true" ]; then
  echo -e "Firewall API: http://localhost:8082"
  
  echo -e "\n${GREEN}You can use the following command to test the firewall${NC}"
  echo -e "${GREEN}directly with curl to see how it works:${NC}"
  echo -e "${YELLOW}curl -s -w \"\\\nTime: %{time_total}\" \"http://localhost:8082/v1/firewall\" \\"
  echo -e " -H \"Authorization: Bearer $JWT_TOKEN_FOR_NOTES\" \\"
  echo -e " -H \"Content-Type: application/json\" \\"
  echo -e " -d '{\"input\":\"Test to scan for malicious content\"}'"
  echo -e "${GREEN}==================================================${NC}"
fi

# Generate test scripts section remains unchanged...