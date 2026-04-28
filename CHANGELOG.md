# Changelog

Calver-tagged. Newest on top.

## 2026.04.28

- Initial release.
- Generates a self-signed CA + per-domain server certificates for any list of FQDNs supplied via `CERTGEN_DOMAINS`.
- All subject fields parameterized via env vars (no hardcoded org/CA name).
- Idempotent: skips generation when all requested certs already exist on disk.
- Multi-arch publish: linux/amd64, linux/arm64.
