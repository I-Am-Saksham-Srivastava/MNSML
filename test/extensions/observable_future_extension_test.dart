import 'dart:async';

import 'package:mnsml/src/api/async.dart';
import 'package:mnsml/src/api/extensions.dart';
import 'package:test/test.dart';

import '../util.dart';

void main() {
  testSetup();

  group('ObservableFutureExtension', () {
    test('Transform Future in ObservableFuture', () async {
      final future = Future.value(1);
      expect(future.asObservable(), isA<ObservableFuture>());
    });
  });
}
