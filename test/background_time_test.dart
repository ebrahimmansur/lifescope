import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/lifescope.dart';

const _channel = MethodChannel('lifescope/background_time');
final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

void main() {
  late List<String> calls;
  late List<Object> errors;

  void mockNative(WidgetTester tester, {bool missing = false}) {
    calls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        if (missing) throw MissingPluginException();
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));
  }

  LifeScope start(WidgetTester tester, {bool extendBackgroundTime = true}) {
    errors = [];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final scope = LifeScope(
      extendBackgroundTime: extendBackgroundTime,
      onError: (error, _) => errors.add(error),
    );
    addTearDown(scope.dispose);
    return scope;
  }

  void hide(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }

  Future<void> simulateExpired(WidgetTester tester) {
    return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(const MethodCall('expired')),
      (_) {},
    );
  }

  testWidgets('holds background time while an async hide runs', (tester) async {
    mockNative(tester);
    final scope = start(tester);
    final save = Completer<void>();
    scope.listen(onHide: () => save.future);

    hide(tester);
    await tester.pump();
    expect(calls, ['begin']);

    save.complete();
    await tester.pump();
    expect(calls, ['begin', 'end']);
  }, variant: _ios);

  testWidgets('sync callbacks do not ask for time', (tester) async {
    mockNative(tester);
    final scope = start(tester);
    scope.listen(onHide: () {}, onStateChange: (_) {});

    hide(tester);
    await tester.pump();

    expect(calls, isEmpty);
  }, variant: _ios);

  testWidgets('overlapping work shares one background task', (tester) async {
    mockNative(tester);
    final scope = start(tester);
    final first = Completer<void>();
    final second = Completer<void>();
    scope
      ..listen(onHide: () => first.future)
      ..listen(onPause: () => second.future);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    first.complete();
    await tester.pump();
    expect(calls, ['begin']);

    second.complete();
    await tester.pump();
    expect(calls, ['begin', 'end']);
  }, variant: _ios);

  testWidgets('does not ask for time when coming back', (tester) async {
    mockNative(tester);
    final scope = start(tester);
    scope.listen(onResume: () async {}, onInactive: () async {});

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, isEmpty);
  }, variant: _ios);

  testWidgets('does nothing on Android', (tester) async {
    mockNative(tester);
    final scope = start(tester);
    scope.listen(onHide: () async {});

    hide(tester);
    await tester.pump();

    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('can be turned off', (tester) async {
    mockNative(tester);
    final scope = start(tester, extendBackgroundTime: false);
    scope.listen(onHide: () async {});

    hide(tester);
    await tester.pump();

    expect(calls, isEmpty);
  }, variant: _ios);

  testWidgets('reports when iOS runs out of time and asks again next time',
      (tester) async {
    mockNative(tester);
    final scope = start(tester);
    final stuck = Completer<void>();
    var hides = 0;
    scope.listen(
      onHide: () => hides++ == 0 ? stuck.future : Future<void>.value(),
    );

    hide(tester);
    await tester.pump();
    await simulateExpired(tester);
    expect(errors.single, isA<TimeoutException>());

    // Back to the foreground and out again while the first save is stuck.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    hide(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(calls.where((c) => c == 'begin'), hasLength(2));

    stuck.complete();
  }, variant: _ios);

  testWidgets('a missing plugin is ignored', (tester) async {
    mockNative(tester, missing: true);
    final scope = start(tester);
    var saved = false;
    scope.listen(onHide: () async => saved = true);

    hide(tester);
    await tester.pump();

    expect(saved, isTrue);
    expect(errors, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: _ios);

  testWidgets('disposing one scope keeps the task another one needs',
      (tester) async {
    mockNative(tester);
    final first = start(tester);
    final second = LifeScope();
    addTearDown(second.dispose);
    final save = Completer<void>();
    first.listen(onHide: () async {});
    second.listen(onHide: () => save.future);

    hide(tester);
    await tester.pump();
    first.dispose();
    await tester.pump();
    expect(calls, ['begin']);

    save.complete();
    await tester.pump();
    expect(calls, ['begin', 'end']);
  }, variant: _ios);
}
