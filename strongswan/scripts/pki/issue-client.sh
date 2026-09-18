#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <client-id>" >&2
  exit 1
fi

CLIENT_ID="$1"

if ! printf '%s\n' "${CLIENT_ID}" |
  grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'
then
  echo "ERROR: invalid client ID: ${CLIENT_ID}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOMELAB_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"

CA_DIR="${HOMELAB_DIR}/secrets/pki/ca"
DB_DIR="${CA_DIR}/database"
CLIENT_DIR="${HOMELAB_DIR}/secrets/pki/clients/${CLIENT_ID}"

CONFIG="${DB_DIR}/openssl.cnf"
CA_CERT="${CA_DIR}/ca-cert.pem"
CA_KEY="${CA_DIR}/ca-key.pem"

KEY="${CLIENT_DIR}/${CLIENT_ID}-key.pem"
CSR="${CLIENT_DIR}/${CLIENT_ID}.csr.pem"
CERT="${CLIENT_DIR}/${CLIENT_ID}-cert.pem"

for f in \
  "${CONFIG}" \
  "${CA_CERT}" \
  "${CA_KEY}" \
  "${DB_DIR}/index.txt" \
  "${DB_DIR}/serial"
do
  if [ ! -f "${f}" ]; then
    echo "ERROR: required file not found: ${f}" >&2
    exit 1
  fi
done

if awk -F '\t'   -v subject="/CN=${CLIENT_ID}"   '$6 == subject { found=1 } END { exit !found }'   "${DB_DIR}/index.txt"
then
  echo "ERROR: client ID already exists in CA database: ${CLIENT_ID}" >&2
  exit 1
fi

if [ -e "${CLIENT_DIR}" ]; then
  echo "ERROR: client directory already exists: ${CLIENT_DIR}" >&2
  exit 1
fi

mkdir -m 700 "${CLIENT_DIR}"

EXTFILE="$(mktemp)"
cleanup() {
  rm -f "${EXTFILE}"
}
trap cleanup EXIT

cat > "${EXTFILE}" <<EXT
[ client_cert ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = DNS:${CLIENT_ID}
EXT

echo "Generating ECDSA P-384 private key..."

openssl ecparam \
  -name secp384r1 \
  -genkey \
  -noout \
  -out "${KEY}"

chmod 600 "${KEY}"

echo "Generating CSR..."

openssl req \
  -new \
  -key "${KEY}" \
  -subj "/CN=${CLIENT_ID}" \
  -out "${CSR}"

echo "Issuing client certificate..."

(
  cd "${DB_DIR}"

  openssl ca \
    -batch \
    -config ./openssl.cnf \
    -extfile "${EXTFILE}" \
    -extensions client_cert \
    -days 365 \
    -in "${CSR}" \
    -out "${CERT}"
)

chmod 644 "${CSR}" "${CERT}"

echo "Validating certificate..."

openssl verify \
  -CAfile "${CA_CERT}" \
  "${CERT}"

openssl x509 \
  -in "${CERT}" \
  -noout \
  -subject \
  -issuer \
  -serial \
  -dates \
  -ext subjectAltName \
  -ext extendedKeyUsage

echo
echo "Issued client certificate:"
echo "  ${CERT}"
echo
echo "Private key:"
echo "  ${KEY}"
