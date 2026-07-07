# Custom Node Integration Plan (Neurohub & NeuroSim)

## Goal
Enable users to seamlessly share their custom Python nodes to Neurohub and discover/install other users' custom nodes directly into the NeuroSim canvas.

## Current State
- **Backend (NeuroSim)**: Fully supports saving and installing custom nodes via `neurocnl/neurosim/app/routers/custom_nodes.py` (`/install`, `/save`, `/delete`).
- **Backend (Neurohub)**: Fully supports `custom_node` as an artefact type (`ArtefactType.custom_node`).
- **Frontend**: `custom_node` is missing from the share options in `ShareModelScreen`, and there is no UI to install a node from Neurohub directly into NeuroSim.

## Implementation Steps

### Phase 1: Enable Sharing Custom Nodes to Neurohub
**Target**: `Neurohub/frontend/lib/screens/share_model_screen.dart`
1. **Update Types**: Add `'custom_node'` to the `_assetTypes` list at the top of the file.
2. **UI Validation**: When `_selectedType == 'custom_node'`, dynamically update the file picker hint to request a valid `.py` file, as the NeuroSim backend requires `filename.endswith('.py')`.

### Phase 2: Beautiful Rendering in Neurohub Feed
**Target**: `Neurohub/frontend/lib/widgets/asset_card.dart` (and related list views)
1. **Icon Mapping**: Add a specific icon mapping for `custom_node` (e.g., `ZetaIcons.extension` or `ZetaIcons.code`).
2. **Badge Color**: Assign a distinct badge color/tone for `custom_node` using `NmtkStatusBadge`.

### Phase 3: Seamless Installation Flow
**Target**: `Neurohub/frontend/lib/screens/project_detail_screen.dart` (or asset inspection screen)
1. **Install Action**: For assets of type `custom_node`, add a primary action button: **"Install to NeuroSim"**.
2. **API Call**: Bind this button to call the NeuroSim backend: `POST /api/neurosim/custom-nodes/install`.
   - **Payload**: `{ "download_url": <hub_asset_public_url>, "filename": <asset_name>.py }`
3. **Feedback**: Show an `NmtkSnackBar` on successful installation or if the neurosim service is unreachable.

### Phase 4: Canvas Component Library Sync (Verification)
**Target**: `neurocnl/frontend/lib/widgets/canvas/...` (Component Library)
1. **Verify Visibility**: Ensure that once a custom node is installed locally (via the `/install` route), it automatically surfaces in the Canvas component sidebar. The backend `services/components.py` already merges custom nodes, so this might work natively, but the frontend state might require an explicit refresh trigger when returning from Neurohub to the Canvas tab.
