"""GET /api/templates — list available CNL templates."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()

_TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "templates"

_TEMPLATE_META: list[dict] = [
    {
        "id": "reflex_arc",
        "name": "Basic Reflex Arc",
        "description": "Minimal sensory-motor reflex with threshold, refractory, decay, and weight.",
        "category": "Basics",
        "tags": ["beginner", "motor-control", "reflex"],
        "difficulty": "beginner",
        "filename": "reflex_arc.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "slip_reflex",
        "name": "Tactile Slip Reflex",
        "description": "3-neuron slip reflex with axonal delay for fast grip correction.",
        "category": "Motor Control",
        "tags": ["intermediate", "motor-control", "tactile"],
        "difficulty": "intermediate",
        "filename": "slip_reflex.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "emg_gripper",
        "name": "EMG Adaptive Gripper",
        "description": "EMG-driven gripper with STDP learning for adaptive grip strength.",
        "category": "Motor Control",
        "tags": ["advanced", "emg", "stdp", "adaptive"],
        "difficulty": "advanced",
        "filename": "emg_gripper.cnl",
        "supported_targets": ["snntorch_sim"],  # STDP learning rule not in NIR standard
    },
    {
        "id": "eeg_attention",
        "name": "EEG Attention Monitor",
        "description": "Classify attention state from EEG alpha band using rate coding.",
        "category": "Cognitive",
        "tags": ["intermediate", "eeg", "bci", "rate-coding"],
        "difficulty": "intermediate",
        "filename": "eeg_attention.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "audio_wakeword",
        "name": "Audio Wake-Word Detector",
        "description": "Detect wake words using temporal coincidence detection with STDP.",
        "category": "Signal Processing",
        "tags": ["advanced", "audio", "stdp", "temporal"],
        "difficulty": "advanced",
        "filename": "audio_wakeword.cnl",
        "supported_targets": ["snntorch_sim"],  # STDP not in NIR standard
    },
    {
        "id": "visual_tracker",
        "name": "Visual Saccade Tracker",
        "description": "Simple visual tracking circuit: retinal sensor drives saccadic eye movement.",
        "category": "Basics",
        "tags": ["beginner", "visual", "tracking", "saccade"],
        "difficulty": "beginner",
        "filename": "visual_tracker.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "object_recognition",
        "name": "Object Recognition Starter",
        "description": "Rate-coded visual classifier with a compact hidden layer and 10-class output.",
        "category": "Vision",
        "tags": ["beginner", "visual", "classification", "object-recognition"],
        "difficulty": "beginner",
        "filename": "object_recognition.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "prosthetic_reflex",
        "name": "Prosthetic Reflex Arc",
        "description": "Slip-velocity PD reflex controller for prosthetic hand grip stabilization",
        "category": "Motor Control",
        "tags": ["advanced", "prosthetic", "reflex", "motor-control"],
        "difficulty": "advanced",
        "filename": "prosthetic_reflex.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "prosthetic_sleep",
        "name": "Prosthetic Sleep Consolidation",
        "description": "Offline PES replay network for memory consolidation during sleep phases",
        "category": "Cognitive",
        "tags": ["advanced", "prosthetic", "sleep", "memory-consolidation"],
        "difficulty": "advanced",
        "filename": "prosthetic_sleep.cnl",
        "supported_targets": ["snntorch_sim"],  # PES learning rule not in NIR standard
    },
    {
        "id": "looming_detector",
        "name": "Looming Detector",
        "description": "Detects approaching objects using spatial connectivity and short-term facilitation.",
        "category": "Vision",
        "tags": ["intermediate", "visual", "spatial", "stp", "looming"],
        "difficulty": "intermediate",
        "filename": "looming_detector.cnl",
        "supported_targets": [
            "snntorch_sim",
            "lava_sim",
        ],  # STP is metadata-only; no advanced learning rules block Lava
    },
    {
        "id": "cpg_rhythm",
        "name": "Rhythm Generator (CPG)",
        "description": "A central pattern generator (CPG) using adaptive spiking for self-timed rhythmic activity.",
        "category": "Motor Control",
        "tags": ["intermediate", "motor-control", "adaptive-spiking", "cpg"],
        "difficulty": "intermediate",
        "filename": "cpg_rhythm.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "stochastic_decision",
        "name": "Probabilistic Decision Maker",
        "description": "Two competing populations using background noise to decide between inputs via stochastic resonance.",
        "category": "Cognitive",
        "tags": ["advanced", "cognitive", "noise", "stochastic", "decision-making"],
        "difficulty": "advanced",
        "validation_backend": "nir",
        "filename": "stochastic_decision.cnl",
        "supported_targets": ["snntorch_sim"],  # Poisson noise sources not in Lava NIR
    },
    {
        "id": "coincidence_detector",
        "name": "Temporal Coincidence Detector",
        "description": "Uses AMPA and NMDA dynamics to detect coincident spikes across different time scales.",
        "category": "Signal Processing",
        "tags": [
            "intermediate",
            "signal-processing",
            "receptor-dynamics",
            "coincidence-detection",
        ],
        "difficulty": "intermediate",
        "filename": "coincidence_detector.cnl",
        "supported_targets": ["snntorch_sim"],  # AMPA/NMDA receptor dynamics not in Lava
    },
    {
        "id": "edge_enhancement",
        "name": "Edge Enhancement Grid",
        "description": "A 2D grid of neurons with local spatial connectivity and lateral inhibition for edge enhancement.",
        "category": "Vision",
        "tags": ["advanced", "visual", "spatial", "lateral-inhibition", "grid"],
        "difficulty": "advanced",
        "filename": "edge_enhancement.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "visual_homeostasis_gate",
        "name": "Visual Homeostasis Gate",
        "description": "Shape-aware salience map with one-to-one retinal mapping, lateral inhibition, homeostasis, STP, neuromodulation, and executable NIR delays.",
        "category": "Vision",
        "tags": ["advanced", "nir", "homeostasis", "stp", "lateral-inhibition"],
        "difficulty": "advanced",
        "validation_backend": "nir",
        "filename": "visual_homeostasis_gate.cnl",
        "supported_targets": ["snntorch_sim"],  # STP + neuromodulation in NIR graph
    },
    {
        "id": "shd_digit_classifier",
        "name": "SHD Spoken-Digit Classifier",
        "description": "Rate-coded spiking classifier for the Spiking Heidelberg Digits (SHD) dataset — 700 cochlea channels, 20 spoken-digit classes.",
        "category": "Signal Processing",
        "tags": ["intermediate", "audio", "classification", "shd"],
        "difficulty": "intermediate",
        "filename": "shd_digit_classifier.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim"],
    },
    {
        "id": "shd_digit_classifier_akida",
        "name": "SHD Spoken-Digit Classifier (Akida)",
        "description": "Akida-hardware-sized variant of the SHD classifier — drops the 700-neuron cochlea encoding stage (exceeds Akida's 256-neurons-per-NP limit) for a 700→128→20 feed-forward chain that fits the card. Expect somewhat lower accuracy than the full-fidelity template.",
        "category": "Signal Processing",
        "tags": ["intermediate", "audio", "classification", "shd", "akida"],
        "difficulty": "intermediate",
        "filename": "shd_digit_classifier_akida.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim", "akida"],
    },
    {
        "id": "ntidigits_digit_classifier",
        "name": "N-TIDIGITS Spoken-Digit Classifier",
        "description": "Rate-coded spiking classifier for the N-TIDIGITS18 silicon-cochlea dataset — 64 input channels, 11 single-spoken-digit classes. 64 channels is well under Akida's 256-neurons-per-NP limit, so this one topology reaches the simulator and the Akida card directly.",
        "category": "Signal Processing",
        "tags": ["intermediate", "audio", "classification", "ntidigits", "akida"],
        "difficulty": "intermediate",
        "filename": "ntidigits_digit_classifier.cnl",
        "supported_targets": ["snntorch_sim", "lava_sim", "akida"],
    },
    {
        "id": "mnist_cnn_classifier_akida",
        "name": "MNIST CNN Classifier (Akida)",
        "description": "Convolutional variant of the MNIST classifier — one Conv2d+global-average-pool stage (28x28x1 in, 8 filters, 3x3 kernel) feeding a small dense head. First template to use Akida's Conv2d/AvgPool2d hardware path; the pool is sized to match the conv's own output extent exactly, since Akida's average pooling is always global. lava_sim has no Conv process, so this one is snnTorch/Akida only.",
        "category": "Vision",
        "tags": ["intermediate", "vision", "classification", "mnist", "conv2d", "akida"],
        "difficulty": "intermediate",
        "filename": "mnist_cnn_classifier_akida.cnl",
        "supported_targets": ["snntorch_sim", "akida"],
    },
    {
        "id": "dopamine_stp_decision",
        "name": "Dopamine STP Decision Circuit",
        "description": "Competing decision populations shaped by short-term plasticity, homeostatic rate targets, neuromodulation, and inhibitory competition.",
        "category": "Cognitive",
        "tags": ["advanced", "nir", "stp", "neuromodulation", "decision-making"],
        "difficulty": "advanced",
        "validation_backend": "nir",
        "filename": "dopamine_stp_decision.cnl",
        "supported_targets": ["snntorch_sim"],  # STP + neuromodulation in NIR graph
    },
]


class TemplateItem(BaseModel):
    id: str
    name: str
    description: str
    category: str
    tags: list[str]
    difficulty: str
    validation_backend: str = "nir"
    supported_targets: list[str] = ["snntorch_sim", "lava_sim"]
    spec: str


class TemplateListResponse(BaseModel):
    templates: list[TemplateItem]


@router.get("/templates", response_model=TemplateListResponse)
def list_templates() -> TemplateListResponse:
    items: list[TemplateItem] = []
    for meta in _TEMPLATE_META:
        path = _TEMPLATES_DIR / meta["filename"]
        if path.exists():
            spec = path.read_text()
        else:
            spec = f"# Template '{meta['name']}' file not found."
        items.append(
            TemplateItem(
                id=meta["id"],
                name=meta["name"],
                description=meta["description"],
                category=meta["category"],
                tags=meta["tags"],
                difficulty=meta["difficulty"],
                validation_backend=meta.get("validation_backend", "nir"),
                supported_targets=meta.get("supported_targets", ["snntorch_sim", "lava_sim"]),
                spec=spec,
            )
        )
    return TemplateListResponse(templates=items)
