# CEL-334 verification summary

**Date:** 2026-09-19  
**Issue:** Ship two reproducible NMTK demo guides (N-MNIST and SHD on Akida)

## Deliverables

| Guide | Path | README link |
|---|---|---|
| N-MNIST (simulation) | [GUIDE-nmnist-snntorch.md](./GUIDE-nmnist-snntorch.md) | [README.md](../../README.md) line 32 |
| SHD on Akida | [GUIDE-shd-akida.md](./GUIDE-shd-akida.md) | [README.md](../../README.md) line 33 |

Index: [docs/guides/README.md](./README.md)

## Automated checks (2026-09-19)

```text
pytest neurocnl/neurocnl/contracts/test_akida_deployment_contract.py::test_guide_shd_topology_is_exportable  PASSED
pytest neurocnl/neurocnl/converter/test_akida_adapter.py::test_guide_mnist_cnn_template_is_akida_exportable  PASSED (when Akida SDK present)
```

## Hardware labels

- N-MNIST guide: simulation only — no hardware steps.
- SHD guide: train + Akida software-sim export = **works**; physical card deploy (§6) = **needs hardware**.

## Live backend

Dev backend health: `GET http://192.168.2.90:9000/api/suite/health` → `{"status":"ok"}`.  
`generate-v2` requires `NMTK_ADMIN_TOKEN` when `NMTK_AUTH_REQUIRED` is enabled (documented in both guides).

## Optional extended verification

Full 20-epoch N-MNIST training (~30–90 min GPU) and measured SHD Akida accuracy table remain optional follow-ups; smoke-generate and contract tests cover the published walkthrough paths.
