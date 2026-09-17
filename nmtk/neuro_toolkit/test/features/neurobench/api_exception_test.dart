// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

void main() {
  group('HttpApiException', () {
    test('isNotFound is true for 404', () {
      const e = HttpApiException(404, 'not found');
      expect(e.isNotFound, isTrue);
      expect(e.isUnauthorized, isFalse);
      expect(e.isServerError, isFalse);
    });

    test('isUnauthorized is true for 401', () {
      const e = HttpApiException(401, 'unauthorized');
      expect(e.isUnauthorized, isTrue);
    });

    test('isServerError is true for 500+', () {
      expect(const HttpApiException(500, '').isServerError, isTrue);
      expect(const HttpApiException(503, '').isServerError, isTrue);
      expect(const HttpApiException(422, '').isServerError, isFalse);
    });

    test('isConflict is true for 409', () {
      expect(const HttpApiException(409, '').isConflict, isTrue);
    });

    test('toString includes status code', () {
      const e = HttpApiException(500, 'Internal Server Error');
      expect(e.toString(), contains('500'));
    });
  });

  group('TimeoutApiException', () {
    test('toString includes endpoint', () {
      const e = TimeoutApiException('/api/neurobench/benchmarks');
      expect(e.toString(), contains('/api/neurobench/benchmarks'));
    });
  });

  group('MalformedResponseException', () {
    test('toString includes endpoint', () {
      const e = MalformedResponseException('/api/neurobench/results', 'bad');
      expect(e.toString(), contains('/api/neurobench/results'));
    });
  });

  group('nmtkUserFacingError', () {
    test('404 → resource not found', () {
      expect(
        nmtkUserFacingError(const HttpApiException(404, '')),
        'Resource not found.',
      );
    });

    test('401 → authentication required', () {
      expect(
        nmtkUserFacingError(const HttpApiException(401, '')),
        'Authentication required.',
      );
    });

    test('409 → conflict', () {
      expect(
        nmtkUserFacingError(const HttpApiException(409, '')),
        'Conflict — item already exists.',
      );
    });

    test('500 → server error', () {
      expect(
        nmtkUserFacingError(const HttpApiException(500, '')),
        'Server error. Try again in a moment.',
      );
    });

    test('timeout → check connection', () {
      expect(
        nmtkUserFacingError(const TimeoutApiException('/api')),
        'Request timed out. Check your connection.',
      );
    });

    test('malformed → unexpected response', () {
      expect(
        nmtkUserFacingError(const MalformedResponseException('/api', 'x')),
        'Unexpected server response.',
      );
    });

    test('unknown error → something went wrong', () {
      expect(
        nmtkUserFacingError(Exception('unknown')),
        'Something went wrong.',
      );
    });
  });
}
