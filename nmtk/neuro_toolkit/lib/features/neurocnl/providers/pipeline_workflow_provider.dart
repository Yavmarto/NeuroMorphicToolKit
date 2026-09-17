import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/services/pipeline_workflow_service.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

/// Feature-local construction seam for the API-only pipeline workflow.
final pipelineWorkflowServiceProvider = Provider<PipelineWorkflowService>((
  ref,
) {
  return PipelineWorkflowService(ref.watch(apiClientProvider));
});
