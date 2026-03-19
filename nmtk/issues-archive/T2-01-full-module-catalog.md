# Add All 7 Modules to Launcher Catalog

**Priority:** High — POC Enhancement  
**Type:** Feature  
**Tier:** 2 (Should Do)  
**Estimated Effort:** 2 hours  

## Description

The neuro_toolkit CatalogScreen currently only lists 3 hardcoded modules (Neuro-Dream-Hand, neurocnl, nmtk). It should list all 7 suite modules with accurate metadata.

## Requirements

1. **Add modules to the catalog data source:**
   | Module | Display Name | Description | Port | Has Frontend? |
   |--------|-------------|-------------|------|---------------|
   | neurocnl | CNL Studio | CNL parser, SNN generator, and simulation engine | 8000 | Yes |
   | Neurosim | NeuroSim | Visual drag-and-drop SNN design canvas | 8001 | Minimal |
   | Neurochip | NeuroChip | Hardware deployment and firmware generation | 8002 | Partial |
   | Neurobench | NeuroBench | SNN testing and benchmarking workbench | 8003 | Scaffold |
   | Neurosense | NeuroSense | Biosignal acquisition and spike encoding | 8004 | Partial |
   | Neurohub | NeuroHub | Suite dashboard and project orchestrator | 8005 | Scaffold |
   | Neuro-Dream-Hand | NDH Simulator | Prosthetic SNN physics simulation (CLI only) | N/A | No |

2. **Module metadata:**
   - Each entry should include: name, description, icon, backend port, install path, whether it has a frontend
   - Load from a JSON manifest file (`assets/modules.json`) rather than hardcoding

3. **Visual updates:**
   - Show status badge (Installed / Not Installed / Running)
   - Gray out modules that require unavailable dependencies (e.g., MuJoCo)

## Acceptance Criteria

- All 7 modules appear in the CatalogScreen
- Module metadata is loaded from a JSON file, not hardcoded
- Each module shows its correct status

## Files Affected

```
nmtk/neuro_toolkit/assets/modules.json                      ← new
nmtk/neuro_toolkit/lib/models/module.dart                    ← update fields
nmtk/neuro_toolkit/lib/providers/module_provider.dart        ← load from JSON
nmtk/neuro_toolkit/lib/screens/catalog.dart                  ← update UI
```
