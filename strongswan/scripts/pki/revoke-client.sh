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

CONFIG="${DB_DIR}/openssl.cnf"
INDEX="${DB_DIR}/index.txt"

MATCHES="$(
  awk -F '\t' \
    -v subject="/CN=${CLIENT_ID}" \
    '$6 == subject {print}' \
    "${INDEX}"
)"

COUNT="$(
  printf '%s\n' "${MATCHES}" |
  grep -c . || true
)"

if [ "${COUNT}" -eq 0 ]; then
  echo "ERROR: client not found in CA database: ${CLIENT_ID}" >&2
  exit 1
fi

if [ "${COUNT}" -ne 1 ]; then
  echo "ERROR: multiple CA database entries found for: ${CLIENT_ID}" >&2
  exit 1
fi

STATUS="$(
  printf '%s\n' "${MATCHES}" |
  cut -f1
)"

SERIAL="$(
  printf '%s\n' "${MATCHES}" |
  cut -f4
)"

if [ "${STATUS}" = "R" ]; then
  echo "ERROR: certificate is already revoked: ${CLIENT_ID}" >&2
  exit 1
fi

if [ "${STATUS}" != "V" ]; then
  echo "ERROR: certificate is not currently valid: ${CLIENT_ID}" >&2
  exit 1
fi

CERT="${DB_DIR}/newcerts/${SERIAL}.pem"

if [ ! -f "${CERT}" ]; then
  echo "ERROR: CA archive certificate not found: ${CERT}" >&2
  exit 1
fi

echo "About to revoke:"
echo "  Client ID : ${CLIENT_ID}"
echo "  Serial    : ${SERIAL}"
echo
read -r -p "Type REVOKE to continue: " CONFIRM

if [ "${CONFIRM}" != "REVOKE" ]; then
  echo "Cancelled."
  exit 1
fi

(
  cd "${DB_DIR}"

  openssl ca \
    -config ./openssl.cnf \
    -revoke "${CERT}" \
    -crl_reason cessationOfOperation
)

echo
echo "Certificate revoked."
echo
echo "IMPORTANT:"
echo "Generate and deploy a new CRL before the revocation becomes effective"
echo "on the VPN server."
