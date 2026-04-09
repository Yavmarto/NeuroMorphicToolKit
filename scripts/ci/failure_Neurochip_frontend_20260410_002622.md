# CI Failure Report: Neurochip_frontend

**Date:** 2026-04-10 00:26:22

## Failed Stages

### test

```
00:00 +0: loading /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widget_test.dart
00:00 +0: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widget_test.dart: App smoke test
00:00 +0 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widget_test.dart: App smoke test
00:00 +0 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/integration_test.dart: E2E Integration Test (Flutter to Backend) Full flow from targets to quantization and analysis [E]
  ClientException with SocketException: Connection refused (OS Error: Connection refused, errno = 61), address = localhost, port = 55645, uri=http://localhost:8000/api/neurochip/targets
  package:http/src/io_client.dart 227:7  IOClient.send
  
00:00 +1 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widget_test.dart: App smoke test
00:00 +2 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widget_test.dart: App smoke test
00:00 +3 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widget_test.dart: App smoke test
00:01 +4 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widgets/target_selector_test.dart: TargetSelector shows loading indicator then dropdown
00:01 +5 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widgets/target_selector_test.dart: TargetSelector shows error message on failure
00:01 +6 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widgets/quantization_explorer_test.dart: QuantizationExplorer shows title and slider
00:02 +7 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widgets/quantization_explorer_test.dart: QuantizationExplorer shows title and slider
00:02 +8 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/widgets/quantization_explorer_test.dart: Slider changes bit-width label
00:02 +9 -1: Some tests failed.
```

