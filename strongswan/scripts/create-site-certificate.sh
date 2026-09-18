#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <site-id>"
  echo
  echo "Example:"
  echo "  $0 site-a-router"
  exit 1
fi

SITE_ID="$1"

if ! printf '%s\n' "${SITE_ID}" |
  grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'
then
  echo "ERROR: invalid site ID: ${SITE_ID}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
HOMELAB_DIR="$(cd "${REPO_DIR}/.." && pwd)"

SECRETS_DIR="${HOMELAB_DIR}/secrets"

CA_DIR="${SECRETS_DIR}/pki/ca"
DB_DIR="${CA_DIR}/database"

CA_CERT="${CA_DIR}/ca-cert.pem"
CA_KEY="${CA_DIR}/ca-key.pem"
CONFIG="${DB_DIR}/openssl.cnf"

OUTPUT_DIR="${SECRETS_DIR}/pki/gateways/${SITE_ID}"

KEY_FILE="${OUTPUT_DIR}/${SITE_ID}-key.pem"
CSR_FILE="${OUTPUT_DIR}/${SITE_ID}.csr.pem"
CERT_FILE="${OUTPUT_DIR}/${SITE_ID}-cert.pem"
P12_FILE="${OUTPUT_DIR}/${SITE_ID}.p12"

for f in \
  "${CA_CERT}" \
  "${CA_KEY}" \
  "${CONFIG}" \
  "${DB_DIR}/index.txt" \
  "${DB_DIR}/serial"
do
  if [ ! -f "${f}" ]; then
    echo "ERROR: required file not found: ${f}" >&2
    exit 1
  fi
done

if awk -F '\t' \
  -v subject="/CN=${SITE_ID}" \
  '$6 == subject { found=1 } END { exit !found }' \
  "${DB_DIR}/index.txt"
then
  echo "ERROR: site ID already exists in CA database: ${SITE_ID}" >&2
  exit 1
fi

if [ -e "${OUTPUT_DIR}" ]; then
  echo "ERROR: output directory already exists: ${OUTPUT_DIR}" >&2
  exit 1
fi

read -s -p "P12 password: " P12_PASSWORD
echo
read -s -p "Confirm P12 password: " P12_PASSWORD_CONFIRM
echo

if [ "${P12_PASSWORD}" != "${P12_PASSWORD_CONFIRM}" ]; then
  echo "ERROR: passwords do not match." >&2
  exit 1
fi

mkdir -m 700 "${OUTPUT_DIR}"

echo "[1/4] Generating EC P-384 private key..."

openssl ecparam \
  -name secp384r1 \
  -genkey \
  -noout \
  -out "${KEY_FILE}"

chmod 600 "${KEY_FILE}"

echo "[2/4] Generating CSR..."

openssl req \
  -new \
  -key "${KEY_FILE}" \
  -out "${CSR_FILE}" \
  -subj "/CN=${SITE_ID}" \
  -addext "subjectAltName = DNS:${SITE_ID}"

echo "[3/4] Issuing site certificate through CA database..."

(
  cd "${DB_DIR}"

  openssl ca \
    -batch \
    -config ./openssl.cnf \
    -extensions site_cert \
    -days 3650 \
    -in "${CSR_FILE}" \
    -out "${CERT_FILE}"
)

chmod 644 "${CSR_FILE}" "${CERT_FILE}"

echo "Validating certificate..."

openssl verify \
  -CAfile "${CA_CERT}" \
  "${CERT_FILE}"

openssl x509 \
  -in "${CERT_FILE}" \
  -noout \
  -subject \
  -issuer \
  -serial \
  -dates \
  -ext basicConstraints \
  -ext keyUsage \
  -ext extendedKeyUsage \
  -ext subjectAltName

echo "[4/4] Creating PKCS#12..."

openssl pkcs12 \
  -export \
  -inkey "${KEY_FILE}" \
  -in "${CERT_FILE}" \
  -certfile "${CA_CERT}" \
  -out "${P12_FILE}" \
  -name "${SITE_ID}" \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -macalg sha1 \
  -passout "pass:${P12_PASSWORD}"

chmod 600 "${P12_FILE}"

echo
echo "Site certificate created successfully."
echo
echo "Site ID : ${SITE_ID}"
echo "Output  : ${OUTPUT_DIR}"
echo
echo "Generated:"
echo "  ${KEY_FILE}"
echo "  ${CSR_FILE}"
echo "  ${CERT_FILE}"
echo "  ${P12_FILE}"
