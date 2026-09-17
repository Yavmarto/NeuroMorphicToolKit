import 'dart:convert';

import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurochip_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';

typedef PipelineStepError = ({String title, String message, String? hint});

String formatDeployError(
  Object error, {
  required String serviceName,
  required String action,
}) {
  return switch (error) {
    ApiException api => _formatHttpError(
      statusCode: api.statusCode,
      body: api.body,
      serviceName: serviceName,
      action: action,
    ),
    NeurochipApiException api => _formatHttpError(
      statusCode: api.statusCode,
      body: api.body,
      serviceName: serviceName,
      action: action,
    ),
    LauncherControlApiException api => _formatHttpError(
      statusCode: api.statusCode,
      body: api.body,
      serviceName: serviceName,
      action: action,
    ),
    _ => _formatGenericError(error, serviceName: serviceName, action: action),
  };
}

String _formatHttpError({
  required int statusCode,
  required String body,
  required String serviceName,
  required String action,
}) {
  final detail = _extractBestMessage(body);
  if (_looksLikeConnectivityFailure(detail) ||
      _looksLikeConnectivityFailure(body)) {
    final suffix = detail != null && detail.isNotEmpty
        ? ' Detail: $detail'
        : body.trim().isNotEmpty
        ? ' Detail: ${body.trim()}'
        : '';
    return 'Could not reach $serviceName while $action. Make sure the backend is running and the configured URL is correct.$suffix';
  }

  if (statusCode == 404) {
    return '$serviceName endpoint not found while $action. This usually means the backend is not running the expected version or the wrong URL is configured.';
  }

  if (statusCode == 500 &&
      (detail == null || _isGenericServerMessage(detail))) {
    return '$serviceName request failed while $action (HTTP 500). No structured error details were returned.';
  }

  if (statusCode == 503) {
    return '$serviceName is unavailable while $action. Check that the backend is running and ready.';
  }

  if (detail != null && detail.isNotEmpty) {
    return detail;
  }

  return '$serviceName request failed while $action (HTTP $statusCode).';
}

PipelineStepError extractPipelineStepError(
  String? rawError, {
  required String stepLabel,
}) {
  final trimmed = rawError?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return (
      title: '$stepLabel failed',
      message: 'An unknown error occurred.',
      hint: null,
    );
  }

  final statusCode = _extractStatusCode(trimmed);
  final payload = _tryDecodeEmbeddedJson(trimmed);
  final detail = _extractDetailMap(payload);
  final item = _extractPrimaryItem(detail);
  final message = _extractPrimaryMessage(detail, item);
  final hint = _extractPrimaryHint(detail, item);
  final title = _resolvePipelineErrorTitle(
    stepLabel: stepLabel,
    statusCode: statusCode,
    detail: detail,
    item: item,
    rawError: trimmed,
  );

  if (message != null && message.isNotEmpty) {
    return (title: title, message: message, hint: hint);
  }

  final cleaned = _cleanPipelineRawError(trimmed, stepLabel: stepLabel);
  return (
    title: title,
    message: cleaned.isEmpty ? 'An unknown error occurred.' : cleaned,
    hint: hint,
  );
}

String _formatGenericError(
  Object error, {
  required String serviceName,
  required String action,
}) {
  final message = error.toString().trim();
  if (_looksLikeConnectivityFailure(message)) {
    return 'Could not reach $serviceName while $action. Make sure the backend is running and the configured URL is correct.';
  }
  if (message.isEmpty) {
    return '$serviceName request failed while $action.';
  }
  return message;
}

String? _extractBestMessage(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final decoded = _tryDecodeEmbeddedJson(trimmed);
  if (decoded == null) {
    return _isGenericServerMessage(trimmed) ? null : trimmed;
  }

  final messages = <String>[];
  _collectMessages(decoded, messages);
  final best = messages
      .map((message) => message.trim())
      .where(
        (message) => message.isNotEmpty && !_isGenericServerMessage(message),
      )
      .toSet()
      .join(' ');
  return best.isEmpty ? null : best;
}

void _collectMessages(Object? value, List<String> messages) {
  switch (value) {
    case String text:
      messages.add(text);
    case List<dynamic> values:
      for (final item in values) {
        _collectMessages(item, messages);
      }
    case Map<String, dynamic> map:
      for (final key in const [
        'detail',
        'message',
        'error',
        'errors',
        'rejection_reasons',
        'rejections',
        'runtimeBody',
        'runtimeJson',
        'warnings',
        'messages',
      ]) {
        final nested = map[key];
        if (nested != null) {
          _collectMessages(nested, messages);
        }
      }
    default:
      break;
  }
}

bool _looksLikeJson(String value) =>
    value.startsWith('{') || value.startsWith('[');

Object? _tryDecodeEmbeddedJson(String value) {
  final trimmed = value.trim();
  if (_looksLikeJson(trimmed)) {
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  final jsonStart = trimmed.indexOf('{');
  if (jsonStart < 0) {
    return null;
  }
  final candidate = trimmed.substring(jsonStart).trim();
  if (!_looksLikeJson(candidate)) {
    return null;
  }
  try {
    return jsonDecode(candidate);
  } catch (_) {
    return null;
  }
}

int? _extractStatusCode(String value) {
  final match = RegExp(r'ApiException\((\d+)\)').firstMatch(value);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

Map<String, dynamic>? _extractDetailMap(Object? value) {
  final decoded = _asStringKeyedMap(value);
  if (decoded == null) {
    return null;
  }
  final detail = decoded['detail'];
  final detailMap = _asStringKeyedMap(detail);
  return detailMap ?? decoded;
}

Map<String, dynamic>? _extractPrimaryItem(Map<String, dynamic>? detail) {
  final items = detail?['items'];
  if (items is List<dynamic>) {
    for (final item in items) {
      final itemMap = _asStringKeyedMap(item);
      if (itemMap != null) {
        return itemMap;
      }
    }
  }
  return null;
}

String? _extractPrimaryMessage(
  Map<String, dynamic>? detail,
  Map<String, dynamic>? item,
) {
  for (final candidate in [
    item?['message'],
    _firstListString(detail?['messages']),
    detail?['message'],
    detail?['detail'],
    _extractBestMessageFromObject(detail),
  ]) {
    final normalized = _normalizeNonEmptyString(candidate);
    if (normalized != null && !_isLikelyMachineCode(normalized)) {
      return normalized;
    }
  }
  return null;
}

String? _extractPrimaryHint(
  Map<String, dynamic>? detail,
  Map<String, dynamic>? item,
) {
  return _normalizeNonEmptyString(item?['hint']) ??
      _normalizeNonEmptyString(detail?['hint']);
}

String _resolvePipelineErrorTitle({
  required String stepLabel,
  required int? statusCode,
  required Map<String, dynamic>? detail,
  required Map<String, dynamic>? item,
  required String rawError,
}) {
  if (_looksLikeConnectivityFailure(rawError) ||
      _looksLikeConnectivityFailure(
        _normalizeNonEmptyString(detail?['message']),
      )) {
    return 'Backend unavailable';
  }

  final errorCode = _normalizeNonEmptyString(detail?['error']);
  if (errorCode != null) {
    final fromCode = _titleFromErrorCode(errorCode);
    if (fromCode != null) {
      return fromCode;
    }
  }

  final itemCode = _normalizeNonEmptyString(item?['code']);
  if (itemCode != null) {
    final fromItemCode = _titleFromErrorCode(itemCode);
    if (fromItemCode != null) {
      return fromItemCode;
    }
  }

  return switch (statusCode) {
    400 => 'Parse error',
    410 => 'Not supported on this backend',
    422 => 'Compilation error',
    503 => 'Backend unavailable',
    _ => '$stepLabel failed',
  };
}

String? _titleFromErrorCode(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'parse_failed' || 'parse_error' => 'Parse error',
    'validation_failed' => 'Validation failed',
    'lowering_failed' ||
    'materializer_error' ||
    'compile_failed' => 'Compilation error',
    'nir_simulation_unsupported' => 'Not supported on this backend',
    'service_unavailable' || 'backend_unavailable' => 'Backend unavailable',
    _ when normalized.contains('connect') && normalized.contains('refused') =>
      'Backend unavailable',
    _ => _looksLikeHumanReadableTitle(value) ? value : null,
  };
}

String _cleanPipelineRawError(String rawError, {required String stepLabel}) {
  var cleaned = rawError.trim();
  cleaned = cleaned.replaceFirst(
    RegExp('^$stepLabel failed:\\s*', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^(generate|simulation|simulate|preview) failed:\s*',
      caseSensitive: false,
    ),
    '',
  );
  cleaned = cleaned.replaceFirst(RegExp(r'^ApiException\(\d+\):\s*'), '');
  return cleaned.trim();
}

Map<String, dynamic>? _asStringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, nestedValue) => MapEntry(key.toString(), nestedValue),
    );
  }
  return null;
}

String? _extractBestMessageFromObject(Object? value) {
  if (value == null) {
    return null;
  }
  final messages = <String>[];
  _collectMessages(value, messages);
  for (final candidate in messages) {
    final normalized = _normalizeNonEmptyString(candidate);
    if (normalized != null &&
        !_isGenericServerMessage(normalized) &&
        !_isLikelyMachineCode(normalized)) {
      return normalized;
    }
  }
  return null;
}

String? _firstListString(Object? value) {
  if (value is List<dynamic>) {
    for (final item in value) {
      final normalized = _normalizeNonEmptyString(item);
      if (normalized != null) {
        return normalized;
      }
    }
  }
  return null;
}

String? _normalizeNonEmptyString(Object? value) {
  if (value == null) {
    return null;
  }
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

bool _isLikelyMachineCode(String value) {
  final normalized = value.trim();
  return normalized.isNotEmpty &&
      RegExp(r'^[a-z0-9_]+$').hasMatch(normalized) &&
      normalized.contains('_');
}

bool _looksLikeHumanReadableTitle(String value) {
  final normalized = value.trim();
  return normalized.isNotEmpty &&
      normalized.contains(RegExp(r'[A-Z ]')) &&
      !normalized.contains('{');
}

bool _isGenericServerMessage(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'internal server error' ||
      normalized == '{"detail":"internal server error"}' ||
      normalized == 'server error';
}

bool _looksLikeConnectivityFailure(String? value) {
  if (value == null) {
    return false;
  }
  final normalized = value.toLowerCase();
  return normalized.contains('connection refused') ||
      normalized.contains('socketexception') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('connection reset by peer') ||
      normalized.contains('connection closed before full header was received');
}
