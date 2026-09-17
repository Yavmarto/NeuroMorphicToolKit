# ADR 0002: Firebase Auth as Identity Provider for Public Registry RC

## Status
Accepted — 2026-07-20

## Context

The original registry auth layer (`registry_auth_service.py`) implements its own bcrypt
password hashing, HMAC JWT issuance, and refresh-token store (Redis). While correct, this
creates three gaps for the public RC:

1. **Email verification**: no flow exists to verify user email addresses.
2. **Password reset**: no flow exists; would require SMTP integration.
3. **OAuth**: no social login; adds significant implementation surface.

Solving all three in-house adds 2–3 weeks of implementation and ongoing maintenance burden.

## Decision

Use **Firebase Authentication** as the identity provider for the public GCP-hosted deployment.

- Registration, login, email verification, password reset, and OAuth (Google Sign-In) are
  delegated entirely to Firebase.
- The FastAPI backend verifies Firebase RS256 ID tokens using `firebase-admin` (ADC on
  Cloud Run; `GOOGLE_APPLICATION_CREDENTIALS` for local testing with Firebase).
- A new `POST /api/v1/auth/sync` endpoint provisions or updates the local `UserDB` row from
  a valid Firebase ID token on first sign-in.
- A `firebase_uid` column is added to `UserDB` (nullable, unique) as the link between the
  Firebase identity and the Neurohub registry user.
- Provider selection is controlled by `NEUROHUB_AUTH_PROVIDER=firebase|internal` so local
  development and self-hosted deployments continue to use the existing internal auth path
  without any Firebase dependency.

## Consequences

### Positive
- Email verification and password reset are free and production-grade.
- Google Sign-In requires a single checkbox in the Firebase console.
- No SMTP server or email template maintenance required.
- Firebase ID token verification uses Google's public key rotation automatically.
- `firebase-admin` is a lazy optional dependency (`pip install neurohub[firebase]`);
  the base install is unaffected.

### Negative
- Local dev requires either `NEUROHUB_AUTH_PROVIDER=internal` (no Firebase needed) or a
  Firebase emulator for end-to-end testing.
- The `hashed_password` column stays on `UserDB` for backward compat with the internal path
  but is an empty string for Firebase-provisioned users.
- Firebase free tier (Spark) is limited to 10k MAU; beyond that, Blaze (pay-as-you-go) applies.

### Neutral
- The `POST /api/v1/auth/register` and `POST /api/v1/auth/login` endpoints remain in the
  router but return HTTP 501 when `NEUROHUB_AUTH_PROVIDER=firebase`, making the switch
  transparent to API clients that check for errors.
- All downstream endpoints are provider-agnostic: they receive a `RegistryUser(id, username, roles)`
  regardless of which provider issued the token.
