# Implementation Plan: CNL Support for Training and Evaluation

## 1. Motivation
Currently, the Architecture tab uses the Cognitive Neural Language (CNL) to define the network structure, while the Pipeline tab uses a simple JSON payload (`PipelineConfig`) for the training and evaluation canvas. To unify the tool's expressive power, this plan outlines how to bring full CNL support to the training and evaluation pipeline, including visual UI updates to allow drawing the pipeline rather than just configuring it in a form.

## 2. CNL Language Extensions
We will extend the CNL grammar to support a `pipeline` block, replacing the existing JSON payload.

**Example Syntax:**
```cnl
pipeline {
    training {
        epochs: 50
        learning_rate: 0.001
        batch_size: 32
        optimizer: Adam
        strategy: surrogate_gradient
        loss_function: mse_count
    }
    evaluation {
        run_evaluation: true
        metrics: [accuracy, loss]
    }
    export {
        export_nir: false
        generate_py_download: true
    }
}
```

## 3. Frontend (UI) Changes
To fully utilize CNL for the pipeline, the Pipeline tab must become a fully functional drawing canvas similar to the Architecture tab.

1. **Visual Pipeline Canvas (`pipeline_canvas.dart`)**:
   - Introduce new visual node types in the pipeline tab (e.g. `DatasetNode`, `OptimizerNode`, `LossNode`, `TrainingLoopNode`).
   - Allow users to drag and drop these nodes to visually wire the training pipeline (e.g., `Dataset -> TrainingLoop -> Loss <- Optimizer`).
   - Create a `PipelineGraph` model that tracks these nodes and connections.

2. **CNL Serialization (`pipeline_config.dart` / `pipeline_graph.dart`)**:
   - Add a `toCnl()` method to serialize the `PipelineGraph` state into a CNL string block instead of, or alongside, the legacy `toJson()`.

3. **State Management (`canvas_provider.dart`)**:
   - Update `CanvasState` to aggregate the CNL from `graph` (Architecture) and the newly created pipeline graph.

4. **API Integration (`notebook_generate_service.dart`)**:
   - Change the backend payload. Instead of sending `{ spec: cnlSpec, pipeline_config: json }`, combine them into a single comprehensive CNL string: `{ spec: fullCnlSpec }`.

## 4. Backend Changes (Parser & Notebook Generation)
1. **CNL Parser Updates (`neurocnl/backend/app/parser/`)**:
   - Update the CNL grammar (e.g. Lark or TextX grammar files) to include `pipeline`, `training`, `evaluation`, and `export` block tokens.
   - Extend the AST visitor/transformer to parse these blocks directly into the existing internal `PipelineConfigPayload` dataclass, ensuring backward compatibility with notebook generation.

2. **Endpoint Updates (`neurocnl/backend/app/routers/notebook.py`)**:
   - Update `GenerateV2Request` to make the `pipeline_config` JSON field optional or deprecated, relying solely on `spec` (which will now contain both architecture and pipeline CNL).
   - Adjust `_build_v2_notebook()` to extract the pipeline configuration directly from the parsed CNL AST.

## 5. Execution Steps
- **Phase 1: Parser & Backend Updates** - Update the Python CNL parser to accept the new syntax, and modify the generation endpoints. Write unit tests for the parser.
- **Phase 2: Visual Pipeline Canvas (UI)** - Build the drag-and-drop nodes for the Pipeline tab in Flutter so users can visually draw the training process.
- **Phase 3: Frontend Serialization** - Update the pipeline state models to implement `toCnl()` and send the unified CNL text to the backend.
- **Phase 4: Deprecation** - Remove the legacy JSON `pipeline_config` from the backend once the unified CNL payload is fully tested and generating notebooks correctly.
