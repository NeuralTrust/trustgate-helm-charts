#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <SERVER_SECRET_KEY>"
  exit 1
fi

header=$(echo -n '{"alg":"HS256","typ":"JWT"}' | openssl base64 -A | tr '+/' '-_' | tr -d '=')
payload=$(echo -n '{}' | openssl base64 -A | tr '+/' '-_' | tr -d '=')
secret="$1"

signature=$(echo -n "$header.$payload" | openssl dgst -binary -sha256 -hmac "$secret" | openssl base64 -A | tr '+/' '-_' | tr -d '=')

echo "$header.$payload.$signature"