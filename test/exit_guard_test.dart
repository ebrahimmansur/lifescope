import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/lifescope.dart';

void main() {
  late LifeScope scope;
  late List<Object> errors;

  void start() {
    errors = [];
    scope = LifeScope(onError: (error, _) => errors.add(error));
    addTearDown(scope.dispose);
  }

  Future<AppExitResponse> requestExit(WidgetTester tester) {
    return tester.binding.handleRequestAppExit();
  }

  testWidgets('exits when there are no guards', (tester) async {
    start();
    expect(await requestExit(tester), AppExitResponse.exit);
  });

  testWidgets('exits when every guard allows it', (tester) async {
    start();
    scope
      ..guardExit(() => AppExitResponse.exit)
      ..guardExit(() async => AppExitResponse.exit);

    expect(await requestExit(tester), AppExitResponse.exit);
  });

  testWidgets('the first cancel wins and later guards are skipped',
      (tester) async {
    start();
    final asked = <int>[];
    scope
      ..guardExit(() {
        asked.add(1);
        return AppExitResponse.exit;
      })
      ..guardExit(() {
        asked.add(2);
        return AppExitResponse.cancel;
      })
      ..guardExit(() {
        asked.add(3);
        return AppExitResponse.exit;
      });

    expect(await requestExit(tester), AppExitResponse.cancel);
    expect(asked, [1, 2]);
  });

  testWidgets('guards are asked one at a time', (tester) async {
    start();
    final gate = Completer<AppExitResponse>();
    var secondAsked = false;
    scope
      ..guardExit(() => gate.future)
      ..guardExit(() {
        secondAsked = true;
        return AppExitResponse.exit;
      });

    final response = requestExit(tester);
    await tester.pump();
    expect(secondAsked, isFalse);

    gate.complete(AppExitResponse.exit);
    expect(await response, AppExitResponse.exit);
    expect(secondAsked, isTrue);
  });

  testWidgets('a throwing guard is reported and allows exit', (tester) async {
    start();
    scope.guardExit(() => throw StateError('boom'));

    expect(await requestExit(tester), AppExitResponse.exit);
    expect(errors.single, isStateError);
  });

  testWidgets('a guard that times out uses onTimeout', (tester) async {
    start();
    scope.guardExit(
      () => Completer<AppExitResponse>().future,
      timeout: const Duration(seconds: 2),
      onTimeout: AppExitResponse.cancel,
    );

    AppExitResponse? response;
    unawaited(requestExit(tester).then((r) => response = r));
    await tester.pump(const Duration(seconds: 2));

    expect(response, AppExitResponse.cancel);
    expect(errors.single, isA<TimeoutException>());
  });

  testWidgets('overlapping requests share one answer', (tester) async {
    start();
    final gate = Completer<AppExitResponse>();
    var calls = 0;
    scope.guardExit(() {
      calls++;
      return gate.future;
    });

    final first = requestExit(tester);
    final second = requestExit(tester);
    gate.complete(AppExitResponse.cancel);

    expect(await first, AppExitResponse.cancel);
    expect(await second, AppExitResponse.cancel);
    expect(calls, 1);
  });

  testWidgets('cancelled guards are not asked', (tester) async {
    start();
    scope.guardExit(() => AppExitResponse.cancel).cancel();

    expect(await requestExit(tester), AppExitResponse.exit);
  });

  testWidgets('dispose removes the guards', (tester) async {
    start();
    final guard = scope.guardExit(() => AppExitResponse.cancel);
    scope.dispose();

    expect(guard.isActive, isFalse);
    expect(await requestExit(tester), AppExitResponse.exit);
  });
}
