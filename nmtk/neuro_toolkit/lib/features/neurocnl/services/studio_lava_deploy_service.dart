import 'package:neuro_toolkit/features/neurocnl/services/neurochip_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';

class StudioLavaDeployException implements Exception {
  const StudioLavaDeployException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StudioLavaDeployService {
  StudioLavaDeployService({
    required ApiClient apiClient,
    required NeurochipClient neurochipClient,
  }) : _apiClient = apiClient,
       _neurochipClient = neurochipClient;

  final ApiClient _apiClient;
  final NeurochipClient _neurochipClient;

  Future<Map<String, dynamic>> validate({
    required String spec,
    required int bitWidth,
  }) async {
    try {
      return await _apiClient.getLavaDeployability(spec, bitWidth: bitWidth);
    } catch (error) {
      throw StudioLavaDeployException(
        formatDeployError(
          error,
          serviceName: 'NeuroStudio',
          action: 'checking Lava simulator exportability',
        ),
      );
    }
  }

  Future<String> compile({
    required Map<String, dynamic> deployPayload,
    required String runConfig,
  }) async {
    try {
      return await _neurochipClient.compileLavaNetwork(
        deployPayload,
        runConfig: runConfig,
      );
    } catch (error) {
      throw StudioLavaDeployException(
        formatDeployError(
          error,
          serviceName: 'Neurochip',
          action: runConfig == 'hw'
              ? 'checking Lava hardware preflight'
              : 'compiling the Lava simulator network',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> run({
    required String sessionId,
    required int steps,
  }) async {
    try {
      return await _neurochipClient.runLavaSession(sessionId, steps: steps);
    } catch (error) {
      throw StudioLavaDeployException(
        formatDeployError(
          error,
          serviceName: 'Neurochip',
          action: 'running the Lava simulator network',
        ),
      );
    }
  }
}
