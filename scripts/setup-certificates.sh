#!/bin/bash

# Create directory for certificates if it doesn't exist
mkdir -p certs

# Generate admin certificate configuration
cat > certs/admin.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = admin.neuraltrust.ai

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
nsCertType = server

[alt_names]
DNS.1 = admin.neuraltrust.ai
EOF

# Generate gateway certificate configuration
cat > certs/gateway.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = *.gateway.neuraltrust.ai

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
nsCertType = server

[alt_names]
DNS.1 = *.gateway.neuraltrust.ai
DNS.2 = gateway.neuraltrust.ai
EOF

# Generate admin certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -sha256 \
  -keyout certs/admin.key -out certs/admin.crt \
  -config certs/admin.conf -extensions v3_req

# Generate gateway certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -sha256 \
  -keyout certs/gateway.key -out certs/gateway.crt \
  -config certs/gateway.conf -extensions v3_req

# Create values file with certificates
cat > custom-values.yaml << EOF
certManager:
  enabled: true
  customCertificates:
    enabled: true
    controlPlane:
      cert: |
$(cat certs/admin.crt | sed 's/^/        /')
      key: |
$(cat certs/admin.key | sed 's/^/        /')
    dataPlane:
      cert: |
$(cat certs/gateway.crt | sed 's/^/        /')
      key: |
$(cat certs/gateway.key | sed 's/^/        /')
EOF

# Merge with existing values
if [ -f values.yaml ]; then
  echo "Merging with existing values.yaml..."
  # Backup existing values
  cp values.yaml values.yaml.bak
  # Append custom values to existing file
  cat custom-values.yaml >> values.yaml
else
  echo "No existing values.yaml found, using generated values..."
  mv custom-values.yaml values.yaml
fi

echo "Certificates generated and values.yaml updated successfully!" 