# CEL-226 — Connecting to server not working

## Problem
Dev build shows stuck **Reconnecting to your server…** overlay with **NeuroStudio Not Available** underneath.

## Triage
- Backend reachable: `GET http://192.168.2.90:8090/health` → 200
- Likely connect gate race or dev auth policy mismatch (CEL-220/CEL-198)

## Delegation
- CEL-227 — Engineer: fix connect flow (done)
- CEL-228 — QA: macOS verify (done)
- CEL-232 — QA: mobile profile verify (PASS 3/3 on CPH2173)

## Mobile fix (2026-09-13)
- `loadLastHost()` skips keychain before profile/debug probe
- No empty secure-storage writes on credential-free connect

CEL-232 QA PASS (2026-09-13): physical Android E2E 3/3. Parent ready to close once CEL-232 marked done.
