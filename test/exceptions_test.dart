import 'package:mnsml/mnsml.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  testSetup();

  test('mnsmlException has the right toString()', () {
    final ex = mnsmlException('Test Exception');

    expect(ex.toString(), equals('Test Exception'));
  });

  test('mnsmlCyclicReactionException has the right toString()', () {
    final ex = mnsmlCyclicReactionException('Test Exception');

    expect(ex.toString(), equals('Test Exception'));
  });

  test('mnsmlCaughtException contains the stacktrace', () {
    try {
      throw Exception('test');
    } on Object catch (e, s) {
      final ex = mnsmlCaughtException(e, stackTrace: s);
      expect(ex.stackTrace, isNotNull);
    }
  });

  test('should preserve stacktrace', () async {
    late StackTrace stackTrace;
    try {
      Computed(() {
        try {
          throw Exception();
        } on Exception catch (e, st) {
          stackTrace = st;
          rethrow;
        }
      }).value;
    } on mnsmlCaughtException catch (e, st) {
      expect(st, stackTrace);
      expect(st, e.stackTrace);
    }
  });
}
