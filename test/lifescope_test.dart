import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/lifescope.dart';

void main() {
  late LifeScope scope;

  void moveTo(WidgetTester tester, AppLifecycleState state) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }

  void start(WidgetTester tester) {
    moveTo(tester, AppLifecycleState.resumed);
    scope = LifeScope();
    addTearDown(scope.dispose);
  }

  testWidgets('starts with the current binding state', (tester) async {
    start(tester);
    expect(scope.state.value, AppLifecycleState.resumed);
  });

  testWidgets('calls the callbacks for each step in order', (tester) async {
    start(tester);
    final log = <String>[];
    scope.listen(
      onInactive: () => log.add('inactive'),
      onHide: () => log.add('hide'),
      onPause: () => log.add('pause'),
      onRestart: () => log.add('restart'),
      onShow: () => log.add('show'),
      onResume: () => log.add('resume'),
    );

    moveTo(tester, AppLifecycleState.paused);
    moveTo(tester, AppLifecycleState.resumed);

    expect(log, [
      'inactive', 'hide', 'pause', //
      'restart', 'show', 'resume',
    ]);
    expect(scope.state.value, AppLifecycleState.resumed);
  });

  testWidgets('reports every step to onStateChange', (tester) async {
    start(tester);
    final states = <AppLifecycleState>[];
    scope.listen(onStateChange: states.add);

    moveTo(tester, AppLifecycleState.hidden);

    expect(states, [AppLifecycleState.inactive, AppLifecycleState.hidden]);
  });

  testWidgets('ignores repeated states', (tester) async {
    start(tester);
    var calls = 0;
    scope.listen(onStateChange: (_) => calls++);

    moveTo(tester, AppLifecycleState.resumed);

    expect(calls, 0);
  });

  testWidgets('a slow listener does not delay other listeners', (tester) async {
    start(tester);
    final gate = Completer<void>();
    final log = <String>[];
    scope
      ..listen(onHide: () => gate.future)
      ..listen(onHide: () => log.add('other hide'));

    moveTo(tester, AppLifecycleState.hidden);

    expect(log, ['other hide']);
    gate.complete();
  });

  testWidgets('a listener sees its own callbacks in order', (tester) async {
    start(tester);
    final gate = Completer<void>();
    final log = <String>[];
    scope.listen(
      onHide: () async {
        log.add('hide start');
        await gate.future;
        log.add('hide end');
      },
      onShow: () => log.add('show'),
    );

    moveTo(tester, AppLifecycleState.hidden);
    moveTo(tester, AppLifecycleState.inactive);
    expect(log, ['hide start']);

    gate.complete();
    await tester.pump();
    expect(log, ['hide start', 'hide end', 'show']);
  });

  testWidgets('cancelled listeners are not called', (tester) async {
    start(tester);
    var calls = 0;
    final sub = scope.listen(onStateChange: (_) => calls++);
    sub.cancel();

    moveTo(tester, AppLifecycleState.hidden);

    expect(calls, 0);
    expect(sub.isActive, isFalse);
  });

  testWidgets('cancelling during a dispatch stops the remaining steps',
      (tester) async {
    start(tester);
    final log = <String>[];
    late LifeScopeSubscription sub;
    sub = scope.listen(
      onInactive: () {
        log.add('inactive');
        sub.cancel();
      },
      onHide: () => log.add('hide'),
    );

    moveTo(tester, AppLifecycleState.hidden);

    expect(log, ['inactive']);
  });

  testWidgets('listeners added during a dispatch wait for the next event',
      (tester) async {
    start(tester);
    final log = <String>[];
    scope.listen(
      onInactive: () {
        scope.listen(onHide: () => log.add('late hide'));
      },
    );

    moveTo(tester, AppLifecycleState.hidden);
    expect(log, isEmpty);
  });

  group('errors', () {
    late List<Object> errors;

    void startWithErrors(WidgetTester tester) {
      errors = [];
      moveTo(tester, AppLifecycleState.resumed);
      scope = LifeScope(
        callbackTimeout: const Duration(seconds: 1),
        onError: (error, _) => errors.add(error),
      );
      addTearDown(scope.dispose);
    }

    testWidgets('a throwing callback does not affect other listeners',
        (tester) async {
      startWithErrors(tester);
      final log = <String>[];
      scope
        ..listen(onHide: () => throw StateError('boom'))
        ..listen(onHide: () => log.add('hide'));

      moveTo(tester, AppLifecycleState.hidden);

      expect(log, ['hide']);
      expect(errors.single, isStateError);
    });

    testWidgets('async errors are reported too', (tester) async {
      startWithErrors(tester);
      scope.listen(onHide: () async => throw StateError('boom'));

      moveTo(tester, AppLifecycleState.hidden);
      await tester.pump();

      expect(errors.single, isStateError);
    });

    testWidgets('a stuck callback times out and the queue moves on',
        (tester) async {
      startWithErrors(tester);
      final log = <String>[];
      scope.listen(
        onHide: () => Completer<void>().future,
        onShow: () => log.add('show'),
      );

      moveTo(tester, AppLifecycleState.hidden);
      moveTo(tester, AppLifecycleState.inactive);
      expect(log, isEmpty);

      await tester.pump(const Duration(seconds: 1));

      expect(log, ['show']);
      expect(errors.single, isA<TimeoutException>());
    });

    testWidgets('errors go to FlutterError by default', (tester) async {
      start(tester);
      scope.listen(onHide: () => throw StateError('boom'));

      moveTo(tester, AppLifecycleState.hidden);

      expect(tester.takeException(), isStateError);
    });
  });

  testWidgets('dispose cancels every subscription', (tester) async {
    start(tester);
    final sub = scope.listen(onHide: () {});
    scope.dispose();

    expect(sub.isActive, isFalse);
    expect(() => scope.listen(), throwsStateError);
  });
}
