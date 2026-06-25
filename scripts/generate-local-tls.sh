#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${ROOT_DIR}/docker/traefik/certs"
CERT_FILE="${CERT_DIR}/local.crt"
KEY_FILE="${CERT_DIR}/local.key"
OPENSSL_CONFIG="$(mktemp)"

cleanup() {
    rm -f "${OPENSSL_CONFIG}"
}

trap cleanup EXIT

mkdir -p "${CERT_DIR}"

cat > "${OPENSSL_CONFIG}" <<'EOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = laravel.localhost

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = laravel.localhost
DNS.2 = manager.localhost
DNS.3 = minio.localhost
DNS.4 = minio-console.localhost
DNS.5 = localhost
IP.1 = 127.0.0.1
EOF

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -config "${OPENSSL_CONFIG}"

chmod 600 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"

echo "Certificado local gerado em ${CERT_FILE}"
echo "Chave local gerada em ${KEY_FILE}"
