#!/bin/sh
set -eu

CERT_DIR="${CERTGEN_OUTPUT_DIR:-/certs}"
DOMAINS="${CERTGEN_DOMAINS:-}"
CA_NAME="${CERTGEN_CA_NAME:-Reference Test CA}"
ORG="${CERTGEN_ORG:-Reference}"
COUNTRY="${CERTGEN_COUNTRY:-US}"
STATE="${CERTGEN_STATE:-Test}"
LOCALITY="${CERTGEN_LOCALITY:-Test}"
CA_DAYS="${CERTGEN_CA_DAYS:-3650}"
CERT_DAYS="${CERTGEN_CERT_DAYS:-825}"
CA_KEY_BITS="${CERTGEN_CA_KEY_BITS:-4096}"
CERT_KEY_BITS="${CERTGEN_CERT_KEY_BITS:-2048}"

if [ -z "$DOMAINS" ]; then
  echo "ERROR: CERTGEN_DOMAINS is required (space-separated list of FQDNs)." >&2
  echo "Example: CERTGEN_DOMAINS=\"mail1.test mail2.test mail3.test\"" >&2
  exit 2
fi

mkdir -p "$CERT_DIR"

# Idempotent: skip if every requested cert already exists.
ALL_PRESENT=1
[ -f "$CERT_DIR/ca.crt" ] || ALL_PRESENT=0
for D in $DOMAINS; do
  [ -f "$CERT_DIR/$D.crt" ] && [ -f "$CERT_DIR/$D.key" ] || ALL_PRESENT=0
done
if [ "$ALL_PRESENT" = 1 ]; then
  echo "All requested certificates already exist in $CERT_DIR; nothing to do."
  exit 0
fi

echo "Generating CA: $CA_NAME ($CA_KEY_BITS bits, $CA_DAYS days)"
openssl genrsa -out "$CERT_DIR/ca.key" "$CA_KEY_BITS" 2>/dev/null
openssl req -x509 -new -nodes \
  -key "$CERT_DIR/ca.key" \
  -sha256 -days "$CA_DAYS" \
  -out "$CERT_DIR/ca.crt" \
  -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$CA_NAME/CN=$CA_NAME"

for D in $DOMAINS; do
  if [ -f "$CERT_DIR/$D.crt" ] && [ -f "$CERT_DIR/$D.key" ]; then
    echo "Skipping $D (already present)"
    continue
  fi
  echo "Issuing cert for $D ($CERT_KEY_BITS bits, $CERT_DAYS days)"
  openssl genrsa -out "$CERT_DIR/$D.key" "$CERT_KEY_BITS" 2>/dev/null
  openssl req -new \
    -key "$CERT_DIR/$D.key" \
    -out "$CERT_DIR/$D.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORG/CN=$D"
  cat > "$CERT_DIR/$D.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $D
DNS.2 = *.$D
EOF
  openssl x509 -req \
    -in "$CERT_DIR/$D.csr" \
    -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/$D.crt" \
    -days "$CERT_DAYS" \
    -sha256 \
    -extfile "$CERT_DIR/$D.ext"
  rm -f "$CERT_DIR/$D.csr" "$CERT_DIR/$D.ext"
  chmod 644 "$CERT_DIR/$D.crt"
  chmod 600 "$CERT_DIR/$D.key"
done

rm -f "$CERT_DIR/ca.srl"
chmod 644 "$CERT_DIR/ca.crt"
chmod 600 "$CERT_DIR/ca.key"

echo "Done. Output in $CERT_DIR:"
ls -1 "$CERT_DIR" | sed 's/^/  /'
