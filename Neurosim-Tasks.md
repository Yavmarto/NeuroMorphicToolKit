# Neurosim — Concrete Tasks to 100% POC Readiness

1. **Wire Canvas Interactions to API**
   - *Description:* The `network_canvas.dart` CustomPainter handles drag-and-drop, but needs to be fully wired to trigger the `ApiClient.runPreview()` and CNL generation when connections are made.
   - *Impact:* Makes the visual designer functional rather than just a drawing tool.

2. **Write Python Integration Tests**
   - *Description:* Add tests in the backend that exercise the full pipeline: JSON Graph -> Parse to CNL -> Validate -> Simulate -> Return Preview.
   - *Impact:* Ensures the core simulation orchestration doesn't break.

3. **Fix Mypy Route Errors**
   - *Description:* Fix missing return types on FastAPI route decorators to silence `mypy` warnings.
   - *Impact:* Achieves strict adherence to the Python coding style guide.
