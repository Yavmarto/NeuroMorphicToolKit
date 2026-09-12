# CEL-226 — Connecting to server not working

## Problem
Dev build shows stuck **Reconnecting to your server…** overlay with **NeuroStudio Not Available** underneath.

## Triage
- Backend reachable: `GET http://192.168.2.90:8090/health` → 200
- Likely connect gate race or dev auth policy mismatch (CEL-220/CEL-198)

## Delegation
- CEL-227 — Engineer: fix connect flow
- CEL-228 — QA: verify after CEL-227 (blocked)

Parent CEL-226 blocked on CEL-227.
