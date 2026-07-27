import 'dart:io';

/// Runs native desktop deployment commands without a coordinator service.
class LocalDeploymentService {
  const LocalDeploymentService();

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}
