#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-reference-certgen:smoke}"
TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

docker build -t "$IMAGE" .

docker run --rm \
  -e CERTGEN_DOMAINS="alpha.test bravo.test" \
  -e CERTGEN_CA_NAME="Smoke CA" \
  -v "$TMPDIR:/certs" \
  "$IMAGE"

for f in ca.crt ca.key alpha.test.crt alpha.test.key bravo.test.crt bravo.test.key; do
  if [ ! -f "$TMPDIR/$f" ]; then
    echo "FAIL: missing $f"
    exit 1
  fi
done

# Verify the cert chain.
openssl verify -CAfile "$TMPDIR/ca.crt" "$TMPDIR/alpha.test.crt" >/dev/null
openssl verify -CAfile "$TMPDIR/ca.crt" "$TMPDIR/bravo.test.crt" >/dev/null

# Verify the SAN includes the FQDN + wildcard.
SAN=$(openssl x509 -in "$TMPDIR/alpha.test.crt" -noout -ext subjectAltName | grep DNS)
echo "$SAN" | grep -q "DNS:alpha.test" || { echo "FAIL: SAN missing alpha.test ($SAN)"; exit 1; }
echo "$SAN" | grep -q "DNS:\*.alpha.test" || { echo "FAIL: SAN missing *.alpha.test ($SAN)"; exit 1; }

# Idempotency: re-run, should be no-op.
docker run --rm \
  -e CERTGEN_DOMAINS="alpha.test bravo.test" \
  -v "$TMPDIR:/certs" \
  "$IMAGE" 2>&1 | grep -q "All requested certificates already exist" \
  || { echo "FAIL: idempotency check did not skip"; exit 1; }

echo "OK: certs generated, chain valid, SANs correct, idempotent re-run skipped"
