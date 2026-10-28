#!/usr/bin/env bash
set -euo pipefail

# CERTGEN_TEST_LOCAL=1 runs the entrypoint directly, without Docker. The shared
# image workflow supplies IMAGE; validate that image rather than rebuilding it.
here="$(cd "$(dirname "$0")/.." && pwd)"
cert_dir=$(mktemp -d)
cleanup() { rm -rf "$cert_dir"; }
trap cleanup EXIT

if [[ "${CERTGEN_TEST_LOCAL:-}" != 1 && -z "${IMAGE:-}" ]]; then
  IMAGE=reference-certgen:smoke
  docker build -t "$IMAGE" "$here"
fi

generate() {
  if [[ "${CERTGEN_TEST_LOCAL:-}" == 1 ]]; then
    CERTGEN_DOMAINS="alpha.test bravo.test" CERTGEN_CA_NAME="Smoke CA" \
      CERTGEN_OUTPUT_DIR="$cert_dir" sh "$here/generate-certs.sh"
  else
    docker run --rm --network none --user "$(id -u):$(id -g)" \
      -e CERTGEN_DOMAINS="alpha.test bravo.test" \
      -e CERTGEN_CA_NAME="Smoke CA" \
      -v "$cert_dir:/certs" \
      "$IMAGE"
  fi
}

# set -e requires the one-shot generator to exit successfully, before checking
# its output. This must never be replaced by a placeholder image HEALTHCHECK.
generate

for f in ca.crt ca.key alpha.test.crt alpha.test.key bravo.test.crt bravo.test.key; do
  if [ ! -s "$cert_dir/$f" ]; then
    echo "FAIL: missing $f"
    exit 1
  fi
done

# Verify each chain, validity, intended hostname, SANs and matching private key.
for domain in alpha.test bravo.test; do
  openssl verify -CAfile "$cert_dir/ca.crt" -verify_hostname "$domain" "$cert_dir/$domain.crt"
  san=$(openssl x509 -in "$cert_dir/$domain.crt" -noout -ext subjectAltName)
  printf '%s\n' "$san" | tr ',' '\n' | sed 's/^[[:space:]]*//' > "$cert_dir/san"
  grep -Fxq "DNS:$domain" "$cert_dir/san"
  grep -Fxq "DNS:*.$domain" "$cert_dir/san"
done
for name in ca alpha.test bravo.test; do
  openssl pkey -in "$cert_dir/$name.key" -check -noout
  openssl pkey -in "$cert_dir/$name.key" -pubout > "$cert_dir/key.pub"
  openssl x509 -in "$cert_dir/$name.crt" -pubkey -noout > "$cert_dir/cert.pub"
  cmp "$cert_dir/key.pub" "$cert_dir/cert.pub"
done

# Idempotency: re-run must exit successfully, skip and leave output unchanged.
openssl dgst -sha256 "$cert_dir/"*.crt "$cert_dir/"*.key > "$cert_dir/before"
generate > "$cert_dir/rerun.log" 2>&1
grep -q "All requested certificates already exist" "$cert_dir/rerun.log" \
  || { echo "FAIL: idempotency check did not skip"; exit 1; }
openssl dgst -sha256 "$cert_dir/"*.crt "$cert_dir/"*.key > "$cert_dir/after"
cmp "$cert_dir/before" "$cert_dir/after"

echo "OK: generator exited successfully; chains, hostnames, SANs and keys valid; re-run unchanged"
