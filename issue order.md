# Issue Execution Order

This file captures the complete recommended execution order across all `issues` and `issues-archive` folders in the workspace.

## Module-Level Execution Order

| Module | Issues source folders | Recommended complete execution order (first → last) |
|---|---|---|
| NMTK / neurocnl / NDH / nmtk_ui_core | Neuro-Dream-Hand/issues, neurocnl/issues, nmtk/issues-archive, nmtk_ui_core/issues | NMTK-01 → NMTK-02 → NMTK-06 → NMTK-03 → NMTK-04 → NMTK-05 → NMTK-07 → NMTK-08 → NMTK-09 → NMTK-10 → NMTK-11 → NMTK-12 → NMTK-13 → NMTK-14 → NMTK-15 → NMTK-16 → NMTK-17 → NMTK-18 → NMTK-19 → NMTK-20 → NMTK-21 → NMTK-22 → NMTK-23 → NMTK-24 → NMTK-25 → NMTK-26 → NMTK-27 → NMTK-28 → NMTK-29 → NMTK-30 |
| Neurobench | Neurobench/issues-archive | NB-B1 → NB-B3 → NB-B2 → NB-R1 → NB-R2 → NB-CT1 → NB-CT2 → NB-ES1 → NB-RP1 → NB-RP2 → NB-RE1 |
| Neurochip | Neurochip/issues-archive | NC-p2-hardware-profiles → NC-p2-firmware-templates → NC-p3-constraint-analyzer → NC-p3-quantization-power → NC-p3-fault-runner → NC-p3-deployment-store → NC-p3-code-gen-flash → NC-p4-target-selector → NC-p4-constraint-report → NC-p4-quantization-explorer → NC-p4-deployment-flow → NC-p5-testing |
| Neurosense | Neurosense/issues-archive | NSe-DM2 → NSe-DM3 → NSe-SA1 → NSe-SA2 → NSe-RS1 → NSe-SE1 → NSe-SE2 → NSe-RS2 |
| Neurohub | Neurohub/issues-archive | NH-cross-suite-client → NH-backend-health-monitor → NH-activity-collector → NH-backend-assets → NH-backend-workflows → NH-frontend-providers → NH-frontend-dashboard → NH-frontend-project-manager → NH-frontend-asset-browser → NH-frontend-workflow-editor |
| Neurosim | Neurosim/issues-archive | NS-D1 → NS-D2 → NS-D3 → NS-D4 → NS-D5 → NS-S1 → NS-S2 → NS-S3 → NS-C1 → NS-C2 → NS-E1 → NS-E2 |

## Cross-Module Dependency Gates

| Cross-module gate | Dependency rule |
|---|---|
| Neurosim → Neurochip | NS-E2 should run after Neurochip backend/export/deploy path is stable (at least through NC-p3 + NC-p4 core flow). |
| Neurobench → Neurochip | NB-CT1 and NB-CT2 should run after Neurochip target/constraint/deploy APIs are working. |
| Neurobench → Neurosense | NB-ES1 and NB-RP2 benefit from Neurosense encoding/recording readiness (NSe-SE1/NSe-RS1+). |
| Neurohub → all apps | NH-activity-collector and NH-backend-health-monitor should run after each app exposes reliable activity/health endpoints. |

## Global Queue (Single Sequential Plan)

| # | Issue | Module |
|---:|---|---|
| 1 | NMTK-01 | Neuro-Dream-Hand |
| 2 | NMTK-02 | nmtk |
| 3 | NMTK-06 | neurocnl |
| 4 | NMTK-03 | nmtk |
| 5 | NMTK-04 | neurocnl |
| 6 | NMTK-05 | neurocnl |
| 7 | NMTK-07 | neurocnl |
| 8 | NMTK-08 | neurocnl |
| 9 | NMTK-09 | nmtk |
| 10 | NMTK-10 | neurocnl |
| 11 | NMTK-11 | neurocnl |
| 12 | NMTK-12 | neurocnl |
| 13 | NMTK-13 | neurocnl |
| 14 | NMTK-14 | neurocnl |
| 15 | NMTK-15 | neurocnl |
| 16 | NMTK-16 | neurocnl |
| 17 | NMTK-17 | neurocnl |
| 18 | NMTK-18 | neurocnl |
| 19 | NMTK-19 | neurocnl |
| 20 | NMTK-20 | neurocnl |
| 21 | NMTK-21 | nmtk_ui_core |
| 22 | NMTK-22 | nmtk |
| 23 | NMTK-23 | nmtk |
| 24 | NMTK-24 | nmtk |
| 25 | NMTK-25 | nmtk |
| 26 | NMTK-26 | nmtk |
| 27 | NMTK-27 | nmtk |
| 28 | NMTK-28 | nmtk |
| 29 | NMTK-29 | nmtk |
| 30 | NMTK-30 | nmtk |
| 31 | NC-p2-hardware-profiles | Neurochip |
| 32 | NC-p2-firmware-templates | Neurochip |
| 33 | NC-p3-constraint-analyzer | Neurochip |
| 34 | NC-p3-quantization-power | Neurochip |
| 35 | NC-p3-fault-runner | Neurochip |
| 36 | NC-p3-deployment-store | Neurochip |
| 37 | NC-p3-code-gen-flash | Neurochip |
| 38 | NC-p4-target-selector | Neurochip |
| 39 | NC-p4-constraint-report | Neurochip |
| 40 | NC-p4-quantization-explorer | Neurochip |
| 41 | NC-p4-deployment-flow | Neurochip |
| 42 | NC-p5-testing | Neurochip |
| 43 | NSe-DM2 | Neurosense |
| 44 | NSe-DM3 | Neurosense |
| 45 | NSe-SA1 | Neurosense |
| 46 | NSe-SA2 | Neurosense |
| 47 | NSe-RS1 | Neurosense |
| 48 | NSe-SE1 | Neurosense |
| 49 | NSe-SE2 | Neurosense |
| 50 | NSe-RS2 | Neurosense |
| 51 | NS-D1 | Neurosim |
| 52 | NS-D2 | Neurosim |
| 53 | NS-D3 | Neurosim |
| 54 | NS-D4 | Neurosim |
| 55 | NS-D5 | Neurosim |
| 56 | NS-S1 | Neurosim |
| 57 | NS-S2 | Neurosim |
| 58 | NS-S3 | Neurosim |
| 59 | NS-C1 | Neurosim |
| 60 | NS-C2 | Neurosim |
| 61 | NS-E1 | Neurosim |
| 62 | NS-E2 | Neurosim |
| 63 | NB-B1 | Neurobench |
| 64 | NB-B3 | Neurobench |
| 65 | NB-B2 | Neurobench |
| 66 | NB-R1 | Neurobench |
| 67 | NB-R2 | Neurobench |
| 68 | NB-CT1 | Neurobench |
| 69 | NB-CT2 | Neurobench |
| 70 | NB-ES1 | Neurobench |
| 71 | NB-RP1 | Neurobench |
| 72 | NB-RP2 | Neurobench |
| 73 | NB-RE1 | Neurobench |
| 74 | NH-cross-suite-client | Neurohub |
| 75 | NH-backend-health-monitor | Neurohub |
| 76 | NH-activity-collector | Neurohub |
| 77 | NH-backend-assets | Neurohub |
| 78 | NH-backend-workflows | Neurohub |
| 79 | NH-frontend-providers | Neurohub |
| 80 | NH-frontend-dashboard | Neurohub |
| 81 | NH-frontend-project-manager | Neurohub |
| 82 | NH-frontend-asset-browser | Neurohub |
| 83 | NH-frontend-workflow-editor | Neurohub |
