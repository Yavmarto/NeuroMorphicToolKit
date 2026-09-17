import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

tasks = {
    "Neurosim": [
        (
            "NS-D1-place-populations",
            "Implement dragging and dropping LIF populations onto the canvas. Includes component library sidebar, node rendering, and basic parameters.",
            "Frontend UI",
        ),
        (
            "NS-D2-connect-populations",
            "Implement drawing directed edges between nodes. Includes clicking output ports, dragging to inputs, and real-time Layer 1 validation against invariants.",
            "Frontend UI",
        ),
        (
            "NS-D3-property-panel",
            "Build the property panel for configuring parameters of selected nodes or edges. Includes inline validation and sync with canvas.",
            "Frontend UI",
        ),
        (
            "NS-D4-templates",
            "Implement starter template gallery (reflex arc, CPG oscillator) that populates the canvas with pre-built circuits.",
            "Frontend UI",
        ),
        (
            "NS-D5-cnl-sync",
            "Implement bidirectional synchronization between the visual canvas and raw CNL spec text in a split view.",
            "Frontend UI",
        ),
        (
            "NS-S1-sim-preview",
            "Build real-time simulation preview panel. Dispatch to backend API and render spike raster plots matching <=500ms runs.",
            "Frontend UI",
        ),
        (
            "NS-S2-param-sweep",
            "Build parameter sweep dialog and grid visualization (SweepGrid). Integrate right-click context menu on parameters.",
            "Frontend UI",
        ),
        (
            "NS-S3-full-sim",
            "Implement full simulation execution with detailed configuration dialog (duration, inputs, seed) and results panel.",
            "Frontend UI",
        ),
        (
            "NS-E1-export",
            "Add export dialog allowing users to export design to Nengo Python, C Header, NeuroML, or raw CNL formats.",
            "Frontend UI",
        ),
        (
            "NS-E2-neurochip-integration",
            "Implement 'Deploy to Neurochip' button that pushes current spec to the Neurochip backend and opens it.",
            "Integration",
        ),
        (
            "NS-C1-save-load",
            "Implement project serialization (save to .neurosim file) and deserialization restoring full canvas state.",
            "Frontend logic",
        ),
        (
            "NS-C2-share-url",
            "Implement URL generation to share small projects encoded in base64 via query parameter.",
            "Frontend logic",
        ),
    ],
    "Neurobench": [
        (
            "NB-B1-standard-bench",
            "Implement UI to select and run standard benchmarks (grip stability, etc) yielding performance scores and metrics.",
            "Frontend UI",
        ),
        (
            "NB-B2-ci-cd-cli",
            "Implement CLI subcommands (`neurobench run`, `neurobench compare`) returning correct exit codes for CI/CD.",
            "Backend/CLI",
        ),
        (
            "NB-B3-custom-bench",
            "Support defining and loading custom benchmark JSON manifests including CNL assertions and inputs.",
            "Backend Data Storage",
        ),
        (
            "NB-CT1-cross-target",
            "Implement cross-target comparison (Teensy vs Loihi) displaying Pareto-optimal tables.",
            "Full Stack",
        ),
        (
            "NB-CT2-sim-real-gap",
            "Implement sim-to-real gap quantification. Requires collecting hardware metrics and comparing to Nengo baselines.",
            "Full Stack",
        ),
        (
            "NB-ES1-encoding-compare",
            "Implement UI comparing rate, temporal, and delta encoding strategies for a given task.",
            "Frontend UI",
        ),
        (
            "NB-R1-baselines-diff",
            "Implement baseline saving and diffing visualizations highlighting regressions vs improvements.",
            "Frontend UI",
        ),
        (
            "NB-R2-regression-alerts",
            "Implement configurable thresholds that fail CLI executions or report warnings on threshold violations.",
            "Backend Logic",
        ),
        (
            "NB-RP1-fault-sweep",
            "Implement fault injection capability invoking neurodreamhand across valid ranges and plot robustness curve.",
            "Full Stack",
        ),
        (
            "NB-RP2-input-perturbation",
            "Sweep input noise limits to determine sensitivity, utilizing real signals via NeuroSense.",
            "Full Stack",
        ),
        (
            "NB-RE1-benchmark-report",
            "Generate comprehensive PDF/HTML exports summarizing bench results using reportlab/weasyprint.",
            "Backend Services",
        ),
    ],
    "Neurochip": [
        (
            "NC-p2-hardware-profiles",
            "Create JSON manifests for teensy41 and loihi2 defining their constraints.",
            "Backend Data",
        ),
        (
            "NC-p2-firmware-templates",
            "Create Jinja2 templates for C/C++ generation (main.ino.j2, lif_engine.h.j2) and python scripts for Loihi.",
            "Backend Data",
        ),
        (
            "NC-p3-constraint-analyzer",
            "Complete 'constraint_analyzer.py' enforcing typing rules without mock dependencies.",
            "Backend Services",
        ),
        (
            "NC-p3-quantization-power",
            "Complete 'quantizer.py' and 'power_estimator.py' integrating neurodreamhand accurate models.",
            "Backend Services",
        ),
        (
            "NC-p3-fault-runner",
            "Complete 'fault_runner.py' wrapping robustness sweeps.",
            "Backend Services",
        ),
        (
            "NC-p3-code-gen-flash",
            "Implement 'teensy_generator.py' with CLI subprocess calls via PlatformIO.",
            "Backend Services",
        ),
        (
            "NC-p3-deployment-store",
            "Implement persistent deployment logging data model.",
            "Backend Storage",
        ),
        (
            "NC-p4-target-selector",
            "Build the target selector dropdown fetching async profiles from the backend API.",
            "Frontend UI",
        ),
        (
            "NC-p4-quantization-explorer",
            "Build visual bit-width charting widget comparing drops in accuracy to energy savings.",
            "Frontend UI",
        ),
        (
            "NC-p4-constraint-report",
            "Build immediate feedback card summarizing invariant and memory constraints for the current network.",
            "Frontend UI",
        ),
        (
            "NC-p4-deployment-flow",
            "Build 'FirmwareGeneratorPanel' with progress indicators tying to the flash execution endpoints.",
            "Frontend UI",
        ),
        (
            "NC-p5-testing",
            "Write pytest suites and frontend widget tests to achieve acceptable coverage in CI.",
            "Testing",
        ),
    ],
    "Neurosense": [
        (
            "NSe-DM2-impedance-checks",
            "Implement impedance checks logic highlighting unsafe channels in UI before recording.",
            "Frontend UI / Backend API",
        ),
        (
            "NSe-DM3-offline-mode",
            "Add mock fallback mode loading playback files for testing without physical devices.",
            "Backend Services",
        ),
        (
            "NSe-SA1-live-viewer",
            "Build 60fps high-performance timeseries real-time chart for live signal viewing.",
            "Frontend UI",
        ),
        (
            "NSe-SA2-quality-dashboard",
            "Calculate and display signal-to-noise ratios (SNR) and artifact presence live.",
            "Frontend UI",
        ),
        (
            "NSe-SE1-spike-encoding",
            "Implement dynamic encoding techniques locally converting continuous signals to spike trains.",
            "Backend Services",
        ),
        (
            "NSe-SE2-encoding-compare",
            "Build UI panel to visually overlay encoded spikes atop the raw continuous signals.",
            "Frontend UI",
        ),
        (
            "NSe-RS1-record-playback",
            "Add capabilities to start/stop saving sessions and loading them for playback streaming.",
            "Full Stack",
        ),
        (
            "NSe-RS2-cnl-integration",
            "Automate streaming recorded sessions as inputs to neurocnl networks.",
            "Integration",
        ),
    ],
    "Neurohub": [
        (
            "NH-backend-workflows",
            "Implement workflow logic and state management connected to database transactions.",
            "Backend Services",
        ),
        (
            "NH-backend-assets",
            "Implement asset upload and versioning logic for shared CNL library.",
            "Backend Services",
        ),
        (
            "NH-backend-health-monitor",
            "Implement health status polling of all companion applications.",
            "Backend Services",
        ),
        (
            "NH-cross-suite-client",
            "Develop python HTTP clients facilitating bidirectional calls across local servers.",
            "Integration",
        ),
        (
            "NH-activity-collector",
            "Collect streams of project execution states from all connected components (NeuroSim, NeuroChip, etc).",
            "Backend Services",
        ),
        (
            "NH-frontend-dashboard",
            "Flesh out central dashboard widgets indicating recent activities and statuses.",
            "Frontend UI",
        ),
        (
            "NH-frontend-project-manager",
            "Build the Project CRUD UI and detailed project overview screen.",
            "Frontend UI",
        ),
        (
            "NH-frontend-workflow-editor",
            "Build out the complex pipeline DAG workflow editor connecting multi-app steps.",
            "Frontend UI",
        ),
        (
            "NH-frontend-asset-browser",
            "Implement list views of available datasets and neural network configurations.",
            "Frontend UI",
        ),
        (
            "NH-frontend-providers",
            "Replace all frontend UI mocks with Riverpod logic referencing backend API clients.",
            "Frontend Logic",
        ),
    ],
    "nmtk": [
        (
            "NMTK-01-setup-to-pyproject",
            "Migrate Neuro-Dream-Hand from setup.py to pyproject.toml and hatchling.",
            "Tooling",
        ),
        (
            "NMTK-02-ruff-formatting",
            "Unify both python projects under Ruff linting, remove all raw print statements for logging.",
            "Tooling",
        ),
        (
            "NMTK-03-mypy-typing",
            "Bring both python environments to mypy --strict pass standards.",
            "Tooling",
        ),
        (
            "NMTK-04-cnl-typeddict",
            "Replace untyped dicts returned by the CNL parser with explicit TypedDict `ParsedSentence`.",
            "Refactoring",
        ),
        (
            "NMTK-05-pipeline-collapse",
            "Unify simulate duplication under a single `run_pipeline` orchestration file in neurocnl.",
            "Refactoring",
        ),
        (
            "NMTK-06-flutter-analysis-opts",
            "Introduce `analysis_options.yaml` in frontend projects based on flutter_lints.",
            "Tooling",
        ),
        (
            "NMTK-07-backend-tests",
            "Add base testing suites hitting FastAPI endpoints via TestClient in neurocnl.",
            "Testing",
        ),
        (
            "NMTK-08-frontend-tests",
            "Add tests for riverpod state models and API serialization.",
            "Testing",
        ),
        (
            "NMTK-09-unified-ci",
            "Setup GitHub Actions covering `ruff`, `mypy`, `pytest` + Flutter equivalents.",
            "DevOps",
        ),
        (
            "NMTK-10-background-jobs",
            "Refactor Nengo simulation endpoints into async background tasks issuing uuid 202 requests.",
            "Backend APIs",
        ),
        (
            "NMTK-11-request-id",
            "Implement request ID middleware generating unique identifiers for all API queries.",
            "Backend APIs",
        ),
        (
            "NMTK-12-health-endpoint",
            "Upgrade existing health logic to report module readiness (nengo, mujoco, etc).",
            "Backend APIs",
        ),
        (
            "NMTK-13-externalize-api-url",
            "Ensure API locators in dart code read from environment variables `--dart-define`.",
            "Frontend Logic",
        ),
        (
            "NMTK-14-ndh-dependency",
            "Officially introduce `neurodreamhand` as a requirement into the main backend ecosystem.",
            "Integration",
        ),
        (
            "NMTK-15-cnl-templates",
            "Expand `/api/templates` to serve prosthetic use cases and examples.",
            "Backend APIs",
        ),
        (
            "NMTK-16-prosthetic-simulate",
            "Host native drop test runs inside neurocnl through `POST /api/prosthetic/simulate`.",
            "Backend APIs",
        ),
        (
            "NMTK-17-prosthetic-sleep",
            "Provide sleep optimization API executing STDP routines inside SNNs.",
            "Backend APIs",
        ),
        (
            "NMTK-18-prosthetic-export",
            "Add capabilities to generate parameter exports (like HDF5) straight from the centralized backend.",
            "Backend APIs",
        ),
        (
            "NMTK-19-go-router",
            "Overhaul base flutter apps combining navigation beneath `go_router`.",
            "Frontend Library",
        ),
        (
            "NMTK-20-navigation-rail",
            "Use a centralized UI container housing `NavigationRail` component matching material desktop patterns.",
            "Frontend Library",
        ),
        (
            "NMTK-21-nmtk-ui-core",
            "De-duplicate UI artifacts building generic buttons/charts into nested `nmtk_ui_core`.",
            "Frontend Library",
        ),
        ("NMTK-22-dependabot", "Roll out Dependabot configurations.", "Maintenance"),
        (
            "NMTK-23-trivy-codeql",
            "Add automated CodeQL + Trivy action workflows for CVSS tracking.",
            "Security",
        ),
        (
            "NMTK-24-pre-commit",
            "Produce a centralized `.pre-commit-config.yaml` governing pre-push validation.",
            "Tooling",
        ),
        (
            "NMTK-25-codecov",
            "Link pytest coverage measurements with PR dashboards.",
            "Tooling",
        ),
        (
            "NMTK-26-git-cliff",
            "Utilize `git-cliff` for changelog formulation matching conventional commits.",
            "Release",
        ),
        (
            "NMTK-27-semantic-release",
            "Deploy `python-semantic-release` pipeline updating tag versions globally.",
            "Release",
        ),
        (
            "NMTK-28-sphinx-docs",
            "Adopt Sphinx rendering python docstrings to an internal documentation hub.",
            "Documentation",
        ),
        (
            "NMTK-29-docker-ci",
            "Verify image build success incrementally in Github Action PR constraints.",
            "CI / CD",
        ),
        (
            "NMTK-30-pio-ci",
            "Utilize specialized firmware actions simulating compilation via PlatformIO against varied uCs.",
            "CI / CD",
        ),
    ],
}

base_dir = os.path.dirname(os.path.abspath(__file__))
# Make sure to first clear out old generic issues created earlier
for folder, t_list in tasks.items():
    issues_dir = os.path.join(base_dir, folder, "issues")
    os.makedirs(issues_dir, exist_ok=True)

    # Optional: Delete existing placeholder issues created previously.
    # We will just overwrite/create. A separate rm command could be run.

    for task_name, desc, category in t_list:
        file_path = os.path.join(issues_dir, f"{task_name}.md")
        content = f"""# Task: {task_name.replace("-", " ")}
## Category
{category}

## Description
{desc}

## Action Items
- Set up an independent environment and confirm prerequisites for this specific task.
- Ensure work corresponds accurately to the module's specification and architecture constraints.
- Implement the functionality requested.
- Write tests confirming behavior (if applicable).
"""
        with open(file_path, "w") as f:
            f.write(content)

logger.info(
    f"Generated {sum(len(v) for v in tasks.values())} independent task files across submodules."
)
