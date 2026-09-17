import 'api_exception.dart';

/// Returns a short, user-readable sentence for any [NmtkApiException].
///
/// Use this in providers to convert caught exceptions into display strings
/// instead of calling `.toString()` which leaks internals to the user.
///
/// ```dart
/// on NmtkApiException catch (e) {
///   _error = nmtkUserFacingError(e);
///   notifyListeners();
/// }
/// ```
String nmtkUserFacingError(Object error) => switch (error) {
      HttpApiException(statusCode: 404) => 'Resource not found.',
      HttpApiException(statusCode: 401) => 'Authentication required.',
      HttpApiException(statusCode: 409) => 'Conflict — item already exists.',
      HttpApiException(isServerError: true) =>
        'Server error. Try again in a moment.',
      HttpApiException() => 'Request failed.',
      TimeoutApiException() => 'Request timed out. Check your connection.',
      MalformedResponseException() => 'Unexpected server response.',
      _ => 'Something went wrong.',
    };
