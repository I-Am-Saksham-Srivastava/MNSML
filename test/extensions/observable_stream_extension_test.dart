import 'dart:async';

import 'package:mnsml/src/api/async.dart';
import 'package:mnsml/src/api/extensions.dart';
import 'package:test/test.dart';

import '../util.dart';

void main() {
  testSetup();

  group('ObservableStreamExtension', () {
    test('Transform Stream in ObservableStream', () async {
      const stream = Stream.empty();
      expect(stream.asObservable(), isA<ObservableStream>());
    });
  });
}
