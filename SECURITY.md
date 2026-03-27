# Security Policy

The NeuroMorphicToolkit (NMTK) project takes security seriously. This document outlines our security policy, including supported versions, how to report vulnerabilities, and our commitment to a responsible disclosure timeline.

## Supported Versions

The following versions of the NMTK root infrastructure and core components are currently supported with security updates:

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |
| < 1.0   | ❌        |

*Note: Individual modules may have different versioning and support cycles. See [Per-Module Security Policies](#per-module-security-policies) below.*

## Reporting a Vulnerability

If you discover a security vulnerability within the NeuroMorphicToolkit or any of its submodules, please report it responsibly:

1. **Do NOT open a public issue.**
2. Use [GitHub Security Advisories](https://github.com/Neuro-Dream-Hand/NeuroMorphicToolkit/security/advisories/new) to report the vulnerability privately.
3. If GitHub Security Advisories are unavailable, please contact the maintainers at `security@neuromorphic-toolkit.org` (hypothetical placeholder).
4. Include a clear description, reproduction steps, and potential impact.

## Response Timeline (Responsible Disclosure)

We are committed to the following timeline for security issues:

- **Acknowledgment:** Within 72 hours of receiving a report.
- **Initial Assessment:** Within 1 week of acknowledgment.
- **Fix or Mitigation:** Targeted within 30 days for critical issues.
- **Public Disclosure:** Following the release of a fix, coordinated with the reporter.

## Per-Module Security Policies

NMTK is a toolkit of modular components. While this root policy provides general guidance, some modules maintain their own specific security documentation:

- **[NeuroCNL](./neurocnl/SECURITY.md)**: conceptual neuromorphic language compiler.
- **[Neuro-Dream-Hand](./Neuro-Dream-Hand/SECURITY.md)**: Hardware robotics and edge integration.

For all other modules (Neurosim, Neurobench, Neurochip, Neurohub, Neurosense), please refer to this root policy.

## Security Best Practices

To maintain the security of your NMTK installation:

- **Secrets Management:** Never commit secrets (API keys, passwords) to the repository or include them in Docker images. Use `.env` files (which are ignored by git) or environment variables.
- **Docker Security:** Containers in our ecosystem are designed to run as non-root users where possible.
- **Dependency Updates:** Regularly update your local submodules and dependencies to ensure you have the latest security patches.
- **Network Isolation:** When running NMTK services in Docker, ensure they are confined to the internal `nmtk-network` unless external access is strictly required.

## Out of Scope

- Denial-of-service (DoS) attacks against development/staging environments.
- Issues in third-party dependencies that are already publicly disclosed (please check CVE databases first).
- Social engineering attacks against project maintainers or users.

## Secrets Management

NMTK handles sensitive information such as API keys and database credentials. Follow these best practices:

- **Environment Variables**: Use environment variables to pass secrets to containers in production.
- **Docker Secrets**: For Swarm or Kubernetes, use native secret management.
- **No Plaintext**: Never store plaintext secrets in `.env` files that are checked into version control. Use `.env.example` as a template.
- **Encryption at Rest**: Ensure that any persistent storage containing sensitive data (e.g., SQLite databases) is protected by appropriate filesystem-level encryption.
