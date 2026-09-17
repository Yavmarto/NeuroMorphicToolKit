import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';

void main() {
  group('formatDeployError', () {
    test('replaces generic 500 responses with a non-generic HTTP message', () {
      final message = formatDeployError(
        const ApiException(500, 'Internal Server Error'),
        serviceName: 'Neurochip',
        action: 'loading PYNQ targets',
      );

      expect(message, contains('HTTP 500'));
      expect(message, contains('No structured error details'));
      expect(message, isNot(contains('backend is running')));
    });

    test('surfaces detailed 422 response messages', () {
      final message = formatDeployError(
        const ApiException(
          422,
          '{"detail":{"messages":["weight_bit_width must be one of (8,) for PYNQ Z2."]}}',
        ),
        serviceName: 'NeuroStudio',
        action: 'checking PYNQ exportability',
      );

      expect(message, contains('weight_bit_width'));
      expect(message, contains('PYNQ Z2'));
    });

    test('formats launcher-control connectivity failures clearly', () {
      final message = formatDeployError(
        const LauncherControlApiException(
          500,
          'SocketException: Connection refused',
        ),
        serviceName: 'launcher control service',
        action: 'loading Akida targets',
      );

      expect(message, contains('Could not reach'));
      expect(message, contains('configured URL is correct'));
    });

    test('keeps runtime proxy details for connectivity failures', () {
      final message = formatDeployError(
        const LauncherControlApiException(
          502,
          '{"error":"Runtime request failed for POST http://203.0.113.51:8002/hardware/pynq/deploy: could not be reached: <urlopen error [Errno 61] Connection refused>","path":"/api/launcher/pynq/boards/board-1/deploy","method":"POST"}',
        ),
        serviceName: 'launcher control service',
        action: 'deploying to the PYNQ board',
      );

      expect(message, contains('Could not reach'));
      expect(message, contains('http://203.0.113.51:8002'));
      expect(message, contains('Connection refused'));
    });

    test('extracts nested runtime error bodies from launcher proxy failures', () {
      final message = formatDeployError(
        const LauncherControlApiException(
          500,
          '{"error":"Runtime request failed for POST http://203.0.113.51:8002/hardware/pynq/deploy: HTTP 500","runtimeBody":"{\\"detail\\":{\\"detail\\":\\"Overlay load failed: No Devices Found\\",\\"error_code\\":\\"PYNQ_OVERLAY_LOAD_FAILED\\"}}"}',
        ),
        serviceName: 'launcher control service',
        action: 'deploying to the PYNQ board',
      );

      expect(message, contains('Overlay load failed'));
      expect(message, contains('PYNQ_OVERLAY_LOAD_FAILED'));
    });
  });

  group('extractPipelineStepError', () {
    test(
      'extracts title, message, and hint from structured ApiException text',
      () {
        final error = extractPipelineStepError(
          'Simulation failed: ApiException(410): '
          '{"detail":{"error":"nir_simulation_unsupported","messages":["Simulation is no longer supported on the NIR-only NeuroCNL surface."],"items":[{"code":"nir_simulation_unsupported","message":"Simulation is no longer supported on the NIR-only NeuroCNL surface.","hint":"Use /api/generate to inspect the compiled topology or /api/export with format=\'nir\' to download the NIR artifact."}]}}',
          stepLabel: 'Preview',
        );

        expect(error.title, 'Not supported on this backend');
        expect(
          error.message,
          'Simulation is no longer supported on the NIR-only NeuroCNL surface.',
        );
        expect(error.hint, contains('/api/generate'));
      },
    );

    test('falls back to a cleaned raw message when no JSON payload exists', () {
      final error = extractPipelineStepError(
        'Generate failed: ValueError: IR lowering error: unsupported concept.',
        stepLabel: 'Generate',
      );

      expect(error.title, 'Generate failed');
      expect(
        error.message,
        'ValueError: IR lowering error: unsupported concept.',
      );
      expect(error.hint, isNull);
    });

    test('maps lowering failures to a compilation title', () {
      final error = extractPipelineStepError(
        'Generate failed: ApiException(422): '
        '{"detail":{"error":"lowering_failed","messages":["The connection sentence is not supported by the NIR backend."],"items":[{"code":"lowering_failed","message":"The connection sentence is not supported by the NIR backend.","hint":"Rewrite using a supported connectivity pattern."}]}}',
        stepLabel: 'Generate',
      );

      expect(error.title, 'Compilation error');
      expect(
        error.message,
        'The connection sentence is not supported by the NIR backend.',
      );
      expect(error.hint, contains('supported connectivity pattern'));
    });
  });
}
