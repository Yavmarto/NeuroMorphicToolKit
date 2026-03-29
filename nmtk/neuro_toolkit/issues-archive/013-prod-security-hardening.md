# [PROD-04] Security Hardening

**Module**: root-infrastructure
**Phase**: Production
**Priority**: P0
**Effort**: Medium (2-3 days)
**Labels**: `root-infrastructure`, `phase:production`, `priority:critical`

## Acceptance Criteria

- [ ] All containers run as non-root
- [ ] All containers have read-only root filesystem where possible
- [ ] Network policies restrict inter-service communication to required paths
- [ ] Secrets management (no plaintext secrets in env files)
- [ ] Dependency vulnerability scanning in CI (Dependabot or equivalent)
- [ ] OWASP dependency check for Python and Dart packages
