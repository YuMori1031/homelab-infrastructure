#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOMELAB_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"

CA_DIR="${HOMELAB_DIR}/secrets/pki/ca"
DB_DIR="${CA_DIR}/database"
CRL_DIR="${CA_DIR}/crl"

CONFIG="${DB_DIR}/openssl.cnf"
CA_CERT="${CA_DIR}/ca-cert.pem"
CRL="${CRL_DIR}/homelab-ca.crl.pem"

for f in \
  "${CONFIG}" \
  "${CA_CERT}" \
  "${CA_DIR}/ca-key.pem" \
  "${DB_DIR}/index.txt" \
  "${DB_DIR}/crlnumber"
do
  if [ ! -f "${f}" ]; then
    echo "ERROR: required file not found: ${f}" >&2
    exit 1
  fi
done

mkdir -p "${CRL_DIR}"

TMP_CRL="$(mktemp)"
cleanup() {
  rm -f "${TMP_CRL}"
}
trap cleanup EXIT

echo "Generating CRL..."

(
  cd "${DB_DIR}"

  openssl ca \
    -config ./openssl.cnf \
    -gencrl \
    -out "${TMP_CRL}"
)

echo "Validating CRL..."

openssl crl \
  -in "${TMP_CRL}" \
  -verify \
  -CAfile "${CA_CERT}" \
  -noout

if ! openssl crl \
  -in "${TMP_CRL}" \
  -noout \
  -text |
  grep -q 'X509v3 Authority Key Identifier'
then
  echo "ERROR: generated CRL has no Authority Key Identifier" >&2
  exit 1
fi

install -m 644 \
  "${TMP_CRL}" \
  "${CRL}"

echo
echo "CRL updated:"
echo "  ${CRL}"

openssl crl \
  -in "${CRL}" \
  -noout \
  -issuer \
  -lastupdate \
  -nextupdate \
  -crlnumber
