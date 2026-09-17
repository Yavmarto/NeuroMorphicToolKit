import 'package:freezed_annotation/freezed_annotation.dart';

part 'deploy_readiness_result.freezed.dart';
part 'deploy_readiness_result.g.dart';

/// Unified result of a deploy-readiness check for the current spec against
/// the currently selected target — mirrors either a simulator preflight
/// result or a hardware/codegen `previewDeployTarget` result.
@Freezed(unionKey: 'status', fallbackUnion: 'ok')
sealed class DeployReadinessResult with _$DeployReadinessResult {
  const DeployReadinessResult._();

  @FreezedUnionValue('ok')
  const factory DeployReadinessResult.ok() = DeployReadinessOk;

  @FreezedUnionValue('unsupported')
  const factory DeployReadinessResult.unsupported({
    required String level, // 'approximate' | 'unsupported'
    required List<String> unsupportedNodes,
    required List<String> diagnostics,
  }) = DeployReadinessUnsupported;

  @FreezedUnionValue('error')
  const factory DeployReadinessResult.error({required String message}) =
      DeployReadinessError;

  factory DeployReadinessResult.fromJson(Map<String, dynamic> json) =>
      _$DeployReadinessResultFromJson(json);
}
