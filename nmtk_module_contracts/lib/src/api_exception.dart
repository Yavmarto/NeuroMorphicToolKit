/// Typed exception hierarchy for all NMTK module API clients.
///
/// All service classes should throw [NmtkApiException] subtypes rather than
/// generic [Exception] strings. This enables callers to branch on [statusCode]
/// or exception type instead of fragile string matching.
///
/// Usage in a service:
/// ```dart
/// if (response.statusCode != 200) {
///   throw HttpApiException(response.statusCode, response.body);
/// }
/// ```
///
/// Usage in a provider:
/// ```dart
/// on HttpApiException catch (e) {
///   final msg = switch (e.statusCode) {
///     409 => 'Already exists.',
///     404 => 'Not found.',
///     _   => 'Request failed (${e.statusCode}).',
///   };
///   state = state.copyWith(errorMessage: msg);
/// }
/// ```
sealed class NmtkApiException implements Exception {
  const NmtkApiException();
}

/// The server returned a non-2xx HTTP response.
final class HttpApiException extends NmtkApiException {
  const HttpApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  bool get isNotFound     => statusCode == 404;
  bool get isUnauthorized => statusCode == 401;
  bool get isConflict     => statusCode == 409;
  bool get isServerError  => statusCode >= 500;

  @override
  String toString() => 'HttpApiException($statusCode): $body';
}

/// The HTTP request timed out before a response arrived.
final class TimeoutApiException extends NmtkApiException {
  const TimeoutApiException(this.endpoint);

  final String endpoint;

  @override
  String toString() => 'TimeoutApiException: $endpoint timed out';
}

/// The server returned a body that could not be decoded as the expected type.
final class MalformedResponseException extends NmtkApiException {
  const MalformedResponseException(this.endpoint, this.raw);

  final String endpoint;
  final String raw;

  @override
  String toString() => 'MalformedResponseException at $endpoint';
}
