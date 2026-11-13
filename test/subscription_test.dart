import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/src/subscription.dart';

void main() {
  group('CallbackSubscription', () {
    test('runs the cancel callback only once', () {
      var calls = 0;
      final sub = CallbackSubscription(() => calls++);

      expect(sub.isActive, isTrue);
      sub
        ..cancel()
        ..cancel();

      expect(sub.isActive, isFalse);
      expect(calls, 1);
    });
  });

  group('SerialQueue', () {
    late List<Object> errors;
    late SerialQueue queue;

    setUp(() {
      errors = [];
      queue = SerialQueue(onError: (e, _) => errors.add(e));
    });

    test('runs synchronous tasks immediately', () {
      final log = <int>[];
      queue
        ..add(() => log.add(1))
        ..add(() => log.add(2));
      expect(log, [1, 2]);
    });

    test('waits for an async task before running the next one', () async {
      final log = <String>[];
      final gate = Completer<void>();

      queue
        ..add(() async {
          log.add('hide start');
          await gate.future;
          log.add('hide end');
        })
        ..add(() => log.add('show'));

      expect(log, ['hide start']);
      gate.complete();
      await pumpEventQueue();
      expect(log, ['hide start', 'hide end', 'show']);
    });

    test('keeps going after a task throws', () async {
      final log = <int>[];
      queue
        ..add(() => throw StateError('sync'))
        ..add(() async => throw StateError('async'))
        ..add(() => log.add(3));

      await pumpEventQueue();
      expect(errors, hasLength(2));
      expect(log, [3]);
    });

    test('drops pending tasks when closed', () async {
      final log = <int>[];
      final gate = Completer<void>();
      queue
        ..add(() => gate.future)
        ..add(() => log.add(2))
        ..close()
        ..add(() => log.add(3));

      gate.complete();
      await pumpEventQueue();
      expect(log, isEmpty);
    });

    test('runs a task added from inside a task after it returns', () {
      final log = <int>[];
      queue.add(() {
        log.add(1);
        queue.add(() => log.add(3));
        log.add(2);
      });
      expect(log, [1, 2, 3]);
    });
  });
}
