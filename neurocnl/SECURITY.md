# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.2.x   | ✅        |
| < 0.2   | ❌        |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public issue.**
2. Use [GitHub Security Advisories](https://github.com/YOUR_ORG/neurocnl/security/advisories/new) to report the vulnerability privately.
3. Include a clear description, reproduction steps, and potential impact.

## Response Timeline

- **Acknowledgment:** Within 72 hours of report.
- **Initial assessment:** Within 1 week.
- **Fix or mitigation:** Targeted within 30 days for critical issues.

## Out of Scope

- Denial-of-service attacks against development/staging environments.
- Issues in dependencies that are already publicly disclosed (please check CVE databases first).
- Social engineering attacks.

## Security Best Practices

- All simulation endpoints are rate-limited.
- Request IDs are generated for traceability.
- Docker containers run as non-root users.
- No secrets are committed to source control.
