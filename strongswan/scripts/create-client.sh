#!/bin/bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <user-name> <device-name> <os-type>"
  echo
  echo "OS types:"
  echo "  ios      - create certificate, p12, and mobileconfig"
  echo "  macos    - create certificate, p12, and mobileconfig"
  echo "  windows  - create certificate and p12 only"
  echo "  android  - create certificate and p12 only"
  echo
  echo "Examples:"
  echo "  $0 user01 ipad ios"
  echo "  $0 user01 mac macos"
  echo "  $0 tanaka windows windows"
  echo "  $0 suzuki pixel android"
  exit 1
fi

USER_NAME="$1"
DEVICE_NAME="$2"
OS_TYPE="$3"
CERT_NAME="${USER_NAME}-${DEVICE_NAME}"

for value in "${USER_NAME}" "${DEVICE_NAME}"; do
  if ! printf '%s\n' "${value}" |
    grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'
  then
    echo "ERROR: invalid identifier: ${value}" >&2
    exit 1
  fi
done

case "${OS_TYPE}" in
  ios|macos|windows|android)
    ;;
  *)
    echo "ERROR: unsupported os-type: ${OS_TYPE}" >&2
    echo "Supported: ios, macos, windows, android" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
HOMELAB_DIR="$(cd "${REPO_DIR}/.." && pwd)"
SECRETS_DIR="${HOMELAB_DIR}/secrets"

ENV_FILE="${SECRETS_DIR}/config/environment.sh"

if [ ! -f "${ENV_FILE}" ]; then
  echo "ERROR: environment file not found: ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${VPN_SERVER:?VPN_SERVER is not defined in ${ENV_FILE}}"

PROFILE_NAME="HomeLab VPN"
ORG_NAME="HomeLab"
DESCRIPTION="IKEv2 VPN profile for HomeLab"

CA_DIR="${SECRETS_DIR}/pki/ca"
DB_DIR="${CA_DIR}/database"

CA_CERT="${CA_DIR}/ca-cert.pem"
CA_KEY="${CA_DIR}/ca-key.pem"
CONFIG="${DB_DIR}/openssl.cnf"

CLIENT_DIR="${SECRETS_DIR}/pki/clients/${USER_NAME}/${DEVICE_NAME}"

KEY_FILE="${CLIENT_DIR}/${DEVICE_NAME}-key.pem"
CSR_FILE="${CLIENT_DIR}/${DEVICE_NAME}.csr.pem"
CERT_FILE="${CLIENT_DIR}/${DEVICE_NAME}-cert.pem"
P12_FILE="${CLIENT_DIR}/${DEVICE_NAME}.p12"
PROFILE_FILE="${CLIENT_DIR}/${DEVICE_NAME}.mobileconfig"

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
  -v subject="/CN=${CERT_NAME}" \
  '$6 == subject { found=1 } END { exit !found }' \
  "${DB_DIR}/index.txt"
then
  echo "ERROR: client ID already exists in CA database: ${CERT_NAME}" >&2
  exit 1
fi

if [ -e "${CLIENT_DIR}" ]; then
  echo "ERROR: client directory already exists: ${CLIENT_DIR}" >&2
  exit 1
fi

CREATE_MOBILECONFIG=false
if [ "${OS_TYPE}" = "ios" ] || [ "${OS_TYPE}" = "macos" ]; then
  CREATE_MOBILECONFIG=true
fi

echo "========================================="
echo "Create VPN Client Certificate"
echo "========================================="
echo "User       : ${USER_NAME}"
echo "Device     : ${DEVICE_NAME}"
echo "OS Type    : ${OS_TYPE}"
echo "CN         : ${CERT_NAME}"
echo "Output Dir : ${CLIENT_DIR}"
echo "========================================="
echo

read -s -p "P12 password: " P12_PASSWORD
echo
read -s -p "Confirm P12 password: " P12_PASSWORD_CONFIRM
echo

if [ "${P12_PASSWORD}" != "${P12_PASSWORD_CONFIRM}" ]; then
  echo "ERROR: passwords do not match." >&2
  exit 1
fi

mkdir -p "$(dirname "${CLIENT_DIR}")"
mkdir -m 700 "${CLIENT_DIR}"

echo
echo "[1/5] Generating private key..."

openssl ecparam \
  -name secp384r1 \
  -genkey \
  -noout \
  -out "${KEY_FILE}"

chmod 600 "${KEY_FILE}"

echo "[2/5] Generating CSR..."

openssl req \
  -new \
  -key "${KEY_FILE}" \
  -out "${CSR_FILE}" \
  -subj "/CN=${CERT_NAME}" \
  -addext "subjectAltName = DNS:${CERT_NAME}"

echo "[3/5] Issuing client certificate through CA database..."

(
  cd "${DB_DIR}"

  openssl ca \
    -batch \
    -config ./openssl.cnf \
    -extensions client_cert \
    -days 825 \
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

echo "[4/5] Creating PKCS#12..."

if [ "${OS_TYPE}" = "macos" ]; then
  openssl pkcs12 \
    -export \
    -inkey "${KEY_FILE}" \
    -in "${CERT_FILE}" \
    -certfile "${CA_CERT}" \
    -out "${P12_FILE}" \
    -name "${CERT_NAME}" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1 \
    -passout "pass:${P12_PASSWORD}"
else
  openssl pkcs12 \
    -export \
    -inkey "${KEY_FILE}" \
    -in "${CERT_FILE}" \
    -certfile "${CA_CERT}" \
    -out "${P12_FILE}" \
    -name "${CERT_NAME}" \
    -passout "pass:${P12_PASSWORD}"
fi

chmod 600 "${P12_FILE}"

if [ "${CREATE_MOBILECONFIG}" = true ]; then
  echo "[5/5] Creating Apple mobileconfig..."

  PROFILE_UUID="$(uuidgen)"
  CA_UUID="$(uuidgen)"
  CERT_UUID="$(uuidgen)"
  VPN_UUID="$(uuidgen)"

  P12_B64="$(base64 < "${P12_FILE}" | tr -d '\n')"
  CA_DER_B64="$(
    openssl x509 -in "${CA_CERT}" -outform der |
      base64 |
      tr -d '\n'
  )"

  cat > "${PROFILE_FILE}" <<EOF_PROFILE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
  <key>PayloadIdentifier</key>
  <string>com.example.homelab.${USER_NAME}.${DEVICE_NAME}</string>
  <key>PayloadUUID</key>
  <string>${PROFILE_UUID}</string>
  <key>PayloadDisplayName</key>
  <string>${PROFILE_NAME}</string>
  <key>PayloadDescription</key>
  <string>${DESCRIPTION}</string>
  <key>PayloadOrganization</key>
  <string>${ORG_NAME}</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>

  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.security.root</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadIdentifier</key>
      <string>com.example.homelab.ca.${USER_NAME}.${DEVICE_NAME}</string>
      <key>PayloadUUID</key>
      <string>${CA_UUID}</string>
      <key>PayloadDisplayName</key>
      <string>HomeLab Root CA</string>
      <key>PayloadOrganization</key>
      <string>${ORG_NAME}</string>
      <key>PayloadContent</key>
      <data>${CA_DER_B64}</data>
    </dict>

    <dict>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadIdentifier</key>
      <string>com.example.homelab.cert.${USER_NAME}.${DEVICE_NAME}</string>
      <key>PayloadUUID</key>
      <string>${CERT_UUID}</string>
      <key>PayloadDisplayName</key>
      <string>${CERT_NAME}</string>
      <key>PayloadOrganization</key>
      <string>${ORG_NAME}</string>
      <key>Password</key>
      <string>${P12_PASSWORD}</string>
      <key>PayloadContent</key>
      <data>${P12_B64}</data>
    </dict>

    <dict>
      <key>PayloadType</key>
      <string>com.apple.vpn.managed</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadIdentifier</key>
      <string>com.example.homelab.vpn.${USER_NAME}.${DEVICE_NAME}</string>
      <key>PayloadUUID</key>
      <string>${VPN_UUID}</string>
      <key>PayloadDisplayName</key>
      <string>${PROFILE_NAME}</string>
      <key>PayloadOrganization</key>
      <string>${ORG_NAME}</string>
      <key>UserDefinedName</key>
      <string>${PROFILE_NAME}</string>
      <key>VPNType</key>
      <string>IKEv2</string>

      <key>IKEv2</key>
      <dict>
        <key>RemoteAddress</key>
        <string>${VPN_SERVER}</string>
        <key>RemoteIdentifier</key>
        <string>${VPN_SERVER}</string>
        <key>LocalIdentifier</key>
        <string>${CERT_NAME}</string>
        <key>AuthenticationMethod</key>
        <string>Certificate</string>
        <key>CertificateType</key>
        <string>ECDSA384</string>
        <key>PayloadCertificateUUID</key>
        <string>${CERT_UUID}</string>
        <key>ExtendedAuthEnabled</key>
        <false/>
        <key>DeadPeerDetectionRate</key>
        <string>Medium</string>
        <key>DisableMOBIKE</key>
        <false/>
        <key>DisableRedirect</key>
        <true/>
        <key>EnablePFS</key>
        <false/>
      </dict>
    </dict>
  </array>
</dict>
</plist>
EOF_PROFILE
else
  echo "[5/5] Skipping mobileconfig generation for OS type: ${OS_TYPE}"
fi

echo
echo "========================================="
echo "Client successfully created"
echo "========================================="
echo "User       : ${USER_NAME}"
echo "Device     : ${DEVICE_NAME}"
echo "OS Type    : ${OS_TYPE}"
echo "CN         : ${CERT_NAME}"
echo "Output Dir : ${CLIENT_DIR}"
echo
echo "Generated files:"
echo "  ${KEY_FILE}"
echo "  ${CSR_FILE}"
echo "  ${CERT_FILE}"
echo "  ${P12_FILE}"

if [ "${CREATE_MOBILECONFIG}" = true ]; then
  echo "  ${PROFILE_FILE}"
fi

echo "========================================="
