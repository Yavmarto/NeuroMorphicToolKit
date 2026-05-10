# Documentation Architecture

## Audiences

- **Beginners**: First-time users evaluating the toolkit, learning neuromorphic concepts, and running pre-built models.
- **Intermediate**: Model authors building custom SNNs, exporting to NIR, and validating across simulators.
- **Advanced**: Backend developers deploying to hardware, benchmarking performance, and troubleshooting platform-specific limitations.

## User Journeys

1. **First-Time Evaluation**: Install toolkit -> run model-zoo example -> verify output -> understand capabilities.
2. **Model Authoring**: Learn CNL syntax -> build custom network -> validate locally -> export to NIR.
3. **Backend Deployment**: Select target backend -> check capability matrix -> deploy model -> handle platform constraints.
4. **Benchmarking and Validation**: Load reference model -> run across backends -> compare metrics -> interpret divergence.

## Proposed Hierarchy

### Getting Started (Beginner)

**Purpose**: Install the toolkit, run first example, and verify setup in under 10 minutes.

- Installation (pip/conda)
- Quick Start: Run a pre-trained model from the zoo
- Verify output and inspect results
- Next steps roadmap

### CNL Language Reference (Intermediate)

**Purpose**: Complete syntax guide for building neuromorphic models in CNL.

- Neuron types (LIF, Izhikevich, etc.)
- Connection patterns (dense, convolutional, recurrent)
- Input/output layers and encoding schemes
- Type system and validation rules
- Visual editor vs. textual syntax

### Model Zoo Overview (Beginner/Intermediate)

**Purpose**: Catalog of pre-built models with usage examples and expected outputs.

- Available models by task (classification, temporal processing, etc.)
- Model metadata (architecture, training method, accuracy)
- Loading and running zoo models
- Customizing pre-built models

### NIR Export and Limitations (Intermediate/Advanced)

**Purpose**: Explain NIR export process and document unsupported features per backend.

- CNL-to-NIR translation rules
- Supported vs. unsupported neuron types
- Backend-specific constraints (precision, connectivity, dynamics)
- Fallback strategies and error messages
- Debugging export failures

### Backend Capability Guide (Advanced)

**Purpose**: Comparison matrix of backend features to guide deployment decisions.

- Supported backends (simulators: snnTorch, Norse, etc.; hardware: Loihi, Akida, etc.)
- Capability matrix (neuron types, plasticity, precision, latency)
- Platform-specific setup (drivers, access requirements)
- Performance characteristics (throughput, power, scalability)

### Benchmarking Guide (Advanced)

**Purpose**: Run standardized benchmarks and interpret cross-backend results.

- Benchmark suite overview (accuracy, latency, energy)
- Running benchmarks across backends
- Interpreting metrics (spike similarity, divergence, spread)
- Reporting and visualization
- Known platform-specific quirks

### Troubleshooting (All Levels)

**Purpose**: Diagnose common errors and resolve platform-specific issues.

- Installation and dependency issues
- CNL validation errors
- NIR export failures
- Backend deployment errors (driver, memory, connectivity)
- Performance debugging (slow inference, high power)
- Where to get help (GitHub issues, community forum)

## Minimum Example Inventory

### Getting Started

- Install command with version check
- Load and run a simple classification model (e.g., MNIST SNN)
- Inspect spike output and accuracy

### CNL Language Reference

- Define a 2-layer LIF network (input -> hidden -> output)
- Add recurrent connections
- Use convolutional topology
- Encode rate-based input

### Model Zoo Overview

- List available models with metadata
- Load a pre-trained model by ID
- Run inference and validate output format

### NIR Export and Limitations

- Export CNL model to NIR graph
- Attempt export with unsupported feature (show error message)
- Check backend compatibility before export

### Backend Capability Guide

- Query supported neuron types for a backend
- Compare latency across three backends for the same model
- Set up hardware backend (e.g., Akida) with minimal config

### Benchmarking Guide

- Run accuracy benchmark on model-zoo model
- Compare spike similarity across backends
- Generate benchmark report table

### Troubleshooting

- Fix "unsupported neuron type" error by switching backend
- Resolve NIR export failure due to dynamic topology
- Debug slow inference by profiling backend

## Recommended Build Order

1. **Getting Started** (Priority 1): Unblock first-time users immediately; validate installation flow.
2. **Model Zoo Overview** (Priority 1): Enable evaluation without requiring CNL knowledge.
3. **CNL Language Reference** (Priority 2): Support model authoring once users are onboarded.
4. **Backend Capability Guide** (Priority 2): Help users choose deployment targets early.
5. **NIR Export and Limitations** (Priority 3): Document export constraints as users hit them.
6. **Troubleshooting** (Priority 3): Capture common issues from early user feedback.
7. **Benchmarking Guide** (Priority 4): Support advanced validation after deployment works.

**Execution Strategy**: Start with Priority 1 pages to enable evaluation, then iterate based on user feedback. Troubleshooting should be updated continuously as issues emerge.
