#!/bin/bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

# Default values
HOSTNAME=${1:-creative-studio.dev.corp.example.com}
PROJECT_ID=${2:-ravi-argolis-01}

echo "Generating self-signed certificate for hostname: $HOSTNAME"

# 1. Generate private key
openssl genrsa -out tls.key 2048

# 2. Create a config file for the CSR with SAN
cat > san.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $HOSTNAME
[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = $HOSTNAME
EOF

# 3. Generate self-signed certificate (valid 1 year)
openssl req -new -x509 -sha256 -key tls.key -out tls.crt \
  -days 365 -config san.conf -extensions v3_req

echo "✅ Certificate generated successfully: tls.crt and tls.key"
echo ""
echo "To upload these to Secret Manager in project '$PROJECT_ID', run the following commands:"
echo "--------------------------------------------------------------------------------"
echo "gcloud secrets create creative-studio-dev-tls-crt --replication-policy=automatic --data-file=./tls.crt --project=$PROJECT_ID"
echo "gcloud secrets create creative-studio-dev-tls-key --replication-policy=automatic --data-file=./tls.key --project=$PROJECT_ID"
echo "--------------------------------------------------------------------------------"

# Cleanup temp config file
rm san.conf
