#!/bin/bash
# Crée la CA interne et le certificat du registre (SAN registry.local)
set -e
cd "$(dirname "$0")"
mkdir -p certs

# la CA
openssl genrsa -out certs/ca.key 4096
openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days 3650 \
  -subj "/O=Shop SAS/CN=Shop SAS CA" -out certs/ca.crt

# clé + demande de certificat pour le serveur
openssl genrsa -out certs/registry.key 2048
openssl req -new -key certs/registry.key -subj "/O=Shop SAS/CN=registry.local" -out certs/registry.csr

# le SAN doit être dans un fichier d'extension
cat > certs/san.ext <<EOF
subjectAltName = DNS:registry.local, DNS:registry, DNS:localhost, IP:127.0.0.1
EOF

openssl x509 -req -in certs/registry.csr -CA certs/ca.crt -CAkey certs/ca.key \
  -CAcreateserial -out certs/registry.crt -days 365 -sha256 -extfile certs/san.ext

# vérification
openssl verify -CAfile certs/ca.crt certs/registry.crt
openssl x509 -in certs/registry.crt -noout -ext subjectAltName
