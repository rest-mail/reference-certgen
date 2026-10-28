# reference-certgen

A tiny one-shot container that generates a self-signed root CA and per-domain server certificates for any list of FQDNs you supply. Idempotent, MIT-licensed, multi-arch.

Designed for **development and testbed environments** where you need realistic TLS without paying for a real CA. Not for production. Use [cert-manager](https://cert-manager.io/) or [Let's Encrypt](https://letsencrypt.org/) for anything user-facing.

## Image

```
ghcr.io/rest-mail/reference-certgen:latest          # newest master build; pin a release instead
ghcr.io/rest-mail/reference-certgen:X.Y.Z          # a release: git tag vX.Y.Z publishes it
```

## Quick start

```bash
docker run --rm \
  -e CERTGEN_DOMAINS="mail1.test mail2.test mail3.test" \
  -v $(pwd)/certs:/certs \
  ghcr.io/rest-mail/reference-certgen:latest

ls certs/
# ca.crt  ca.key  mail1.test.crt  mail1.test.key  mail2.test.crt  mail2.test.key  mail3.test.crt  mail3.test.key
```

Run again with the same volume — it skips work that's already done.

## Output

For each FQDN in `CERTGEN_DOMAINS`:

| File | Purpose |
|------|---------|
| `<domain>.crt` | server certificate, signed by the local CA, with SANs for `<domain>` and `*.<domain>` |
| `<domain>.key` | server private key (RSA 2048 by default) |

Plus once per run:

| File | Purpose |
|------|---------|
| `ca.crt` | root CA cert — distribute to clients you want to trust the issued certs |
| `ca.key` | root CA private key — keep this safe; anything signed with it will be trusted by anyone holding `ca.crt` |

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CERTGEN_DOMAINS` | **yes** | — | Space-separated list of FQDNs to issue certs for |
| `CERTGEN_OUTPUT_DIR` | no | `/certs` | Where to write certs (mount this) |
| `CERTGEN_CA_NAME` | no | `Reference Test CA` | CN/O of the root CA |
| `CERTGEN_ORG` | no | `Reference` | O field of issued certs |
| `CERTGEN_COUNTRY` | no | `US` | C field |
| `CERTGEN_STATE` | no | `Test` | ST field |
| `CERTGEN_LOCALITY` | no | `Test` | L field |
| `CERTGEN_CA_DAYS` | no | `3650` | CA validity in days |
| `CERTGEN_CERT_DAYS` | no | `825` | Server-cert validity (Apple's max for non-CT certs) |
| `CERTGEN_CA_KEY_BITS` | no | `4096` | CA RSA key size |
| `CERTGEN_CERT_KEY_BITS` | no | `2048` | Server-cert RSA key size |

## Idempotency

The script checks whether `ca.crt` and every requested `<domain>.crt`/`<domain>.key` already exist in `$CERTGEN_OUTPUT_DIR`. If so, it exits 0 with no changes. This makes it safe to run on every container start as a one-shot init container.

To force regeneration, delete the output directory.

## Trusting the CA

To make a client trust the issued certs:

```bash
# Linux
cp ca.crt /usr/local/share/ca-certificates/reference-test-ca.crt
update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt

# Browsers usually have their own trust store — import via Settings.
```

## Why one-shot?

certgen does its work and exits. It's not a long-lived service. In compose / k8s, run it as a **one-shot init container** before the daemons that need the certs:

```yaml
# docker-compose.yml
services:
  certgen:
    image: ghcr.io/rest-mail/reference-certgen:latest
    environment:
      CERTGEN_DOMAINS: mail1.test mail2.test mail3.test
    volumes:
      - certs:/certs

  postfix:
    depends_on:
      certgen:
        condition: service_completed_successfully
    volumes:
      - certs:/certs:ro
    # ...
```

## Validation

The image build uses the shared `rest-mail/deploy` workflow. As a one-shot job,
it explicitly sets `require-healthcheck: false` and supplies `tests/smoke.sh` as
its runtime check. The check runs the built image, requires successful exit,
and verifies generated certificate chains, hostnames, SANs, matching private
keys and an unchanged idempotent re-run. No placeholder HEALTHCHECK is needed.

Run the same check locally without Docker using the host's OpenSSL:

```sh
CERTGEN_TEST_LOCAL=1 tests/smoke.sh
```

To check an existing image, use `IMAGE=<image> tests/smoke.sh`. With neither
option set, `tests/smoke.sh` builds the image before checking it.

## License

MIT.

## See also

- [`rest-mail/conventions`](https://github.com/rest-mail/conventions) — the contract every `reference-*` image follows
- [`rest-mail/testbed`](https://github.com/rest-mail/testbed) — runs this image to provide TLS for the development sandbox
